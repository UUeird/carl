extends GutTest

## Economy: building costs currency, upgrades step tiers with rising cost capped
## at max, selling refunds 50% of total spent and frees the slot.

const MAIN := preload("res://scenes/td_main.tscn")

var game

func before_each():
	game = MAIN.instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)   # let _ready run (reads path, wires slots)
	game.currency = 1000   # plenty for cost assertions

func _slot(n: int):
	return game.get_node("Slots/Slot%d" % n)

func test_building_a_cannon_costs_its_base_price():
	game.set_build_type(TDTower.Type.BASIC)
	game._on_slot_clicked(_slot(0))
	assert_eq(game.currency, 1000 - TDTower.TYPES[TDTower.Type.BASIC]["base_cost"],
		"currency should drop by the cannon base cost")
	assert_true(_slot(0).occupied, "slot should be occupied after building")

func test_cannot_build_without_enough_currency():
	game.currency = 10
	game.set_build_type(TDTower.Type.BASIC)
	game._on_slot_clicked(_slot(0))
	assert_eq(game.currency, 10, "currency unchanged when too poor")
	assert_false(_slot(0).occupied, "slot stays free when build is refused")

func test_upgrade_steps_level_and_charges_rising_cost():
	game.set_build_type(TDTower.Type.BASIC)
	game._on_slot_clicked(_slot(0))
	game._select_slot(_slot(0))
	var tower = game._slot_tower[_slot(0)]
	var c0 = game.currency
	var up1 = tower.upgrade_cost()
	game.upgrade_selected()
	assert_eq(tower.level, 2, "level should advance to 2")
	assert_eq(game.currency, c0 - up1, "currency drops by the upgrade cost")

func test_upgrade_capped_at_max_level():
	game.set_build_type(TDTower.Type.BASIC)
	game._on_slot_clicked(_slot(0))
	game._select_slot(_slot(0))
	var tower = game._slot_tower[_slot(0)]
	game.upgrade_selected()  # ->2
	game.upgrade_selected()  # ->3
	var c_at_max = game.currency
	game.upgrade_selected()  # should be refused
	assert_eq(tower.level, TDTower.MAX_LEVEL, "stays at max level")
	assert_eq(game.currency, c_at_max, "no charge when already max")

func test_sell_refunds_half_total_spent_and_frees_slot():
	game.set_build_type(TDTower.Type.BASIC)
	game._on_slot_clicked(_slot(0))
	game._select_slot(_slot(0))
	var tower = game._slot_tower[_slot(0)]
	game.upgrade_selected()  # spend more so refund != base
	var spent = tower.total_spent
	var before = game.currency
	game.sell_selected()
	assert_eq(game.currency, before + int(spent * 0.5), "refund is 50% of total spent")
	assert_false(_slot(0).occupied, "slot is freed after selling")
	assert_false(game._slot_tower.has(_slot(0)), "slot/tower mapping cleared")
