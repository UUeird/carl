extends Node
class_name Combat

## The swappable heart of the prototype. ALL combat feel lives here so we can
## decide melee vs ranged vs mixed by flipping one export and tuning numbers in
## the inspector — no code edits needed to compare feels.

enum Mode { MELEE, RANGED, MIXED }

@export var combat_mode: Mode = Mode.MELEE

@export_group("Melee")
@export var melee_damage: float = 25.0
@export var melee_range: float = 2.2          ## how far forward the hit reaches
@export var melee_arc_degrees: float = 100.0  ## width of the swing, centered on facing
@export var melee_cooldown: float = 0.45

@export_group("Ranged")
@export var ranged_damage: float = 15.0
@export var ranged_cooldown: float = 0.30
@export var projectile_speed: float = 18.0
@export var projectile_scene: PackedScene

## Layer mask of things attacks can hit (dummy, boss). Set in inspector.
@export_flags_3d_physics var hittable_layers: int = 0

var _cooldown_left: float = 0.0

func _process(delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left -= delta

func can_attack() -> bool:
	return _cooldown_left <= 0.0

## origin: world position the attacker stands at.
## facing: normalized horizontal direction the attacker faces (used by melee).
## muzzle: world position projectiles spawn from (the gun's muzzle). Defaults to
##   origin if not given.
## aim_dir: full 3D direction projectiles travel (e.g. camera forward in FP).
##   Defaults to facing (flat) if not given — correct for the iso view.
func try_attack(origin: Vector3, facing: Vector3, muzzle: Vector3 = Vector3.INF, aim_dir: Vector3 = Vector3.INF) -> void:
	if not can_attack():
		return
	var shot_origin := origin if muzzle == Vector3.INF else muzzle
	var shot_dir := facing if aim_dir == Vector3.INF else aim_dir
	match combat_mode:
		Mode.MELEE:
			_do_melee(origin, facing)
			_cooldown_left = melee_cooldown
		Mode.RANGED:
			_do_ranged(shot_origin, shot_dir)
			_cooldown_left = ranged_cooldown
		Mode.MIXED:
			# Mixed = melee swing + a projectile on the same press. Cheap way to
			# feel both at once; we split to separate inputs later if it's promising.
			_do_melee(origin, facing)
			_do_ranged(shot_origin, shot_dir)
			_cooldown_left = max(melee_cooldown, ranged_cooldown)

func _do_melee(origin: Vector3, facing: Vector3) -> void:
	# Sphere query in front of the attacker, then keep only targets within the arc.
	var space := get_viewport().get_world_3d().direct_space_state if get_viewport() else null
	if space == null:
		return
	var center := origin + facing * (melee_range * 0.5)
	var shape := SphereShape3D.new()
	shape.radius = melee_range * 0.6
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis.IDENTITY, center)
	params.collision_mask = hittable_layers
	params.collide_with_areas = false
	params.collide_with_bodies = true
	var half_arc := deg_to_rad(melee_arc_degrees) * 0.5
	for hit in space.intersect_shape(params, 16):
		var collider = hit.get("collider")
		if collider == null:
			continue
		var to_target: Vector3 = collider.global_position - origin
		to_target.y = 0.0
		if to_target.length() < 0.001:
			_apply_damage(collider, melee_damage)
			continue
		if facing.angle_to(to_target.normalized()) <= half_arc:
			_apply_damage(collider, melee_damage)

func _do_ranged(muzzle: Vector3, dir: Vector3) -> void:
	if projectile_scene == null:
		push_warning("Combat: RANGED mode but no projectile_scene assigned.")
		return
	var proj := projectile_scene.instantiate()
	# Spawn into the current scene so it outlives any attack animation.
	get_tree().current_scene.add_child(proj)
	# Spawn right at the muzzle and fly along the full 3D aim (FP: includes pitch).
	if proj.has_method("launch"):
		proj.launch(muzzle, dir.normalized(), projectile_speed, ranged_damage, hittable_layers)
	else:
		proj.global_position = muzzle

func _apply_damage(target: Node, amount: float) -> void:
	# Convention: damageable entities expose take_damage() OR have a Health child.
	if target.has_method("take_damage"):
		target.take_damage(amount)
		return
	var health := target.get_node_or_null("Health")
	if health and health.has_method("take_damage"):
		health.take_damage(amount)
