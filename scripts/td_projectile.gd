extends Area3D
class_name TDProjectile

## A tower's shot. Tracks its assigned target so it reliably connects with moving
## creeps, then applies damage. Falls back to flying straight if the target dies
## mid-flight (and expires on a lifetime).

@export var speed: float = 14.0

var _target: Node3D
var _damage: float = 0.0
var _dir: Vector3 = Vector3.FORWARD
var _life: float = 2.5
var _slow_factor: float = 1.0
var _slow_dur: float = 0.0

func launch(pos: Vector3, target: Node3D, damage: float, speed_override: float = -1.0) -> void:
	global_position = pos
	_target = target
	_damage = damage
	if speed_override > 0.0:
		speed = speed_override
	if is_instance_valid(target):
		_dir = (target.global_position - pos).normalized()

## Frost towers call this so the shot slows its target on hit.
func set_slow(factor: float, duration: float) -> void:
	_slow_factor = factor
	_slow_dur = duration

func _physics_process(delta: float) -> void:
	if is_instance_valid(_target):
		var to: Vector3 = _target.global_position - global_position
		_dir = to.normalized()
		# Hit when close enough to the target center.
		if to.length() <= 0.6:
			_hit(_target)
			return
	global_position += _dir * speed * delta
	_life -= delta
	if _life <= 0.0:
		queue_free()

func _hit(body: Node) -> void:
	if body and body.has_method("take_damage"):
		body.take_damage(_damage)
	if _slow_dur > 0.0 and body and body.has_method("apply_slow"):
		body.apply_slow(_slow_factor, _slow_dur)
	queue_free()
