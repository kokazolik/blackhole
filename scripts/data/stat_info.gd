class_name StatInfo
extends RefCounted
## Как показывать параметры игроку: название, вид числа и этап.
##
## Вид: "x" — множитель к базовому (1,6 — на 60% больше), "xl" — то же, но меньше
## лучше (снос, сколы), "p" — доля в процентах, "m" — «во сколько раз», "n" — целое,
## "b" — есть или нет. Этап: 0 пыль, 1 галька, 2 валун, 3 способности.

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
	"moons": ["Спутники", "n", 3],
	"moon_size": ["Размер спутников", "x", 3],
	"chain_eat": ["Цепное поглощение", "p", 3],
	"pulse": ["Импульс, уровень", "n", 3],
}

const GROUPS := ["Пылинка", "Галька", "Валун", "Способности"]


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
