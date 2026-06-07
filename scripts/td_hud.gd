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
	_refresh()

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
		b.pressed.connect(func(): _select_build_type(type))
		box.add_child(b)
		_build_buttons.append({ "btn": b, "type": type })
	_select_build_type(TDTower.TYPES.keys()[0])

func _select_build_type(type) -> void:
	_game.set_build_type(type)
	for entry in _build_buttons:
		entry["btn"].button_pressed = (entry["type"] == type)

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
	_panel_stats.text = line
	if t.is_max_level():
		_upgrade_btn.text = "Max level"
		_upgrade_btn.disabled = true
	else:
		_upgrade_btn.text = "Upgrade — %d" % t.upgrade_cost()
		_upgrade_btn.disabled = false
	_sell_btn.text = "Sell — +%d" % t.sell_value()

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
