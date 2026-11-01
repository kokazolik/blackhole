class_name UiTheme
## Общий стиль интерфейса: Unbounded и Manrope, тонкое стекло с волосяной рамкой, цвета акцентов.

# Весь интерфейс на одной паре: Unbounded — заголовки, Manrope — текст.
# Старые имена (SERIF и т. п.) оставлены, чтобы не трогать каждый экран:
# они теперь указывают на Manrope, крупные заголовки — FONT_HEAD.
const FONT_TEXT := preload("res://assets/fonts/Manrope-Medium.ttf")
const FONT_SEMI := preload("res://assets/fonts/Manrope-Bold.ttf")
const FONT_NUMBERS := preload("res://assets/fonts/InterDisplay-Bold.otf")
const FONT_SERIF := preload("res://assets/fonts/Manrope-Medium.ttf")
const FONT_SERIF_ITALIC := preload("res://assets/fonts/Manrope-Medium.ttf")
const FONT_SERIF_BOLD := preload("res://assets/fonts/Manrope-Bold.ttf")
const FONT_HEAD := preload("res://assets/fonts/Unbounded-Medium.ttf")
# Меню и коллекция: современная гротесковая пара. Unbounded — широкий
# «космический» заголовочный, Manrope — спокойный текст.
const FONT_DISPLAY := preload("res://assets/fonts/Unbounded-Light.ttf")
const FONT_DISPLAY_MED := preload("res://assets/fonts/Unbounded-Medium.ttf")
const FONT_DISPLAY_BOLD := preload("res://assets/fonts/Unbounded-Bold.ttf")
const FONT_UI := preload("res://assets/fonts/Manrope-Medium.ttf")
const FONT_UI_BOLD := preload("res://assets/fonts/Manrope-Bold.ttf")
const PARCHMENT := Color(0.9, 0.91, 0.95)  # цвет текста рассказа: холодный светлый

const GOLD := Color(1.0, 0.82, 0.42)
const GOLD_DEEP := Color(0.92, 0.6, 0.18)
const ICE := Color(0.62, 0.8, 1.0)
const CHONDRULE := Color(0.5, 0.92, 0.82)  # вторая валюта, хондры
const TEXT := Color(0.9, 0.93, 1.0)
const TEXT_DIM := Color(0.62, 0.68, 0.82)
const GLASS := Color(0.05, 0.07, 0.14, 0.62)
const GLASS_BORDER := Color(0.55, 0.7, 1.0, 0.22)

static var _theme: Theme


## Звёздная пыль: четырёхлучевая искра с мягким ореолом.
static func draw_spark(ci: CanvasItem, c: Vector2, r: float, col: Color = GOLD) -> void:
	ci.draw_circle(c, r * 1.07, Color(col, 0.12))
	var w := r * 0.29
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(w, -w), c + Vector2(r, 0), c + Vector2(w, w),
		c + Vector2(0, r), c + Vector2(-w, w), c + Vector2(-r, 0), c + Vector2(-w, -w)]), col)
	ci.draw_circle(c, r * 0.21, Color(1, 1, 0.9, col.a))


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


## Карточка: тёмное стекло с волосяной рамкой, как в меню и коллекции.
static func painted_panel(margin := 26.0) -> StyleBox:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.035, 0.04, 0.075, 0.94)
	s.border_color = Color(0.85, 0.9, 1.0, 0.2)
	s.set_border_width_all(1)
	s.set_corner_radius_all(10)
	s.set_content_margin_all(margin)
	s.anti_aliasing = true
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 18
	return s


## Кнопка карточки: стекло меню, текст по центру.
static func paint_button(b: Button, primary := false, font_size := 26) -> void:
	glass_button(b, primary, roundi(font_size * 0.68), HORIZONTAL_ALIGNMENT_CENTER)


## Шрифт с разрядкой: широкие буквы заголовков дышат.
static func spaced(base: Font, spacing: int) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = base
	f.spacing_glyph = spacing
	return f


## Кнопка меню: тонкое стекло с волосяной рамкой, текст разрядкой.
## Главная — с тёплой заливкой и светлой рамкой; при наведении стекло светлеет.
static func glass_button(b: Button, primary := false, font_size := 17, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var s := StyleBoxFlat.new()
		s.set_corner_radius_all(6)
		s.anti_aliasing = true
		s.set_border_width_all(1)
		s.content_margin_left = 26
		s.content_margin_right = 26
		s.content_margin_top = 12
		s.content_margin_bottom = 12
		var bg := Color(1.0, 0.8, 0.5, 0.16) if primary else Color(0.75, 0.82, 1.0, 0.05)
		var edge := Color(1.0, 0.84, 0.6, 0.7) if primary else Color(0.85, 0.9, 1.0, 0.18)
		match state:
			"hover":
				bg = Color(bg, bg.a + 0.08)
				edge = Color(edge, minf(edge.a + 0.25, 1.0))
			"pressed":
				bg = Color(bg, bg.a + 0.16)
			"disabled":
				bg = Color(bg, bg.a * 0.5)
				edge = Color(edge, edge.a * 0.5)
		s.bg_color = bg
		s.border_color = edge
		if primary:
			# Мягкий тёплый ореол вокруг главной кнопки.
			s.shadow_color = Color(1.0, 0.7, 0.35, 0.18)
			s.shadow_size = 10
		b.add_theme_stylebox_override(state, s)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = align
	b.add_theme_font_override("font", spaced(FONT_DISPLAY_MED if primary else FONT_DISPLAY, 2))
	b.add_theme_font_size_override("font_size", font_size)
	var col := Color(1.0, 0.92, 0.8) if primary else Color(0.88, 0.9, 0.96)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(key, col)
	b.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	b.add_theme_color_override("font_disabled_color", Color(0.6, 0.6, 0.66))


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

	t.set_stylebox("panel", "PanelContainer", glass(10, Color(0.035, 0.04, 0.075, 0.72), Color(0.85, 0.9, 1.0, 0.16)))

	t.set_font("font", "Button", FONT_SEMI)
	t.set_stylebox("normal", "Button", glass(6, Color(0.04, 0.05, 0.09, 0.72), Color(0.85, 0.9, 1.0, 0.2), 12.0))
	t.set_stylebox("hover", "Button", glass(6, Color(0.08, 0.09, 0.14, 0.8), Color(0.9, 0.94, 1.0, 0.42), 12.0))
	t.set_stylebox("pressed", "Button", glass(6, Color(0.12, 0.13, 0.2, 0.88), Color(1.0, 1.0, 1.0, 0.55), 12.0))
	t.set_stylebox("disabled", "Button", glass(6, Color(0.04, 0.04, 0.07, 0.55), Color(1, 1, 1, 0.08), 12.0))
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
