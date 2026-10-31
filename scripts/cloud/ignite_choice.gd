extends Control
## Решение в миг зажигания: сбросить остатки кокона и стать спокойной звездой
## или «дожать» газ диска, рискуя вспышками FU Ориона.

signal chosen(which: String)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiTheme.get_theme()
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.03, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var box := VBoxContainer.new()
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = -470
	box.offset_right = 470
	box.offset_top = -330
	box.offset_bottom = -24
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	box.add_child(_line("Ты звезда. Что дальше?", UiTheme.FONT_SERIF_BOLD, 34, UiTheme.GOLD))
	box.add_child(_line("Вокруг ещё крутится диск газа. Его можно отпустить или дожать.", UiTheme.FONT_SERIF_ITALIC, 19, UiTheme.PARCHMENT))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	box.add_child(row)
	row.add_child(_card("Спокойная звезда", "Ветер сдувает остатки кокона. Ровный свет: звёздной пыли +25% до конца облака. Газ облака по-прежнему падает на тебя.", "calm", false))
	row.add_child(_card("Дожать", "Газ диска падает в полтора раза быстрее, но диск будет вспыхивать. Поймаешь вспышку — масса прибавится, упустишь — её сдует.", "push", true))


func pick(which: String) -> void:
	chosen.emit(which)
	queue_free()


func _card(title: String, desc: String, which: String, primary: bool) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.painted_panel(22))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	v.add_child(_line(title, UiTheme.FONT_SERIF_BOLD, 28, UiTheme.GOLD))
	var d := _line(desc, UiTheme.FONT_SERIF_ITALIC, 18, UiTheme.PARCHMENT)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(390, 96)
	v.add_child(d)
	var b := Button.new()
	b.text = "Выбрать"
	b.custom_minimum_size = Vector2(220, 54)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UiTheme.paint_button(b, primary, 22)
	b.pressed.connect(pick.bind(which))
	v.add_child(b)
	return panel


func _line(text: String, font: Font, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l
