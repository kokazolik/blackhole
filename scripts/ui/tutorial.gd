class_name Tutorial
extends Control
## Обучение с рассказчиком: Звездочёт ведёт новичка по первым шагам.
##
## Карточка с его словами стоит внизу справа (слева стик, его не закрываем),
## а пока открыта книга знаний — внизу слева, чтобы не загораживать описание
## навыка. Золотая стрелка показывает, куда смотреть или нажать. Шаг либо
## ждёт действия в игре, либо кнопку «Дальше».

const CHARS_PER_SECOND := 45.0
const CARD_WIDTH := 600.0
const STEPS := [
	{
		"id": "move",
		"text": "Здравствуй, путник. Я Звездочёт и буду рядом, пока ты осваиваешься. Коснись левой половины экрана и веди пальцем: так ты летишь.",
	},
	{
		"id": "absorb",
		"text": "Видишь крупицы вокруг? Подлети к ним: твоя слабая гравитация притянет их, и они прилипнут. Собери три пылинки.",
	},
	{
		"id": "currency",
		"text": "Каждая пылинка приносит звёздную пыль. Слева сверху видно, сколько её у тебя. За неё ты будешь узнавать новое.",
		"tap": true,
	},
	{
		"id": "composition",
		"text": "Ты состоишь из того же, что и пыль вокруг: силикатов, металла, углерода и льда. Сверху твой состав. Слева название зоны диска: ближе к звезде больше камня и металла, а за снеговой линией много льда.",
		"tap": true,
	},
	{
		"id": "big",
		"text": "Пылинки с тонким кольцом крупнее обычных. Пока тебе их не удержать, но знания помогут и с этим.",
		"tap": true,
	},
	{
		"id": "collect",
		"text": "Собери звёздную пыль на первое знание. Её хватит, когда счётчик внизу заполнится.",
	},
	{
		"id": "book",
		"text": "Хватает! Открой звёздную книгу справа сверху: в ней знания, которые делают тебя сильнее.",
	},
	{
		"id": "buy",
		"text": "Это древо знаний. Выбери «Начало» и изучи его: ты сможешь собирать пыль покрупнее.",
	},
	{
		"id": "close",
		"text": "Видишь, ветви потянулись дальше? Каждое знание открывает новые. Теперь возвращайся в полёт.",
	},
	{
		"id": "star",
		"text": "И последнее. Не подлетай близко к звезде: у неё так жарко, что пыль испаряется, а с ней и ты. Следи за надписью слева сверху. Дальше сам. Доброго пути, путник.",
		"tap": true,
		"button": "В путь",
	},
]
const NEEDS_START := ["collect", "book", "buy"]
# Звездочёт рассказывает о жизни гальки, когда пылинка дорастает до неё.
const PEBBLE_STEPS := [
	{
		"id": "p_intro",
		"text": "Поздравляю, путник: ты теперь галька, камешек размером с горошину. Ты уже так тяжёл, что отстаёшь от газа диска, и он дует тебе навстречу.",
		"tap": true,
	},
	{
		"id": "p_drift",
		"text": "Встречный ветер тормозит тебя, и ты по спирали дрейфуешь к звезде. Чем крупнее галька, тем сильнее сносит. Слева сверху видно, куда и как быстро. Держись подальше от жара.",
		"tap": true,
	},
	{
		"id": "p_collide",
		"text": "Вокруг другие гальки. Подлетай к ним медленно: зелёная дуга значит, что вы слипнетесь. Красная — удар слишком сильный, от тебя отколются осколки. Пунктир — галька крупнее тебя, её не присоединить.",
		"tap": true,
	},
	{
		"id": "p_rings",
		"text": "Видишь светлые кольца в диске? Это ловушки давления. Ветра там почти нет, и гальки копятся. Хорошее место, чтобы расти.",
		"tap": true,
	},
	{
		"id": "p_book",
		"text": "В книге знаний проросла новая ветвь, «Галька». Её знания помогут бороться с ветром и мягче сталкиваться. Твой путь к валуну начинается.",
		"tap": true,
		"button": "В путь",
	},
]

var main: Node  # сцена игры: игрок, интерфейс, древо
var steps: Array = STEPS
var pebble := false  # рассказ о гальке, а не первое обучение
var start_delay := 2.2
var _step := -1
var _card: PanelContainer
var _name: Label
var _text: Label
var _progress: Label
var _next: Button
var _emblem: Control
var _pointer: Control
var _shown := 0.0
var _time := 0.0
var _step_time := 0.0
var _absorbed := 0
var _moved := 0.0
var _target := Vector2.INF  # куда показывает стрелка (экран), INF — никуда
var _done := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.get_theme()
	_build()
	GameState.absorbed.connect(func(_a, _b, _c): _absorbed += 1)
	modulate.a = 0.0
	# Рассказчик появляется, когда камера уже приблизилась к пылинке.
	var tw := create_tween()
	tw.tween_interval(start_delay)
	tw.tween_callback(_show_step.bind(0))
	tw.tween_property(self, "modulate:a", 1.0, 0.8)


func _build() -> void:
	_pointer = Control.new()
	_pointer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pointer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pointer.draw.connect(_draw_pointer)
	add_child(_pointer)

	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", UiTheme.painted_panel(22))
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	# Карточка стоит на нижнем крае и растёт вверх под длину реплики.
	_card.anchor_top = 1.0
	_card.anchor_bottom = 1.0
	_card.offset_top = -20.0
	_card.offset_bottom = -20.0
	_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_card.gui_input.connect(_on_card_input)
	add_child(_card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(row)
	_emblem = Control.new()
	_emblem.custom_minimum_size = Vector2(64, 64)
	_emblem.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_emblem.draw.connect(_draw_emblem)
	row.add_child(_emblem)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	_name = Label.new()
	_name.text = "Звездочёт"
	_name.add_theme_font_override("font", UiTheme.FONT_SERIF_BOLD)
	_name.add_theme_font_size_override("font_size", 20)
	_name.add_theme_color_override("font_color", Color(1.0, 0.82, 0.48))
	col.add_child(_name)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	_text.add_theme_font_override("font", UiTheme.FONT_SERIF_ITALIC)
	_text.add_theme_font_size_override("font_size", 20)
	_text.add_theme_color_override("font_color", UiTheme.PARCHMENT)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_text)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(bottom)
	_progress = Label.new()
	_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_progress.add_theme_font_override("font", UiTheme.FONT_SERIF_BOLD)
	_progress.add_theme_font_size_override("font_size", 19)
	_progress.add_theme_color_override("font_color", Color(1.0, 0.82, 0.48))
	bottom.add_child(_progress)
	var skip := Button.new()
	skip.text = "Пропустить обучение"
	skip.flat = true
	skip.focus_mode = Control.FOCUS_NONE
	skip.add_theme_font_override("font", UiTheme.FONT_SERIF_ITALIC)
	skip.add_theme_font_size_override("font_size", 16)
	for key in ["font_color", "font_hover_color", "font_pressed_color"]:
		skip.add_theme_color_override(key, Color(UiTheme.PARCHMENT, 0.5))
	for state in ["normal", "hover", "pressed", "focus"]:
		skip.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	skip.pressed.connect(_finish)
	bottom.add_child(skip)
	_next = Button.new()
	_next.text = "Дальше"
	_next.custom_minimum_size = Vector2(150, 48)
	UiTheme.paint_button(_next, true, 20)
	_next.pressed.connect(_advance)
	bottom.add_child(_next)


func _show_step(i: int) -> void:
	if i >= steps.size():
		_finish()
		return
	var step: Dictionary = steps[i]
	# Кто уже изучил «Начало» (старое сохранение), тому эти шаги не нужны.
	if step.id in NEEDS_START and Skills.is_owned("start"):
		_show_step(i + 1)
		return
	_step = i
	_step_time = 0.0
	_shown = 0.0
	_absorbed = 0
	_moved = 0.0
	_text.text = step.text
	_text.visible_characters = 0
	_next.text = step.get("button", "Дальше")
	_next.visible = false
	_progress.text = ""
	# Новая реплика: карточка чуть вздрагивает, привлекая взгляд.
	_card.pivot_offset = _card.size * 0.5
	_card.scale = Vector2(0.97, 0.97)
	create_tween().tween_property(_card, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _advance() -> void:
	if _step < 0 or _done:
		return
	_show_step(_step + 1)


func _on_card_input(event: InputEvent) -> void:
	var tap: bool = (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
		or (event is InputEventScreenTouch and event.pressed)
	# Касание карточки допечатывает реплику сразу.
	if tap and _step >= 0 and _shown < _text.text.length():
		_shown = _text.text.length()
		_text.visible_characters = -1


func _finish() -> void:
	if _done:
		return
	_done = true
	if pebble:
		GameState.pebble_intro_done = true
	else:
		GameState.tutorial_done = true
	GameState.save_game()
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.6)
	tw.tween_callback(queue_free)


func _process(delta: float) -> void:
	_time += delta
	var tree: SkillTreeScreen = main.tree_screen
	var hud: Hud = main.hud
	# В меню паузы и после гибели рассказчик молчит.
	visible = not main.player.dead and not main.pause_menu.visible
	_layout(tree.visible)
	_pointer.queue_redraw()
	_emblem.queue_redraw()
	if _step < 0 or _done or not visible:
		return
	_step_time += delta
	var full := _text.text.length()
	if _shown < full:
		_shown = minf(_shown + CHARS_PER_SECOND * delta, full)
		_text.visible_characters = int(_shown)
	var step: Dictionary = steps[_step]
	var typed := _shown >= full
	_next.visible = step.get("tap", false) and typed
	_target = Vector2.INF
	match step.id:
		"move":
			_target = Vector2(VirtualJoystick.RADIUS + 60.0, size.y - VirtualJoystick.RADIUS - 50.0)
			if main.joystick.output.length() > 0.3:
				_moved += delta
				_target = Vector2.INF
			if _moved > 1.2:
				_advance()
		"absorb":
			_progress.text = "%d / 3" % mini(_absorbed, 3)
			if _absorbed >= 3:
				_advance()
		"currency":
			_target = _center_of(hud._currency_label)
		"composition":
			_target = _center_of(hud._comp_bar)
		"collect":
			var cost := Skills.cost("start")
			_progress.text = "%d / %d" % [mini(int(GameState.currency), int(cost)), int(cost)]
			_target = _center_of(hud._currency_label)
			if GameState.currency >= cost:
				_advance()
		"book":
			_target = _center_of(hud._tree_button)
			if tree.visible:
				_advance()
		"buy":
			if Skills.is_owned("start"):
				_advance()
			elif tree._selected == "start":
				_target = _center_of(tree._buy_button)
			else:
				_target = tree._canvas.get_global_transform() * tree._node_pos("start")
		"close":
			_target = _center_of(tree.close_button)
			if not tree.visible:
				_advance()
		"p_drift":
			_target = _center_of(hud._wind_label)
		"p_book":
			_target = _center_of(hud._tree_button)


func _center_of(c: Control) -> Vector2:
	return c.get_global_rect().get_center()


## Внизу справа в полёте, внизу слева над древом знаний.
func _layout(tree_open: bool) -> void:
	var w := CARD_WIDTH
	if tree_open:
		w = minf(CARD_WIDTH, size.x - SkillTreeScreen.INFO_WIDTH - 72.0)
	var x := 24.0 if tree_open else size.x - w - 24.0
	_card.offset_left = x
	_card.offset_right = x + w


## Медальон Звездочёта: тёмный круг, золотой обод и восьмилучевая звезда,
## вокруг которой по орбите бежит пылинка.
func _draw_emblem() -> void:
	var c := _emblem.size * 0.5
	var r := 30.0
	_emblem.draw_circle(c, r, Color(0.08, 0.05, 0.16))
	_emblem.draw_circle(c, r * 0.8, Color(0.14, 0.08, 0.24))
	_emblem.draw_arc(c, r, 0.0, TAU, 64, Color(1.0, 0.8, 0.45), 2.5, true)
	_emblem.draw_arc(c, r - 4.0, 0.0, TAU, 64, Color(1.0, 0.8, 0.45, 0.45), 1.0, true)
	var pts := PackedVector2Array()
	var spin := _time * 0.3
	for i in 16:
		var a := spin + i * TAU / 16.0
		var len := r * (0.62 if i % 4 == 0 else (0.36 if i % 2 == 0 else 0.16))
		pts.append(c + Vector2.from_angle(a) * len)
	_emblem.draw_colored_polygon(pts, Color(1.0, 0.86, 0.55))
	_emblem.draw_circle(c, 3.5, Color(1.0, 0.97, 0.88))
	var orbit := c + Vector2.from_angle(-_time * 1.4) * Vector2(r * 0.72, r * 0.72)
	_emblem.draw_circle(orbit, 2.2, Color(0.75, 0.88, 1.0))


## Стрелка покачивается и указывает на цель, вокруг цели расходятся кольца.
func _draw_pointer() -> void:
	if _target == Vector2.INF or not visible:
		return
	var t := _target
	var gold := Color(1.0, 0.82, 0.45)
	for k in 2:
		var p := fmod(_time * 0.8 + k * 0.5, 1.0)
		_pointer.draw_arc(t, 18.0 + 34.0 * p, 0.0, TAU, 48, Color(gold, 0.7 * (1.0 - p)), 2.5, true)
	var dir := (size * 0.5 - t).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.DOWN
	var bob := 8.0 * sin(_time * 5.0)
	var tip := t + dir * (44.0 + bob)
	var tail := tip + dir * 54.0
	var side := dir.orthogonal()
	var head := PackedVector2Array([tip, tip + dir * 22.0 + side * 15.0, tip + dir * 22.0 - side * 15.0])
	var outline := Color(0.12, 0.05, 0.0, 0.8)
	_pointer.draw_line(tip + dir * 18.0, tail, outline, 10.0, true)
	_pointer.draw_colored_polygon(PackedVector2Array([tip - dir * 3.0, head[1] + dir * 2.0 + side * 3.0, head[2] + dir * 2.0 - side * 3.0]), outline)
	_pointer.draw_line(tip + dir * 18.0, tail, gold, 6.0, true)
	_pointer.draw_colored_polygon(head, gold)
