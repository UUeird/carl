extends Node
class_name Health

## Reusable health component. Attach as a child node to any damageable entity
## (player, boss, dummy). Other systems talk to it via take_damage() and the
## signals below — they never touch hp directly.

signal health_changed(current: float, maximum: float)
signal died

@export var max_health: float = 100.0

var current_health: float

func _ready() -> void:
	current_health = max_health
	# Defer so listeners connected after _ready (e.g. HUD) still get an initial value.
	health_changed.emit.call_deferred(current_health, max_health)

func take_damage(amount: float) -> void:
	if current_health <= 0.0:
		return
	current_health = max(current_health - amount, 0.0)
	health_changed.emit(current_health, max_health)
	if current_health <= 0.0:
		died.emit()

func heal(amount: float) -> void:
	if current_health <= 0.0:
		return
	current_health = min(current_health + amount, max_health)
	health_changed.emit(current_health, max_health)

func is_alive() -> bool:
	return current_health > 0.0
