class_name VirtualJoystick
extends Control
## Плавающий стик: появляется там, где палец коснулся левой половины экрана.

const RADIUS := 90.0
const KNOB_RADIUS := 38.0
const DEAD_ZONE := 0.08

var output := Vector2.ZERO
## Скорость убегания в долях предельной (на этапе планетезимали), иначе < 0.
## Внутри этого радиуса стика всё, во что врежешься, прилипает.
var escape_frac := -1.0:
	set(v):
		if absf(v - escape_frac) > 0.005:
			escape_frac = v
			queue_redraw()
var _touch_index := -1
var _base := Vector2.ZERO
var _knob := Vector2.ZERO


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func reset() -> void:
	_touch_index = -1
	output = Vector2.ZERO
	queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index == -1 and event.position.x < size.x * 0.5:
			_touch_index = event.index
			_base = event.position
			_knob = _base
			output = Vector2.ZERO
		elif not event.pressed and event.index == _touch_index:
			reset()
		queue_redraw()
	elif event is InputEventScreenDrag and event.index == _touch_index:
		var offset: Vector2 = event.position - _base
		if offset.length() > RADIUS:
			# База тянется за пальцем, чтобы не приходилось возвращаться к центру.
			_base += offset.normalized() * (offset.length() - RADIUS)
			offset = event.position - _base
		_knob = _base + offset
		output = offset / RADIUS
		if output.length() < DEAD_ZONE:
			output = Vector2.ZERO
		queue_redraw()


func _draw() -> void:
	if _touch_index == -1:
		# Подсказка, где стик, пока к экрану не прикоснулись.
		var hint := Vector2(RADIUS + 60.0, size.y - RADIUS - 50.0)
		draw_circle(hint, RADIUS, Color(0.5, 0.65, 1.0, 0.04))
		draw_arc(hint, RADIUS, 0.0, TAU, 64, Color(0.7, 0.82, 1.0, 0.14), 2.0, true)
		draw_circle(hint, KNOB_RADIUS, Color(0.7, 0.82, 1.0, 0.08))
		_draw_escape(hint, 0.5)
		return
	draw_circle(_base, RADIUS, Color(0.4, 0.55, 1.0, 0.07))
	draw_arc(_base, RADIUS, 0.0, TAU, 64, Color(0.7, 0.82, 1.0, 0.3), 2.0, true)
	_draw_escape(_base, 1.0)
	# Подсвеченная дуга в сторону движения.
	if output.length() > 0.0:
		var a := output.angle()
		var spread := 0.5 + 0.4 * output.length()
		draw_arc(_base, RADIUS, a - spread, a + spread, 24, Color(1.0, 0.85, 0.5, 0.25 + 0.5 * output.length()), 4.0, true)
	draw_circle(_knob, KNOB_RADIUS + 8.0, Color(0.7, 0.82, 1.0, 0.08))
	draw_circle(_knob, KNOB_RADIUS, Color(0.75, 0.85, 1.0, 0.28))
	draw_arc(_knob, KNOB_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.45), 2.0, true)


## Золотая зона «липнет»: скорость ниже убегания. За ней — красноватое кольцо,
## где камни уже отскакивают. Когда убегание выше предельной скорости, золотой
## весь стик.
func _draw_escape(c: Vector2, alpha: float) -> void:
	if escape_frac <= 0.0:
		return
	var gold := Color(1.0, 0.82, 0.42)
	var zr := RADIUS * minf(escape_frac, 1.0)
	for k in 4:
		var f := 1.0 - k * 0.22
		draw_circle(c, zr * f, Color(gold, 0.035 * alpha))
	if escape_frac < 1.0:
		draw_arc(c, (RADIUS + zr) * 0.5, 0.0, TAU, 64, Color(1.0, 0.4, 0.3, 0.14 * alpha), RADIUS - zr, true)
		# Пунктир на границе убегания.
		var n := 28
		for i in n:
			var a := TAU * i / n
			draw_arc(c, zr, a, a + TAU / n * 0.5, 3, Color(gold, 0.85 * alpha), 1.6, true)
	else:
		draw_arc(c, RADIUS, 0.0, TAU, 64, Color(gold, 0.75 * alpha), 2.5, true)
