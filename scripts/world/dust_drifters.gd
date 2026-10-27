class_name DustDrifters
extends Node2D
## Пролетающая мимо галька на этапе пылинки.
##
## Камешек — тот, кем ты скоро станешь. Он в тысячу раз крупнее тебя, поэтому
## на экран попадает только его край: почти прямая стена, которая
## медленно проплывает мимо. Вблизи видно, из чего он сложен: хондры, светлые
## включения, искры металла в тёмной матрице. Пыль на пути он сметает, а от
## его края ты отскакиваешь.

signal appeared(kind: String, world_position: Vector2)

const HERALD_FIRST := 55.0
const HERALD_INTERVAL := Vector2(100.0, 150.0)
const HERALD_SIZE := 1000.0         # радиус гальки в твоих радиусах: край на экране почти прямой
const HERALD_GAP := Vector2(6.0, 12.0)  # край проходит в стольких твоих радиусах
const HERALD_CROSS := 30.0          # за сколько проплывает мимо, с
const HERALD_SPIN := 0.012          # медленное вращение, рад/с
const HERALD_LIT_CONE := 1.2        # отклонение от «звезда за спиной», рад: край к тебе освещён
const TILE := 45.0                  # плитка поверхности в твоих радиусах
const TILE_SIZE := 1024
const QUAD := 1.08
# Неровный каменный край: гармоники по углу, амплитуды в твоих радиусах (форма
# тела целиком не видна никогда). Те же числа в herald_rock.gdshader.
const LUMP_K: Array[float] = [61.0, 97.0, 157.0, 241.0, 373.0, 587.0]
const LUMP_AMP: Array[float] = [2.0 / HERALD_SIZE, 1.5 / HERALD_SIZE, 1.4 / HERALD_SIZE,
		1.0 / HERALD_SIZE, 0.7 / HERALD_SIZE, 0.4 / HERALD_SIZE]

var player: Player
var dust_field: DustField
var _rng := RandomNumberGenerator.new()

var herald_active := false
var herald_radius := 0.0
var _h_timer := HERALD_FIRST
var _h_pos := Vector2.ZERO   # в системе отсчёта пыли
var _h_vel := Vector2.ZERO
var _h_travel := 0.0
var _h_length := 0.0
var _h_spin := 0.0
var _lump_a := PackedFloat32Array()
var _lump_p := PackedFloat32Array()
var _h_sprite := Sprite2D.new()
var _baked := false


func _ready() -> void:
	_rng.randomize()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/herald_rock.gdshader")
	_h_sprite.material = mat
	var blank := Image.create(16, 16, false, Image.FORMAT_L8)
	blank.fill(Color.WHITE)
	_h_sprite.texture = ImageTexture.create_from_image(blank)
	_h_sprite.visible = false
	add_child(_h_sprite)
	_lump_a.resize(LUMP_K.size())
	_lump_p.resize(LUMP_K.size())
	if GameState.stage == 0:
		_bake_tiles()


## Поверхность печём один раз при загрузке: дорогой шум хондр рисуется в две
## плитки (альбедо и рельеф), с них снимаются мип-уровни, чтобы узор не рябил
## у края шара, где он сжимается. Каждая галька потом — та же плитка со своим
## сдвигом, оттенком и силуэтом.
func _bake_tiles() -> void:
	var vps: Array[SubViewport] = []
	for pass_id in 2:
		var vp := SubViewport.new()
		vp.size = Vector2i(TILE_SIZE, TILE_SIZE)
		vp.use_hdr_2d = pass_id == 1  # высота в 8 битах дала бы ступеньки на свету
		vp.disable_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		var rect := ColorRect.new()
		rect.size = Vector2(TILE_SIZE, TILE_SIZE)
		var bm := ShaderMaterial.new()
		bm.shader = preload("res://shaders/herald_tile_bake.gdshader")
		bm.set_shader_parameter("pass_id", pass_id)
		bm.set_shader_parameter("seed", _rng.randf())
		rect.material = bm
		vp.add_child(rect)
		add_child(vp)
		vps.append(vp)
	# Обе плитки с одним зерном, иначе рельеф не совпадёт с рисунком.
	(vps[1].get_child(0).material as ShaderMaterial).set_shader_parameter("seed",
			(vps[0].get_child(0).material as ShaderMaterial).get_shader_parameter("seed"))
	await RenderingServer.frame_post_draw
	var mat := _h_sprite.material as ShaderMaterial
	for pass_id in 2:
		var img := vps[pass_id].get_texture().get_image()
		if pass_id == 1:
			img.convert(Image.FORMAT_RGH)  # высота и маска хондр, полуточность
		img.generate_mipmaps()
		mat.set_shader_parameter("color_tex" if pass_id == 0 else "height_tex", ImageTexture.create_from_image(img))
		vps[pass_id].queue_free()
	_baked = true


## Идут ли события: только пылинка, после обучения и пока жив.
func _allowed() -> bool:
	return GameState.stage == 0 and GameState.tutorial_done and player.pebble_k <= 0.0 and not player.dead


func _process(delta: float) -> void:
	if not _allowed():
		if herald_active:
			_herald_end()
		return
	_update_herald(delta)


func herald_center() -> Vector2:
	return _h_pos + dust_field.frame_offset


## Ближайшая к тебе точка края: туда смотрит подсказка.
func herald_spot() -> Vector2:
	var c := herald_center()
	return c + (player.position - c).normalized() * herald_radius


## Край гальки в направлении (в своей системе, с учётом вращения), в радиусах.
func _edge(local_angle: float) -> float:
	var e := 1.0
	for i in LUMP_K.size():
		e += _lump_a[i] * sin(LUMP_K[i] * local_angle + _lump_p[i])
	return e


func _update_herald(delta: float) -> void:
	if not herald_active:
		_h_timer -= delta
		if _h_timer <= 0.0 and _baked:
			_h_timer = _rng.randf_range(HERALD_INTERVAL.x, HERALD_INTERVAL.y)
			_herald_start()
		return
	_h_pos += _h_vel * delta
	_h_travel += _h_vel.length() * delta
	_h_spin += HERALD_SPIN * delta
	if _h_travel > _h_length:
		_herald_end()
		return
	var c := herald_center()
	_h_sprite.position = c
	_h_sprite.rotation = _h_spin
	var mat := _h_sprite.material as ShaderMaterial
	mat.set_shader_parameter("light_dir", (-c).normalized().rotated(-_h_spin))
	mat.set_shader_parameter("star_light", Color(1.0, 0.9, 0.75) * (1.0 + 0.9 * Star.flare))
	_sweep_dust()
	_herald_collide(c)


## Галька плывёт мимо боком: ближе всего её край в паре-тройке твоих радиусов,
## и почти всё время на экране только он. Обычно она снаружи, звезда светит на
## обращённый к тебе край; иногда сбоку — тогда по нему идёт терминатор.
func _herald_start() -> void:
	var view_r := dust_field.view_radius()
	herald_radius = player.radius * HERALD_SIZE
	var outward := player.position.normalized()
	var n := outward.rotated(_rng.randf_range(-HERALD_LIT_CONE, HERALD_LIT_CONE))
	var along := n.orthogonal() * (1.0 if _rng.randf() < 0.5 else -1.0)
	var gap := player.radius * _rng.randf_range(HERALD_GAP.x, HERALD_GAP.y)
	var reach := herald_radius + view_r * 1.05
	var half := sqrt(maxf(reach * reach - pow(herald_radius + gap, 2), 1.0))
	var mid := player.position + n * (herald_radius + gap)
	var start := mid - along * half
	if (start - n * herald_radius).length() < GameData.sublimation_distance() * 1.2:
		_h_timer = 10.0
		return
	_h_length = half * 2.0
	_h_vel = along * _h_length / HERALD_CROSS
	_h_pos = start - dust_field.frame_offset
	_h_travel = 0.0
	_h_spin = _rng.randf() * TAU
	for i in LUMP_K.size():
		_lump_a[i] = LUMP_AMP[i] * _rng.randf_range(0.4, 1.0)
		_lump_p[i] = _rng.randf() * TAU
	var mat := _h_sprite.material as ShaderMaterial
	mat.set_shader_parameter("lump_a", _lump_a)
	mat.set_shader_parameter("lump_p", _lump_p)
	mat.set_shader_parameter("quad", QUAD)
	mat.set_shader_parameter("tile", TILE / HERALD_SIZE)
	mat.set_shader_parameter("size_pr", HERALD_SIZE)
	mat.set_shader_parameter("offset", Vector2(_rng.randf(), _rng.randf()) * 10.0)
	# Оттенок по составу: плитка запечена для среднего камня.
	var w := Vector4(_rng.randf_range(0.3, 0.6), _rng.randf_range(0.05, 0.2), _rng.randf_range(0.1, 0.35), _rng.randf_range(0.0, 0.25))
	w /= w.x + w.y + w.z + w.w
	var t := Vector3(1.0, 1.0, 1.0) + Vector3(0.08, 0.03, -0.05) * (w.x - 0.45) * 4.0 \
			- Vector3(0.1, 0.1, 0.1) * (w.z - 0.28) * 4.0 + Vector3(-0.03, 0.0, 0.06) * (w.w - 0.15) * 4.0
	mat.set_shader_parameter("tint", t)
	_h_sprite.scale = Vector2.ONE * herald_radius * QUAD * 2.0 / 16.0
	_h_sprite.position = herald_center()
	_h_sprite.visible = true
	herald_active = true
	appeared.emit("herald", start)


func _herald_end() -> void:
	herald_active = false
	_h_sprite.visible = false


## Пыль на пути галька сметает: пылинки, оказавшиеся внутри, выталкивает на край
## и уносит с собой.
func _sweep_dust() -> void:
	var outer := herald_radius * 1.05
	for d in dust_field.dust:
		if d.idx < 0:
			continue
		var to := d.pos - _h_pos
		var dsq := to.length_squared()
		if dsq > pow(outer + d.r, 2) or dsq < 0.0001:
			continue
		var dist := sqrt(dsq)
		var dir := to / dist
		var e := herald_radius * _edge(dir.rotated(-_h_spin).angle()) + d.r
		if dist < e:
			dust_field.shove(d, _h_pos + dir * e, _h_vel + dir * 6.0)


## Галька в миллиард раз тяжелее: от неё отскакиваешь, её не сдвинуть.
func _herald_collide(c: Vector2) -> void:
	var to := player.position - c
	var d := to.length()
	if d < 0.001 or d > herald_radius * 1.05 + player.radius:
		return
	var n := to / d
	var contact := herald_radius * _edge(n.rotated(-_h_spin).angle()) + player.radius
	if d >= contact:
		return
	player.position = c + n * contact
	var into := (player.velocity - _h_vel).dot(n)
	if into < 0.0:
		player.velocity -= n * into * 1.4
