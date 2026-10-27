class_name Giant
extends Node2D
## Странник: на этапе «Галька» мимо иногда проплывает огромный валун, в десятки раз
## крупнее тебя. В диске тела всех размеров летят рядом, и тот, кем ты станешь,
## уже существует. Съесть его нельзя: он расталкивает гальки на своём пути, о него
## можно удариться, а за ним тянется шлейф пыли, сорванной встречным газом.

const FIRST_DELAY := 100.0        # после начала этапа «Галька», с
const INTERVAL := Vector2(150.0, 230.0)
const SIZE := Vector2(9.0, 14.0)  # радиус в твоих радиусах
const CROSS_TIME := 34.0          # за сколько пересекает экран
const MIN_MASS := 45.0            # пока галька совсем мала, ей хватает своих забот
const SHED_RATE := 7.0            # пылинок в секунду с подветренного края
const BOUNCE := 0.35
const BAKE_SIZE := 1024

var pebble_field: PebbleField
var dust_field: DustField
var player: Player
var radius := 0.0
var active := false
var _pos := Vector2.ZERO   # в системе отсчёта пыли
var _vel := Vector2.ZERO
var _travel := 0.0
var _length := 0.0
var _spin := 0.0
var _timer := FIRST_DELAY
var _shed := 0.0
var _sprite := Sprite2D.new()
var _bake := SubViewport.new()
var _bake_mat := ShaderMaterial.new()
var _rng := RandomNumberGenerator.new()

signal appeared(world_position: Vector2)


func _ready() -> void:
	_rng.randomize()
	# Рельеф дорогой: печём его в текстуру (giant_bake), а каждый кадр считаем
	# только свет (giant_rock). Печём заранее — при загрузке и сразу после ухода
	# прошлого Странника, когда его нет на экране, а не в миг появления.
	_bake.size = Vector2i(BAKE_SIZE, BAKE_SIZE)
	_bake.transparent_bg = true
	_bake.use_hdr_2d = true  # высота в 8 битах дала бы ступеньки на свету
	_bake.disable_3d = true
	_bake.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var rect := ColorRect.new()
	rect.size = Vector2(BAKE_SIZE, BAKE_SIZE)
	_bake_mat.shader = preload("res://shaders/giant_bake.gdshader")
	rect.material = _bake_mat
	_bake.add_child(rect)
	add_child(_bake)
	_prebake()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/giant_rock.gdshader")
	_sprite.material = mat
	_sprite.texture = _bake.get_texture()
	_sprite.visible = false
	add_child(_sprite)


func world_center() -> Vector2:
	return _pos + dust_field.frame_offset


func update(delta: float) -> void:
	if not active:
		if GameState.stage != 1 or GameState.is_boulder() or GameState.mass < MIN_MASS or player.pebble_k < 1.0:
			return
		_timer -= delta
		if _timer <= 0.0:
			_timer = _rng.randf_range(INTERVAL.x, INTERVAL.y)
			_spawn()
		return
	if GameState.is_boulder() or player.dead:
		_despawn()
		return
	_pos += _vel * delta
	_travel += _vel.length() * delta
	_spin += delta * 0.02
	if _travel > _length:
		_despawn()
		return
	var c := world_center()
	_collide_player(c)
	_shed_dust(c, delta)
	_draw_sprite(c)


func _spawn() -> void:
	var view_r := dust_field.view_radius()
	radius = player.radius * _rng.randf_range(SIZE.x, SIZE.y)
	# Плывёт поперёк экрана и проходит рядом с тобой: край в паре твоих радиусов.
	var dir := Vector2.from_angle(_rng.randf() * TAU)
	var side := dir.orthogonal() * (1.0 if _rng.randf() < 0.5 else -1.0)
	var miss := radius + player.radius * _rng.randf_range(2.0, 5.0)
	var start := player.position + side * miss - dir * (view_r + radius * 1.1)
	if start.length() < GameData.sublimation_distance() * 1.1 or (start + dir * 2.0 * (view_r + radius)).length() < GameData.sublimation_distance() * 1.1:
		_timer = 20.0
		return
	_length = 2.0 * (view_r + radius * 1.1)
	_vel = dir * _length / CROSS_TIME
	_pos = start - dust_field.frame_offset
	_travel = 0.0
	_spin = _rng.randf() * TAU
	active = true
	var mat := _sprite.material as ShaderMaterial
	var w := Vector4(_rng.randf_range(0.3, 0.6), _rng.randf_range(0.05, 0.25), _rng.randf_range(0.1, 0.35), _rng.randf_range(0.0, 0.2))
	mat.set_shader_parameter("mix_w", w / (w.x + w.y + w.z + w.w))
	_sprite.visible = true
	appeared.emit(start)


func _despawn() -> void:
	active = false
	_sprite.visible = false
	_prebake()


## Следующий Странник — новая глыба: печём её рельеф, пока его нет на экране.
func _prebake() -> void:
	_bake_mat.set_shader_parameter("seed", _rng.randf())
	_bake.render_target_update_mode = SubViewport.UPDATE_ONCE


func _draw_sprite(c: Vector2) -> void:
	_sprite.position = c
	_sprite.rotation = _spin
	_sprite.scale = Vector2.ONE * radius * Player.PEBBLE_SCALE / BAKE_SIZE
	var mat := _sprite.material as ShaderMaterial
	mat.set_shader_parameter("light_dir", (-c).normalized().rotated(-_spin))
	mat.set_shader_parameter("star_light", Color(1.0, 0.9, 0.75) * (1.0 + 0.9 * Star.flare))


## Ты — мелочь рядом с ним: удар отбрасывает тебя, а его не сдвинуть.
func _collide_player(c: Vector2) -> void:
	var to := player.position - c
	var d := to.length()
	var contact := radius * 0.93 + player.radius
	if d >= contact or d < 0.001:
		return
	var n := to / d
	player.position = c + n * contact
	var rel := player.velocity - _vel
	var into := rel.dot(n)
	if into < 0.0:
		player.velocity -= n * into * (1.0 + BOUNCE)
		if -into > player.stick_speed() * 0.6:
			pebble_field.spray(player.position - n * player.radius, n, -into)


## Встречный газ срывает пыль с его подветренного края: за ним тянется шлейф еды.
func _shed_dust(c: Vector2, delta: float) -> void:
	_shed += SHED_RATE * delta
	var back := -_vel.normalized()
	while _shed >= 1.0:
		_shed -= 1.0
		var a := back.rotated(_rng.randf_range(-0.9, 0.9))
		var at := c + a * radius * _rng.randf_range(0.95, 1.1)
		var level := 1 + int(_rng.randf() < 0.4) + int(_rng.randf() < 0.12)
		dust_field.add_debris(at, _vel * 0.3 + a * _rng.randf_range(5.0, 25.0) * GameData.world_k, mini(level, Skills.max_dust_level()), "silicate")


## Гальки на его пути не исчезают: он расталкивает их, как ледокол, и гонит
## перед собой. Удар быстрее предела слипания выбивает из гальки пыль.
func shove(p: PebbleField.Pebble, wp: Vector2) -> void:
	if not active:
		return
	var c := world_center()
	var to := wp - c
	var contact := radius * 0.93 + p.r * 0.92
	var d2 := to.length_squared()
	if d2 >= contact * contact or d2 < 0.000001:
		return
	var d := sqrt(d2)
	var n := to / d
	p.pos += n * (contact - d)
	var into := (p.vel - _vel).dot(n)
	if into < 0.0:
		p.vel -= n * into * (1.0 + BOUNCE)
		p.spin = clampf(p.spin + _rng.randf_range(-1.0, 1.0) * -into / maxf(p.r, 1.0), -3.0, 3.0)
		if -into > player.stick_speed() and p.hit_cd <= 0.0:
			p.hit_cd = 0.3
			pebble_field.spray_from(wp - n * p.r, n, -into * 0.5, p.material)
