extends Node2D
class_name CSFan

## A festival-goer in the crowd. You don't hurt fans — you win them over. Each
## fan has up to three stacked "vibe" layers, worn down in order, the same way
## TD enemies had shield → armor → flesh:
##   headphones (blue)  — tuned out; glowsticks barely register, Hype Blast knocks them off
##   arms crossed (yellow) — skeptical
##   hype (pink)        — once full, they're converted
## A converted fan dances on the beat and gives you Lift when you surf over them.
## Unconverted fans that reach you grab at you and cost Lift.
##
## Stats and flags live in TYPES — adding or tuning a fan type is a one-place edit.

signal converted(fan)

enum Type { FAN, HEADPHONES, SKEPTIC, ELITE, CARL }

const TYPES := {
	Type.FAN: {
		"name": "Fan", "color": Color("#C85A7C"),
		"phones": 0.0, "crossed": 0.0, "hype": 3.0,
		"radius": 15.0, "chase": 0.0, "grab": 10.0, "score": 10,
	},
	Type.HEADPHONES: {
		"name": "Headphones", "color": Color("#4F7BD9"),
		"phones": 4.0, "crossed": 0.0, "hype": 3.0,
		"radius": 15.0, "chase": 0.0, "grab": 10.0, "score": 20,
	},
	Type.SKEPTIC: {
		"name": "Skeptic", "color": Color("#C9A43A"),
		"phones": 0.0, "crossed": 5.0, "hype": 3.0,
		"radius": 16.0, "chase": 80.0, "grab": 12.0, "score": 25,
	},
	Type.ELITE: {
		"name": "Superfan", "color": Color("#8E3FD1"),
		"phones": 4.0, "crossed": 5.0, "hype": 6.0,
		"radius": 26.0, "chase": 50.0, "grab": 18.0, "score": 80,
	},
	# Carl: not an obstacle — a glimpse of your lost friend. Touch him to log a
	# sighting. He darts sideways through the crowd and is gone in a few beats.
	Type.CARL: {
		"name": "Carl", "color": Color("#FF8A3D"),
		"phones": 0.0, "crossed": 0.0, "hype": 0.0,
		"radius": 16.0, "chase": 0.0, "grab": 0.0, "score": 250, "carl": true,
	},
}

# How much each source counts against each layer (multiplier on its power).
const MODS := {
	"glowstick": {"phones": 0.5,  "crossed": 1.0, "hype": 1.0},
	"blast":     {"phones": 2.0,  "crossed": 1.5, "hype": 1.0},
}

const DANCE_COLORS := [Color("#FF5FA2"), Color("#5FE1FF"), Color("#B6F23A"), Color("#FFD23F")]

static var all_fans: Array = []          ## live fans (registry, not a group scan)
# Shared per-frame context the game sets once, instead of every fan looking it up.
static var scroll_speed: float = 120.0   ## px/s the crowd flows toward the player
static var player_pos: Vector2 = Vector2.ZERO
static var pulse: float = 0.0            ## conductor.beat_pulse(), drives the dance bob

var fan_type: int = Type.FAN
var radius: float = 15.0
var chase: float = 0.0
var grab_cost: float = 12.0
var score: int = 10
var is_carl: bool = false
var color: Color = Color.WHITE

var phones: float = 0.0
var crossed: float = 0.0
var hype: float = 0.0
var max_phones: float = 0.0
var max_crossed: float = 0.0
var max_hype: float = 0.0

var is_converted: bool = false
var touched: bool = false                ## already grabbed you / gave you lift
var drift_x: float = 0.0                 ## sideways wander (Carl darts)
var _flash: float = 0.0                  ## hit flash, faded by _process (no per-hit tween)
var _dance_color: Color = Color.WHITE

func _ready() -> void:
	all_fans.append(self)

func _exit_tree() -> void:
	all_fans.erase(self)

func configure(type: int) -> void:
	fan_type = type
	var info: Dictionary = TYPES[type]
	color = info["color"]
	radius = info["radius"]
	chase = info["chase"]
	grab_cost = info["grab"]
	score = info["score"]
	is_carl = info.get("carl", false)
	max_phones = info["phones"]
	max_crossed = info["crossed"]
	max_hype = info["hype"]
	phones = max_phones
	crossed = max_crossed
	hype = max_hype
	_dance_color = DANCE_COLORS[randi() % DANCE_COLORS.size()]
	if is_carl:
		drift_x = 160.0 * (1.0 if randf() < 0.5 else -1.0)
	queue_redraw()

func total_vibe() -> float:
	return phones + crossed + hype

## Apply `power` from `source` ("glowstick" / "blast") through the layers in
## order. Returns true if this hit converted the fan.
func win_over(power: float, source: String) -> bool:
	if is_converted or is_carl:
		return false
	var mods: Dictionary = MODS[source]
	var remaining := power
	for layer in ["phones", "crossed", "hype"]:
		var hp: float = get(layer)
		if hp <= 0.0 or remaining <= 0.0:
			continue
		var effective: float = remaining * mods[layer]
		if effective >= hp:
			set(layer, 0.0)
			remaining -= hp / mods[layer]   # unused power flows to the next layer
		else:
			set(layer, hp - effective)
			remaining = 0.0
	_flash = 0.12
	queue_redraw()
	if total_vibe() <= 0.001:
		_convert()
		return true
	return false

func _convert() -> void:
	is_converted = true
	chase = 0.0
	queue_redraw()
	converted.emit(self)

func _process(delta: float) -> void:
	var v := Vector2(drift_x, scroll_speed)
	if chase > 0.0 and not is_converted:
		var to := player_pos - position
		if to.y > -40.0 and to.length() < 320.0:   # only while you're ahead/near
			v.x += clamp(to.x, -1.0, 1.0) * chase
	position += v * delta
	if _flash > 0.0:
		_flash = max(_flash - delta, 0.0)
	queue_redraw()

func _draw() -> void:
	var bob := 0.0
	var body := color
	if is_converted:
		bob = -6.0 * pulse
		body = _dance_color
	if _flash > 0.0:
		body = body.lerp(Color.WHITE, 0.7)
	var r := radius
	var c := Vector2(0, bob)
	# Body + head.
	draw_circle(c + Vector2(0, r * 0.35), r, body.darkened(0.15))
	draw_circle(c - Vector2(0, r * 0.55), r * 0.55, body.lightened(0.15))
	if is_carl:
		# Bucket hat so Carl reads instantly.
		draw_rect(Rect2(c + Vector2(-r * 0.7, -r * 1.25), Vector2(r * 1.4, r * 0.35)), Color("#2B2B2B"))
		draw_rect(Rect2(c + Vector2(-r * 0.45, -r * 1.55), Vector2(r * 0.9, r * 0.35)), Color("#2B2B2B"))
		return
	if is_converted:
		# Arms up, dancing.
		draw_line(c + Vector2(-r * 0.6, 0), c + Vector2(-r * 1.1, -r * 1.2 + bob), body, 3.0)
		draw_line(c + Vector2(r * 0.6, 0), c + Vector2(r * 1.1, -r * 1.2 + bob), body, 3.0)
		return
	if phones > 0.0:
		draw_arc(c - Vector2(0, r * 0.55), r * 0.7, PI, TAU, 10, Color("#6FA0FF"), 3.0)
		draw_circle(c + Vector2(-r * 0.7, -r * 0.5), r * 0.22, Color("#6FA0FF"))
		draw_circle(c + Vector2(r * 0.7, -r * 0.5), r * 0.22, Color("#6FA0FF"))
	if crossed > 0.0:
		draw_line(c + Vector2(-r * 0.8, r * 0.1), c + Vector2(r * 0.8, r * 0.6), Color("#F2CF5B"), 4.0)
		draw_line(c + Vector2(r * 0.8, r * 0.1), c + Vector2(-r * 0.8, r * 0.6), Color("#F2CF5B"), 4.0)
	# Layer bar under the fan (only once worn down at all, so the crowd stays readable).
	var maxv := max_phones + max_crossed + max_hype
	if maxv > 0.0 and total_vibe() < maxv:
		var w := r * 2.2
		var x0 := -w / 2.0
		var y0 := r * 1.5 + bob
		draw_rect(Rect2(x0, y0, w, 4), Color(0, 0, 0, 0.6))
		var x := x0
		for pair in [[phones, Color("#6FA0FF")], [crossed, Color("#F2CF5B")], [hype, Color("#FF5FA2")]]:
			var seg: float = w * pair[0] / maxv
			if seg > 0.0:
				draw_rect(Rect2(x, y0, seg, 4), pair[1])
				x += seg
