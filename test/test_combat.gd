extends GutTest

## Combat mechanics: missile AoE with falloff, shock slow, beam DPS, and the
## missile's velocity-lead prediction (which leads ahead but locks at fire time).

const MAIN := preload("res://scenes/td_main.tscn")
const TOWER := preload("res://scenes/td_tower.tscn")
const ENEMY := preload("res://scenes/td_enemy.tscn")
const BOMB := preload("res://scenes/td_bomb.tscn")

var game

func before_each():
	game = MAIN.instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)

func _enemy_at(pos: Vector3, progress: int = 1):
	var e = ENEMY.instantiate()
	game.add_child(e)
	e.add_to_group("td_enemy")
	e.configure(TDEnemy.Type.GRUNT)   # flesh_hp=30, no armor/shield
	e.set_physics_process(false)
	# Give it a 2-point path so current_velocity() has a real direction; set_path
	# moves it to path[0], so override position afterward.
	e.set_path(PackedVector3Array([pos, pos + Vector3(10, 0, 0)]))
	e.global_position = pos
	e._target_idx = progress if progress < 2 else 1
	return e

func test_missile_aoe_full_damage_at_center():
	var e = _enemy_at(Vector3(0, 1, 0))
	var hp0 = e.health.current_health
	var b = BOMB.instantiate(); game.add_child(b)
	b.launch_bomb(Vector3(0, 2, 5), Vector3(0, 1, 0), 10.0, 18.0, 2.5)
	b._explode()   # trigger AoE directly
	assert_almost_eq(hp0 - e.health.current_health, 18.0, 0.01,
		"enemy at the blast center takes full damage")

func test_missile_aoe_falloff_at_edge_is_less_than_center():
	var center = _enemy_at(Vector3(0, 1, 0))
	var edge = _enemy_at(Vector3(2.0, 1, 0))   # near the 2.5 radius edge
	var b = BOMB.instantiate(); game.add_child(b)
	b.launch_bomb(Vector3(0, 2, 5), Vector3(0, 1, 0), 10.0, 18.0, 2.5)
	b._explode()
	var center_dmg = 30.0 - center.health.current_health
	var edge_dmg = 30.0 - edge.health.current_health
	assert_gt(edge_dmg, 0.0, "edge enemy still takes some damage")
	assert_lt(edge_dmg, center_dmg, "edge damage is reduced by falloff")

func test_missile_aoe_misses_enemies_outside_radius():
	var far = _enemy_at(Vector3(10, 1, 10))
	var b = BOMB.instantiate(); game.add_child(b)
	b.launch_bomb(Vector3(0, 2, 5), Vector3(0, 1, 0), 10.0, 18.0, 2.5)
	b._explode()
	assert_eq(far.health.current_health, 30.0, "enemy outside the radius is untouched")

func test_shock_slow_reduces_effective_velocity():
	var e = _enemy_at(Vector3(-6, 1, -6), 2)   # heading toward waypoint 2
	var full = e.current_velocity().length()
	e.apply_slow(0.5, 1.0)
	var slowed = e.current_velocity().length()
	assert_almost_eq(slowed, full * 0.5, 0.01, "slow halves the effective speed")

func test_beam_applies_continuous_dps():
	var t = TOWER.instantiate(); game.add_child(t)
	t.configure(TDTower.Type.BEAM)
	t.global_position = Vector3(0, 0, 0)
	var e = _enemy_at(Vector3(2, 1, 0))
	var hp0 = e.health.current_health
	# Force the retarget timer so the first _process call runs a full target pick.
	t._retarget_timer = 0.0
	# Run the tower's process step manually with a 0.5s delta.
	t._process(0.5)
	var expected = t._stats()["dps"] * 0.5
	assert_almost_eq(hp0 - e.health.current_health, expected, 0.01,
		"beam deals dps * delta per step")

func test_missile_lead_predicts_ahead_of_motion():
	var t = TOWER.instantiate(); game.add_child(t)
	t.configure(TDTower.Type.MISSILE)
	t.global_position = Vector3(0, 0, 0)
	# Enemy moving along +X (waypoint to its right).
	var e = _enemy_at(Vector3(5, 1, 0), 1)
	var origin = t.muzzle.global_position
	var lead = t._predict_landing(e, origin, t._stats()["proj_speed"])
	var vel = e.current_velocity()
	var ahead = (lead - e.global_position).dot(vel)
	assert_gt(ahead, 0.0, "predicted landing leads the target along its velocity")
