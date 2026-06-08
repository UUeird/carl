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
	_bg = _make_quad(Color(0.7, 0.12, 0.12), 0.0, 0)
	_fill = _make_quad(Color(0.25, 0.8, 0.3), 0.02, 1)   # in front + higher draw priority
	add_child(_bg)
	add_child(_fill)
	_health = get_node_or_null(health_path)
	if _health:
		_health.health_changed.connect(_on_health_changed)
		_health.died.connect(func(): visible = false)
	visible = false

func _make_quad(color: Color, z: float, priority: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(WIDTH, HEIGHT)
	mi.mesh = q
	mi.position.z = z
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED     # visible from either side after billboard flip
	mat.no_depth_test = true                          # don't let the bg/world occlude the fill
	mat.render_priority = priority                    # fill (1) draws after bg (0)
	mi.material_override = mat
	if priority == 0:
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
	_billboard()

# Face the camera. The iso camera is fixed, so its facing basis is the same for
# every bar — cache it statically and refresh only when the camera moves, instead
# of doing a get_camera_3d() lookup + look_at() per bar per frame.
static var _cam: Camera3D = null
static var _cam_basis: Basis = Basis.IDENTITY
static var _cam_xform_cache: Transform3D

func _billboard() -> void:
	if _cam == null or not is_instance_valid(_cam):
		_cam = get_viewport().get_camera_3d()
		if _cam == null:
			return
		_refresh_cam_basis()
	elif _cam.global_transform != _cam_xform_cache:
		_refresh_cam_basis()
	global_basis = _cam_basis

static func _set_cam_static(c: Camera3D) -> void:
	_cam = c

func _refresh_cam_basis() -> void:
	_cam_xform_cache = _cam.global_transform
	# Yaw-only billboard toward the camera (bars stay upright).
	var to := _cam.global_position - global_position
	to.y = 0.0
	if to.length() > 0.01:
		_cam_basis = Basis.looking_at(-to.normalized(), Vector3.UP)

func _set_alpha(a: float) -> void:
	if _fill_mat:
		var c := _fill_mat.albedo_color; c.a = a; _fill_mat.albedo_color = c
	if _bg_mat:
		var c := _bg_mat.albedo_color; c.a = a; _bg_mat.albedo_color = c
