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
var clumps: GasClumps
var world: GiantWorld
var joystick: VirtualJoystick
var tree_screen: SkillTreeScreen
var pause_menu: PauseMenu
var earths := 10.0
var orbit := 7500.0
var ang := 0.0               # угол гиганта на орбите: «вперёд» по экрану — вверх
var vel := Vector2.ZERO     # x — от звезды, y — назад по орбите (экран вниз)
var kick := Vector2.ZERO    # толчки извне: праща, притяжение тяжёлых тел; гаснут сами
var _vortex_t := 0.0
var gas := 0.0
var gas_total := 1.0
var moons := 0
var moon_prog := 0.0
var ring_m := 0.0                 # кольцо из разорванных тел, масс Земли
var ring_col := Color(0.8, 0.8, 0.82)
var ring_col2 := Color(0.6, 0.55, 0.5)
const RING_DECAY := 0.006         # доля кольца в секунду: оседает в гиганта и копится в луны у края
const RING_MOON := 6.0            # прогресс луны с массы Земли, ушедшей из кольца
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
var envelope := 1.0          # сколько газа осело на ядро (0 — голое ядро, 1 — сплошные облака)
var _core_type := "silicate"
var _env_step := 0           # какие подписи про оболочку уже были
var _focus_t := 0.0          # камера подъезжает к событию (разрыв, удар): секунд осталось
var _focus_dur := 1.0
var _focus_loc := Vector2.ZERO   # куда смотреть, в системе гиганта
var _focus_k := 0.0
var _focus_w := 0.0
var value_boost := 0.0      # секунд звёздной пыли ×1,5 (событие парникового мира)
# Эпохи этапа: мир наполняется постепенно. 0 — рыхлое облако, вокруг только газ;
# 1 — кормовая зона: обломки и планетезимали; 2 — соседи: зародыши, троянцы,
# лёгкий соперник; 3 — хозяин диска: суперземли, мини-нептуны, тяжёлые
# соперники, пролёт карлика. Эпоха растёт по массе или по времени газа.
var era := -1
var era_min := 0             # для бота: сразу с этой эпохи


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
	ring_m = float(g.get("ring_m", 0.0))
	var rc: Array = g.get("ring_col", [])
	if rc.size() >= 6:
		ring_col = Color(rc[0], rc[1], rc[2])
		ring_col2 = Color(rc[3], rc[4], rc[5])
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
	clumps = GasClumps.new()
	clumps.stage = self
	add_child(clumps)
	world = GiantWorld.new()
	world.stage = self
	add_child(world)
	body = GiantBody.new()
	body.sigma_at = func(x: float) -> float: return disk.at(orbit + x * body.hill)
	add_child(body)
	clumps.bind(body.gas)
	world.bind(body.gas)
	body.set_look(str(g.get("flavor", "giant_cold")))
	body.moons = moons
	# Только что после лавины: газ оседает на твёрдое ядро на глазах.
	envelope = float(g.get("env", 0.0 if g.get("sigma", []).is_empty() else 1.0))
	_core_type = GameState.body_type()
	if _core_type in ["neutral", "unformed"]:
		_core_type = GameData.lead_material(GameState.materials)
	body.set_core(_core_type, str(g.get("flavor", "giant_cold")))
	body.envelope = envelope
	_env_step = 3 if envelope >= 1.0 else (2 if envelope > 0.6 else (1 if envelope > 0.25 else 0))

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

	world.setup()
	_era_check(true)
	if envelope < 0.05:
		hud.caption("Газовый гигант", _core_line(), 5.0)
		# Камера наезжает на ядро: пусть игрок разглядит, из чего он.
		focus(Vector2.ZERO, 9.0, 1.2)
	else:
		hud.caption("Газовый гигант", "газ диска ещё течёт к тебе", 2.5)


## Подпись на входе: какое ядро у тебя и чем оно дымит в первый газ.
func _core_line() -> String:
	match _core_type:
		"metal":
			return "железное ядро тлеет в глубине рыхлого облака газа: оно тянется до самой сферы Хилла"
		"ice":
			return "ледяное ядро парит в глубине рыхлого облака газа: оно прозрачнее, пыли мало"
		"carbon":
			return "углеродное ядро тлеет в глубине облака газа, густого от сажи"
		"titan":
			return "лёд и углерод в глубине оранжевой мглы, как у Титана: газ облепляет тебя"
		"venus":
			return "раскалённое ядро в глубине желтоватой сернистой мглы: газ облепляет тебя"
		"chondrite":
			return "пёстрое ядро в глубине облака газа: оно тянется до самой сферы Хилла"
	return "каменное ядро в десять масс Земли тлеет в глубине рыхлого облака газа до самой сферы Хилла"


## Какая эпоха положена сейчас. Первая — когда осела оболочка (или прошла
## минута газа: горячему у звезды быстрее, ледяному на окраине медленнее),
## следующие открывает дерево навыков.
func _era_target() -> int:
	var t := gas_total - gas
	var tk: float = {"giant_hot": 0.85, "giant_ice": 1.15, "giant_dense": 0.95}.get(str(GameState.giant.get("flavor", "")), 1.0)
	var e := era_min
	if envelope >= 0.6 or t >= 60.0 * tk:
		e = maxi(e, 1)
	# Дальше — через дерево: приливом рвать крупнее или хватать дальше —
	# и к тебе идут зародыши и соседи; праща или тяжёлая поступь — и в диск
	# заходят суперземли, мини-нептуны и тяжёлые соперники.
	if e >= 1 and (Skills.level("g_tidal") > 0 or Skills.level("g_grab") > 0):
		e = maxi(e, 2)
	if e >= 2 and (Skills.level("g_sling") > 0 or Skills.level("g_guard") > 0):
		e = maxi(e, 3)
	return e


func _era_check(first: bool) -> void:
	var want := _era_target()
	if first:
		# Загрузка посреди этапа: мир сразу такой, каким был.
		era = want
		world.fill_to(era)
		return
	if want <= era:
		return
	era += 1
	world.on_era(era)
	var line := _era_line(era)
	match era:
		1:
			hud.caption("Кормовая зона", line, 5.0)
		2:
			hud.caption("Соседи", line, 5.0)
		3:
			hud.caption("Хозяин диска", line, 5.0)


## Что пришло с новой эпохой: у каждого ядра своё.
func _era_line(n: int) -> String:
	var f := str(GameState.giant.get("flavor", "giant_cold"))
	match n:
		1:
			var add: String = {"giant_ice": "с окраин падают ледяные кометы",
				"giant_dense": "среди обломков железные осколки: прилив их не рвёт, они падают целыми",
				"giant_dark": "тела тёмные от углерода, пыли с них больше",
				"giant_hot": "у звезды обломки раскалены: лава и железо"}.get(f, "камень и лёд вперемешку")
			return "оболочка осела, и тяготение дотянулось дальше: в зону входят обломки и планетезимали. Мелкие рви приливом; " + add
		2:
			var add: String = {"giant_ice": "за снеговой линией бродят ледяные карлики",
				"giant_dense": "железные ядра разбитых зародышей тяжелы для прилива",
				"giant_dark": "двойных тел больше: прилив разводит пары",
				"giant_hot": "у звезды тесно, соседи ближе"}.get(f, "соседний гигант пока легче тебя")
			return "к краям щели сползаются зародыши, в точках Лагранжа впереди и позади копятся троянцы, по чужой орбите идёт соперник; " + add
		3:
			var add: String = {"giant_ice": "мини-нептуны с кольцами: сперва сорвёшь оболочку",
				"giant_dense": "крупное тело можно таранить с разгона",
				"giant_dark": "тяжёлый соперник уже рядом",
				"giant_hot": "у звезды кружат раскалённые суперземли",
				"giant_cold": "в холоде вырос третий гигант"}.get(f, "")
			return "в диск заходят суперземли и мини-нептуны, тяжёлые соперники тянут тебя, сквозь диск может пройти карлик; " + add
	return ""


## Газ оседает на ядро: быстрее, когда течёт густо и когда ты тяжелее.
## Плотное железное ядро держит газ крепче, у льда и углерода оболочка
## в холоде садится медленнее.
func _grow_envelope(delta: float) -> void:
	if envelope >= 1.0:
		return
	var k := 1.0
	match _core_type:
		"metal":
			k = 1.25
		"ice", "titan":
			k = 0.9
		"carbon":
			k = 0.95
	envelope = minf(envelope + delta * (0.5 + 1.0 * _flow) * k / 70.0, 1.0)
	envelope = maxf(envelope, clampf((earths - 12.0) / 150.0, 0.0, 1.0))
	if _env_step < 1 and envelope > 0.25:
		_env_step = 1
		hud.caption("Оболочка падает", "газа стало слишком много, чтобы держаться: облако валится на ядро и раскаляется от сжатия", 4.0)
	elif _env_step < 2 and envelope > 0.6:
		_env_step = 2
		hud.caption("Остывание", "раскалённый шар тускнеет, в нём выпадают первые облака", 3.5)
	elif _env_step < 3 and envelope >= 1.0:
		_env_step = 3
		hud.caption("Пояса", "вращение растянуло облака в пояса: теперь ты газовый гигант", 3.5)


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
	_grow_envelope(delta)
	_era_check(false)
	gas -= delta
	var gk := clampf(gas / gas_total, 0.0, 1.0)
	var h := hill()
	var width := 1.6 * h * Skills.stat("giant_reach")
	var feed := disk.feed(orbit, width)
	if _feed0 < 0.0:
		_feed0 = maxf(feed, 0.05)
	var mexp := 2.0 / 3.0 + Skills.stat("giant_runaway") / 3.0
	mdot = GameData.GIANT_ACC * feed * gk * pow(earths / 10.0, mexp) * Skills.stat("giant_acc") * world.acc_mul()
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
	var speed := GameData.GIANT_SPEED * pow(earths / 10.0, -0.1) * Skills.stat("giant_speed")
	vel = vel.lerp(input * speed, minf(delta * 3.0, 1.0))
	kick *= exp(-1.2 * delta)
	var was := Vector2(orbit, ang)
	var move := vel + kick
	orbit += move.x * delta
	ang = wrapf(ang + move.y * delta / orbit, -PI, PI)
	var mig := GameData.GIANT_MIGRATE * disk.at(orbit) * gk * maxf(1.0 - Skills.stat("giant_anchor"), 0.0)
	orbit -= mig * delta
	orbit = clampf(orbit, GameData.GIANT_ORBIT_MIN, GameData.GIANT_DISK.y - 600.0)
	# Газ лежит в диске, а не едет с гигантом: сдвигаем частицы навстречу.
	var moved := Vector2(orbit - was.x, wrapf(ang - was.y, -PI, PI) * orbit)
	body.gas.shift(moved)
	world.shift(moved)

	_flow = lerpf(_flow, clampf(mdot / (0.6 * pow(earths / 10.0, mexp) * Skills.stat("giant_acc")), 0.0, 1.0), minf(delta * 2.0, 1.0))
	clumps.step(delta)
	world.step(delta)
	_vortices(delta, h)
	_moons_step(delta)
	value_boost = maxf(value_boost - delta, 0.0)
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


## Подвести камеру к событию: loc — в системе гиганта, k — насколько ближе.
func focus(loc: Vector2, dur: float, k: float) -> void:
	if _focus_t > 0.5 and _focus_k >= k:
		return
	_focus_loc = loc
	_focus_dur = dur
	_focus_t = dur
	_focus_k = k


func pay(gained: float) -> void:
	if gained <= 0.0:
		return
	var value := (1.5 if value_boost > 0.0 else 1.0) * gained * GameData.GIANT_VALUE * Skills.stat("value") * Skills.stat("value_mul") \
		* GameState.value_bonus() * (1.0 + 0.08 * moons)
	GameState.add_currency(value)


## Луны собираются из пыли в своём диске; поле решает, сколько их удержится.
func _moons_step(delta: float) -> void:
	moon_prog += delta * (0.35 + 0.65 * _flow) * Skills.stat("giant_moons") / MOON_TIME
	# Кольцо медленно тает: внутренний край оседает в облака, у внешнего края
	# (за пределом Роша) обломки слипаются в луны. У горячего гиганта звезда
	# выпаривает кольцо втрое быстрее.
	if ring_m > 0.0:
		var hot := 3.0 if str(GameState.giant.get("flavor", "")) == "giant_hot" else 1.0
		var lost := ring_m * RING_DECAY * hot * delta
		ring_m = maxf(ring_m - lost, 0.0)
		if ring_m < 0.002:
			ring_m = 0.0
		moon_prog += lost * RING_MOON * Skills.stat("giant_moons") / hot
	body.ring_m = ring_m
	body.ring_col = ring_col
	body.ring_col2 = ring_col2
	body.ring_bands = 1.0 if GameState.body_type() == "neutral" else 0.0
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


## Вихри Россби на краях щели: газ, сгребённый приливом, закручивается.
func _vortices(delta: float, h: float) -> void:
	if not _said.has("gap"):
		return
	_vortex_t -= delta
	if _vortex_t > 0.0:
		return
	_vortex_t = randf_range(45.0, 70.0)
	var side := 1.0 if randf() < 0.5 else -1.0
	var r := orbit + side * 2.6 * h
	if r < GameData.GIANT_ORBIT_MIN or r > GameData.GIANT_DISK.y - 800.0:
		r = orbit - side * 2.6 * h
	world.spawn_vortex(r, str(GameState.giant.get("flavor", "")) == "giant_dark")


## Подсказки и вехи по ходу этапа.
func _tell(feed: float, gk: float) -> void:
	if _time > 7.0 and not _said.has("move"):
		_said["move"] = true
		hud.caption("Ищи газ", "стик в любую сторону: подъезжай к сгусткам газа, их всасывает само. Чем больше выпьешь, тем дальше дотянешься", 4.5)
	if era >= 2 and not _said.has("roles"):
		_said["roles"] = true
		hud.caption("Кого есть", "мелкие тела рви приливом, средние бросай пращой, а от тех, что тяжелее тебя (красная метка), держись подальше", 4.5)
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
	# Крупный разрыв или удар: камера на пару секунд подъезжает ближе.
	_focus_t = maxf(_focus_t - delta, 0.0)
	var want := 0.0
	if _focus_t > 0.0:
		var el := _focus_dur - _focus_t
		want = smoothstep(0.0, 0.6, el) * smoothstep(0.0, 1.2, _focus_t)
	_focus_w = lerpf(_focus_w, want, minf(delta * 3.0, 1.0))
	z *= 1.0 + _focus_k * _focus_w
	camera.zoom = camera.zoom.lerp(Vector2(z, z), minf(delta * 2.0, 1.0)) if delta > 0.0 else Vector2(z, z)
	camera.position = Vector2.from_angle(ang) * orbit + _focus_loc.rotated(ang) * _focus_w
	camera.rotation = ang
	body.position = Vector2.from_angle(ang) * orbit
	body.rotation = ang
	body.body_r = GameData.giant_body_r(earths)
	body.hill = h
	body.reach = Skills.stat("giant_reach")
	body.envelope = envelope
	# Молодой гигант раздут жаром: после сжатия он почти вдвое шире и
	# усаживается, пока остывает.
	body.inflate = lerpf(1.7, 1.0, smoothstep(0.3, 0.95, envelope)) if envelope < 1.0 else 1.0
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
	g["ring_m"] = ring_m
	g["ring_col"] = [ring_col.r, ring_col.g, ring_col.b, ring_col2.r, ring_col2.g, ring_col2.b]
	g["env"] = envelope
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
