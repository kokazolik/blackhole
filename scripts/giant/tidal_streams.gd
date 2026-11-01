class_name TidalStreams
extends Node2D
## Приливный разрыв тела у гиганта: как это выглядит.
##
## 1. В миг разрыва тело снимается в текстуру своим же шейдером (кратеры,
##    моря, лёд, облака) — дальше ломается именно оно, а не «нечто».
## 2. По телу бегут трещины (ячейки Вороного с рваными краями), в них светится
##    нутро по составу: расплав у камня, свежий лёд, тлеющий углерод.
## 3. Куски расходятся вдоль орбиты: ближний к гиганту уходит первым, дальний
##    отстаёт — так прилив и растягивает тело (как кометa Шумейкеров — Леви 9).
## 4. Прилив стачивает куски с краёв в пыль. Пыль — лента цвета самого тела,
##    закрученная спиралью прямого вращения к облакам гиганта.
## 5. Каждая пылинка летит сама по Кеплеру: ближние к гиганту быстрее, поэтому
##    нить сама растягивается в дугу вдоль орбиты. Газ околопланетного диска
##    тормозит пыль, и она медленно уходит по спирали (мелочь быстрее, куски
##    отстают). В облаках пыль просто тонет в дымке, без вспышек; кусок
##    покрупнее даёт маленький шлейф и тёмный след, как у кометы в 1994-м.
## 6. В тени гиганта (от звезды за ним) пыль тёмная.
##
## Всё живёт в системе гиганта (узел — его ребёнок), поэтому летит вместе с
## ним и не ломается, как бы игрок ни ехал.

const K := 96                 # точек вдоль ленты
const DIR := -1.0             # прямое вращение: на экране против часовой
const SPLIT := 0.7            # секунд трещины расходятся, прежде чем тело распадётся
const W0 := 0.75              # угловая скорость орбиты у самых облаков, рад/с (∝ r^-1.5)

# Палитры по составу: свет на пыли, ореол, накал, искры, дымка, трещины.
const PALS := {
	"ice": [Color(0.8, 0.9, 1.0), Color(0.45, 0.68, 1.0), Color(0.92, 0.98, 1.0), 1.0, 0.0, Color(0.88, 0.95, 1.0)],
	"rock": [Color(0.86, 0.74, 0.58), Color(0.95, 0.55, 0.28), Color(1.0, 0.72, 0.42), 0.25, 0.0, Color(0.42, 0.38, 0.34)],
	"metal": [Color(0.8, 0.82, 0.86), Color(0.62, 0.7, 1.0), Color(1.0, 0.94, 0.84), 1.3, 0.0, Color(0.62, 0.62, 0.66)],
	"carbon": [Color(0.36, 0.3, 0.26), Color(0.85, 0.32, 0.1), Color(1.0, 0.52, 0.18), 0.2, 0.0, Color(0.06, 0.055, 0.05)],
	"lava": [Color(0.75, 0.38, 0.2), Color(1.0, 0.28, 0.06), Color(1.0, 0.8, 0.4), 0.45, 0.0, Color(1.0, 0.55, 0.12)],
	"nep": [Color(0.55, 0.78, 0.92), Color(0.3, 0.55, 0.95), Color(0.85, 0.95, 1.0), 0.1, 1.0, Color(0.6, 0.85, 1.0)],
	"rival": [Color(0.86, 0.76, 0.6), Color(0.9, 0.6, 0.35), Color(1.0, 0.85, 0.6), 0.15, 0.7, Color(1.0, 0.7, 0.4)],
	"ring": [Color(0.9, 0.94, 1.0), Color(0.55, 0.75, 1.0), Color(1.0, 1.0, 1.0), 1.6, 0.0, Color(0.8, 0.95, 1.0)],
}

var world                     # system_world.gd
var streams: Array = []
var plumes: Array = []        # шлейфы ударов: огненный веер из облаков
var _time := 0.0


## Струя из точки from (в системе гиганта). mode: "spiral" — к облакам по
## спирали, "arc" — выброс при ударе, дугой и обратно.
## opts: T, Ls, turns, span, hgt, snap ({tex, disc, vp}), shards (число), rad, gain_shards.
func spawn(from: Vector2, mode: String, mass: float, pay: float, pal: String, seed_v: float, width: float, opts := {}) -> Dictionary:
	var st := {
		"mode": mode, "r0": from.length(), "th0": from.angle(), "from": from, "mass": mass, "paid": 0.0, "pay": pay,
		"pal": pal if PALS.has(pal) else "rock", "seed": seed_v, "w": width, "t": 0.0,
		"T": float(opts.get("T", 3.6)), "Ls": float(opts.get("Ls", 2.2)),
		"turns": float(opts.get("turns", 1.0)), "span": float(opts.get("span", 0.9)),
		"hgt": float(opts.get("hgt", 300.0)), "spot": 0.0, "shards": [], "node": null,
		"delay": 0.0, "snap": opts.get("snap", {}), "scarred": false, "L0": 0.0,
	}
	if mode == "spiral":
		_init_points(st, float(opts.get("rad", width / 2.6)), world.stage.body.body_r * world.stage.body.inflate)
	var p: Array = PALS[st.pal]
	var node := MeshInstance2D.new()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/tidal_stream.gdshader")
	mat.set_shader_parameter("noise_tex", NoiseTex.get_tex())
	mat.set_shader_parameter("c_tail", p[0])
	mat.set_shader_parameter("c_glow", p[1])
	mat.set_shader_parameter("c_hot", p[2])
	mat.set_shader_parameter("sparkle", p[3])
	mat.set_shader_parameter("haze", p[4])
	mat.set_shader_parameter("seed", fmod(seed_v, 7.0))
	var snap: Dictionary = st.snap
	if not snap.is_empty():
		mat.set_shader_parameter("use_body", true)
		mat.set_shader_parameter("body_tex", snap.tex)
		mat.set_shader_parameter("disc", snap.disc)
	node.material = mat
	node.mesh = ArrayMesh.new()
	add_child(node)
	st.node = node
	var n := int(opts.get("shards", 0))
	if n > 0 and not snap.is_empty():
		st.delay = SPLIT
		_make_shards(st, n, float(opts.get("rad", 20.0)), float(opts.get("gain_shards", 0.0)), p[5])
	streams.append(st)
	return st


## Вещество нити: K пылинок вдоль радиуса (прилив тянет тело к гиганту и
## прочь от него), у каждой своя орбита и своё торможение газом.
func _init_points(st: Dictionary, rad: float, R: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(float(st.seed) * 7919.0) + 3
	var pr := PackedFloat32Array()
	var pt := PackedFloat32Array()
	var pg := PackedFloat32Array()
	var r0: float = st.r0
	# Торможение подобрано так, чтобы пыль ушла в облака за жизнь T + Ls,
	# растянутую в 1,8 раза: обломки кружат, а не сыплются за пару секунд.
	var life := (float(st.T) + float(st.Ls)) * 1.8
	var g0 := log(maxf(r0 - 0.9 * R, 1.0) / (0.1 * R)) / life * 0.55
	for k in K:
		var sk := float(k) / (K - 1)
		pr.append(r0 + (sk - 0.5) * 2.0 * rad * 1.4)
		pt.append(float(st.th0) + rng.randfn(0.0, 0.004))
		# Мелочь у головы тормозится сильнее, у хвоста — слабее.
		pg.append(g0 * (0.75 + 0.5 * rng.randf()) * (1.2 - 0.4 * sk))
	st["pr"] = pr
	st["pt"] = pt
	st["pg"] = pg
	st["g0"] = g0
	st["R0"] = R


## Пылинка или кусок на орбите: Кеплер плюс торможение газом диска (сильнее
## глубже, где газ плотнее). Возвращает новые r, θ.
static func _orbit_step(r: float, th: float, g: float, R: float, delta: float) -> Vector2:
	var gg := g * pow(R / maxf(r, R * 0.5), 2.0)
	r -= (r - 0.9 * R) * gg * delta
	th += DIR * W0 * pow(maxf(r, R * 0.5) / R, -1.5) * delta
	return Vector2(r, th)


## Шлейф удара в точке at (система гиганта, на облаках), высотой hgt.
func plume(at: Vector2, hgt: float, smoke: Color, seed_v: float, life := 3.2) -> void:
	var node := ColorRect.new()
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.size = Vector2(hgt * 1.6, hgt)
	node.pivot_offset = Vector2(hgt * 0.8, hgt)
	node.position = at - node.pivot_offset
	node.rotation = at.angle() + PI * 0.5
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/impact_plume.gdshader")
	m.set_shader_parameter("noise_tex", NoiseTex.get_tex())
	m.set_shader_parameter("smoke", smoke)
	m.set_shader_parameter("seed", fmod(seed_v, 5.0))
	node.material = m
	add_child(node)
	plumes.append({"node": node, "t": 0.0, "life": life})


## Куски тела: ячейки Вороного по снимку. Порядок вдоль нити — по оси на гиганта.
func _make_shards(st: Dictionary, n: int, rad: float, gain: float, crack: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(float(st.seed) * 1000.0)
	var seeds := PackedVector2Array()
	for i in n:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 0.85
		seeds.append(Vector2.from_angle(a) * r)
	var snap: Dictionary = st.snap
	var disc: float = snap.disc
	var to_g: Vector2 = -(st.from as Vector2).normalized()   # к гиганту, в его системе
	var wr := rad / disc
	for i in n:
		var c := seeds[i]
		var rect := ColorRect.new()
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.size = Vector2(wr, wr)
		rect.pivot_offset = (Vector2(0.5, 0.5) + c * disc) * wr
		var m := ShaderMaterial.new()
		m.shader = preload("res://shaders/shard.gdshader")
		m.set_shader_parameter("body_tex", snap.tex)
		m.set_shader_parameter("noise_tex", NoiseTex.get_tex())
		m.set_shader_parameter("seeds", seeds)
		m.set_shader_parameter("n", n)
		m.set_shader_parameter("cell", i)
		m.set_shader_parameter("disc", disc)
		m.set_shader_parameter("crack_col", crack)
		m.set_shader_parameter("emit", 1.0 if st.pal == "lava" else 0.0)
		m.set_shader_parameter("seed", fmod(float(st.seed), 5.0))
		rect.material = m
		rect.visible = false
		add_child(rect)
		(st.shards as Array).append({"node": rect, "c": c, "spin": rng.randf_range(-0.35, 0.35), "k": rng.randf(),
			"gain": gain / n, "done": false, "s": 0.0, "side": 0.0})
	# Где кусок в нити: ближний к гиганту — голова.
	var ang: float = world.stage.ang
	for sh in st.shards:
		var cl: Vector2 = (sh.c as Vector2).rotated(-ang)   # из системы экрана в систему гиганта
		sh.s = clampf(0.5 - cl.dot(to_g) * 0.55, 0.02, 0.95)
		sh.side = cl.dot(to_g.orthogonal())
		if st.mode == "spiral":
			# Кусок — на своей орбите; крупному газ почти не мешает: он отстаёт от пыли.
			sh["r"] = float(st.r0) + (float(sh.s) - 0.5) * 2.0 * rad * 1.4
			sh["th"] = float(st.th0) + float(sh.side) * rad / maxf(float(st.r0), 1.0) * 0.6
			sh["g"] = float(st.g0) * 0.5 * (0.8 + 0.4 * float(sh.k))
	st["rad"] = rad


func _ease(st: Dictionary, x: float) -> float:
	return pow(x, 1.3) if st.mode == "spiral" else x


func _x(st: Dictionary, s: float) -> float:
	return (float(st.t) - float(st.delay) - s * float(st.Ls)) / float(st.T)


## Где частичка s сейчас: доля пути u (у хвоста в первые мгновения чуть меньше
## нуля: тело ещё вытягивается и только трогается).
func _u(st: Dictionary, s: float) -> float:
	var x := clampf(_x(st, s), 0.0, 1.0)
	return _ease(st, x) - 0.08 * s * (1.0 - x)


func _path(st: Dictionary, u: float, R: float) -> Vector2:
	if st.mode == "arc":
		var uu := clampf(u, -0.2, 1.0)
		var r := R * 0.92 + float(st.hgt) * sin(PI * clampf(uu, 0.0, 1.0)) + R * 0.08 * clampf(-uu * 5.0, 0.0, 1.0)
		return Vector2.from_angle(float(st.th0) + DIR * float(st.span) * uu) * r
	var rend := R * 0.9
	var r0: float = st.r0
	var r2 := rend + (r0 - rend) * pow(maxf(1.0 - u, 0.0), 1.2)
	if u < 0.0:
		r2 = r0 - (r0 - rend) * 1.2 * u
	var th := float(st.th0) + DIR * TAU * float(st.turns) * u
	# Орбита не идеальный круг: чуть вытянута, как у настоящих обломков.
	r2 *= 1.0 + 0.07 * sin(2.0 * th + float(st.seed)) * (1.0 - clampf(u, 0.0, 1.0))
	return Vector2.from_angle(th) * r2


func step(delta: float, R: float) -> void:
	_time += delta
	var pk := []
	for pl in plumes:
		pl.t = float(pl.t) + delta
		var k := float(pl.t) / float(pl.life)
		if k >= 1.0:
			(pl.node as Node).queue_free()
			continue
		((pl.node as ColorRect).material as ShaderMaterial).set_shader_parameter("t", k)
		pk.append(pl)
	plumes = pk
	var keep := []
	for st in streams:
		st.t = float(st.t) + delta
		if st.mode == "spiral":
			if _step_spiral(st, delta, R):
				keep.append(st)
			else:
				_free(st)
			continue
		var tt := float(st.t) - float(st.delay)
		var drained := clampf((tt - float(st.T)) / float(st.Ls), 0.0, 1.0)
		var add: float = float(st.mass) * drained - float(st.paid)
		if add > 0.0:
			st.paid = float(st.paid) + add
			world.stage.earths += add
			world.stage.pay(add * float(st.pay))
		for sh in st.shards:
			if not sh.done and _x(st, float(sh.s)) >= 1.0:
				sh.done = true
				(sh.node as CanvasItem).visible = false
				_shard_hit(st, sh, R)
		if tt < float(st.T) + float(st.Ls) + 0.5:
			keep.append(st)
		else:
			_free(st)
	streams = keep
	for st in streams:
		_build(st, R)
		_place_shards(st, R)


func _free(st: Dictionary) -> void:
	(st.node as Node).queue_free()
	for sh in st.shards:
		(sh.node as Node).queue_free()
	var snap: Dictionary = st.snap
	if snap.has("vp"):
		(snap.vp as Node).queue_free()


## Спираль: каждая пылинка и каждый кусок по своей орбите. Пыль, дошедшая до
## облаков, просто тонет в дымке (масса засчитывается по доле утонувшего).
func _step_spiral(st: Dictionary, delta: float, R: float) -> bool:
	var pr: PackedFloat32Array = st.pr
	var pt: PackedFloat32Array = st.pt
	var pg: PackedFloat32Array = st.pg
	var dead := 0
	var moving := (st.shards as Array).is_empty() or float(st.t) > SPLIT * 0.6
	for k in K:
		if pr[k] <= R:
			dead += 1
			continue
		if not moving:
			continue
		var v := _orbit_step(pr[k], pt[k], pg[k], R, delta)
		pr[k] = v.x
		pt[k] = v.y
	st.pr = pr
	st.pt = pt
	var frac := float(dead) / K
	var add: float = float(st.mass) * frac - float(st.paid)
	if add > 0.0:
		st.paid = float(st.paid) + add
		world.stage.earths += add
		world.stage.pay(add * float(st.pay))
	# Пыль оседает в облаках: тёмная дымка на месте, где ушла голова нити.
	if dead > K / 3 and not st.scarred:
		st.scarred = true
		world.stage.body.scar(Vector2.from_angle(pt[0]), float(st.w) * 0.2)
	var left := 0
	for sh in st.shards:
		if sh.done:
			continue
		if float(st.t) > SPLIT * 0.6:
			var v := _orbit_step(float(sh.r), float(sh.th), float(sh.g), R, delta)
			sh.r = v.x
			sh.th = v.y
		if float(sh.r) <= R:
			sh.done = true
			(sh.node as CanvasItem).visible = false
			_shard_hit(st, sh, R)
		else:
			left += 1
	return (dead < K or left > 0) and float(st.t) < 90.0


## Доля пути куска от места разрыва до облаков.
func _prog(st: Dictionary, sh: Dictionary) -> float:
	if st.mode != "spiral":
		return clampf(_x(st, float(sh.s)), 0.0, 1.0)
	var R: float = st.R0
	return clampf((float(st.r0) - float(sh.r)) / maxf(float(st.r0) - R, 1.0), 0.0, 1.0)


## Кусок дошёл до облаков. Сточенный в пыль — уже в нити. Уцелевший входит
## в атмосферу на десятках км/с: короткий шлейф над облаками и тёмный след,
## как у осколков кометы Шумейкеров — Леви 9. Шлейф по размеру куска, без
## светящихся шаров.
func _shard_hit(st: Dictionary, sh: Dictionary, R: float) -> void:
	var g: float = sh.gain
	world.stage.earths += g
	world.stage.pay(g * float(st.pay) * Skills.stat("giant_impact"))
	var er := _erode(st, sh)
	if er > 0.95:
		return   # сточился в пыль по дороге: пыль уже в нити
	var at: Vector2 = Vector2.from_angle(float(sh.th)) * R if st.mode == "spiral" else _path(st, 1.0, R)
	var size := float(st.get("rad", 20.0)) * (1.0 - er) * 0.6
	world.stage.body.scar(at.normalized(), size)
	var smoke: Color = (PALS[st.pal] as Array)[0]
	plume(at.normalized() * R * 0.97, clampf(R * 0.05 + size * 1.4, R * 0.05, R * 0.22), smoke.darkened(0.45), float(st.seed) + float(sh.k), 2.4)


func _erode(st: Dictionary, sh: Dictionary) -> float:
	var x := _prog(st, sh)
	return smoothstep(0.05, 0.95, x) * (0.55 + 0.6 * float(sh.k))


## Куски: сначала на своих местах (трещины разгораются), потом вдоль нити.
func _place_shards(st: Dictionary, R: float) -> void:
	if (st.shards as Array).is_empty():
		return
	var t: float = st.t
	var rad: float = st.rad
	var ang: float = world.stage.ang
	var from: Vector2 = st.from
	var crack := smoothstep(0.0, SPLIT, t)
	var go := smoothstep(SPLIT * 0.6, SPLIT + 1.6, t)
	for sh in st.shards:
		var node: ColorRect = sh.node
		if sh.done:
			continue
		node.visible = t > 0.05      # снимок готов со второго кадра
		var c: Vector2 = sh.c
		var cl := c.rotated(-ang) * rad
		# Трещины расходятся: куски чуть раздвигаются ещё на месте.
		var home := from + cl * (1.0 + 0.06 * crack)
		var on: Vector2
		var u := 0.0
		if st.mode == "spiral":
			on = Vector2.from_angle(float(sh.th)) * float(sh.r)
		else:
			u = _u(st, float(sh.s))
			on = _path(st, u, R)
			var tg := (_path(st, u + 0.004, R) - _path(st, u - 0.004, R)).normalized()
			on += tg.orthogonal() * float(sh.side) * rad * 0.7
		var p := home.lerp(on, go)
		node.position = p - node.pivot_offset
		node.rotation = -ang + float(sh.spin) * maxf(t - SPLIT, 0.0)
		var sc := 1.0 - 0.25 * smoothstep(0.3, 1.0, _prog(st, sh))
		node.scale = Vector2(sc, sc)
		var m := node.material as ShaderMaterial
		m.set_shader_parameter("crack", crack * (1.0 - 0.5 * go))
		m.set_shader_parameter("erode", _erode(st, sh))
		# Тень гиганта: звезда слева (−x), за гигантом справа темно.
		m.set_shader_parameter("shade", _shade(p, R))


## Освещённость точки (система гиганта): 1 — на свету, 0.06 — в тени гиганта.
static func _shade(p: Vector2, R: float) -> float:
	if p.x <= 0.0:
		return 1.0
	return lerpf(1.0, 0.06, smoothstep(R * 1.04, R * 0.9, absf(p.y)) * smoothstep(0.0, R * 0.3, p.x))


## Лента: K точек по веществу, ширина — колокол, со временем расплывается.
func _build(st: Dictionary, R: float) -> void:
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	verts.resize(K * 2)
	uvs.resize(K * 2)
	cols.resize(K * 2)
	var W: float = st.w
	var tt := float(st.t) - float(st.delay)
	var spiral: bool = st.mode == "spiral"
	# Пыль появляется, когда тело начало сыпаться.
	var fade_in := smoothstep(-0.2, 0.9, tt) if not (st.shards as Array).is_empty() else smoothstep(0.0, 0.35, tt)
	var life := (float(st.T) + float(st.Ls)) * (1.8 if spiral else 1.0)
	var spread := clampf(tt / life, 0.0, 1.0)
	# Точки нити.
	var pts := PackedVector2Array()
	pts.resize(K)
	var sink := PackedFloat32Array()
	sink.resize(K)
	var prog := PackedFloat32Array()
	prog.resize(K)
	var pr: PackedFloat32Array = st.get("pr", PackedFloat32Array())
	var pt: PackedFloat32Array = st.get("pt", PackedFloat32Array())
	for k in K:
		var sk := float(k) / (K - 1)
		if spiral:
			var r := maxf(pr[k], R)
			pts[k] = Vector2.from_angle(pt[k]) * r
			# В облаках пыль тонет в дымке: тает на последних процентах радиуса.
			sink[k] = smoothstep(R * 1.0, R * 1.08, pr[k])
			prog[k] = clampf((float(st.r0) - pr[k]) / maxf(float(st.r0) - R, 1.0), 0.0, 1.0)
		else:
			var u := _u(st, sk)
			pts[k] = _path(st, u, R)
			sink[k] = 1.0 - smoothstep(0.86, 1.0, _x(st, sk))
			prog[k] = clampf(u, 0.0, 1.0)
	var length := 0.0
	for k in range(1, K):
		length += pts[k].distance_to(pts[k - 1])
	if float(st.L0) <= 0.0 and length > 0.0:
		st.L0 = maxf(length, W * 2.0)
	# Вещество одно и то же: растянулась нить вдвое — вдвое тоньше по плотности.
	var thin := clampf(pow(float(st.L0) / maxf(length, 1.0), 0.6), 0.3, 1.0) if spiral else 1.0
	var nrm_prev := Vector2.UP
	for k in K:
		var s := float(k) / (K - 1)
		var p := pts[k]
		var tg := pts[mini(k + 1, K - 1)] - pts[maxi(k - 1, 0)]
		var nrm := tg.normalized().orthogonal() if tg.length() > 0.01 else nrm_prev
		if nrm.dot(nrm_prev) < 0.0 and k > 0:
			nrm = -nrm
		nrm_prev = nrm
		var uc := prog[k]
		# Нить заострена с обоих концов: голова — тонкий язык, хвост тает.
		var prof := 0.08 + 0.92 * pow(sin(PI * clampf(s * 0.94 + 0.03, 0.0, 1.0)), 0.75)
		# Нить узкая: поперёк её держит только разброс скоростей обломков.
		var w: float = W * prof * ((0.55 + 0.25 * spread) if spiral else (1.0 + 0.9 * spread))
		w *= lerpf(1.0, 0.6, uc) if spiral else lerpf(1.0, 0.8, uc)
		var a := fade_in * smoothstep(1.0, 0.75, s) * smoothstep(0.0, 0.07, s) * sink[k] * thin
		# Пыль вне атмосферы холодная. Чуть тлеет только то, что входит в
		# облака (метеоры), а выброс удара остывает на взлёте.
		var heat: float = smoothstep(R * 1.1, R * 1.0, p.length()) * 0.35 if spiral else clampf(0.65 - uc * 1.1, 0.0, 1.0)
		var c := Color(heat, _shade(p, R), 0.0, a)
		verts[k * 2] = p + nrm * w * 0.5
		verts[k * 2 + 1] = p - nrm * w * 0.5
		uvs[k * 2] = Vector2(s, 0.0)
		uvs[k * 2 + 1] = Vector2(s, 1.0)
		cols[k * 2] = c
		cols[k * 2 + 1] = c
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = cols
	var mesh: ArrayMesh = (st.node as MeshInstance2D).mesh
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, arr)
	var mat := (st.node as MeshInstance2D).material as ShaderMaterial
	var fs := PackedFloat32Array()
	var fk := PackedFloat32Array()
	fs.resize(16)
	fk.resize(16)
	fs.fill(-1.0)
	var i := 0
	for sh in st.shards:
		if i >= 16:
			break
		if not sh.done and float(st.t) > SPLIT:
			fs[i] = _nearest_s(st, sh, R) if spiral else float(sh.s)
			fk[i] = (1.0 - _erode(st, sh) * 0.7) * smoothstep(SPLIT, SPLIT + 1.0, float(st.t))
		i += 1
	mat.set_shader_parameter("frag_s", fs)
	mat.set_shader_parameter("frag_k", fk)
	mat.set_shader_parameter("len", maxf(length / maxf(W, 1.0), 1.0))
	mat.set_shader_parameter("time", _time)
	# Звезда в системе гиганта всегда слева (−x).
	mat.set_shader_parameter("light", Vector2(-1.0, 0.0))


## Где в нити кусок (координата вещества ближайшей пылинки).
func _nearest_s(st: Dictionary, sh: Dictionary, R: float) -> float:
	var pr: PackedFloat32Array = st.pr
	var pt: PackedFloat32Array = st.pt
	var q := Vector2.from_angle(float(sh.th)) * float(sh.r)
	var best := 0
	var bd := INF
	for k in range(0, K, 3):
		var d := q.distance_squared_to(Vector2.from_angle(pt[k]) * maxf(pr[k], R))
		if d < bd:
			bd = d
			best = k
	return float(best) / (K - 1)
