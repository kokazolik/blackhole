class_name DustField
extends Node2D
## Вся пыль вокруг игрока: появление, притяжение, поглощение и отрисовка одним проходом.
##
## Пыль хранится простыми объектами и рисуется в одном _draw, без отдельной ноды на
## каждую пылинку: так на телефоне держатся сотни частиц.
##
## Распределение неравномерное, как в настоящем диске: сгустки и нити пыли
## (шум) поверх средней плотности, которая зависит от расстояния до звезды.
## Вся пыль медленно сносится орбитальным сдвигом относительно игрока.

const BASE_TARGET_COUNT := 700
const MAX_DENSITY_SCALE := 1.8  # потолок числа пылинок у снеговой линии, бережём телефон
const SPAWN_ATTEMPTS := 4
const ATLAS := preload("res://assets/dust/dust_atlas.png")
const ATLAS_CELL := 64
const ATLAS_VARIANTS := 4
const SPRITE_SCALE := 3.4  # видимое зерно занимает ~80% клетки атласа
const MAX_SPAWN_PER_FRAME := 24
const CLUSTER_INTERVAL := Vector2(7.0, 15.0)
const CLUSTER_SIZE := Vector2i(15, 30)
const DRAG := 0.55  # доля скорости, остающаяся через секунду
const POPUP_TIME := 0.9
const POPUP_LIMIT := 40

class Dust:
	var pos: Vector2
	var vel: Vector2
	var level: int
	var material: String
	var r: float
	var color: Color
	var variant: int
	var rot: float
	var spin: float

var player: Player
var camera: Camera2D
var dust: Array[Dust] = []
var rng := RandomNumberGenerator.new()
var _cluster_timer := 0.0
var _filled := false
var _popups: Array = []  # всплывающие «+N» цвета материала
var _clumps := FastNoiseLite.new()


func _ready() -> void:
	rng.randomize()
	_cluster_timer = rng.randf_range(2.0, 5.0)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# Гребневый шум даёт вытянутые нити и сгустки с пустотами между ними.
	_clumps.seed = 1337
	_clumps.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_clumps.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_clumps.fractal_octaves = 3
	_clumps.frequency = 0.0022
	GameState.absorbed.connect(_on_absorbed)


func _on_absorbed(at: Vector2, material: String, gained: float) -> void:
	if _popups.size() >= POPUP_LIMIT:
		_popups.pop_front()
	var text := "+%d" % roundi(gained) if is_equal_approx(gained, roundf(gained)) else "+%.1f" % gained
	_popups.append({"pos": at, "text": text, "color": GameData.MATERIALS[material].color, "t": 0.0})


func view_radius() -> float:
	var size := get_viewport_rect().size
	return size.length() * 0.5 / camera.zoom.x


func _physics_process(delta: float) -> void:
	var view_r := view_radius()
	var active_r := view_r * 1.35
	_maintain(view_r, active_r, delta)

	var pp := player.position
	var pr := player.radius
	var pull_r := player.pull_radius()
	var strength := player.pull_strength()
	var max_lvl := Skills.max_dust_level()
	var despawn_sq := pow(active_r * 1.3, 2)
	var drag := pow(DRAG, delta)
	var player_orbit := GameData.orbit_speed(pp.length())

	var i := dust.size() - 1
	while i >= 0:
		var d := dust[i]
		var to := pp - d.pos
		var dist_sq := to.length_squared()
		if dist_sq > despawn_sq:
			_remove_at(i)
			i -= 1
			continue
		var dist := sqrt(dist_sq)
		var edible := d.level <= max_lvl
		if dist < pull_r and dist > 0.001:
			var dir := to / dist
			if edible:
				var k := 0.35 + 0.65 * (1.0 - dist / pull_r)
				d.vel += dir * strength * k * delta
			elif dist < pr + d.r + 2.0:
				# Пыль выше открытого уровня отталкивается от поверхности.
				d.pos = pp - dir * (pr + d.r + 2.0)
				d.vel = -dir * maxf(player.velocity.length(), 20.0) * 0.8
		d.vel *= drag
		# Орбитальный сдвиг: ближе к звезде пыль обгоняет игрока, дальше — отстаёт.
		var rd := d.pos.length()
		var shear := GameData.orbit_speed(rd) - player_orbit
		d.pos += (d.vel + Vector2(-d.pos.y, d.pos.x) / maxf(rd, 1.0) * shear) * delta
		d.rot += d.spin * delta
		if edible and d.pos.distance_squared_to(pp) < pow(pr + d.r * 0.5, 2):
			GameState.absorb(d.level, d.material, d.pos)
			_remove_at(i)
		i -= 1
	for popup in _popups:
		popup.t += delta
	_popups = _popups.filter(func(pp_): return pp_.t < POPUP_TIME)
	queue_redraw()


func _remove_at(i: int) -> void:
	dust[i] = dust.back()
	dust.pop_back()


func _maintain(view_r: float, active_r: float, delta: float) -> void:
	var density_scale := clampf(GameData.radial_density(player.position.length()), 0.35, MAX_DENSITY_SCALE)
	var target := int(BASE_TARGET_COUNT * Skills.stat("spawn") * density_scale)
	var spawn_budget := MAX_SPAWN_PER_FRAME
	if not _filled:
		# Первое заполнение: пыль сразу по всему экрану, а не только за краем.
		for n in target:
			_spawn_single(_random_point(0.0, active_r))
		_filled = true
		return
	while dust.size() < target and spawn_budget > 0:
		_spawn_single(_random_point(view_r * 1.05, active_r))
		spawn_budget -= 1

	_cluster_timer -= delta * Skills.stat("cluster")
	if _cluster_timer <= 0.0:
		_cluster_timer = rng.randf_range(CLUSTER_INTERVAL.x, CLUSTER_INTERVAL.y)
		_spawn_cluster(_random_point(view_r * 1.1, active_r * 0.95), view_r)


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


## Доля «заполненности» места сгустками: 0.15 в пустотах, 1.0 в гуще нитей.
func clump_density(pos: Vector2) -> float:
	var n := (_clumps.get_noise_2dv(pos) + 1.0) * 0.5
	return 0.15 + 0.85 * smoothstep(0.35, 0.8, n)


func _spawn_single(pos: Vector2) -> void:
	# Отбор: в пустотах точка чаще отбрасывается и ищется заново рядом.
	var accepted := false
	for attempt in SPAWN_ATTEMPTS:
		var falloff := GameData.radial_density(pos.length()) / maxf(GameData.radial_density(player.position.length()), 0.01)
		if rng.randf() < clump_density(pos) * clampf(falloff, 0.2, 2.0) * 0.6:
			accepted = true
			break
		pos = _random_point(pos.distance_to(player.position) * 0.95, pos.distance_to(player.position) * 1.05)
	if not accepted:
		return
	if pos.length() < GameData.STAR_RADIUS * 1.5:
		return
	var material: String = GameData.pick_weighted(GameData.material_weights(pos.length()), rng)
	_add_dust(pos, _pick_level("spawn_weight"), material)


func _spawn_cluster(center: Vector2, view_r: float) -> void:
	if center.length() < GameData.STAR_RADIUS * 2.0:
		return
	var level := _pick_level("cluster_weight")
	var material: String = GameData.pick_weighted(GameData.material_weights(center.length()), rng)
	var spread := view_r * 0.1
	for n in rng.randi_range(CLUSTER_SIZE.x, CLUSTER_SIZE.y):
		var offset := Vector2(rng.randfn(0.0, spread), rng.randfn(0.0, spread))
		_add_dust(center + offset, level, material)


func _add_dust(pos: Vector2, level: int, material: String) -> void:
	var d := Dust.new()
	d.pos = pos
	d.vel = Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 4.0)
	d.level = level
	d.material = material
	var data := GameData.level_data(level)
	d.r = data.radius * rng.randf_range(0.85, 1.15)
	d.color = GameData.MATERIALS[material].color
	d.variant = rng.randi() % ATLAS_VARIANTS
	d.rot = rng.randf() * TAU
	d.spin = rng.randf_range(-0.6, 0.6)
	dust.append(d)


func _draw() -> void:
	var max_lvl := Skills.max_dust_level()
	var view_sq := pow(view_radius() * 1.1, 2)
	var pp := player.position
	var line_w := 1.2 / camera.zoom.x
	for d in dust:
		if d.pos.distance_squared_to(pp) > view_sq:
			continue
		var edible := d.level <= max_lvl
		draw_set_transform(d.pos, d.rot)
		# Слабое свечение цвета материала, чтобы мелкие пылинки читались на тёмном фоне.
		draw_circle(Vector2.ZERO, d.r * 1.9, Color(d.color, 0.09 if edible else 0.04))
		var s := d.r * SPRITE_SCALE
		var row := GameData.MATERIAL_ORDER.find(d.material)
		var region := Rect2(d.variant * ATLAS_CELL, row * ATLAS_CELL, ATLAS_CELL, ATLAS_CELL)
		draw_texture_rect_region(ATLAS, Rect2(-s * 0.5, -s * 0.5, s, s), region, Color(1, 1, 1, 1.0 if edible else 0.4))
		if not edible:
			# Недоступная пыль: тусклая, с обводкой цвета своего уровня.
			draw_arc(Vector2.ZERO, d.r * 1.7 + line_w, 0.0, TAU, 16, Color(GameData.level_data(d.level).color, 0.5), line_w)
		elif d.level > 1:
			draw_arc(Vector2.ZERO, d.r * 1.7 + line_w, 0.0, TAU, 12, Color(GameData.level_data(d.level).color, 0.6), line_w)
	draw_set_transform(Vector2.ZERO)

	# Всплывающие цифры поверх пыли. Размер шрифта переводим в мировые единицы.
	var font := ThemeDB.fallback_font
	var font_size := maxi(4, roundi(22.0 / camera.zoom.x))
	for popup in _popups:
		var k: float = popup.t / POPUP_TIME
		var pos: Vector2 = popup.pos + Vector2(0, -30.0 * k / camera.zoom.x * 2.0)
		var w := font.get_string_size(popup.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string_outline(font, pos - Vector2(w * 0.5, 0), popup.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, maxi(1, font_size / 6), Color(0, 0, 0, 0.7 * (1.0 - k)))
		draw_string(font, pos - Vector2(w * 0.5, 0), popup.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(popup.color, 1.0 - k))
