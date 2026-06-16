extends Node3D

## Standalone tower sandbox — launched from the map picker.
## Left-drag to orbit, scroll to zoom, O to return to auto-orbit.
## Hold Fire to fire at the tower's natural cooldown rate.
## Esc returns to map picker.

const TOWER_SCENE      := preload("res://scenes/td_tower.tscn")
const ROCKET_SCENE     := preload("res://scenes/td_rocket.tscn")
const PROJECTILE_SCENE := preload("res://scenes/td_projectile.tscn")
const BOMB_SCENE       := preload("res://scenes/td_bomb.tscn")

# Camera spherical coords — angles in radians, radius in world units.
const CAM_TARGET   := Vector3(0.0, 0.5, 0.0)
const ORBIT_R      := 5.8
const ORBIT_PITCH  := 0.58   # ~33° above horizon
const ORBIT_SPEED  := 0.35   # rad/s auto-orbit
const DRAG_SENS    := 0.006  # rad/px
const ZOOM_STEP    := 0.35
const ZOOM_MIN     := 2.0
const ZOOM_MAX     := 12.0
const RETURN_SPEED := 2.5

# Positions of the dummy targets shown in front of the tower while firing.
# Beam uses all of them (one per max_targets); others use just index 0.
const DUMMY_POSITIONS := [
	Vector3(0.0,  0.8, -2.5),
	Vector3(-1.2, 0.8, -2.2),
	Vector3( 1.2, 0.8, -2.2),
	Vector3( 0.0, 0.8, -1.8),
]

var _tower: TDTower = null
var _current_type: int = TDTower.Type.MISSILE
var _camera: Camera3D = null
var _type_buttons: Array = []
var _legend: Label = null

# Dummy target node parented to World while fire is held (non-beam),
# or for the full 2s beam window. Set as _tower._target so the tower's
# own _process loop governs the cooldown and fires at its natural rate.
var _fire_target: Node3D = null
# Additional dummy nodes registered in TDEnemy.all_enemies for beam multi-target.
var _beam_dummies: Array = []
var _fire_held: bool = false

# Camera state
var _cam_yaw: float   = PI * 0.25
var _cam_pitch: float = ORBIT_PITCH
var _cam_r: float     = ORBIT_R

# Orbit / drag
var _orbiting: bool  = true
var _dragging: bool  = false
var _returning: bool = false


func _ready() -> void:
	_build_3d()
	_build_ui()
	_spawn_tower(_current_type)
	_apply_camera()


func _build_3d() -> void:
	var world := Node3D.new()
	world.name = "World"
	add_child(world)

	var ground := MeshInstance3D.new()
	var disc   := CylinderMesh.new()
	disc.top_radius      = 2.2
	disc.bottom_radius   = 2.2
	disc.height          = 0.06
	disc.radial_segments = 32
	ground.mesh = disc
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.22, 0.26, 0.30)
	ground.material_override = gmat
	ground.position.y = -0.03
	world.add_child(ground)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 35, 0)
	sun.light_energy = 1.2
	world.add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -150, 0)
	fill.light_energy = 0.4
	fill.light_color  = Color(0.7, 0.8, 1.0)
	world.add_child(fill)

	_camera = Camera3D.new()
	world.add_child(_camera)


func _build_ui() -> void:
	var ui := CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)

	var back := Button.new()
	back.text = "← Back"
	back.position = Vector2(12, 12)
	back.custom_minimum_size = Vector2(90, 36)
	back.pressed.connect(_go_back)
	ui.add_child(back)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.position.y = 12
	ui.add_child(hbox)

	for type in TDTower.Type.values():
		var info: Dictionary = TDTower.TYPES[type]
		var btn := Button.new()
		btn.text = info["name"]
		btn.custom_minimum_size = Vector2(110, 36)
		btn.add_theme_font_size_override("font_size", 14)
		var t: int = type
		btn.pressed.connect(func(): _switch_type(t))
		hbox.add_child(btn)
		_type_buttons.append(btn)

	_refresh_type_buttons()

	var bottom := HBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.position.y = -58
	ui.add_child(bottom)

	var upgrade := Button.new()
	upgrade.text = "Upgrade"
	upgrade.custom_minimum_size = Vector2(110, 40)
	upgrade.add_theme_font_size_override("font_size", 14)
	upgrade.pressed.connect(_upgrade)
	bottom.add_child(upgrade)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(16, 0)
	bottom.add_child(gap)

	var fire := Button.new()
	fire.text = "Fire"
	fire.custom_minimum_size = Vector2(110, 40)
	fire.add_theme_font_size_override("font_size", 14)
	fire.button_down.connect(_on_fire_down)
	fire.button_up.connect(_on_fire_up)
	bottom.add_child(fire)

	_legend = Label.new()
	_legend.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_legend.position = Vector2(12, -28)
	_legend.add_theme_font_size_override("font_size", 11)
	_legend.add_theme_color_override("font_color", Color(0.50, 0.53, 0.60))
	ui.add_child(_legend)
	_refresh_legend()


# ── Camera ────────────────────────────────────────────────────────────────────

func _apply_camera() -> void:
	var pos := Vector3(
		sin(_cam_yaw) * cos(_cam_pitch) * _cam_r,
		sin(_cam_pitch) * _cam_r,
		cos(_cam_yaw) * cos(_cam_pitch) * _cam_r
	)
	_camera.position = pos + CAM_TARGET
	_camera.look_at(CAM_TARGET, Vector3.UP)


func _refresh_legend() -> void:
	if _orbiting:
		_legend.text = "drag — orbit    scroll — zoom    O — stop orbit    Esc — back"
	else:
		_legend.text = "drag — orbit    scroll — zoom    O — resume orbit    Esc — back"


# ── Tower management ──────────────────────────────────────────────────────────

func _spawn_tower(type: int) -> void:
	_clear_fire_targets()
	if is_instance_valid(_tower):
		_tower.queue_free()
	_tower = TOWER_SCENE.instantiate() as TDTower
	_tower.projectile_scene = PROJECTILE_SCENE
	_tower.bomb_scene       = BOMB_SCENE
	_tower.rocket_scene     = ROCKET_SCENE
	get_node("World").add_child(_tower)
	_tower.configure(type)
	_current_type = type
	_refresh_type_buttons()


func _switch_type(type: int) -> void:
	_spawn_tower(type)


func _upgrade() -> void:
	if is_instance_valid(_tower) and not _tower.is_max_level():
		_tower.upgrade()


# ── Fire targets ──────────────────────────────────────────────────────────────

func _clear_fire_targets() -> void:
	if is_instance_valid(_fire_target):
		_fire_target.queue_free()
	_fire_target = null
	for d in _beam_dummies:
		if is_instance_valid(d):
			TDEnemy.all_enemies.erase(d)
			d.queue_free()
	_beam_dummies.clear()
	if is_instance_valid(_tower):
		_tower._target = null


func _on_fire_down() -> void:
	_fire_held = true
	if not is_instance_valid(_tower):
		return
	var s: Dictionary = TDTower.TYPES[_current_type]["tiers"][0]
	if s.get("beam", false):
		# Beam fires by finding entries in TDEnemy.all_enemies — populate with
		# as many dummies as the beam's max_targets so all arcs draw.
		_clear_fire_targets()
		var max_t: int = s.get("max_targets", 2)
		for i in min(max_t, DUMMY_POSITIONS.size()):
			var d := Node3D.new()
			d.position = DUMMY_POSITIONS[i]
			get_node("World").add_child(d)
			TDEnemy.all_enemies.append(d)
			_beam_dummies.append(d)
		get_tree().create_timer(2.0).timeout.connect(_clear_fire_targets)
	else:
		# Non-beam: create a persistent target and assign it to the tower.
		# The tower's own _process loop will fire at its natural cooldown rate.
		_clear_fire_targets()
		_fire_target = Node3D.new()
		_fire_target.position = DUMMY_POSITIONS[0]
		get_node("World").add_child(_fire_target)
		_tower._target = _fire_target


func _on_fire_up() -> void:
	_fire_held = false
	# Clear non-beam target so the tower stops firing when released.
	var s: Dictionary = TDTower.TYPES[_current_type]["tiers"][0]
	if not s.get("beam", false):
		_clear_fire_targets()


# ── Per-frame ─────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _returning:
		_cam_pitch = lerp(_cam_pitch, ORBIT_PITCH, delta * RETURN_SPEED)
		_cam_r     = lerp(_cam_r,     ORBIT_R,     delta * RETURN_SPEED)
		if abs(_cam_pitch - ORBIT_PITCH) < 0.01 and abs(_cam_r - ORBIT_R) < 0.05:
			_cam_pitch = ORBIT_PITCH
			_cam_r     = ORBIT_R
			_returning = false
			_orbiting  = true
			_refresh_legend()

	if _orbiting and not _dragging:
		_cam_yaw += delta * ORBIT_SPEED

	# Reassign every frame so the tower's retarget tick can't clear it.
	if _fire_held and is_instance_valid(_tower) and is_instance_valid(_fire_target):
		_tower._target = _fire_target

	_apply_camera()


# ── Input ─────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_go_back()
		return

	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_O:
		if _orbiting:
			_orbiting  = false
			_returning = false
			_refresh_legend()
		else:
			_returning = true
			_orbiting  = false
			_refresh_legend()
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_r = clamp(_cam_r - ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
			if _orbiting:
				_orbiting = false
				_returning = false
				_refresh_legend()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_r = clamp(_cam_r + ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
			if _orbiting:
				_orbiting = false
				_returning = false
				_refresh_legend()

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if _dragging:
			_orbiting  = false
			_returning = false
			_refresh_legend()

	if event is InputEventMouseMotion and _dragging:
		_cam_yaw  -= event.relative.x * DRAG_SENS
		_cam_pitch = clamp(_cam_pitch + event.relative.y * DRAG_SENS, 0.05, PI * 0.48)


func _go_back() -> void:
	_clear_fire_targets()
	get_tree().change_scene_to_file("res://scenes/map_picker.tscn")


# ── Style helpers ─────────────────────────────────────────────────────────────

func _refresh_type_buttons() -> void:
	for i in _type_buttons.size():
		var btn = _type_buttons[i]
		var active: bool = (i == _current_type)
		var info: Dictionary = TDTower.TYPES[i]
		var c: Color = info["color"]
		if active:
			btn.add_theme_color_override("font_color", Color.WHITE)
			btn.add_theme_stylebox_override("normal",
				_solid_box(Color(c.r * 0.6, c.g * 0.6, c.b * 0.6)))
		else:
			btn.remove_theme_color_override("font_color")
			btn.remove_theme_stylebox_override("normal")


func _solid_box(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left     = 4
	sb.corner_radius_top_right    = 4
	sb.corner_radius_bottom_left  = 4
	sb.corner_radius_bottom_right = 4
	return sb
