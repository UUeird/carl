extends Camera3D

## Orbit/pan camera controller for the isometric TD view.
##
## Left-drag:  pan the focus point along the ground plane.
## Right-drag: orbit — horizontal drag rotates azimuth, vertical changes elevation.
##
## The camera is always orthographic; zoom (size) is not changed here.
## State is stored as (azimuth, elevation, distance, focus) and the transform
## is rebuilt each frame so the numbers stay clean.

@export var pan_speed: float = 1.0       ## multiplier on the pixel→world conversion (1 = exact screen-space tracking)
@export var orbit_speed: float = 0.4     ## degrees per pixel
@export var zoom_speed: float = 0.025    ## fraction of distance per scroll step
@export var min_distance: float = 10.0
@export var max_distance: float = 150.0
@export var min_elevation: float = 15.0  ## degrees above horizon
@export var max_elevation: float = 80.0  ## degrees above horizon

var _azimuth: float = 0.0
var _elevation: float = 0.0
var _distance: float = 50.0
var _focus: Vector3 = Vector3.ZERO

var _panning: bool = false
var _pan_moved: bool = false   ## true once the left-drag has actually moved
var _orbiting: bool = false
var _orbit_pivot: Vector3 = Vector3.ZERO  ## world point under cursor at right-click
var _last_mouse: Vector2 = Vector2.ZERO

func _ready() -> void:
	# Derive all orbit state from the actual scene transform so the first drag
	# doesn't snap the camera to a different position.
	var fwd := -global_transform.basis.z          # camera looks along -Z
	# Find where the look direction hits Y=0.
	if abs(fwd.y) > 0.001:
		var t := -global_position.y / fwd.y
		_focus = global_position + fwd * t
	else:
		_focus = global_position + fwd * _distance
	var offset := global_position - _focus
	_distance = offset.length()
	var flat := Vector2(offset.x, offset.z)
	_azimuth = rad_to_deg(atan2(flat.x, flat.y))
	_elevation = rad_to_deg(asin(offset.y / maxf(_distance, 0.001)))

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_panning = true
				_pan_moved = false
				_last_mouse = event.position
			else:
				_panning = false
				# If the mouse moved during this press it was a drag — consume the
				# release so the game doesn't treat it as a deselect click.
				if _pan_moved:
					get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = event.pressed
			_last_mouse = event.position
			if event.pressed:
				# Find the world point under the cursor (Y=0 plane) to orbit around.
				var fwd := -global_transform.basis.z
				if abs(fwd.y) > 0.001:
					var t := -global_position.y / fwd.y
					_orbit_pivot = global_position + fwd * t
				else:
					_orbit_pivot = _focus
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = clampf(_distance * (1.0 - zoom_speed), min_distance, max_distance)
			_apply_transform()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = clampf(_distance * (1.0 + zoom_speed), min_distance, max_distance)
			_apply_transform()
			get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion:
		if _panning:
			_pan_moved = true
			_do_pan(event.relative)
			get_viewport().set_input_as_handled()
		elif _orbiting:
			_do_orbit(event.relative)
			get_viewport().set_input_as_handled()

func _do_pan(delta: Vector2) -> void:
	# Move focus in camera-local XZ (right and up-screen directions projected to Y=0).
	var right := global_transform.basis.x
	var up_screen := global_transform.basis.y
	# Project both onto the Y=0 plane and normalize.
	right.y = 0.0
	up_screen.y = 0.0
	if right.length_squared() > 0.001:
		right = right.normalized()
	if up_screen.length_squared() > 0.001:
		up_screen = up_screen.normalized()
	# Convert pixel delta to world units using the perspective FOV and distance to
	# focus, so panning feels like dragging the ground regardless of camera angle.
	var viewport_h := float(get_viewport().get_visible_rect().size.y)
	var world_per_px := (2.0 * _distance * tan(deg_to_rad(fov * 0.5))) / maxf(viewport_h, 1.0) * pan_speed
	_focus -= right * delta.x * world_per_px
	_focus += up_screen * delta.y * world_per_px
	_apply_transform()

func _do_orbit(delta: Vector2) -> void:
	_azimuth -= delta.x * orbit_speed
	_elevation = clampf(_elevation + delta.y * orbit_speed, min_elevation, max_elevation)
	# Orbit around the click pivot: camera sits at pivot + offset, looks at pivot.
	# Update _distance to match the pivot distance so zoom stays consistent.
	_distance = (_orbit_pivot - global_position).length()
	_focus = _orbit_pivot
	_apply_transform()

func _camera_offset() -> Vector3:
	var az := deg_to_rad(_azimuth)
	var el := deg_to_rad(_elevation)
	return Vector3(
		cos(el) * sin(az),
		sin(el),
		cos(el) * cos(az)
	) * _distance

func _apply_transform() -> void:
	var offset := _camera_offset()
	global_position = _focus + offset
	look_at(_focus, Vector3.UP)
