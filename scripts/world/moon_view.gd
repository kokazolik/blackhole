class_name MoonView
extends ColorRect
## Луна шейдером (shaders/moon.gdshader): кратеры, моря, терминатор.
## Стиль по составу: 0 камень, 1 лёд, 2 сера, 3 углерод, 4 железо, 5 смесь.

const SHADER := preload("res://shaders/moon.gdshader")

var _mat := ShaderMaterial.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat.shader = SHADER
	material = _mat


## Поставить луну центром в c (в координатах родителя) радиусом r.
func put(c: Vector2, r: float, style: int, light: Vector2, seed_v: float, spin: float, shadow := 1.0, heat := 0.0, form := 1.0) -> void:
	visible = true
	var q := r * 2.2
	size = Vector2(q, q)
	position = c - size * 0.5
	_mat.set_shader_parameter("style", style)
	_mat.set_shader_parameter("light_dir", light)
	_mat.set_shader_parameter("seed", seed_v)
	_mat.set_shader_parameter("spin", spin)
	_mat.set_shader_parameter("shadow", shadow)
	_mat.set_shader_parameter("heat", heat)
	_mat.set_shader_parameter("form", form)


## Стиль луны по составу тела: лёд, железо, углерод, сера и т.д.
static func style_for_type(type: String) -> int:
	match type:
		"ice", "titan":
			return 1
		"venus":
			return 2
		"carbon":
			return 3
		"metal":
			return 4
		"chondrite":
			return 5
	return 0


## Луны гиганта: у каждого ядра свой набор (как галилеевы у Юпитера).
static func style_for_giant(flavor: String, i: int) -> int:
	var sets := {
		"giant_cold": [2, 1, 5, 3],
		"giant_ice": [1, 5, 1, 3],
		"giant_hot": [2, 0, 4, 0],
		"giant_dense": [4, 2, 0, 4],
		"giant_dark": [3, 3, 5, 0],
	}
	var s: Array = sets.get(flavor, sets["giant_cold"])
	return int(s[i % s.size()])
