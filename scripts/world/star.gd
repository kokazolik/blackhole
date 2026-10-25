extends Node2D
## Молодая звезда в центре диска (шейдер) и границы зон.

const QUAD_EXTENT := 1.8  # квад шейдера в радиусах звезды
const HALO_EXTENT := 7.0  # дальнее свечение короны, в радиусах звезды
const HALO_COLOR := Color(1.0, 0.45, 0.12)
# Вид звезды: запечённая поверхность + живая анимация.
# Исходник поверхности: shaders/young_star_procedural.gdshader (тяжёлый, только для запекания
# через tools/bake_star.tscn). Рельефный вариант: shaders/young_star_relief.gdshader.
const STAR_SHADER := preload("res://shaders/young_star.gdshader")
const SURFACE_TEX := preload("res://assets/star/star_surface.png")


func _ready() -> void:
	# Дальнее свечение: одна текстура вместо шейдера на весь экран.
	var halo := Sprite2D.new()
	halo.texture = _make_halo()
	halo.scale = Vector2.ONE * GameData.STAR_RADIUS * 2.0 * HALO_EXTENT / halo.texture.get_width()
	add_child(halo)

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


## Радиальное свечение: яркость спадает как exp(-0.9 · расстояние от края в радиусах).
func _make_halo() -> ImageTexture:
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var r := Vector2(x - c, y - c).length() / c * HALO_EXTENT
			var a := 0.3 * exp(-0.9 * maxf(r - 1.0, 0.0)) * smoothstep(HALO_EXTENT, HALO_EXTENT * 0.6, r)
			img.set_pixel(x, y, Color(HALO_COLOR, a))
	return ImageTexture.create_from_image(img)


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
