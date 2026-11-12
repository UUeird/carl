extends RefCounted
class_name UITheme

## "Tabletop War Room" UI look (design canvas, carl-43): a quiet slate panel UI
## where saturation is saved for what matters in combat. Every UI color, font,
## panel and button style lives here so the HUD and screens read from one place.

# --- Palette ---------------------------------------------------------------
const TABLE := Color("#14171C")          ## screen background
const PANEL := Color("#1B1F26")          ## solid panel / idle card fill
const PANEL_GLASS := Color(0.078, 0.09, 0.11, 0.90)  ## HUD panels over the map
const BORDER := Color("#2C323C")         ## panel edge
const BORDER_STRONG := Color("#3A414D")  ## button edge
const SELECTED := Color("#283039")       ## selected card fill
const TEXT := Color("#E6E9EE")
const MUTED := Color("#9AA3B0")          ## captions, secondary text
const FAINT := Color("#7D8794")          ## version string, hints
const ACCENT := Color("#F2CF5B")         ## primary action
const LIVES := Color("#FF7B6E")
const GOLD := Color("#F2CF5B")
const DANGER := Color("#FF9D92")         ## sell

## Element colors: glyph/border, the chosen-button fill, and its label.
const ELEMENTS := {
	"fire":   { "color": Color("#FF8A3D"), "fill": Color("#2A1D14"), "text": Color("#FFB27E") },
	"poison": { "color": Color("#B6F23A"), "fill": Color("#1E2612"), "text": Color("#D4F78A") },
	"shock":  { "color": Color("#6B8DFF"), "fill": Color("#161C2E"), "text": Color("#A9BCFF") },
}

# --- Type ------------------------------------------------------------------
const MIN_TOUCH := 44.0                  ## smallest clickable height/width

const _DISPLAY_FONTS := {
	600: "res://assets/fonts/ChakraPetch-SemiBold.ttf",
	700: "res://assets/fonts/ChakraPetch-Bold.ttf",
}
const _BODY_FONT := "res://assets/fonts/Inter-Variable.ttf"

static var _font_cache: Dictionary = {}
static var _theme: Theme

## Chakra Petch, for headings, numbers in the stat bar, and primary buttons.
static func display_font(weight: int = 700) -> Font:
	var key := "display_%d" % weight
	if not _font_cache.has(key):
		var f: Font = load(_DISPLAY_FONTS.get(weight, _DISPLAY_FONTS[700]))
		_font_cache[key] = f if f else ThemeDB.fallback_font
	return _font_cache[key]

## Inter at a given weight (variable font). `tracking` adds px between glyphs,
## for the small uppercase captions.
static func body_font(weight: int = 500, tracking: int = 0) -> Font:
	var key := "body_%d_%d" % [weight, tracking]
	if not _font_cache.has(key):
		var base: Font = load(_BODY_FONT)
		if base == null:
			_font_cache[key] = ThemeDB.fallback_font
		else:
			var v := FontVariation.new()
			v.base_font = base
			var wght := TextServerManager.get_primary_interface().name_to_tag("wght")
			v.variation_opentype = { wght: weight }
			v.spacing_glyph = tracking
			_font_cache[key] = v
	return _font_cache[key]

## The default theme for a UI root: Inter 500 on slate, secondary buttons.
static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = body_font(500)
	t.default_font_size = 14
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", panel_box())
	_add_button_styles(t, "Button", "secondary")
	_theme = t
	return t

# --- Boxes -----------------------------------------------------------------
static func box(bg: Color, border: Color = Color.TRANSPARENT, border_w: int = 0,
		radius: int = 8, pad_x: float = 12.0, pad_y: float = 8.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad_x
	s.content_margin_right = pad_x
	s.content_margin_top = pad_y
	s.content_margin_bottom = pad_y
	s.anti_aliasing = true
	return s

## Translucent HUD panel over the map.
static func panel_box(radius: int = 12, pad: float = 16.0) -> StyleBoxFlat:
	return box(PANEL_GLASS, BORDER, 1, radius, pad, pad)

# --- Buttons ---------------------------------------------------------------
## Button kinds:
##   primary   — yellow accent fill, dark display text (Start wave)
##   secondary — glass fill, strong border (Maps, Pause, Reset)
##   light     — light fill, dark text (Upgrade)
##   danger    — transparent, red text (Sell)
##   card      — build-bar / map card: panel fill, white border when selected
static func style_button(b: Button, kind: String = "secondary") -> void:
	var states := _button_states(kind)
	for state in states["boxes"]:
		b.add_theme_stylebox_override(state, states["boxes"][state])
	for c in states["colors"]:
		b.add_theme_color_override(c, states["colors"][c])
	if states.has("font"):
		b.add_theme_font_override("font", states["font"])
	b.add_theme_font_size_override("font_size", states.get("size", 14))
	b.custom_minimum_size.y = max(b.custom_minimum_size.y, MIN_TOUCH)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

## An element-picker button, tinted when `chosen`.
static func style_element_button(b: Button, element: String, chosen: bool) -> void:
	var e: Dictionary = ELEMENTS[element]
	var idle := box(e["fill"], e["color"], 2, 8, 6, 8) if chosen else box(PANEL, BORDER_STRONG, 1, 8, 6, 8)
	var hover := idle.duplicate()
	hover.border_color = e["color"]
	for state in ["normal", "focus", "pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(state, idle)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("disabled", idle)
	var text_c: Color = e["text"] if chosen else TEXT
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_disabled_color"]:
		b.add_theme_color_override(c, text_c)
	b.add_theme_font_override("font", body_font(600))
	b.add_theme_font_size_override("font_size", 13)
	b.custom_minimum_size.y = 58
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

static func _add_button_styles(t: Theme, type: String, kind: String) -> void:
	var states := _button_states(kind)
	for state in states["boxes"]:
		t.set_stylebox(state, type, states["boxes"][state])
	for c in states["colors"]:
		t.set_color(c, type, states["colors"][c])

static func _button_states(kind: String) -> Dictionary:
	var normal: StyleBoxFlat
	var hover: StyleBoxFlat
	var pressed: StyleBoxFlat
	var disabled: StyleBoxFlat
	var fg := TEXT
	var fg_disabled := Color(TEXT, 0.4)
	var out := {}
	match kind:
		"primary":
			normal = box(ACCENT, Color.TRANSPARENT, 0, 8, 20, 8)
			hover = box(ACCENT.lightened(0.12), Color.TRANSPARENT, 0, 8, 20, 8)
			pressed = box(ACCENT.darkened(0.12), Color.TRANSPARENT, 0, 8, 20, 8)
			disabled = box(Color(ACCENT, 0.28), Color.TRANSPARENT, 0, 8, 20, 8)
			fg = TABLE
			fg_disabled = Color(TABLE, 0.7)
			out["font"] = display_font(700)
			out["size"] = 15
		"light":
			normal = box(TEXT, Color.TRANSPARENT, 0, 8, 14, 8)
			hover = box(Color.WHITE, Color.TRANSPARENT, 0, 8, 14, 8)
			pressed = box(TEXT.darkened(0.15), Color.TRANSPARENT, 0, 8, 14, 8)
			disabled = box(Color(TEXT, 0.18), Color.TRANSPARENT, 0, 8, 14, 8)
			fg = TABLE
			fg_disabled = Color(TEXT, 0.55)
			out["font"] = body_font(600)
		"danger":
			normal = box(Color.TRANSPARENT, BORDER_STRONG, 1, 8, 14, 8)
			hover = box(Color(DANGER, 0.08), DANGER, 1, 8, 14, 8)
			pressed = box(Color(DANGER, 0.16), DANGER, 1, 8, 14, 8)
			disabled = box(Color.TRANSPARENT, BORDER, 1, 8, 14, 8)
			fg = DANGER
			fg_disabled = Color(DANGER, 0.4)
			out["font"] = body_font(600)
		"card":
			normal = box(PANEL, BORDER_STRONG, 1, 10, 8, 8)
			hover = box(SELECTED, MUTED, 1, 10, 8, 8)
			pressed = box(SELECTED, TEXT, 2, 10, 8, 8)
			disabled = box(PANEL, BORDER, 1, 10, 8, 8)
			out["font"] = body_font(600)
			out["size"] = 13
		_:  # secondary
			normal = box(PANEL_GLASS, BORDER_STRONG, 1, 8, 16, 8)
			hover = box(Color(SELECTED, 0.95), MUTED, 1, 8, 16, 8)
			pressed = box(SELECTED, TEXT, 1, 8, 16, 8)
			disabled = box(PANEL_GLASS, BORDER, 1, 8, 16, 8)
	out["boxes"] = {
		"normal": normal, "hover": hover, "pressed": pressed,
		"hover_pressed": pressed, "disabled": disabled, "focus": StyleBoxEmpty.new(),
	}
	out["colors"] = {
		"font_color": fg, "font_hover_color": fg, "font_pressed_color": fg,
		"font_hover_pressed_color": fg, "font_focus_color": fg, "font_disabled_color": fg_disabled,
		"icon_normal_color": fg, "icon_hover_color": fg, "icon_pressed_color": fg,
		"icon_hover_pressed_color": fg, "icon_disabled_color": fg_disabled,
	}
	return out

# --- Labels ----------------------------------------------------------------
static func label(text: String, size: int = 14, color: Color = TEXT, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if font:
		l.add_theme_font_override("font", font)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## Small uppercase muted caption ("LIVES", "CHOOSE ELEMENT").
static func caption(text: String, size: int = 10) -> Label:
	return label(text.to_upper(), size, MUTED, body_font(500, 1))

# --- Icons (inline SVG from the design canvas) -----------------------------
const ICON_FIRE := '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 56 56"><path d="M28 53 C16 53 9 45 9 35 C9 25 16 19 20 10 C22 16 25 19 28 20 C29 13 33 7 39 3 C38 12 47 21 47 34 C47 45 40 53 28 53 Z" fill="#FF8A3D"/></svg>'
const ICON_POISON := '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 14 16"><path d="M7 0 C9 4 13 7 13 10.5 C13 13.5 10.3 16 7 16 C3.7 16 1 13.5 1 10.5 C1 7 5 4 7 0 Z" fill="#B6F23A"/></svg>'
const ICON_SHOCK := '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 56 56"><path d="M34 2 L12 31 H25 L19 54 L45 21 H31 L38 2 Z" fill="#6B8DFF"/></svg>'
const ICON_MACHINE_GUN := '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" fill="none" stroke="#FFFFFF" stroke-width="2"><rect x="7" y="14" width="18" height="12" rx="2"/><line x1="12" y1="14" x2="12" y2="4"/><line x1="20" y1="14" x2="20" y2="4"/></svg>'
const ICON_BEAM := '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" fill="none" stroke="#FFFFFF" stroke-width="2"><path d="M8 26 h16 l-3 -8 h-10 z"/><path d="M16 18 v-6 M11 12 l5 -7 l5 7"/></svg>'
const ICON_MISSILE := '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" fill="none" stroke="#FFFFFF" stroke-width="2"><ellipse cx="16" cy="22" rx="10" ry="4"/><path d="M13 20 v-10 l3 -5 l3 5 v10"/></svg>'
const ICON_PAUSE := '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" stroke-width="2.4" stroke-linecap="round"><line x1="8" y1="5" x2="8" y2="19"/><line x1="16" y1="5" x2="16" y2="19"/></svg>'
const ICON_PLAY := '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M7 4.5 L19 12 L7 19.5 Z" fill="#FFFFFF"/></svg>'

## Icon per tower shape (TDTower.TYPES[type]["shape"]).
const TOWER_ICONS := { "cannon": ICON_MACHINE_GUN, "beam": ICON_BEAM, "rocket_silo": ICON_MISSILE }
const ELEMENT_ICONS := { "fire": ICON_FIRE, "poison": ICON_POISON, "shock": ICON_SHOCK }

static var _icon_cache: Dictionary = {}

## Rasterize an SVG string to a texture `px` tall (cached). White-stroked icons
## take their color from the button's icon colors / a modulate.
static func icon(svg: String, px: int) -> Texture2D:
	var key := "%d:%d" % [svg.hash(), px]
	if _icon_cache.has(key):
		return _icon_cache[key]
	var img := Image.new()
	# Render at the requested height: scale by px / viewBox height.
	var vb_h := _viewbox_height(svg)
	if img.load_svg_from_string(svg, float(px) / vb_h) != OK:
		return null
	var tex := ImageTexture.create_from_image(img)
	_icon_cache[key] = tex
	return tex

static func _viewbox_height(svg: String) -> float:
	var i := svg.find('viewBox="')
	if i < 0:
		return 24.0
	var parts := svg.substr(i + 9, svg.find('"', i + 9) - i - 9).split(" ")
	return float(parts[3]) if parts.size() == 4 else 24.0
