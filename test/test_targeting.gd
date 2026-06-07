extends GutTest

## Tower targeting: range limit, "furthest along the path" leader selection, and
## line-of-sight blocking through the map's obstacle.

const MAIN := preload("res://scenes/td_main.tscn")
const TOWER := preload("res://scenes/td_tower.tscn")
const ENEMY := preload("res://scenes/td_enemy.tscn")

var game

func before_each():
	game = MAIN.instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)

# Make a bare enemy at a position with a given path-progress (_target_idx).
func _enemy_at(pos: Vector3, progress: int = 1):
	var e = ENEMY.instantiate()
	game.add_child(e)
	e.add_to_group("td_enemy")
	e.set_physics_process(false)   # freeze; we place it manually
	e.global_position = pos
	e._target_idx = progress
	return e

func _tower_at(pos: Vector3, type: int = TDTower.Type.BASIC):
	var t = TOWER.instantiate()
	game.add_child(t)
	t.configure(type)
	t.global_position = pos
	return t

func test_enemy_out_of_range_is_not_targeted():
	var t = _tower_at(Vector3(0, 0, 0))
	var r = t._stats()["range"]
	_enemy_at(Vector3(r + 5.0, 1, 0))     # well beyond range
	assert_null(t._pick_target(), "no target when the only enemy is out of range")

func test_enemy_in_range_is_targeted():
	var t = _tower_at(Vector3(0, 0, 0))
	var e = _enemy_at(Vector3(2, 1, 0))
	assert_eq(t._pick_target(), e, "in-range enemy is targeted")

func test_targets_enemy_furthest_along_the_path():
	var t = _tower_at(Vector3(0, 0, 0))
	var behind = _enemy_at(Vector3(1, 1, 0), 1)
	var ahead = _enemy_at(Vector3(2, 1, 0), 4)   # higher progress = closer to leaking
	assert_eq(t._pick_target(), ahead, "should target the leader (furthest along)")

func test_line_of_sight_blocked_by_obstacle():
	# The map's Obstacle wall sits around (4, y, 3.5). Put the tower south of it
	# and an enemy north of it so the wall is between them.
	var t = _tower_at(Vector3(4, 0, 6))
	var origin = t.muzzle.global_position
	var behind_wall = _enemy_at(Vector3(4, 1, 1))   # other side of the wall
	assert_false(t._has_los(origin, behind_wall), "wall should block line of sight")

func test_clear_line_of_sight_when_unobstructed():
	var t = _tower_at(Vector3(-10, 0, -6))
	var origin = t.muzzle.global_position
	var open = _enemy_at(Vector3(-8, 1, -6))   # open ground near the start
	assert_true(t._has_los(origin, open), "clear shot when nothing is between")
