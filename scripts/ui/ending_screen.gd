class_name EndingScreen
extends Control
## Экран концовки: кем ты стал, что унёс с собой (наследие) и новый забег.

const PLANET_COLORS := {
	"giant_cold": [Color(0.86, 0.72, 0.52), Color(0.6, 0.4, 0.26)],
	"giant_hot": [Color(1.0, 0.62, 0.36), Color(0.7, 0.28, 0.16)],
	"giant_ice": [Color(0.55, 0.8, 0.95), Color(0.24, 0.46, 0.76)],
	"giant_dark": [Color(0.42, 0.32, 0.24), Color(0.16, 0.11, 0.08)],
	"giant_dense": [Color(0.78, 0.76, 0.72), Color(0.44, 0.4, 0.38)],
	"giant_core": [Color(0.9, 0.78, 0.6), Color(0.62, 0.46, 0.3)],
	"super_jupiter": [Color(0.98, 0.78, 0.56), Color(0.7, 0.34, 0.2)],
	"brown_dwarf": [Color(0.8, 0.36, 0.24), Color(0.36, 0.1, 0.08)],
	"super_earth": [Color(0.55, 0.62, 0.7), Color(0.3, 0.34, 0.4)],
	"planet_rock": [Color(0.66, 0.56, 0.46), Color(0.38, 0.3, 0.24)],
	"planet_living": [Color(0.36, 0.6, 0.86), Color(0.36, 0.56, 0.3)],
	"planet_iron": [Color(0.7, 0.72, 0.78), Color(0.4, 0.42, 0.48)],
	"planet_dark": [Color(0.3, 0.27, 0.26), Color(0.14, 0.12, 0.12)],
	"planet_ocean": [Color(0.3, 0.56, 0.84), Color(0.14, 0.3, 0.56)],
	"planet_layered": [Color(0.72, 0.6, 0.5), Color(0.5, 0.42, 0.5)],
	"planet_titan": [Color(0.92, 0.62, 0.3), Color(0.42, 0.3, 0.2)],
	"planet_venus": [Color(0.95, 0.84, 0.55), Color(0.7, 0.55, 0.3)],
	"dwarf_planet": [Color(0.6, 0.57, 0.54), Color(0.36, 0.34, 0.33)],
}

var kind := ""
var gained := 0
var _icon := Control.new()
var _time := 0.0


func _init(ending: String, points: int) -> void:
	kind = ending
	gained = points


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiTheme.get_theme()
	modulate.a = 0.0
	var info: Dictionary = GameData.ENDINGS.get(kind, GameData.ENDINGS["planet_rock"])

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.02, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.painted_panel(36))
	panel.custom_minimum_size = Vector2(680, 0)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	_icon.custom_minimum_size = Vector2(0, 120)
	_icon.draw.connect(_draw_planet)
	box.add_child(_icon)

	box.add_child(_line("Концовка", UiTheme.FONT_SERIF_ITALIC, 20, Color(UiTheme.PARCHMENT, 0.7)))
	box.add_child(_line(info["name"], UiTheme.FONT_SERIF_BOLD, 42, UiTheme.GOLD))
	box.add_child(_line(info["desc"], UiTheme.FONT_SERIF_ITALIC, 21, UiTheme.PARCHMENT))

	var core := "железное ядро %d%% массы" % roundi(GameState.core_share * 100.0) if GameState.is_melted else "без ядра"
	var stats := "%s · %s · %s%s" % [GameData.format_size(GameState.mass), GameData.format_earths(GameState.mass), core,
		" · есть луна" if GameState.has_moon else ""]
	if GameState.is_giant():
		var e: float = float(GameState.giant.get("e", 10.0))
		var body: String = GameData.BODY_TYPES[GameState.fate_type()]["name"]
		stats = "%d масс Земли · %s массы Юпитера · ядро: %s · лун: %d" % [roundi(e), String.num(e / GameData.JUPITER_EARTHS, 2),
			body.to_lower(), int(GameState.giant.get("moons", 0))]
	elif kind.begins_with("giant"):
		# Состав был у ядра: теперь оно в центре, под толщей водорода и гелия.
		var body: String = GameData.BODY_TYPES[GameState.fate_type()]["name"]
		stats = "ядро: %s, %s, под толщей газа%s" % [body.to_lower(), GameData.format_earths(GameState.mass),
			" · есть луна" if GameState.has_moon else ""]
	box.add_child(_line(stats, null, 20, Color(0.75, 0.88, 1.0)))

	var legacy := "Наследие +%d" % gained
	if gained > int(info["legacy"]):
		legacy += " (новая концовка — вдвое)"
	box.add_child(_line(legacy, UiTheme.FONT_SERIF_BOLD, 26, UiTheme.GOLD))
	box.add_child(_line("Всего наследия %d: звёздной пыли +%d%% в каждом новом забеге. Концовок открыто %d из %d." % [
		GameState.legacy, roundi(GameState.legacy * GameData.LEGACY_BONUS * 100.0), GameState.endings_seen.size(), GameData.ENDINGS.size()],
		UiTheme.FONT_SERIF_ITALIC, 19, UiTheme.PARCHMENT))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	box.add_child(row)
	var again := Button.new()
	again.text = "Новый забег"
	again.custom_minimum_size = Vector2(250, 64)
	UiTheme.paint_button(again, true, 24)
	again.pressed.connect(func():
		get_tree().paused = false
		GameState.reset_run()
		Fader.go(Fader.GAME))
	row.add_child(again)
	var menu := Button.new()
	menu.text = "Главное меню"
	menu.custom_minimum_size = Vector2(230, 64)
	UiTheme.paint_button(menu, false, 24)
	menu.pressed.connect(func():
		get_tree().paused = false
		GameState.reset_run()
		Fader.go(Fader.MENU))
	row.add_child(menu)

	create_tween().tween_property(self, "modulate:a", 1.0, 1.0)


func _process(delta: float) -> void:
	_time += delta
	_icon.queue_redraw()


func _line(text: String, font: Font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font:
		l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## Итоговое тело: шар цвета концовки с полосами или материками и тенью.
func _draw_planet() -> void:
	var c := _icon.size * 0.5
	var r := 30.0 if kind == "dwarf_planet" else 52.0  # карлик заметно мельче
	var cols: Array = PLANET_COLORS.get(kind, PLANET_COLORS["planet_rock"])
	var giant := kind.begins_with("giant") or kind == "super_jupiter" or kind == "brown_dwarf"
	for k in 6:
		_icon.draw_circle(c, r * (1.0 + 0.05 * (6 - k)), Color(cols[0], 0.04))
	_icon.draw_circle(c, r, cols[0])
	var hazy := kind == "planet_titan" or kind == "planet_venus"  # поверхность скрыта облаками
	if hazy:
		for k in 4:
			_icon.draw_circle(c, r * (1.06 + 0.05 * k), Color(cols[0], 0.08))
		for i in 3:
			var y := -0.55 + i * 0.5 + 0.05 * sin(_time * 0.3 + i)
			var w := sqrt(maxf(1.0 - y * y, 0.0)) * r
			_icon.draw_line(c + Vector2(-w, y * r), c + Vector2(w, y * r), Color(cols[1], 0.22), 12.0, true)
	elif giant:
		for i in 5:
			var y := -0.8 + i * 0.38
			var w := sqrt(maxf(1.0 - y * y, 0.0)) * r
			_icon.draw_line(c + Vector2(-w, y * r), c + Vector2(w, y * r), Color(cols[1], 0.7), 7.0, true)
	else:
		for i in 7:
			var a := i * 2.4 + _time * 0.15
			var d := r * 0.55 * fposmod(i * 0.61, 1.0)
			var p := c + Vector2(cos(a) * d, sin(i * 1.3) * r * 0.5)
			_icon.draw_circle(p, r * (0.12 + 0.06 * (i % 3)), Color(cols[1], 0.85))
	# Ночная сторона.
	for k in 6:
		var f := k / 6.0
		_icon.draw_circle(c + Vector2(r * (0.25 + 0.4 * f), 0.0), r * (0.95 - 0.5 * f), Color(0.02, 0.01, 0.04, 0.1))
	_icon.draw_arc(c, r, 0.0, TAU, 64, Color(1.0, 0.92, 0.75, 0.4), 1.5, true)
	if GameState.has_moon:
		var m := c + Vector2(cos(_time * 0.6) * r * 1.6, sin(_time * 0.6) * r * 0.3)
		_icon.draw_circle(m, 8.0, Color(0.75, 0.74, 0.72))
		_icon.draw_circle(m + Vector2(3.0, 0.0), 6.0, Color(0.05, 0.05, 0.08, 0.4))
