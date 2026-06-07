extends GutTest

## Wave/economy flow: killing pays bounty, leaking costs a life, and the game
## ends in defeat at 0 lives / victory after the last wave.

const MAIN := preload("res://scenes/td_main.tscn")
const ENEMY := preload("res://scenes/td_enemy.tscn")

var game

func before_each():
	game = MAIN.instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)

func _make_enemy():
	var e = ENEMY.instantiate()
	game.add_child(e)
	e.add_to_group("td_enemy")
	e.set_physics_process(false)
	return e

func test_killing_an_enemy_pays_its_bounty():
	var c0 = game.currency
	var e = _make_enemy()
	game._alive_enemies = 1
	game._on_enemy_killed(e)
	assert_eq(game.currency, c0 + e.bounty, "currency increases by the enemy bounty")

func test_leaking_costs_a_life():
	var lives0 = game.lives
	var e = _make_enemy()
	game._alive_enemies = 1
	game._on_enemy_leaked(e)
	assert_eq(game.lives, lives0 - e.leak_damage, "a leak costs leak_damage lives")

func test_defeat_when_lives_reach_zero():
	var result = [null]
	game.game_over.connect(func(v): result[0] = v)
	game.lives = 1
	var e = _make_enemy()
	game._alive_enemies = 1
	game._on_enemy_leaked(e)
	assert_eq(game.lives, 0, "lives hit zero")
	assert_eq(result[0], false, "defeat fires game_over(false)")

func test_cannot_start_wave_while_enemies_alive():
	game._alive_enemies = 3
	assert_false(game.can_start_wave(), "cannot start the next wave mid-combat")

func test_victory_after_final_wave_cleared():
	var result = [null]
	game.game_over.connect(func(v): result[0] = v)
	game.wave = game.wave_count        # on the last wave
	game._alive_enemies = 1
	var e = _make_enemy()
	game._on_enemy_killed(e)           # clears the last enemy of the last wave
	assert_eq(result[0], true, "victory fires game_over(true)")
