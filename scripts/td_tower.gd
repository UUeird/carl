extends Node3D
class_name TDTower

## A stationary auto-tower. Each frame it targets the enemy furthest along the
## path within range (and line of sight). Cannon/Frost fire discrete projectiles
## on a cooldown; the Beam tower instead applies continuous DPS to a locked
## target and draws a solid beam. Stats come from TYPES so balancing and adding
## tiers/types is a one-place edit.

enum Type { BASIC, FROST, BEAM, BOMB }

# Per-type, per-level stats. Index 0 = level 1.
#  - Beam towers use "dps" + "beam": true instead of "damage"/"cooldown".
#  - Bomb towers use "aoe" (blast radius) + "bomb": true; they lob to a predicted
#    ground point, so upgrading "proj_speed" both speeds the lob AND tightens the
#    lead prediction (shorter flight time = less chance the target has turned).
#  - "proj_speed" applies to all projectile towers (cannon/frost shot speed too).
const TYPES := {
	Type.BASIC: {
		"name": "Cannon",
		"color": Color(0.5, 0.55, 0.65),
		"base_cost": 50,
		"upgrade_costs": [40, 70],            # cost L1->L2, L2->L3
		"tiers": [
			{ "range": 6.0, "damage": 10.0, "cooldown": 0.7, "proj_speed": 14.0 },
			{ "range": 6.8, "damage": 16.0, "cooldown": 0.6, "proj_speed": 18.0 },
			{ "range": 7.6, "damage": 24.0, "cooldown": 0.5, "proj_speed": 22.0 },
		],
	},
	Type.FROST: {
		"name": "Frost",
		"color": Color(0.45, 0.7, 0.95),
		"base_cost": 65,
		"upgrade_costs": [50, 80],
		"tiers": [
			{ "range": 5.5, "damage": 4.0, "cooldown": 0.9, "proj_speed": 13.0, "slow": 0.6, "slow_dur": 1.2 },
			{ "range": 6.0, "damage": 6.0, "cooldown": 0.8, "proj_speed": 16.0, "slow": 0.5, "slow_dur": 1.5 },
			{ "range": 6.5, "damage": 9.0, "cooldown": 0.7, "proj_speed": 20.0, "slow": 0.4, "slow_dur": 1.8 },
		],
	},
	Type.BEAM: {
		"name": "Beam",
		"color": Color(0.95, 0.4, 0.85),
		"base_cost": 70,
		"upgrade_costs": [55, 85],
		"tiers": [
			{ "range": 6.5, "dps": 9.0, "beam": true },
			{ "range": 7.2, "dps": 15.0, "beam": true },
			{ "range": 8.0, "dps": 24.0, "beam": true },
		],
	},
	Type.BOMB: {
		"name": "Bomb",
		"color": Color(0.95, 0.6, 0.25),
		"base_cost": 80,
		"upgrade_costs": [65, 100],
		"tiers": [
			{ "range": 7.0, "damage": 18.0, "cooldown": 1.6, "proj_speed": 10.0, "aoe": 2.2, "bomb": true },
			{ "range": 7.8, "damage": 28.0, "cooldown": 1.4, "proj_speed": 13.0, "aoe": 2.6, "bomb": true },
			{ "range": 8.6, "damage": 42.0, "cooldown": 1.2, "proj_speed": 17.0, "aoe": 3.2, "bomb": true },
		],
	},
}
const MAX_LEVEL := 3

@export var projectile_scene: PackedScene
@export var bomb_scene: PackedScene

@onready var turret: Node3D = $Turret
@onready var muzzle: Node3D = $Turret/Muzzle
@onready var _head: MeshInstance3D = $Turret/Head
@onready var _range_sphere: MeshInstance3D = $RangeSphere
@onready var _beam: MeshInstance3D = $Beam

var tower_type: int = Type.BASIC
var level: int = 1
var total_spent: int = 0
var _cooldown: float = 0.0
var _target: Node3D = null          ## cached current target
var _retarget_timer: float = 0.0    ## time until the next full re-pick
const RETARGET_INTERVAL := 0.15     ## seconds between full target searches
var _head_material: StandardMaterial3D
var _beam_material: StandardMaterial3D

func _ready() -> void:
	_head_material = StandardMaterial3D.new()
	_head_material.metallic = 0.4
	if _head:
		_head.material_override = _head_material
	if _beam:
		_beam.top_level = true     # position in world space, not relative to the tower
		_beam.visible = false
		_beam_material = StandardMaterial3D.new()
		_beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_beam_material.emission_enabled = true
		_beam_material.emission_energy_multiplier = 1.4
		_beam.material_override = _beam_material
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

## Draw the beam from the muzzle to the target (or hide it when target is null).
## The beam mesh is a unit-tall cylinder along +Y; we orient and stretch it to
## span muzzle→target.
func _set_beam(target: Node3D) -> void:
	if _beam == null:
		return
	if target == null or not is_instance_valid(target):
		_beam.visible = false
		return
	var a := muzzle.global_position if muzzle else global_position
	var b: Vector3 = target.global_position
	var dir := b - a
	var dist := dir.length()
	if dist < 0.01:
		_beam.visible = false
		return
	_beam.visible = true
	var up := dir.normalized()
	# Build an orthonormal basis whose Y axis points along the beam.
	var arbitrary := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := arbitrary.cross(up).normalized()
	var z := x.cross(up).normalized()
	var basis := Basis(x, up, z)
	_beam.global_transform = Transform3D(basis, (a + b) * 0.5)
	# Cylinder base height is 1.0; scale Y to the span, keep it thin.
	_beam.scale = Vector3(1.0, dist, 1.0)
	if _beam_material:
		var c: Color = TYPES[tower_type]["color"]
		_beam_material.albedo_color = c
		_beam_material.emission = c

func _physics_process(delta: float) -> void:
	_cooldown = max(_cooldown - delta, 0.0)
	_retarget_timer -= delta

	# Re-pick only on the throttle, or when the cached target is gone/out of range
	# (a cheap check — no raycast). The full search was the tower hotspot, so we
	# keep it off the per-frame path.
	if _retarget_timer <= 0.0 or not _target_valid(_stats()["range"]):
		_target = _pick_target()
		_retarget_timer = RETARGET_INTERVAL

	if _target == null:
		if _is_beam():
			_set_beam(null)
		return

	var look := _target.global_position
	look.y = turret.global_position.y
	if look.distance_to(turret.global_position) > 0.05:
		turret.look_at(look, Vector3.UP)

	if _is_beam():
		# Continuous DPS to the locked target; redraw the beam each frame.
		if _target.has_method("take_damage"):
			_target.take_damage(_stats()["dps"] * delta)
		_set_beam(_target)
	elif _cooldown <= 0.0:
		_fire(_target)
		_cooldown = _stats()["cooldown"]

func _is_beam() -> bool:
	return _stats().get("beam", false)

## Layer mask of geometry that blocks line of sight (environment/obstacles).
const BLOCKER_MASK := 4

# Cheap per-frame validity: target still exists and is in range. No raycast here
# (LOS is only re-checked on the throttled full re-pick) — keeps the per-frame
# path allocation- and raycast-free.
func _target_valid(r: float) -> bool:
	if _target == null or not is_instance_valid(_target):
		return false
	return global_position.distance_to(_target.global_position) <= r

# Full target search: single pass tracking the most-progressed enemy that's in
# range AND has line of sight. No array/sort/lambda (those dominated the cost);
# this runs only on the retarget throttle, not every frame.
func _pick_target() -> Node3D:
	var r: float = _stats()["range"]
	var origin := muzzle.global_position if muzzle else global_position
	var best: Node3D = null
	var best_prog := -1.0
	for e in get_tree().get_nodes_in_group("td_enemy"):
		if not is_instance_valid(e):
			continue
		var prog := float(e._target_idx) if "_target_idx" in e else 0.0
		if prog <= best_prog:
			continue   # can't beat current best; skip the distance/LOS work
		if global_position.distance_to(e.global_position) > r:
			continue
		if not _has_los(origin, e):
			continue
		best_prog = prog
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
	var s := _stats()
	var origin := muzzle.global_position if muzzle else global_position
	if s.get("bomb", false):
		_fire_bomb(target, s, origin)
	else:
		_fire_projectile(target, s, origin)

func _fire_projectile(target: Node3D, s: Dictionary, origin: Vector3) -> void:
	if projectile_scene == null:
		return
	var proj := projectile_scene.instantiate()
	get_tree().current_scene.add_child(proj)
	proj.add_to_group("td_projectile")   # for the debug overlay's live count
	if proj.has_method("launch"):
		proj.launch(origin, target, s["damage"], s.get("proj_speed", -1.0))
		if tower_type == Type.FROST and proj.has_method("set_slow"):
			proj.set_slow(s["slow"], s["slow_dur"])
		_tint_projectile(proj)
	else:
		proj.global_position = origin

func _fire_bomb(target: Node3D, s: Dictionary, origin: Vector3) -> void:
	if bomb_scene == null:
		return
	# Predict where the target *would* be, assuming it keeps its current velocity.
	# Because the lead point is locked at fire time, a turn in the path makes the
	# bomb miss — exactly the intended fallibility.
	var speed: float = s.get("proj_speed", 10.0)
	var lead := _predict_landing(target, origin, speed)
	var bomb := bomb_scene.instantiate()
	get_tree().current_scene.add_child(bomb)
	bomb.add_to_group("td_projectile")   # for the debug overlay's live count
	if bomb.has_method("launch_bomb"):
		bomb.launch_bomb(origin, lead, speed, s["damage"], s["aoe"])

## Solve (roughly) for the lead point: horizontal flight time ≈ ground distance /
## speed, iterated a couple of times since moving the aim point changes the time.
func _predict_landing(target: Node3D, origin: Vector3, speed: float) -> Vector3:
	var vel := Vector3.ZERO
	if target.has_method("current_velocity"):
		vel = target.current_velocity()
	var aim: Vector3 = target.global_position
	for _i in 3:
		var ground: float = Vector2(aim.x - origin.x, aim.z - origin.z).length()
		var t: float = ground / maxf(speed, 0.01)
		aim = target.global_position + vel * t
	aim.y = target.global_position.y
	return aim

# One shared projectile material per tower type, built lazily and reused — so we
# don't allocate a StandardMaterial3D on every shot.
static var _proj_materials: Dictionary = {}

static func _projectile_material(type: int) -> StandardMaterial3D:
	if not _proj_materials.has(type):
		var mat := StandardMaterial3D.new()
		var c: Color = TYPES[type]["color"]
		mat.albedo_color = c
		mat.emission_enabled = true
		mat.emission = c
		mat.emission_energy_multiplier = 0.8
		_proj_materials[type] = mat
	return _proj_materials[type]

func _tint_projectile(proj: Node) -> void:
	var m := proj.get_node_or_null("Mesh")
	if m and m is MeshInstance3D:
		m.material_override = _projectile_material(tower_type)
