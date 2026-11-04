class_name FracWorld
extends Node2D
## Движок разрушения тел.
##
## Тело — набор ячеек (кусков будущего излома), соседние ячейки сцеплены
## швами. Пока швы целы, тело летит как одно твёрдое: центр масс, скорость,
## угол, вращение. Каждый кадр движок считает, с какой силой тело рвут
## снаружи (прилив, вращение, напор атмосферы, удар), и раскладывает эту
## силу по швам: шов несёт всё, что тянет за его плоскость половину тела.
## Перегруженный шов лопается, а близкий к пределу копит усталость, поэтому
## трещина идёт по телу за доли секунды, а не мгновенно. Когда тело
## распадается на части без связи, каждая часть становится своим телом:
## со своей массой, вращением и скоростью (её доля движения целого).
##
## Дальше части живут сами под тяготением поля: ближние к центру обгоняют
## дальних, и цепочка вытягивается сама. Газ тормозит мелкое сильнее
## крупного. Куски сталкиваются (отскок, трение) и от сильного удара ломаются
## снова. В атмосфере напор воздуха крошит их, трение греет, и они тают
## пылью. Мелкий кусок, которому ломаться дальше некуда, рассыпается пылью.
##
## Прочность шва калибруется при рождении тела: тело начинает трескаться
## там, где мир велит (предел Роша вещества), а мелкие куски крепче крупных
## (закон Вейбулла: в меньшем объёме меньше трещин). Поэтому одно и то же
## тело рвётся сперва надвое, потом на части, а мелочь держится до
## атмосферы.
##
## Мир (этап) даёт поле FracField и забирает массу через src.sink:
## sink(масса, кусок ли, точка, размер, src).

const DT_MAX := 1.0 / 90.0
const MAX_CELLS := 420
const MAX_GRAINS := 900
const MAX_CHUNKS := 64        # кусков больше — мелочь уже не дробится, а рассыпается пылью
const FATIGUE := 0.62        # шов под нагрузкой выше этой доли прочности копит усталость
const FATIGUE_K := 2.2
const TS_CHUNK := 2.6        # время торможения куска газом при плотности 1, с
const TS_GRAIN := 0.45
const TS_SPIN := 0.25
const CRACK_RATE := 6.0
const SPARK_V := 0.06         # удар быстрее этой доли v_ref — искры (у металла)       # швов в секунду на кусок (плюс 0,6 на ячейку)         # доля бокового ветра, что раскручивает куски
const RAM_K := 2.4           # напор атмосферы в долях прочности шва при скорости v_ref
const HEAT_K := 1.6          # нагрев трением в атмосфере
const IMPACT_K := 0.8        # скорость удара, что колет шов: IMPACT_K·L·√прилива_разрыва
var prof := Vector3.ZERO
var time_k := 1.0             # замедление времени движка (раскол виден глазом)
const LIFE := 40.0           # кусок дольше этого не живёт: тонет с учётом массы
const GRAIN_LIFE := 30.0

var field: FracField
var sources: Array = []
var chunks: Array = []
var _time := 0.0
var _rng := RandomNumberGenerator.new()
var _dust := Node2D.new()
# Пыль: упакованные массивы, по пылинке на индекс.
var gx := PackedFloat32Array()
var gy := PackedFloat32Array()
var gvx := PackedFloat32Array()
var gvy := PackedFloat32Array()
var gm := PackedFloat32Array()   # масса; < 0 — пылинки нет
var gs := PackedFloat32Array()   # размер, ед.
var gh := PackedFloat32Array()   # жар 0..1
var gk := PackedFloat32Array()   # своя связь с газом (множитель времени торможения)
var gt := PackedFloat32Array()   # возраст
var gsrc: Array = []             # Source пылинки
var _free_g := PackedInt32Array()
# Дымка: пар льда, сажа, облачка пыли из трещин — мягкие пятна, без массы.
const MAX_HAZE := 240
var hz: Array = []               # [pos, vel, t, life, size, grow, color, push]
var _vap_t := {}                 # Chunk → время до следующей струйки пара/дыма
var _n_cells := 0
var stats := {"breaks": 0, "splits": 0, "hits": 0, "dust": 0}


class Source:
	## Одно разрушенное тело: общий снимок поверхности, вещество, учёт массы.
	var tex: Texture2D = null
	var vp: Node = null
	var mat: Dictionary
	var mat_name := "rock"
	var col := Color(0.6, 0.55, 0.5)
	var sink: Callable
	var notify: Callable
	var left := 0.0          # масса, ещё не ушедшая в мир
	var sigma := 1.0         # прочность шва на единицу длины
	var tide0 := 1.0         # прилив, при котором тело начинает трескаться
	var L0 := 10.0           # радиус тела при рождении
	var S0 := 10.0           # размер (√площади) тела при рождении
	var coh := 0.8           # доля прочности от сцепления (остальное — тяготение груды)
	var M0 := 1.0
	var vq := 30.0           # скорость удара, что колет шов
	var inflow := 0.3
	var heat0 := 0.0
	var t := 0.0
	var refs := 0
	var broke := false
	var hit := false
	var seed_i := 0
	var id := 0
	var tag = null           # что угодно для мира


class Bond:
	var a: Cell
	var b: Cell
	var len := 1.0
	var s := 1.0             # прочность
	var w := 1.0             # разброс Вейбулла этого шва
	var dmg := 0.0
	var broken := false
	var crack := 0.0         # насколько трещина раскрылась на вид, 0..1


class Cell:
	var poly: PackedVector2Array     # вершины от центра ячейки
	var tri: PackedInt32Array
	var kind: PackedByteArray        # на ребро: 0 — поверхность, 1 — излом
	var bond: Array                  # на ребро: Bond или null
	var uv: PackedVector2Array
	var c := Vector2.ZERO            # центр ячейки в системе куска
	var m := 0.0
	var area := 0.0
	var size := 1.0
	var ik := 0.0                    # момент инерции на единицу массы
	var reach := 1.0
	var uvo := Vector2.ZERO          # снимок: uv центра и базис на единицу длины
	var uvx := Vector2.ZERO
	var uvy := Vector2.ZERO
	var chunk: Chunk
	var src: Source
	var heat := 0.0
	var gen := 0
	var tone := 1.0
	var id := 0
	var idx := 0
	var u := Vector2.ZERO            # смещение в сетке пружин (для решения нагрузок)


class Chunk:
	var cells: Array = []
	var bonds: Array = []            # швы внутри куска (и лопнувшие, пока он цел)
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var ang := 0.0
	var w := 0.0
	var m := 0.0
	var inertia := 1.0
	var rad := 1.0
	var size := 1.0
	var age := 0.0
	var grace := 0.0
	var family := 0
	var src: Source
	var dead := false
	var stress_t := 0.0
	var intact := 0                  # целых швов
	var crack_acc := 0.0             # сколько швов трещина успеет пройти


func _ready() -> void:
	_rng.randomize()
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/frac.gdshader")
	material = m
	_dust.show_behind_parent = true
	_dust.draw.connect(_draw_dust)
	add_child(_dust)


# ---------------------------------------------------------------------------
# Рождение тела

## Тело в движок. o: pos, vel, w, rad, mass, mat, tex, disc, tex_rot,
## sink, notify, cells, seed, r_crit (точка, где начинается разрыв приливом)
## или tide0 (прилив разрыва), col, heat, impact_at, inflow, tag.
func spawn_body(o: Dictionary) -> Source:
	var src := Source.new()
	var mat_name: String = o.get("mat", "rock")
	src.mat_name = mat_name
	src.mat = FracMat.get_mat(mat_name)
	src.tex = o.get("tex", null)
	src.vp = o.get("vp", null)
	src.col = o.get("col", src.mat["dust_col"])
	src.sink = o.get("sink", Callable())
	src.notify = o.get("notify", Callable())
	src.inflow = float(o.get("inflow", 0.3))
	src.heat0 = float(o.get("heat", src.mat["heat"]))
	src.tag = o.get("tag", null)
	src.seed_i = int(float(o.get("seed", _rng.randf())) * 100003.0)
	src.id = randi()
	_rng.seed = src.seed_i + 17
	var rad: float = maxf(float(o.get("rad", 20.0)), 2.0)
	var mass: float = maxf(float(o.get("mass", 1.0)), 1e-6)
	src.left = mass
	src.L0 = rad
	src.M0 = mass
	src.coh = float(o.get("coh", src.mat["coh"]))
	var pos: Vector2 = o.get("pos", Vector2.ZERO)
	var vel: Vector2 = o.get("vel", Vector2.ZERO)
	_budget(int(o.get("cells", 24)))
	# Прилив, при котором тело начинает рваться: из точки разрыва или задан.
	src.tide0 = field.tide(pos.normalized() * float(o.get("r_crit", pos.length())))
	# Прочность шва на единицу длины: центральный шов круглого тела несёт
	# 0,106·M·прилив (половина массы на плече 4L/3π, шов длиной 2L).
	src.sigma = 0.106 * mass * maxf(src.tide0, 1e-6)
	src.vq = IMPACT_K * rad * sqrt(maxf(src.tide0, 1e-6))
	# Нарезка: зёрна гуще вдоль линии на центр (там прилив и рвёт плитами)
	# или у точки удара.
	var n := clampi(int(round(float(o.get("cells", 24)) * float(src.mat["cells"]))), 3, 56)
	var seeds: PackedVector2Array
	if o.has("impact_at"):
		seeds = FracGeom.seeds_impact(n, rad, o.impact_at, _rng)
	else:
		seeds = FracGeom.seeds_tidal(n, rad, -pos.normalized() if pos.length() > 0.01 else Vector2.RIGHT, _rng)
	var shape := FracGeom.outline(rad, clampi(int(rad * 0.9), 20, 44), 0.05 if src.tex != null else 0.1, _rng)
	var stags := PackedInt32Array()
	stags.resize(shape.size())
	stags.fill(-1)
	var raw := FracGeom.voronoi(shape, stags, seeds)
	var tex_rot: float = float(o.get("tex_rot", 0.0))
	var disc: float = float(o.get("disc", 0.45))
	var ch := Chunk.new()
	ch.src = src
	ch.pos = pos
	ch.vel = vel
	ch.w = float(o.get("w", 0.0))
	ch.family = src.id
	var cells := _make_cells(raw, src, rad, float(src.mat["jag"]) * rad / sqrt(float(n)), 0,
		Vector2(0.5, 0.5), Vector2(cos(tex_rot), sin(tex_rot)) * disc / rad, Vector2(-sin(tex_rot), cos(tex_rot)) * disc / rad, Vector2.ZERO, mass)
	ch.cells = cells[0]
	ch.bonds = cells[1]
	for c: Cell in ch.cells:
		c.chunk = ch
		c.heat = src.heat0 * _rng.randf_range(0.7, 1.0)
	_finish_chunk(ch, true)
	# Калибровка: в точке разрыва самый слабый шов держит ровно свою
	# нагрузку — там тело и начинает трескаться, остальные позже.
	if ch.bonds.size() > 0 and ch.cells.size() > 1:
		# Каждый шов знает, как сильно его может нагрузить прилив (по восьми
		# поворотам тела — худший). Его прочность — наполовину от этой
		# нагрузки, наполовину общая на единицу длины: тело рвётся у предела
		# при любом повороте, а середина (где нагрузка больше) — первой.
		# Чуть выше предела: к самому пределу тело уже идёт трещинами.
		var at: Vector2 = pos.normalized() * float(o.get("r_crit", pos.length())) * 1.1
		var a0 := ch.ang
		var nb := ch.bonds.size()
		var worst := PackedFloat32Array()
		worst.resize(nb)
		var sum := 0.0
		for k in 8:
			ch.ang = a0 + PI * k / 8.0
			var loads: PackedFloat32Array = _loads(ch, at, 160)[0]
			var best := 0.0
			for bi in nb:
				var bd: Bond = ch.bonds[bi]
				worst[bi] = maxf(worst[bi], loads[bi])
				best = maxf(best, loads[bi] / maxf(bd.len * bd.w, 1e-6))
			sum += best
		ch.ang = a0
		src.S0 = ch.size
		if sum > 0.0:
			src.sigma = sum / 8.0
			for bi in nb:
				var bd: Bond = ch.bonds[bi]
				bd.s = bd.w * (0.5 * maxf(worst[bi], 1e-9) + 0.5 * src.sigma * maxf(bd.len, 0.01))
	chunks.append(ch)
	sources.append(src)
	return src


## Ячейки из сырых многоугольников Вороного. Центры — в системе тела
## (origin — где центр тела в этой системе). uv: снимок, uv0 — uv точки
## origin, ux/uy — uv на единицу длины. Возвращает [ячейки, швы].
func _make_cells(raw: Array, src: Source, rad: float, amp: float, gen: int, uv0: Vector2, ux: Vector2, uy: Vector2, origin: Vector2, mass: float) -> Array:
	var cells: Array = []
	var by_idx := {}
	var total := 0.0
	var polys := []
	for i in raw.size():
		var r: Array = raw[i]
		if r.is_empty():
			polys.append(null)
			continue
		var jg: Array = FracGeom.jag(r[0], r[1], i, amp, src.seed_i + gen * 7)
		var poly: PackedVector2Array = jg[0]
		var tri := Geometry2D.triangulate_polygon(poly)
		if tri.is_empty():
			# Рваный излом вышел самопересекающимся: берём ровный.
			jg = [r[0], r[1]]
			poly = r[0]
			tri = Geometry2D.triangulate_polygon(poly)
			if tri.is_empty():
				polys.append(null)
				continue
		var a := FracGeom.area(poly)
		if a < 1e-4:
			polys.append(null)
			continue
		polys.append([poly, jg[1], tri, a, FracGeom.centroid(poly)])
		total += a
	for i in polys.size():
		var pd = polys[i]
		if pd == null:
			continue
		var cell := Cell.new()
		var cen: Vector2 = pd[4]
		var poly: PackedVector2Array = pd[0]
		var loc := PackedVector2Array()
		loc.resize(poly.size())
		for k in poly.size():
			loc[k] = poly[k] - cen
		cell.poly = loc
		cell.tri = pd[2]
		var tags: PackedInt32Array = pd[1]
		cell.kind = PackedByteArray()
		cell.kind.resize(tags.size())
		cell.bond = []
		cell.bond.resize(tags.size())
		for k in tags.size():
			cell.kind[k] = 0 if tags[k] == -1 else 1
		cell.c = origin + cen
		cell.area = pd[3]
		cell.m = mass * cell.area / total
		cell.size = sqrt(cell.area)
		cell.ik = FracGeom.inertia_k(loc)
		cell.reach = FracGeom.reach(loc)
		cell.uvo = uv0 + ux * cen.x + uy * cen.y
		cell.uvx = ux
		cell.uvy = uy
		cell.uv = PackedVector2Array()
		cell.uv.resize(loc.size())
		for k in loc.size():
			cell.uv[k] = cell.uvo + ux * loc[k].x + uy * loc[k].y
		cell.src = src
		cell.gen = gen
		cell.tone = _rng.randf_range(0.88, 1.1)
		cell.id = i
		src.refs += 1
		_n_cells += 1
		by_idx[i] = cell
		cells.append(cell)
	# Швы: по каждому внутреннему ребру — с соседом, один шов на пару.
	var bonds: Array = []
	var pair := {}
	for i in polys.size():
		var pd = polys[i]
		if pd == null or not by_idx.has(i):
			continue
		var cell: Cell = by_idx[i]
		var tags: PackedInt32Array = pd[1]
		var poly: PackedVector2Array = pd[0]
		for k in tags.size():
			var j := tags[k]
			if j < 0:
				continue
			if not by_idx.has(j):
				# Сосед выродился: ребро — свежий излом наружу.
				continue
			var key := Vector2i(mini(i, j), maxi(i, j))
			var bd: Bond = pair.get(key, null)
			if bd == null:
				bd = Bond.new()
				bd.a = by_idx[key.x]
				bd.b = by_idx[key.y]
				bd.len = 0.0
				bd.w = exp(_rng.randfn(0.0, 1.1 / float(src.mat["weib"])))
				pair[key] = bd
				bonds.append(bd)
			if i == key.x:
				bd.len += poly[k].distance_to(poly[(k + 1) % poly.size()])
			cell.bond[k] = bd
	for bd: Bond in bonds:
		bd.s = src.sigma * maxf(bd.len, 0.01) * bd.w
	return [cells, bonds]


## Масса, центр, инерция, размер куска. reset — ячейки уже от центра.
func _finish_chunk(ch: Chunk, reset := false) -> void:
	var m := 0.0
	var c := Vector2.ZERO
	for cell: Cell in ch.cells:
		m += cell.m
		c += cell.c * cell.m
	c /= maxf(m, 1e-9)
	if c.length_squared() > 1e-8:
		for cell: Cell in ch.cells:
			cell.c -= c
		ch.pos += c.rotated(ch.ang)
	var I := 0.0
	var rad := 0.0
	var area := 0.0
	for cell: Cell in ch.cells:
		I += cell.m * (cell.ik + cell.c.length_squared())
		rad = maxf(rad, cell.c.length() + cell.reach)
		area += cell.area
	ch.m = m
	ch.inertia = maxf(I, 1e-9)
	ch.rad = maxf(rad, 0.5)
	ch.size = sqrt(area)
	var n := 0
	for bd: Bond in ch.bonds:
		if not bd.broken:
			n += 1
	ch.intact = n


## Места на новые ячейки: если их слишком много, старое облако досрочно
## тонет (масса засчитывается миру).
func _budget(want: int) -> void:
	while _n_cells + want > MAX_CELLS and not sources.is_empty():
		_finish_source(sources[0])


func _finish_source(src: Source) -> void:
	for ch: Chunk in chunks:
		if ch.src == src and not ch.dead:
			_sink_chunk(ch, true)
	for i in gm.size():
		if gm[i] >= 0.0 and gsrc[i] == src:
			_pay(src, gm[i], false, Vector2(gx[i], gy[i]), 0.0)
			_kill_grain(i)
	if src.left > 1e-9 and src.sink.is_valid():
		src.sink.call(src.left, false, Vector2.ZERO, 0.0, src)
	src.left = 0.0
	_drop_source(src)


func _drop_source(src: Source) -> void:
	if src.vp != null and is_instance_valid(src.vp):
		src.vp.queue_free()
		src.vp = null
	sources.erase(src)
	if src.notify.is_valid():
		src.notify.call("done", src)


# ---------------------------------------------------------------------------
# Шаг

func step(delta: float) -> void:
	if field == null:
		return
	delta *= time_k
	_time += delta
	delta = minf(delta, 0.05)
	var n := maxi(1, ceili(delta / DT_MAX))
	var dt := delta / n
	var t0 := Time.get_ticks_usec()
	# Толпа кусков сталкивается раз за кадр, а не на каждом подшаге.
	var crowd := chunks.size() > 24
	for i in n:
		_move_chunks(dt)
		if not crowd:
			_collide(dt)
	if crowd:
		_collide(delta)
	var t1 := Time.get_ticks_usec()
	_stress(delta)
	var t2 := Time.get_ticks_usec()
	_entry(delta)
	_step_grains(delta)
	_step_haze(delta)
	_cleanup()
	prof = Vector3(t1 - t0, t2 - t1, Time.get_ticks_usec() - t2)
	queue_redraw()
	_dust.queue_redraw()


func _move_chunks(dt: float) -> void:
	for ch: Chunk in chunks:
		if ch.dead:
			continue
		var src: Source = ch.src
		var a := field.accel(ch.pos, ch.vel)
		var rho := field.gas_rho(ch.pos)
		var vg := field.gas_v(ch.pos, src.inflow * (1.0 + maxf(ch.age - 5.0, 0.0) * 0.35))
		var ts := TS_CHUNK * sqrt(ch.size / maxf(src.L0, 0.1)) * float(src.mat["rho"]) / maxf(rho, 0.02)
		var v := ch.vel + a * dt
		# Кусок тяжёл: газ тормозит его падение и сносит внутрь, но вбок
		# почти не раскручивает (кусок летит по своей орбите, а не с ветром).
		var rh := ch.pos.normalized()
		var tg := Vector2(-rh.y, rh.x)
		vg = rh * vg.dot(rh) + tg * lerpf(v.dot(tg), vg.dot(tg), TS_SPIN)
		ch.vel = vg + (v - vg) * exp(-dt / maxf(ts, 0.005))
		ch.pos += ch.vel * dt
		ch.ang += ch.w * dt
		ch.age += dt
		ch.grace = maxf(ch.grace - dt, 0.0)


## Нагрузка на швы: внешние силы на каждую ячейку минус то, что нужно ей,
## чтобы лететь с телом как одно целое. Сумма по одну сторону шва — то, что
## шов держит.
func _stress(delta: float) -> void:
	var born: Array = []
	for ch: Chunk in chunks:
		if ch.dead:
			continue
		var src: Source = ch.src
		var nc := ch.cells.size()
		if nc == 1:
			_stress_single(ch, born)
			continue
		if ch.intact == 0:
			continue
		var lt := _loads(ch, ch.pos)
		var loads: PackedFloat32Array = lt[0]
		# Приливный момент: вытянутый кусок разворачивает вдоль линии на центр.
		ch.w += float(lt[1]) / ch.inertia * delta
		# Напор атмосферы — в долях прочности шва.
		var at := field.atm(ch.pos)
		var ram := 0.0
		if at > 0.0:
			var vr := (ch.vel - field.gas_v(ch.pos, 0.0)).length() / maxf(field.v_ref(), 1.0)
			ram = RAM_K * float(src.mat["ram"]) * at * vr * vr
		var wk := _strength_k(src, ch.size)
		var cand: Array = []
		for bi in ch.bonds.size():
			var bd: Bond = ch.bonds[bi]
			if bd.broken:
				bd.crack = minf(bd.crack + delta * 2.5, 1.0)
				continue
			var load := loads[bi] + ram * src.sigma * bd.len
			var eff := bd.s * (1.0 - bd.dmg) * wk
			var ratio := load / maxf(eff, 1e-12)
			if ratio > 1.0:
				cand.append([ratio, bd])
			elif ratio > FATIGUE:
				bd.dmg = minf(bd.dmg + FATIGUE_K * (ratio - FATIGUE) * delta, 0.9)
		if cand.is_empty():
			continue
		# Трещина бежит с конечной скоростью: за кадр лопается несколько
		# самых нагруженных швов, остальные — в следующих кадрах.
		cand.sort_custom(func(x, y) -> bool: return x[0] > y[0])
		# Скорость трещины — швов в секунду, а не в кадр: раскол виден.
		ch.crack_acc = minf(ch.crack_acc + delta * (CRACK_RATE + nc * 0.6), float(cand.size()))
		var lim := int(ch.crack_acc)
		if lim < 1:
			continue
		ch.crack_acc -= lim
		for i in mini(lim, cand.size()):
			_break(ch, cand[i][1] as Bond)
		_split(ch, born, Vector2.ZERO, 0.0)
	chunks.append_array(born)


## Нагрузка на каждый шов куска, если бы он был в точке at.
## На каждую ячейку действует внешняя сила минус то, что нужно ей, чтобы
## лететь с куском как одно целое (общее ускорение и вращение). Швы —
## пружины между центрами ячеек (жёсткость по длине шва); решаем, как
## растянется сетка под этими силами (Гаусс — Зейдель, с прошлого решения),
## и натяжение пружины — нагрузка шва. Лопнул шов — его ношу берут
## соседи, у кончика трещины нагрузка растёт, и трещина бежит дальше.
## iters — итераций решения. Возвращает [нагрузки по ch.bonds, момент сил].
func _loads(ch: Chunk, at: Vector2, iters := 24) -> Array:
	var nc := ch.cells.size()
	var cs := cos(ch.ang)
	var sn := sin(ch.ang)
	var xs := PackedVector2Array()
	var fs := PackedVector2Array()
	xs.resize(nc)
	fs.resize(nc)
	var A := Vector2.ZERO
	for k in nc:
		var cell: Cell = ch.cells[k]
		cell.idx = k
		var r := Vector2(cell.c.x * cs - cell.c.y * sn, cell.c.x * sn + cell.c.y * cs)
		xs[k] = r
		var ak := field.stress_accel(at + r, ch.vel + Vector2(-r.y, r.x) * ch.w)
		fs[k] = ak
		A += ak * cell.m
	A /= ch.m
	var w2 := ch.w * ch.w
	var tq := 0.0
	for k in nc:
		var cell: Cell = ch.cells[k]
		var f: Vector2 = (fs[k] - A) * cell.m
		tq += xs[k].cross(f)
		fs[k] = f + xs[k] * (w2 * cell.m)
	# Сетка пружин: по ячейке — список (шов, сосед, направление, жёсткость).
	var nb := ch.bonds.size()
	var dirs := PackedVector2Array()
	var ks := PackedFloat32Array()
	dirs.resize(nb)
	ks.resize(nb)
	var adj: Array = []
	adj.resize(nc)
	for k in nc:
		adj[k] = []
	var kmax := 0.0
	for bi in nb:
		var bd: Bond = ch.bonds[bi]
		if bd.broken:
			continue
		var d: Vector2 = xs[bd.b.idx] - xs[bd.a.idx]
		var dl := maxf(d.length(), 1e-4)
		dirs[bi] = d / dl
		ks[bi] = bd.len / dl
		kmax = maxf(kmax, ks[bi])
		(adj[bd.a.idx] as Array).append(bi)
		(adj[bd.b.idx] as Array).append(bi)
	var eps := kmax * 0.0005 + 1e-9
	var us := PackedVector2Array()
	us.resize(nc)
	for k in nc:
		us[k] = (ch.cells[k] as Cell).u
	# Шов держит и разрыв, и сдвиг (ячейки сцеплены рваным краем), поэтому
	# пружина одинаково жёсткая во все стороны: висящая на одном шве ячейка
	# передаёт ему всю свою ношу, перемычка между частями несёт всё.
	for it in iters:
		for k in nc:
			var den := eps
			var rhs: Vector2 = fs[k]
			for bi in adj[k]:
				var bd: Bond = ch.bonds[bi]
				var o: int = bd.b.idx if bd.a.idx == k else bd.a.idx
				var kk: float = ks[bi]
				den += kk
				rhs += us[o] * kk
			us[k] = rhs / den
	# Снимаем общий сдвиг, чтобы решение не уплывало.
	var mean := Vector2.ZERO
	for k in nc:
		mean += us[k]
	mean /= maxf(nc, 1)
	for k in nc:
		(ch.cells[k] as Cell).u = us[k] - mean
	var out := PackedFloat32Array()
	out.resize(nb)
	for bi in nb:
		var bd: Bond = ch.bonds[bi]
		if bd.broken:
			continue
		# Разрыв — полностью, сдвиг — с весом (на срез вещество крепче).
		var fv: Vector2 = (us[bd.b.idx] - us[bd.a.idx]) * ks[bi]
		out[bi] = maxf(fv.dot(dirs[bi]), 0.0) + 0.6 * absf(fv.cross(dirs[bi]))
	return [out, tq]


## Во сколько раз шов куска размера size крепче, чем у целого тела.
## Прочность — сцепление вещества (не зависит от размера, у мелкого даже
## выше: меньше трещин, закон Вейбулла) плюс тяготение груды (держит тем
## слабее, чем меньше кусок, ∝ size²). У монолита (железо, камень) почти всё
## — сцепление: куски держатся. У груды обломков и кометы почти всё —
## тяготение: внутри предела Роша она рассыпается целиком, до пыли.
func _strength_k(src: Source, size: float) -> float:
	var x := clampf(size / maxf(src.S0, 0.01), 0.0, 1.0)
	return src.coh * pow(1.0 / maxf(x, 0.05), 1.5 / float(src.mat["weib"])) + (1.0 - src.coh) * x * x


## Кусок из одной ячейки: дробится, если его рвёт сильнее, чем держит
## его собственная толща (обычно — напор атмосферы).
func _stress_single(ch: Chunk, born: Array) -> void:
	var cell: Cell = ch.cells[0]
	var src: Source = ch.src
	var at := field.atm(ch.pos)
	var tide := field.tide(ch.pos)
	var wk := _strength_k(src, cell.size)
	# Прилив поперёк самой ячейки (как у шва посередине) и вращение.
	var cut := 1.13 * cell.size
	var load := 0.12 * cell.m * (tide + 2.0 * ch.w * ch.w) * cell.size
	var strength := src.sigma * cut * wk
	if at > 0.0:
		var vr := (ch.vel - field.gas_v(ch.pos, 0.0)).length() / maxf(field.v_ref(), 1.0)
		load += RAM_K * float(src.mat["ram"]) * at * vr * vr * src.sigma * cut
	if load < strength:
		return
	if cell.size > src.L0 * 0.16 and cell.gen < 3:
		_subdivide(ch, born, Vector2.ZERO, false)
	elif load > strength * 1.6:
		_pulverize(ch, cell, 1.0)


## Шов лопнул: из излома сыплется крошка (рыхлое — больше).
func _break(ch: Chunk, bd: Bond) -> void:
	bd.broken = true
	stats.breaks += 1
	var src: Source = ch.src
	var share := float(src.mat["dust"]) * 0.05
	var ma := bd.a.m * share
	var mb := bd.b.m * share
	bd.a.m -= ma
	bd.b.m -= mb
	var cs := cos(ch.ang)
	var sn := sin(ch.ang)
	var mid: Vector2 = (bd.a.c + bd.b.c) * 0.5
	var r := Vector2(mid.x * cs - mid.y * sn, mid.x * sn + mid.y * cs)
	var at := ch.pos + r
	var v := ch.vel + Vector2(-r.y, r.x) * ch.w
	var axis := (bd.b.c - bd.a.c).normalized().rotated(ch.ang).orthogonal()
	var hk := float(src.mat.get("haze", 0.5))
	if hk > 0.05:
		var hc: Color = src.mat.get("dust_col", Color(0.6, 0.55, 0.5))
		hc.a = 0.22 + 0.25 * hk
		_add_haze(at, v, bd.len * 0.5, bd.len * (0.4 + 0.8 * hk), _rng.randf_range(2.5, 4.5), hc, Vector2.ZERO)
	var cnt := clampi(int(bd.len / maxf(src.L0, 0.1) * 8.0 * (0.5 + float(src.mat["dust"]))), 2, 7)
	for i in cnt:
		var along := axis * bd.len * _rng.randf_range(-0.5, 0.5)
		_add_grain(src, at + along, v + _rng.randf_range(-1.0, 1.0) * axis.orthogonal() * src.L0 * 0.4 + along * 0.3,
			(ma + mb) / cnt, src.L0 * _rng.randf_range(0.03, 0.07), maxf(bd.a.heat, bd.b.heat))


## Лопнули швы: ищем части без связи (объединение по целым швам) и
## разделяем кусок. Каждой части — её доля движения целого.
func _split(ch: Chunk, born: Array, kick_at: Vector2, kick_v: float) -> void:
	var nc := ch.cells.size()
	var parent := {}
	for c: Cell in ch.cells:
		parent[c] = c
	var find := func(x):
		var r = x
		while parent[r] != r:
			r = parent[r]
		return r
	for bd: Bond in ch.bonds:
		if bd.broken:
			continue
		var ra = find.call(bd.a)
		var rb = find.call(bd.b)
		if ra != rb:
			parent[ra] = rb
	var groups := {}
	for c: Cell in ch.cells:
		var r = find.call(c)
		if not groups.has(r):
			groups[r] = []
		(groups[r] as Array).append(c)
	_finish_chunk_intact(ch)
	if groups.size() <= 1:
		return
	stats.splits += 1
	var src: Source = ch.src
	if not src.broke:
		src.broke = true
		if src.notify.is_valid():
			src.notify.call("break", src)
	var list: Array = groups.values()
	# Самая большая часть остаётся этим куском, остальные — новые.
	list.sort_custom(func(x, y) -> bool: return x.size() > y.size())
	var old_bonds: Array = ch.bonds
	var base_pos := ch.pos
	var base_vel := ch.vel
	var base_w := ch.w
	for gi in list.size():
		var grp: Array = list[gi]
		var nch: Chunk = ch if gi == 0 else Chunk.new()
		if gi > 0:
			nch.src = src
			nch.ang = ch.ang
			nch.w = base_w
			nch.age = ch.age
			nch.family = ch.family
			born.append(nch)
		nch.pos = base_pos
		nch.cells = grp
		var gset := {}
		for c: Cell in grp:
			gset[c] = true
			c.chunk = nch
		var bl: Array = []
		for bd: Bond in old_bonds:
			if gset.has(bd.a) and gset.has(bd.b):
				bl.append(bd)
		nch.bonds = bl
		nch.pos = base_pos
		_finish_chunk(nch)
		# Скорость части: поступательная целого плюс вращение вокруг его центра.
		var r := nch.pos - base_pos
		nch.vel = base_vel + Vector2(-r.y, r.x) * base_w
		if kick_v > 0.0:
			var away := (nch.pos - kick_at)
			if away.length_squared() > 1e-6:
				nch.vel += away.normalized() * kick_v * _rng.randf_range(0.5, 1.0) * sqrt(src.L0 / maxf(nch.size, 0.5)) * 0.35
		nch.grace = 0.25


func _finish_chunk_intact(ch: Chunk) -> void:
	var n := 0
	for bd: Bond in ch.bonds:
		if not bd.broken:
			n += 1
	ch.intact = n


## Дробление куска-ячейки: внутри неё — свои ячейки и швы (следующее
## поколение), рисуются тем же снимком. near — где гуще (точка удара).
func _subdivide(ch: Chunk, born: Array, near: Vector2, by_impact: bool) -> void:
	var cell: Cell = ch.cells[0]
	var src: Source = ch.src
	if chunks.size() > MAX_CHUNKS:
		_pulverize(ch, cell, 1.0)
		return
	var n := clampi(int(round(cell.size / src.L0 * 14.0 * float(src.mat["cells"]))) + 2, 3, 8)
	_budget(n)
	if ch.dead:
		return
	var r := cell.reach
	var seeds := FracGeom.seeds_impact(n, r * 0.9, near, _rng) if by_impact else FracGeom.seeds_tidal(n, r * 0.9, -(ch.pos.normalized()).rotated(-ch.ang), _rng)
	if seeds.size() < 2:
		_pulverize(ch, cell, 1.0)
		return
	# Контур — сама ячейка: её рёбра снаружи остаются как были (поверхность
	# или старый излом).
	var tags := PackedInt32Array()
	tags.resize(cell.poly.size())
	for k in cell.poly.size():
		tags[k] = -1 if cell.kind[k] == 0 else -2
	var raw := FracGeom.voronoi(cell.poly, tags, seeds)
	var res := _make_cells(raw, src, r, float(src.mat["jag"]) * r / sqrt(float(n)) * 0.8, cell.gen + 1,
		cell.uvo, cell.uvx, cell.uvy, cell.c, cell.m)
	var cells: Array = res[0]
	if cells.size() < 2:
		for c: Cell in cells:
			_n_cells -= 1
			src.refs -= 1
		return
	# Старые изломы на краю ячейки остаются изломом (−2 → kind 1, без шва).
	for c: Cell in cells:
		c.heat = cell.heat
		c.chunk = ch
	_n_cells -= 1
	src.refs -= 1
	ch.cells = cells
	ch.bonds = res[1]
	_finish_chunk(ch)


## Мелочь рассыпается пылью: масса — в пылинки, вылетают со скоростью куска.
func _pulverize(ch: Chunk, cell: Cell, share: float) -> void:
	var src: Source = ch.src
	var r := cell.c.rotated(ch.ang)
	var at := ch.pos + r
	var v := ch.vel + Vector2(-r.y, r.x) * ch.w
	var cnt := clampi(int(cell.size / maxf(src.L0, 0.1) * 30.0), 3, 14)
	var dm := cell.m * share / cnt
	for i in cnt:
		var off := Vector2.from_angle(_rng.randf() * TAU) * cell.reach * sqrt(_rng.randf())
		_add_grain(src, at + off, v + off * _rng.randf_range(0.5, 2.0), dm, cell.size * _rng.randf_range(0.08, 0.22), cell.heat)
	stats.dust += cnt
	ch.cells.erase(cell)
	cell.chunk = null
	_n_cells -= 1
	src.refs -= 1
	if ch.cells.is_empty():
		ch.dead = true
		return
	var keep: Array = []
	for bd: Bond in ch.bonds:
		if bd.a != cell and bd.b != cell:
			keep.append(bd)
	ch.bonds = keep
	_finish_chunk(ch)


# ---------------------------------------------------------------------------
# Столкновения кусков

func _collide(dt: float) -> void:
	var n := chunks.size()
	if n < 2:
		return
	# Сетка: каждая клетка — 2 радиуса самого крупного куска (не больше
	# доли поля), сравниваем только соседей.
	var cellsz := 8.0
	for ch: Chunk in chunks:
		cellsz = maxf(cellsz, ch.rad * 2.0)
	var grid := {}
	for i in n:
		var ch: Chunk = chunks[i]
		if ch.dead:
			continue
		var key := Vector2i(floori(ch.pos.x / cellsz), floori(ch.pos.y / cellsz))
		if not grid.has(key):
			grid[key] = []
		(grid[key] as Array).append(i)
	var born: Array = []
	for i in n:
		var a: Chunk = chunks[i]
		if a.dead:
			continue
		var key := Vector2i(floori(a.pos.x / cellsz), floori(a.pos.y / cellsz))
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var lst = grid.get(key + Vector2i(dx, dy), null)
				if lst == null:
					continue
				for j in lst:
					if j <= i:
						continue
					var b: Chunk = chunks[j]
					if b.dead:
						continue
					if a.family == b.family and (a.grace > 0.0 or b.grace > 0.0):
						continue
					var d := a.pos.distance_to(b.pos)
					if d > a.rad + b.rad:
						continue
					_contact(a, b, born)
	chunks.append_array(born)


## Касание двух кусков: ищем самую глубокую пару ячеек (кругами), толкаем
## импульсом с отскоком и трением, сильный удар колет швы.
func _contact(a: Chunk, b: Chunk, born: Array) -> void:
	var best := 0.0
	var pa := Vector2.ZERO
	var pb := Vector2.ZERO
	var ra := 0.0
	var rb := 0.0
	var ca := cos(a.ang)
	var sa := sin(a.ang)
	var cb := cos(b.ang)
	var sb := sin(b.ang)
	for x: Cell in a.cells:
		var xa: Vector2 = a.pos + Vector2(x.c.x * ca - x.c.y * sa, x.c.x * sa + x.c.y * ca)
		var rx: float = x.size * 0.56
		if xa.distance_to(b.pos) > b.rad + rx:
			continue
		for y: Cell in b.cells:
			var yb: Vector2 = b.pos + Vector2(y.c.x * cb - y.c.y * sb, y.c.x * sb + y.c.y * cb)
			var ry: float = y.size * 0.56
			var pen := rx + ry - xa.distance_to(yb)
			if pen > best:
				best = pen
				pa = xa
				pb = yb
				ra = rx
				rb = ry
	if best <= 0.0:
		return
	var nrm := (pb - pa)
	if nrm.length_squared() < 1e-8:
		nrm = (b.pos - a.pos)
	nrm = nrm.normalized()
	var p := pa + nrm * (ra - best * 0.5)
	var r1 := p - a.pos
	var r2 := p - b.pos
	var v1 := a.vel + Vector2(-r1.y, r1.x) * a.w
	var v2 := b.vel + Vector2(-r2.y, r2.x) * b.w
	var vrel := v2 - v1
	var vn := vrel.dot(nrm)
	# Раздвигаем по массе, чтобы не вязли друг в друге.
	var inv1 := 1.0 / a.m
	var inv2 := 1.0 / b.m
	var corr := nrm * best * 0.6 / (inv1 + inv2)
	a.pos -= corr * inv1
	b.pos += corr * inv2
	if vn >= 0.0:
		return
	var e := (float(a.src.mat["rest"]) + float(b.src.mat["rest"])) * 0.5
	var rn1 := r1.cross(nrm)
	var rn2 := r2.cross(nrm)
	var k := inv1 + inv2 + rn1 * rn1 / a.inertia + rn2 * rn2 / b.inertia
	var j := -(1.0 + e) * vn / k
	var imp := nrm * j
	# Трение по касательной.
	var tg := nrm.orthogonal()
	var vt := vrel.dot(tg)
	var rt1 := r1.cross(tg)
	var rt2 := r2.cross(tg)
	var kt := inv1 + inv2 + rt1 * rt1 / a.inertia + rt2 * rt2 / b.inertia
	var mu := (float(a.src.mat["fric"]) + float(b.src.mat["fric"])) * 0.5
	var jt := clampf(-vt / kt, -mu * j, mu * j)
	imp += tg * jt
	a.vel -= imp * inv1
	b.vel += imp * inv2
	a.w -= r1.cross(imp) / a.inertia
	b.w += r2.cross(imp) / b.inertia
	stats.hits += 1
	var sk := maxf(float(a.src.mat.get("sparks", 0.0)), float(b.src.mat.get("sparks", 0.0)))
	if sk > 0.0 and -vn > SPARK_V * field.v_ref():
		# Удар на километрах в секунду плавит край: брызги капель, светятся и гаснут.
		var n := clampi(int(sk * 3.0 + -vn / field.v_ref() * 20.0 * sk), 1, 8)
		var vc := (a.vel * inv2 + b.vel * inv1) / (inv1 + inv2)
		for i in n:
			var dv := (tg * _rng.randf_range(-1.0, 1.0) + nrm * _rng.randf_range(-0.4, 0.4)) * -vn * _rng.randf_range(0.3, 0.9)
			_add_grain(a.src, p, vc + dv, 1e-9, a.src.L0 * 0.025, 1.25)
	# Удар колет швы у точки касания, дальше — слабее.
	_impact_crack(a, p, -vn, born)
	_impact_crack(b, p, -vn, born)


func _impact_crack(ch: Chunk, p: Vector2, v: float, born: Array) -> void:
	if ch.dead:
		return
	var src: Source = ch.src
	var q := v / maxf(src.vq, 0.01)
	if q < 0.6:
		return
	var loc := (p - ch.pos).rotated(-ch.ang)
	var wk := _strength_k(src, ch.size)
	if ch.cells.size() == 1:
		var cell: Cell = ch.cells[0]
		var wk1 := _strength_k(src, cell.size)
		if q > 1.4 * wk1:
			if cell.size > src.L0 * 0.14 and cell.gen < 3:
				_subdivide(ch, born, loc - cell.c, true)
				_impact_crack(ch, p, v * 0.8, born)
			else:
				_pulverize(ch, cell, 1.0)
		return
	var lam := maxf(ch.size * 0.45, 0.5)
	var any := false
	for bd: Bond in ch.bonds:
		if bd.broken:
			continue
		var mid: Vector2 = (bd.a.c + bd.b.c) * 0.5
		var load := q * exp(-mid.distance_to(loc) / lam)
		if load > bd.w * (1.0 - bd.dmg) * wk:
			_break(ch, bd)
			any = true
		elif load > FATIGUE * bd.w * wk:
			bd.dmg = minf(bd.dmg + 0.25 * load, 0.9)
	if any:
		_split(ch, born, ch.pos + loc.rotated(ch.ang), v * 0.25)


# ---------------------------------------------------------------------------
# Атмосфера, поверхность, пыль

## Вход в атмосферу: трение греет, жар плавит кусок с краёв в пыль, кусок,
## ушедший под облака, тонет (мир получает массу и место удара).
func _entry(delta: float) -> void:
	for ch: Chunk in chunks:
		if ch.dead:
			continue
		var src: Source = ch.src
		var at := field.atm(ch.pos)
		var cool := 0.25 / sqrt(maxf(ch.size / maxf(src.L0, 0.1), 0.05))
		var vr := 0.0
		if at > 0.0:
			vr = (ch.vel - field.gas_v(ch.pos, 0.0)).length() / maxf(field.v_ref(), 1.0)
		for cell: Cell in ch.cells:
			cell.heat = maxf(cell.heat - cell.heat * cool * 0.15 * delta, 0.0)
			if at > 0.0:
				cell.heat = minf(cell.heat + HEAT_K * at * vr * vr * vr * delta * src.L0 / maxf(cell.size, 0.5) * 0.25, 1.4)
		_trail(ch, at, vr, delta)
		if at > 0.3 and vr > 0.25:
			# Обгорает: самая горячая ячейка тает пылью с конечной скоростью.
			var hot: Cell = null
			for cell: Cell in ch.cells:
				if cell.heat > 1.0 and (hot == null or cell.heat > hot.heat):
					hot = cell
			if hot != null and _rng.randf() < delta * 6.0:
				_pulverize(ch, hot, 1.0)
				if ch.dead:
					continue
		var gone := ch.age > LIFE or field.lost(ch.pos)
		if field.sunk(ch.pos, ch.rad) or gone:
			_sink_chunk(ch, gone)


## Следы куска по веществу: лёд на свету парит (струйка от звезды, потом
## её сносит прочь), раскалённое в атмосфере дымит — углерод сажей, лава и
## камень дымком. Пар и дым — без массы, только вид.
func _trail(ch: Chunk, at: float, vr: float, delta: float) -> void:
	var src: Source = ch.src
	var heat := 0.0
	for cell: Cell in ch.cells:
		heat = maxf(heat, cell.heat)
	var big := clampf(ch.size / maxf(src.L0, 0.1) * 2.0, 0.25, 1.0)
	var vap := float(src.mat.get("vapor", 0.0)) * (clampf(field.shade(ch.pos) * 1.4 - 0.3, 0.0, 1.0) * 0.6 + heat * 2.0)
	# Дымит то, что горит: накал куска или ударная волна перед ним.
	var soot := float(src.mat.get("soot", 0.0)) * clampf(maxf(heat * 1.6 - 0.4, at * vr * 2.0), 0.0, 1.0) * minf(at * 4.0, 1.0)
	var rate := (vap * 9.0 + soot * 14.0) * big
	if rate < 0.05:
		return
	var tleft: float = _vap_t.get(ch, 0.0) - delta
	if tleft > 0.0:
		_vap_t[ch] = tleft
		return
	_vap_t[ch] = 1.0 / rate * _rng.randf_range(0.6, 1.4)
	var L := field.light_dir(ch.pos)
	if vap >= soot:
		# Пар: со стороны звезды, тонкой струйкой; давление света и
		# испарения сносит его прочь от звезды.
		var c: Color = src.mat.get("dust_col", Color(0.85, 0.9, 1.0)).lerp(Color(0.92, 0.95, 1.0), 0.6)
		c.a = clampf(0.13 + 0.18 * vap, 0.0, 0.38)
		var off := L.rotated(_rng.randf_range(-0.6, 0.6)) * ch.rad * 0.8
		_add_haze(ch.pos + off, ch.vel + off.normalized() * src.L0 * 0.9, ch.rad * 0.08, ch.rad * 0.55, _rng.randf_range(1.2, 2.0), c, -L * src.L0 * 0.7)
	else:
		# Дым: срывается с хвоста, газ уносит его назад.
		var vrel := ch.vel - field.gas_v(ch.pos, 0.0)
		var back := -vrel.normalized() if vrel.length_squared() > 1e-4 else -ch.pos.normalized()
		var c: Color = Color(0.08, 0.065, 0.055) if float(src.mat.get("soot", 0.0)) > 0.7 else Color(0.32, 0.27, 0.23)
		c.a = clampf(0.3 + 0.35 * soot, 0.0, 0.6)
		_add_haze(ch.pos + back * ch.rad * 0.8, field.gas_v(ch.pos, 0.0) + vrel * 0.35, ch.rad * 0.5, ch.rad * 2.5, _rng.randf_range(1.2, 2.2), c, Vector2.ZERO)


func _add_haze(p: Vector2, v: Vector2, size: float, grow: float, life: float, col: Color, push: Vector2) -> void:
	if hz.size() >= MAX_HAZE:
		hz.pop_front()
	hz.append([p, v, 0.0, life, maxf(size, 0.3), grow, col, push])


func _step_haze(delta: float) -> void:
	if hz.is_empty():
		return
	var keep: Array = []
	for h: Array in hz:
		var t: float = h[2] + delta
		if t >= float(h[3]):
			continue
		var p: Vector2 = h[0]
		if field.sunk(p, 0.0):
			continue
		var v: Vector2 = h[1]
		# Дымка — газ: быстро сходится со скоростью газа, плюс свой снос.
		var vg := field.gas_v(p, 0.0)
		v = vg + (v - vg) * exp(-delta / 0.8) + (h[7] as Vector2) * delta
		h[0] = p + v * delta
		h[1] = v
		h[2] = t
		keep.append(h)
	hz = keep


func _sink_chunk(ch: Chunk, quiet: bool) -> void:
	if ch.dead:
		return
	ch.dead = true
	var src: Source = ch.src
	_pay(src, ch.m, true, ch.pos, 0.0 if quiet else ch.size)
	if not src.hit and not quiet:
		src.hit = true
		if src.notify.is_valid():
			src.notify.call("hit", src)
	_n_cells -= ch.cells.size()
	src.refs -= ch.cells.size()


func _pay(src: Source, m: float, chunk: bool, at: Vector2, size: float) -> void:
	m = minf(m, src.left)
	if m <= 0.0:
		return
	src.left -= m
	if src.sink.is_valid():
		src.sink.call(m, chunk, at, size, src)


func _add_grain(src: Source, p: Vector2, v: Vector2, m: float, size: float, heat: float) -> void:
	var i: int
	if not _free_g.is_empty():
		i = _free_g[_free_g.size() - 1]
		_free_g.resize(_free_g.size() - 1)
	elif gm.size() < MAX_GRAINS:
		i = gm.size()
		gx.append(0.0); gy.append(0.0); gvx.append(0.0); gvy.append(0.0)
		gm.append(0.0); gs.append(0.0); gh.append(0.0); gk.append(0.0); gt.append(0.0)
		gsrc.append(null)
	else:
		# Пыли и так полно: эта сразу уходит в мир.
		_pay(src, m, false, p, 0.0)
		return
	gx[i] = p.x
	gy[i] = p.y
	gvx[i] = v.x
	gvy[i] = v.y
	gm[i] = m
	gs[i] = maxf(size, 0.3)
	gh[i] = heat
	gk[i] = _rng.randf_range(0.6, 1.5)
	gt[i] = 0.0
	gsrc[i] = src
	src.refs += 1


func _kill_grain(i: int) -> void:
	var src: Source = gsrc[i]
	if src != null:
		src.refs -= 1
	gm[i] = -1.0
	gsrc[i] = null
	_free_g.append(i)


## Выброс пыли и брызг из точки (удар о поверхность): каждая пылинка летит
## по своей дуге под тяготением поля и падает обратно или ложится в диск.
func spray(src: Source, at: Vector2, dir: Vector2, count: int, mass: float, v0: float, spread: float, heat: float, size: float) -> void:
	for i in count:
		var d := dir.rotated(_rng.randfn(0.0, spread))
		_add_grain(src, at, d * v0 * _rng.randf_range(0.35, 1.0), mass / count, size * _rng.randf_range(0.5, 1.4), heat * _rng.randf_range(0.6, 1.0))


func _step_grains(delta: float) -> void:
	# Пыль — один шаг на кадр (торможение газом решено точно, через exp).
	var steps := maxi(1, ceili(delta / (1.0 / 30.0)))
	var dt := delta / steps
	for i in gm.size():
		if gm[i] < 0.0:
			continue
		var src: Source = gsrc[i]
		var p := Vector2(gx[i], gy[i])
		var v := Vector2(gvx[i], gvy[i])
		var ts0 := TS_GRAIN * gk[i] * gs[i] / maxf(src.L0 * 0.1, 0.1) * float(src.mat["rho"])
		var inflow := src.inflow * (1.0 + maxf(gt[i] - 4.0, 0.0) * 0.4) * gk[i]
		for s in steps:
			var a := field.accel(p, v)
			var vg := field.gas_v(p, inflow)
			var ts := ts0 / maxf(field.gas_rho(p), 0.02)
			v += a * dt
			v = vg + (v - vg) * exp(-dt / maxf(ts, 0.004))
			p += v * dt
		gt[i] += delta
		# Остывает: мелочь быстрее. В атмосфере — вспыхивает метеором.
		var at := field.atm(p)
		gh[i] = maxf(gh[i] - delta * (0.5 + 1.5 / maxf(gs[i], 0.5)) * gh[i] * 0.4, 0.0)
		if at > 0.0:
			gh[i] = maxf(gh[i], at * 0.5)
		if field.sunk(p, 0.0) or gt[i] > GRAIN_LIFE:
			_pay(src, gm[i], false, p, 0.0)
			_kill_grain(i)
			continue
		gx[i] = p.x
		gy[i] = p.y
		gvx[i] = v.x
		gvy[i] = v.y


func _cleanup() -> void:
	var keep: Array = []
	for ch: Chunk in chunks:
		if not ch.dead:
			keep.append(ch)
	chunks = keep
	if not _vap_t.is_empty():
		for k in _vap_t.keys():
			if (k as Chunk).dead:
				_vap_t.erase(k)
	var ks: Array = []
	for src: Source in sources:
		src.t += get_process_delta_time()
		if src.refs <= 0:
			if src.left > 1e-9 and src.sink.is_valid():
				src.sink.call(src.left, false, Vector2.ZERO, 0.0, src)
			src.left = 0.0
			if src.vp != null and is_instance_valid(src.vp):
				src.vp.queue_free()
				src.vp = null
			if src.notify.is_valid():
				src.notify.call("done", src)
		else:
			ks.append(src)
	sources = ks


func busy() -> bool:
	return not chunks.is_empty()


func grain_count() -> int:
	return gm.size() - _free_g.size()


# ---------------------------------------------------------------------------
# Рисование

## Цвет накала по температуре: тёмно-красный → оранжевый → жёлтый.
## Дымка: мягкие пятна (веер треугольников, к краю прозрачные), одним вызовом.
func _draw_haze(px: float) -> void:
	if hz.is_empty():
		return
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	const SEG := 9
	for h: Array in hz:
		var k: float = float(h[2]) / float(h[3])
		var r := maxf(float(h[4]) + float(h[5]) * sqrt(k), 1.5 * px)
		var c: Color = h[6]
		var p: Vector2 = h[0]
		var sh := field.shade(p)
		var cc := Color(c.r * (0.35 + 0.65 * sh), c.g * (0.35 + 0.65 * sh), c.b * (0.35 + 0.65 * sh), c.a * (1.0 - k) * minf(k * 8.0 + 0.2, 1.0))
		var edge := cc
		edge.a = 0.0
		var i0 := pts.size()
		pts.append(p)
		cols.append(cc)
		for j in SEG:
			pts.append(p + Vector2.from_angle(TAU * j / SEG) * r)
			cols.append(edge)
		for j in SEG:
			idx.append_array([i0, i0 + 1 + j, i0 + 1 + (j + 1) % SEG])
	RenderingServer.canvas_item_add_triangle_array(_dust.get_canvas_item(), idx, pts, cols)


## Болид: раскалённый кусок в атмосфере тянет за собой светящийся след
## (сжатый и нагретый газ перед ним), узкий и короткий, цвета накала.
func _draw_bolides(px: float) -> void:
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for ch: Chunk in chunks:
		if ch.dead:
			continue
		var at := field.atm(ch.pos)
		if at < 0.05:
			continue
		var heat := 0.0
		for cell: Cell in ch.cells:
			heat = maxf(heat, cell.heat)
		var vrel := ch.vel - field.gas_v(ch.pos, 0.0)
		var sp := vrel.length()
		# Светится сжатый ударной волной газ перед куском: ярче — быстрее и глубже.
		var shock := at * clampf(sp / maxf(field.v_ref(), 1.0) * 1.5, 0.0, 1.0)
		heat = maxf(heat, 0.45 + shock)
		if shock < 0.08 or sp < 1e-3:
			continue
		var back := -vrel / sp
		var len := ch.rad * (2.0 + 7.0 * clampf(heat - 0.5, 0.0, 1.0)) * clampf(sp / maxf(field.v_ref(), 1.0) * 2.0, 0.4, 1.6)
		var w := maxf(ch.rad * 0.7, 1.2 * px)
		var side := back.orthogonal()
		var c := glow_col(heat)
		c.a = clampf(shock * 2.0, 0.0, 0.8)
		var tail := c
		tail.a = 0.0
		var i0 := pts.size()
		pts.append_array([ch.pos + side * w, ch.pos - side * w, ch.pos + back * len])
		cols.append_array([c, c, tail])
		idx.append_array([i0, i0 + 1, i0 + 2])
	if not idx.is_empty():
		RenderingServer.canvas_item_add_triangle_array(_dust.get_canvas_item(), idx, pts, cols)


static func glow_col(h: float) -> Color:
	var a := Color(0.55, 0.06, 0.02)
	var b := Color(1.0, 0.42, 0.08)
	var c := Color(1.0, 0.86, 0.55)
	if h < 0.6:
		return a.lerp(b, h / 0.6)
	return b.lerp(c, clampf((h - 0.6) / 0.6, 0.0, 1.0))


func _draw() -> void:
	if chunks.is_empty():
		return
	var ci := get_canvas_item()
	var zoom := 1.0
	var vp := get_viewport()
	if vp != null:
		var cam := vp.get_camera_2d()
		if cam != null:
			zoom = maxf(cam.zoom.x, 0.0001)
	var px := 1.0 / zoom
	var no_uv := PackedVector2Array()
	for ch: Chunk in chunks:
		if ch.dead:
			continue
		var src: Source = ch.src
		var cs := cos(ch.ang)
		var sn := sin(ch.ang)
		var shade := field.shade(ch.pos)
		var L := field.light_dir(ch.pos)
		var inner: Color = src.mat["inner"]
		# Тонет в облаках: тает у самой кромки.
		var fade := 1.0
		var rim_pts := PackedVector2Array()
		var rim_cols := PackedColorArray()
		var rim_idx := PackedInt32Array()
		for cell: Cell in ch.cells:
			var cc: Vector2 = ch.pos + Vector2(cell.c.x * cs - cell.c.y * sn, cell.c.x * sn + cell.c.y * cs)
			var n: int = cell.poly.size()
			var pts := PackedVector2Array()
			pts.resize(n)
			for k in n:
				var v: Vector2 = cell.poly[k]
				pts[k] = cc + Vector2(v.x * cs - v.y * sn, v.x * sn + v.y * cs)
			var heat: float = cell.heat
			var cols := PackedColorArray()
			cols.resize(n)
			if src.tex != null:
				cols.fill(Color(shade * cell.tone, clampf(heat, 0.0, 1.0), 0.0, fade))
				RenderingServer.canvas_item_add_triangle_array(ci, cell.tri, pts, cols, cell.uv, PackedInt32Array(), PackedFloat32Array(), src.tex.get_rid())
			else:
				var base: Color = src.col * cell.tone
				for k in n:
					var lk := 0.55 + 0.6 * maxf(cell.poly[k].normalized().rotated(ch.ang).dot(L), 0.0)
					var cl := (base * lk * shade).lerp(glow_col(heat), clampf(heat, 0.0, 1.0) * 0.8)
					cl.a = fade
					cols[k] = cl
				if no_uv.size() < n:
					no_uv.resize(n)
					no_uv.fill(Vector2(-1.0, -1.0))
				var uvs := no_uv.slice(0, n)
				RenderingServer.canvas_item_add_triangle_array(ci, cell.tri, pts, cols, uvs)
			# Изломы: свежая грань скола, освещённая со стороны звезды, —
			# полоска вдоль ребра внутрь ячейки. Трещина внутри ещё целого
			# куска — тёмная линия, раскрывается со временем.
			var rw := clampf(cell.size * 0.14, 0.9 * px, 3.5 * px)
			for k in n:
				if cell.kind[k] == 0:
					continue
				var bd = cell.bond[k]
				var exposed: bool = bd == null or (bd as Bond).a.chunk != (bd as Bond).b.chunk \
					or (bd as Bond).a.chunk == null or (bd as Bond).b.chunk == null or (bd as Bond).a.chunk.dead or (bd as Bond).b.chunk.dead
				var p0 := pts[k]
				var p1 := pts[(k + 1) % n]
				if not exposed:
					if (bd as Bond).broken:
						var cw := (0.5 + 1.2 * (bd as Bond).crack) * px
						var ccol := Color(0.03, 0.025, 0.02, 0.85 * fade)
						if heat > 0.45:
							ccol = glow_col(heat).lerp(ccol, 0.3)
							ccol.a = fade
						draw_line(p0, p1, ccol, cw)
					continue
				var e := p1 - p0
				if e.length_squared() < 1e-6:
					continue
				var nrm := Vector2(e.y, -e.x).normalized()
				if nrm.dot(p0 - cc) < 0.0:
					nrm = -nrm
				var lit := 0.32 + 0.85 * maxf(nrm.dot(L), 0.0)
				var col := (inner * lit * maxf(shade, 0.12)).lerp(glow_col(heat), clampf(heat * 1.1, 0.0, 1.0) * 0.9)
				col.a = fade
				var i0 := rim_pts.size()
				var q0 := p0 + (cc - p0).normalized() * minf(rw, p0.distance_to(cc) * 0.4)
				var q1 := p1 + (cc - p1).normalized() * minf(rw, p1.distance_to(cc) * 0.4)
				rim_pts.append_array([p0, p1, q1, q0])
				var dim := col.darkened(0.25)
				dim.a = 0.0
				rim_cols.append_array([col, col, dim.lerp(col, 0.4), dim.lerp(col, 0.4)])
				rim_idx.append_array([i0, i0 + 1, i0 + 2, i0, i0 + 2, i0 + 3])
		if not rim_idx.is_empty():
			var uvs := PackedVector2Array()
			uvs.resize(rim_pts.size())
			uvs.fill(Vector2(-1.0, -1.0))
			RenderingServer.canvas_item_add_triangle_array(ci, rim_idx, rim_pts, rim_cols, uvs)


func _draw_dust() -> void:
	var zoom := 1.0
	var vp := get_viewport()
	if vp != null and vp.get_camera_2d() != null:
		zoom = maxf(vp.get_camera_2d().zoom.x, 0.0001)
	var px := 1.0 / zoom
	_draw_haze(px)
	_draw_bolides(px)
	if gm.is_empty():
		return
	for i in gm.size():
		if gm[i] < 0.0:
			continue
		var src: Source = gsrc[i]
		var p := Vector2(gx[i], gy[i])
		var s := maxf(gs[i], 1.1 * px)
		var h := gh[i]
		var col: Color = src.col * field.shade(p)
		col = col.lerp(glow_col(h), clampf(h * 1.2, 0.0, 1.0))
		col.a = clampf(0.55 + 0.35 * gs[i] / maxf(2.0 * px, 0.01), 0.3, 0.95) * smoothstep(0.0, 0.15, gt[i] + 0.15)
		_dust.draw_rect(Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)), col)
