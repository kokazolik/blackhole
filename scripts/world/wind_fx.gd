class_name WindFx
extends Node2D
## Струи встречного газа вокруг гальки: тонкие светлые штрихи вдоль сноса.
## Чем сильнее дрейф к звезде, тем они ярче и длиннее; в кольце-ловушке почти
## пропадают. Штрихи живут в системе отсчёта пыли и текут мимо гальки.

const COUNT := 34

var player: Player
var dust_field: DustField
var pebble_field: PebbleField
var camera: Camera2D
var _streaks: Array = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat


func _process(delta: float) -> void:
	if player.pebble_k <= 0.0 or player.dead:
		visible = false
		return
	visible = true
	var view_r := dust_field.view_radius()
	var flow := -player.drift_velocity  # газ относительно гальки
	while _streaks.size() < COUNT:
		_streaks.append(_new_streak(view_r))
	for s in _streaks:
		s.t += delta
		# Газ течёт мимо: штрих смещается против сноса быстрее, чем пыль.
		s.pos += flow * 1.5 * delta
		var rel: Vector2 = s.pos + dust_field.frame_offset - player.position
		if s.t > s.life or rel.length() > view_r * 1.1:
			s.merge(_new_streak(view_r), true)
	queue_redraw()


func _new_streak(view_r: float) -> Dictionary:
	var at := player.position + Vector2.from_angle(_rng.randf() * TAU) * sqrt(_rng.randf()) * view_r
	return {"pos": at - dust_field.frame_offset, "t": 0.0, "life": _rng.randf_range(1.2, 2.6), "len": _rng.randf_range(0.6, 1.4)}


func _draw() -> void:
	var drift := player.drift_velocity
	var speed := drift.length()
	if speed < 0.5:
		return
	var dir := -drift / speed
	var strength := clampf(speed / (GameData.DRIFT_SPEED * GameData.speed_k()), 0.0, 2.0) * player.pebble_k
	var px := 1.0 / camera.zoom.x
	for s in _streaks:
		var k: float = s.t / s.life
		var a := sin(k * PI) * 0.16 * strength
		var p: Vector2 = s.pos + dust_field.frame_offset
		# В ветровой тени крупного тела струй нет: видна спокойная полоса.
		if pebble_field:
			a *= 1.0 - pebble_field.shadow_at(p)
		var l: float = speed * 2.2 * s.len
		var tail := p - dir * l
		draw_line(tail, p, Color(0.85, 0.9, 1.0, a * 0.4), 1.2 * px, true)
		draw_line(tail.lerp(p, 0.5), p, Color(0.9, 0.95, 1.0, a), 1.4 * px, true)
