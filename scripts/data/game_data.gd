class_name GameData
## Статичные игровые данные: уровни пыли, материалы, зоны диска, стадии роста.

# Мир: звезда в центре (0, 0), расстояния в пикселях мира.
const STAR_RADIUS := 2000.0  # звезда огромная по сравнению с пылинками
const INNER_ZONE := 3600.0  # ближе к звезде: металл и силикаты
const SNOW_LINE := 6800.0   # дальше: лёд и углерод
const START_DISTANCE := 4300.0  # с края экрана видно сияние звезды

# Радиус пылинки игрока при массе 1: на старте игрок размером с пыль 1-го уровня.
# Радиус растёт как кубический корень массы, поэтому к первому навыку (~50 пылинок)
# игрок примерно с пыль 2-го уровня.
const BASE_RADIUS := 2.1

# Нагрев у звезды. Огня в космосе нет: гореть нечему и нечем (нет кислорода).
# Пылинка нагревается излучением звезды, светится сама, как раскалённый металл,
# а потом испаряется (сублимирует) прямо в газ, и звёздный ветер уносит пар.
const HEAT_START := 1.75          # в радиусах звезды: ближе пылинка заметно греется
const SPACE_TEMP := 300.0         # K, температура пылинки вдали от этой зоны
const SURFACE_TEMP := 3000.0      # K, у самой поверхности звезды
const GLOW_TEMP := 800.0          # K, точка Дрейпера: тело начинает светиться тёмно-красным
const SUBLIMATION_TEMP := 1400.0  # K, силикатная пыль испаряется (поэтому у звезды пыли нет)
const DEATH_MASS := 0.12          # меньше этого от пылинки ничего не осталось

# Индекс в массиве = уровень пыли - 1. Масса подобрана симуляцией игрока-бота:
# до «Гальки» (масса 30) около 15–20 минут игры.
const DUST_LEVELS := [
	{"radius": 1.9, "mass": 0.0135, "value": 1.0, "spawn_weight": 1.0, "cluster_weight": 1.0, "color": Color(0.91, 0.93, 1.0)},
	{"radius": 2.5, "mass": 0.043, "value": 2.0, "spawn_weight": 0.3, "cluster_weight": 0.5, "color": Color(1.0, 0.70, 0.28)},
	{"radius": 3.3, "mass": 0.135, "value": 5.0, "spawn_weight": 0.1, "cluster_weight": 0.25, "color": Color(0.61, 0.55, 1.0)},
]

# Множители пыли на этапе пылинки: этап шёл ~16 минут почти ровным темпом,
# ужимаем до ~11, не уменьшая число покупок.
const DUST_STAGE_MASS := 1.5
const DUST_STAGE_VALUE := 1.45

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
const SNOW_LINE_WIDTH := 700.0
# Орбитальная скорость на стартовом расстоянии; вблизи звезды быстрее, как v ~ 1/sqrt(r).
const ORBIT_SPEED_AT_START := 25.0

# Состав тела. Пока собрано мало вещества, тип не определён.
const COMPOSITION_MIN_MASS := 0.5
const SPECIALIZE_SHARE := 0.5  # один материал выше этой доли: специализация
const MIX_MAX_SHARE := 0.4     # все материалы не выше этой доли: смесь (хондрит)
const DUO_SHARE := 0.25        # переходное тело: второй материал от этой доли делает двойной тип
# Двойные типы переходного тела: пара главных материалов даёт особый мир.
# Лёд с углеродом — метановый мир, как Титан. Камень с углеродом — углекислый
# газ выходит из пород и запирает тепло, как на Венере.
const DUO_TYPES := {"titan": ["ice", "carbon"], "venus": ["silicate", "carbon"]}

# Тип тела не даёт сиюминутных бонусов: состав решает, кем тело станет потом.
# Из металлических планетезималей вырастают железные миры, из каменных —
# землеподобные планеты, ледяные за снеговой линией становятся ядрами гигантов.
const BODY_TYPES := {
	"unformed": {"name": "Неоформленное", "desc": "состав ещё не сложился"},
	"neutral": {"name": "Переходное", "desc": "путь ещё не выбран"},
	"titan": {"name": "Лёд и углерод", "desc": "путь: метановый мир, как Титан", "color": Color(0.92, 0.62, 0.3)},
	"venus": {"name": "Камень и углерод", "desc": "путь: парниковый мир, как Венера", "color": Color(0.95, 0.82, 0.5)},
	"chondrite": {"name": "Хондрит (смесь)", "desc": "путь: строительный астероид, гибкий к любой судьбе"},
	"silicate": {"name": "Каменное", "desc": "путь: землеподобная планета"},
	"metal": {"name": "Металлическое", "desc": "путь: железный мир с огромным ядром"},
	"carbon": {"name": "Углистое", "desc": "путь: тёмный углистый мир, богатый органикой"},
	"ice": {"name": "Ледяное", "desc": "путь: ядро планеты-гиганта"},
}

const STAGES := [
	{"name": "Пылинка", "mass": 0.0},
	{"name": "Галька", "mass": 30.0},
	{"name": "Валун", "mass": 3000.0},        # ~1 м: в сто раз крупнее гальки
	{"name": "Планетезималь", "mass": 3000000.0},  # ~1 км: здесь уже правит гравитация
	{"name": "Зародыш планеты", "mass": 3000000000.0},  # ~1000 км: кормовая полоса выедена
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
	var second := ""
	for key in MATERIAL_ORDER:
		if key != top_key and (second == "" or shares[key] > shares[second]):
			second = key
	if shares[second] >= DUO_SHARE:
		for duo in DUO_TYPES:
			var pair: Array = DUO_TYPES[duo]
			if top_key in pair and second in pair:
				return duo
	return "neutral"


## Ведущий материал тела (у переходного тела его бонусы и судьба).
static func lead_material(materials: Dictionary) -> String:
	var shares := composition(materials)
	var top_key: String = MATERIAL_ORDER[0]
	for key in MATERIAL_ORDER:
		if shares[key] > shares[top_key]:
			top_key = key
	return top_key


## Средняя плотность пыли на расстоянии от звезды (1.0 на старте).
static func radial_density(distance: float) -> float:
	var falloff := START_DISTANCE / maxf(distance, STAR_RADIUS)
	var snow := 1.0 + SNOW_LINE_BOOST * exp(-pow((distance - SNOW_LINE) / SNOW_LINE_WIDTH, 2.0))
	return falloff * snow


## Орбитальная скорость (по Кеплеру) на расстоянии от звезды.
static func orbit_speed(distance: float) -> float:
	return ORBIT_SPEED_AT_START * sqrt(START_DISTANCE / maxf(distance, STAR_RADIUS))


## Орбитальная скорость вокруг звезды (на экране — по часовой стрелке).
static func orbit_velocity(pos: Vector2) -> Vector2:
	var r := pos.length()
	if r < 0.001:
		return Vector2.ZERO
	return Vector2(-pos.y, pos.x) / r * orbit_speed(r)


static func stage_index(mass: float) -> int:
	var idx := 0
	for i in STAGES.size():
		if mass >= STAGES[i].mass:
			idx = i
	return idx


## Коротко для цен: три значащие цифры без лишних нулей — 300K, 1.25M, 45.5K.
static func format_short(v: float) -> String:
	if v < 1000.0:
		return str(int(floor(v)))
	var suffixes := ["K", "M", "B", "T"]
	var i := -1
	while v >= 1000.0 and i < suffixes.size() - 1:
		v /= 1000.0
		i += 1
	var digits := 0 if v >= 100.0 else (1 if v >= 10.0 else 2)
	var s := String.num(v, digits)
	if "." in s:
		s = s.rstrip("0").rstrip(".")
	return s + suffixes[i]


## Русское склонение по числу: 1 хондру, 2 хондры, 5 хондр.
static func plural(n: int, one: String, few: String, many: String) -> String:
	var n100 := n % 100
	var n10 := n % 10
	if n100 >= 11 and n100 <= 14:
		return many
	if n10 == 1:
		return one
	if n10 >= 2 and n10 <= 4:
		return few
	return many


static func format_number(v: float) -> String:
	if v < 1000.0:
		return str(int(floor(v)))
	var suffixes := ["K", "M", "B", "T"]
	var tier := int(floor(log(v) / log(1000.0)))
	if tier <= suffixes.size():
		return "%.2f%s" % [v / pow(1000.0, tier), suffixes[tier - 1]]
	return "%.2fe%d" % [v / pow(10.0, floor(log(v) / log(10.0))), int(floor(log(v) / log(10.0)))]


## Примерный реальный размер тела по массе. Шкала логарифмическая, как и рост:
## масса 1 — пылинка ~0.1 мм, 30 — галька ~1 см, 3000 — валун ~1 м, 3·10⁶ — ~1 км.
static func real_size_cm(m: float) -> float:
	if m < 30.0:
		return 0.01 * pow(100.0, log(maxf(m, 0.001)) / log(30.0))
	return m / 30.0


static func format_size(m: float) -> String:
	var cm := real_size_cm(m)
	if cm < 0.1:
		return "≈ %d мкм" % roundi(cm * 10000.0)
	if cm < 1.0:
		return "≈ %.1f мм" % (cm * 10.0)
	if cm < 100.0:
		return "≈ %d см" % roundi(cm) if cm >= 10.0 else "≈ %.1f см" % cm
	if cm < 100000.0:
		return "≈ %.1f м" % (cm / 100.0) if cm < 1000.0 else "≈ %d м" % roundi(cm / 100.0)
	var km := cm / 100000.0
	return "≈ %.1f км" % km if km < 100.0 else "≈ %d км" % roundi(km)


static func format_mass(v: float) -> String:
	if v < 100.0:
		return "%.2f" % v
	return format_number(v)


## Температура пылинки на расстоянии от звезды, K. Растёт к поверхности.
static func temperature_at(distance: float) -> float:
	var heat := clampf((HEAT_START - distance / STAR_RADIUS) / (HEAT_START - 1.0), 0.0, 1.0)
	return SPACE_TEMP + (SURFACE_TEMP - SPACE_TEMP) * pow(heat, 1.3)


## Цвет свечения нагретого тела (приближение чёрного тела): тёмно-красный при
## ~800 K, оранжевый к 1400 K, жёлто-белый к 3000 K. Альфа — яркость свечения.
static func thermal_color(temp: float) -> Color:
	var t := clampf((temp - GLOW_TEMP) / (SURFACE_TEMP - GLOW_TEMP), 0.0, 1.0)
	var c: Color
	if t < 0.3:
		c = Color(0.45, 0.04, 0.0).lerp(Color(0.95, 0.25, 0.03), t / 0.3)
	elif t < 0.65:
		c = Color(0.95, 0.25, 0.03).lerp(Color(1.0, 0.62, 0.22), (t - 0.3) / 0.35)
	else:
		c = Color(1.0, 0.62, 0.22).lerp(Color(1.0, 0.92, 0.75), (t - 0.65) / 0.35)
	# Яркость свечения: от еле заметного тления до ослепительного у звезды.
	c.a = 0.1 + 0.9 * pow(t, 0.8) if temp > GLOW_TEMP else 0.0
	return c


## Расстояние от звезды, ближе которого любая пыль испаряется (температура выше
## SUBLIMATION_TEMP). Обратная функция к temperature_at.
static func sublimation_distance() -> float:
	var heat := pow((SUBLIMATION_TEMP - SPACE_TEMP) / (SURFACE_TEMP - SPACE_TEMP), 1.0 / 1.3)
	return (HEAT_START - heat * (HEAT_START - 1.0)) * STAR_RADIUS


## Зона диска, где сейчас игрок: название, чего там больше и цвет подписи.
static func zone_at(distance: float) -> Dictionary:
	if distance < sublimation_distance():
		return {"name": "Зона испарения", "desc": "пыль не выживает, всё уходит в газ", "color": Color(1.0, 0.5, 0.25)}
	if distance < INNER_ZONE:
		return {"name": "Внутренний диск", "desc": "металл и силикаты", "color": Color(1.0, 0.75, 0.45)}
	if absf(distance - SNOW_LINE) < SNOW_LINE_WIDTH:
		return {"name": "Снеговая линия", "desc": "замерзает лёд, пыли больше всего", "color": Color(0.7, 0.92, 1.0)}
	if distance < SNOW_LINE:
		return {"name": "Каменная зона", "desc": "силикаты и углерод", "color": Color(0.92, 0.82, 0.62)}
	return {"name": "Ледяная зона", "desc": "лёд и углерод", "color": Color(0.62, 0.85, 1.0)}


# --- Этап «Галька» ---
# Газ диска подпирается давлением и вращается чуть медленнее твёрдых тел. Пыль
# летит вместе с газом, а галька уже достаточно тяжёлая, чтобы отставать:
# встречный ветер тормозит её, и она по спирали дрейфует к звезде. Скорость
# дрейфа растёт с размером (число Стокса растёт к метровым телам).
const PEBBLE_STAGE := 1               # индекс «Гальки» в STAGES
const DRIFT_SPEED := 15.0             # дрейф гальки радиусом PEBBLE_REF_RADIUS, ед./с
const PEBBLE_REF_RADIUS := 6.5        # радиус игрока при массе 30
const DRIFT_SIZE_EXP := 0.8
const DRIFT_TANGENTIAL := 0.45        # обгон газа по орбите, в долях радиального дрейфа
# Ловушки давления: кольца, где давление газа максимально. Внутри кольца газ
# быстрее, снаружи медленнее, поэтому гальки сносит к середине кольца и там они
# копятся. Такие кольца видны в диске HL Тельца на снимках ALMA.
const PRESSURE_RINGS := [5300.0, 6800.0, 8700.0, 11000.0]  # вторая — на снеговой линии
const RING_WIDTH := 300.0
# Слипание и раскол: медленно — слипаются, быстро — откалываются осколки.
const STICK_SPEED := 42.0             # скорость удара, до которой гальки слипаются, ед./с
const SHATTER_FACTOR := 1.7           # во столько раз быстрее — галька разлетается целиком
# Откол растёт с энергией удара: масса чужой гальки × (скорость / порог)². Но не
# больше CHIP_MAX от своей массы за один удар.
const CHIP_K := 0.35
const CHIP_MAX := 0.015
const CHIP_MAX_BIG := 0.05   # удар о гальку, которую не удержать, бьёт сильнее: до 5% массы
# Чужие гальки той же плотности, что и ты: масса честно растёт как куб радиуса.
const PEBBLE_DENSITY := 1.0
# Азарт: серия слипаний, жеоды и потоковая неустойчивость.
const COMBO_WINDOW := 3.5             # секунд между слипаниями, чтобы серия не прервалась
const GEODE_GLOW := Color(1.0, 0.85, 0.4)
const SWARM_INTERVAL := 80.0          # раз в столько секунд рой на первом уровне навыка
const SWARM_DURATION := 20.0


static func is_pebble_size(r: float) -> bool:
	return r >= PEBBLE_REF_RADIUS * 0.6


## Насколько тело в ловушке давления: 1 в середине кольца, 0 вдали.
static func trap_strength(distance: float) -> float:
	var best := 0.0
	for rc in PRESSURE_RINGS:
		var x: float = (distance - rc) / RING_WIDTH
		best = maxf(best, exp(-x * x / 1.44))
	return best


## Скорость дрейфа тела радиуса r относительно пыли (она летит вместе с газом).
## Вдали от колец — к звезде и чуть вперёд по орбите; у кольца радиальная
## составляющая меняет знак, и тело сносит к его середине.
static func gas_drift(pos: Vector2, r: float) -> Vector2:
	var dist := pos.length()
	if dist < 1.0:
		return Vector2.ZERO
	# r — радиус в мире; снос считаем по настоящему размеру и переводим в мир.
	var base := DRIFT_SPEED * pow(r / world_k / PEBBLE_REF_RADIUS, DRIFT_SIZE_EXP) * speed_k()
	var radial := -1.0
	var calm := 0.0
	for rc in PRESSURE_RINGS:
		var x: float = (dist - rc) / RING_WIDTH
		var g := exp(-x * x / 1.44)
		if g > calm:
			calm = g
			radial = -((1.0 - g) + g * tanh(2.0 * x))
	var out := pos / dist
	var along := orbit_velocity(pos).normalized()
	return (out * radial + along * DRIFT_TANGENTIAL * (1.0 - calm)) * base


## Масса чужого тела радиуса r. Плотность у всех одна, поэтому масса — как куб
## отношения радиусов к телу игрока (с его массой и радиусом по body_radius).
static func pebble_mass(r: float, player_mass: float) -> float:
	return player_mass * pow(r / body_radius(player_mass), 3.0) * PEBBLE_DENSITY


## Сколько массы прирастает, когда съел тело радиуса r. Теперь можно есть всё,
## что меньше тебя, и по честному кубу крупная добыча сразу удваивала бы тело:
## прирост растёт как квадрат отношения радиусов, а не как куб.
const BITE_K := 0.05
const BITE_EXP := 2.0


static func bite_mass(r: float, player_mass: float) -> float:
	return player_mass * BITE_K * pow(r / body_radius(player_mass), BITE_EXP) * PEBBLE_DENSITY


# --- Этап «Валун» ---
# Метровый барьер: тела около метра сильнее всего тормозятся газом и быстрее всех
# падают на звезду. Сразу после превращения снос почти вдвое сильнее, чем у
# крупной гальки, а с ростом слабеет: километровое тело газ почти не замечает.
const BOULDER_STAGE := 2
const PLANETESIMAL_STAGE := 3
const BOULDER_MASS := 3000.0
const BARRIER_PEAK := 1.8            # снос в начале этапа, в долях «гальки того же размера»
const BARRIER_FADE := 0.5            # как быстро снос слабеет с массой
# Радиус тела растёт медленнее куба массы: иначе к километру диск не влез бы в
# экран. Настоящий размер всё равно пишется в HUD.
const BOULDER_RADIUS_EXP := 1.0 / 9.0


# Смена масштаба на валуне. Настоящая звезда больше метрового валуна в
# миллиарды раз; показать так нельзя, но и прежние ~70 раз — слишком мало. При
# превращении в валун всё вокруг тебя (тело, гальки, скорости, снос) становится
# в BOULDER_WORLD раз меньше, а звезда и диск остаются прежними. Камера
# приближается, и на экране ты прежнего размера, а звезда — огромная.
const BOULDER_WORLD := 0.25
static var world_k := 1.0  # 1 до валуна, BOULDER_WORLD на валуне; плавно в переходе (ставит Player)


## Скорости на валуне уменьшаются слабее, чем размеры: иначе диск для валуна
## становится в 4 раза больше, и до колец и снеговой линии не долететь.
static func speed_k() -> float:
	return sqrt(world_k)


static func body_radius(m: float) -> float:
	if m <= BOULDER_MASS:
		return BASE_RADIUS * pow(maxf(m, 0.0), 1.0 / 3.0) * world_k
	return BASE_RADIUS * pow(BOULDER_MASS, 1.0 / 3.0) * pow(m / BOULDER_MASS, BOULDER_RADIUS_EXP) * world_k


## Во сколько раз снос сильнее, чем у гальки того же радиуса (1 до валуна).
static func barrier_drift(m: float) -> float:
	if m <= BOULDER_MASS:
		return 1.0
	return BARRIER_PEAK * pow(m / BOULDER_MASS, -BARRIER_FADE)

# На этапе «Валун» тело уже само весит как тысячи галек, и каждое слипание
# прибавляет ему лишь малую долю: рост к планетезимали растянут на ~25 минут.
const BOULDER_GAIN := 1.15
const BOULDER_GAIN_FADE := 0.15
# Доход за слипание на валуне тот же, что был на гальке (игрок богат), цены ветки под него.
const BOULDER_VALUE := 1.0
# К концу этапа тело в сотни раз тяжелее, и без притормаживания доход взлетал
# в сотни раз: книга скупалась за минуту. На валуне он растёт с массой слабее.
const BOULDER_VALUE_FADE := 0.35


static func boulder_value(m: float) -> float:
	return BOULDER_VALUE * pow(maxf(m / BOULDER_MASS, 1.0), -BOULDER_VALUE_FADE)


# Что вещество тела даёт валуну. Ключ — тип тела (GameData.body_type), эффекты
# складываются с навыками так же, как эффекты узлов древа.
const BOULDER_MATERIAL := {
	"metal": {"effects": {"drift": -0.12, "thrust": 0.1}, "text": "металл тяжёлый: снос −12%, тяга +10%"},
	"silicate": {"effects": {"chip": -0.25}, "text": "камень прочный: сколов на 25% меньше"},
	"ice": {"effects": {"stick": 0.2, "grip": 0.04}, "text": "лёд липкий: слипание +20%, без дуги прилипает на 4% крупнее"},
	"carbon": {"effects": {"chip": -0.12, "stick": 0.12}, "text": "пористый углерод гасит удары: сколов −12%, слипание +12%"},
	"chondrite": {"effects": {"drift": -0.04, "chip": -0.08, "stick": 0.06}, "text": "смесь: снос −4%, сколов −8%, слипание +6%"},
	"titan": {"effects": {"stick": 0.16, "chip": -0.06, "grip": 0.02}, "text": "лёд с углеродом: слипание +16%, сколов −6%, прилипает на 2% крупнее"},
	"venus": {"effects": {"chip": -0.18, "stick": 0.06}, "text": "камень с углеродом: сколов −18%, слипание +6%"},
}

## Бонус вещества валуну; переходное тело получает бонус ведущего материала.
static func boulder_material(type: String) -> Dictionary:
	if type == "neutral":
		type = lead_material(GameState.materials)
	return BOULDER_MATERIAL.get(type, {})


# Ближе к километру валун начинает сам притягивать мелочь: от SELF_GRAV_FROM
# притяжение растёт и к планетезимали выходит на полную силу.
const SELF_GRAV_FROM := 300000.0


static func self_gravity(m: float) -> float:
	if m <= SELF_GRAV_FROM:
		return 0.0
	return clampf(log(m / SELF_GRAV_FROM) / log(STAGES[3].mass / SELF_GRAV_FROM), 0.0, 1.0)


static func boulder_gain(m: float) -> float:
	if m <= BOULDER_MASS:
		return 1.0
	return BOULDER_GAIN * pow(m / BOULDER_MASS, -BOULDER_GAIN_FADE)


# --- Этап «Планетезималь» ---
# Тело от километра до тысячи километров держит собственная гравитация. Сливается
# всё, что подлетает медленнее второй космической (скорости убегания), а исход
# быстрого удара решает удельная энергия Q против прочности тела Q*.
# Настоящие числа (плотность 2 г/см³): убегание ~1,06 м/с на километр радиуса,
# Q* ~100 Дж/кг у километрового тела и ~10⁶ у тысячекилометрового.
const EMBRYO_STAGE := 4
const PLANET_MASS := 3.0e6       # 1 км
const PLANET_END_MASS := 3.0e9   # ~1000 км: тело становится зародышем планеты
const AU_UNITS := SNOW_LINE / 2.7  # снеговая линия молодой звезды около 2,7 а.е.
# Масштаб против звезды. Настоящая звезда в тысячу раз крупнее даже тысячекилометрового
# тела. Чтобы планетезималь не дорастала на экране до звезды, на 10 и на 100 км мир
# вокруг тебя снова мельчает вдвое, как при превращении в валун (BOULDER_WORLD):
# ты остаёшься того же размера на экране, а звезда и диск становятся огромнее.
const PLANET_WORLD_STEPS := [[3.0e7, 0.5], [3.0e8, 0.5]]
# Скорость убегания в игре: от скорости слипания валуна, растёт с радиусом медленнее,
# чем настоящая (в тысячу раз за этап на экране не показать).
const PLANET_ESC_K := 2.0
const PLANET_ESC_EXP := 0.25
# Сфера Хилла: ~170 радиусов тела на 1 а.е. при любом размере, дальше от звезды шире.
# На экране сжата, иначе не влезла бы.
const HILL_PER_AU := 170.0
const HILL_SCREEN := 0.035
# Рост: каждая добыча прибавляет долю массы, как на валуне, но планетезималь
# собирает мелочь гравитацией и растёт быстрее.
const PLANET_GAIN := 1.3
const PLANET_GAIN_FADE := 0.06
const PLANET_VALUE := 3.0
# Кормовая полоса: кольцо диска шириной ZONE_BIN. Всё вещество в ней рано или поздно
# проходит мимо тебя; съел — оно кончается (масса изоляции). За снеговой линией
# вещества в разы больше: там есть лёд.
const ZONE_BIN := 700.0
const ZONE_CAPACITY := 0.6       # в долях PLANET_END_MASS внутри снеговой линии
const ZONE_SNOW_BOOST := 2.5
# Алюминий-26: период полураспада 0,72 млн лет. В игре — 7 минут на этапе.
# Недра крупного тела, выросшего, пока жар не угас, плавятся: железо тонет в ядро.
const AL_HALF := 420.0
const MELT_KM := 20.0      # с этого размера тело удерживает тепло недр почти целиком
const MELT_T := 1250.0     # недра плавятся (железо-сернистая смесь), K
const CORE_COLD := 200.0   # недра без нагрева, K
const CORE_HEAT := 1700.0  # нагрев алюминием-26 в начале этапа у крупного тела, K
# Лёд в недрах тает, и горячая вода уносит тепло наружу: так углистые хондриты
# остались непереплавленными. Порог плавления растёт с долей льда (углерод — на четверть:
# в нём вода связана в глинах).
const WET_COOL := 900.0


## Насколько вода в недрах поднимает порог плавления, K.
static func wet_cooling(shares: Dictionary) -> float:
	return WET_COOL * (float(shares.get("ice", 0.0)) + 0.25 * float(shares.get("carbon", 0.0)))


## Настоящий радиус тела в километрах (по шкале real_size_cm).
static func planet_km(m: float) -> float:
	return real_size_cm(m) / 100000.0


## Во сколько раз мир вокруг ещё мельче, чем на валуне (1, 0.5, 0.25).
static func planet_world(m: float) -> float:
	var k := 1.0
	for step in PLANET_WORLD_STEPS:
		if m >= step[0]:
			k *= step[1]
	return k


## Настоящая скорость убегания, м/с (плотность 2 г/см³).
static func escape_ms(m: float) -> float:
	return 1.06 * planet_km(m)


## Скорость убегания тела массы m в игровых единицах.
static func escape_game(m: float) -> float:
	var true_r := body_radius(m) / world_k
	var base := STICK_SPEED * pow(true_r / PEBBLE_REF_RADIUS, 0.4) * speed_k()
	return base * PLANET_ESC_K * pow(maxf(planet_km(m), 1.0), PLANET_ESC_EXP)


## Удельная прочность Q*, Дж/кг: у километра ~100, к 1000 км ~10⁶
## (Benz & Asphaug 1999, приблизительно).
static func qstar(km: float) -> float:
	if km < 10.0:
		return 100.0 * maxf(km, 0.1)
	return 1000.0 * pow(km / 10.0, 1.5)


## Во сколько раз быстрее убегания надо ударить тело твоей массы, чтобы разнести.
## Настоящее отношение — от ~27 у километра до ~2,7 у тысячи км; в игре сжато
## в 4…2, иначе мелкие тела не раскалывались бы никогда.
static func disrupt_ratio(m: float) -> float:
	var km := maxf(planet_km(m), 1.0)
	return lerpf(4.0, 2.0, clampf(log(km) / log(1000.0), 0.0, 1.0))


## Сфера Хилла в радиусах тела на этом расстоянии от звезды (настоящая).
static func hill_ratio(distance: float) -> float:
	return HILL_PER_AU * distance / AU_UNITS


## Кольцо диска (кормовая полоса), в котором точка.
static func zone_bin(distance: float) -> int:
	return int(distance / ZONE_BIN)


## Сколько вещества всего в кормовой полосе на этом расстоянии.
static func zone_capacity(distance: float) -> float:
	var snow := ZONE_SNOW_BOOST if distance > SNOW_LINE else 1.0
	return PLANET_END_MASS * ZONE_CAPACITY * snow


## Доля массы за добычу на этапе планетезимали.
static func planet_gain(m: float) -> float:
	return PLANET_GAIN * pow(maxf(m / PLANET_MASS, 1.0), -PLANET_GAIN_FADE)


## Жар алюминия-26 (1 — в начале этапа) через t секунд.
static func al_heat(t: float) -> float:
	return pow(0.5, t / AL_HALF)


## Температура недр: алюминий греет, а удержать тепло может только крупное тело —
## мелкое остывает быстрее, чем нагревается. size_k — множитель «эффективного» размера.
static func core_temp(km: float, heat: float, size_k := 1.0) -> float:
	return CORE_COLD + CORE_HEAT * heat * clampf(km * size_k / MELT_KM, 0.0, 1.0)


# Что вещество даёт планетезимали и как она плавится. Эффекты складываются с навыками.
const PLANET_MATERIAL := {
	"metal": {"effects": {"qstar": 0.25}, "text": "металл: прочность +25%", "melt": "огромное железное ядро"},
	"silicate": {"effects": {"heal": 0.15}, "text": "камень: обломки возвращаются +15%", "melt": "базальтовая кора, как у Весты"},
	"ice": {"effects": {"hill": 0.1}, "text": "лёд лёгкий: сфера Хилла +10%", "melt": "подлёдный океан, как у Цереры"},
	"carbon": {"effects": {"calm": 0.1}, "text": "углерод гасит удары: рой остывает на 10% быстрее", "melt": "вода в порах и органика"},
	"chondrite": {"effects": {"qstar": 0.08, "heal": 0.05, "calm": 0.04}, "text": "смесь: понемногу всего", "melt": "слоистое тело"},
	"titan": {"effects": {"hill": 0.06, "calm": 0.06}, "text": "лёд с углеродом: сфера Хилла +6%, рой остывает на 6% быстрее", "melt": "метан и вода под коркой льда"},
	"venus": {"effects": {"heal": 0.1, "calm": 0.05}, "text": "камень с углеродом: обломки возвращаются +10%, рой остывает на 5% быстрее", "melt": "углекислый газ уходит из пород"},
}

# Что вещество даёт зародышу. Расплавленное тело (а зародыш почти всегда расплавлен)
# получает вдвое: в итоге лёд +50% к росту от гальки, камень +16% массы соседа и т. д.
const EMBRYO_MATERIAL := {
	"ice": {"effects": {"embryo_feed": 0.25}, "text": "лёд: галька липнет к холодному телу, рост от гальки +25%"},
	"silicate": {"effects": {"merge_keep": 0.08}, "text": "камень: при слиянии в тебе остаётся на 8% больше массы соседа"},
	"metal": {"effects": {"rival_pull": 0.15, "qstar": 0.1}, "text": "металл: тяжёлое тело тянет соседей на 15% сильнее, прочность +10%"},
	"carbon": {"effects": {"hill": 0.1, "embryo_feed": 0.1}, "text": "углерод: липкая органика ловит гальку, сфера Хилла +10%, рост от гальки +10%"},
	"chondrite": {"effects": {"merge_keep": 0.04, "embryo_feed": 0.1}, "text": "смесь: понемногу всего"},
	"titan": {"effects": {"embryo_feed": 0.18, "hill": 0.05}, "text": "лёд с углеродом: рост от гальки +18%, сфера Хилла +5%"},
	"venus": {"effects": {"merge_keep": 0.05, "hill": 0.05, "embryo_feed": 0.05}, "text": "камень с углеродом: +5% массы соседа, сфера Хилла +5%, рост от гальки +5%"},
}


## Бонус вещества этому этапу: зародышу свой, планетезимали свой.
static func stage_material(type: String, embryo: bool) -> Dictionary:
	var key := planet_type(type)
	return EMBRYO_MATERIAL[key] if embryo else PLANET_MATERIAL[key]


# Путь после планетезимали: решает состав тела.
const EMBRYO_PATHS := {
	"ice": {"name": "Ледяное ядро", "desc": "галечная аккреция до ~10 масс Земли, потом лавина газа: газовый гигант"},
	"silicate": {"name": "Каменный зародыш", "desc": "гигантские столкновения: землеподобная планета, может быть, со своей Луной"},
	"metal": {"name": "Железный зародыш", "desc": "огромное ядро: железный мир, как Меркурий"},
	"carbon": {"name": "Тёмный зародыш", "desc": "вода и органика: тёмный мир или планета-океан"},
}


## Путь по составу: смесь выбирает по месту — за снеговой линией ледяное ядро.
## Тип тела для бонусов планетезимали: несложившийся состав считается смесью.
## Переходное тело идёт по ведущему материалу.
static func planet_type(type: String) -> String:
	if PLANET_MATERIAL.has(type):
		return type
	if type == "neutral":
		return lead_material(GameState.materials)
	return "chondrite"


static func embryo_path(type: String, distance: float) -> String:
	if EMBRYO_PATHS.has(type):
		return type
	if type == "titan":
		return "ice"
	if type == "venus":
		return "silicate"
	return "ice" if distance > SNOW_LINE else "silicate"


# --- Этап «Зародыш планеты» ---
# Кормовая полоса выедена: дальше растут гигантскими ударами о соседей-зародышей
# и галечной аккрецией (за снеговой линией её втрое больше). Газ диска живёт
# несколько миллионов лет, в игре GAS_TIME секунд. Кто к его концу набрал
# ~10 масс Земли, тот втягивает газ лавиной и становится гигантом; кто не успел —
# остаётся каменной планетой.
const EARTH_KM := 6371.0
const GIANT_EARTHS := 10.0   # критическая масса ядра: газ падает лавиной
const SUPER_EARTHS := 1.0    # от массы Земли — суперземля, ей дают второй шанс
const GAS_TIME := 900.0
# --- Этап «Газовый гигант» ---
# Ядро в 10 масс Земли тянет газ лавиной. Газ течёт к тебе из кормовой зоны,
# ты выедаешь в диске щель и тянешься к её краям, пока диск не рассеется.
# Масса в массах Земли, расстояния — в тех же единицах, что и диск.
const GIANT_STAGE := 5
const GIANT_GAS_TIME := 540.0
const GIANT_ACC := 0.45          # скорость аккреции газа, M⊕/с при полной плотности
const GIANT_EAT := 0.004         # сколько плотности уносит каждая масса Земли
const GIANT_TORQUE := 0.3        # приливы гиганта расталкивают газ к краям щели
const GIANT_VISC := 0.25         # вязкость: газ медленно затекает обратно в щель
const GIANT_DISK := Vector2(700.0, 14000.0)  # изнутри диск срезан полем звезды
const GIANT_BINS := 200
const GIANT_SPEED := 400.0       # радиальная скорость гиганта в 10 M⊕
const GIANT_MIGRATE := 25.0      # миграция II типа к звезде при полной плотности
const GIANT_VALUE := 60000.0    # звёздной пыли за массу Земли газа
const SUPER_JUPITER := 1000.0
const BROWN_DWARF := 4134.0      # 13 масс Юпитера: загорается дейтерий
const HOT_ORBIT := 3600.0        # ближе — горячий юпитер
# Звезда на этапе гиганта: в 5–6 раз шире Юпитера и в 11 раз шире ядра
# в 10 масс Земли (у Солнца — в 10 раз шире Юпитера; диск в игре сжат).
const GIANT_STAR_R := 2200.0
const GIANT_ORBIT_MIN := 2900.0  # ближе нельзя: прилив звезды и её корона
const JUPITER_EARTHS := 318.0


## Чем кончается этап гиганта: масса, орбита и ядро.
static func giant_final(flavor: String, earths: float, r: float) -> String:
	if earths >= BROWN_DWARF:
		return "brown_dwarf"
	if earths >= SUPER_JUPITER:
		return "super_jupiter"
	if r < HOT_ORBIT:
		return "giant_hot"
	return "giant_cold" if flavor == "giant_hot" else flavor


## Радиус гиганта в единицах диска: оболочка почти не растёт с массой.
static func giant_body_r(earths: float) -> float:
	return 200.0 * pow(maxf(earths, 1.0) / 10.0, 0.2)


# --- Этап «Молодая планета» ---
# Масса Земли набрана, газ уходит. Сотни миллионов лет поздней бомбардировки:
# кометы с окраин несут воду, недра выдыхают атмосферу, звёздный ветер её
# сдувает, если нет магнитного поля. Температуру решают орбита и парник.
# У каждого состава своя игра: сухое железо зовёт кометы, океанский мир
# выпаривает лишнюю воду, углерод и «Венера» бегут от парника, Титан мёрзнет.
const YOUNG_STAGE := 5          # тот же уровень, что и гигант: вторая ветка
const YOUNG_TIME := 240.0
const YOUNG_DISK := Vector2(1400.0, 13000.0)
const YOUNG_SPEED := 300.0
const YOUNG_TEQ := 265.0        # K: равновесная температура на 1 а.е. без атмосферы
const YOUNG_GH := 38.0          # K парника на ln(1 + бар)
const YOUNG_STRIP := 0.006      # доля атмосферы, что звёздный ветер сдувает за секунду на 1 а.е. без поля
const YOUNG_COMET := 0.03       # воды (в океанах Земли) с одной кометы
const YOUNG_VALUE := 30000.0    # звёздной пыли за удар
const YOUNG_LIFE := Vector2(273.0, 335.0)  # K: жидкая вода и мягкий климат
const YOUNG_WATER := Vector2(0.5, 2.5) 
const YOUNG_ATMO_MAX := 5.0       # бар: толще — жара под одеялом, жизни тяжело    # океанов Земли: есть море и есть суша
# out — выдох атмосферы недрами (бар/с в начале), gh — сила парника,
# speed — подвижность орбиты, field — добавка к полю, chondrules — хондр с удара камня.
const YOUNG_TYPES := {
	"silicate": {"out": 0.006, "gh": 1.0, "speed": 1.0, "field": 0.0, "chondrules": 1, "atmo": Color(0.55, 0.75, 1.0),
		"goal": "землеподобный мир: возьми воду у комет, тепло у звезды, а поле ядра удержит небо"},
	"metal": {"out": 0.0015, "gh": 1.0, "speed": 0.75, "field": 0.4, "chondrules": 1, "atmo": Color(0.6, 0.72, 0.95),
		"goal": "сухое железо: поле удержит любое небо, но воду и воздух придётся звать с холодных окраин"},
	"ice": {"out": 0.003, "gh": 1.0, "speed": 1.0, "field": 0.0, "chondrules": 1, "atmo": Color(0.6, 0.8, 1.0),
		"goal": "океан без берегов: чтобы проступила суша, выпари лишнюю воду у звезды и не сорвись в парник"},
	"carbon": {"out": 0.03, "gh": 1.6, "speed": 1.0, "field": 0.0, "chondrules": 1, "atmo": Color(0.85, 0.6, 0.38),
		"goal": "углистая дымка греет вдвое: держись дальше от звезды, иначе станешь парником; в холоде — Титан"},
	"chondrite": {"out": 0.01, "gh": 1.1, "speed": 1.0, "field": 0.0, "chondrules": 2, "atmo": Color(0.6, 0.75, 0.95),
		"goal": "смесь всего понемногу: любой путь открыт, а удары камней дают вдвое больше хондр"},
	"titan": {"out": 0.012, "gh": 1.3, "speed": 1.0, "field": 0.0, "chondrules": 1, "atmo": Color(0.98, 0.62, 0.28),
		"goal": "лёд и метан: в холоде за снеговой линией останешься Титаном, у тепла есть шанс на живой мир"},
	"venus": {"out": 0.035, "gh": 1.6, "speed": 1.0, "field": 0.0, "chondrules": 1, "atmo": Color(1.0, 0.87, 0.55),
		"goal": "камень выдыхает углекислый газ: парник неизбежен, если не уйти от звезды и не набрать воды"},
}


static func young_params(type: String) -> Dictionary:
	return YOUNG_TYPES.get(type, YOUNG_TYPES["silicate"])


## Температура поверхности, K: орбита, парник и пар над горячим океаном.
static func young_temp(r: float, atmo: float, water: float, gh: float) -> float:
	var t := YOUNG_TEQ * pow(AU_UNITS / maxf(r, 100.0), 0.5) + YOUNG_GH * gh * log(1.0 + atmo)
	# Тёплый океан парит: пар тоже держит тепло, и парник может сорваться.
	return t + 30.0 * minf(water, 2.0) * smoothstep(300.0, 373.0, t)


## Орбита, где при данном парнике будет температура t_k (для зоны жизни на карте).
static func young_orbit_for(t_k: float, greenhouse: float) -> float:
	var teq := maxf(t_k - greenhouse, 20.0)
	return AU_UNITS * pow(YOUNG_TEQ / teq, 2.0)


## Чем кончится молодая планета: base — судьба по составу, дальше решают
## температура, вода и атмосфера.
static func young_final(type: String, base: String, water: float, atmo: float, t_k: float) -> String:
	if t_k > 373.0 and atmo > 3.0:
		return "planet_venus"
	if t_k >= YOUNG_LIFE.x and t_k <= YOUNG_LIFE.y and water >= YOUNG_WATER.x and water <= YOUNG_WATER.y and atmo >= 0.3 and atmo <= YOUNG_ATMO_MAX:
		return "planet_living"
	if water > YOUNG_WATER.y and t_k >= YOUNG_LIFE.x:
		return "planet_ocean"
	if t_k < 210.0 and atmo >= 0.5 and type in ["titan", "carbon", "ice"]:
		return "planet_titan"
	if base == "planet_living":
		return "planet_rock"  # жизнь решает этап: не вышло — каменный мир
	return base


const PLANET_ROUTE_GROWTH := 0.5  # путь планеты: масса прибывает вдвое медленнее
const EMBRYO_SWARM := 0.25   # рой планетезималей выеден: мелочь вокруг кормит вчетверо хуже
const EMBRYO_FLOW := 0.9     # галька, дрейфующая с газом, — главная пища за снеговой линией
const EMBRYO_FLOW_VALUE := 4.0  # и звёздной пыли она даёт больше мелочи роя
const EMBRYO_FLOW_OUTER := 1.3  # за снеговой линией галька крупнее и липнет ко льду: масса и навыки гальки сильнее
const MAGMA_IMPACTS := 2     # гигантских ударов, чтобы хондрит расплавился в магматический океан
const IMPACT_REL := 0.2      # гигантский удар — сосед хотя бы в пятую часть твоей массы
const MOON_SLANT := 0.55     # косой удар (доля касательной скорости), после которого собирается луна
const MOON_BONUS := 0.1      # луна стабилизирует ось: +10% к ценности добычи
# Миграция I типа: зародыш толкает газ, газ толкает его к звезде. Растёт с массой,
# пропадает вместе с газом. В долях твоей предельной скорости при массе Земли.
const MIGRATE := 0.09
const SECOND_CHANCE_TIME := 75.0  # секунд, чтобы суперземля нырнула в молодого гиганта
const LEGACY_BONUS := 0.1    # каждое очко наследия: +10% звёздной пыли в следующих забегах


## Вид поверхности зародыша (embryo.gdshader): 0 камень, 1 железо, 2 углерод,
## 3 лёд, 4 слоистое — по типу тела.
const EMBRYO_STYLE := {"silicate": 0, "metal": 1, "carbon": 2, "ice": 3, "chondrite": 4, "titan": 2, "venus": 0}
# Цвет дымки по виду: азот и пар, металлическая пыль, рыжий смог, водяной пар, смесь.
const EMBRYO_ATMO := [Color(0.55, 0.75, 1.0), Color(0.85, 0.7, 0.5), Color(0.95, 0.6, 0.35), Color(0.6, 0.85, 1.0), Color(0.8, 0.75, 0.95), Color(0.45, 0.72, 1.0)]
# Двойные типы прячутся под густой дымкой своего цвета: рыжий азотный смог
# у Титана, жёлтые облака у парникового мира. [цвет, во сколько раз гуще].
# Третье число — сплошной облачный покров: у парникового мира поверхности не видно.
const DUO_ATMO := {"titan": [Color(0.98, 0.62, 0.28), 1.6, 0.55], "venus": [Color(1.0, 0.87, 0.55), 2.2, 0.92]}
const LIVING_STYLE := 5  # живая планета: океаны, материки, облака
const MAGMA_COOL := 50.0     # секунд остывает магматический океан после гигантского удара


## Что значит доля ядра: металла в теле столько, сколько стекло в центр.
static func core_note(core: float) -> String:
	if core < 0.1:
		return "железа мало: ядро крошечное"
	if core < 0.25:
		return "меньше земного (у Земли 32%)"
	if core < 0.45:
		return "как у Земли (32%)"
	return "огромное, как у Меркурия"


static func embryo_style(type: String) -> int:
	return int(EMBRYO_STYLE.get(type, 4))


## Толщина атмосферы: с ~0.3 массы Земли тело удерживает газ, к ~1.5 дымка густая.
static func embryo_atmo(m: float) -> float:
	return clampf((earth_masses(m) - 0.3) / 1.2, 0.0, 1.0)


## Насколько тело скруглилось собственной гравитацией: с ~300 км начинает,
## к ~2000 км почти шар (как Веста бугристая, а Церера уже круглая).
static func roundness(m: float) -> float:
	return clampf((planet_km(m) - 300.0) / 1700.0, 0.0, 1.0)


## Масса в массах Земли: тело в 6371 км — одна Земля (масса растёт как куб размера).
static func earth_masses(m: float) -> float:
	return pow(planet_km(m) / EARTH_KM, 3.0)


## Масса тела в игровых единицах, которое весит e масс Земли.
static func mass_for_earths(e: float) -> float:
	return EARTH_KM * pow(e, 1.0 / 3.0) * 100000.0 * 30.0


# --- Этап «Облако»: путь к звезде ---
# Коричневый карлик или супер-Юпитер выброшен из своей системы и падает в
# молекулярное облако, колыбель звёзд. Газ облака лежит волокнами, в узлах
# гуще всего. Масса растёт в логарифме: чем ты больше, тем больше газа тянешь
# (аккреция Бонди), а быстрый полёт её срывает. На CLOUD_IGNITE массах Юпитера
# загорается водород, дальше ты молодая звезда и тянешь газ, пока облако живо.
# Масса к концу решает, какой звездой ты станешь.
const CLOUD_STAGE := 6
const CLOUD_TIME := 480.0         # секунд, пока облако не рассеется
const CLOUD_N := 96               # клеток сетки газа по стороне
const CLOUD_CELL := 250.0         # мировых единиц в клетке
const CLOUD_K := 0.0095           # прирост ln M в секунду при плотности 1
const CLOUD_EAT := 0.05           # доля газа клетки, что ты выпиваешь в секунду (при 13 Mj)
const CLOUD_SPEED := 760.0        # скорость протозвезды
const CLOUD_FRONT_SPEED := 38.0   # скорость фронта ультрафиолета, ед/с
const CLOUD_UV_LOSS := 0.012      # доля массы, что выпаривает ультрафиолет в секунду
const CLOUD_VALUE := 2.0e7        # звёздной пыли за массу Юпитера газа
const SUN_JUPITERS := 1048.0      # масс Юпитера в массе Солнца
const CLOUD_SN_SPEED := 260.0     # скорость ударной волны сверхновой
# Классы звёзд по массе (в массах Солнца): верхние границы.
const STAR_CLASSES := [
	["star_red", 0.45], ["star_sun", 2.0], ["star_white", 8.0], ["star_blue", 25.0], ["star_titan", 1.0e9],
]
# Что состав даёт облаку и звезде. ignite — масс Юпитера до зажигания водорода
# (металлы и сажа делают недра непрозрачными: зажигание раньше; чистый лёд —
# позже); acc — общий множитель аккреции; cold — бонус в холодных плотных узлах;
# reach — радиус захвата (поле металла собирает газ воронкой); ion — доля
# ионизованного газа, что всё равно можно тянуть; uv — как сильно выпаривает
# ультрафиолет (сажа и пыль заслоняют); merge — сколько массы соседа остаётся
# в тебе; speed — подвижность; heat — «парниковый кокон» Венеры: рост падает
# к зажиганию; cocoon — цвет пылевого кокона и диска; tint — оттенок звезды.
const CLOUD_TYPES := {
	"silicate": {"ignite": 80.0, "acc": 1.0, "cold": 0.0, "reach": 1.0, "ion": 0.0, "uv": 0.75, "merge": 0.75,
		"speed": 1.0, "heat": 0.0, "shock": 1.5, "cocoon": Color(0.78, 0.6, 0.44), "tint": Color(1.0, 0.96, 0.9),
		"goal": "силикатная пыль кокона гасит ультрафиолет, а ударная волна сверхновой для тебя вдвое щедрее",
		"chem": "Силикатная пыль в ветре: спокойная и долгая для своего класса."},
	"metal": {"ignite": 75.0, "acc": 1.0, "cold": 0.0, "reach": 1.35, "ion": 0.35, "uv": 0.9, "merge": 0.6,
		"speed": 0.85, "heat": 0.0, "shock": 1.0, "cocoon": Color(0.8, 0.66, 0.52), "tint": Color(1.0, 0.86, 0.66),
		"goal": "железо делает недра непрозрачными: зажжёшься раньше всех, а поле тянет газ воронкой даже из ионизованной зоны",
		"chem": "Богата металлами: плотнее и оранжевее соседок своего класса, с сильным полем. Путь к магнитару."},
	"ice": {"ignite": 85.0, "acc": 1.0, "cold": 0.45, "reach": 1.0, "ion": 0.0, "uv": 1.5, "merge": 0.6,
		"speed": 1.1, "heat": 0.0, "shock": 1.0, "cocoon": Color(0.72, 0.84, 0.95), "tint": Color(0.86, 0.92, 1.0),
		"goal": "холодный газ липнет к ледяному телу: в плотных узлах растёшь почти вдвое быстрее, но ультрафиолет тебя выпаривает",
		"chem": "Много кислорода и воды: голубее соседок своего класса, в ветре водяные мазеры."},
	"carbon": {"ignite": 79.0, "acc": 1.15, "cold": 0.0, "reach": 1.0, "ion": 0.0, "uv": 0.5, "merge": 0.6,
		"speed": 1.0, "heat": 0.0, "shock": 1.0, "cocoon": Color(0.42, 0.33, 0.28), "tint": Color(1.0, 0.82, 0.64),
		"goal": "сажа излучает тепло: газ остывает и падает быстрее, а тёмный кокон заслоняет от ультрафиолета",
		"chem": "Углеродная: краснее соседок своего класса, в старости окутается сажей, а умрёт алмазом."},
	"chondrite": {"ignite": 80.0, "acc": 1.0, "cold": 0.1, "reach": 1.05, "ion": 0.0, "uv": 1.0, "merge": 1.0,
		"speed": 1.0, "heat": 0.0, "shock": 1.0, "cocoon": Color(0.7, 0.62, 0.58), "tint": Color(1.0, 0.94, 0.84),
		"goal": "смесь всего понемногу: сливаешься с соседями без потерь, и они чаще приходят к тебе",
		"chem": "Эталонное солнце: все пути открыты."},
	"titan": {"ignite": 83.0, "acc": 1.05, "cold": 0.25, "reach": 1.0, "ion": 0.0, "uv": 0.7, "merge": 0.6,
		"speed": 0.9, "heat": 0.0, "shock": 1.0, "cocoon": Color(0.9, 0.6, 0.32), "tint": Color(1.0, 0.9, 0.78),
		"goal": "лёд и сажа: холодные узлы кормят, рыжая метановая дымка прикрывает от ультрафиолета, но ты тяжёл на подъём",
		"chem": "Двойственная: азотно-метановая дымка в ветре, цвет меняется с фазой."},
	"venus": {"ignite": 76.0, "acc": 1.2, "cold": 0.0, "reach": 1.0, "ion": 0.0, "uv": 1.0, "merge": 0.6,
		"speed": 1.0, "heat": 0.35, "shock": 1.0, "cocoon": Color(0.95, 0.82, 0.52), "tint": Color(1.0, 0.92, 0.72),
		"goal": "парниковый кокон держит тепло: растёшь быстро и зажигаешься рано, но к зажиганию газ всё хуже падает в горячий кокон",
		"chem": "Мутная от сажи: горит ярче соседок своего класса и живёт короче."},
}


static func cloud_params(type: String, neutral := false) -> Dictionary:
	var p: Dictionary = CLOUD_TYPES.get(type, CLOUD_TYPES["chondrite"]).duplicate()
	if neutral and type != "chondrite":
		# Переходное тело: половина механики лидера, половина смеси.
		var c: Dictionary = CLOUD_TYPES["chondrite"]
		for k in ["ignite", "acc", "cold", "reach", "ion", "uv", "merge", "speed", "heat", "shock"]:
			p[k] = lerpf(float(p[k]), float(c[k]), 0.5)
		p["goal"] = "переходное тело: половина особенностей ведущего вещества. " + str(p["goal"])
	return p


## Каким классом звезды станет масса (в массах Юпитера). Без зажигания —
## несостоявшаяся звезда.
static func star_class(mj: float, lit: bool) -> String:
	if not lit:
		return "star_failed"
	var ms := mj / SUN_JUPITERS
	for c in STAR_CLASSES:
		if ms < float(c[1]):
			return str(c[0])
	return "star_titan"


## Порог следующего класса, в массах Юпитера (для подсказки «до … нужно»).
static func star_next(mj: float) -> float:
	var ms := mj / SUN_JUPITERS
	for c in STAR_CLASSES:
		if ms < float(c[1]):
			return float(c[1]) * SUN_JUPITERS
	return -1.0


## «1,3 массы Солнца» или «45 масс Юпитера».
static func format_star_mass(mj: float) -> String:
	if mj < 0.3 * SUN_JUPITERS:
		return "%d масс Юпитера" % roundi(mj)
	var ms := mj / SUN_JUPITERS
	return (String.num(ms, 2) if ms < 10.0 else str(roundi(ms))).replace(".", ",") + " массы Солнца"


# Цвет звезды по массе: красный карлик — солнце — белая — голубая.
static func star_color(mj: float) -> Color:
	var ms := log(maxf(mj / SUN_JUPITERS, 0.05)) / log(10.0)  # −1.3 … 1.7
	var stops := [[-1.3, Color(1.0, 0.42, 0.2)], [-0.4, Color(1.0, 0.62, 0.36)], [0.0, Color(1.0, 0.9, 0.72)],
		[0.5, Color(0.92, 0.94, 1.0)], [1.0, Color(0.7, 0.8, 1.0)], [1.7, Color(0.56, 0.68, 1.0)]]
	for i in stops.size() - 1:
		var a: Array = stops[i]
		var b: Array = stops[i + 1]
		if ms <= float(b[0]):
			return (a[1] as Color).lerp(b[1], clampf((ms - float(a[0])) / (float(b[0]) - float(a[0])), 0.0, 1.0))
	return stops.back()[1]


## «0.42 Земли»: масса в массах Земли, коротко.
static func format_earths(m: float) -> String:
	var e := earth_masses(m)
	if e < 0.01:
		return "%.3f Земли" % e
	if e < 1.0:
		return "%.2f Земли" % e
	return "%.1f Земли" % e


# Концовки. legacy — очки наследия за неё; каждое даёт LEGACY_BONUS в следующих забегах.
const ENDINGS := {
	"giant_cold": {"name": "Газовый гигант", "legacy": 6,
		"desc": "Ядро в десять масс Земли за снеговой линией втянуло газ диска лавиной. Так родился Юпитер."},
	"giant_ice": {"name": "Ледяной гигант", "legacy": 6,
		"desc": "Ядро изо льда утонуло под толщей воды, аммиака и метана. Метан окрасил тебя в голубой цвет, как Нептун."},
	"giant_dark": {"name": "Тёмный гигант", "legacy": 6,
		"desc": "Углистое ядро наполнило атмосферу метаном и сажей: бурые полосы почти чёрные, а в глубине идёт алмазный дождь."},
	"giant_dense": {"name": "Плотный гигант", "legacy": 6,
		"desc": "Тяжёлое железное ядро сжало газ: ты меньше Юпитера, но намного плотнее. Такие гиганты находят у других звёзд."},
	"giant_hot": {"name": "Горячий юпитер", "legacy": 5,
		"desc": "Газ диска утащил тебя к самой звезде. Ты кружишь у неё за несколько дней, и твои облака раскалены докрасна."},
	"super_jupiter": {"name": "Супер-Юпитер", "legacy": 9,
		"desc": "Больше тысячи масс Земли: ты выпил газ с огромной полосы диска. Твоя гравитация уже раскачивает орбиты всех соседей."},
	"brown_dwarf": {"name": "Коричневый карлик", "legacy": 12,
		"desc": "Тринадцать масс Юпитера: в недрах загорелся дейтерий. Ты уже не планета, но ещё не звезда."},
	"giant_core": {"name": "Сердце гиганта", "legacy": 4,
		"desc": "Газ ушёл, но ты нырнул в молодого гиганта и стал его ядром. Его атмосфера теперь твоя."},
	"super_earth": {"name": "Суперземля", "legacy": 3,
		"desc": "Тяжелее Земли, но газ диска рассеялся раньше, чем ты дорос до гиганта. Такие миры — самые частые в Галактике."},
	"super_iron": {"name": "Железная суперземля", "legacy": 3,
		"desc": "Несколько масс Земли, и почти всё — железо: гравитация сдавила ядро так, что тяжелее тебя по плотности почти ничего нет. Супер-Меркурий."},
	"super_neptune": {"name": "Мини-Нептун", "legacy": 3,
		"desc": "Ледяное ядро успело схватить немного водорода, прежде чем газ ушёл. Под тонкой газовой шубой — горячий океан под давлением. Самые частые планеты Галактики похожи на тебя."},
	"super_diamond": {"name": "Алмазная суперземля", "legacy": 3,
		"desc": "Углерода в тебе так много, а давление так велико, что мантия стала алмазной. Такую планету ищут у звезды 55 Рака."},
	"super_titan": {"name": "Метановая суперземля", "legacy": 3,
		"desc": "Лёд с углеродом в теле в несколько Земель: густая рыжая дымка, метановые моря и толстая ледяная кора над глубоким океаном."},
	"super_venus": {"name": "Супер-Венера", "legacy": 3,
		"desc": "Камень с углеродом выдохнул столько углекислого газа, что тяжёлая планета утонула в собственной атмосфере. Под облаками плавится свинец."},
	"planet_rock": {"name": "Каменный мир", "legacy": 2,
		"desc": "Кора, мантия и железное ядро. Газ рассеялся, и ты остался землеподобной планетой."},
	"planet_living": {"name": "Живая планета", "legacy": 4,
		"desc": "Каменный мир с железным ядром, магнитным полем и водой. Самая редкая концовка: здесь может начаться жизнь."},
	"planet_iron": {"name": "Железный мир", "legacy": 3,
		"desc": "Огромное железное ядро под тонкой корой, как у Меркурия. Его магнитное поле — самое сильное среди каменных планет."},
	"planet_dark": {"name": "Тёмный углистый мир", "legacy": 3,
		"desc": "Чёрная поверхность, богатая органикой, а глубоко внутри давление сжимает углерод в алмаз."},
	"planet_ocean": {"name": "Океанский мир", "legacy": 3,
		"desc": "Лёд растаял в глобальный океан глубиной в сотни километров. Ни одного материка."},
	"planet_layered": {"name": "Слоистый мир", "legacy": 3,
		"desc": "Пёстрая мантия слоями поверх железного ядра: ты собрал всего понемногу и расплавился, не выбрав одно."},
	"planet_titan": {"name": "Мир-Титан", "legacy": 3,
		"desc": "Лёд пополам с углеродом: под рыжей дымкой азота текут метановые реки и плещутся озёра, а под коркой льда прячется водный океан."},
	"planet_venus": {"name": "Парниковый мир", "legacy": 3,
		"desc": "Углерод в камне вышел углекислым газом и запер тепло. Под жёлтыми облаками жарче, чем в печи, как на Венере."},
	"star_failed": {"name": "Несостоявшаяся звезда", "legacy": 10,
		"desc": "Облако рассеялось раньше, чем в недрах загорелся водород. Ты самый тяжёлый коричневый карлик в округе: тлеешь дейтерием и медленно остываешь миллиарды лет."},
	"star_red": {"name": "Красный карлик", "legacy": 14,
		"desc": "Водород загорелся! Ты маленькая тусклая звезда, как Проксима Центавра. Будешь гореть триллионы лет, дольше, чем существует Вселенная."},
	"star_sun": {"name": "Звезда, как Солнце", "legacy": 18,
		"desc": "Жёлтая звезда главной последовательности. Миллиарды лет ровного света: у таких звёзд бывают живые планеты."},
	"star_white": {"name": "Белая звезда", "legacy": 22,
		"desc": "Горячая и яркая, как Сириус или Вега. Ты сжигаешь водород в десятки раз быстрее Солнца, а в конце станешь белым карликом."},
	"star_blue": {"name": "Голубой гигант", "legacy": 28,
		"desc": "Массивная звезда, как Ригель. Твой ультрафиолет сам выжигает облако вокруг. Жизнь короткая, и кончится она сверхновой."},
	"star_titan": {"name": "Голубой сверхгигант", "legacy": 35,
		"desc": "Больше двадцати пяти масс Солнца: одна из самых массивных звёзд облака. Твоё ядро однажды схлопнется в чёрную дыру."},
	"dwarf_planet": {"name": "Карликовая планета", "legacy": 1,
		"desc": "Газ ушёл раньше, чем ты дорос до массы Земли. Орбиту ты так и не расчистил, и по правилам астрономов ты уже не планета, как Церера и Плутон."},
}

# Карта развилок для игрока: что решает судьбу на каждом этапе.
const FORK_MAP := [
	["Пылинка и галька", "где кормишься, то и ешь: у звезды камень и металл, за снеговой линией лёд и углерод"],
	["Планетезималь", "алюминий греет недра первые минуты: каменное тело в 12–20 км расплавится, и состав застынет навсегда; лёд и углерод уносят тепло водой — ледяное тело останется хондритом"],
	["Зародыш планеты", "выбор пути: гонка с газом диска до 10 масс Земли — газовый гигант, путь к звезде; или спокойный рост до массы Земли — каменная планета"],
	["Каменная планета", "тип решает застывший состав: железный, каменный, тёмный, океанский, слоистый; переходное тело со льдом и углеродом — Мир-Титан, с камнем и углеродом — парниковый мир"],
	["Молодая планета", "поздняя бомбардировка: орбита решает климат, кометы с окраин несут воду, поле ядра держит небо; тепло, вода и атмосфера в меру — живая планета, перегрев — парник, лишняя вода — океан, холод с метаном — Титан"],
	["Газовый гигант", "газ течёт к тебе из кормовой зоны: выедаешь щель и тянешься к её краям; масса к уходу газа решает, станешь ли ты Юпитером, супер-Юпитером или коричневым карликом; не дай газу утащить тебя к звезде — станешь горячим юпитером; железное ядро даёт магнитное поле, а поле удерживает луны"],
	["Облако", "коричневый карлик или супер-Юпитер падает в молекулярное облако: держись узлов газа, ешь соседей поменьше, уходи от фронта ультрафиолета, лови ударную волну сверхновой; на ~80 массах Юпитера загорается водород, а масса к концу облака решает, какой звездой станешь; состав двигает порог зажигания"],
	["Дальше", "жизнь звезды → её смерть → чёрная дыра: эти этапы ещё строятся"],
]


## Суперземля, если газ ушёл на 1–10 массах Земли: решает состав.
static func super_earth_ending(type: String) -> String:
	match type:
		"metal":
			return "super_iron"
		"ice":
			return "super_neptune"
		"carbon":
			return "super_diamond"
		"titan":
			return "super_titan"
		"venus":
			return "super_venus"
	return "super_earth"


## Каким гигантом станет ядро: железное — плотным где угодно; у звезды — горячим;
## за снеговой линией лёд даёт ледяного гиганта, углерод — тёмного, остальное — Юпитер.
static func giant_ending(type: String, cold: bool) -> String:
	if type == "metal":
		return "giant_dense"
	if not cold:
		return "giant_hot"
	match type:
		"ice", "titan":
			return "giant_ice"
		"carbon":
			return "giant_dark"
	return "giant_cold"


# Цвета гиганта по концовке: светлые полосы, тёмные полосы, шторм.
const GIANT_LOOK := {
	"giant_cold": [Color(0.95, 0.86, 0.68), Color(0.66, 0.42, 0.26), Color(0.82, 0.38, 0.22)],
	"giant_hot": [Color(1.0, 0.72, 0.46), Color(0.62, 0.22, 0.12), Color(1.0, 0.86, 0.5)],
	"giant_ice": [Color(0.62, 0.86, 0.96), Color(0.22, 0.46, 0.78), Color(0.12, 0.22, 0.5)],
	"giant_dark": [Color(0.5, 0.38, 0.28), Color(0.16, 0.11, 0.08), Color(0.78, 0.46, 0.2)],
	"giant_dense": [Color(0.8, 0.78, 0.74), Color(0.44, 0.4, 0.38), Color(0.66, 0.5, 0.36)],
	"super_jupiter": [Color(0.98, 0.8, 0.6), Color(0.7, 0.36, 0.22), Color(0.95, 0.5, 0.3)],
	"brown_dwarf": [Color(0.86, 0.42, 0.3), Color(0.38, 0.12, 0.1), Color(1.0, 0.62, 0.3)],
}


## Какой концовкой кончается каменная ветка: решает застывший состав и вода.
static func planet_ending(type: String, shares: Dictionary, core: float, water := 0.0) -> String:
	match type:
		"metal":
			return "planet_iron"
		"carbon":
			return "planet_dark"
		"ice":
			return "planet_ocean"
		"titan":
			return "planet_titan"
		"venus":
			return "planet_venus"
		"silicate":
			var wet := float(shares.get("ice", 0.0)) + float(shares.get("carbon", 0.0)) * 0.5 + water
			return "planet_living" if core > 0.05 and wet > 0.08 else "planet_rock"
	# Смесь массой с Землю непременно переплавлена ударами и собственным весом.
	return "planet_layered"
