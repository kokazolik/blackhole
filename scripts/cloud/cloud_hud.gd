extends Control
## Интерфейс облака: звёздная пыль и масса слева, время облака, путь к
## зажиганию и будущий класс звезды сверху, карта облака справа внизу,
## стрелка к ближайшему узлу газа и кнопка сброса вспышки FU Ориона.

signal tree_requested
signal menu_requested
signal burst_pressed

const BOOK_ICON := preload("res://assets/ui/book.png")
const MAP := 210.0

var stage  # cloud_stage.gd
var _currency: Label
var _chondrules: Label
var _mass: Label
var _status: Label
var _title: Label
var _bar: Control
var _time_label: Label
var _class: Label
var _ign: Control
var _map: Control
var _map_tex: ImageTexture
var _map_img: Image
var _map_t := 0.0
var _spark: Control
var _caption: VBoxContainer
var _cap_title: Label
var _cap_sub: Label
var _toast: Label
var _badge: Control
var _pointer: Control
var _burst: Button
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
	_mass = _label(19, UiTheme.TEXT, UiTheme.FONT_SEMI)
	left.add_child(_mass)
	_status = _label(16, UiTheme.TEXT_DIM, UiTheme.FONT_TEXT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(360, 0)
	left.add_child(_status)
	_shown = GameState.currency

	var top := VBoxContainer.new()
	top.anchor_left = 0.5
	top.anchor_right = 0.5
	top.offset_left = -230
	top.offset_right = 230
	top.offset_top = 12
	top.add_theme_constant_override("separation", 4)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	_title = _label(26, UiTheme.PARCHMENT, UiTheme.FONT_SERIF_BOLD)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_title)
	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(440, 10)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	top.add_child(_bar)
	_time_label = _label(14, UiTheme.TEXT_DIM, UiTheme.FONT_TEXT)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_time_label)
	_ign = Control.new()
	_ign.custom_minimum_size = Vector2(440, 22)
	_ign.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ign.draw.connect(_draw_ign)
	top.add_child(_ign)
	_class = _label(16, UiTheme.GOLD, UiTheme.FONT_SEMI)
	_class.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_class.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(_class)

	_map = Control.new()
	_map.anchor_left = 1.0
	_map.anchor_right = 1.0
	_map.anchor_top = 1.0
	_map.anchor_bottom = 1.0
	_map.offset_left = -MAP - 18
	_map.offset_right = -18
	_map.offset_top = -MAP - 18
	_map.offset_bottom = -18
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.clip_contents = true
	_map.draw.connect(_draw_map)
	add_child(_map)
	_map_img = Image.create(GameData.CLOUD_N, GameData.CLOUD_N, false, Image.FORMAT_RGBA8)
	_map_tex = ImageTexture.create_from_image(_map_img)

	_pointer = Control.new()
	_pointer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pointer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pointer.draw.connect(_draw_pointer)
	add_child(_pointer)

	_burst = Button.new()
	_burst.text = "Сбросить вспышку"
	_burst.anchor_left = 0.5
	_burst.anchor_right = 0.5
	_burst.anchor_top = 1.0
	_burst.anchor_bottom = 1.0
	_burst.offset_left = -150
	_burst.offset_right = 150
	_burst.offset_top = -170
	_burst.offset_bottom = -100
	_burst.focus_mode = Control.FOCUS_NONE
	UiTheme.paint_button(_burst, true, 26)
	_burst.visible = false
	_burst.pressed.connect(func(): burst_pressed.emit())
	add_child(_burst)

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
	_caption.offset_top = 130
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.modulate.a = 0.0
	add_child(_caption)
	_cap_title = _label(32, UiTheme.PARCHMENT, UiTheme.FONT_SERIF_BOLD)
	_cap_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_child(_cap_title)
	_cap_sub = _label(19, Color(UiTheme.PARCHMENT, 0.85), UiTheme.FONT_SERIF_ITALIC)
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
	_toast.offset_top = -170
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.modulate.a = 0.0
	add_child(_toast)


func _label(size: int, color: Color, font: Font) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func caption(title: String, sub: String, hold := 4.0) -> void:
	_cap_title.text = title
	_cap_sub.text = sub
	var tw := _caption.create_tween()
	tw.tween_property(_caption, "modulate:a", 1.0, 0.7)
	tw.tween_interval(hold)
	tw.tween_property(_caption, "modulate:a", 0.0, 1.2)


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
	var mj: float = stage.mj
	_mass.text = GameData.format_star_mass(mj) + ("" if mj >= 0.3 * GameData.SUN_JUPITERS else " · %s массы Солнца" % String.num(mj / GameData.SUN_JUPITERS, 3).replace(".", ","))
	_status.text = _status_text()
	_title.text = "Молодая звезда" if stage.lit else "Облако"
	var left: float = stage.left()
	_time_label.text = "облако рассеется через %d:%02d" % [int(left) / 60, int(left) % 60]
	_class.text = _class_text(mj)
	_ign.visible = not stage.lit
	_map.visible = stage.ign_t < 0.0 and stage.dawn_t < 0.0
	stage.joystick.visible = stage.ign_t < 0.0 and stage.dawn_t < 0.0
	_badge.visible = _can_buy()
	_burst.visible = stage.burst_t >= 0.0
	if _burst.visible:
		var hot: bool = stage.burst_window()
		_burst.modulate = Color(1.2, 1.1, 0.7) if hot else Color(1.0, 0.75, 0.7)
		_burst.text = "Сбросить вспышку!" if hot else "Вспышка копится…"
	_map_t -= delta
	if _map_t <= 0.0:
		_map_t = 0.5
		_bake_map()
	_pointer.queue_redraw()
	_spark.queue_redraw()
	_badge.queue_redraw()
	_bar.queue_redraw()
	_ign.queue_redraw()
	_map.queue_redraw()


func _status_text() -> String:
	if stage.ign_t >= 0.0:
		return "зажигание"
	if stage.uv_loss:
		return "ультрафиолет выпаривает тебя: уходи в тёмный газ"
	var rho: float = stage.local
	var where := "пустота"
	if rho > 0.9:
		where = "узел волокон"
	elif rho > 0.45:
		where = "волокно газа"
	elif rho > 0.18:
		where = "редкий газ"
	var gain: float = stage.rate * 100.0
	var txt := "%s · рост %s%%/с" % [where, String.num(gain, 1).replace(".", ",")]
	if stage.in_shock > 0.3:
		txt += " · ударная волна!"
	if stage.vel.length() > GameData.CLOUD_SPEED * 0.5:
		txt += " · мчишься: газ не успевает падать"
	return txt


func _class_text(mj: float) -> String:
	if not stage.lit:
		return ""
	var now: String = GameData.ENDINGS[GameData.star_class(mj, true)]["name"]
	var nxt := GameData.star_next(mj)
	if nxt < 0.0:
		return "станешь: " + now
	return "станешь: %s · следующий класс с %s" % [now, GameData.format_star_mass(nxt)]


func _can_buy() -> bool:
	for id in Skills.order:
		if Skills.is_unlocked(id) and Skills.level(id) < Skills.max_level(id) \
				and GameState.currency >= Skills.cost(id) and GameState.chondrules >= Skills.cost2(id):
			return true
	return false


func _draw_bar() -> void:
	var rect := Rect2(Vector2.ZERO, _bar.size)
	UiTheme.pill(Color(1, 1, 1, 0.08), 4).draw(_bar.get_canvas_item(), rect)
	var f: float = clampf(stage.left() / GameData.CLOUD_TIME, 0.0, 1.0)
	if f > 0.001:
		var col := Color(0.75, 0.55, 0.9).lerp(Color(1.0, 0.35, 0.3), 1.0 - smoothstep(0.0, 0.25, f))
		UiTheme.pill(col, 4).draw(_bar.get_canvas_item(), Rect2(Vector2.ZERO, Vector2(maxf(rect.size.x * f, 8.0), rect.size.y)))


## Путь к зажиганию в логарифме массы: от старта до порога состава.
func _draw_ign() -> void:
	var s := _ign.size
	var y := 5.0
	var from: float = log(maxf(stage.mj0 * 0.9, 1.0))
	var to: float = log(float(stage.params["ignite"]))
	var f := clampf((log(stage.mj) - from) / (to - from), 0.0, 1.0)
	UiTheme.pill(Color(1, 1, 1, 0.08), 4).draw(_ign.get_canvas_item(), Rect2(0, y, s.x, 8))
	UiTheme.pill(UiTheme.GOLD, 4).draw(_ign.get_canvas_item(), Rect2(0, y, maxf(s.x * f, 8.0), 8))
	var txt := "до зажигания водорода: %d из %d масс Юпитера" % [floori(stage.mj), roundi(float(stage.params["ignite"]))]
	_ign.draw_string(UiTheme.FONT_TEXT, Vector2(0, y + 24), txt, HORIZONTAL_ALIGNMENT_CENTER, s.x, 14, Color(UiTheme.GOLD, 0.9))


## Карта облака: газ, фронт, сверхновая, соседи и ты.
func _bake_map() -> void:
	var n := GameData.CLOUD_N
	var bytes := PackedByteArray()
	bytes.resize(n * n * 4)
	for j in n:
		var fy: float = stage.front_at((j + 0.5) * GameData.CLOUD_CELL)
		for i in n:
			var k := j * n + i
			var g: float = clampf(stage.grid[k] / 1.4, 0.0, 1.0)
			var ion := (i + 0.5) * GameData.CLOUD_CELL < fy
			var c := Color(0.95, 0.35, 0.42, 0.25 + 0.4 * g) if ion else Color(0.95, 0.78, 0.6, 0.12 + 0.75 * sqrt(g))
			bytes[k * 4] = int(c.r * 255.0)
			bytes[k * 4 + 1] = int(c.g * 255.0)
			bytes[k * 4 + 2] = int(c.b * 255.0)
			bytes[k * 4 + 3] = int(c.a * 255.0)
	_map_img.set_data(n, n, false, Image.FORMAT_RGBA8, bytes)
	_map_tex.update(_map_img)


func _draw_map() -> void:
	var s := Vector2(MAP, MAP)
	UiTheme.pill(Color(0.03, 0.03, 0.07, 0.62), 10).draw(_map.get_canvas_item(), Rect2(Vector2.ZERO, s))
	_map.draw_texture_rect(_map_tex, Rect2(Vector2(5, 5), s - Vector2(10, 10)), false)
	var w := GameData.CLOUD_N * GameData.CLOUD_CELL
	var k := (MAP - 10.0) / w
	var o := Vector2(5, 5)
	if stage.sn.has("c"):
		var c: Vector2 = stage.sn.c
		_map.draw_arc(o + c * k, float(stage.sn.r) * k, 0.0, TAU, 64, Color(0.6, 0.85, 1.0, 0.8), 2.0, true)
	for rv in stage.rivals:
		var m: float = rv.mj
		var col := Color(1.0, 0.4, 0.3) if m > stage.mj * 1.2 else (Color(0.5, 0.85, 1.0) if stage.mj > m * 1.2 else Color(1.0, 0.85, 0.5))
		var p: Vector2 = o + (rv.p as Vector2) * k
		if p.x > 2 and p.y > 2 and p.x < MAP - 2 and p.y < MAP - 2:
			_map.draw_circle(p, 2.5, col)
	var me: Vector2 = o + (stage.pos as Vector2) * k
	_map.draw_circle(me, 4.5 + sin(_time * 5.0), UiTheme.GOLD)
	_map.draw_arc(me, 7.0, 0.0, TAU, 24, Color(UiTheme.GOLD, 0.6), 1.5, true)
	_map.draw_string(UiTheme.FONT_TEXT, Vector2(8, MAP - 8), "горячие звёзды ←", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.55, 0.6, 0.85))


## Стрелка к ближайшему узлу газа, если вокруг пусто, а узел за краем экрана.
func _draw_pointer() -> void:
	if stage.ign_t >= 0.0 or stage.local > 0.35:
		return
	var tgt: Vector2 = stage.hub_target()
	if tgt.x < 0.0:
		return
	var vp := _pointer.size
	var zoom: float = stage.camera.zoom.x
	var rel: Vector2 = (tgt - stage.pos) * zoom
	var sp := vp * 0.5 + rel
	if sp.x > 80 and sp.x < vp.x - 80 and sp.y > 80 and sp.y < vp.y - 80:
		return
	var dir := rel.normalized()
	# Точка на краю безопасной рамки экрана.
	var half := vp * 0.5 - Vector2(70, 90)
	var t := minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
	var at := vp * 0.5 + dir * t
	at.y = maxf(at.y, 230.0)
	# Не налезать на карту справа внизу и на стик слева внизу.
	if (at.x > vp.x - MAP - 160.0 or at.x < 320.0) and at.y > vp.y - MAP - 60.0:
		at.y = vp.y - MAP - 60.0
	var a := 0.65 + 0.35 * sin(_time * 4.0)
	var col := Color(1.0, 0.82, 0.55, a)
	var nrm := Vector2(-dir.y, dir.x)
	_pointer.draw_colored_polygon(PackedVector2Array([at + dir * 20.0, at - dir * 8.0 + nrm * 15.0, at - dir * 8.0 - nrm * 15.0]), col)
	_pointer.draw_string(UiTheme.FONT_SEMI, at - dir * 40.0 + Vector2(-50, 6), "узел газа", HORIZONTAL_ALIGNMENT_CENTER, 100, 15, col)
