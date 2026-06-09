extends Node3D
class_name HealthBar

## Floating health bar that billboards toward the camera.
## Each active health layer gets its own full-width bar stacked vertically:
##   flesh (green) at the bottom, armor (yellow) above, shield (blue) above that.
## Each bar shows a colored fill over a red background; fill shrinks left as HP drains.
##
## Behavior: hidden until HP changes, visible for SHOW_TIME, then fades over
## FADE_TIME. Any change during the visible/fading window resets the timer.

const SHOW_TIME := 2.0
const FADE_TIME := 0.5
const WIDTH  := 1.2
const HEIGHT := 0.13
const GAP    := 0.03   # vertical gap between stacked bars

# Layer colors (fill)
const COLOR_FLESH  := Color(0.85, 0.15, 0.15)
const COLOR_ARMOR  := Color(0.85, 0.75, 0.15)
const COLOR_SHIELD := Color(0.25, 0.55, 0.95)
const COLOR_BG     := Color(0.2,  0.2,  0.2)

@export var health_path: NodePath = NodePath("../Health")
@export var y_offset: float = 1.3

var _health
var _timer: float = 0.0
var _initialized: bool = false

# Each layer: a bg quad + a fill quad
var _flesh_bg:    MeshInstance3D
var _flesh_fill:  MeshInstance3D
var _armor_bg:    MeshInstance3D
var _armor_fill:  MeshInstance3D
var _shield_bg:   MeshInstance3D
var _shield_fill: MeshInstance3D

# Materials — stored so _set_alpha can reach them all
var _flesh_bg_mat:    StandardMaterial3D
var _flesh_fill_mat:  StandardMaterial3D
var _armor_bg_mat:    StandardMaterial3D
var _armor_fill_mat:  StandardMaterial3D
var _shield_bg_mat:   StandardMaterial3D
var _shield_fill_mat: StandardMaterial3D

# Current fill ratios (0..1)
var _flesh_ratio:  float = 1.0
var _armor_ratio:  float = 1.0
var _shield_ratio: float = 1.0

# Which layers are active
var _has_armor:  bool = false
var _has_shield: bool = false

func _ready() -> void:
	position.y = y_offset
	_ensure_shared_resources()

	# Flesh bar — always present, sits at y=0 (relative to this node)
	_flesh_bg_mat   = _new_mat(COLOR_BG,    0)
	_flesh_fill_mat = _new_mat(COLOR_FLESH, 1)
	_flesh_bg   = _make_bar(_flesh_bg_mat,   0.0)
	_flesh_fill = _make_bar(_flesh_fill_mat, 0.02)
	add_child(_flesh_bg)
	add_child(_flesh_fill)

	# Armor bar — hidden until setup_layers enables it
	_armor_bg_mat   = _new_mat(COLOR_BG,    0)
	_armor_fill_mat = _new_mat(COLOR_ARMOR, 1)
	_armor_bg   = _make_bar(_armor_bg_mat,   0.0)
	_armor_fill = _make_bar(_armor_fill_mat, 0.02)
	add_child(_armor_bg)
	add_child(_armor_fill)
	_armor_bg.visible   = false
	_armor_fill.visible = false

	# Shield bar — hidden until setup_layers enables it
	_shield_bg_mat   = _new_mat(COLOR_BG,     0)
	_shield_fill_mat = _new_mat(COLOR_SHIELD, 1)
	_shield_bg   = _make_bar(_shield_bg_mat,   0.0)
	_shield_fill = _make_bar(_shield_fill_mat, 0.02)
	add_child(_shield_bg)
	add_child(_shield_fill)
	_shield_bg.visible   = false
	_shield_fill.visible = false

	_health = get_node_or_null(health_path)
	if _health:
		_health.health_changed.connect(_on_health_changed)
		_health.died.connect(func(): visible = false)
	visible = false

## Call after configure() on an enemy. flesh/armor/shield are the MAX hp values (0 = absent).
func setup_layers(_flesh: float, armor: float, shield: float) -> void:
	_has_armor  = armor  > 0.0
	_has_shield = shield > 0.0
	_armor_bg.visible    = _has_armor
	_armor_fill.visible  = _has_armor
	_shield_bg.visible   = _has_shield
	_shield_fill.visible = _has_shield
	_flesh_ratio  = 1.0
	_armor_ratio  = 1.0
	_shield_ratio = 1.0
	_restack()
	_apply_fills()

## Update fill ratios. Called by td_enemy after every take_damage / receive_heal.
func update_layers(flesh_cur: float, flesh_max: float,
		armor_cur: float, armor_max: float,
		shield_cur: float, shield_max: float) -> void:
	_flesh_ratio  = flesh_cur  / maxf(flesh_max,  0.001) if flesh_max  > 0.0 else 0.0
	_armor_ratio  = armor_cur  / maxf(armor_max,  0.001) if armor_max  > 0.0 else 0.0
	_shield_ratio = shield_cur / maxf(shield_max, 0.001) if shield_max > 0.0 else 0.0
	# Hide depleted layers entirely; restack so remaining bars stay flush.
	if _has_armor and armor_cur <= 0.0:
		_has_armor = false
		_armor_bg.visible   = false
		_armor_fill.visible = false
		_restack()
	if _has_shield and shield_cur <= 0.0:
		_has_shield = false
		_shield_bg.visible   = false
		_shield_fill.visible = false
		_restack()
	_apply_fills()
	_show()

# Position bars vertically: flesh at bottom, armor above, shield above that.
func _restack() -> void:
	var y: float = 0.0
	_set_bar_y(_flesh_bg, _flesh_fill, y)
	if _has_armor:
		y += HEIGHT + GAP
		_set_bar_y(_armor_bg, _armor_fill, y)
	if _has_shield:
		y += HEIGHT + GAP
		_set_bar_y(_shield_bg, _shield_fill, y)

func _set_bar_y(bg: MeshInstance3D, fill: MeshInstance3D, y: float) -> void:
	bg.position.y   = y
	fill.position.y = y

# Scale each fill quad to reflect its current HP ratio; bg always full width.
func _apply_fills() -> void:
	_apply_fill(_flesh_fill,  _flesh_ratio)
	_apply_fill(_armor_fill,  _armor_ratio)
	_apply_fill(_shield_fill, _shield_ratio)

func _apply_fill(mi: MeshInstance3D, ratio: float) -> void:
	var r := maxf(ratio, 0.0001)
	mi.scale.x = r
	# Anchor the fill to the left edge: center shifts left as it shrinks.
	mi.position.x = (r - 1.0) * WIDTH * 0.5

func _on_health_changed(current: float, maximum: float) -> void:
	# Simple (non-layered) mode: just drive flesh fill from the Health signal.
	if not _has_armor and not _has_shield:
		_flesh_ratio = clampf(current / maxf(maximum, 0.001), 0.0, 1.0)
		_apply_fills()
	if not _initialized:
		_initialized = true
		return
	_show()

func _show() -> void:
	_timer = SHOW_TIME + FADE_TIME
	visible = true
	_set_alpha(1.0)

func _process(delta: float) -> void:
	if not visible:
		return
	PerfTimer.begin("health_bars")
	_timer -= delta
	if _timer <= 0.0:
		visible = false
		PerfTimer.end("health_bars")
		return
	if _timer < FADE_TIME:
		_set_alpha(_timer / FADE_TIME)
	_billboard()
	PerfTimer.end("health_bars")

static var _cam: Camera3D = null
static var _cam_pos: Vector3 = Vector3.ZERO
static var _cam_xform_cache: Transform3D

static var _shared_quad: QuadMesh = null
static var _shared_bg_mat_template: StandardMaterial3D = null
static var _shared_fill_mat_template: StandardMaterial3D = null

static func _ensure_shared_resources() -> void:
	if _shared_quad != null:
		return
	_shared_quad = QuadMesh.new()
	_shared_quad.size = Vector2(WIDTH, HEIGHT)
	_shared_bg_mat_template = StandardMaterial3D.new()
	_shared_bg_mat_template.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shared_bg_mat_template.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shared_bg_mat_template.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shared_bg_mat_template.no_depth_test = true
	_shared_bg_mat_template.render_priority = 0
	_shared_fill_mat_template = _shared_bg_mat_template.duplicate()
	_shared_fill_mat_template.render_priority = 1

func _new_mat(color: Color, priority: int) -> StandardMaterial3D:
	var mat: StandardMaterial3D = (
		_shared_bg_mat_template if priority == 0 else _shared_fill_mat_template
	).duplicate()
	mat.albedo_color = color
	return mat

func _make_bar(mat: StandardMaterial3D, z: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _shared_quad
	mi.position.z = z
	mi.material_override = mat
	return mi

func _billboard() -> void:
	if _cam == null or not is_instance_valid(_cam):
		_cam = get_viewport().get_camera_3d()
		if _cam == null:
			return
		_cam_pos = _cam.global_position
		_cam_xform_cache = _cam.global_transform
	elif _cam.global_transform != _cam_xform_cache:
		_cam_xform_cache = _cam.global_transform
		_cam_pos = _cam.global_position
	var to := _cam_pos - global_position
	if to.length() > 0.01:
		global_basis = Basis.looking_at(-to.normalized(), Vector3.UP)

func _set_alpha(a: float) -> void:
	for mat in [_flesh_fill_mat, _armor_fill_mat, _shield_fill_mat,
				_flesh_bg_mat,   _armor_bg_mat,   _shield_bg_mat]:
		if mat:
			var c: Color = mat.albedo_color; c.a = a; mat.albedo_color = c
