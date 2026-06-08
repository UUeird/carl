extends GutTest

## Demo autoplay driver. The variety picker is a pure function, so it's tested
## directly; the end-to-end build/upgrade is tested through the game's public API.

const MAIN := preload("res://scenes/td_main.tscn")
const TDDemo := preload("res://scripts/td_demo.gd")

var game

func before_each():
	game = MAIN.instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)

# --- next_variety_type: always picks the least-built type ----------------------

func test_variety_picks_first_type_when_nothing_built():
	var counts = {}
	for t in TDTower.TYPES.keys():
		counts[t] = 0
	assert_eq(TDDemo.next_variety_type(counts), TDTower.TYPES.keys()[0],
		"with nothing built, builds the first type")

func test_variety_picks_the_missing_type():
	# Everything built once except the last type → that one is next.
	var keys = TDTower.TYPES.keys()
	var counts = {}
	for t in keys:
		counts[t] = 1
	var missing = keys[keys.size() - 1]
	counts[missing] = 0
	assert_eq(TDDemo.next_variety_type(counts), missing,
		"picks the under-represented type")

func test_variety_spreads_evenly_before_doubling():
	# Simulate building one at a time; the first N builds should be all distinct.
	var counts = {}
	for t in TDTower.TYPES.keys():
		counts[t] = 0
	var seen = {}
	for _i in TDTower.TYPES.size():
		var pick = TDDemo.next_variety_type(counts)
		seen[pick] = true
		counts[pick] += 1
	assert_eq(seen.size(), TDTower.TYPES.size(),
		"the first round of builds covers every type once")

# --- end-to-end through the game API ------------------------------------------

func test_try_build_places_a_tower_and_charges_currency():
	var slot = game.free_slots()[0]
	var c0 = game.currency
	var ok = game.try_build(slot, TDTower.Type.BASIC)
	assert_true(ok, "build succeeds on a free slot with enough currency")
	assert_true(slot.occupied, "slot becomes occupied")
	assert_eq(game.currency, c0 - TDTower.TYPES[TDTower.Type.BASIC]["base_cost"],
		"currency drops by the tower's cost")

func test_try_build_fails_when_too_poor():
	var slot = game.free_slots()[0]
	game.currency = 0
	assert_false(game.try_build(slot, TDTower.Type.BASIC), "no build with zero currency")
	assert_false(slot.occupied, "slot stays free")

func test_try_upgrade_raises_level_and_charges():
	var slot = game.free_slots()[0]
	game.try_build(slot, TDTower.Type.BASIC)
	var tower = game.built_towers()[0]
	game.currency = 9999
	var lvl0 = tower.level
	assert_true(game.try_upgrade(tower), "upgrade succeeds when affordable")
	assert_eq(tower.level, lvl0 + 1, "tower level increases by one")

func test_free_slots_shrinks_as_we_build():
	var n0 = game.free_slots().size()
	assert_gt(n0, 0, "there are free slots to begin with")
	game.try_build(game.free_slots()[0], TDTower.Type.BASIC)
	assert_eq(game.free_slots().size(), n0 - 1, "one fewer free slot after building")
