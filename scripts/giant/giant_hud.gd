extends Control
## Интерфейс этапа гиганта: звёздная пыль и масса слева, газ диска и класс
## гиганта сверху, поле и луны, карта газа по радиусу снизу, книга и меню справа.

signal tree_requested
signal menu_requested

const BOOK_ICON := preload("res://assets/ui/book.png")
const MAP_SIZE := Vector2(520.0, 54.0)

var stage  # сцена этапа (giant_stage.gd): из неё берём числа
var _currency: Label
var _chondrules: Label
var _mass: Label
var _field: Label
var _title: Label
var _class: Label
var _gas_bar: Control
var _gas_label: Label
var _map: Control
var _spark: Control
var _caption: VBoxContainer
var _cap_title: Label
var _cap_sub: Label
var _toast: Label
var _badge: Control
var _ev_label: Label
var _pointer: Control
var _shown := 0.0
var _time := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.get_theme()
	var left := VBoxContainer.new()
	left.position = Vector2(22, 14)
	left.add_theme_constant_override("separation", -2)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(left)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(row)
	_spark = Control.new()
	_spark.custom_minimum_size = Vector2(34, 46)
	_spark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spark.draw.connect(func() -> void:
		UiTheme.draw_spark(_spark, _spark.size * 0.5, 14.0 * (1.0 + 0.06 * sin(_time * 3.0))))
	row.add_child(_spark)
	_currency = _label(40, UiTheme.GOLD, UiTheme.FONT_NUMBERS)
	row.add_child(_currency)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(10, 0)
	row.add_child(gap)
	var bead := Control.new()
	bead.custom_minimum_size = Vector2(22, 46)
	bead.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bead.draw.connect(func() -> void: UiTheme.draw_chondrule(bead, bead.size * 0.5 + Vector2(0, 2), 9.0))
	row.add_child(bead)
	_chondrules = _label(28, UiTheme.CHONDRULE, UiTheme.FONT_NUMBERS)
	row.add_child(_chondrules)
	_mass = _label(18, UiTheme.TEXT, UiTheme.FONT_SEMI)
	left.add_child(_mass)
	_field = _label(15, UiTheme.TEXT_DIM, UiTheme.FONT_TEXT)
	left.add_child(_field)
	_shown = GameState.currency

	var top := VBoxContainer.new()
	top.anchor_left = 0.5
	top.anchor_right = 0.5
	top.offset_left = -220
	top.offset_right = 220
	top.offset_top = 12
	top.add_theme_constant_override("separation", 4)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	_title = _label(26, UiTheme.PARCHMENT, UiTheme.FONT_SERIF_BOLD)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.text = "Газовый гигант"
	top.add_child(_title)
	_gas_bar = Control.new()
	_gas_bar.custom_minimum_size = Vector2(440, 10)
	_gas_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gas_bar.draw.connect(_draw_gas_bar)
	top.add_child(_gas_bar)
	_gas_label = _label(14, UiTheme.TEXT_DIM, UiTheme.FONT_TEXT)
	_gas_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_gas_label)
	_class = _label(16, UiTheme.GOLD, UiTheme.FONT_SEMI)
	_class.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_class)

	_map = Control.new()
	_map.anchor_left = 0.5
	_map.anchor_right = 0.5
	_map.anchor_top = 1.0
	_map.anchor_bottom = 1.0
	_map.offset_left = -MAP_SIZE.x * 0.5
	_map.offset_right = MAP_SIZE.x * 0.5
	_map.offset_top = -MAP_SIZE.y - 30
	_map.offset_bottom = -30
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.draw.connect(_draw_map)
	add_child(_map)
	# Событие: строка над картой и стрелка к цели, если она за краем экрана.
	_ev_label = _label(17, UiTheme.PARCHMENT, UiTheme.FONT_SEMI)
	_ev_label.anchor_left = 0.5
	_ev_label.anchor_right = 0.5
	_ev_label.anchor_top = 1.0
	_ev_label.anchor_bottom = 1.0
	_ev_label.offset_left = -300
	_ev_label.offset_right = 300
	_ev_label.offset_top = -MAP_SIZE.y - 60
	_ev_label.offset_bottom = -MAP_SIZE.y - 34
	_ev_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_ev_label)
	_pointer = Control.new()
	_pointer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pointer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pointer.draw.connect(_draw_pointer)
	add_child(_pointer)

	var tree := Button.new()
	tree.icon = BOOK_ICON
	tree.expand_icon = true
	tree.flat = true
	tree.anchor_left = 1.0
	tree.anchor_right = 1.0
	tree.offset_left = -112
	tree.offset_right = -12
	tree.offset_top = 4
	tree.offset_bottom = 104
	tree.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		tree.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	tree.pressed.connect(func(): tree_requested.emit())
	add_child(tree)
	_badge = Control.new()
	_badge.position = Vector2(76, 14)
	_badge.size = Vector2(14, 14)
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.draw.connect(func() -> void:
		_badge.draw_circle(Vector2(7, 7), 6.0 + sin(_time * 4.0), Color(1.0, 0.45, 0.3)))
	tree.add_child(_badge)
	var menu := Button.new()
	menu.flat = true
	menu.anchor_left = 1.0
	menu.anchor_right = 1.0
	menu.offset_left = -86
	menu.offset_right = -38
	menu.offset_top = 108
	menu.offset_bottom = 152
	menu.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		menu.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	menu.draw.connect(func() -> void:
		var c := menu.size * 0.5
		menu.draw_circle(c, 21.0, Color(0.05, 0.03, 0.1, 0.45))
		menu.draw_arc(c, 21.0, 0.0, TAU, 48, Color(UiTheme.GOLD, 0.55), 1.5, true)
		for i in 3:
			menu.draw_line(c + Vector2(-9, -7 + i * 7), c + Vector2(9, -7 + i * 7), UiTheme.GOLD, 2.5, true))
	menu.pressed.connect(func(): menu_requested.emit())
	add_child(menu)

	_caption = VBoxContainer.new()
	_caption.anchor_left = 0.5
	_caption.anchor_right = 0.5
	_caption.anchor_top = 0.5
	_caption.anchor_bottom = 0.5
	_caption.offset_left = -420
	_caption.offset_right = 420
	_caption.offset_top = 150
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.modulate.a = 0.0
	add_child(_caption)
	_cap_title = _label(32, UiTheme.PARCHMENT, UiTheme.FONT_SERIF_BOLD)
	_cap_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_child(_cap_title)
	_cap_sub = _label(18, Color(UiTheme.PARCHMENT, 0.8), UiTheme.FONT_SERIF_ITALIC)
	_cap_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cap_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.add_child(_cap_sub)

	_toast = _label(22, Color(1.0, 0.88, 0.6), UiTheme.FONT_SEMI)
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.anchor_top = 0.5
	_toast.anchor_bottom = 0.5
	_toast.offset_left = -400
	_toast.offset_right = 400
	_toast.offset_top = -150
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.modulate.a = 0.0
	add_child(_toast)


func _label(size: int, color: Color, font: Font) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


var _cap_tw: Tween
var _cap_queue: Array = []


## Большая подпись по центру: появляется и тает. Если на экране уже есть
## подпись, новая ждёт своей очереди, а не перебивает её на полуслове.
func caption(title: String, sub: String, hold := 4.0) -> void:
	if _cap_tw != null and _cap_tw.is_running():
		if _cap_queue.size() < 3:
			_cap_queue.append([title, sub, hold])
		return
	_cap_title.text = title
	_cap_sub.text = sub
	_cap_tw = _caption.create_tween()
	_cap_tw.tween_property(_caption, "modulate:a", 1.0, 0.7)
	_cap_tw.tween_interval(hold)
	_cap_tw.tween_property(_caption, "modulate:a", 0.0, 1.0)
	_cap_tw.finished.connect(func() -> void:
		if not _cap_queue.is_empty():
			var c: Array = _cap_queue.pop_front()
			caption(c[0], c[1], c[2]))


## Короткое сообщение над гигантом.
func toast(text: String, color := Color(1.0, 0.88, 0.6)) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", color)
	var tw := _toast.create_tween()
	_toast.modulate.a = 0.0
	tw.tween_property(_toast, "modulate:a", 1.0, 0.3)
	tw.tween_interval(2.2)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.8)


func _process(delta: float) -> void:
	_time += delta
	if stage == null:
		return
	_shown = lerpf(_shown, GameState.currency, minf(delta * 6.0, 1.0))
	if absf(_shown - GameState.currency) < 1.0:
		_shown = GameState.currency
	_currency.text = GameData.format_number(_shown)
	_chondrules.text = str(GameState.chondrules)
	var e: float = stage.earths
	_mass.text = "%s масс Земли · %s массы Юпитера" % [_fmt(e), String.num(e / GameData.JUPITER_EARTHS, 2)]
	var field: float = GameState.giant_field()
	_field.text = "Магнитное поле %d%% · лун %d из %d" % [roundi(field * 100.0), stage.moons, GameState.giant_moon_cap()]
	var left: float = maxf(stage.gas, 0.0)
	_gas_label.text = "газ диска рассеется через %d:%02d" % [int(left) / 60, int(left) % 60]
	_class.text = _class_text(e, stage.orbit)
	_badge.visible = _can_buy()
	var ev = stage.events
	_ev_label.visible = ev != null and ev.active()
	if _ev_label.visible:
		_ev_label.text = ev.hint()
		_ev_label.add_theme_color_override("font_color", ev.color().lerp(UiTheme.PARCHMENT, 0.4))
	_pointer.queue_redraw()
	_spark.queue_redraw()
	_badge.queue_redraw()
	_gas_bar.queue_redraw()
	_map.queue_redraw()


func _fmt(e: float) -> String:
	return str(roundi(e)) if e >= 100.0 else String.num(e, 1)


func _class_text(e: float, r: float) -> String:
	var now := GameData.giant_final(GameState.giant.get("flavor", "giant_cold"), e, r)
	var name: String = GameData.ENDINGS[now]["name"]
	if e < GameData.SUPER_JUPITER:
		return "сейчас: %s · супер-Юпитер с %d масс Земли" % [name, roundi(GameData.SUPER_JUPITER)]
	if e < GameData.BROWN_DWARF:
		return "сейчас: %s · коричневый карлик с %d масс Земли" % [name, roundi(GameData.BROWN_DWARF)]
	return "сейчас: " + name


func _can_buy() -> bool:
	for id in Skills.order:
		if Skills.is_unlocked(id) and Skills.level(id) < Skills.max_level(id) \
				and GameState.currency >= Skills.cost(id) and GameState.chondrules >= Skills.cost2(id):
			return true
	return false


func _draw_gas_bar() -> void:
	var rect := Rect2(Vector2.ZERO, _gas_bar.size)
	UiTheme.pill(Color(1, 1, 1, 0.08), 4).draw(_gas_bar.get_canvas_item(), rect)
	var f: float = clampf(stage.gas / stage.gas_total, 0.0, 1.0)
	if f > 0.001:
		var col := Color(1.0, 0.66, 0.36).lerp(Color(1.0, 0.35, 0.25), 1.0 - smoothstep(0.0, 0.3, f))
		UiTheme.pill(col, 4).draw(_gas_bar.get_canvas_item(), Rect2(Vector2.ZERO, Vector2(maxf(rect.size.x * f, 8.0), rect.size.y)))


## Карта газа: плотность по радиусу от звезды наружу, ты — золотая метка.
func _draw_map() -> void:
	var disk = stage.disk
	if disk == null or disk.sigma.is_empty():
		return
	var s := MAP_SIZE
	UiTheme.pill(Color(0.03, 0.04, 0.09, 0.55), 10).draw(_map.get_canvas_item(), Rect2(Vector2.ZERO, s))
	var lo := GameData.GIANT_DISK.x
	var hi := GameData.GIANT_DISK.y
	var top := 8.0
	var h := s.y - 18.0
	# Зона горячих юпитеров и снеговая линия.
	var hot_x := (GameData.HOT_ORBIT - lo) / (hi - lo) * s.x
	_map.draw_rect(Rect2(0, top, hot_x, h), Color(1.0, 0.4, 0.2, 0.12))
	var snow_x := (GameData.SNOW_LINE - lo) / (hi - lo) * s.x
	_map.draw_line(Vector2(snow_x, top), Vector2(snow_x, top + h), Color(0.6, 0.85, 1.0, 0.45), 1.5)
	var pts := PackedVector2Array()
	var n: int = disk.sigma.size()
	var col_w := s.x / n
	for i in n:
		var v: float = disk.sigma[i]
		var y := top + h - clampf(v / 2.2, 0.0, 1.0) * h
		pts.append(Vector2((i + 0.5) * col_w, y))
		_map.draw_rect(Rect2(i * col_w, y, col_w + 0.5, top + h - y), Color(1.0, 0.7, 0.4, 0.22))
	_map.draw_polyline(pts, Color(1.0, 0.8, 0.5, 0.85), 2.0, true)
	var ev = stage.events
	if ev != null and ev.active():
		var ex: float = (ev.r - lo) / (hi - lo) * s.x
		var ec: Color = ev.color()
		var a := 0.6 + 0.4 * sin(_time * 4.0)
		if ev.kind == "flare":
			_map.draw_rect(Rect2(0, top, ex, h), Color(ec, 0.18 * a))
		else:
			var ew: float = ev.tol() / (hi - lo) * s.x
			_map.draw_rect(Rect2(ex - ew, top, ew * 2.0, h), Color(ec, 0.22 * a))
		_map.draw_line(Vector2(ex, top - 2), Vector2(ex, top + h + 2), Color(ec, a), 2.0)
		_map.draw_colored_polygon(PackedVector2Array([Vector2(ex - 6, top - 9), Vector2(ex + 6, top - 9), Vector2(ex, top - 1)]), Color(ec, a))
	# Тела диска на карте: еда тёплая, тяжелее тебя — красная.
	var w = stage.world
	if w != null:
		for b in w.bodies:
			var role: String = w.role(b)
			if role == "food" and float(b.m) < 0.4:
				continue
			var bx: float = (float(b.r) - lo) / (hi - lo) * s.x
			if bx < 0.0 or bx > s.x:
				continue
			var bc := Color(1.0, 0.4, 0.32, 0.95) if role == "danger" else (UiTheme.GOLD if role == "merge" else (Color(0.95, 0.88, 0.7, 0.6) if role == "food" else (Color(1.0, 0.62, 0.32, 0.85) if role == "big" else Color(0.7, 0.8, 0.95, 0.6))))
			var by := top + h * (0.25 + 0.5 * fmod(float(b.seed), 1.0))
			_map.draw_circle(Vector2(bx, by), 4.0 if b.kind in ["rival", "dwarf"] else 2.0, bc)
	var px: float = (stage.orbit - lo) / (hi - lo) * s.x
	_map.draw_line(Vector2(px, top - 4), Vector2(px, top + h + 2), UiTheme.GOLD, 2.5)
	_map.draw_circle(Vector2(px, top - 4), 5.0, UiTheme.GOLD)
	var f := UiTheme.FONT_TEXT
	_map.draw_string(f, Vector2(6, s.y - 2), "звезда", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.7, 0.5, 0.8))
	_map.draw_string(f, Vector2(snow_x + 4, s.y - 2), "снеговая линия", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.85, 1.0, 0.8))


## Стрелки к телам мира за краем экрана: еда, вихри, опасность.
func _draw_world_marks() -> void:
	var w = stage.world
	if w == null:
		return
	var vp := _pointer.size
	var cam: Camera2D = stage.camera
	var zoom: float = cam.zoom.x
	var center: Vector2 = cam.get_screen_center_position()
	var used := []
	for m in w.markers():
		var sp: Vector2 = ((m.p as Vector2) - center).rotated(-cam.rotation) * zoom + vp * 0.5
		var margin := 48.0
		if sp.x > margin and sp.x < vp.x - margin and sp.y > 140.0 and sp.y < vp.y - 120.0:
			continue
		var dir := (sp - vp * 0.5).normalized()
		# Точка на краю безопасной рамки экрана.
		var half := Vector2(vp.x * 0.5 - margin, vp.y * 0.5 - 130.0)
		var k := minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
		var at := vp * 0.5 + dir * k
		var clash := false
		for u in used:
			if (u as Vector2).distance_to(at) < 90.0:
				clash = true
		if clash:
			continue
		used.append(at)
		var c: Color = m.col
		var a := 0.6 + 0.3 * sin(_time * 3.0)
		var tip := at + dir * 16.0
		var side := dir.orthogonal() * 11.0
		_pointer.draw_colored_polygon(PackedVector2Array([tip, at - dir * 6.0 + side, at - dir * 6.0 - side]), Color(c, a))
		var dist := ((m.p as Vector2) - center).length() / GameData.AU_UNITS
		var txt := "%s · %s а.е." % [m.text, ("%.1f" % dist).replace(".", ",")]
		var tp := at - dir * 40.0 - Vector2(110.0, -5.0)
		tp.x = clampf(tp.x, 8.0, vp.x - 228.0)
		_pointer.draw_string(UiTheme.FONT_SEMI, tp, txt, HORIZONTAL_ALIGNMENT_CENTER, 220, 14, Color(c, 0.9))


## Стрелка к цели события у края экрана, если сама цель за ним.
func _draw_pointer() -> void:
	_draw_world_marks()
	var ev = stage.events
	if ev == null or not ev.active():
		return
	var vp := _pointer.size
	var zoom: float = stage.camera.zoom.x
	var sx: float = vp.x * 0.5 + (ev.r - stage.orbit) * zoom
	if sx > 60.0 and sx < vp.x - 60.0:
		return
	var right := sx >= vp.x - 60.0
	var c: Color = ev.color()
	var a := 0.65 + 0.35 * sin(_time * 4.0)
	var x := vp.x - 46.0 if right else 46.0
	var y := vp.y * 0.5
	var d := 1.0 if right else -1.0
	_pointer.draw_colored_polygon(PackedVector2Array([Vector2(x + 18 * d, y), Vector2(x - 6 * d, y - 16), Vector2(x - 6 * d, y + 16)]), Color(c, a))
	var dist := absf(ev.r - stage.orbit) / GameData.AU_UNITS
	var txt := ("%.1f" % dist).replace(".", ",") + " а.е."
	var tx := x - 70.0 if right else x - 10.0
	_pointer.draw_string(UiTheme.FONT_SEMI, Vector2(tx, y + 38), txt, HORIZONTAL_ALIGNMENT_CENTER, 80, 15, Color(c, 0.9))
