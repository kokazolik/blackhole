extends Node2D
## Далёкие гиганты на фоне: протопланеты и зарождающийся газовый гигант в
## своём диске. Они в тысячи раз дальше всего, что вокруг, поэтому почти не
## сдвигаются, пока ты летишь, и остаются такими же огромными на любом этапе:
## до них тебе расти и расти.
##
## Живёт в слое фона (координаты экрана). Небо — тор: тела расставлены по нему
## и, уйдя за край, со временем возвращаются с другой стороны.

const PARALLAX := 0.03     # медленнее дальних звёзд (0.06), быстрее туманностей
const MARGIN := 700.0      # запас тора сверх экрана, px

var camera: Camera2D
var _bodies: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _shift := Vector2.ZERO
var _last := Vector2.INF


func _ready() -> void:
	_rng.randomize()
	var blank := Image.create(16, 16, false, Image.FORMAT_L8)
	blank.fill(Color.WHITE)
	var tex := ImageTexture.create_from_image(blank)
	# Гигант в диске и две протопланеты, по своим долям неба.
	var kinds := [1, 0, 0]
	for i in kinds.size():
		var kind: int = kinds[i]
		var radius := _rng.randf_range(70.0, 105.0) if kind == 1 else _rng.randf_range(38.0, 80.0)
		var quad := 2.7 if kind == 1 else 1.4
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://shaders/far_body.gdshader")
		mat.set_shader_parameter("kind", kind)
		mat.set_shader_parameter("seed", _rng.randf())
		mat.set_shader_parameter("quad", quad)
		mat.set_shader_parameter("tilt", _rng.randf_range(-0.6, 0.6))
		mat.set_shader_parameter("haze", _rng.randf_range(0.4, 0.55) if kind == 1 else _rng.randf_range(0.45, 0.65))
		var s := Sprite2D.new()
		s.texture = tex
		s.material = mat
		s.scale = Vector2.ONE * radius * quad * 2.0 / 16.0
		add_child(s)
		# Доли неба: по трети тора по ширине, высота случайная.
		_bodies.append({"sprite": s, "u": (float(i) + _rng.randf_range(0.2, 0.8)) / kinds.size(), "v": _rng.randf(), "reach": radius * quad})


func _process(_delta: float) -> void:
	if camera == null:
		return
	var size := get_viewport_rect().size
	var sky := size + Vector2(MARGIN, MARGIN) * 2.0
	var center := camera.get_screen_center_position()
	# Сдвиг копим по кадрам: при отъезде камеры тела не должны прыгать.
	if _last != Vector2.INF and center.distance_to(_last) * camera.zoom.x < 400.0:
		_shift += (center - _last) * camera.zoom.x * PARALLAX
	_last = center
	var shift := _shift
	var to_star := -center.normalized()
	for b in _bodies:
		var s: Sprite2D = b.sprite
		var base := Vector2(b.u * sky.x, b.v * sky.y)
		var p := Vector2(fposmod(base.x - shift.x, sky.x), fposmod(base.y - shift.y, sky.y)) - Vector2(MARGIN, MARGIN)
		s.position = p
		var reach: float = b.reach
		s.visible = p.x > -reach and p.y > -reach and p.x < size.x + reach and p.y < size.y + reach
		if s.visible:
			var mat := s.material as ShaderMaterial
			mat.set_shader_parameter("light_dir", to_star)
			mat.set_shader_parameter("star_light", Color(1.0, 0.9, 0.75) * (1.0 + 0.6 * Star.flare))
