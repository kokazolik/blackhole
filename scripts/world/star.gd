extends Node2D
## Молодая звезда в центре диска (шейдер) и границы зон.

const QUAD_EXTENT := 1.8  # квад шейдера в радиусах звезды
const HALO_EXTENT := 3.0  # свечение короны только рядом со звездой, в радиусах звезды
const HALO_COLOR := Color(1.0, 0.45, 0.12)
# Вид звезды: запечённая поверхность + живая анимация.
# Исходник поверхности: shaders/young_star_procedural.gdshader (тяжёлый, только для запекания
# через tools/bake_star.tscn). Рельефный вариант: shaders/young_star_relief.gdshader.
const STAR_SHADER := preload("res://shaders/young_star.gdshader")
const HALO_SHADER := preload("res://shaders/star_halo.gdshader")
const SURFACE_TEX := preload("res://assets/star/star_surface.png")


func _ready() -> void:
	# Дальнее свечение: простой квад, яркость считается формулой в шейдере.
	var halo_quad := QuadMesh.new()
	halo_quad.size = Vector2.ONE * GameData.STAR_RADIUS * 2.0 * HALO_EXTENT
	var halo_mat := ShaderMaterial.new()
	halo_mat.shader = HALO_SHADER
	halo_mat.set_shader_parameter("extent", HALO_EXTENT)
	halo_mat.set_shader_parameter("star_radius", GameData.STAR_RADIUS)
	halo_mat.set_shader_parameter("halo_color", HALO_COLOR)
	var halo := MeshInstance2D.new()
	halo.mesh = halo_quad
	halo.material = halo_mat
	add_child(halo)

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * GameData.STAR_RADIUS * 2.0 * QUAD_EXTENT
	var mat := ShaderMaterial.new()
	mat.shader = STAR_SHADER
	mat.set_shader_parameter("extent", QUAD_EXTENT)
	mat.set_shader_parameter("star_radius", GameData.STAR_RADIUS)
	mat.set_shader_parameter("surface_tex", SURFACE_TEX)
	mat.set_shader_parameter("noise_tex", _make_noise())
	var body := MeshInstance2D.new()
	body.mesh = quad
	body.material = mat
	# QuadMesh в 2D перевёрнут по Y, для звезды это неважно.
	add_child(body)


## Бесшовный шум для кипения и короны, генерируется при старте.
func _make_noise() -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.normalize = true
	tex.noise = noise
	return tex


func _draw() -> void:
	# Границы зон: внутренняя (металл) и снеговая линия (лёд).
	_draw_dashed_ring(GameData.INNER_ZONE, Color(1.0, 0.7, 0.4, 0.10))
	_draw_dashed_ring(GameData.SNOW_LINE, Color(0.6, 0.9, 1.0, 0.14))


## Пунктир одним вызовом отрисовки: отрезки собраны в один массив.
func _draw_dashed_ring(radius: float, color: Color) -> void:
	var segments := 360
	var points := PackedVector2Array()
	for i in range(0, segments, 2):
		points.append(Vector2.from_angle(TAU * i / segments) * radius)
		points.append(Vector2.from_angle(TAU * (i + 1) / segments) * radius)
	draw_multiline(points, color, 0.6)
