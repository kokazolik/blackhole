extends Node2D
## Далёкие звёзды на фоне с лёгким параллаксом.

const STAR_COUNT := 220
const PARALLAX := 0.03

var camera: Camera2D
var _stars: Array = []


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in STAR_COUNT:
		_stars.append({
			"p": Vector2(rng.randf(), rng.randf()),
			"r": rng.randf_range(0.5, 1.3),
			"a": rng.randf_range(0.06, 0.3),
		})


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var size := get_viewport_rect().size
	var shift := camera.global_position * PARALLAX if camera else Vector2.ZERO
	for s in _stars:
		var p := Vector2(fposmod(s.p.x * size.x - shift.x, size.x), fposmod(s.p.y * size.y - shift.y, size.y))
		draw_circle(p, s.r, Color(0.85, 0.9, 1.0, s.a))
