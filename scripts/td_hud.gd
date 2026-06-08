extends CanvasLayer

## TD HUD: lives / currency / wave, build-type buttons, a Start-wave button, a
## per-tower panel (Upgrade / Sell), and messages. Reacts to controller signals;
## the build buttons and panel are created in code since the panel is dynamic.

@export var game_path: NodePath

@onready var root: Control = $Root
@onready var stats: Label = $Root/Stats
@onready var message: Label = $Root/Message
@onready var start_btn: Button = $Root/StartBtn
@onready var hint: Label = $Root/Hint

var _game
var _build_buttons: Array = []
var _panel: PanelContainer
var _panel_title: Label
var _panel_stats: Label
var _upgrade_btn: Button
var _sell_btn: Button
var _selected_tower = null
var _game_over: bool = false   ## once over, panel is view-only (no upgrade/sell)

func _ready() -> void:
	_game = get_node_or_null(game_path)
	if _game == null:
		return
	_game.state_changed.connect(_refresh)
	_game.message.connect(_on_message)
	_game.game_over.connect(_on_game_over)
	_game.tower_selected.connect(_on_tower_selected)
	_game.selection_cleared.connect(func(): _hide_panel())
	start_btn.pressed.connect(func(): _game.start_next_wave())
	hint.text = "Pick a tower, click a green slot to build. Click a built tower to upgrade or sell."
	# Panel before type buttons: selecting the initial type clears selection,
	# which touches the panel.
	_build_panel()
	_build_type_buttons()
	_build_demo_button()
	_refresh()

# Debug-only "Demo" button: kicks off the autoplay driver. Hidden in release
# builds (where _game.demo_available() is false), so players never see it.
func _build_demo_button() -> void:
	if not _game.demo_available():
		return
	var b := Button.new()
	b.text = "Demo ▶"
	# Right-anchored, on the same row as Start-wave but to its left, so it clears
	# the tower details panel (which opens at the top-right, under Start-wave).
	b.anchor_left = 1.0
	b.anchor_right = 1.0
	b.offset_left = -390.0
	b.offset_right = -210.0
	b.offset_top = 16.0
	b.offset_bottom = 54.0
	b.pressed.connect(func():
		_game.start_demo()
		b.disabled = true
		b.text = "Demo running…")
	root.add_child(b)

func _build_type_buttons() -> void:
	var box := HBoxContainer.new()
	box.position = Vector2(20, 78)
	box.add_theme_constant_override("separation", 8)
	root.add_child(box)
	# Pull types/costs straight from the tower's TYPES table.
	for type in TDTower.TYPES.keys():
		var info: Dictionary = TDTower.TYPES[type]
		var b := Button.new()
		b.toggle_mode = true
		b.text = "%s — %d" % [info["name"], info["base_cost"]]
		b.focus_mode = Control.FOCUS_NONE   # don't let focus outline muddy the selected look
		_style_type_button(b, info["color"])
		b.pressed.connect(func(): _select_build_type(type))
		box.add_child(b)
		_build_buttons.append({ "btn": b, "type": type })
	_select_build_type(TDTower.TYPES.keys()[0])

# Theme one build button in its tower's identity color. We override every state's
# StyleBox so the SELECTED (pressed) look is unmistakable — a bright fill in the
# tower color with a thick light border — while the idle/hover looks stay muted
# with just a thin colored accent. _refresh_type_button_text() adds a ► marker.
func _style_type_button(b: Button, color: Color) -> void:
	var idle := StyleBoxFlat.new()
	idle.bg_color = Color(0.13, 0.14, 0.17, 0.92)
	idle.set_border_width_all(2)
	idle.border_color = Color(color.r, color.g, color.b, 0.55)
	idle.set_corner_radius_all(5)
	idle.content_margin_left = 12
	idle.content_margin_right = 12
	idle.content_margin_top = 6
	idle.content_margin_bottom = 6

	var hover := idle.duplicate()
	hover.bg_color = Color(0.2, 0.21, 0.25, 0.95)
	hover.border_color = Color(color.r, color.g, color.b, 0.85)

	# Selected = pressed state: fill with the tower color, bright thick border.
	var selected := idle.duplicate()
	selected.bg_color = Color(color.r, color.g, color.b, 0.92)
	selected.set_border_width_all(3)
	selected.border_color = Color(1, 1, 1, 0.9)

	b.add_theme_stylebox_override("normal", idle)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("focus", idle)
	b.add_theme_stylebox_override("pressed", selected)
	# Toggled-on uses the same styleboxes as pressed/hover-pressed.
	b.add_theme_stylebox_override("hover_pressed", selected)
	# Dark text reads better on the bright selected fill; light text otherwise.
	b.add_theme_color_override("font_pressed_color", Color(0.05, 0.05, 0.07))
	b.add_theme_color_override("font_hover_pressed_color", Color(0.05, 0.05, 0.07))

func _select_build_type(type) -> void:
	_game.set_build_type(type)
	for entry in _build_buttons:
		entry["btn"].button_pressed = entry["type"] == type

func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -240
	_panel.offset_top = 70
	_panel.offset_right = -20
	root.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_panel.add_child(v)
	_panel_title = Label.new()
	_panel_title.add_theme_font_size_override("font_size", 18)
	v.add_child(_panel_title)
	_panel_stats = Label.new()
	v.add_child(_panel_stats)
	_upgrade_btn = Button.new()
	_upgrade_btn.pressed.connect(func(): _game.upgrade_selected())
	v.add_child(_upgrade_btn)
	_sell_btn = Button.new()
	_sell_btn.pressed.connect(func(): _game.sell_selected())
	v.add_child(_sell_btn)

func _on_tower_selected(tower) -> void:
	_selected_tower = tower
	_panel.visible = true
	_refresh_panel()

func _hide_panel() -> void:
	_selected_tower = null
	if _panel:
		_panel.visible = false

func _refresh_panel() -> void:
	var t = _selected_tower
	if t == null or not is_instance_valid(t):
		_hide_panel()
		return
	var s: Dictionary = t._stats()
	_panel_title.text = "%s  ·  Lv %d/%d" % [t.type_name(), t.level, TDTower.MAX_LEVEL]
	var line: String
	if s.get("beam", false):
		line = "DPS %s   RNG %s" % [str(s["dps"]), str(s["range"])]
	else:
		line = "DMG %s   RNG %s   CD %ss" % [str(s["damage"]), str(s["range"]), str(s["cooldown"])]
	if "slow" in s:
		line += "\nSlow ×%s for %ss" % [str(s["slow"]), str(s["slow_dur"])]
	if "aoe" in s:
		line += "\nAoE radius %s" % str(s["aoe"])
	line += "\nHP %d/%d" % [int(ceil(t.health)), int(TDTower.MAX_HEALTH)]
	_panel_stats.text = line
	if _game_over:
		# View-only after the game ends: stats/health still show, actions are off.
		_upgrade_btn.text = "Game over"
		_upgrade_btn.disabled = true
		_sell_btn.text = "Sell: +%d" % t.sell_value()
		_sell_btn.disabled = true
		return
	if t.is_max_level():
		_upgrade_btn.text = "Max level"
		_upgrade_btn.disabled = true
	else:
		_upgrade_btn.text = "Upgrade: %d" % t.upgrade_cost()
		_upgrade_btn.disabled = false
	_sell_btn.text = "Sell: +%d" % t.sell_value()
	_sell_btn.disabled = false

func _refresh() -> void:
	stats.text = "♥ %d    ⬢ %d    Wave %d/%d" % [_game.lives, _game.currency, _game.wave, _game.wave_count]
	start_btn.text = "Start wave %d  ▶" % (_game.wave + 1)
	start_btn.disabled = not _game.can_start_wave()
	# Keep the panel's affordability/level state fresh after currency changes.
	if _panel and _panel.visible:
		_refresh_panel()

func _on_message(text: String) -> void:
	message.text = text

func _on_game_over(_victory: bool) -> void:
	start_btn.disabled = true
	_game_over = true
	# Keep the panel usable for inspection, but reflect that actions are blocked.
	if _panel and _panel.visible:
		_refresh_panel()
