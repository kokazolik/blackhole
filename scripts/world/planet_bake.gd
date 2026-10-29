class_name PlanetBake
extends SubViewport
## Печёт рельеф планетезимали в развёртку сферы (planetesimal_bake.gdshader).
## Шейдер тяжёлый, поэтому развёртка рисуется полосами, по одной за кадр:
## телефон не замирает, а через десяток кадров текстура готова.

const SIZE := Vector2i(2048, 1024)
const STRIPS := 16

var done := false
var normals := SubViewport.new()  # нормали поверхности, второй проход
var _rect := ColorRect.new()
var _mat := ShaderMaterial.new()
var _strip := -1


func _init(seed_value: float) -> void:
	size = SIZE
	transparent_bg = true  # в альфе лежит тон, а не прозрачность
	use_hdr_2d = true  # высота в 8 битах дала бы ступеньки на свету
	disable_3d = true
	render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	_mat.shader = preload("res://shaders/planetesimal_bake.gdshader")
	_mat.set_shader_parameter("seed", seed_value)
	_rect.material = _mat
	add_child(_rect)
	normals.size = SIZE
	normals.transparent_bg = true
	normals.use_hdr_2d = true
	normals.disable_3d = true
	normals.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var rect := ColorRect.new()
	rect.size = Vector2(SIZE)
	var nm := ShaderMaterial.new()
	nm.shader = preload("res://shaders/planetesimal_normals.gdshader")
	nm.set_shader_parameter("height_map", get_texture())
	rect.material = nm
	normals.add_child(rect)
	add_child(normals)


func start() -> void:
	_strip = 0
	done = false


func _process(_delta: float) -> void:
	if _strip < 0:
		return
	if _strip == STRIPS:
		normals.render_target_update_mode = SubViewport.UPDATE_ONCE
		_strip += 1
		return
	if _strip > STRIPS:
		_strip = -1
		done = true
		return
	var h := float(SIZE.y) / STRIPS
	_rect.position = Vector2(0.0, h * _strip)
	_rect.size = Vector2(SIZE.x, h)
	_mat.set_shader_parameter("region", Vector4(0.0, float(_strip) / STRIPS, 1.0, 1.0 / STRIPS))
	render_target_update_mode = SubViewport.UPDATE_ONCE
	_strip += 1
