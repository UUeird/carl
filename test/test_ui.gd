extends GutTest

## The shared UITheme and the map picker. Looks are checked headed
## (VISUAL_CHECKLIST.md); these cover what the UI says and does.

const PICKER := preload("res://scenes/map_picker.tscn")

# --- UITheme -----------------------------------------------------------------
func test_theme_fonts_load_the_bundled_files():
	assert_ne(UITheme.display_font(700), ThemeDB.fallback_font, "Chakra Petch bold should load")
	assert_ne(UITheme.display_font(600), ThemeDB.fallback_font, "Chakra Petch semibold should load")
	assert_true(UITheme.body_font(500) is FontVariation, "Inter should load as a weighted variation")

func test_icon_rasterizes_at_requested_height():
	var tex := UITheme.icon(UITheme.ICON_PLAY, 18)
	assert_not_null(tex)
	assert_eq(tex.get_height(), 18)
	assert_same(UITheme.icon(UITheme.ICON_PLAY, 18), tex, "icons are cached")

func test_styled_buttons_meet_touch_target():
	for kind in ["primary", "secondary", "light", "danger", "card"]:
		var b := Button.new()
		UITheme.style_button(b, kind)
		assert_gte(b.custom_minimum_size.y, UITheme.MIN_TOUCH, kind)
		b.free()

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
