extends Node2D
## Гигант на этапе газа: сам шар (giant_planet.gdshader), свой диск вокруг
## (giant_cpd.gdshader), потоки газа из щели и луны.
##
## Потоки считаются честно, в задаче Хилла: во вращающейся вместе с гигантом
## системе газ течёт мимо по сдвигу, гравитация гиганта разворачивает его в
## подковы, а ближние струи закручивает и роняет в свой диск.
## Единица длины потоков — видимый радиус Хилла (hill), время — оборот газа.

const GIANT_SHADER := preload("res://shaders/giant_planet.gdshader")
const CPD_SHADER := preload("res://shaders/giant_cpd.gdshader")
const OMEGA := 0.55          # как быстро течёт газ в единицах задачи Хилла, 1/с
const STREAM_MAX := 240
const TRAIL := 7
const CAPTURE := 0.45        # ближе — газ упал в свой диск
const MOON_NAMES := ["Ио", "Европа", "Ганимед", "Каллисто", "Амальтея", "Фемисто"]

var body_r := 200.0
var hill := 440.0
var reach := 1.0
var inflate := 1.0           # раздувание оболочки на входе в этап
var flow := 0.5              # сколько газа падает сейчас, 0..1
var field := 0.3
var moons := 0
var zoom := 0.3
var sigma_at: Callable       # плотность газа по смещению от орбиты в радиусах Хилла
var captured := 0            # сколько струй упало с прошлого опроса

var _planet := ColorRect.new()
var _cpd := ColorRect.new()
var _streams := Node2D.new()
var _planet_mat := ShaderMaterial.new()
var _cpd_mat := ShaderMaterial.new()
var _pos: Array[Vector2] = []
var _vel: Array[Vector2] = []
var _trail: Array[PackedVector2Array] = []
var _bri: Array[float] = []          # струи всосанных сгустков ярче фоновых
var _birth := {}                      # луна -> {t, from}: рождение или захват на глазах
var _falling: Array = []              # луны, что падают в гиганта
var _impacts: Array = []
var _spawn_acc := 0.0
var _time := 0.0
var _cpd_flash := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_cpd_mat.shader = CPD_SHADER
	_cpd.material = _cpd_mat
	_cpd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cpd)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_streams.material = add
	_streams.draw.connect(_draw_streams)
	add_child(_streams)
	_planet_mat.shader = GIANT_SHADER
	_planet_mat.set_shader_parameter("light_dir", Vector2(-1.0, -0.12))
	_planet_mat.set_shader_parameter("seed", _rng.randf())
	_planet.material = _planet_mat
	_planet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_planet)
	var moons_layer := Node2D.new()
	moons_layer.draw.connect(_draw_moons.bind(moons_layer))
	moons_layer.set_meta("moons", true)
	add_child(moons_layer)


## Цвета полос по ядру; у самой звезды (hot до 1) облака раскаляются.
func set_look(flavor: String, hot := 0.0) -> void:
	var look: Array = GameData.GIANT_LOOK.get(flavor, GameData.GIANT_LOOK["giant_cold"])
	var burn: Array = GameData.GIANT_LOOK["giant_hot"]
	_planet_mat.set_shader_parameter("zone_col", _muted((look[0] as Color).lerp(burn[0], hot * 0.6), 0.35))
	_planet_mat.set_shader_parameter("belt_col", _muted((look[1] as Color).lerp(burn[1], hot * 0.6), 0.3))
	_planet_mat.set_shader_parameter("storm_col", _muted((look[2] as Color).lerp(burn[2], hot * 0.6), 0.2))
	_planet_mat.set_shader_parameter("heat", hot)


## Природные облака не бывают кричащими: цвет наполовину к своей яркости.
static func _muted(c: Color, k: float) -> Color:
	var l := c.r * 0.3 + c.g * 0.55 + c.b * 0.15
	return c.lerp(Color(l, l, l), k)


## Струя газа упала в свой диск: он вспыхивает.
func flash() -> void:
	_cpd_flash = minf(_cpd_flash + 0.08, 1.0)


func _process(delta: float) -> void:
	_time += delta
	_cpd_flash = maxf(_cpd_flash - delta * 0.8, 0.0)
	var r := body_r * inflate
	var q := r * 2.0 / 0.72  # тело — BODY (0.36) ширины квада
	_planet.size = Vector2(q, q)
	_planet.position = -_planet.size * 0.5
	_planet_mat.set_shader_parameter("aurora", field)
	_planet_mat.set_shader_parameter("churn", clampf(flow + _cpd_flash * 0.5, 0.0, 1.0))
	_planet_mat.set_shader_parameter("spin", _time * 0.12)  # оборот меньше чем за минуту: вращение видно
	var cr := hill * 0.95
	_cpd.size = Vector2(cr, cr) * 2.0
	_cpd.position = -_cpd.size * 0.5
	# Полость поля: от поверхности гиганта и шире с полем.
	_cpd_mat.set_shader_parameter("inner", clampf(r / cr * (1.05 + 0.6 * field), 0.2, 0.75))
	_cpd_mat.set_shader_parameter("glow", clampf(0.25 + flow * 0.6 + _cpd_flash, 0.0, 1.4))
	_cpd_mat.set_shader_parameter("field", field)
	for i in _birth.keys():
		_birth[i].t = float(_birth[i].t) + delta / 4.0
		if float(_birth[i].t) >= 1.0:
			_birth.erase(i)
	var keep := []
	for f in _falling:
		f.t = float(f.t) + delta / 3.0
		if f.t >= 1.0:
			var an := float(f.ang) + _time * 0.9 + 4.0
			_impacts.append({"t": 0.0, "p": Vector2(cos(an), sin(an)) * r * 0.95})
			flash()
		else:
			keep.append(f)
	_falling = keep
	var ik := []
	for im in _impacts:
		im.t = float(im.t) + delta / 1.2
		if im.t < 1.0:
			ik.append(im)
	_impacts = ik
	_step_streams(delta)
	_streams.queue_redraw()
	for c in get_children():
		if c.has_meta("moons"):
			c.queue_redraw()


func _step_streams(delta: float) -> void:
	# Новые струи: чем гуще газ и сильнее аккреция, тем их больше.
	_spawn_acc += delta * (4.0 + 60.0 * flow)
	while _spawn_acc >= 1.0 and _pos.size() < STREAM_MAX:
		_spawn_acc -= 1.0
		_spawn()
	_spawn_acc = minf(_spawn_acc, 1.0)
	var dt := delta * OMEGA
	var steps := maxi(1, ceili(dt / 0.012))
	var h := dt / steps
	var i := _pos.size() - 1
	while i >= 0:
		var p := _pos[i]
		var v := _vel[i]
		var gone := false
		for k in steps:
			var d2 := p.length_squared() + 0.02
			var inv := 3.0 / (d2 * sqrt(d2))
			var a := Vector2(2.0 * v.y + 3.0 * p.x - inv * p.x, -2.0 * v.x - inv * p.y)
			v += a * h
			# У самого гиганта газ трётся о свой диск и оседает по спирали.
			if d2 < 1.0:
				v *= 1.0 - 1.6 * h
			p += v * h
			if p.length() < CAPTURE:
				gone = true
				captured += 1
				flash()
				break
		if not gone and (absf(p.y) > 7.5 or absf(p.x) > 5.0):
			gone = true
		if gone:
			_pos.remove_at(i)
			_vel.remove_at(i)
			_trail.remove_at(i)
			_bri.remove_at(i)
		else:
			_pos[i] = p
			_vel[i] = v
			var t := _trail[i]
			t.append(Vector2(p.x, -p.y) * hill)
			if t.size() > TRAIL:
				t.remove_at(0)
			_trail[i] = t
		i -= 1


func _spawn() -> void:
	# Газ приходит по сдвигу: внутренний догоняет сзади, внешний набегает спереди.
	for attempt in 6:
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		var x := side * _rng.randf_range(0.6, 2.6) * reach
		if sigma_at.is_valid() and _rng.randf() > clampf(sigma_at.call(x), 0.0, 1.5) / 1.5:
			continue
		var y := 6.5 * side + _rng.randf_range(-0.5, 0.5)
		_pos.append(Vector2(x, y))
		_vel.append(Vector2(0.0, -1.5 * x))
		_trail.append(PackedVector2Array([Vector2(x, -y) * hill]))
		_bri.append(0.0)
		return


## Струя всосанного газа: из точки local (в координатах гиганта) по спирали в свой диск.
func inject(local: Vector2) -> void:
	if _pos.size() >= STREAM_MAX + 80:
		return
	var p := Vector2(local.x, -local.y) / maxf(hill, 1.0)
	p += Vector2(_rng.randf_range(-0.12, 0.12), _rng.randf_range(-0.12, 0.12))
	var v := -p.normalized() * _rng.randf_range(0.6, 1.1) + Vector2(0.0, -1.5 * p.x) * 0.3
	_pos.append(p)
	_vel.append(v)
	_trail.append(PackedVector2Array([Vector2(p.x, -p.y) * hill]))
	_bri.append(1.0)


## Новая луна собирается на глазах: из пыли своего диска или из захваченного тела.
func birth(i: int, from := Vector2.INF) -> void:
	_birth[i] = {"t": 0.0, "from": from}


## Лишняя луна падает в гиганта по спирали.
func fall() -> void:
	var r := body_r * inflate
	_falling.append({"t": 0.0, "a": r * (1.55 + 0.55 * moons), "ang": _rng.randf() * TAU})


func _draw_streams() -> void:
	# Струи почти прозрачны: это разреженный газ, видный лишь в отражённом
	# свете. Заметнее там, где поток сгущается у самого гиганта, и в струях
	# всосанных сгустков.
	var w := 1.3 / maxf(zoom, 0.01)
	for j in _trail.size():
		var t := _trail[j]
		var n := t.size()
		if n < 2:
			continue
		var head := t[n - 1]
		var near := clampf(1.0 - head.length() / (hill * 2.5), 0.0, 1.0)
		near *= near
		var bi := _bri[j]
		var col := Color(0.85, 0.74 + 0.1 * near, 0.62 + 0.15 * near).lerp(Color(1.0, 0.8, 0.6), bi * 0.5)
		var a := 0.03 + 0.14 * near + 0.22 * bi
		for k in range(1, n):
			var f := float(k) / (n - 1)
			_streams.draw_line(t[k - 1], t[k], Color(col, a * f * f), w * (0.6 + 0.6 * f + 0.8 * bi), true)


func _moon_ball(ci: Node2D, p: Vector2, mr: float, c: Color, shadow: float) -> void:
	# Шар: освещённая сторона к звезде (влево), мягкий терминатор.
	var steps := 10
	for k in steps:
		var f := float(k) / steps
		var rr := mr * (1.0 - f * 0.85)
		var off := Vector2(-mr * 0.5 * f, -mr * 0.06 * f)
		var lum := (0.06 + 0.94 * pow(f, 0.7)) * shadow
		ci.draw_circle(p + off, rr, Color(c.r * lum, c.g * lum, c.b * lum))
	ci.draw_arc(p, mr, PI * 0.55, PI * 1.45, 24, Color(0.7, 0.8, 1.0, 0.18 * shadow), mr * 0.12, true)


func _draw_moons(ci: Node2D) -> void:
	var r := body_r * inflate
	var px := 1.0 / maxf(zoom, 0.01)
	var cols := [Color(0.78, 0.68, 0.42), Color(0.74, 0.72, 0.68), Color(0.5, 0.47, 0.44), Color(0.42, 0.39, 0.37)]
	for i in moons:
		var a := r * (1.55 + 0.55 * i)
		var w := 0.9 * pow(a / r, -1.5)
		var ang := _time * w + i * 2.1
		var p := Vector2(cos(ang), sin(ang)) * a
		var mr := maxf(r * (0.06 + 0.02 * (i % 3)), 2.0 * px)
		var c: Color = cols[i % cols.size()]
		var grow := 1.0
		if _birth.has(i):
			var b: Dictionary = _birth[i]
			var e := smoothstep(0.0, 1.0, float(b.t))
			var from: Vector2 = b.from
			if from.x == INF:
				# Пыль своего диска стягивается в комок: облачко по орбите сжимается в шар.
				for k in 28:
					var f := float(k) / 28.0
					var spread := (1.0 - e) * (0.4 + 2.2 * f)
					var aa := ang - spread * (0.3 + 0.7 * fmod(k * 0.618, 1.0))
					var rr := a * (1.0 + (1.0 - e) * 0.18 * sin(k * 2.3))
					ci.draw_circle(Vector2(cos(aa), sin(aa)) * rr, maxf(mr * (0.12 + 0.18 * (1.0 - f)), 0.8 * px), Color(c.lightened(0.2), 0.5 * (1.0 - e * 0.7)))
				grow = smoothstep(0.3, 1.0, e)
			else:
				# Захваченное тело подходит по дуге и садится на орбиту.
				var q := from.lerp(p, e)
				q += (p - from).orthogonal().normalized() * sin(e * PI) * from.distance_to(p) * 0.25
				for k in 10:
					var f := float(k + 1) / 10.0
					var ek := clampf(e - f * 0.15, 0.0, 1.0)
					var qk := from.lerp(p, ek) + (p - from).orthogonal().normalized() * sin(ek * PI) * from.distance_to(p) * 0.25
					ci.draw_circle(qk, mr * 0.35 * (1.0 - f), Color(0.8, 0.85, 1.0, 0.2 * (1.0 - f)))
				p = q
			ci.draw_arc(Vector2.ZERO, a, 0.0, TAU, 128, Color(0.75, 0.82, 0.95, 0.035 * e), px, true)
		else:
			ci.draw_arc(Vector2.ZERO, a, 0.0, TAU, 128, Color(0.75, 0.82, 0.95, 0.035), px, true)
		if grow <= 0.01:
			continue
		# Тень гиганта: луна за ним гаснет.
		var shadow := 1.0
		if p.x > 0.0 and absf(p.y) < r:
			shadow = 0.18 + 0.82 * smoothstep(r * 0.8, r, absf(p.y))
		_moon_ball(ci, p, mr * grow, c, shadow)
	# Падающие луны: спираль вниз, вспышка в облаках.
	for f in _falling:
		var e := smoothstep(0.0, 1.0, float(f.t))
		var a2: float = lerpf(float(f.a), r * 0.98, e)
		var an: float = float(f.ang) + _time * 0.9 * pow(a2 / r, -1.5) + e * 4.0
		var p2 := Vector2(cos(an), sin(an)) * a2
		var mr2 := r * 0.07 * (1.0 - 0.4 * e)
		for k in 8:
			var bk := float(k + 1) / 8.0
			var anb := an - bk * 0.35
			ci.draw_circle(Vector2(cos(anb), sin(anb)) * (a2 + bk * r * 0.05), mr2 * 0.4 * (1.0 - bk), Color(1.0, 0.7, 0.45, 0.3 * e * (1.0 - bk)))
		_moon_ball(ci, p2, mr2, Color(0.7, 0.66, 0.6).lerp(Color(1.0, 0.55, 0.25), smoothstep(0.6, 1.0, e)), 1.0)
	for im in _impacts:
		var k := 1.0 - float(im.t)
		ci.draw_circle(im.p, r * 0.08 * (1.0 + 2.0 * float(im.t)), Color(1.0, 0.75, 0.5, 0.5 * k * k))
		ci.draw_circle(im.p, r * 0.04, Color(1.0, 0.95, 0.85, 0.9 * k))


static func moon_name(i: int) -> String:
	return MOON_NAMES[i % MOON_NAMES.size()]
