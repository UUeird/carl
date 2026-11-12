extends GutTest

## UI restyle (carl-46): the shared UITheme, the in-game HUD wired to the real
## game, and the map picker. Looks are checked headed (VISUAL_CHECKLIST.md);
## these cover what the UI says and does.

const MAIN := preload("res://scenes/td_main.tscn")
const PICKER := preload("res://scenes/map_picker.tscn")
const TOWER := preload("res://scenes/td_tower.tscn")

# --- UITheme -----------------------------------------------------------------
func test_theme_fonts_load_the_bundled_files():
	assert_ne(UITheme.display_font(700), ThemeDB.fallback_font, "Chakra Petch bold should load")
	assert_ne(UITheme.display_font(600), ThemeDB.fallback_font, "Chakra Petch semibold should load")
	assert_true(UITheme.body_font(500) is FontVariation, "Inter should load as a weighted variation")

func test_icon_rasterizes_at_requested_height():
	var tex := UITheme.icon(UITheme.ICON_FIRE, 18)
	assert_not_null(tex)
	assert_eq(tex.get_height(), 18)
	assert_same(UITheme.icon(UITheme.ICON_FIRE, 18), tex, "icons are cached")

func test_every_tower_shape_has_a_build_icon():
	for type in TDTower.TYPES:
		var shape: String = TDTower.TYPES[type].get("shape", "")
		assert_true(UITheme.TOWER_ICONS.has(shape), "no build-bar icon for shape '%s'" % shape)

func test_styled_buttons_meet_touch_target():
	for kind in ["primary", "secondary", "light", "danger", "card"]:
		var b := Button.new()
		UITheme.style_button(b, kind)
		assert_gte(b.custom_minimum_size.y, UITheme.MIN_TOUCH, kind)
		b.free()

# --- HUD ---------------------------------------------------------------------
var game
var hud

func _start_game():
	game = MAIN.instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)
	hud = game.get_node("HUD")

func after_each():
	get_tree().paused = false

func test_hud_stat_bar_shows_lives_gold_and_wave():
	await _start_game()
	assert_eq(hud._lives_value.text, str(game.lives))
	assert_eq(hud._gold_value.text, str(game.currency))
	assert_eq(hud._wave_value.text, "0 / %d" % game.wave_count)
	assert_eq(hud.start_btn.text, "START WAVE 1")
	game.currency += 25
	game.state_changed.emit()
	assert_eq(hud._gold_value.text, str(game.currency), "gold refreshes on state change")

func test_build_bar_has_one_card_per_tower_type_and_selects():
	await _start_game()
	assert_eq(hud._build_buttons.size(), TDTower.TYPES.size())
	var pressed: Array = hud._build_buttons.filter(func(e): return e["btn"].button_pressed)
	assert_eq(pressed.size(), 1, "exactly one build card is selected")
	hud._select_build_type(TDTower.Type.MISSILE)
	for e in hud._build_buttons:
		assert_eq(e["btn"].button_pressed, e["type"] == TDTower.Type.MISSILE)

func _build_and_select(type: int):
	var slot = game.get_node("Slots").get_child(0)
	game.currency = 9999
	assert_true(game.try_build(slot, type), "built a tower")
	game._select_slot(slot)
	return hud._selected_tower

func test_tower_panel_requires_an_element_before_upgrade():
	await _start_game()
	var t = _build_and_select(TDTower.Type.MACHINE_GUN)
	assert_true(hud._panel.visible, "panel opens on select")
	assert_true(hud._damage_type_box.visible, "element picker shows at level 1")
	assert_true(hud._upgrade_btn.disabled)
	assert_eq(hud._upgrade_btn.text, "Choose an element")
	assert_eq(hud._sell_btn.text, "Sell · %d" % t.sell_value())
	# Pick Fire through the panel's own button.
	var fire = hud._dt_buttons.filter(func(e): return e["dt"] == TDTower.DamageType.FIRE)[0]
	fire["btn"].pressed.emit()
	assert_eq(t.damage_type, TDTower.DamageType.FIRE)
	assert_false(hud._damage_type_box.visible, "picker hides once chosen")
	assert_false(hud._upgrade_btn.disabled)
	assert_eq(hud._upgrade_btn.text, "Upgrade · %d" % t.upgrade_cost())

func test_panel_stats_match_tower_kind():
	await _start_game()
	var mg = TOWER.instantiate(); game.add_child(mg); mg.configure(TDTower.Type.MACHINE_GUN)
	var beam = TOWER.instantiate(); game.add_child(beam); beam.configure(TDTower.Type.BEAM)
	var missile = TOWER.instantiate(); game.add_child(missile); missile.configure(TDTower.Type.MISSILE)
	var captions := func(t): return hud.panel_stats(t).map(func(p): return p[0])
	assert_eq(captions.call(mg), ["Damage", "Rate", "Range", "HP"])
	assert_eq(captions.call(beam), ["DPS", "Targets", "Range", "HP"])
	assert_true("Blast" in captions.call(missile), "missile shows its blast radius")
	var rate: String = hud.panel_stats(mg)[1][1]
	assert_eq(rate, "4.5/s", "rate is shots per second from the cooldown")
	mg.set_damage_type(TDTower.DamageType.SHOCK)
	assert_true(["Element", "Shock"] in hud.panel_stats(mg), "chosen element is listed")

func test_pause_button_toggles_tree_pause():
	await _start_game()
	hud.toggle_pause()
	assert_true(get_tree().paused)
	assert_eq(hud.message.text, "Paused")
	assert_eq(hud.process_mode, Node.PROCESS_MODE_ALWAYS, "HUD stays live to unpause")
	hud.toggle_pause()
	assert_false(get_tree().paused)

# --- Map picker ----------------------------------------------------------------
func test_map_picker_has_a_card_per_map_and_every_scene_exists():
	var picker = PICKER.instantiate()
	add_child_autofree(picker)
	await wait_process_frames(1)
	assert_eq(picker.cards.size(), MapPicker.MAPS.size())
	for entry in MapPicker.MAPS:
		assert_true(ResourceLoader.exists(entry["scene"]), "missing scene %s" % entry["scene"])
		for key in ["name", "tag", "desc", "thumb"]:
			assert_true(entry.has(key), "%s lacks '%s'" % [entry.get("name", "?"), key])
		assert_not_null(UITheme.icon(entry["thumb"], 64), "%s thumbnail renders" % entry["name"])
