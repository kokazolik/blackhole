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
signal combo_changed(chain: int, multiplier: float)  # 0 — серия сорвалась или угасла
signal swarm_started(world_position: Vector2)
signal geode_found(world_position: Vector2, value: float)
signal eddy_started(world_position: Vector2)
signal pebble_absorbed(world_position: Vector2)

const ATLAS := preload("res://assets/pebbles/pebble_atlas.png")
const SHADER := preload("res://shaders/pebble.gdshader")
const EDDY_SHADER := preload("res://shaders/eddy.gdshader")
const EDDY_EXTENT := 1.3  # половина стороны квадрата вихря в его радиусах (как EXTENT в шейдере)
const MAX_PEBBLES := 140
const BASE_COUNT := 5               # галек в округе при плотности 1 (вне колец)
const RING_BOOST := 2.5               # в кольце-ловушке галек больше
# Радиусы чужих галек в долях радиуса игрока. Мелких обломков больше, чем крупных
# (распределение как после дробления), но встречаются и тела крупнее тебя.
const R_RANGE := Vector2(0.17, 1.25)
const R_SKEW := 2.2
const SIZE_GAP := 1.35                 # несъедобные — минимум на столько крупнее предела хватки
const QUAD := 2.8                     # сторона квадрата в радиусах гальки
const DRAG := 0.5                     # доля собственной скорости, остающаяся через секунду
# Звёздная пыль за гальку: растёт с твоей массой (как доход в idle-играх) и с тем,
# насколько крупную гальку удалось присоединить.
const VALUE_PER_PEBBLE := 13.0
# При слипании прирастает не всё: часть вещества разлетается пылью и осколками
# (в опытах с пылевыми агрегатами прилипает лишь доля). Это и держит темп этапа.
const ACCRETION := 0.5
const VALUE_MASS_EXP := 0.52          # доход растёт с массой медленнее её самой: книга не скупается за минуту
const MASS_THINNING := 0.3
const THINNING_FROM := 3.33          # в массах начала этапа: до неё тел вокруг столько же, сколько в начале
# Валун: гальки вокруг стали мелочью-едой. Масса с них небольшая, зато звёздной
# пыли много и они прилипают на любой скорости. Растёт валун на малых валунах.
const FOOD_COUNT := 16
const FOOD_R := Vector2(0.18, 0.34)   # в долях радиуса игрока
const FOOD_MASS_R := 0.52            # еда рисуется крупнее, чем весит: иначе её не разглядеть
const FOOD_VALUE := 3.0
const SWARM_COUNT := 16               # галек в рое на первом уровне навыка
const RESTITUTION := 0.35             # сколько скорости остаётся после отскока
const HINT_RANGE := 7.0               # в радиусах игрока: где видно кольцо-подсказку удара
# Вихрь турбулентности: газ закручивает гальки в круговорот. Появляется в стороне
# и стоит на месте — нырять туда или нет, решает игрок. Внутри больше добычи и жеод,
# слипание ценнее, но гальки несутся по кругу: удар против течения раскалывает,
# а кто плывёт по течению, сближается с ними мягко.
const EDDY_INTERVAL := 240.0           # редкое событие: 3–4 раза за этап
const EDDY_DURATION := 30.0
const EDDY_COUNT := 10
const EDDY_VALUE := 1.5               # множитель звёздной пыли за гальку из вихря
const EDDY_SPIN := 1.7                # скорость круговорота в долях скорости слипания

class Pebble:
	var pos: Vector2  # в системе отсчёта пыли (мир = pos + dust_field.frame_offset)
	var vel: Vector2  # собственная скорость после ударов, гаснет
	var r: float
	var material: String
	var cell: int
	var angle: float
	var spin: float
	var geode := false
	var swarm := false  # из роя: рассеивается, когда рой кончился
	var eddy := false   # кружится в вихре
	var food := false   # мелочь на этапе «Валун»: прилипает на любой скорости

var player: Player
var dust_field: DustField
var camera: Camera2D
var pebbles: Array[Pebble] = []
var rng := RandomNumberGenerator.new()
var _mm := MultiMesh.new()
var _mm_node := MultiMeshInstance2D.new()
var _buf := PackedFloat32Array()
var _hint := Node2D.new()  # кольца-подсказки поверх галек
var chain := 0           # шагов в текущей серии слипаний
var _chain_timer := 0.0
var _swarm_timer := -1.0  # до следующего роя; <0 — навыка нет
var swarm_left := 0.0     # сколько ещё длится текущий рой
var eddy_center := Vector2.ZERO  # в системе отсчёта пыли
var eddy_radius := 0.0
var eddy_left := 0.0
var _eddy_timer := EDDY_INTERVAL * 0.6
var _eddy_fx := ColorRect.new()  # закрученный газ под гальками (шейдер eddy)
var _eddy_t := 0.0


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
	var eddy_mat := ShaderMaterial.new()
	eddy_mat.shader = EDDY_SHADER
	_eddy_fx.material = eddy_mat
	_eddy_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_eddy_fx.visible = false
	add_child(_eddy_fx)
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
	_update_combo(delta)
	_update_swarm(delta)
	_update_eddy(delta)
	var drag := pow(DRAG, delta)
	var pull := Skills.stat("pebble_pull")
	var pull_r := player.pull_radius() * 1.5
	var evap := GameData.sublimation_distance()
	var i := pebbles.size() - 1
	while i >= 0:
		var p := pebbles[i]
		var wp := world_pos(p)
		p.vel *= drag
		if p.eddy and eddy_left > 0.0:
			p.vel = p.vel.lerp(eddy_flow(wp), 1.0 - exp(-3.0 * delta))
		if pull > 0.0 and absorbable(p):
			# «Вихрь в газе»: подходящие гальки сами плывут к тебе.
			var to_p := player.position - wp
			var dl := to_p.length()
			if dl < pull_r and dl > 0.001:
				p.vel += to_p / dl * player.pull_strength() * 0.6 * pull * (1.0 - dl / pull_r) * delta
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
	# Чем крупнее ты, тем реже в округе тела, которые тебе по силам: к концу этапа
	# рост не срывается в лавину.
	var stage_mass := GameData.BOULDER_MASS if GameState.is_boulder() else 30.0
	var thin := pow(maxf(GameState.mass / (stage_mass * THINNING_FROM), 1.0), -MASS_THINNING)
	var target := mini(int(BASE_COUNT * clampf(density, 0.3, 2.5) * Skills.stat("pebbles") * player.pebble_k * thin + 0.5), MAX_PEBBLES)
	var food_target := int(FOOD_COUNT * clampf(density, 0.3, 2.5) * Skills.stat("pebbles") * player.boulder_k + 0.5)
	var bodies := 0
	var food := 0
	for p in pebbles:
		if p.food:
			food += 1
		else:
			bodies += 1
	var budget := 8
	while (bodies < target or food < food_target) and budget > 0 and pebbles.size() < MAX_PEBBLES:
		budget -= 1
		var at := pp + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf_range(pow(view_r * 1.05, 2), active_r * active_r))
		if food < food_target and (bodies >= target or rng.randf() < 0.6):
			_spawn_food(at)
			food += 1
		else:
			_spawn(at)
			bodies += 1


func _spawn(at: Vector2) -> void:
	var dist := at.length()
	if dist < GameData.sublimation_distance() * 1.1:
		return
	# Вне колец часть мест пустует: там ветер уносит гальки.
	if rng.randf() > 0.35 + 0.65 * GameData.trap_strength(dist):
		return
	var p := Pebble.new()
	p.pos = at - dust_field.frame_offset
	p.r = player.radius * lerpf(R_RANGE.x, R_RANGE.y, pow(rng.randf(), R_SKEW))
	# Чуть-чуть крупнее предела не бывает: несъедобная галька должна выглядеть
	# заметно крупнее самой большой съедобной, а не «такой же».
	var limit := player.radius * minf(Skills.stat("grip"), 0.95)
	if p.r >= limit and p.r < limit * SIZE_GAP:
		p.r = limit * SIZE_GAP
	p.geode = rng.randf() < Skills.stat("geode")
	p.material = _pick_material(dist)
	p.cell = GameData.MATERIAL_ORDER.find(p.material) * 4 + rng.randi() % 4
	p.angle = rng.randf() * TAU
	p.spin = rng.randf_range(-0.25, 0.25)
	pebbles.append(p)


## Мелкая галька-еда валуна: россыпью, иногда кучкой.
func _spawn_food(at: Vector2) -> void:
	if at.length() < GameData.sublimation_distance() * 1.1:
		return
	var n := mini(1 if rng.randf() < 0.6 else rng.randi_range(2, 4), MAX_PEBBLES - pebbles.size())
	for k in n:
		var p := Pebble.new()
		p.pos = at + Vector2(rng.randfn(0.0, 1.0), rng.randfn(0.0, 1.0)) * player.radius * 0.8 - dust_field.frame_offset
		p.r = player.radius * rng.randf_range(FOOD_R.x, FOOD_R.y)
		p.food = true
		p.material = _pick_material(at.length())
		p.cell = GameData.MATERIAL_ORDER.find(p.material) * 4 + rng.randi() % 4
		p.angle = rng.randf() * TAU
		p.spin = rng.randf_range(-0.4, 0.4)
		pebbles.append(p)


## Галька нужного размера в заданном месте: Звездочёт показывает её новичку.
func spawn_for_guide(at: Vector2, r: float) -> Pebble:
	var p := Pebble.new()
	p.pos = at - dust_field.frame_offset
	p.r = r
	p.material = _pick_material(at.length())
	p.cell = GameData.MATERIAL_ORDER.find(p.material) * 4 + rng.randi() % 4
	p.angle = rng.randf() * TAU
	p.spin = rng.randf_range(-0.25, 0.25)
	pebbles.append(p)
	_write()  # время может стоять, а показать её надо сразу
	return p


## Материал новой гальки: что водится в этой зоне, с перевесом в сторону навыков
## ветви «Состав». Льда у звезды не бывает при любых навыках.
func _pick_material(dist: float) -> String:
	var weights := GameData.material_weights(dist)
	for key in weights:
		weights[key] *= Skills.stat("affinity_" + key)
	return GameData.pick_weighted(weights, rng)


## Можно ли присоединить гальку: предел размера растёт с навыками ветви «Захват».
func absorbable(p: Pebble) -> bool:
	return p.food or p.r < player.radius * minf(Skills.stat("grip"), 0.95)


## Серия гаснет, если долго не слипаться.
func _update_combo(delta: float) -> void:
	if chain > 0:
		_chain_timer -= delta
		if _chain_timer <= 0.0:
			chain = 0
			combo_changed.emit(0, 1.0)


func combo_multiplier() -> float:
	return 1.0 + Skills.stat("combo") * minf(maxf(chain - 1, 0), Skills.stat("combo_cap"))


## Потоковая неустойчивость: раз в интервал рядом сбивается рой мелких галек.
func _update_swarm(delta: float) -> void:
	var lvl := Skills.stat("swarm")
	if lvl <= 0.0:
		return
	if swarm_left > 0.0:
		swarm_left -= delta
		if swarm_left <= 0.0:
			# Рой рассеивается: оставшиеся гальки газ уносит.
			for p in pebbles:
				if p.swarm:
					p.swarm = false
					p.vel += Vector2.from_angle(rng.randf() * TAU) * 30.0
	var interval := GameData.SWARM_INTERVAL / (1.0 + 0.12 * (lvl - 1.0))
	if _swarm_timer < 0.0:
		_swarm_timer = interval * 0.5
	_swarm_timer -= delta
	if _swarm_timer <= 0.0 and not player.dead:
		_swarm_timer = interval
		_spawn_swarm(lvl)


func _spawn_swarm(lvl: float) -> void:
	var view_r := dust_field.view_radius()
	var dir := player.velocity.normalized() if player.velocity.length() > 5.0 else Vector2.from_angle(rng.randf() * TAU)
	var center := player.position + dir.rotated(rng.randf_range(-0.6, 0.6)) * view_r * 0.75
	if center.length() < GameData.sublimation_distance() * 1.3:
		center = player.position + player.position.normalized() * view_r * 0.75
	var spread := view_r * (0.12 + 0.02 * lvl)
	var count := mini(int(SWARM_COUNT * (1.0 + 0.35 * (lvl - 1.0))), MAX_PEBBLES - pebbles.size())
	var grip := minf(Skills.stat("grip"), 0.95)
	for k in count:
		var p := Pebble.new()
		p.pos = center + Vector2(rng.randfn(0.0, spread), rng.randfn(0.0, spread)) - dust_field.frame_offset
		# Рой из галек, которые ты способен присоединить: гоняться за ним есть смысл.
		p.r = player.radius * rng.randf_range(R_RANGE.x, maxf(grip * 0.95, R_RANGE.x))
		p.material = _pick_material(center.length())
		p.cell = GameData.MATERIAL_ORDER.find(p.material) * 4 + rng.randi() % 4
		p.angle = rng.randf() * TAU
		p.spin = rng.randf_range(-0.4, 0.4)
		p.geode = rng.randf() < Skills.stat("geode") * 2.0
		p.swarm = true
		pebbles.append(p)
	swarm_left = GameData.SWARM_DURATION
	swarm_started.emit(center)


## Вихрь появляется сам, без навыка: впереди-сбоку, на краю видимого.
func _update_eddy(delta: float) -> void:
	if eddy_left > 0.0:
		eddy_left -= delta
		var wc := eddy_center + dust_field.frame_offset
		var to_c := player.position - wc
		var d := to_c.length()
		if d < eddy_radius and d > 0.001:
			# Течение подхватывает и тебя.
			player.velocity += (eddy_flow(player.position) - player.velocity) * (1.0 - exp(-0.8 * delta)) * (1.0 - d / eddy_radius)
		if eddy_left <= 0.0:
			for p in pebbles:
				if p.eddy:
					p.eddy = false
		_update_eddy_fx(delta)
		return
	_eddy_fx.visible = false
	_eddy_timer -= delta
	if _eddy_timer <= 0.0 and not player.dead:
		_eddy_timer = EDDY_INTERVAL * rng.randf_range(0.8, 1.2)
		_spawn_eddy()


## Скорость газа в вихре: по кругу, быстрее всего на середине радиуса.
func eddy_flow(world: Vector2) -> Vector2:
	var to := world - (eddy_center + dust_field.frame_offset)
	var d := to.length()
	if d < 0.001 or d > eddy_radius * 1.2:
		return Vector2.ZERO
	var x := d / eddy_radius
	var speed := player.stick_speed() * EDDY_SPIN * x * exp(1.0 - x * x * 2.0) * 0.8
	return to.orthogonal() / d * speed


func _spawn_eddy() -> void:
	var view_r := dust_field.view_radius()
	var dir := player.velocity.normalized() if player.velocity.length() > 5.0 else Vector2.from_angle(rng.randf() * TAU)
	var center := player.position + dir.rotated(rng.randf_range(0.5, 1.0) * (1.0 if rng.randf() < 0.5 else -1.0)) * view_r * 0.85
	if center.length() < GameData.sublimation_distance() * 1.4:
		return
	eddy_radius = view_r * 0.38
	eddy_center = center - dust_field.frame_offset
	eddy_left = EDDY_DURATION
	_eddy_t = 0.0
	(_eddy_fx.material as ShaderMaterial).set_shader_parameter("seed", rng.randf())
	var grip := minf(Skills.stat("grip"), 0.95)
	var count := mini(EDDY_COUNT, MAX_PEBBLES - pebbles.size())
	for k in count:
		var p := Pebble.new()
		var a := rng.randf() * TAU
		var d := eddy_radius * sqrt(rng.randf_range(0.04, 1.0))
		p.pos = eddy_center + Vector2.from_angle(a) * d
		# Половина по зубам, остальные крупнее: сталкиваться с ними на ходу больно.
		if rng.randf() < 0.5:
			p.r = player.radius * rng.randf_range(R_RANGE.x, maxf(grip * 0.95, R_RANGE.x))
		else:
			p.r = player.radius * rng.randf_range(grip * SIZE_GAP, maxf(0.9, grip * SIZE_GAP))
		p.material = _pick_material(center.length())
		p.cell = GameData.MATERIAL_ORDER.find(p.material) * 4 + rng.randi() % 4
		p.angle = rng.randf() * TAU
		p.spin = rng.randf_range(-0.8, 0.8)
		p.geode = rng.randf() < Skills.stat("geode") * 3.0 + 0.02
		p.eddy = true
		p.vel = eddy_flow(p.pos + dust_field.frame_offset)
		pebbles.append(p)
	eddy_started.emit(center)


## Вихрь рисует шейдер: квадрат следует за центром, газ появляется и гаснет.
func _update_eddy_fx(delta: float) -> void:
	_eddy_t += delta
	var c := eddy_center + dust_field.frame_offset
	var half := eddy_radius * EDDY_EXTENT
	_eddy_fx.visible = eddy_left > 0.0
	_eddy_fx.position = c - Vector2(half, half)
	_eddy_fx.size = Vector2(half, half) * 2.0
	var fade := clampf(eddy_left / 3.0, 0.0, 1.0) * clampf((EDDY_DURATION - eddy_left) / 2.0, 0.0, 1.0)
	var ice := smoothstep(GameData.SNOW_LINE - GameData.SNOW_LINE_WIDTH, GameData.SNOW_LINE + GameData.SNOW_LINE_WIDTH, c.length())
	var mat := _eddy_fx.material as ShaderMaterial
	mat.set_shader_parameter("t", _eddy_t)
	mat.set_shader_parameter("fade", fade)
	mat.set_shader_parameter("tint", Color(0.95, 0.8, 0.62).lerp(Color(0.75, 0.88, 1.0), ice))


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
	var stick := player.stick_speed() * Skills.stat("glue_" + p.material)
	var at := player.position + n * player.radius
	if p.food or (absorbable(p) and impact <= stick):
		var m := GameData.pebble_mass(p.r * (FOOD_MASS_R if p.food else 1.0), GameState.mass) * ACCRETION * Skills.stat("accretion") * GameData.boulder_gain(GameState.mass)
		if not p.food:  # серию держат только настоящие слипания, мелочь её не продлевает
			chain += 1
			_chain_timer = GameData.COMBO_WINDOW
		var size_rel := p.r * (FOOD_MASS_R if p.food else 1.0) / player.radius
		var value := VALUE_PER_PEBBLE * pow(GameState.mass / 30.0, VALUE_MASS_EXP) * pow(size_rel / 0.2, 1.5) * combo_multiplier()
		if p.eddy:
			value *= EDDY_VALUE
		if p.food:
			value *= FOOD_VALUE
		if GameState.is_boulder():
			value *= GameData.BOULDER_VALUE
		if p.geode:
			value *= Skills.stat("geode_value")
			geode_found.emit(wp, value)
		GameState.absorb_mass(m, value, p.material, at)
		pebble_absorbed.emit(wp)
		if Skills.stat("combo") > 0.0 and chain >= 2 and not p.food:
			combo_changed.emit(chain, combo_multiplier())
		pebbles.remove_at(index)
		return
	if impact > stick:
		var excess := impact / stick
		var m_other := GameData.pebble_mass(p.r, GameState.mass)
		var loss := minf(GameData.CHIP_K * m_other * (excess * excess - 1.0), GameState.mass * GameData.CHIP_MAX) * Skills.stat("chip")
		var player_mat := _main_material()
		if chain > 0:
			chain = 0
			combo_changed.emit(0, 1.0)
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
	var m_other := GameData.pebble_mass(p.r, GameState.mass)
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
		_buf[b + 11] = 1.0 if p.geode else 0.0
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
	# Пунктиры всех крупных галек — одним вызовом: по вызову на штрих телефон
	# не тянул, когда вокруг рой крупных галек.
	var dash_pts := PackedVector2Array()
	var dash_cols := PackedColorArray()
	for p in pebbles:
		if p.food:
			continue  # мелочь прилипает всегда: подсказка не нужна
		var wp := world_pos(p)
		var to := wp - player.position
		var dist := to.length()
		var range_r := player.radius * HINT_RANGE
		if dist > range_r:
			continue
		var fade := clampf((range_r - dist) / (range_r * 0.4), 0.0, 1.0)
		# Толщина обводки по размеру гальки на экране: у крошечной кольцо не толще её самой.
		var pr := p.r * camera.zoom.x
		var w_face := clampf(pr * 0.2, 0.8, 2.5)
		var w_mat := clampf(pr * 0.13, 0.6, 1.6)
		var rr := p.r * 1.12 + (w_face * 0.5 + 1.0) * px
		if not absorbable(p):
			# Мелкий пунктир вплотную к гальке: заметно, но не спорит с самой галькой.
			var dash_col := Color(0.8, 0.85, 1.0, 0.3 * fade)
			for k in 24:
				var a0 := k * TAU / 24.0
				dash_pts.append(wp + Vector2.from_angle(a0) * p.r * 1.1)
				dash_pts.append(wp + Vector2.from_angle(a0 + TAU / 72.0) * p.r * 1.1)
				dash_cols.append(dash_col)
			continue
		var n := to / maxf(dist, 0.001)
		var approach := (player.motion() - GameData.gas_drift(wp, p.r)).dot(n)
		var ok := approach <= stick * Skills.stat("glue_" + p.material)
		var col := Color(0.5, 1.0, 0.55) if ok else Color(1.0, 0.32, 0.25)
		var face := (-to).angle()
		_hint.draw_arc(wp, rr, face - 1.1, face + 1.1, 20, Color(col, 0.85 * fade), w_face * px, true)
		# Остаток кольца — цвет материала: нужное вещество видно издалека.
		var mat_col: Color = GameData.MATERIALS[p.material].color
		_hint.draw_arc(wp, rr, face + 1.1, face + TAU - 1.1, 28, Color(mat_col, 0.55 * fade), w_mat * px, true)
	if not dash_pts.is_empty():
		_hint.draw_multiline_colors(dash_pts, dash_cols, -1.0)
