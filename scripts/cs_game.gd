extends Node2D
class_name CSGame

## "Find Carl" crowd-surf prototype: one level = one song.
##
## You crowd-surf up a vertical crowd toward the main stage. The CSConductor is
## the clock for everything: the crowd spawns on the beat with rules picked by
## the current section's kind (SECTION_RULES), drops hit with an elite burst and
## a screen flash, and the boss section brings the DJ on stage. Reaching the end
## of the song = reaching the stage. Lift is your health: grabby fans and the
## DJ's attacks drain it, surfing over converted (dancing) fans refills it.

signal ended(won: bool)

const BEATMAP := "res://assets/music/test_track.json"
const TRACK := "res://assets/music/test_track.wav"
const MAP_PICKER := "res://scenes/map_picker.tscn"

const FIELD := Rect2(340, 0, 600, 720)
const BOSS_POS := Vector2(640, 120)
const LIFT_PER_DANCER := 6.0
const LIFT_PER_GROOVE := 2.0   ## Lift per beat of input at full groove — staying in the pocket keeps you up
const FREAK_OUT_GROOVE := 0.45  ## 16ths at a human ~25 ms wobble score ~0.5 — that counts
# Groove tiers for feedback, highest first: [min groove, label, color].
const GROOVE_TIERS := [
	[0.85, "LOCKED IN", Color("#FFD23F")],
	[0.6, "GROOVING", Color("#5FE1FF")],
	[0.3, "FINDING IT", Color("#9AA3B0")],
	[0.0, "OFF BEAT", Color("#7D8794")],
]

# Gameplay per section kind — the one place to tune pacing against the music.
#   every:  spawn on every Nth beat (0 = none)     count: fans per spawn
#   mix:    {CSFan.Type: weight}                   scroll: crowd flow px/s
#   burst:  fans spawned the moment the section starts (drops "hit")
#   carl:   chance per beat that Carl darts through (max once per section)
const SECTION_RULES := {
	"intro":  {"every": 4, "count": 1, "scroll": 90.0,  "mix": {CSFan.Type.FAN: 1}},
	"groove": {"every": 2, "count": 1, "scroll": 120.0, "mix": {CSFan.Type.FAN: 3, CSFan.Type.HEADPHONES: 1}, "carl": 0.06},
	"build":  {"every": 1, "count": 1, "scroll": 140.0, "mix": {CSFan.Type.FAN: 2, CSFan.Type.HEADPHONES: 1, CSFan.Type.SKEPTIC: 1}},
	"drop":   {"every": 1, "count": 1, "scroll": 190.0, "mix": {CSFan.Type.FAN: 4, CSFan.Type.HEADPHONES: 2, CSFan.Type.SKEPTIC: 2, CSFan.Type.ELITE: 1},
		"burst": [CSFan.Type.ELITE, CSFan.Type.ELITE]},
	"break":  {"every": 4, "count": 1, "scroll": 70.0,  "mix": {CSFan.Type.FAN: 1}, "carl": 0.15},
	"boss":   {"every": 2, "count": 1, "scroll": 140.0, "mix": {CSFan.Type.FAN: 3, CSFan.Type.HEADPHONES: 1, CSFan.Type.SKEPTIC: 1},
		"boss": true, "burst": [CSFan.Type.ELITE]},
	"outro":  {"every": 0, "count": 0, "scroll": 80.0,  "mix": {}},
}

@export var use_audio: bool = true      ## false in tests: manual clock, no sound

var conductor: CSConductor
var player: CSPlayer
var boss: CSBoss = null
var score: int = 0
var best_combo: int = 0
var fans_won: int = 0
var carl_sightings: int = 0
var carl_chances: int = 0               ## sections where Carl could appear
var blasts: int = 0
var groove: CSGroove = CSGroove.new()
var _groove_sum: float = 0.0
var _tier: String = ""
var damage_from := {"grab": 0.0, "ring": 0.0}   ## where Lift went — for tuning
var over: bool = false
var won: bool = false

var _scroll: float = 90.0
var _scroll_target: float = 90.0
var _scroll_offset: float = 0.0
var _carl_this_section: bool = false
var _flash: float = 0.0
var _shake: float = 0.0
var _popups: Array = []                 ## [{text, pos, t, color}] drawn in _draw (no nodes)
var _camera: Camera2D
var _hud: CanvasLayer
var _ui := {}

func _ready() -> void:
	CSGlowstick.reset_pool()
	_camera = Camera2D.new()
	_camera.position = Vector2(640, 360)
	add_child(_camera)

	conductor = CSConductor.new()
	conductor.manual_clock = not use_audio
	add_child(conductor)
	var stream: AudioStream = load(TRACK) if use_audio and ResourceLoader.exists(TRACK) else null
	conductor.load_song(BEATMAP, stream)
	groove.setup(conductor.seconds_per_beat(), conductor.offset)
	groove.max_sub = 4
	conductor.beat.connect(_on_beat)
	conductor.half_beat.connect(_on_half_beat)
	conductor.section_changed.connect(_on_section_changed)
	conductor.finished.connect(_on_song_finished)

	player = CSPlayer.new()
	player.field = FIELD
	player.position = Vector2(FIELD.get_center().x, FIELD.end.y - 90)
	add_child(player)

	CSGlowstick.field_top = FIELD.position.y - 20
	CSGlowstick.prewarm(self)
	_build_hud()
	# Capture the mouse while surfing: the OS cursor is hidden and locked, and
	# the surfer steers by mouse motion (see CSPlayer.nudge_reticle).
	if use_audio:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	conductor.play()

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

# --- Beat-driven flow ---------------------------------------------------------

func _on_beat(b: int) -> void:
	if over:
		return
	var s := conductor.current_section()
	var rules: Dictionary = SECTION_RULES.get(s.get("kind", ""), {})
	var every: int = rules.get("every", 0)
	if every > 0 and b % every == 0:
		for i in rules.get("count", 1):
			spawn_fan(_pick(rules["mix"]))
	if rules.has("carl") and not _carl_this_section and randf() < rules["carl"]:
		_carl_this_section = true
		spawn_fan(CSFan.Type.CARL)
	if is_instance_valid(boss) and s.get("kind", "") == "boss":   # the DJ only attacks during their drop
		boss.on_beat(b, player.position)

func _on_half_beat(_n: int) -> void:
	if over:
		return
	player.throw_on_half_beat(self)

func _on_section_changed(s: Dictionary) -> void:
	var rules: Dictionary = SECTION_RULES.get(s["kind"], {})
	_scroll_target = rules.get("scroll", 120.0)
	_carl_this_section = false
	if rules.has("carl"):
		carl_chances += 1
	for t in rules.get("burst", []):
		spawn_fan(t)
	if s["kind"] in ["drop", "boss"]:
		_flash = 0.35
		_shake = 0.4
		popup("DROP!", Vector2(FIELD.get_center().x, 300), Color("#FFD23F"), 1.2)
	if rules.get("boss", false) and boss == null:
		_spawn_boss()
	if _ui.has("section"):
		_ui["section"].text = s["name"].to_upper()

func _on_song_finished() -> void:
	# The song carried you to the stage. You only find out where Carl went if the
	# DJ is on your side.
	_end(is_instance_valid(boss) and boss.defeated)

func _spawn_boss() -> void:
	boss = CSBoss.new()
	boss.position = BOSS_POS
	add_child(boss)
	boss.phase_changed.connect(_on_boss_phase)
	boss.won_over.connect(_on_boss_won_over)
	popup("WIN OVER THE DJ!", Vector2(FIELD.get_center().x, 420), Color("#FF5FA2"), 2.5, 28)
	popup("blast on the beat to send cheers to the stage", Vector2(FIELD.get_center().x, 452), UITheme.TEXT, 2.5, 15)

func _on_boss_phase(p: int) -> void:
	popup("PHASE %d" % p, BOSS_POS + Vector2(0, 120), Color("#FF5FA2"), 1.0)
	_shake = 0.25

func _on_boss_won_over() -> void:
	score += 1000
	popup("THE DJ IS VIBING!", BOSS_POS + Vector2(0, 140), Color("#B6F23A"), 2.0)
	for f in CSFan.all_fans.duplicate():
		if is_instance_valid(f) and not f.is_carl:
			f.win_over(999.0, "blast")

# --- Spawning -----------------------------------------------------------------

func _pick(mix: Dictionary) -> int:
	var total := 0
	for w in mix.values():
		total += w
	var roll: int = randi() % maxi(total, 1)
	for t in mix:
		roll -= mix[t]
		if roll < 0:
			return t
	return CSFan.Type.FAN

func spawn_fan(type: int, pos: Variant = null) -> CSFan:
	var f := CSFan.new()
	f.configure(type)
	if pos == null:
		var margin := f.radius + 8.0
		f.position = Vector2(randf_range(FIELD.position.x + margin, FIELD.end.x - margin), FIELD.position.y - f.radius)
		if type == CSFan.Type.CARL:
			f.position = Vector2(FIELD.position.x + 20 if f.drift_x > 0 else FIELD.end.x - 20, randf_range(240, 420))
	else:
		f.position = pos
	f.converted.connect(_on_fan_converted)
	add_child(f)
	return f

func _on_fan_converted(f: CSFan) -> void:
	fans_won += 1
	score += f.score * (1 + player.combo / 4)

# --- Per-frame ----------------------------------------------------------------

func _process(delta: float) -> void:
	CSFan.pulse = conductor.beat_pulse()
	CSFan.player_pos = player.position
	_scroll = lerp(_scroll, _scroll_target, min(delta * 2.0, 1.0))
	CSFan.scroll_speed = _scroll
	_scroll_offset = fposmod(_scroll_offset + _scroll * delta, 80.0)
	if not over:
		_check_contacts()
		if is_instance_valid(boss):
			var dmg := boss.hit_test(player.position, CSPlayer.RADIUS)
			if dmg > 0.0 and player.take_hit(dmg):
				damage_from["ring"] += dmg
				_shake = 0.2
				popup("-%d" % dmg, player.position + Vector2(0, -30), Color("#FF7B6E"))
		if player.lift <= 0.0:
			_end(false)
	_cull_fans()
	for p in _popups:
		p["t"] -= delta
		p["pos"].y -= 30.0 * delta
	_popups = _popups.filter(func(p): return p["t"] > 0.0)
	_flash = max(_flash - delta, 0.0)
	_shake = max(_shake - delta, 0.0)
	_camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 10.0 * _shake
	if groove.groove(conductor.song_time) < 0.3 and player.combo > 0 and blasts > 0 \
			and conductor.song_time - groove._times[-1] > CSGroove.IDLE_BEATS * conductor.seconds_per_beat():
		player.combo = 0   # stopped playing: the groove (and combo) fades
	best_combo = max(best_combo, player.combo)
	_update_hud()
	queue_redraw()

func _check_contacts() -> void:
	for f in CSFan.all_fans:
		if not is_instance_valid(f) or f.touched:
			continue
		if player.position.distance_to(f.position) > f.radius + CSPlayer.RADIUS:
			continue
		if f.is_carl:
			f.touched = true
			carl_sightings += 1
			score += f.score
			popup("CARL?! ...he slipped away", f.position + Vector2(0, -30), Color("#FF8A3D"), 1.6)
			f.queue_free()
		elif f.is_converted:
			f.touched = true
			player.gain_lift(LIFT_PER_DANCER)
			popup("+lift", f.position + Vector2(0, -20), Color("#B6F23A"), 0.5)
		elif player.take_hit(f.grab_cost):
			damage_from["grab"] += f.grab_cost
			f.touched = true
			_shake = 0.15
			popup("grabbed!", player.position + Vector2(0, -30), Color("#FF7B6E"), 0.6)

func _cull_fans() -> void:
	for f in CSFan.all_fans.duplicate():
		if is_instance_valid(f) and (f.position.y > FIELD.end.y + 40 or f.position.x < FIELD.position.x - 40 or f.position.x > FIELD.end.x + 40):
			f.queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("jump") or event.is_action_pressed("attack"):
		# Re-grab the mouse if focus was lost (e.g. Cmd-Tab) — that click just recaptures.
		if use_audio and not over and event is InputEventMouseButton \
				and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		try_hype_blast()
	elif event.is_action_pressed("restart"):
		get_tree().reload_current_scene()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().change_scene_to_file(MAP_PICKER)

## One rhythm input (click / Space / tap / shake): feeds the groove meter and
## fires a Hype Blast sized by it. Returns the groove tier label, or "" if it
## came too fast to count.
func try_hype_blast() -> String:
	if over or not player.can_blast(conductor.beat_pos()):
		return ""
	var g := groove.record(conductor.song_time)
	var s := groove.subdivision()
	player.hype_blast(g, s, conductor.beat_pos())
	blasts += 1
	_groove_sum += g
	player.gain_lift(LIFT_PER_GROOVE * g * g / s)
	var tier := groove_tier(g, s)
	if tier[1] != _tier:   # announce tier changes, not every input
		_tier = tier[1]
		popup(_tier + "!", player.position + Vector2(0, -44), tier[2], 0.7)
	if g > 0.3 and is_instance_valid(boss) and boss.hittable() and randf() < 0.5 / s + 0.25:
		popup("cheer!", boss.position + Vector2(randf_range(-90, 90), 70), Color("#FF5FA2"), 0.6, 15)
	return tier[1]

## [min, label, color] for a groove value; fast + in time gets its own tier.
func groove_tier(g: float, s: int) -> Array:
	if s >= 4 and g >= FREAK_OUT_GROOVE:
		return [FREAK_OUT_GROOVE, "FREAKING OUT", Color("#FF5FA2")]
	for t in GROOVE_TIERS:
		if g >= t[0]:
			return t
	return GROOVE_TIERS[-1]

func avg_groove() -> float:
	return 0.0 if blasts == 0 else _groove_sum / blasts

func popup(text: String, pos: Vector2, color: Color = Color.WHITE, life: float = 0.8, size: int = 22) -> void:
	_popups.append({"text": text, "pos": pos, "t": life, "life": life, "color": color, "size": size})

func _end(victory: bool) -> void:
	if over:
		return
	over = true
	won = victory
	player.input_enabled = false
	_popups.clear()   # nothing should bleed through the results panel
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE   # results buttons need a cursor
	_show_results()
	ended.emit(victory)

# --- Drawing (gray-box) -------------------------------------------------------

func _draw() -> void:
	var pulse := conductor.beat_pulse()
	var kind: String = conductor.current_section().get("kind", "intro")
	draw_rect(Rect2(0, 0, 1280, 720), UITheme.TABLE)
	# Crowd floor: stripes flowing toward you at the scroll speed.
	draw_rect(FIELD, Color("#1E1A26"))
	var y := FIELD.position.y - 80.0 + _scroll_offset
	while y < FIELD.end.y:
		draw_rect(Rect2(FIELD.position.x, y, FIELD.size.x, 2), Color(1, 1, 1, 0.05))
		y += 80.0
	# Stage at the top, lights pulse on the beat (harder in drops).
	var hot := kind in ["drop", "boss"]
	draw_rect(Rect2(FIELD.position.x, 0, FIELD.size.x, 60), Color("#2A2F3A"))
	for i in 6:
		var x := FIELD.position.x + 50.0 + i * 100.0
		var c: Color = CSFan.DANCE_COLORS[(i + int(conductor.beat_pos())) % CSFan.DANCE_COLORS.size()] if hot else Color("#5FE1FF")
		draw_circle(Vector2(x, 20), 8, Color(c, 0.4 + 0.6 * pulse))
		if hot:
			draw_line(Vector2(x, 20), Vector2(x + sin(conductor.song_time * 2.0 + i) * 200.0, FIELD.end.y), Color(c, 0.08 + 0.12 * pulse), 10.0)
	# Beat indicator under the surfer: a ring that closes onto you each beat,
	# so you can see when to hit Space even with the sound off.
	if not over:
		var frac := fposmod(conductor.beat_pos(), 1.0)
		draw_arc(player.position, 18.0 + 50.0 * (1.0 - frac), 0, TAU, 40, Color(1, 1, 1, 0.25 * frac), 2.0)

# Popups draw above everything in a dedicated overlay so they're never hidden.
class _Overlay extends Node2D:
	var game
	func _process(_d: float) -> void:
		queue_redraw()
	func _draw() -> void:
		# Side gutters sit above the play layer so boss attacks never cover the HUD.
		var f: Rect2 = CSGame.FIELD
		var pulse: float = game.conductor.beat_pulse()
		draw_rect(Rect2(-40, -40, f.position.x + 40, 800), UITheme.TABLE)
		draw_rect(Rect2(f.end.x, -40, 1320 - f.end.x, 800), UITheme.TABLE)
		draw_line(Vector2(f.position.x, 0), Vector2(f.position.x, 720), Color(1, 1, 1, 0.08 + 0.25 * pulse), 2.0)
		draw_line(Vector2(f.end.x, 0), Vector2(f.end.x, 720), Color(1, 1, 1, 0.08 + 0.25 * pulse), 2.0)
		if game._flash > 0.0:
			draw_rect(Rect2(0, 0, 1280, 720), Color(1, 1, 1, game._flash * 0.6))
		var font := UITheme.display_font(700)
		for p in game._popups:
			var a: float = clamp(p["t"] / p["life"] * 2.0, 0.0, 1.0)
			var size: int = p.get("size", 22)
			var w := font.get_string_size(p["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			draw_string_outline(font, p["pos"] - Vector2(w / 2.0, 0), p["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Color(0, 0, 0, a))
			draw_string(font, p["pos"] - Vector2(w / 2.0, 0), p["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(p["color"], a))

# --- HUD ----------------------------------------------------------------------

func _build_hud() -> void:
	var overlay := _Overlay.new()
	overlay.game = self
	overlay.z_index = 100
	add_child(overlay)

	_hud = CanvasLayer.new()
	add_child(_hud)
	var root := Control.new()
	root.theme = UITheme.theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(root)

	var left := VBoxContainer.new()
	left.position = Vector2(28, 28)
	left.custom_minimum_size = Vector2(FIELD.position.x - 56, 0)
	left.add_theme_constant_override("separation", 6)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(left)
	left.add_child(UITheme.caption("MAIN STAGE · PROTOTYPE"))
	left.add_child(UITheme.label("FIND CARL", 34, UITheme.TEXT, UITheme.display_font(700)))
	left.add_child(UITheme.caption(conductor.title.to_upper()))
	_ui["section"] = UITheme.label("—", 18, UITheme.ACCENT, UITheme.display_font(600))
	left.add_child(_ui["section"])
	left.add_child(_spacer(18))
	left.add_child(UITheme.caption("SCORE"))
	_ui["score"] = UITheme.label("0", 28, UITheme.TEXT, UITheme.display_font(700))
	left.add_child(_ui["score"])
	left.add_child(UITheme.caption("GROOVE"))
	_ui["groove"] = _bar(Color("#FFD23F"))
	left.add_child(_ui["groove"])
	_ui["groove_label"] = UITheme.label("click in time with the beat", 13, UITheme.MUTED)
	left.add_child(_ui["groove_label"])
	left.add_child(UITheme.caption("COMBO"))
	_ui["combo"] = UITheme.label("0", 28, UITheme.TEXT, UITheme.display_font(700))
	left.add_child(_ui["combo"])
	left.add_child(_spacer(18))
	left.add_child(UITheme.caption("GOAL"))
	left.add_child(UITheme.label("Reach the stage and win over\nthe DJ on the final drop.", 14, UITheme.TEXT))
	left.add_child(_spacer(10))
	var help := UITheme.label("Move: mouse (or WASD / arrows)\nClick in time: Hype Blast\n  steady rhythm = bigger blasts\n  go double-time in builds & drops!\n  (Space works too; cheers at the DJ)\nGlowsticks fly on the beat\nSurf over dancers for lift\nTouch Carl (orange, bucket hat)\nR restart · Esc maps", 13, UITheme.MUTED)
	left.add_child(help)


	var right := VBoxContainer.new()
	right.position = Vector2(FIELD.end.x + 28, 28)
	right.custom_minimum_size = Vector2(1280 - FIELD.end.x - 56, 0)
	right.add_theme_constant_override("separation", 6)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(right)
	right.add_child(UITheme.caption("LIFT"))
	_ui["lift"] = _bar(Color("#B6F23A"))
	right.add_child(_ui["lift"])
	right.add_child(_spacer(10))
	right.add_child(UITheme.caption("DISTANCE TO STAGE"))
	_ui["progress"] = _bar(Color("#5FE1FF"))
	right.add_child(_ui["progress"])
	right.add_child(_spacer(10))
	right.add_child(UITheme.caption("CARL SIGHTINGS"))
	_ui["carl"] = UITheme.label("0", 28, Color("#FF8A3D"), UITheme.display_font(700))
	right.add_child(_ui["carl"])
	right.add_child(_spacer(10))
	right.add_child(UITheme.caption("DJ WON OVER"))
	_ui["boss"] = _bar(Color("#FF5FA2"))
	right.add_child(_ui["boss"])
	_ui["boss_status"] = UITheme.label("Arrives on the final drop", 13, UITheme.MUTED)
	right.add_child(_ui["boss_status"])

	var results := PanelContainer.new()
	results.add_theme_stylebox_override("panel", UITheme.panel_box(14, 28))
	results.visible = false
	results.custom_minimum_size = Vector2(460, 0)
	results.position = Vector2(640 - 230, 170)
	root.add_child(results)
	_ui["results"] = results
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 10)
	results.add_child(rv)
	_ui["res_title"] = UITheme.label("", 28, UITheme.TEXT, UITheme.display_font(700))
	_ui["res_title"].autowrap_mode = TextServer.AUTOWRAP_WORD
	rv.add_child(_ui["res_title"])
	_ui["res_body"] = UITheme.label("", 15, UITheme.MUTED)
	_ui["res_body"].autowrap_mode = TextServer.AUTOWRAP_WORD
	rv.add_child(_ui["res_body"])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	rv.add_child(row)
	var again := Button.new()
	again.text = "Play again"
	UITheme.style_button(again, "primary")
	again.pressed.connect(func(): get_tree().reload_current_scene())
	row.add_child(again)
	var back := Button.new()
	back.text = "Map picker"
	UITheme.style_button(back, "secondary")
	back.pressed.connect(func(): get_tree().change_scene_to_file(MAP_PICKER))
	row.add_child(back)
	_ui["again"] = again

func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

func _bar(color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(0, 14)
	b.max_value = 1.0
	b.show_percentage = false
	b.add_theme_stylebox_override("background", UITheme.box(Color("#2C323C"), Color.TRANSPARENT, 0, 7, 0, 0))
	b.add_theme_stylebox_override("fill", UITheme.box(color, Color.TRANSPARENT, 0, 7, 0, 0))
	return b

func _update_hud() -> void:
	if _ui.is_empty():
		return
	_ui["score"].text = str(score)
	_ui["combo"].text = "%d%s" % [player.combo, "  ×3 glowsticks" if player.combo >= CSPlayer.COMBO_TRIPLE else ""]
	var g := groove.groove(conductor.song_time)
	_ui["groove"].value = g
	if blasts > 0:
		var t := groove_tier(g, groove.subdivision())
		var pace: String = {1: "quarter notes", 2: "8th notes", 4: "16th notes"}[groove.subdivision()]
		_ui["groove_label"].text = "%s · %s" % [t[1], pace]
		_ui["groove_label"].add_theme_color_override("font_color", t[2])
	_ui["lift"].value = player.lift / CSPlayer.MAX_LIFT
	_ui["progress"].value = conductor.progress()
	_ui["carl"].text = str(carl_sightings)
	_ui["boss"].value = dj_won_over()
	if is_instance_valid(boss):
		_ui["boss_status"].text = "WON OVER!" if boss.defeated else "%d%% · blast on the beat!" % int(dj_won_over() * 100.0)
		_ui["boss_status"].add_theme_color_override("font_color", Color("#B6F23A") if boss.defeated else Color("#FF5FA2"))

## 0..1 how far the DJ has been won over (0 before they arrive).
func dj_won_over() -> float:
	if not is_instance_valid(boss):
		return 0.0
	return 1.0 - boss.total() / boss.max_total()

func _show_results() -> void:
	var title: String
	var why := ""
	var pct := int(dj_won_over() * 100.0)
	if won:
		title = "You won over the DJ!"
		why = "They got on the mic: \"CARL, YOUR FRIEND IS LOOKING FOR YOU.\" Word is he's headed to the next stage."
	elif player.lift <= 0.0:
		title = "You got dropped."
		why = "The crowd let you fall before the stage. Surf over dancing fans and keep clicking in time to keep your Lift up."
	else:
		title = "You reached the stage, but the DJ wasn't won over."
		why = "The DJ was only %d%% won over when the song ended, so nobody could tell you where Carl went. A steady groove sends cheers to the stage, and going double-time in time hits even harder." % pct
	_ui["res_title"].text = title
	_ui["res_body"].text = "%s\n\nScore %d · Best combo %d · Fans won over %d\nAvg groove %d%% · DJ won over %d%% · Carl sightings %d" % [
		why, score, best_combo, fans_won, int(round(avg_groove() * 100.0)), pct, carl_sightings]
	_ui["results"].visible = true
