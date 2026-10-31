extends ColorRect
## Фон космоса: туманности и звёзды в несколько слоёв параллакса (shaders/space_bg.gdshader).
##
## Игрок и пыль вокруг летят по орбите вместе, поэтому полёт читается по фону:
## ближние звёзды сдвигаются заметнее дальних, туманности почти неподвижны.

const SHADER := preload("res://shaders/space_bg.gdshader")

var camera: Camera2D
var _mat := ShaderMaterial.new()
var _off := Vector2.ZERO
var _last := Vector2(INF, INF)


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
		if camera.ignore_rotation:
			_mat.set_shader_parameter("offset", center * camera.zoom.x)
		else:
			# Камера вращается вместе с гигантом: фон сдвигаем по экранному
			# смещению, иначе полёт вдоль орбиты не читался бы по звёздам.
			if _last.x == INF:
				_off = center * camera.zoom.x
			else:
				_off += (center - _last).rotated(-camera.global_rotation) * camera.zoom.x
			_last = center
			_mat.set_shader_parameter("offset", _off)
		_mat.set_shader_parameter("orbit_angle", center.angle())
		_mat.set_shader_parameter("star_dir", (-center.normalized()).rotated(-camera.global_rotation))
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
