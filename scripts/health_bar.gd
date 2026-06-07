extends Node3D
class_name HealthBar

## A floating green-over-red health bar for any entity with a Health child.
## Behavior: hidden until HP changes (damage OR heal), then visible for 2s, then
## fades over 0.5s. Any change during the visible-or-fading window resets the 2s
## timer and restores full opacity. The green fill shrinks left→right as HP drops
## (revealing red) and grows back on heal. Billboards toward the active camera.

const SHOW_TIME := 2.0
const FADE_TIME := 0.5
const WIDTH := 1.2
const HEIGHT := 0.16

@export var health_path: NodePath = NodePath("../Health")
@export var y_offset: float = 1.3

var _health
var _fill: MeshInstance3D
var _bg: MeshInstance3D
var _fill_mat: StandardMaterial3D
var _bg_mat: StandardMaterial3D
var _timer: float = 0.0          ## counts down; >FADE_TIME = solid, <=FADE_TIME = fading
var _ratio: float = 1.0
var _initialized: bool = false   ## skip Health's initial full-HP emit on _ready

func _ready() -> void:
	position.y = y_offset
	_bg = _make_quad(Color(0.7, 0.12, 0.12), 0.0)
	_fill = _make_quad(Color(0.25, 0.8, 0.3), 0.01)   # nudged forward to avoid z-fight
	add_child(_bg)
	add_child(_fill)
	_health = get_node_or_null(health_path)
	if _health:
		_health.health_changed.connect(_on_health_changed)
	visible = false

func _make_quad(color: Color, z: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(WIDTH, HEIGHT)
	mi.mesh = q
	mi.position.z = z
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED   # we billboard the whole node
	mi.material_override = mat
	if color.r > color.g:
		_bg_mat = mat
	else:
		_fill_mat = mat
	return mi

func _on_health_changed(current: float, maximum: float) -> void:
	_ratio = clampf(current / maxf(maximum, 0.001), 0.0, 1.0)
	_apply_ratio()
	# The first emit is Health's initial full-HP broadcast on _ready — don't pop
	# the bar for it; only actual damage/heal should show the bar.
	if not _initialized:
		_initialized = true
		return
	# Reset the show window (fresh 2s, full opacity) on any change.
	_timer = SHOW_TIME + FADE_TIME
	visible = true
	_set_alpha(1.0)

func _apply_ratio() -> void:
	# Shrink the green fill from the left: scale X and shift left so its left edge
	# stays put while the right edge recedes, revealing the red background.
	_fill.scale.x = max(_ratio, 0.0001)
	_fill.position.x = -WIDTH * 0.5 * (1.0 - _ratio)

func _process(delta: float) -> void:
	if not visible:
		return
	_timer -= delta
	if _timer <= 0.0:
		visible = false
		return
	if _timer < FADE_TIME:
		_set_alpha(_timer / FADE_TIME)
	# Billboard: face the active camera each frame.
	var cam := get_viewport().get_camera_3d()
	if cam:
		var look := cam.global_position
		look.y = global_position.y   # keep the bar upright, only yaw toward camera
		if look.distance_to(global_position) > 0.01:
			look_at(look, Vector3.UP)
			rotate_object_local(Vector3.UP, PI)   # quads face +Z; flip to face the camera

func _set_alpha(a: float) -> void:
	if _fill_mat:
		var c := _fill_mat.albedo_color; c.a = a; _fill_mat.albedo_color = c
	if _bg_mat:
		var c := _bg_mat.albedo_color; c.a = a; _bg_mat.albedo_color = c
