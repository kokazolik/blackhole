class_name GameData
## Статичные игровые данные: уровни пыли, материалы, зоны диска, стадии роста.

# Мир: звезда в центре (0, 0), расстояния в пикселях мира.
const STAR_RADIUS := 180.0
const INNER_ZONE := 900.0   # ближе к звезде: металл и силикаты
const SNOW_LINE := 1900.0   # дальше: лёд и углерод
const START_DISTANCE := 1300.0

# Радиус пылинки игрока при массе 1. Радиус растёт как кубический корень массы.
const BASE_RADIUS := 6.0

# Индекс в массиве = уровень пыли - 1.
const DUST_LEVELS := [
	{"radius": 2.1, "mass": 0.04, "value": 1.0, "spawn_weight": 1.0, "cluster_weight": 1.0, "color": Color(0.91, 0.93, 1.0)},
	{"radius": 2.9, "mass": 0.12, "value": 2.0, "spawn_weight": 0.3, "cluster_weight": 0.5, "color": Color(1.0, 0.70, 0.28)},
	{"radius": 4.0, "mass": 0.40, "value": 5.0, "spawn_weight": 0.1, "cluster_weight": 0.25, "color": Color(0.61, 0.55, 1.0)},
]

const MATERIALS := {
	"silicate": {"name": "Силикаты", "color": Color(0.87, 0.77, 0.58)},
	"metal": {"name": "Металл", "color": Color(0.66, 0.74, 0.86)},
	"carbon": {"name": "Углерод", "color": Color(0.70, 0.50, 0.44)},
	"ice": {"name": "Лёд", "color": Color(0.72, 0.94, 1.0)},
}
const MATERIAL_ORDER := ["silicate", "metal", "carbon", "ice"]  # совпадает со строками атласа пыли

# Плотность пыли в диске. Поверхностная плотность падает как 1/r,
# а у снеговой линии пыль копится (намерзает лёд), там её в несколько раз больше.
const SNOW_LINE_BOOST := 2.0
const SNOW_LINE_WIDTH := 220.0
# Орбитальная скорость на стартовом расстоянии; вблизи звезды быстрее, как v ~ 1/sqrt(r).
const ORBIT_SPEED_AT_START := 60.0

# Состав тела. Пока собрано мало вещества, тип не определён.
const COMPOSITION_MIN_MASS := 0.5
const SPECIALIZE_SHARE := 0.5  # один материал выше этой доли: специализация
const MIX_MAX_SHARE := 0.4     # все материалы не выше этой доли: смесь (хондрит)

const BODY_TYPES := {
	"unformed": {"name": "Неоформленное", "desc": "состав ещё не сложился", "mass": 1.0, "value": 1.0, "speed": 1.0},
	"neutral": {"name": "Переходное", "desc": "без бонусов", "mass": 1.0, "value": 1.0, "speed": 1.0},
	"chondrite": {"name": "Хондрит (смесь)", "desc": "+15% массы, +15% валюты", "mass": 1.15, "value": 1.15, "speed": 1.0},
	"silicate": {"name": "Каменное", "desc": "+15% массы, валюты и скорости", "mass": 1.15, "value": 1.15, "speed": 1.15},
	"metal": {"name": "Металлическое", "desc": "+20% валюты, −20% роста", "mass": 0.8, "value": 1.2, "speed": 1.0},
	"carbon": {"name": "Углистое", "desc": "+50% валюты, −20% массы", "mass": 0.8, "value": 1.5, "speed": 1.0},
	"ice": {"name": "Ледяное", "desc": "+50% массы, −25% валюты", "mass": 1.5, "value": 0.75, "speed": 1.0},
}

const STAGES := [
	{"name": "Пылинка", "mass": 0.0},
	{"name": "Галька", "mass": 30.0},
	{"name": "Валун", "mass": 300.0},
	{"name": "Планетезималь", "mass": 3000.0},
]


static func level_data(level: int) -> Dictionary:
	return DUST_LEVELS[clampi(level, 1, DUST_LEVELS.size()) - 1]


static func material_weights(distance: float) -> Dictionary:
	if distance < INNER_ZONE:
		return {"metal": 0.45, "silicate": 0.5, "carbon": 0.05}
	if distance < SNOW_LINE:
		return {"silicate": 0.55, "carbon": 0.3, "metal": 0.1, "ice": 0.05}
	return {"ice": 0.6, "carbon": 0.35, "silicate": 0.05}


static func pick_weighted(weights: Dictionary, rng: RandomNumberGenerator):
	var total := 0.0
	for w in weights.values():
		total += w
	var roll := rng.randf() * total
	for key in weights:
		roll -= weights[key]
		if roll <= 0.0:
			return key
	return weights.keys().back()


## Доли материалов (0..1) по собранной массе.
static func composition(materials: Dictionary) -> Dictionary:
	var total := 0.0
	for key in MATERIAL_ORDER:
		total += float(materials.get(key, 0.0))
	var shares := {}
	for key in MATERIAL_ORDER:
		shares[key] = float(materials.get(key, 0.0)) / total if total > 0.0 else 0.0
	return shares


static func body_type(materials: Dictionary) -> String:
	var total := 0.0
	for key in MATERIAL_ORDER:
		total += float(materials.get(key, 0.0))
	if total < COMPOSITION_MIN_MASS:
		return "unformed"
	var shares := composition(materials)
	var top_key: String = MATERIAL_ORDER[0]
	for key in MATERIAL_ORDER:
		if shares[key] > shares[top_key]:
			top_key = key
	if shares[top_key] > SPECIALIZE_SHARE:
		return top_key
	if shares[top_key] <= MIX_MAX_SHARE:
		return "chondrite"
	return "neutral"


## Средняя плотность пыли на расстоянии от звезды (1.0 на старте).
static func radial_density(distance: float) -> float:
	var falloff := START_DISTANCE / maxf(distance, STAR_RADIUS)
	var snow := 1.0 + SNOW_LINE_BOOST * exp(-pow((distance - SNOW_LINE) / SNOW_LINE_WIDTH, 2.0))
	return falloff * snow


## Орбитальная скорость (по Кеплеру) на расстоянии от звезды.
static func orbit_speed(distance: float) -> float:
	return ORBIT_SPEED_AT_START * sqrt(START_DISTANCE / maxf(distance, STAR_RADIUS))


static func stage_index(mass: float) -> int:
	var idx := 0
	for i in STAGES.size():
		if mass >= STAGES[i].mass:
			idx = i
	return idx


static func format_number(v: float) -> String:
	if v < 1000.0:
		return str(int(floor(v)))
	var suffixes := ["K", "M", "B", "T"]
	var tier := int(floor(log(v) / log(1000.0)))
	if tier <= suffixes.size():
		return "%.2f%s" % [v / pow(1000.0, tier), suffixes[tier - 1]]
	return "%.2fe%d" % [v / pow(10.0, floor(log(v) / log(10.0))), int(floor(log(v) / log(10.0)))]


static func format_mass(v: float) -> String:
	if v < 100.0:
		return "%.2f" % v
	return format_number(v)
