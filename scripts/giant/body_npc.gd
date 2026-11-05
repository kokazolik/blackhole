class_name BodyNpc
extends RefCounted
## Тела мира гиганта живут своей жизнью (автор: «как NPC, которые идут по
## своим делам»). Орбит нет: каждое тело само выбирает, куда плыть.
##
## - Охотники (зародыш, суперземля, мини-нептун, ледяной карлик) ищут мелочь
##   легче четверти себя и съедают её: растут у тебя на глазах.
## - Мелочь (обломки, планетезимали, двойные, железные ядра, троянцы) бродит
##   и уходит от тех, кто может её съесть, — от охотников и от тебя.
## - Вещество выбирает свой край диска: лёд и титан тянутся за снеговую
##   линию, камень, железо, лава и венера — к теплу, углерод и хондрит где угодно.
## - Соперник-гигант охотится на тела, тяжелее тебя — занят своим, легче — уходит.
##
## Тяга у тел слабая: их легко сбить с курса тяготением, а газ гасит рывки.

const HUNTERS := ["embryo", "superearth", "minineptune", "icedwarf"]
const SPEED := {"rubble": 70.0, "planetesimal": 60.0, "binary": 55.0, "irondwarf": 50.0,
	"icedwarf": 48.0, "embryo": 45.0, "superearth": 36.0, "minineptune": 30.0, "trojan": 50.0}
const MAT_SPEED := {"metal": 0.85, "ice": 1.1, "lava": 0.95}
const RIVAL_SPEED := 170.0
const RIVAL_ACC := 55.0


static func speed_of(b: Dictionary) -> float:
	return float(SPEED.get(b.kind, 45.0)) * float(MAT_SPEED.get(b.mat, 1.0))


## Свой край диска по веществу: [r_min, r_max].
static func zone_of(b: Dictionary) -> Vector2:
	var m: String = b.get("sub", b.mat)
	match m:
		"ice", "titan":
			return Vector2(GameData.SNOW_LINE - 400.0, GameData.GIANT_DISK.y - 1500.0)
		"metal", "rock", "lava", "venus":
			return Vector2(GameData.HOT_ORBIT * 0.7, GameData.SNOW_LINE + 600.0)
	return Vector2(GameData.HOT_ORBIT * 0.7, GameData.GIANT_DISK.y - 1500.0)


## Шаг свободного тела: решить, куда плыть, и подправить дрейф.
static func step(w, b: Dictionary, delta: float, gpos: Vector2) -> void:
	if b.kind in ["comet", "rival", "dwarf"]:
		return
	var p: Vector2 = w.pos_of(b)
	b["think"] = float(b.get("think", 0.0)) - delta
	if float(b.think) <= 0.0:
		b.think = w._rng.randf_range(1.0, 2.2)
		_decide(w, b, p, gpos)
	var want := Vector2.ZERO
	var sp := speed_of(b)
	match str(b.get("do", "wander")):
		"hunt":
			var t: Dictionary = w._body_by_id(int(b.get("prey", -1)))
			if t.is_empty() or t.state != "free":
				b.do = "wander"
				b.think = 0.0
			else:
				var tp: Vector2 = w.pos_of(t)
				var d := tp.distance_to(p)
				want = (tp - p) / maxf(d, 1.0) * sp * 1.3
				if d < (w.rad_of(b) + w.rad_of(t)) * 0.9:
					_eat(w, b, t)
		"flee":
			var from: Vector2 = b.get("from", gpos)
			want = (p - from).normalized() * sp * 1.4
		_:
			var goal: Vector2 = b.get("goal", p)
			var d := goal.distance_to(p)
			if d < 150.0:
				b.think = 0.0
			want = (goal - p) / maxf(d, 1.0) * sp * smoothstep(0.0, 400.0, d)
	var dr: Vector2 = b.get("drift", Vector2.ZERO)
	b["drift"] = dr.move_toward(want, sp * 0.6 * delta)


static func _decide(w, b: Dictionary, p: Vector2, gpos: Vector2) -> void:
	var m := float(b.m)
	# Кто рядом может меня съесть: ты (если я тебе еда) или охотник.
	var h: float = w.stage.hill()
	if p.distance_to(gpos) < 4.5 * h and w.role(b) == "food":
		b.do = "flee"
		b["from"] = gpos
		return
	var best := {}
	var bd := INF
	var threat := {}
	var td := INF
	for o in w.bodies:
		if o == b or o.state != "free" or o.kind in ["comet"]:
			continue
		var op: Vector2 = w.pos_of(o)
		var d := op.distance_to(p)
		if d > 2200.0:
			continue
		var om := float(o.m)
		if (o.kind in HUNTERS or o.kind == "rival") and om > m * 4.0 and d < 900.0 and d < td:
			td = d
			threat = o
		elif b.kind in HUNTERS and om < m * 0.25 and not o.kind in ["rival", "dwarf"] and d < bd:
			bd = d
			best = o
	if not threat.is_empty():
		b.do = "flee"
		b["from"] = w.pos_of(threat)
		return
	if not best.is_empty():
		b.do = "hunt"
		b["prey"] = int(best.id)
		return
	b.do = "wander"
	if not b.has("goal") or (b.goal as Vector2).distance_to(p) < 200.0 or w._rng.randf() < 0.15:
		var z := zone_of(b)
		var g: Vector2 = p + Vector2.from_angle(w._rng.randf() * TAU) * w._rng.randf_range(800.0, 2600.0)
		var r := clampf(g.length(), z.x, z.y)
		b["goal"] = g.normalized() * r


static func _eat(w, b: Dictionary, t: Dictionary) -> void:
	b.m = float(b.m) + float(t.m) * 0.9
	t.state = "rival_eat"
	t.t = 0.0
	t["host"] = b.id
	b.do = "wander"
	b.think = 0.5


## Соперник-гигант: охотится на тела, а от тебя уходит, если ты тяжелее.
static func step_rival(w, b: Dictionary, delta: float, gpos: Vector2) -> void:
	var p: Vector2 = w.pos_of(b)
	b["think"] = float(b.get("think", 0.0)) - delta
	if float(b.think) <= 0.0:
		b.think = w._rng.randf_range(1.5, 3.0)
		var e: float = w.stage.earths
		var d := p.distance_to(gpos)
		if e > float(b.m) * 1.15 and d < 7000.0:
			b.do = "flee"
		else:
			var best := {}
			var bd := INF
			for o in w.bodies:
				if o == b or o.state != "free" or o.kind in ["rival", "dwarf"]:
					continue
				var dd: float = (w.pos_of(o) as Vector2).distance_to(p)
				if dd < 4000.0 and float(o.m) < float(b.m) * 0.1 and dd / sqrt(float(o.m) + 0.01) < bd:
					bd = dd / sqrt(float(o.m) + 0.01)
					best = o
			if not best.is_empty() and (w.pos_of(best) as Vector2).distance_to(gpos) > 6000.0:
				b.do = "hunt"
				b["prey"] = int(best.id)
			else:
				b.do = "wander"
				# Занят своим: бродит, но не к тебе — сближение решаешь ты.
				var dir := Vector2.from_angle(w._rng.randf() * TAU)
				if dir.dot(gpos - p) > 0.0 and d < 12000.0:
					dir = -dir
				var g: Vector2 = p + dir * 3000.0
				b["goal"] = g.normalized() * clampf(g.length(), GameData.HOT_ORBIT, GameData.GIANT_DISK.y - 2000.0)
	var want := Vector2.ZERO
	match str(b.get("do", "wander")):
		"flee":
			want = (p - gpos).normalized() * RIVAL_SPEED
		"hunt":
			var t: Dictionary = w._body_by_id(int(b.get("prey", -1)))
			if t.is_empty() or t.state != "free":
				b.think = 0.0
			else:
				want = ((w.pos_of(t) as Vector2) - p).normalized() * RIVAL_SPEED
		_:
			var goal: Vector2 = b.get("goal", p)
			want = (goal - p).limit_length(RIVAL_SPEED)
	var v: Vector2 = b.get("v", Vector2.ZERO)
	# Тяга слабая: тяготение тебя и удары сильнее её.
	b["v"] = v + (want - v).limit_length(RIVAL_ACC * delta)
