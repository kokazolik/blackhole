extends ColorRect
## Слой размытых пылинок перед камерой (shaders/foreground_dust.gdshader).

var camera: Camera2D
var _mat := ShaderMaterial.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat.shader = preload("res://shaders/foreground_dust.gdshader")
	_mat.set_shader_parameter("bokeh", preload("res://assets/space/bokeh.png"))
	material = _mat


func _process(_delta: float) -> void:
	_mat.set_shader_parameter("view_size", size)
	if camera:
		_mat.set_shader_parameter("offset", camera.get_screen_center_position() * camera.zoom.x)
