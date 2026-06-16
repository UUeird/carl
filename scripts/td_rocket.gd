extends Node3D
class_name TDRocket

## Rocket projectile for the Missile tower.  Arcs to a fixed lead-predicted
## ground point (same pattern as TDBomb) and on impact plays a two-stage
## explosion: a quick dome fire burst followed by a mushroom smoke cloud.
##
## In-flight visuals:
##   - Silver rocket body mesh (rocket_body.glb) oriented along velocity.
##   - Low-poly flame trail: a cone MeshInstance3D behind the nozzle that
##     pulses in size each frame (cheap, no tween per frame).
##   - Flame fades into a grey smoke disc as the rocket climbs (lerped by
##     arc progress so the flame is brightest at launch, smokiest at peak).
##
## Uses a static pool — call TDRocket.acquire() instead of instantiating.

@onready var mesh: MeshInstance3D = $Mesh

var _from:        Vector3
var _to:          Vector3
var _damage:      float = 0.0
var _aoe:         float = 2.0
var _damage_type: int   = TDTower.DamageType.PHYSICAL
var _t:           float = 0.0
var _flight:      float = 1.0
var _arc_height:  float = 3.0
var _exploded:    bool  = false
var _prev_pos:    Vector3

# Flame trail node parented to self, updated each frame.
var _flame: MeshInstance3D = null

static var _pool: Array = []

# Shared static meshes / materials — initialised once, reused by all instances.
static var _flame_mesh:       CylinderMesh      = null
static var _flame_mat:        StandardMaterial3D = null
static var _smoke_mat:        StandardMaterial3D = null

# Explosion visuals.
static var _burst_mesh:       SphereMesh        = null
static var _burst_mat:        StandardMaterial3D = null
static var _mushroom_mesh:    SphereMesh        = null
static var _mushroom_mat:     StandardMaterial3D = null
static var _stem_mesh:        CylinderMesh      = null
static var _stem_mat:         StandardMaterial3D = null
static var _shockwave_mesh:   TorusMesh         = null
static var _shockwave_mat:    StandardMaterial3D = null
static var _debris_mesh:      BoxMesh           = null
static var _debris_mat:       StandardMaterial3D = null

const POOL_SIZE    := 8
const FLAME_HEIGHT := 0.22
const FLAME_RADIUS := 0.05
const DEBRIS_COUNT := 6


static func _ensure_statics() -> void:
	if _flame_mesh != null:
		return

	# Flame — tapered cylinder (Godot 4 has no ConeMesh).
	_flame_mesh               = CylinderMesh.new()
	_flame_mesh.height        = FLAME_HEIGHT
	_flame_mesh.top_radius    = 0.001
	_flame_mesh.bottom_radius = FLAME_RADIUS
	_flame_mesh.radial_segments = 8

	_flame_mat = StandardMaterial3D.new()
	_flame_mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flame_mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame_mat.albedo_color               = Color(1.0, 0.65, 0.1, 0.92)
	_flame_mat.emission_enabled           = true
	_flame_mat.emission                   = Color(1.0, 0.45, 0.05)
	_flame_mat.emission_energy_multiplier = 1.8

	_smoke_mat = StandardMaterial3D.new()
	_smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_smoke_mat.albedo_color = Color(0.55, 0.55, 0.55, 0.55)

	# Dome burst — hemisphere that expands and shifts orange→black as it fades.
	_burst_mesh        = SphereMesh.new()
	_burst_mesh.radius = 1.0
	_burst_mesh.height = 2.0

	_burst_mat = StandardMaterial3D.new()
	_burst_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_burst_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_burst_mat.albedo_color = Color(1.0, 0.55, 0.1, 0.85)

	# Mushroom cap.
	_mushroom_mesh        = SphereMesh.new()
	_mushroom_mesh.radius = 1.0
	_mushroom_mesh.height = 0.8

	_mushroom_mat = StandardMaterial3D.new()
	_mushroom_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mushroom_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mushroom_mat.albedo_color = Color(0.38, 0.35, 0.33, 0.70)

	# Mushroom stem.
	_stem_mesh              = CylinderMesh.new()
	_stem_mesh.top_radius   = 0.12
	_stem_mesh.bottom_radius = 0.20
	_stem_mesh.height       = 1.0

	_stem_mat = StandardMaterial3D.new()
	_stem_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_stem_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_stem_mat.albedo_color = Color(0.42, 0.38, 0.35, 0.65)

	# Shockwave ring — flat torus that expands outward along the ground plane.
	_shockwave_mesh              = TorusMesh.new()
	_shockwave_mesh.inner_radius = 0.80
	_shockwave_mesh.outer_radius = 1.00
	_shockwave_mesh.rings        = 6
	_shockwave_mesh.ring_segments = 24

	_shockwave_mat = StandardMaterial3D.new()
	_shockwave_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shockwave_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shockwave_mat.albedo_color = Color(1.0, 0.75, 0.3, 0.70)
	_shockwave_mat.cull_mode    = BaseMaterial3D.CULL_DISABLED

	# Debris — small tumbling cubes ejected on impact.
	_debris_mesh      = BoxMesh.new()
	_debris_mesh.size = Vector3(0.06, 0.06, 0.06)

	_debris_mat = StandardMaterial3D.new()
	_debris_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_debris_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_debris_mat.albedo_color = Color(0.20, 0.18, 0.16, 1.0)


func _ready() -> void:
	_ensure_statics()
	_build_flame()


static func prewarm(scene_root: Node, rocket_scene: PackedScene) -> void:
	_ensure_statics()
	for i in POOL_SIZE:
		var r: TDRocket = rocket_scene.instantiate()
		r._exploded = false
		r.set_physics_process(false)
		r.visible = false
		scene_root.add_child(r)
		_pool.append(r)


static func acquire(scene_root: Node, rocket_scene: PackedScene) -> TDRocket:
	if _pool.size() > 0:
		return _pool.pop_back()
	var r: TDRocket = rocket_scene.instantiate()
	scene_root.add_child(r)
	return r


func launch_rocket(from: Vector3, to: Vector3, speed: float,
		damage: float, aoe: float,
		damage_type: int = TDTower.DamageType.PHYSICAL) -> void:
	_from        = from
	_to          = to
	_damage      = damage
	_aoe         = aoe
	_damage_type = damage_type
	_t           = 0.0
	_exploded    = false
	_prev_pos    = from
	var ground := Vector2(to.x - from.x, to.z - from.z).length()
	_flight      = maxf(ground / maxf(speed, 0.01), 0.25)
	_arc_height  = clampf(ground * 0.45, 1.8, 6.0)
	global_position = from
	visible = true
	set_physics_process(true)


func _build_flame() -> void:
	_flame = MeshInstance3D.new()
	_flame.mesh              = _flame_mesh
	_flame.material_override = _flame_mat.duplicate()
	add_child(_flame)
	# Position at the nozzle (bottom of the rocket body in local space).
	_flame.position = Vector3(0, -FLAME_HEIGHT * 0.5 - 0.04, 0)


func _physics_process(delta: float) -> void:
	PerfTimer.begin("rockets")
	if _exploded:
		PerfTimer.end("rockets")
		return

	_t += delta / _flight
	if _t >= 1.0:
		global_position = _to
		_explode()
		PerfTimer.end("rockets")
		return

	var pos := _from.lerp(_to, _t)
	pos.y  += _arc_height * 4.0 * _t * (1.0 - _t)

	# Orient rocket body along velocity vector.  Must set position first so
	# look_at has a valid origin; skip if vel_dir is degenerate or parallel to UP.
	global_position = pos
	var vel_dir := (pos - _prev_pos)
	_prev_pos = pos
	if vel_dir.length_squared() > 0.0001:
		var up := Vector3.RIGHT if abs(vel_dir.normalized().dot(Vector3.UP)) > 0.99 else Vector3.UP
		look_at(pos + vel_dir, up)

	_update_flame(delta)
	PerfTimer.end("rockets")


func _update_flame(_delta: float) -> void:
	if _flame == null or not is_instance_valid(_flame):
		return
	# Pulse size slightly each frame — cheap liveliness without per-frame tweens.
	var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.018) * 0.18
	_flame.scale = Vector3(pulse, pulse, pulse)
	# Lerp color from flame (launch) toward smoke (arc peak) then back to flame.
	var arc_phase: float = 1.0 - abs(_t - 0.5) * 2.0   # 0 at ends, 1 at peak
	var mat: StandardMaterial3D = _flame.material_override
	if mat:
		mat.albedo_color = _flame_mat.albedo_color.lerp(_smoke_mat.albedo_color, arc_phase * 0.7)
		mat.emission_energy_multiplier = lerpf(1.8, 0.2, arc_phase * 0.8)


func _explode() -> void:
	_exploded = true
	# Damage — do this before any visual work so a null scene_root doesn't skip it.
	for e in TDEnemy.all_enemies:
		if not is_instance_valid(e):
			continue
		var d := _to.distance_to(e.global_position)
		if d <= _aoe and e.has_method("take_damage"):
			var falloff := 1.0 - (d / _aoe) * 0.6
			e.take_damage(_damage * falloff, _damage_type)

	_spawn_explosion()
	_return_to_pool()


func _spawn_explosion() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return

	# Dome burst.
	var burst_mat: StandardMaterial3D = _burst_mat.duplicate()
	var burst := MeshInstance3D.new()
	burst.mesh              = _burst_mesh
	burst.material_override = burst_mat
	burst.global_position   = _to
	burst.scale             = Vector3.ONE * 0.15
	scene.add_child(burst)

	# Mushroom stem.
	var stem_mat: StandardMaterial3D = _stem_mat.duplicate()
	var stem := MeshInstance3D.new()
	stem.mesh              = _stem_mesh
	stem.material_override = stem_mat
	stem.global_position   = _to
	stem.scale             = Vector3(0.08, 0.08, 0.08)
	scene.add_child(stem)

	# Mushroom cap.
	var cap_mat: StandardMaterial3D = _mushroom_mat.duplicate()
	var cap := MeshInstance3D.new()
	cap.mesh              = _mushroom_mesh
	cap.material_override = cap_mat
	cap.global_position   = _to + Vector3(0, 0.1, 0)
	cap.scale             = Vector3(0.08, 0.05, 0.08)
	scene.add_child(cap)

	# Shockwave ring — flat torus expanding outward at ground level.
	var sw_mat: StandardMaterial3D = _shockwave_mat.duplicate()
	var shockwave := MeshInstance3D.new()
	shockwave.mesh              = _shockwave_mesh
	shockwave.material_override = sw_mat
	shockwave.global_position   = _to
	shockwave.scale             = Vector3(0.1, 0.1, 0.1)
	scene.add_child(shockwave)

	# Debris cubes — ejected radially, arc up and fall.
	var debris: Array = []
	var debris_vels: Array = []
	for i in DEBRIS_COUNT:
		var d := MeshInstance3D.new()
		d.mesh              = _debris_mesh
		d.material_override = _debris_mat
		d.global_position   = _to + Vector3(0, 0.2, 0)
		scene.add_child(d)
		var angle := i * TAU / DEBRIS_COUNT + randf() * 0.4
		var speed := randf_range(2.5, 5.0)
		debris_vels.append(Vector3(cos(angle) * speed, randf_range(3.0, 6.0), sin(angle) * speed))
		debris.append(d)

	scene.add_child(_ExplosionFade.new(
		burst, burst_mat, stem, stem_mat, cap, cap_mat,
		shockwave, sw_mat, debris, debris_vels, _aoe
	))


func _return_to_pool() -> void:
	visible = false
	set_physics_process(false)
	_pool.append(self)


# ---------------------------------------------------------------------------
# Inner class — three-phase explosion: shockwave + dome burst + mushroom rise
# ---------------------------------------------------------------------------
class _ExplosionFade extends Node:
	# Phase 1 (0 → SHOCK_DUR):  shockwave ring expands; dome burst ignites.
	# Phase 2 (0 → BURST_DUR):  dome shifts orange→black and fades out.
	# Phase 3 (BURST_DUR → END): mushroom rises and dissipates; debris falls.
	const SHOCK_DUR := 0.14
	const BURST_DUR := 0.22
	const TOTAL_DUR := 0.70
	const GRAVITY   := 9.8

	var _burst:      MeshInstance3D
	var _burst_mat:  StandardMaterial3D
	var _stem:       MeshInstance3D
	var _stem_mat:   StandardMaterial3D
	var _cap:        MeshInstance3D
	var _cap_mat:    StandardMaterial3D
	var _shockwave:  MeshInstance3D
	var _sw_mat:     StandardMaterial3D
	var _debris:     Array
	var _dvels:      Array
	var _aoe:        float
	var _elapsed:    float = 0.0
	var _ground_y:   float

	func _init(
			burst: MeshInstance3D, bmat: StandardMaterial3D,
			stem:  MeshInstance3D, smat: StandardMaterial3D,
			cap:   MeshInstance3D, cmat: StandardMaterial3D,
			sw:    MeshInstance3D, swmat: StandardMaterial3D,
			debris: Array, dvels: Array, aoe: float) -> void:
		_burst     = burst;  _burst_mat  = bmat
		_stem      = stem;   _stem_mat   = smat
		_cap       = cap;    _cap_mat    = cmat
		_shockwave = sw;     _sw_mat     = swmat
		_debris    = debris; _dvels      = dvels
		_aoe       = aoe
		_ground_y  = burst.global_position.y

	func _process(delta: float) -> void:
		PerfTimer.begin("explosion_fade")
		_elapsed += delta
		var f: float = minf(_elapsed / TOTAL_DUR, 1.0)

		# ── Shockwave ring ───────────────────────────────────────────────────
		var sf: float = minf(_elapsed / SHOCK_DUR, 1.0)
		if is_instance_valid(_shockwave):
			var sr: float = lerpf(0.1, _aoe * 1.6, sf)
			_shockwave.scale = Vector3(sr, 0.08, sr)
		_sw_mat.albedo_color.a = lerpf(0.70, 0.0, sf)

		# ── Dome burst: expands + shifts orange→dark grey→transparent ────────
		var bf: float = minf(_elapsed / BURST_DUR, 1.0)
		if is_instance_valid(_burst):
			_burst.scale = Vector3.ONE * lerpf(0.15, _aoe * 1.05, bf)
		# Colour travels orange (0) → dark grey (0.6) → invisible (1.0)
		var hue_f: float = minf(bf * 1.6, 1.0)
		_burst_mat.albedo_color = Color(
			lerpf(1.0,  0.15, hue_f),
			lerpf(0.55, 0.12, hue_f),
			lerpf(0.1,  0.08, hue_f),
			lerpf(0.85, 0.0,  bf)
		)

		# ── Mushroom: rises and fades after the burst ─────────────────────────
		var mf: float = clampf((_elapsed - BURST_DUR) / (TOTAL_DUR - BURST_DUR), 0.0, 1.0)
		var stem_h: float = lerpf(0.08, _aoe * 0.95, mf)
		var stem_r: float = lerpf(0.08, _aoe * 0.25, mf)
		if is_instance_valid(_stem):
			_stem.scale            = Vector3(stem_r, stem_h, stem_r)
			_stem.global_position.y = _ground_y
		_stem_mat.albedo_color.a = lerpf(0.65, 0.0, mf)

		var cap_r: float = lerpf(0.08, _aoe * 0.70, mf)
		var cap_h: float = cap_r * 0.52
		if is_instance_valid(_cap):
			_cap.scale             = Vector3(cap_r, cap_h, cap_r)
			_cap.global_position.y = _ground_y + stem_h + cap_h * 0.5
		_cap_mat.albedo_color.a = lerpf(0.70, 0.0, mf)

		# ── Debris: arc upward then fall under gravity ────────────────────────
		for i in _debris.size():
			if not is_instance_valid(_debris[i]):
				continue
			_dvels[i].y -= GRAVITY * delta
			_debris[i].global_position += _dvels[i] * delta
			# Bounce/stop at ground.
			if _debris[i].global_position.y < _ground_y:
				_debris[i].global_position.y = _ground_y
				_dvels[i] = Vector3.ZERO
			# Fade out over total duration.
			var dm: StandardMaterial3D = _debris[i].material_override
			if dm:
				dm.albedo_color.a = lerpf(1.0, 0.0, f)

		if f >= 1.0:
			for node in ([_burst, _stem, _cap, _shockwave] + _debris):
				if is_instance_valid(node):
					node.queue_free()
			PerfTimer.end("explosion_fade")
			queue_free()
			return
		PerfTimer.end("explosion_fade")
