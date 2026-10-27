class_name UiTheme
## Общий стиль интерфейса: шрифт Inter, «стеклянные» панели и кнопки, цвета акцентов.

const FONT_TEXT := preload("res://assets/fonts/Inter-Medium.otf")
const FONT_SEMI := preload("res://assets/fonts/Inter-SemiBold.otf")
const FONT_NUMBERS := preload("res://assets/fonts/InterDisplay-Bold.otf")
# Голос рассказчика и заголовки меню: книжная антиква.
const FONT_SERIF := preload("res://assets/fonts/LiberationSerif-Regular.ttf")
const FONT_SERIF_ITALIC := preload("res://assets/fonts/LiberationSerif-Italic.ttf")
const FONT_SERIF_BOLD := preload("res://assets/fonts/LiberationSerif-Bold.ttf")
const PANEL_TEX := preload("res://assets/ui/panel_painted.png")
const BUTTON_DARK_TEX := preload("res://assets/ui/button_dark.png")
const BUTTON_GOLD_TEX := preload("res://assets/ui/button_gold.png")
const PARCHMENT := Color(0.96, 0.9, 0.78)  # цвет текста рассказа

const GOLD := Color(1.0, 0.82, 0.42)
const GOLD_DEEP := Color(0.92, 0.6, 0.18)
const ICE := Color(0.62, 0.8, 1.0)
const CHONDRULE := Color(0.5, 0.92, 0.82)  # вторая валюта, хондры
const TEXT := Color(0.9, 0.93, 1.0)
const TEXT_DIM := Color(0.62, 0.68, 0.82)
const GLASS := Color(0.05, 0.07, 0.14, 0.62)
const GLASS_BORDER := Color(0.55, 0.7, 1.0, 0.22)

static var _theme: Theme


## Хондра: застывшая стеклянная капля с бликом.
static func draw_chondrule(ci: CanvasItem, c: Vector2, r: float) -> void:
	ci.draw_circle(c, r * 1.6, Color(CHONDRULE, 0.12))
	ci.draw_circle(c, r, CHONDRULE.darkened(0.35))
	ci.draw_circle(c + Vector2(-0.12, -0.12) * r, r * 0.78, CHONDRULE)
	ci.draw_circle(c + Vector2(-0.35, -0.35) * r, r * 0.28, Color(1, 1, 1, 0.85))


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


## Расписная карточка с золотой рамкой (меню, рассказчик).
static func painted_panel(margin := 26.0) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = PANEL_TEX
	s.set_texture_margin_all(30)
	s.set_content_margin_all(margin)
	return s


## Расписная кнопка: тёмная с золотым кантом или главная золотая.
static func paint_button(b: Button, primary := false, font_size := 26) -> void:
	var tex := BUTTON_GOLD_TEX if primary else BUTTON_DARK_TEX
	for state in ["normal", "hover", "pressed", "disabled"]:
		var s := StyleBoxTexture.new()
		s.texture = tex
		s.set_texture_margin_all(20)
		s.content_margin_left = 28
		s.content_margin_right = 28
		s.content_margin_top = 10
		s.content_margin_bottom = 10
		match state:
			"hover":
				s.modulate_color = Color(1.15, 1.12, 1.05)
			"pressed":
				s.modulate_color = Color(0.85, 0.82, 0.78)
			"disabled":
				s.modulate_color = Color(0.6, 0.6, 0.65, 0.7)
		b.add_theme_stylebox_override(state, s)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", FONT_SERIF_BOLD)
	b.add_theme_font_size_override("font_size", font_size)
	var text_col := Color(0.16, 0.09, 0.02) if primary else PARCHMENT
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(key, text_col)
	b.add_theme_color_override("font_disabled_color", Color(0.6, 0.58, 0.55))


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
