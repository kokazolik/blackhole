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
## - мелочь (лёгкая) — съесть: прилив тянет её в задачу Хилла, у предела Роша
##   тело вытягивается и рвётся на «нитку жемчуга» (крупные обломки) и
##   пылевую струю (частицы газа); куски огибают тебя и падают вспышками;
## - средние — праща: пролёт рядом бросает тело к звезде или прочь из
##   системы, тебя отдачей толкает обратно;
## - тяжелее тебя — опасность: тянут к себе, вырывают луны, срывают газ.
## Соперник, которого ты перерос, сливается с тобой.
## У каждого ядра своё население: лёд — кометы и ледяные миры, плотное —
## железные тела, тёмное — углеродные, горячее — лавовые миры у звезды.

signal body_eaten(b: Dictionary)

const K_DRIFT := 0.12        # темп сдвига тел по орбитам (рад/с на единицу x^-1.5 − 1)
const HILL_W := 0.35         # «время газа» задачи Хилла (как GasParticles.OMEGA)
const ROCHE := 1.0           # предел Роша в радиусах Хилла: здесь тело рвётся
const CAPTURE := 0.42        # куски ниже этого — упали в облака
const EAT_RATIO := 0.1       # съесть можно тело легче этой доли твоей массы
const MERGE_RATIO := 1.4     # соперника-гиганта — когда ты тяжелее во столько раз
const SLING := 380.0         # пинок пращи, ед./с
const RADIAL_DRAG := 0.12    # газ гасит радиальную скорость тел
const DEBRIS_BASE := 1000000 # номера учёта обломков в частицах
const N_BODIES := 170

# Виды тел: масса в массах Земли, видимый радиус, чем рисуется, что дают.
const KINDS := {
	"rubble": {"name": "рой обломков", "m": Vector2(0.02, 0.06), "rad": 14.0, "view": "moon", "ch": 0, "extra": 0.0004, "pieces": 5},
	"planetesimal": {"name": "планетезималь", "m": Vector2(0.1, 0.35), "rad": 20.0, "view": "moon", "ch": 1, "extra": 0.001},
	"comet": {"name": "комета", "m": Vector2(0.01, 0.03), "rad": 9.0, "view": "comet", "ch": 1, "extra": 0.0008},
	"embryo": {"name": "зародыш", "m": Vector2(0.6, 3.0), "rad": 34.0, "view": "embryo", "ch": 3, "extra": 0.004},
	"superearth": {"name": "суперземля", "m": Vector2(4.0, 12.0), "rad": 48.0, "view": "embryo", "ch": 5, "extra": 0.008},
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
]
const NEPTUNE_LOOK := [Color(0.62, 0.8, 0.9), Color(0.36, 0.58, 0.78), Color(0.2, 0.32, 0.6)]
const DWARF_LOOK := [Color(0.55, 0.22, 0.2), Color(0.28, 0.08, 0.1), Color(0.75, 0.3, 0.18)]

var stage                    # giant_stage.gd
var bodies: Array = []
var vortices: Array = []
var _pearls: Array = []      # крупные обломки разорванных тел: летят по задаче Хилла
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
var _spawn_t := 4.0
var _dwarf_t := 140.0
var _said := {}
var _sling_cd := 0.0
var _hit_cd := 0.0


func _ready() -> void:
	_rng.randomize()
	_flash_tex = _make_flash_tex()


func setup() -> void:
	for i in N_BODIES:
		_spawn_random(true)
	# Соперники: один полегче (вырастешь — съешь), один тяжелее (бойся).
	var e: float = stage.earths
	_spawn_rival(maxf(e * 3.0, 35.0) * _rng.randf_range(0.9, 1.3))
	_spawn_rival(maxf(e * 12.0, 140.0) * _rng.randf_range(0.9, 1.4))
	if _flavor() in ["giant_cold", "giant_hot"]:
		_spawn_rival(maxf(e * 30.0, 300.0) * _rng.randf_range(0.9, 1.2))


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


func _pick_kind(r: float) -> String:
	var f := _flavor()
	var w := {"rubble": 0.3, "planetesimal": 0.3, "embryo": 0.18, "superearth": 0.08, "minineptune": 0.03, "comet": 0.0}
	if r > GameData.SNOW_LINE:
		w["comet"] = 0.18 * (2.2 if f == "giant_ice" else 1.0)
		w["minineptune"] = 0.07 * (1.8 if f == "giant_ice" else 1.0)
	if f == "giant_hot" and r < GameData.HOT_ORBIT + 2500.0:
		w["superearth"] = 0.16
	if f == "giant_cold":
		w["superearth"] *= 1.5
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
	if kind == "comet":
		mat = "ice"
	var b := {
		"id": _next_id, "kind": kind, "mat": mat, "m": m, "r": r, "a": a, "vr": 0.0,
		"seed": _rng.randf() * 10.0, "spin": _rng.randf() * TAU,
		# Медленно, как настоящие тела: оборот за минуты, а не за секунды.
		"spin_rate": _rng.randf_range(0.008, 0.03) * (1.0 if _rng.randf() < 0.5 else -1.0),
		"tilt": _rng.randf_range(0.2, 0.6), "state": "free", "t": 0.0,
		"h": Vector4.ZERO, "stretch": 0.0, "cd": 0.0, "tag": "", "look": _rng.randi() % RIVAL_LOOKS.size(),
	}
	if kind == "comet":
		# Кометы падают с окраин к звезде по вытянутой орбите.
		b["vr"] = -_rng.randf_range(90.0, 180.0)
	_next_id += 1
	bodies.append(b)
	return b


func _spawn_rival(m: float) -> Dictionary:
	var g: float = stage.orbit
	var r := 0.0
	for attempt in 12:
		r = _rng.randf_range(GameData.HOT_ORBIT, GameData.GIANT_DISK.y - 1500.0)
		if absf(r - g) > 2600.0:
			break
	var a: float = stage.ang + _rng.randf_range(0.6, 2.6) * (1.0 if _rng.randf() < 0.5 else -1.0)
	return _add_body("rival", r, a, "gas", m)


## Коричневый карлик проходит сквозь диск по прямой, издалека.
func _spawn_dwarf() -> void:
	var g: Vector2 = stage.body.position
	var dir := g.normalized().rotated(_rng.randf_range(-0.4, 0.4))
	var side := dir.orthogonal() * (1.0 if _rng.randf() < 0.5 else -1.0)
	var miss := _rng.randf_range(1200.0, 2600.0) * (1.0 if _rng.randf() < 0.5 else -1.0)
	var start := g + dir * miss - side * 9000.0
	var b := _add_body("dwarf", start.length(), start.angle(), "gas")
	b["vel"] = side * 520.0
	b["state"] = "pass"
	stage.hud.caption("Коричневый карлик", "несостоявшаяся звезда в двадцать масс Юпитера проходит сквозь диск: она вырывает луны и швыряет всё вокруг. Держись подальше", 4.5)


static func _cap(t: String) -> String:
	return t.left(1).to_upper() + t.substr(1)


static func pos_of(b: Dictionary) -> Vector2:
	return Vector2.from_angle(float(b.a)) * float(b.r)


func rad_of(b: Dictionary) -> float:
	var k: String = b.kind
	if k == "rival":
		return GameData.giant_body_r(float(b.m)) * 0.95
	if k == "dwarf":
		return GameData.giant_body_r(318.0) * 1.05  # карлики размером с Юпитер
	return float(KINDS[k]["rad"]) * pow(float(b.m) / float((KINDS[k]["m"] as Vector2).x), 0.18)


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
	return "sling"


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
	_step_pearls(delta, h)
	_step_vortices(delta, gpos, h)
	# Тела не кончаются: новые приходят с окраин и из-за края экрана.
	_spawn_t -= delta
	var want := roundi(N_BODIES * Skills.stat("giant_bodies"))
	if _spawn_t <= 0.0:
		_spawn_t = _rng.randf_range(1.0, 2.5)
		var small := 0
		for b in bodies:
			if not (b.kind in ["rival", "dwarf"]):
				small += 1
		if small < want:
			_spawn_random(false)
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
		_danger(b, delta, gpos, h)
		return p.length() < GameData.GIANT_DISK.y + 12000.0 and _time < 1e9 and p.distance_to(gpos) < 16000.0
	# Свободное тело: сдвиг диска, радиальная скорость гаснет в газе.
	var x := float(b.r) / orbit
	b.a = wrapf(float(b.a) - K_DRIFT * (pow(x, -1.5) - 1.0) * delta, -PI, PI)
	if b.kind == "comet":
		b.r = float(b.r) + float(b.vr) * delta
	else:
		b.r = float(b.r) + float(b.vr) * delta
		b.vr = float(b.vr) * exp(-RADIAL_DRAG * delta)
	if b.kind == "rival":
		# Соперник тоже пьёт газ и растёт, пока газ есть.
		var gk: float = clampf(stage.gas / stage.gas_total, 0.0, 1.0)
		b.m = float(b.m) * (1.0 + 0.0018 * gk * delta)
		b.r = maxf(float(b.r) - 6.0 * gk * delta, GameData.HOT_ORBIT - 400.0)
		_rival_feed(b)
	# Ушло за пределы: упало в звезду или выброшено из системы.
	if float(b.r) < GameData.GIANT_STAR_R * 1.08:
		_into_star(b)
		return false
	if float(b.r) > GameData.GIANT_DISK.y + 600.0:
		if b.kind != "comet":
			_ejected(b)
		return false
	var p2 := pos_of(b)
	var d := p2.distance_to(gpos)
	var ro := role(b)
	if b.state == "gone":
		return false
	match ro:
		"food", "merge":
			if d < (2.0 * h * reach if ro == "food" else h * 1.6 + rad_of(b)):
				_capture(b, gpos, h, orbit)
				if b.state == "gone":
					return false
		"sling":
			if d < 2.2 * h + rad_of(b) and float(b.cd) <= 0.0:
				_sling(b, p2, gpos)
			_danger_soft(b, delta, gpos, h)
		"danger":
			_danger(b, delta, gpos, h)
	return true


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
	if b.kind in ["embryo", "planetesimal"] and stage.moons < GameState.giant_moon_cap() \
			and _rng.randf() < Skills.stat("giant_moon_grab") * (1.5 if _flavor() == "giant_dense" else 1.0):
		b["moon"] = true
		_capture(b, gpos, h, orbit)
		return
	var loc: Vector2 = stage.body.to_local(pos_of(b))
	var x := float(b.r) / orbit
	var lvy := -K_DRIFT * (pow(x, -1.5) - 1.0) * float(b.r)   # локальная y — рост угла
	var s := h * HILL_W
	b.h = Vector4(loc.x / h, -loc.y / h, float(b.vr) / s, -lvy / s)
	b.state = "captured"
	b.t = 0.0
	if not _said.has("roche"):
		_said["roche"] = true
		stage.hud.caption("Предел Роша", "прилив гиганта вытягивает тело и рвёт его на нитку обломков: куски огибают тебя и падают в облака", 4.0)
	if b.kind == "rival" and not _said.has("merge"):
		_said["merge"] = true
		stage.hud.caption("Слияние гигантов", "ты перерос соседа: он падает в тебя по спирали", 3.5)


func _step_captured(b: Dictionary, delta: float, h: float) -> bool:
	var g := 3.0 * pow(Skills.stat("giant_reach"), 3.0)
	var dt := delta * HILL_W
	var steps := maxi(1, ceili(dt / 0.02))
	var hh := dt / steps
	var p: Vector4 = b.h
	for k in steps:
		p = GasParticles.hill_step(p, hh, g, 0.9)
		# Трение о свой диск и прилив тянут тело к тебе, пока оно не порвётся.
		var d := sqrt(p.x * p.x + p.y * p.y)
		p.z -= p.x / maxf(d, 0.1) * 0.9 * hh
		p.w -= p.y / maxf(d, 0.1) * 0.9 * hh
	b.h = p
	var dist := sqrt(p.x * p.x + p.y * p.y)
	var roche := ROCHE * (1.25 if b.kind == "rival" else 1.0)
	b.stretch = smoothstep(roche * 1.8, roche, dist)
	b.t = float(b.t) + delta
	# Мир помнит, где тело: для HUD и отрисовки.
	var wp: Vector2 = stage.body.to_global(Vector2(p.x, -p.y) * h)
	b.r = wp.length()
	b.a = wp.angle()
	if dist < roche or float(b.t) > 14.0:
		_tear(b, p, h)
		return false
	return true


## У предела Роша тело рвётся: нитка обломков и пылевая струя.
func _tear(b: Dictionary, p: Vector4, h: float) -> void:
	var info: Dictionary = KINDS[b.kind]
	var m: float = b.m
	var gas: GasParticles = stage.body.gas
	var rad := rad_of(b) / h
	var axis := Vector2(p.x, p.y).normalized()
	var tang := axis.orthogonal()
	var col: Color = MATS[b.mat]["col"] if MATS.has(b.mat) else Color(0.85, 0.78, 0.66)
	if b.kind in ["rival", "minineptune"]:
		var look: Array = NEPTUNE_LOOK if b.kind == "minineptune" else RIVAL_LOOKS[int(b.look)]
		col = (look[0] as Color).lerp(look[1], 0.4)
	var n := clampi(int(80.0 + 60.0 * log(1.0 + m * 20.0)), 80, 380)
	var id := DEBRIS_BASE + int(b.id)
	var gain := _gain(b)
	var share_dust := 0.65 if b.kind != "rival" else 0.85
	_debris[id] = {"per": gain * share_dust / n, "mat": b.mat, "kind": b.kind, "left": n, "pay": _pay_k(b)}
	for i in n:
		# Вытянутое тело: куски вдоль оси на гиганта; ближняя часть быстрее.
		var s := _rng.randf_range(-1.0, 1.0)
		var along := s * rad * (2.5 + 2.0 * float(b.stretch))
		var across := _rng.randfn(0.0, 0.25) * rad
		var q := Vector2(p.x, p.y) + axis * along + tang * across
		var dv := axis * (-s * 0.35) + tang * s * 0.25 + Vector2(_rng.randfn(0.0, 0.06), _rng.randfn(0.0, 0.06))
		var c := col.lerp(col.lightened(0.3), _rng.randf() * 0.4)
		var size := _rng.randf_range(0.016, 0.038) * (1.6 if b.kind == "rival" else 1.0)
		gas.add(q.x, q.y, p.z + dv.x, p.w + dv.y, size, _rng.randf_range(0.3, 0.55), c, id)
	# Крупные обломки: нитка жемчуга, как у кометы Шумейкеров–Леви 9.
	var pearls := 0 if b.kind in ["rival", "minineptune", "comet"] else clampi(3 + int(m * 2.0), 3, 9)
	for i in pearls:
		var s := (float(i) / maxf(pearls - 1, 1)) * 2.0 - 1.0
		var q := Vector2(p.x, p.y) + axis * s * rad * 2.2
		var dv := axis * (-s * 0.3)
		_pearls.append({"h": Vector4(q.x, q.y, p.z + dv.x, p.w + dv.y), "r": rad_of(b) * _rng.randf_range(0.22, 0.42),
			"mat": b.mat, "seed": float(b.seed) + i, "gain": gain * (1.0 - share_dust) / pearls, "pay": _pay_k(b),
			"spin": _rng.randf() * TAU})
	if pearls == 0:
		var rest := gain * (1.0 - share_dust)
		stage.earths += rest
		stage.pay(rest * _pay_k(b))
	_reward(b, gain)


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
func _reward(b: Dictionary, gain: float) -> void:
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
	if ch > 0:
		GameState.add_chondrules(ch, stage.body.position)
		extra += " · хондры +%d" % ch
	var fem: bool = b.kind in ["comet", "planetesimal", "superearth"]
	var verb := ("Поглощён" if not fem else "Поглощена") if b.kind == "rival" else ("Разорвана" if fem else "Разорван")
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
	_flashes.append({"p": pos_of(b).normalized() * GameData.GIANT_STAR_R, "t": 0.0, "dur": 2.0, "size": 900.0, "col": Color(1.0, 0.85, 0.6)})
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
	var out := signf(float(b.r) - float(stage.orbit))
	if out == 0.0:
		out = 1.0
	var power := SLING * Skills.stat("giant_sling") * pow(clampf(e / maxf(m, 0.01), 0.3, 8.0), 0.4)
	b.vr = float(b.vr) + out * power
	b.cd = 5.0
	b["slung"] = true
	# Отдача: тебя толкает в другую сторону, тем сильнее, чем тяжелее тело.
	stage.kick.x -= out * 260.0 * clampf(m / e, 0.05, 1.0)
	_flashes.append({"p": p, "t": 0.0, "dur": 0.8, "size": rad_of(b) * 3.0, "col": Color(0.8, 0.9, 1.0)})
	stage.pay(m * 0.4 * Skills.stat("giant_sling"))
	if not _said.has("sling"):
		_said["sling"] = true
		stage.hud.caption("Гравитационная праща", "тело слишком велико, чтобы съесть, но пролёт рядом бросает его: изнутри орбиты — к звезде, снаружи — прочь из системы", 4.5)
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


## Гигант сдвинулся: захваченные тела и обломки остаются на месте в диске.
func shift(d: Vector2) -> void:
	var h: float = stage.hill()
	var dx := d.x / h
	var dy := -d.y / h
	for b in bodies:
		if b.state == "captured":
			var p: Vector4 = b.h
			b.h = Vector4(p.x - dx, p.y - dy, p.z, p.w)
	for pr in _pearls:
		var p: Vector4 = pr.h
		pr.h = Vector4(p.x - dx, p.y - dy, p.z, p.w)


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
	var orbit: float = stage.orbit
	var inside := in_vortex()
	for v in vortices:
		v.t = float(v.t) + delta
		var x := float(v.r) / orbit
		v.a = wrapf(float(v.a) - K_DRIFT * (pow(x, -1.5) - 1.0) * delta, -PI, PI)
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
	for b in bodies:
		if b.state != "free" and b.state != "pass":
			continue
		var ro := role(b)
		var d := pos_of(b).distance_to(g)
		if ro == "danger" and d < 9000.0:
			out.append({"p": pos_of(b), "col": Color(1.0, 0.4, 0.32), "text": KINDS[b.kind]["name"]})
		elif ro == "merge":
			out.append({"p": pos_of(b), "col": UiTheme.GOLD, "text": "слияние"})
		elif ro == "food" and float(b.m) > 0.4:
			var score := d / sqrt(float(b.m))
			if score < bd:
				bd = score
				best = b
	if not best.is_empty():
		out.append({"p": pos_of(best), "col": Color(0.95, 0.85, 0.6), "text": KINDS[best.kind]["name"]})
	for v in vortices:
		out.append({"p": Vector2.from_angle(float(v.a)) * float(v.r), "col": Color(0.8, 0.7, 0.5), "text": "вихрь"})
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
		if ro != "food" and ro != "merge":
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

func _view(kind: String) -> Control:
	if not _pools.has(kind):
		_pools[kind] = []
		_used[kind] = 0
	var pool: Array = _pools[kind]
	var i: int = _used[kind]
	_used[kind] = i + 1
	if i < pool.size():
		var v: Control = pool[i]
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
			node.material = mat
	add_child(node)
	pool.append(node)
	return node


## Карта облаков чужого гиганта печётся один раз на палитру.
func _map_for(key: String, look: Array, seed_v: float) -> Texture2D:
	if _maps.has(key):
		return (_maps[key] as SubViewport).get_texture()
	var vp := SubViewport.new()
	vp.size = Vector2i(256, 128)
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var rect := ColorRect.new()
	rect.size = Vector2(256, 128)
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
			(pool[i] as Control).visible = false
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
	var min_px := {"moon": 5.0, "embryo": 8.0, "giant": 12.0, "comet": 3.0}
	rad = maxf(rad, float(min_px.get(view, 3.0)) * px)
	var role_s := role(b)
	if role_s == "danger" or role_s == "merge":
		# Метка вокруг тяжёлого тела: красная — бойся, золотая — можно слиться.
		var col := Color(1.0, 0.35, 0.28) if role_s == "danger" else UiTheme.GOLD
		draw_arc(p, hill_of(b), 0.0, TAU, 96, Color(col, 0.08 + 0.1 * pulse), 2.0 * px, true)
	match view:
		"moon":
			var pieces := int(info.get("pieces", 1))
			for i in pieces:
				var o := Vector2.ZERO
				var rr := rad
				if pieces > 1:
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
			var big: bool = b.kind == "superearth"
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
			m.set_shader_parameter("haze_col", Color(0.62, 0.74, 0.95) if b.kind != "dwarf" else Color(0.9, 0.35, 0.25))
			m.set_shader_parameter("light_dir", light)
			m.set_shader_parameter("spin", float(b.spin) * 3.0)
			m.set_shader_parameter("tilt", 0.1)
			m.set_shader_parameter("heat", 1.0 if b.kind == "dwarf" else (0.6 if float(b.r) < GameData.HOT_ORBIT else 0.0))
			_shape(node, axis_ang, stretch * 0.6, fade)
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


## Приливная деформация: тело вытягивается вдоль оси на гиганта.
func _shape(node: Control, axis_ang: float, stretch: float, fade: float) -> void:
	node.pivot_offset = node.size * 0.5
	node.rotation = axis_ang if stretch > 0.001 else 0.0
	node.scale = Vector2(1.0 + 1.4 * stretch, 1.0 - 0.35 * stretch)
	node.modulate.a = fade


func _body_by_id(id: int) -> Dictionary:
	for b in bodies:
		if int(b.id) == id:
			return b
	return {}


func _draw_flashes() -> void:
	var used := 0
	for f in _flashes:
		if used >= _flash_nodes.size():
			var s := Sprite2D.new()
			s.texture = _flash_tex
			var mat := CanvasItemMaterial.new()
			mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			s.material = mat
			add_child(s)
			_flash_nodes.append(s)
		var spr: Sprite2D = _flash_nodes[used]
		used += 1
		var t := float(f.t)
		spr.visible = true
		spr.position = f.p
		var size: float = float(f.size) * (0.4 + 1.2 * sqrt(t))
		spr.scale = Vector2.ONE * size * 2.0 / 128.0
		var c: Color = f.col
		spr.modulate = Color(c.r, c.g, c.b, (1.0 - t) * (1.0 - t))
	for i in range(used, _flash_nodes.size()):
		(_flash_nodes[i] as Sprite2D).visible = false


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
