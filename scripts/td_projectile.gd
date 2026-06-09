extends Node3D
class_name TDProjectile

## A tower's shot. Tracks its assigned target so it reliably connects with moving
## creeps, then applies damage. Falls back to flying straight if the target dies
## mid-flight (and expires on a lifetime).
## Uses a static pool — call TDProjectile.acquire() instead of instantiating directly.

@export var speed: float = 14.0

var _target: Node3D
var _damage: float = 0.0
var _damage_type: int = TDTower.DamageType.PHYSICAL
var _dir: Vector3 = Vector3.FORWARD
var _life: float = 2.5
var _slow_factor: float = 1.0
var _slow_dur: float = 0.0
var _active: bool = false

static var _pool: Array = []
const POOL_SIZE := 32

static func prewarm(scene_root: Node, proj_scene: PackedScene) -> void:
	for i in POOL_SIZE:
		var p: TDProjectile = proj_scene.instantiate()
		p._active = false
		p.set_physics_process(false)
		p.visible = false
		scene_root.add_child(p)
		_pool.append(p)

static func acquire(scene_root: Node, proj_scene: PackedScene) -> TDProjectile:
	if _pool.size() > 0:
		return _pool.pop_back()
	# Pool exhausted — allocate a new one rather than dropping the shot.
	var p: TDProjectile = proj_scene.instantiate()
	scene_root.add_child(p)
	return p

func launch(pos: Vector3, target: Node3D, damage: float, speed_override: float = -1.0, damage_type: int = TDTower.DamageType.PHYSICAL) -> void:
	global_position = pos
	_target = target
	_damage = damage
	_damage_type = damage_type
	_slow_factor = 1.0
	_slow_dur = 0.0
	_life = 2.5
	if speed_override > 0.0:
		speed = speed_override
	if is_instance_valid(target):
		_dir = (target.global_position - pos).normalized()
	_active = true
	visible = true
	set_physics_process(true)

func set_slow(factor: float, duration: float) -> void:
	_slow_factor = factor
	_slow_dur = duration

func _physics_process(delta: float) -> void:
	PerfTimer.begin("projectiles")
	if is_instance_valid(_target):
		var to: Vector3 = _target.global_position - global_position
		_dir = to.normalized()
		if to.length() <= 0.6:
			PerfTimer.end("projectiles")
			_hit(_target)
			return
	global_position += _dir * speed * delta
	_life -= delta
	if _life <= 0.0:
		PerfTimer.end("projectiles")
		_return_to_pool()
		return
	PerfTimer.end("projectiles")

func _hit(body: Node) -> void:
	if body and body.has_method("take_damage"):
		body.take_damage(_damage, _damage_type)
	if _slow_dur > 0.0 and body and body.has_method("apply_slow"):
		body.apply_slow(_slow_factor, _slow_dur)
	_return_to_pool()

func _return_to_pool() -> void:
	_active = false
	_target = null
	visible = false
	set_physics_process(false)
	_pool.append(self)
