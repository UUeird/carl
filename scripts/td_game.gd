extends Node3D
class_name TDGame

## Tower-defense game controller: owns the economy, lives, and wave flow, spawns
## enemies along the path, and builds towers when the player clicks a free slot.
## Emits state-change signals the HUD listens to (decoupled, like the old design).

signal state_changed                 ## currency / lives / wave changed
signal game_over(victory: bool)
signal message(text: String)
signal tower_selected(tower)         ## player clicked a built tower
signal selection_cleared

@export var starting_currency: int = 150
@export var starting_lives: int = 20
@export var enemies_per_wave: int = 6
@export var wave_count: int = 5
@export var spawn_interval: float = 0.9

@export var enemy_scene: PackedScene
@export var tower_scene: PackedScene
@export var projectile_scene: PackedScene   ## used only for shader pre-warm at startup
@export var bomb_scene: PackedScene         ## used only for shader pre-warm at startup
@export var path_node: NodePath        ## primary Path3D route
@export var path_node_b: NodePath      ## secondary (branch) Path3D route; if set, enemies randomly take either
@export var enemy_y: float = 1.0       ## height creeps walk at

var currency: int
var lives: int
var wave: int = 0
var build_type: int = 0               ## TDTower.Type to place (set by HUD)
var _alive_enemies: int = 0
var _spawning: bool = false
var _wave_cooldown: float = 0.0
const WAVE_COOLDOWN := 2.0
var _over: bool = false
var _waypoints: PackedVector3Array = PackedVector3Array()
var _waypoints_b: PackedVector3Array = PackedVector3Array()
var _slot_tower: Dictionary = {}      ## slot -> tower built on it
var _selected_slot = null             ## currently selected (for the panel)
var _preview: MeshInstance3D = null   ## range sphere shown while hovering a free slot
var _demo = null                      ## TDDemo autoplay driver (debug builds only)

func _ready() -> void:
	currency = starting_currency
	lives = starting_lives
	_waypoints = _read_path(path_node)
	_waypoints_b = _read_path(path_node_b)
	# Wire up every tower slot in the scene.
	for slot in get_tree().get_nodes_in_group("tower_slot"):
		if slot.has_signal("clicked"):
			slot.clicked.connect(_on_slot_clicked)
		if slot.has_signal("hovered"):
			slot.hovered.connect(_on_slot_hovered)
			slot.unhovered.connect(_on_slot_unhovered)
	_make_preview()
	_prewarm_shaders()
	state_changed.emit.call_deferred()
	message.emit.call_deferred("Build towers, then start the wave.")

## True when the autoplay demo is available (debug builds only). Note this can't
## depend on a node created in _ready: the HUD is a child, so its _ready runs
## BEFORE this node's _ready. Gate purely on the build type; the driver itself is
## created lazily in start_demo().
func demo_available() -> bool:
	return OS.is_debug_build()

## Kick off the autoplay demo (debug builds only). Creates the driver on first use
## so it doesn't rely on _ready ordering relative to the HUD.
func start_demo() -> void:
	if not OS.is_debug_build():
		return
	if _demo == null:
		# preload (not the global class_name) so a fresh headless run parses before
		# the editor has registered TDDemo in its class cache.
		_demo = preload("res://scripts/td_demo.gd").new()
		add_child(_demo)
		_demo.setup(self)
	_demo.start()

# Spawn one instance of every scene type far off-screen for a single frame so
# Godot compiles their shaders before gameplay starts, eliminating mid-wave stutter.
func _prewarm_shaders() -> void:
	var nodes: Array = []

	# Prime the glb mesh caches for all enemy and tower types so the first
	# configure() call of each type doesn't hit load() mid-wave.
	for type in TDEnemy.Type.values():
		TDEnemy._load_glb_mesh(TDEnemy._MESHES[type])
	for shape in TDTower._HEAD_MESHES:
		TDTower._load_glb_mesh(TDTower._HEAD_MESHES[shape])
	TDTower._load_glb_mesh(TDTower._BASE_MESH_PATH)

	# Pre-allocate the damage number pool so hits never alloc a Label3D mid-frame.
	preload("res://scripts/damage_number.gd").prewarm(self)

	# One instance per enemy type so every mesh gets GPU-uploaded before wave 1.
	# A single instantiate() only preloads whichever type configure() defaults to.
	if enemy_scene != null:
		for type in TDEnemy.Type.values():
			var e: Node = enemy_scene.instantiate()
			e.position = Vector3(0, -9999, 0)
			add_child(e)
			if e.has_method("configure"):
				e.configure(type)
			nodes.append(e)

	# Pre-allocate projectile and bomb pools so shots never instantiate mid-wave.
	if projectile_scene != null:
		TDProjectile.prewarm(self, projectile_scene)
	if bomb_scene != null:
		TDBomb.prewarm(self, bomb_scene)

	# One instance of the tower scene for shader compilation.
	if tower_scene != null:
		var n: Node = tower_scene.instantiate()
		n.position = Vector3(0, -9999, 0)
		add_child(n)
		nodes.append(n)

	# Force all four per-type projectile tint materials to exist now, not on first shot.
	for type in TDTower.Type.values():
		var mat := TDTower._projectile_material(type)
		var mi := MeshInstance3D.new()
		mi.position = Vector3(0, -9999, 0)
		mi.material_override = mat
		add_child(mi)
		nodes.append(mi)

	# Pre-allocate enemy shot pool so gunner enemies never allocate mid-wave.
	TDEnemy.prewarm_shot_pool(self)

	# Initialize enemy VFX material templates and add them off-screen so their
	# shaders compile now (heal pulse, explosion, tracer) rather than mid-combat.
	for mat in TDEnemy.prewarm_vfx_templates():
		var mi := MeshInstance3D.new()
		mi.position = Vector3(0, -9999, 0)
		mi.material_override = mat
		add_child(mi)
		nodes.append(mi)

	await get_tree().process_frame
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()

func _make_preview() -> void:
	_preview = MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = 1.0
	m.height = 2.0
	_preview.mesh = m
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_preview.material_override = mat
	_preview.visible = false
	add_child(_preview)

func _on_slot_hovered(slot) -> void:
	if _over or slot.occupied or _preview == null:
		return
	var info: Dictionary = TDTower.TYPES[build_type]
	var r: float = info["tiers"][0]["range"]
	var c: Color = info["color"]
	_preview.global_position = slot.global_position + Vector3.UP * 0.85
	_preview.scale = Vector3.ONE * r
	var mat := _preview.material_override
	mat.albedo_color = Color(c.r, c.g, c.b, 0.14)
	_preview.visible = true

func _on_slot_unhovered(_slot) -> void:
	if _preview:
		_preview.visible = false

func _read_path(node_path: NodePath) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var p := get_node_or_null(node_path)
	if p and p is Path3D and p.curve:
		for i in p.curve.point_count:
			var local: Vector3 = p.curve.get_point_position(i)
			pts.append(p.to_global(local))
	return pts

func _process(delta: float) -> void:
	if _wave_cooldown > 0.0:
		var prev := _wave_cooldown
		_wave_cooldown = max(_wave_cooldown - delta, 0.0)
		# Only emit when cooldown crosses zero (wave becomes startable), not every frame.
		if prev > 0.0 and _wave_cooldown <= 0.0:
			state_changed.emit()

## Called by the HUD's "Start wave" button.
func start_next_wave() -> void:
	if _over or _wave_cooldown > 0.0:
		return
	if wave >= wave_count:
		return
	wave += 1
	_wave_cooldown = WAVE_COOLDOWN
	state_changed.emit()
	_spawn_wave()

func _spawn_wave() -> void:
	_spawning = true
	# Boss spawns between waves: after wave 1 clears, a solo boss walks in before
	# the player can start the next wave. Skipped after the final wave.
	if wave > 1 and wave <= wave_count:
		_spawn_one(TDEnemy.Type.BOSS)
		await get_tree().create_timer(spawn_interval).timeout
	for i in enemies_per_wave:
		if _over:
			break
		_spawn_one()
		await get_tree().create_timer(spawn_interval).timeout
	_spawning = false

func _spawn_one(type: int = -1) -> void:
	if enemy_scene == null or _waypoints.size() < 2:
		return
	var e := enemy_scene.instantiate() as TDEnemy
	# Pick branch randomly when a second path is configured.
	var src := _waypoints
	if _waypoints_b.size() >= 2 and randf() < 0.5:
		src = _waypoints_b
	var pts := PackedVector3Array()
	for w in src:
		pts.append(Vector3(w.x, enemy_y, w.z))
	add_child(e)
	e.add_to_group("td_enemy")
	# configure() after add_child so its @onready Health ref is valid; defaults to
	# a wave-appropriate mix when no explicit type is given.
	e.configure(type if type >= 0 else _pick_enemy_type())
	e.set_path(pts)
	e.killed.connect(_on_enemy_killed)
	e.reached_goal.connect(_on_enemy_leaked)
	_alive_enemies += 1

## Choose an enemy type for the current wave. Early waves are pure Grunts; Healers
## appear from wave 2 and Gunners from wave 3, as a minority of each wave.
func _pick_enemy_type() -> int:
	var roll := randf()
	if wave >= 3 and roll < 0.2:
		return TDEnemy.Type.GUNNER
	if wave >= 2 and roll < 0.45:
		return TDEnemy.Type.HEALER
	return TDEnemy.Type.GRUNT

func _on_enemy_killed(e: TDEnemy) -> void:
	currency += e.bounty
	_dec_enemies()
	state_changed.emit()

func _on_enemy_leaked(e: TDEnemy) -> void:
	lives = max(lives - e.leak_damage, 0)
	_dec_enemies()
	state_changed.emit()
	if lives <= 0:
		_end(false)

func _dec_enemies() -> void:
	_alive_enemies = max(_alive_enemies - 1, 0)
	if _alive_enemies == 0 and not _spawning and not _over:
		if wave >= wave_count:
			_end(true)
		else:
			message.emit("All clear! Start wave %d when ready." % [wave + 1])

func _on_slot_clicked(slot) -> void:
	# Occupied slot → select its tower (open the panel). Still allowed after the
	# game is over so players can inspect tower stats/health; building, upgrading,
	# and selling stay blocked (guarded in try_build / try_upgrade / sell_selected).
	if slot.occupied:
		_select_slot(slot)
		return
	if _over:
		return
	# Free slot → build the currently selected tower type.
	var cost: int = TDTower.TYPES[build_type]["base_cost"]
	if currency < cost:
		message.emit("Not enough currency (need %d)." % cost)
		return
	try_build(slot, build_type)

## Build a tower of `type` on a free `slot`, charging its cost. Returns true on
## success. Shared by the click handler and the demo driver; the caller is
## responsible for any "not enough currency" messaging it wants.
func try_build(slot, type: int) -> bool:
	if _over or tower_scene == null or slot == null or slot.occupied:
		return false
	var cost: int = TDTower.TYPES[type]["base_cost"]
	if currency < cost:
		return false
	var t := tower_scene.instantiate()
	add_child(t)
	t.global_position = slot.global_position
	t.configure(type)
	if t.has_signal("destroyed"):
		t.destroyed.connect(_on_tower_destroyed.bind(slot))
	slot.set_occupied()
	_slot_tower[slot] = t
	currency -= cost
	state_changed.emit()
	return true

## A Gunner (or explosive grunt blast) destroyed a built tower: free its slot and
## drop it from the map. If it was the selected tower, dismiss the panel too.
func _on_tower_destroyed(_tower, slot) -> void:
	if _selected_slot == slot:
		_clear_selection()
	_slot_tower.erase(slot)
	if slot.has_method("set_free"):
		slot.set_free()
	else:
		slot.occupied = false
	message.emit("A tower was destroyed!")
	state_changed.emit()

func set_build_type(type: int) -> void:
	build_type = type
	_clear_selection()

func _select_slot(slot) -> void:
	# Hide any previously-selected tower's range ring.
	_hide_selected_range()
	_selected_slot = slot
	var tower = _slot_tower.get(slot)
	if tower:
		if tower.has_method("show_range"):
			tower.show_range()
		tower_selected.emit(tower)

func _clear_selection() -> void:
	_hide_selected_range()
	_selected_slot = null
	selection_cleared.emit()

func _hide_selected_range() -> void:
	var prev = _slot_tower.get(_selected_slot)
	if prev and prev.has_method("hide_range"):
		prev.hide_range()

func upgrade_selected() -> void:
	if not try_upgrade(_slot_tower.get(_selected_slot)):
		return
	tower_selected.emit(_slot_tower.get(_selected_slot))   # refresh the panel

## Upgrade a specific tower if affordable and not maxed; charges the cost. Returns
## true on success. Shared by the panel button and the demo driver.
func try_upgrade(tower) -> bool:
	if tower == null or _over or not is_instance_valid(tower):
		return false
	if tower.is_max_level():
		return false
	var cost: int = tower.upgrade_cost()
	if currency < cost:
		return false
	currency -= cost
	tower.upgrade()
	state_changed.emit()
	return true

## All built towers (used by the demo driver). Order isn't guaranteed.
func built_towers() -> Array:
	return _slot_tower.values()

## Free tower slots, sorted by node name for deterministic build order.
func free_slots() -> Array:
	var slots := []
	for slot in get_tree().get_nodes_in_group("tower_slot"):
		if not slot.occupied:
			slots.append(slot)
	slots.sort_custom(func(a, b): return a.name < b.name)
	return slots

func sell_selected() -> void:
	var slot = _selected_slot
	var tower = _slot_tower.get(slot)
	if tower == null or _over:
		return
	currency += tower.sell_value()
	tower.queue_free()
	_slot_tower.erase(slot)
	if slot.has_method("set_free"):
		slot.set_free()
	else:
		slot.occupied = false
	_clear_selection()
	state_changed.emit()

func _end(victory: bool) -> void:
	if _over:
		return
	_over = true
	game_over.emit(victory)
	var msg := "VICTORY — all waves cleared! Press R to restart." if victory else "DEFEAT — press R to restart."
	message.emit(msg)

func can_start_wave() -> bool:
	return not _over and _wave_cooldown <= 0.0 and wave < wave_count

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		get_tree().reload_current_scene()
		return
	# Esc, or a left-click that no tower/slot consumed, dismisses the panel.
	if event.is_action_pressed("ui_cancel"):
		_clear_selection()
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT and _selected_slot != null:
		_clear_selection()
