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

func test_head_color_is_type_color_regardless_of_damage():
	# Damage is shown by the HealthBar, not by tinting the head, so the head color
	# must stay the type's identity color even when badly hurt.
	var t = _tower(TDTower.Type.BOMB)
	var full = t._head_color()
	t.take_damage(t.MAX_HEALTH * 0.75)
	var hurt = t._head_color()
	assert_eq(hurt, full, "head keeps its type color after taking damage")
	var base: Color = TDTower.TYPES[TDTower.Type.BOMB]["color"]
	assert_almost_eq(hurt.r, base.r, 0.001, "bomb head stays its base orange")

func test_damage_emits_health_changed_for_the_bar():
	var t = _tower(TDTower.Type.BASIC)
	var got := []
	t.health_changed.connect(func(cur, mx): got.append([cur, mx]))
	t.take_damage(10.0)
	assert_eq(got.size(), 1, "taking damage emits health_changed once")
	assert_almost_eq(got[0][0], t.MAX_HEALTH - 10.0, 0.001, "emitted current HP reflects the hit")
	assert_almost_eq(got[0][1], t.MAX_HEALTH, 0.001, "emitted max HP is MAX_HEALTH")

func test_each_type_gets_a_distinct_head_mesh():
	var meshes := {}
	for type in [TDTower.Type.BASIC, TDTower.Type.FROST, TDTower.Type.BEAM, TDTower.Type.BOMB]:
		var t = _tower(type)
		var m: Mesh = t._head.mesh
		meshes[type] = m.get_class()
	# Frost (prism), Beam (cylinder), Bomb (sphere) all differ from the cannon box.
	assert_ne(meshes[TDTower.Type.FROST], meshes[TDTower.Type.BASIC], "frost head differs from cannon")
	assert_ne(meshes[TDTower.Type.BEAM], meshes[TDTower.Type.BASIC], "beam head differs from cannon")
	assert_ne(meshes[TDTower.Type.BOMB], meshes[TDTower.Type.BASIC], "bomb head differs from cannon")

func test_beam_tower_builds_emitter_reaching_the_muzzle():
	var t = _tower(TDTower.Type.BEAM, Vector3.ZERO)
	assert_not_null(t._emitter, "beam tower builds an emitter assembly")
	assert_true(t._emitter.visible, "emitter is visible")
	assert_eq(t._emitter.get_child_count(), 6, "emitter has post + barrel + nozzle + 2 prongs + tip")
	# The last child is the glowing tip; it should sit at the muzzle's local Z (the
	# beam's origin), so the emitter visibly extends out to where the beam begins.
	var tip: Node3D = t._emitter.get_child(t._emitter.get_child_count() - 1)
	var muzzle_z: float = t.turret.to_local(t.muzzle.global_position).z
	assert_almost_eq(tip.position.z, muzzle_z, 0.001, "emitter tip is at the muzzle / beam start")

func test_non_beam_towers_have_no_visible_emitter():
	for type in [TDTower.Type.BASIC, TDTower.Type.FROST, TDTower.Type.BOMB]:
		var t = _tower(type)
		assert_true(t._emitter == null or not t._emitter.visible,
			"type %d has no visible beam emitter" % type)

func test_turret_rotates_gradually_not_instantly():
	var t = _tower(TDTower.Type.BASIC, Vector3.ZERO)
	t.turret.rotation.y = 0.0
	# Target directly behind (requires a large yaw); a single small step must not
	# snap all the way around.
	var look := Vector3(0, t.turret.global_position.y, 5.0)
	var aimed: bool = t._rotate_turret_toward(look, 0.016)
	assert_false(aimed, "turret is not instantly aimed at a far-off target after one tick")
	assert_lt(absf(t.turret.rotation.y), 0.2, "turret only swung a small step toward the target")
