extends Area3D

## When the player enters the boss arena, wake the boss and (optionally) seal the
## entrance behind them so the fight is committed.

@export var boss_path: NodePath
@export var seal_door_path: NodePath
@export var seal_rise: float = 4.0

var _fired: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if _fired or not body.is_in_group("player"):
		return
	_fired = true
	var boss := get_node_or_null(boss_path)
	if boss and boss.has_method("activate"):
		boss.activate()
	var door := get_node_or_null(seal_door_path)
	if door:
		var tw := create_tween()
		tw.tween_property(door, "position:y", door.position.y + seal_rise, 0.4)
