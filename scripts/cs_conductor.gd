extends Node
class_name CSConductor

## The song clock. Everything in a crowd-surf level keys off this: spawns happen
## on `beat`, glowsticks fire on `half_beat`, section kinds (build/drop/boss) set
## the spawn rules, and the Hype Blast is judged against the nearest beat.
##
## Time source: the audio playback position (compensated for mix latency) while
## a stream is playing; otherwise a manual clock advanced by `advance()` — used
## by tests and when no audio device exists, so gameplay never depends on sound.

signal beat(n: int)                      ## every quarter note
signal half_beat(n: int)                 ## every eighth note (n counts eighths)
signal section_changed(section: Dictionary)
signal finished                          ## song ran past its last beat

## Timing windows for judge(), in seconds from the nearest beat.
const PERFECT_WINDOW := 0.07
const GOOD_WINDOW := 0.14

var bpm: float = 120.0
var offset: float = 0.0                  ## seconds before beat 0
var length_beats: int = 0
var sections: Array = []                 ## [{name, kind, start, end}] in beats
var title: String = ""

var song_time: float = 0.0               ## seconds since the song started
var playing: bool = false
var manual_clock: bool = false           ## true: time only moves via advance()

var _player: AudioStreamPlayer = null
var _last_half: int = -1
var _section_idx: int = -1
var _done: bool = false

func seconds_per_beat() -> float:
	return 60.0 / bpm

## Current position in beats (fractional). Negative before beat 0.
func beat_pos() -> float:
	return (song_time - offset) / seconds_per_beat()

func current_section() -> Dictionary:
	return sections[_section_idx] if _section_idx >= 0 and _section_idx < sections.size() else {}

func section_at(b: float) -> Dictionary:
	for s in sections:
		if b >= s["start"] and b < s["end"]:
			return s
	return {}

## 0..1 through the song — doubles as "distance to the stage".
func progress() -> float:
	return clamp(beat_pos() / max(length_beats, 1), 0.0, 1.0)

## Load the beatmap JSON (and optionally the audio). Returns false on bad data.
func load_song(beatmap_path: String, stream: AudioStream = null) -> bool:
	var f := FileAccess.open(beatmap_path, FileAccess.READ)
	if f == null:
		push_error("CSConductor: can't open %s" % beatmap_path)
		return false
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		push_error("CSConductor: bad beatmap %s" % beatmap_path)
		return false
	load_beatmap(data)
	if stream != null:
		if _player == null:
			_player = AudioStreamPlayer.new()
			add_child(_player)
		_player.stream = stream
	return true

func load_beatmap(data: Dictionary) -> void:
	bpm = float(data.get("bpm", 120.0))
	offset = float(data.get("offset", 0.0))
	length_beats = int(data.get("length_beats", 0))
	title = str(data.get("title", ""))
	sections = []
	for s in data.get("sections", []):
		sections.append({"name": s["name"], "kind": s["kind"], "start": int(s["start"]), "end": int(s["end"])})

func play() -> void:
	song_time = 0.0
	_last_half = -1
	_section_idx = -1
	_done = false
	playing = true
	if _player != null and _player.stream != null and not manual_clock:
		_player.play()

func stop() -> void:
	playing = false
	if _player != null:
		_player.stop()

## Manual clock step (tests / no audio). Fires every event crossed.
func advance(dt: float) -> void:
	song_time += dt
	_emit_events()

func _process(delta: float) -> void:
	if not playing or manual_clock:
		return
	if _player != null and _player.playing:
		var t := _player.get_playback_position() + AudioServer.get_time_since_last_mix() \
			- AudioServer.get_output_latency()
		song_time = max(song_time, t)   # never run backwards (mix jitter)
	else:
		song_time += delta
	_emit_events()

func _emit_events() -> void:
	if not playing:
		return
	var halves := int(floor(beat_pos() * 2.0))
	while _last_half < halves:
		_last_half += 1
		if _last_half < 0:
			continue
		if _last_half % 2 == 0:
			var b := _last_half / 2
			_update_section(b)
			if b >= length_beats:
				_finish()
				return
			beat.emit(b)
		half_beat.emit(_last_half)

func _update_section(b: int) -> void:
	for i in sections.size():
		if b >= sections[i]["start"] and b < sections[i]["end"]:
			if i != _section_idx:
				_section_idx = i
				section_changed.emit(sections[i])
			return

func _finish() -> void:
	if _done:
		return
	_done = true
	playing = false
	finished.emit()

## Rate an input at song time `t` against the nearest beat:
## "perfect", "good" or "miss".
func judge(t: float = -1.0) -> String:
	if t < 0.0:
		t = song_time
	var spb := seconds_per_beat()
	var rel := fposmod(t - offset, spb)
	var dist: float = min(rel, spb - rel)
	if dist <= PERFECT_WINDOW:
		return "perfect"
	if dist <= GOOD_WINDOW:
		return "good"
	return "miss"

## 1.0 exactly on a beat, falling to 0.0 halfway between — for pulsing visuals.
func beat_pulse() -> float:
	var frac := fposmod(beat_pos(), 1.0)
	return pow(1.0 - frac, 3.0)
