extends Node3D
class_name TDTower

## A stationary auto-shooter. Each frame it picks a target among enemies in range
## (the one furthest along the path — i.e. closest to leaking) and fires on a
## cooldown. Enemies are found via the "td_enemy" group.

@export var range_radius: float = 6.0
@export var damage: float = 10.0
@export var fire_cooldown: float = 0.7
@export var projectile_scene: PackedScene

@onready var turret: Node3D = $Turret
@onready var muzzle: Node3D = $Turret/Muzzle

var _cooldown: float = 0.0

func _physics_process(delta: float) -> void:
	_cooldown = max(_cooldown - delta, 0.0)
	var target := _pick_target()
	if target == null:
		return
	# Aim the turret at the target (cosmetic).
	var look := target.global_position
	look.y = turret.global_position.y
	if look.distance_to(turret.global_position) > 0.05:
		turret.look_at(look, Vector3.UP)
	if _cooldown <= 0.0:
		_fire(target)
		_cooldown = fire_cooldown

func _pick_target() -> Node3D:
	var best: Node3D = null
	var best_progress := -1.0
	for e in get_tree().get_nodes_in_group("td_enemy"):
		if not is_instance_valid(e):
			continue
		var d := global_position.distance_to(e.global_position)
		if d > range_radius:
			continue
		# "Furthest along" ~= furthest waypoint index; fall back to distance.
		var prog := float(e._target_idx) if "_target_idx" in e else 0.0
		if prog > best_progress:
			best_progress = prog
			best = e
	return best

func _fire(target: Node3D) -> void:
	if projectile_scene == null:
		return
	var proj := projectile_scene.instantiate()
	get_tree().current_scene.add_child(proj)
	var origin := muzzle.global_position if muzzle else global_position
	if proj.has_method("launch"):
		proj.launch(origin, target, damage)
	else:
		proj.global_position = origin
