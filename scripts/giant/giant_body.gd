extends Node2D
## Гигант на этапе газа: сам шар (gas_giant.gdshader), свой диск вокруг
## (giant_cpd.gdshader), потоки газа из щели и луны.
##
## Потоки считаются честно, в задаче Хилла: во вращающейся вместе с гигантом
## системе газ течёт мимо по сдвигу, гравитация гиганта разворачивает его в
## подковы, а ближние струи закручивает и роняет в свой диск.
## Единица длины потоков — видимый радиус Хилла (hill), время — оборот газа.

const GIANT_SHADER := preload("res://shaders/gas_giant.gdshader")
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
	_planet_mat.set_shader_parameter("ring_k", 0.0)
	_planet_mat.set_shader_parameter("ambient", 0.22)
	_planet_mat.set_shader_parameter("tilt", 0.18)
	_planet_mat.set_shader_parameter("spin_speed", 0.03)
	_planet_mat.set_shader_parameter("light_dir", Vector2(-1.0, -0.15))
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
	_planet_mat.set_shader_parameter("band_light", (look[0] as Color).lerp(burn[0], hot))
	_planet_mat.set_shader_parameter("band_dark", (look[1] as Color).lerp(burn[1], hot))
	_planet_mat.set_shader_parameter("storm_col", (look[2] as Color).lerp(burn[2], hot))


## Струя газа упала в свой диск: он вспыхивает.
func flash() -> void:
	_cpd_flash = minf(_cpd_flash + 0.08, 1.0)


func _process(delta: float) -> void:
	_time += delta
	_cpd_flash = maxf(_cpd_flash - delta * 0.8, 0.0)
	var r := body_r * inflate
	var q := r * 2.0 / 0.68  # тело — BODY (0.34) высоты квада
	_planet.size = Vector2(q, q)
	_planet.position = -_planet.size * 0.5
	_planet_mat.set_shader_parameter("aurora", field)
	_planet_mat.set_shader_parameter("heat", clampf(flow * 0.8 + _cpd_flash * 0.5, 0.0, 1.0))
	var cr := hill * 0.95
	_cpd.size = Vector2(cr, cr) * 2.0
	_cpd.position = -_cpd.size * 0.5
	# Полость поля: от поверхности гиганта и шире с полем.
	_cpd_mat.set_shader_parameter("inner", clampf(r / cr * (1.05 + 0.6 * field), 0.2, 0.75))
	_cpd_mat.set_shader_parameter("glow", clampf(0.25 + flow * 0.6 + _cpd_flash, 0.0, 1.4))
	_cpd_mat.set_shader_parameter("field", field)
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
		return


func _draw_streams() -> void:
	var w := 2.4 / maxf(zoom, 0.01)
	for t in _trail:
		var n := t.size()
		if n < 2:
			continue
		var head := t[n - 1]
		var near := clampf(1.0 - head.length() / (hill * 2.5), 0.0, 1.0)
		near *= near
		var col := Color(1.0, 0.7 + 0.25 * near, 0.4 + 0.45 * near)
		var a := 0.05 + 0.55 * near
		for k in range(1, n):
			var f := float(k) / (n - 1)
			_streams.draw_line(t[k - 1], t[k], Color(col, a * f), w * (0.4 + 0.8 * f), true)
		_streams.draw_circle(head, w * (0.6 + 0.6 * near), Color(col, a))


func _draw_moons(ci: Node2D) -> void:
	var r := body_r * inflate
	for i in moons:
		var a := r * (1.55 + 0.55 * i)
		var w := 0.9 * pow(a / r, -1.5)
		var ang := _time * w + i * 2.1
		var p := Vector2(cos(ang), sin(ang)) * a
		var mr := r * (0.085 + 0.025 * (i % 3))
		ci.draw_arc(Vector2.ZERO, a, 0.0, TAU, 96, Color(0.75, 0.85, 1.0, 0.07), 1.2 / maxf(zoom, 0.01), true)
		ci.draw_circle(p, mr * 2.2, Color(0.8, 0.9, 1.0, 0.06))
		var cols := [Color(0.95, 0.82, 0.45), Color(0.86, 0.84, 0.8), Color(0.62, 0.58, 0.54), Color(0.5, 0.46, 0.44)]
		ci.draw_circle(p, mr, cols[i % cols.size()])
		# Ночная сторона: от звезды (слева) отвёрнута вправо.
		ci.draw_circle(p + Vector2(mr * 0.35, 0.0), mr * 0.82, Color(0.02, 0.02, 0.05, 0.55))


static func moon_name(i: int) -> String:
	return MOON_NAMES[i % MOON_NAMES.size()]
