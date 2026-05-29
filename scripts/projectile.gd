extends Area3D

## Straight-flying projectile for RANGED combat. Launched by combat.gd.
##
## Moves by stepping global_position, but detects hits with a swept sphere cast
## from the previous position to the new one each frame. This avoids two bugs:
##   - tunnelling (fast shots skipping past a thin target between frames), and
##   - vertical misses (a perfectly flat shot sailing over/under a capsule when
##     the shooter and target stand at slightly different heights).

@export var hit_radius: float = 0.6

var _velocity: Vector3 = Vector3.ZERO
var _damage: float = 0.0
var _lifetime: float = 3.0
var _hit_mask: int = 0

func launch(pos: Vector3, dir: Vector3, speed: float, damage: float, hit_mask: int) -> void:
	global_position = pos
	_velocity = dir.normalized() * speed
	_damage = damage
	_hit_mask = hit_mask
	collision_mask = hit_mask

func _physics_process(delta: float) -> void:
	var from := global_position
	var to := from + _velocity * delta
	# Step in sub-segments no larger than the hit radius so a fast shot can't
	# skip past a target between overlap checks.
	var dist := from.distance_to(to)
	var steps := maxi(1, int(ceil(dist / hit_radius)))
	for s in range(1, steps + 1):
		global_position = from.lerp(to, float(s) / steps)
		if _check_overlap():
			return

	_lifetime -= delta
	if _lifetime <= 0.0:
		queue_free()

func _check_overlap() -> bool:
	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = hit_radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis.IDENTITY, global_position)
	params.collision_mask = _hit_mask
	params.collide_with_bodies = true
	params.collide_with_areas = false
	var hits := space.intersect_shape(params, 4)
	for hit in hits:
		var body = hit.get("collider")
		if body:
			_apply(body)
			queue_free()
			return true
	return false

func _apply(body: Node) -> void:
	if body.has_method("take_damage"):
		body.take_damage(_damage)
	else:
		var health := body.get_node_or_null("Health")
		if health and health.has_method("take_damage"):
			health.take_damage(_damage)
