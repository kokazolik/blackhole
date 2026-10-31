extends Node2D
## Этап «Газовый гигант»: своя сцена после лавины газа.
##
## Мир во вращающейся вместе с гигантом системе: звезда в начале координат,
## гигант на оси +x и меняет только орбиту. Газ течёт к нему из кормовой зоны,
## щель в диске растёт, и за газом приходится тянуться. Когда диск рассеется,
## масса, орбита и ядро решают концовку.

const GasDisk := preload("res://scripts/giant/gas_disk.gd")
const GiantBody := preload("res://scripts/giant/giant_body.gd")
const GiantHud := preload("res://scripts/giant/giant_hud.gd")
const GiantEvents := preload("res://scripts/giant/giant_events.gd")
const GasClumps := preload("res://scripts/giant/gas_clumps.gd")
const SAVE_EVERY := 3.0
const STAR_SCALE := GameData.GIANT_STAR_R / GameData.STAR_RADIUS  # звезда в разы шире гиганта
const STAR_GLOW := 6200.0   # радиус свечения вокруг звезды
const MOON_TIME := 75.0     # секунд на луну при обычном притоке газа
const MOON_FALL_GAIN := 0.6 # масс Земли, если луна упала в гиганта
const MOON_CHONDRULES := 6  # луна слиплась из пыли: в ней хондры

var camera := Camera2D.new()
var disk: GasDisk
var body: GiantBody
var hud: GiantHud
var events: GiantEvents
var clumps: GasClumps
var joystick: VirtualJoystick
var tree_screen: SkillTreeScreen
var pause_menu: PauseMenu
var earths := 10.0
var orbit := 7500.0
var ang := 0.0               # угол гиганта на орбите: «вперёд» по экрану — вверх
var vel := Vector2.ZERO     # x — от звезды, y — назад по орбите (экран вниз)
var gas := 0.0
var gas_total := 1.0
var moons := 0
var moon_prog := 0.0
var mdot := 0.0             # аккреция сейчас, M⊕/с
var auto_input := 0.0       # для бота: радиальный ввод вместо стика
var auto_y := 0.0           # для бота: ввод вдоль орбиты
var use_auto := false
var _flow := 0.0
var _feed0 := -1.0          # плотность в зоне в начале: по ней видно, что открылась щель
var _save_t := 0.0
var _time := 0.0
var _said := {}
var _ending_t := -1.0
var _inflate := 0.35
var value_boost := 0.0      # секунд звёздной пыли ×1,5 (событие парникового мира)


func _ready() -> void:
	process_priority = 100
	var g: Dictionary = GameState.giant
	earths = float(g.get("e", GameData.GIANT_EARTHS))
	orbit = maxf(float(g.get("r", 7500.0)), GameData.GIANT_ORBIT_MIN)
	ang = float(g.get("ang", 0.0))
	gas_total = GameData.GIANT_GAS_TIME * (1.0 + Skills.stat("giant_gas"))
	gas = float(g.get("gas", gas_total))
	moons = int(g.get("moons", 0))
	moon_prog = float(g.get("moon_prog", 0.0))
	GameState.stage = GameData.GIANT_STAGE

	var bg := CanvasLayer.new()
	bg.layer = -1
	add_child(bg)
	var starfield := preload("res://scripts/world/starfield.gd").new()
	starfield.camera = camera
	bg.add_child(starfield)
	disk = GasDisk.new()
	disk.camera = camera
	bg.add_child(disk)
	disk.setup(Array(g.get("sigma", [])))

	# Звезда здесь в честном масштабе: горячие юпитеры кружат примерно в десяти
	# её радиусах, а не у самой поверхности. Широкое свечение заменяет корону.
	var glow := Node2D.new()
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = add
	# Свечение одним квадом с радиальным градиентом: раньше было 60 кругов на весь
	# экран друг на друге, и это был самый тяжёлый слой этапа.
	var grad := Gradient.new()
	var core := GameData.STAR_RADIUS * STAR_SCALE * 1.1 / STAR_GLOW
	grad.set_offset(0, 0.0)
	grad.set_color(0, Color(1.0, 0.92, 0.8, 0.5))
	grad.set_offset(1, 1.0)
	grad.set_color(1, Color(1.0, 0.62, 0.3, 0.0))
	grad.add_point(core, Color(1.0, 0.9, 0.75, 0.42))
	grad.add_point(lerpf(core, 1.0, 0.25), Color(1.0, 0.8, 0.55, 0.12))
	grad.add_point(lerpf(core, 1.0, 0.6), Color(1.0, 0.7, 0.42, 0.035))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.scale = Vector2.ONE * STAR_GLOW * 2.0 / 256.0
	glow.add_child(spr)
	spr.material = add
	add_child(glow)
	var star := preload("res://scripts/world/star.gd").new()
	star.show_zones = false
	star.scale = Vector2.ONE * STAR_SCALE
	add_child(star)
	star.get_child(0).visible = false  # тёмное кольцо короны на светлом газе лишнее
	events = GiantEvents.new()
	events.stage = self
	add_child(events)
	clumps = GasClumps.new()
	clumps.stage = self
	add_child(clumps)
	body = GiantBody.new()
	body.sigma_at = func(x: float) -> float: return disk.at(orbit + x * body.hill)
	add_child(body)
	clumps.bind(body.gas)
	body.set_look(str(g.get("flavor", "giant_cold")))
	body.moons = moons
	# Только что после лавины: оболочка раздувается на глазах.
	if g.get("sigma", []).is_empty():
		_inflate = 0.35
	else:
		_inflate = 1.0

	# Камера поворачивается вместе с гигантом: звезда всегда слева, вперёд по орбите — вверх.
	camera.ignore_rotation = false
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 4.0
	camera.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(camera)
	_update_view(0.0)
	camera.position = Vector2.from_angle(ang) * orbit
	camera.rotation = ang
	camera.reset_smoothing()

	var ui := CanvasLayer.new()
	ui.name = "UI"
	ui.layer = 10
	add_child(ui)
	joystick = VirtualJoystick.new()
	ui.add_child(joystick)
	hud = GiantHud.new()
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
	# «Долгий диск» продлевает газ сразу, а не со следующего забега.
	GameState.skills_changed.connect(func() -> void:
		var total := GameData.GIANT_GAS_TIME * (1.0 + Skills.stat("giant_gas"))
		gas += total - gas_total
		gas_total = total)

	if _inflate < 1.0:
		hud.caption("Газовый гигант", "ядро в десять масс Земли втягивает газ диска лавиной: ты раздуваешься", 4.5)
	else:
		hud.caption("Газовый гигант", "газ диска ещё течёт к тебе", 2.5)


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


func hill() -> float:
	return 2.2 * GameData.giant_body_r(earths)


func _process(delta: float) -> void:
	if get_tree().paused:
		return
	_time += delta
	if _ending_t >= 0.0:
		_ending_t -= delta
		_update_view(delta)
		if _ending_t < 0.0:
			_show_ending()
		return
	_inflate = minf(_inflate + delta * 0.22, 1.0)
	gas -= delta
	var gk := clampf(gas / gas_total, 0.0, 1.0)
	var h := hill()
	var width := 1.6 * h * Skills.stat("giant_reach")
	var feed := disk.feed(orbit, width)
	if _feed0 < 0.0:
		_feed0 = maxf(feed, 0.05)
	var mexp := 2.0 / 3.0 + Skills.stat("giant_runaway") / 3.0
	mdot = GameData.GIANT_ACC * feed * gk * pow(earths / 10.0, mexp) * Skills.stat("giant_acc") * events.acc_mul()
	var gained := mdot * delta
	earths += gained
	# Широкая кормовая зона расталкивает газ медленнее: щель открывается позже.
	var torque := GameData.GIANT_TORQUE * earths / 100.0 / Skills.stat("giant_reach")
	disk.step(delta, orbit, width, h, gained * GameData.GIANT_EAT, torque)
	pay(gained)

	# Движение: стик в любую сторону. Влево-вправо — к звезде и от неё, вверх-вниз —
	# вперёд и назад по орбите, за сгустками газа и телами. Гигант тяжёлый:
	# разгоняется и тормозит плавно. Газ тянет внутрь (миграция II типа).
	var input := Vector2(auto_input, auto_y) if use_auto else joystick.output
	if not use_auto:
		input += Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
	input = input.limit_length(1.0)
	var speed := GameData.GIANT_SPEED * pow(earths / 10.0, -0.25) * Skills.stat("giant_speed")
	vel = vel.lerp(input * speed, minf(delta * 2.2, 1.0))
	var was := Vector2(orbit, ang)
	orbit += vel.x * delta
	ang = wrapf(ang + vel.y * delta / orbit, -PI, PI)
	var mig := GameData.GIANT_MIGRATE * disk.at(orbit) * gk * maxf(1.0 - Skills.stat("giant_anchor"), 0.0)
	orbit -= mig * delta
	orbit = clampf(orbit, GameData.GIANT_ORBIT_MIN, GameData.GIANT_DISK.y - 600.0)
	# Газ лежит в диске, а не едет с гигантом: сдвигаем частицы навстречу.
	body.gas.shift(Vector2(orbit - was.x, wrapf(ang - was.y, -PI, PI) * orbit))

	_flow = lerpf(_flow, clampf(mdot / (0.6 * pow(earths / 10.0, mexp) * Skills.stat("giant_acc")), 0.0, 1.0), minf(delta * 2.0, 1.0))
	clumps.step(delta)
	_moons_step(delta)
	value_boost = maxf(value_boost - delta, 0.0)
	events.step(delta)
	_update_view(delta)
	_tell(feed, gk)

	if earths >= GameData.BROWN_DWARF and not _said.has("bd"):
		_said["bd"] = true
		hud.caption("Дейтерий загорелся!", "тринадцать масс Юпитера: в недрах пошла термоядерная реакция", 3.0)
		_end(2.5)
		return
	if gas <= 0.0:
		hud.caption("Газ рассеялся", "звезда сдула остатки диска: ты больше не растёшь", 3.0)
		_end(3.0)
		return
	_save_t += delta
	if _save_t >= SAVE_EVERY:
		_save_t = 0.0
		save()


## Сколько масс Земли за секунду дал бы газ плотности s сейчас: мерка для сгустков.
func clump_gain(s: float) -> float:
	var gk := clampf(gas / gas_total, 0.0, 1.0)
	var mexp := 2.0 / 3.0 + Skills.stat("giant_runaway") / 3.0
	return GameData.GIANT_ACC * clampf(s, 0.1, 1.5) * maxf(gk, 0.3) * pow(earths / 10.0, mexp) * Skills.stat("giant_acc")


func pay(gained: float) -> void:
	if gained <= 0.0:
		return
	var value := (1.5 if value_boost > 0.0 else 1.0) * gained * GameData.GIANT_VALUE * Skills.stat("value") * Skills.stat("value_mul") \
		* GameState.value_bonus() * (1.0 + 0.08 * moons)
	GameState.add_currency(value)


## Луны собираются из пыли в своём диске; поле решает, сколько их удержится.
func _moons_step(delta: float) -> void:
	moon_prog += delta * (0.35 + 0.65 * _flow) * Skills.stat("giant_moons") / MOON_TIME
	if moon_prog < 1.0:
		return
	moon_prog -= 1.0
	if moons < GameState.giant_moon_cap():
		hud.toast("Родилась луна %s! Хондры +%d" % [GiantBody.moon_name(moons), MOON_CHONDRULES], Color(0.85, 0.92, 1.0))
		GameState.add_chondrules(MOON_CHONDRULES, body.position)
		moons += 1
		body.moons = moons
		body.birth(moons - 1)
		if moons == 1 and not _said.has("moon"):
			_said["moon"] = true
			hud.caption("Своя луна", "пыль в твоём диске слиплась в спутник: каждая луна +8% к звёздной пыли", 3.0)
	else:
		earths += MOON_FALL_GAIN
		body.fall()
		hud.toast("Новая луна упала в тебя: поле слишком слабое, чтобы удержать больше", Color(1.0, 0.7, 0.55))
		if not _said.has("fall"):
			_said["fall"] = true
			hud.caption("Магнитное поле", "поле выметает полость у гиганта и спасает луны от падения: его даёт железное ядро и «Динамо»", 4.0)


## Подсказки и вехи по ходу этапа.
func _tell(feed: float, gk: float) -> void:
	if _time > 7.0 and not _said.has("move"):
		_said["move"] = true
		hud.caption("Ищи газ", "стик в любую сторону: влево к звезде, вправо от неё, вверх и вниз вдоль орбиты. Догоняй сгустки газа и всё, что кружит в диске", 4.0)
	if feed < _feed0 * 0.45 and not _said.has("gap"):
		_said["gap"] = true
		hud.caption("Щель в диске", "ты выпил газ вдоль своей орбиты, а приливы сгребли остаток к краям: тянись к ним", 4.0)
	if orbit < GameData.HOT_ORBIT + 500.0 and not _said.has("hot"):
		_said["hot"] = true
		hud.caption("Слишком близко к звезде", "газ тянет тебя внутрь: если газ уйдёт, пока ты здесь, станешь горячим юпитером", 4.0)
	if earths >= GameData.JUPITER_EARTHS and not _said.has("jup"):
		_said["jup"] = true
		hud.toast("Масса Юпитера!", UiTheme.GOLD)
	if earths >= GameData.SUPER_JUPITER and not _said.has("sj"):
		_said["sj"] = true
		hud.caption("Супер-Юпитер", "тысяча масс Земли: до коричневого карлика нужно вчетверо больше", 3.0)
	if gas < 60.0 and not _said.has("last"):
		_said["last"] = true
		hud.caption("Газ рассеивается", "звезда сдувает диск: осталась минута", 3.0)


func _update_view(delta: float) -> void:
	var h := hill()
	var vp := get_viewport_rect().size
	var z := vp.x * 0.5 / (3.2 * h + 600.0)
	camera.zoom = camera.zoom.lerp(Vector2(z, z), minf(delta * 2.0, 1.0)) if delta > 0.0 else Vector2(z, z)
	camera.position = Vector2.from_angle(ang) * orbit
	camera.rotation = ang
	body.position = Vector2.from_angle(ang) * orbit
	body.rotation = ang
	body.body_r = GameData.giant_body_r(earths)
	body.hill = h
	body.reach = Skills.stat("giant_reach")
	body.inflate = 0.35 + 0.65 * smoothstep(0.0, 1.0, (_inflate - 0.35) / 0.65) if _inflate < 1.0 else 1.0
	body.flow = _flow
	body.field = GameState.giant_field()
	body.zoom = camera.zoom.x
	body.set_look(str(GameState.giant.get("flavor", "giant_cold")), 1.0 - smoothstep(GameData.HOT_ORBIT - 300.0, GameData.HOT_ORBIT + 900.0, orbit))
	var gk := clampf(gas / gas_total, 0.0, 1.0)
	disk.set_view(orbit, h, gk, 0.3 + 0.5 * clampf(earths / 300.0, 0.0, 1.0), ang)


func save() -> void:
	var g := GameState.giant
	g["e"] = earths
	g["r"] = orbit
	g["ang"] = ang
	g["gas"] = gas
	g["moons"] = moons
	g["moon_prog"] = moon_prog
	var arr := []
	for v in disk.sigma:
		arr.append(snappedf(v, 0.0001))
	g["sigma"] = arr
	GameState.mass = GameData.mass_for_earths(earths)
	GameState.save_game()


func _end(delay: float) -> void:
	_ending_t = delay
	joystick.reset()
	save()


func _show_ending() -> void:
	var kind := GameData.giant_final(str(GameState.giant.get("flavor", "giant_cold")), earths, orbit)
	GameState.has_moon = moons > 0
	# Коричневый карлик и супер-Юпитер могут уйти в облако и стать звездой.
	if kind in ["brown_dwarf", "super_jupiter"]:
		joystick.visible = false
		hud.visible = false
		get_tree().paused = true
		var choice := preload("res://scripts/cloud/cloud_choice.gd").new()
		choice.kind = kind
		choice.chosen.connect(func(route: String) -> void:
			if route == "cloud":
				get_tree().paused = false
				GameState.start_cloud(kind)
				Fader.go(Fader.CLOUD)
			else:
				_finish(kind))
		$UI.add_child(choice)
		if use_auto and GameState.giant.has("bot_route"):
			choice.chosen.emit(str(GameState.giant.get("bot_route", "stay")))
			choice.queue_free()
		return
	_finish(kind)


func _finish(kind: String) -> void:
	var pts := GameState.finish(kind)
	joystick.visible = false
	hud.visible = false
	get_tree().paused = true
	$UI.add_child(EndingScreen.new(kind, pts))
