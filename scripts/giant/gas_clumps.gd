extends Node2D
## Сгустки газа в диске: их можно догнать и всосать самому.
##
## Сам газ — частицы в задаче Хилла (gas_particles.gd): сгусток течёт по
## сдвигу, а подойдёшь ближе, и гравитация гиганта сама растянет его приливом
## в струю, закрутит и уронит в свой диск. Здесь только учёт: что за сгустки
## у этого ядра, сколько их, что даёт каждая севшая частица.
## Где газа больше, там и сгустков больше: в выеденной щели их почти нет.
## У каждого ядра свои сгустки: лёд строит луны, углеродные тучи дают пыль,
## тяжёлые несут хондры, у горячего гиганта газ раскалён и гуще у звезды.

const DRIFT := 0.3           # мелкие тела плывут медленнее газа: их можно догнать
const SECONDS := 3.0         # сгусток стоит стольких секунд аккреции при полном газе
const PARTS := 46            # частиц в сгустке

const KINDS := {
	"giant_cold": {"name": "сгусток водорода", "col": Color(0.86, 0.78, 0.66), "mass": 1.0, "n": 5},
	"giant_ice": {"name": "ледяной сгусток", "col": Color(0.7, 0.86, 1.0), "mass": 1.0, "n": 5, "ice": 1.0},
	"giant_dark": {"name": "углеродная туча", "col": Color(0.3, 0.22, 0.16), "mass": 0.9, "n": 5, "dark": 0.65},
	"giant_dense": {"name": "тяжёлый сгусток", "col": Color(0.8, 0.8, 0.86), "mass": 1.6, "n": 4},
	"giant_hot": {"name": "раскалённый сгусток", "col": Color(1.0, 0.62, 0.36), "mass": 1.2, "n": 5, "hot": 0.7},
}

var stage                    # giant_stage.gd
var clumps := {}             # id -> {mass, left, eaten, said}
var eaten := 0
var _next_id := 0
var _rng := RandomNumberGenerator.new()
var _time := 0.0
var _kind: Dictionary = {}
var _flavor := ""
var _spawn_t := 1.0


func _ready() -> void:
	_rng.randomize()


func bind(gas: GasParticles) -> void:
	gas.particle_eaten.connect(_on_eaten)


func kind() -> Dictionary:
	var f := str(GameState.giant.get("flavor", "giant_cold"))
	if f != _flavor:
		_flavor = f
		_kind = KINDS.get(f, KINDS["giant_cold"])
	return _kind


func capture_r() -> float:
	return 1.25 * stage.hill() * Skills.stat("giant_reach")


## Ближайший сгусток в мировых координатах (для бота); {} — нет.
func nearest() -> Dictionary:
	var best := {}
	var bd := INF
	var gas: GasParticles = stage.body.gas
	for id in clumps.keys():
		var c := gas.clump_center(id)
		if c.x == INF:
			continue
		var d := c.length()
		if d < bd:
			bd = d
			best = {"id": id, "hill": c}
	return best


func world_pos(c: Dictionary) -> Vector2:
	var h: Vector2 = c.hill
	return stage.body.to_global(Vector2(h.x, -h.y) * stage.hill())


func step(delta: float) -> void:
	_time += delta
	var k := kind()
	var gas: GasParticles = stage.body.gas
	var gk: float = clampf(stage.gas / stage.gas_total, 0.0, 1.0)
	# Уплывшие и съеденные сгустки забываем.
	for id in clumps.keys():
		if gas.count_of(id) == 0:
			clumps.erase(id)
	var want := roundi(float(k["n"]) * (0.4 + 0.6 * gk))
	_spawn_t -= delta
	if _spawn_t <= 0.0 and clumps.size() < want:
		_spawn_t = _rng.randf_range(1.5, 3.5)
		_spawn(k, gas)
	var orbit: float = stage.orbit
	var vp := get_viewport_rect().size
	var half_h: float = vp.y * 0.5 / stage.camera.zoom.x
	_step_rocks(delta, k, orbit, stage.ang, half_h, stage.body.position, capture_r())
	queue_redraw()


func _spawn(k: Dictionary, gas: GasParticles) -> void:
	var h: float = stage.hill()
	var orbit: float = stage.orbit
	for attempt in 6:
		# Сам газ падает на гиганта только из полосы 1.25–2.1 радиуса Хилла
		# (задача Хилла). Сгустки рождаются вне её: чтобы съесть, надо подъехать.
		# Навык «длинные руки» расширяет полосу, и часть сгустков падает сама.
		var off := _rng.randf_range(2.4, 3.8) if _rng.randf() < 0.75 else _rng.randf_range(0.3, 1.0)
		var x := (1.0 if _rng.randf() < 0.5 else -1.0) * off
		var r := orbit + x * h
		if r < GameData.GIANT_STAR_R * 1.25 or r > GameData.GIANT_DISK.y - 600.0:
			continue
		var s: float = stage.disk.at(r)
		if k.has("ice"):
			s *= 1.6 if r > GameData.SNOW_LINE else 0.45
		if k.has("hot"):
			s *= 1.8 if r < GameData.HOT_ORBIT + 2000.0 else 0.6
		if _rng.randf() > clampf(s, 0.0, 1.5) / 1.5:
			continue
		# Внешние приходят сверху, внутренние снизу: навстречу по течению.
		var y := signf(x) * _rng.randf_range(4.5, 6.0)
		var id := _next_id
		_next_id += 1
		var count := PARTS if k["mass"] < 1.3 else PARTS + 14
		var gain: float = maxf(stage.clump_gain(s) * float(k["mass"]) * SECONDS, 0.05)
		clumps[id] = {"mass": gain / count, "left": count, "eaten": 0, "said": false}
		gas.spawn_clump(id, x, y, _rng.randf_range(0.35, 0.55), count, k["col"])
		return


## Частица сгустка села в свой диск гиганта: масса и пыль приходят по частям.
func _on_eaten(id: int) -> void:
	if not clumps.has(id):
		return
	var c: Dictionary = clumps[id]
	var k := kind()
	c.eaten = int(c.eaten) + 1
	var gain: float = c.mass
	stage.earths += gain
	var pay_k := 2.5 if k.has("dark") else 1.0
	if GameState.body_type() == "venus":
		pay_k *= 1.3
	stage.pay(gain * pay_k)
	stage.body.flash()
	if not c.said and int(c.eaten) >= int(c.left) / 2:
		c.said = true
		eaten += 1
		_reward(k, float(c.mass) * float(c.left))


func _reward(k: Dictionary, total: float) -> void:
	var extra := ""
	if k.has("dark"):
		extra = " · пыль ×2,5"
	elif k.has("ice"):
		stage.moon_prog += 0.15
		extra = " · лёд пошёл на луну"
	elif float(k["mass"]) > 1.3:
		GameState.add_chondrules(1, stage.body.position)
		extra = " · хондры +1"
	if GameState.body_type() == "chondrite" and _rng.randf() < 0.25:
		GameState.add_chondrules(1, stage.body.position)
	stage.hud.toast("Всасываешь %s: +%s масс Земли%s" % [k["name"], String.num(total, 1).replace(".", ","), extra], (k["col"] as Color).lerp(Color.WHITE, 0.4))


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
var _views: Array = []   # MoonView для крупных тел и кусков
var _used := 0
const MAT_STYLE := {"rock": 0, "metal": 4, "ice": 1, "carbon": 3}


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
		var r := clampf(orbit + dx, GameData.GIANT_STAR_R * 1.3, GameData.GIANT_DISK.y - 700.0)
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
	_used = 0
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
			if rad / px > 3.5:
				_view(c, rad, int(MAT_STYLE[b.mat]), light_dir, float(b.seed) + float(part[1]), heat)
			else:
				_ball(c, rad, col.lerp(Color(1.0, 0.55, 0.25), heat * 0.8), light_dir)
			if heat > 0.0:
				draw_circle(c, rad * (1.3 + heat), Color(1.0, 0.6, 0.3, 0.25 * heat))
		if float(b.pull) < 0.0 and b.kind == "embryo":
			# У зародыша своя пыльная дымка: видно, что это не камешек.
			var ec := Vector2.from_angle(float(b.a)) * float(b.r)
			for j in 6:
				var f := float(j) / 6.0
				draw_circle(ec, size * (1.2 + 1.2 * f), Color(col, 0.025 * (1.0 - f)))
	for j in range(_used, _views.size()):
		(_views[j] as MoonView).visible = false
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


## Крупное тело шейдером: кратеры, лёд, железо — по веществу.
func _view(c: Vector2, rad: float, style: int, light: Vector2, seed_v: float, heat: float) -> void:
	if _used >= _views.size():
		var v := MoonView.new()
		add_child(v)
		_views.append(v)
	var view: MoonView = _views[_used]
	_used += 1
	view.put(c, rad, style, light, fmod(seed_v, 10.0), _time * 0.3 + seed_v, 1.0, heat, 1.0)
