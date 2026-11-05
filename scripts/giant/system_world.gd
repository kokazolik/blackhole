class_name GiantWorld
extends Node2D
## Мир газового гиганта: вся молодая система вокруг тебя.
##
## По орбитам кружат тела, оставшиеся с ранних этапов и выросшие без тебя:
## рои обломков, планетезимали, зародыши, суперземли, мини-нептуны, кометы
## с окраин и соперники-гиганты. Всё течёт по сдвигу диска: внутренние
## обгоняют тебя, внешние отстают.
##
## Что делать с телом, решает его масса относительно твоей:
## - мелочь (до 1/10 твоей массы) — захват: тело ложится на орбиту вокруг
##   тебя и скручивается по спирали;
## - крупное (до 1/1,4) — само падает на тебя, когда подлетаешь (тяготение
##   взаимное), и его можно взять тараном: гигантский удар с разгона. Медленно
##   подошёл — захват, как у мелочи, только спираль дольше;
## - тяжелее — праща (бросает тело) или опасность: тянут к себе, вырывают
##   луны, срывают газ.
## А рвёт ли захваченное тело, решает его плотность, как в жизни. Предел Роша
## у рыхлого и ледяного (кометы, груды обломков, газовая оболочка
## мини-нептуна) — 2,5–2,8 радиуса гиганта, у камня — 1,7, у железа — ниже
## облаков: железное тело не рвётся, а врезается целым. Мини-нептун сначала
## теряет газовую оболочку, потом рвётся или врезается его ядро.
## Соперник, которого ты перерос, сливается с тобой.
## У каждого ядра своё население: лёд — кометы и ледяные миры, плотное —
## железные тела, тёмное — углеродные, горячее — лавовые миры у звезды.

signal body_eaten(b: Dictionary)

const K_DRIFT := 0.12        # темп сдвига тел по орбитам (рад/с на единицу x^-1.5 − 1)
const HILL_W := 0.35         # «время газа» задачи Хилла (как GasParticles.OMEGA)
# Предел Роша в радиусах гиганта по веществу (жидкое тело: 2,44·(ρ_пл/ρ_т)^⅓,
# у Юпитера ρ 1,33): лёд ~1 г/см³ — 2,7; камень 3,3 — 1,8; железо 7,9 — 1,35,
# а с прочностью ещё ниже. Рыхлые груды и кометы рвутся раньше всех.
const ROCHE_R := {"ice": 2.5, "carbon": 2.1, "rock": 1.75, "lava": 1.65, "metal": 0.95, "gas": 2.0}
const ROCHE_KIND := {"comet": 2.8, "rubble": 2.6, "trojan": 2.4, "irondwarf": 0.9, "icedwarf": 2.6}
const ENVELOPE_R := 2.7      # здесь мини-нептун теряет газовую оболочку
const GAS_ROT := 0.92        # газ своего диска кружит с такой долей круговой скорости
const HANDOVER := 1.2        # тело уходит в движок разрушения на стольких пределах Роша
const FRAC_SLOW := 0.6       # раскол и полёт кусков идут медленнее (автор: «чуть замедлим»)
const IMPACT_V := 330.0      # скорость сближения для гигантского удара, ед./с
const BIG_RATIO := 1.4       # крупное: легче тебя хотя бы во столько раз
const CAPTURE := 0.42        # куски ниже этого — упали в облака
const EAT_RATIO := 0.1       # съесть можно тело легче этой доли твоей массы
const MERGE_RATIO := 1.4     # соперника-гиганта — когда ты тяжелее во столько раз
const SLING := 380.0         # пинок пращи, ед./с
const RADIAL_DRAG := 0.12    # газ гасит радиальную скорость тел
const DEBRIS_BASE := 1000000 # номера учёта обломков в частицах
const N_BODIES := 170
const ERA_BODIES := [12, 40, 65, 90]   # сколько мелких тел в мире по эпохам

# Виды тел: масса в массах Земли, видимый радиус, чем рисуется, что дают.
const EARTH_R := 36.0         # радиус Земли в единицах мира (Юпитер ≈ 400 = 11 R⊕)
const DENS_R := {"metal": 0.8, "rock": 1.0, "lava": 1.0, "chondrite": 1.0, "venus": 1.0,
	"carbon": 1.12, "ice": 1.25, "titan": 1.2, "gas": 1.0}
const SYL := ["ка", "ро", "лин", "те", "ва", "ми", "до", "ра", "сэ", "ну", "ор", "эл",
	"та", "ги", "ла", "ви", "ар", "зе", "мо", "кай", "ри", "нот", "ве", "са", "ол", "ден"]
const KINDS := {
	"rubble": {"name": "рой обломков", "m": Vector2(0.02, 0.06), "rad": 14.0, "view": "moon", "ch": 0, "extra": 0.0004, "pieces": 1},
	"planetesimal": {"name": "планетезималь", "m": Vector2(0.1, 0.35), "rad": 15.0, "view": "moon", "ch": 1, "extra": 0.001},
	"comet": {"name": "комета", "m": Vector2(0.01, 0.03), "rad": 6.0, "view": "comet", "ch": 1, "extra": 0.0008},
	"embryo": {"name": "зародыш", "m": Vector2(0.6, 3.0), "rad": 27.0, "view": "embryo", "ch": 3, "extra": 0.004},
	"superearth": {"name": "суперземля", "m": Vector2(4.0, 12.0), "rad": 48.0, "view": "embryo", "ch": 5, "extra": 0.008},
	"binary": {"name": "двойная планетезималь", "m": Vector2(0.15, 0.6), "rad": 12.0, "view": "moon", "ch": 2, "extra": 0.0012},
	"irondwarf": {"name": "железное ядро", "m": Vector2(0.05, 0.25), "rad": 11.0, "view": "moon", "ch": 2, "extra": 0.0014},
	"icedwarf": {"name": "ледяной карлик", "m": Vector2(0.2, 0.9), "rad": 18.0, "view": "embryo", "ch": 2, "extra": 0.002},
	"trojan": {"name": "троянец", "m": Vector2(0.03, 0.12), "rad": 9.0, "view": "moon", "ch": 1, "extra": 0.0005},
	"minineptune": {"name": "мини-нептун", "m": Vector2(12.0, 28.0), "rad": 78.0, "view": "giant", "ch": 6, "extra": 0.015},
	"rival": {"name": "гигант-соперник", "m": Vector2(40.0, 400.0), "rad": 0.0, "view": "giant", "ch": 12, "extra": 0.0},
	"dwarf": {"name": "коричневый карлик", "m": Vector2(4500.0, 6500.0), "rad": 0.0, "view": "giant", "ch": 0, "extra": 0.0},
}

# Вещество: как выглядит в шейдерах луны и зародыша, сколько пыли за массу.
const MATS := {
	"rock": {"moon": 0, "embryo": 0, "pay": 2.0, "col": Color(0.62, 0.55, 0.47)},
	"metal": {"moon": 4, "embryo": 1, "pay": 3.0, "col": Color(0.62, 0.62, 0.66)},
	"carbon": {"moon": 3, "embryo": 2, "pay": 2.6, "col": Color(0.26, 0.22, 0.2)},
	"ice": {"moon": 1, "embryo": 3, "pay": 2.0, "col": Color(0.82, 0.9, 0.98)},
	"lava": {"moon": 2, "embryo": 0, "pay": 2.4, "col": Color(0.9, 0.5, 0.28)},
}

# Палитры чужих гигантов и мини-нептунов: зона, пояс, пятно.
const RIVAL_LOOKS := [
	[Color(0.86, 0.8, 0.7), Color(0.6, 0.48, 0.38), Color(0.75, 0.45, 0.3)],
	[Color(0.78, 0.82, 0.86), Color(0.5, 0.56, 0.62), Color(0.62, 0.66, 0.72)],
	[Color(0.88, 0.74, 0.56), Color(0.56, 0.36, 0.22), Color(0.82, 0.5, 0.3)],
	# Миры поменьше (WORLD_CLS): 3 ледяной гигант, 4 сатурн, 5 рыхлый мир,
	# 6 сажевый гигант, 7 тяжёлое ядро, 8 горячий нептун.
	[Color(0.56, 0.76, 0.92), Color(0.3, 0.5, 0.78), Color(0.22, 0.34, 0.66)],
	[Color(0.93, 0.87, 0.7), Color(0.78, 0.68, 0.5), Color(0.86, 0.76, 0.56)],
	[Color(0.92, 0.84, 0.76), Color(0.82, 0.7, 0.62), Color(0.96, 0.88, 0.8)],
	[Color(0.36, 0.29, 0.25), Color(0.17, 0.13, 0.11), Color(0.46, 0.3, 0.2)],
	[Color(0.72, 0.68, 0.63), Color(0.47, 0.44, 0.43), Color(0.62, 0.52, 0.43)],
	[Color(0.5, 0.64, 0.86), Color(0.3, 0.4, 0.62), Color(0.86, 0.52, 0.36)],
]
## Миры заметного размера (автор: «как мы, только меньше — ¼, ⅓, ½ размера,
## и нестандартные, чтобы их есть по физике»). Размер — доля твоего радиуса,
## масса из размера честно: ледяные гиганты и сатурны по закону
## M = 17·(R/3,9 R⊕)^1,92 (Нептун → Сатурн), рыхлый мир — 2–8 M⊕ при размере
## Сатурна (как Kepler-51), тяжёлое ядро втрое плотнее (как HD 149026 b).
## Все легче тебя: едятся слиянием (GiantEncounter) — прилив, перетекание
## через L1, общая оболочка; мягкость soft и время слияния ce — свои.
const WORLD_CLS := {
	"icegiant": {"title": "ледяной гигант", "size": Vector2(0.25, 0.4), "look": 3, "soft": 1.2, "ce": 2.6, "w": 1.0},
	"saturn": {"title": "сатурн", "size": Vector2(0.4, 0.55), "look": 4, "soft": 1.15, "ce": 2.8, "w": 0.8},
	"puff": {"title": "рыхлый мир", "size": Vector2(0.35, 0.5), "look": 5, "soft": 2.4, "ce": 1.8, "w": 0.6},
	"soot": {"title": "сажевый гигант", "size": Vector2(0.3, 0.45), "look": 6, "soft": 1.0, "ce": 3.0, "w": 0.6},
	"dense": {"title": "тяжёлое ядро", "size": Vector2(0.25, 0.35), "look": 7, "soft": 0.65, "ce": 4.2, "w": 0.5},
	"hotnep": {"title": "горячий нептун", "size": Vector2(0.25, 0.35), "look": 8, "soft": 1.5, "ce": 2.2, "w": 0.3},
}
const WORLDS_BY_ERA := [2, 3, 4, 5]
const NEPTUNE_LOOK := [Color(0.62, 0.8, 0.9), Color(0.36, 0.58, 0.78), Color(0.2, 0.32, 0.6)]
const DWARF_LOOK := [Color(0.55, 0.22, 0.2), Color(0.28, 0.08, 0.1), Color(0.75, 0.3, 0.18)]

var stage                    # giant_stage.gd
var bodies: Array = []
var vortices: Array = []
var _pearls: Array = []      # крупные обломки разорванных тел: летят по задаче Хилла
var tides: TidalStreams     # газовые струи (оболочки, кольца) и шлейфы ударов
var frac: FracWorld          # движок разрушения: всё твёрдое ломается в нём
var enc: GiantEncounter      # сближение с крупными жидкими телами: прилив, полость Роша, касание
var _ffield: GiantFracField
var _white: ImageTexture
var _width_curve: Curve
var _flashes: Array = []     # вспышки ударов в облаках и падений в звезду
var _debris := {}            # учёт пыли разорванных тел: id -> {per, mat, kind, left}
var _next_id := 1
var _time := 0.0
var _rng := RandomNumberGenerator.new()
var _pools := {}             # вид -> Array узлов
var _used := {}
var _maps := {}              # палитра -> запечённая карта облаков
var _flash_tex: GradientTexture2D
var _flash_nodes: Array = []
var _ring_list: Array = []   # кольца мини-нептунов этого кадра: задняя половина под телом, передняя поверх
var _over := Node2D.new()    # поверх гиганта: огонь удара и ударная волна
var _spawn_t := 4.0
var _dwarf_t := 140.0
var _wander_t := 0.0         # до следующей проверки странника-гиганта, с
var _said := {}
var _sling_cd := 0.0
var _hit_cd := 0.0


func _ready() -> void:
	_rng.randomize()
	_flash_tex = _make_flash_tex()
	_over.z_index = 20
	add_child(_over)
	_over.draw.connect(_draw_rings)


func setup() -> void:
	tides = TidalStreams.new()
	tides.world = self
	stage.body.add_child(tides)
	_ffield = GiantFracField.new()
	_ffield.world = self
	_ffield.refresh()
	frac = FracWorld.new()
	frac.field = _ffield
	frac.time_k = FRAC_SLOW
	stage.body.add_child(frac)
	enc = GiantEncounter.new()
	enc.stage = stage
	enc.world = self
	add_child(enc)


## Мир сразу такой, какой положен эпохе (начало этапа или загрузка посреди).
func fill_to(era: int) -> void:
	for i in ERA_BODIES[clampi(era, 0, 3)]:
		_spawn_random(true)
	for n in range(1, era + 1):
		_era_guests(n)


## Новая эпоха: мелкие тела подтянутся сами (их ждёт счётчик), а гости
## приходят издалека, из-за края экрана.
func on_era(era: int) -> void:
	_era_guests(era)
	# Первая горсть новых тел сразу, чтобы перемену было видно.
	for i in 6:
		_spawn_random(false)


func _era_guests(era: int) -> void:
	# Соседи-гиганты своей массы, не по твоей (автор: «вначале слабые, в конце
	# сильные»): пришли — тяжелее тебя, к концу этапа ты их перерастаешь.
	match era:
		2:
			_spawn_rival(_rng.randf_range(160.0, 260.0))
			_spawn_trojans()
		3:
			_spawn_rival(_rng.randf_range(700.0, 1100.0))
			if _flavor() in ["giant_cold", "giant_hot"]:
				_spawn_rival(_rng.randf_range(1800.0, 2600.0))
			_dwarf_t = minf(_dwarf_t, _rng.randf_range(50.0, 90.0))


## Троянцы: рои в точках Лагранжа L4 и L5, на 60° впереди и позади тебя по
## твоей же орбите. Сдвиг их не уносит: они ждут, пока ты к ним придёшь.
func _spawn_trojans() -> void:
	var o: float = stage.orbit
	var n := 14 if _flavor() == "giant_cold" else 10
	for side in [-1.0, 1.0]:
		for i in n:
			var a: float = float(stage.ang) + side * PI / 3.0 + _rng.randfn(0.0, 0.035)
			var b := _add_body("trojan", o + _rng.randfn(0.0, 260.0), a, _material_at(o))
			b.tag = "trojan"


func bind(gas: GasParticles) -> void:
	gas.particle_eaten.connect(_on_debris)


func _flavor() -> String:
	return str(GameState.giant.get("flavor", "giant_cold"))


# --- Население ---

## Вещество тела по месту и ядру: у звезды лава и железо, за снеговой линией лёд.
func _material_at(r: float) -> String:
	var f := _flavor()
	var roll := _rng.randf()
	if f == "giant_dense" and roll < 0.45:
		return "metal"
	if f == "giant_dark" and roll < 0.45:
		return "carbon"
	if f == "giant_hot" and r < GameData.HOT_ORBIT + 2500.0 and roll < 0.55:
		return "lava"
	roll = _rng.randf()
	if r < GameData.HOT_ORBIT + 1200.0:
		return "lava" if roll < 0.45 else ("metal" if roll < 0.75 else "rock")
	if r > GameData.SNOW_LINE:
		return "ice" if roll < 0.65 else ("carbon" if roll < 0.85 else "rock")
	return "metal" if roll < 0.2 else ("carbon" if roll < 0.35 else "rock")


## Смешанное вещество тела (для движка разрушения): хондрит, лёд с органикой
## (титан), камень с углеродом (венера). Своего состава вокруг вдвое больше;
## у переходного тела смесей больше всех. Пусто — чистое вещество.
func _sub_mat(mat: String, r: float) -> String:
	var type := GameState.body_type()
	var k := 1.5 if type == "neutral" else 1.0
	var cand := {}
	var snow := r > GameData.SNOW_LINE
	match mat:
		"rock":
			cand["chondrite"] = 0.25
			if not snow:
				cand["venus"] = 0.12
		"carbon":
			cand["titan" if snow else "venus"] = 0.35
		"ice":
			cand["titan"] = 0.2
	for key in cand:
		var pk: float = float(cand[key]) * k * (2.0 if key == type else 1.0)
		if _rng.randf() < pk:
			return key
	return ""


func _pick_kind(r: float) -> String:
	var f := _flavor()
	var w := {"rubble": 0.24, "planetesimal": 0.22, "binary": 0.08, "irondwarf": 0.03, "icedwarf": 0.0,
		"embryo": 0.16, "superearth": 0.08, "minineptune": 0.03, "comet": 0.0}
	if r > GameData.SNOW_LINE:
		w["comet"] = 0.18 * (2.2 if f == "giant_ice" else 1.0)
		w["minineptune"] = 0.07 * (1.8 if f == "giant_ice" else 1.0)
		w["icedwarf"] = 0.08 * (2.0 if f == "giant_ice" else 1.0)
		w["irondwarf"] = 0.0
	else:
		# Железные ядра — осколки разбитых зародышей у звезды.
		w["irondwarf"] *= 3.0 if f == "giant_dense" else 1.0
	if f == "giant_dark":
		w["binary"] *= 2.0
	if f == "giant_hot" and r < GameData.HOT_ORBIT + 2500.0:
		w["superearth"] = 0.16
	if f == "giant_cold":
		w["superearth"] *= 1.5
	# Эпохи: сначала только пыль и обломки, крупное приходит потом.
	var era: int = maxi(stage.era, 0)
	if era < 1:
		w["planetesimal"] = 0.0
		w["binary"] = 0.0
		w["irondwarf"] = 0.0
	if era < 2:
		w["embryo"] = 0.0
		w["icedwarf"] = 0.0
		w["irondwarf"] = 0.0
	if era < 3:
		w["superearth"] = 0.0
		w["minineptune"] = 0.0
	var total := 0.0
	for k in w:
		total += float(w[k])
	var x := _rng.randf() * total
	for k in w:
		x -= float(w[k])
		if x <= 0.0:
			return k
	return "rubble"


func _spawn_random(anywhere: bool) -> void:
	var lo := GameData.GIANT_ORBIT_MIN * 1.05
	var hi := GameData.GIANT_DISK.y - 400.0
	var r := lerpf(lo, hi, sqrt(_rng.randf()))
	var a := _rng.randf() * TAU
	if not anywhere:
		# Новые приходят из-за края экрана: с окраин или по орбите издалека.
		var g: float = stage.ang
		a = g + (1.0 if _rng.randf() < 0.5 else -1.0) * _rng.randf_range(0.5, 1.2)
	var kind := _pick_kind(r)
	_add_body(kind, r, a, _material_at(r))


func _add_body(kind: String, r: float, a: float, mat: String, m := -1.0) -> Dictionary:
	var info: Dictionary = KINDS[kind]
	var mr: Vector2 = info["m"]
	if m < 0.0:
		m = _rng.randf_range(mr.x, mr.y)
	match kind:
		"comet", "icedwarf":
			mat = "ice"
		"irondwarf":
			mat = "metal"
	var b := {
		"id": _next_id, "kind": kind, "mat": mat, "m": m, "r": r, "a": a, "vr": 0.0,
		"seed": _rng.randf() * 10.0, "spin": _rng.randf() * TAU,
		# Медленно, как настоящие тела: оборот за минуты, а не за секунды.
		"spin_rate": _rng.randf_range(0.008, 0.03) * (1.0 if _rng.randf() < 0.5 else -1.0),
		"tilt": _rng.randf_range(0.2, 0.6), "state": "free", "t": 0.0,
		"h": Vector4.ZERO, "stretch": 0.0, "cd": 0.0, "tag": "", "look": _rng.randi() % 3,
	}
	var sub := _sub_mat(mat, r)
	if sub != "":
		b["sub"] = sub
	if kind == "comet":
		# Кометы падают с окраин к звезде.
		b["vr"] = -_rng.randf_range(90.0, 180.0)
	elif not kind in ["rival", "dwarf"]:
		# Свой медленный дрейф: мир не стоит на месте, но и не крутится.
		b["drift"] = Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(8.0, 40.0)
	if kind == "minineptune" and _rng.randf() < (0.7 if _flavor() == "giant_ice" else 0.4):
		b["rings"] = true
	_next_id += 1
	bodies.append(b)
	return b


func _spawn_rival(m: float) -> Dictionary:
	# Соседи-гиганты рождаются далеко от тебя: встреча — твой выбор.
	var gp: Vector2 = stage.body.position
	var r := 0.0
	var a := 0.0
	for attempt in 16:
		r = _rng.randf_range(GameData.HOT_ORBIT, GameData.GIANT_DISK.y - 1500.0)
		a = _rng.randf() * TAU
		if (Vector2.from_angle(a) * r).distance_to(gp) > 9000.0:
			break
	return _add_body("rival", r, a, "gas", m)


## Странники-гиганты (автор: «первую минуту никого, потом с небольшим
## шансом — гиганты меньше и больше тебя, чтобы дух захватывало»). Первая
## минута этапа пустая. Дальше раз в 60–120 с бросок: с шансом по флейвору
## сквозь диск идёт чужой гигант своим курсом. Масса — от твоей: 40% легче
## (0,35–0,8), 35% тяжелее (1,3–2,8), 25% огромный (4–12, до 4200 M⊕):
## молодой, ещё раздутый жаром — в 1,4–1,9 раза шире, идёт медленно.
## Часть проходит вплотную (2,5–4 суммы радиусов): прилив, перетекание,
## слияние — уже GiantEncounter. Ушёл за 18 000 — исчез без следа.
const WANDER_CHANCE := {"giant_cold": 0.4, "giant_hot": 0.42, "giant_ice": 0.36,
	"giant_dark": 0.32, "giant_dense": 0.3}


func _step_wanderers(delta: float) -> void:
	var elapsed: float = float(stage.gas_total) - float(stage.gas)
	if elapsed < 60.0 or stage.gas < 40.0:
		return
	_wander_t -= delta
	if _wander_t > 0.0:
		return
	_wander_t = _rng.randf_range(60.0, 120.0)
	var n := 0
	for b in bodies:
		if b.kind == "rival" and b.has("cruise"):
			n += 1
	if n >= 2 or _rng.randf() > float(WANDER_CHANCE.get(_flavor(), 0.35)):
		return
	spawn_wanderer(-1.0)


var _world_t := 0.0


## Миры поменьше всегда где-то рядом: их видно издалека, за ними можно
## гнаться. Первые — через 45 с, дальше по эпохам 2/3/4/5 сразу.
func _step_worlds(delta: float) -> void:
	var elapsed: float = float(stage.gas_total) - float(stage.gas)
	if elapsed < 45.0 or stage.gas < 40.0:
		return
	_world_t -= delta
	if _world_t > 0.0:
		return
	_world_t = _rng.randf_range(5.0, 11.0)
	var n := 0
	for b in bodies:
		if b.has("cls"):
			n += 1
	var want := roundi(float(WORLDS_BY_ERA[clampi(stage.era, 0, 3)]) * Skills.stat("giant_bodies"))
	if n < want:
		spawn_world("")


## Какой мир придёт: по флейвору гиганта и по твоему составу (правило 1).
func _pick_cls() -> String:
	var w := {}
	for k in WORLD_CLS:
		w[k] = float(WORLD_CLS[k]["w"])
	match _flavor():
		"giant_ice":
			w.icegiant *= 2.0
			w.saturn *= 1.3
		"giant_cold":
			w.saturn *= 1.6
		"giant_hot":
			w.hotnep *= 4.0
			w.puff *= 1.8
		"giant_dense":
			w.dense *= 2.5
			w.puff *= 0.3
		"giant_dark":
			w.soot *= 2.5
	match GameState.body_type():
		"ice":
			w.icegiant *= 1.5
		"carbon":
			w.soot *= 1.5
		"metal":
			w.dense *= 1.5
		"titan":
			w.icegiant *= 1.3
			w.soot *= 1.3
		"venus":
			w.puff *= 1.3
			w.soot *= 1.3
		"silicate":
			w.saturn *= 1.3
		"chondrite", "neutral":
			# Смешанное тело — пёстрый мир вокруг: все виды ближе к поровну.
			for k in w:
				w[k] = sqrt(float(w[k]))
	var total := 0.0
	for k in w:
		total += float(w[k])
	var x := _rng.randf() * total
	for k in w:
		x -= float(w[k])
		if x <= 0.0:
			return k
	return "icegiant"


func spawn_world(cls: String, near := -1.0) -> Dictionary:
	if cls == "":
		cls = _pick_cls()
	var c: Dictionary = WORLD_CLS[cls]
	var e: float = stage.earths
	var rme := _giant_r()
	var rr: float = rme * _rng.randf_range(c.size.x, c.size.y)
	var re := rr / EARTH_R
	var m := 17.0 * pow(re / 3.9, 1.92)
	if cls == "puff":
		m = _rng.randf_range(2.0, 8.0) * clampf(rme / 400.0, 0.4, 1.5)
	elif cls == "dense":
		m *= 3.0
	m = clampf(m, 0.5, e / 1.7)
	var g: Vector2 = stage.body.position
	var p := g
	for attempt in 12:
		var d := near if near > 0.0 else _rng.randf_range(5200.0, 9000.0)
		p = g + Vector2.from_angle(_rng.randf() * TAU) * d
		if p.length() > GameData.HOT_ORBIT and p.length() < GameData.GIANT_DISK.y - 1500.0:
			break
	var b := _add_body("rival", p.length(), p.angle(), "gas", m)
	b["cls"] = cls
	b["look"] = int(c.look)
	b["puff"] = rr / GameData.giant_body_r(m)
	if cls == "saturn":
		b["rings"] = true
	return b


func spawn_wanderer(k := -1.0, close := -1) -> Dictionary:
	var e: float = stage.earths
	var f := _flavor()
	var roll := _rng.randf()
	var huge := false
	if k <= 0.0:
		if roll < 0.4:
			k = _rng.randf_range(0.35, 0.8)
		elif roll < 0.75:
			k = _rng.randf_range(1.3, 2.8)
		else:
			k = _rng.randf_range(4.0, 12.0)
	huge = k >= 4.0
	var m := clampf(e * k, 40.0, 4200.0)
	var g: Vector2 = stage.body.position
	var dir := Vector2.from_angle(_rng.randf() * TAU)
	var side := dir.orthogonal()
	var b := {}
	var r1 := GameData.giant_body_r(e)
	var speed := _rng.randf_range(260.0, 380.0) if huge else _rng.randf_range(320.0, 520.0)
	var puff := 1.0
	if huge:
		# Плотный флейвор и соседи у него плотнее; горячий раздувает сильнее.
		puff = _rng.randf_range(1.4, 1.9) * ({"giant_hot": 1.15, "giant_dense": 0.8}.get(f, 1.0) as float)
	var r2 := GameData.giant_body_r(m) * puff
	var near_pass := _rng.randf() < 0.4 if close < 0 else close == 1
	# Огромный проходит чуть дальше: дух захватывает, но удрать успеваешь.
	var miss := (_rng.randf_range(3.6, 5.0) if huge else _rng.randf_range(2.5, 4.0)) * (r1 + r2) if near_pass else _rng.randf_range(5000.0, 9000.0)
	var start := g + side * miss * (1.0 if _rng.randf() < 0.5 else -1.0) - dir * 11000.0
	b = _add_body("rival", start.length(), start.angle(), "gas", m)
	b["puff"] = puff
	b["cruise"] = dir * speed
	b["v"] = dir * speed
	if huge:
		Input.vibrate_handheld(400)
	return b


## Коричневый карлик проходит сквозь диск по прямой, издалека.
func _spawn_dwarf() -> void:
	var g: Vector2 = stage.body.position
	var dir := g.normalized().rotated(_rng.randf_range(-0.4, 0.4))
	var side := dir.orthogonal() * (1.0 if _rng.randf() < 0.5 else -1.0)
	# Мимо тебя, но близко: на таком расстоянии тяга карлика ещё слабее твоего
	# хода. Подлетишь сам ближе пары тысяч — его тяготение уже не отпустит.
	var miss := _rng.randf_range(4800.0, 7000.0) * (1.0 if _rng.randf() < 0.5 else -1.0)
	var start := g + dir * miss - side * 9000.0
	var b := _add_body("dwarf", start.length(), start.angle(), "gas")
	b["vel"] = side * 520.0
	b["state"] = "pass"
	stage.hud.caption("Коричневый карлик", "несостоявшаяся звезда в двадцать масс Юпитера проходит сквозь диск: она вырывает луны и швыряет всё вокруг. Держись подальше", 4.5)


static func _cap(t: String) -> String:
	return t.left(1).to_upper() + t.substr(1)


static func pos_of(b: Dictionary) -> Vector2:
	return Vector2.from_angle(float(b.a)) * float(b.r)


## Радиус честно по массе и веществу (автор): R/R⊕ ≈ (M/M⊕)^0,27 для камня,
## железо плотнее, лёд и углерод рыхлее; у мини-нептуна газовая оболочка
## (≈2 R⊕ × M^0,2); гиганты — тем же законом, что и ты; коричневые карлики —
## размером с Юпитер при любой массе (вырожденный газ).
func rad_of(b: Dictionary) -> float:
	var k: String = b.kind
	if k == "rival":
		# Молодой тяжёлый странник ещё не сжался: раздут жаром (puff).
		return GameData.giant_body_r(float(b.m)) * float(b.get("puff", 1.0))
	if k == "dwarf":
		return GameData.giant_body_r(318.0) * 1.05
	if k == "comet":
		return float(KINDS[k]["rad"]) * pow(float(b.m) / 0.01, 0.18)
	var m := maxf(float(b.m), 0.001)
	if k == "minineptune" and not b.get("core", false):
		return EARTH_R * 2.0 * pow(m, 0.2)
	var dens: float = DENS_R.get(b.get("sub", b.mat), 1.0)
	if k in ["rubble", "comet"]:
		dens *= 1.3     # рыхлая груда
	return EARTH_R * dens * pow(m, 0.27)


## Имя тела: у каждой планеты своё, как в каталоге.
func name_of(b: Dictionary) -> String:
	if not b.has("name"):
		b["name"] = _gen_name(b)
	return b.name


func _gen_name(b: Dictionary) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(int(b.id) * 7919 + 13)
	if b.kind == "dwarf":
		return "Карлик %s-%d" % [["Ахернар", "Тейде", "Глизе", "Лугаль"][rng.randi() % 4], rng.randi_range(100, 999)]
	var n := ""
	for i in rng.randi_range(2, 3):
		n += SYL[rng.randi() % SYL.size()]
	n = n.left(1).to_upper() + n.substr(1)
	if b.kind == "rival":
		return n
	if b.kind in ["rubble", "planetesimal", "binary", "irondwarf", "trojan"]:
		return "(%d) %s" % [rng.randi_range(12, 9999), n]
	return n


func hill_of(b: Dictionary) -> float:
	return 2.2 * rad_of(b) if b.kind in ["rival", "dwarf"] else rad_of(b) * 3.0


func eat_limit() -> float:
	return float(stage.earths) * EAT_RATIO * Skills.stat("giant_tidal")


## Что это тело для тебя: "food" — съесть, "merge" — слиться, "sling" — праща, "danger".
func role(b: Dictionary) -> String:
	var e: float = stage.earths
	var m: float = b.m
	if b.kind == "dwarf":
		return "danger"
	if b.kind == "rival":
		if e >= m * (MERGE_RATIO - Skills.stat("giant_merge")):
			return "merge"
		return "danger" if m > e else "sling"
	if m <= eat_limit():
		return "food"
	if m <= e / (BIG_RATIO - Skills.stat("giant_merge")):
		return "big"
	return "sling"


## Предел Роша тела в радиусах Хилла (у тебя Хилл = 2,2 радиуса гиганта).
func roche_h(b: Dictionary) -> float:
	var rr: float = ROCHE_KIND.get(b.kind, ROCHE_R.get(b.mat, 1.8))
	if b.kind == "minineptune" and not b.get("core", false):
		rr = ENVELOPE_R
	if b.kind == "rival":
		rr = 2.4
	# Навык прилива поднимает предел (как будто гигант плотнее).
	return rr * pow(Skills.stat("giant_tidal"), 0.33) * _giant_r() / stage.hill()


func _giant_r() -> float:
	return stage.body.outer_r()


## Касание облаков, в радиусах Хилла.
func contact_h(b: Dictionary) -> float:
	return (_giant_r() + rad_of(b) * 0.8) / stage.hill()


## Скорость тела в мире: свой дрейф, радиальная и набранная тяготением.
## Орбит нет: тело не уносит сдвигом диска.
func _vel_of(b: Dictionary) -> Vector2:
	return Vector2.from_angle(float(b.a)) * float(b.vr) + (b.get("v", Vector2.ZERO) as Vector2) \
		+ (b.get("drift", Vector2.ZERO) as Vector2)


func _player_vel() -> Vector2:
	return stage.vel


# --- Шаг ---

func step(delta: float) -> void:
	_time += delta
	_sling_cd = maxf(_sling_cd - delta, 0.0)
	_hit_cd = maxf(_hit_cd - delta, 0.0)
	var orbit: float = stage.orbit
	var gpos: Vector2 = stage.body.position
	var h: float = stage.hill()
	var reach: float = Skills.stat("giant_reach") * Skills.stat("giant_grab")
	var keep := []
	for b in bodies:
		if _step_body(b, delta, orbit, gpos, h, reach):
			keep.append(b)
	bodies = keep
	enc.move_bodies(delta)
	enc.step(delta)
	_step_pearls(delta, h)
	tides.step(delta, _giant_r())
	_ffield.refresh()
	frac.step(delta)
	_step_vortices(delta, gpos, h)
	# Тела не кончаются: новые приходят с окраин и из-за края экрана.
	_spawn_t -= delta
	var want := roundi(ERA_BODIES[clampi(stage.era, 0, 3)] * Skills.stat("giant_bodies"))
	# Диск тает: новых тел почти нет, мир пустеет к концу.
	if stage.gas < 90.0:
		want = roundi(want * 0.3)
	if _spawn_t <= 0.0:
		_spawn_t = _rng.randf_range(1.0, 2.5)
		var small := 0
		for b in bodies:
			if not (b.kind in ["rival", "dwarf"]):
				small += 1
		if small < want:
			_spawn_random(false)
	_step_wanderers(delta)
	_step_worlds(delta)
	if stage.era >= 3:
		_dwarf_t -= delta
	if _dwarf_t <= 0.0 and stage.gas > 50.0:
		_dwarf_t = _rng.randf_range(170.0, 240.0)
		_spawn_dwarf()
	var fl := []
	for f in _flashes:
		f.t = float(f.t) + delta / float(f.dur)
		if float(f.t) < 1.0:
			fl.append(f)
	_flashes = fl
	queue_redraw()


## Возвращает false, если тело ушло из мира.
func _step_body(b: Dictionary, delta: float, orbit: float, gpos: Vector2, h: float, reach: float) -> bool:
	b.spin = float(b.spin) + float(b.spin_rate) * delta
	b.cd = maxf(float(b.cd) - delta, 0.0)
	var st: String = b.state
	if st == "captured":
		return _step_captured(b, delta, h)
	if st == "rival_eat":
		b.t = float(b.t) + delta / 1.8
		return float(b.t) < 1.0
	if st == "pass":
		var p := pos_of(b) + (b.vel as Vector2) * delta
		b.r = p.length()
		b.a = p.angle()
		_scatter_near(b, delta)
		return p.length() < GameData.GIANT_DISK.y + 12000.0 and _time < 1e9 and p.distance_to(gpos) < 16000.0
	# Свободное тело: занято своим (BodyNpc) — плывёт к цели своим дрейфом,
	# радиальная скорость гаснет в газе. Орбит нет — само никуда не уносит.
	if b.kind == "rival":
		if b.has("cruise") and pos_of(b).distance_to(gpos) > 18000.0 and float(b.t) > 20.0:
			return false   # странник ушёл своей дорогой
		b.t = float(b.get("t", 0.0)) + delta
		BodyNpc.step_rival(self, b, delta, gpos)
	else:
		BodyNpc.step(self, b, delta, gpos)
	var dr: Vector2 = b.get("drift", Vector2.ZERO)
	if dr != Vector2.ZERO:
		var np := pos_of(b) + dr * delta
		b.r = np.length()
		b.a = np.angle()
	if b.kind == "comet":
		b.r = float(b.r) + float(b.vr) * delta
	else:
		b.r = float(b.r) + float(b.vr) * delta
		b.vr = float(b.vr) * exp(-RADIAL_DRAG * delta)
	if b.kind == "rival":
		# Соперник тоже пьёт газ и растёт, пока газ есть.
		var gk: float = clampf(stage.gas / stage.gas_total, 0.0, 1.0)
		b.m = float(b.m) * (1.0 + 0.0006 * gk * delta)
		_rival_feed(b)
	# Ушло за пределы: упало в звезду или выброшено из системы.
	if float(b.r) < GameData.GIANT_STAR_R * 1.08:
		_into_star(b)
		return false
	if float(b.r) > GameData.GIANT_DISK.y + 600.0 and not b.has("cruise"):
		if b.kind != "comet":
			_ejected(b)
		return false
	var p2 := pos_of(b)
	var d := p2.distance_to(gpos)
	var ro := role(b)
	if b.state == "gone":
		return false
	if ro in ["food", "big", "sling"] and b.kind != "rival":
		_attract(b, delta, p2, gpos, d, h)
		p2 = pos_of(b)
		d = p2.distance_to(gpos)
	# Соперники и карлик — жидкие тела: с ними всё решает GiantEncounter
	# (тяготение, прилив, перетекание, касание, общая оболочка).
	if b.kind in ["rival", "dwarf"]:
		return true
	match ro:
		"food", "merge":
			if d < (2.0 * h * reach if ro == "food" else h * 1.6 + rad_of(b)) and float(b.cd) <= 0.0:
				_capture(b, gpos, h, orbit)
				if b.state == "gone":
					return false
		"big":
			var vrel := (_vel_of(b) - _player_vel()).length()
			if d < _giant_r() + rad_of(b) * 0.8:
				if vrel >= IMPACT_V * _impact_need():
					_giant_impact(b, p2, vrel)
					return false
				_capture(b, gpos, h, orbit)
			elif d < 1.6 * h and vrel < IMPACT_V * 0.75 and float(b.cd) <= 0.0:
				# Подошёл медленно: тело ложится на орбиту, как мелочь.
				_capture(b, gpos, h, orbit)
		"sling":
			if d < 2.2 * h + rad_of(b) and float(b.cd) <= 0.0:
				_sling(b, p2, gpos)
			_danger_soft(b, delta, gpos, h)
		"danger":
			_danger(b, delta, gpos, h)
	return true


## Механизм Хиллса: прилив разводит двойную. Одна половина остаётся у тебя,
## вторая уносит лишнюю энергию и улетает быстро, как из пращи.
func _split_binary(b: Dictionary) -> void:
	var half := float(b.m) * 0.5
	b.m = half
	b.kind = "planetesimal"
	var p := pos_of(b)
	var gp: Vector2 = stage.body.position
	var out: Vector2 = (p - gp).normalized().rotated(_rng.randf_range(-0.6, 0.6))
	var o := _add_body("planetesimal", p.length(), p.angle(), b.mat, half)
	o["v"] = out * _rng.randf_range(420.0, 560.0)
	o["slung"] = true
	o.cd = 6.0
	o.vr = out.dot(p.normalized()) * 260.0
	if not _said.has("hills"):
		_said["hills"] = true
		stage.hud.caption("Двойная разделилась", "прилив развёл пару: одна половина осталась у тебя, вторая улетела с лишней энергией. Так в жизни рождаются сверхбыстрые тела", 4.0)


## Своя луна тела при захвате: твоё поле её удержит или выбросит.
func _take_sat(b: Dictionary) -> void:
	if not b.get("sat", false):
		return
	b.erase("sat")
	if stage.moons < GameState.giant_moon_cap():
		stage.moons += 1
		stage.body.moons = stage.moons
		stage.body.birth(stage.moons - 1, stage.body.to_local(pos_of(b)))
		stage.hud.toast("Луна %s теперь твоя: перешла к тебе от тела" % stage.body.moon_name(stage.moons - 1), Color(0.85, 0.9, 1.0))
	else:
		stage.hud.toast("Его луну выбросило: твоё поле больше не держит", Color(0.75, 0.82, 0.95))


## Тяготение взаимное: тело падает на тебя тем быстрее, чем ближе, а тебя
## тянет к нему во столько раз слабее, во сколько оно легче.
func _attract(b: Dictionary, delta: float, p: Vector2, gpos: Vector2, d: float, h: float) -> void:
	var v: Vector2 = b.get("v", Vector2.ZERO)
	if d < 4.0 * h:
		var dir := (gpos - p) / maxf(d, 1.0)
		# То же тяготение, что ведёт захваченное тело (задача Хилла), — энергия
		# сохраняется: быстрый пролёт уходит по гиперболе, а не липнет.
		var g := 3.0 * pow(Skills.stat("giant_reach"), 3.0)
		var acc := g * h * HILL_W * HILL_W * pow(h / maxf(d, h * 0.5), 2.0)
		v += dir * acc * delta
		var q := clampf(float(b.m) / float(stage.earths), 0.0, 1.0)
		if q > 0.02:
			stage.kick += (-dir).rotated(-float(stage.ang)) * acc * q * delta
	# Газ диска понемногу гасит набранную скорость.
	v *= exp(-0.12 * delta)
	if v.length_squared() < 1.0 and d > 4.0 * h:
		b.erase("v")
		return
	b["v"] = v
	var np := p + v * delta
	b.r = np.length()
	b.a = np.angle()


## Сколько разгона нужно для удара: плотные тела надо бить сильнее.
func _impact_need() -> float:
	return 1.0 / sqrt(Skills.stat("giant_impact"))


## Тело попало в твою сферу Хилла: дальше его ведёт задача Хилла.
func _capture(b: Dictionary, gpos: Vector2, h: float, orbit: float) -> void:
	if b.get("moon", false) and stage.moons < GameState.giant_moon_cap():
		# Железное поле ловит тело целым: оно садится на лунную орбиту.
		var loc0: Vector2 = stage.body.to_local(pos_of(b))
		stage.moons += 1
		stage.body.moons = stage.moons
		stage.body.birth(stage.moons - 1, loc0)
		stage.hud.toast("Поле захватило луну %s!" % stage.body.moon_name(stage.moons - 1), Color(0.8, 0.85, 0.95))
		b.state = "gone"
		body_eaten.emit(b)
		return
	if b.kind in ["embryo", "planetesimal"] and stage.moons < GameState.giant_moon_cap() and role(b) == "food" \
			and _rng.randf() < Skills.stat("giant_moon_grab") * (1.5 if _flavor() == "giant_dense" else 1.0):
		b["moon"] = true
		_capture(b, gpos, h, orbit)
		return
	if b.kind == "binary":
		_split_binary(b)
	_take_sat(b)
	var loc: Vector2 = stage.body.to_local(pos_of(b))
	# Скорость тела в мире: оно летит своей дорогой, ты — своей (shift
	# двигает систему вместе с тобой, тело в ней остаётся на своём пути).
	var lv: Vector2 = _vel_of(b).rotated(-float(stage.ang))   # x — от звезды, y — рост угла
	var s := h * HILL_W
	b.h = Vector4(loc.x / h, -loc.y / h, lv.x / s, -lv.y / s)
	b["q"] = clampf(float(b.m) / float(stage.earths), 0.0, 1.0)
	b.state = "captured"
	b.t = 0.0
	if not _said.has("roche"):
		_said["roche"] = true
		stage.hud.caption("Захват", "тело легло на орбиту вокруг тебя и скручивается по спирали. Рыхлое и ледяное рвёт приливом ещё над облаками, камень — у самых облаков, а железо врезается целым", 4.5)
	if b.kind == "rival" and not _said.has("merge"):
		_said["merge"] = true
		stage.hud.caption("Слияние гигантов", "ты перерос соседа: он падает в тебя по спирали", 3.5)


func _step_captured(b: Dictionary, delta: float, h: float) -> bool:
	var g := 3.0 * pow(Skills.stat("giant_reach"), 3.0)
	if _solid(b):
		# У предела Роша время тела плавно замедляется до времени движка:
		# куски стартуют с той же скоростью, что видна была у целого тела.
		var p0: Vector4 = b.h
		var d0 := sqrt(p0.x * p0.x + p0.y * p0.y)
		var ho0 := maxf(roche_h(b) * HANDOVER, contact_h(b) * 1.6)
		delta *= lerpf(1.0, FRAC_SLOW, smoothstep(ho0 * 1.9, ho0 * 1.05, d0))
	var dt := delta * HILL_W
	var steps := maxi(1, ceili(dt / 0.02))
	var hh := dt / steps
	var p: Vector4 = b.h
	# Честно (автор: «тело не должно клеиться»): только тяготение гиганта и
	# трение о его околопланетный диск (до ~1 Хилла) и атмосферу. Пролетел
	# быстро мимо — тело уходит по гиперболе своей дорогой; зашло в диск
	# медленно — газ гасит скорость относительно тебя, и оно ложится на орбиту.
	var q: float = b.get("q", 0.0)
	var fr := 0.9 / (1.0 + q)
	var ho := maxf(roche_h(b) * HANDOVER, contact_h(b) * 1.6) if _solid(b) else 0.0
	var pl: Vector2 = (stage.vel as Vector2).rotated(-float(stage.ang)) / (h * HILL_W)
	var pv := Vector2(pl.x, -pl.y)     # твоя скорость в единицах задачи
	for k in steps:
		p = GasParticles.hill_step(p, hh, g, 0.0)
		var d := sqrt(p.x * p.x + p.y * p.y)
		var vk := sqrt(g / maxf(d, 0.05)) * GAS_ROT
		# Трение только в самом диске (ближе ~1 Хилла) и чуть сильнее у предела
		# Роша, где газ плотнее. Снаружи — чистое тяготение: пролёт по гиперболе.
		var fr2 := fr * smoothstep(1.0, 0.45, d) + (1.5 * smoothstep(ho * 1.4, ho * 1.05, d) if ho > 0.0 else 0.0)
		# Орбит нет (автор): газ у тебя не кружит, а летит вместе с тобой и
		# падает в тебя. Тело в нём теряет скорость относительно тебя и падает.
		var gx := pv.x - p.x / maxf(d, 0.05) * vk * 0.3
		var gy := pv.y - p.y / maxf(d, 0.05) * vk * 0.3
		p.z -= (p.z - gx) * fr2 * hh
		p.w -= (p.w - gy) * fr2 * hh
	b.h = p
	var dist := sqrt(p.x * p.x + p.y * p.y)
	var roche := roche_h(b)
	var touch := contact_h(b)
	var solid := _solid(b)
	# Твёрдое тело не тянется картинкой: его рвёт движок разрушения.
	b.stretch = 0.0 if solid else smoothstep(roche * 1.5, roche, dist) * (1.0 if roche > touch else 0.35)
	b.t = float(b.t) + delta
	# Мир помнит, где тело: для HUD и отрисовки.
	var wp: Vector2 = stage.body.to_global(Vector2(p.x, -p.y) * h)
	b.r = wp.length()
	b.a = wp.angle()
	if dist > 2.4:
		# Ушло за сферу Хилла: снова свободное, со своей скоростью.
		var s := h * HILL_W
		b["v"] = (Vector2(p.z, -p.w) * s).rotated(float(stage.ang))
		b.erase("drift")
		b.vr = 0.0
		b.state = "free"
		b.stretch = 0.0
		b.cd = 4.0
		return true
	if b.kind == "minineptune" and not b.get("core", false) and dist < roche:
		_strip_envelope(b, p, h)
		return true
	if solid:
		# Движку тело отдаём чуть раньше предела Роша: трещины пойдут сами,
		# когда прилив превысит прочность. Плотное (железо) — у самых облаков:
		# прилив его не берёт, а напор атмосферы и удар — может.
		var at := roche * HANDOVER if roche > touch else touch * 1.6
		if dist < at * 1.15 and not b.has("snap"):
			b["snap"] = _snapshot(b)   # снимок готов к следующему кадру
		if dist < at:
			_to_engine(b, p, h, roche > touch)
			return false
		if float(b.t) > 24.0:
			# Долго кружит далеко: без движка, чтобы куски не улетали из сферы Хилла.
			_hit_whole(b, p, h)
			return false
		return true
	if roche > touch and dist < roche:
		_tear(b, p, h)
		return false
	if dist < touch or float(b.t) > 24.0:
		# Плотное тело прилив не рвёт: оно врезается целым.
		_hit_whole(b, p, h)
		return false
	return true


## Твёрдое ли тело (его ломает движок), или газ (рвётся лентой).
func _solid(b: Dictionary) -> bool:
	if b.kind in ["rival", "dwarf"]:
		return false
	if b.kind == "minineptune":
		return b.get("core", false)
	return true


## Тело уходит в движок разрушения. Оно летит дальше само, под тем же
## тяготением; прилив, удары и атмосфера ломают его по прочности вещества.
## Награда — в миг, когда тело треснуло (или врезалось целым).
func _to_engine(b: Dictionary, p: Vector4, h: float, tidal: bool) -> FracWorld.Source:
	var from := Vector2(p.x, -p.y) * h
	# Движок живёт в твоей системе: скорость тела относительно тебя.
	var vel := Vector2(p.z, -p.w) * h * HILL_W - _pv_local()
	var gain := _gain(b)
	var snap: Dictionary = b.get("snap", {})
	if snap.is_empty():
		snap = _snapshot(b)
	b.erase("snap")
	var zoom := maxf(stage.camera.zoom.x, 0.001)
	var rad := maxf(rad_of(b), 6.0 / zoom)
	var m: float = b.m
	# Сколько ячеек: крупное рядом с тобой режется мельче, мелочь — горсткой.
	var qk := clampf(sqrt(m / maxf(float(stage.earths) * 0.1, 0.001)), 0.0, 1.0)
	var cells := roundi(lerpf(7.0, 34.0, qk) + clampf(rad * zoom / 6.0, 0.0, 10.0))
	var mat: String = str(b.mat) if FracMat.MATS.has(str(b.mat)) else "rock"
	if b.kind == "comet":
		mat = "ice"
	if FracMat.MATS.has(str(b.get("sub", ""))):
		mat = str(b.sub)
	var o := {
		"pos": from, "vel": vel, "w": float(b.spin_rate) * 0.5, "rad": rad, "mass": gain, "mat": mat,
		"cells": cells, "seed": fmod(float(b.seed), 97.0) / 97.0, "r_crit": roche_h(b) * h,
		"inflow": 0.22, "sink": _frac_sink, "notify": _frac_notify,
		"tag": {"b": b, "gain": gain, "pay": _pay_k(b), "done": false, "big": qk > 0.6, "tidal": tidal},
	}
	if b.kind in ["comet", "rubble"]:
		# Рыхлое: груда и кометное ядро держатся только тяготением.
		o["inflow"] = 0.3
		o["coh"] = 0.05
	elif b.kind in ["trojan", "binary", "icedwarf"]:
		o["coh"] = minf(float(FracMat.get_mat(mat)["coh"]), 0.3)
	if not snap.is_empty():
		o["tex"] = snap.tex
		o["vp"] = snap.vp
		o["disc"] = snap.disc
		o["tex_rot"] = float(stage.ang)
	else:
		o["col"] = (MATS[mat]["col"] as Color) if MATS.has(mat) else Color(0.8, 0.85, 0.9)
	if b.mat == "lava":
		o["heat"] = 1.0
	elif str(GameState.giant.get("flavor", "")) == "giant_hot":
		o["heat"] = float(FracMat.get_mat(mat)["heat"]) + 0.15
	var src := frac.spawn_body(o)
	if (float(b.m) > 0.4 and float(b.m) > float(stage.earths) * 0.02) or b.kind in ["icedwarf", "superearth", "minineptune"]:
		# Крупное тело ломается на глазах: камера подъезжает.
		stage.focus(from * 0.6, 5.0, 0.9)
	return src


## Масса из движка: пыль и куски ушли в облака.
func _frac_sink(m: float, chunk: bool, at: Vector2, size: float, src: FracWorld.Source) -> void:
	var t: Dictionary = src.tag
	stage.earths += m
	stage.pay(m * float(t.pay) * (Skills.stat("giant_impact") if chunk else 1.0))
	if not chunk or size <= 0.0:
		return
	var r := _giant_r()
	var b: Dictionary = t.b
	# Кусок вошёл в облака на десятках км/с: короткий шлейф и тёмный след,
	# как у осколков кометы Шумейкеров — Леви 9. Мелочь — без шлейфа.
	if size > r * 0.02:
		stage.body.scar(at.normalized(), size * 0.6, FracMat.get_mat(src.mat_name).get("scar", Color(0.2, 0.14, 0.11)))
		var np := int(t.get("plumes", 0))
		if tides.plumes.size() < 6 and np < 3 and size > r * 0.035:
			t["plumes"] = np + 1
			var smoke: Color = MATS[b.mat]["col"] if MATS.has(b.mat) else Color(0.6, 0.55, 0.5)
			tides.plume(at.normalized() * r * 0.97, clampf(r * 0.02 + size * 0.5, r * 0.025, r * 0.09), smoke.darkened(0.45), float(b.seed) + size, 2.4)


func _frac_notify(ev: String, src: FracWorld.Source) -> void:
	var t: Dictionary = src.tag
	if t.done:
		return
	var b: Dictionary = t.b
	match ev:
		"break", "done":
			t.done = true
			# Кольца нет (автор: «никаких орбит»): всё разорванное падает в тебя.
			_reward(b, float(t.gain))
		"hit":
			# Не треснуло и врезалось целым: огненный след, жар оболочки.
			t.done = true
			stage.body.flash()
			stage.body.impact_heat = minf(stage.body.impact_heat + 0.25 * clampf(float(b.get("q", 0.05)) * 4.0, 0.2, 1.0), 1.0)
			_composition_hit(b, 0.5)
			_reward(b, float(t.gain), "hit")


## Часть разорванного приливом тела остаётся на орбите и ложится в кольцо.
## Доля — по веществу (лёд больше всех, железо — нисколько), по гиганту
## (ледяной держит кольца лучше, горячий хуже, плотный тянет обломки вниз)
## и по твоему составу (ледяное и титан — кольца гуще, металл — реже).
func _to_ring(mat: String, gain: float) -> void:
	var fm := FracMat.get_mat(mat)
	var share := float(fm.get("ring", 0.0))
	if share <= 0.0:
		return
	share *= {"giant_ice": 1.4, "giant_hot": 0.5, "giant_dense": 0.75, "giant_dark": 1.0}.get(_flavor(), 1.0)
	share *= {"ice": 1.3, "titan": 1.2, "metal": 0.7, "chondrite": 1.1}.get(GameState.body_type(), 1.0)
	var add := gain * share
	if add <= 0.0:
		return
	var col: Color = fm.get("ring_col", Color(0.7, 0.68, 0.65))
	var old: float = stage.ring_m
	var k := add / maxf(old + add, 1e-6)
	if GameState.body_type() == "neutral" and old > 0.0 and absf(col.v - (stage.ring_col as Color).v) > 0.08:
		# Переходное: новое вещество ложится своей полосой, не смешиваясь.
		stage.ring_col2 = (stage.ring_col2 as Color).lerp(col, maxf(k, 0.35))
	else:
		stage.ring_col = (stage.ring_col as Color).lerp(col, k if old > 0.0 else 1.0)
		if old <= 0.0:
			stage.ring_col2 = col.darkened(0.25)
	stage.ring_m = old + add
	if old <= 0.0 and add > 0.01:
		var line := "обломки легли на орбиту, у края кольцо слипается в луны"
		if GameState.once("ring", line):
			stage.hud.caption("Своё кольцо", line, 3.5)


## У предела Роша тело рвётся: нитка обломков и пылевая струя.
func _tear(b: Dictionary, p: Vector4, h: float) -> void:
	var info: Dictionary = KINDS[b.kind]
	var m: float = b.m
	var gain := _gain(b)
	var share_dust := 0.65 if b.kind != "rival" else 0.85
	# Нить: вещество закручивается к тебе спиралью прямого вращения и уходит
	# в облака. Траектория в системе гиганта: летит с тобой, не ломается.
	var pal: String = str(b.mat)
	if b.kind == "rival":
		pal = "rival"
	elif b.kind == "minineptune" and not b.get("core", false):
		pal = "nep"
	var big := clampf(float(b.m) / maxf(float(stage.earths) * 0.1, 0.01), 0.0, 3.0)
	var opts := {"T": 3.2 + 0.5 * big, "Ls": 1.6 + 0.7 * big, "turns": _rng.randf_range(0.95, 1.35)}
	if b.kind == "rival":
		opts = {"T": 4.8, "Ls": 3.6, "turns": 1.4}
	var from := Vector2(p.x, -p.y) * h
	# Тело снимается в текстуру своим шейдером: дальше ломается именно оно.
	var snap := _snapshot(b)
	var solid: bool = not (b.kind in ["rival", "minineptune", "comet"]) or b.get("core", false)
	var pearls := clampi(6 + int(m * 2.0), 7, 14) if solid and not snap.is_empty() else 0
	opts["snap"] = snap
	opts["shards"] = pearls
	if (float(b.m) > 0.4 and float(b.m) > float(stage.earths) * 0.02) or b.kind in ["rival", "icedwarf", "superearth", "minineptune"]:
		# Крупное тело ломается на глазах: камера подъезжает.
		stage.focus(from * 0.6, 4.5, 0.9)
	opts["rad"] = maxf(rad_of(b), 6.0 / maxf(stage.camera.zoom.x, 0.001))
	opts["gain_shards"] = gain * (1.0 - share_dust)
	if solid or b.kind == "comet":
		# Твёрдое тело рассыпается, как валун: куски, обломки, пыль — каждый
		# со скоростью тела в миг разрыва, без остановки.
		var vel := Vector2(p.z, -p.w) * h * HILL_W - _pv_local()
		var flv := str(GameState.giant.get("flavor", ""))
		# Сколько всего рисовать — по размеру тела рядом с тобой: мелочь
		# (рой обломков, планетезималь) тонет тихой горсткой, крупное
		# тело (зародыш, суперземля) рассыпается на глазах.
		var qk := clampf(sqrt(m / maxf(float(stage.earths) * 0.1, 0.001)), 0.0, 1.0)
		var dopts := {"snap": snap, "chunks": (clampi(2 + int(qk * 5.0), 2, 7) if qk > 0.25 else 0) if pearls > 0 else 0, "rad": opts["rad"],
			# У звезды горячий гигант: пыль и так тёплая; в холодной зоне — нет.
			"hot_k": 0.15 if flv == "giant_hot" else 0.0,
			"frags": roundi(lerpf(3.0, 28.0, qk)),
			"dust": roundi(lerpf(25.0, 220.0, qk))}
		var dpal := pal
		if b.kind == "comet":
			dpal = "ice"
		tides.spawn_debris(from, vel, gain, _pay_k(b), dpal, float(b.seed), dopts)
		_reward(b, gain)
		return
	tides.spawn(from, "spiral", gain * share_dust, _pay_k(b), pal, float(b.seed), rad_of(b) * (3.0 if b.kind == "rival" else 2.6), opts)
	if pearls == 0:
		var rest := gain * (1.0 - share_dust)
		stage.earths += rest
		stage.pay(rest * _pay_k(b))
	_reward(b, gain)


## Снимок тела в текстуру его же шейдером (для кусков и цвета пыли).
func _snapshot(b: Dictionary) -> Dictionary:
	var info: Dictionary = KINDS[b.kind]
	var view: String = info["view"]
	if b.get("core", false):
		view = "embryo"
	if view == "comet":
		return {}
	var S := 192
	var vp := SubViewport.new()
	vp.size = Vector2i(S, S)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var light := (-pos_of(b)).normalized()
	var disc := 0.36
	# Снимок — тот же вид, что и у целого тела (без накала: прилив не греет).
	var heat := 0.85 if b.mat == "lava" else 0.0
	match view:
		"moon":
			var mv := MoonView.new()
			vp.add_child(mv)
			mv.put(Vector2(S, S) * 0.5, S / 2.2, int(MATS[b.mat]["moon"]) if MATS.has(b.mat) else 0, light, fmod(float(b.seed), 10.0), float(b.spin), 1.0, heat, 1.0)
			disc = 1.0 / 2.2
		"embryo":
			var node := ColorRect.new()
			node.size = Vector2(S, S)
			var m := ShaderMaterial.new()
			m.shader = preload("res://shaders/embryo.gdshader")
			var big: bool = b.kind == "superearth" or b.get("core", false)
			m.set_shader_parameter("style", int(MATS[b.mat]["embryo"]) if MATS.has(b.mat) else 0)
			m.set_shader_parameter("light_dir", light)
			m.set_shader_parameter("spin", b.spin)
			m.set_shader_parameter("tilt", b.tilt)
			m.set_shader_parameter("seed", fmod(float(b.seed), 1.0))
			m.set_shader_parameter("magma", 0.85 if b.mat == "lava" else heat)
			m.set_shader_parameter("atmo", 0.55 if big else 0.1)
			m.set_shader_parameter("veil", 0.8 if big and b.mat == "carbon" else 0.0)
			m.set_shader_parameter("ocean", 0.6 if big and b.mat == "rock" else 0.0)
			m.set_shader_parameter("frost", 0.9 if b.mat == "ice" else 0.0)
			m.set_shader_parameter("clouds", 0.5 if big and b.mat == "rock" else 0.0)
			m.set_shader_parameter("atmo_col", Color(0.9, 0.7, 0.45) if b.mat == "carbon" else Color(0.55, 0.75, 1.0))
			node.material = m
			vp.add_child(node)
		"giant":
			var node := ColorRect.new()
			node.size = Vector2(S, S)
			var m := ShaderMaterial.new()
			m.shader = preload("res://shaders/giant_planet.gdshader")
			m.set_shader_parameter("use_map", true)
			var look: Array = NEPTUNE_LOOK if b.kind == "minineptune" else RIVAL_LOOKS[int(b.look)]
			var key := "nep" if b.kind == "minineptune" else "rv%d" % int(b.look)
			m.set_shader_parameter("map", _map_for(key, look, 0.17 + 0.23 * int(b.look)))
			m.set_shader_parameter("haze_col", Color(0.62, 0.74, 0.95))
			m.set_shader_parameter("light_dir", light)
			m.set_shader_parameter("spin", float(b.spin) * 3.0)
			m.set_shader_parameter("tilt", 0.1)
			node.material = m
			vp.add_child(node)
	tides.add_child(vp)
	return {"vp": vp, "tex": vp.get_texture(), "disc": disc}


## Мини-нептун у предела Роша своей оболочки: газ срывает лентой, ядро
## летит дальше по спирали (и рвётся или врезается уже как каменное/ледяное).
func _strip_envelope(b: Dictionary, p: Vector4, h: float) -> void:
	var env: float = float(b.m) * 0.7
	var col := (NEPTUNE_LOOK[0] as Color).lerp(NEPTUNE_LOOK[1], 0.3)
	var from := Vector2(p.x, -p.y) * h
	stage.focus(from * 0.6, 4.5, 0.8)
	tides.spawn(from, "spiral", env * 0.6, 1.2, "nep", float(b.seed) + 3.0, rad_of(b) * 3.6, {"T": 4.4, "Ls": 3.2, "turns": 1.3, "snap": _snapshot(b)})
	stage.earths += env * 0.4
	stage.pay(env * 0.4 * 1.2)
	b.m = float(b.m) - env
	b["core"] = true
	if b.get("rings", false):
		# Кольца — лёд: их срывает вместе с оболочкой отдельной светлой лентой.
		b.erase("rings")
		tides.spawn(from * 1.04, "spiral", env * 0.05, 2.0, "ring", float(b.seed) + 7.0, rad_of(b) * 1.4, {"T": 3.4, "Ls": 2.0, "turns": 1.0})
	if b.mat == "gas":
		b.mat = "ice" if float(b.r) > GameData.SNOW_LINE else "rock"
	b.stretch = 0.0
	stage.body.flash()
	if not _said.has("envelope"):
		_said["envelope"] = true
		stage.hud.caption("Оболочку сорвало", "газ мини-нептуна рыхлый, и прилив срывает его первым. Осталось плотное ядро: оно ещё летит по спирали", 4.0)
	else:
		stage.hud.toast("Мини-нептун без оболочки: +%s масс Земли газа, ядро ещё летит" % String.num(env * 0.4, 1).replace(".", ","), col.lerp(Color.WHITE, 0.4))


## Плотное тело дошло до облаков целым: огненный шар и шрам, без ленты.
func _hit_whole(b: Dictionary, p: Vector4, h: float) -> void:
	var gain := _gain(b)
	stage.earths += gain
	stage.pay(gain * _pay_k(b) * Skills.stat("giant_impact"))
	var dir := Vector2(p.x, -p.y).normalized()
	var r := _giant_r()
	stage.body.scar(dir, rad_of(b) * 0.7)
	stage.body.flash()
	stage.body.flash()
	stage.body.impact_heat = minf(stage.body.impact_heat + 0.25 * clampf(float(b.get("q", 0.05)) * 4.0, 0.2, 1.0), 1.0)
	# Целое тело входит в облака: шлейф по размеру тела, дым его цвета.
	var smoke: Color = MATS[b.mat]["col"] if MATS.has(b.mat) else Color(0.4, 0.33, 0.26)
	tides.plume(dir * r * 0.97, clampf(rad_of(b) * 1.6, r * 0.05, r * 0.2), smoke.darkened(0.4), float(b.seed), 3.0)
	_composition_hit(b, 0.5)
	_reward(b, gain, "hit")


## Гигантский удар: таран с разгона. Вспышка, ударная волна по облакам,
## выбитое вещество кольцом, раскалённая оболочка. Что ещё, решает вещество.
func _giant_impact(b: Dictionary, wp: Vector2, vrel: float) -> void:
	var loc: Vector2 = stage.body.to_local(wp)
	var dir := loc.normalized()
	var q := clampf(float(b.m) / float(stage.earths), 0.0, 1.0)
	var speed_bonus := clampf((vrel / IMPACT_V - 1.0) * 0.3, 0.0, 0.3)
	var gain := _gain(b) * (1.0 + speed_bonus)
	stage.earths += gain * 0.85
	stage.pay(gain * 0.85 * _pay_k(b) * Skills.stat("giant_impact") * 1.3)
	var r := _giant_r()
	var h: float = stage.hill()
	# Огонь — шлейф над облаками (ниже), без светящихся шаров. По облакам
	# бежит волна: тёмное кольцо, как волны от ударов кометы в 1994-м.
	# Всё привязано к гиганту (loc): он летит дальше, а след остаётся на нём.
	var at := dir * r * 0.9
	stage.focus(at * 0.8, 4.0, 0.7)
	_flashes.append({"p": at * 0.95, "loc": true, "t": 0.0, "dur": 6.0, "size": r * 1.5, "col": Color(0.1, 0.075, 0.06), "ring": true})
	stage.body.scar(dir, rad_of(b) * 1.3)
	stage.body.impact_heat = minf(stage.body.impact_heat + 0.45 + q, 1.0)
	# Выбитое вещество: две ленты из точки удара, с прямым вращением —
	# они обовьют тебя и упадут обратно позже.
	var hd := Vector2(dir.x, -dir.y)
	var tang := hd.orthogonal()
	var col: Color = MATS[b.mat]["col"] if MATS.has(b.mat) else Color(0.85, 0.78, 0.66)
	var hot_col := col.lerp(Color(1.0, 0.7, 0.45), 0.35)
	# Шлейф: огненный веер поднимается из облаков и опадает дымом цвета тела.
	var smoke: Color = MATS[b.mat]["col"] if MATS.has(b.mat) else Color(0.4, 0.33, 0.26)
	tides.plume(dir * r * 0.96, r * (0.4 + 0.4 * q), smoke.darkened(0.35), float(b.seed), 3.4)
	# Само тело врезается и крошится в облаках: напор атмосферы рвёт его
	# спереди назад. Выбитое вещество — брызги расплава по дугам: они
	# падают обратно или ложатся в диск, каждая по своей орбите.
	var rel_l: Vector2 = (_vel_of(b) - _player_vel()).rotated(-float(stage.ang))
	var zoom := maxf(stage.camera.zoom.x, 0.001)
	var rad := maxf(rad_of(b), 6.0 / zoom)
	var mat: String = str(b.mat) if FracMat.MATS.has(str(b.mat)) else "rock"
	var snap := _snapshot(b)
	var o := {
		"pos": loc - rel_l.normalized() * rad * 0.2, "vel": rel_l, "rad": rad, "mass": gain * 0.15, "mat": mat,
		"cells": 26, "seed": fmod(float(b.seed), 97.0) / 97.0, "r_crit": r * 3.0,
		"impact_at": -dir * rad * 0.8, "inflow": 0.3, "sink": _frac_sink, "notify": func(_e, _s) -> void: pass,
		"tag": {"b": b, "gain": gain, "pay": _pay_k(b), "done": true, "big": true},
	}
	if not snap.is_empty():
		o["tex"] = snap.tex
		o["vp"] = snap.vp
		o["disc"] = snap.disc
		o["tex_rot"] = float(stage.ang)
	else:
		o["col"] = col
	var src := frac.spawn_body(o)
	var vesc := sqrt(2.0) * _ffield.v_ref()
	var hot := {"ice": 0.0, "metal": 0.7, "carbon": 0.6, "lava": 1.0}.get(mat, 0.85) as float
	# Конус выброса наклонён по ходу удара (косой удар бросает вперёд).
	var fwd := rel_l.normalized()
	var ej_dir := (dir + (fwd - dir * fwd.dot(dir)) * 0.6).normalized()
	frac.spray(src, dir * r * 1.01, ej_dir, int(70 + 60 * q), 0.0, vesc * (0.45 + 0.25 * q), 0.45, hot, rad * 0.08)
	frac.spray(src, dir * r * 1.01, dir, 40, 0.0, vesc * 0.3, 0.9, hot * 0.7, rad * 0.05)
	# Брызги веером: мелкая раскалённая пыль без массы.
	var gas: GasParticles = stage.body.gas
	var c0 := hd * contact_h(b)
	for i in 30:
		var a := _rng.randfn(0.0, 0.55)
		var vv := hd.rotated(a) * _rng.randf_range(0.6, 1.8) - tang * _rng.randf_range(0.2, 0.9)
		gas.add(c0.x, c0.y, vv.x, vv.y, _rng.randf_range(0.008, 0.02), _rng.randf_range(0.4, 0.75), hot_col.darkened(0.15), -1)
	# Отдача: тело приносит свой импульс.
	var rel: Vector2 = (_vel_of(b) - _player_vel()).rotated(-float(stage.ang))
	stage.kick += rel * q * 0.6
	_take_sat(b)
	var extra := _composition_hit(b, 1.0)
	if stage.moons > 0 and _rng.randf() < 0.25 + 0.4 * q:
		stage.moons -= 1
		stage.body.moons = stage.moons
		stage.body.steal(-loc * 6.0)
		extra += " · удар выбил луну"
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(220)
	if not _said.has("impact"):
		_said["impact"] = true
		stage.hud.caption("Гигантский удар", "крупное тело с разгона: его масса твоя, оболочка раскалилась, выбитое вещество упадёт обратно", 4.0)
	_reward(b, gain, "impact", extra)


## Удар по веществу: у каждого состава свой след.
func _composition_hit(b: Dictionary, k: float) -> String:
	var f := _flavor()
	match str(b.mat):
		"carbon":
			# Сажа расходится по облакам: гигант темнеет на минуту-другую.
			stage.body.soot = minf(stage.body.soot + 0.6 * k, 1.0)
			return " · сажа затянула облака"
		"metal":
			# Железо тонет к ядру: динамо крепче.
			var add := 0.03 * k * (2.0 if f == "giant_dense" else 1.0)
			GameState.giant["field_bonus"] = minf(float(GameState.giant.get("field_bonus", 0.0)) + add, 0.3)
			return " · железо ушло к ядру, поле крепче"
		"ice":
			# Лёд испаряется в кольцо пара: из него соберётся луна.
			stage.moon_prog += 0.6 * k * (1.5 if f == "giant_ice" else 1.0)
			return " · лёд ушёл кольцом пара на луну"
		"lava":
			stage.body.impact_heat = minf(stage.body.impact_heat + 0.3 * k, 1.0)
			stage.body.heat_hold = 2.0
			return " · расплав: жар держится вдвое дольше"
		"rock":
			GameState.add_chondrules(int(round(3.0 * k)), stage.body.position)
			return " · брызги расплава: хондры +%d" % int(round(3.0 * k))
	return ""


func _gain(b: Dictionary) -> float:
	if b.kind == "rival":
		return float(b.m)
	var info: Dictionary = KINDS[b.kind]
	return float(b.m) + float(info["extra"]) * float(stage.earths)


func _pay_k(b: Dictionary) -> float:
	var k: float = MATS[b.mat]["pay"] if MATS.has(b.mat) else 1.0
	if b.mat == "carbon":
		k *= Skills.stat("giant_soot")
	if GameState.body_type() == "venus" and b.mat == "carbon":
		k *= 1.3
	return k


## Награды за тело сразу, как его порвало: по веществу и ядру.
func _reward(b: Dictionary, gain: float, how := "tear", more := "") -> void:
	var info: Dictionary = KINDS[b.kind]
	var ch: int = int(info["ch"])
	var type := GameState.body_type()
	var f := _flavor()
	var extra := ""
	if type == "chondrite" and ch > 0:
		ch += 1 + ch / 2
	match str(b.mat):
		"ice":
			var mp := 0.08 + 0.12 * minf(float(b.m), 3.0)
			if f == "giant_ice":
				mp *= 2.0
			if type == "titan":
				mp *= 1.5
			stage.moon_prog += mp
			extra = " · лёд пошёл на луну"
		"metal":
			extra = " · железо: пыль ×3"
			if f == "giant_dense":
				GameState.giant["field_bonus"] = minf(float(GameState.giant.get("field_bonus", 0.0)) + 0.01 * minf(float(b.m), 3.0), 0.3)
				extra += ", поле крепнет"
		"carbon":
			extra = " · сажа: пыль ×%s" % String.num(_pay_k(b), 1).replace(".", ",")
		"lava":
			extra = " · раскалённое"
	if how == "hit":
		# Целым врезалось: обломков-хондр меньше, чем при разрыве.
		ch = ch / 2
	if ch > 0:
		GameState.add_chondrules(ch, stage.body.position)
		extra += " · хондры +%d" % ch
	if how != "tear":
		extra = more + extra
	var fem: bool = b.kind in ["comet", "planetesimal", "superearth", "binary"]
	var verb := ("Поглощён" if not fem else "Поглощена") if b.kind == "rival" else ("Разорвана" if fem else "Разорван")
	var neut: bool = b.kind == "irondwarf"
	if neut:
		verb = "Разорвано"
	if how == "hit":
		verb = "Врезалось" if neut else ("Врезалась" if fem else "Врезался")
	elif how == "impact":
		verb = "Таран:"
	var num := String.num(gain, 1 if gain >= 0.1 else 2).replace(".", ",")
	stage.hud.toast("%s %s: +%s масс Земли%s" % [verb, info["name"], num, extra],
		(MATS[b.mat]["col"] as Color).lerp(Color.WHITE, 0.5) if MATS.has(b.mat) else Color(1.0, 0.86, 0.7))
	body_eaten.emit(b)


## Пыль разорванного тела села в твой диск.
func _on_debris(id: int) -> void:
	if not _debris.has(id):
		return
	var d: Dictionary = _debris[id]
	stage.earths += float(d.per)
	stage.pay(float(d.per) * float(d.pay))
	d.left = int(d.left) - 1
	if int(d.left) <= 0:
		_debris.erase(id)


func _step_pearls(delta: float, h: float) -> void:
	var g := 3.0 * pow(Skills.stat("giant_reach"), 3.0)
	var dt := delta * HILL_W
	var steps := maxi(1, ceili(dt / 0.02))
	var hh := dt / steps
	var keep := []
	for pr in _pearls:
		var p: Vector4 = pr.h
		var hit := false
		for k in steps:
			p = GasParticles.hill_step(p, hh, g, 0.25)
			if p.x * p.x + p.y * p.y < CAPTURE * CAPTURE:
				hit = true
				break
		pr.h = p
		pr.spin = float(pr.spin) + delta * 0.06
		if hit:
			_impact(pr, p)
		elif absf(p.x) < 8.0 and absf(p.y) < 10.0:
			keep.append(pr)
	_pearls = keep


## Обломок врезался в облака: огненный шар на краю диска, как у Юпитера в 1994-м.
func _impact(pr: Dictionary, p: Vector4) -> void:
	var gain: float = float(pr.gain)
	stage.earths += gain
	stage.pay(gain * float(pr.pay) * Skills.stat("giant_impact"))
	stage.body.flash()
	stage.body.scar(Vector2(p.x, -p.y).normalized(), float(pr.r))
	var r: float = stage.body.body_r * stage.body.inflate
	var at: Vector2 = stage.body.to_global(Vector2(p.x, -p.y).normalized() * r * 0.97)
	_flashes.append({"p": at, "t": 0.0, "dur": 1.4, "size": r * 0.35 * clampf(float(pr.r) / 8.0, 0.5, 1.6), "col": Color(1.0, 0.82, 0.6)})


func _into_star(b: Dictionary) -> void:
	if b.get("slung", false):
		var v := float(b.m) * 2.5 * Skills.stat("giant_sling")
		stage.earths += 0.0
		stage.pay(v)
		GameState.add_chondrules(1 + int(b.m), stage.body.position)
		stage.hud.toast("%s упал в звезду после твоей пращи: пыль и хондры" % _cap(str(KINDS[b.kind]["name"])), Color(1.0, 0.8, 0.55))


func _ejected(b: Dictionary) -> void:
	if b.get("slung", false):
		var ch := 2 + int(float(b.m) * 0.5)
		GameState.add_chondrules(ch, stage.body.position)
		stage.pay(float(b.m) * 1.5 * Skills.stat("giant_sling"))
		stage.hud.toast("%s выброшен из системы: хондры +%d" % [_cap(str(KINDS[b.kind]["name"])), ch], Color(0.75, 0.85, 1.0))


## Гравитационная праща: тело не по зубам, но его можно бросить.
func _sling(b: Dictionary, p: Vector2, gpos: Vector2) -> void:
	var e: float = stage.earths
	var m: float = b.m
	# Пролёт рядом: тело уходит по ходу твоего движения (гравитационный
	# манёвр), стоишь — просто от тебя. К звезде или прочь — по тому, куда
	# смотрит бросок.
	var pv: Vector2 = _player_vel()
	var dir := pv.normalized() if pv.length() > 80.0 else (p - gpos).normalized()
	var power := SLING * Skills.stat("giant_sling") * pow(clampf(e / maxf(m, 0.01), 0.3, 8.0), 0.4)
	var rad := Vector2.from_angle(float(b.a))
	var out := signf(dir.dot(rad))
	if out == 0.0:
		out = 1.0
	b.vr = float(b.vr) + dir.dot(rad) * power
	b["drift"] = (b.get("drift", Vector2.ZERO) as Vector2) + (dir - rad * dir.dot(rad)) * power * 0.5
	b.cd = 5.0
	b["slung"] = true
	# Отдача: тебя толкает в другую сторону, тем сильнее, чем тяжелее тело.
	stage.kick -= dir.rotated(-float(stage.ang)) * 260.0 * clampf(m / e, 0.05, 1.0)
	stage.pay(m * 0.4 * Skills.stat("giant_sling"))
	if not _said.has("sling"):
		_said["sling"] = true
		stage.hud.caption("Гравитационная праща", "тело слишком велико, чтобы съесть, но пролёт рядом бросает его по ходу твоего движения: к звезде или прочь из системы", 4.5)
	elif _sling_cd <= 0.0:
		stage.hud.toast("Праща: %s летит %s" % [KINDS[b.kind]["name"], "наружу" if out > 0.0 else "к звезде"], Color(0.8, 0.9, 1.0))
	_sling_cd = 2.0


## Тяжёлое тело тянет к себе, а вплотную рвёт у тебя газ и луны.
func _danger(b: Dictionary, delta: float, gpos: Vector2, h: float) -> void:
	var p := pos_of(b)
	var to := p - gpos
	var d := to.length()
	var bh := hill_of(b)
	if d > 3.2 * bh:
		return
	var e: float = stage.earths
	var guard := 1.0 + Skills.stat("giant_guard")
	var pull := 240.0 * sqrt(clampf(float(b.m) / e, 1.0, 50.0)) / pow(maxf(d / bh, 0.6), 2.0) / guard
	var loc: Vector2 = to.normalized().rotated(-float(stage.ang))
	# Сквозь друг друга гиганты не проходят: ближе пары радиусов тесный
	# пролёт швыряет обоих в стороны (праща), лёгкого — сильнее.
	var touch := (_giant_r() + rad_of(b)) * 1.35
	if d < touch:
		var np := gpos + to.normalized() * touch
		b.r = np.length()
		b.a = np.angle()
		stage.kick -= loc * 900.0 * delta * clampf(float(b.m) / e, 1.0, 4.0)
		pull = 0.0
	stage.kick += loc * pull * delta
	if not _said.has("danger"):
		_said["danger"] = true
		stage.hud.caption("Тело тяжелее тебя", "%s тянет тебя к себе. Подойдёшь вплотную — вырвет луну и сорвёт часть газа" % _cap(str(KINDS[b.kind]["name"])), 4.0)
	if d < 1.3 * bh + h * 0.3 and _hit_cd <= 0.0:
		_hit_cd = 6.0
		# Тесный пролёт: тебя швыряет, газ уходит к нему, луна улетает.
		stage.kick -= loc * 700.0 / guard
		var lost: float = e * 0.035 / guard
		stage.earths -= lost
		b.m = float(b.m) + lost
		var text := "%s сорвал с тебя %s масс Земли" % [_cap(str(KINDS[b.kind]["name"])), String.num(lost, 1).replace(".", ",")]
		if stage.moons > 0 and _rng.randf() < 0.7 / guard:
			stage.moons -= 1
			stage.body.moons = stage.moons
			stage.body.steal(stage.body.to_local(p))
			text += " и увёл луну"
		stage.hud.toast(text, Color(1.0, 0.55, 0.45))
		var gas: GasParticles = stage.body.gas
		var dir := Vector2(loc.x, -loc.y)
		for i in 60:
			var s := _rng.randf()
			gas.add(dir.x * (0.6 + s), dir.y * (0.6 + s), dir.x * 1.5 + _rng.randfn(0.0, 0.2), dir.y * 1.5 + _rng.randfn(0.0, 0.2),
				0.05, 0.4, Color(0.9, 0.8, 0.66), -1)


## Средние тела слегка тянут к себе: видно, что они массивны.
func _danger_soft(b: Dictionary, delta: float, gpos: Vector2, h: float) -> void:
	if b.kind != "rival":
		return
	var to := pos_of(b) - gpos
	var d := to.length()
	var bh := hill_of(b)
	if d > 2.5 * bh:
		return
	var loc: Vector2 = to.normalized().rotated(-float(stage.ang))
	stage.kick += loc * 90.0 / pow(maxf(d / bh, 0.7), 2.0) * delta


## Соперник глотает мелочь у себя под боком.
func _rival_feed(rv: Dictionary) -> void:
	var p := pos_of(rv)
	var bh := hill_of(rv) * 1.4
	for b in bodies:
		if b == rv or b.state != "free" or b.kind in ["rival", "dwarf"]:
			continue
		if float(b.m) > float(rv.m) * 0.1:
			continue
		if pos_of(b).distance_to(p) < bh:
			b.state = "rival_eat"
			b.t = 0.0
			b["host"] = rv.id
			rv.m = float(rv.m) + float(b.m)


## Карлик раскидывает всё на своём пути.
func _scatter_near(dw: Dictionary, delta: float) -> void:
	var p := pos_of(dw)
	var bh := hill_of(dw) * 3.0
	for b in bodies:
		if b == dw or b.state != "free":
			continue
		var d := pos_of(b).distance_to(p)
		if d < bh:
			var out := signf(float(b.r) - float(dw.r))
			b.vr = float(b.vr) + out * 300.0 * delta * (1.0 - d / bh)
			b["slung"] = false


## Твоя скорость в твоей же системе (x — от звезды), единицы мира.
func _pv_local() -> Vector2:
	return (stage.vel as Vector2).rotated(-float(stage.ang))


## Гигант сдвинулся. Захваченные тела летят своей дорогой в мире: их
## координаты относительно тебя сдвигаются целиком (скорость — мировая).
func shift(d: Vector2) -> void:
	var h: float = stage.hill()
	var dx := d.x / h
	var dy := -d.y / h
	for b in bodies:
		if b.state == "captured":
			b.h = _shift_one(b.h, dx, dy)
	for pr in _pearls:
		pr.h = _shift_one(pr.h, dx, dy)


static func _shift_one(p: Vector4, dx: float, dy: float) -> Vector4:
	return Vector4(p.x - dx, p.y - dy, p.z, p.w)


# --- Вихри у краёв щели ---

func spawn_vortex(r: float, dark := false, life := 70.0, force := false) -> Dictionary:
	if vortices.size() >= 2 and not force:
		return {}
	var v := {"r": r, "a": float(stage.ang) + _rng.randf_range(-0.25, 0.25), "t": 0.0, "life": life,
		"size": stage.hill() * 1.4, "seed": _rng.randf() * 10.0, "dark": dark, "inside": 0.0}
	vortices.append(v)
	if not _said.has("vortex"):
		_said["vortex"] = true
		stage.hud.caption("Вихрь у края щели", "газ на краю щели закрутился в вихрь, и в нём копится пыль: зайди в него", 4.0)
	return v


func in_vortex() -> Dictionary:
	var g: Vector2 = stage.body.position
	for v in vortices:
		var p := Vector2.from_angle(float(v.a)) * float(v.r)
		var loc := (p - g).rotated(-float(stage.ang))
		var s: float = v.size
		if pow(loc.x / s, 2.0) + pow(loc.y / (s * 2.6), 2.0) < 1.0:
			return v
	return {}


func acc_mul() -> float:
	return 1.6 if not in_vortex().is_empty() else 1.0


func _step_vortices(delta: float, gpos: Vector2, h: float) -> void:
	var keep := []
	var inside := in_vortex()
	for v in vortices:
		v.t = float(v.t) + delta
		if v == inside:
			v.inside = float(v.inside) + delta
			# Пыль вихря: хондры раз в несколько секунд, у тёмного — сажа.
			if int(float(v.inside) / 3.0) != int((float(v.inside) - delta) / 3.0):
				var f := _flavor()
				GameState.add_chondrules(2 if f == "giant_dense" else 1, stage.body.position)
				if f == "giant_ice":
					stage.moon_prog += 0.08
				if f == "giant_dark":
					stage.pay(stage.clump_gain(1.0) * 6.0)
		if float(v.t) < float(v.life):
			keep.append(v)
	vortices = keep


# --- Для HUD и бота ---

## Метки целей за краем экрана: самое крупное съедобное и опасности.
func markers() -> Array:
	var out := []
	var g: Vector2 = stage.body.position
	var best := {}
	var bd := INF
	var big := {}
	var bbig := INF
	var troj := {}
	var bt := INF
	for b in bodies:
		if b.state != "free" and b.state != "pass":
			continue
		var ro := role(b)
		var d := pos_of(b).distance_to(g)
		if ro == "danger" and d < 9000.0:
			out.append({"p": pos_of(b), "col": Color(1.0, 0.4, 0.32), "text": KINDS[b.kind]["name"]})
		elif ro == "merge":
			out.append({"p": pos_of(b), "col": UiTheme.GOLD, "text": "слияние"})
		elif ro == "big" and d < 7000.0:
			var sb := d / sqrt(float(b.m))
			if sb < bbig:
				bbig = sb
				big = b
		elif b.kind == "trojan" and d < bt:
			bt = d
			troj = b
		elif ro == "food" and float(b.m) > 0.4:
			var score := d / sqrt(float(b.m))
			if score < bd:
				bd = score
				best = b
	if not best.is_empty() and best.kind != "trojan":
		out.append({"p": pos_of(best), "col": Color(0.95, 0.85, 0.6), "text": KINDS[best.kind]["name"]})
	if not big.is_empty():
		out.append({"p": pos_of(big), "col": Color(1.0, 0.66, 0.36), "text": "таран: " + str(KINDS[big.kind]["name"])})
	if not troj.is_empty() and bt > 2500.0:
		out.append({"p": pos_of(troj), "col": Color(0.85, 0.9, 0.75), "text": "троянцы"})
	return out


## Ближайшая еда для бота, в мировых координатах; Vector2.INF — нет.
func nearest_food() -> Vector2:
	var g: Vector2 = stage.body.position
	var best := Vector2.INF
	var bd := INF
	for b in bodies:
		if b.state != "free":
			continue
		var ro := role(b)
		if ro != "food" and ro != "merge" and ro != "big":
			continue
		var d := pos_of(b).distance_to(g) / pow(float(b.m) + 0.2, 0.3)
		if d < bd:
			bd = d
			best = pos_of(b)
	return best


func nearest_danger() -> Vector2:
	var g: Vector2 = stage.body.position
	for b in bodies:
		if role(b) == "danger" and pos_of(b).distance_to(g) < 3.5 * hill_of(b):
			return pos_of(b)
	return Vector2.INF


# --- Вид ---

func _view(kind: String) -> CanvasItem:
	if not _pools.has(kind):
		_pools[kind] = []
		_used[kind] = 0
	var pool: Array = _pools[kind]
	var i: int = _used[kind]
	_used[kind] = i + 1
	if i < pool.size():
		var v: CanvasItem = pool[i]
		v.visible = true
		return v
	var node: Control
	match kind:
		"moon":
			node = MoonView.new()
		_:
			node = ColorRect.new()
			node.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var mat := ShaderMaterial.new()
			match kind:
				"embryo":
					mat.shader = preload("res://shaders/embryo.gdshader")
				"giant":
					mat.shader = preload("res://shaders/giant_planet.gdshader")
					mat.set_shader_parameter("use_map", true)
				"comet":
					mat.shader = preload("res://shaders/comet.gdshader")
					mat.set_shader_parameter("noise_tex", NoiseTex.get_tex())
				"vortex":
					mat.shader = preload("res://shaders/vortex.gdshader")
					mat.set_shader_parameter("noise_tex", NoiseTex.get_tex())
				"ring":
					mat.shader = preload("res://shaders/giant_ring.gdshader")
			node.material = mat
	add_child(node)
	pool.append(node)
	return node


## Карта облаков чужого гиганта печётся один раз на палитру.
func _map_for(key: String, look: Array, seed_v: float) -> Texture2D:
	if _maps.has(key):
		return (_maps[key] as SubViewport).get_texture()
	var vp := SubViewport.new()
	# Карта печётся один раз, а крупные соседи бывают шире экрана: 1024×512
	# (было 256×128 — на большом теле видно было мыло).
	vp.size = Vector2i(1024, 512)
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var rect := ColorRect.new()
	rect.size = Vector2(1024, 512)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/giant_map.gdshader")
	mat.set_shader_parameter("zone_col", look[0])
	mat.set_shader_parameter("belt_col", look[1])
	mat.set_shader_parameter("storm_col", look[2])
	mat.set_shader_parameter("seed", seed_v)
	mat.set_shader_parameter("spin_jet", seed_v * 3.0)
	rect.material = mat
	vp.add_child(rect)
	add_child(vp)
	_maps[key] = vp
	return vp.get_texture()


func _draw() -> void:
	if stage == null:
		return
	for k in _used.keys():
		_used[k] = 0
	_ring_list.clear()
	var cam: Camera2D = stage.camera
	var zoom: float = cam.zoom.x
	var px := 1.0 / maxf(zoom, 0.001)
	var vp := get_viewport_rect().size
	var half := vp.length() * 0.5 * px
	var cpos: Vector2 = cam.get_screen_center_position()
	var gpos: Vector2 = stage.body.position
	var h: float = stage.hill()
	var pulse := 0.5 + 0.5 * sin(_time * 3.0)
	for v in vortices:
		var p := Vector2.from_angle(float(v.a)) * float(v.r)
		if p.distance_to(cpos) > half + float(v.size) * 3.0:
			continue
		var node := _view("vortex") as ColorRect
		var s: float = v.size
		node.size = Vector2(s * 2.0, s * 2.0 * 2.6)
		node.pivot_offset = node.size * 0.5
		node.position = p - node.size * 0.5
		node.rotation = float(v.a)
		var m := node.material as ShaderMaterial
		var fl := f_life(v)
		m.set_shader_parameter("strength", fl)
		m.set_shader_parameter("time", _time)
		m.set_shader_parameter("seed", v.seed)
		m.set_shader_parameter("aspect", 2.6)
		m.set_shader_parameter("dark", 1.0 if v.dark else 0.0)
		m.set_shader_parameter("light_dir", Vector2(-1.0, 0.0))
		var look: Array = GameData.GIANT_LOOK.get(_flavor(), GameData.GIANT_LOOK["giant_cold"])
		m.set_shader_parameter("gas_col", (look[0] as Color).lerp(Color(0.8, 0.72, 0.6), 0.5))
		m.set_shader_parameter("dust_col", (look[1] as Color).darkened(0.2))
	for b in bodies:
		var p := pos_of(b)
		var rad := rad_of(b)
		if p.distance_to(cpos) > half + rad * 6.0 + (2000.0 if b.kind == "comet" else 0.0):
			continue
		_draw_body(b, p, rad, px, gpos, h, pulse)
	for pr in _pearls:
		var q: Vector4 = pr.h
		var wp: Vector2 = stage.body.to_global(Vector2(q.x, -q.y) * h)
		var d := sqrt(q.x * q.x + q.y * q.y)
		var heat := smoothstep(1.0, 0.45, d)
		var mv := _view("moon") as MoonView
		mv.put(wp, maxf(float(pr.r), 2.0 * px), int(MATS[pr.mat]["moon"]) if MATS.has(pr.mat) else 0, (-wp).normalized(), fmod(float(pr.seed), 10.0), float(pr.spin), 1.0, heat, 1.0)
	for k in _pools.keys():
		var pool: Array = _pools[k]
		for i in range(int(_used[k]), pool.size()):
			(pool[i] as CanvasItem).visible = false
	_draw_flashes()


func f_life(v: Dictionary) -> float:
	return smoothstep(0.0, 4.0, float(v.t)) * smoothstep(float(v.life), float(v.life) - 6.0, float(v.t))


func _draw_body(b: Dictionary, p: Vector2, rad: float, px: float, gpos: Vector2, h: float, pulse: float) -> void:
	var info: Dictionary = KINDS[b.kind]
	var light := (-p).normalized()
	var stretch: float = b.stretch
	var axis_ang := (gpos - p).angle()
	var heat := 0.0
	var fade := 1.0
	if b.state == "rival_eat":
		# Соперник глотает мелочь: тело тянется к нему и гаснет.
		var host := _body_by_id(int(b.get("host", -1)))
		var e := float(b.t)
		if not host.is_empty():
			var hp := pos_of(host)
			p = p.lerp(hp, e * e)
			axis_ang = (hp - p).angle()
		stretch = e
		fade = 1.0 - smoothstep(0.6, 1.0, e)
		heat = e * 0.6
	else:
		heat = stretch * 0.5
	if b.mat == "lava":
		heat = maxf(heat, 0.0)
	var view: String = info["view"]
	if b.get("core", false):
		view = "embryo"
	var min_px := {"moon": 5.0, "embryo": 8.0, "giant": 12.0, "comet": 3.0}
	rad = maxf(rad, float(min_px.get(view, 3.0)) * px)
	var role_s := role(b)
	if role_s == "danger" or role_s == "merge":
		# Метка вокруг тяжёлого тела: красная — бойся, золотая — можно слиться.
		var col := Color(1.0, 0.35, 0.28) if role_s == "danger" else UiTheme.GOLD
		draw_arc(p, hill_of(b), 0.0, TAU, 96, Color(col, 0.08 + 0.1 * pulse), 2.0 * px, true)
	elif role_s == "big" and b.state == "free":
		# Крупное: оранжевая дуга, ярче, когда скорости хватает на таран.
		var ok := (_vel_of(b) - _player_vel()).length() >= IMPACT_V * _impact_need()
		draw_arc(p, rad * 1.9, 0.0, TAU, 64, Color(1.0, 0.62, 0.32, (0.35 + 0.3 * pulse) if ok else 0.14), (2.5 if ok else 1.5) * px, true)
	if b.get("sat", false) and b.state == "free":
		_draw_sat(b, p, rad, light, px)
	match view:
		"moon":
			var pieces := int(info.get("pieces", 1))
			if b.kind == "binary":
				pieces = 2
			for i in pieces:
				var o := Vector2.ZERO
				var rr := rad
				if b.kind == "binary":
					# Пара кружит вокруг общего центра масс.
					var ph := _time * 0.22 + float(b.seed)
					o = Vector2.from_angle(ph) * rad * (1.1 if i == 0 else -1.5)
					rr = rad * (0.8 if i == 0 else 0.6)
				elif pieces > 1:
					o = Vector2(sin(float(b.seed) + i * 2.4), cos(float(b.seed) * 1.3 + i * 1.7)) * rad * 2.6
					rr = rad * (0.45 + 0.35 * fmod(i * 0.37, 1.0))
				var mv := _view("moon") as MoonView
				mv.put(p + o, rr, int(MATS[b.mat]["moon"]), light, fmod(float(b.seed) + i, 10.0), float(b.spin), 1.0, heat, 1.0)
				_shape(mv, axis_ang, stretch, fade)
		"embryo":
			var node := _view("embryo") as ColorRect
			var q := rad / 0.36
			node.size = Vector2(q, q)
			node.position = p - node.size * 0.5
			var m := node.material as ShaderMaterial
			m.set_shader_parameter("style", int(MATS[b.mat]["embryo"]))
			m.set_shader_parameter("light_dir", light.rotated(-axis_ang * signf(stretch)))
			m.set_shader_parameter("spin", b.spin)
			m.set_shader_parameter("tilt", b.tilt)
			m.set_shader_parameter("seed", fmod(float(b.seed), 1.0))
			var big: bool = b.kind == "superearth" or b.get("core", false)
			m.set_shader_parameter("magma", 0.85 if b.mat == "lava" else heat * 0.6)
			m.set_shader_parameter("atmo", 0.55 if big else 0.1)
			m.set_shader_parameter("veil", 0.8 if big and b.mat == "carbon" else 0.0)
			m.set_shader_parameter("ocean", 0.6 if big and b.mat == "rock" else 0.0)
			m.set_shader_parameter("frost", 0.9 if b.mat == "ice" else 0.0)
			m.set_shader_parameter("clouds", 0.5 if big and b.mat == "rock" else 0.0)
			m.set_shader_parameter("atmo_col", Color(0.9, 0.7, 0.45) if b.mat == "carbon" else Color(0.55, 0.75, 1.0))
			_shape(node, axis_ang, stretch, fade)
		"giant":
			var node := _view("giant") as ColorRect
			var q := rad / 0.36
			node.size = Vector2(q, q)
			node.position = p - node.size * 0.5
			var m := node.material as ShaderMaterial
			var look: Array
			var key := ""
			if b.kind == "minineptune":
				look = NEPTUNE_LOOK
				key = "nep"
			elif b.kind == "dwarf":
				look = DWARF_LOOK
				key = "dwarf"
			else:
				look = RIVAL_LOOKS[int(b.look)]
				key = "rv%d" % int(b.look)
			m.set_shader_parameter("map", _map_for(key, look, 0.17 + 0.23 * int(b.look)))
			if b.get("rings", false) and not b.get("core", false):
				# Кольцо тем же шейдером, что у тебя: вид сверху, дорожки, щель
				# Кассини, сгустки по Кеплеру, тень планеты. Сатурну — широкое
				# и тёплое, мини-нептуну — узкое ледяное.
				var sat: bool = b.get("cls", "") == "saturn"
				var rn := _view("ring") as ColorRect
				var ro := 2.25 if sat else 1.75
				var hs := rad * (ro + 0.05)
				rn.size = Vector2(hs, hs) * 2.0
				rn.position = p - Vector2(hs, hs)
				var rm := rn.material as ShaderMaterial
				rm.set_shader_parameter("half_size", hs)
				rm.set_shader_parameter("planet_r", rad)
				rm.set_shader_parameter("r_in", 1.28 if sat else 1.35)
				rm.set_shader_parameter("r_out", ro)
				rm.set_shader_parameter("opacity", 0.95 if sat else 0.55)
				rm.set_shader_parameter("col", Vector3(0.88, 0.82, 0.7) if sat else Vector3(0.8, 0.86, 0.92))
				rm.set_shader_parameter("light_dir", light)
				rm.set_shader_parameter("seed", fmod(float(b.seed), 10.0))
				rm.set_shader_parameter("time", _time)
				rn.modulate.a = fade
			m.set_shader_parameter("haze_col", Color(0.62, 0.74, 0.95) if b.kind != "dwarf" else Color(0.9, 0.35, 0.25))
			m.set_shader_parameter("light_dir", light)
			m.set_shader_parameter("spin", float(b.spin) * 3.0)
			m.set_shader_parameter("tilt", 0.1)
			m.set_shader_parameter("heat", 1.0 if b.kind == "dwarf" else (0.6 if float(b.r) < GameData.HOT_ORBIT or b.get("cls", "") == "hotnep" else 0.0))
			# Рядом с тобой форму ведёт GiantEncounter: прилив, полость, касание.
			var deform: bool = b.has("sh")
			m.set_shader_parameter("deform", deform)
			if deform:
				m.set_shader_parameter("shape", b.sh)
			var ch := float(b.get("ce_heat", 0.0))
			var to_me: Vector2 = (stage.body.position - p).normalized()
			m.set_shader_parameter("shock", Vector4(to_me.x, to_me.y, ch, 0.9 + 1.2 * ch))
			_shape(node, axis_ang, 0.0 if deform else stretch * 0.6, fade)
		"comet":
			var node := _view("comet") as ColorRect
			var len := clampf(5200000.0 / float(b.r) / maxf(float(b.r) / 4000.0, 1.0), 500.0, 2600.0)
			var wid := len * 0.28
			node.size = Vector2(len, wid)
			node.pivot_offset = Vector2(len * 0.08, wid * 0.5)
			node.position = p - node.pivot_offset
			node.rotation = p.angle()
			var m := node.material as ShaderMaterial
			m.set_shader_parameter("aspect", len / wid)
			m.set_shader_parameter("time", _time)
			m.set_shader_parameter("seed", b.seed)
			m.set_shader_parameter("bright", clampf(9000.0 / float(b.r), 0.5, 1.6) * fade)
			m.set_shader_parameter("bend", 0.25)
			var mv := _view("moon") as MoonView
			mv.put(p, maxf(rad * 0.6, 1.5 * px), 1, light, fmod(float(b.seed), 10.0), float(b.spin), 1.0, heat, 1.0)


## Своя луна тела: маленький шар на орбите вокруг него.
func _draw_sat(b: Dictionary, p: Vector2, rad: float, light: Vector2, px: float) -> void:
	var ph := _time * 0.12 + float(b.seed) * 2.0
	var o := Vector2(cos(ph), sin(ph) * 0.45).rotated(float(b.seed)) * rad * 2.8
	var mv := _view("moon") as MoonView
	mv.put(p + o, maxf(rad * 0.22, 2.5 * px), int(MATS[b.mat]["moon"]) if MATS.has(b.mat) else 0, light, fmod(float(b.seed) * 3.0, 10.0), float(b.spin), 1.0, 0.0, 1.0)


## Приливная деформация: тело вытягивается вдоль оси на гиганта.
func _shape(node: Control, axis_ang: float, stretch: float, fade: float) -> void:
	node.pivot_offset = node.size * 0.5
	node.rotation = axis_ang if stretch > 0.001 else 0.0
	# Жидкое тело у предела Роша — вытянутый эллипсоид, но не «пилюля».
	node.scale = Vector2(1.0 + 0.35 * stretch, 1.0 - 0.12 * stretch)
	node.modulate.a = fade


func _body_by_id(id: int) -> Dictionary:
	for b in bodies:
		if int(b.id) == id:
			return b
	return {}


func _draw_flashes() -> void:
	var used := 0
	_over.queue_redraw()
	for f in _flashes:
		if f.get("ring", false):
			continue
		if used >= _flash_nodes.size():
			var s := Sprite2D.new()
			s.texture = _flash_tex
			var mat := CanvasItemMaterial.new()
			mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			s.material = mat
			_over.add_child(s)
			_flash_nodes.append(s)
		var spr: Sprite2D = _flash_nodes[used]
		used += 1
		var t := float(f.t)
		spr.visible = true
		spr.position = stage.body.to_global(f.p) if f.get("loc", false) else f.p
		var size: float = float(f.size) * (0.4 + 1.2 * sqrt(t))
		spr.scale = Vector2.ONE * size * 2.0 / 128.0
		var c: Color = f.col
		spr.modulate = Color(c.r, c.g, c.b, (1.0 - t) * (1.0 - t))
	for i in range(used, _flash_nodes.size()):
		(_flash_nodes[i] as Sprite2D).visible = false


## Кольца: эллипс из нескольких полос льда; задняя половина под телом.
func _draw_ring(ci: CanvasItem, rg: Dictionary, front: bool) -> void:
	var p: Vector2 = rg.p
	var r: float = rg.r
	var a: float = rg.a
	ci.draw_set_transform(p, a, Vector2(1.0, 0.28))
	var from := 0.0 if front else PI
	var bands := [[1.35, 0.10, 0.35], [1.55, 0.16, 0.55], [1.78, 0.07, 0.25], [1.95, 0.12, 0.42], [2.15, 0.05, 0.18]]
	for bd in bands:
		var rr := r * float(bd[0])
		var w := r * float(bd[1])
		var c := Color(0.86, 0.84, 0.78, float(bd[2]))
		ci.draw_arc(Vector2.ZERO, rr, from, from + PI, 48, c, w, true)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Ударная волна: кольцо бежит по облакам от точки удара и тает.
func _draw_rings() -> void:
	for rg in _ring_list:
		_draw_ring(_over, rg, true)
	for f in _flashes:
		if not f.get("ring", false):
			continue
		var tr := float(f.t)
		var rr := float(f.size) * (0.08 + 0.92 * sqrt(tr))
		var cc: Color = f.col
		var fp: Vector2 = stage.body.to_global(f.p) if f.get("loc", false) else f.p
		# Волна — тёмное кольцо в облаках: только по диску гиганта.
		var gc: Vector2 = stage.body.global_position
		var gr := _giant_r() * 0.99
		var a := 0.32 * smoothstep(0.0, 0.05, tr) * (1.0 - tr)
		_clip_arc(fp, rr, gc, gr, Color(cc, a), float(f.size) * 0.035 * (1.0 - 0.4 * tr))
		_clip_arc(fp, rr * 0.9, gc, gr, Color(cc, a * 0.35), float(f.size) * 0.08 * (1.0 - 0.4 * tr))


## Окружность, обрезанная диском гиганта (волна не выходит за облака).
func _clip_arc(c: Vector2, rr: float, gc: Vector2, gr: float, col: Color, w: float) -> void:
	var seg := PackedVector2Array()
	for i in 97:
		var q := c + Vector2.from_angle(TAU * i / 96.0) * rr
		if q.distance_to(gc) < gr:
			seg.append(q)
		else:
			if seg.size() > 1:
				_over.draw_polyline(seg, col, w, true)
			seg.clear()
	if seg.size() > 1:
		_over.draw_polyline(seg, col, w, true)


static func _make_flash_tex() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.15, Color(1, 0.95, 0.85, 0.85))
	g.add_point(0.45, Color(1, 0.7, 0.4, 0.25))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	return tex
