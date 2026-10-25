extends Control
## Главное меню: расписная картина молодой звезды с диском, название и кнопки.
## Картина медленно «дышит» (приближение и сдвиг), по ней плывут золотые пылинки.

const BG := preload("res://assets/intro/menu.png")
const MOTES := 46

var _bg: TextureRect
var _motes_layer: Control
var _motes: Array = []
var _time := 0.0
var _confirm: PanelContainer


func _ready() -> void:
	theme = UiTheme.get_theme()
	get_tree().paused = false
	_build()
	for i in MOTES:
		_motes.append(_new_mote(true))


func _build() -> void:
	var under := ColorRect.new()
	under.color = Color(0.01, 0.01, 0.03)
	under.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(under)

	_bg = TextureRect.new()
	_bg.texture = BG
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	_motes_layer = Control.new()
	_motes_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_motes_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_motes_layer.draw.connect(_draw_motes)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_motes_layer.material = add
	add_child(_motes_layer)

	# Слева: название и кнопки столбиком.
	var column := VBoxContainer.new()
	column.anchor_top = 0.0
	column.anchor_bottom = 1.0
	column.offset_left = 80
	column.offset_right = 560
	column.offset_top = 60
	column.offset_bottom = -40
	column.add_theme_constant_override("separation", 14)
	add_child(column)

	var title := Label.new()
	title.text = "От пылинки"
	_style_title(title, 64)
	column.add_child(title)
	var title2 := Label.new()
	title2.text = "до чёрной дыры"
	_style_title(title2, 46)
	column.add_child(title2)
	var subtitle := Label.new()
	subtitle.text = "путь длиною в миллиарды лет"
	subtitle.add_theme_font_override("font", UiTheme.FONT_SERIF_ITALIC)
	subtitle.add_theme_font_size_override("font_size", 22)
	subtitle.add_theme_color_override("font_color", Color(UiTheme.PARCHMENT, 0.75))
	column.add_child(subtitle)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 30)
	column.add_child(gap)

	var progress := GameState.has_progress()
	if progress:
		_add_button(column, "Продолжить путь", true, _continue)
	_add_button(column, "Новая игра", not progress, _new_game)
	_add_button(column, "Пролог", false, func(): _open_prologue(false))
	if OS.get_name() != "Web":
		_add_button(column, "Выход", false, func(): get_tree().quit())

	var version := Label.new()
	version.text = "версия " + str(ProjectSettings.get_setting("application/config/version", ""))
	version.anchor_left = 1.0
	version.anchor_right = 1.0
	version.anchor_top = 1.0
	version.anchor_bottom = 1.0
	version.offset_left = -220
	version.offset_right = -20
	version.offset_top = -36
	version.offset_bottom = -12
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	version.add_theme_font_size_override("font_size", 14)
	version.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
	add_child(version)

	# Появление: название и кнопки проступают снизу вверх.
	column.modulate.a = 0.0
	column.position.y += 20
	var tw := create_tween().set_parallel(true)
	tw.tween_property(column, "modulate:a", 1.0, 1.2).set_delay(0.2)
	tw.tween_property(column, "position:y", column.position.y - 20, 1.2).set_delay(0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _style_title(l: Label, size_px: int) -> void:
	l.add_theme_font_override("font", UiTheme.FONT_SERIF_BOLD)
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", Color(1.0, 0.84, 0.5))
	l.add_theme_color_override("font_outline_color", Color(0.12, 0.05, 0.0, 0.8))
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_shadow_color", Color(1.0, 0.6, 0.2, 0.35))
	l.add_theme_constant_override("shadow_offset_y", 0)
	l.add_theme_constant_override("shadow_outline_size", 18)


func _add_button(parent: Control, text: String, primary: bool, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(330, 64)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	UiTheme.paint_button(b, primary)
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _continue() -> void:
	Fader.go(Fader.GAME)


func _new_game() -> void:
	if GameState.has_progress():
		_ask_new_game()
		return
	_start_new()


func _start_new() -> void:
	GameState.reset_run()
	_open_prologue(true)


## Пролог после новой игры ведёт в игру, а открытый из меню — обратно в меню.
func _open_prologue(then_game: bool) -> void:
	Prologue.then_game = then_game
	Fader.go(Fader.PROLOGUE)


func _ask_new_game() -> void:
	if _confirm:
		return
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_confirm = PanelContainer.new()
	_confirm.add_theme_stylebox_override("panel", UiTheme.painted_panel(32))
	_confirm.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_confirm.custom_minimum_size = Vector2(560, 0)
	_confirm.position -= Vector2(280, 120)
	add_child(_confirm)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	_confirm.add_child(box)
	var q := Label.new()
	q.text = "Начать путь заново?"
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.add_theme_font_override("font", UiTheme.FONT_SERIF_BOLD)
	q.add_theme_font_size_override("font_size", 32)
	q.add_theme_color_override("font_color", Color(1.0, 0.84, 0.5))
	box.add_child(q)
	var t := Label.new()
	t.text = "Всё собранное и изученное будет потеряно."
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_override("font", UiTheme.FONT_SERIF_ITALIC)
	t.add_theme_font_size_override("font_size", 21)
	t.add_theme_color_override("font_color", UiTheme.PARCHMENT)
	box.add_child(t)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	box.add_child(row)
	var yes := _add_button(row, "Начать заново", true, _start_new)
	yes.custom_minimum_size = Vector2(230, 60)
	var no := _add_button(row, "Отмена", false, func():
		dim.queue_free()
		_confirm.queue_free()
		_confirm = null)
	no.custom_minimum_size = Vector2(180, 60)


func _new_mote(anywhere: bool) -> Dictionary:
	var s := size if size.x > 0 else Vector2(1280, 720)
	return {
		"pos": Vector2(randf() * s.x, randf() * s.y if anywhere else s.y + 10.0),
		"vel": Vector2(randf_range(-6, 10), randf_range(-14, -4)),
		"r": randf_range(0.8, 2.2),
		"phase": randf() * TAU,
	}


func _process(delta: float) -> void:
	_time += delta
	# Картина медленно приближается и плывёт: как будто мы тоже летим.
	var k := 1.06 + 0.03 * sin(_time * 0.08)
	_bg.size = size * k
	_bg.position = -(size * (k - 1.0)) * 0.5 + Vector2(sin(_time * 0.05) * 14.0, cos(_time * 0.04) * 8.0)
	for i in _motes.size():
		var m: Dictionary = _motes[i]
		m.pos += m.vel * delta
		if m.pos.y < -10 or m.pos.x > size.x + 10 or m.pos.x < -10:
			_motes[i] = _new_mote(false)
	_motes_layer.queue_redraw()


func _draw_motes() -> void:
	for m in _motes:
		var tw := 0.5 + 0.5 * sin(_time * 2.0 + m.phase)
		var c := Color(1.0, 0.82, 0.5, 0.35 + 0.5 * tw)
		_motes_layer.draw_circle(m.pos, m.r * 3.0, Color(c, c.a * 0.15))
		_motes_layer.draw_circle(m.pos, m.r, c)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		get_tree().quit()
