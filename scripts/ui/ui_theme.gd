class_name UiTheme
## Общий стиль интерфейса: шрифт Inter, «стеклянные» панели и кнопки, цвета акцентов.

const FONT_TEXT := preload("res://assets/fonts/Inter-Medium.otf")
const FONT_SEMI := preload("res://assets/fonts/Inter-SemiBold.otf")
const FONT_NUMBERS := preload("res://assets/fonts/InterDisplay-Bold.otf")

const GOLD := Color(1.0, 0.82, 0.42)
const GOLD_DEEP := Color(0.92, 0.6, 0.18)
const ICE := Color(0.62, 0.8, 1.0)
const TEXT := Color(0.9, 0.93, 1.0)
const TEXT_DIM := Color(0.62, 0.68, 0.82)
const GLASS := Color(0.05, 0.07, 0.14, 0.62)
const GLASS_BORDER := Color(0.55, 0.7, 1.0, 0.22)

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


static func glass(radius := 18, bg := GLASS, border := GLASS_BORDER, margin := 14.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	s.anti_aliasing = true
	# Мягкая тень вокруг панели отделяет её от космоса.
	s.shadow_color = Color(0, 0, 0, 0.25)
	s.shadow_size = 6
	return s


static func pill(color: Color, radius := 16) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.anti_aliasing = true
	return s


static func _build() -> Theme:
	var t := Theme.new()
	t.default_font = FONT_TEXT
	t.default_font_size = 20

	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.55))
	t.set_constant("outline_size", "Label", 3)

	t.set_stylebox("panel", "PanelContainer", glass())

	t.set_font("font", "Button", FONT_SEMI)
	t.set_stylebox("normal", "Button", glass(16, Color(0.08, 0.1, 0.2, 0.7), Color(0.6, 0.75, 1.0, 0.35), 12.0))
	t.set_stylebox("hover", "Button", glass(16, Color(0.12, 0.15, 0.28, 0.8), Color(0.7, 0.85, 1.0, 0.55), 12.0))
	t.set_stylebox("pressed", "Button", glass(16, Color(0.16, 0.2, 0.36, 0.9), Color(0.8, 0.9, 1.0, 0.7), 12.0))
	t.set_stylebox("disabled", "Button", glass(16, Color(0.06, 0.07, 0.12, 0.6), Color(1, 1, 1, 0.08), 12.0))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", TEXT_DIM)

	t.set_stylebox("background", "ProgressBar", pill(Color(1, 1, 1, 0.08), 4))
	t.set_stylebox("fill", "ProgressBar", pill(ICE, 4))

	t.set_font("normal_font", "RichTextLabel", FONT_TEXT)
	t.set_font("bold_font", "RichTextLabel", FONT_SEMI)
	t.set_color("default_color", "RichTextLabel", TEXT)
	return t
