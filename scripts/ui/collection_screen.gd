class_name CollectionScreen
extends Control
## Коллекция тел: дерево путей от пылинки вниз. Где побывал и кем стал —
## тело шейдером, как в игре; что ещё не открыто — чёрный силуэт в тени.
## Тап по узлу — карточка: что это за тело, или как его получить.
## Дерево тянется пальцем (и колёсиком мыши).

signal closed

const HEAD_H := 96.0
const MARGIN := 70.0
const TAP_SLOP := 14.0

var _world := Node2D.new()
var _under := Node2D.new()     # ветки и подсветка
var _labels := Node2D.new()    # подписи поверх тел
var _arts := {}                # id -> ColorRect
var _time := 0.0
var _zoom := 1.0
var _scroll := Vector2.ZERO    # сдвиг мира, экранные пиксели
var _bounds := Rect2()
var _drag_from := Vector2.ZERO
var _drag_start := Vector2.ZERO
var _dragging := false
var _moved := 0.0
var _selected := ""
var _card: PanelContainer
var _card_title: Label
var _card_state: Label
var _card_text: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiTheme.get_theme()
	clip_contents = true

	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.008, 0.025, 0.97)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_bounds = Rect2(Vector2.ZERO, Vector2.ZERO)
	for id in CollectionData.all_ids():
		_bounds = _bounds.expand(CollectionData.pos_of(id))
	add_child(_world)
	_world.add_child(_under)
	_under.draw.connect(_draw_under)
	for id in CollectionData.all_ids():
		# Не открыто: тела нет, только чёрный силуэт в тени (рисует _draw_labels).
		if not CollectionData.seen(id):
			continue
		var art := BodyArt.make(id)
		var q := BodyArt.quad_size(id, _radius(id))
		art.size = Vector2(q, q)
		art.position = CollectionData.pos_of(id) - art.size * 0.5
		_world.add_child(art)
		_arts[id] = art
	_world.add_child(_labels)
	_labels.draw.connect(_draw_labels)
	_bounds = _bounds.grow(MARGIN)
	_bounds.end.y += 30.0

	# Шапка поверх дерева: дерево уходит под неё в тень.
	var band := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.01, 0.008, 0.025, 1.0))
	grad.set_color(1, Color(0.01, 0.008, 0.025, 0.0))
	grad.add_point(0.7, Color(0.01, 0.008, 0.025, 0.92))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 64
	band.texture = gt
	band.stretch_mode = TextureRect.STRETCH_SCALE
	band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	band.anchor_right = 1.0
	band.offset_bottom = HEAD_H + 20.0
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(band)
	_build_head()
	_build_card()
	_layout()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.25)


func _radius(id: String) -> float:
	match id:
		"dust":
			return 16.0
		"pebble":
			return 22.0
		"boulder":
			return 27.0
		"plsim":
			return 33.0
		"embryo":
			return 40.0
		"young", "giant", "cloud", "next":
			return 44.0
		"dwarf_planet":
			return 26.0
	if CollectionData.is_stage(id):
		return 40.0
	return 38.0


func _build_head() -> void:
	var title := Label.new()
	title.text = "Коллекция тел"
	title.position = Vector2(32, 16)
	title.add_theme_font_override("font", UiTheme.FONT_SERIF_BOLD)
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.5))
	title.add_theme_color_override("font_outline_color", Color(0.1, 0.04, 0.0, 0.8))
	title.add_theme_constant_override("outline_size", 6)
	add_child(title)
	var n_end := 0
	for e in CollectionData.ENDING_NODES:
		if e in GameState.endings_seen:
			n_end += 1
	var n_st := 0
	for s in CollectionData.STAGE_NODES:
		if CollectionData.seen(s):
			n_st += 1
	var sub := Label.new()
	sub.text = "тел открыто %d из %d · этапов пройдено %d из %d · тапни тело, чтобы узнать о нём" % [
		n_end, CollectionData.ENDING_NODES.size(), n_st, CollectionData.STAGE_NODES.size() - 1]
	sub.position = Vector2(34, 60)
	sub.add_theme_font_override("font", UiTheme.FONT_SERIF_ITALIC)
	sub.add_theme_font_size_override("font_size", 19)
	sub.add_theme_color_override("font_color", Color(UiTheme.PARCHMENT, 0.8))
	add_child(sub)
	var back := Button.new()
	back.text = "Назад"
	UiTheme.paint_button(back, false, 22)
	back.anchor_left = 1.0
	back.anchor_right = 1.0
	back.offset_left = -220
	back.offset_right = -24
	back.offset_top = 20
	back.offset_bottom = 78
	back.pressed.connect(close)
	add_child(back)


func _build_card() -> void:
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", UiTheme.painted_panel(26))
	_card.anchor_left = 1.0
	_card.anchor_right = 1.0
	_card.anchor_top = 1.0
	_card.anchor_bottom = 1.0
	_card.offset_left = -470
	_card.offset_right = -24
	_card.offset_top = -280
	_card.offset_bottom = -24
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.visible = false
	add_child(_card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_card.add_child(box)
	_card_title = Label.new()
	_card_title.add_theme_font_override("font", UiTheme.FONT_SERIF_BOLD)
	_card_title.add_theme_font_size_override("font_size", 30)
	_card_title.add_theme_color_override("font_color", UiTheme.GOLD)
	_card_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_card_title)
	_card_state = Label.new()
	_card_state.add_theme_font_override("font", UiTheme.FONT_SERIF_ITALIC)
	_card_state.add_theme_font_size_override("font_size", 19)
	box.add_child(_card_state)
	_card_text = Label.new()
	_card_text.add_theme_font_override("font", UiTheme.FONT_SERIF)
	_card_text.add_theme_font_size_override("font_size", 21)
	_card_text.add_theme_color_override("font_color", UiTheme.PARCHMENT)
	_card_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_card_text)


func _layout() -> void:
	var vp := size if size.x > 0.0 else get_viewport_rect().size
	# Дерево по ширине целиком; по высоте — листается.
	_zoom = clampf((vp.x - 40.0) / _bounds.size.x, 0.55, 1.1)
	_scroll.x = (vp.x - _bounds.size.x * _zoom) * 0.5 - _bounds.position.x * _zoom
	_scroll.y = HEAD_H - _bounds.position.y * _zoom
	_apply()


func _apply() -> void:
	var vp := size if size.x > 0.0 else get_viewport_rect().size
	var top := HEAD_H - _bounds.position.y * _zoom
	var bottom := vp.y - _bounds.end.y * _zoom
	_scroll.y = clampf(_scroll.y, minf(bottom, top), top)
	var wl := (vp.x - _bounds.size.x * _zoom) * 0.5 - _bounds.position.x * _zoom
	if _bounds.size.x * _zoom > vp.x:
		_scroll.x = clampf(_scroll.x, vp.x - _bounds.end.x * _zoom, -_bounds.position.x * _zoom)
	else:
		_scroll.x = wl
	_world.position = _scroll
	_world.scale = Vector2.ONE * _zoom


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_scroll.y += 60.0
			_apply()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_scroll.y -= 60.0
			_apply()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_press(mb.pressed, mb.position)
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.index == 0:
			_press(st.pressed, st.position)
	elif event is InputEventMouseMotion and _dragging:
		_drag((event as InputEventMouseMotion).position)
	elif event is InputEventScreenDrag and _dragging:
		_drag((event as InputEventScreenDrag).position)


func _press(down: bool, at: Vector2) -> void:
	if down:
		_dragging = true
		_drag_from = at
		_drag_start = _scroll
		_moved = 0.0
		return
	if _dragging and _moved < TAP_SLOP:
		_tap(at)
	_dragging = false


func _drag(at: Vector2) -> void:
	var d := at - _drag_from
	_moved = maxf(_moved, d.length())
	_scroll = _drag_start + d
	_apply()


func _tap(at: Vector2) -> void:
	var w := (at - _scroll) / _zoom
	var best := ""
	var bd := INF
	for id in CollectionData.all_ids():
		var d := w.distance_to(CollectionData.pos_of(id))
		if d < _radius(id) + 26.0 and d < bd:
			bd = d
			best = id
	select(best)


func select(id: String) -> void:
	_selected = id
	_card.visible = id != ""
	if id == "":
		return
	var seen := CollectionData.seen(id)
	_card_title.text = CollectionData.title_of(id)
	if CollectionData.is_stage(id):
		var info: Dictionary = CollectionData.STAGE_NODES[id]
		if id == "next":
			_card_state.text = "впереди"
			_card_text.text = str(info["hint"])
		elif seen:
			_card_state.text = "ты здесь был"
			_card_text.text = str(info["desc"])
		else:
			_card_state.text = "ещё не был · как сюда попасть"
			_card_text.text = str(info["hint"])
	else:
		var e: Dictionary = GameData.ENDINGS[id]
		if seen:
			_card_state.text = "открыто · наследие %d" % int(e["legacy"])
			_card_text.text = str(e["desc"])
		else:
			_card_state.text = "ещё не открыто · как получить"
			_card_text.text = str(CollectionData.ENDING_NODES[id]["hint"])
	_card_state.add_theme_color_override("font_color", Color(0.62, 0.86, 1.0) if seen else Color(1.0, 0.78, 0.5))


func close() -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func() -> void:
		closed.emit()
		queue_free())


func _process(delta: float) -> void:
	_time += delta
	for id in _arts:
		BodyArt.tick(_arts[id], id, _time + float(absi(str(id).hash()) % 100))
	_under.queue_redraw()
	_labels.queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_inside_tree():
		_layout()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


# --- Рисование ---

func _draw_under() -> void:
	# Ветки: от развилки вниз плавной S-кривой к первому телу столбика, дальше
	# столбик идёт прямо вниз от тела к телу. Путь к открытому — золотой.
	var dp := {}
	for id in CollectionData.all_ids():
		dp[id] = _draw_parent(id)
	var lit := {}
	for id in CollectionData.all_ids():
		if CollectionData.seen(id):
			var c: String = id
			while c != "" and not lit.has(c):
				lit[c] = true
				c = dp[c]
	for id in CollectionData.all_ids():
		var par: String = dp[id]
		if par == "":
			continue
		var on := lit.has(id)
		var col := Color(1.0, 0.8, 0.45, 0.55) if on else Color(0.55, 0.55, 0.65, 0.16)
		var a := CollectionData.pos_of(par)
		var b := CollectionData.pos_of(id)
		var a2 := a + Vector2(0, _radius(par))
		var b2 := b - Vector2(0, _radius(id))
		var pts := PackedVector2Array()
		if absf(b.y - a.y) < 1.0:
			a2 = a + Vector2(signf(b.x - a.x) * _radius(par), 0)
			b2 = b - Vector2(signf(b.x - a.x) * _radius(id), 0)
			pts = PackedVector2Array([a2, b2])
		elif absf(b.x - a.x) < 1.0:
			pts = PackedVector2Array([a2, b2])
		else:
			var mid := (a2.y + b2.y) * 0.5
			for i in 25:
				var t := float(i) / 24.0
				var u := 1.0 - t
				pts.append(a2 * u * u * u + Vector2(a2.x, mid) * 3.0 * u * u * t + Vector2(b2.x, mid) * 3.0 * u * t * t + b2 * t * t * t)
		_under.draw_polyline(pts, col, 2.5 if on else 1.6, true)
	# За каждым телом мягкий ореол: открытое светится тёплым, закрытое — едва видный край.
	for id in CollectionData.all_ids():
		var p := CollectionData.pos_of(id)
		var r := _radius(id)
		if CollectionData.seen(id):
			for k in 6:
				_under.draw_circle(p, r * (1.12 + 0.1 * k), Color(1.0, 0.8, 0.5, 0.025))
		else:
			_under.draw_arc(p, r + 1.5, 0.0, TAU, 48, Color(0.75, 0.7, 0.62, 0.22), 1.5, true)
		if id == _selected:
			var pulse := 0.5 + 0.5 * sin(_time * 3.0)
			_under.draw_arc(p, r + 8.0, 0.0, TAU, 64, Color(1.0, 0.84, 0.5, 0.5 + 0.4 * pulse), 2.5, true)


func _draw_labels() -> void:
	var font: Font = UiTheme.FONT_SERIF_BOLD
	for id in CollectionData.all_ids():
		var p := CollectionData.pos_of(id)
		var r := _radius(id)
		var seen := CollectionData.seen(id)
		var stage := CollectionData.is_stage(id)
		var fs := 22 if stage else 19
		var col := (Color(1.0, 0.84, 0.5) if stage else UiTheme.PARCHMENT) if seen else Color(0.6, 0.6, 0.68, 0.7)
		if not seen:
			# Силуэт в тени: чёрный шар, по краю едва светится контровой свет.
			_labels.draw_circle(p, r, Color(0.0, 0.0, 0.0, 1.0))
			_labels.draw_arc(p, r - 1.0, PI * 0.65, PI * 1.45, 32, Color(0.85, 0.78, 0.65, 0.28), 2.0, true)
		var y := p.y + r + 24.0
		for line in _wrap(font, CollectionData.title_of(id), fs, 160.0 if not stage else 260.0):
			var w := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var tp := Vector2(p.x - w * 0.5, y)
			_labels.draw_string_outline(font, tp, line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0.02, 0.01, 0.04, 0.9))
			_labels.draw_string(font, tp, line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
			y += fs + 2.0
		if not seen:
			# Знак вопроса на силуэте: тело ещё ждёт.
			var q := "?"
			var qf := int(r * 0.9)
			var qw := font.get_string_size(q, HORIZONTAL_ALIGNMENT_LEFT, -1, qf).x
			_labels.draw_string(font, p + Vector2(-qw * 0.5, qf * 0.35), q, HORIZONTAL_ALIGNMENT_LEFT, -1, qf, Color(0.8, 0.75, 0.65, 0.22))


## Название в одну-две строки, чтобы соседи не налезали друг на друга.
func _wrap(font: Font, text: String, fs: int, max_w: float) -> PackedStringArray:
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= max_w:
		return PackedStringArray([text])
	var words := text.split(" ")
	var best := PackedStringArray([text])
	var best_w := INF
	for i in range(1, words.size()):
		var a := " ".join(words.slice(0, i))
		var b := " ".join(words.slice(i))
		var w := maxf(font.get_string_size(a, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, font.get_string_size(b, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
		if w < best_w:
			best_w = w
			best = PackedStringArray([a, b])
	return best


## От кого рисовать ветку: от тела выше в том же столбике, иначе от развилки.
func _draw_parent(id: String) -> String:
	var par := CollectionData.parent_of(id)
	if par == "":
		return ""
	var p := CollectionData.pos_of(id)
	var best := par
	var by := -INF
	for o in CollectionData.all_ids():
		if o == id or CollectionData.parent_of(o) != par:
			continue
		var q := CollectionData.pos_of(o)
		if absf(q.x - p.x) < 1.0 and q.y < p.y and q.y > by:
			by = q.y
			best = o
	return best
