class_name PathChoice
extends Control
## Начало этапа зародыша: игрок выбирает путь. Газовый гигант — гонка с газом диска
## до десяти масс Земли; каменная планета — спокойный рост до массы Земли, а какой
## она будет, решает состав. Две большие картинки, чтобы выбор был виден сразу.

signal chosen(route: String)

const GIANT_SHADER := preload("res://shaders/gas_giant.gdshader")
const EMBRYO_SHADER := preload("res://shaders/embryo.gdshader")
const ART_SIZE := Vector2(380, 250)

var _planet_mat := ShaderMaterial.new()
var _spin := 0.0


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
	box.add_child(_line("Каким ты станешь?", UiTheme.FONT_SERIF_BOLD, 40, UiTheme.GOLD))
	box.add_child(_line("Газ диска рассеется через %d минут. Выбери путь — его уже не сменить." % roundi(GameData.GAS_TIME / 60.0),
		UiTheme.FONT_SERIF_ITALIC, 20, UiTheme.PARCHMENT))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 28)
	box.add_child(row)

	# Гигант помнит ядро: вид и имя — по составу и месту, где сейчас тело.
	var gk := GameData.giant_ending(GameState.fate_type(), true)
	var look: Array = GameData.GIANT_LOOK[gk]
	var giant := ShaderMaterial.new()
	giant.shader = GIANT_SHADER
	giant.set_shader_parameter("aspect", ART_SIZE.x / ART_SIZE.y)
	giant.set_shader_parameter("band_light", look[0])
	giant.set_shader_parameter("band_dark", look[1])
	giant.set_shader_parameter("storm_col", look[2])
	var g: Dictionary = GameData.ENDINGS[gk]
	row.add_child(_card(giant, 1.0, g["name"],
		"Гонка с газом: набери %d масс Земли, и газ рухнет на тебя лавиной. Дальше новый этап: пей газ диска и расти до Юпитера и больше. Не успеешь — суперземля или карликовая планета." % roundi(GameData.GIANT_EARTHS),
		"Наследие %d–%d · рискованно" % [int(GameData.ENDINGS["giant_hot"]["legacy"]), int(GameData.ENDINGS["brown_dwarf"]["legacy"])], "giant", false))

	_planet_mat.shader = EMBRYO_SHADER
	var style := GameData.embryo_style(GameState.fate_type())
	_planet_mat.set_shader_parameter("style", style)
	var duo: Array = GameData.DUO_ATMO.get(GameState.fate_type(), [GameData.EMBRYO_ATMO[style], 1.0, 0.0])
	_planet_mat.set_shader_parameter("atmo", minf(0.55 * float(duo[1]), 1.0))
	_planet_mat.set_shader_parameter("atmo_col", duo[0])
	_planet_mat.set_shader_parameter("veil", float(duo[2]))
	_planet_mat.set_shader_parameter("light_dir", Vector2(-0.85, -0.35).normalized())
	_planet_mat.set_shader_parameter("seed", 0.37)
	var fate := GameState.composition_ending()
	if fate == "planet_living":
		# Живая планета: океаны, материки и облака под голубой дымкой.
		_planet_mat.set_shader_parameter("style", GameData.LIVING_STYLE)
		_planet_mat.set_shader_parameter("atmo", 0.8)
		_planet_mat.set_shader_parameter("atmo_col", GameData.EMBRYO_ATMO[GameData.LIVING_STYLE])
	var p: Dictionary = GameData.ENDINGS[fate]
	var hint := "Кем станешь, решает состав: сейчас это «%s»." % p["name"]
	if not GameState.is_melted:
		hint = "Кем станешь, решает состав, он ещё не застыл: сейчас это «%s»." % p["name"]
	row.add_child(_card(_planet_mat, 0.5, p["name"],
		"Спокойный рост: набери массу Земли и расчисти орбиту, иначе останешься карликовой планетой. " + hint,
		"Наследие %d" % int(p["legacy"]), "planet", true))


func _process(delta: float) -> void:
	_spin += delta * 0.08
	_planet_mat.set_shader_parameter("spin", _spin)


## Карточка пути: картинка, имя, что нужно сделать, награда и кнопка.
func _card(mat: ShaderMaterial, art_k: float, title: String, desc: String, reward: String, route: String, primary: bool) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.painted_panel(24))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var frame := CenterContainer.new()
	frame.custom_minimum_size = ART_SIZE
	v.add_child(frame)
	var art := ColorRect.new()
	art.material = mat
	art.custom_minimum_size = ART_SIZE if art_k >= 1.0 else Vector2.ONE * ART_SIZE.y * art_k / 0.72
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(art)
	v.add_child(_line(title, UiTheme.FONT_SERIF_BOLD, 32, UiTheme.GOLD))
	var d := _line(desc, UiTheme.FONT_SERIF_ITALIC, 18, UiTheme.PARCHMENT)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(ART_SIZE.x, 100)
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
