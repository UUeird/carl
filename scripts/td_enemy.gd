extends CharacterBody3D
class_name TDEnemy

## A tower-defense creep: walks an ordered list of waypoints from spawn to goal.
## Reuses the shared Health component. Reaching the goal costs the player a life;
## dying to towers pays out currency. The game controller wires up the signals.

signal reached_goal(enemy: TDEnemy)
signal killed(enemy: TDEnemy)

enum Type { GRUNT, HEALER, GUNNER, BOSS }

# Per-type stats and behavior flags. GRUNT is the default explosive creep; HEALER
# pulses a healing aura over nearby allies; GUNNER carries a turret that shoots
# the nearest tower. Mirrors TDTower.TYPES so adding/tuning types is one place.
const TYPES := {
	Type.GRUNT: {
		"name": "Grunt",
		"color": Color(0.85, 0.4, 0.4),
		"flesh_hp": 30.0, "armor_hp": 0.0, "shield_hp": 0.0,
		"speed": 3.5,
		"bounty": 5,
		"leak_damage": 1,
		"explosive": true,           # blast on goal + small AoE-vs-towers on death
		"death_aoe": 2.0,            # radius of the on-death blast
		"death_aoe_dmg": 12.0,       # damage dealt to towers caught in it
	},
	Type.HEALER: {
		"name": "Healer",
		"color": Color(0.45, 0.85, 0.5),
		"flesh_hp": 16.0, "armor_hp": 14.0, "shield_hp": 0.0,
		"speed": 3.2,
		"bounty": 9,
		"leak_damage": 1,
		"heal_radius": 3.5,
		"heal_amount": 6.0,          # HP restored per pulse to each ally in range
		"heal_interval": 1.0,        # seconds between pulses
	},
	Type.GUNNER: {
		"name": "Gunner",
		"color": Color(0.65, 0.55, 0.85),
		"flesh_hp": 24.0, "armor_hp": 0.0, "shield_hp": 20.0,
		"speed": 2.8,
		"bounty": 12,
		"leak_damage": 1,
		"gun_range": 6.0,
		"gun_damage": 6.0,
		"gun_cooldown": 1.1,         # seconds between shots at a tower
	},
	Type.BOSS: {
		"name": "Boss",
		"color": Color(0.9, 0.25, 0.15),
		"flesh_hp": 120.0, "armor_hp": 60.0, "shield_hp": 0.0,
		"speed": 1.8,
		"bounty": 40,
		"leak_damage": 5,            # costs 5 lives if it reaches the goal
		"boss_scale": 2.0,           # rendered at 2× normal size
	},
}

@export var speed: float = 3.5
@export var bounty: int = 5          ## currency paid when killed by a tower
@export var leak_damage: int = 1     ## lives lost if it reaches the goal

@onready var health: Health = $Health
@onready var mesh: MeshInstance3D = $Mesh
@onready var _health_bar: HealthBar = $HealthBar

var enemy_type: int = Type.GRUNT
var _path: PackedVector3Array = PackedVector3Array()
var _target_idx: int = 0
var _last_facing_idx: int = -1   ## track when waypoint changes so look_at only fires once per segment
var _dead: bool = false
var _material: StandardMaterial3D
var _base_color: Color = Color(0.85, 0.4, 0.4)

# Behavior state, populated by configure() from TYPES.
var _boss_scale: float = 1.0
var _explosive: bool = false
var _death_aoe: float = 0.0
var _death_aoe_dmg: float = 0.0
var _heal_radius: float = 0.0
var _heal_amount: float = 0.0
var _heal_interval: float = 0.0
var _heal_timer: float = 0.0
var _gun_range: float = 0.0
var _gun_damage: float = 0.0
var _gun_cooldown: float = 0.0
var _gun_timer: float = 0.0

# Health layers — damage flows shield → armor → flesh, each fully depleted first.
var shield_hp: float = 0.0
var armor_hp: float = 0.0
var flesh_hp: float = 0.0
var max_shield_hp: float = 0.0
var max_armor_hp: float = 0.0
var max_flesh_hp: float = 0.0

# Slow effect: while _slow_timer > 0, move at speed * _slow_factor.
var _slow_factor: float = 1.0
var _slow_timer: float = 0.0
const SLOW_COLOR := Color(0.55, 0.75, 1.0)

## Shared live-enemy list so towers don't call get_nodes_in_group every retarget tick.
static var all_enemies: Array = []

const _MESHES := {
	Type.GRUNT:  "res://assets/models/enemies/grunt.glb",
	Type.HEALER: "res://assets/models/enemies/healer.glb",
	Type.GUNNER: "res://assets/models/enemies/gunner.glb",
	Type.BOSS:   "res://assets/models/enemies/grunt.glb",   # reuses grunt mesh, scaled up
}
static var _mesh_cache: Dictionary = {}

# Shared material templates for one-shot VFX — duplicated per spawn so the
# shader compiles once at startup, not on first combat use.
static var _heal_pulse_mat: StandardMaterial3D = null
static var _tracer_mat: StandardMaterial3D = null
static var _explosion_mat: StandardMaterial3D = null
static var _vfx_sphere_mesh: SphereMesh = null   # shared by both heal pulse and explosion
static var _shot_mesh: SphereMesh = null          # gunner projectile
static var _shot_mat: StandardMaterial3D = null
static var _shot_pool: Array = []
const _SHOT_POOL_SIZE := 24
const _SHOT_SPEED := 10.0

## Call from td_game._prewarm_shaders() to initialize templates before first combat.
## Returns materials so the caller can add MeshInstances for shader compile.
static func prewarm_vfx_templates() -> Array:
	_ensure_vfx_templates()
	return [_heal_pulse_mat, _explosion_mat, _tracer_mat, _shot_mat]

static func prewarm_shot_pool(scene_root: Node) -> void:
	_ensure_vfx_templates()
	for i in _SHOT_POOL_SIZE:
		var mi := MeshInstance3D.new()
		mi.mesh = _shot_mesh
		mi.material_override = _shot_mat
		mi.visible = false
		scene_root.add_child(mi)
		_shot_pool.append(mi)

static func _ensure_vfx_templates() -> void:
	if _heal_pulse_mat != null:
		return
	_vfx_sphere_mesh = SphereMesh.new()
	_vfx_sphere_mesh.radius = 1.0
	_vfx_sphere_mesh.height = 2.0
	_heal_pulse_mat = StandardMaterial3D.new()
	_heal_pulse_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_heal_pulse_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_heal_pulse_mat.albedo_color = Color(0.45, 0.95, 0.5, 0.28)
	_explosion_mat = StandardMaterial3D.new()
	_explosion_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_explosion_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_explosion_mat.albedo_color = Color(1.0, 0.55, 0.2, 0.5)
	_tracer_mat = StandardMaterial3D.new()
	_tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_mat.emission_enabled = true
	_tracer_mat.emission = Color(1.0, 0.85, 0.4)
	_tracer_mat.albedo_color = Color(1.0, 0.85, 0.4)
	_shot_mesh = SphereMesh.new()
	_shot_mesh.radius = 0.18
	_shot_mesh.height = 0.36
	_shot_mat = StandardMaterial3D.new()
	_shot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shot_mat.emission_enabled = true
	_shot_mat.emission = Color(1.0, 0.2, 0.1)
	_shot_mat.albedo_color = Color(1.0, 0.4, 0.2)

static func _load_glb_mesh(path: String) -> Mesh:
	if _mesh_cache.has(path):
		return _mesh_cache[path]
	var packed: PackedScene = load(path)
	if packed == null:
		return null
	var root: Node = packed.instantiate()
	var m: Mesh = null
	for child in root.get_children():
		if child is MeshInstance3D:
			m = child.mesh
			break
	root.queue_free()
	_mesh_cache[path] = m
	return m

func _ready() -> void:
	health.died.connect(_on_died)
	_material = StandardMaterial3D.new()
	_material.albedo_color = _base_color
	mesh.material_override = _material
	TDEnemy.all_enemies.append(self)

func _exit_tree() -> void:
	TDEnemy.all_enemies.erase(self)
	_release_dmg_number()

## Set the enemy's type before it's added to the scene. Pulls stats + behavior
## flags from TYPES; safe to call before or after _ready (re-applies the color).
func configure(type: int) -> void:
	enemy_type = type
	var info: Dictionary = TYPES[type]
	speed = info["speed"]
	bounty = info["bounty"]
	leak_damage = info["leak_damage"]
	_base_color = info["color"]
	_boss_scale = info.get("boss_scale", 1.0)
	scale = Vector3.ONE * _boss_scale
	_explosive = info.get("explosive", false)
	_death_aoe = info.get("death_aoe", 0.0)
	_death_aoe_dmg = info.get("death_aoe_dmg", 0.0)
	_heal_radius = info.get("heal_radius", 0.0)
	_heal_amount = info.get("heal_amount", 0.0)
	_heal_interval = info.get("heal_interval", 0.0)
	# Stagger heal/gun ticks so same-type enemies don't all act on one frame.
	_heal_timer = randf() * maxf(_heal_interval, 0.01)
	_gun_range = info.get("gun_range", 0.0)
	_gun_damage = info.get("gun_damage", 0.0)
	_gun_cooldown = info.get("gun_cooldown", 0.0)
	_gun_timer = randf() * maxf(_gun_cooldown, 0.01)
	max_flesh_hp  = info.get("flesh_hp",  0.0)
	max_armor_hp  = info.get("armor_hp",  0.0)
	max_shield_hp = info.get("shield_hp", 0.0)
	flesh_hp  = max_flesh_hp
	armor_hp  = max_armor_hp
	shield_hp = max_shield_hp
	var total_hp := max_flesh_hp + max_armor_hp + max_shield_hp
	if health:
		health.max_health = total_hp
		health.current_health = total_hp
	if _health_bar:
		_health_bar.setup_layers(max_flesh_hp, max_armor_hp, max_shield_hp)
	if _material:
		_material.albedo_color = _base_color
	if mesh:
		var m := _load_glb_mesh(_MESHES[type])
		if m:
			mesh.mesh = m

## Called by the spawner before adding to the scene.
func set_path(points: PackedVector3Array) -> void:
	_path = points
	if _path.size() > 0:
		global_position = _path[0]
		_target_idx = 1

func _physics_process(delta: float) -> void:
	PerfTimer.begin("enemies")
	if _dmg_linger > 0.0:
		_dmg_linger -= delta
		if _dmg_linger <= 0.0:
			_release_dmg_number()
	if _dead or _target_idx >= _path.size():
		PerfTimer.end("enemies")
		return
	_tick_slow(delta)
	_tick_flash(delta)
	if _heal_radius > 0.0:
		_tick_heal(delta)
	if _gun_range > 0.0:
		_tick_gun(delta)
	var target: Vector3 = _path[_target_idx]
	var to: Vector3 = target - global_position
	to.y = 0.0
	var dist := to.length()
	if dist <= 0.1:
		_target_idx += 1
		if _target_idx >= _path.size():
			_leak()
		PerfTimer.end("enemies")
		return
	var step := to.normalized() * (speed * _slow_factor) * delta
	if step.length() >= dist:
		global_position = Vector3(target.x, global_position.y, target.z)
	else:
		global_position += step
	if _target_idx != _last_facing_idx and to.length() > 0.05:
		look_at(global_position + to.normalized(), Vector3.UP)
		_last_facing_idx = _target_idx
	PerfTimer.end("enemies")

## Current horizontal velocity (direction to the next waypoint × effective speed).
## Bomb towers use this to lead the target — note it points straight along the
## current segment, so it mispredicts through turns (by design).
func current_velocity() -> Vector3:
	if _dead or _target_idx >= _path.size():
		return Vector3.ZERO
	var to: Vector3 = _path[_target_idx] - global_position
	to.y = 0.0
	if to.length() < 0.001:
		return Vector3.ZERO
	return to.normalized() * (speed * _slow_factor)

const DMG_LINGER := 0.25   ## seconds after last hit before the number pops off

var _dmg_accum: float = 0.0         ## total damage since number was acquired
var _dmg_linger: float = 0.0        ## countdown to pop-off; reset on each hit
var _dmg_number: DamageNumber = null ## pinned node, null when not displaying

## Apply damage through the health layers: shield → armor → flesh, each fully
## depleted before the next takes any damage. Modifiers from the damage type
## are applied per layer as damage flows through. All sources feed the shared
## per-enemy accumulator — beam, bullet, bomb all show as one number.
func take_damage(amount: float, damage_type: int = TDTower.DamageType.PHYSICAL) -> void:
	if _dead:
		return
	_dmg_accum += amount
	_dmg_linger = DMG_LINGER
	var scene_root := get_tree().current_scene
	if _dmg_number == null and scene_root != null:
		_dmg_number = DamageNumber.acquire(scene_root, global_position + Vector3.UP * 1.4)
	if _dmg_number != null:
		_dmg_number.text = str(int(round(_dmg_accum)))
		_dmg_number.global_position = global_position + Vector3.UP * 1.4
	_apply_layer_damage(amount, damage_type)
	# _apply_layer_damage may fire the died signal, setting _dead = true and
	# releasing _dmg_number. Nothing to update after that point.

func _apply_layer_damage(amount: float, damage_type: int) -> void:
	var mods: Dictionary = TDTower.DAMAGE_MODIFIERS[damage_type]
	var remaining := amount
	if shield_hp > 0.0:
		var effective: float = remaining * mods["shield"]
		var absorbed: float = minf(shield_hp, effective)
		shield_hp -= absorbed
		remaining -= absorbed / (mods["shield"] as float)
	if remaining > 0.0 and armor_hp > 0.0:
		var effective: float = remaining * mods["armor"]
		var absorbed: float = minf(armor_hp, effective)
		armor_hp -= absorbed
		remaining -= absorbed / (mods["armor"] as float)
	if remaining > 0.0 and flesh_hp > 0.0:
		var effective: float = remaining * mods["flesh"]
		var absorbed: float = minf(flesh_hp, effective)
		flesh_hp -= absorbed
	var total_hp := shield_hp + armor_hp + flesh_hp
	health.set_hp(total_hp)
	if _health_bar:
		_health_bar.update_layers(flesh_hp, max_flesh_hp, armor_hp, max_armor_hp, shield_hp, max_shield_hp)
	_flash()

## Apply a slow: factor in (0,1] multiplies speed; refreshes/keeps the stronger
## slow and the longer remaining duration.
func apply_slow(factor: float, duration: float) -> void:
	if _dead:
		return
	_slow_factor = min(_slow_factor, factor) if _slow_timer > 0.0 else factor
	_slow_timer = max(_slow_timer, duration)
	_refresh_color()

func _tick_slow(delta: float) -> void:
	if _slow_timer > 0.0:
		_slow_timer -= delta
		if _slow_timer <= 0.0:
			_slow_factor = 1.0
			_refresh_color()

const FLASH_TIME := 0.15
var _flash_timer: float = 0.0

# Timer-driven flash (no per-hit tween): set white, then fade back in
# _physics_process. Repeated hits just refresh the timer — so a beam hitting
# every frame costs nothing extra instead of spawning ~60 tweens/sec.
func _flash() -> void:
	_flash_timer = FLASH_TIME
	_material.albedo_color = Color.WHITE

func _tick_flash(delta: float) -> void:
	if _flash_timer <= 0.0:
		return
	_flash_timer -= delta
	if _flash_timer <= 0.0:
		_material.albedo_color = _current_color()
	else:
		_material.albedo_color = Color.WHITE.lerp(_current_color(), 1.0 - _flash_timer / FLASH_TIME)

func _current_color() -> Color:
	return SLOW_COLOR if _slow_timer > 0.0 else _base_color

func _refresh_color() -> void:
	# Don't stomp an in-progress flash; only set resting color when not flashing.
	if _flash_timer <= 0.0:
		_material.albedo_color = _current_color()

# --- Healer: pulse a heal over nearby living allies ----------------------------

func _tick_heal(delta: float) -> void:
	_heal_timer -= delta
	if _heal_timer > 0.0:
		return
	_heal_timer = _heal_interval
	var pos := global_position
	for e in TDEnemy.all_enemies:
		if e == self or not is_instance_valid(e) or e._dead:
			continue
		if pos.distance_to(e.global_position) <= _heal_radius:
			e.receive_heal(_heal_amount)
	_spawn_heal_pulse()

## Heal applied by a Healer ally. Restores flesh first, then armor, then shield.
func receive_heal(amount: float) -> void:
	if _dead:
		return
	var remaining := amount
	var flesh_gap := max_flesh_hp - flesh_hp
	var flesh_heal := minf(remaining, flesh_gap)
	flesh_hp += flesh_heal
	remaining -= flesh_heal
	var armor_gap := max_armor_hp - armor_hp
	var armor_heal := minf(remaining, armor_gap)
	armor_hp += armor_heal
	remaining -= armor_heal
	shield_hp = minf(shield_hp + remaining, max_shield_hp)
	health.set_hp(flesh_hp + armor_hp + shield_hp)
	if _health_bar:
		_health_bar.update_layers(flesh_hp, max_flesh_hp, armor_hp, max_armor_hp, shield_hp, max_shield_hp)

func _spawn_heal_pulse() -> void:
	if get_tree().current_scene == null:
		return
	_ensure_vfx_templates()
	var ring := MeshInstance3D.new()
	ring.mesh = _vfx_sphere_mesh
	var heal_mat: StandardMaterial3D = _heal_pulse_mat.duplicate()
	ring.material_override = heal_mat
	ring.position = Vector3.ZERO
	ring.scale = Vector3.ONE * 0.3
	# Parent to self so the ring stays centered on the healer as it moves.
	add_child(ring)
	add_child(_VfxFade.new(ring, heal_mat, _heal_radius, 0.4))

# --- Gunner: shoot the nearest tower in range ----------------------------------

func _tick_gun(delta: float) -> void:
	_gun_timer -= delta
	if _gun_timer > 0.0:
		return
	var tower := _nearest_tower()
	if tower == null:
		return
	_gun_timer = _gun_cooldown
	if tower.has_method("take_damage"):
		tower.take_damage(_gun_damage)
	_fire_shot(tower)

func _nearest_tower() -> Node3D:
	var best: Node3D = null
	var best_d := _gun_range
	for t in TDTower.all_towers:
		if not is_instance_valid(t):
			continue
		var d := global_position.distance_to(t.global_position)
		if d <= best_d:
			best_d = d
			best = t
	return best

func _fire_shot(tower: Node3D) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	_ensure_vfx_templates()
	var mi: MeshInstance3D
	if _shot_pool.size() > 0:
		mi = _shot_pool.pop_back()
	else:
		mi = MeshInstance3D.new()
		mi.mesh = _shot_mesh
		mi.material_override = _shot_mat
		scene.add_child(mi)
	mi.global_position = global_position + Vector3.UP * 0.6
	mi.visible = true
	add_child(_ShotMover.new(mi, tower, _gun_damage, _shot_pool))

# --- Explosive: blast on goal + AoE-vs-towers on death -------------------------

func _spawn_explosion(damage_towers: bool) -> void:
	# Damage nearby towers first (independent of the visual, which needs a scene).
	# Goal blasts pass false — leaking already costs lives, so it's cosmetic there.
	if damage_towers and _death_aoe > 0.0:
		var pos := global_position
		for t in TDTower.all_towers:
			if not is_instance_valid(t):
				continue
			if pos.distance_to(t.global_position) <= _death_aoe and t.has_method("take_damage"):
				t.take_damage(_death_aoe_dmg)
	# Visual blast (skipped if there's no current scene, e.g. under tests).
	var scene := get_tree().current_scene
	if scene == null:
		return
	_ensure_vfx_templates()
	var ring := MeshInstance3D.new()
	ring.mesh = _vfx_sphere_mesh
	var explosion_mat: StandardMaterial3D = _explosion_mat.duplicate()
	ring.material_override = explosion_mat
	scene.add_child(ring)
	ring.global_position = global_position
	var radius: float = maxf(_death_aoe, 1.5)
	ring.scale = Vector3.ONE * 0.3
	scene.add_child(_VfxFade.new(ring, explosion_mat, radius, 0.25))

func _leak() -> void:
	if _dead:
		return
	_dead = true
	_release_dmg_number()
	if _explosive:
		_spawn_explosion(false)   # cosmetic blast on the base; no tower damage
	reached_goal.emit(self)
	queue_free()

func _release_dmg_number() -> void:
	DamageNumber.release(_dmg_number)
	_dmg_number = null
	_dmg_accum = 0.0

func _on_died() -> void:
	if _dead:
		return
	_dead = true
	_release_dmg_number()
	if _explosive:
		_spawn_explosion(true)    # AoE that can damage nearby towers
	killed.emit(self)
	add_child(_ShrinkFade.new(self, 0.2))

# Fades out a MeshInstance3D (and optionally expands it) without using Tween.
# target_scale > 0 → expand ring to that size while fading; -1 → no scale change.
class _VfxFade extends Node:
	var _ring: MeshInstance3D
	var _mat: StandardMaterial3D
	var _target_scale: float
	var _duration: float
	var _start_alpha: float
	var _elapsed: float = 0.0

	func _init(ring: MeshInstance3D, mat: StandardMaterial3D, target_scale: float, duration: float) -> void:
		_ring = ring
		_mat = mat
		_target_scale = target_scale
		_duration = duration
		_start_alpha = mat.albedo_color.a

	func _process(delta: float) -> void:
		_elapsed += delta
		var f := minf(_elapsed / _duration, 1.0)
		if is_instance_valid(_ring) and _target_scale > 0.0:
			_ring.scale = Vector3.ONE * lerpf(0.3, _target_scale, f)
		_mat.albedo_color.a = lerpf(_start_alpha, 0.0, f)
		if f >= 1.0:
			if is_instance_valid(_ring):
				_ring.queue_free()
			queue_free()

# Shrinks host node to zero then frees it — replaces the death-shrink Tween.
class _ShrinkFade extends Node:
	var _host: Node3D
	var _duration: float
	var _elapsed: float = 0.0
	var _start_scale: Vector3

	func _init(host: Node3D, duration: float) -> void:
		_host = host
		_duration = duration

	func _ready() -> void:
		_start_scale = _host.scale if is_instance_valid(_host) else Vector3.ONE

	func _process(delta: float) -> void:
		_elapsed += delta
		var f := minf(_elapsed / _duration, 1.0)
		# Ease-in-back equivalent: overshoot then shrink
		var t := 1.0 - f
		var eased := t * t * t  # simple ease-in; close enough without Tween.TRANS_BACK
		if is_instance_valid(_host):
			_host.scale = _start_scale * eased
		if f >= 1.0:
			if is_instance_valid(_host):
				_host.queue_free()
			queue_free()

# Moves a pooled MeshInstance3D from the gunner to a target tower, then returns
# it to the pool. Does NOT deal damage (already applied in _tick_gun).
class _ShotMover extends Node:
	var _mi: MeshInstance3D
	var _target: Node3D
	var _pool: Array
	const SPEED := 10.0

	func _init(mi: MeshInstance3D, target: Node3D, _dmg: float, pool: Array) -> void:
		_mi = mi
		_target = target
		_pool = pool

	func _process(delta: float) -> void:
		if not is_instance_valid(_mi):
			queue_free()
			return
		var dest := _target.global_position + Vector3.UP * 0.6 if is_instance_valid(_target) else _mi.global_position
		var to := dest - _mi.global_position
		if to.length() <= SPEED * delta + 0.1:
			_mi.visible = false
			_pool.append(_mi)
			queue_free()
			return
		_mi.global_position += to.normalized() * SPEED * delta
