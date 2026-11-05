class_name CollectionData
extends RefCounted
## Коллекция тел: дерево путей от пылинки вниз. Этапы — развилки, концовки —
## листья. Где игрок побывал и кем стал, хранит GameState (stages_seen,
## endings_seen); здесь только устройство дерева и подсказки «как получить».
##
## pos — место в дереве (x вправо, y вниз), parent — откуда ведёт ветка.

const STAGE_NODES := {
	"dust": {"title": "Пылинка", "parent": "", "pos": Vector2(0, 0),
		"desc": "Пылинка в протопланетном диске. С неё начинается каждый путь.",
		"hint": "Начни новую игру."},
	"pebble": {"title": "Галька", "parent": "dust", "pos": Vector2(0, 150),
		"desc": "Пыль слиплась в камешек размером с ладонь. Газ тянет его к звезде.",
		"hint": "Собирай пыль: потяжелеешь — слипнешься в гальку."},
	"boulder": {"title": "Валун", "parent": "pebble", "pos": Vector2(0, 300),
		"desc": "Метровый валун: гальки липнут, но удары откалывают куски.",
		"hint": "Ешь гальку, пока не дорастёшь до метра."},
	"plsim": {"title": "Планетезималь", "parent": "boulder", "pos": Vector2(0, 450),
		"desc": "Тело в километр. Дальше правит гравитация, а алюминий плавит недра.",
		"hint": "Дорасти валуном до километра."},
	"embryo": {"title": "Зародыш планеты", "parent": "plsim", "pos": Vector2(0, 600),
		"desc": "Тело в тысячу километров. Здесь развилка: спокойная планета или гонка с газом.",
		"hint": "Расти планетезималью, пока кормовая полоса не опустеет."},
	"young": {"title": "Молодая планета", "parent": "embryo", "pos": Vector2(-490, 780),
		"desc": "Масса Земли набрана, газ ушёл. Поздняя бомбардировка решает климат.",
		"hint": "На зародыше выбери путь планеты и набери массу Земли до того, как уйдёт газ."},
	"giant": {"title": "Газовый гигант", "parent": "embryo", "pos": Vector2(400, 780),
		"desc": "Ядро в десять масс Земли втянуло газ диска лавиной.",
		"hint": "На зародыше выбери гонку с газом и набери десять масс Земли, пока газ не рассеялся."},
	"cloud": {"title": "Облако", "parent": "giant", "pos": Vector2(725, 780),
		"desc": "Молекулярное облако: здесь коричневый карлик и супер-Юпитер растут в звезду.",
		"hint": "Стань супер-Юпитером или коричневым карликом и уйди в облако."},
	"next": {"title": "Жизнь звезды", "parent": "cloud", "pos": Vector2(725, 1680),
		"desc": "", "hint": "Этот путь ещё строится: жизнь звезды, её смерть и чёрная дыра."},
}

# Концовки: где висят в дереве и как их взять.
const ENDING_NODES := {
	"dwarf_planet": {"parent": "embryo", "pos": Vector2(-85, 780),
		"hint": "Не успей дорасти до массы Земли, пока газ диска не рассеялся."},
	"giant_core": {"parent": "embryo", "pos": Vector2(85, 780),
		"hint": "На гонке с газом не дотяни до десяти масс Земли. Когда газ уйдёт, рядом пройдёт молодой гигант: медленно нырни в него."},
	"super_earth": {"parent": "embryo", "pos": Vector2(-85, 960),
		"hint": "Гонка с газом, но газ ушёл раньше десяти масс Земли, и в гиганта ты не нырнул. Камень или смесь без перевеса."},
	"super_iron": {"parent": "embryo", "pos": Vector2(85, 960),
		"hint": "Как суперземля, но тело больше чем наполовину из металла: кормись у звезды."},
	"super_neptune": {"parent": "embryo", "pos": Vector2(-85, 1140),
		"hint": "Как суперземля, но тело больше чем наполовину изо льда: кормись за снеговой линией."},
	"super_diamond": {"parent": "embryo", "pos": Vector2(85, 1140),
		"hint": "Как суперземля, но тело больше чем наполовину из углерода."},
	"super_titan": {"parent": "embryo", "pos": Vector2(-85, 1320),
		"hint": "Как суперземля, но тело — лёд с углеродом поровну."},
	"super_venus": {"parent": "embryo", "pos": Vector2(85, 1320),
		"hint": "Как суперземля, но тело — камень с углеродом поровну."},
	"planet_rock": {"parent": "young", "pos": Vector2(-575, 960),
		"hint": "Каменное тело на пути планеты, которому не хватило воды, поля или тепла для жизни."},
	"planet_living": {"parent": "young", "pos": Vector2(-405, 960),
		"hint": "Каменный мир с железным ядром. На молодой планете держи климат от 0 до 60 °C, лови кометы ради воды (0,5–2,5 океана Земли) и атмосферу 0,3–5 бар."},
	"planet_iron": {"parent": "young", "pos": Vector2(-575, 1140),
		"hint": "Путь планеты телом больше чем наполовину из металла."},
	"planet_dark": {"parent": "young", "pos": Vector2(-405, 1140),
		"hint": "Путь планеты телом больше чем наполовину из углерода."},
	"planet_ocean": {"parent": "young", "pos": Vector2(-575, 1320),
		"hint": "Путь планеты ледяным телом, или поймай на молодой планете слишком много комет: больше 2,5 океана воды."},
	"planet_layered": {"parent": "young", "pos": Vector2(-405, 1320),
		"hint": "Путь планеты пёстрым телом: хондрит или смесь без перевеса одного вещества."},
	"planet_titan": {"parent": "young", "pos": Vector2(-575, 1500),
		"hint": "Лёд с углеродом на пути планеты. Или ледяное и углеродное тело, замёрзшее на дальней орбите с атмосферой."},
	"planet_venus": {"parent": "young", "pos": Vector2(-405, 1500),
		"hint": "Камень с углеродом на пути планеты. Или любой мир, перегретый у звезды под толстой атмосферой."},
	"giant_cold": {"parent": "giant", "pos": Vector2(315, 960),
		"hint": "Гигант за снеговой линией с каменным или пёстрым ядром: газ ушёл до тысячи масс Земли."},
	"giant_ice": {"parent": "giant", "pos": Vector2(485, 960),
		"hint": "Гигант с ледяным ядром (или лёд с углеродом) за снеговой линией."},
	"giant_dark": {"parent": "giant", "pos": Vector2(315, 1140),
		"hint": "Гигант с углеродным ядром за снеговой линией."},
	"giant_dense": {"parent": "giant", "pos": Vector2(485, 1140),
		"hint": "Гигант с железным ядром: тело больше чем наполовину из металла."},
	"giant_hot": {"parent": "giant", "pos": Vector2(315, 1320),
		"hint": "Пусть газ утащит гиганта к звезде: закончи этап ближе границы горячих юпитеров."},
	"super_jupiter": {"parent": "giant", "pos": Vector2(485, 1320),
		"hint": "Набери гигантом тысячу масс Земли и останься планетой."},
	"giant_swallowed": {"parent": "giant", "pos": Vector2(315, 1500),
		"hint": "Подойди вплотную к гиганту-соседу тяжелее себя: его прилив и общая оболочка проглотят тебя."},
	"giant_eaten_dwarf": {"parent": "giant", "pos": Vector2(485, 1680),
		"hint": "Не уйди с дороги коричневого карлика, когда он проходит сквозь диск."},
	"giant_chthonian": {"parent": "giant", "pos": Vector2(315, 1680),
		"hint": "Пусть сосед тяжелее тебя сорвёт приливом всю газовую оболочку, но уйди от него, прежде чем ядро коснётся его газа."},
	"brown_dwarf": {"parent": "giant", "pos": Vector2(485, 1500),
		"hint": "Набери гигантом тринадцать масс Юпитера: без «Долгого диска» и «Убегающей аккреции» не выйдет."},
	"star_failed": {"parent": "cloud", "pos": Vector2(640, 960),
		"hint": "Уйди в облако, но не дотяни до зажигания водорода (около 80 масс Юпитера)."},
	"star_red": {"parent": "cloud", "pos": Vector2(810, 960),
		"hint": "Зажги водород в облаке и закончи легче половины Солнца."},
	"star_sun": {"parent": "cloud", "pos": Vector2(640, 1140),
		"hint": "Зажги водород и вырасти до массы от половины до двух Солнц."},
	"star_white": {"parent": "cloud", "pos": Vector2(810, 1140),
		"hint": "Звезда от двух до восьми масс Солнца."},
	"star_blue": {"parent": "cloud", "pos": Vector2(640, 1320),
		"hint": "Звезда от восьми до двадцати пяти масс Солнца."},
	"star_titan": {"parent": "cloud", "pos": Vector2(810, 1320),
		"hint": "Больше двадцати пяти масс Солнца: самые жадные звёзды облака."},
}


## Через какие этапы ведёт путь к концовке (для старых сохранений).
static func stages_for(ending: String) -> Array:
	var out := ["dust", "pebble", "boulder", "plsim", "embryo"]
	if not ENDING_NODES.has(ending):
		return out
	var p := str(ENDING_NODES[ending]["parent"])
	while p != "" and p != "embryo":
		out.append(p)
		p = str(STAGE_NODES[p]["parent"])
	return out


static func all_ids() -> Array:
	return STAGE_NODES.keys() + ENDING_NODES.keys()


static func is_stage(id: String) -> bool:
	return STAGE_NODES.has(id)


static func parent_of(id: String) -> String:
	return str(STAGE_NODES[id]["parent"]) if is_stage(id) else str(ENDING_NODES[id]["parent"])


static func pos_of(id: String) -> Vector2:
	return STAGE_NODES[id]["pos"] if is_stage(id) else ENDING_NODES[id]["pos"]


static func title_of(id: String) -> String:
	return str(STAGE_NODES[id]["title"]) if is_stage(id) else str(GameData.ENDINGS[id]["name"])


static func seen(id: String) -> bool:
	if id == "next":
		return false
	return id in GameState.stages_seen if is_stage(id) else id in GameState.endings_seen
