class_name Player
extends Node2D
## Пылинка игрока: движение от стика/клавиатуры, рост от массы, поле притяжения.
## У звезды нагревается, светится и испаряется; коснувшись поверхности — гибнет.
##
## Став галькой, тело отстаёт от газа: встречный ветер сносит его к звезде
## (GameData.gas_drift), а скорость набирается и гасится заметно медленнее.

signal burned_up

const ACCEL_FACTOR := 3.0
const PEBBLE_ACCEL_FACTOR := 1.4  # галька тяжелее: тяга разгоняет её дольше
const GRAIN_TEX := preload("res://assets/player/player_grain.png")
# Галька рисуется шейдером: обломки окрашены по составу, и вид перетекает за ним.
const MIX_SMOOTH_TIME := 1.5
const GRAIN_SCALE := 3.7   # зерно на текстуре занимает ~70% её ширины; видимый размер как у пыли (~2.7 радиуса)
const SPIN_SPEED := 0.15   # медленное вращение комка, рад/с
const TRAIL_POINTS := 20
const TRAIL_STEP := 0.035  # секунд между точками следа
const BURN_RATE := 0.9     # скорость испарения при максимальном нагреве (с площади поверхности)

var velocity := Vector2.ZERO        # собственное движение относительно окружающей пыли
var frame_velocity := Vector2.ZERO  # орбитальное движение вокруг звезды вместе с пылью
var drift_velocity := Vector2.ZERO  # снос встречным ветром газа (только у гальки)
var pebble_k := 0.0                 # 0 — пылинка, 1 — галька (плавная смена облика)
var move_input := Vector2.ZERO  # задаётся стиком, длина 0..1
var radius := GameData.BASE_RADIUS
var body_color := Color.WHITE
var _pulse := 0.0
var _spin := 0.0
var _trail: Array[Vector2] = []  # след в мировых координатах, летит по орбите вместе с пылью
var _trail_timer := 0.0
var _glow_tex := _make_glow()
var _grain := Sprite2D.new()  # сам комок: отдельный спрайт, чтобы его освещала звезда
var _pebble := Sprite2D.new()  # процедурная галька, проступает при переходе
var _mix := Vector4(0.25, 0.25, 0.25, 0.25)  # сглаженные доли состава для шейдера
var temperature := GameData.SPACE_TEMP
var burn := 0.0      # 0..1: насколько быстро сейчас испаряется вещество
var dead := false


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	position = GameState.player_position
	radius = target_radius()
	_update_color()
	GameState.absorbed.connect(_on_absorbed)
	GameState.skills_changed.connect(queue_redraw)
	_grain.texture = GRAIN_TEX
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/lit_grain.gdshader")
	_grain.material = mat
	add_child(_grain)
	var body := ShaderMaterial.new()
	body.shader = preload("res://shaders/pebble_body.gdshader")
	body.set_shader_parameter("seed", randf())
	_pebble.material = body
	# Шейдеру нужна только площадка того же размера, что у зерна.
	var blank := Image.create(GRAIN_TEX.get_width(), GRAIN_TEX.get_height(), false, Image.FORMAT_L8)
	blank.fill(Color.WHITE)
	_pebble.texture = ImageTexture.create_from_image(blank)
	add_child(_pebble)
	_mix = _target_mix()
	pebble_k = 1.0 if GameState.is_pebble() else 0.0
	GameState.stage_reached.connect(_on_stage_reached)


func _on_stage_reached(index: int) -> void:
	if index == GameData.PEBBLE_STAGE:
		create_tween().tween_property(self, "pebble_k", 1.0, 2.5).set_trans(Tween.TRANS_SINE)


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


## Скорость удара, до которой гальки слипаются. Лёд липкий: чем больше льда в
## составе, тем мягче можно сталкиваться.
func stick_speed() -> float:
	var ice: float = GameData.composition(GameState.materials).get("ice", 0.0)
	return GameData.STICK_SPEED * pow(radius / GameData.PEBBLE_REF_RADIUS, 0.4) \
		* Skills.stat("stick") * (1.0 + 0.6 * ice)


## Скорость относительно окружающей пыли и газа: своё движение плюс снос ветром.
func motion() -> Vector2:
	return velocity + drift_velocity


# Движение в _process (каждый кадр отрисовки), а не на шаге физики: иначе на
# экранах с частотой выше 60 Гц пылинка двигается рывками.
func _process(delta: float) -> void:
	if dead:
		# Облако пара продолжает лететь по орбите, камера — за ним.
		position += GameData.orbit_velocity(position) * delta
		return
	var dir := move_input + _keyboard_input()
	dir = dir.limit_length(1.0)
	var top := max_speed()
	var accel := lerpf(ACCEL_FACTOR, PEBBLE_ACCEL_FACTOR * Skills.stat("thrust"), pebble_k)
	velocity = velocity.move_toward(dir * top, top * accel * delta)
	# Игрок вместе со всей пылью вокруг летит по орбите, стик добавляет своё движение.
	frame_velocity = GameData.orbit_velocity(position)
	drift_velocity = GameData.gas_drift(position, radius) * Skills.stat("drift") * pebble_k
	position += (velocity + drift_velocity + frame_velocity) * delta

	_update_heat(delta)
	if dead:
		return

	radius = lerpf(radius, target_radius(), 1.0 - exp(-4.0 * delta))
	_spin += (SPIN_SPEED + velocity.length() / maxf(radius, 1.0) * 0.05) * delta
	_update_trail(delta)
	_pulse = maxf(0.0, _pulse - delta * 4.0)
	GameState.player_position = position
	queue_redraw()


## Нагрев излучением звезды. Выше температуры испарения вещество уходит в газ
## с поверхности (поэтому быстрее при большой площади), тело тает и уменьшается.
## Касание поверхности звезды или полное испарение — гибель.
func _update_heat(delta: float) -> void:
	var dist := position.length()
	temperature = GameData.temperature_at(dist)
	burn = clampf((temperature - GameData.SUBLIMATION_TEMP) / (GameData.SURFACE_TEMP - GameData.SUBLIMATION_TEMP), 0.0, 1.0)
	if burn > 0.0:
		GameState.ablate(BURN_RATE * pow(GameState.mass, 2.0 / 3.0) * burn * burn * delta)
	if dist < GameData.STAR_RADIUS + radius * 0.5 or GameState.mass < GameData.DEATH_MASS:
		die()


func die() -> void:
	if dead:
		return
	dead = true
	velocity = Vector2.ZERO
	GameState.burned_up = true
	_grain.visible = false
	_pebble.visible = false
	queue_redraw()
	burned_up.emit()


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
	if dead:
		return
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
	var heat_col := GameData.thermal_color(temperature)
	if heat_col.a > 0.0:
		# Раскалённое тело светит вокруг себя своим цветом.
		var hs := r * (4.0 + 5.0 * heat_col.a)
		draw_texture_rect(_glow_tex, Rect2(-hs * 0.5, -hs * 0.5, hs, hs), false, Color(heat_col, 0.6 * heat_col.a))
	_update_grain(r)


## Комок поворачивается, а свет всегда идёт от звезды: переводим направление
## на звезду в координаты спрайта.
func _update_grain(r: float) -> void:
	var to_star := (-position).normalized().rotated(-_spin)
	var heat_col := GameData.thermal_color(temperature)
	for sprite in [_grain, _pebble]:
		sprite.rotation = _spin
		sprite.scale = Vector2.ONE * r * GRAIN_SCALE / GRAIN_TEX.get_width()
		var mat := sprite.material as ShaderMaterial
		mat.set_shader_parameter("light_dir", to_star)
		mat.set_shader_parameter("star_light", Color(1.0, 0.9, 0.75) * (1.0 + 0.9 * Star.flare))
		mat.set_shader_parameter("emission", Vector4(heat_col.r, heat_col.g, heat_col.b, heat_col.a))
	# Галька темнее и плотнее рыхлой пылинки: цвет состава почти без осветления.
	_grain.modulate = Color(body_color.lightened(0.5 + 0.3 * _pulse), 1.0 - pebble_k)
	_grain.visible = pebble_k < 1.0
	_pebble.visible = pebble_k > 0.0
	if _pebble.visible:
		_mix = _mix.lerp(_target_mix(), 1.0 - exp(-get_process_delta_time() / MIX_SMOOTH_TIME))
		var body := _pebble.material as ShaderMaterial
		body.set_shader_parameter("mix_w", _mix)
		body.set_shader_parameter("growth", clampf(log(maxf(GameState.mass, 30.0) / 30.0) / log(100.0), 0.0, 1.0))
		_pebble.modulate = Color(Color.WHITE * (1.1 + 0.3 * _pulse), pebble_k)


## Доли веществ для шейдера гальки. Пока состав не сложился — поровну.
func _target_mix() -> Vector4:
	var shares := GameData.composition(GameState.materials)
	var v := Vector4(shares.get("silicate", 0.0), shares.get("metal", 0.0), shares.get("carbon", 0.0), shares.get("ice", 0.0))
	var total := v.x + v.y + v.z + v.w
	return v / total if total > 0.0 else Vector4(0.25, 0.25, 0.25, 0.25)
