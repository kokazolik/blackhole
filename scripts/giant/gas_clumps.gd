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


func _spawn(k: Dictionary, gas: GasParticles) -> void:
	var h: float = stage.hill()
	var orbit: float = stage.orbit
	for attempt in 6:
		# Сгустки рождаются в 2,6–4 радиусах Хилла: издалека тяготение тянет
		# газ еле-еле, подлетишь — стечёт к тебе за секунды. «Длинные руки»
		# усиливают тяготение (g ∝ reach³), и дальние сгустки текут сами.
		var off := _rng.randf_range(2.6, 4.0)
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
		# Сгусток лежит в стороне, в любом направлении: орбит нет, его
		# никуда не несёт — подлетай, и тяготение стянет газ к тебе.
		var y := _rng.randf_range(-1.0, 1.0) * off * 1.2
		var id := _next_id
		_next_id += 1
		var count := PARTS if k["mass"] < 1.3 else PARTS + 14
		var gain: float = maxf(stage.clump_gain(s) * float(k["mass"]) * SECONDS, 0.05)
		# Смешанное ядро (хондрит, переходное) тянет газ любого сорта: сгустки
		# ему жирнее — иначе оно отстаёт от специализаций (баланс по ботам).
		if GameState.body_type() in ["chondrite", "neutral"]:
			gain *= 1.15
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
