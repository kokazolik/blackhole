class_name GasParticles
extends MultiMeshInstance2D
## Газ вокруг гиганта частицами: и фоновые струи, и сгустки, которые можно всосать.
##
## Каждая частица летит в задаче Хилла (как настоящий газ во вращающейся вместе
## с гигантом системе): сдвиговое течение диска, кориолис и гравитация гиганта.
## Поэтому сгусток сам вытягивается приливом в струю, огибает гиганта подковой,
## если прошёл далеко, или закручивается в свой диск и падает, если близко.
## Никакой анимации «сжатия»: форма — следствие физики.
##
## Рисуется одним вызовом: MultiMesh мягких спрайтов, вытянутых по скорости.
## Координаты частиц в радиусах Хилла, ось y — против экранной (как в body).

signal particle_eaten(clump: int)

const MAX := 700
const OMEGA := 0.35          # темп течения газа, 1/с в единицах задачи Хилла
const CAPTURE := 0.42        # ближе — газ упал в свой диск
const FLOATS := 12           # 8 на Transform2D + 4 на цвет

var hill := 440.0
var reach := 1.0
var sigma_at: Callable       # плотность газа по смещению от орбиты в радиусах Хилла
var flow := 0.5

var px := PackedFloat32Array()
var py := PackedFloat32Array()
var vx := PackedFloat32Array()
var vy := PackedFloat32Array()
var sz := PackedFloat32Array()     # размер в радиусах Хилла
var al := PackedFloat32Array()     # непрозрачность
var cid := PackedInt32Array()      # номер сгустка, −1 — фоновая струя
var fade := PackedFloat32Array()   # 1 — живая, падает к 0, когда частица села в диск
var cols: Array[Color] = []
var n := 0
var _buf := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()
var _spawn_acc := 0.0


func _ready() -> void:
	_rng.randomize()
	for arr in [px, py, vx, vy, sz, al, fade]:
		arr.resize(MAX)
	cid.resize(MAX)
	cols.resize(MAX)
	_buf.resize(MAX * FLOATS)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	mm.mesh = quad
	mm.instance_count = MAX
	mm.visible_instance_count = 0
	multimesh = mm
	# Мягкое пятно: гауссов спад, без жёсткого края.
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.55))
	g.add_point(0.7, Color(1, 1, 1, 0.12))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	texture = tex


func _add(x: float, y: float, ux: float, uy: float, size: float, alpha: float, c: Color, clump: int) -> void:
	if n >= MAX:
		return
	px[n] = x
	py[n] = y
	vx[n] = ux
	vy[n] = uy
	sz[n] = size
	al[n] = alpha
	cid[n] = clump
	fade[n] = 1.0
	cols[n] = c
	n += 1


func _remove(i: int) -> void:
	n -= 1
	if i == n:
		return
	px[i] = px[n]
	py[i] = py[n]
	vx[i] = vx[n]
	vy[i] = vy[n]
	sz[i] = sz[n]
	al[i] = al[n]
	cid[i] = cid[n]
	fade[i] = fade[n]
	cols[i] = cols[n]


## Гигант сдвинулся на d (в его же координатах): газ остаётся на месте в диске.
func shift(d: Vector2) -> void:
	var dx := d.x / hill
	var dy := -d.y / hill
	for i in n:
		px[i] -= dx
		py[i] -= dy


## Сгусток: облако частиц с центром (x, y), течёт по сдвигу.
func spawn_clump(id: int, x: float, y: float, radius: float, count: int, c: Color) -> void:
	for k in count:
		var a := _rng.randf() * TAU
		var rr := radius * sqrt(-2.0 * log(maxf(_rng.randf(), 1e-4))) * 0.5
		var ox := cos(a) * rr * 0.75
		var oy := sin(a) * rr * 1.3   # сдвиг уже вытянул его вдоль орбиты
		var x0 := x + ox
		var cc := c.lerp(c.lightened(0.25), _rng.randf() * 0.5)
		_add(x0, y + oy, _rng.randf_range(-0.03, 0.03), -1.5 * x0 + _rng.randf_range(-0.03, 0.03),
			radius * _rng.randf_range(0.45, 0.9), _rng.randf_range(0.10, 0.2), cc, id)


## Центр сгустка (по живым частицам), в радиусах Хилла; Vector2.INF — сгустка нет.
func clump_center(id: int) -> Vector2:
	var s := Vector2.ZERO
	var k := 0
	for i in n:
		if cid[i] == id and fade[i] >= 1.0:
			s += Vector2(px[i], py[i])
			k += 1
	return s / k if k > 0 else Vector2.INF


func count_of(id: int) -> int:
	var k := 0
	for i in n:
		if cid[i] == id:
			k += 1
	return k


func step(delta: float) -> void:
	# Фоновые струи: чем гуще газ и сильнее аккреция, тем их больше.
	_spawn_acc += delta * (6.0 + 50.0 * flow)
	var streams := 0
	for i in n:
		if cid[i] < 0:
			streams += 1
	while _spawn_acc >= 1.0:
		_spawn_acc -= 1.0
		if streams < 260:
			_spawn_stream()
			streams += 1
	var dt := delta * OMEGA
	var steps := maxi(1, ceili(dt / 0.02))
	var h := dt / steps
	var g := 3.0 * reach * reach * reach   # «Длинные руки» шире сфера Хилла
	var cap2 := CAPTURE * CAPTURE
	var i := n - 1
	while i >= 0:
		if fade[i] < 1.0:
			fade[i] -= delta * 3.0
			if fade[i] <= 0.0:
				_remove(i)
			i -= 1
			continue
		var x := px[i]
		var y := py[i]
		var ux := vx[i]
		var uy := vy[i]
		var gone := false
		for k in steps:
			var d2 := x * x + y * y + 0.02
			var inv := g / (d2 * sqrt(d2))
			var ax := 2.0 * uy + 3.0 * x - inv * x
			var ay := -2.0 * ux - inv * y
			ux += ax * h
			uy += ay * h
			# У самого гиганта газ трётся о свой диск и оседает по спирали.
			if d2 < 1.0:
				var damp := 1.0 - 1.4 * h
				ux *= damp
				uy *= damp
			x += ux * h
			y += uy * h
			if d2 < cap2:
				gone = true
				break
		px[i] = x
		py[i] = y
		vx[i] = ux
		vy[i] = uy
		if gone:
			fade[i] = 0.99
			if cid[i] >= 0:
				particle_eaten.emit(cid[i])
		elif absf(y) > 9.0 or absf(x) > 7.0:
			_remove(i)
		i -= 1
	_upload()


func _spawn_stream() -> void:
	# Газ приходит по сдвигу: внутренний догоняет снизу, внешний набегает сверху.
	for attempt in 6:
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		var x := side * _rng.randf_range(0.6, 2.6) * reach
		if sigma_at.is_valid() and _rng.randf() > clampf(sigma_at.call(x), 0.0, 1.5) / 1.5:
			continue
		var y := 6.5 * side + _rng.randf_range(-0.5, 0.5)
		_add(x, y, 0.0, -1.5 * x, _rng.randf_range(0.03, 0.06), _rng.randf_range(0.5, 0.9), Color(0.9, 0.8, 0.68), -1)
		return


## Буфер MultiMesh одним присвоением: поворот по скорости, вытягивание по ней же.
func _upload() -> void:
	var b := _buf
	for i in n:
		var x := px[i]
		var y := py[i]
		var ux := vx[i]
		var uy := -vy[i]
		var sp := sqrt(ux * ux + uy * uy) + 1e-5
		var d := sqrt(x * x + y * y)
		var near := clampf(1.0 - d / 2.5, 0.0, 1.0)
		var w := sz[i] * hill
		var stretch := 1.0 + minf(sp * 0.9, 5.0) * (0.4 if cid[i] >= 0 else 1.6)
		var l := w * stretch
		var cx := ux / sp
		var cy := uy / sp
		var o := i * FLOATS
		b[o] = cx * l
		b[o + 1] = -cy * w
		b[o + 2] = 0.0
		b[o + 3] = x * hill
		b[o + 4] = cy * l
		b[o + 5] = cx * w
		b[o + 6] = 0.0
		b[o + 7] = -y * hill
		var c := cols[i]
		# Сжатый у гиганта газ греется: тёплый оттенок и ярче.
		var heat := near * near
		var a := al[i] * clampf(fade[i], 0.0, 1.0)
		if cid[i] < 0:
			a *= 0.05 + 0.25 * heat
		else:
			a *= 1.0 + 0.6 * heat
		b[o + 8] = lerpf(c.r, 1.0, heat * 0.35)
		b[o + 9] = lerpf(c.g, 0.82, heat * 0.35)
		b[o + 10] = lerpf(c.b, 0.6, heat * 0.35)
		b[o + 11] = a
	multimesh.visible_instance_count = n
	if n > 0:
		multimesh.buffer = b
