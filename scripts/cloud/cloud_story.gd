extends Control
## Карточка-история на входе в облако: как карлик оказался в облаке и почему
## он может стать звездой. Автор просил объяснить это игроку честно.

signal closed

var from := "brown_dwarf"
var ignite := 80.0
var goal := ""
var _box: VBoxContainer
var _pages: Array = []
var _page := 0
var _text: Label
var _title: Label
var _btn: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiTheme.get_theme()
	var who := "коричневый карлик в тринадцать масс Юпитера" if from == "brown_dwarf" else "супер-Юпитер"
	_pages = [
		["Изгнание", "Мимо твоей звезды прошла соседняя. Её притяжение раскачало твою орбиту, и ты, %s, вылетел из родной системы. Планеты остались позади." % who],
		["Межзвёздная тьма", "Миллион лет ты летел в пустоте между звёздами, пока не упал в молекулярное облако: холодный газ и пыль на десятки световых лет. Все звёзды Галактики рождаются в таких облаках."],
		["Зерно звезды", "Обычно звезда собирается прямо из сгустка газа, а не из планеты. Но гравитации всё равно, кто ты: тело в %s, упавшее в густой газ, тянет его к себе, как любая протозвезда. Набери %d масс Юпитера, и в недрах загорится водород." % [
			"тринадцать масс Юпитера" if from == "brown_dwarf" else "несколько масс Юпитера", roundi(ignite)]],
		["Твой состав", goal.substr(0, 1).to_upper() + goal.substr(1) + "." + ("\n\nСупер-Юпитеру путь длиннее: дейтерий в тебе ещё не загорелся, начинаешь с меньшей массой." if from != "brown_dwarf" else "")],
	]
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.03, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.painted_panel(34))
	panel.custom_minimum_size = Vector2(700, 0)
	center.add_child(panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 14)
	panel.add_child(_box)
	_title = _line("", UiTheme.FONT_SERIF_BOLD, 38, UiTheme.GOLD)
	_box.add_child(_title)
	_text = _line("", UiTheme.FONT_SERIF_ITALIC, 23, UiTheme.PARCHMENT)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(640, 150)
	_box.add_child(_text)
	_btn = Button.new()
	_btn.custom_minimum_size = Vector2(260, 62)
	_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UiTheme.paint_button(_btn, true, 24)
	_btn.pressed.connect(_next)
	_box.add_child(_btn)
	_show()


func _show() -> void:
	var pg: Array = _pages[_page]
	_title.text = str(pg[0])
	_text.text = str(pg[1])
	_btn.text = "В облако" if _page == _pages.size() - 1 else "Дальше"
	_text.modulate.a = 0.0
	create_tween().tween_property(_text, "modulate:a", 1.0, 0.5)


func _next() -> void:
	_page += 1
	if _page >= _pages.size():
		close()
		return
	_show()


func close() -> void:
	closed.emit()
	queue_free()


func _line(text: String, font: Font, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l
