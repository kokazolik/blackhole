class_name SkillTreeScreen
extends Control
## Экран древа: игра на паузе, древо двигается пальцем и масштабируется щипком.

signal closed

const SPACING := 170.0
const INFO_WIDTH := 360.0
const NODE_RADIUS := 42.0
const TAP_SLOP := 14.0
const ZOOM_RANGE := Vector2(0.5, 1.8)

const COLOR_LOCKED := Color(0.35, 0.37, 0.45)
const COLOR_AVAILABLE := Color(0.55, 0.75, 1.0)
const COLOR_AFFORDABLE := Color(1.0, 0.82, 0.45)
const COLOR_OWNED := Color(0.75, 0.95, 0.8)

var _canvas: Control
var _currency_label: Label
var _info: PanelContainer
var _info_title: Label
var _info_desc: RichTextLabel
var _info_level: Label
var _buy_button: Button
var _selected := ""
var _press_pos := Vector2.ZERO
var _dragging := false
var _pressed := false
var _touches := {}
var _pinch_dist := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()
	GameState.currency_changed.connect(_refresh.unbind(1))
	GameState.skills_changed.connect(_refresh)


func open() -> void:
	visible = true
	get_tree().paused = true
	_canvas.scale = Vector2.ONE
	_canvas.position = Vector2((size.x - INFO_WIDTH) * 0.5, size.y * 0.5) - _node_pos("start")
	_select("" if Skills.is_owned("start") else "start")
	_refresh()


func close() -> void:
	visible = false
	get_tree().paused = false
	closed.emit()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.06, 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_tree)
	add_child(_canvas)

	_currency_label = Label.new()
	_currency_label.position = Vector2(24, 18)
	_currency_label.add_theme_font_size_override("font_size", 40)
	_currency_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.5))
	add_child(_currency_label)

	var close_btn := Button.new()
	close_btn.text = "Назад"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_font_size_override("font_size", 28)
	close_btn.anchor_left = 1.0
	close_btn.anchor_right = 1.0
	close_btn.offset_left = -194
	close_btn.offset_right = -24
	close_btn.offset_top = 20
	close_btn.offset_bottom = 96
	close_btn.pressed.connect(close)
	add_child(close_btn)

	_info = PanelContainer.new()
	# Панель справа: в горизонтальном режиме не перекрывает древо.
	_info.anchor_left = 1.0
	_info.anchor_right = 1.0
	_info.anchor_top = 0.0
	_info.anchor_bottom = 1.0
	_info.offset_left = -INFO_WIDTH - 24
	_info.offset_right = -24
	_info.offset_top = 116
	_info.offset_bottom = -24
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.13, 0.96)
	style.border_color = Color(0.4, 0.5, 0.8, 0.6)
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(16)
	_info.add_theme_stylebox_override("panel", style)
	add_child(_info)

	var text_box := VBoxContainer.new()
	text_box.add_theme_constant_override("separation", 12)
	_info.add_child(text_box)

	_info_title = Label.new()
	_info_title.add_theme_font_size_override("font_size", 28)
	text_box.add_child(_info_title)
	_info_desc = RichTextLabel.new()
	_info_desc.bbcode_enabled = true
	_info_desc.fit_content = true
	_info_desc.scroll_active = false
	_info_desc.add_theme_font_size_override("normal_font_size", 22)
	text_box.add_child(_info_desc)
	_info_level = Label.new()
	_info_level.add_theme_font_size_override("font_size", 18)
	_info_level.add_theme_color_override("font_color", Color(0.7, 0.75, 0.9))
	text_box.add_child(_info_level)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_box.add_child(spacer)

	_buy_button = Button.new()
	_buy_button.custom_minimum_size = Vector2(0, 76)
	_buy_button.add_theme_stylebox_override("normal", _button_style(Color(0.85, 0.62, 0.2)))
	_buy_button.add_theme_stylebox_override("hover", _button_style(Color(0.95, 0.72, 0.3)))
	_buy_button.add_theme_stylebox_override("pressed", _button_style(Color(0.75, 0.52, 0.15)))
	_buy_button.add_theme_stylebox_override("disabled", _button_style(Color(0.2, 0.21, 0.27)))
	_buy_button.add_theme_color_override("font_color", Color(0.08, 0.06, 0.02))
	_buy_button.add_theme_color_override("font_hover_color", Color(0.08, 0.06, 0.02))
	_buy_button.add_theme_color_override("font_pressed_color", Color(0.08, 0.06, 0.02))
	_buy_button.add_theme_color_override("font_disabled_color", Color(0.55, 0.57, 0.65))
	_buy_button.focus_mode = Control.FOCUS_NONE
	_buy_button.add_theme_font_size_override("font_size", 24)
	_buy_button.pressed.connect(_on_buy)
	text_box.add_child(_buy_button)


func _button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(12)
	return style


func _node_pos(id: String) -> Vector2:
	var p: Array = Skills.nodes[id].pos
	return Vector2(p[0], p[1]) * SPACING


func _select(id: String) -> void:
	_selected = id
	_refresh()


func _on_buy() -> void:
	if _selected != "":
		Skills.buy(_selected)


func _refresh() -> void:
	if not is_node_ready():
		return
	_currency_label.text = "✦ " + GameData.format_number(GameState.currency)
	_info.visible = _selected != ""
	if _selected != "":
		var node: Dictionary = Skills.nodes[_selected]
		var unlocked := Skills.is_unlocked(_selected)
		_info_title.text = node.title if unlocked else "???"
		_info_desc.text = node.desc if unlocked else "Откроется, когда купишь соседний навык."
		_info_level.text = "Уровень %d / %d" % [Skills.level(_selected), Skills.max_level(_selected)]
		if Skills.is_maxed(_selected):
			_buy_button.text = "Изучено"
			_buy_button.disabled = true
		else:
			_buy_button.text = "✦ " + GameData.format_number(Skills.cost(_selected))
			_buy_button.disabled = not Skills.can_buy(_selected)
	_canvas.queue_redraw()


func _draw_tree() -> void:
	var font := get_theme_default_font()
	# Связи.
	for id in Skills.order:
		if not Skills.is_discovered(id):
			continue
		for req in Skills.nodes[id].get("requires", []):
			if not Skills.is_discovered(req):
				continue
			var active := Skills.is_owned(req)
			var col := Color(0.6, 0.75, 1.0, 0.55) if active else Color(0.4, 0.42, 0.5, 0.25)
			_canvas.draw_line(_node_pos(req), _node_pos(id), col, 4.0 if active else 2.0, true)
	# Узлы.
	for id in Skills.order:
		if not Skills.is_discovered(id):
			continue
		var p := _node_pos(id)
		var unlocked := Skills.is_unlocked(id)
		var col := COLOR_LOCKED
		if Skills.is_owned(id):
			col = COLOR_OWNED
		elif Skills.can_buy(id):
			col = COLOR_AFFORDABLE
		elif unlocked:
			col = COLOR_AVAILABLE
		if id == _selected:
			_canvas.draw_circle(p, NODE_RADIUS + 10.0, Color(col, 0.25))
		_canvas.draw_circle(p, NODE_RADIUS, Color(0.05, 0.06, 0.1))
		if Skills.is_owned(id):
			var fill := float(Skills.level(id)) / Skills.max_level(id)
			_canvas.draw_circle(p, NODE_RADIUS * (0.35 + 0.55 * fill), Color(col, 0.55))
		_canvas.draw_arc(p, NODE_RADIUS, 0.0, TAU, 40, col, 4.0, true)
		var title: String = Skills.nodes[id].title if unlocked else "???"
		_draw_centered(font, p + Vector2(0, NODE_RADIUS + 28.0), title, 20, Color(col, 0.95))
		if unlocked and Skills.max_level(id) > 1:
			_draw_centered(font, p + Vector2(0, 8.0), "%d/%d" % [Skills.level(id), Skills.max_level(id)], 18, Color.WHITE)


func _draw_centered(font: Font, pos: Vector2, text: String, font_size: int, color: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_canvas.draw_string(font, pos - Vector2(w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _hit_test(screen_pos: Vector2) -> String:
	var local := (screen_pos - _canvas.position) / _canvas.scale.x
	for id in Skills.order:
		if Skills.is_discovered(id) and local.distance_to(_node_pos(id)) <= NODE_RADIUS + 12.0:
			return id
	return ""


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_pressed = true
				_dragging = false
				_press_pos = event.position
			elif _pressed:
				_pressed = false
				if not _dragging and _touches.size() < 2:
					_select(_hit_test(event.position))
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(event.position, 1.1)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(event.position, 1.0 / 1.1)
	elif event is InputEventMouseMotion and _pressed and _touches.size() < 2:
		if not _dragging and event.position.distance_to(_press_pos) > TAP_SLOP:
			_dragging = true
		if _dragging:
			_canvas.position += event.relative
			_canvas.queue_redraw()
	elif event is InputEventMagnifyGesture:
		_zoom_at(event.position, event.factor)


func _notification(what: int) -> void:
	# Кнопка «назад» на Android закрывает древо.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and visible:
		close()


## Щипок двумя пальцами, а на ПК Tab/Esc закрывают древо.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_TAB, KEY_ESCAPE]:
		close()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		_pinch_dist = _current_pinch_dist()
		if _touches.size() >= 2:
			_dragging = true
	elif event is InputEventScreenDrag and _touches.has(event.index):
		_touches[event.index] = event.position
		if _touches.size() >= 2:
			var d := _current_pinch_dist()
			if _pinch_dist > 0.0:
				var mid: Vector2 = (_touches.values()[0] + _touches.values()[1]) * 0.5
				_zoom_at(mid, d / _pinch_dist)
			_pinch_dist = d


func _current_pinch_dist() -> float:
	if _touches.size() < 2:
		return 0.0
	var v := _touches.values()
	return (v[0] as Vector2).distance_to(v[1])


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var old := _canvas.scale.x
	var new_scale := clampf(old * factor, ZOOM_RANGE.x, ZOOM_RANGE.y)
	_canvas.position = screen_pos - (screen_pos - _canvas.position) * (new_scale / old)
	_canvas.scale = Vector2(new_scale, new_scale)
	_canvas.queue_redraw()
