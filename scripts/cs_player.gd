extends Node2D
class_name CSPlayer

## You, crowd-surfing toward the stage. Move with the mouse: the game captures
## the cursor and steers a virtual reticle by mouse *motion* (event.relative),
## and the surfer chases the reticle at a capped speed, so dodging stays a
## skill. Relative motion is used because absolute cursor positions proved
## unreliable on macOS (stale/frozen); captured + relative is what the earlier
## FP prototype used successfully on the same machine or WASD/arrows —
## whichever you touched last wins. Glowsticks fly on every eighth note
## automatically (the game calls throw_on_half_beat). Click (or Space) ON the
## beat for a Hype Blast: a radial wave that strips headphones and
## crossed arms. Perfect timing = bigger + stronger, and builds your combo; a
## mistimed blast fizzles and drops the combo.

const SPEED := 380.0            ## keyboard speed
const MOUSE_SPEED := 720.0      ## max speed chasing the cursor (not a teleport: grabs stay fair)
const RADIUS := 14.0
const MAX_LIFT := 100.0
const INVULN := 1.2
# Hype Blast strength comes from your GROOVE (CSGroove: how steady your
# rhythm is over the last few beats), not a per-hit judgement. Every input
# blasts; tighter groove = bigger, stronger blast.
const BLAST_RADIUS := Vector2(60.0, 210.0)   ## radius at groove 0 → 1
const BLAST_POWER := Vector2(0.5, 4.0)       ## power at groove 0 → 1
# Going faster splits power across more inputs, but not evenly: per-input power
# scales by sub^-FAST_SPLIT, so in-time 8ths/16ths out-hype quarters (16ths at
# full groove ≈ 1.7× per beat). That's the "legal freak-out".
const FAST_SPLIT := 0.6
const CHEER_MAX := 2.0           ## boss hype per distant blast at full groove (quarter notes)
const MIN_GAP_BEATS := 0.18      ## fastest input that counts (just under a 16th)
const COMBO_TRIPLE := 8         ## combo needed for a 3-way glowstick spread

var field: Rect2 = Rect2(0, 0, 600, 720)
var lift: float = MAX_LIFT
var invuln: float = 0.0
var combo: int = 0
var input_enabled: bool = true
var use_mouse: bool = false     ## flips on with mouse motion, off with a movement key
var mouse_target: Vector2 = Vector2.ZERO   ## the virtual reticle, in game space
var mouse_sensitivity: float = 1.0
var _blast_fx: float = 0.0
var _blast_radius: float = 0.0
var _blast_color: Color = Color.WHITE
var _last_blast_beat: float = -99.0

func _process(delta: float) -> void:
	if input_enabled:
		var dir := Vector2(
			Input.get_axis("move_left", "move_right"),
			Input.get_axis("move_up", "move_down"))
		if dir != Vector2.ZERO:
			use_mouse = false
		if use_mouse:
			position = position.move_toward(mouse_target, MOUSE_SPEED * delta)
		else:
			if dir.length() > 1.0:
				dir = dir.normalized()
			position += dir * SPEED * delta
	position.x = clamp(position.x, field.position.x + RADIUS, field.end.x - RADIUS)
	position.y = clamp(position.y, field.position.y + 180.0, field.end.y - RADIUS)
	if invuln > 0.0:
		invuln = max(invuln - delta, 0.0)
	if _blast_fx > 0.0:
		_blast_fx = max(_blast_fx - delta, 0.0)
	queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and input_enabled:
		nudge_reticle(event.relative)

## Move the virtual reticle by a mouse delta. The first nudge after keyboard
## play starts the reticle at the surfer, so switching never yanks you.
func nudge_reticle(rel: Vector2) -> void:
	if rel == Vector2.ZERO:
		return
	if not use_mouse:
		use_mouse = true
		mouse_target = position
	mouse_target += rel * mouse_sensitivity
	mouse_target.x = clamp(mouse_target.x, field.position.x + RADIUS, field.end.x - RADIUS)
	mouse_target.y = clamp(mouse_target.y, field.position.y + 180.0, field.end.y - RADIUS)

func throw_on_half_beat(parent: Node) -> void:
	var p := 1.0 + mini(combo, 16) * 0.05   # combo makes every throw a little stronger
	var dir := throw_dir()
	CSGlowstick.throw(parent, position + dir * 18.0, dir * CSGlowstick.SPEED, p)
	if combo >= COMBO_TRIPLE:
		for a in [-0.17, 0.17]:
			var d := dir.rotated(a)
			CSGlowstick.throw(parent, position + d * 16.0, d * CSGlowstick.SPEED, p)

## Straight up — except while the DJ is on the booth, when you throw at the
## stage, so dodging bass rings sideways never takes you out of the fight.
func throw_dir() -> Vector2:
	var boss = CSBoss.active
	if is_instance_valid(boss) and boss.hittable():
		return position.direction_to(boss.position)
	return Vector2.UP

## Attempt a Hype Blast with the given judgement. Returns the judgement actually
## applied ("" if locked out). Applies to fans + boss within the radius.
## Can another input count yet? (Faster than a 16th is ignored.)
func can_blast(beat_now: float) -> bool:
	return beat_now - _last_blast_beat >= MIN_GAP_BEATS

## Fire a Hype Blast shaped by `groove` (0..1) at subdivision `sub` (inputs per
## beat). Returns the power used, or -1.0 if it came too fast to count.
func hype_blast(groove: float, sub: int, beat_now: float) -> float:
	if not can_blast(beat_now):
		return -1.0
	_last_blast_beat = beat_now
	var split := pow(float(sub), -FAST_SPLIT)
	var radius: float = lerp(BLAST_RADIUS.x, BLAST_RADIUS.y, groove)
	var power: float = lerp(BLAST_POWER.x, BLAST_POWER.y, groove) * split
	var mult := 1.0 + mini(combo, 16) * 0.05
	for f in CSFan.all_fans.duplicate():
		if is_instance_valid(f) and position.distance_to(f.position) < radius + f.radius:
			f.win_over(power * mult, "blast")
	# In-groove blasts send a cheer wave to the stage: rhythm is how you win the
	# DJ over from anywhere. Surfing right up to the booth hits much harder.
	var boss = CSBoss.active
	if is_instance_valid(boss):
		if position.distance_to(boss.position) < radius + boss.RADIUS:
			boss.win_over(power * mult * 3.0, "blast")
		elif groove > 0.3:
			boss.win_over(CHEER_MAX * groove * groove * split * mult, "blast")
	# Combo = staying in the groove: builds while locked in, drops when you lose it.
	if groove >= 0.6:
		combo += 1
	elif groove < 0.3:
		combo = 0
	_blast_fx = 0.3
	_blast_radius = radius
	_blast_color = Color("#FFD23F") if groove >= 0.8 else (Color("#5FE1FF") if groove >= 0.5 else Color("#7D8794"))
	return power

## Something grabbed / hit you. Returns true if it landed (not invulnerable).
func take_hit(amount: float) -> bool:
	if invuln > 0.0 or amount <= 0.0:
		return false
	lift = max(lift - amount, 0.0)
	invuln = INVULN
	combo = 0
	return true

func gain_lift(amount: float) -> void:
	lift = min(lift + amount, MAX_LIFT)

func _draw() -> void:
	if _blast_fx > 0.0:
		var k := 1.0 - _blast_fx / 0.3
		draw_arc(Vector2.ZERO, _blast_radius * (0.3 + 0.7 * k), 0, TAU, 48,
			Color(_blast_color, 1.0 - k), 6.0)
	# Cursor reticle (the OS cursor is hidden while surfing) — shows where you're steering.
	# Always drawn in mouse mode (even under the surfer): four corner ticks
	# around the aim point, big enough to read past the surfer sprite.
	if use_mouse and input_enabled:
		var m := to_local(mouse_target)
		if m.length() > 6.0:
			draw_line(Vector2.ZERO, m, Color(1, 1, 1, 0.15), 1.0)
		for k in 4:
			var d := Vector2.from_angle(PI / 4.0 + k * PI / 2.0)
			draw_line(m + d * 22.0, m + d * 30.0, Color(1, 1, 1, 0.85), 2.5)
	if invuln > 0.0 and int(invuln * 20.0) % 2 == 0:
		return   # blink while invulnerable
	# Surfer: lying flat on raised hands.
	var pulse: float = CSFan.pulse
	draw_circle(Vector2(0, 4), RADIUS + 6, Color(1, 1, 1, 0.12 + 0.2 * pulse))
	draw_rect(Rect2(-9, -8, 18, 26), Color("#F2F4F7"))
	draw_circle(Vector2(0, -14), 9, Color("#FFD9B0"))
	draw_line(Vector2(-9, -4), Vector2(-20, -18), Color("#FFD9B0"), 3.0)
	draw_line(Vector2(9, -4), Vector2(20, -18), Color("#FFD9B0"), 3.0)
