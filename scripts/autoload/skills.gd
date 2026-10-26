extends Node
## Древо навыков: определения узлов из data/skills.json и итоговые множители.
##
## Эффекты узла складываются за каждый уровень: {"gravity": 0.25} на 3 уровне даёт +75%.
## Особый эффект "dust_level" не складывается, а открывает пыль этого уровня.

signal stats_changed

const DATA_PATH := "res://data/skills.json"
const BASE_STATS := {
	"gravity": 1.0,   # сила притяжения пыли (электростатика, не гравитация)
	"reach": 1.0,     # радиус притяжения
	"speed": 1.0,     # скорость движения
	"spawn": 0.17,    # плотность пыли вокруг; растёт только навыком «Плотное облако»
	"cluster": 1.0,   # частота скоплений
	"value": 1.0,     # валюта с пыли
	"dust_level": 1,  # максимальный уровень поглощаемой пыли
	# Этап «Галька»:
	"drift": 1.0,     # сила встречного ветра (дрейфа к звезде)
	"stick": 1.0,     # скорость удара, до которой гальки слипаются
	"thrust": 1.0,    # тяга: как быстро галька набирает и гасит скорость
	"chip": 1.0,      # сколько массы откалывается при сильном ударе
	"pebbles": 1.0,   # сколько галек вокруг
	"grip": 0.32,      # предел размера присоединяемой гальки, в долях своего радиуса
	"combo": 0.0,     # прибавка к звёздной пыли за каждый шаг серии слипаний
	"combo_cap": 3.0, # сколько шагов серии учитывается
	"geode": 0.0,     # шанс, что галька окажется жеодой
	"geode_value": 10.0,  # во сколько раз жеода ценнее
	"swarm": 0.0,     # уровень потоковой неустойчивости: 0 — роёв нет
	"pebble_pull": 0.0,  # гальки сами плывут к тебе (легендарный «Вихрь в газе»)
	"accretion": 1.0, # этап «Валун»: доля вещества, прирастающая при слипании (к PebbleField.ACCRETION)
	# Ветвь «Состав»: сколько галек этого материала вокруг и как легко с ними слипаться.
	"affinity_silicate": 1.0, "affinity_metal": 1.0, "affinity_carbon": 1.0, "affinity_ice": 1.0,
	"glue_silicate": 1.0, "glue_metal": 1.0, "glue_carbon": 1.0, "glue_ice": 1.0,
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
## либо все родители при "requires_all": true. "requires_level" — какого уровня
## должны быть родители (по умолчанию хватает первого). Корневые узлы доступны всегда.
func is_unlocked(id: String) -> bool:
	# Путь вещества выбирают один раз: остальные ветки «Избирательности» закрыты.
	if blocked_by(id) != "":
		return false
	# Ветви следующих стадий открываются, когда тело до них доросло.
	if GameState.stage < int(nodes[id].get("requires_stage", 0)):
		return false
	var reqs: Array = nodes[id].get("requires", [])
	if reqs.is_empty():
		return true
	var need_all: bool = nodes[id].get("requires_all", false)
	var need_level := int(nodes[id].get("requires_level", 1))
	for req in reqs:
		var owned := level(req) >= need_level
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


## Узел другого пути вещества, из-за которого этот закрыт; "" — не закрыт.
func blocked_by(id: String) -> String:
	var path: String = nodes[id].get("path", "")
	if path == "":
		return ""
	for other in order:
		var p: String = nodes[other].get("path", "")
		if p != "" and p != path and is_owned(other):
			return other
	return ""


## Выбранный путь вещества ("ice", "metal"...) или "".
func chosen_path() -> String:
	for id in order:
		if nodes[id].get("path", "") != "" and is_owned(id):
			return nodes[id].path
	return ""


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
	# Скидки складываются, но совсем убрать сколы и ветер нельзя.
	stats.chip = maxf(stats.chip, 0.1)
	stats.drift = maxf(stats.drift, 0.2)
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
