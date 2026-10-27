class_name PauseMenu
extends Control
## Меню паузы поверх игры: продолжить, выйти в главное меню или начать заново.
## Игра стоит, пока меню открыто.
## Пять касаний по заголовку «Пауза» открывают меню разработчика: прыжки по этапам.

var _panel: PanelContainer
var _box: VBoxContainer
var _title_taps := 0
var _dev: PanelContainer
var _dev_grid: GridContainer
var _dev_status: Label


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
	if _dev:
		_dev.queue_free()
		_dev = null
		_panel.visible = true
	visible = false
	get_tree().paused = false


func _show_main() -> void:
	_clear()
	_title_taps = 0
	var t := _title("Пауза")
	t.mouse_filter = Control.MOUSE_FILTER_STOP
	t.gui_input.connect(func(e: InputEvent):
		if (e is InputEventMouseButton or e is InputEventScreenTouch) and e.pressed:
			_title_taps += 1
			if _title_taps >= 5:
				_show_dev())
	_note("Пылинка ждёт. Звезда тоже подождёт.")
	_button("Продолжить", true, close)
	_button("Главное меню", false, func(): Fader.go(Fader.MENU))
	_button("Плавность: 120 кадров" if GameState.fps_120 else "Плавность: 60 кадров", false, func():
		GameState.fps_120 = not GameState.fps_120
		GameState.apply_fps()
		GameState.save_game()
		_show_main())
	_button("Начать заново", false, _show_confirm)


func _show_confirm() -> void:
	_clear()
	_title("Начать путь заново?")
	_note("Всё собранное и изученное будет потеряно.")
	_button("Начать заново", true, func():
		GameState.reset_run()
		Fader.go(Fader.GAME))
	_button("Отмена", false, _show_main)


## Меню разработчика — простая плотная сетка без украшений. Кнопки, которые
## не перезапускают игру, меню не закрывают: можно нажать несколько подряд.
func _show_dev() -> void:
	_panel.visible = false
	_dev = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.1, 0.96)
	style.border_color = Color(0.35, 0.38, 0.45)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	_dev.add_theme_stylebox_override("panel", style)
	_center(_dev)
	add_child(_dev)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_dev.add_child(box)
	var head := Label.new()
	head.text = "Разработчик"
	head.add_theme_font_size_override("font_size", 18)
	head.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	box.add_child(head)
	_dev_grid = GridContainer.new()
	_dev_grid.columns = 3
	_dev_grid.add_theme_constant_override("h_separation", 6)
	_dev_grid.add_theme_constant_override("v_separation", 6)
	box.add_child(_dev_grid)
	_dev_status = Label.new()
	_dev_status.add_theme_font_size_override("font_size", 14)
	_dev_status.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	box.add_child(_dev_status)

	_dev_button("Пылинка → галька", func(): _jump(29.6, 0))
	_dev_button("Галька: начало", func(): _jump(31.0, 1))
	_dev_button("Галька: ~100", func(): _jump(100.0, 1))
	_dev_button("Галька → валун", func(): _jump(2900.0, 1))
	_dev_button("Валун: начало", func(): _jump(3001.0, 2))
	_dev_button("Валун: ~100 000", func(): _jump(100000.0, 2))
	var fps := _dev_button("", func(): pass)
	var fps_text := func(): fps.text = "FPS: вкл" if Hud.show_fps else "FPS: выкл"
	fps_text.call()
	fps.pressed.connect(func():
		Hud.show_fps = not Hud.show_fps
		fps_text.call()
		_dev_say("FPS показывается" if Hud.show_fps else "FPS скрыт"))
	_dev_button("+10 000 пыли", func():
		GameState.add_currency(10000.0)
		_dev_say("Звёздная пыль: %s" % GameData.format_number(GameState.currency)))
	_dev_button("Навыки на максимум", func():
		for id in Skills.order:
			if int(Skills.nodes[id].get("requires_stage", 0)) <= GameState.stage:
				GameState.skill_levels[id] = Skills.max_level(id)
		Skills.recompute()
		GameState.skills_changed.emit()
		_dev_say("Все доступные навыки на максимуме"))
	_dev_button("Позвать Странника", func():
		var main := get_tree().current_scene
		var pf: Variant = main.get("pebble_field") if main else null
		if pf and GameState.stage == 1 and not GameState.is_boulder() and GameState.mass < Giant.MIN_MASS:
			_dev_say("Странник приходит с массы %d" % int(Giant.MIN_MASS))
		elif pf and GameState.stage == 1 and not GameState.is_boulder():
			pf.giant._timer = 0.05
			_dev_say("Странник появится, как только продолжишь")
		else:
			_dev_say("Странник бывает только на этапе гальки"))
	_dev_button("Сбросить подсказки", func():
		GameState.tips_seen = []
		GameState.save_game()
		_dev_say("Подсказки Звездочёта покажутся снова"))
	_dev_button("Назад", func():
		_dev.queue_free()
		_dev = null
		_panel.visible = true
		_show_main())


func _dev_button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(200, 44)
	b.add_theme_font_size_override("font_size", 16)
	b.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed"]:
		var st := StyleBoxFlat.new()
		st.bg_color = {"normal": Color(0.16, 0.18, 0.24), "hover": Color(0.2, 0.23, 0.3), "pressed": Color(0.28, 0.32, 0.42)}[state]
		st.set_corner_radius_all(4)
		st.set_content_margin_all(6)
		b.add_theme_stylebox_override(state, st)
	b.add_theme_color_override("font_color", Color(0.9, 0.92, 0.95))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.pressed.connect(action)
	_dev_grid.add_child(b)
	return b


func _dev_say(text: String) -> void:
	_dev_status.text = text


## Ставит массу и этап, состав растягивается под новую массу, игра перезапускается.
func _jump(mass: float, stage: int) -> void:
	var total := 0.0
	for key in GameState.materials:
		total += float(GameState.materials[key])
	if total <= 0.0:
		GameState.materials = {"silicate": 0.5, "metal": 0.15, "carbon": 0.2, "ice": 0.15}
		total = 1.0
	for key in GameState.materials:
		GameState.materials[key] = float(GameState.materials[key]) * mass / total
	GameState.mass = mass
	GameState.stage = stage
	GameState.tutorial_done = true
	# «Галька: начало» — с рассказом Звездочёта, как у нового игрока.
	GameState.pebble_intro_done = stage >= 1 and mass > 35.0
	GameState.boulder_intro_done = stage >= 2 and mass > 3100.0
	GameState.tips_seen = []
	GameState.save_game()
	Fader.go(Fader.GAME)


func _clear() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	# Панель заново подстраивается под новое содержимое.
	_panel.set_offsets_preset(Control.PRESET_CENTER)


func _title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", UiTheme.FONT_SERIF_BOLD)
	l.add_theme_font_size_override("font_size", 38)
	l.add_theme_color_override("font_color", Color(1.0, 0.84, 0.5))
	_box.add_child(l)
	return l


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
