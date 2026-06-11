extends Node3D
class_name TDProjectile

## A tower's shot. Two launch modes:
##   launch()          — homing: tracks the target node each frame, always connects
##                       unless the target dies mid-flight.
##   launch_straight() — lead-locked: direction is fixed at fire time; the bullet
##                       flies straight and misses if the target turns, slows, or
##                       reverses after the shot leaves. Use for skill-expression
##                       towers (Machine Gun) where player-aimed prediction matters.
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

## Lead-locked launch: direction fixed at fire time, no homing. The bullet travels
## toward aim_point and hits whatever body it reaches within contact distance.
## Misses if the target has moved away from aim_point by the time the shot arrives.
func launch_straight(pos: Vector3, aim_point: Vector3, damage: float, speed_override: float = -1.0, damage_type: int = TDTower.DamageType.PHYSICAL) -> void:
	global_position = pos
	_target = null   # no tracking — straight flight only
	_damage = damage
	_damage_type = damage_type
	_slow_factor = 1.0
	_slow_dur = 0.0
	_life = 2.5
	if speed_override > 0.0:
		speed = speed_override
	_dir = (aim_point - pos).normalized()
	_active = true
	visible = true
	set_physics_process(true)

func set_shock_slow(factor: float, duration: float) -> void:
	_slow_factor = factor
	_slow_dur = duration

const HIT_RADIUS := 0.6   # contact distance for both homing and straight shots

func _physics_process(delta: float) -> void:
	PerfTimer.begin("projectiles")
	if is_instance_valid(_target):
		# Homing mode: steer toward the live target each frame.
		var to: Vector3 = _target.global_position - global_position
		_dir = to.normalized()
		if to.length() <= HIT_RADIUS:
			PerfTimer.end("projectiles")
			_hit(_target)
			return
	elif _active:
		# Straight mode: check all enemies for proximity hit.
		for e in TDEnemy.all_enemies:
			if not is_instance_valid(e):
				continue
			if global_position.distance_to(e.global_position) <= HIT_RADIUS:
				PerfTimer.end("projectiles")
				_hit(e)
				return
	global_position += _dir * speed * delta
	# Orient the capsule along the direction of travel so it reads as a bullet.
	if _dir.length_squared() > 0.01:
		look_at(global_position + _dir, Vector3.UP if absf(_dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT)
	_life -= delta
	if _life <= 0.0:
		PerfTimer.end("projectiles")
		_return_to_pool()
		return
	PerfTimer.end("projectiles")

func _hit(body: Node) -> void:
	if body and body.has_method("take_damage"):
		body.take_damage(_damage, _damage_type)
	# Shock slow: only land if the enemy has no active shield (shield absorbs it).
	# take_damage runs first so a shield-depleting hit can expose the enemy in one frame.
	if _slow_dur > 0.0 and body and body.has_method("apply_slow"):
		var shielded: bool = body.get("shield_hp") != null and (body.shield_hp as float) > 0.0
		if not shielded:
			body.apply_slow(_slow_factor, _slow_dur)
	_return_to_pool()

func _return_to_pool() -> void:
	_active = false
	_target = null
	visible = false
	set_physics_process(false)
	_pool.append(self)
