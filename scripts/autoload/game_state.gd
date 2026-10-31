extends Node
## Состояние забега: валюта, масса, материалы, уровни навыков. Сохраняется в user://.

signal currency_changed(value: float)
signal chondrules_changed(value: int)
signal chondrule_found(position: Vector2, amount: int)
signal mass_changed(value: float)
signal skills_changed
signal absorbed(position: Vector2, material: String, gained: float)
signal stage_reached(index: int)  # впервые достигнута новая стадия (Галька, ...)
signal chipped(position: Vector2, lost: float)  # удар: от тела откололись осколки
signal melted  # планетезималь расплавилась от алюминия-26: железо ушло в ядро
signal moon_formed(position: Vector2)  # косой гигантский удар: из обломков собралась луна
signal gas_gone  # газ диска рассеялся: гонка зародыша окончена
signal giant_hit(rel: float)  # гигантский удар зародыша: поверхность плавится в магматический океан

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1
const AUTOSAVE_SECONDS := 10.0
const HEAL_RATE := 0.12  # какая доля накопленного залечивания прирастает за секунду

var currency := 0.0
var chondrules := 0  # вторая валюта: застывшие капли расплава, за них берут способности
var mass := 1.0
var materials := {}
var skill_levels := {}
var player_position := Vector2(GameData.START_DISTANCE, 0.0)
var burned_up := false  # пылинка испарилась у звезды: забег окончен, сохранять нечего
var burned_embryo := false  # сгорел зародыш (упал в звезду), а не пылинка; для экрана гибели
var stage := 0  # высшая достигнутая стадия: потеря массы осколками её не отнимает
# Не сбрасываются вместе с забегом: пролог и обучение достаточно пройти один раз.
var prologue_seen := false
var tutorial_done := false
var pebble_intro_done := false  # рассказ Звездочёта о жизни гальки уже был
var boulder_intro_done := false
var fps_120 := false  # настройка, а не прогресс: «Начать заново» её не сбрасывает
var heal_pool := 0.0  # отколотая масса, которая ещё прирастёт обратно (не сохраняется)
var tips_seen: Array = []  # какие явления Звездочёт уже показал по ходу игры
var tree_view: Array = []  # где игрок оставил камеру книги: [x, y, масштаб] точки в центре
var tree_seen = []  # узлы, что игрок уже видел в книге; null — старое сохранение
# Этап «Планетезималь»:
var planet_time := 0.0   # секунд на этапе: по ним остывает алюминий-26
var is_melted := false   # недра расплавились, железо ушло в ядро
var core_share := 0.0    # доля металла, ушедшая в ядро при плавлении
var melt_type := ""      # тип тела в момент плавления: дальше состав не меняется
var zone_eaten := {}     # кольцо диска (GameData.zone_bin) → сколько вещества из него съедено
var embryo_path := ""    # путь после планетезимали (GameData.EMBRYO_PATHS), записан навсегда
var embryo_choice := ""  # выбор игрока в начале зародыша: "giant" — гонка с газом, "planet" — до массы Земли
# Этап «Зародыш планеты»:
var gas_left := -1.0     # секунд до рассеяния газа диска; <0 — гонка ещё не началась
var magma_hits := 0      # гигантских ударов: хондрит плавится в магматический океан
var has_moon := false
var ending := ""         # чем кончился забег (GameData.ENDINGS), "" — ещё идёт
# Не сбрасываются вместе с забегом: наследие прошлых концовок.
var legacy := 0
var endings_seen: Array = []
## Этап газового гиганта: flavor (гигант по ядру), e (массы Земли), r (орбита),
## gas (сколько секунд газа осталось), sigma (плотность газа по радиусу),
## moons, moon_prog. Пусто — этап не начался.
var giant := {}
## Этап молодой планеты: r (орбита), t (секунд прошло), w (вода, океанов Земли),
## a (атмосфера, бар). Пусто — этапа нет.
var young := {}
# Этап «Облако»: масса в массах Юпитера, позиция, время, зажигание, сетка газа.
var cloud := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_reset_values()
	load_game()
	apply_fps()
	var timer := Timer.new()
	timer.wait_time = AUTOSAVE_SECONDS
	timer.autostart = true
	timer.timeout.connect(save_game)
	add_child(timer)


func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		save_game()


## grains > 1 — облачко из нескольких пылинок.
func absorb(level: int, material: String, at: Vector2, grains := 1) -> void:
	var data := GameData.level_data(level)
	# Этап пылинки ужат: каждая пылинка весит и стоит больше, чем пыль вокруг гальки.
	var mk := GameData.DUST_STAGE_MASS if stage == 0 else 1.0
	var vk := GameData.DUST_STAGE_VALUE if stage == 0 else 1.0
	absorb_mass(data.mass * grains * mk, data.value * grains * vk, material, at)


## Присоединить вещество: масса растит тело, ценность даёт звёздную пыль.
func absorb_mass(base_mass: float, base_value: float, material: String, at: Vector2) -> void:
	var gained_mass: float = base_mass * body_bonus("mass") * route_growth()
	mass += gained_mass
	if is_melted:
		_add_frozen(gained_mass)
	else:
		materials[material] = materials.get(material, 0.0) + gained_mass
	if is_planet():
		eat_zone(player_position.length(), gained_mass)
	var gained: float = base_value * Skills.stat("value") * Skills.stat("value_mul") * (1.0 if is_boulder() else Skills.stat("pebble_value_mul")) * body_bonus("value") * value_bonus()
	add_currency(gained)
	mass_changed.emit(mass)
	absorbed.emit(at, material, gained)
	_check_stage()


## Присоединить тело смешанного состава (сосед-планетезималь): масса делится
## по долям mix, а не уходит целиком в один материал.
func absorb_mix(base_mass: float, base_value: float, mix: Dictionary, at: Vector2) -> void:
	var total := 0.0
	var top := ""
	for key in mix:
		total += float(mix[key])
		if top == "" or float(mix[key]) > float(mix[top]):
			top = key
	if total <= 0.0:
		return
	var gained_mass: float = base_mass * body_bonus("mass") * route_growth()
	mass += gained_mass
	if is_melted:
		_add_frozen(gained_mass)
	else:
		for key in mix:
			materials[key] = materials.get(key, 0.0) + gained_mass * float(mix[key]) / total
	if is_planet():
		eat_zone(player_position.length(), gained_mass)
	var gained: float = base_value * Skills.stat("value") * Skills.stat("value_mul") * (1.0 if is_boulder() else Skills.stat("pebble_value_mul")) * body_bonus("value") * value_bonus()
	add_currency(gained)
	mass_changed.emit(mass)
	absorbed.emit(at, top, gained)
	_check_stage()


## После плавления состав застыл: новое вещество растворяется в мантии и коре
## в тех же долях, тип тела больше не меняется.
func _add_frozen(gained_mass: float) -> void:
	var shares := GameData.composition(materials)
	for key in shares:
		materials[key] = materials.get(key, 0.0) + gained_mass * float(shares[key])


## Наследие прошлых концовок и луна: множитель звёздной пыли.
func value_bonus() -> float:
	return (1.0 + GameData.LEGACY_BONUS * legacy) * (1.0 + (GameData.MOON_BONUS + Skills.stat("moon_value") if has_moon else 0.0))


func is_young() -> bool:
	return stage >= GameData.YOUNG_STAGE and not young.is_empty() and giant.is_empty()


## Масса Земли набрана на пути планеты: начинается поздняя бомбардировка.
## Воду и атмосферу на старте даёт состав: лёд — вода, углерод — дымка.
func start_young(r: float) -> void:
	stage = GameData.YOUNG_STAGE
	var sh := GameData.composition(materials)
	var water := 4.0 * float(sh.get("ice", 0.0)) + 0.4 * float(sh.get("carbon", 0.0)) + Skills.stat("water")
	young = {"r": r, "t": 0.0, "w": water, "a": 0.2 + 1.5 * float(sh.get("carbon", 0.0))}
	save_game()


## Магнитное поле молодой планеты, 0..1: железное ядро и сам состав.
func young_field() -> float:
	var core := core_share + Skills.stat("core_boost") if is_melted else 0.0
	return clampf(0.1 + core * 1.8 + float(GameData.young_params(fate_type())["field"]), 0.0, 1.0)


func is_giant() -> bool:
	return stage >= GameData.GIANT_STAGE and not giant.is_empty() and cloud.is_empty()


func is_cloud() -> bool:
	return stage >= GameData.CLOUD_STAGE and not cloud.is_empty()


## Коричневый карлик или супер-Юпитер выброшен из системы и падает в облако.
## from — «brown_dwarf» или «super_jupiter»: супер-Юпитеру путь длиннее.
func start_cloud(from: String) -> void:
	var e := float(giant.get("e", GameData.BROWN_DWARF))
	stage = GameData.CLOUD_STAGE
	cloud = {"mj": e / GameData.JUPITER_EARTHS, "from": from, "t": 0.0, "lit": false, "push": "",
		"x": -1.0, "y": -1.0, "grid": [], "story": false}
	save_game()


## Лавина газа: забег продолжается этапом газового гиганта.
func start_giant(flavor: String, r: float) -> void:
	stage = GameData.GIANT_STAGE
	giant = {"flavor": flavor, "e": maxf(earth_masses(), GameData.GIANT_EARTHS), "r": maxf(r, GameData.GIANT_ORBIT_MIN),
		"gas": GameData.GIANT_GAS_TIME * (1.0 + Skills.stat("giant_gas")), "sigma": [], "moons": 0, "moon_prog": 0.0}
	save_game()


## Магнитное поле гиганта, 0..1: его раскручивает железное ядро.
func giant_field() -> float:
	var core := core_share if is_melted else 0.0
	return clampf(0.15 + core * 1.6 + Skills.stat("giant_field"), 0.0, 1.0)


## Сколько лун удержит магнитное поле: оно расчищает полость у планеты,
## и луны не падают в неё вместе с газом.
func giant_moon_cap() -> int:
	return 1 + int(giant_field() * 4.0)


func is_embryo() -> bool:
	return stage >= GameData.EMBRYO_STAGE


## Доля газа диска, что ещё осталась (1 — в начале этапа зародыша).
func gas_frac() -> float:
	if gas_left < 0.0:
		return 1.0
	return clampf(gas_left / GameData.GAS_TIME, 0.0, 1.0)


func earth_masses() -> float:
	return GameData.earth_masses(mass)


## Гигантский удар зародыша: rel — масса соседа в долях твоей, slant — доля
## касательной скорости. Удары греют тело до магматического океана: хондрит
## плавится здесь, с тем составом, что набрал. Косой удар выбрасывает диск
## обломков, из него собирается луна.
func giant_impact(rel: float, slant: float, at: Vector2) -> void:
	if not is_embryo() or rel < GameData.IMPACT_REL:
		return
	magma_hits += 1
	giant_hit.emit(rel)
	if not is_melted and magma_hits >= GameData.MAGMA_IMPACTS:
		_melt()
	if not has_moon and slant >= moon_slant():
		has_moon = true
		moon_formed.emit(at)
	save_game()


func _melt() -> void:
	is_melted = true
	core_share = float(GameData.composition(materials).get("metal", 0.0))
	melt_type = GameData.planet_type(body_type())
	save_game()
	melted.emit()


## Тип тела для судьбы: застывший при плавлении, иначе нынешний.
func fate_type() -> String:
	return melt_type if is_melted and melt_type != "" else GameData.planet_type(body_type())


## Какой каменной планетой кончится забег: решает застывший (или нынешний) состав.
func composition_ending() -> String:
	var core := core_share + Skills.stat("core_boost") if is_melted else 0.0
	return GameData.planet_ending(fate_type(), GameData.composition(materials), core, Skills.stat("water"))


## Насколько косым должен быть гигантский удар, чтобы собралась луна.
func moon_slant() -> float:
	return GameData.MOON_SLANT - Skills.stat("moon_slant")


## Путь каменной планеты: цель — масса Земли, гиганта не будет.
func planet_route() -> bool:
	return embryo_choice == "planet"


## Путь планеты растёт медленнее: без лавины газа зародыш набирает массу
## столкновениями, и до массы Земли идут почти всю жизнь газового диска.
func route_growth() -> float:
	return GameData.PLANET_ROUTE_GROWTH if planet_route() and is_embryo() else 1.0


## Сколько масс Земли нужно набрать на выбранном пути.
func embryo_goal() -> float:
	return GameData.SUPER_EARTHS if planet_route() else GameData.GIANT_EARTHS


## Забег окончен концовкой: начисляем наследие (за новую концовку — вдвое).
func finish(kind: String) -> int:
	if ending != "":
		return 0
	ending = kind
	var pts := int(GameData.ENDINGS[kind]["legacy"])
	if not kind in endings_seen:
		endings_seen.append(kind)
		pts *= 2
	if kind == "planet_living" and Skills.stat("garden") > 0.0:
		pts *= 2
	legacy += pts
	save_game()
	return pts


func is_pebble() -> bool:
	return stage >= GameData.PEBBLE_STAGE


func is_boulder() -> bool:
	return stage >= GameData.BOULDER_STAGE


func is_planet() -> bool:
	return stage >= GameData.PLANETESIMAL_STAGE


## Сколько кормовой полосы на этом расстоянии уже выедено, 0..1.
func zone_depletion(distance: float) -> float:
	var bin := str(GameData.zone_bin(distance))
	return clampf(float(zone_eaten.get(bin, 0.0)) / (GameData.zone_capacity(distance) * Skills.stat("zone")), 0.0, 1.0)


func eat_zone(distance: float, amount: float) -> void:
	var bin := str(GameData.zone_bin(distance))
	zone_eaten[bin] = float(zone_eaten.get(bin, 0.0)) + amount


## Жар алюминия-26: 1 в начале этапа, вдвое меньше каждые AL_HALF (навык замедляет).
func al_heat() -> float:
	return GameData.al_heat(planet_time / Skills.stat("al_slow"))


## Температура недр, K: растёт с размером, падает по мере распада алюминия.
func core_temp() -> float:
	return GameData.core_temp(GameData.planet_km(mass), al_heat(), Skills.stat("al_slow"))


## Тело не расплавилось и уже не расплавится: хондрит, хранящий хондры.
func is_chondrite() -> bool:
	return is_planet() and not is_melted and core_too_cold()


## Плавиться уже нечем: даже у крупного тела недра не дойдут до плавления.
func core_too_cold() -> bool:
	return GameData.CORE_COLD + GameData.CORE_HEAT * al_heat() < melt_t()


## Порог плавления недр: лёд и вода уносят тепло, «Холодные недра» — ещё больше.
func melt_t() -> float:
	return GameData.MELT_T + core_cooling()


## На сколько кельвинов лёд, углерод и навык поднимают порог плавления.
func core_cooling() -> float:
	return GameData.wet_cooling(GameData.composition(materials)) + Skills.stat("cold_core")


## Время на этапе планетезимали идёт, алюминий остывает; недра, разогревшиеся
## до температуры плавления, плавятся.
func tick_planet(delta: float) -> void:
	planet_time += delta
	if is_embryo() and gas_left > 0.0:
		gas_left = maxf(gas_left - delta, 0.0)
		if gas_left == 0.0:
			gas_gone.emit()
	if is_melted:
		return
	if core_temp() >= melt_t():
		_melt()


func _check_stage() -> void:
	var idx := GameData.stage_index(mass)
	if idx > stage:
		stage = idx
		stage_reached.emit(stage)
		skills_changed.emit()  # в книге открываются ветви новой стадии
		save_game()


## Сильный удар: от тела откалывается часть вещества, состав сохраняет пропорции.
func chip(amount: float, at: Vector2) -> void:
	ablate(amount)
	chipped.emit(at, amount)
	if is_boulder():
		heal_pool += amount * Skills.stat("heal")


## «Самозалечивание»: часть отколотой массы постепенно прирастает обратно,
## в тех же долях состава.
func regrow(delta: float) -> void:
	if heal_pool <= 0.0 or mass <= 0.0:
		return
	var amount := minf(heal_pool, maxf(heal_pool * HEAL_RATE * delta, mass * 0.0005 * delta))
	heal_pool -= amount
	var k := (mass + amount) / mass
	mass += amount
	for key in materials:
		materials[key] *= k
	mass_changed.emit(mass)
	_check_stage()


## Сублимация льда внутри снеговой линии: уходит только лёд.
func sublimate_ice(amount: float) -> void:
	if is_melted:
		return  # лёд расплавленного тела — под корой, состав застыл
	var ice: float = materials.get("ice", 0.0)
	amount = minf(amount, ice)
	if amount <= 0.0:
		return
	materials["ice"] = ice - amount
	mass -= amount
	mass_changed.emit(mass)


## Испарение у звезды: масса уходит в газ, состав сохраняет пропорции.
func ablate(amount: float) -> void:
	if amount <= 0.0 or mass <= 0.0:
		return
	var k := maxf(mass - amount, 0.0) / mass
	mass -= amount
	for key in materials:
		materials[key] *= k
	mass_changed.emit(mass)


func body_type() -> String:
	return GameData.body_type(materials)


func body_bonus(key: String) -> float:
	return float(GameData.BODY_TYPES[body_type()].get(key, 1.0))


func add_currency(amount: float) -> void:
	currency += amount
	currency_changed.emit(currency)


func add_chondrules(amount: int, at: Vector2) -> void:
	chondrules += amount
	chondrules_changed.emit(chondrules)
	chondrule_found.emit(at, amount)


func spend_chondrules(amount: int) -> bool:
	if chondrules < amount:
		return false
	chondrules -= amount
	chondrules_changed.emit(chondrules)
	return true


func spend(amount: float) -> bool:
	if currency < amount:
		return false
	currency -= amount
	currency_changed.emit(currency)
	return true


func get_skill_level(id: String) -> int:
	return int(skill_levels.get(id, 0))


func set_skill_level(id: String, level: int) -> void:
	skill_levels[id] = level
	skills_changed.emit()


func save_game() -> void:
	if burned_up:
		_reset_values()  # закрыли игру во время гибели: начнём заново
	var data := {
		"version": SAVE_VERSION,
		"currency": currency,
		"chondrules": chondrules,
		"mass": mass,
		"materials": materials,
		"skills": skill_levels,
		"position": [player_position.x, player_position.y],
		"prologue_seen": prologue_seen,
		"tutorial_done": tutorial_done,
		"stage": stage,
		"pebble_intro_done": pebble_intro_done,
		"boulder_intro_done": boulder_intro_done,
		"tips_seen": tips_seen,
		"fps_120": fps_120,
		"tree_view": tree_view,
		"planet_time": planet_time,
		"melted": is_melted,
		"core_share": core_share,
		"melt_type": melt_type,
		"zone_eaten": zone_eaten,
		"embryo_path": embryo_path,
		"embryo_choice": embryo_choice,
		"gas_left": gas_left,
		"magma_hits": magma_hits,
		"has_moon": has_moon,
		"ending": ending,
		"legacy": legacy,
		"endings_seen": endings_seen,
		"giant": giant,
		"young": young,
		"cloud": cloud,
	}
	if tree_seen != null:
		data.tree_seen = tree_seen
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var data = JSON.parse_string(file.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
	prologue_seen = bool(data.get("prologue_seen", false))
	tutorial_done = bool(data.get("tutorial_done", false))
	currency = float(data.get("currency", 0.0))
	chondrules = int(data.get("chondrules", 0))
	stage = int(data.get("stage", 0))
	pebble_intro_done = bool(data.get("pebble_intro_done", false))
	boulder_intro_done = bool(data.get("boulder_intro_done", false))
	tips_seen = Array(data.get("tips_seen", []))
	fps_120 = bool(data.get("fps_120", false))
	tree_view = Array(data.get("tree_view", []))
	planet_time = float(data.get("planet_time", 0.0))
	is_melted = bool(data.get("melted", false))
	core_share = float(data.get("core_share", 0.0))
	melt_type = str(data.get("melt_type", ""))
	zone_eaten = Dictionary(data.get("zone_eaten", {}))
	embryo_path = str(data.get("embryo_path", ""))
	embryo_choice = str(data.get("embryo_choice", ""))
	gas_left = float(data.get("gas_left", -1.0))
	magma_hits = int(data.get("magma_hits", 0))
	has_moon = bool(data.get("has_moon", false))
	ending = str(data.get("ending", ""))
	legacy = int(data.get("legacy", 0))
	endings_seen = Array(data.get("endings_seen", []))
	giant = Dictionary(data.get("giant", {}))
	young = Dictionary(data.get("young", {}))
	cloud = Dictionary(data.get("cloud", {}))
	# В старых сохранениях не знаем, что игрок видел: книга откроется без показа.
	tree_seen = Array(data.tree_seen) if data.has("tree_seen") else null
	mass = maxf(GameData.DEATH_MASS * 2.0, float(data.get("mass", 1.0)))
	stage = maxi(stage, GameData.stage_index(mass))
	for key in data.get("materials", {}):
		materials[key] = float(data.materials[key])
	for key in data.get("skills", {}):
		skill_levels[key] = int(data.skills[key])
	var pos = data.get("position", [])
	if pos is Array and pos.size() == 2:
		player_position = Vector2(pos[0], pos[1])
		# Позиция внутри звезды (старые версии) — возвращаем на старт.
		if player_position.length() < GameData.STAR_RADIUS * 1.05:
			player_position = Vector2(GameData.START_DISTANCE, 0.0)


## Есть ли что продолжать: хоть что-то собрано или куплено.
func has_progress() -> bool:
	return currency > 0.0 or mass > 1.0 or not skill_levels.is_empty()


## 60 кадров ровно — по умолчанию; 120 — для мощных телефонов с быстрым экраном.
func apply_fps() -> void:
	Engine.max_fps = 120 if fps_120 else 60


func reset_run() -> void:
	_reset_values()
	currency_changed.emit(currency)
	chondrules_changed.emit(chondrules)
	mass_changed.emit(mass)
	skills_changed.emit()
	save_game()


func _reset_values() -> void:
	burned_up = false
	heal_pool = 0.0
	stage = 0
	currency = 0.0
	chondrules = 0
	mass = 1.0
	skill_levels = {}
	tree_view = []
	tree_seen = []
	planet_time = 0.0
	is_melted = false
	core_share = 0.0
	melt_type = ""
	zone_eaten = {}
	embryo_path = ""
	embryo_choice = ""
	gas_left = -1.0
	magma_hits = 0
	has_moon = false
	ending = ""
	giant = {}
	young = {}
	cloud = {}
	player_position = Vector2(GameData.START_DISTANCE, 0.0)
	materials = {}
	for key in GameData.MATERIAL_ORDER:
		materials[key] = 0.0
