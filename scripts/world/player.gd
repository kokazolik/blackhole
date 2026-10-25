class_name Player
extends Node2D
## Пылинка игрока: движение от стика/клавиатуры, рост от массы, поле притяжения.

const ACCEL_FACTOR := 3.0
const GRAIN_TEX := preload("res://assets/player/player_grain.png")
const GRAIN_SCALE := 2.8   # зерно на текстуре занимает ~70% её ширины
const SPIN_SPEED := 0.15   # медленное вращение комка, рад/с
const TRAIL_POINTS := 20
const TRAIL_STEP := 0.035  # секунд между точками следа

var velocity := Vector2.ZERO        # собственное движение относительно окружающей пыли
var frame_velocity := Vector2.ZERO  # орбитальное движение вокруг звезды вместе с пылью
var move_input := Vector2.ZERO  # задаётся стиком, длина 0..1
var radius := GameData.BASE_RADIUS
var body_color := Color.WHITE
var _pulse := 0.0
var _ring_phase := 0.0
var _spin := 0.0
var _trail: Array[Vector2] = []  # след в мировых координатах, летит по орбите вместе с пылью
var _trail_timer := 0.0
var _glow_tex := _make_glow()


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	position = GameState.player_position
	radius = target_radius()
	_update_color()
	GameState.absorbed.connect(_on_absorbed)
	GameState.skills_changed.connect(queue_redraw)


## Мягкое свечение одной текстурой вместо стопки полупрозрачных кругов.
static func _make_glow() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.45))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	return tex


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
	# Игрок вместе со всей пылью вокруг летит по орбите, стик добавляет своё движение.
	frame_velocity = GameData.orbit_velocity(position)
	position += (velocity + frame_velocity) * delta

	# Звезду не пересечь: выталкиваем на безопасное расстояние.
	var min_dist := GameData.STAR_RADIUS * 1.3 + radius
	var dist := position.length()
	if dist < min_dist:
		var n := position.normalized() if dist > 0.01 else Vector2.RIGHT
		position = n * min_dist
		velocity = velocity.slide(n)

	radius = lerpf(radius, target_radius(), 1.0 - exp(-4.0 * delta))
	_spin += (SPIN_SPEED + velocity.length() / maxf(radius, 1.0) * 0.05) * delta
	_update_trail(delta)
	_pulse = maxf(0.0, _pulse - delta * 4.0)
	_ring_phase = fmod(_ring_phase + delta * 0.6, 1.0)
	GameState.player_position = position
	queue_redraw()


## След из пыльного шлейфа: виден только когда игрок движется относительно пыли.
func _update_trail(delta: float) -> void:
	for i in _trail.size():
		_trail[i] += frame_velocity * delta
	_trail_timer += delta
	if _trail_timer >= TRAIL_STEP:
		_trail_timer = 0.0
		_trail.push_front(position)
		if _trail.size() > TRAIL_POINTS:
			_trail.pop_back()


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
	draw_arc(Vector2.ZERO, pr, 0.0, TAU, 40, ring, maxf(1.0, radius * 0.08), true)
	var wave_r := lerpf(pr, radius, _ring_phase)
	draw_arc(Vector2.ZERO, wave_r, 0.0, TAU, 32, Color(ring, ring.a * 0.6 * _ring_phase), maxf(1.0, radius * 0.05), true)

	# Шлейф мелкой пыли позади.
	for i in range(1, _trail.size()):
		var t := 1.0 - float(i) / TRAIL_POINTS
		var p := _trail[i] - position
		if p.length() < radius:
			continue
		draw_circle(p, radius * (0.1 + 0.25 * t), Color(body_color, 0.14 * t))

	# Свечение и пылинка-комок.
	var r := radius * (1.0 + 0.12 * _pulse)
	var gs := r * 5.2
	draw_texture_rect(_glow_tex, Rect2(-gs * 0.5, -gs * 0.5, gs, gs), false, Color(body_color, 0.22 + 0.15 * _pulse))
	var s := r * GRAIN_SCALE
	var tint := body_color.lightened(0.35 + 0.3 * _pulse)
	draw_set_transform(Vector2.ZERO, _spin)
	draw_texture_rect(GRAIN_TEX, Rect2(-s * 0.5, -s * 0.5, s, s), false, tint)
	draw_set_transform(Vector2.ZERO)
