extends GutTest

## Tests for the Tower Sandbox scene: verifies that the sandbox loads, switches
## tower types, fires without crashing, and cleans up correctly.

const SANDBOX_SCENE    := preload("res://scenes/tower_sandbox.tscn")
const PROJECTILE_SCENE := preload("res://scenes/td_projectile.tscn")
const BOMB_SCENE       := preload("res://scenes/td_bomb.tscn")
const ROCKET_SCENE     := preload("res://scenes/td_rocket.tscn")

var _sandbox

func before_each() -> void:
	_sandbox = SANDBOX_SCENE.instantiate()
	add_child_autofree(_sandbox)
	await wait_physics_frames(2)

func after_each() -> void:
	TDEnemy.all_enemies.clear()

# --- Scene loads ---------------------------------------------------------------

func test_sandbox_loads_with_tower() -> void:
	assert_not_null(_sandbox._tower, "tower is spawned on ready")
	assert_true(is_instance_valid(_sandbox._tower), "tower is valid")

func test_sandbox_has_camera() -> void:
	assert_not_null(_sandbox._camera, "camera is present")
	assert_true(is_instance_valid(_sandbox._camera), "camera is valid")

func test_sandbox_default_type_is_missile() -> void:
	assert_eq(_sandbox._current_type, TDTower.Type.MISSILE, "defaults to Missile")

# --- Type switching -----------------------------------------------------------

func test_switch_to_machine_gun() -> void:
	_sandbox._switch_type(TDTower.Type.MACHINE_GUN)
	assert_eq(_sandbox._current_type, TDTower.Type.MACHINE_GUN)
	assert_true(is_instance_valid(_sandbox._tower), "tower valid after switch")

func test_switch_to_beam() -> void:
	_sandbox._switch_type(TDTower.Type.BEAM)
	assert_eq(_sandbox._current_type, TDTower.Type.BEAM)
	assert_true(is_instance_valid(_sandbox._tower), "tower valid after switch")

func test_switch_to_missile() -> void:
	_sandbox._switch_type(TDTower.Type.MISSILE)
	assert_eq(_sandbox._current_type, TDTower.Type.MISSILE)
	assert_true(is_instance_valid(_sandbox._tower), "tower valid after switch")

func test_switch_replaces_old_tower() -> void:
	var first = _sandbox._tower
	_sandbox._switch_type(TDTower.Type.BEAM)
	await wait_physics_frames(2)
	assert_false(is_instance_valid(first), "old tower freed after switch")
	assert_ne(_sandbox._tower, first, "new tower is a different instance")

# --- Upgrade ------------------------------------------------------------------

func test_upgrade_increases_level() -> void:
	_sandbox._switch_type(TDTower.Type.MACHINE_GUN)
	var t = _sandbox._tower
	var lvl_before: int = t.level
	_sandbox._upgrade()
	assert_eq(t.level, lvl_before + 1, "level increments after upgrade")

func test_upgrade_does_not_exceed_max() -> void:
	var t = _sandbox._tower
	while not t.is_max_level():
		_sandbox._upgrade()
	var lvl_max: int = t.level
	_sandbox._upgrade()
	assert_eq(t.level, lvl_max, "level capped at max")

# --- Fire (no crash) ----------------------------------------------------------

func test_fire_machine_gun_sets_target() -> void:
	_sandbox._switch_type(TDTower.Type.MACHINE_GUN)
	await wait_physics_frames(1)
	_sandbox._on_fire_down()
	assert_not_null(_sandbox._fire_target, "fire target created on fire_down")
	assert_true(is_instance_valid(_sandbox._fire_target), "fire target is valid")
	_sandbox._on_fire_up()

func test_fire_up_clears_target() -> void:
	_sandbox._switch_type(TDTower.Type.MACHINE_GUN)
	await wait_physics_frames(1)
	_sandbox._on_fire_down()
	_sandbox._on_fire_up()
	assert_null(_sandbox._fire_target, "fire target cleared on fire_up")

func test_fire_missile_sets_target() -> void:
	_sandbox._switch_type(TDTower.Type.MISSILE)
	await wait_physics_frames(1)
	_sandbox._on_fire_down()
	assert_not_null(_sandbox._fire_target, "fire target created for missile")
	_sandbox._on_fire_up()

func test_fire_beam_registers_dummy_enemies() -> void:
	_sandbox._switch_type(TDTower.Type.BEAM)
	await wait_physics_frames(1)
	_sandbox._on_fire_down()
	var s: Dictionary = TDTower.TYPES[TDTower.Type.BEAM]["tiers"][0]
	var expected: int = mini(s.get("max_targets", 2), _sandbox.DUMMY_POSITIONS.size())
	assert_eq(TDEnemy.all_enemies.size(), expected, "beam dummy enemies registered")
	assert_eq(_sandbox._beam_dummies.size(), expected, "beam dummies tracked internally")

func test_fire_beam_does_not_crash() -> void:
	_sandbox._switch_type(TDTower.Type.BEAM)
	await wait_physics_frames(1)
	_sandbox._on_fire_down()
	await wait_physics_frames(4)
	assert_true(is_instance_valid(_sandbox._tower), "tower still valid after beam fire")

# --- Fire target cleanup ------------------------------------------------------

func test_clear_fire_targets_removes_beam_dummies() -> void:
	_sandbox._switch_type(TDTower.Type.BEAM)
	await wait_physics_frames(1)
	_sandbox._on_fire_down()
	assert_gt(TDEnemy.all_enemies.size(), 0, "dummies added")
	_sandbox._clear_fire_targets()
	assert_eq(TDEnemy.all_enemies.size(), 0, "dummies removed after clear")
	assert_eq(_sandbox._beam_dummies.size(), 0, "internal list cleared")

func test_switch_type_clears_fire_targets() -> void:
	_sandbox._switch_type(TDTower.Type.BEAM)
	_sandbox._on_fire_down()
	assert_gt(TDEnemy.all_enemies.size(), 0, "dummies present")
	_sandbox._switch_type(TDTower.Type.MISSILE)
	await wait_physics_frames(1)
	assert_eq(TDEnemy.all_enemies.size(), 0, "dummies cleared on type switch")

# --- Orbit / camera -----------------------------------------------------------

func test_orbit_starts_enabled() -> void:
	assert_true(_sandbox._orbiting, "orbiting on by default")

func test_o_key_stops_orbit() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_O
	ev.pressed = true
	_sandbox._unhandled_input(ev)
	assert_false(_sandbox._orbiting, "orbit stopped after first O key")
	assert_false(_sandbox._returning, "not returning yet — orbit just paused")

func test_o_key_resumes_return_when_stopped() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_O
	ev.pressed = true
	_sandbox._unhandled_input(ev)
	assert_false(_sandbox._orbiting)
	_sandbox._unhandled_input(ev)
	assert_true(_sandbox._returning, "second O press starts return-to-orbit")
