class_name StatInfo
extends RefCounted
## Как показывать параметры игроку: название, вид числа и этап.
##
## Вид: "x" — множитель к базовому (1,6 — на 60% больше), "xl" — то же, но меньше
## лучше (снос, сколы), "p" — доля в процентах, "m" — «во сколько раз», "n" — целое,
## "b" — есть или нет. Этап: 0 пыль, 1 галька, 2 валун, 3 способности,
## 4 планетезималь и зародыш, 5 газовый гигант, 6 облако.

const INFO := {
	"value": ["Ценность добычи", "x", 0],
	"speed": ["Скорость", "x", 0],
	"gravity": ["Притяжение", "x", 0],
	"reach": ["Радиус притяжения", "x", 0],
	"spawn": ["Пыли вокруг", "x", 0],
	"cluster": ["Скоплений пыли", "x", 0],
	"dust_level": ["Уровень пыли", "n", 0],
	"pebble_value_mul": ["Доход гальки", "x", 1],
	"drift": ["Снос к звезде", "xl", 1],
	"stick": ["Слипание", "x", 1],
	"thrust": ["Тяга", "x", 1],
	"chip": ["Сколы", "xl", 1],
	"grip": ["Прилипает без дуги", "p", 1],
	"pebbles": ["Галек вокруг", "x", 1],
	"combo": ["Серия: за шаг", "p", 1],
	"combo_cap": ["Серия: шагов", "n", 1],
	"geode": ["Шанс жеоды", "p", 1],
	"geode_value": ["Ценность жеоды", "m", 1],
	"swarm": ["Рои галек", "n", 1],
	"pebble_pull": ["Гальки плывут к тебе", "b", 1],
	"affinity_silicate": ["Галек камня", "x", 1],
	"affinity_metal": ["Галек металла", "x", 1],
	"affinity_carbon": ["Галек углерода", "x", 1],
	"affinity_ice": ["Галек льда", "x", 1],
	"glue_silicate": ["Липкость камня", "x", 1],
	"glue_metal": ["Липкость металла", "x", 1],
	"glue_carbon": ["Липкость углерода", "x", 1],
	"glue_ice": ["Липкость льда", "x", 1],
	"mass_silicate": ["Масса с камня", "x", 1],
	"mass_metal": ["Масса с металла", "x", 1],
	"mass_carbon": ["Масса с углерода", "x", 1],
	"mass_ice": ["Масса со льда", "x", 1],
	"value_mul": ["Множитель дохода", "x", 2],
	"accretion": ["Прирост при слипании", "x", 2],
	"self_grav": ["Своя гравитация", "p", 2],
	"grav_focus": ["Разгон притяжением", "x", 2],
	"debris_value": ["Ценность обломков", "x", 2],
	"shadow": ["Ветровая тень", "x", 2],
	"heal": ["Залечивание сколов", "p", 2],
	"drift_mul": ["Множитель сноса", "xl", 2],
	"rubble_pile": ["Куча щебня", "b", 2],
	"collapse": ["Коллапс сгустка", "b", 2],
	"capture": ["Круг захвата", "x", 4],
	"calm": ["Остывание роя", "x", 4],
	"hill": ["Сфера Хилла", "x", 4],
	"qstar": ["Прочность к удару", "x", 4],
	"al_slow": ["Жар алюминия-26", "x", 4],
	"zone": ["Кормовая полоса", "x", 4],
	"sling": ["Гравитационная праща", "x", 4],
	"flow_catch": ["Ловля галечного потока", "x", 4],
	"runaway": ["Убегающий рост", "b", 4],
	"oligarch": ["Своя полоса", "b", 4],
	"iron_core": ["Железное ядро", "b", 4],
	"tidal": ["Приливный разрыв", "b", 3],
	"still": ["Успокоение, уровень", "n", 3],
	"moons": ["Облачка пылевого гало", "n", 3],
	"moon_size": ["Размер гало", "x", 3],
	"chain_eat": ["Цепное поглощение", "p", 3],
	"pulse": ["Волна плотности, уровень", "n", 3],
	"cold_core": ["Порог плавления недр, +K", "n", 3],
	"rival_pull": ["Соседи тянутся к тебе", "x", 4],
	"rival_rate": ["Соседи приходят чаще", "x", 4],
	"merge_keep": ["Масса соседа остаётся", "p", 4],
	"merge_value": ["Пыль за слияние", "x", 4],
	"impact_more": ["Частота гигантских ударов", "x", 4],
	"magma_feed": ["Рост в магме", "p", 4],
	"embryo_feed": ["Рост от гальки", "x", 4],
	"migrate": ["Миграция к звезде", "xl", 4],
	"devour": ["Пожиратель", "b", 4],
	"water": ["Вода комет", "p", 4],
	"core_boost": ["Доля ядра", "p", 4],
	"moon_slant": ["Луна от прямого удара", "p", 4],
	"moon_value": ["Бонус луны к добыче", "p", 4],
	"garden": ["Сад: наследие ×2", "b", 4],
	"giant_acc": ["Аккреция газа", "x", 5],
	"giant_reach": ["Кормовая зона", "x", 5],
	"giant_anchor": ["Тяга сильнее", "p", 5],
	"giant_field": ["Магнитное поле", "p", 5],
	"giant_moons": ["Рождение лун", "x", 5],
	"giant_gas": ["Газ живёт дольше", "p", 5],
	"giant_speed": ["Скорость гиганта", "x", 5],
	"giant_runaway": ["Убегающая аккреция", "b", 5],
	"giant_tidal": ["Прилив рвёт тела", "x", 5],
	"giant_grab": ["Радиус прилива", "x", 5],
	"giant_sling": ["Сила пращи", "x", 5],
	"giant_guard": ["Тяжёлые тянут слабее", "p", 5],
	"giant_moon_grab": ["Луна целиком", "p", 5],
	"giant_soot": ["Пыль за углерод", "x", 5],
	"giant_impact": ["Пыль за удары", "x", 5],
	"giant_merge": ["Слияние гигантов раньше", "p", 5],
	"giant_eat": ["Съедаемый гигант (доля твоей массы)", "p", 5],
	"giant_bodies": ["Тел в диске", "x", 5],
	"cloud_acc": ["Аккреция облака", "x", 6],
	"cloud_reach": ["Захват газа", "x", 6],
	"cloud_shield": ["Защита от ультрафиолета", "p", 6],
	"cloud_speed": ["Скорость протозвезды", "x", 6],
	"cloud_merge": ["Масса соседа", "p", 6],
	"cloud_burst": ["Окно вспышки FU Ориона", "p", 6],
}

const GROUPS := ["Пылинка", "Галька", "Валун", "Способности", "Планетезималь и зародыш", "Газовый гигант", "Облако"]


static func title(key: String) -> String:
	return INFO[key][0] if INFO.has(key) else key


static func kind(key: String) -> String:
	return INFO[key][1] if INFO.has(key) else "x"


static func group(key: String) -> int:
	return INFO[key][2] if INFO.has(key) else 0


## Значение параметра так, как его видит игрок: «1,6», «12%», «×15», «есть».
static func format(key: String, v: float) -> String:
	match kind(key):
		"x", "xl":
			return num(v / float(Skills.BASE_STATS.get(key, 1.0)))
		"p":
			return num(v * 100.0) + "%"
		"m":
			return "×" + num(v)
		"n":
			return str(int(round(v)))
		"b":
			return "есть" if v > 0.0 else "нет"
	return num(v)


## Вклад одного узла: «+30%», «−12%», «+1», «есть».
static func format_delta(key: String, d: float) -> String:
	if key == "dust_level":
		return "до ур. %d" % int(d)
	var sign := "+" if d >= 0.0 else "−"
	match kind(key):
		"x", "xl":
			return sign + num(absf(d) / float(Skills.BASE_STATS.get(key, 1.0)) * 100.0) + "%"
		"p":
			return sign + num(absf(d) * 100.0) + "%"
		"m":
			return sign + num(absf(d))
		"n":
			return sign + str(int(round(absf(d))))
		"b":
			return "есть"
	return sign + num(absf(d))


## Улучшение ли это: у сноса и сколов меньше — лучше.
static func better(key: String, before: float, after: float) -> bool:
	return after < before if kind(key) == "xl" else after > before


## До трёх значащих цифр, запятая вместо точки: 1,6 · 1,75 · 12,5 · 240.
static func num(v: float) -> String:
	var a := absf(v)
	var digits := 0 if a >= 100.0 else (1 if a >= 10.0 else 2)
	var s := String.num(v, digits)
	if "." in s:
		s = s.rstrip("0").rstrip(".")
	return s.replace(".", ",")
