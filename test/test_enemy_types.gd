extends GutTest

## New enemy types and destructible towers: Healer aura heals nearby allies,
## Gunner damages the nearest tower in range, explosive Grunt blasts towers on
## death, and a tower at 0 HP is destroyed and frees its slot.

const MAIN := preload("res://scenes/td_main.tscn")
const TOWER := preload("res://scenes/td_tower.tscn")
const ENEMY := preload("res://scenes/td_enemy.tscn")

var game

func before_each():
	game = MAIN.instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)

func _enemy(type: int, pos: Vector3):
	var e = ENEMY.instantiate()
	game.add_child(e)
	e.add_to_group("td_enemy")
	e.configure(type)
	e.set_physics_process(false)   # freeze movement; we drive ticks manually
	e.global_position = pos
	return e

func _tower(pos: Vector3, type: int = TDTower.Type.MACHINE_GUN):
	var t = TOWER.instantiate()
	game.add_child(t)
	t.configure(type)
	t.global_position = pos
	return t

# --- Configure / type stats ---------------------------------------------------

func test_configure_applies_type_stats():
	var g = _enemy(TDEnemy.Type.GUNNER, Vector3.ZERO)
	var info = TDEnemy.TYPES[TDEnemy.Type.GUNNER]
	assert_eq(g.speed, info["speed"], "speed comes from the type table")
	assert_eq(g.bounty, info["bounty"], "bounty comes from the type table")
	var expected_hp: float = info["flesh_hp"] + info["armor_hp"] + info["shield_hp"]
	assert_eq(g.health.max_health, expected_hp, "max health is the sum of all layer HP")

# --- Towers are destructible --------------------------------------------------

func test_tower_takes_damage_and_survives():
	var t = _tower(Vector3.ZERO)
	t.take_damage(10.0)
	assert_eq(t.health, TDTower.MAX_HEALTH - 10.0, "tower loses HP but is not destroyed")

func test_tower_destroyed_at_zero_health_emits_signal():
	var t = _tower(Vector3.ZERO)
	var fired = [null]
	t.destroyed.connect(func(tower): fired[0] = tower)
	t.take_damage(TDTower.MAX_HEALTH)
	assert_eq(fired[0], t, "destroyed signal fires with the tower at 0 HP")

func test_destroyed_tower_frees_its_slot():
	# Build a real tower via a slot so the game's destroyed handler runs.
	var slot = game.get_tree().get_nodes_in_group("tower_slot")[0]
	game.build_type = TDTower.Type.MACHINE_GUN
	game._on_slot_clicked(slot)
	assert_true(slot.occupied, "slot is occupied after building")
	var tower = game._slot_tower[slot]
	tower.take_damage(TDTower.MAX_HEALTH)
	assert_false(slot.occupied, "slot is freed when its tower is destroyed")
	assert_false(game._slot_tower.has(slot), "slot/tower mapping is dropped")

# --- Gunner -------------------------------------------------------------------

func test_gunner_damages_nearest_tower_in_range():
	var t = _tower(Vector3(2, 0, 0))
	var g = _enemy(TDEnemy.Type.GUNNER, Vector3.ZERO)
	g._gun_timer = 0.0                 # ready to fire now
	var hp0 = t.health
	g._tick_gun(0.0)
	assert_lt(t.health, hp0, "gunner damages a tower within gun range")

func test_gunner_ignores_towers_out_of_range():
	var info = TDEnemy.TYPES[TDEnemy.Type.GUNNER]
	var far = info["gun_range"] + 5.0
	var t = _tower(Vector3(far, 0, 0))
	var g = _enemy(TDEnemy.Type.GUNNER, Vector3.ZERO)
	g._gun_timer = 0.0
	var hp0 = t.health
	g._tick_gun(0.0)
	assert_eq(t.health, hp0, "gunner does not hit a tower beyond its range")

# --- Healer -------------------------------------------------------------------

func test_healer_heals_a_damaged_ally_in_range():
	var ally = _enemy(TDEnemy.Type.GRUNT, Vector3(1, 0, 0))
	ally.take_damage(15.0)
	var hp_before = ally.health.current_health
	var healer = _enemy(TDEnemy.Type.HEALER, Vector3.ZERO)
	healer._heal_timer = 0.0
	healer._tick_heal(0.0)
	assert_gt(ally.health.current_health, hp_before, "healer restores HP to a nearby damaged ally")

func test_healer_does_not_heal_itself():
	var healer = _enemy(TDEnemy.Type.HEALER, Vector3.ZERO)
	healer.take_damage(10.0)
	var hp_before = healer.health.current_health
	healer._heal_timer = 0.0
	healer._tick_heal(0.0)
	assert_eq(healer.health.current_health, hp_before, "healer's aura skips itself")

func test_healer_ignores_allies_out_of_range():
	var info = TDEnemy.TYPES[TDEnemy.Type.HEALER]
	var far = info["heal_radius"] + 5.0
	var ally = _enemy(TDEnemy.Type.GRUNT, Vector3(far, 0, 0))
	ally.take_damage(15.0)
	var hp_before = ally.health.current_health
	var healer = _enemy(TDEnemy.Type.HEALER, Vector3.ZERO)
	healer._heal_timer = 0.0
	healer._tick_heal(0.0)
	assert_eq(ally.health.current_health, hp_before, "out-of-range allies are not healed")

# --- Explosive grunt ----------------------------------------------------------

func test_explosive_grunt_damages_nearby_tower_on_death():
	var t = _tower(Vector3(1, 0, 0))
	var g = _enemy(TDEnemy.Type.GRUNT, Vector3.ZERO)
	var hp0 = t.health
	g.health.take_damage(g.health.max_health)   # kill it -> _on_died -> explosion
	assert_lt(t.health, hp0, "explosive grunt's death blast damages a nearby tower")

func test_explosive_grunt_spares_distant_tower_on_death():
	var info = TDEnemy.TYPES[TDEnemy.Type.GRUNT]
	var far = info["death_aoe"] + 5.0
	var t = _tower(Vector3(far, 0, 0))
	var g = _enemy(TDEnemy.Type.GRUNT, Vector3.ZERO)
	var hp0 = t.health
	g.health.take_damage(g.health.max_health)
	assert_eq(t.health, hp0, "a tower outside the blast radius is untouched")
