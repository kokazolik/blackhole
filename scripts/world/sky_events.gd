extends Node2D
## Редкие события на фоне: кометы, падающие метеоры и вспышки далёких звёзд.
##
## Живёт в слое фона (координаты экрана) и рисуется только пока что-то летит,
## поэтому почти ничего не стоит. Хвост кометы, как в жизни, смотрит от звезды.

const COMET_INTERVAL := Vector2(35.0, 75.0)
const FIRST_COMET := Vector2(8.0, 15.0)
const METEOR_INTERVAL := Vector2(5.0, 14.0)
const FLARE_INTERVAL := Vector2(25.0, 50.0)
const PARALLAX := 0.12  # кометы далеко, сдвигаются чуть быстрее звёзд фона

var camera: Camera2D
var star_screen_pos := Vector2.ZERO  # задаёт main.gd, чтобы хвост смотрел от звезды
var _comets: Array = []
var _meteors: Array = []
var _flares: Array = []
var _comet_timer := 0.0
var _meteor_timer := 0.0
var _flare_timer := 0.0
var _last_cam := Vector2.ZERO
var _glow := _make_glow()


static func _make_glow() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.25, Color(1, 1, 1, 0.5))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	return tex


func _ready() -> void:
	_comet_timer = randf_range(FIRST_COMET.x, FIRST_COMET.y)
	_meteor_timer = randf_range(METEOR_INTERVAL.x, METEOR_INTERVAL.y)
	_flare_timer = randf_range(FLARE_INTERVAL.x, FLARE_INTERVAL.y)


func _process(delta: float) -> void:
	var size := get_viewport_rect().size
	var cam := camera.get_screen_center_position() * camera.zoom.x if camera else Vector2.ZERO
	var cam_shift := (cam - _last_cam) * PARALLAX
	_last_cam = cam
	if cam_shift.length() > 200.0:
		cam_shift = Vector2.ZERO  # скачок камеры (загрузка, сброс)

	_comet_timer -= delta
	if _comet_timer <= 0.0:
		_comet_timer = randf_range(COMET_INTERVAL.x, COMET_INTERVAL.y)
		_spawn_comet(size)
	_meteor_timer -= delta
	if _meteor_timer <= 0.0:
		_meteor_timer = randf_range(METEOR_INTERVAL.x, METEOR_INTERVAL.y)
		_spawn_meteor(size)
	_flare_timer -= delta
	if _flare_timer <= 0.0:
		_flare_timer = randf_range(FLARE_INTERVAL.x, FLARE_INTERVAL.y)
		_flares.append({"pos": Vector2(randf() * size.x, randf() * size.y), "t": 0.0, "life": randf_range(2.5, 4.0)})

	if _comets.is_empty() and _meteors.is_empty() and _flares.is_empty():
		return
	var bounds := Rect2(Vector2.ZERO, size).grow(400.0)
	for c in _comets:
		c.pos += c.vel * delta - cam_shift
		c.t += delta
	_comets = _comets.filter(func(c): return c.t < 3.0 or bounds.has_point(c.pos))
	for m in _meteors:
		m.t += delta
	_meteors = _meteors.filter(func(m): return m.t < m.life)
	for f in _flares:
		f.t += delta
		f.pos -= cam_shift * 0.5
	_flares = _flares.filter(func(f): return f.t < f.life)
	queue_redraw()


func _spawn_comet(size: Vector2) -> void:
	# Старт за краем экрана, курс через экран с разбросом.
	var center := size * 0.5
	var from_dir := Vector2.from_angle(randf() * TAU)
	var start := center + from_dir * (size.length() * 0.5 + 150.0)
	var target := center + Vector2(randf_range(-0.3, 0.3) * size.x, randf_range(-0.3, 0.3) * size.y)
	var vel := (target - start).normalized() * randf_range(35.0, 70.0)
	_comets.append({"pos": start, "vel": vel, "t": 0.0, "len": randf_range(120.0, 220.0), "size": randf_range(2.5, 4.0)})


func _spawn_meteor(size: Vector2) -> void:
	var start := Vector2(randf() * size.x, randf() * size.y * 0.7)
	var dir := Vector2.from_angle(randf_range(0.3, 1.2) * (1.0 if randf() < 0.5 else -1.0) + (0.0 if randf() < 0.5 else PI))
	_meteors.append({"pos": start, "dir": dir, "t": 0.0, "life": randf_range(0.5, 0.9), "speed": randf_range(500.0, 800.0)})


func _draw() -> void:
	for c in _comets:
		_draw_comet(c)
	for m in _meteors:
		var k: float = m.t / m.life
		var head: Vector2 = m.pos + m.dir * m.speed * m.t
		var tail_len := 90.0 * sin(k * PI)
		var tail: Vector2 = head - m.dir * tail_len
		var a := sin(k * PI)
		_draw_streak(tail, head, 1.6, Color(0.8, 0.9, 1.0, 0.0), Color(1.0, 1.0, 1.0, 0.8 * a))
		draw_texture_rect(_glow, Rect2(head - Vector2(6, 6), Vector2(12, 12)), false, Color(0.85, 0.92, 1.0, 0.6 * a))
	for f in _flares:
		# Далёкая звезда разгорается и гаснет, с четырьмя лучами.
		var k: float = f.t / f.life
		var a := sin(k * PI)
		var r := 3.0 + 10.0 * a
		draw_texture_rect(_glow, Rect2(f.pos - Vector2(r, r) * 2.0, Vector2(r, r) * 4.0), false, Color(0.8, 0.88, 1.0, 0.35 * a))
		var col := Color(0.9, 0.95, 1.0, 0.6 * a)
		draw_line(f.pos - Vector2(r * 2.5, 0), f.pos + Vector2(r * 2.5, 0), col, 1.0, true)
		draw_line(f.pos - Vector2(0, r * 2.5), f.pos + Vector2(0, r * 2.5), col, 1.0, true)
		draw_circle(f.pos, 1.5, Color(1, 1, 1, a))


func _draw_comet(c: Dictionary) -> void:
	var head: Vector2 = c.pos
	var fade := clampf(c.t / 2.0, 0.0, 1.0)
	var length: float = c.len
	var s: float = c.size
	# Хвост смотрит от звезды: ионный — прямой и голубой,
	# пылевой — шире, желтоватый и изгибается назад по курсу кометы.
	var away := (head - star_screen_pos).normalized()
	var back := -(c.vel as Vector2).normalized()
	var dust_end := head + (away + back * 0.7).normalized() * length
	var dust_ctrl := head + away * length * 0.5
	var dust_pts := PackedVector2Array()
	for i in 9:
		var t := i / 8.0
		dust_pts.append(head.lerp(dust_ctrl, t).lerp(dust_ctrl.lerp(dust_end, t), t))
	# Широкий бледный слой под основным смягчает края хвоста.
	_draw_tail(dust_pts, s * 2.5, length * 0.4, Color(1.0, 0.85, 0.6, 0.12 * fade), Color(1.0, 0.75, 0.5, 0.0))
	_draw_tail(dust_pts, s * 1.2, length * 0.22, Color(1.0, 0.88, 0.65, 0.35 * fade), Color(1.0, 0.75, 0.5, 0.0))
	var ion_pts := PackedVector2Array([head, head + away * length * 0.6, head + away * length * 1.3])
	_draw_tail(ion_pts, s * 0.8, length * 0.06, Color(0.6, 0.85, 1.0, 0.5 * fade), Color(0.4, 0.65, 1.0, 0.0))
	draw_texture_rect(_glow, Rect2(head - Vector2(s, s) * 6.0, Vector2(s, s) * 12.0), false, Color(0.75, 0.9, 1.0, 0.55 * fade))
	draw_circle(head, s * 0.6, Color(1, 1, 1, 0.95 * fade))


## Хвост вдоль ломаной: ширина и цвет плавно меняются от головы к концу.
## Контур собирается в один многоугольник, так что это один вызов отрисовки.
func _draw_tail(pts: PackedVector2Array, w0: float, w1: float, c0: Color, c1: Color) -> void:
	var n := pts.size()
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var lcol := PackedColorArray()
	var rcol := PackedColorArray()
	for i in n:
		var t := float(i) / (n - 1)
		var dir := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var off := dir.orthogonal() * lerpf(w0, w1, t) * 0.5
		var col := c0.lerp(c1, t)
		left.append(pts[i] + off)
		right.append(pts[i] - off)
		lcol.append(col)
		rcol.append(col)
	right.reverse()
	rcol.reverse()
	draw_polygon(left + right, lcol + rcol)


## Полоса, сужающаяся к хвосту, с плавным переходом цвета (один вызов отрисовки).
func _draw_streak(from: Vector2, to: Vector2, width: float, col_from: Color, col_to: Color) -> void:
	var dir := to - from
	if dir.length_squared() < 0.01:
		return
	var n := dir.normalized().orthogonal() * width * 0.5
	var pts := PackedVector2Array([from, to + n, to - n])
	var cols := PackedColorArray([col_from, col_to, col_to])
	draw_polygon(pts, cols)
