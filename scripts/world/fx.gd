class_name AbsorbFx
extends Node2D
## Анимация поглощения пыли: искры падают прямо в пылинку, вспышка-кольцо на ней
## и всплывающее «+N» цветом материала. Рисуется только пока эффекты живы.

const SPARK_TIME := 0.3
const RING_TIME := 0.45
const POPUP_TIME := 1.0
const SPARKS_PER_ABSORB := 4
const LIMIT := 48  # на каждый вид эффекта, чтобы скопление не грузило кадр

var player: Player
var camera: Camera2D
var _sparks: Array = []  # смещение от игрока в момент поглощения
var _rings: Array = []
var _popups: Array = []


func _ready() -> void:
	GameState.absorbed.connect(_on_absorbed)


func _on_absorbed(at: Vector2, material: String, gained: float) -> void:
	var color: Color = GameData.MATERIALS[material].color
	var offset := at - player.position
	if _sparks.size() < LIMIT:
		for i in SPARKS_PER_ABSORB:
			_sparks.append({
				"off": offset + Vector2.from_angle(randf() * TAU) * player.radius * randf_range(0.5, 1.5),
				"color": color,
				"t": -i * 0.03,
			})
	if _rings.size() < LIMIT:
		_rings.append({"color": color, "t": 0.0})
	if _popups.size() >= LIMIT:
		_popups.pop_front()
	var text := "+%d" % roundi(gained) if is_equal_approx(gained, roundf(gained)) else "+%.1f" % gained
	_popups.append({"pos": at, "text": text, "color": color, "t": 0.0, "drift": randf_range(-0.4, 0.4)})


func _process(delta: float) -> void:
	if _sparks.is_empty() and _rings.is_empty() and _popups.is_empty():
		return
	for s in _sparks:
		s.t += delta
	for r in _rings:
		r.t += delta
	for p in _popups:
		p.t += delta
		p.pos += player.frame_velocity * delta  # всплывашки летят по орбите вместе со всем
	_sparks = _sparks.filter(func(s): return s.t < SPARK_TIME)
	_rings = _rings.filter(func(r): return r.t < RING_TIME)
	_popups = _popups.filter(func(p): return p.t < POPUP_TIME)
	queue_redraw()


func _draw() -> void:
	var pp := player.position
	var pr := player.radius
	var px := 1.0 / camera.zoom.x  # один пиксель экрана в мировых единицах

	# Искры: падают к центру и гаснут.
	for s in _sparks:
		if s.t < 0.0:
			continue
		var k: float = s.t / SPARK_TIME
		var e := k * k
		var off: Vector2 = (s.off as Vector2) * (1.0 - e)
		var p := pp + off
		var a := 1.0 - e
		draw_circle(p, (1.2 + 1.5 * (1.0 - k)) * px, Color(s.color, 0.25 * a))
		draw_circle(p, (0.6 + 0.8 * (1.0 - k)) * px, Color(Color.WHITE.lerp(s.color, 0.3), a))

	# Вспышка: кольцо расходится от поверхности пылинки.
	for r in _rings:
		var k: float = r.t / RING_TIME
		var e := 1.0 - pow(1.0 - k, 3.0)
		var radius := pr * (1.2 + 2.2 * e)
		draw_arc(pp, radius, 0.0, TAU, 32, Color(r.color, 0.55 * (1.0 - k)), maxf(1.5 * px, pr * 0.15 * (1.0 - k)), true)

	# «+N»: выскакивает с упругим увеличением, всплывает и тает. Текст рисуем
	# в пикселях экрана (масштаб 1/zoom), чтобы шрифт был чётким при любом приближении.
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
