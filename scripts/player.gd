extends CharacterBody3D

## Player controller supporting two view modes (toggle with V):
##   - ISO  : screen-aligned WASD, mouse-cursor aim, follow camera (the default).
##   - FP   : first-person mouse-look, camera-relative WASD, camera-forward aim.
## Combat/jump/health are camera-agnostic and shared by both modes.

signal checkpoint_reached(point: Vector3)

@export var move_speed: float = 6.0
@export var acceleration: float = 60.0
@export var air_acceleration: float = 30.0
@export var jump_velocity: float = 10.5
@export var gravity: float = 24.0
## Coyote time: jump still works briefly after walking off a ledge.
@export var coyote_time: float = 0.12
## Y below which the player is considered to have fallen into a pit.
@export var fall_kill_y: float = -8.0
## Damage taken on falling into a pit (0 = free respawn).
@export var fall_damage: float = 20.0
@export var mouse_sensitivity: float = 0.0025
## HUD that owns the FP crosshair (set in main.tscn).
@export var hud_path: NodePath

@onready var combat: Combat = $Combat
@onready var health: Health = $Health
@onready var swing_fx: MeshInstance3D = $SwingFx
@onready var ground_ray: RayCast3D = $GroundRay
@onready var landing_marker: MeshInstance3D = $LandingMarker
@onready var fp_camera: Camera3D = $FPCamera
@onready var mesh: MeshInstance3D = $Mesh
@onready var snout: MeshInstance3D = $Snout

var _aim_point: Vector3
var _spawn_point: Vector3
var _coyote_left: float = 0.0
var _fp_mode: bool = false
var _fp_pitch: float = 0.0
var _iso_camera: Camera3D

func _ready() -> void:
	health.died.connect(_on_died)
	_spawn_point = global_position
	checkpoint_reached.connect(func(p): _spawn_point = p)
	# The iso follow-camera is whatever is current at startup.
	_iso_camera = get_viewport().get_camera_3d()

func _physics_process(delta: float) -> void:
	if _fp_mode:
		_update_aim_fp()
	else:
		_update_aim_iso()
		_face_aim_iso()
	_move(delta)
	_update_landing_marker()
	_check_fall()
	# Poll here rather than _unhandled_input so HUD/UI can't swallow the click.
	if Input.is_action_just_pressed("attack") and combat.can_attack():
		_attack()

func _input(event: InputEvent) -> void:
	# Handled in _input (not _unhandled_input) so the full-screen HUD Control
	# can't swallow mouse-motion before it reaches us.
	if event.is_action_pressed("toggle_view"):
		_set_fp_mode(not _fp_mode)
	if not _fp_mode:
		return
	# Free the mouse from FP capture with Esc.
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Re-capture on click when in FP.
	if event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# FP mouse-look: yaw the body, pitch the camera.
	if event is InputEventMouseMotion \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		_fp_pitch = clampf(_fp_pitch - event.relative.y * mouse_sensitivity, -1.4, 1.4)
		fp_camera.rotation.x = _fp_pitch

func _set_fp_mode(on: bool) -> void:
	_fp_mode = on
	fp_camera.current = on
	if not on and _iso_camera:
		_iso_camera.current = true
	# Hide the player body + aim helpers in first person.
	mesh.visible = not on
	snout.visible = not on
	landing_marker.visible = landing_marker.visible and not on
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE
	var hud := get_node_or_null(hud_path)
	if hud and hud.has_method("set_crosshair_visible"):
		hud.set_crosshair_visible(on)
	if on:
		# Reset pitch so the camera starts level.
		_fp_pitch = 0.0
		fp_camera.rotation.x = 0.0

func _move(delta: float) -> void:
	var input := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	var dir := Vector3.ZERO
	if input.length() > 0.01:
		input = input.normalized()
		var cam_right: Vector3
		var cam_fwd: Vector3
		if _fp_mode:
			# In FP, move relative to the body's own facing (which mouse-look turns).
			cam_right = global_transform.basis.x
			cam_fwd = -global_transform.basis.z
		else:
			# In ISO, move relative to the follow camera's screen orientation.
			var cam := get_viewport().get_camera_3d()
			var b := global_transform.basis if cam == null else cam.global_transform.basis
			cam_right = b.x
			cam_fwd = -b.z
		cam_right.y = 0.0
		cam_fwd.y = 0.0
		cam_right = cam_right.normalized()
		cam_fwd = cam_fwd.normalized()
		dir = (cam_right * input.x - cam_fwd * input.y).normalized()

	var grounded := is_on_floor()
	if grounded:
		_coyote_left = coyote_time
	else:
		_coyote_left = max(_coyote_left - delta, 0.0)

	var accel := acceleration if grounded else air_acceleration
	var target_vel := dir * move_speed
	velocity.x = move_toward(velocity.x, target_vel.x, accel * delta)
	velocity.z = move_toward(velocity.z, target_vel.z, accel * delta)

	if not grounded:
		velocity.y -= gravity * delta
	if Input.is_action_just_pressed("jump") and (grounded or _coyote_left > 0.0):
		velocity.y = jump_velocity
		_coyote_left = 0.0

	move_and_slide()

func _check_fall() -> void:
	if global_position.y < fall_kill_y:
		_respawn()

func _respawn() -> void:
	velocity = Vector3.ZERO
	global_position = _spawn_point
	if fall_damage > 0.0:
		health.take_damage(fall_damage)

func _update_aim_iso() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var mouse := get_viewport().get_mouse_position()
	var ray_origin := cam.project_ray_origin(mouse)
	var ray_dir := cam.project_ray_normal(mouse)
	if absf(ray_dir.y) < 0.0001:
		return
	var plane_y := global_position.y
	var t := (plane_y - ray_origin.y) / ray_dir.y
	if t > 0.0:
		_aim_point = ray_origin + ray_dir * t

func _face_aim_iso() -> void:
	var to_aim := _aim_point - global_position
	to_aim.y = 0.0
	if to_aim.length() > 0.05:
		look_at(global_position + to_aim.normalized(), Vector3.UP)

func _update_aim_fp() -> void:
	# Aim straight out from the camera; the body already yaws with the look.
	_aim_point = fp_camera.global_position - fp_camera.global_transform.basis.z * 50.0

func _attack() -> void:
	var facing: Vector3
	if _fp_mode:
		facing = -fp_camera.global_transform.basis.z
	else:
		facing = -global_transform.basis.z  # forward (toward aim)
	facing.y = 0.0
	combat.try_attack(global_position, facing.normalized())
	if combat.combat_mode != Combat.Mode.RANGED:
		_show_swing()

func _update_landing_marker() -> void:
	if _fp_mode:
		landing_marker.visible = false
		return
	# Project straight down to show where the player will land. Brighter/larger
	# when airborne — solves the iso depth ambiguity over gaps.
	ground_ray.force_raycast_update()
	if ground_ray.is_colliding():
		var p := ground_ray.get_collision_point()
		landing_marker.visible = true
		landing_marker.global_position = p + Vector3.UP * 0.03
		var airborne := not is_on_floor()
		landing_marker.scale = Vector3.ONE * (1.3 if airborne else 0.85)
	else:
		landing_marker.visible = false

func _show_swing() -> void:
	swing_fx.visible = true
	swing_fx.scale = Vector3(0.2, 1.0, 0.2)
	var tw := create_tween()
	tw.tween_property(swing_fx, "scale", Vector3(1.2, 1.0, 1.2), 0.14) \
		.set_trans(Tween.TRANS_BACK)
	tw.tween_callback(func(): swing_fx.visible = false)

func _on_died() -> void:
	# Restart is handled by main.gd (press R).
	set_physics_process(false)
