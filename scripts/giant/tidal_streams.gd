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
var debris: Array = []        # разорванные тела: куски, обломки, пыль (см. spawn_debris)
var _time := 0.0

# Разрыв по-новому: тело не режется на ленты, а рассыпается, как валун:
# несколько крупных кусков (настоящая поверхность со снимка), десятки
# угловатых обломков и сотни пылинок. Каждый стартует со скоростью самого
# тела (без остановки и рывка), дальше газ околопланетного диска сводит его
# на свою спираль: пыль за доли секунды, обломки за секунду, куски за
# несколько. Ближние к гиганту обгоняют дальних — облако само тянется в дугу.
# Свет: прилив тело почти не греет. Светится только то, что уже было
# горячим внутри (расплав лавы, тёплые недра камня, тлеющий углерод) — и
# остывает на лету, мелочь быстрее. Ледяное и холодное — матовая пыль.
# Вспыхивает лишь то, что входит в облака: короткий метеор у самого края.
const K_DUST := 4.0           # как быстро газ подхватывает пылинку, 1/с
const K_FRAG := 1.9
const K_CHUNK := 1.25
# Цвет нутра и накала по веществу: свежий скол, свечение расплава, начальный жар.
const HEAT := {
	"lava": [Color(1.0, 0.42, 0.1), 1.0], "rock": [Color(1.0, 0.36, 0.1), 0.38],
	"carbon": [Color(0.95, 0.3, 0.06), 0.28], "metal": [Color(1.0, 0.62, 0.32), 0.18],
	"ice": [Color(0.8, 0.9, 1.0), 0.0], "nep": [Color(0.8, 0.9, 1.0), 0.0],
	"rival": [Color(1.0, 0.5, 0.2), 0.2], "ring": [Color(0.8, 0.9, 1.0), 0.0],
}


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
		# Мелочь у головы тормозится сильнее, у хвоста — слабее. Плавно по
		# нити: соседние пылинки летят почти одинаково, нить не рвётся в клочья.
		pg.append(g0 * (1.12 - 0.24 * sk) * (1.0 + 0.06 * sin(sk * 7.0 + float(st.seed))))
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
	var dk := []
	for d in debris:
		if _step_debris(d, delta, R):
			dk.append(d)
		else:
			_free_debris(d)
	debris = dk
	queue_redraw()


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
	# Шлейф у кометы 1994 года поднимался на ~3000 км: 4% радиуса Юпитера.
	plume(at.normalized() * R * 0.97, clampf(R * 0.025 + size * 0.5, R * 0.03, R * 0.08), smoke.darkened(0.45), float(st.seed) + float(sh.k), 2.4)


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
	# Утонувшие пылинки стягиваем к соседней живой: иначе лента тянет
	# хорду от точки в облаках до живой пыли — линию поперёк гиганта.
	if spiral:
		var last := -1
		for k in K:
			if pr[k] > R:
				last = k
			elif last >= 0:
				pts[k] = pts[last]
		# Голова, утонувшая раньше любой живой пылинки, — к первой живой.
		var first := -1
		for k in K:
			if pr[k] > R:
				first = k
				break
		if first > 0:
			for k in first:
				pts[k] = pts[first]
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
		w *= sink[k] if spiral else 1.0
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
	# Треугольники по отрезкам: отрезок длиннее доли радиуса не рисуем —
	# иначе разошедшиеся пылинки соединяет прямая линия через гиганта.
	var tv := PackedVector2Array()
	var tu := PackedVector2Array()
	var tc := PackedColorArray()
	var max_seg := maxf(R * 0.35, W * 2.0)
	for k in K - 1:
		if pts[k].distance_to(pts[k + 1]) > max_seg:
			continue
		var i0 := k * 2
		var i1 := k * 2 + 1
		var i2 := k * 2 + 2
		var i3 := k * 2 + 3
		for idx in [i0, i1, i2, i1, i3, i2]:
			tv.append(verts[idx])
			tu.append(uvs[idx])
			tc.append(cols[idx])
	var mesh: ArrayMesh = (st.node as MeshInstance2D).mesh
	mesh.clear_surfaces()
	if tv.size() >= 3:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = tv
		arr[Mesh.ARRAY_TEX_UV] = tu
		arr[Mesh.ARRAY_COLOR] = tc
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
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


# ---------------------------------------------------------------------------
# Разрыв твёрдого тела: куски, обломки, пыль.

## from, vel — где тело и с какой скоростью летело (система гиганта, ед./с).
## mass — масса, которая уйдёт в гиганта; pay — множитель награды.
## opts: snap (снимок тела), chunks (сколько крупных кусков), rad (радиус
## тела на экране), hot_k (добавка жара: горячий гигант у звезды), comet.
func spawn_debris(from: Vector2, vel: Vector2, mass: float, pay: float, pal: String, seed_v: float, opts := {}) -> Dictionary:
	var R: float = world.stage.body.body_r * world.stage.body.inflate
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed_v * 7919.0) + 11
	if not PALS.has(pal):
		pal = "rock"
	var heat_info: Array = HEAT.get(pal, HEAT["rock"])
	var hot0 := clampf(float(heat_info[1]) + float(opts.get("hot_k", 0.0)), 0.0, 1.0)
	var rad: float = float(opts.get("rad", 20.0))
	var r0 := from.length()
	var d := {
		"t": 0.0, "pal": pal, "seed": seed_v, "pay": pay, "R0": R, "r0": r0, "from": from, "rad": rad,
		"hot": hot0, "hot_col": heat_info[0], "chunks": [], "frags": [], "scarred": false,
		"g0": log(maxf(r0 - 0.9 * R, 1.0) / (0.1 * R)) / 11.0 * 0.6, "left": mass,
		# Пыль — упакованные массивы: x, y, vx, vy, размер, жар, масса.
		"dx": PackedFloat32Array(), "dy": PackedFloat32Array(), "dvx": PackedFloat32Array(), "dvy": PackedFloat32Array(),
		"ds": PackedFloat32Array(), "dh": PackedFloat32Array(), "dm": PackedFloat32Array(), "dk": PackedFloat32Array(),
		"dg": PackedFloat32Array(),
	}
	var rhat := from.normalized()
	# Прилив тянет тело вдоль линии на гиганта: ближняя половина уходит
	# вперёд и вниз, дальняя отстаёт. Скорость — самого тела плюс растяжение.
	var stretch := func(off: Vector2) -> Vector2:
		return vel + rhat * off.dot(rhat) * 2.4 + off.orthogonal() * 0.15
	# Крупные куски — ячейки Вороного по снимку. Их доля массы зависит от
	# прочности: камень и металл держатся кусками, лёд и углерод сыплются.
	var snap: Dictionary = opts.get("snap", {})
	var n := int(opts.get("chunks", 0))
	var chunk_share := {"metal": 0.55, "rock": 0.42, "lava": 0.3, "carbon": 0.3, "ice": 0.25}.get(pal, 0.35) as float
	if n <= 0 or snap.is_empty():
		chunk_share = 0.0
	var m_chunks := mass * chunk_share
	var m_frags := mass * (1.0 - chunk_share) * 0.4
	var m_dust := mass * (1.0 - chunk_share) * 0.6
	if chunk_share > 0.0:
		_debris_chunks(d, n, rad, m_chunks, snap, rng, stretch)
	# Угловатые обломки: размер по степенному закону — мелких много, крупных мало.
	var nf := int(opts.get("frags", 26))
	for i in nf:
		var off := _blob(rng, rhat, rad * 0.9)
		var sz := rad * (0.05 + 0.16 * pow(rng.randf(), 2.2))
		(d.frags as Array).append(_new_frag(from + off, stretch.call(off) + _jit(rng, rad * 0.4), sz, m_frags / nf, hot0 * rng.randf_range(0.4, 1.0), rng))
	# Пыль: сотни пылинок по всему диску тела.
	var nd := int(opts.get("dust", 200))
	for i in nd:
		var off := _blob(rng, rhat, rad)
		_add_dust(d, from + off, stretch.call(off) + _jit(rng, rad * 0.6), m_dust / nd, hot0 * rng.randf_range(0.3, 1.0), rng)
	debris.append(d)
	return d


## Точка в теле, уже вытянутом приливом вдоль линии на гиганта.
static func _blob(rng: RandomNumberGenerator, rhat: Vector2, rad: float) -> Vector2:
	var o := Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * rad
	return rhat * o.dot(rhat) * 1.5 + rhat.orthogonal() * o.dot(rhat.orthogonal()) * 0.8


static func _jit(rng: RandomNumberGenerator, s: float) -> Vector2:
	return Vector2(rng.randfn(0.0, s), rng.randfn(0.0, s))


func _add_dust(d: Dictionary, p: Vector2, v: Vector2, m: float, heat: float, rng: RandomNumberGenerator) -> void:
	(d.dx as PackedFloat32Array).append(p.x)
	(d.dy as PackedFloat32Array).append(p.y)
	(d.dvx as PackedFloat32Array).append(v.x)
	(d.dvy as PackedFloat32Array).append(v.y)
	(d.ds as PackedFloat32Array).append(pow(rng.randf(), 1.8))   # 0 — пылинка, 1 — песчинка
	(d.dh as PackedFloat32Array).append(heat)
	(d.dm as PackedFloat32Array).append(m)
	# Мелочь газ подхватывает быстрее, песчинки дольше летят по инерции.
	(d.dk as PackedFloat32Array).append(K_DUST * rng.randf_range(0.7, 1.3))
	# Своя скорость дрейфа внутрь: одни пылинки тонут быстрее, другие кружат —
	# облако расходится по радиусу, и сдвиг вращения тянет его в дугу.
	(d.dg as PackedFloat32Array).append(rng.randf_range(0.5, 1.7))


func _new_frag(p: Vector2, v: Vector2, sz: float, m: float, heat: float, rng: RandomNumberGenerator) -> Dictionary:
	# Угловатый камень: 5–7 вершин с рваным радиусом, как обломки валуна.
	var pts := PackedVector2Array()
	var nv := rng.randi_range(5, 7)
	var a0 := rng.randf() * TAU
	for k in nv:
		var a := a0 + TAU * (float(k) + rng.randf_range(-0.3, 0.3)) / nv
		pts.append(Vector2.from_angle(a) * rng.randf_range(0.55, 1.0))
	return {"p": p, "v": v, "sz": sz, "m": m, "heat": heat, "pts": pts, "a": rng.randf() * TAU,
		"spin": rng.randf_range(-1.6, 1.6), "k": K_FRAG * rng.randf_range(0.75, 1.25), "g": rng.randf_range(0.5, 1.4), "tone": rng.randf_range(0.8, 1.15)}


func _debris_chunks(d: Dictionary, n: int, rad: float, m: float, snap: Dictionary, rng: RandomNumberGenerator, stretch: Callable) -> void:
	var seeds := PackedVector2Array()
	for i in n:
		seeds.append(Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * 0.85)
	var disc: float = snap.disc
	var wr := rad / disc
	var ang: float = world.stage.ang
	var p: Array = PALS[d.pal]
	for i in n:
		var c := seeds[i]
		var rect := ColorRect.new()
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.size = Vector2(wr, wr)
		rect.pivot_offset = (Vector2(0.5, 0.5) + c * disc) * wr
		var mt := ShaderMaterial.new()
		mt.shader = preload("res://shaders/shard.gdshader")
		mt.set_shader_parameter("body_tex", snap.tex)
		mt.set_shader_parameter("noise_tex", NoiseTex.get_tex())
		mt.set_shader_parameter("seeds", seeds)
		mt.set_shader_parameter("n", n)
		mt.set_shader_parameter("cell", i)
		mt.set_shader_parameter("disc", disc)
		mt.set_shader_parameter("crack_col", p[5])
		mt.set_shader_parameter("hot_col", d.hot_col)
		mt.set_shader_parameter("seed", fmod(float(d.seed), 5.0))
		rect.material = mt
		rect.visible = false
		add_child(rect)
		var off := c.rotated(-ang) * rad
		(d.chunks as Array).append({"node": rect, "c": c, "p": (d.from as Vector2) + off, "v": stretch.call(off),
			"spin": rng.randf_range(-0.4, 0.4), "k": K_CHUNK * rng.randf_range(0.8, 1.2), "q": rng.randf(),
			"m": m / n, "er": 0.0, "acc": 0.0, "done": false})
	d["snap"] = snap


## Скорость газа диска в точке: круговая по Кеплеру (прямое вращение) и
## медленный дрейф внутрь, глубже — быстрее.
func _gas_v(p: Vector2, R: float, g: float) -> Vector2:
	var r := maxf(p.length(), R * 0.5)
	var rh := p / r
	var w := W0 * pow(r / R, -1.5)
	var vr := -(r - 0.9 * R) * g * pow(R / r, 2.0)
	# Прямое вращение: угол убывает (DIR = −1), касательная — (sin, −cos).
	return rh * vr + Vector2(rh.y, -rh.x) * (-DIR) * w * r


func _relax(p: Vector2, v: Vector2, k: float, R: float, g: float, dt: float) -> Vector2:
	var vg := _gas_v(p, R, g)
	return vg + (v - vg) * exp(-k * dt)


func _sink(d: Dictionary, m: float, mult := 1.0) -> void:
	if m <= 0.0:
		return
	d.left = float(d.left) - m
	world.stage.earths += m
	world.stage.pay(m * float(d.pay) * mult)


func _step_debris(d: Dictionary, delta: float, R: float) -> bool:
	d.t = float(d.t) + delta
	var t: float = d.t
	var g: float = d.g0
	var steps := maxi(1, ceili(delta / 0.02))
	var dt := delta / steps
	var hot_col: Color = d.hot_col
	var rng := RandomNumberGenerator.new()
	rng.seed = int(t * 1000.0) + int(float(d.seed) * 31.0)
	var ang: float = world.stage.ang
	# Крупные куски: летят, стачиваются, роняют обломки и пыль.
	var cool := 0.22   # остывание за секунду (крупное — медленнее)
	var any := false
	for ch in d.chunks:
		if ch.done:
			continue
		var pp: Vector2 = ch.p
		var vv: Vector2 = ch.v
		for i in steps:
			vv = _relax(pp, vv, float(ch.k), R, g * 0.55, dt)
			pp += vv * dt
		ch.p = pp
		ch.v = vv
		var prog := clampf((float(d.r0) - pp.length()) / maxf(float(d.r0) - R, 1.0), 0.0, 1.0)
		var er := clampf(smoothstep(0.0, 0.9, prog) * (0.55 + 0.6 * float(ch.q)) + t * 0.03, 0.0, 1.0)
		var der := er - float(ch.er)
		if der > 0.0:
			ch.er = er
			# Что сточилось, то сыплется с куска: масса уходит в пыль и обломки.
			var lost := float(ch.m) * der
			ch.acc = float(ch.acc) + der * 40.0
			while float(ch.acc) >= 1.0:
				ch.acc = float(ch.acc) - 1.0
				var off := Vector2.from_angle(rng.randf() * TAU) * float(d.rad) * 0.3
				var vel := vv + _jit(rng, float(d.rad) * 0.35)
				var heat := float(d.hot) * maxf(1.0 - t * 0.1, 0.2)
				if rng.randf() < 0.18:
					(d.frags as Array).append(_new_frag(pp + off, vel, float(d.rad) * rng.randf_range(0.04, 0.12), lost * 0.25, heat, rng))
				else:
					_add_dust(d, pp + off, vel, lost / 40.0 * 0.8, heat, rng)
			ch.m = float(ch.m) - lost
		if pp.length() <= R * 0.99:
			ch.done = true
			(ch.node as CanvasItem).visible = false
			_chunk_hit(d, ch, R)
			continue
		any = true
		var node: ColorRect = ch.node
		node.visible = true
		node.position = pp - node.pivot_offset
		node.rotation = -ang + float(ch.spin) * t
		var sc := 1.0 - 0.3 * er
		node.scale = Vector2(sc, sc)
		var m := node.material as ShaderMaterial
		# Трещины проступают в первые доли секунды, пока тело ещё целое.
		m.set_shader_parameter("crack", smoothstep(0.0, 0.5, t))
		m.set_shader_parameter("erode", er)
		m.set_shader_parameter("shade", _shade(pp, R))
		m.set_shader_parameter("emit", float(d.hot) * exp(-t * cool * 0.6))
	# Обломки.
	var fk := []
	for f in d.frags:
		var pp: Vector2 = f.p
		var vv: Vector2 = f.v
		for i in steps:
			vv = _relax(pp, vv, float(f.k), R, g * 0.8 * float(f.g), dt)
			pp += vv * dt
		f.p = pp
		f.v = vv
		f.a = float(f.a) + float(f.spin) * delta
		# Мелкое остывает быстрее: тепло уходит с поверхности.
		f.heat = float(f.heat) * exp(-delta * cool * 2.2)
		if pp.length() <= R:
			_sink(d, float(f.m))
			continue
		fk.append(f)
	d.frags = fk
	# Пыль.
	var dx: PackedFloat32Array = d.dx
	var dy: PackedFloat32Array = d.dy
	var dvx: PackedFloat32Array = d.dvx
	var dvy: PackedFloat32Array = d.dvy
	var dh: PackedFloat32Array = d.dh
	var dkk: PackedFloat32Array = d.dk
	var dm: PackedFloat32Array = d.dm
	var dg: PackedFloat32Array = d.dg
	var alive := 0
	var sunk := 0.0
	var first_sink := Vector2.ZERO
	for i in dx.size():
		if dm[i] < 0.0:
			continue
		var pp := Vector2(dx[i], dy[i])
		var vv := Vector2(dvx[i], dvy[i])
		for s in steps:
			vv = _relax(pp, vv, dkk[i], R, g * dg[i], dt)
			pp += vv * dt
		if pp.length() <= R:
			sunk += dm[i]
			dm[i] = -1.0
			if first_sink == Vector2.ZERO:
				first_sink = pp
			continue
		dx[i] = pp.x
		dy[i] = pp.y
		dvx[i] = vv.x
		dvy[i] = vv.y
		dh[i] = dh[i] * exp(-delta * cool * 4.0)
		alive += 1
	d.dx = dx
	d.dy = dy
	d.dvx = dvx
	d.dvy = dvy
	d.dh = dh
	d.dm = dm
	_sink(d, sunk)
	if first_sink != Vector2.ZERO and not d.scarred and alive < dx.size() * 0.6:
		# Пыль оседает в облаках: тёмная дымка там, где ушла голова облака.
		d.scarred = true
		world.stage.body.scar(first_sink.normalized(), float(d.rad) * 0.5)
	if (alive == 0 and (d.frags as Array).is_empty() and not any) or t > 60.0:
		_sink(d, maxf(float(d.left), 0.0))
		return false
	return true


## Кусок дошёл до облаков. Сточенный почти весь — тонет без следа. Уцелевший
## входит на десятках км/с: короткий шлейф и тёмный шрам (Шумейкеры — Леви 9).
func _chunk_hit(d: Dictionary, ch: Dictionary, R: float) -> void:
	_sink(d, float(ch.m), Skills.stat("giant_impact"))
	if float(ch.er) > 0.95:
		return
	var at: Vector2 = (ch.p as Vector2).normalized()
	var size := float(d.rad) * (1.0 - float(ch.er)) * 0.6
	world.stage.body.scar(at, size)
	var smoke: Color = (PALS[d.pal] as Array)[0]
	plume(at * R * 0.97, clampf(R * 0.025 + size * 0.5, R * 0.03, R * 0.08), smoke.darkened(0.45), float(d.seed) + float(ch.q), 2.4)


func _free_debris(d: Dictionary) -> void:
	for ch in d.chunks:
		(ch.node as Node).queue_free()
	var snap: Dictionary = d.get("snap", {})
	if snap.has("vp"):
		(snap.vp as Node).queue_free()


## Цвет накала по температуре: тёмно-красный → оранжевый → жёлтый.
static func _glow_col(h: float, base: Color) -> Color:
	return base.lerp(Color(1.0, 0.85, 0.55), clampf(h - 0.6, 0.0, 0.4) * 1.5)


func _draw() -> void:
	if debris.is_empty():
		return
	var R: float = world.stage.body.body_r * world.stage.body.inflate
	var zoom: float = maxf(world.stage.camera.zoom.x, 0.001)
	var px := 1.0 / zoom
	for d in debris:
		var p: Array = PALS[d.pal]
		var dust_col: Color = p[0]
		var rock_col: Color = (p[0] as Color).lerp(p[5], 0.35)
		var hot_col: Color = d.hot_col
		var fade := smoothstep(0.0, 0.25, float(d.t))
		var rad: float = d.rad
		# Обломки: многоугольник, освещённый со стороны звезды (−x).
		for f in d.frags:
			var c: Vector2 = f.p
			var sz := maxf(float(f.sz), 1.6 * px)
			var sh := _shade(c, R)
			var heat: float = f.heat
			var entry := smoothstep(R * 1.1, R * 1.0, c.length())
			var pts := PackedVector2Array()
			var cols := PackedColorArray()
			for v in f.pts:
				var vv: Vector2 = (v as Vector2).rotated(float(f.a))
				pts.append(c + vv * sz)
				var lit := 0.45 + 0.65 * maxf(-vv.normalized().x, 0.0)
				var col := (rock_col * float(f.tone) * lit * sh)
				col = col.lerp(_glow_col(maxf(heat, entry), hot_col), clampf(maxf(heat, entry * 0.8), 0.0, 1.0) * 0.85)
				col.a = fade
				cols.append(col)
			draw_polygon(pts, cols)
			var hh := maxf(heat, entry * 0.7)
			if hh > 0.15:
				# Горячий камень светится сам; ореол маленький, без «шара».
				draw_circle(c, sz * 1.9, Color(hot_col, 0.16 * hh * fade))
		# Пыль: матовые точки цвета тела; горячие — тлеют.
		var dx: PackedFloat32Array = d.dx
		var dy: PackedFloat32Array = d.dy
		var ds: PackedFloat32Array = d.ds
		var dh: PackedFloat32Array = d.dh
		var dm: PackedFloat32Array = d.dm
		for i in dx.size():
			if dm[i] < 0.0:
				continue
			var c := Vector2(dx[i], dy[i])
			var r := c.length()
			var entry := smoothstep(R * 1.08, R * 1.0, r)
			var hh := maxf(dh[i], entry * 0.6)
			var s := maxf(rad * (0.012 + 0.03 * ds[i]), (0.9 + 1.4 * ds[i]) * px)
			var col := dust_col * (0.55 + 0.45 * ds[i]) * _shade(c, R)
			col = col.lerp(_glow_col(hh, hot_col), clampf(hh, 0.0, 1.0))
			# Пылинка тонет в облаках: тает у самого края.
			col.a = fade * (0.5 + 0.4 * ds[i]) * smoothstep(R * 1.0, R * 1.04, r)
			draw_rect(Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), col)
			if hh > 0.3:
				draw_circle(c, s * 1.6, Color(hot_col, 0.12 * hh * col.a))
