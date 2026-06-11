extends Node3D
class_name TDTower

## A stationary auto-tower. Each frame it targets the enemy furthest along the
## path within range (and line of sight). Projectile towers fire on a cooldown;
## the Beam tower applies continuous DPS. Stats come from TYPES — one-place edits.
##
## Projectile firing modes (set via TYPES flags):
##   (default)       Homing — tracks the live target node, always connects unless
##                   the target dies mid-flight. Good for slow reliable towers.
##   "lead_shot":true Lead-locked — aim point fixed at fire time via _predict_landing().
##                   Misses if the target turns, slows, or reverses. Good for fast
##                   high-RoF towers where prediction is part of the skill expression.
##   "bomb":true     Arc lob — same lead prediction but via TDBomb; adds AoE splash.

enum Type { MACHINE_GUN, BEAM, MISSILE }

enum DamageType { PHYSICAL, FIRE, POISON, SHOCK }

# Damage modifier per type per enemy health layer.
# Applied as a multiplier when damage flows through that layer.
# shield → armor → flesh, each fully depleted before the next takes damage.
const DAMAGE_MODIFIERS := {
	DamageType.PHYSICAL: { "flesh": 1.0, "armor": 1.0,  "shield": 1.0 },
	DamageType.FIRE:     { "flesh": 1.0, "armor": 0.75, "shield": 1.5 },
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
#  - "lead_shot": true  — straight non-homing bullet, aim locked at fire time.
#  - "dual_barrel": true — alternates left/right muzzle offset each shot.
#  - "beam": true        — continuous DPS mode; uses "dps" not "damage"/"cooldown".
#  - "bomb": true        — arc lob with AoE; uses "aoe" blast radius.
#  - "proj_speed" applies to all projectile towers (affects lead prediction too).
const TYPES := {
	Type.MACHINE_GUN: {
		"name": "Machine Gun",
		"color": Color(0.5, 0.55, 0.65),
		"shape": "cannon",
		"base_cost": 50,
		"upgrade_costs": [40, 70],
		# lead_shot: bullets fly straight to the predicted lead point locked at fire
		# time — they do NOT home. A target that turns, slows, or reverses will cause
		# the shot to miss. This is intentional; see _fire_lead_shot() in td_tower.gd.
		# dual_barrel: alternates left/right muzzle offset each shot.
		"tiers": [
			{ "range": 6.0, "damage": 4.0,  "cooldown": 0.22, "proj_speed": 22.0, "lead_shot": true, "dual_barrel": true },
			{ "range": 6.8, "damage": 6.5,  "cooldown": 0.18, "proj_speed": 28.0, "lead_shot": true, "dual_barrel": true },
			{ "range": 7.6, "damage": 10.0, "cooldown": 0.14, "proj_speed": 36.0, "lead_shot": true, "dual_barrel": true },
		],
	},
	Type.BEAM: {
		"name": "Beam",
		"color": Color(0.55, 0.57, 0.62),   # neutral grey; elemental color drives the arc/dome tint
		"shape": "beam",
		"base_cost": 70,
		"upgrade_costs": [55, 85],
		"tiers": [
			{ "range": 6.5, "dps": 9.0,  "beam": true, "max_targets": 2, "electrodes": 2 },
			{ "range": 7.2, "dps": 15.0, "beam": true, "max_targets": 2, "electrodes": 2 },
			{ "range": 8.0, "dps": 24.0, "beam": true, "max_targets": 4, "electrodes": 4 },
		],
	},
	Type.MISSILE: {
		"name": "Missile",
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

# Slow applied by Shock-typed hits to enemies that have no active shield.
const SHOCK_SLOW_FACTOR   := 0.55   # multiplier on enemy speed (lower = slower)
const SHOCK_SLOW_DURATION := 1.4    # seconds the slow lasts

@export var projectile_scene: PackedScene
@export var bomb_scene: PackedScene

@onready var turret: Node3D = $Turret
@onready var muzzle: Node3D = $Turret/Muzzle
@onready var _head: MeshInstance3D = $Turret/Head
@onready var _barrel: MeshInstance3D = $Turret/Barrel
@onready var _base: MeshInstance3D = $Base
@onready var _range_sphere: MeshInstance3D = $RangeSphere
@onready var _beam: MeshInstance3D = $Beam

# Elemental cap mesh (the colored piece on top) — one per tower shape.
const _HEAD_MESHES := {
	"cannon": "res://assets/models/towers/cannon_cap.glb",
	"beam":   "res://assets/models/towers/beam_head.glb",
	"bomb":   "res://assets/models/towers/bomb_head.glb",
}
# Grey body mesh shown under the cap — cannon has a dedicated split body;
# beam/bomb still use the head mesh for the full shape (no split yet).
const _BODY_MESHES := {
	"cannon": "res://assets/models/towers/cannon_body.glb",
}
const _BASE_MESH_PATH := "res://assets/models/towers/base.glb"

## Cache loaded meshes so we only extract them from the PackedScene once.
static var _mesh_cache: Dictionary = {}

## Beam tower electrode crown — a spinning Node3D parented under _emitter.
## Electrode rods are children; tips are tracked in world space each frame for
## per-tip LOS checks and arc origin selection.
var _emitter: Node3D = null
var _electrode_crown: Node3D = null      ## the spinning node
var _electrode_rods: Array = []          ## MeshInstance3D rods, rebuilt on level-up
var _electrode_mat: StandardMaterial3D = null   ## shared glow material for all rods
## Active beam targets for the multi-arc beam. Rebuilt on the retarget tick.
var _beam_targets: Array = []
## Arc MeshInstance3D slots — one per max possible target (6). Created once.
var _arc_meshes: Array = []
var _arc_materials: Array = []
const ELECTRODE_ROD_RADIUS := 0.04
const ELECTRODE_ROD_LENGTH := 0.48
const ELECTRODE_CROWN_RADIUS := 0.18   # base of rods distance from dome centre
const ELECTRODE_CROWN_HEIGHT := 0.28   # height of rod bases above turret origin
const ELECTRODE_SPIN_SPEED   := 1.2    # radians/sec idle rotation
const BEAM_ARC_RADIUS        := 0.035  # visual thickness of each arc cylinder

var tower_type: int = Type.MACHINE_GUN
var damage_type: int = DamageType.PHYSICAL
var level: int = 1
var total_spent: int = 0
var _cooldown: float = 0.0
var _left_barrel_next: bool = true  ## alternates which muzzle offset fires (dual_barrel towers)
var _target: Node3D = null          ## cached current target
var _retarget_timer: float = 0.0    ## time until the next full re-pick
const RETARGET_INTERVAL := 0.25     ## seconds between full target searches
var _head_material: StandardMaterial3D
var _barrel_material: StandardMaterial3D  ## static grey for the body mesh

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
	# Static grey for the body/barrel mesh — no emission, slightly rougher so it
	# reads as unpainted metal and stays visually subordinate to the colored cap.
	_barrel_material = StandardMaterial3D.new()
	_barrel_material.albedo_color = Color(0.38, 0.40, 0.44)
	_barrel_material.metallic = 0.3
	_barrel_material.roughness = 0.85
	TDTower.all_towers.append(self)
	# $Beam (the old single-cylinder beam) is superseded by per-arc meshes; hide it permanently.
	if _beam:
		_beam.visible = false
	_apply_visual()
	# Initial full-HP broadcast for the HealthBar (deferred so the bar's _ready has
	# connected first). The bar treats this first emit as "full health, stay hidden".
	health_changed.emit.call_deferred(health, MAX_HEALTH)

func _exit_tree() -> void:
	TDTower.all_towers.erase(self)
	for arc in _arc_meshes:
		if is_instance_valid(arc):
			arc.queue_free()
	_arc_meshes.clear()

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
	DamageType.FIRE:   Color(1.0,  0.22, 0.05),   # bold orange-red
	DamageType.POISON: Color(0.35, 0.85, 0.25),
	DamageType.SHOCK:  Color(0.25, 0.55, 1.0),    # electric blue / lightning
}
# Neutral grey shown on the cap before an element is chosen (level 1, no damage
# type yet). Once an element is selected the cap takes on the elemental color.
const _PRE_ELEMENT_CAP_COLOR := Color(0.40, 0.42, 0.47)

func _head_color() -> Color:
	var base: Color
	if damage_type == DamageType.PHYSICAL:
		base = _PRE_ELEMENT_CAP_COLOR
	else:
		base = _DAMAGE_TYPE_COLORS.get(damage_type, _PRE_ELEMENT_CAP_COLOR)
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
	_set_head_color(_head_color())
	if turret:
		turret.scale = Vector3.ONE * (1.0 + (level - 1) * 0.12)
	_apply_shape()
	_update_electrode_crown()
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
	if _base:
		_base.mesh = _load_glb_mesh(_BASE_MESH_PATH)
	var head_path: String = _HEAD_MESHES.get(shape, _HEAD_MESHES["cannon"])
	_head.mesh = _load_glb_mesh(head_path)
	# Cannon uses a split mesh: grey boxy housing on _barrel, colored cap on _head.
	# Other tower types have no dedicated body mesh yet — keep _barrel hidden.
	if _barrel:
		var body_path: String = _BODY_MESHES.get(shape, "")
		if body_path != "":
			_barrel.mesh = _load_glb_mesh(body_path)
			_barrel.material_override = _barrel_material
			_barrel.visible = true
		else:
			_barrel.visible = false
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
		_update_electrode_crown()
		return
	if turret == null:
		return
	_emitter = Node3D.new()
	turret.add_child(_emitter)
	# Shared glow material for all electrode rods — colour updated per frame.
	_electrode_mat = StandardMaterial3D.new()
	_electrode_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_electrode_mat.emission_enabled = true
	_electrode_mat.emission_energy_multiplier = 1.8
	# Spinning crown node — all rods are children of this so rotating it spins them.
	_electrode_crown = Node3D.new()
	_emitter.add_child(_electrode_crown)
	# Four arc mesh slots (max electrodes at level 3). Created once; hidden when unused.
	const MAX_ARCS := 4
	for _i in MAX_ARCS:
		var arc := MeshInstance3D.new()
		arc.top_level = true   # world-space positioning like the old single beam
		arc.visible = false
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.emission_enabled = true
		mat.emission_energy_multiplier = 1.6
		arc.material_override = mat
		if get_tree().current_scene:
			get_tree().current_scene.add_child(arc)
		else:
			turret.add_child(arc)
		_arc_meshes.append(arc)
		_arc_materials.append(mat)
	_build_electrode_crown()

# Builds (or rebuilds) the electrode rods for the current level's electrode count.
func _build_electrode_crown() -> void:
	if _electrode_crown == null:
		return
	# Remove old rods.
	for rod in _electrode_rods:
		if is_instance_valid(rod):
			rod.queue_free()
	_electrode_rods.clear()
	var n: int = _stats().get("electrodes", 5)
	var rod_mesh := CylinderMesh.new()
	rod_mesh.top_radius    = ELECTRODE_ROD_RADIUS * 0.4
	rod_mesh.bottom_radius = ELECTRODE_ROD_RADIUS
	rod_mesh.height        = ELECTRODE_ROD_LENGTH
	for i in n:
		var angle := TAU * i / n
		var rod := MeshInstance3D.new()
		rod.mesh = rod_mesh
		rod.material_override = _electrode_mat
		# Place rod base at the crown ring, then tilt 45° outward from vertical.
		# The cylinder mesh origin is at its centre, so shift down half-length so
		# the base sits at the ring and the tip extends outward+upward.
		rod.position = Vector3(
			sin(angle) * ELECTRODE_CROWN_RADIUS,
			ELECTRODE_CROWN_HEIGHT,
			cos(angle) * ELECTRODE_CROWN_RADIUS
		)
		# Tilt outward: positive X rotation in local space leans the top away from
		# centre. rotate_y first to face outward, then tilt on local X.
		rod.rotation.y = angle
		rod.rotate_object_local(Vector3.RIGHT, deg_to_rad(45.0))
		_electrode_crown.add_child(rod)
		_electrode_rods.append(rod)

# Called from _apply_visual when level changes — refreshes rod count if needed.
func _update_electrode_crown() -> void:
	if _electrode_crown == null:
		return
	var n: int = _stats().get("electrodes", 5)
	if _electrode_rods.size() != n:
		_build_electrode_crown()

# Returns the world-space tip position of electrode i.
func _electrode_tip(i: int) -> Vector3:
	if i >= _electrode_rods.size():
		return global_position
	var rod: MeshInstance3D = _electrode_rods[i]
	if not is_instance_valid(rod):
		return global_position
	# Tip is at the top of the rod (local +Y by half length).
	return rod.global_transform * Vector3(0.0, ELECTRODE_ROD_LENGTH * 0.5, 0.0)

# Pick up to max_targets enemies sorted by path progress (furthest first).
# Uses tower-centre distance for the range gate; per-tip LOS is checked at arc time.
func _pick_beam_targets() -> Array:
	var s := _stats()
	var r: float = s["range"]
	var max_t: int = s.get("max_targets", 4)
	# Collect all valid candidates with their progress scores.
	var candidates: Array = []
	for e in TDEnemy.all_enemies:
		if not is_instance_valid(e) or e._dead:
			continue
		if global_position.distance_to(e.global_position) > r:
			continue
		var prog := float(e._target_idx) if "_target_idx" in e else 0.0
		candidates.append([prog, e])
	# Sort descending by progress (furthest along path first).
	candidates.sort_custom(func(a, b): return a[0] > b[0])
	var result: Array = []
	for pair in candidates:
		if result.size() >= max_t:
			break
		result.append(pair[1])
	return result

# Draw (or hide) all arc slots. For each active target, find the nearest electrode
# tip that has LOS to it and isn't already assigned; draw a cylinder arc between
# the tip and the target. Remaining slots are hidden.
func _arc_color() -> Color:
	# Arcs are white before an element is chosen; once an element is picked they
	# take its color. This is separate from _head_color() so the cap stays grey
	# (uncolored metal) while the arcs already read as electric.
	if damage_type == DamageType.PHYSICAL:
		return Color.WHITE
	return _DAMAGE_TYPE_COLORS.get(damage_type, Color.WHITE)

func _update_arcs(targets: Array) -> void:
	var arc_color: Color = _arc_color()
	var used_electrodes: Array = []
	var slot := 0
	for raw_target in targets:
		var target: Node3D = raw_target as Node3D
		if slot >= _arc_meshes.size():
			break
		if target == null or not is_instance_valid(target):
			continue
		if "_dead" in target and target.get("_dead"):
			continue
		# Find the nearest idle electrode tip with LOS to this target.
		var best_tip := Vector3.ZERO
		var best_dist := INF
		var best_ei := -1
		for ei in _electrode_rods.size():
			if ei in used_electrodes:
				continue
			var tip := _electrode_tip(ei)
			if not _has_los(tip, target):
				continue
			var d: float = tip.distance_to(target.global_position)
			if d < best_dist:
				best_dist = d
				best_tip = tip
				best_ei = ei
		if best_ei >= 0:
			used_electrodes.append(best_ei)
		if best_ei < 0:
			# No electrode has LOS right now (crown mid-rotation) — hide this arc.
			(_arc_meshes[slot] as MeshInstance3D).visible = false
			slot += 1
			continue
		# Position the arc cylinder between tip and target centre.
		var arc: MeshInstance3D = _arc_meshes[slot]
		var a: Vector3 = best_tip
		var b: Vector3 = target.global_position
		var dir: Vector3 = b - a
		var dist: float = dir.length()
		if dist < 0.05:
			arc.visible = false
			slot += 1
			continue
		arc.visible = true
		var up: Vector3 = dir.normalized()
		var arbitrary := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
		var xv := arbitrary.cross(up).normalized()
		var zv := xv.cross(up).normalized()
		arc.global_transform = Transform3D(Basis(xv, up, zv), (a + b) * 0.5)
		arc.scale = Vector3(1.0, dist, 1.0)
		var mat: StandardMaterial3D = _arc_materials[slot]
		mat.albedo_color = arc_color
		mat.emission = arc_color
		if arc.mesh == null:
			var cm := CylinderMesh.new()
			cm.top_radius    = BEAM_ARC_RADIUS
			cm.bottom_radius = BEAM_ARC_RADIUS
			cm.height = 1.0   # scaled by Y
			arc.mesh = cm
		slot += 1
	# Hide unused slots.
	while slot < _arc_meshes.size():
		(_arc_meshes[slot] as MeshInstance3D).visible = false
		slot += 1


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
	# Beam towers manage their own multi-target list; skip the single-target pick.
	if not s.get("beam", false):
		if _retarget_timer <= 0.0 or not _target_valid(s["range"]):
			_target = _pick_target()
			_retarget_timer = RETARGET_INTERVAL

	if s.get("beam", false):
		# Spin the electrode crown continuously.
		if _electrode_crown != null:
			_electrode_crown.rotation.y += ELECTRODE_SPIN_SPEED * delta
		# Update electrode glow colour each frame (white pre-element, element color after).
		if _electrode_mat != null:
			var c := _arc_color()
			_electrode_mat.albedo_color = c
			_electrode_mat.emission = c
		# On retarget tick, rebuild the multi-target list.
		if _retarget_timer <= 0.0:
			_beam_targets = _pick_beam_targets()
			_retarget_timer = RETARGET_INTERVAL
		else:
			# Purge any targets that died or left range mid-interval.
			var r: float = s["range"]
			_beam_targets = _beam_targets.filter(func(e):
				if not is_instance_valid(e): return false
				if "_dead" in e and e.get("_dead"): return false
				return global_position.distance_to((e as Node3D).global_position) <= r)
		# Apply DPS and shock slow to every active target.
		for raw_t in _beam_targets:
			var t: Node3D = raw_t as Node3D
			if t == null or not is_instance_valid(t):
				continue
			if t.has_method("take_damage"):
				t.take_damage(s["dps"] * delta, damage_type)
			if damage_type == DamageType.SHOCK and t.has_method("apply_slow"):
				var shielded: bool = t.get("shield_hp") != null and (t.shield_hp as float) > 0.0
				if not shielded:
					t.apply_slow(SHOCK_SLOW_FACTOR, SHOCK_SLOW_DURATION)
		_update_arcs(_beam_targets)
		PerfTimer.end("towers")
		return

	# Non-beam towers: hide any leftover arcs, then do normal single-target logic.
	_update_arcs([])
	if _target == null:
		PerfTimer.end("towers")
		return

	var look := _target.global_position
	look.y = turret.global_position.y
	var aimed := true
	if look.distance_to(turret.global_position) > 0.05:
		aimed = _rotate_turret_toward(look, delta)

	if _cooldown <= 0.0 and aimed:
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

## Barrel half-separation for dual-barrel towers (world units, applied along turret local X).
const DUAL_BARREL_OFFSET := 0.18

func _fire(target: Node3D) -> void:
	var s := _stats()
	var origin := muzzle.global_position if muzzle else global_position
	if s.get("bomb", false):
		_fire_bomb(target, s, origin)
	elif s.get("lead_shot", false):
		_fire_lead_shot(target, s, origin)
	else:
		_fire_projectile(target, s, origin)

## Fire a straight (non-homing) projectile aimed at the predicted lead point.
## The aim is locked at fire time — if the target turns, slows, or reverses after
## the shot leaves, the bullet flies past. This is the intended fallibility of the
## Machine Gun (and any future "lead_shot" tower).
##
## dual_barrel: each call alternates a left/right offset along the turret's local X
## so consecutive shots visually come from different barrels.
func _fire_lead_shot(target: Node3D, s: Dictionary, origin: Vector3) -> void:
	if projectile_scene == null:
		return
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	# Apply barrel offset if this type uses dual barrels.
	var fire_origin := origin
	if s.get("dual_barrel", false) and turret != null:
		var side := turret.global_transform.basis.x * DUAL_BARREL_OFFSET
		fire_origin = origin + (side if _left_barrel_next else -side)
		_left_barrel_next = not _left_barrel_next
	var speed: float = s.get("proj_speed", 14.0)
	var lead := _predict_landing(target, fire_origin, speed)
	var proj := TDProjectile.acquire(scene_root, projectile_scene)
	proj.add_to_group("td_projectile")
	if proj.has_method("launch_straight"):
		proj.launch_straight(fire_origin, lead, s["damage"], speed, damage_type)
		if damage_type == DamageType.SHOCK and proj.has_method("set_shock_slow"):
			proj.set_shock_slow(SHOCK_SLOW_FACTOR, SHOCK_SLOW_DURATION)
		_tint_projectile(proj)
	else:
		proj.global_position = fire_origin

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
		if damage_type == DamageType.SHOCK and proj.has_method("set_shock_slow"):
			proj.set_shock_slow(SHOCK_SLOW_FACTOR, SHOCK_SLOW_DURATION)
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
# One material per DamageType, shared across all towers. Pre-element = neutral grey.
static var _proj_materials: Dictionary = {}

static func _projectile_material(dt: int) -> StandardMaterial3D:
	if not _proj_materials.has(dt):
		var mat := StandardMaterial3D.new()
		var c: Color = _DAMAGE_TYPE_COLORS.get(dt, Color(0.55, 0.57, 0.62))
		mat.albedo_color = c
		mat.emission_enabled = true
		mat.emission = c
		mat.emission_energy_multiplier = 0.8
		_proj_materials[dt] = mat
	return _proj_materials[dt]

func _tint_projectile(proj: Node) -> void:
	var m := proj.get_node_or_null("Mesh")
	if m and m is MeshInstance3D:
		m.material_override = _projectile_material(damage_type)
