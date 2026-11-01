class_name NoiseTex
## Общая бесшовная текстура шума для шейдеров этапа гиганта.
## Шум в шейдере считался заново в каждом пикселе каждый кадр (fbm по 4–5 слоёв);
## выборка из готовой текстуры в десятки раз дешевле и на вид та же.
## Текстура 256×256 покрывает 16 единиц шума: fbm(p) ≈ texture(tex, p / 16).

static var _tex: NoiseTexture2D


static func get_tex() -> NoiseTexture2D:
	if _tex == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_VALUE_CUBIC
		n.frequency = 1.0 / 16.0
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = 4
		n.fractal_gain = 0.5
		n.fractal_lacunarity = 2.03
		n.seed = 1337
		_tex = NoiseTexture2D.new()
		_tex.width = 256
		_tex.height = 256
		_tex.seamless = true
		_tex.normalize = true
		_tex.generate_mipmaps = true
		_tex.noise = n
	return _tex
