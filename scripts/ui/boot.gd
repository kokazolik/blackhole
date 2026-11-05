extends Control
## Экран загрузки (автор: «чтобы в начале игры не лагало»). Лаг первых секунд
## — компиляция шейдеров при первом показе и растеризация букв шрифтов. Здесь
## это делается заранее, под тёмным экраном:
## 1) каждый шейдер игры рисуется один раз крошечным квадратом (и в варианте
##    MultiMesh — так рисуются пыль, гальки и газ гиганта);
## 2) все шрифты печатают алфавит в ходовых размерах;
## 3) сцены этапов грузятся в фоне и остаются в памяти (Boot.keep).
## Потом — плавный переход в меню.

const SHADERS := [
	"comet", "dust", "eddy", "embryo", "far_body", "frac", "gas_disk", "gas_giant",
	"giant_bake", "giant_cpd", "giant_map", "giant_planet", "giant_ring", "giant_rock",
	"herald_rock", "herald_shadow", "herald_tile_bake", "impact_plume", "lit_grain",
	"menu_bg", "moon", "nebula", "pebble", "pebble_body", "planetesimal",
	"planetesimal_bake", "planetesimal_normals", "pressure_rings", "protostar",
	"pulse_ripple", "shard", "space_bg", "spotlight", "star_halo", "tidal_stream",
	"vortex", "young_envelope", "young_star",
]
## Эти шейдеры рисуются через MultiMesh — у них свой вариант программы.
const MULTI := ["dust", "pebble", "lit_grain"]
const SCENES := [Fader.MENU, Fader.GAME, Fader.GIANT, Fader.YOUNG, Fader.CLOUD, Fader.PROLOGUE]
const GLYPHS := "АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯабвгдеёжзийклмнопрстуфхцчшщъыьэюя" \
	+ "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 .,:;!?«»—–-+×·%/()⊕☉"
const SIZES := [10, 11, 12, 13, 14, 15, 16, 18, 20, 22, 24, 26, 28, 32, 36, 40, 48, 56, 64]
const PHASES := ["Собираем пыль", "Раскручиваем диск", "Зажигаем звёзды", "Почти готово"]
const MIN_TIME := 1.2
## Что сейчас готовится — по-человечески (автор: «пусть показывается процент
## и что там компилируется»).
const TITLES := {
	"comet": "кометы", "dust": "пыль диска", "eddy": "вихри газа", "embryo": "зародыши планет",
	"far_body": "далёкие тела", "frac": "раскол тел", "gas_disk": "газовый диск",
	"gas_giant": "газовые гиганты", "giant_bake": "облака гиганта", "giant_cpd": "диск у гиганта",
	"giant_map": "карты облаков", "giant_planet": "шар гиганта", "giant_ring": "кольца",
	"giant_rock": "ядро гиганта", "herald_rock": "валуны", "herald_shadow": "тени валунов",
	"herald_tile_bake": "поверхность валунов", "impact_plume": "шлейфы ударов",
	"lit_grain": "зёрна на свету", "menu_bg": "диск в меню", "moon": "малые тела",
	"nebula": "туманность", "pebble": "гальки", "pebble_body": "тело гальки",
	"planetesimal": "планетезимали", "planetesimal_bake": "рельеф планетезималей",
	"planetesimal_normals": "свет на рельефе", "pressure_rings": "кольца давления",
	"protostar": "протозвезда", "pulse_ripple": "волны", "shard": "осколки",
	"space_bg": "звёздное небо", "spotlight": "свет звезды", "star_halo": "сияние звезды",
	"tidal_stream": "приливные струи", "vortex": "вихри", "young_envelope": "оболочка молодого гиганта",
	"young_star": "молодая звезда",
}
const SCENE_TITLES := {
	Fader.MENU: "меню", Fader.GAME: "диск и пыль", Fader.GIANT: "этап гиганта",
	Fader.YOUNG: "молодая планета", Fader.CLOUD: "облако и звезда", Fader.PROLOGUE: "пролог",
}

static var keep: Array = []      # сцены этапов: держим, чтобы не грузить второй раз

var _warm := Control.new()       # под экраном загрузки: сюда рисуется прогрев
var _bar := ColorRect.new()
var _bar_bg := ColorRect.new()
var _status := Label.new()
var _detail := Label.new()
var _jobs: Array = []
var _done := 0
var _total := 1
var _t := 0.0
var _leaving := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_warm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_warm)
	_build_ui()
	for path in SCENES:
		ResourceLoader.load_threaded_request(path, "", true)
	for s in SHADERS:
		_jobs.append(["shader", s])
	var fonts := [UiTheme.FONT_TEXT, UiTheme.FONT_SEMI, UiTheme.FONT_NUMBERS, UiTheme.FONT_HEAD,
		UiTheme.FONT_DISPLAY, UiTheme.FONT_DISPLAY_BOLD]
	for f in fonts:
		_jobs.append(["font", f])
	for path in SCENES:
		_jobs.append(["scene", path])
	_total = _jobs.size()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.01, 0.03)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.anchor_left = 0.0
	box.anchor_right = 1.0
	box.offset_left = 48.0
	box.offset_right = -48.0
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	add_child(box)
	for line in ["ОТ ПЫЛИНКИ", "ДО ЧЁРНОЙ ДЫРЫ"]:
		var t := Label.new()
		t.text = line
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t.add_theme_font_override("font", UiTheme.spaced(UiTheme.FONT_DISPLAY, 6))
		t.add_theme_font_size_override("font_size", 30)
		t.add_theme_color_override("font_color", Color(UiTheme.PARCHMENT, 0.92))
		box.add_child(t)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 36)
	box.add_child(gap)
	# Волосяная линия прогресса: тусклая дорожка и тёплая заливка.
	var holder := CenterContainer.new()
	box.add_child(holder)
	_bar_bg.custom_minimum_size = Vector2(260, 2)
	_bar_bg.color = Color(1, 1, 1, 0.12)
	holder.add_child(_bar_bg)
	_bar.size = Vector2(0, 2)
	_bar.color = Color(UiTheme.GOLD, 0.85)
	_bar_bg.add_child(_bar)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_override("font", UiTheme.spaced(UiTheme.FONT_TEXT, 2))
	_status.add_theme_font_size_override("font_size", 14)
	_status.add_theme_color_override("font_color", Color(UiTheme.PARCHMENT, 0.55))
	_status.text = PHASES[0]
	box.add_child(_status)
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail.add_theme_font_override("font", UiTheme.FONT_TEXT)
	_detail.add_theme_font_size_override("font_size", 12)
	_detail.add_theme_color_override("font_color", Color(UiTheme.PARCHMENT, 0.35))
	box.add_child(_detail)


func _process(delta: float) -> void:
	_t += delta
	# Несколько задач за кадр: каждая — один шейдер или один шрифт.
	var budget := 1
	while budget > 0 and not _jobs.is_empty():
		var j: Array = _jobs[0]
		if j[0] == "scene":
			var st := ResourceLoader.load_threaded_get_status(j[1])
			if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				break
			if st == ResourceLoader.THREAD_LOAD_LOADED:
				keep.append(ResourceLoader.load_threaded_get(j[1]))
			_detail.text = "сцена: " + str(SCENE_TITLES.get(j[1], j[1]))
		elif j[0] == "shader":
			_warm_shader(j[1])
			_detail.text = "шейдер: %s · %s.gdshader" % [TITLES.get(j[1], j[1]), str(j[1]).get_file()]
		else:
			_warm_font(j[1])
			_detail.text = "шрифт: " + str((j[1] as Font).resource_path.get_file().get_basename())
		_jobs.pop_front()
		_done += 1
		budget -= 1
	var k := minf(float(_done) / float(_total), _t / MIN_TIME)
	_bar.size = Vector2(_bar_bg.custom_minimum_size.x * k, 2)
	_status.text = "%s · %d%%" % [PHASES[mini(int(k * PHASES.size()), PHASES.size() - 1)], roundi(k * 100.0)]
	if _jobs.is_empty():
		_detail.text = "всё готово"
	if _jobs.is_empty() and _t >= MIN_TIME and not _leaving:
		_leaving = true
		# Ещё кадр — дорисовать последний прогрев, потом в меню.
		await get_tree().process_frame
		await get_tree().process_frame
		Fader.go(Fader.MENU, 0.5, 0.9)


func _warm_shader(sname: String) -> void:
	var sh := load("res://shaders/%s.gdshader" % sname) as Shader
	if sh == null:
		return
	var m := ShaderMaterial.new()
	m.shader = sh
	var r := ColorRect.new()
	r.size = Vector2(4, 4)
	r.material = m
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_warm.add_child(r)
	if sname in MULTI:
		for colors in [true, false]:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_2D
			mm.use_colors = colors
			mm.use_custom_data = true
			var q := QuadMesh.new()
			q.size = Vector2(4, 4)
			mm.mesh = q
			mm.instance_count = 1
			mm.set_instance_transform_2d(0, Transform2D(0.0, Vector2(2, 2)))
			var n := MultiMeshInstance2D.new()
			n.multimesh = mm
			n.material = m
			_warm.add_child(n)
	if sname == "dust":
		# Газ гиганта — MultiMesh с цветами без своего шейдера.
		var mm2 := MultiMesh.new()
		mm2.transform_format = MultiMesh.TRANSFORM_2D
		mm2.use_colors = true
		mm2.mesh = QuadMesh.new()
		mm2.instance_count = 1
		var n2 := MultiMeshInstance2D.new()
		n2.multimesh = mm2
		_warm.add_child(n2)


func _warm_font(f: Font) -> void:
	for s in SIZES:
		var l := Label.new()
		l.text = GLYPHS
		l.add_theme_font_override("font", f)
		l.add_theme_font_size_override("font_size", s)
		l.position = Vector2(0, 0)
		l.clip_text = true
		l.size = Vector2(4, 4)
		_warm.add_child(l)
