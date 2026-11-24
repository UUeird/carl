extends RefCounted
class_name CSGroove

## Rhythm over time, not hit-or-miss per beat. Every input (click, Space, tap,
## later a phone shake) is recorded; "groove" is how phase-locked your recent
## inputs are to the beat grid at whatever subdivision you're playing — quarter,
## eighth or sixteenth notes.
##
## groove = phase × evenness × tempo fit, all 0..1:
##   phase    — how close each input is to the grid, in absolute milliseconds
##              (PHASE_TOLERANCE), after removing your average lateness. Absolute
##              rather than relative to the subdivision, so a human-sized wobble
##              doesn't count 4× worse at 16ths than at quarters.
##   evenness — how even the gaps between inputs are (coefficient of variation).
##              This is what separates a drum roll from random mashing, which
##              always lands "near" a dense 16th grid by chance.
##   tempo    — how close your pace is to a real subdivision of the beat.
## A *constant* lateness (shake-detection lag, audio latency, a player who's
## always a hair behind) doesn't lower groove — only inconsistency does.
## `offset()` reports that constant lateness.
##
## The subdivision is inferred from how fast you're going (median gap between
## inputs), capped per section by `max_sub` — builds and drops unlock 16ths so
## you can legally freak out with the snare roll.

const WINDOW_BEATS := 4.0       ## how much recent history counts
const MIN_INPUTS := 3           ## need this many to judge a rhythm at all
const IDLE_BEATS := 1.5         ## stop for longer than this and groove fades
const SUBS := [1, 2, 4]         ## quarter, eighth, sixteenth
const PHASE_TOLERANCE := 0.08   ## seconds; Gaussian width of "close to the grid"
const EVENNESS_TOLERANCE := 0.4 ## coefficient of variation of gaps that halves-ish the score

var spb: float = 0.5            ## seconds per beat (set from the conductor)
var offset_s: float = 0.0       ## song offset (beat 0 time)
var max_sub: int = 2            ## fastest subdivision the current section allows

var _times: Array = []          ## recent input times (song seconds)
var _groove: float = 0.0
var _sub: int = 1

func setup(seconds_per_beat: float, song_offset: float = 0.0) -> void:
	spb = seconds_per_beat
	offset_s = song_offset

## Record one input at song time `t`. Returns the groove right after it.
func record(t: float) -> float:
	_times.append(t)
	while not _times.is_empty() and _times[0] < t - WINDOW_BEATS * spb:
		_times.pop_front()
	_recompute()
	return _groove

## Current groove (0..1) at song time `now`, fading if you've stopped.
func groove(now: float = -1.0) -> float:
	if now >= 0.0 and not _times.is_empty():
		var idle: float = now - _times[-1]
		var limit := IDLE_BEATS * spb
		if idle > limit:
			return _groove * clamp(1.0 - (idle - limit) / (2.0 * spb), 0.0, 1.0)
	return _groove

## Inputs per beat you're currently playing at: 1, 2 or 4.
func subdivision() -> int:
	return _sub

## Average lateness in seconds (positive = behind the grid). Constant lateness
## doesn't hurt groove; this is here for calibration/telemetry.
func offset() -> float:
	if _times.size() < MIN_INPUTS:
		return 0.0
	var period := spb / _sub
	var v := Vector2.ZERO
	for t in _times:
		v += Vector2.from_angle(TAU * fposmod(t - offset_s, period) / period)
	var ang := v.angle()
	if ang > PI:
		ang -= TAU
	return ang / TAU * period

func reset() -> void:
	_times.clear()
	_groove = 0.0
	_sub = 1

func _recompute() -> void:
	if _times.size() < MIN_INPUTS:
		_groove = 0.0
		return
	# Tempo: median gap → nearest allowed subdivision.
	var gaps: Array = []
	for i in range(1, _times.size()):
		gaps.append(_times[i] - _times[i - 1])
	gaps.sort()
	var med: float = gaps[gaps.size() / 2]
	var best := 1
	var best_err := INF
	for s in SUBS:
		if s > max_sub:
			continue
		var err: float = abs(log(med / (spb / s)))
		if err < best_err:
			best_err = err
			best = s
	_sub = best
	var period := spb / _sub
	var lag := offset()
	var phase := 0.0
	for t in _times:
		var d := fposmod(t - offset_s - lag + period / 2.0, period) - period / 2.0
		phase += exp(-(d * d) / (PHASE_TOLERANCE * PHASE_TOLERANCE))
	phase /= _times.size()
	var mean := 0.0
	for g in gaps:
		mean += g
	mean /= gaps.size()
	var variance := 0.0
	for g in gaps:
		variance += (g - mean) * (g - mean)
	var cv: float = sqrt(variance / gaps.size()) / maxf(mean, 0.0001)
	var evenness := exp(-(cv * cv) / (EVENNESS_TOLERANCE * EVENNESS_TOLERANCE))
	# Way off tempo (steady but unrelated rate) — scale down by tempo mismatch.
	var tempo_fit: float = clamp(1.0 - best_err * 2.0, 0.0, 1.0)
	_groove = phase * evenness * tempo_fit
