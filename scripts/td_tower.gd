extends Node3D
class_name TDTower

## A stationary auto-tower. Each frame it targets the enemy furthest along the
## path within range (and line of sight). Cannon/Bomb fire discrete projectiles
## on a cooldown; the Beam tower applies continuous DPS to a locked target.
## Stats come from TYPES so balancing and adding tiers/types is a one-place edit.

enum Type { BASIC, BEAM, BOMB }

enum DamageType { PHYSICAL, FIRE, FROST, POISON, SHOCK }

# Damage modifier per type per enemy health layer.
# Applied as a multiplier when damage flows through that layer.
# shield → armor → flesh, each fully depleted before the next takes damage.
const DAMAGE_MODIFIERS := {
	DamageType.PHYSICAL: { "flesh": 1.0, "armor": 1.0,  "shield": 1.0 },
	DamageType.FIRE:     { "flesh": 1.0, "armor": 0.75, "shield": 1.5 },
	DamageType.FROST:    { "flesh": 1.0, "armor": 1.25, "shield": 0.75 },
	DamageType.POISON:   { "flesh": 1.5, "armor": 1.25, "shield": 0.5 },
	DamageType.SHOCK:    { "flesh": 1.0, "armor": 0.5,  "shield": 2.0 },
}

signal destroyed(tower)        ## fired when a tower's health hits 0 (e.g. shot by a Gunner)
signal health_changed(current: float, maximum: float)  ## drives the floating HealthBar
signal died                                            ## HealthBar listens to hide on death

## Shared live-tower list so Gunner enemies can find towers without scanning the
## scene tree every frame. Towers self-register in _ready, deregister in _exit_tree.
static var all_towers: Array = []

## All towers share the same durability for now (tune per-type later if needed).
const MAX_HEALTH := 60.0

# Per-type, per-level stats. Index 0 = level 1.
#  - Beam towers use "dps" + "beam": true instead of "damage"/"cooldown".
#  - Bomb towers use "aoe" (blast radius) + "bomb": true; they lob to a predicted
#    ground point, so upgrading "proj_speed" both speeds the lob AND tightens the
#    lead prediction (shorter flight time = less chance the target has turned).
#  - "proj_speed" applies to all projectile towers.
const TYPES := {
	Type.BASIC: {
		"name": "Cannon",
		"color": Color(0.5, 0.55, 0.65),
		"shape": "cannon",
		"base_cost": 50,
		"upgrade_costs": [40, 70],            # cost L1->L2, L2->L3
		"tiers": [
			{ "range": 6.0, "damage": 10.0, "cooldown": 0.7, "proj_speed": 14.0 },
			{ "range": 6.8, "damage": 16.0, "cooldown": 0.6, "proj_speed": 18.0 },
			{ "range": 7.6, "damage": 24.0, "cooldown": 0.5, "proj_speed": 22.0 },
		],
	},
	Type.BEAM: {
		"name": "Beam",
		"color": Color(0.95, 0.4, 0.85),
		"shape": "beam",
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
		"shape": "bomb",
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

# Slow parameters applied by frost-typed projectiles on hit.
const FROST_SLOW_FACTOR    := 0.55   # multiplier on enemy speed (lower = slower)
const FROST_SLOW_DURATION  := 1.4    # seconds the slow lasts

@export var projectile_scene: PackedScene
@export var bomb_scene: PackedScene

@onready var turret: Node3D = $Turret
@onready var muzzle: Node3D = $Turret/Muzzle
@onready var _head: MeshInstance3D = $Turret/Head
@onready var _barrel: MeshInstance3D = $Turret/Barrel
@onready var _base: MeshInstance3D = $Base
@onready var _range_sphere: MeshInstance3D = $RangeSphere
@onready var _beam: MeshInstance3D = $Beam

const _HEAD_MESHES := {
	"cannon": "res://assets/models/towers/cannon_head.glb",
	"beam":   "res://assets/models/towers/beam_head.glb",
	"bomb":   "res://assets/models/towers/bomb_head.glb",
}
const _BASE_MESH_PATH := "res://assets/models/towers/base.glb"

## Cache loaded meshes so we only extract them from the PackedScene once.
static var _mesh_cache: Dictionary = {}

## Built lazily for the Beam tower: a tesla-coil/ray-gun emitter that extends out
## along the barrel to the muzzle, where the beam begins. Null for other types.
var _emitter: Node3D = null

var tower_type: int = Type.BASIC
var damage_type: int = DamageType.PHYSICAL
var level: int = 1
var total_spent: int = 0
var _cooldown: float = 0.0
var _target: Node3D = null          ## cached current target
var _retarget_timer: float = 0.0    ## time until the next full re-pick
const RETARGET_INTERVAL := 0.25     ## seconds between full target searches
var _head_material: StandardMaterial3D
var _beam_material: StandardMaterial3D

var health: float = MAX_HEALTH       ## current durability; Gunner fire reduces it
var _destroyed: bool = false
const FLASH_TIME := 0.15
var _flash_timer: float = 0.0


func _ready() -> void:
	_head_material = StandardMaterial3D.new()
	# Low metallic + a faint self-emission so the head reads as its true type color
	# whether it's in direct light or a wall's shadow (a high-metallic head looked
	# very different lit vs. shadowed — a lit bomb looked yellow, a shadowed one brown).
	_head_material.metallic = 0.1
	_head_material.roughness = 0.7
	_head_material.emission_enabled = true
	_head_material.emission_energy_multiplier = 0.6
	if _head:
		_head.material_override = _head_material
	TDTower.all_towers.append(self)
	if _beam:
		_beam.top_level = true     # position in world space, not relative to the tower
		_beam.visible = false
		_beam_material = StandardMaterial3D.new()
		_beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_beam_material.emission_enabled = true
		_beam_material.emission_energy_multiplier = 1.4
		_beam.material_override = _beam_material
	_apply_visual()
	# Initial full-HP broadcast for the HealthBar (deferred so the bar's _ready has
	# connected first). The bar treats this first emit as "full health, stay hidden".
	health_changed.emit.call_deferred(health, MAX_HEALTH)

func _exit_tree() -> void:
	TDTower.all_towers.erase(self)

## Damage from a Gunner creep (or an explosive grunt's death blast). At 0 the
## tower is destroyed: it emits `destroyed` so the game frees the slot, then frees
## itself. Flashes white on each hit for feedback.
func take_damage(amount: float) -> void:
	if _destroyed:
		return
	health = max(health - amount, 0.0)
	health_changed.emit(health, MAX_HEALTH)
	_flash_timer = FLASH_TIME
	_set_head_color(Color.WHITE)
	if health <= 0.0:
		_die()

func _die() -> void:
	if _destroyed:
		return
	_destroyed = true
	died.emit()
	destroyed.emit(self)
	add_child(_ShrinkAndFree.new(self, 0.2))

class _ShrinkAndFree extends Node:
	var _host: Node3D
	var _dur: float
	var _elapsed: float = 0.0
	var _start_scale: Vector3

	func _init(host: Node3D, dur: float) -> void:
		_host = host
		_dur = dur

	func _ready() -> void:
		_start_scale = _host.scale if is_instance_valid(_host) else Vector3.ONE

	func _process(delta: float) -> void:
		_elapsed += delta
		var f := minf(_elapsed / _dur, 1.0)
		var t := 1.0 - f
		if is_instance_valid(_host):
			_host.scale = _start_scale * (t * t * t)
		if f >= 1.0:
			if is_instance_valid(_host):
				_host.queue_free()
			queue_free()

## Called by the game controller right after instantiation.
func configure(type: int) -> void:
	tower_type = type
	level = 1
	total_spent = TYPES[type]["base_cost"]
	# Spread retarget ticks across the full interval so all towers never fire
	# their LOS raycasts in the same physics frame.
	_retarget_timer = randf() * RETARGET_INTERVAL
	_apply_visual()

func _stats() -> Dictionary:
	return TYPES[tower_type]["tiers"][level - 1]

func type_name() -> String: return TYPES[tower_type]["name"]
func damage_type_name() -> String:
	match damage_type:
		DamageType.FIRE:    return "Fire"
		DamageType.FROST:   return "Frost"
		DamageType.POISON:  return "Poison"
		DamageType.SHOCK:   return "Shock"
		_:                  return "Physical"
func is_max_level() -> bool: return level >= MAX_LEVEL
## True when the tower is at level 1 and has not yet chosen a damage type branch.
func needs_damage_type() -> bool: return level == 1 and damage_type == DamageType.PHYSICAL
func upgrade_cost() -> int:
	if is_max_level(): return 0
	return TYPES[tower_type]["upgrade_costs"][level - 1]
func sell_value() -> int: return int(total_spent * 0.5)

## Set the damage type branch. Only meaningful at level 1 before first upgrade;
## the choice is permanent and affects all future shots.
func set_damage_type(dt: int) -> void:
	damage_type = dt
	_apply_visual()

## Returns true if upgraded (caller already checked/charged affordability).
func upgrade() -> bool:
	if is_max_level(): return false
	total_spent += upgrade_cost()
	level += 1
	_apply_visual()
	return true

## Resting head color. Once a damage type is chosen it overrides the tower-type
## base color so the elemental branch reads at a glance.
const _DAMAGE_TYPE_COLORS := {
	DamageType.FIRE:   Color(0.95, 0.35, 0.15),
	DamageType.FROST:  Color(0.45, 0.75, 0.98),
	DamageType.POISON: Color(0.35, 0.85, 0.25),
	DamageType.SHOCK:  Color(0.95, 0.90, 0.2),
}
func _head_color() -> Color:
	var base: Color = _DAMAGE_TYPE_COLORS.get(damage_type, TYPES[tower_type]["color"])
	return base.lightened((level - 1) * 0.18)

# Set both albedo and the faint emission to the same color, so a head in shadow
# still glows toward its true type hue instead of going muddy/brown.
func _set_head_color(c: Color) -> void:
	if _head_material == null:
		return
	_head_material.albedo_color = c
	_head_material.emission = c

# Timer-driven white flash on hit; fades back to the resting head color. Mirrors
# the enemy's flash so repeated Gunner hits just refresh the timer (no tweens).
func _tick_flash(delta: float) -> void:
	_flash_timer -= delta
	if _head_material == null:
		return
	if _flash_timer <= 0.0:
		_set_head_color(_head_color())
	else:
		_set_head_color(Color.WHITE.lerp(_head_color(), 1.0 - _flash_timer / FLASH_TIME))

func _apply_visual() -> void:
	if _head_material == null: return
	# Brighten slightly per level so upgrades read at a glance.
	_set_head_color(_head_color())
	if _head:
		_head.scale = Vector3.ONE * (1.0 + (level - 1) * 0.12)
	_apply_shape()
	if _range_sphere and _range_sphere.visible:
		_update_range_sphere()

# Load a Mesh from a .glb PackedScene. GLB files import as scenes with a
# MeshInstance3D child; we extract and cache the Mesh resource so we only
# traverse the scene tree once per path.
static func _load_glb_mesh(path: String) -> Mesh:
	if _mesh_cache.has(path):
		return _mesh_cache[path]
	var packed: PackedScene = load(path)
	if packed == null:
		return null
	var root: Node = packed.instantiate()
	var mesh: Mesh = null
	for child in root.get_children():
		if child is MeshInstance3D:
			mesh = child.mesh
			break
	root.queue_free()
	_mesh_cache[path] = mesh
	return mesh

# Per-type head silhouette from the exported .glb assets. Barrel is hidden
# permanently — it is now part of each head mesh. Beam tower still builds its
# procedural emitter assembly on top of the glb base.
func _apply_shape() -> void:
	if _head == null:
		return
	var shape: String = TYPES[tower_type].get("shape", "cannon")
	if _emitter and shape != "beam":
		_emitter.visible = false
	if _barrel:
		_barrel.visible = false
	if _base:
		_base.mesh = _load_glb_mesh(_BASE_MESH_PATH)
	var head_path: String = _HEAD_MESHES.get(shape, _HEAD_MESHES["cannon"])
	_head.mesh = _load_glb_mesh(head_path)
	if shape == "beam":
		_build_beam_emitter()

# Build (once) the Beam tower's tesla-coil / ray-gun emitter under the Turret. It
# reads as a ray gun: a short vertical coil post on the head lifts a prominent
# horizontal barrel that extends forward along -Z out to the muzzle, capped by a
# pair of glowing prongs and a bright tip exactly at the beam's start point.
# Parented to the Turret so it swings with the aim. Re-shown on later calls.
func _build_beam_emitter() -> void:
	if _emitter != null:
		_emitter.visible = true
		return
	if turret == null:
		return
	# Muzzle local position relative to the turret = the beam's start point.
	var muzzle_z: float = -0.85
	if muzzle:
		muzzle_z = turret.to_local(muzzle.global_position).z

	_emitter = Node3D.new()
	turret.add_child(_emitter)

	var emat := _head_material if _head_material else StandardMaterial3D.new()
	var c: Color = TYPES[Type.BEAM]["color"]
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.emission_enabled = true
	glow.emission_energy_multiplier = 2.0
	glow.albedo_color = c
	glow.emission = c

	# The barrel runs at this height, lifted above the head so it reads as a gun.
	var by := 0.24

	# Coil post: a narrow ribbed pillar rising from the head — kept slim so the fat
	# horizontal barrel reads as a distinct element, not one continuous spike.
	var post := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.07; pm.bottom_radius = 0.13; pm.height = by
	pm.rings = 6                      # ribbed, coil-like
	post.mesh = pm
	post.position = Vector3(0, by * 0.5, 0.1)
	post.material_override = emat
	_emitter.add_child(post)

	# Main ray-gun barrel: a chunky box housing that's clearly WIDER than the post,
	# running horizontally from behind the post forward to the muzzle. A box reads
	# as a gun even when foreshortened (pointing toward/away from the camera).
	var barrel_back := 0.16
	var barrel_len: float = absf(muzzle_z - barrel_back)
	var barrel := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.26, 0.22, barrel_len)
	barrel.mesh = bm
	barrel.position = Vector3(0, by, (barrel_back + muzzle_z) * 0.5)
	barrel.material_override = emat
	_emitter.add_child(barrel)

	# Tapered glowing nozzle at the front of the barrel — the focusing emitter.
	var nozzle := MeshInstance3D.new()
	var nm := CylinderMesh.new()
	nm.top_radius = 0.05; nm.bottom_radius = 0.13; nm.height = 0.18
	nozzle.mesh = nm
	nozzle.rotation = Vector3(-PI / 2.0, 0, 0)   # point along -Z
	nozzle.position = Vector3(0, by, muzzle_z + 0.06)
	nozzle.material_override = glow
	_emitter.add_child(nozzle)

	# Two emitter prongs flanking the muzzle (the tesla "horns"), glowing.
	for sx in [-1.0, 1.0]:
		var prong := MeshInstance3D.new()
		var prm := CylinderMesh.new()
		prm.top_radius = 0.02; prm.bottom_radius = 0.035; prm.height = 0.3
		prong.mesh = prm
		prong.rotation = Vector3(-PI / 2.0, 0, 0)
		prong.position = Vector3(sx * 0.11, by, muzzle_z + 0.1)
		prong.material_override = glow
		_emitter.add_child(prong)

	# Glowing emitter tip at the muzzle — the bright orb the beam shoots from.
	var tip := MeshInstance3D.new()
	var tm := SphereMesh.new()
	tm.radius = 0.11; tm.height = 0.22
	tip.mesh = tm
	tip.position = Vector3(0, by, muzzle_z)
	tip.material_override = glow
	_emitter.add_child(tip)


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

func _process(delta: float) -> void:
	PerfTimer.begin("towers")
	if _destroyed:
		PerfTimer.end("towers")
		return
	_cooldown = max(_cooldown - delta, 0.0)
	_retarget_timer -= delta
	if _flash_timer > 0.0:
		_tick_flash(delta)

	var s := _stats()
	if _retarget_timer <= 0.0 or not _target_valid(s["range"]):
		_target = _pick_target()
		_retarget_timer = RETARGET_INTERVAL

	if _target == null:
		if s.get("beam", false):
			_set_beam(null)
		PerfTimer.end("towers")
		return

	var look := _target.global_position
	look.y = turret.global_position.y
	var aimed := true
	if look.distance_to(turret.global_position) > 0.05:
		aimed = _rotate_turret_toward(look, delta)

	if s.get("beam", false):
		if _target.has_method("take_damage"):
			_target.take_damage(s["dps"] * delta, damage_type)
		_set_beam(_target)
	elif _cooldown <= 0.0 and aimed:
		# Only fire once the barrel has actually swung onto the target, so shots
		# leave the muzzle pointed the right way instead of snapping mid-turn.
		_fire(_target)
		_cooldown = s["cooldown"]
	PerfTimer.end("towers")

## Max turret yaw speed (radians/sec). Turrets swing toward their target rather
## than snapping, so re-targeting reads as a visible rotation. Returns true once
## the turret is aimed within AIM_TOLERANCE of the target (the gate for firing).
const TURN_SPEED := 5.0
const AIM_TOLERANCE := 0.12   # radians (~7°)

func _rotate_turret_toward(look: Vector3, delta: float) -> bool:
	var to_target := look - turret.global_position
	# Barrel/muzzle point along the turret's local -Z, so the yaw that aims -Z at
	# the target is atan2(-x, -z) of the to-target vector.
	var desired := atan2(-to_target.x, -to_target.z)
	var current := turret.rotation.y
	var diff := wrapf(desired - current, -PI, PI)
	var step := TURN_SPEED * delta
	if absf(diff) <= step:
		turret.rotation.y = desired
		return true
	turret.rotation.y = current + signf(diff) * step
	return absf(diff) <= AIM_TOLERANCE


## Layer mask of geometry that blocks line of sight (environment/obstacles).
const BLOCKER_MASK := 4

# Cheap per-frame validity: target still exists and is in range. No raycast here
# (LOS is only re-checked on the throttled full re-pick) — keeps the per-frame
# path allocation- and raycast-free.
func _target_valid(r: float) -> bool:
	if _target == null or not is_instance_valid(_target):
		return false
	if "_dead" in _target and _target._dead:
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
	for e in TDEnemy.all_enemies:
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
	params.exclude = [self, enemy]
	var hit := space.intersect_ray(params)
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
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var proj := TDProjectile.acquire(scene_root, projectile_scene)
	proj.add_to_group("td_projectile")   # for the debug overlay's live count
	if proj.has_method("launch"):
		proj.launch(origin, target, s["damage"], s.get("proj_speed", -1.0), damage_type)
		if damage_type == DamageType.FROST and proj.has_method("set_slow"):
			proj.set_slow(FROST_SLOW_FACTOR, FROST_SLOW_DURATION)
		_tint_projectile(proj)
	else:
		proj.global_position = origin

func _fire_bomb(target: Node3D, s: Dictionary, origin: Vector3) -> void:
	if bomb_scene == null:
		return
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	# Predict where the target *would* be, assuming it keeps its current velocity.
	# Because the lead point is locked at fire time, a turn in the path makes the
	# bomb miss — exactly the intended fallibility.
	var speed: float = s.get("proj_speed", 10.0)
	var lead := _predict_landing(target, origin, speed)
	var bomb := TDBomb.acquire(scene_root, bomb_scene)
	bomb.add_to_group("td_projectile")   # for the debug overlay's live count
	if bomb.has_method("launch_bomb"):
		bomb.launch_bomb(origin, lead, speed, s["damage"], s["aoe"], damage_type)

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
