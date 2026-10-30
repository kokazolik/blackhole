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

# Тип тела не даёт сиюминутных бонусов: состав решает, кем тело станет потом.
# Из металлических планетезималей вырастают железные миры, из каменных —
# землеподобные планеты, ледяные за снеговой линией становятся ядрами гигантов.
const BODY_TYPES := {
	"unformed": {"name": "Неоформленное", "desc": "состав ещё не сложился"},
	"neutral": {"name": "Переходное", "desc": "путь ещё не выбран"},
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
	return "neutral"


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
	return "≈ %.1f км" % (cm / 100000.0)


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
}

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
}

# Путь после планетезимали: решает состав тела.
const EMBRYO_PATHS := {
	"ice": {"name": "Ледяное ядро", "desc": "галечная аккреция до ~10 масс Земли, потом лавина газа: газовый гигант"},
	"silicate": {"name": "Каменный зародыш", "desc": "гигантские столкновения: землеподобная планета, может быть, со своей Луной"},
	"metal": {"name": "Железный зародыш", "desc": "огромное ядро: железный мир, как Меркурий"},
	"carbon": {"name": "Тёмный зародыш", "desc": "вода и органика: тёмный мир или планета-океан"},
}


## Путь по составу: смесь выбирает по месту — за снеговой линией ледяное ядро.
## Тип тела для бонусов планетезимали: несложившийся состав считается смесью.
static func planet_type(type: String) -> String:
	return type if PLANET_MATERIAL.has(type) else "chondrite"


static func embryo_path(type: String, distance: float) -> String:
	if EMBRYO_PATHS.has(type):
		return type
	return "ice" if distance > SNOW_LINE else "silicate"
