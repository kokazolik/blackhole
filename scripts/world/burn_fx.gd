class_name BurnFx
extends Node2D
## Испарение пылинки у звезды. Пламени нет: в вакууме гореть нечему.
## С раскалённой стороны, обращённой к звезде, вещество уходит в пар. Давление
## света и звёздный ветер сдувают пар от звезды, поэтому за пылинкой тянется
## хвост, как у кометы. Пар остывает и гаснет. При гибели остатки разлетаются
## раскалёнными осколками и тоже испаряются.

signal finished  # анимация гибели закончилась

const LIMIT := 320
const DEATH_TIME := 2.6

var player: Player
var _vapor: Array = []
var _shards: Array = []
var _spawn_acc := 0.0
var _ice_acc := 0.0
var _death_t := -1.0
var _death_pos := Vector2.ZERO
var _death_r := 1.0
var _glow := _make_glow()


static func _make_glow() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.3, Color(1, 1, 1, 0.4))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	return tex


func _ready() -> void:
	# Светящийся газ складывается со светом фона, а не перекрывает его.
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	player.burned_up.connect(_on_burned_up)


## Пылинка из поля испарилась у звезды: маленькое облачко пара.
func puff(at: Vector2, r: float) -> void:
	for i in 5:
		if _vapor.size() < LIMIT:
			_emit_vapor(at, r, GameData.SUBLIMATION_TEMP + 300.0, 0.8)


func _process(delta: float) -> void:
	if not player.dead and player.ice_vapor > 0.0:
		# Лёд внутри снеговой линии сублимирует: голубоватые струйки пара.
		_ice_acc += delta * (3.0 + 400.0 * player.ice_vapor / maxf(GameState.mass, 1.0))
		while _ice_acc >= 1.0 and _vapor.size() < LIMIT:
			_ice_acc -= 1.0
			_emit_vapor(player.position, player.radius, 0.0, 0.7)
			_vapor[-1]["ice"] = true
		_ice_acc = fmod(_ice_acc, 1.0)
	if not player.dead and player.burn > 0.0:
		_spawn_acc += delta * (6.0 + 90.0 * player.burn)
		while _spawn_acc >= 1.0 and _vapor.size() < LIMIT:
			_spawn_acc -= 1.0
			_emit_vapor(player.position, player.radius, player.temperature, 1.0)
		_spawn_acc = fmod(_spawn_acc, 1.0)

	if _death_t >= 0.0:
		_death_t += delta
		_death_pos += GameData.orbit_velocity(_death_pos) * delta
		if _death_t >= DEATH_TIME:
			_death_t = -1.0
			finished.emit()

	if _vapor.is_empty() and _shards.is_empty() and _death_t < 0.0:
		return
	for v in _vapor:
		var away: Vector2 = (v.pos as Vector2).normalized()
		v.vel += away * v.push * delta  # давление излучения от звезды
		v.pos += (v.vel + GameData.orbit_velocity(v.pos)) * delta
		v.t += delta
	_vapor = _vapor.filter(func(v): return v.t < v.life)
	for s in _shards:
		var away: Vector2 = (s.pos as Vector2).normalized()
		s.vel += away * s.r * 3.0 * delta
		s.pos += (s.vel + GameData.orbit_velocity(s.pos)) * delta
		s.t += delta
		s.r = maxf(s.r - s.r0 * delta / s.life, 0.0)  # осколок тает
		if randf() < delta * 30.0 and _vapor.size() < LIMIT:
			_emit_vapor(s.pos, s.r, GameData.SURFACE_TEMP * (1.0 - s.t / s.life * 0.5), 0.6)
	_shards = _shards.filter(func(s): return s.t < s.life and s.r > 0.0)
	queue_redraw()


## Частица пара: вылетает с горячей стороны (к звезде), потом её сдувает назад.
func _emit_vapor(at: Vector2, r: float, temp: float, scale_k: float) -> void:
	var to_star := -at.normalized()
	var dir := to_star.rotated(randf_range(-1.6, 1.6))
	_vapor.append({
		"pos": at + dir * r * randf_range(0.7, 1.0),
		"vel": dir * r * randf_range(1.0, 3.0),
		"push": r * randf_range(6.0, 12.0),
		"size": r * randf_range(0.35, 0.7) * scale_k,
		"temp": temp,
		"t": 0.0,
		"life": randf_range(1.2, 2.4),
	})


func _on_burned_up() -> void:
	_death_t = 0.0
	_death_pos = player.position
	_death_r = player.radius
	var away := player.position.normalized()
	for i in 9:
		var dir := Vector2.from_angle(randf() * TAU)
		var r0 := _death_r * randf_range(0.2, 0.45)
		_shards.append({
			"pos": _death_pos + dir * _death_r * 0.4,
			"vel": (dir * randf_range(2.0, 5.0) + away * 2.0) * _death_r,
			"r": r0, "r0": r0, "t": 0.0, "life": randf_range(1.0, 1.9),
		})
	for i in 70:
		_emit_vapor(_death_pos, _death_r, GameData.SURFACE_TEMP, 1.6)


func _draw() -> void:
	for v in _vapor:
		var k: float = v.t / v.life
		# Пар остывает: от цвета раскалённой поверхности к тусклому голубоватому
		# свечению ионизированного газа, и гаснет.
		var hot := GameData.thermal_color(v.temp)
		var col := Color(hot.r, hot.g, hot.b).lerp(Color(0.45, 0.55, 0.9), clampf(k * 1.6, 0.0, 1.0))
		var a := (1.0 - k) * (0.35 + 0.5 * hot.a)
		if v.get("ice", false):
			# Пар льда разреженный: тонкая голубоватая дымка, а не белый шлейф.
			col = Color(0.55, 0.75, 1.0)
			a = (1.0 - k) * k * 4.0 * 0.06
		var s: float = v.size * (1.0 + 2.5 * k)  # газ расширяется
		draw_texture_rect(_glow, Rect2(v.pos - Vector2(s, s), Vector2(s, s) * 2.0), false, Color(col, a))
	for sh in _shards:
		var k: float = sh.t / sh.life
		var col := GameData.thermal_color(GameData.SURFACE_TEMP * (1.0 - 0.6 * k))
		var r: float = sh.r
		draw_texture_rect(_glow, Rect2(sh.pos - Vector2(r, r) * 3.0, Vector2(r, r) * 6.0), false, Color(col, 0.7))
		draw_circle(sh.pos, r, Color(col.lightened(0.3), 1.0))
	if _death_t >= 0.0 and _death_t < 0.8:
		# Последняя вспышка: тело целиком переходит в раскалённый газ.
		var k := _death_t / 0.8
		var r := _death_r * (1.5 + 5.0 * k)
		draw_texture_rect(_glow, Rect2(_death_pos - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(1.0, 0.9, 0.7, 0.9 * (1.0 - k)))
