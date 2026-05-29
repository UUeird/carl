extends Area3D

## Updates the player's respawn point when entered. Place these at the start of
## each arena / after tricky platforming so a pit fall doesn't send you far back.

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player") and body.has_signal("checkpoint_reached"):
		# Respawn slightly above the checkpoint's floor position.
		body.checkpoint_reached.emit(global_position + Vector3.UP * 1.5)
