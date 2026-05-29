extends Area3D

## Puzzle feasibility probe: when a body steps on the plate, open the linked door.
## Proves signal-driven puzzle wiring fits the 3D-iso scene. Prototype keeps the
## door open once triggered (no re-close) for simplicity.

@export var door_path: NodePath
@export var open_height: float = 4.0
@export var open_time: float = 0.6

@onready var mesh: MeshInstance3D = $Mesh

var _triggered: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(_body: Node) -> void:
	if _triggered:
		return
	_triggered = true
	_press_feedback()
	_open_door()

func _press_feedback() -> void:
	if mesh:
		var tw := create_tween()
		tw.tween_property(mesh, "position:y", mesh.position.y - 0.1, 0.1)

func _open_door() -> void:
	var door := get_node_or_null(door_path)
	if door == null:
		push_warning("PressurePlate: door_path not set or invalid.")
		return
	var tw := create_tween()
	tw.tween_property(door, "position:y", door.position.y + open_height, open_time) \
		.set_trans(Tween.TRANS_CUBIC)
