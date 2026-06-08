extends Node
class_name TDDemo

## Debug-only autoplay driver. Drives the existing public game API (try_build /
## try_upgrade / start_next_wave) to play a full run hands-free: it builds towers
## prioritizing TYPE VARIETY (one of each before doubling up) so a watcher sees the
## widest range of gameplay, upgrades what's built, and starts each of the 5 waves
## as soon as the cooldown allows. Stops at game over.
##
## It only acts through the same methods the player's clicks do — no special-casing
## — so what you watch is real gameplay, just automated.

const TICK := 0.6          ## seconds between demo actions (slow enough to watch)
const DEMO_BANK := 600     ## debug-only currency grant so the demo can field all
                           ## tower types + upgrades — the showcase, not the economy

var _game: TDGame
var _running: bool = false
var _timer: float = 0.0

func setup(game: TDGame) -> void:
	_game = game

func is_running() -> bool:
	return _running

func start() -> void:
	if _running or _game == null:
		return
	_running = true
	_timer = 0.0
	# Top up the bank so the demo can actually show every tower type + upgrades
	# instead of being gated by the early economy. Debug-only by construction.
	_game.currency = max(_game.currency, DEMO_BANK)
	_game.state_changed.emit()
	_game.message.emit("Demo running — autoplaying all waves.")

func stop() -> void:
	_running = false

func _process(delta: float) -> void:
	if not _running or _game == null:
		return
	if _game._over:
		_running = false
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = TICK
	_act()

## One action per tick, in priority order:
##   1. Build toward type variety while there are free slots and currency.
##   2. Otherwise upgrade the lowest-level tower we can afford.
##   3. Start the next wave — but hold while we can still afford to fill an empty
##      slot, so the showcase deploys all tower types before rushing ahead. The
##      first wave always starts (otherwise the run never begins / earns money).
func _act() -> void:
	var did_build := _try_build_for_variety()
	if not did_build:
		_try_upgrade_weakest()
	if _game.can_start_wave() and (_game.wave == 0 or not _can_still_build()):
		_game.start_next_wave()

## True if there's a free slot AND we can afford the cheapest tower for it — i.e.
## the demo still has build work to do before it should rush the next wave.
func _can_still_build() -> bool:
	if _game.free_slots().is_empty():
		return false
	var cheapest := 1 << 30
	for type in TDTower.TYPES.keys():
		cheapest = mini(cheapest, TDTower.TYPES[type]["base_cost"])
	return _game.currency >= cheapest

## Build the under-represented type on the next free slot. Returns true if it built.
func _try_build_for_variety() -> bool:
	var slots: Array = _game.free_slots()
	if slots.is_empty():
		return false
	var type: int = next_variety_type(_type_counts())
	return _game.try_build(slots[0], type)

## Upgrade the lowest-level (cheapest-to-improve) built tower we can afford.
func _try_upgrade_weakest() -> bool:
	var best = null
	var best_level := TDTower.MAX_LEVEL + 1
	for t in _game.built_towers():
		if not is_instance_valid(t) or t.is_max_level():
			continue
		if t.level < best_level:
			best_level = t.level
			best = t
	if best == null:
		return false
	return _game.try_upgrade(best)

## Count built towers by type.
func _type_counts() -> Dictionary:
	var counts := {}
	for type in TDTower.TYPES.keys():
		counts[type] = 0
	for t in _game.built_towers():
		if is_instance_valid(t):
			counts[t.tower_type] = counts.get(t.tower_type, 0) + 1
	return counts

## Pick the next type to build for maximum variety: the least-built type, ties
## broken by enum order. Pure function (takes counts) so it's unit-testable.
static func next_variety_type(counts: Dictionary) -> int:
	var best_type: int = TDTower.TYPES.keys()[0]
	var best_count := 1 << 30
	for type in TDTower.TYPES.keys():
		var c: int = counts.get(type, 0)
		if c < best_count:
			best_count = c
			best_type = type
	return best_type
