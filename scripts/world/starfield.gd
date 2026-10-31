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
	_mat.set_shader_parameter("disk_streams", preload("res://assets/space/disk_streams.png"))
	material = _mat


func _process(_delta: float) -> void:
	_mat.set_shader_parameter("view_size", size)
	if camera:
		var center := camera.get_screen_center_position()
		_mat.set_shader_parameter("offset", center * camera.zoom.x)
		_mat.set_shader_parameter("orbit_angle", center.angle())
		_mat.set_shader_parameter("star_dir", -center.normalized())
		var d := center.length()
		_mat.set_shader_parameter("snow", exp(-pow((d - GameData.SNOW_LINE) / GameData.SNOW_LINE_WIDTH, 2.0)))
	_mat.set_shader_parameter("flare", Star.flare)
	# Пока игрок с пылинку или гальку, еда размером со звезду: фон приглушаем.
	var dim := 1.0
	if GameState.stage <= 1:
		dim = 0.4
	elif GameState.stage == 2:
		dim = 0.65
	_mat.set_shader_parameter("star_dim", dim)
