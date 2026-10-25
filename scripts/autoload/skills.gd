extends Node
## Древо навыков: определения узлов из data/skills.json и итоговые множители.
##
## Эффекты узла складываются за каждый уровень: {"gravity": 0.25} на 3 уровне даёт +75%.
## Особый эффект "dust_level" не складывается, а открывает пыль этого уровня.

signal stats_changed

const DATA_PATH := "res://data/skills.json"
const BASE_STATS := {
	"gravity": 1.0,   # сила притяжения
	"reach": 1.0,     # радиус притяжения
	"speed": 1.0,     # скорость движения
	"spawn": 0.17,    # плотность пыли вокруг; растёт только навыком «Плотное облако»
	"cluster": 1.0,   # частота скоплений
	"value": 1.0,     # валюта с пыли
	"dust_level": 1,  # максимальный уровень поглощаемой пыли
}

var nodes := {}
var order: Array[String] = []
var stats := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_definitions()
	recompute()
	GameState.skills_changed.connect(recompute)


func stat(key: String) -> float:
	return float(stats.get(key, BASE_STATS.get(key, 1.0)))


func max_dust_level() -> int:
	return int(stats.get("dust_level", 1))


func level(id: String) -> int:
	return GameState.get_skill_level(id)


func max_level(id: String) -> int:
	return int(nodes[id].get("max_level", 1))


func cost(id: String) -> float:
	var node: Dictionary = nodes[id]
	return floor(float(node.cost) * pow(float(node.get("cost_growth", 1.0)), level(id)))


func is_owned(id: String) -> bool:
	return level(id) > 0


func is_maxed(id: String) -> bool:
	return level(id) >= max_level(id)


## Узел доступен, когда выполнены требования: любой из родителей куплен,
## либо все родители при "requires_all": true. Корневые узлы доступны всегда.
func is_unlocked(id: String) -> bool:
	var reqs: Array = nodes[id].get("requires", [])
	if reqs.is_empty():
		return true
	var need_all: bool = nodes[id].get("requires_all", false)
	for req in reqs:
		var owned := is_owned(req)
		if need_all and not owned:
			return false
		if not need_all and owned:
			return true
	return need_all


## Узел видно (пусть и как «???»), если доступен хотя бы один его родитель.
func is_discovered(id: String) -> bool:
	if is_unlocked(id):
		return true
	for req in nodes[id].get("requires", []):
		if is_unlocked(req):
			return true
	return false


func can_buy(id: String) -> bool:
	return is_unlocked(id) and not is_maxed(id) and GameState.currency >= cost(id)


func any_affordable() -> bool:
	for id in order:
		if can_buy(id):
			return true
	return false


func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	if not GameState.spend(cost(id)):
		return false
	GameState.set_skill_level(id, level(id) + 1)
	return true


func recompute() -> void:
	stats = BASE_STATS.duplicate()
	for id in order:
		var lvl := level(id)
		if lvl <= 0:
			continue
		var effects: Dictionary = nodes[id].get("effects", {})
		for key in effects:
			if key == "dust_level":
				stats.dust_level = maxi(int(stats.dust_level), int(effects[key]))
			else:
				stats[key] = float(stats.get(key, 1.0)) + float(effects[key]) * lvl
	stats_changed.emit()


func _load_definitions() -> void:
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("Не найден файл навыков: " + DATA_PATH)
		return
	var data = JSON.parse_string(file.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Ошибка разбора " + DATA_PATH)
		return
	for node in data.nodes:
		nodes[node.id] = node
		order.append(node.id)
