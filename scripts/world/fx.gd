class_name AbsorbFx
extends Node2D
## Анимация поглощения пыли. Пылинка касается поверхности, и в точке касания
## вспыхивает свет её материала. По краю комка в обе стороны бежит световая волна,
## а пара искр отскакивает по дуге и падает обратно на поверхность. Потом
## всплывает «+N». Свет рисуется сложением цветов (светится, а не закрашивает),
## текст обычным слоем. Рисуется только пока эффекты живы.

const FLASH_TIME := 0.35
const WAVE_TIME := 0.55
const MOTE_TIME := 0.5
const POPUP_TIME := 1.0
const MOTES_PER_ABSORB := 5
const LIMIT := 40  # на каждый вид эффекта, чтобы скопление не грузило кадр

var player: Player
var camera: Camera2D
var _hits: Array = []    # вспышка в точке касания и волна по краю
var _motes: Array = []   # искры, отскакивающие по дуге
var _popups: Array = []
var _light: Node2D       # слой света со сложением цветов
var _glow := _make_glow()


static func _make_glow() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.25, Color(1, 1, 1, 0.45))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	return tex


func _ready() -> void:
	_light = Node2D.new()
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_light.material = mat
	_light.draw.connect(_draw_light)
	add_child(_light)
	move_child(_light, 0)
	GameState.absorbed.connect(_on_absorbed)
	GameState.chipped.connect(_on_chipped)


## Сильный удар: вспышка в точке удара и всплывающая потеря массы.
func _on_chipped(at: Vector2, lost: float) -> void:
	var angle := (at - player.position).angle()
	if _hits.size() < LIMIT:
		_hits.append({"angle": angle, "color": Color(1.0, 0.55, 0.3), "t": 0.0})
	if _popups.size() >= LIMIT:
		_popups.pop_front()
	_popups.append({"pos": at, "text": "−%.1f массы" % lost, "color": Color(1.0, 0.5, 0.35), "t": 0.0, "drift": randf_range(-0.4, 0.4)})


func _on_absorbed(at: Vector2, material: String, gained: float) -> void:
	var color: Color = GameData.MATERIALS[material].color
	var angle := (at - player.position).angle()
	if _hits.size() < LIMIT:
		_hits.append({"angle": angle, "color": color, "t": 0.0})
	if _motes.size() < LIMIT:
		for i in MOTES_PER_ABSORB:
			# Искра отскакивает от точки касания и по дуге садится на поверхность рядом.
			_motes.append({
				"from": angle,
				"to": angle + randf_range(-1.4, 1.4),
				"height": randf_range(0.8, 2.2),
				"color": color,
				"t": -i * 0.03,
			})
	if _popups.size() >= LIMIT:
		_popups.pop_front()
	var text := "+%d" % roundi(gained) if is_equal_approx(gained, roundf(gained)) else "+%.1f" % gained
	_popups.append({"pos": at, "text": text, "color": color, "t": 0.0, "drift": randf_range(-0.4, 0.4)})


func _process(delta: float) -> void:
	if _hits.is_empty() and _motes.is_empty() and _popups.is_empty():
		return
	for h in _hits:
		h.t += delta
	for m in _motes:
		m.t += delta
	for p in _popups:
		p.t += delta
		p.pos += player.frame_velocity * delta  # всплывашки летят по орбите вместе со всем
	_hits = _hits.filter(func(h): return h.t < WAVE_TIME)
	_motes = _motes.filter(func(m): return m.t < MOTE_TIME)
	_popups = _popups.filter(func(p): return p.t < POPUP_TIME)
	_light.queue_redraw()
	queue_redraw()


func _draw_light() -> void:
	var pp := player.position
	var pr := player.radius
	var px := 1.0 / camera.zoom.x  # один пиксель экрана в мировых единицах

	for h in _hits:
		var col: Color = (h.color as Color).lightened(0.35)
		var a0: float = h.angle
		var contact := pp + Vector2.from_angle(a0) * pr
		# Вспышка в точке касания: быстро разгорается и гаснет.
		var kf := clampf(h.t / FLASH_TIME, 0.0, 1.0)
		var flash := sin(minf(kf * 1.6, 1.0) * PI * 0.5) * (1.0 - kf)
		var fs := pr * (2.0 + 3.0 * kf)
		_light.draw_texture_rect(_glow, Rect2(contact - Vector2(fs, fs), Vector2(fs, fs) * 2.0), false, Color(col, 0.6 * flash))
		_light.draw_circle(contact, maxf(pr * 0.2, 2.0 * px) * (1.0 - kf), Color(1, 1, 1, flash))
		# Световая волна обегает край комка в обе стороны и сходится на другой стороне.
		var kw: float = h.t / WAVE_TIME
		var travel := PI * (1.0 - pow(1.0 - kw, 2.0))
		var span := 0.5 * (1.0 - kw) + 0.15
		var wa := (1.0 - kw) * 0.85
		var w := maxf(pr * 0.22 * (1.0 - kw * 0.6), 2.0 * px)
		var rr := pr * 1.15
		_light.draw_arc(pp, rr, a0 + travel - span, a0 + travel, 12, Color(col, wa), w, true)
		_light.draw_arc(pp, rr, a0 - travel, a0 - travel + span, 12, Color(col, wa), w, true)
		# Мягкое свечение всего комка.
		var gs := pr * 4.0
		_light.draw_texture_rect(_glow, Rect2(pp - Vector2(gs, gs), Vector2(gs, gs) * 2.0), false, Color(col, 0.2 * (1.0 - kw)))

	for m in _motes:
		if m.t < 0.0:
			continue
		var k: float = m.t / MOTE_TIME
		var ang := lerpf(m.from, m.to, k)
		var lift: float = sin(k * PI) * m.height * pr
		var p := pp + Vector2.from_angle(ang) * (pr + lift)
		var col: Color = Color.WHITE.lerp(m.color, 0.35)
		var a := 1.0 - k * k
		var s := maxf(pr * 0.5, 5.0 * px)
		_light.draw_texture_rect(_glow, Rect2(p - Vector2(s, s), Vector2(s, s) * 2.0), false, Color(col, 0.5 * a))
		_light.draw_circle(p, maxf(pr * 0.1, 1.3 * px), Color(col, a))


func _draw() -> void:
	# «+N»: выскакивает с упругим увеличением, всплывает и тает. Текст рисуем
	# в пикселях экрана (масштаб 1/zoom), чтобы шрифт был чётким при любом приближении.
	var px := 1.0 / camera.zoom.x
	var font: Font = UiTheme.FONT_NUMBERS
	for p in _popups:
		var k: float = p.t / POPUP_TIME
		var pop := 1.0 + 0.5 * exp(-k * 14.0) * sin(k * 30.0) if k < 0.3 else 1.0
		var font_size := roundi(20.0 * pop)
		var pos: Vector2 = p.pos + Vector2(p.drift * 20.0 * k, -36.0 * (1.0 - pow(1.0 - k, 2.0)) - 8.0) * px
		var alpha := 1.0 if k < 0.6 else 1.0 - (k - 0.6) / 0.4
		var w := font.get_string_size(p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_set_transform(pos, 0.0, Vector2(px, px))
		draw_string_outline(font, Vector2(-w * 0.5, 0), p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(0, 0, 0, 0.6 * alpha))
		draw_string(font, Vector2(-w * 0.5, 0), p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(p.color.lightened(0.25), alpha))
	draw_set_transform(Vector2.ZERO)
