class_name GiantEncounter
extends Node2D
## Сближение двух жидких тел: ты и гигант-соперник или коричневый карлик.
## Всё по физике, без скриптов и подписей.
##
## 1. Тяготение взаимное: каждого тянет к другому G·m/d². Тебя толкает в твою
##    скорость (импульс остаётся: орбит нет), соперника — в его. Лёгкого тянет
##    сильнее; у тяжёлого соседа есть точка невозврата, где тяга сильнее хода.
## 2. Прилив: шар вытягивается вдоль линии центров (равновесный прилив,
##    ε = h·(m₂/m₁)·(R/d)³, h — податливость оболочки по флейвору) и не может
##    выйти за полость Роша (scripts/physics/roche.gd). Форма — 64 радиуса,
##    догоняет цель как упругая оболочка (колебания основной моды: после
##    тесного пролёта шар «дрожит» и успокаивается).
## 3. Переполнение полости: газ сверх неё течёт через L1 к соседу,
##    ṁ ∝ m·(ΔR/R)³ (политропа). Струя — частицы в поле обоих тел.
## 4. Касание: оболочки давят друг на друга (сплющиваются по общей границе,
##    раздаются вбок — площадь сохраняется), трение в общей оболочке гасит
##    относительную скорость, удар греет газ (свечение там, где реально горячо),
##    выброс газа вбок. Ядро лёгкого тонет к центру тяжёлого: общая оболочка.
## 5. Ядро утонуло — лёгкий поглощён. Если это ты — конец игры.

const N := Roche.N
const G := 3.5e5             # тяготение: a = G·m/d², масса в массах Земли
const RANGE := 5.5           # сближение считается ближе RANGE·(R₁+R₂)
const MDOT_K := 1.2          # переполнение: доля массы в секунду при ΔR = R
const MDOT_MAX := 0.18
const PRESS := 3000.0        # отталкивание оболочек при касании (∝ перекрытие²)
const DRAG := 3.5            # трение в общей оболочке (вдоль границы)
const STICK := 5.0           # общая оболочка держит расходящиеся тела
const SHAPE_W := 5.2         # частота основной моды оболочки, рад/с
const SHAPE_Z := 0.32        # затухание
const MAX_P := 900
## Высасывание соседа, которого тебе можно съесть (role "merge", навык
## «Пожиратель гигантов»): доля его газа в секунду при касании. Растёт с
## близостью ∝ k², начинается с SUCK_FROM суммы радиусов.
const SUCK := 0.2
const SUCK_FROM := 2.6
## Твой флейвор: горячий гигант раздут и пьёт жаднее, плотный — медленно,
## но его ядро тяжелее и держит; ледяной рыхлый — быстрее.
const SUCK_BY := {"giant_hot": 1.3, "giant_ice": 1.15, "giant_cold": 1.0, "giant_dark": 1.0, "giant_dense": 0.8}
## Сосед легче этой доли твоей массы: его ядро рвётся приливом, пока газ ещё
## течёт к тебе (автор). Горячий гигант раздут — тянет ядро раньше, плотный
## держит своё газом крепче.
const EARLY_Q := {"giant_hot": 0.42, "giant_ice": 0.36, "giant_cold": 0.33, "giant_dark": 0.33, "giant_dense": 0.25}

## Оболочка по флейвору: податливость прилива (число Лява), время утопления
## ядра в общей оболочке, цвет струи. Плотный гигант (железное ядро, газ
## сжат к центру) почти не вытягивается и держится дольше всех; горячий
## раздут и течёт первым; ледяной рыхлый; у тёмного струя сажистая.
const FLUID := {
	"giant_cold": {"soft": 1.0, "ce": 3.2},
	"giant_ice": {"soft": 1.25, "ce": 2.6},
	"giant_dark": {"soft": 1.05, "ce": 3.0},
	"giant_dense": {"soft": 0.62, "ce": 4.6},
	"giant_hot": {"soft": 1.4, "ce": 2.3},
	"rival": {"soft": 1.0, "ce": 3.0},
	"dwarf": {"soft": 0.4, "ce": 3.0},   # вырожденный газ: плотный, почти не тянется
}
## Ядро по составу: железо тонет медленнее (держит форму), лёд растворяется.
const CORE_CE := {"metal": 1.35, "ice": 0.85, "titan": 0.9, "chondrite": 1.05, "venus": 1.1}

var stage
var world
var shape := PackedFloat32Array()      # твоя форма, радиусы в долях R, локальные углы
var shape_v := PackedFloat32Array()
var shock := Vector4.ZERO              # твой ударный нагрев: направление (локальное), сила, температура
var absorbing := {}                    # тело, которое сейчас тонет (ты или соперник)
var _absorb_t := 0.0
var _p_pos := PackedVector2Array()     # частицы струи и выброса, мировые координаты
var _p_vel := PackedVector2Array()
var _p_life := PackedFloat32Array()
var _p_max := PackedFloat32Array()
var _p_col := PackedColorArray()
var _p_size := PackedFloat32Array()
var _sink_p := Vector2.ZERO   # где ты (для угасания струи у края облаков)
var _sink_r := 1.0
var _p_to := []                        # к кому падает (тело или {} — к тебе), null — ни к кому
var _rng := RandomNumberGenerator.new()
var _emit_acc := {}


func _ready() -> void:
	_rng.randomize()
	shape.resize(N)
	shape_v.resize(N)
	shape.fill(1.0)
	shape_v.fill(0.0)
	z_index = 3


func _flavor() -> String:
	return str(GameState.giant.get("flavor", "giant_cold"))


func _fluid_me() -> Dictionary:
	return FLUID.get(_flavor(), FLUID["giant_cold"])


func _fluid_of(b: Dictionary) -> Dictionary:
	if b.has("cls"):
		return GiantWorld.WORLD_CLS[b.cls]
	return FLUID["dwarf"] if b.kind == "dwarf" else FLUID["rival"]


func _my_col() -> Color:
	var look: Array = GameData.GIANT_LOOK.get(_flavor(), GameData.GIANT_LOOK["giant_cold"])
	return (look[0] as Color).lerp(look[1], 0.35)


func _col_of(b: Dictionary) -> Color:
	var look: Array = world.DWARF_LOOK if b.kind == "dwarf" else world.RIVAL_LOOKS[int(b.look)]
	return (look[0] as Color).lerp(look[1], 0.35)


## Шаг: все пары «ты — крупное тело» рядом.
func step(delta: float) -> void:
	var gpos: Vector2 = stage.body.position
	var R1: float = world._giant_r()
	var target := PackedFloat32Array()
	target.resize(N)
	target.fill(1.0)
	var heat_me := 0.0
	var near := false
	for b in world.bodies:
		if not (b.kind in ["rival", "dwarf"]) or not (b.state in ["free", "pass"]):
			continue
		if b == absorbing:
			continue
		var p: Vector2 = world.pos_of(b)
		var R2: float = world.rad_of(b)
		var to := p - gpos
		var d := to.length()
		if d > RANGE * (R1 + R2) or d < 1.0:
			if b.has("sh"):
				_relax_body(b, delta, d)
			# Ушёл после тесного пролёта, не слившись: праща («Праща» g_sling).
			if b.get("close", false) and d >= 1.0:
				b.erase("close")
				if b.kind == "rival":
					stage.pay(float(b.m) * 0.3 * Skills.stat("giant_sling"))
			continue
		near = true
		_pair(b, delta, gpos, p, to, d, R1, R2, target)
		heat_me = maxf(heat_me, float(b.get("ce_heat", 0.0)))
	if not absorbing.is_empty() or _absorb_t > 0.0:
		_step_absorb(delta, gpos, R1, target)
	_spring(shape, shape_v, _smooth(target), delta)
	shock.z = maxf(shock.z - delta * 0.25, 0.0)
	_step_particles(delta, gpos, R1)
	stage.body.set_shape(shape if near or _absorb_t > 0.0 or _moving(shape_v) else PackedFloat32Array(), shock)
	queue_redraw()


## Газ не держит изломов: цель формы сглаживается по углу (кроме острия
## у L1 — его сглаживание лишь слегка скругляет).
func _smooth(t: PackedFloat32Array) -> PackedFloat32Array:
	var o := PackedFloat32Array()
	o.resize(N)
	for i in N:
		o[i] = 0.25 * t[(i + N - 1) % N] + 0.5 * t[i] + 0.25 * t[(i + 1) % N]
	return o


func _moving(v: PackedFloat32Array) -> bool:
	for x in v:
		if absf(x) > 0.002:
			return true
	return false


## Упругая оболочка: каждый радиус — осциллятор к своей цели.
func _spring(s: PackedFloat32Array, v: PackedFloat32Array, t: PackedFloat32Array, delta: float) -> void:
	var w2 := SHAPE_W * SHAPE_W
	var damp := 2.0 * SHAPE_Z * SHAPE_W
	var steps := maxi(1, ceili(delta / 0.02))
	var dt := delta / steps
	for _k in steps:
		for i in N:
			var a := -w2 * (s[i] - t[i]) - damp * v[i]
			v[i] += a * dt
			s[i] = clampf(s[i] + v[i] * dt, 0.15, 1.32)


func _relax_body(b: Dictionary, delta: float, _d: float) -> void:
	var s: PackedFloat32Array = b.sh
	var v: PackedFloat32Array = b.shv
	var t := PackedFloat32Array()
	t.resize(N)
	t.fill(1.0)
	_spring(s, v, t, delta)
	b.sh = s
	b.shv = v
	if not _moving(v):
		var flat := true
		for x in s:
			if absf(x - 1.0) > 0.003:
				flat = false
		if flat:
			b.erase("sh")
			b.erase("shv")


## Одна пара. to — от тебя к соседу (мировые), d — расстояние.
func _pair(b: Dictionary, delta: float, gpos: Vector2, p: Vector2, to: Vector2, d: float,
		R1: float, R2: float, target: PackedFloat32Array) -> void:
	var m1: float = stage.earths
	var m2: float = b.m
	var n := to / d
	var ang: float = stage.ang
	var phi_w := n.angle()
	# --- Тяготение ---
	var a1 := G * m2 / (d * d)
	# «Праща» (g_sling): твой пролёт сильнее бросает соседа.
	var a2 := G * m1 / (d * d) * (Skills.stat("giant_sling") if b.kind == "rival" else 1.0)
	if d < 2.0 * (R1 + R2):
		b["close"] = true
	# «Хватка массы» (g_guard): оболочка сидит туже, её труднее вытянуть.
	var guard := 1.0 + Skills.stat("giant_guard")
	stage.kick += n.rotated(-ang) * a1 * delta
	_push(b, -n * a2 * delta)
	# --- Прилив и полость ---
	var f1 := _fluid_me()
	var f2 := _fluid_of(b)
	# Тонкая оболочка над ядром почти не тянется: масса сжата к центру.
	var eps1 := clampf(1.5 * float(f1.soft) * lerpf(0.3, 1.0, float(stage.body.env_k)) * (m2 / m1) * pow(R1 / d, 3.0) / guard, 0.0, 0.5)
	var eps2 := clampf(1.5 * float(f2.soft) * (m1 / m2) * pow(R2 / d, 3.0), 0.0, 0.5)
	var t1 := Roche.table(m1 / m2)
	var t2 := Roche.table(m2 / m1)
	var phi_l := phi_w - ang                  # на соседа в твоих локальных углах
	var over1 := 0.0
	var over2 := 0.0
	if not b.has("sh"):
		var s0 := PackedFloat32Array()
		s0.resize(N)
		s0.fill(1.0)
		var v0 := PackedFloat32Array()
		v0.resize(N)
		b["sh"] = s0
		b["shv"] = v0
	var tb := PackedFloat32Array()
	tb.resize(N)
	# Касание: общая граница — где давления равны; грубо — делит перекрытие
	# пополам по радиусам. Сплющенное раздаётся вбок (площадь та же).
	var reach1 := R1 * _dir_r(shape, phi_l)
	var reach2 := R2 * _dir_r(b.sh, phi_w + PI)
	var overlap := reach1 + reach2 - d
	var cut1 := INF
	var cut2 := INF
	if overlap > 0.0:
		var share1 := R1 / (R1 + R2)
		cut1 = (reach1 - overlap * share1) / R1
		cut2 = (reach2 - overlap * (1.0 - share1)) / R2
	for i in N:
		var th := TAU * i / N
		# Ты: угол от направления на соседа.
		var dth1 := th - phi_l
		var tide1 := _ellipse(eps1, dth1)
		var lob1 := d * _lobe(t1, dth1) / R1
		var r1 := minf(tide1, lob1)
		if cos(dth1) > 0.0:
			over1 = maxf(over1, tide1 - lob1)
		var dth2 := th - (phi_w + PI)
		var tide2 := _ellipse(eps2, dth2)
		var lob2 := d * _lobe(t2, dth2) / R2
		var r2 := minf(tide2, lob2)
		if cos(dth2) > 0.0:
			over2 = maxf(over2, tide2 - lob2)
		if overlap > 0.0:
			# Плоская граница: r·cos(Δ) ≤ cut. Вбок — раздувание.
			var c1 := cos(dth1)
			if c1 > 0.05:
				r1 = minf(r1, cut1 / c1)
			var c2 := cos(dth2)
			if c2 > 0.05:
				r2 = minf(r2, cut2 / c2)
			var side := clampf(overlap / minf(R1, R2), 0.0, 0.6)
			# Вбок раздаётся только то, что ещё внутри своей полости.
			r1 = minf(r1 * (1.0 + 0.35 * side * pow(sin(dth1), 2.0)), lob1)
			r2 = minf(r2 * (1.0 + 0.35 * side * pow(sin(dth2), 2.0)), lob2)
		target[i] = minf(target[i], r1) if r1 < 1.0 else maxf(target[i], r1)
		tb[i] = r2
	var sb: PackedFloat32Array = b.sh
	var vb: PackedFloat32Array = b.shv
	_spring(sb, vb, _smooth(tb), delta)
	b.sh = sb
	b.shv = vb
	# --- Высасывание: ты можешь съесть этого гиганта ---
	# Не отталкиваешь его, а пьёшь: газ соседа течёт к тебе струёй, тем
	# сильнее, чем ближе. Твой газ к нему не течёт. Останется голое ядро.
	var edible: bool = b.kind == "rival" and world.role(b) == "merge"
	if edible:
		over1 = 0.0
		var kk := smoothstep(SUCK_FROM, 0.9, d / (R1 + R2))
		if kk > 0.0:
			var rate := SUCK * kk * kk * float(SUCK_BY.get(_flavor(), 1.0)) * float(f2.soft) * (1.0 + Skills.stat("giant_merge") * 2.0)
			var keep := 0.0 if b.get("core_out", false) else core_of(b)
			var dm3 := minf(rate * m2 * delta, maxf(m2 - keep, 0.0))
			if dm3 > 0.0:
				b.m = float(b.m) - dm3
				stage.earths += dm3 * 0.95
				stage.pay(dm3 * 0.95)
				_emit(b, "it", rate * 0.5, p - n * minf(R2 * 0.95, d * 0.5), -n, gpos, p, delta, _col_of(b))
				b["ce_heat"] = clampf(float(b.get("ce_heat", 0.0)) + kk * delta * 0.3, 0.0, 0.8)
		# Небольшой сосед: ядро выходит к пределу Роша раньше, чем кончится газ.
		if not b.get("core_out", false) and m2 <= m1 * float(EARLY_Q.get(_flavor(), 0.33)):
			var tmp := {"kind": "superearth", "mat": _core_mat(b), "core": true}
			if d < world.roche_h(tmp) * stage.hill() * 1.25:
				_release_core(b)
	# --- Перетекание через L1 ---
	# Когда оболочки уже слились, полость теряет смысл: газ течёт только от
	# лёгкого к тяжёлому (общая оболочка садится на тяжёлое ядро).
	if R1 + R2 > d:
		if m1 < m2:
			over2 = 0.0
		else:
			over1 = 0.0
	if over1 > 0.0:
		# Течёт только газ: твёрдое ядро полость не покидает.
		var dm := minf(minf(MDOT_K * pow(over1, 3.0), MDOT_MAX) * m1 * delta / guard, maxf(m1 - stage.core_m(), 0.0))
		stage.earths -= dm
		b.m = float(b.m) + dm * 0.92
		_emit(b, "me", dm / m1 / delta, gpos + n * Roche.l1(m1 / m2) * d, n, p, gpos, delta, _my_col())
	if over2 > 0.0:
		var dm2 := minf(minf(MDOT_K * pow(over2, 3.0), MDOT_MAX) * m2 * delta, maxf(m2 - core_of(b), 0.0))
		b.m = float(b.m) - dm2
		stage.earths += dm2 * 0.92
		stage.pay(dm2 * 0.92)
		_emit(b, "it", dm2 / m2 / delta, p - n * Roche.l1(m2 / m1) * d, -n, gpos, p, delta, _col_of(b))
	# --- Касание: давление, трение, удар, общая оболочка ---
	var v1: Vector2 = world._player_vel()
	var v2: Vector2 = world._vel_of(b)
	var vrel := v2 - v1
	if overlap > 0.0:
		var o := overlap / minf(R1, R2)
		var mt := m1 + m2
		if not b.get("touched", false):
			b["touched"] = true
			_first_touch(b, n, -vrel.dot(n), R1, R2, gpos, p)
		# Газ на газ — удар неупругий: сближение по нормали гасит ударная
		# волна сразу, расхождение держит общая оболочка (липко). Давление
		# мягкое: тела вдавливаются друг в друга, пока не уравновесят тяготение.
		var vn := vrel.dot(n)          # < 0 — сближаются
		var kill := vn if vn < 0.0 else vn * (1.0 - exp(-STICK * o * delta))
		var dvn := n * kill
		var vt := vrel - n * vn
		var dvt := vt * (1.0 - exp(-DRAG * o * delta))
		var dv := dvn + dvt
		stage.kick += dv.rotated(-ang) * (m2 / mt)
		_push(b, -dv * (m1 / mt))
		# Съедаемого не отталкиваешь: давление только между равными.
		var ap := 0.0 if edible else PRESS * o * o
		stage.kick -= n.rotated(-ang) * ap * (m2 / mt) * delta
		_push(b, n * ap * (m1 / mt) * delta)
		# Трение греет общую оболочку.
		var fr := clampf(o * vrel.length() / 600.0, 0.0, 1.0)
		b["ce_heat"] = clampf(float(b.get("ce_heat", 0.0)) + fr * delta * 0.6, 0.0, 1.0)
		_heat_me(n.rotated(-ang), fr * delta * 0.6, 1.4)
	# Общая оболочка: центры ближе суммы радиусов — ядро лёгкого тонет.
	var sph := (R1 + R2 - d) / minf(R1, R2)
	if sph > -0.03 and not edible:
		var light2 := m1 < m2
		var ce_t2 := float((f1 if light2 else f2).ce)
		if light2:
			ce_t2 *= float(CORE_CE.get(GameState.body_type(), 1.0))
		else:
			# «Слияние» (g_merge): твоя оболочка быстрее гасит ядро соседа.
			ce_t2 /= 1.0 + 2.0 * Skills.stat("giant_merge")
		b["ce"] = float(b.get("ce", 0.0)) + delta * (0.15 + 1.5 * maxf(sph, 0.0)) / ce_t2
		if float(b.ce) >= 1.0:
			_begin_absorb(b, light2)
	else:
		b["ce"] = maxf(float(b.get("ce", 0.0)) - delta * 0.1, 0.0)
	if d > 3.0 * (R1 + R2):
		b.erase("touched")
	# Оболочку сорвало до ядра. Вплотную голое ядро тонет в соседе (это
	# решает общая оболочка выше), а вдали оно остаётся само по себе.
	if stage.env_frac() < 0.03 and absorbing.is_empty() and sph < -0.05:
		stage.swallowed("giant_chthonian")
	if b.kind == "rival" and b.get("core_out", false) and float(b.m) <= maxf(0.4, float(b.get("m0", b.m)) * 0.01):
		# Ядро уже рвётся у тебя, газ допит до конца.
		stage.earths += float(b.m)
		b.m = 0.0
		b.state = "gone"
		return
	if b.kind == "rival" and not b.get("core_out", false) and float(b.m) <= core_of(b) * 1.03 and absorbing.is_empty():
		_strip_rival(b)
		return
	b["ce_heat"] = maxf(float(b.get("ce_heat", 0.0)) - delta * 0.05, 0.0)
	# Тесный пролёт срывает луны: их орбиты шире твоей полости.
	if stage.moons > 0 and d < (R1 + R2) * 1.6 and float(b.get("moon_cd", 0.0)) <= 0.0 and m2 > m1 * 0.5:
		b["moon_cd"] = 5.0
		if _rng.randf() < 0.6 / guard:
			stage.moons -= 1
			stage.body.moons = stage.moons
			stage.body.steal(stage.body.to_local(p))
	b["moon_cd"] = maxf(float(b.get("moon_cd", 0.0)) - delta, 0.0)


## Ядро соседа: несколько масс Земли камня и льда под его газом.
func core_of(b: Dictionary) -> float:
	if not b.has("core_m"):
		var k := 1.0
		# Тяжёлое ядро (мир «dense») — втрое больше, рыхлый мир — почти без ядра.
		match str(b.get("cls", "")):
			"dense":
				k = 3.0
			"puff":
				k = 0.5
			"icegiant":
				k = 1.6
		b["core_m"] = clampf(float(b.m) * 0.04 * k, 2.0, 60.0)
	return float(b.core_m)


## С соседа сорвало весь газ: осталось голое ядро — твёрдое тело,
## дальше его ведёт движок разрушения.
func _strip_rival(b: Dictionary) -> void:
	b.kind = "superearth"
	b["core"] = true
	b.mat = _core_mat(b)
	b.m = core_of(b)
	for k in ["sh", "shv", "ce", "ce_heat", "m0", "touched", "v", "cruise", "puff", "cls", "rings"]:
		b.erase(k)
	# Ядро — не газ (автор): высосать его нельзя. Оно твёрдое и уже в твоём
	# поле — сразу падает к тебе и рвётся приливом у предела Роша, как любое
	# твёрдое тело (вещество решает как: лёд крошится, камень плитами, железо
	# доходит до облаков целым и рвётся напором). Неважно, какого оно размера.
	b["sucked"] = true
	b.state = "free"
	b.cd = 0.0
	world._capture(b, stage.body.position, stage.hill(), stage.orbit)


## Ядро того, из чего сосед собирался: ледяной гигант — лёд, сажевый —
## углерод, тяжёлое ядро — железо, горячий нептун — лава, остальные — камень.
func _core_mat(b: Dictionary) -> String:
	return {"icegiant": "ice", "soot": "carbon", "dense": "metal", "hotnep": "lava"}.get(str(b.get("cls", "")), "rock")


## Ядро небольшого соседа выходит из его газа отдельным твёрдым телом и
## падает к тебе, а остаток газа течёт дальше струёй.
func _release_core(b: Dictionary) -> void:
	var cm := core_of(b)
	if float(b.m) <= cm * 1.05:
		return
	b["core_out"] = true
	if not b.has("m0"):
		b["m0"] = float(b.m)
	b.m = float(b.m) - cm
	var c: Dictionary = world._add_body("superearth", float(b.r), float(b.a), _core_mat(b), cm)
	c["core"] = true
	c["sucked"] = true
	c.erase("drift")
	if b.has("v"):
		c["v"] = b.v
	world._capture(c, stage.body.position, stage.hill(), stage.orbit)


## Приливный эллипс той же площади: полуоси 1+ε вдоль линии центров и
## 1/(1+ε) поперёк (не «восьмёрка», как у 1+ε·cos2θ при большом ε).
static func _ellipse(eps: float, th: float) -> float:
	var a := 1.0 + eps
	var b := 1.0 / a
	var c := cos(th)
	var s := sin(th)
	return a * b / sqrt(b * b * c * c + a * a * s * s)


## Полость: спереди — до L1 (газ стекает к соседу), сзади — не уже, чем
## сбоку: обратная точка лежит дальше, и тыл остаётся круглым (капля).
func _lobe(t: PackedFloat32Array, th: float) -> float:
	var r := Roche.lobe(t, th)
	if cos(th) < 0.0:
		r = maxf(r, Roche.lobe(t, PI * 0.5))
	return r


## Радиус формы в направлении th (локальные углы этой формы).
func _dir_r(s: PackedFloat32Array, th: float) -> float:
	var f := fposmod(th, TAU) / TAU * N
	var i := int(f) % N
	return lerpf(s[i], s[(i + 1) % N], f - floorf(f))


## Толчок крупного тела (мировые единицы скорости).
func _push(b: Dictionary, dv: Vector2) -> void:
	if b.state == "pass":
		b.vel = (b.vel as Vector2) + dv
	else:
		b["v"] = (b.get("v", Vector2.ZERO) as Vector2) + dv


## Своё движение тела с набранной скоростью (свободным телам _step_body его не даёт).
func move_bodies(delta: float) -> void:
	for b in world.bodies:
		if b.kind != "rival" or b.state != "free" or not b.has("v"):
			continue
		var v: Vector2 = b.v
		var np: Vector2 = world.pos_of(b) + v * delta
		b.r = np.length()
		b.a = np.angle()
		if not b.has("cruise"):
			v *= exp(-0.35 * delta)
		if v.length_squared() < 4.0:
			b.erase("v")
		else:
			b.v = v


func _heat_me(dir_local: Vector2, add: float, temp: float) -> void:
	var s := minf(shock.z + add, 1.0)
	var d := Vector2(shock.x, shock.y).lerp(dir_local, 0.3 if shock.z > 0.05 else 1.0).normalized()
	shock = Vector4(d.x, d.y, s, maxf(shock.w * 0.98, temp))


## Первое касание: ударная волна греет газ по линии удара, газ брызжет вбок.
func _first_touch(b: Dictionary, n: Vector2, vin: float, R1: float, R2: float, gpos: Vector2, p: Vector2) -> void:
	var v := maxf(vin, 0.0)
	var k := clampf(v / 700.0, 0.0, 1.0)
	b["ce_heat"] = maxf(float(b.get("ce_heat", 0.0)), 0.25 + 0.75 * k)
	# Температура за ударной волной растёт как v²: медленно — тёмно-красное, быстро — жёлтое.
	_heat_me(n.rotated(-float(stage.ang)), 0.25 + 0.75 * k, 0.9 + 1.6 * k * k)
	stage.body.impact_heat = maxf(stage.body.impact_heat, 0.3 * k)
	# Выброс: доля лёгкого ∝ (v/v_уб)², газ уходит веером вбок от линии удара.
	var light_me: bool = stage.earths < float(b.m)
	var ml: float = stage.earths if light_me else float(b.m)
	var frac := clampf(0.04 * k * k, 0.0, 0.04)
	if light_me:
		stage.earths -= ml * frac
	else:
		b.m = float(b.m) - ml * frac
	var at := gpos + n * (R1 - maxf(R1 + R2 - gpos.distance_to(p), 0.0) * 0.5)
	var side := n.orthogonal()
	var cnt := int(30 + 90 * k)
	for i in cnt:
		var sg := 1.0 if i % 2 == 0 else -1.0
		var dir := (side * sg).rotated(_rng.randfn(0.0, 0.35))
		var sp := (0.25 + 0.75 * _rng.randf()) * maxf(v, 150.0)
		var c := _my_col().lerp(_col_of(b), _rng.randf())
		_add_p(at + side * sg * _rng.randf_range(0.0, 0.3) * minf(R1, R2), dir * sp + (world._player_vel() + world._vel_of(b)) * 0.5,
			_rng.randf_range(2.5, 5.0), c.lerp(Color(1.0, 0.7, 0.4), 0.3 * k), _rng.randf_range(0.05, 0.12) * minf(R1, R2), null)


## Струя через L1: частицы стартуют у L1 с малой скоростью к соседу и
## скоростью донора; дальше — тяготение обоих.
func _emit(b: Dictionary, who: String, rate: float, at: Vector2, n: Vector2, acc_p: Vector2, don_p: Vector2, delta: float, c: Color) -> void:
	var key := str(b.id) + who
	var acc := float(_emit_acc.get(key, 0.0)) + clampf(rate * 1500.0, 6.0, 90.0) * delta
	var don_v: Vector2 = world._player_vel() if who == "me" else world._vel_of(b)
	var acc_v: Vector2 = world._vel_of(b) if who == "me" else world._player_vel()
	var R := don_p.distance_to(at)
	# Струя из точки Лагранжа несёт момент: относительное движение тел и
	# вращение принимающего уводят её вбок, и газ входит в облака по касательной
	# у края, закручиваясь дугой, а не падает отвесно в центр диска.
	var acc_m: float = float(b.m) if who == "me" else float(stage.earths)
	var d := maxf(acc_p.distance_to(at), 1.0)
	var t_dir := n.orthogonal()
	var side := signf(t_dir.dot(don_v - acc_v))
	if side == 0.0:
		side = 1.0
	var vt := 0.42 * sqrt(G * acc_m / d) * side
	while acc >= 1.0:
		acc -= 1.0
		var j := n.orthogonal() * _rng.randfn(0.0, 0.06) * R
		var v := don_v + n * _rng.randf_range(40.0, 110.0) + t_dir * (vt * _rng.randf_range(0.8, 1.15) + _rng.randfn(0.0, 25.0))
		_add_p(at + j, v, _rng.randf_range(3.0, 6.0), c, _rng.randf_range(0.04, 0.08) * R, b if who == "me" else {})
	_emit_acc[key] = acc


func _add_p(p: Vector2, v: Vector2, life: float, c: Color, size: float, to) -> void:
	if _p_pos.size() >= MAX_P:
		return
	_p_pos.append(p)
	_p_vel.append(v)
	_p_life.append(life)
	_p_max.append(life)
	_p_col.append(c)
	_p_size.append(size)
	_p_to.append(to)


func _step_particles(delta: float, gpos: Vector2, R1: float) -> void:
	_sink_p = gpos
	_sink_r = R1
	if _p_pos.is_empty():
		return
	var big := []
	for b in world.bodies:
		if b.kind in ["rival", "dwarf"] and b.state in ["free", "pass"]:
			big.append([world.pos_of(b), float(b.m), world.rad_of(b)])
	var keep := 0
	for i in _p_pos.size():
		var p := _p_pos[i]
		var v := _p_vel[i]
		var dead := false
		# Тебя и крупные тела чувствует каждая частица.
		var dg := gpos - p
		var r2 := maxf(dg.length_squared(), R1 * R1 * 0.25)
		v += dg / sqrt(r2) * G * float(stage.earths) / r2 * delta
		# Газ ныряет в облака у самого края: дальше его не видно.
		if dg.length() < R1 * 1.0 and _p_life[i] < _p_max[i] - 0.3:
			dead = true
		for bb in big:
			var dd: Vector2 = (bb[0] as Vector2) - p
			var rr := maxf(dd.length_squared(), float(bb[2]) * float(bb[2]) * 0.25)
			v += dd / sqrt(rr) * G * float(bb[1]) / rr * delta
			if dd.length() < float(bb[2]) * 1.0 and _p_life[i] < _p_max[i] - 0.3:
				dead = true
		v *= exp(-0.15 * delta)
		p += v * delta
		var life := _p_life[i] - delta
		if dead or life <= 0.0:
			continue
		_p_pos[keep] = p
		_p_vel[keep] = v
		_p_life[keep] = life
		_p_max[keep] = _p_max[i]
		_p_col[keep] = _p_col[i]
		_p_size[keep] = _p_size[i]
		_p_to[keep] = _p_to[i]
		keep += 1
	_p_pos.resize(keep)
	_p_vel.resize(keep)
	_p_life.resize(keep)
	_p_max.resize(keep)
	_p_col.resize(keep)
	_p_size.resize(keep)
	_p_to.resize(keep)


# --- Поглощение ---

func _begin_absorb(b: Dictionary, me: bool) -> void:
	if not absorbing.is_empty():
		return
	absorbing = b
	_absorb_t = 0.001
	b["absorb_me"] = me


## Лёгкое ядро тонет: лёгкий шар сжимается к центру тяжёлого, его газ
## переходит к тяжёлому. Ты — конец игры; сосед — его масса твоя.
func _step_absorb(delta: float, gpos: Vector2, R1: float, target: PackedFloat32Array) -> void:
	var b: Dictionary = absorbing
	if b.is_empty():
		_absorb_t = 0.0
		return
	_absorb_t += delta / 2.6
	var k := clampf(_absorb_t, 0.0, 1.0)
	var p: Vector2 = world.pos_of(b)
	var me: bool = b.get("absorb_me", false)
	var n := (p - gpos).normalized()
	if me:
		# Тебя тянет к центру соседа, оболочка стекает к нему: летите вместе.
		stage.vel = stage.vel.lerp(world._vel_of(b), minf(delta * 3.0, 1.0))
		stage.pos = stage.pos.lerp(p, minf(delta * 1.2, 1.0))
		for i in N:
			target[i] = minf(shape[i], lerpf(1.0, 0.18, k))
		stage.body.fade = 1.0 - smoothstep(0.35, 1.0, k)
		_heat_me(n.rotated(-float(stage.ang)), delta * 0.5, 1.6)
		if k >= 1.0:
			absorbing = {}
			stage.swallowed("giant_eaten_dwarf" if b.kind == "dwarf" else "giant_swallowed")
	else:
		var sb: PackedFloat32Array = b.sh
		for i in N:
			sb[i] = minf(sb[i], lerpf(1.0, 0.15, k))
		b.sh = sb
		var np := p.lerp(gpos, delta * 1.6)
		b.r = np.length()
		b.a = np.angle()
		_heat_me(n.rotated(-float(stage.ang)), delta * 0.4, 1.3)
		if k >= 1.0:
			var gain := float(b.m) * 0.94
			# Импульс сохраняется: слитое тело летит с общей скоростью.
			stage.vel = (stage.vel * stage.earths + world._vel_of(b) * gain) / (stage.earths + gain)
			stage.earths += gain
			stage.pay(gain)
			stage.body.impact_heat = maxf(stage.body.impact_heat, 0.55)
			b.state = "gone"
			world.bodies.erase(b)
			absorbing = {}
			_absorb_t = 0.0


# --- Вид: струи и выброс газа ---

func _draw() -> void:
	if _p_pos.is_empty():
		return
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	const SEG := 7
	for i in _p_pos.size():
		var k := _p_life[i] / _p_max[i]
		var p := _p_pos[i]
		var v := _p_vel[i]
		var c := _p_col[i]
		# Газ струи — не светится: тусклый, цвета донора, в тени своей стороны
		# темнее; редеет, расплываясь, и тонет в облаках у края (последние
		# 25% радиуса над облаками — угасает).
		var depth := smoothstep(_sink_r * 1.0, _sink_r * 1.25, p.distance_to(_sink_p))
		var r := _p_size[i] * (1.0 + 2.2 * (1.0 - k))
		c = c.darkened(0.25)
		c.a = 0.32 * minf(k * 3.0, 1.0) * minf((1.0 - k) * 10.0 + 0.3, 1.0) * depth / (1.0 + 0.8 * (1.0 - k))
		var edge := c
		edge.a = 0.0
		# Вытянуто по скорости: газ течёт струёй, а не точками.
		var ax := v.normalized() if v.length_squared() > 1.0 else Vector2.RIGHT
		var stretch := clampf(v.length() / 300.0, 1.0, 3.0)
		var i0 := pts.size()
		pts.append(p)
		cols.append(c)
		for j in SEG:
			var e := Vector2.from_angle(TAU * j / SEG)
			pts.append(p + ax * e.x * r * stretch + ax.orthogonal() * e.y * r)
			cols.append(edge)
		for j in SEG:
			idx.append_array([i0, i0 + 1 + j, i0 + 1 + (j + 1) % SEG])
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), idx, pts, cols)
