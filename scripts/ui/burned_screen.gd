class_name BurnedScreen
extends Control
## Экран после гибели у звезды: что произошло и кнопки нового забега или меню.

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiTheme.get_theme()
	modulate.a = 0.0

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.02, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.painted_panel(36))
	panel.custom_minimum_size = Vector2(620, 0)
	_center(panel)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Упал в звезду" if GameState.burned_embryo else "Пылинка испарилась"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", UiTheme.FONT_SERIF_BOLD)
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(1.0, 0.72, 0.4))
	box.add_child(title)

	var text := Label.new()
	text.text = "Огня в космосе нет: излучение звезды раскалило пылинку, вещество перешло в газ, и звёздный ветер унёс его прочь. Но в диске ещё много пыли — путь можно начать снова."
	if GameState.burned_embryo:
		text.text = "Газ диска тянул тяжёлое тело к звезде, и орбиту не удалось удержать: жар расплавил и испарил зародыш. Но в диске ещё много пыли — путь можно начать снова."
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.add_theme_font_override("font", UiTheme.FONT_SERIF_ITALIC)
	text.add_theme_font_size_override("font_size", 21)
	text.add_theme_color_override("font_color", UiTheme.PARCHMENT)
	box.add_child(text)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	box.add_child(row)
	var again := Button.new()
	again.text = "Начать заново"
	again.custom_minimum_size = Vector2(250, 64)
	UiTheme.paint_button(again, true, 24)
	again.pressed.connect(_restart)
	row.add_child(again)
	var menu := Button.new()
	menu.text = "Главное меню"
	menu.custom_minimum_size = Vector2(230, 64)
	UiTheme.paint_button(menu, false, 24)
	menu.pressed.connect(func():
		GameState.reset_run()
		Fader.go(Fader.MENU))
	row.add_child(menu)

	create_tween().tween_property(self, "modulate:a", 1.0, 0.8)


func _restart() -> void:
	GameState.reset_run()
	Fader.go(Fader.GAME)


## Панель по центру экрана: растёт во все стороны под своё содержимое.
func _center(panel: Control) -> void:
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
