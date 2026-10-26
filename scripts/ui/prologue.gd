class_name Prologue
extends Control
## Пролог: рассказчик говорит с путником. Расписные картины сменяют друг друга,
## текст печатается по буквам. Касание допечатывает строку или листает дальше.
##
## Рассказ объясняет, что ждёт в игре, и по-научному: откуда у звезды пыль
## и почему путь начинается именно с пылинки.

static var then_game := true  # после пролога — в игру (новая игра) или обратно в меню

const CHARS_PER_SECOND := 42.0
const FADE := 0.9

const PAGES := [
	{
		"image": preload("res://assets/intro/p1_path.png"),
		"title": "Путник",
		"text": "Послушай, путник. Тебе выпала дорога, длиннее которой нет во Вселенной.\n\nТы начнёшь пылинкой — меньше песчинки, легче вздоха. Соберёшь себя в гальку, в валун, в глыбу размером с город. Станешь планетой, потом звездой. А в самом конце пути, если хватит сил, — чёрной дырой, из которой не вырывается даже свет.",
	},
	{
		"image": preload("res://assets/intro/p2_forge.png"),
		"title": "Кузница звёзд",
		"text": "С чего всё начинается? После Большого взрыва во Вселенной были почти только водород и гелий. Кремний, железо, углерод и кислород выковали звёзды — в своих недрах, как в кузнице.\n\nУмирая, старые звёзды сбрасывают оболочки или взрываются сверхновыми. Выкованные элементы разлетаются, остывают и собираются в крошечные пылинки — в сотни раз тоньше волоса.",
	},
	{
		"image": preload("res://assets/intro/p3_cloud.png"),
		"title": "Рождение звезды",
		"text": "Пыль и газ копятся в холодных тёмных облаках. Однажды облако сжимается под собственной тяжестью. В центре загорается молодая звезда, а остатки облака, вращаясь, расплющиваются в плоский диск вокруг неё — протопланетный диск.\n\nГаза в нём примерно в сто раз больше, чем пыли. Но именно пыль станет камнем, планетами и всем, что на них появится.",
	},
	{
		"image": preload("res://assets/intro/p4_grains.png"),
		"title": "Почему пылинка",
		"text": "Планеты не появляются сразу. Пылинки сталкиваются и слипаются — их держат слабые электрические силы, как пыль липнет к экрану. Из пылинок растут рыхлые комочки, из комочков — галька, из гальки — валуны.\n\nУ самой звезды слишком жарко: пыль там испаряется. А за снеговой линией, где холодно, на пылинках намерзает лёд, и они слипаются охотнее.",
	},
	{
		"image": preload("res://assets/intro/p5_start.png"),
		"title": "Начало пути",
		"text": "Вот и ты — одна пылинка в диске молодой звезды. Вокруг миллиарды таких же, и все вы летите вокруг неё по кругу.\n\nДвигайся, собирай пыль, расти. Читай книгу звёздных знаний. И держись подальше от звезды: огня в её жаре нет, но и пощады тоже.\n\nТвой путь начинается.",
	},
]

var _page := -1
var _shown := 0.0      # сколько букв уже напечатано
var _time := 0.0
var _page_time := 0.0
var _img_a: TextureRect
var _img_b: TextureRect
var _title: Label
var _text: Label
var _hint: Label
var _dots: Control
var _leaving := false


func _ready() -> void:
	theme = UiTheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_show_page(0)


func _build() -> void:
	var under := ColorRect.new()
	under.color = Color(0.01, 0.01, 0.03)
	under.set_anchors_preset(Control.PRESET_FULL_RECT)
	under.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(under)
	_img_a = _make_image()
	_img_b = _make_image()

	# Рассказ внизу на расписной карточке.
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiTheme.painted_panel(30))
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 1.0
	card.anchor_bottom = 1.0
	card.offset_left = -500
	card.offset_right = 500
	card.offset_top = -300
	card.offset_bottom = -24
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.self_modulate = Color(1, 1, 1, 0.92)
	add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	_title = Label.new()
	_title.add_theme_font_override("font", UiTheme.FONT_SERIF_BOLD)
	_title.add_theme_font_size_override("font_size", 30)
	_title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.48))
	box.add_child(_title)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.add_theme_font_override("font", UiTheme.FONT_SERIF_ITALIC)
	_text.add_theme_font_size_override("font_size", 22)
	_text.add_theme_color_override("font_color", UiTheme.PARCHMENT)
	_text.add_theme_constant_override("line_spacing", 2)
	box.add_child(_text)

	_hint = Label.new()
	_hint.text = "коснись, чтобы продолжить"
	_hint.anchor_left = 0.5
	_hint.anchor_right = 0.5
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_left = 180
	_hint.offset_right = 500
	_hint.offset_top = -334
	_hint.offset_bottom = -306
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.add_theme_font_override("font", UiTheme.FONT_SERIF_ITALIC)
	_hint.add_theme_font_size_override("font_size", 17)
	_hint.add_theme_color_override("font_color", Color(1.0, 0.82, 0.48))
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)

	# Точки страниц над карточкой.
	_dots = Control.new()
	_dots.anchor_left = 0.5
	_dots.anchor_right = 0.5
	_dots.anchor_top = 1.0
	_dots.anchor_bottom = 1.0
	_dots.offset_left = -100
	_dots.offset_right = 100
	_dots.offset_top = -328
	_dots.offset_bottom = -312
	_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dots.draw.connect(_draw_dots)
	add_child(_dots)

	var skip := Button.new()
	skip.text = "Пропустить"
	UiTheme.paint_button(skip, false, 20)
	skip.anchor_left = 1.0
	skip.anchor_right = 1.0
	skip.offset_left = -200
	skip.offset_right = -24
	skip.offset_top = 20
	skip.offset_bottom = 72
	skip.pressed.connect(_finish)
	add_child(skip)


func _make_image() -> TextureRect:
	var t := TextureRect.new()
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.modulate.a = 0.0
	add_child(t)
	return t


func _show_page(i: int) -> void:
	_page = i
	_shown = 0.0
	_page_time = 0.0
	var page: Dictionary = PAGES[i]
	# Новая картина проявляется поверх старой.
	var old := _img_a
	_img_a = _img_b
	_img_b = old
	_img_a.texture = page.image
	move_child(_img_a, 2)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_img_a, "modulate:a", 1.0, FADE)
	tw.tween_property(_img_b, "modulate:a", 0.0, FADE)
	_title.text = page.title
	_text.text = page.text
	_text.visible_characters = 0
	_dots.queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	_page_time += delta
	var full: int = (PAGES[_page].text as String).length()
	if _shown < full and _page_time > 0.4:
		_shown = minf(_shown + CHARS_PER_SECOND * delta, full)
		_text.visible_characters = int(_shown)
	_hint.modulate.a = (0.45 + 0.4 * sin(_time * 3.0)) if _shown >= full else 0.0
	# Картина медленно наезжает: у каждой страницы своё направление.
	for img in [_img_a, _img_b]:
		var k := 1.04 + 0.04 * clampf(_page_time / 14.0, 0.0, 1.0)
		img.size = size * k
		var drift := Vector2(-1 if _page % 2 == 0 else 1, -0.5) * _page_time * 1.6
		img.position = -(size * (k - 1.0)) * 0.5 + drift.limit_length(size.x * (k - 1.0) * 0.45)


func _gui_input(event: InputEvent) -> void:
	var tap: bool = (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
		or (event is InputEventScreenTouch and event.pressed)
	if tap:
		_advance()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.pressed and not event.echo and event.physical_keycode in [KEY_SPACE, KEY_ENTER, KEY_RIGHT]:
		_advance()


func _advance() -> void:
	var full: int = (PAGES[_page].text as String).length()
	if _shown < full:
		_shown = full
		_text.visible_characters = -1
		return
	if _page + 1 < PAGES.size():
		_show_page(_page + 1)
	else:
		_finish()


func _finish() -> void:
	if _leaving:
		return
	_leaving = true
	GameState.prologue_seen = true
	GameState.save_game()
	Fader.go(Fader.GAME if then_game else Fader.MENU, 1.0, 1.4)


func _draw_dots() -> void:
	var n := PAGES.size()
	var c := _dots.size * 0.5
	for i in n:
		var p := c + Vector2((i - (n - 1) * 0.5) * 22.0, 0)
		if i == _page:
			_dots.draw_circle(p, 5.0, Color(1.0, 0.82, 0.48))
		else:
			_dots.draw_circle(p, 3.5, Color(1.0, 0.9, 0.75, 0.35))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_finish()
