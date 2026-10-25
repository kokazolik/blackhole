class_name VirtualJoystick
extends Control
## Плавающий стик: появляется там, где палец коснулся левой половины экрана.

const RADIUS := 90.0
const KNOB_RADIUS := 38.0
const DEAD_ZONE := 0.08

var output := Vector2.ZERO
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
		return
	draw_circle(_base, RADIUS, Color(0.4, 0.55, 1.0, 0.07))
	draw_arc(_base, RADIUS, 0.0, TAU, 64, Color(0.7, 0.82, 1.0, 0.3), 2.0, true)
	# Подсвеченная дуга в сторону движения.
	if output.length() > 0.0:
		var a := output.angle()
		var spread := 0.5 + 0.4 * output.length()
		draw_arc(_base, RADIUS, a - spread, a + spread, 24, Color(1.0, 0.85, 0.5, 0.25 + 0.5 * output.length()), 4.0, true)
	draw_circle(_knob, KNOB_RADIUS + 8.0, Color(0.7, 0.82, 1.0, 0.08))
	draw_circle(_knob, KNOB_RADIUS, Color(0.75, 0.85, 1.0, 0.28))
	draw_arc(_knob, KNOB_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.45), 2.0, true)
