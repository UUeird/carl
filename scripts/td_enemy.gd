extends CharacterBody3D
class_name TDEnemy

## A tower-defense creep: walks an ordered list of waypoints from spawn to goal.
## Reuses the shared Health component. Reaching the goal costs the player a life;
## dying to towers pays out currency. The game controller wires up the signals.

signal reached_goal(enemy: TDEnemy)
signal killed(enemy: TDEnemy)

enum Type { GRUNT, HEALER, GUNNER }

# Per-type stats and behavior flags. GRUNT is the default explosive creep; HEALER
# pulses a healing aura over nearby allies; GUNNER carries a turret that shoots
# the nearest tower. Mirrors TDTower.TYPES so adding/tuning types is one place.
const TYPES := {
	Type.GRUNT: {
		"name": "Grunt",
		"color": Color(0.85, 0.4, 0.4),
		"health": 30.0,
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
		"health": 26.0,
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
		"health": 44.0,
		"speed": 2.8,
		"bounty": 12,
		"leak_damage": 1,
		"gun_range": 6.0,
		"gun_damage": 6.0,
		"gun_cooldown": 1.1,         # seconds between shots at a tower
	},
}

@export var speed: float = 3.5
@export var bounty: int = 5          ## currency paid when killed by a tower
@export var leak_damage: int = 1     ## lives lost if it reaches the goal

@onready var health: Health = $Health
@onready var mesh: MeshInstance3D = $Mesh

var enemy_type: int = Type.GRUNT
var _path: PackedVector3Array = PackedVector3Array()
var _target_idx: int = 0
var _last_facing_idx: int = -1   ## track when waypoint changes so look_at only fires once per segment
var _dead: bool = false
var _material: StandardMaterial3D
var _base_color: Color = Color(0.85, 0.4, 0.4)

# Behavior state, populated by configure() from TYPES.
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

# Slow effect: while _slow_timer > 0, move at speed * _slow_factor.
var _slow_factor: float = 1.0
var _slow_timer: float = 0.0
const SLOW_COLOR := Color(0.55, 0.75, 1.0)

## Shared live-enemy list so towers don't call get_nodes_in_group every retarget tick.
static var all_enemies: Array = []

func _ready() -> void:
	health.died.connect(_on_died)
	_material = StandardMaterial3D.new()
	_material.albedo_color = _base_color
	mesh.material_override = _material
	TDEnemy.all_enemies.append(self)

func _exit_tree() -> void:
	TDEnemy.all_enemies.erase(self)

## Set the enemy's type before it's added to the scene. Pulls stats + behavior
## flags from TYPES; safe to call before or after _ready (re-applies the color).
func configure(type: int) -> void:
	enemy_type = type
	var info: Dictionary = TYPES[type]
	speed = info["speed"]
	bounty = info["bounty"]
	leak_damage = info["leak_damage"]
	_base_color = info["color"]
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
	if health:
		health.max_health = info["health"]
		health.current_health = info["health"]
	if _material:
		_material.albedo_color = _base_color

## Called by the spawner before adding to the scene.
func set_path(points: PackedVector3Array) -> void:
	_path = points
	if _path.size() > 0:
		global_position = _path[0]
		_target_idx = 1

func _physics_process(delta: float) -> void:
	if _dead or _target_idx >= _path.size():
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
		return
	var step := to.normalized() * (speed * _slow_factor) * delta
	if step.length() >= dist:
		global_position = Vector3(target.x, global_position.y, target.z)
	else:
		global_position += step
	if _target_idx != _last_facing_idx and to.length() > 0.05:
		look_at(global_position + to.normalized(), Vector3.UP)
		_last_facing_idx = _target_idx

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

var _pending_dmg: float = 0.0   ## accumulates sub-1 hits (e.g. beam per-frame DPS)

func take_damage(amount: float) -> void:
	if _dead:
		return
	health.take_damage(amount)
	_flash()
	# Pop a floating number per whole point of damage; accumulate fractional
	# (beam) damage so we show "9" once rather than a flicker of "0"s.
	_pending_dmg += amount
	if _pending_dmg >= 1.0:
		var shown := int(round(_pending_dmg))
		_pending_dmg -= shown
		DamageNumber.popup(get_tree().current_scene, global_position + Vector3.UP * 1.4, shown)

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

## Heal applied by a Healer ally. Goes through Health so the bar reacts.
func receive_heal(amount: float) -> void:
	if _dead:
		return
	health.heal(amount)

func _spawn_heal_pulse() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var ring := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = 1.0
	m.height = 2.0
	ring.mesh = m
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.45, 0.95, 0.5, 0.28)
	ring.material_override = mat
	scene.add_child(ring)
	ring.global_position = global_position
	ring.scale = Vector3.ONE * 0.3
	var tw := ring.create_tween()
	tw.tween_property(ring, "scale", Vector3.ONE * _heal_radius, 0.4)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.4)
	tw.tween_callback(ring.queue_free)

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
	_spawn_tracer(tower.global_position)

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

func _spawn_tracer(to: Vector3) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var line := MeshInstance3D.new()
	var a := global_position + Vector3.UP * 0.6
	var dir := to - a
	var dist := dir.length()
	if dist < 0.01:
		return
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.04
	cyl.bottom_radius = 0.04
	cyl.height = 1.0
	line.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.4)
	mat.albedo_color = Color(1.0, 0.85, 0.4)
	line.material_override = mat
	scene.add_child(line)
	var up := dir.normalized()
	var arbitrary := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := arbitrary.cross(up).normalized()
	var z := x.cross(up).normalized()
	line.global_transform = Transform3D(Basis(x, up, z), (a + to) * 0.5)
	line.scale = Vector3(1.0, dist, 1.0)
	var tw := line.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.12)
	tw.tween_callback(line.queue_free)

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
	var ring := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = 1.0
	m.height = 2.0
	ring.mesh = m
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.55, 0.2, 0.5)
	ring.material_override = mat
	scene.add_child(ring)
	ring.global_position = global_position
	var radius: float = maxf(_death_aoe, 1.5)
	ring.scale = Vector3.ONE * 0.3
	var tw := ring.create_tween()
	tw.tween_property(ring, "scale", Vector3.ONE * radius, 0.25)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.25)
	tw.tween_callback(ring.queue_free)

func _leak() -> void:
	if _dead:
		return
	_dead = true
	if _explosive:
		_spawn_explosion(false)   # cosmetic blast on the base; no tower damage
	reached_goal.emit(self)
	queue_free()

func _on_died() -> void:
	if _dead:
		return
	_dead = true
	if _explosive:
		_spawn_explosion(true)    # AoE that can damage nearby towers
	killed.emit(self)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ZERO, 0.2).set_trans(Tween.TRANS_BACK)
	tw.tween_callback(queue_free)
