class_name SettingsScreen
extends Control
## Настройки: лист тёмного стекла поверх меню или паузы. Каждая строка —
## название, короткое пояснение и кнопка-значение справа; нажатие сразу
## применяет и сохраняет. Внизу — стереть весь прогресс (с подтверждением).

signal closed

const ROW_W := 640.0

var _wipe_armed := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiTheme.get_theme()
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.03, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := PanelContainer.new()
	var glass := StyleBoxFlat.new()
	glass.bg_color = Color(0.04, 0.045, 0.08, 0.94)
	glass.set_border_width_all(1)
	glass.border_color = Color(0.85, 0.9, 1.0, 0.18)
	glass.set_corner_radius_all(10)
	glass.content_margin_left = 34
	glass.content_margin_right = 34
	glass.content_margin_top = 24
	glass.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", glass)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -ROW_W * 0.5 - 34
	panel.offset_right = ROW_W * 0.5 + 34
	panel.offset_top = 24
	panel.offset_bottom = -24
	add_child(panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	panel.add_child(outer)
	var head := Label.new()
	head.text = "НАСТРОЙКИ"
	head.add_theme_font_override("font", UiTheme.spaced(UiTheme.FONT_DISPLAY, 6))
	head.add_theme_font_size_override("font_size", 24)
	head.add_theme_color_override("font_color", Color(1.0, 0.84, 0.55))
	outer.add_child(head)

	# Строки в прокрутке: на низком экране лист не вылезет за край.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 10)
	scroll.add_child(rows)

	_row(rows, "Плавность", "30 бережёт батарею, 120 — для быстрых экранов",
		func() -> String: return "%d кадров" % GameState.fps_max,
		func() -> void:
			var opts := [30, 60, 120]
			var i := opts.find(GameState.fps_max)
			GameState.fps_max = opts[(i + 1) % opts.size()])
	_toggle(rows, "Вибрация", "Толчок, когда рядом проходит огромное тело или бьёт удар", "vibration")
	_toggle(rows, "Имена и массы тел", "Подписи над планетами на этапе гиганта", "show_names")
	_toggle(rows, "Стрелки к телам", "Куда лететь, когда тело за краем экрана (гигант)", "show_marks")
	_toggle(rows, "Подписи событий", "Короткие пояснения, что сейчас случилось", "captions")
	_toggle(rows, "Не гасить экран", "Телефон не уснёт посреди игры", "keep_awake")
	_toggle(rows, "Кнопка скриншота", "Кружок у правого края: снимок экрана в галерею (Pictures/DustToBlackhole)", "shot_button")
	_toggle(rows, "Счётчик кадров", "Сколько кадров в секунду — в левом верхнем углу", "fps_counter")

	var sep := Control.new()
	sep.custom_minimum_size = Vector2(0, 6)
	rows.add_child(sep)
	var wipe := _row(rows, "Стереть весь прогресс", "Забег, наследие, коллекцию тел и пролог. Настройки останутся",
		func() -> String: return "Точно стереть?" if _wipe_armed else "Стереть",
		func() -> void:
			if _wipe_armed:
				GameState.wipe_all()
				Fader.go(Fader.MENU)
			else:
				_wipe_armed = true)
	wipe.add_theme_color_override("font_color", Color(1.0, 0.6, 0.5))
	wipe.add_theme_color_override("font_hover_color", Color(1.0, 0.7, 0.6))

	var done := Button.new()
	done.text = "Готово"
	done.custom_minimum_size = Vector2(220, 50)
	done.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UiTheme.glass_button(done, true, 16, HORIZONTAL_ALIGNMENT_CENTER)
	done.pressed.connect(close)
	outer.add_child(done)

	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.18)


func close() -> void:
	closed.emit()
	queue_free()


## Строка-переключатель: значение — поле GameState с тем же именем.
func _toggle(parent: Control, title: String, note: String, field: String) -> void:
	_row(parent, title, note,
		func() -> String: return "Вкл" if bool(GameState.get(field)) else "Выкл",
		func() -> void: GameState.set(field, not bool(GameState.get(field))))


func _row(parent: Control, title: String, note: String, value: Callable, change: Callable) -> Button:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	row.add_child(text)
	var t := Label.new()
	t.text = title
	t.add_theme_font_override("font", UiTheme.FONT_SEMI)
	t.add_theme_font_size_override("font_size", 18)
	t.add_theme_color_override("font_color", Color(0.92, 0.93, 0.98))
	text.add_child(t)
	var n := Label.new()
	n.text = note
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.add_theme_font_override("font", UiTheme.FONT_TEXT)
	n.add_theme_font_size_override("font_size", 13)
	n.add_theme_color_override("font_color", Color(0.75, 0.8, 0.92, 0.6))
	text.add_child(n)
	var b := Button.new()
	b.custom_minimum_size = Vector2(170, 46)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiTheme.glass_button(b, false, 14, HORIZONTAL_ALIGNMENT_CENTER)
	b.text = value.call()
	b.pressed.connect(func() -> void:
		change.call()
		GameState.apply_fps()
		GameState.save_game()
		b.text = value.call())
	row.add_child(b)
	return b
