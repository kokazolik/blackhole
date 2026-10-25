extends Node2D
## Молодая звезда в центре диска (шейдер) и границы зон.

const QUAD_EXTENT := 4.0  # квад шейдера в радиусах звезды, должен совпадать с extent
# Вид звезды: запечённая поверхность + живая анимация.
# Исходник поверхности: shaders/young_star_procedural.gdshader (тяжёлый, только для запекания
# через tools/bake_star.tscn). Рельефный вариант: shaders/young_star_relief.gdshader.
const STAR_SHADER := preload("res://shaders/young_star.gdshader")
const SURFACE_TEX := preload("res://assets/star/star_surface.png")


func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * GameData.STAR_RADIUS * 2.0 * QUAD_EXTENT
	var mat := ShaderMaterial.new()
	mat.shader = STAR_SHADER
	mat.set_shader_parameter("extent", QUAD_EXTENT)
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


func _draw_dashed_ring(radius: float, color: Color) -> void:
	var segments := 360
	for i in range(0, segments, 2):
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		draw_arc(Vector2.ZERO, radius, a0, a1, 4, color, 3.0)
