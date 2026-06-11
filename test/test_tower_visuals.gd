extends GutTest

## Tower visual-improvement logic: damage darkens the resting head color, each
## type gets a distinct head mesh, and the turret swings toward its target rather
## than snapping instantly.

const MAIN := preload("res://scenes/td_main.tscn")
const TOWER := preload("res://scenes/td_tower.tscn")
const ENEMY := preload("res://scenes/td_enemy.tscn")

var game

func before_each():
	game = MAIN.instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)

func _tower(type: int, pos: Vector3 = Vector3.ZERO):
	var t = TOWER.instantiate(); game.add_child(t)
	t.configure(type)
	t.global_position = pos
	return t

func _enemy_at(pos: Vector3):
	var e = ENEMY.instantiate()
	game.add_child(e)
	e.set_physics_process(false)
	e.set_path(PackedVector3Array([pos, pos + Vector3(10, 0, 0)]))
	e.global_position = pos
	e._target_idx = 1
	return e

func test_head_color_is_stable_regardless_of_damage():
	# Damage is shown by the HealthBar, not by tinting the head, so the cap color
	# must not change when the tower takes damage.  Before an element is chosen the
	# cap is the neutral grey pre-element color; after choosing an element it takes
	# that element's color.  Neither should shift on damage.
	var t = _tower(TDTower.Type.MISSILE)
	var full = t._head_color()
	t.take_damage(t.MAX_HEALTH * 0.75)
	var hurt = t._head_color()
	assert_eq(hurt, full, "head color is unchanged after taking damage")
	# Pre-element cap must be the neutral grey, not the tower type color.
	assert_almost_eq(hurt.r, TDTower._PRE_ELEMENT_CAP_COLOR.r, 0.001, "pre-element cap is neutral grey")

func test_damage_emits_health_changed_for_the_bar():
	var t = _tower(TDTower.Type.MACHINE_GUN)
	var got := []
	t.health_changed.connect(func(cur, mx): got.append([cur, mx]))
	t.take_damage(10.0)
	assert_eq(got.size(), 1, "taking damage emits health_changed once")
	assert_almost_eq(got[0][0], t.MAX_HEALTH - 10.0, 0.001, "emitted current HP reflects the hit")
	assert_almost_eq(got[0][1], t.MAX_HEALTH, 0.001, "emitted max HP is MAX_HEALTH")

func test_each_type_gets_a_distinct_head_mesh():
	# All types now use ArrayMesh loaded from GLB — compare the resource reference,
	# not get_class() (which returns "ArrayMesh" for all of them).
	var meshes := {}
	for type in [TDTower.Type.MACHINE_GUN, TDTower.Type.BEAM, TDTower.Type.MISSILE]:
		var t = _tower(type)
		meshes[type] = t._head.mesh
	assert_ne(meshes[TDTower.Type.BEAM], meshes[TDTower.Type.MACHINE_GUN], "beam head differs from cannon")
	assert_ne(meshes[TDTower.Type.MISSILE], meshes[TDTower.Type.MACHINE_GUN], "missile head differs from cannon")

func test_beam_tower_builds_electrode_crown():
	var t = _tower(TDTower.Type.BEAM, Vector3.ZERO)
	assert_not_null(t._emitter, "beam tower builds an emitter assembly")
	assert_true(t._emitter.visible, "emitter is visible")
	assert_not_null(t._electrode_crown, "emitter contains an electrode crown node")
	var expected_rods: int = t._stats().get("electrodes", 5)
	assert_eq(t._electrode_rods.size(), expected_rods,
		"crown has %d electrode rods at level 1" % expected_rods)
	# Arc mesh slots created (one per max possible arc = 4).
	assert_eq(t._arc_meshes.size(), 4, "four arc mesh slots created")

func test_non_beam_towers_have_no_visible_emitter():
	for type in [TDTower.Type.MACHINE_GUN, TDTower.Type.MISSILE]:
		var t = _tower(type)
		assert_true(t._emitter == null or not t._emitter.visible,
			"type %d has no visible beam emitter" % type)

func test_turret_rotates_gradually_not_instantly():
	var t = _tower(TDTower.Type.MACHINE_GUN, Vector3.ZERO)
	t.turret.rotation.y = 0.0
	# Target directly behind (requires a large yaw); a single small step must not
	# snap all the way around.
	var look := Vector3(0, t.turret.global_position.y, 5.0)
	var aimed: bool = t._rotate_turret_toward(look, 0.016)
	assert_false(aimed, "turret is not instantly aimed at a far-off target after one tick")
	assert_lt(absf(t.turret.rotation.y), 0.2, "turret only swung a small step toward the target")
