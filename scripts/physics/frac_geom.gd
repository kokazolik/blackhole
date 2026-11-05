class_name FracGeom
extends RefCounted
## Геометрия движка разрушения: контур тела, ячейки Вороного с рваными
## гранями, площадь, центр масс, момент инерции.
##
## Ячейка хранится многоугольником, у каждого ребра — метка: −1 — внешняя
## поверхность тела, иначе номер соседней ячейки (по этому ребру они
## сцеплены). Рваная грань строится одинаково для обеих соседних ячеек
## (смещения зависят только от пары номеров и концов ребра), поэтому куски
## точно прилегают друг к другу и после раскола расходятся по общему излому.


## Неровный контур тела радиуса rad: n вершин, бугры по шуму.
static func outline(rad: float, n: int, rough: float, rng: RandomNumberGenerator) -> PackedVector2Array:
	var out := PackedVector2Array()
	var ph1 := rng.randf() * TAU
	var ph2 := rng.randf() * TAU
	for k in n:
		var a := TAU * float(k) / n
		var r := 1.0 + rough * (0.55 * sin(2.0 * a + ph1) + 0.3 * sin(5.0 * a + ph2) + 0.25 * rng.randf_range(-1.0, 1.0))
		out.append(Vector2.from_angle(a) * rad * r)
	return out


## Отсечение полуплоскостью (x − m)·d ≤ 0 с сохранением меток рёбер.
## tags[k] — метка ребра poly[k] → poly[k+1]; новое ребро по линии среза
## получает метку tag.
static func clip(poly: PackedVector2Array, tags: PackedInt32Array, m: Vector2, d: Vector2, tag: int) -> Array:
	var out := PackedVector2Array()
	var ot := PackedInt32Array()
	var n := poly.size()
	for k in n:
		var a := poly[k]
		var b := poly[(k + 1) % n]
		var sa := (a - m).dot(d)
		var sb := (b - m).dot(d)
		var ina := sa <= 0.0
		var inb := sb <= 0.0
		if ina:
			out.append(a)
			ot.append(tags[k])
			if not inb:
				out.append(a + (b - a) * (sa / (sa - sb)))
				ot.append(tag)
		elif inb:
			out.append(a + (b - a) * (sa / (sa - sb)))
			ot.append(tags[k])
	return [out, ot]


## Ячейки Вороного внутри контура shape по зёрнам seeds. Возвращает массив
## [многоугольник, метки рёбер] на каждое зерно (пустой — если ячейка
## выродилась).
static func voronoi(shape: PackedVector2Array, shape_tags: PackedInt32Array, seeds: PackedVector2Array) -> Array:
	var cells := []
	for i in seeds.size():
		var poly := shape
		var tags := shape_tags
		for j in seeds.size():
			if i == j:
				continue
			var mid := (seeds[i] + seeds[j]) * 0.5
			var d := seeds[j] - seeds[i]
			if d.length_squared() < 1e-8:
				continue
			var r: Array = clip(poly, tags, mid, d, j)
			poly = r[0]
			tags = r[1]
			if poly.size() < 3:
				break
		cells.append([poly, tags] if poly.size() >= 3 else [])
	return cells


## Рваный излом: внутренние рёбра (метка ≥ 0) ломаются на несколько
## отрезков со смещением поперёк. Смещение зависит от пары ячеек и концов
## ребра, поэтому у соседа излом выходит тем же, только в обратном порядке.
static func jag(poly: PackedVector2Array, tags: PackedInt32Array, self_id: int, amp: float, seed_v: int) -> Array:
	var out := PackedVector2Array()
	var ot := PackedInt32Array()
	var n := poly.size()
	for k in n:
		var a := poly[k]
		var b := poly[(k + 1) % n]
		var t := tags[k]
		out.append(a)
		ot.append(t)
		if t < 0:
			continue
		var len := a.distance_to(b)
		if len < amp * 2.5:
			continue
		# Канонический порядок концов: у обоих соседей одинаковый.
		var flip := a.x > b.x or (is_equal_approx(a.x, b.x) and a.y > b.y)
		var p0 := b if flip else a
		var p1 := a if flip else b
		var nrm := (p1 - p0).orthogonal() / len
		var lo := mini(t, self_id)
		var hi := maxi(t, self_id)
		var segs := clampi(int(len / (amp * 2.2)), 2, 4)
		var pts := PackedVector2Array()
		for s in range(1, segs):
			var u := float(s) / segs
			var h := _hash(lo * 7919 + hi * 104729 + s * 31 + seed_v)
			var off := (h * 2.0 - 1.0) * amp * minf(1.0, len / (amp * 5.0))
			pts.append(p0.lerp(p1, u + (_hash(lo * 131 + hi * 17 + s + seed_v) - 0.5) * 0.25 / segs) + nrm * off)
		if flip:
			pts.reverse()
		for p in pts:
			out.append(p)
			ot.append(t)
	return [out, ot]


static func _hash(i: int) -> float:
	var x := (i * 374761393 + 668265263) & 0x7fffffff
	x = ((x ^ (x >> 13)) * 1274126177) & 0x7fffffff
	return float(x & 0xffff) / 65535.0


static func area(poly: PackedVector2Array) -> float:
	var s := 0.0
	var n := poly.size()
	for k in n:
		s += poly[k].cross(poly[(k + 1) % n])
	return absf(s) * 0.5


static func centroid(poly: PackedVector2Array) -> Vector2:
	var a := 0.0
	var c := Vector2.ZERO
	var n := poly.size()
	for k in n:
		var p := poly[k]
		var q := poly[(k + 1) % n]
		var cr := p.cross(q)
		a += cr
		c += (p + q) * cr
	if absf(a) < 1e-9:
		var s := Vector2.ZERO
		for p in poly:
			s += p
		return s / maxf(n, 1)
	return c / (3.0 * a)


## Полярный момент многоугольника на единицу массы (относительно его центра,
## вершины уже от центра).
static func inertia_k(poly: PackedVector2Array) -> float:
	var num := 0.0
	var den := 0.0
	var n := poly.size()
	for k in n:
		var p := poly[k]
		var q := poly[(k + 1) % n]
		var cr := absf(p.cross(q))
		num += cr * (p.dot(p) + p.dot(q) + q.dot(q))
		den += cr
	return num / maxf(6.0 * den, 1e-9)


## Самая дальняя вершина от центра.
static func reach(poly: PackedVector2Array) -> float:
	var r := 0.0
	for p in poly:
		r = maxf(r, p.length_squared())
	return sqrt(r)


## Зёрна для приливного раскола: тело рвётся поперёк линии на гиганта,
## поэтому зёрна гуще вдоль этой оси — выходят плиты, а не крошка.
static func seeds_tidal(n: int, rad: float, axis: Vector2, rng: RandomNumberGenerator) -> PackedVector2Array:
	var out := PackedVector2Array()
	var tries := 0
	while out.size() < n and tries < n * 40:
		tries += 1
		var p := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
		if p.length_squared() > 0.92:
			continue
		# Поперёк оси зёрна реже: ячейки вытянуты поперёк, раскол — плитами.
		var q := axis * p.dot(axis) + axis.orthogonal() * p.dot(axis.orthogonal()) * 0.85
		var ok := true
		var min_d := rad * 1.25 / sqrt(float(n))
		for s in out:
			if s.distance_to(q * rad) < min_d:
				ok = false
				break
		if ok:
			out.append(q * rad)
	return out


## Зёрна для удара: гуще у точки удара (там мелкое крошево), к дальнему
## краю реже (там крупные куски).
static func seeds_impact(n: int, rad: float, at: Vector2, rng: RandomNumberGenerator) -> PackedVector2Array:
	var out := PackedVector2Array()
	var tries := 0
	while out.size() < n and tries < n * 40:
		tries += 1
		var p := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * rad
		if p.length_squared() > rad * rad * 0.92:
			continue
		var d := p.distance_to(at) / rad
		if rng.randf() > 1.0 / (0.35 + d * d * 1.6):
			continue
		var min_d := rad * 0.12 * (0.35 + d)
		var ok := true
		for s in out:
			if s.distance_to(p) < min_d:
				ok = false
				break
		if ok:
			out.append(p)
	return out
