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
	var gained_mass: float = base_mass * body_bonus("mass")
	mass += gained_mass
	materials[material] = materials.get(material, 0.0) + gained_mass
	var gained: float = base_value * Skills.stat("value") * Skills.stat("value_mul") * (1.0 if is_boulder() else Skills.stat("pebble_value_mul")) * body_bonus("value")
	add_currency(gained)
	mass_changed.emit(mass)
	absorbed.emit(at, material, gained)
	_check_stage()


func is_pebble() -> bool:
	return stage >= GameData.PEBBLE_STAGE


func is_boulder() -> bool:
	return stage >= GameData.BOULDER_STAGE


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
	player_position = Vector2(GameData.START_DISTANCE, 0.0)
	materials = {}
	for key in GameData.MATERIAL_ORDER:
		materials[key] = 0.0
