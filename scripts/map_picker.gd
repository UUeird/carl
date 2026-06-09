extends Control
class_name MapPicker

## Full-screen map selection screen shown at launch and when returning from a map.
## To add a new map: append one entry to MAPS. Nothing else to change.

const MAPS := [
	{ "name": "Main Map",  "scene": "res://scenes/td_main.tscn" },
	{ "name": "Test Map",  "scene": "res://scenes/td_test_map.tscn" },
]

func _ready() -> void:
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.custom_minimum_size = Vector2(320, 0)
	add_child(vbox)

	var title := Label.new()
	title.text = "carl"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(0.9, 0.92, 0.96))
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "select a map"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.55, 0.58, 0.65))
	vbox.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 32)
	vbox.add_child(spacer)

	for entry in MAPS:
		var btn := Button.new()
		btn.text = entry["name"]
		btn.custom_minimum_size = Vector2(320, 48)
		btn.add_theme_font_size_override("font_size", 18)
		var scene_path: String = entry["scene"]
		btn.pressed.connect(func(): _load_map(scene_path))
		vbox.add_child(btn)

func _load_map(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)
