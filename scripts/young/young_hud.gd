extends Control
## Интерфейс молодой планеты: пыль и хондры слева, время бомбардировки и
## судьба сверху, три шкалы климата справа (температура, вода, небо),
## карта орбит снизу с зоной жизни и кометным поясом, книга и меню справа.

signal tree_requested
signal menu_requested

const BOOK_ICON := preload("res://assets/ui/book.png")
const MAP_SIZE := Vector2(520.0, 54.0)
const GAUGE_W := 230.0
const MAP_MAX_AU := 5.2

var stage  # young_stage.gd
var _currency: Label
var _chondrules: Label
var _info: Label
var _class: Label
var _time_bar: Control
var _time_label: Label
var _gauges: Control
var _map: Control
var _spark: Control
var _caption: VBoxContainer
var _cap_title: Label
var _cap_sub: Label
var _toast: Label
var _badge: Control
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
	_info = _label(16, UiTheme.TEXT, UiTheme.FONT_SEMI)
	left.add_child(_info)
	_shown = GameState.currency

	var top := VBoxContainer.new()
	top.anchor_left = 0.5
	top.anchor_right = 0.5
	top.offset_left = -240
	top.offset_right = 240
	top.offset_top = 12
	top.add_theme_constant_override("separation", 4)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	var title := _label(26, UiTheme.PARCHMENT, UiTheme.FONT_SERIF_BOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text = "Молодая планета"
	top.add_child(title)
	_time_bar = Control.new()
	_time_bar.custom_minimum_size = Vector2(440, 10)
	_time_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_time_bar.draw.connect(_draw_time_bar)
	top.add_child(_time_bar)
	_time_label = _label(14, UiTheme.TEXT_DIM, UiTheme.FONT_TEXT)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_time_label)
	_class = _label(17, UiTheme.GOLD, UiTheme.FONT_SEMI)
	_class.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_class)

	_gauges = Control.new()
	_gauges.anchor_left = 1.0
	_gauges.anchor_right = 1.0
	_gauges.offset_left = -GAUGE_W - 30.0
	_gauges.offset_right = -30.0
	_gauges.offset_top = 190.0
	_gauges.offset_bottom = 400.0
	_gauges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gauges.draw.connect(_draw_gauges)
	add_child(_gauges)

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
	_cap_sub = _label(18, Color(UiTheme.PARCHMENT, 0.85), UiTheme.FONT_SERIF_ITALIC)
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
	var body: String = GameData.BODY_TYPES.get(stage.type, GameData.BODY_TYPES["neutral"])["name"]
	_info.text = "%s · %s а.е. от звезды\nМагнитное поле %d%%" % [body, _num(stage.au(), 2), roundi(stage.field * 100.0)]
	var left: float = stage.left()
	_time_label.text = "бомбардировка стихнет через %d:%02d" % [int(left) / 60, int(left) % 60]
	_class.text = "сейчас: " + str(GameData.ENDINGS[stage.fate()]["name"])
	_badge.visible = _can_buy()
	_spark.queue_redraw()
	_badge.queue_redraw()
	_time_bar.queue_redraw()
	_gauges.queue_redraw()
	_map.queue_redraw()


static func _num(v: float, digits := 1) -> String:
	return String.num(v, digits).replace(".", ",")


func _can_buy() -> bool:
	for id in Skills.order:
		if Skills.is_unlocked(id) and Skills.level(id) < Skills.max_level(id) \
				and GameState.currency >= Skills.cost(id) and GameState.chondrules >= Skills.cost2(id):
			return true
	return false


func _draw_time_bar() -> void:
	var rect := Rect2(Vector2.ZERO, _time_bar.size)
	UiTheme.pill(Color(1, 1, 1, 0.08), 4).draw(_time_bar.get_canvas_item(), rect)
	var f: float = clampf(stage.left() / GameData.YOUNG_TIME, 0.0, 1.0)
	if f > 0.001:
		UiTheme.pill(Color(0.75, 0.82, 1.0), 4).draw(_time_bar.get_canvas_item(), Rect2(Vector2.ZERO, Vector2(maxf(rect.size.x * f, 8.0), rect.size.y)))


## Три шкалы климата: где сейчас планета и где нужно для жизни (зелёная полоса).
func _draw_gauges() -> void:
	var s := _gauges.size
	UiTheme.pill(Color(0.03, 0.04, 0.09, 0.5), 12).draw(_gauges.get_canvas_item(), Rect2(Vector2(-14, -12), s + Vector2(28, 10)))
	var t_c: float = stage.temp - 273.0
	var rows := [
		["Температура", "%d °C" % roundi(t_c), _tmap(stage.temp), _tmap(GameData.YOUNG_LIFE.x), _tmap(GameData.YOUNG_LIFE.y),
			Color(1.0, 0.55, 0.35) if stage.temp > 373.0 else (Color(0.7, 0.85, 1.0) if stage.temp < 273.0 else Color(0.6, 0.95, 0.6))],
		["Вода", "%s океана Земли" % _num(stage.water), _wmap(stage.water), _wmap(GameData.YOUNG_WATER.x), _wmap(GameData.YOUNG_WATER.y),
			Color(0.45, 0.7, 1.0)],
		["Атмосфера", "%s бар" % _num(stage.atmo), _amap(stage.atmo), _amap(0.3), _amap(GameData.YOUNG_ATMO_MAX),
			Color(stage.params["atmo"])],
	]
	var y := 0.0
	var f := UiTheme.FONT_SEMI
	for r in rows:
		_gauges.draw_string(f, Vector2(0, y + 14), str(r[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiTheme.TEXT_DIM)
		_gauges.draw_string(f, Vector2(0, y + 14), str(r[1]), HORIZONTAL_ALIGNMENT_RIGHT, GAUGE_W, 15, UiTheme.TEXT)
		var bar := Rect2(0, y + 24, GAUGE_W, 8)
		UiTheme.pill(Color(1, 1, 1, 0.08), 4).draw(_gauges.get_canvas_item(), bar)
		var lo: float = r[3]
		var hi: float = r[4]
		_gauges.draw_rect(Rect2(GAUGE_W * lo, y + 22, GAUGE_W * (hi - lo), 12), Color(0.45, 0.95, 0.5, 0.22))
		var x: float = GAUGE_W * clampf(r[2], 0.0, 1.0)
		_gauges.draw_rect(Rect2(0, y + 24, x, 8), Color(r[5], 0.55))
		_gauges.draw_circle(Vector2(x, y + 28), 7.0, r[5])
		y += 62.0


## Шкалы: температура 150..500 K, вода 0..4 океана, атмосфера по логарифму до 100 бар.
static func _tmap(k: float) -> float:
	return (k - 150.0) / 350.0


static func _wmap(w: float) -> float:
	return w / 4.0


static func _amap(a: float) -> float:
	return log(1.0 + a) / log(101.0)


## Карта орбит: звезда слева, зона жизни зелёная (сдвигается с парником),
## кометы гуще за снеговой линией, ты — золотая метка.
func _draw_map() -> void:
	var s := MAP_SIZE
	UiTheme.pill(Color(0.03, 0.04, 0.09, 0.55), 10).draw(_map.get_canvas_item(), Rect2(Vector2.ZERO, s))
	var top := 8.0
	var h := s.y - 18.0
	var au_px := s.x / MAP_MAX_AU
	# Кометный пояс: чем дальше, тем гуще.
	for i in 40:
		var a0 := 1.4 + (MAP_MAX_AU - 1.4) * float(i) / 40.0
		var k := smoothstep(1.4, 3.4, a0)
		_map.draw_rect(Rect2(a0 * au_px, top, (MAP_MAX_AU - 1.4) / 40.0 * au_px + 0.5, h), Color(0.55, 0.8, 1.0, 0.3 * k))
	# Зона жизни при нынешнем парнике.
	var gh: float = stage.greenhouse()
	var w: float = stage.water
	var gh_steam := 30.0 * minf(w, 2.0) * 0.5
	var r_in := GameData.young_orbit_for(GameData.YOUNG_LIFE.y, gh + gh_steam) / GameData.AU_UNITS
	var r_out := GameData.young_orbit_for(GameData.YOUNG_LIFE.x, gh) / GameData.AU_UNITS
	var x0 := clampf(r_in * au_px, 0.0, s.x)
	var x1 := clampf(r_out * au_px, 0.0, s.x)
	if x1 > x0:
		_map.draw_rect(Rect2(x0, top, x1 - x0, h), Color(0.45, 0.95, 0.5, 0.3))
	_map.draw_rect(Rect2(0, top, 0.5 * au_px, h), Color(1.0, 0.5, 0.25, 0.35))
	var px: float = clampf(stage.au() * au_px, 0.0, s.x)
	_map.draw_line(Vector2(px, top - 4), Vector2(px, top + h + 2), UiTheme.GOLD, 2.5)
	_map.draw_circle(Vector2(px, top - 4), 5.0, UiTheme.GOLD)
	var f := UiTheme.FONT_TEXT
	_map.draw_string(f, Vector2(6, s.y - 2), "звезда", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.7, 0.5, 0.85))
	if x1 - x0 > 72.0:
		_map.draw_string(f, Vector2(x0, top + 14), "зона жизни", HORIZONTAL_ALIGNMENT_CENTER, x1 - x0, 11, Color(0.6, 1.0, 0.65, 0.9))
	_map.draw_string(f, Vector2(s.x - 110, s.y - 2), "кометы с водой", HORIZONTAL_ALIGNMENT_RIGHT, 104, 11, Color(0.65, 0.85, 1.0, 0.85))
