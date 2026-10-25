class_name Player
extends Node2D
## Пылинка игрока: движение от стика/клавиатуры, рост от массы, поле притяжения.

const ACCEL_FACTOR := 3.0
const GLOW_LAYERS := 5

var velocity := Vector2.ZERO
var move_input := Vector2.ZERO  # задаётся стиком, длина 0..1
var radius := GameData.BASE_RADIUS
var body_color := Color.WHITE
var _pulse := 0.0
var _ring_phase := 0.0


func _ready() -> void:
	position = GameState.player_position
	radius = target_radius()
	_update_color()
	GameState.absorbed.connect(_on_absorbed)
	GameState.skills_changed.connect(queue_redraw)


func target_radius() -> float:
	return GameData.BASE_RADIUS * pow(GameState.mass, 1.0 / 3.0)


func pull_radius() -> float:
	return radius * 7.0 * Skills.stat("reach") * sqrt(Skills.stat("gravity"))


func pull_strength() -> float:
	return 12.0 * radius * Skills.stat("gravity")


func max_speed() -> float:
	return 28.0 * pow(radius, 0.75) * Skills.stat("speed") * GameState.body_bonus("speed")


func _physics_process(delta: float) -> void:
	var dir := move_input + _keyboard_input()
	dir = dir.limit_length(1.0)
	var top := max_speed()
	velocity = velocity.move_toward(dir * top, top * ACCEL_FACTOR * delta)
	position += velocity * delta

	# Звезду не пересечь: выталкиваем на безопасное расстояние.
	var min_dist := GameData.STAR_RADIUS * 1.3 + radius
	var dist := position.length()
	if dist < min_dist:
		var n := position.normalized() if dist > 0.01 else Vector2.RIGHT
		position = n * min_dist
		velocity = velocity.slide(n)

	radius = lerpf(radius, target_radius(), 1.0 - exp(-4.0 * delta))
	_pulse = maxf(0.0, _pulse - delta * 4.0)
	_ring_phase = fmod(_ring_phase + delta * 0.6, 1.0)
	GameState.player_position = position
	queue_redraw()


func _keyboard_input() -> Vector2:
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		v.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		v.x += 1
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		v.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		v.y += 1
	return v.normalized()


func _on_absorbed(_at: Vector2, _material: String, _gained: float) -> void:
	_pulse = 1.0
	_update_color()


## Цвет пылинки смешивается из собранных материалов.
func _update_color() -> void:
	var total := 0.0
	var c := Color(0, 0, 0)
	for key in GameData.MATERIAL_ORDER:
		var amount: float = GameState.materials.get(key, 0.0)
		total += amount
		c += GameData.MATERIALS[key].color * amount
	body_color = c / total if total > 0.0 else Color(0.9, 0.88, 0.82)
	body_color.a = 1.0


func _draw() -> void:
	# Поле притяжения: слабое кольцо и бегущая волна внутрь.
	var pr := pull_radius()
	var ring := Color(0.55, 0.75, 1.0, 0.10 + 0.05 * (Skills.stat("gravity") - 1.0))
	draw_arc(Vector2.ZERO, pr, 0.0, TAU, 64, ring, maxf(1.0, radius * 0.08), true)
	var wave_r := lerpf(pr, radius, _ring_phase)
	draw_arc(Vector2.ZERO, wave_r, 0.0, TAU, 48, Color(ring, ring.a * 0.6 * _ring_phase), maxf(1.0, radius * 0.05), true)

	# Свечение и ядро.
	var r := radius * (1.0 + 0.12 * _pulse)
	for i in GLOW_LAYERS:
		var t := float(GLOW_LAYERS - i) / GLOW_LAYERS
		draw_circle(Vector2.ZERO, r * (1.0 + t * 1.6), Color(body_color, 0.06 * (1.0 - t * 0.5)))
	draw_circle(Vector2.ZERO, r, body_color)
	draw_circle(Vector2.ZERO, r * 0.55, body_color.lightened(0.45))
