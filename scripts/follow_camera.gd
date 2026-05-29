extends Camera3D

## Isometric follow camera with look-ahead. Keeps a fixed iso angle (set in the
## scene), smoothly tracks the target's position, and biases toward where the
## player is moving/aiming so you see more of what's ahead.

@export var target_path: NodePath
## Fixed offset from the target that defines the iso framing. Captured from the
## camera's starting position relative to the target if left at zero.
@export var offset: Vector3 = Vector3.ZERO
@export var follow_smoothing: float = 6.0
@export var look_ahead_distance: float = 4.0
@export var look_ahead_smoothing: float = 3.0

var _target: Node3D
var _look_ahead: Vector3 = Vector3.ZERO

func _ready() -> void:
	_target = get_node_or_null(target_path)
	if _target and offset == Vector3.ZERO:
		offset = global_position - _target.global_position
	if _target:
		global_position = _target.global_position + offset

func _physics_process(delta: float) -> void:
	if _target == null:
		return
	# Look-ahead based on the target's horizontal velocity (falls back to facing).
	var lead := Vector3.ZERO
	if _target is CharacterBody3D:
		var vel: Vector3 = _target.velocity
		vel.y = 0.0
		if vel.length() > 0.5:
			lead = vel.normalized() * look_ahead_distance
	_look_ahead = _look_ahead.lerp(lead, clampf(look_ahead_smoothing * delta, 0.0, 1.0))

	var desired := _target.global_position + offset + _look_ahead
	global_position = global_position.lerp(desired, clampf(follow_smoothing * delta, 0.0, 1.0))
