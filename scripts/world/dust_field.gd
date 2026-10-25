class_name DustField
extends Node2D
## Вся пыль вокруг игрока: появление, притяжение, поглощение и отрисовка.
##
## Распределение неравномерное, как в настоящем диске: сгустки и нити пыли
## (шум) поверх средней плотности, которая зависит от расстояния до звезды.
##
## Пыль летит по орбите вместе с игроком: в пределах экрана разница орбитальных
## скоростей ничтожна, поэтому вблизи пыль неподвижна относительно игрока.
## Движение по орбите видно по звёздам и туманностям фона.
##
## Оптимизация для телефона:
## - вся пыль рисуется одним MultiMesh (один вызов отрисовки), вращение в шейдере;
## - пыль хранится в координатах орбитальной системы отсчёта: общий полёт по орбите —
##   это сдвиг одного узла, а не перезапись тысяч позиций;
## - каждый кадр обрабатывается только пыль рядом с игроком, полный обход редкий.

# Плотность пыли на единицу площади мира при spawn = 1. Число пылинок вокруг считается
# от площади активной области, поэтому плотность в мире не зависит от приближения камеры.
const DUST_PER_AREA := 0.0022
const MAX_DUST := 2600
const MAX_DENSITY_SCALE := 1.8  # потолок числа пылинок у снеговой линии
const SPAWN_ATTEMPTS := 4
const ATLAS := preload("res://assets/dust/dust_atlas.png")
const DUST_SHADER := preload("res://shaders/dust.gdshader")
const ATLAS_VARIANTS := 4
const QUAD_SCALE := 3.8  # сторона квадрата в радиусах пылинки, как QUAD в шейдере
const MAX_SPAWN_PER_FRAME := 24
const CLUSTER_CHECK := 5.0    # раз в столько секунд бросаем шанс на скопление
const CLUSTER_CHANCE := 0.03  # скопление — редкая находка
const CLUSTER_SIZE := Vector2i(15, 30)
const SPAWN_MARGIN := 24.0  # насколько за краем экрана появляется пыль, в пикселях
const DRAG := 0.55  # доля скорости, остающаяся через секунду
const SCAN_INTERVAL := 0.2  # как часто полный обход: удаление дальней пыли и поиск ближней
const REBASE_DISTANCE := 20000.0
const FLOATS := 16  # на экземпляр: 8 трансформ, 4 цвет, 4 данные

class Dust:
	var pos: Vector2  # в системе отсчёта, летящей по орбите (мир = pos + frame_offset)
	var vel: Vector2
	var level: int
	var material: String
	var r: float
	var idx: int  # место в массиве и в буфере MultiMesh, -1 у удалённой
	var cell: int
	var phase: float

var player: Player
var camera: Camera2D
var dust: Array[Dust] = []
var frame_offset := Vector2.ZERO
var rng := RandomNumberGenerator.new()
var _near: Array[Dust] = []
var _hidden_rect := Rect2()
var _active_count := 0  # пыль в активной области на последнем обходе плюс появившаяся после
var _scan_timer := 0.0
var _cluster_timer := 0.0
var _filled := false
var _clumps := FastNoiseLite.new()
var _rare := FastNoiseLite.new()  # где встречаются плотные нити: ~2% пространства
var _mm_node := MultiMeshInstance2D.new()
var _mm := MultiMesh.new()
var _buf := PackedFloat32Array()
var _dirty := false


func _ready() -> void:
	rng.randomize()
	_cluster_timer = CLUSTER_CHECK
	# Гребневый шум даёт вытянутые нити и сгустки с пустотами между ними.
	_clumps.seed = 1337
	_clumps.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_clumps.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_clumps.fractal_octaves = 3
	_clumps.frequency = 0.0063
	_rare.seed = 4242
	_rare.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_rare.fractal_octaves = 2
	_rare.frequency = 0.0009

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_mm.transform_format = MultiMesh.TRANSFORM_2D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = quad
	_mm.instance_count = MAX_DUST
	_mm.custom_aabb = AABB(Vector3(-1e6, -1e6, -1.0), Vector3(2e6, 2e6, 2.0))
	_mm.visible_instance_count = 0
	_buf.resize(MAX_DUST * FLOATS)
	var mat := ShaderMaterial.new()
	mat.shader = DUST_SHADER
	mat.set_shader_parameter("atlas", ATLAS)
	var level_colors := PackedColorArray()
	for data in GameData.DUST_LEVELS:
		level_colors.append(data.color)
	mat.set_shader_parameter("level_colors", level_colors)
	_mm_node.multimesh = _mm
	_mm_node.material = mat
	add_child(_mm_node)

	GameState.skills_changed.connect(_rewrite_all)


func view_radius() -> float:
	var size := get_viewport_rect().size
	return size.length() * 0.5 / camera.zoom.x


func world_pos(d: Dust) -> Vector2:
	return d.pos + frame_offset


# Движение считается каждый кадр отрисовки, а не на шаге физики: на экранах
# 90–120 Гц и при неровных кадрах так нет подёргиваний.
func _process(delta: float) -> void:
	# Общий полёт по орбите: сдвигается только узел MultiMesh.
	frame_offset += player.frame_velocity * delta
	if frame_offset.length() > REBASE_DISTANCE:
		_rebase()
	_mm_node.position = frame_offset

	var view_r := view_radius()
	var active_r := view_r * 1.35
	_maintain(view_r, active_r, delta)

	var pp := player.position - frame_offset
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = SCAN_INTERVAL
		_scan(pp, active_r)

	var pr := player.radius
	var pull_r := player.pull_radius()
	var strength := player.pull_strength()
	var max_lvl := Skills.max_dust_level()
	var drag := pow(DRAG, delta)
	for d in _near:
		if d.idx < 0:
			continue
		var to := pp - d.pos
		var dist_sq := to.length_squared()
		var edible := d.level <= max_lvl
		if dist_sq < pull_r * pull_r and dist_sq > 0.000001:
			var dist := sqrt(dist_sq)
			var dir := to / dist
			if edible:
				# Пыль не летит прямо, а закручивается по спирали, как в настоящем захвате.
				var k := 0.35 + 0.65 * (1.0 - dist / pull_r)
				d.vel += (dir + dir.orthogonal() * 0.6) * strength * k * delta
			elif dist < pr + d.r + 0.7:
				# Пыль выше открытого уровня отталкивается от поверхности.
				d.pos = pp - dir * (pr + d.r + 0.7)
				d.vel = -dir * maxf(player.velocity.length(), 8.0) * 0.8
				_write_origin(d)
		if d.vel.length_squared() > 0.0001:
			d.vel *= drag
			d.pos += d.vel * delta
			_write_origin(d)
		if edible and d.pos.distance_squared_to(pp) < pow(pr + d.r * 0.5, 2):
			GameState.absorb(d.level, d.material, world_pos(d))
			_remove(d)

	if _dirty:
		_mm.buffer = _buf
		_mm.visible_instance_count = dust.size()
		_dirty = false


## Редкий полный обход: удаляет пыль далеко за экраном и собирает ближнюю,
## которую стоит проверять каждый кадр.
func _scan(pp: Vector2, active_r: float) -> void:
	var despawn_sq := pow(active_r * 1.15, 2)
	var active_sq := active_r * active_r
	# Запас на то, сколько игрок пролетит до следующего обхода.
	var near_r := player.pull_radius() + player.radius + player.max_speed() * SCAN_INTERVAL * 2.0 + 20.0
	var near_sq := near_r * near_r
	_near.clear()
	_active_count = 0
	var i := dust.size() - 1
	while i >= 0:
		var d := dust[i]
		var dist_sq := d.pos.distance_squared_to(pp)
		if dist_sq > despawn_sq:
			_remove(d)
			i -= 1
			continue
		# Плотность считаем только по пыли вокруг игрока: отставшая позади пыль
		# не должна мешать досыпать пыль впереди.
		if dist_sq < active_sq:
			_active_count += 1
		if dist_sq < near_sq or d.vel.length_squared() > 0.0001:
			_near.append(d)
		i -= 1


func _rebase() -> void:
	for d in dust:
		d.pos += frame_offset
		_write_origin(d)
	frame_offset = Vector2.ZERO


func _remove(d: Dust) -> void:
	var i := d.idx
	var last := dust.back() as Dust
	if last != d:
		dust[i] = last
		last.idx = i
		var src := (dust.size() - 1) * FLOATS
		var dst := i * FLOATS
		for k in FLOATS:
			_buf[dst + k] = _buf[src + k]
	dust.pop_back()
	d.idx = -1
	_dirty = true


func _write_origin(d: Dust) -> void:
	var k := d.idx * FLOATS
	_buf[k + 3] = d.pos.x
	_buf[k + 7] = d.pos.y
	_dirty = true


func _write(d: Dust) -> void:
	var k := d.idx * FLOATS
	var s := d.r * QUAD_SCALE
	var col: Color = GameData.MATERIALS[d.material].color
	_buf[k] = s
	_buf[k + 1] = 0.0
	_buf[k + 2] = 0.0
	_buf[k + 3] = d.pos.x
	_buf[k + 4] = 0.0
	_buf[k + 5] = s
	_buf[k + 6] = 0.0
	_buf[k + 7] = d.pos.y
	_buf[k + 8] = col.r
	_buf[k + 9] = col.g
	_buf[k + 10] = col.b
	_buf[k + 11] = 1.0
	_buf[k + 12] = d.cell
	_buf[k + 13] = 1.0 if d.level <= Skills.max_dust_level() else 0.4
	_buf[k + 14] = d.level
	_buf[k + 15] = d.phase
	_dirty = true


## После покупки навыка меняется, какая пыль доступна: обновляем всё.
func _rewrite_all() -> void:
	for d in dust:
		_write(d)


func _maintain(view_r: float, active_r: float, delta: float) -> void:
	var density_scale := clampf(GameData.radial_density(player.position.length()), 0.35, MAX_DENSITY_SCALE)
	var target := mini(int(DUST_PER_AREA * PI * active_r * active_r * Skills.stat("spawn") * density_scale), MAX_DUST - CLUSTER_SIZE.y)
	var spawn_budget := MAX_SPAWN_PER_FRAME
	if not _filled:
		# Первое заполнение: пыль сразу по всему экрану, а не только за краем.
		for n in target:
			_spawn_single(_random_point(0.0, active_r))
		_filled = true
		_scan_timer = 0.0
		return
	# Новая пыль появляется только чуть за краем экрана: на глазах игрока ничего
	# не возникает из пустоты. Условия отбора (расстояние до звезды, сгустки) те же.
	_hidden_rect = _screen_rect_world().grow(SPAWN_MARGIN / camera.zoom.x)
	var min_r := minf(_hidden_rect.size.x, _hidden_rect.size.y) * 0.5
	while _active_count < target and spawn_budget > 0:
		if _spawn_single(_random_point(min_r, active_r), true):
			_active_count += 1
		spawn_budget -= 1

	# Скопление выпадает с небольшим шансом; навык «скоплений» его повышает,
	# а пока пыли мало, скопления ещё и мельче.
	_cluster_timer -= delta
	if _cluster_timer <= 0.0:
		_cluster_timer = CLUSTER_CHECK
		if rng.randf() < CLUSTER_CHANCE * Skills.stat("cluster"):
			_spawn_cluster(_random_point(view_r * 1.15, active_r * 0.95), view_r)


## Случайная точка в мировых координатах в кольце вокруг игрока.
func _random_point(min_r: float, max_r: float) -> Vector2:
	var angle := rng.randf() * TAU
	var r := sqrt(rng.randf_range(min_r * min_r, max_r * max_r))
	return player.position + Vector2.from_angle(angle) * r


func _spawnable_levels() -> int:
	# Видна пыль на один уровень выше открытой, как цель для прокачки.
	return mini(Skills.max_dust_level() + 1, GameData.DUST_LEVELS.size())


func _pick_level(weight_key: String) -> int:
	var weights := {}
	for lvl in range(1, _spawnable_levels() + 1):
		weights[lvl] = GameData.level_data(lvl)[weight_key]
	return GameData.pick_weighted(weights, rng)


## Доля «заполненности» места: обычно пыль лежит ровно с лёгкими колебаниями,
## а плотные нити со сгустками и пустотами попадаются редко, примерно на 2% пространства.
## Порог 0.77–0.80 подобран по распределению шума _rare (97–98-й перцентиль).
func clump_density(pos: Vector2) -> float:
	var n := (_clumps.get_noise_2dv(pos) + 1.0) * 0.5
	var calm := 0.3 + 0.3 * smoothstep(0.35, 0.8, n)
	var rare := smoothstep(0.77, 0.80, (_rare.get_noise_2dv(pos) + 1.0) * 0.5)
	if rare <= 0.0:
		return calm
	var filament := 0.15 + 0.85 * smoothstep(0.35, 0.8, n)
	return lerpf(calm, filament * 1.6, rare)


## Видимая часть мира: экран вокруг центра камеры.
func _screen_rect_world() -> Rect2:
	var half := get_viewport_rect().size * 0.5 / camera.zoom.x
	return Rect2(camera.get_screen_center_position() - half, half * 2.0)


func _spawn_single(pos: Vector2, off_screen := false) -> bool:
	# Отбор: в пустотах точка чаще отбрасывается и ищется заново рядом.
	var accepted := false
	var player_density := maxf(GameData.radial_density(player.position.length()), 0.01)
	for attempt in SPAWN_ATTEMPTS:
		var falloff := GameData.radial_density(pos.length()) / player_density
		if rng.randf() < clump_density(pos) * clampf(falloff, 0.2, 2.0) * 0.6:
			accepted = true
			break
		pos = _random_point(pos.distance_to(player.position) * 0.95, pos.distance_to(player.position) * 1.05)
	if not accepted or pos.length() < GameData.STAR_RADIUS * 1.35:
		return false
	if off_screen and _hidden_rect.has_point(pos):
		return false
	var material: String = GameData.pick_weighted(GameData.material_weights(pos.length()), rng)
	return _add_dust(pos, _pick_level("spawn_weight"), material)


func _spawn_cluster(center: Vector2, view_r: float) -> void:
	if center.length() < GameData.STAR_RADIUS * 1.4:
		return
	var level := _pick_level("cluster_weight")
	var material: String = GameData.pick_weighted(GameData.material_weights(center.length()), rng)
	var spread := view_r * 0.1
	var size_k := clampf(Skills.stat("spawn"), 0.3, 1.0)
	for n in roundi(rng.randi_range(CLUSTER_SIZE.x, CLUSTER_SIZE.y) * size_k):
		var pos := center + Vector2(rng.randfn(0.0, spread), rng.randfn(0.0, spread))
		# Части скопления, попавшие на экран, не появляются из воздуха.
		if not _screen_rect_world().has_point(pos):
			_add_dust(pos, level, material)


## pos в мировых координатах.
func _add_dust(pos: Vector2, level: int, material: String) -> bool:
	if dust.size() >= MAX_DUST:
		return false
	var d := Dust.new()
	d.pos = pos - frame_offset
	d.vel = Vector2.ZERO
	d.level = level
	d.material = material
	var data := GameData.level_data(level)
	d.r = data.radius * rng.randf_range(0.85, 1.15)
	d.cell = GameData.MATERIAL_ORDER.find(material) * ATLAS_VARIANTS + rng.randi() % ATLAS_VARIANTS
	d.phase = rng.randf() * TAU
	d.idx = dust.size()
	dust.append(d)
	_write(d)
	return true
