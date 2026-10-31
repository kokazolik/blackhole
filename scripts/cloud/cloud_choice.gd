extends Control
## Конец гиганта для тех, кто дорос до супер-Юпитера: остаться им (концовка)
## или уйти в облако, путь к звезде. Справа — протозвезда в коконе.

signal chosen(route: String)

const GIANT_SHADER := preload("res://shaders/gas_giant.gdshader")
const PROTO_SHADER := preload("res://shaders/protostar.gdshader")
const ART := Vector2(360, 230)

var kind := "brown_dwarf"
var _proto := ShaderMaterial.new()
var _t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiTheme.get_theme()
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.03, 0.86)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)
	var bd := kind == "brown_dwarf"
	box.add_child(_line("Дейтерий горит!" if bd else "Газ диска ушёл", UiTheme.FONT_SERIF_BOLD, 40, UiTheme.GOLD))
	box.add_child(_line("Ты уже не планета. Можно остаться здесь, а можно стать звездой." if bd else "Ты тяжелее тысячи Земель. Можно остаться здесь, а можно попробовать стать звездой.",
		UiTheme.FONT_SERIF_ITALIC, 20, UiTheme.PARCHMENT))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 28)
	box.add_child(row)

	var look: Array = GameData.GIANT_LOOK[kind]
	var giant := ShaderMaterial.new()
	giant.shader = GIANT_SHADER
	giant.set_shader_parameter("aspect", ART.x / ART.y)
	giant.set_shader_parameter("band_light", look[0])
	giant.set_shader_parameter("band_dark", look[1])
	giant.set_shader_parameter("storm_col", look[2])
	var e: Dictionary = GameData.ENDINGS[kind]
	row.add_child(_card(giant, "Остаться: " + str(e["name"]), str(e["desc"]), "Наследие %d" % int(e["legacy"]), "stay", false))

	_proto.shader = PROTO_SHADER
	var params := GameData.cloud_params(GameState.fate_type(), GameState.body_type() == "neutral" and not GameState.is_melted)
	_proto.set_shader_parameter("cocoon_col", params["cocoon"])
	_proto.set_shader_parameter("heat", 0.7)
	_proto.set_shader_parameter("jets", 0.8)
	_proto.set_shader_parameter("axis", 0.35)
	var mj := float(GameState.giant.get("e", GameData.BROWN_DWARF)) / GameData.JUPITER_EARTHS
	var desc := "Соседняя звезда выбросит тебя из системы в молекулярное облако. Набери %d масс Юпитера, и загорится водород. Сейчас в тебе %s." % [
		roundi(float(params["ignite"])), String.num(mj, 1).replace(".", ",")]
	if not bd:
		desc += " Путь длиннее, чем у коричневого карлика."
	row.add_child(_card(_proto, "В облако: путь к звезде", desc, "Наследие %d–%d · новый этап" % [int(GameData.ENDINGS["star_failed"]["legacy"]),
		int(GameData.ENDINGS["star_titan"]["legacy"])], "cloud", true))


func _process(delta: float) -> void:
	_t += delta
	_proto.set_shader_parameter("time", _t)


func _card(mat: ShaderMaterial, title: String, desc: String, reward: String, route: String, primary: bool) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.painted_panel(24))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var frame := CenterContainer.new()
	frame.custom_minimum_size = ART
	v.add_child(frame)
	var art := ColorRect.new()
	art.material = mat
	art.custom_minimum_size = ART if route == "stay" else Vector2.ONE * ART.y * 1.1
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(art)
	if route == "cloud":
		art.color = Color(0, 0, 0, 0)
	v.add_child(_line(title, UiTheme.FONT_SERIF_BOLD, 28, UiTheme.GOLD))
	var d := _line(desc, UiTheme.FONT_SERIF_ITALIC, 18, UiTheme.PARCHMENT)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(ART.x, 110)
	v.add_child(d)
	v.add_child(_line(reward, UiTheme.FONT_SEMI, 16, Color(0.75, 0.88, 1.0)))
	var b := Button.new()
	b.text = "Выбрать"
	b.custom_minimum_size = Vector2(240, 56)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UiTheme.paint_button(b, primary, 24)
	b.pressed.connect(func():
		chosen.emit(route)
		queue_free())
	v.add_child(b)
	return panel


func _line(text: String, font: Font, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font:
		l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l
