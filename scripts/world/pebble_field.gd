class_name PebbleField
extends Node2D
## Чужие гальки на этапе «Галька».
##
## Гальки, как и игрок, отстают от газа и дрейфуют к звезде, причём крупные быстрее.
## В кольцах-ловушках давления дрейф меняет знак, поэтому гальки там копятся.
## Столкновение решает скорость удара: медленно — гальки слипаются, быстро —
## откалываются осколки, а на большой скорости чужая галька разлетается целиком.
## Осколки становятся обычной пылью, её можно собрать обратно.
##
## Галек немного (до MAX_PEBBLES), поэтому все рисуются одним MultiMesh, который
## переписывается каждый кадр.

signal evaporated(world_position: Vector2, grain_radius: float)

const ATLAS := preload("res://assets/pebbles/pebble_atlas.png")
const SHADER := preload("res://shaders/pebble.gdshader")
const MAX_PEBBLES := 140
const BASE_COUNT := 22               # галек в округе при плотности 1 (вне колец)
const RING_BOOST := 2.5               # в кольце-ловушке галек больше
# Радиусы чужих галек в долях радиуса игрока: тела одного размера дрейфуют вместе,
# поэтому рядом в основном гальки, сравнимые с тобой.
const R_RANGE := Vector2(0.35, 1.3)
const QUAD := 2.8                     # сторона квадрата в радиусах гальки
const DRAG := 0.5                     # доля собственной скорости, остающаяся через секунду
const VALUE_PER_MASS := 4.2           # звёздная пыль за единицу массы гальки
const RESTITUTION := 0.35             # сколько скорости остаётся после отскока
const HINT_RANGE := 7.0               # в радиусах игрока: где видно кольцо-подсказку удара

class Pebble:
	var pos: Vector2  # в системе отсчёта пыли (мир = pos + dust_field.frame_offset)
	var vel: Vector2  # собственная скорость после ударов, гаснет
	var r: float
	var material: String
	var cell: int
	var angle: float
	var spin: float

var player: Player
var dust_field: DustField
var camera: Camera2D
var pebbles: Array[Pebble] = []
var rng := RandomNumberGenerator.new()
var _mm := MultiMesh.new()
var _mm_node := MultiMeshInstance2D.new()
var _buf := PackedFloat32Array()
var _hint := Node2D.new()  # кольца-подсказки поверх галек


func _ready() -> void:
	rng.randomize()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_mm.transform_format = MultiMesh.TRANSFORM_2D
	_mm.use_custom_data = true
	_mm.mesh = quad
	_mm.instance_count = MAX_PEBBLES
	_mm.custom_aabb = AABB(Vector3(-1e6, -1e6, -1.0), Vector3(2e6, 2e6, 2.0))
	_mm.visible_instance_count = 0
	_buf.resize(MAX_PEBBLES * 12)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("atlas", ATLAS)
	mat.set_shader_parameter("star_radius", GameData.STAR_RADIUS)
	mat.set_shader_parameter("heat_start", GameData.HEAT_START)
	mat.set_shader_parameter("snow_line", GameData.SNOW_LINE)
	mat.set_shader_parameter("snow_width", GameData.SNOW_LINE_WIDTH)
	_mm_node.multimesh = _mm
	_mm_node.material = mat
	add_child(_mm_node)
	_hint.draw.connect(_draw_hints)
	add_child(_hint)


func world_pos(p: Pebble) -> Vector2:
	return p.pos + dust_field.frame_offset


func _process(delta: float) -> void:
	if player.pebble_k <= 0.0:
		return
	var to_star := -player.position.normalized()
	_mm_node.material.set_shader_parameter("light_dir", Vector2(to_star.x, -to_star.y))
	_mm_node.material.set_shader_parameter("star_light", DustField.STAR_LIGHT * (1.0 + 0.9 * Star.flare))
	_maintain()
	var drag := pow(DRAG, delta)
	var evap := GameData.sublimation_distance()
	var i := pebbles.size() - 1
	while i >= 0:
		var p := pebbles[i]
		var wp := world_pos(p)
		p.vel *= drag
		p.pos += (p.vel + GameData.gas_drift(wp, p.r)) * delta
		p.angle += p.spin * delta
		if wp.length() < evap:
			evaporated.emit(wp, p.r)
			pebbles.remove_at(i)
		elif not player.dead:
			_collide(p, i)
		i -= 1
	_write()
	_hint.queue_redraw()


## Гальки появляются за краем экрана, в кольцах-ловушках чаще.
func _maintain() -> void:
	var view_r := dust_field.view_radius()
	var active_r := view_r * 1.4
	var pp := player.position
	var i := pebbles.size() - 1
	while i >= 0:
		if world_pos(pebbles[i]).distance_to(pp) > active_r * 1.2:
			pebbles.remove_at(i)
		i -= 1
	var density := GameData.radial_density(pp.length()) * (1.0 + RING_BOOST * GameData.trap_strength(pp.length()))
	# Число галек в округе не растёт с приближением камеры: иначе рост ускорялся бы сам собой.
	var target := mini(int(BASE_COUNT * clampf(density, 0.3, 2.5) * Skills.stat("pebbles") * player.pebble_k), MAX_PEBBLES)
	var budget := 6
	while pebbles.size() < target and budget > 0:
		budget -= 1
		var at := pp + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf_range(pow(view_r * 1.05, 2), active_r * active_r))
		_spawn(at)


func _spawn(at: Vector2) -> void:
	var dist := at.length()
	if dist < GameData.sublimation_distance() * 1.1:
		return
	# Вне колец часть мест пустует: там ветер уносит гальки.
	if rng.randf() > 0.35 + 0.65 * GameData.trap_strength(dist):
		return
	var p := Pebble.new()
	p.pos = at - dust_field.frame_offset
	p.r = player.radius * lerpf(R_RANGE.x, R_RANGE.y, pow(rng.randf(), 1.4))
	p.material = GameData.pick_weighted(GameData.material_weights(dist), rng)
	p.cell = GameData.MATERIAL_ORDER.find(p.material) * 4 + rng.randi() % 4
	p.angle = rng.randf() * TAU
	p.spin = rng.randf_range(-0.25, 0.25)
	pebbles.append(p)


## Можно ли присоединить гальку: она должна быть заметно меньше тебя.
func absorbable(p: Pebble) -> bool:
	return p.r < player.radius * 0.92


func _collide(p: Pebble, index: int) -> void:
	var wp := world_pos(p)
	var to := wp - player.position
	var dist := to.length()
	var contact := player.radius + p.r * 0.92
	if dist >= contact or dist < 0.001:
		return
	var n := to / dist
	var drift_p := GameData.gas_drift(wp, p.r)
	var rel := player.motion() - (p.vel + drift_p)
	var impact := rel.dot(n)  # скорость сближения вдоль линии удара
	var stick := player.stick_speed()
	var at := player.position + n * player.radius
	if absorbable(p) and impact <= stick:
		var m := GameData.pebble_mass(p.r)
		GameState.absorb_mass(m, m * VALUE_PER_MASS, p.material, at)
		pebbles.remove_at(index)
		return
	if impact > stick:
		var excess := impact / stick
		var m_other := GameData.pebble_mass(p.r)
		var loss := minf(GameData.CHIP_K * m_other * (excess * excess - 1.0), GameState.mass * GameData.CHIP_MAX) * Skills.stat("chip")
		var player_mat := _main_material()
		GameState.chip(loss, at)
		_debris(at, n * -1.0, impact, player_mat, clampi(int(loss * 6.0), 3, 14))
		if absorbable(p) and excess > GameData.SHATTER_FACTOR:
			# Чужая галька разлетается целиком: её вещество становится пылью.
			_debris(wp, n, impact, p.material, clampi(int(p.r * 2.5), 6, 22))
			pebbles.remove_at(index)
			_bounce(n, impact, p, 0.3)
			return
	_bounce(n, maxf(impact, 0.0), p, 1.0)
	# Расталкиваем, чтобы тела не застряли друг в друге.
	var push := contact - dist + 0.5
	player.position -= n * push * 0.5
	p.pos += n * push * 0.5


## Отскок: у кого меньше масса, того отбрасывает сильнее.
func _bounce(n: Vector2, impact: float, p: Pebble, k: float) -> void:
	var m_player := GameState.mass
	var m_other := GameData.pebble_mass(p.r)
	var share := m_other / (m_player + m_other)
	player.velocity -= n * impact * (1.0 + RESTITUTION) * share * k
	p.vel += n * impact * (1.0 + RESTITUTION) * (1.0 - share) * k


func _main_material() -> String:
	var best := "silicate"
	var amount := -1.0
	for key in GameState.materials:
		if GameState.materials[key] > amount:
			amount = GameState.materials[key]
			best = key
	return best


## Осколки разлетаются веером от точки удара и становятся обычной пылью.
func _debris(at: Vector2, dir: Vector2, impact: float, material: String, count: int) -> void:
	for k in count:
		var d := dir.rotated(rng.randf_range(-1.3, 1.3))
		var speed := impact * rng.randf_range(0.5, 1.3) + 20.0
		var level := 1 + int(rng.randf() < 0.45) + int(rng.randf() < 0.15)
		dust_field.add_debris(at + d * rng.randf_range(0.5, 2.5), d * speed, mini(level, Skills.max_dust_level()), material)


func _write() -> void:
	var off := dust_field.frame_offset
	for k in pebbles.size():
		var p := pebbles[k]
		var s := p.r * QUAD
		var b := k * 12
		var pos := p.pos + off
		_buf[b] = s
		_buf[b + 1] = 0.0
		_buf[b + 2] = 0.0
		_buf[b + 3] = pos.x
		_buf[b + 4] = 0.0
		_buf[b + 5] = s
		_buf[b + 6] = 0.0
		_buf[b + 7] = pos.y
		_buf[b + 8] = p.cell
		_buf[b + 9] = p.angle
		_buf[b + 10] = 0.0
		_buf[b + 11] = 0.0
	_mm.buffer = _buf
	_mm.visible_instance_count = pebbles.size()


## Дуга со стороны игрока подсказывает, чем кончится удар на текущей скорости:
## зелёная — слипнетесь, красная — полетят осколки. Слишком крупные гальки
## обведены пунктиром: их не присоединить, только оттолкнуть.
func _draw_hints() -> void:
	if player.dead:
		return
	var px := 1.0 / camera.zoom.x
	var stick := player.stick_speed()
	for p in pebbles:
		var wp := world_pos(p)
		var to := wp - player.position
		var dist := to.length()
		var range_r := player.radius * HINT_RANGE
		if dist > range_r:
			continue
		var fade := clampf((range_r - dist) / (range_r * 0.4), 0.0, 1.0)
		var rr := p.r * 1.25
		if not absorbable(p):
			for s in 12:
				var a0 := s * TAU / 12.0
				_hint.draw_arc(wp, rr, a0, a0 + TAU / 24.0, 4, Color(0.8, 0.85, 1.0, 0.35 * fade), 1.5 * px, true)
			continue
		var n := to / maxf(dist, 0.001)
		var approach := (player.motion() - GameData.gas_drift(wp, p.r)).dot(n)
		var ok := approach <= stick
		var col := Color(0.5, 1.0, 0.55) if ok else Color(1.0, 0.32, 0.25)
		var face := (-to).angle()
		_hint.draw_arc(wp, rr, face - 1.1, face + 1.1, 20, Color(col, 0.85 * fade), 2.5 * px, true)
		_hint.draw_arc(wp, rr, face + 1.1, face + TAU - 1.1, 28, Color(col, 0.2 * fade), 1.2 * px, true)
