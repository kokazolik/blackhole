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
		draw_arc(hint, RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.08), 3.0, true)
		draw_circle(hint, KNOB_RADIUS, Color(1, 1, 1, 0.06))
		return
	draw_circle(_base, RADIUS, Color(1, 1, 1, 0.06))
	draw_arc(_base, RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.25), 3.0, true)
	draw_circle(_knob, KNOB_RADIUS, Color(1, 1, 1, 0.3))
