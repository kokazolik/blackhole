extends ColorRect
## Фон космоса: туманности и звёзды в несколько слоёв параллакса (shaders/space_bg.gdshader).
##
## Игрок и пыль вокруг летят по орбите вместе, поэтому полёт читается по фону:
## ближние звёзды сдвигаются заметнее дальних, туманности почти неподвижны.

const SHADER := preload("res://shaders/space_bg.gdshader")

var camera: Camera2D
var _mat := ShaderMaterial.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat.shader = SHADER
	_mat.set_shader_parameter("nebula", preload("res://assets/space/nebula.png"))
	_mat.set_shader_parameter("stars_far", preload("res://assets/space/stars_far.png"))
	_mat.set_shader_parameter("stars_near", preload("res://assets/space/stars_near.png"))
	material = _mat


func _process(_delta: float) -> void:
	_mat.set_shader_parameter("view_size", size)
	if camera:
		_mat.set_shader_parameter("offset", camera.get_screen_center_position() * camera.zoom.x)
