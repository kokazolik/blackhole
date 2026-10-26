class_name SkillTreeScreen
extends Control
## Экран древа: игра на паузе, древо двигается пальцем и масштабируется щипком.
##
## Фон — рисованный космос. Видны только узлы, которые уже можно купить:
## ветки никуда не ведут заранее, а вырастают к новым узлам после покупки.

signal closed

const SPACING := 170.0
const INFO_WIDTH := 360.0
const NODE_RADIUS := 42.0
const TAP_SLOP := 14.0
const ZOOM_RANGE := Vector2(0.5, 1.8)

const BG_TEXTURE := preload("res://assets/ui/tree_bg.png")
const BG_PARALLAX := 0.15
const GROW_TIME := 0.9    # сколько растёт ветка к новому узлу
const APPEAR_TIME := 0.55  # сколько узел «распускается» после ветки
const BRANCH_STAGGER := 0.25

const COLOR_AVAILABLE := Color(0.62, 0.72, 0.95)
const COLOR_AFFORDABLE := Color(1.0, 0.82, 0.45)
const COLOR_OWNED := Color(0.78, 0.62, 0.42)
const COLOR_MAXED := Color(0.55, 0.88, 0.72)
const COLOR_BLOCKED := Color(0.42, 0.4, 0.46)
# Цвет ободка у веток веществ: путь виден сразу, ещё до выбора.
const PATH_COLORS := {
	"silicate": Color(0.87, 0.77, 0.58), "metal": Color(0.75, 0.8, 0.9),
	"carbon": Color(0.72, 0.5, 0.42), "ice": Color(0.6, 0.85, 1.0),
}
const BRANCH_COLOR := Color(0.95, 0.78, 0.45)

var _canvas: Node2D  # общий сдвиг и масштаб древа; рисуют три слоя внутри
# Слои: под узлами — свечение и искры (каждый кадр), сами узлы, ветки и подписи
# (только когда что-то поменялось), поверх — вращающиеся украшения (каждый кадр).
# Подписи с обводкой и сглаженные дуги дороги, поэтому статичное не перерисовывается.
var _layer_under := Node2D.new()
var _layer_static := Node2D.new()
var _layer_over := Node2D.new()
var _g: CanvasItem  # слой, в который сейчас рисуем
var _colors := {}   # цвет узла, считается при перерисовке статичного слоя
var _anim_until := 0.0  # до этого времени ветки растут и узлы распускаются
var _view := Rect2()    # видимая часть древа в его координатах (с запасом)
var _currency_label: Label
var _info: PanelContainer
var _info_title: Label
var _info_desc: RichTextLabel
var _info_level: Label
var _buy_button: Button
var close_button: Button
var _selected := ""
var _press_pos := Vector2.ZERO
var _dragging := false
var _pressed := false
var _touches := {}
var _pinch_dist := 0.0
var _time := 0.0
var _bg: TextureRect
var _glow := _make_glow()
var _edges := {}       # "родитель>узел" -> время начала роста
var _node_shown := {}  # узел -> время, когда начинает появляться
var _bursts := {}      # узел -> время покупки (вспышка)


static func _make_glow() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.3, Color(1, 1, 1, 0.35))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	return tex


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiTheme.get_theme()
	visible = false
	_build()
	GameState.currency_changed.connect(_refresh.unbind(1))
	GameState.skills_changed.connect(_on_skills_changed)


func open() -> void:
	visible = true
	get_tree().paused = true
	_canvas.scale = Vector2.ONE
	_canvas.position = Vector2((size.x - INFO_WIDTH) * 0.5, size.y * 0.5) - _node_pos("start")
	_sync_branches(false)
	_select("" if Skills.is_owned("start") else "start")
	_refresh()


func _on_skills_changed() -> void:
	_sync_branches(visible)
	_refresh()


## Ветка идёт от купленного узла к узлу, который стал доступен. Новые ветки
## растут по очереди, а узел на конце распускается, когда ветка дотянется.
func _sync_branches(animate: bool) -> void:
	if not animate:
		_edges.clear()
		_node_shown.clear()
	var delay := 0.0
	for id in Skills.order:
		# Пути веществ видны сразу, как только открыта «Избирательность»: игрок
		# заранее видит развилку. Закрытые пути остаются на виду — серыми, с замком.
		var is_path: bool = Skills.nodes[id].get("path", "") != ""
		if not Skills.is_unlocked(id) and not is_path:
			continue
		var reqs: Array = Skills.nodes[id].get("requires", [])
		if reqs.is_empty() and not _node_shown.has(id):
			_node_shown[id] = -INF
		for req in reqs:
			var key: String = req + ">" + id
			if _edges.has(key) or not Skills.is_owned(req):
				continue
			var start := _time + delay if animate else -INF
			_edges[key] = start
			if animate:
				delay += BRANCH_STAGGER
			if not _node_shown.has(id):
				_node_shown[id] = start + GROW_TIME
				_anim_until = maxf(_anim_until, start + GROW_TIME + APPEAR_TIME + 0.1)
	_layer_static.queue_redraw()


func close() -> void:
	visible = false
	get_tree().paused = false
	closed.emit()


func _build() -> void:
	var under := ColorRect.new()
	under.color = Color(0.02, 0.02, 0.06)
	under.set_anchors_preset(Control.PRESET_FULL_RECT)
	under.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(under)
	# Рисованный космос чуть больше экрана: сдвигается вслед за древом (параллакс).
	_bg = TextureRect.new()
	_bg.texture = BG_TEXTURE
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	# Node2D, а не Control: Control отсекает рисование по своему (нулевому) размеру,
	# и древо пропадало целиком, когда его начало уезжало за верх экрана.
	_canvas = Node2D.new()
	add_child(_canvas)
	for layer in [_layer_under, _layer_static, _layer_over]:
		_canvas.add_child(layer)
	_layer_under.draw.connect(_draw_under)
	_layer_static.draw.connect(_draw_static)
	_layer_over.draw.connect(_draw_over)

	_currency_label = Label.new()
	_currency_label.position = Vector2(28, 20)
	_currency_label.add_theme_font_size_override("font_size", 40)
	_currency_label.add_theme_font_override("font", UiTheme.FONT_NUMBERS)
	_currency_label.add_theme_color_override("font_color", UiTheme.GOLD)
	add_child(_currency_label)

	var close_btn := Button.new()
	close_button = close_btn
	close_btn.text = "Закрыть книгу"
	UiTheme.paint_button(close_btn, false, 22)
	close_btn.anchor_left = 1.0
	close_btn.anchor_right = 1.0
	close_btn.offset_left = -INFO_WIDTH - 24
	close_btn.offset_right = -24
	close_btn.offset_top = 24
	close_btn.offset_bottom = 90
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
	_info.offset_top = 104
	_info.offset_bottom = -24
	_info.add_theme_stylebox_override("panel", UiTheme.painted_panel(28))
	add_child(_info)

	# Заголовок книги по центру над древом.
	var heading := Label.new()
	heading.text = "Книга звёздных знаний"
	heading.anchor_right = 1.0
	heading.offset_right = -INFO_WIDTH - 48
	heading.offset_top = 22
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_theme_font_override("font", UiTheme.FONT_SERIF_BOLD)
	heading.add_theme_font_size_override("font_size", 32)
	heading.add_theme_color_override("font_color", Color(1.0, 0.84, 0.5))
	heading.add_theme_color_override("font_outline_color", Color(0.1, 0.04, 0.0, 0.8))
	heading.add_theme_constant_override("outline_size", 6)
	add_child(heading)

	var text_box := VBoxContainer.new()
	text_box.add_theme_constant_override("separation", 12)
	_info.add_child(text_box)

	_info_title = Label.new()
	_info_title.add_theme_font_size_override("font_size", 32)
	_info_title.add_theme_font_override("font", UiTheme.FONT_SERIF_BOLD)
	text_box.add_child(_info_title)
	_info_desc = RichTextLabel.new()
	_info_desc.bbcode_enabled = true
	_info_desc.fit_content = true
	_info_desc.scroll_active = false
	_info_desc.add_theme_font_override("normal_font", UiTheme.FONT_SERIF)
	_info_desc.add_theme_font_size_override("normal_font_size", 21)
	_info_desc.add_theme_color_override("default_color", UiTheme.PARCHMENT)
	text_box.add_child(_info_desc)
	_info_level = Label.new()
	_info_level.add_theme_font_override("font", UiTheme.FONT_SERIF_ITALIC)
	_info_level.add_theme_font_size_override("font_size", 19)
	_info_level.add_theme_color_override("font_color", Color(UiTheme.PARCHMENT, 0.6))
	text_box.add_child(_info_level)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_box.add_child(spacer)

	_buy_button = Button.new()
	_buy_button.custom_minimum_size = Vector2(0, 70)
	UiTheme.paint_button(_buy_button, true, 24)
	_buy_button.pressed.connect(_on_buy)
	text_box.add_child(_buy_button)


func _node_pos(id: String) -> Vector2:
	var p: Array = Skills.nodes[id].pos
	return Vector2(p[0], p[1]) * SPACING


func _select(id: String) -> void:
	_selected = id
	_refresh()


func _on_buy() -> void:
	if _selected != "" and Skills.buy(_selected):
		_bursts[_selected] = _time


func _refresh() -> void:
	if not is_node_ready():
		return
	_currency_label.text = "✦ " + GameData.format_number(GameState.currency)
	_info.visible = _selected != ""
	if _selected != "":
		var node: Dictionary = Skills.nodes[_selected]
		_info_title.text = node.title
		_info_title.add_theme_color_override("font_color", UiTheme.GOLD)
		_info_desc.text = node.desc
		_info_level.text = "Изучено %d из %d" % [Skills.level(_selected), Skills.max_level(_selected)]
		if node.get("legendary", false):
			_info_level.text = "Легендарный навык" + (" · изучен" if Skills.is_owned(_selected) else "")
		var blocker := Skills.blocked_by(_selected)
		if blocker != "":
			_info_level.text = "Путь закрыт: выбрано «%s»" % Skills.nodes[blocker].title
			_buy_button.text = "Путь закрыт"
			_buy_button.disabled = true
		elif Skills.is_maxed(_selected):
			_buy_button.text = "Изучено"
			_buy_button.disabled = true
		else:
			var price := GameData.format_number(Skills.cost(_selected))
			_buy_button.disabled = not Skills.can_buy(_selected)
			_buy_button.text = ("Нужно " if _buy_button.disabled else "Изучить за ") + price
			if not Skills.is_unlocked(_selected):
				var req: Array = node.get("requires", [])
				var lv := int(node.get("requires_level", 1))
				if not req.is_empty():
					_buy_button.text = "Нужно: %s ур. %d" % [Skills.nodes[req[0]].title, lv]
	_layer_static.queue_redraw()


func _process(delta: float) -> void:
	# Узлы пульсируют, ветки растут и по ним бегут искры, поэтому перерисовка каждый кадр.
	if visible:
		_time += delta
		_layout_bg()
		var inv := 1.0 / _canvas.scale.x
		_view = Rect2(-_canvas.position * inv, size * inv).grow(NODE_RADIUS * 4.0)
		_layer_under.queue_redraw()
		_layer_over.queue_redraw()
		if _time < _anim_until:
			_layer_static.queue_redraw()


func _layout_bg() -> void:
	var margin := size * 0.12
	_bg.size = size + margin * 2.0
	var shift := (_canvas.position - size * 0.5) * BG_PARALLAX
	_bg.position = -margin + shift.clamp(-margin, margin)


func _is_visible_node(id: String) -> bool:
	return _node_shown.has(id) and _time >= float(_node_shown[id])


func _draw_under() -> void:
	_g = _layer_under
	for key in _edges:
		var t: float = (_time - float(_edges[key])) / GROW_TIME
		if t > 0.0:
			var parts: PackedStringArray = (key as String).split(">")
			var a := _node_pos(parts[0])
			var b := _node_pos(parts[1])
			if _view.intersects(Rect2(a, Vector2.ZERO).expand(b)):
				_draw_branch_fx(a, b, minf(t, 1.0), absi((key as String).hash()))
	for id in Skills.order:
		if _is_visible_node(id) and _view.has_point(_node_pos(id)):
			_draw_node_under(id, _node_pos(id), _appear(id))
	_g.draw_set_transform(Vector2.ZERO)


func _draw_static() -> void:
	_g = _layer_static
	for key in _edges:
		var t: float = (_time - float(_edges[key])) / GROW_TIME
		if t > 0.0:
			var parts: PackedStringArray = (key as String).split(">")
			_draw_branch(_node_pos(parts[0]), _node_pos(parts[1]), minf(t, 1.0), absi((key as String).hash()))
	for id in Skills.order:
		if _is_visible_node(id):
			_draw_node(id, _node_pos(id), _appear(id))
	_g.draw_set_transform(Vector2.ZERO)
	_draw_path_fork()


func _draw_over() -> void:
	_g = _layer_over
	for id in Skills.order:
		if _is_visible_node(id) and _view.has_point(_node_pos(id)):
			_draw_node_over(id, _node_pos(id), _appear(id))
	_g.draw_set_transform(Vector2.ZERO)


func _appear(id: String) -> float:
	return clampf((_time - float(_node_shown[id])) / APPEAR_TIME, 0.0, 1.0)


## Над четырьмя ветками веществ — надпись о развилке: выбрать можно только одну.
func _draw_path_fork() -> void:
	var xs: Array[float] = []
	var y := INF
	for id in Skills.order:
		if Skills.nodes[id].get("path", "") != "" and _is_visible_node(id):
			var p := _node_pos(id)
			if p.y <= y + 1.0:
				if p.y < y - 1.0:
					xs.clear()
				y = minf(y, p.y)
				xs.append(p.x)
	if xs.size() < 2:
		return
	var a: float = xs.min()
	var b: float = xs.max()
	var chosen := Skills.chosen_path()
	var text := "развилка: выбери одно вещество" if chosen == "" else "путь выбран"
	var col := Color(1.0, 0.85, 0.55, 0.85) if chosen == "" else Color(0.7, 0.66, 0.6, 0.6)
	var ly := y - NODE_RADIUS - 30.0
	# Пунктирная скобка над ветками.
	var x := a
	while x < b:
		_g.draw_line(Vector2(x, ly + 12.0), Vector2(minf(x + 10.0, b), ly + 12.0), col, 2.0, true)
		x += 18.0
	_g.draw_line(Vector2(a, ly + 12.0), Vector2(a, ly + 22.0), col, 2.0, true)
	_g.draw_line(Vector2(b, ly + 12.0), Vector2(b, ly + 22.0), col, 2.0, true)
	var font: Font = UiTheme.FONT_SERIF_ITALIC
	var fs := 20
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var mid := (a + b) * 0.5
	_g.draw_rect(Rect2(mid - w * 0.5 - 8.0, ly - 10.0, w + 16.0, 28.0), Color(0.05, 0.03, 0.1, 0.85))
	_g.draw_string(font, Vector2(mid - w * 0.5, ly + 10.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## Ветка — изогнутый золотой стебель с почками. Пока растёт, на кончике искра;
## выросшая ветка изредка пропускает по себе огонёк от родителя к узлу.
func _draw_branch(a: Vector2, b: Vector2, t: float, seed_hash: int) -> void:
	var grow := 1.0 - pow(1.0 - t, 3.0)
	var bend := (b - a).orthogonal() * (0.16 if seed_hash % 2 == 0 else -0.16)
	var ctrl := (a + b) * 0.5 + bend
	# Ветка выходит из ободка узла, а не из центра, и упирается в ободок нового.
	a += (ctrl - a).normalized() * NODE_RADIUS
	b += (ctrl - b).normalized() * NODE_RADIUS
	var pts := PackedVector2Array()
	var n := 24
	var last := 0
	for i in n + 1:
		var u := float(i) / n
		if u > grow:
			break
		pts.append(a.lerp(ctrl, u).lerp(ctrl.lerp(b, u), u))
		last = i
	var tip := a.lerp(ctrl, grow).lerp(ctrl.lerp(b, grow), grow)
	if last < n:
		pts.append(tip)
	if pts.size() < 2:
		return
	_g.draw_polyline(pts, Color(BRANCH_COLOR, 0.10), 12.0, true)
	_g.draw_polyline(pts, Color(BRANCH_COLOR, 0.25), 6.0, true)
	_g.draw_polyline(pts, Color(BRANCH_COLOR.lightened(0.2), 0.9), 2.5, true)
	# Почки-завитки вдоль ветки.
	for j in 3:
		var u := 0.25 + 0.22 * j
		if u > grow:
			break
		var p := a.lerp(ctrl, u).lerp(ctrl.lerp(b, u), u)
		var side := (b - a).normalized().orthogonal() * (1.0 if j % 2 == 0 else -1.0)
		var bud := p + side * 11.0
		_g.draw_line(p, bud, Color(BRANCH_COLOR, 0.7), 1.5, true)
		_g.draw_circle(bud, 2.6, Color(BRANCH_COLOR.lightened(0.3), 0.9))


## Живая часть ветки: искра на растущем кончике, огонёк по выросшей ветке.
func _draw_branch_fx(a: Vector2, b: Vector2, t: float, seed_hash: int) -> void:
	var grow := 1.0 - pow(1.0 - t, 3.0)
	var bend := (b - a).orthogonal() * (0.16 if seed_hash % 2 == 0 else -0.16)
	var ctrl := (a + b) * 0.5 + bend
	a += (ctrl - a).normalized() * NODE_RADIUS
	b += (ctrl - b).normalized() * NODE_RADIUS
	if t < 1.0:
		var tip := a.lerp(ctrl, grow).lerp(ctrl.lerp(b, grow), grow)
		_g.draw_texture_rect(_glow, Rect2(tip - Vector2(18, 18), Vector2(36, 36)), false, Color(1.0, 0.9, 0.6, 0.9))
		_g.draw_circle(tip, 3.0, Color.WHITE)
	else:
		var run := fmod(_time * 0.45 + float(seed_hash % 97) / 97.0, 1.0)
		if run < 0.6:
			var u := run / 0.6
			var p := a.lerp(ctrl, u).lerp(ctrl.lerp(b, u), u)
			var a_run := sin(u * PI)
			_g.draw_texture_rect(_glow, Rect2(p - Vector2(10, 10), Vector2(20, 20)), false, Color(1.0, 0.92, 0.7, 0.7 * a_run))


## Узел: свечение, тёмный медальон с двойным золотым ободком, значок навыка,
## точки уровней снизу. k — прогресс появления (упругое «распускание»).
## Рисуется в три слоя: _draw_node_under (свечение, венец), _draw_node (сам медальон
## и подпись, кешируется), _draw_node_over (вращающиеся украшения, выбор, вспышки).
func _node_color(id: String) -> Color:
	var owned := Skills.is_owned(id)
	var affordable := Skills.can_buy(id)
	# Порядок важен: изученный до конца — спокойный нефритовый, доступный к покупке —
	# пульсирующее золото (даже если часть уровней уже куплена), начатый — тусклая бронза.
	var maxed := Skills.is_maxed(id)
	var blocked := Skills.blocked_by(id) != ""
	var path: String = Skills.nodes[id].get("path", "")
	var col: Color = PATH_COLORS.get(path, COLOR_AVAILABLE)
	if blocked:
		col = COLOR_BLOCKED
	elif maxed:
		col = COLOR_MAXED
	elif affordable:
		col = COLOR_AFFORDABLE
	elif owned:
		col = COLOR_OWNED
	return col


func _pop(p: Vector2, k: float) -> void:
	var c1 := k - 1.0
	var pop := 1.0 + 2.70158 * c1 * c1 * c1 + 1.70158 * c1 * c1  # упругий выход за 1 и назад
	_g.draw_set_transform(p, 0.0, Vector2(pop, pop))


func _draw_node_under(id: String, p: Vector2, k: float) -> void:
	var owned := Skills.is_owned(id)
	var affordable := Skills.can_buy(id)
	var maxed := Skills.is_maxed(id)
	var col: Color = _colors.get(id, COLOR_AVAILABLE)
	_pop(p, k)
	var legendary: bool = Skills.nodes[id].get("legendary", false)
	var r := NODE_RADIUS * (1.3 if legendary else 1.0)
	var pulse := 0.5 + 0.5 * sin(_time * 3.0)
	if legendary:
		# Легендарный навык: золотой венец из медленно вращающихся лучей.
		var gold := Color(1.0, 0.78, 0.3, 0.75 if owned else 0.45)
		for i in 16:
			var ang := _time * 0.15 + i * TAU / 16.0
			var ray_len := r * (1.45 + (0.2 if i % 2 == 0 else 0.0) + 0.06 * pulse)
			_g.draw_line(Vector2.from_angle(ang) * (r + 6.0), Vector2.from_angle(ang) * ray_len, gold, 2.0, true)
		_g.draw_arc(Vector2.ZERO, r + 5.0, 0.0, TAU, 56, gold, 2.5, true)

	var glow_a := 0.25 + 0.2 * pulse if affordable else (0.3 if maxed else (0.2 if owned else 0.12))
	var gr := r * (2.6 + (0.25 * pulse if affordable else 0.0))
	_g.draw_texture_rect(_glow, Rect2(-Vector2(gr, gr), Vector2(gr, gr) * 2.0), false, Color(col, glow_a))


func _draw_node_over(id: String, p: Vector2, k: float) -> void:
	var owned := Skills.is_owned(id)
	var col: Color = _colors.get(id, COLOR_AVAILABLE)
	_pop(p, k)
	var legendary: bool = Skills.nodes[id].get("legendary", false)
	var r := NODE_RADIUS * (1.3 if legendary else 1.0)
	if k < 1.0:
		# Вспышка при появлении.
		var fr := r * (1.0 + 1.5 * k)
		_g.draw_arc(Vector2.ZERO, fr, 0.0, TAU, 48, Color(1.0, 0.9, 0.65, 1.0 - k), 3.0, true)
	if _bursts.has(id):
		var bt: float = (_time - float(_bursts[id])) / 0.7
		if bt < 1.0:
			_g.draw_arc(Vector2.ZERO, r * (1.1 + 1.4 * bt), 0.0, TAU, 48, Color(1.0, 0.9, 0.6, 0.9 * (1.0 - bt)), 4.0 * (1.0 - bt) + 1.0, true)
			_g.draw_texture_rect(_glow, Rect2(-Vector2(r, r) * 3.0, Vector2(r, r) * 6.0), false, Color(1.0, 0.9, 0.6, 0.5 * (1.0 - bt)))
		else:
			_bursts.erase(id)

	if id == _selected:
		_g.draw_arc(Vector2.ZERO, r + 13.0, 0.0, TAU, 56, Color(col, 0.85), 2.0, true)
		# Бегущие засечки вокруг выбранного узла.
		for i in 12:
			var ang := _time * 0.6 + i * TAU / 12.0
			_g.draw_line(Vector2.from_angle(ang) * (r + 9.0), Vector2.from_angle(ang) * (r + 17.0), Color(col, 0.6), 1.5, true)

	if owned:
		# Орнамент: ромбики вокруг купленного узла медленно вращаются.
		for i in 8:
			var ang := -_time * 0.25 + i * TAU / 8.0
			var c := Vector2.from_angle(ang) * (r + 4.0)
			var d := Vector2.from_angle(ang) * 3.5
			var o := d.orthogonal() * 0.6
			_g.draw_colored_polygon(PackedVector2Array([c - d, c + o, c + d, c - o]), col)


func _draw_node(id: String, p: Vector2, k: float) -> void:
	var owned := Skills.is_owned(id)
	var affordable := Skills.can_buy(id)
	var blocked := Skills.blocked_by(id) != ""
	var col := _node_color(id)
	_colors[id] = col
	_pop(p, k)
	var legendary: bool = Skills.nodes[id].get("legendary", false)
	var r := NODE_RADIUS * (1.3 if legendary else 1.0)
	_g.draw_circle(Vector2.ZERO, r, Color(0.07, 0.045, 0.13))
	_g.draw_circle(Vector2(-r * 0.12, -r * 0.15), r * 0.78, Color(0.16, 0.1, 0.26, 0.6))
	_g.draw_circle(Vector2(-r * 0.2, -r * 0.25), r * 0.45, Color(0.26, 0.17, 0.38, 0.35))
	_g.draw_arc(Vector2.ZERO, r, 0.0, TAU, 56, col, 3.0, true)
	_g.draw_arc(Vector2.ZERO, r - 6.0, 0.0, TAU, 48, Color(col, 0.45), 1.2, true)
	_draw_icon(Skills.nodes[id].get("icon", id), col.lightened(0.15) if owned or affordable else Color(col, 0.85))

	var max_lvl := Skills.max_level(id)
	if max_lvl > 1:
		var lvl := Skills.level(id)
		for i in max_lvl:
			var ang := PI * 0.5 + (i - (max_lvl - 1) * 0.5) * 0.22
			var dp := Vector2.from_angle(ang) * (r - 12.0)
			if i < lvl:
				_g.draw_circle(dp, 3.2, col.lightened(0.3))
			else:
				_g.draw_arc(dp, 2.8, 0.0, TAU, 12, Color(col, 0.5), 1.0, true)
	if blocked:
		# Путь закрыт: тёмная вуаль, перечёркнутый круг и замочек.
		_g.draw_circle(Vector2.ZERO, r, Color(0.03, 0.02, 0.06, 0.55))
		var dg := Vector2(r, -r) * 0.62
		_g.draw_line(-dg, dg, Color(0.75, 0.35, 0.35, 0.8), 3.0, true)
		var lp := Vector2(r * 0.62, r * 0.62)
		_g.draw_rect(Rect2(lp - Vector2(8, 4), Vector2(16, 12)), Color(0.8, 0.75, 0.7))
		_g.draw_arc(lp - Vector2(0, 4), 5.0, PI, TAU, 12, Color(0.8, 0.75, 0.7), 2.5, true)

	var font: Font = UiTheme.FONT_SERIF_BOLD
	var title: String = Skills.nodes[id].title
	var w := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 21).x
	var tp := Vector2(-w * 0.5, r + 30.0)
	_g.draw_string_outline(font, tp, title, HORIZONTAL_ALIGNMENT_LEFT, -1, 21, 5, Color(0.03, 0.02, 0.06, 0.85))
	_g.draw_string(font, tp, title, HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color(col.lightened(0.2), 0.95))
	_g.draw_set_transform(Vector2.ZERO)


## Значки навыков рисуются линиями, в стиле гравюры.
func _draw_icon(id: String, col: Color) -> void:
	var w := 2.2
	match id:
		"start":
			var pts := PackedVector2Array()
			for i in 40:
				var t := i / 39.0
				pts.append(Vector2.from_angle(t * TAU * 2.2 + _time * 0.3) * (2.0 + 15.0 * t))
			_g.draw_polyline(pts, col, w, true)
			_g.draw_circle(Vector2.ZERO, 3.0, col)
		"gravity_1":
			_g.draw_circle(Vector2.ZERO, 4.5, col)
			_g.draw_arc(Vector2.ZERO, 11.0, 0.0, TAU, 32, Color(col, 0.6), 1.4, true)
			for i in 4:
				var d := Vector2.from_angle(i * TAU / 4.0 + PI / 4.0)
				var tip := d * 9.0
				_g.draw_line(d * 19.0, tip, col, w, true)
				_g.draw_line(tip, tip + d.rotated(0.6) * 5.0, col, w, true)
				_g.draw_line(tip, tip + d.rotated(-0.6) * 5.0, col, w, true)
		"reach_1":
			_g.draw_circle(Vector2.ZERO, 4.0, col)
			for i in 10:
				var a0 := i * TAU / 10.0
				_g.draw_arc(Vector2.ZERO, 17.0, a0, a0 + TAU / 20.0, 6, col, w, true)
			_g.draw_arc(Vector2.ZERO, 10.0, 0.0, TAU, 28, Color(col, 0.5), 1.2, true)
		"drift_1":
			for i in 3:
				var y := -8.0 + i * 8.0
				_g.draw_line(Vector2(-18.0 + i * 3.0, y), Vector2(4.0 - i * 2.0, y), Color(col, 0.5 + 0.25 * i), w, true)
			_g.draw_circle(Vector2(10.0, 0.0), 6.0, col)
		"density_1":
			for v in [Vector2(0, 0), Vector2(-9, -6), Vector2(8, -8), Vector2(11, 5), Vector2(-7, 9), Vector2(2, 13), Vector2(-14, 2), Vector2(3, -15)]:
				_g.draw_circle(v, 2.8 if v == Vector2.ZERO else 2.0, col)
		"value_1":
			var top := Vector2(0, -16)
			var bottom := Vector2(0, 16)
			var l := Vector2(-11, -3)
			var rr := Vector2(11, -3)
			_g.draw_polyline(PackedVector2Array([top, rr, bottom, l, top]), col, w, true)
			_g.draw_line(l, rr, Color(col, 0.7), 1.4, true)
			_g.draw_line(top, Vector2(-4, -3), Color(col, 0.6), 1.2, true)
			_g.draw_line(top, Vector2(4, -3), Color(col, 0.6), 1.2, true)
			_g.draw_line(Vector2(-4, -3), bottom, Color(col, 0.6), 1.2, true)
			_g.draw_line(Vector2(4, -3), bottom, Color(col, 0.6), 1.2, true)
		"cluster_1":
			for v in [Vector2(-6, 4), Vector2(6, 4), Vector2(0, -6)]:
				_g.draw_arc(v, 7.5, 0.0, TAU, 24, col, w, true)
			_g.draw_circle(Vector2.ZERO, 2.5, col)
		"dust_3":
			_g.draw_line(Vector2(-9, 6), Vector2(9, 6), Color(col, 0.7), w, true)
			_g.draw_line(Vector2(-9, 6), Vector2(0, -9), Color(col, 0.7), w, true)
			_g.draw_line(Vector2(9, 6), Vector2(0, -9), Color(col, 0.7), w, true)
			for v in [Vector2(-9, 6), Vector2(9, 6), Vector2(0, -9)]:
				_g.draw_circle(v, 5.0, col)
		"pebble_root":
			# Гладкая галька, газ обтекает её линиями.
			_ellipse(Vector2(4, 0), Vector2(9.0, 6.5), 0.0, col)
			for y in [-12.0, 12.0]:
				var pts := PackedVector2Array()
				for i in 12:
					var x := -18.0 + i * 3.4
					pts.append(Vector2(x, y * (0.55 + 0.45 * absf(x - 4.0) / 22.0)))
				_g.draw_polyline(pts, Color(col, 0.7), 1.6, true)
			_g.draw_line(Vector2(-18, 0), Vector2(-8, 0), Color(col, 0.7), 1.6, true)
		"toughness":
			# Плотно спечённый камень: многогранник с внутренними гранями.
			var pts := PackedVector2Array()
			for i in 7:
				pts.append(Vector2.from_angle(i * TAU / 6.0 + 0.3) * 14.0)
			_g.draw_polyline(pts, col, w, true)
			for i in 3:
				_g.draw_line(Vector2.ZERO, pts[i * 2], Color(col, 0.6), 1.4, true)
			_g.draw_circle(Vector2.ZERO, 3.0, col)
		"thrust":
			_g.draw_circle(Vector2(6, 0), 6.5, col)
			_g.draw_arc(Vector2(6, 0), 12.0, PI * 0.65, PI * 1.35, 14, Color(col, 0.7), w, true)
			_g.draw_line(Vector2(-6, -12), Vector2(-16, -12), Color(col, 0.6), w, true)
			_g.draw_line(Vector2(-6, 12), Vector2(-16, 12), Color(col, 0.6), w, true)
		"ice_crust":
			_g.draw_circle(Vector2.ZERO, 7.0, col)
			for i in 6:
				var d := Vector2.from_angle(i * TAU / 6.0)
				_g.draw_line(d * 10.0, d * 17.0, col, w, true)
				_g.draw_line(d * 14.0, d * 14.0 + d.rotated(0.9) * 4.0, Color(col, 0.7), 1.4, true)
				_g.draw_line(d * 14.0, d * 14.0 + d.rotated(-0.9) * 4.0, Color(col, 0.7), 1.4, true)
		"pebble_swarm":
			for v in [Vector2(-8, -5), Vector2(7, -8), Vector2(9, 7), Vector2(-6, 9), Vector2(0, 0)]:
				var rr := 4.2 if v == Vector2.ZERO else 3.2
				_ellipse(v, Vector2(rr, rr * 0.7), v.x * 0.1, col)
		"grip":
			# Крупное тело обволакивает камешек поменьше.
			_g.draw_circle(Vector2(-3, 2), 9.0, col)
			_g.draw_arc(Vector2(-3, 2), 13.0, -0.9, 1.6, 16, Color(col, 0.7), w, true)
			_ellipse(Vector2(11, -9), Vector2(4.5, 3.6), 0.4, col)
		"armor":
			var pts := PackedVector2Array()
			for i in 7:
				pts.append(Vector2.from_angle(i * TAU / 6.0) * 15.0)
			_g.draw_polyline(pts, col, w, true)
			_g.draw_arc(Vector2.ZERO, 9.0, 0.0, TAU, 24, Color(col, 0.7), 1.6, true)
			_g.draw_circle(Vector2.ZERO, 3.5, col)
		"combo":
			# Цепочка камешков, каждый следующий ярче.
			for i in 4:
				var v := Vector2(-15 + i * 10, 8 - i * 5)
				_g.draw_circle(v, 2.5 + i * 0.9, Color(col, 0.45 + 0.18 * i))
		"geode":
			# Расколотая жеода: кристаллы внутри скорлупы.
			_g.draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 28, col, w, true)
			for i in 7:
				var d := Vector2.from_angle(i * TAU / 7.0 + 0.2)
				_g.draw_colored_polygon(PackedVector2Array([d * 3.0 + d.orthogonal() * 2.2, d * 11.0, d * 3.0 - d.orthogonal() * 2.2]), Color(col, 0.85))
		"swarm":
			# Рой галек стягивается в сгусток.
			for i in 9:
				var a := i * TAU / 9.0 + _time * 0.4
				var r := 8.0 + 8.0 * fmod(i * 0.37, 1.0)
				_g.draw_circle(Vector2.from_angle(a) * r, 2.2, Color(col, 0.8))
			_g.draw_circle(Vector2.ZERO, 4.0, col)
		"selective":
			# Сито: из потока проходит только нужное.
			_g.draw_polyline(PackedVector2Array([Vector2(-16, -12), Vector2(16, -12), Vector2(4, 4), Vector2(4, 15), Vector2(-4, 15), Vector2(-4, 4), Vector2(-16, -12)]), col, w, true)
			for v in [Vector2(-8, -17), Vector2(1, -19), Vector2(10, -16)]:
				_g.draw_circle(v, 2.2, Color(col, 0.75))
		"mat_metal":
			# Подкова магнита.
			_g.draw_arc(Vector2(0, 2), 11.0, 0.0, PI, 20, col, 5.0, true)
			_g.draw_line(Vector2(-11, 2), Vector2(-11, -12), col, 5.0, true)
			_g.draw_line(Vector2(11, 2), Vector2(11, -12), col, 5.0, true)
			_g.draw_line(Vector2(-14, -12), Vector2(-8, -12), Color(col, 0.6), 3.0, true)
			_g.draw_line(Vector2(8, -12), Vector2(14, -12), Color(col, 0.6), 3.0, true)
		"mat_ice":
			for i in 3:
				var d := Vector2.from_angle(i * PI / 3.0)
				_g.draw_line(-d * 16.0, d * 16.0, col, w, true)
				for sgn in [-1.0, 1.0]:
					var t: Vector2 = d * 10.0 * sgn
					_g.draw_line(t, t + (d * sgn).rotated(0.8) * 5.0, Color(col, 0.75), 1.5, true)
					_g.draw_line(t, t + (d * sgn).rotated(-0.8) * 5.0, Color(col, 0.75), 1.5, true)
		"mat_silicate":
			# Кристалл кварца: вытянутая шестигранная призма.
			var pts := PackedVector2Array([Vector2(0, -17), Vector2(8, -9), Vector2(8, 10), Vector2(0, 17), Vector2(-8, 10), Vector2(-8, -9), Vector2(0, -17)])
			_g.draw_polyline(pts, col, w, true)
			_g.draw_line(Vector2(0, -17), Vector2(0, 17), Color(col, 0.55), 1.3, true)
		"mat_carbon":
			# Бензольное кольцо — знак органики.
			var pts := PackedVector2Array()
			for i in 7:
				pts.append(Vector2.from_angle(i * TAU / 6.0 + PI / 6.0) * 15.0)
			_g.draw_polyline(pts, col, w, true)
			_g.draw_arc(Vector2.ZERO, 8.0, 0.0, TAU, 24, Color(col, 0.75), 1.6, true)
		_:
			for i in 4:
				var d := Vector2.from_angle(i * TAU / 4.0)
				_g.draw_colored_polygon(PackedVector2Array([Vector2.ZERO + d.orthogonal() * 3.0, d * 16.0, -d.orthogonal() * 3.0]), col)


func _ellipse(c: Vector2, radii: Vector2, rot: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 20:
		pts.append(c + (Vector2.from_angle(i * TAU / 20.0) * radii).rotated(rot))
	_g.draw_colored_polygon(pts, col)


func _hit_test(screen_pos: Vector2) -> String:
	var local := (screen_pos - _canvas.position) / _canvas.scale.x
	for id in Skills.order:
		if _is_visible_node(id) and local.distance_to(_node_pos(id)) <= NODE_RADIUS + 12.0:
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
