extends Node2D
## Сгустки газа в диске: их можно догнать и всосать самому.
##
## Сгустки плывут по сдвиговому течению: внутренние обгоняют гиганта снизу
## вверх, внешние отстают сверху вниз. Где газа больше, там и сгустков больше,
## поэтому в выеденной щели их почти нет, а на её краях густо. Подойди ближе
## сферы Хилла, и гравитация гиганта утянет сгусток по спирали в свой диск.
## У каждого ядра свои сгустки: лёд строит луны, углеродные тучи дают пыль,
## тяжёлые несут хондры, у горячего гиганта газ раскалён и гуще у звезды.

const SHADER := preload("res://shaders/gas_clump.gdshader")
const PULL_TIME := 1.8       # секунд на спираль всасывания
const DRIFT := 0.3           # сгустки плывут медленнее рисунка газа, чтобы их можно было догнать
const SECONDS := 3.0         # сгусток стоит стольких секунд аккреции при полном газе

const KINDS := {
	"giant_cold": {"name": "сгусток водорода", "col": Color(0.86, 0.76, 0.62), "mass": 1.0, "n": 8},
	"giant_ice": {"name": "ледяной сгусток", "col": Color(0.66, 0.84, 1.0), "mass": 1.0, "n": 7, "ice": 1.0},
	"giant_dark": {"name": "углеродная туча", "col": Color(0.55, 0.4, 0.27), "mass": 0.9, "n": 8, "dark": 0.65},
	"giant_dense": {"name": "тяжёлый сгусток", "col": Color(0.8, 0.8, 0.84), "mass": 1.6, "n": 5},
	"giant_hot": {"name": "раскалённый сгусток", "col": Color(1.0, 0.68, 0.42), "mass": 1.2, "n": 7, "hot": 0.7},
}

var stage                    # giant_stage.gd
var clumps: Array = []
var eaten := 0
var _rng := RandomNumberGenerator.new()
var _time := 0.0
var _kind: Dictionary = {}
var _flavor := ""


func _ready() -> void:
	_rng.randomize()


func kind() -> Dictionary:
	var f := str(GameState.giant.get("flavor", "giant_cold"))
	if f != _flavor:
		_flavor = f
		_kind = KINDS.get(f, KINDS["giant_cold"])
	return _kind


func world_pos(c: Dictionary) -> Vector2:
	return Vector2.from_angle(float(c.a)) * float(c.r)


func capture_r() -> float:
	return 1.25 * stage.hill() * Skills.stat("giant_reach")


## Ближайший свободный сгусток: для бота и подсказок.
func nearest() -> Dictionary:
	var best := {}
	var bd := INF
	for c in clumps:
		if float(c.pull) >= 0.0:
			continue
		var d: float = world_pos(c).distance_to(stage.body.position)
		if d < bd:
			bd = d
			best = c
	return best


func step(delta: float) -> void:
	_time += delta
	var k := kind()
	var gk: float = clampf(stage.gas / stage.gas_total, 0.0, 1.0)
	var vp := get_viewport_rect().size
	var zoom: float = stage.camera.zoom.x
	var half_h := vp.y * 0.5 / zoom
	var orbit: float = stage.orbit
	var ang: float = stage.ang
	var gpos: Vector2 = stage.body.position
	var want := roundi(float(k["n"]) * (0.4 + 0.6 * gk))
	var tries := 0
	while clumps.size() < want and tries < 4:
		tries += 1
		_spawn(k, orbit, ang, half_h, false)
	var cap := capture_r()
	var keep := []
	for c in clumps:
		var node: ColorRect = c.node
		var mat: ShaderMaterial = node.material
		if float(c.pull) >= 0.0:
			c.pull = float(c.pull) + delta / PULL_TIME
			var e := smoothstep(0.0, 1.0, float(c.pull))
			var rel: Vector2 = (c.rel0 as Vector2).rotated(-2.2 * e) * pow(1.0 - e, 1.2)
			var wp := gpos + rel
			c.r = wp.length()
			c.a = wp.angle()
			mat.set_shader_parameter("pull", minf(float(c.pull) * 1.4, 1.0))
			# Газ струями уходит в свой диск гиганта.
			c.inj = float(c.inj) + delta * 14.0
			while float(c.inj) >= 1.0:
				c.inj = float(c.inj) - 1.0
				stage.body.inject(rel.rotated(-ang))
			if float(c.pull) >= 1.0:
				_eat(c, k)
				node.queue_free()
				continue
		else:
			# Течение: внутренний газ обгоняет гиганта, внешний отстаёт.
			var x := float(c.r) / orbit
			var dom := 0.35 * (pow(x, -1.5) - 1.0) * DRIFT
			c.a = float(c.a) - dom * delta
			var wp := world_pos(c)
			var to := gpos - wp
			var d := to.length()
			# Гравитация гиганта подтягивает сгусток, когда тот близко.
			if d < cap * 2.2:
				wp += to.normalized() * delta * 160.0 * smoothstep(cap * 2.2, cap, d)
				c.r = wp.length()
				c.a = wp.angle()
			if d < cap:
				c.pull = 0.0
				c.rel0 = wp - gpos
				c.inj = 0.0
			var da := absf(wrapf(float(c.a) - ang, -PI, PI)) * orbit
			if da > half_h * 3.2 or float(c.r) < GameData.GIANT_DISK.x + 200.0 or float(c.r) > GameData.GIANT_DISK.y - 300.0:
				node.queue_free()
				continue
		_place(c)
		mat.set_shader_parameter("time", _time)
		keep.append(c)
	clumps = keep
	_step_rocks(delta, k, orbit, ang, half_h, gpos, cap)
	queue_redraw()


func _spawn(k: Dictionary, orbit: float, ang: float, half_h: float, anywhere: bool) -> void:
	var h: float = stage.hill()
	for attempt in 6:
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		var dx := side * _rng.randf_range(0.9, 5.0) * h
		var r := orbit + dx
		if r < GameData.GIANT_DISK.x + 500.0 or r > GameData.GIANT_DISK.y - 600.0:
			continue
		var s: float = stage.disk.at(r)
		if k.has("ice"):
			s *= 1.6 if r > GameData.SNOW_LINE else 0.45
		if k.has("hot"):
			s *= 1.8 if r < GameData.HOT_ORBIT + 2000.0 else 0.6
		if _rng.randf() > clampf(s, 0.0, 1.5) / 1.5:
			continue
		# Внутренние приходят снизу (сзади), внешние сверху: навстречу по течению.
		var off := half_h * _rng.randf_range(1.1, 1.6) if not anywhere else _rng.randf_range(-1.0, 1.0) * half_h
		var a := ang + (off if dx < 0.0 else -off) / orbit
		var c := {"r": r, "a": a, "seed": _rng.randf() * 10.0, "size": h * _rng.randf_range(0.4, 0.65) * (1.25 if k["mass"] > 1.3 else 1.0),
			"pull": -1.0, "rel0": Vector2.ZERO, "inj": 0.0}
		var node := ColorRect.new()
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		mat.set_shader_parameter("col", k["col"])
		mat.set_shader_parameter("seed", c.seed)
		mat.set_shader_parameter("dark", float(k.get("dark", 0.0)))
		mat.set_shader_parameter("hot", float(k.get("hot", 0.0)))
		mat.set_shader_parameter("ice", float(k.get("ice", 0.0)))
		mat.set_shader_parameter("light", Vector2(0.0, 1.0))
		node.material = mat
		add_child(node)
		c["node"] = node
		clumps.append(c)
		_place(c)
		return


## Квад сгустка: ось x вдоль орбиты, размер сжимается при всасывании.
func _place(c: Dictionary) -> void:
	var node: ColorRect = c.node
	var sz := float(c.size) * 2.0
	if float(c.pull) >= 0.0:
		sz *= 1.0 - 0.55 * smoothstep(0.0, 1.0, float(c.pull))
	node.size = Vector2(sz * 1.6, sz)
	node.pivot_offset = node.size * 0.5
	var wp := world_pos(c)
	node.position = wp - node.pivot_offset
	var rot := float(c.a) + PI * 0.5
	node.rotation = rot
	var mat: ShaderMaterial = node.material
	var tide: Vector2 = (stage.body.position - wp).rotated(-rot)
	mat.set_shader_parameter("tide_dir", tide.normalized() if tide.length() > 1.0 else Vector2(-1, 0))


func _eat(c: Dictionary, k: Dictionary) -> void:
	eaten += 1
	var gain: float = stage.clump_gain(float(stage.disk.at(float(c.r)) if c.has("r") else 1.0)) * float(k["mass"]) * SECONDS
	gain = maxf(gain, 0.05)
	stage.earths += gain
	var type := GameState.body_type()
	var pay_k := 1.0
	var extra := ""
	if k.has("dark"):
		pay_k = 2.5
		extra = " · пыль ×2,5"
	elif k.has("ice"):
		stage.moon_prog += 0.15
		extra = " · лёд пошёл на луну"
	elif float(k["mass"]) > 1.3:
		GameState.add_chondrules(1, stage.body.position)
		extra = " · хондры +1"
	if type == "venus":
		pay_k *= 1.3
	if type == "chondrite" and _rng.randf() < 0.25:
		GameState.add_chondrules(1, stage.body.position)
	stage.pay(gain * pay_k)
	stage.body.flash()
	stage.body.flash()
	stage.hud.toast("Всосан %s: +%s масс Земли%s" % [k["name"], String.num(gain, 1).replace(".", ","), extra], (k["col"] as Color).lerp(Color.WHITE, 0.3))


# --- Мелкие тела: всё, что было до тебя ---
# Зародыши, планетезимали и рои обломков ещё кружат в диске. Гигант их не
# ждёт: подойди, и прилив разорвёт тело на куски (предел Роша), куски
# по спирали уйдут в оболочку и вспыхнут. Что за тела, решает место в диске:
# у звезды каменные и железные, за снеговой линией ледяные; у плотного ядра
# чаще железные, у тёмного углеродные, у горячего раскалённые.

const ROCKS := {
	"embryo": {"name": "зародыш", "size": 0.2, "gain": 1.6, "ch": 3, "w": 0.15},
	"planetesimal": {"name": "планетезималь", "size": 0.1, "gain": 0.45, "ch": 1, "w": 0.45},
	"rubble": {"name": "рой обломков", "size": 0.05, "gain": 0.2, "ch": 0, "w": 0.4},
}
const ROCK_MAX := 5
const SHRED_TIME := 2.2

var rocks: Array = []
var _flares: Array = []
var _rock_t := 2.0


func _material_at(r: float) -> String:
	var f := str(GameState.giant.get("flavor", "giant_cold"))
	if f == "giant_dense" and _rng.randf() < 0.5:
		return "metal"
	if f == "giant_dark" and _rng.randf() < 0.5:
		return "carbon"
	if r > GameData.SNOW_LINE:
		return "ice" if _rng.randf() < 0.75 else "rock"
	return "metal" if _rng.randf() < 0.2 else "rock"


const ROCK_COL := {
	"rock": Color(0.62, 0.54, 0.46), "metal": Color(0.66, 0.66, 0.7),
	"ice": Color(0.8, 0.88, 0.96), "carbon": Color(0.32, 0.27, 0.24),
}


func _step_rocks(delta: float, _k: Dictionary, orbit: float, ang: float, half_h: float, gpos: Vector2, cap: float) -> void:
	var h: float = stage.hill()
	_rock_t -= delta
	if _rock_t <= 0.0 and rocks.size() < ROCK_MAX:
		_rock_t = _rng.randf_range(3.0, 6.0)
		var roll := _rng.randf()
		var kind := "rubble"
		if roll < ROCKS["embryo"]["w"]:
			kind = "embryo"
		elif roll < ROCKS["embryo"]["w"] + ROCKS["planetesimal"]["w"]:
			kind = "planetesimal"
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		var dx := side * _rng.randf_range(1.0, 4.5) * h
		var r := clampf(orbit + dx, GameData.GIANT_DISK.x + 600.0, GameData.GIANT_DISK.y - 700.0)
		var off := half_h * _rng.randf_range(1.1, 1.5)
		var mat := _material_at(r)
		var n := 6 if kind == "rubble" else 1
		rocks.append({"kind": kind, "mat": mat, "r": r, "a": ang + (off if dx < 0.0 else -off) / orbit,
			"pull": -1.0, "rel0": Vector2.ZERO, "seed": _rng.randf() * 100.0, "n": n,
			"hot": r < GameData.HOT_ORBIT + 800.0})
	var keep := []
	for b in rocks:
		var size: float = h * float(ROCKS[b.kind]["size"])
		if float(b.pull) >= 0.0:
			b.pull = float(b.pull) + delta / SHRED_TIME
			if float(b.pull) >= 1.0:
				_eat_rock(b)
				continue
		else:
			var x := float(b.r) / orbit
			b.a = float(b.a) - 0.35 * (pow(x, -1.5) - 1.0) * DRIFT * delta
			var wp := Vector2.from_angle(float(b.a)) * float(b.r)
			var to := gpos - wp
			var d := to.length()
			if d < cap * 2.0:
				wp += to.normalized() * delta * 220.0 * smoothstep(cap * 2.0, cap, d)
				b.r = wp.length()
				b.a = wp.angle()
			if d < cap + size:
				b.pull = 0.0
				b.rel0 = wp - gpos
				if not stage._said.has("shred"):
					stage._said["shred"] = true
					stage.hud.caption("Предел Роша", "прилив гиганта рвёт всё, что подошло близко: зародыши и обломки падают в тебя", 3.5)
			var da := absf(wrapf(float(b.a) - ang, -PI, PI)) * orbit
			if da > half_h * 3.2:
				continue
		keep.append(b)
	rocks = keep
	var fl := []
	for f in _flares:
		f.t = float(f.t) + delta
		if float(f.t) < 0.9:
			fl.append(f)
	_flares = fl


## Где сейчас тело или его куски: спираль к гиганту после разрыва.
func _rock_parts(b: Dictionary, gpos: Vector2, size: float) -> Array:
	var parts := []
	if float(b.pull) < 0.0:
		var c := Vector2.from_angle(float(b.a)) * float(b.r)
		for i in int(b.n):
			var o := Vector2(sin(float(b.seed) + i * 2.4), cos(float(b.seed) * 1.3 + i * 1.7)) * size * (2.5 if int(b.n) > 1 else 0.0)
			parts.append([c + o, size * (1.0 if int(b.n) == 1 else 0.6 + 0.4 * fmod(i * 0.37, 1.0)), 0.0])
		return parts
	var e := smoothstep(0.0, 1.0, float(b.pull))
	# До половины пути тело целое и вытягивается, потом рвётся на куски.
	var broken := smoothstep(0.25, 0.45, float(b.pull))
	var pieces := maxi(int(b.n), 1 + int(broken * 7.0))
	for i in pieces:
		var lag := float(i) / maxf(pieces, 1) * 0.18 * broken
		var ei := clampf(e - lag, 0.0, 1.0)
		var rel: Vector2 = (b.rel0 as Vector2).rotated(-2.6 * ei) * pow(1.0 - ei, 1.15)
		var sz := size * (1.0 if pieces == 1 else 0.35 + 0.3 * fmod(i * 0.61, 1.0))
		parts.append([gpos + rel, sz * (1.0 - 0.5 * ei), ei])
	return parts


## Тело события уже засчитано: показать только, как прилив его рвёт и роняет.
func shred_now(kind: String, mat: String, rel: Vector2, n := 1) -> void:
	var wp: Vector2 = stage.body.position + rel
	rocks.append({"kind": kind, "mat": mat, "r": wp.length(), "a": wp.angle(), "pull": 0.0, "rel0": rel,
		"seed": _rng.randf() * 100.0, "n": n, "hot": false, "free": true})


func _eat_rock(b: Dictionary) -> void:
	if b.get("free", false):
		stage.body.flash()
		var r0: float = stage.body.body_r * stage.body.inflate
		_flares.append({"p": (b.rel0 as Vector2).rotated(-2.6).normalized() * r0 * 0.95, "t": 0.0, "big": b.kind == "embryo"})
		return
	var info: Dictionary = ROCKS[b.kind]
	var gain: float = float(info["gain"]) + 0.01 * stage.earths * (1.0 if b.kind == "embryo" else 0.3)
	stage.earths += gain
	var pay_k := 2.0
	var extra := ""
	match str(b.mat):
		"ice":
			stage.moon_prog += 0.2 if str(GameState.giant.get("flavor", "")) == "giant_ice" else 0.1
			extra = " · лёд пошёл на луну"
		"metal":
			pay_k = 3.0
			extra = " · железо: пыль ×3"
		"carbon":
			pay_k = 2.6
	var ch := int(info["ch"]) + (1 if GameState.body_type() == "chondrite" and b.kind != "rubble" else 0)
	if ch > 0:
		GameState.add_chondrules(ch, stage.body.position)
		extra += " · хондры +%d" % ch
	stage.pay(gain * pay_k)
	stage.body.flash()
	var rel: Vector2 = (b.rel0 as Vector2).rotated(-2.6)
	var r: float = stage.body.body_r * stage.body.inflate
	_flares.append({"p": rel.normalized() * r * 0.95 if rel.length() > 1.0 else Vector2(-r, 0), "t": 0.0, "big": b.kind == "embryo"})
	stage.hud.toast("Уничтожен %s: +%s масс Земли%s" % [info["name"], String.num(gain, 1).replace(".", ","), extra], Color(1.0, 0.86, 0.7))


func _draw() -> void:
	if stage == null:
		return
	var gpos: Vector2 = stage.body.position
	var h: float = stage.hill()
	var px := 1.0 / maxf(stage.camera.zoom.x, 0.01)
	var light_dir := -gpos.normalized()
	for b in rocks:
		var size: float = h * float(ROCKS[b.kind]["size"])
		var col: Color = ROCK_COL[b.mat]
		for part in _rock_parts(b, gpos, size):
			var c: Vector2 = part[0]
			var rad := maxf(float(part[1]), 1.5 * px)
			var e: float = part[2]
			# Куски накаляются, врезаясь в оболочку гиганта.
			var heat := smoothstep(0.55, 1.0, e)
			if b.hot:
				heat = maxf(heat, 0.35)
			if e > 0.3:
				var back: Vector2 = (c - gpos).rotated(0.5).normalized() * rad * (3.0 + 6.0 * heat)
				draw_line(c, c + back, Color(1.0, 0.7, 0.45, 0.25 + 0.4 * heat), rad * 0.8, true)
			_ball(c, rad, col.lerp(Color(1.0, 0.55, 0.25), heat * 0.8), light_dir)
			if heat > 0.0:
				draw_circle(c, rad * (1.3 + heat), Color(1.0, 0.6, 0.3, 0.25 * heat))
		if float(b.pull) < 0.0 and b.kind == "embryo":
			# У зародыша своя пыльная дымка: видно, что это не камешек.
			var ec := Vector2.from_angle(float(b.a)) * float(b.r)
			for j in 6:
				var f := float(j) / 6.0
				draw_circle(ec, size * (1.2 + 1.2 * f), Color(col, 0.025 * (1.0 - f)))
	var r: float = stage.body.body_r * stage.body.inflate
	for f in _flares:
		var k := 1.0 - float(f.t) / 0.9
		var big := 1.8 if f.big else 1.0
		var at: Vector2 = gpos + (f.p as Vector2)
		draw_circle(at, r * 0.1 * big * (1.0 + float(f.t) * 2.0), Color(1.0, 0.8, 0.55, 0.5 * k * k))
		draw_circle(at, r * 0.045 * big, Color(1.0, 0.95, 0.85, 0.9 * k))


func _ball(c: Vector2, rad: float, col: Color, light: Vector2) -> void:
	var steps := 8
	for k in steps:
		var f := float(k) / steps
		var lum := 0.08 + 0.92 * pow(f, 0.7)
		draw_circle(c + light * rad * 0.5 * f, rad * (1.0 - f * 0.85), Color(col.r * lum, col.g * lum, col.b * lum))
