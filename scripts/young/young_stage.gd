extends Node2D
## Этап «Молодая планета»: масса Земли набрана, идёт поздняя бомбардировка.
##
## Планета крупно в центре, звезда слева за краем. Стик двигает орбиту:
## ближе к звезде теплее, дальше — холоднее, но оттуда летят кометы с водой.
## Недра выдыхают атмосферу, звёздный ветер её сдувает, если поле слабое,
## а горячий океан парит и может сорвать парник. Что будет на планете, когда
## бомбардировка стихнет, то и станет концовкой.
##
## У каждого состава своя игра (GameData.YOUNG_TYPES): сухое железо зовёт
## кометы, океанский мир выпаривает лишнюю воду, углерод и «Венера» бегут от
## парника, Титан остаётся в холоде, хондрит собирает хондры.

const YoungHud := preload("res://scripts/young/young_hud.gd")
const EMBRYO_SHADER := preload("res://shaders/embryo.gdshader")
const SAVE_EVERY := 3.0
const SPAWN_R := 900.0       # откуда прилетают тела, пикселей от планеты

var camera := Camera2D.new()
var hud: YoungHud
var joystick: VirtualJoystick
var tree_screen: SkillTreeScreen
var pause_menu: PauseMenu
var type := "silicate"
var params: Dictionary
var orbit := 2518.0
var time := 0.0
var water := 0.3
var atmo := 0.3
var temp := 288.0
var field := 0.3
var auto_input := 0.0        # для бота
var use_auto := false
var planet_r := 190.0

var _planet := ColorRect.new()
var _mat := ShaderMaterial.new()
var _sky := Node2D.new()     # звезда, тела и вспышки
var _bodies: Array = []      # {p, v, comet}
var _flashes: Array = []     # {p, t, comet}
var _comet_acc := 0.0
var _rock_acc := 0.0
var _save_t := 0.0
var _said := {}
var _ending_t := -1.0
var _spin := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_priority = 100
	_rng.randomize()
	var y: Dictionary = GameState.young
	type = GameState.fate_type()
	if not GameData.YOUNG_TYPES.has(type):
		type = "silicate"
	params = GameData.young_params(type)
	orbit = float(y.get("r", GameData.AU_UNITS))
	time = float(y.get("t", 0.0))
	water = float(y.get("w", 0.3))
	atmo = float(y.get("a", 0.3))
	field = GameState.young_field()
	GameState.stage = GameData.YOUNG_STAGE

	var bg := CanvasLayer.new()
	bg.layer = -1
	add_child(bg)
	var starfield := preload("res://scripts/world/starfield.gd").new()
	starfield.camera = camera
	bg.add_child(starfield)

	_sky.draw.connect(_draw_sky)
	add_child(_sky)
	_mat.shader = EMBRYO_SHADER
	_mat.set_shader_parameter("style", GameData.embryo_style(type))
	_mat.set_shader_parameter("seed", _rng.randf())
	_mat.set_shader_parameter("tilt", _rng.randf_range(0.3, 0.6))
	_mat.set_shader_parameter("light_dir", Vector2(-1.0, -0.15))
	_mat.set_shader_parameter("atmo_col", params["atmo"])
	_planet.material = _mat
	_planet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_planet)
	var front := Node2D.new()   # вспышки ударов поверх планеты
	front.set_meta("front", true)
	front.draw.connect(_draw_flashes.bind(front))
	add_child(front)

	camera.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(camera)

	var ui := CanvasLayer.new()
	ui.name = "UI"
	ui.layer = 10
	add_child(ui)
	joystick = VirtualJoystick.new()
	ui.add_child(joystick)
	hud = YoungHud.new()
	hud.stage = self
	ui.add_child(hud)
	tree_screen = SkillTreeScreen.new()
	ui.add_child(tree_screen)
	pause_menu = PauseMenu.new()
	ui.add_child(pause_menu)
	hud.tree_requested.connect(func() -> void:
		joystick.reset()
		tree_screen.open())
	hud.menu_requested.connect(_open_pause)
	_update_temp()
	_update_view(0.0)
	hud.caption("Молодая планета", params["goal"], 5.0)


func _open_pause() -> void:
	if tree_screen.visible:
		return
	joystick.reset()
	pause_menu.open()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and tree_screen != null and not tree_screen.visible:
		if pause_menu.visible:
			pause_menu.close()
		else:
			_open_pause()


func au() -> float:
	return orbit / GameData.AU_UNITS


## Парник сейчас, K: для зоны жизни на карте.
func greenhouse() -> float:
	return GameData.YOUNG_GH * float(params["gh"]) * log(1.0 + atmo)


func _update_temp() -> void:
	temp = GameData.young_temp(orbit, atmo, water, float(params["gh"]))


## Чем кончится, если бомбардировка стихнет сейчас.
func fate() -> String:
	return GameData.young_final(type, GameState.composition_ending(), water, atmo, temp)


func left() -> float:
	return maxf(GameData.YOUNG_TIME - time, 0.0)


func _process(delta: float) -> void:
	if get_tree().paused:
		return
	_spin += delta * 0.05
	if _ending_t >= 0.0:
		_ending_t -= delta
		_step_bodies(delta, false)
		_update_view(delta)
		if _ending_t < 0.0:
			_show_ending()
		return
	time += delta
	var k := clampf(time / GameData.YOUNG_TIME, 0.0, 1.0)

	# Орбита: планеты без газа не мигрируют, но рассеяние на соседях сдвигает
	# их понемногу; в игре — стик.
	var input := auto_input if use_auto else joystick.output.x
	if not use_auto:
		input += Input.get_axis("ui_left", "ui_right")
	input = clampf(input, -1.0, 1.0)
	orbit = clampf(orbit + input * GameData.YOUNG_SPEED * float(params["speed"]) * delta,
		GameData.YOUNG_DISK.x, GameData.YOUNG_DISK.y)

	# Недра выдыхают атмосферу, к концу всё слабее.
	atmo += float(params["out"]) * lerpf(1.0, 0.15, k) * delta
	# Звёздный ветер сдувает небо, магнитное поле его держит.
	var wind := pow(1.0 / maxf(au(), 0.3), 2.0)
	atmo -= atmo * GameData.YOUNG_STRIP * (1.0 - field) * wind * delta
	_update_temp()
	# Вода: тёплый океан понемногу теряет водород, кипящий — быстро; пар
	# оставляет в небе кислород и углекислый газ.
	var boil := 0.006 * smoothstep(320.0, 373.0, temp) + 0.02 * smoothstep(373.0, 420.0, temp)
	var lost := water * boil * delta
	water -= lost
	atmo += lost * 0.5
	atmo = maxf(atmo, 0.0)

	_spawn(delta)
	_step_bodies(delta, true)
	_tell()
	_update_view(delta)
	GameState.add_currency(GameData.YOUNG_VALUE * 0.04 * delta * _value_k())

	if time >= GameData.YOUNG_TIME:
		hud.caption("Бомбардировка стихла", "что есть на планете сейчас, то и останется", 3.0)
		_end(3.0)
		return
	_save_t += delta
	if _save_t >= SAVE_EVERY:
		_save_t = 0.0
		save()


func _value_k() -> float:
	return Skills.stat("value") * Skills.stat("value_mul") * GameState.value_bonus()


## Кометы летят с холодных окраин: чем дальше орбита, тем их больше.
## Каменные тела — из внутреннего пояса.
func _spawn(delta: float) -> void:
	var a := au()
	_comet_acc += delta * (0.03 + 0.5 * smoothstep(1.4, 3.4, a))
	_rock_acc += delta * (0.12 + 0.25 * (1.0 - smoothstep(1.0, 3.0, a)))
	while _comet_acc >= 1.0:
		_comet_acc -= 1.0
		_launch(true)
	while _rock_acc >= 1.0:
		_rock_acc -= 1.0
		_launch(false)


func _launch(comet: bool) -> void:
	# Кометы приходят снаружи (справа), камни — с любой стороны.
	var ang := _rng.randf_range(-1.0, 1.0) if comet else _rng.randf_range(-PI, PI)
	var from := Vector2(cos(ang), sin(ang)) * SPAWN_R
	var to := Vector2(_rng.randf_range(-0.6, 0.6), _rng.randf_range(-0.6, 0.6)) * planet_r
	var v := (to - from).normalized() * _rng.randf_range(260.0, 380.0)
	_bodies.append({"p": from, "v": v, "comet": comet})


func _step_bodies(delta: float, live: bool) -> void:
	var keep := []
	for b in _bodies:
		var p: Vector2 = b.p
		p += b.v * delta
		b.p = p
		if p.length() < planet_r * 0.98:
			if live:
				_hit(b.comet, p)
			continue
		if p.length() < SPAWN_R * 1.3:
			keep.append(b)
	_bodies = keep
	var fl := []
	for f in _flashes:
		f.t += delta
		if f.t < 1.2:
			fl.append(f)
	_flashes = fl


func _hit(comet: bool, at: Vector2) -> void:
	_flashes.append({"p": at.normalized() * planet_r, "t": 0.0, "comet": comet})
	GameState.add_currency(GameData.YOUNG_VALUE * _value_k())
	if comet:
		water += GameData.YOUNG_COMET * (1.0 + Skills.stat("water") * 2.0)
		atmo += 0.015
	elif _rng.randf() < 0.4:
		GameState.add_chondrules(int(params["chondrules"]), at)


## Подсказки по ходу этапа.
func _tell() -> void:
	if time > 7.0 and not _said.has("move"):
		_said["move"] = true
		hud.caption("Орбита решает климат", "стик влево — к звезде, теплее; вправо — к холодным окраинам, оттуда летят кометы с водой", 4.5)
	if temp > 373.0 and water > 0.05 and not _said.has("boil"):
		_said["boil"] = true
		hud.caption("Океан кипит", "пар держит тепло, и парник может сорваться: уходи от звезды, если не хочешь стать Венерой", 4.0)
	if temp < 273.0 and water > 0.15 and time > 12.0 and not _said.has("ice"):
		_said["ice"] = true
		hud.caption("Вода замёрзла", "здесь слишком холодно для морей: подойди к звезде или дай атмосфере погреть", 4.0)
	if fate() == "planet_living" and not _said.has("life"):
		_said["life"] = true
		hud.caption("Зона жизни", "тепло, вода и небо: удержи их, пока не стихнет бомбардировка", 4.0)
	if atmo < 0.15 and field < 0.35 and au() < 1.3 and time > 30.0 and not _said.has("strip"):
		_said["strip"] = true
		hud.caption("Ветер звезды", "слабое магнитное поле не держит атмосферу: её сдувает в космос", 4.0)
	if left() < 30.0 and not _said.has("last"):
		_said["last"] = true
		hud.caption("Бомбардировка стихает", "полминуты: какой планета будет тогда, такой и останется", 3.0)


func _update_view(_delta: float) -> void:
	var vp := get_viewport_rect().size
	planet_r = vp.y * 0.27
	var q := planet_r * 2.0 / 0.72
	_planet.size = Vector2(q, q)
	_planet.position = -_planet.size * 0.5
	camera.position = Vector2(0.0, 0.0)
	var light := clampf(pow(1.0 / maxf(au(), 0.3), 0.5), 0.45, 1.5)
	_mat.set_shader_parameter("star_light", Color(1.0, 0.9, 0.75) * light)
	_mat.set_shader_parameter("spin", _spin)
	_mat.set_shader_parameter("magma", 0.8 * clampf(1.0 - time / 50.0, 0.0, 1.0))
	_mat.set_shader_parameter("atmo", clampf(log(1.0 + atmo) / log(21.0), 0.0, 1.0))
	var veil := smoothstep(8.0, 40.0, atmo)
	if type in ["titan", "carbon"]:
		veil = maxf(veil, 0.6 * smoothstep(1.5, 8.0, atmo))
	_mat.set_shader_parameter("veil", veil)
	var col: Color = params["atmo"]
	if temp > 373.0:
		col = col.lerp(Color(0.95, 0.95, 0.92), smoothstep(373.0, 430.0, temp) * minf(water + 0.3, 1.0))
	_mat.set_shader_parameter("atmo_col", col)
	var liquid := 1.0 - smoothstep(373.0, 400.0, temp)
	_mat.set_shader_parameter("ocean", sqrt(clampf(water / GameData.YOUNG_WATER.y, 0.0, 1.0)) * liquid)
	_mat.set_shader_parameter("clouds", smoothstep(0.1, 0.8, water) * smoothstep(0.15, 0.8, atmo) * smoothstep(255.0, 285.0, temp) * liquid)
	_mat.set_shader_parameter("frost", smoothstep(285.0, 220.0, temp))
	_sky.queue_redraw()
	for c in get_children():
		if c.has_meta("front"):
			c.queue_redraw()


## Звезда за левым краем, тела на подлёте.
func _draw_sky() -> void:
	var vp := get_viewport_rect().size
	var near := clampf(1.0 / maxf(au(), 0.3), 0.2, 2.5)
	var c := Vector2(-vp.x * 0.5 - 260.0, -40.0)
	for i in 40:
		var f := float(i) / 39.0
		_sky.draw_circle(c, lerpf(900.0 * near, 120.0, f), Color(1.0, 0.7 + 0.25 * f, 0.4 + 0.5 * f, (0.004 + 0.02 * f * f) * near))
	for b in _bodies:
		var p: Vector2 = b.p
		var v: Vector2 = b.v
		if b.comet:
			# Хвост кометы всегда от звезды.
			var tail := Vector2(1.0, 0.04) * 70.0
			for k in 6:
				var f := float(k) / 6.0
				_sky.draw_line(p + tail * f, p + tail * (f + 1.0 / 6.0), Color(0.7, 0.88, 1.0, 0.35 * (1.0 - f)), 3.5 - 2.8 * f, true)
			_sky.draw_circle(p, 3.2, Color(0.85, 0.94, 1.0))
		else:
			_sky.draw_line(p, p - v.normalized() * 22.0, Color(0.9, 0.7, 0.5, 0.25), 2.0, true)
			_sky.draw_circle(p, 3.0, Color(0.62, 0.52, 0.44))
			_sky.draw_circle(p + Vector2(-1.0, -1.0), 1.6, Color(0.85, 0.74, 0.62))


func _draw_flashes(ci: Node2D) -> void:
	for f in _flashes:
		var k: float = 1.0 - f.t / 1.2
		var col := Color(0.7, 0.9, 1.0) if f.comet else Color(1.0, 0.65, 0.35)
		ci.draw_circle(f.p, 6.0 + 26.0 * (1.0 - k), Color(col, 0.35 * k))
		ci.draw_circle(f.p, 4.0 * k, Color(1.0, 0.95, 0.85, k))


func save() -> void:
	var y := GameState.young
	y["r"] = orbit
	y["t"] = time
	y["w"] = water
	y["a"] = atmo
	y["temp"] = temp
	GameState.save_game()


func _end(delay: float) -> void:
	_ending_t = delay
	joystick.reset()
	save()


func _show_ending() -> void:
	var kind := fate()
	var pts := GameState.finish(kind)
	joystick.visible = false
	hud.visible = false
	get_tree().paused = true
	$UI.add_child(EndingScreen.new(kind, pts))
