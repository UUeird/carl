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
@export var path_node: NodePath        ## a Path3D defining the route
@export var enemy_y: float = 1.0       ## height creeps walk at

var currency: int
var lives: int
var wave: int = 0
var build_type: int = 0               ## TDTower.Type to place (set by HUD)
var _alive_enemies: int = 0
var _spawning: bool = false
var _over: bool = false
var _waypoints: PackedVector3Array = PackedVector3Array()
var _slot_tower: Dictionary = {}      ## slot -> tower built on it
var _selected_slot = null             ## currently selected (for the panel)

func _ready() -> void:
	currency = starting_currency
	lives = starting_lives
	_waypoints = _read_path()
	# Wire up every tower slot in the scene.
	for slot in get_tree().get_nodes_in_group("tower_slot"):
		if slot.has_signal("clicked"):
			slot.clicked.connect(_on_slot_clicked)
	state_changed.emit.call_deferred()
	message.emit.call_deferred("Build towers, then start the wave.")

func _read_path() -> PackedVector3Array:
	var pts := PackedVector3Array()
	var p := get_node_or_null(path_node)
	if p and p is Path3D and p.curve:
		for i in p.curve.point_count:
			var local: Vector3 = p.curve.get_point_position(i)
			pts.append(p.to_global(local))
	return pts

## Called by the HUD's "Start wave" button.
func start_next_wave() -> void:
	if _over or _spawning or _alive_enemies > 0:
		return
	if wave >= wave_count:
		return
	wave += 1
	state_changed.emit()
	_spawn_wave()

func _spawn_wave() -> void:
	_spawning = true
	for i in enemies_per_wave:
		if _over:
			break
		_spawn_one()
		await get_tree().create_timer(spawn_interval).timeout
	_spawning = false

func _spawn_one() -> void:
	if enemy_scene == null or _waypoints.size() < 2:
		return
	var e := enemy_scene.instantiate() as TDEnemy
	# Walk at a fixed height regardless of the path's authored Y.
	var pts := PackedVector3Array()
	for w in _waypoints:
		pts.append(Vector3(w.x, enemy_y, w.z))
	add_child(e)
	e.add_to_group("td_enemy")
	e.set_path(pts)
	e.killed.connect(_on_enemy_killed)
	e.reached_goal.connect(_on_enemy_leaked)
	_alive_enemies += 1

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
			message.emit("Wave %d cleared! Build, then start wave %d." % [wave, wave + 1])

func _on_slot_clicked(slot) -> void:
	if _over:
		return
	# Occupied slot → select its tower (open the panel).
	if slot.occupied:
		_select_slot(slot)
		return
	# Free slot → build the currently selected tower type.
	if tower_scene == null:
		return
	var cost: int = TDTower.TYPES[build_type]["base_cost"]
	if currency < cost:
		message.emit("Not enough currency (need %d)." % cost)
		return
	var t := tower_scene.instantiate()
	add_child(t)
	t.global_position = slot.global_position
	t.configure(build_type)
	slot.set_occupied()
	_slot_tower[slot] = t
	currency -= cost
	state_changed.emit()

func set_build_type(type: int) -> void:
	build_type = type
	_clear_selection()

func _select_slot(slot) -> void:
	_selected_slot = slot
	var tower = _slot_tower.get(slot)
	if tower:
		tower_selected.emit(tower)

func _clear_selection() -> void:
	_selected_slot = null
	selection_cleared.emit()

func upgrade_selected() -> void:
	var tower = _slot_tower.get(_selected_slot)
	if tower == null or _over:
		return
	if tower.is_max_level():
		message.emit("Tower is already at max level.")
		return
	var cost: int = tower.upgrade_cost()
	if currency < cost:
		message.emit("Not enough currency to upgrade (need %d)." % cost)
		return
	currency -= cost
	tower.upgrade()
	state_changed.emit()
	tower_selected.emit(tower)   # refresh the panel

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
	return not _over and not _spawning and _alive_enemies == 0 and wave < wave_count

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		get_tree().reload_current_scene()
