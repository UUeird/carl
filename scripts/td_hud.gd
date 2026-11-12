extends CanvasLayer

## TD HUD, "Tabletop War Room" layout (design canvas carl-43, Screens › In-game HUD):
##   top-left   Lives / Gold / Wave stat panel, with the hint under it
##   top-right  Reset · Maps · Pause · START WAVE N (plus debug-only buttons)
##   right      tower panel: stats grid, element picker, Upgrade · Sell
##   bottom     build bar: one card per tower type, with its cost
## Everything is built in code from UITheme; the scenes only provide HUD/Root.

const DT := TDTower.DamageType
## Element picker order: [damage type, UITheme element key, label].
const ELEMENT_CHOICES := [
	[DT.FIRE,   "fire",   "Fire"],
	[DT.POISON, "poison", "Poison"],
	[DT.SHOCK,  "shock",  "Shock"],
]
const HINT := "Pick a tower below, then click a green slot to build. Click a built tower to upgrade or sell."

@export var game_path: NodePath

@onready var root: Control = $Root

var _game
# Top bar
var _lives_value: Label
var _gold_value: Label
var _wave_value: Label
var _hint: Label
var start_btn: Button
var _pause_btn: Button
# Bottom
var _build_buttons: Array = []   ## {btn, type}
var message: Label
var _version_label: Label
# Tower panel
var _panel: PanelContainer
var _panel_title: Label
var _panel_level: Label
var _panel_stats: GridContainer
var _damage_type_box: VBoxContainer   ## shown at level 1 to pick damage branch
var _dt_buttons: Array = []           ## {btn, dt, element}
var _upgrade_btn: Button
var _sell_btn: Button
var _selected_tower = null
var _game_over: bool = false   ## once over, panel is view-only (no upgrade/sell)

func _ready() -> void:
	# The HUD keeps running while the tree is paused so Pause can be undone.
	process_mode = Node.PROCESS_MODE_ALWAYS
	root.theme = UITheme.theme()
	_game = get_node_or_null(game_path)
	if _game == null:
		return
	_game.state_changed.connect(_refresh)
	_game.message.connect(_on_message)
	_game.game_over.connect(_on_game_over)
	_game.tower_selected.connect(_on_tower_selected)
	_game.selection_cleared.connect(func(): _hide_panel())
	_build_stat_bar()
	_build_actions()
	# Panel before the build bar: selecting the initial type clears selection,
	# which touches the panel.
	_build_panel()
	_build_build_bar()
	_build_footer()
	_refresh()

# --- Top-left: Lives / Gold / Wave ----------------------------------------
func _build_stat_bar() -> void:
	var col := VBoxContainer.new()
	col.position = Vector2(20, 16)
	col.add_theme_constant_override("separation", 8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(col)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.panel_box(10, 6))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN   # don't stretch to the hint's width
	col.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	panel.add_child(row)
	_lives_value = _stat_block(row, "Lives", UITheme.LIVES)
	_stat_divider(row)
	_gold_value = _stat_block(row, "Gold", UITheme.GOLD)
	_stat_divider(row)
	_wave_value = _stat_block(row, "Wave", UITheme.TEXT)

	_hint = UITheme.label(HINT, 12, UITheme.FAINT)
	col.add_child(_hint)

func _stat_block(parent: Control, caption: String, color: Color) -> Label:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 14)
	m.add_theme_constant_override("margin_right", 14)
	parent.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	m.add_child(v)
	v.add_child(UITheme.caption(caption))
	var value := UITheme.label("", 24, color, UITheme.display_font(700))
	v.add_child(value)
	return value

func _stat_divider(parent: Control) -> void:
	var line := ColorRect.new()
	line.color = UITheme.BORDER
	line.custom_minimum_size = Vector2(1, 0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)

# --- Top-right: actions ----------------------------------------------------
func _build_actions() -> void:
	var row := HBoxContainer.new()
	row.anchor_left = 1.0
	row.anchor_right = 1.0
	row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	row.offset_left = -20.0
	row.offset_right = -20.0
	row.offset_top = 16.0
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 8)
	root.add_child(row)

	# Debug-only helpers first (leftmost), so the player-facing cluster stays put.
	if OS.is_debug_build():
		var gold := _action_button(row, "+500 gold")
		gold.pressed.connect(func(): _game.cheat_add_gold())
	if _game.demo_available():
		var demo := _action_button(row, "Demo ▶")
		demo.pressed.connect(func():
			_game.start_demo()
			demo.disabled = true
			demo.text = "Demo running…")
	var reset := _action_button(row, "Reset")
	reset.pressed.connect(func():
		get_tree().paused = false
		get_tree().reload_current_scene())
	var maps := _action_button(row, "Maps")
	maps.pressed.connect(func():
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/map_picker.tscn"))

	_pause_btn = _action_button(row, "")
	_pause_btn.custom_minimum_size = Vector2(UITheme.MIN_TOUCH, UITheme.MIN_TOUCH)
	_pause_btn.icon = UITheme.icon(UITheme.ICON_PAUSE, 18)
	_pause_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_btn.tooltip_text = "Pause"
	_pause_btn.pressed.connect(toggle_pause)

	start_btn = Button.new()
	UITheme.style_button(start_btn, "primary")
	start_btn.pressed.connect(func(): _game.start_next_wave())
	row.add_child(start_btn)

func _action_button(parent: Control, text: String) -> Button:
	var b := Button.new()
	b.text = text
	UITheme.style_button(b, "secondary")
	parent.add_child(b)
	return b

func toggle_pause() -> void:
	var paused := not get_tree().paused
	get_tree().paused = paused
	_pause_btn.icon = UITheme.icon(UITheme.ICON_PLAY if paused else UITheme.ICON_PAUSE, 18)
	_pause_btn.tooltip_text = "Resume" if paused else "Pause"
	message.text = "Paused" if paused else ""

# --- Bottom: build bar -----------------------------------------------------
func _build_build_bar() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.panel_box(14, 8))
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_bottom = -16.0
	root.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	# Pull types/costs straight from the tower's TYPES table.
	for type in TDTower.TYPES.keys():
		var info: Dictionary = TDTower.TYPES[type]
		var b := _build_card(info)
		b.pressed.connect(func(): _select_build_type(type))
		row.add_child(b)
		_build_buttons.append({ "btn": b, "type": type })
	_select_build_type(TDTower.TYPES.keys()[0])

func _build_card(info: Dictionary) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(108, 84)
	UITheme.style_button(b, "card")
	b.tooltip_text = "%s — %d gold" % [info["name"], info["base_cost"]]
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 3)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var icon := TextureRect.new()
	icon.texture = UITheme.icon(UITheme.TOWER_ICONS.get(info.get("shape", ""), UITheme.ICON_MACHINE_GUN), 26)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.modulate = UITheme.TEXT
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(icon)
	var name_l := UITheme.label(info["name"], 13, UITheme.TEXT, UITheme.body_font(600))
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name_l)
	var cost := UITheme.label(str(info["base_cost"]), 12, UITheme.GOLD, UITheme.body_font(600))
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cost)
	return b

func _select_build_type(type) -> void:
	_game.set_build_type(type)
	for entry in _build_buttons:
		entry["btn"].button_pressed = entry["type"] == type

# --- Footer: message + version ---------------------------------------------
func _build_footer() -> void:
	message = UITheme.label("", 16, UITheme.TEXT, UITheme.body_font(600))
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.anchor_left = 0.5
	message.anchor_right = 0.5
	message.anchor_top = 1.0
	message.anchor_bottom = 1.0
	message.offset_left = -300.0
	message.offset_right = 300.0
	message.offset_top = -148.0
	message.offset_bottom = -124.0
	root.add_child(message)

	_version_label = UITheme.label("v" + str(ProjectSettings.get_setting("application/config/version", "dev")), 11, UITheme.FAINT)
	_version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_version_label.anchor_left = 1.0
	_version_label.anchor_right = 1.0
	_version_label.anchor_top = 1.0
	_version_label.anchor_bottom = 1.0
	_version_label.offset_left = -200.0
	_version_label.offset_right = -12.0
	_version_label.offset_top = -26.0
	_version_label.offset_bottom = -8.0
	root.add_child(_version_label)

# --- Right: tower panel ----------------------------------------------------
func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.add_theme_stylebox_override("panel", UITheme.panel_box(12, 16))
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -300.0
	_panel.offset_right = -20.0
	_panel.offset_top = 84.0
	root.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_panel.add_child(v)

	var title_row := HBoxContainer.new()
	v.add_child(title_row)
	_panel_title = UITheme.label("", 19, UITheme.TEXT, UITheme.display_font(700))
	_panel_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(_panel_title)
	_panel_level = UITheme.label("", 12, UITheme.MUTED)
	_panel_level.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(_panel_level)

	_panel_stats = GridContainer.new()
	_panel_stats.columns = 3
	_panel_stats.add_theme_constant_override("h_separation", 8)
	_panel_stats.add_theme_constant_override("v_separation", 8)
	v.add_child(_panel_stats)

	# Element picker — shown at level 1 so the player picks their branch
	# before the first upgrade. Hidden otherwise.
	_damage_type_box = VBoxContainer.new()
	_damage_type_box.add_theme_constant_override("separation", 8)
	v.add_child(_damage_type_box)
	_damage_type_box.add_child(UITheme.caption("Choose element (permanent)", 11))
	var dt_grid := GridContainer.new()
	dt_grid.columns = 3
	dt_grid.add_theme_constant_override("h_separation", 8)
	_damage_type_box.add_child(dt_grid)
	for entry in ELEMENT_CHOICES:
		var dt: int = entry[0]
		var element: String = entry[1]
		var b := Button.new()
		b.text = entry[2]
		b.icon = UITheme.icon(UITheme.ELEMENT_ICONS[element], 18)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UITheme.style_element_button(b, element, false)
		b.pressed.connect(func():
			if _selected_tower and is_instance_valid(_selected_tower):
				_selected_tower.set_damage_type(dt)
				_refresh_panel())
		dt_grid.add_child(b)
		_dt_buttons.append({ "btn": b, "dt": dt, "element": element })
	_damage_type_box.visible = false

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	v.add_child(actions)
	_upgrade_btn = Button.new()
	_upgrade_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_button(_upgrade_btn, "light")
	_upgrade_btn.pressed.connect(func(): _game.upgrade_selected())
	actions.add_child(_upgrade_btn)
	_sell_btn = Button.new()
	UITheme.style_button(_sell_btn, "danger")
	_sell_btn.pressed.connect(func(): _game.sell_selected())
	actions.add_child(_sell_btn)

func _on_tower_selected(tower) -> void:
	_selected_tower = tower
	_panel.visible = true
	_refresh_panel()

func _hide_panel() -> void:
	_selected_tower = null
	if _panel:
		_panel.visible = false

## [caption, value] pairs for the stats grid, from the tower's current tier.
static func panel_stats(t) -> Array:
	var s: Dictionary = t._stats()
	var out: Array = []
	if s.get("beam", false):
		out.append(["DPS", _num(s["dps"])])
		out.append(["Targets", str(s.get("max_targets", 1))])
	else:
		out.append(["Damage", _num(s["damage"])])
		out.append(["Rate", "%s/s" % _num(1.0 / float(s["cooldown"]))])
	out.append(["Range", "%.1f" % float(s["range"])])
	out.append(["HP", "%d/%d" % [int(ceil(t.health)), int(TDTower.MAX_HEALTH)]])
	if "aoe" in s:
		out.append(["Blast", "%.1f" % float(s["aoe"])])
	if t.damage_type != DT.PHYSICAL:
		out.append(["Element", t.damage_type_name()])
	return out

static func _num(x: float) -> String:
	return str(int(x)) if is_equal_approx(x, round(x)) else "%.1f" % x

func _refresh_panel() -> void:
	var t = _selected_tower
	if t == null or not is_instance_valid(t):
		_hide_panel()
		return
	_panel_title.text = t.type_name()
	_panel_level.text = "Lv %d / %d" % [t.level, TDTower.MAX_LEVEL]
	for c in _panel_stats.get_children():
		_panel_stats.remove_child(c)
		c.free()   # already detached; free now so cells never linger as orphans
	for pair in panel_stats(t):
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", 0)
		cell.add_child(UITheme.label(pair[0], 11, UITheme.MUTED))
		cell.add_child(UITheme.label(pair[1], 15, UITheme.TEXT, UITheme.body_font(600)))
		_panel_stats.add_child(cell)

	# Show the element picker only at level 1 (before choosing a branch).
	var picking: bool = t.needs_damage_type() and not _game_over
	_damage_type_box.visible = picking
	for entry in _dt_buttons:
		UITheme.style_element_button(entry["btn"], entry["element"], t.damage_type == entry["dt"])

	_sell_btn.text = "Sell · %d" % t.sell_value()
	if _game_over:
		_upgrade_btn.text = "Game over"
		_upgrade_btn.disabled = true
		_sell_btn.disabled = true
		return
	if picking:
		_upgrade_btn.text = "Choose an element"
		_upgrade_btn.disabled = true
	elif t.is_max_level():
		_upgrade_btn.text = "Max level"
		_upgrade_btn.disabled = true
	else:
		_upgrade_btn.text = "Upgrade · %d" % t.upgrade_cost()
		_upgrade_btn.disabled = false
	_sell_btn.disabled = false

# --- State -----------------------------------------------------------------
func _refresh() -> void:
	_lives_value.text = str(_game.lives)
	_gold_value.text = str(_game.currency)
	_wave_value.text = "%d / %d" % [_game.wave, _game.wave_count]
	start_btn.text = ("Start wave %d" % (_game.wave + 1)).to_upper()
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
