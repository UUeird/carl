extends Area3D
class_name TowerSlot

## A buildable spot beside the path. Click it to build a tower (the game
## controller handles cost/affordability and actually spawning the tower).
## Highlights on hover; goes dim/occupied once built.

signal clicked(slot: TowerSlot)
signal hovered(slot: TowerSlot)
signal unhovered(slot: TowerSlot)

@onready var mesh: MeshInstance3D = $Mesh

var occupied: bool = false
var _material: StandardMaterial3D
const COLOR_FREE  := Color(0.62, 0.64, 0.68, 0.90)   # light grey — available
const COLOR_HOVER := Color(0.85, 0.87, 0.92, 0.97)   # near-white on hover
const COLOR_TAKEN := Color(0.22, 0.23, 0.26, 0.50)   # dim grey — occupied

func _ready() -> void:
	input_event.connect(_on_input_event)
	mouse_entered.connect(_on_hover)
	mouse_exited.connect(_on_unhover)
	_material = StandardMaterial3D.new()
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = COLOR_FREE
	mesh.material_override = _material

func _on_input_event(_cam, event: InputEvent, _pos, _normal, _idx) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(self)
		# Mark handled so the game controller's empty-click dismiss doesn't also fire.
		get_viewport().set_input_as_handled()

func _on_hover() -> void:
	if not occupied:
		_material.albedo_color = COLOR_HOVER
	hovered.emit(self)

func _on_unhover() -> void:
	if not occupied:
		_material.albedo_color = COLOR_FREE
	unhovered.emit(self)

func set_occupied() -> void:
	occupied = true
	_material.albedo_color = COLOR_TAKEN

func set_free() -> void:
	occupied = false
	_material.albedo_color = COLOR_FREE
