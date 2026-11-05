extends ColorRect
## Газовый диск этапа гиганта: плотность газа по радиусу и её рисунок.
##
## Плотность хранится столбцами от внутреннего края диска к внешнему. Гигант
## пьёт газ из кормовой зоны, приливы расталкивают газ к краям щели, вязкость
## медленно затягивает щель обратно. Рисует шейдер на весь экран (gas_disk.gdshader).

const SHADER := preload("res://shaders/gas_disk.gdshader")

var camera: Camera2D
var sigma := PackedFloat32Array()
var _mat := ShaderMaterial.new()
var _img: Image
var _tex: ImageTexture
var _dr := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat.shader = SHADER
	material = _mat
	_dr = (GameData.GIANT_DISK.y - GameData.GIANT_DISK.x) / GameData.GIANT_BINS
	_mat.set_shader_parameter("disk_range", GameData.GIANT_DISK)
	_mat.set_shader_parameter("snow_line", GameData.SNOW_LINE)
	_mat.set_shader_parameter("noise_tex", NoiseTex.get_tex())


## Плотность из сохранения или нетронутый диск: Σ ∝ 1/r, у звезды газ
## выметен её магнитным полем.
func setup(saved: Array) -> void:
	sigma.resize(GameData.GIANT_BINS)
	if saved.size() == GameData.GIANT_BINS:
		for i in sigma.size():
			sigma[i] = float(saved[i])
	else:
		for i in sigma.size():
			var r := bin_r(i)
			sigma[i] = GameData.SNOW_LINE / maxf(r, 2200.0) * smoothstep(700.0, 1600.0, r)
	_img = Image.create_from_data(sigma.size(), 1, false, Image.FORMAT_RF, sigma.to_byte_array())
	_tex = ImageTexture.create_from_image(_img)
	_mat.set_shader_parameter("sigma_tex", _tex)


func bin_r(i: int) -> float:
	return GameData.GIANT_DISK.x + (i + 0.5) * _dr


func at(r: float) -> float:
	var f := clampf((r - GameData.GIANT_DISK.x) / _dr - 0.5, 0.0, sigma.size() - 1.001)
	var i := int(f)
	return lerpf(sigma[i], sigma[i + 1], f - i)


## Средняя плотность в кормовой зоне шириной width вокруг орбиты r.
func feed(r: float, width: float) -> float:
	var sw := 0.0
	var s := 0.0
	for i in sigma.size():
		var w := exp(-pow((bin_r(i) - r) / width, 2.0))
		sw += w
		s += w * sigma[i]
	return s / maxf(sw, 1e-6)


## Шаг газа: аккреция eaten (в единицах плотности) из зоны, прилив, вязкость.
func step(delta: float, r: float, width: float, hill: float, eaten: float, torque: float) -> void:
	var n := sigma.size()
	var w := PackedFloat32Array()
	w.resize(n)
	var sw := 0.0
	for i in n:
		w[i] = exp(-pow((bin_r(i) - r) / width, 2.0))
		sw += w[i]
	var moved := 0.0
	var gap := 1.1 * hill
	for i in n:
		var s := sigma[i] - eaten * w[i] / maxf(sw, 1e-6)
		var d := maxf(s, 0.0) * minf(0.5, torque * exp(-pow((bin_r(i) - r) / gap, 2.0)) * delta)
		sigma[i] = maxf(s - d, 0.0)
		moved += d
	# Сгребённый приливами газ ложится валами по краям щели.
	if moved > 0.0:
		var e := PackedFloat32Array()
		e.resize(n)
		var se := 0.0
		for i in n:
			var br := bin_r(i)
			e[i] = exp(-pow((br - r - 2.6 * hill) / (0.5 * hill), 2.0)) + exp(-pow((br - r + 2.6 * hill) / (0.5 * hill), 2.0))
			se += e[i]
		if se > 1e-6:
			for i in n:
				sigma[i] += moved * e[i] / se
	# Вязкость: газ затекает в щель (явная схема, шаг заведомо устойчив).
	var nu := minf(GameData.GIANT_VISC * 5.0 * delta, 0.45)
	var prev := sigma[0]
	for i in range(1, n - 1):
		var cur := sigma[i]
		sigma[i] = cur + nu * (prev - 2.0 * cur + sigma[i + 1])
		prev = cur


func _process(_delta: float) -> void:
	if _img == null or camera == null:
		return
	_img.set_data(sigma.size(), 1, false, Image.FORMAT_RF, sigma.to_byte_array())
	_tex.update(_img)
	_mat.set_shader_parameter("view_size", size)
	_mat.set_shader_parameter("cam", camera.get_screen_center_position())
	_mat.set_shader_parameter("zoom", camera.zoom.x)
	_mat.set_shader_parameter("cam_rot", camera.global_rotation)
	_mat.set_shader_parameter("flare", Star.flare)


func set_view(rp: float, hill: float, gas: float, wake: float, gang := 0.0) -> void:
	_mat.set_shader_parameter("gang", gang)
	_mat.set_shader_parameter("rp", rp)
	_mat.set_shader_parameter("hill", hill)
	_mat.set_shader_parameter("gas", gas)
	_mat.set_shader_parameter("wake", wake)
