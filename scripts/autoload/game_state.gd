extends Node
## Состояние забега: валюта, масса, материалы, уровни навыков. Сохраняется в user://.

signal currency_changed(value: float)
signal mass_changed(value: float)
signal skills_changed
signal absorbed(position: Vector2, material: String, gained: float)

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1
const AUTOSAVE_SECONDS := 10.0

var currency := 0.0
var mass := 1.0
var materials := {}
var skill_levels := {}
var player_position := Vector2(GameData.START_DISTANCE, 0.0)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_reset_values()
	load_game()
	var timer := Timer.new()
	timer.wait_time = AUTOSAVE_SECONDS
	timer.autostart = true
	timer.timeout.connect(save_game)
	add_child(timer)


func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		save_game()


func absorb(level: int, material: String, at: Vector2) -> void:
	var data := GameData.level_data(level)
	var gained_mass: float = data.mass * body_bonus("mass")
	mass += gained_mass
	materials[material] = materials.get(material, 0.0) + gained_mass
	var gained: float = data.value * Skills.stat("value") * body_bonus("value")
	add_currency(gained)
	mass_changed.emit(mass)
	absorbed.emit(at, material, gained)


func body_type() -> String:
	return GameData.body_type(materials)


func body_bonus(key: String) -> float:
	return float(GameData.BODY_TYPES[body_type()].get(key, 1.0))


func add_currency(amount: float) -> void:
	currency += amount
	currency_changed.emit(currency)


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
	var data := {
		"version": SAVE_VERSION,
		"currency": currency,
		"mass": mass,
		"materials": materials,
		"skills": skill_levels,
		"position": [player_position.x, player_position.y],
	}
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
	currency = float(data.get("currency", 0.0))
	mass = maxf(1.0, float(data.get("mass", 1.0)))
	for key in data.get("materials", {}):
		materials[key] = float(data.materials[key])
	for key in data.get("skills", {}):
		skill_levels[key] = int(data.skills[key])
	var pos = data.get("position", [])
	if pos is Array and pos.size() == 2:
		player_position = Vector2(pos[0], pos[1])


func reset_run() -> void:
	_reset_values()
	currency_changed.emit(currency)
	mass_changed.emit(mass)
	skills_changed.emit()
	save_game()


func _reset_values() -> void:
	currency = 0.0
	mass = 1.0
	skill_levels = {}
	player_position = Vector2(GameData.START_DISTANCE, 0.0)
	materials = {}
	for key in GameData.MATERIAL_ORDER:
		materials[key] = 0.0
