extends Node2D
class_name CSBoss

## The headliner on the decks. Arrives when the boss drop hits. Has the same
## three vibe layers as a fan, but deep — and each layer you strip moves it to
## the next phase, adding attacks. Attacks are the show itself, fired on the
## beat so you can read them from the music:
##   phase 1 — bass shockwave rings every 4 beats
##   phase 2 — rings every 2 beats + laser sweeps: aimed on a beat (telegraph), fire on the next
##   phase 3 — same, with lasers twice as often
## Ring openings stay near the middle (GAP_RANGE) so dodging never pins you to
## a wall.
## Win the DJ over and they call Carl's name on the mic.

signal phase_changed(phase: int)
signal won_over

const RADIUS := 70.0
const LAYERS := {"phones": 30.0, "crossed": 45.0, "hype": 60.0}
const MODS := {
	"glowstick": {"phones": 0.5, "crossed": 1.0, "hype": 1.0},
	"blast":     {"phones": 2.0, "crossed": 1.5, "hype": 1.0},
}
const RING_SPEED := 230.0       ## px/s a shockwave expands
const RING_THICK := 14.0        ## half-width of a ring's hit band
const RING_MAX := 900.0
const RING_GAP := 0.42          ## half-width (radians) of the opening you surf through
const GAP_DRIFT := 0.25         ## max shift of the opening between consecutive rings
const GAP_RANGE := 0.3          ## openings stay within ±this (radians) of straight down
const LASER_WIDTH := 16.0
const LASER_LIFE := 0.28
const RING_DAMAGE := 10.0
const LASER_DAMAGE := 12.0

static var active = null        ## the boss currently on stage (or null)

var phones: float = LAYERS["phones"]
var crossed: float = LAYERS["crossed"]
var hype: float = LAYERS["hype"]
var phase: int = 1
var defeated: bool = false
var rings: Array = []           ## [{r, gap}] expanding shockwaves (data, not nodes)
var _gap: float = PI / 2.0      ## where the next ring's opening points (PI/2 = straight down)
var lasers: Array = []          ## [{angle, t, armed}] telegraph → fire
var _flash: float = 0.0
var _arrive: float = 0.0        ## 0→1 entrance slide

func _ready() -> void:
	active = self

func _exit_tree() -> void:
	if active == self:
		active = null

func hittable() -> bool:
	return not defeated and _arrive >= 1.0

func total() -> float:
	return phones + crossed + hype

func max_total() -> float:
	return LAYERS["phones"] + LAYERS["crossed"] + LAYERS["hype"]

func win_over(power: float, source: String) -> void:
	if not hittable():
		return
	var mods: Dictionary = MODS[source]
	var remaining := power
	for layer in ["phones", "crossed", "hype"]:
		var hp: float = get(layer)
		if hp <= 0.0 or remaining <= 0.0:
			continue
		var effective: float = remaining * mods[layer]
		if effective >= hp:
			set(layer, 0.0)
			remaining -= hp / mods[layer]
		else:
			set(layer, hp - effective)
			remaining = 0.0
	_flash = 0.08
	var p := 1 + int(phones <= 0.0) + int(crossed <= 0.0)
	if p != phase:
		phase = p
		phase_changed.emit(phase)
	if total() <= 0.001:
		defeated = true
		rings.clear()
		lasers.clear()
		won_over.emit()

## Called by the game on every beat while the boss is on stage.
func on_beat(b: int, target: Vector2) -> void:
	if defeated or _arrive < 1.0:
		return
	# Arm telegraphed lasers from the previous beat.
	for l in lasers:
		if not l["armed"]:
			l["armed"] = true
			l["t"] = LASER_LIFE
	var ring_every := 4 if phase == 1 else 2
	if b % ring_every == 0:
		_gap = clamp(_gap + randf_range(-GAP_DRIFT, GAP_DRIFT), PI / 2.0 - GAP_RANGE, PI / 2.0 + GAP_RANGE)
		rings.append({"r": RADIUS, "gap": _gap})
	var laser_every := 0 if phase < 2 else (4 if phase >= 3 else 8)
	if laser_every > 0 and b % laser_every == 1:
		lasers.append({"angle": (target - position).angle(), "t": 0.0, "armed": false})

## Returns damage dealt to a player at `p` (radius `pr`) this frame.
func hit_test(p: Vector2, pr: float) -> float:
	var dmg := 0.0
	var d := p.distance_to(position)
	var ang := (p - position).angle()
	for ring in rings:
		if abs(d - ring["r"]) < RING_THICK + pr \
				and abs(angle_difference(ang, ring.get("gap", -99.0))) > RING_GAP:
			dmg = max(dmg, RING_DAMAGE)
	for l in lasers:
		if l["armed"] and l["t"] > 0.0:
			var dir := Vector2.from_angle(l["angle"])
			var rel := p - position
			if rel.dot(dir) > 0.0 and abs(rel.cross(dir)) < LASER_WIDTH + pr:
				dmg = max(dmg, LASER_DAMAGE)
	return dmg

func _process(delta: float) -> void:
	if _arrive < 1.0:
		_arrive = min(_arrive + delta * 1.5, 1.0)
	for ring in rings:
		ring["r"] += RING_SPEED * delta
	rings = rings.filter(func(r): return r["r"] < RING_MAX)
	for l in lasers:
		if l["armed"]:
			l["t"] -= delta
	lasers = lasers.filter(func(l): return not l["armed"] or l["t"] > 0.0)
	if _flash > 0.0:
		_flash = max(_flash - delta, 0.0)
	queue_redraw()

func _draw() -> void:
	var slide := (1.0 - _arrive) * -160.0
	var o := Vector2(0, slide)
	var pulse: float = CSFan.pulse
	# Attacks (drawn in boss-local space).
	for ring in rings:
		var g: float = ring["gap"]
		draw_arc(o, ring["r"], g + RING_GAP, g + TAU - RING_GAP, 64, Color(1.0, 0.35, 0.85, 0.75), RING_THICK * 0.9)
	for l in lasers:
		var dir := Vector2.from_angle(l["angle"]) * 1200.0
		if l["armed"]:
			draw_line(o, o + dir, Color(0.4, 1.0, 1.0, 0.9), LASER_WIDTH * 2.0)
			draw_line(o, o + dir, Color.WHITE, 4.0)
		else:
			draw_dashed_line(o, o + dir, Color(0.4, 1.0, 1.0, 0.6), 2.0, 10.0)
	# DJ booth + DJ.
	var booth := Color("#2A2F3A")
	if _flash > 0.0:
		booth = booth.lerp(Color.WHITE, 0.5)
	draw_rect(Rect2(o + Vector2(-110, 10), Vector2(220, 50)), booth)
	draw_rect(Rect2(o + Vector2(-110, 10), Vector2(220, 6)), Color("#FF5FA2"))
	var dj := Color("#E6E9EE") if not defeated else Color("#B6F23A")
	var bob := -8.0 * pulse
	draw_circle(o + Vector2(0, -18 + bob), 34, dj.darkened(0.3))
	draw_circle(o + Vector2(0, -62 + bob), 20, dj)
	if phones > 0.0:
		draw_arc(o + Vector2(0, -62 + bob), 25, PI, TAU, 14, Color("#6FA0FF"), 5.0)
	if defeated:
		draw_line(o + Vector2(-28, -30 + bob), o + Vector2(-50, -90 + bob), dj, 5.0)
		draw_line(o + Vector2(28, -30 + bob), o + Vector2(50, -90 + bob), dj, 5.0)
