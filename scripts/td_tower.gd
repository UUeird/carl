extends Node3D
class_name TDTower

## A stationary auto-shooter. Each frame it targets the enemy furthest along the
## path within range and fires on a cooldown. Two types (basic damage, frost
## slow), each with three upgrade tiers. Stats come from TYPES below so balancing
## and adding tiers is a one-place edit.

enum Type { BASIC, FROST }

# Per-type, per-level stats. Index 0 = level 1.
const TYPES := {
	Type.BASIC: {
		"name": "Cannon",
		"color": Color(0.5, 0.55, 0.65),
		"base_cost": 50,
		"upgrade_costs": [40, 70],            # cost L1->L2, L2->L3
		"tiers": [
			{ "range": 6.0, "damage": 10.0, "cooldown": 0.7 },
			{ "range": 6.8, "damage": 16.0, "cooldown": 0.6 },
			{ "range": 7.6, "damage": 24.0, "cooldown": 0.5 },
		],
	},
	Type.FROST: {
		"name": "Frost",
		"color": Color(0.45, 0.7, 0.95),
		"base_cost": 65,
		"upgrade_costs": [50, 80],
		"tiers": [
			{ "range": 5.5, "damage": 4.0, "cooldown": 0.9, "slow": 0.6, "slow_dur": 1.2 },
			{ "range": 6.0, "damage": 6.0, "cooldown": 0.8, "slow": 0.5, "slow_dur": 1.5 },
			{ "range": 6.5, "damage": 9.0, "cooldown": 0.7, "slow": 0.4, "slow_dur": 1.8 },
		],
	},
}
const MAX_LEVEL := 3

@export var projectile_scene: PackedScene

@onready var turret: Node3D = $Turret
@onready var muzzle: Node3D = $Turret/Muzzle
@onready var _head: MeshInstance3D = $Turret/Head
@onready var _range_sphere: MeshInstance3D = $RangeSphere

var tower_type: int = Type.BASIC
var level: int = 1
var total_spent: int = 0
var _cooldown: float = 0.0
var _head_material: StandardMaterial3D

func _ready() -> void:
	_head_material = StandardMaterial3D.new()
	_head_material.metallic = 0.4
	if _head:
		_head.material_override = _head_material
	_apply_visual()

## Called by the game controller right after instantiation.
func configure(type: int) -> void:
	tower_type = type
	level = 1
	total_spent = TYPES[type]["base_cost"]
	_apply_visual()

func _stats() -> Dictionary:
	return TYPES[tower_type]["tiers"][level - 1]

func type_name() -> String: return TYPES[tower_type]["name"]
func is_max_level() -> bool: return level >= MAX_LEVEL
func upgrade_cost() -> int:
	if is_max_level(): return 0
	return TYPES[tower_type]["upgrade_costs"][level - 1]
func sell_value() -> int: return int(total_spent * 0.5)

## Returns true if upgraded (caller already checked/charged affordability).
func upgrade() -> bool:
	if is_max_level(): return false
	total_spent += upgrade_cost()
	level += 1
	_apply_visual()
	return true

func _apply_visual() -> void:
	if _head_material == null: return
	var base: Color = TYPES[tower_type]["color"]
	# Brighten slightly per level so upgrades read at a glance.
	_head_material.albedo_color = base.lightened((level - 1) * 0.18)
	if _head:
		_head.scale = Vector3.ONE * (1.0 + (level - 1) * 0.12)
	if _range_sphere and _range_sphere.visible:
		_update_range_sphere()

## Show the spherical range. Call with no args for this tower's current range, or
## pass a type to preview that type's level-1 range (used while placing).
func show_range(preview_type: int = -1) -> void:
	if _range_sphere == null:
		return
	var r: float
	var col: Color
	if preview_type >= 0:
		r = TYPES[preview_type]["tiers"][0]["range"]
		col = TYPES[preview_type]["color"]
	else:
		r = _stats()["range"]
		col = TYPES[tower_type]["color"]
	_range_sphere.visible = true
	_range_sphere.scale = Vector3.ONE * r        # base SphereMesh has radius 1
	var mat := _range_sphere.material_override
	if mat == null or not (mat is StandardMaterial3D):
		mat = StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED   # see the dome from inside too
		_range_sphere.material_override = mat
	mat.albedo_color = Color(col.r, col.g, col.b, 0.16)

func _update_range_sphere() -> void:
	_range_sphere.scale = Vector3.ONE * _stats()["range"]

func hide_range() -> void:
	if _range_sphere:
		_range_sphere.visible = false

func _physics_process(delta: float) -> void:
	_cooldown = max(_cooldown - delta, 0.0)
	var target := _pick_target()
	if target == null:
		return
	var look := target.global_position
	look.y = turret.global_position.y
	if look.distance_to(turret.global_position) > 0.05:
		turret.look_at(look, Vector3.UP)
	if _cooldown <= 0.0:
		_fire(target)
		_cooldown = _stats()["cooldown"]

## Layer mask of geometry that blocks line of sight (environment/obstacles).
const BLOCKER_MASK := 4

func _pick_target() -> Node3D:
	var best: Node3D = null
	var best_progress := -1.0
	var r: float = _stats()["range"]
	var origin := muzzle.global_position if muzzle else global_position
	for e in get_tree().get_nodes_in_group("td_enemy"):
		if not is_instance_valid(e):
			continue
		# Spherical range: true 3D distance (matters once maps have height).
		if global_position.distance_to(e.global_position) > r:
			continue
		# Line of sight: skip enemies blocked by terrain/obstacles.
		if not _has_los(origin, e):
			continue
		var prog := float(e._target_idx) if "_target_idx" in e else 0.0
		if prog > best_progress:
			best_progress = prog
			best = e
	return best

func _has_los(origin: Vector3, enemy: Node3D) -> bool:
	var space := get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(origin, enemy.global_position, BLOCKER_MASK)
	params.hit_from_inside = false
	var hit := space.intersect_ray(params)
	# Clear LOS if nothing blocked the ray before reaching the enemy.
	return hit.is_empty()

func _fire(target: Node3D) -> void:
	if projectile_scene == null:
		return
	var s := _stats()
	var proj := projectile_scene.instantiate()
	get_tree().current_scene.add_child(proj)
	var origin := muzzle.global_position if muzzle else global_position
	if proj.has_method("launch"):
		proj.launch(origin, target, s["damage"])
		# Frost towers tell the projectile to also slow on hit.
		if tower_type == Type.FROST and proj.has_method("set_slow"):
			proj.set_slow(s["slow"], s["slow_dur"])
			if "color" in proj:
				pass
		_tint_projectile(proj)
	else:
		proj.global_position = origin

func _tint_projectile(proj: Node) -> void:
	var m := proj.get_node_or_null("Mesh")
	if m and m is MeshInstance3D:
		var mat := StandardMaterial3D.new()
		var c: Color = TYPES[tower_type]["color"]
		mat.albedo_color = c
		mat.emission_enabled = true
		mat.emission = c
		mat.emission_energy_multiplier = 0.8
		m.material_override = mat
