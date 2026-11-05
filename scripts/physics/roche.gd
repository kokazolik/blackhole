class_name Roche
extends RefCounted
## Полость Роша жидкого тела рядом с соседом — по-настоящему, в плоскости.
##
## Тело в начале координат, сосед в (1, 0) (расстояние — единица), G(m1+m2) = 1.
## Система отсчёта свободно падает вместе с телом (пролёт, а не тесная пара
## с общим вращением): потенциал Φ = −μ1/r1 − μ2/r2 + μ2·x, последний член —
## сила инерции от ускорения тела к соседу. Поверхность через точку L1 —
## граница, за которой газ уже не держится телом: он перетекает к соседу
## (со стороны соседа) или уходит прочь (с обратной стороны).
##
## Таблица радиусов полости по 64 направлениям считается один раз на каждое
## отношение масс (сетка по логарифму) и берётся из кэша.

const N := 64
const Q_STEP := 0.04          # шаг сетки по log10(q)
static var _cache := {}


## Радиус полости по Эгглтону (доля расстояния), q = m_тела / m_соседа.
static func eggleton(q: float) -> float:
	var q3 := pow(maxf(q, 1e-4), 1.0 / 3.0)
	var q23 := q3 * q3
	return 0.49 * q23 / (0.6 * q23 + log(1.0 + q3))


static func _phi(x: float, y: float, mu1: float, mu2: float) -> float:
	var r1 := sqrt(x * x + y * y)
	var dx := x - 1.0
	var r2 := sqrt(dx * dx + y * y)
	return -mu1 / maxf(r1, 1e-5) - mu2 / maxf(r2, 1e-5) + mu2 * x


## Точка L1 на оси между телами (доля расстояния от тела).
static func l1(q: float) -> float:
	return float(table(q)[N])


## Радиусы полости по направлениям (доля расстояния), индекс 0 — на соседа;
## элемент N — расстояние до L1.
static func table(q: float) -> PackedFloat32Array:
	var key := roundi(clampf(log(maxf(q, 1e-4)) / log(10.0), -4.0, 4.0) / Q_STEP)
	if _cache.has(key):
		return _cache[key]
	var qq := pow(10.0, key * Q_STEP)
	var mu1 := qq / (1.0 + qq)
	var mu2 := 1.0 - mu1
	# L1: dΦ/dx = μ1/x² − μ2/(1−x)² + μ2 = 0 между телами, делением пополам.
	var lo := 1e-4
	var hi := 1.0 - 1e-4
	for i in 60:
		var x := (lo + hi) * 0.5
		var g := mu1 / (x * x) - mu2 / ((1.0 - x) * (1.0 - x)) + mu2
		if g > 0.0:
			lo = x
		else:
			hi = x
	var xl := (lo + hi) * 0.5
	var pl := _phi(xl, 0.0, mu1, mu2)
	var out := PackedFloat32Array()
	out.resize(N + 1)
	for k in N:
		var th := TAU * k / N
		var c := cos(th)
		var s := sin(th)
		# Идём наружу, пока потенциал не дойдёт до уровня L1 (или пока не начнёт
		# падать: с обратной стороны полость может быть открыта).
		var step := xl / 48.0
		var r := step
		var prev := _phi(r * c, r * s, mu1, mu2)
		var found := -1.0
		while r < 1.6:
			var r2 := r + step
			var v := _phi(r2 * c, r2 * s, mu1, mu2)
			if v >= pl:
				# Уточнить делением пополам.
				var a := r
				var b := r2
				for j in 24:
					var m := (a + b) * 0.5
					if _phi(m * c, m * s, mu1, mu2) >= pl:
						b = m
					else:
						a = m
				found = (a + b) * 0.5
				break
			if v < prev:
				found = r
				break
			prev = v
			r = r2
		out[k] = found if found > 0.0 else 1.6
	out[0] = xl
	out[N] = xl
	_cache[key] = out
	return out


## Радиус полости в направлении th (рад, 0 — на соседа), доля расстояния.
static func lobe(t: PackedFloat32Array, th: float) -> float:
	var f := fposmod(th, TAU) / TAU * N
	var i := int(f) % N
	var j := (i + 1) % N
	return lerpf(t[i], t[j], f - floorf(f))
