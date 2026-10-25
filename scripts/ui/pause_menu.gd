class_name PauseMenu
extends Control
## Меню паузы поверх игры: продолжить, выйти в главное меню или начать заново.
## Игра стоит, пока меню открыто.

var _panel: PanelContainer
var _box: VBoxContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiTheme.get_theme()
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.03, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiTheme.painted_panel(36))
	_center(_panel)
	add_child(_panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 16)
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_child(_box)


func open() -> void:
	if visible:
		return
	visible = true
	get_tree().paused = true
	_show_main()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.18)


func close() -> void:
	visible = false
	get_tree().paused = false


func _show_main() -> void:
	_clear()
	_title("Пауза")
	_note("Пылинка ждёт. Звезда тоже подождёт.")
	_button("Продолжить", true, close)
	_button("Главное меню", false, func(): Fader.go(Fader.MENU))
	_button("Начать заново", false, _show_confirm)


func _show_confirm() -> void:
	_clear()
	_title("Начать путь заново?")
	_note("Всё собранное и изученное будет потеряно.")
	_button("Начать заново", true, func():
		GameState.reset_run()
		Fader.go(Fader.GAME))
	_button("Отмена", false, _show_main)


func _clear() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	# Панель заново подстраивается под новое содержимое.
	_panel.set_offsets_preset(Control.PRESET_CENTER)


func _title(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", UiTheme.FONT_SERIF_BOLD)
	l.add_theme_font_size_override("font_size", 38)
	l.add_theme_color_override("font_color", Color(1.0, 0.84, 0.5))
	_box.add_child(l)


func _note(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", UiTheme.FONT_SERIF_ITALIC)
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", UiTheme.PARCHMENT)
	_box.add_child(l)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	_box.add_child(gap)


func _button(text: String, primary: bool, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(360, 62)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UiTheme.paint_button(b, primary, 24)
	b.pressed.connect(action)
	_box.add_child(b)


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


## Панель по центру экрана: растёт во все стороны под своё содержимое.
func _center(panel: Control) -> void:
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
