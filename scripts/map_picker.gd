extends Control
class_name MapPicker

## Full-screen map selection screen shown at launch and when returning from a map.
## Layout follows the design canvas (carl-43, Screens › Map picker): big title,
## version top-right, one card per map with a thumbnail.
## To add a new map: append one entry to MAPS. Nothing else to change.

const MAPS := [
	{
		"name": "Find Carl: Main Stage", "scene": "res://scenes/cs_main.tscn", "tag": "Proto",
		"desc": "Crowd-surf one song · win fans over on the beat",
		"thumb": '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 260"><rect x="110" y="0" width="180" height="260" fill="#1E1A26"/><rect x="110" y="0" width="180" height="30" fill="#2A2F3A"/><circle cx="150" cy="80" r="9" fill="#C85A7C"/><circle cx="230" cy="110" r="9" fill="#4F7BD9"/><circle cx="190" cy="150" r="9" fill="#FF5FA2"/><circle cx="250" cy="60" r="12" fill="#8E3FD1"/><circle cx="160" cy="170" r="9" fill="#FF8A3D"/><rect x="190" y="205" width="14" height="22" fill="#F2F4F7"/></svg>',
	},
]
const THUMB_HEIGHT := 260   ## raster height of the thumbnail SVGs
const THUMB_BG := Color("#191D23")

var cards: Array = []   ## one Button per MAPS entry, in order

func _ready() -> void:
	theme = UITheme.theme()
	var bg := ColorRect.new()
	bg.color = UITheme.TABLE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 80)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 56)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 40)
	margin.add_child(page)

	# Header: title + subtitle on the left, version on the right.
	var header := HBoxContainer.new()
	page.add_child(header)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 4)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	titles.add_child(UITheme.label("carl", 80, UITheme.TEXT, UITheme.display_font(700)))
	titles.add_child(UITheme.label("Select a map", 17, UITheme.MUTED))
	var version := UITheme.label("v" + str(ProjectSettings.get_setting("application/config/version", "dev")), 12, UITheme.FAINT)
	version.size_flags_vertical = Control.SIZE_SHRINK_END
	header.add_child(version)

	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 24)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(grid)
	for entry in MAPS:
		var card := _make_card(entry)
		grid.add_child(card)
		cards.append(card)

func _make_card(entry: Dictionary) -> Button:
	var featured: bool = entry["tag"] == "Play"
	var b := Button.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.tooltip_text = "Play %s" % entry["name"]
	var edge := UITheme.ACCENT if featured else UITheme.BORDER
	var normal := UITheme.box(UITheme.PANEL, edge, 2 if featured else 1, 14, 0, 0)
	var hover := UITheme.box(UITheme.SELECTED, UITheme.ACCENT if featured else UITheme.MUTED, 2 if featured else 1, 14, 0, 0)
	for state in ["normal", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, normal)
	for state in ["hover", "pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(state, hover)

	# Inset by the border width so the thumbnail doesn't paint over the card edge.
	var inset := 2 if featured else 1
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = inset
	v.offset_top = inset
	v.offset_right = -inset
	v.offset_bottom = -inset
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	# Thumbnail well: darker, top corners rounded to sit inside the card; it
	# grows with the card so the row fills the screen height.
	var well := PanelContainer.new()
	var well_box := UITheme.box(THUMB_BG, Color.TRANSPARENT, 0, 0, 8, 8)
	well_box.corner_radius_top_left = 13 - inset
	well_box.corner_radius_top_right = 13 - inset
	well.add_theme_stylebox_override("panel", well_box)
	well.size_flags_vertical = Control.SIZE_EXPAND_FILL
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(well)
	var thumb := TextureRect.new()
	thumb.texture = UITheme.icon(entry["thumb"], THUMB_HEIGHT)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.custom_minimum_size = Vector2(0, THUMB_HEIGHT * 0.75)
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.add_child(thumb)

	var body := MarginContainer.new()
	for side in ["left", "right"]:
		body.add_theme_constant_override("margin_" + side, 22)
	for side in ["top", "bottom"]:
		body.add_theme_constant_override("margin_" + side, 18)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(body)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 6)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(text)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(row)
	var name_l := UITheme.label(entry["name"], 24, UITheme.TEXT, UITheme.display_font(700))
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_l)
	var tag := UITheme.label(entry["tag"], 13, UITheme.ACCENT if featured else UITheme.MUTED)
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(tag)
	var desc := UITheme.label(entry["desc"], 13, UITheme.MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(desc)

	var scene_path: String = entry["scene"]
	b.pressed.connect(func(): _load_map(scene_path))
	return b

func _load_map(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)
