class_name DustDrifters
extends Node2D
## Пролетающие мимо на этапе пылинки.
##
## Пушистый великан — рыхлый фрактальный комок из сотен пылинок, в десятки раз
## крупнее тебя. Так в диске и растут первые тела: пылинки слипаются цепочками,
## и выходит ажурное облако (фрактальная размерность ~1.9). Зёрна на краях держатся
## на одном-двух контактах: подлети — и они оторвутся к тебе. Внутри паутина из
## пыли тормозит.
##
## Галька-предвестник — камешек, которым ты скоро станешь. Газ её почти не держит,
## и она проносится сквозь пыль за пару секунд, а за ней закручивается вихревой
## след: пыль и тебя самого тащит следом.

signal appeared(kind: String, world_position: Vector2)

const FLUFF_FIRST := 100.0
const FLUFF_INTERVAL := Vector2(150.0, 210.0)
const FLUFF_GRAINS := 384
const FLUFF_GRAIN_R := 1.9          # как пылинка первого уровня
const FLUFF_CROSS := 45.0           # за сколько проплывает экран, с
const FLUFF_MASS_K := 0.35          # зёрна комка — мельчайшие мономеры: легче свободной пыли
const FLUFF_VALUE_K := 0.5
const FLUFF_FRAY_DEG := 2           # столько контактов или меньше — зерно сорвёт притяжением
const FLUFF_STICKY := 0.22          # торможение внутри: доля на каждое зерно рядом, 1/с
const FLUFF_STICKY_MAX := 2.5

const HERALD_FIRST := 55.0
const HERALD_INTERVAL := Vector2(100.0, 150.0)
const HERALD_SIZE := 5.5            # радиус гальки в твоих радиусах
const HERALD_CROSS := 3.2           # за сколько пролетает экран, с
const HERALD_WARN := 1.2            # столько секунд у края мерцает отблеск перед появлением
const WAKE_LEN := 14.0              # длина следа в радиусах гальки
const WAKE_WIDTH := 2.6             # полуширина следа в радиусах гальки
const TRAIL_POINTS := 26

var player: Player
var dust_field: DustField
var _rng := RandomNumberGenerator.new()

# Пушистый великан
var fluff_active := false
var fluff_radius := 0.0
var _fl_timer := FLUFF_FIRST
var _fl_pos := Vector2.ZERO   # центр в системе отсчёта пыли
var _fl_vel := Vector2.ZERO
var _fl_travel := 0.0
var _fl_length := 0.0
var _fl_spin := 0.0
var _fl_spin_rate := 0.0
var _fl_pts := PackedVector2Array()  # зёрна в координатах комка
var _fl_deg := PackedInt32Array()    # сколько у зерна соседей
var _fl_mat: Array[String] = []
var _fl_level := PackedInt32Array()
var _fl_ready := false   # комок построен заранее, ждёт появления
var _fl_building := false
var _fl_mm := MultiMesh.new()
var _fl_node := MultiMeshInstance2D.new()
var _fl_buf := PackedFloat32Array()
var _fl_dirty := false

# Галька-предвестник
var herald_active := false
var herald_radius := 0.0
var _h_timer := HERALD_FIRST
var _h_warn := -1.0
var _h_pos := Vector2.ZERO   # в системе отсчёта пыли
var _h_vel := Vector2.ZERO
var _h_travel := 0.0
var _h_length := 0.0
var _h_spin := 0.0
var _h_trail: Array[Vector2] = []  # прошлые положения, в системе отсчёта пыли
var _h_trail_t := 0.0
var _h_sprite := Sprite2D.new()
var _glow := Player._make_glow()
var _h_entry := Vector2.ZERO
var _h_dir := Vector2.ZERO


func _ready() -> void:
	_rng.randomize()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_fl_mm.transform_format = MultiMesh.TRANSFORM_2D
	_fl_mm.use_colors = true
	_fl_mm.use_custom_data = true
	_fl_mm.mesh = quad
	_fl_mm.instance_count = FLUFF_GRAINS
	_fl_mm.visible_instance_count = 0
	_fl_buf.resize(FLUFF_GRAINS * 16)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/fluff_grain.gdshader")
	mat.set_shader_parameter("atlas", DustField.ATLAS)
	_fl_node.multimesh = _fl_mm
	_fl_node.material = mat
	_fl_node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_fl_node.visible = false
	add_child(_fl_node)

	var hm := ShaderMaterial.new()
	hm.shader = preload("res://shaders/pebble_body.gdshader")
	_h_sprite.material = hm
	var blank := Image.create(256, 256, false, Image.FORMAT_L8)
	blank.fill(Color.WHITE)
	_h_sprite.texture = ImageTexture.create_from_image(blank)
	_h_sprite.visible = false
	add_child(_h_sprite)


## Идут ли события: только пылинка, после обучения и пока жив.
func _allowed() -> bool:
	return GameState.stage == 0 and GameState.tutorial_done and player.pebble_k <= 0.0 and not player.dead


func _process(delta: float) -> void:
	if not _allowed():
		if fluff_active:
			_fluff_end()
		if herald_active or _h_warn >= 0.0:
			_herald_end()
		return
	_update_fluff(delta)
	_update_herald(delta)
	queue_redraw()


func fluff_center() -> Vector2:
	return _fl_pos + dust_field.frame_offset


func herald_center() -> Vector2:
	return _h_pos + dust_field.frame_offset


# ---------------------------------------------------------------- великан

func _update_fluff(delta: float) -> void:
	if not fluff_active:
		_fl_timer -= delta
		# Комок строится заранее, за несколько кадров, чтобы появление не дёрнуло игру.
		if _fl_timer < 8.0 and not _fl_ready and not _fl_building:
			_build_fluff()
		if _fl_timer <= 0.0 and _fl_ready:
			_fl_timer = _rng.randf_range(FLUFF_INTERVAL.x, FLUFF_INTERVAL.y)
			_fluff_start()
		return
	_fl_pos += _fl_vel * delta
	_fl_travel += _fl_vel.length() * delta
	_fl_spin += _fl_spin_rate * delta
	if _fl_travel > _fl_length or _fl_pts.is_empty():
		_fluff_end()
		return
	var c := fluff_center()
	_fl_node.position = c
	_fl_node.rotation = _fl_spin
	var to_star := (-c).normalized().rotated(-_fl_spin)
	var mat := _fl_node.material as ShaderMaterial
	mat.set_shader_parameter("light_dir", Vector2(to_star.x, -to_star.y))
	mat.set_shader_parameter("star_light", DustField.STAR_LIGHT * (1.0 + 0.9 * Star.flare))
	_fluff_interact(c, delta)


func _fluff_interact(c: Vector2, delta: float) -> void:
	var pp := player.position
	var pull_r := player.pull_radius()
	var reach := fluff_radius + pull_r
	if pp.distance_squared_to(c) > reach * reach:
		return
	var pr := player.radius
	var max_lvl := Skills.max_dust_level()
	var local := (pp - c).rotated(-_fl_spin)
	var fray_r := pull_r * 0.55
	var near_sq := pow(pr * 3.0, 2)
	var eat_sq := pow(pr + FLUFF_GRAIN_R * 0.6, 2)
	var near := 0
	var i := _fl_pts.size() - 1
	while i >= 0:
		var g := _fl_pts[i]
		var d2 := g.distance_squared_to(local)
		if d2 < near_sq:
			near += 1
		var edible := _fl_level[i] <= max_lvl
		if edible and d2 < eat_sq:
			# Коснулся — зерно прилипло к тебе.
			var at := c + g.rotated(_fl_spin)
			var data := GameData.level_data(_fl_level[i])
			GameState.absorb_mass(data.mass * GameData.DUST_STAGE_MASS * FLUFF_MASS_K,
					data.value * GameData.DUST_STAGE_VALUE * FLUFF_VALUE_K, _fl_mat[i], at)
			_fl_remove(i)
		elif edible and _fl_deg[i] <= FLUFF_FRAY_DEG and d2 < fray_r * fray_r:
			# Слабо держащееся зерно на краю срывает притяжением: летит к тебе.
			var at := c + g.rotated(_fl_spin)
			dust_field.add_debris(at, (pp - at).normalized() * 12.0 + _fl_vel, _fl_level[i], _fl_mat[i])
			_fl_remove(i)
		i -= 1
	if _fl_dirty:
		_fl_dirty = false
		_fl_mm.buffer = _fl_buf
		_fl_mm.visible_instance_count = _fl_pts.size()
	if near > 0:
		# Паутина из пыли: чем гуще вокруг, тем сильнее вязнешь.
		var k := minf(near * FLUFF_STICKY, FLUFF_STICKY_MAX)
		player.velocity = player.velocity.lerp(_fl_vel, 1.0 - exp(-k * delta))


func _fluff_start() -> void:
	var view_r := dust_field.view_radius()
	var dir := Vector2.from_angle(_rng.randf() * TAU)
	var side := dir.orthogonal() * (1.0 if _rng.randf() < 0.5 else -1.0)
	var miss := fluff_radius * _rng.randf_range(0.2, 0.9)
	# Появляется сразу у края: ждать полминуты, пока он вплывёт, скучно.
	var start := player.position + side * miss - dir * (view_r * 0.8 + fluff_radius)
	var far := start + dir * 2.0 * (view_r * 0.8 + fluff_radius)
	if start.length() < GameData.sublimation_distance() * 1.2 or far.length() < GameData.sublimation_distance() * 1.2:
		_fl_timer = 15.0
		return
	_fl_length = 2.0 * (view_r * 0.8 + fluff_radius) + view_r * 0.4
	_fl_vel = dir * _fl_length / FLUFF_CROSS
	_fl_pos = start - dust_field.frame_offset
	_fl_travel = 0.0
	_fl_spin = _rng.randf() * TAU
	_fl_spin_rate = _rng.randf_range(-0.05, 0.05)
	_fl_ready = false
	fluff_active = true
	_fl_node.visible = true
	_fl_write_all()
	appeared.emit("fluff", start)


func _fluff_end() -> void:
	fluff_active = false
	_fl_node.visible = false
	_fl_pts.clear()


## Комок по модели слипания кластеров (BCCA): сначала пары зёрен, потом пары пар
## и так далее. Каждая пара сближается по случайной прямой до первого касания —
## так и выходят ажурные ветвистые агрегаты, как в опытах и моделях диска.
func _build_fluff() -> void:
	_fl_building = true
	var r := FLUFF_GRAIN_R
	var clusters: Array = []
	for k in FLUFF_GRAINS:
		clusters.append(PackedVector2Array([Vector2.ZERO]))
	while clusters.size() > 1:
		var next: Array = []
		var k := 0
		while k + 1 < clusters.size():
			next.append(_stick(clusters[k], clusters[k + 1], r))
			k += 2
			if clusters[0].size() >= 32:
				await get_tree().process_frame  # крупные слияния — по одному за кадр
		if k < clusters.size():
			next.append(clusters[k])
		clusters = next
		await get_tree().process_frame
	var pts: PackedVector2Array = clusters[0]
	var centre := Vector2.ZERO
	for p in pts:
		centre += p
	centre /= pts.size()
	var rad := 0.0
	for k in pts.size():
		pts[k] -= centre
		rad = maxf(rad, pts[k].length())
	_fl_pts = pts
	fluff_radius = rad + r
	# Соседи: по ним видно, какие зёрна держатся слабо (на краях ветвей).
	var grid := _grid(pts, r * 2.0)
	_fl_deg.resize(pts.size())
	for k in pts.size():
		_fl_deg[k] = _touching(grid, pts[k], r * 2.0, r * 2.3) - 1
	var weights := GameData.material_weights(player.position.length())
	_fl_mat.clear()
	_fl_level.resize(pts.size())
	for k in pts.size():
		_fl_mat.append(GameData.pick_weighted(weights, _rng))
		_fl_level[k] = 2 if _rng.randf() < 0.12 else 1
	_fl_building = false
	_fl_ready = true


func _stick(a: PackedVector2Array, b: PackedVector2Array, r: float) -> PackedVector2Array:
	var ca := _centroid(a)
	var cb := _centroid(b)
	var ra := 0.0
	for p in a:
		ra = maxf(ra, p.distance_to(ca))
	var rb := 0.0
	for p in b:
		rb = maxf(rb, p.distance_to(cb))
	var u := Vector2.from_angle(_rng.randf() * TAU)
	var lateral := u.orthogonal() * _rng.randf_range(-0.6, 0.6) * minf(ra, rb)
	var grid := _grid(a, r * 2.0)
	var offset := ca + u * (ra + rb + r * 2.0) + lateral - cb
	var step := r * 0.8
	var steps := int((ra + rb) * 2.0 / step) + 4
	var hit := false
	for s in steps:
		for p in b:
			var q := p + offset
			# Только зёрна, что уже вошли в круг кластера A, могут его коснуться.
			if q.distance_squared_to(ca) > pow(ra + r * 2.0, 2):
				continue
			if _touching(grid, q, r * 2.0, r * 2.0) > 0:
				hit = true
				break
		if hit:
			break
		offset -= u * step
	if not hit:
		offset = ca + u * (ra * 0.6 + rb * 0.6) - cb
	var out := a.duplicate()
	for p in b:
		out.append(p + offset)
	return out


func _centroid(pts: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in pts:
		c += p
	return c / pts.size()


func _grid(pts: PackedVector2Array, cell: float) -> Dictionary:
	var g := {}
	for p in pts:
		var key := Vector2i(floori(p.x / cell), floori(p.y / cell))
		if g.has(key):
			g[key].append(p)
		else:
			g[key] = [p]
	return g


func _touching(grid: Dictionary, q: Vector2, cell: float, dist: float) -> int:
	var n := 0
	var kx := floori(q.x / cell)
	var ky := floori(q.y / cell)
	var d2 := dist * dist
	for y in range(ky - 1, ky + 2):
		for x in range(kx - 1, kx + 2):
			var key := Vector2i(x, y)
			if not grid.has(key):
				continue
			for p in grid[key]:
				if q.distance_squared_to(p) < d2:
					n += 1
	return n


func _fl_write_all() -> void:
	var max_lvl := Skills.max_dust_level()
	for k in _fl_pts.size():
		_fl_write(k, max_lvl)
	_fl_mm.buffer = _fl_buf
	_fl_mm.visible_instance_count = _fl_pts.size()
	(_fl_node.material as ShaderMaterial).set_shader_parameter("radius", fluff_radius)


func _fl_write(k: int, max_lvl: int) -> void:
	var b := k * 16
	var s := FLUFF_GRAIN_R * 3.8 * (1.25 if _fl_level[k] > 1 else 1.0)
	var col: Color = GameData.MATERIALS[_fl_mat[k]].color
	var p := _fl_pts[k]
	_fl_buf[b] = s
	_fl_buf[b + 1] = 0.0
	_fl_buf[b + 2] = 0.0
	_fl_buf[b + 3] = p.x
	_fl_buf[b + 4] = 0.0
	_fl_buf[b + 5] = s
	_fl_buf[b + 6] = 0.0
	_fl_buf[b + 7] = p.y
	_fl_buf[b + 8] = col.r
	_fl_buf[b + 9] = col.g
	_fl_buf[b + 10] = col.b
	_fl_buf[b + 11] = 1.0
	_fl_buf[b + 12] = GameData.MATERIAL_ORDER.find(_fl_mat[k]) * DustField.ATLAS_VARIANTS + (k * 7) % DustField.ATLAS_VARIANTS
	_fl_buf[b + 13] = 1.0 if _fl_level[k] <= max_lvl else 0.4
	_fl_buf[b + 14] = _fl_level[k]
	_fl_buf[b + 15] = float(k) * 2.399


## Убрать зерно: на его место встаёт последнее (порядок не важен).
func _fl_remove(i: int) -> void:
	var last := _fl_pts.size() - 1
	if i != last:
		_fl_pts[i] = _fl_pts[last]
		_fl_deg[i] = _fl_deg[last]
		_fl_mat[i] = _fl_mat[last]
		_fl_level[i] = _fl_level[last]
		_fl_write(i, Skills.max_dust_level())
	_fl_pts.remove_at(last)
	_fl_deg.remove_at(last)
	_fl_mat.remove_at(last)
	_fl_level.remove_at(last)
	_fl_dirty = true


# ---------------------------------------------------------------- предвестник

func _update_herald(delta: float) -> void:
	if not herald_active and _h_warn < 0.0:
		_h_timer -= delta
		if _h_timer <= 0.0:
			_h_timer = _rng.randf_range(HERALD_INTERVAL.x, HERALD_INTERVAL.y)
			_herald_prepare()
		return
	if _h_warn >= 0.0:
		# Отблеск у края экрана: оттуда сейчас вылетит.
		_h_warn -= delta
		if _h_warn < 0.0:
			herald_active = true
			_h_sprite.visible = true
			appeared.emit("herald", herald_center())
		return
	_h_pos += _h_vel * delta
	_h_travel += _h_vel.length() * delta
	_h_spin += delta * 2.5
	_h_trail_t -= delta
	if _h_trail_t <= 0.0:
		_h_trail_t = 0.03
		_h_trail.push_front(_h_pos)
		if _h_trail.size() > TRAIL_POINTS:
			_h_trail.pop_back()
	if _h_travel > _h_length:
		_herald_end()
		return
	var c := herald_center()
	_h_sprite.position = c
	_h_sprite.rotation = _h_spin
	_h_sprite.scale = Vector2.ONE * herald_radius * Player.PEBBLE_SCALE / 256.0
	var mat := _h_sprite.material as ShaderMaterial
	mat.set_shader_parameter("light_dir", (-c).normalized().rotated(-_h_spin))
	mat.set_shader_parameter("star_light", Color(1.0, 0.9, 0.75) * (1.0 + 0.9 * Star.flare))
	_herald_wake(delta)
	_herald_collide(c)


func _herald_prepare() -> void:
	var view_r := dust_field.view_radius()
	herald_radius = player.radius * HERALD_SIZE
	_h_dir = Vector2.from_angle(_rng.randf() * TAU)
	var side := _h_dir.orthogonal() * (1.0 if _rng.randf() < 0.5 else -1.0)
	var miss := herald_radius + player.radius * _rng.randf_range(4.0, 9.0)
	var start := player.position + side * miss - _h_dir * (view_r + herald_radius * 2.0)
	var far := start + _h_dir * 2.0 * (view_r + herald_radius * 2.0)
	if start.length() < GameData.sublimation_distance() * 1.2 or far.length() < GameData.sublimation_distance() * 1.2:
		_h_timer = 10.0
		return
	_h_length = 2.0 * (view_r + herald_radius * 2.0)
	_h_vel = _h_dir * _h_length / HERALD_CROSS
	_h_pos = start - dust_field.frame_offset
	_h_travel = 0.0
	_h_trail.clear()
	_h_entry = player.position + side * miss - _h_dir * view_r * 0.85
	_h_warn = HERALD_WARN
	var mat := _h_sprite.material as ShaderMaterial
	mat.set_shader_parameter("seed", _rng.randf())
	mat.set_shader_parameter("growth", 0.3)
	mat.set_shader_parameter("boulder", 0.0)
	mat.set_shader_parameter("detail", 1.0)
	var w := Vector4(_rng.randf_range(0.3, 0.6), _rng.randf_range(0.05, 0.2), _rng.randf_range(0.1, 0.35), _rng.randf_range(0.0, 0.25))
	mat.set_shader_parameter("mix_w", w / (w.x + w.y + w.z + w.w))


func _herald_end() -> void:
	herald_active = false
	_h_warn = -1.0
	_h_sprite.visible = false
	_h_trail.clear()


## Вихревой след: за галькой газ закручивается дорожкой вихрей. Пыль в следе
## тащит вперёд по ходу гальки и раскачивает поперёк — она расходится волнами.
func _wake_flow(rel: Vector2) -> Vector2:
	var behind := rel.dot(-_h_dir)
	if behind < -herald_radius * 1.5 or behind > herald_radius * WAKE_LEN:
		return Vector2.ZERO
	var across := rel.cross(_h_dir)
	var t := clampf(behind / (herald_radius * WAKE_LEN), 0.0, 1.0)
	var width := herald_radius * WAKE_WIDTH * (0.6 + 0.8 * t)
	if absf(across) > width:
		return Vector2.ZERO
	var k := (1.0 - absf(across) / width) * (1.0 - t)
	var speed := _h_vel.length()
	var swirl := sin(behind / herald_radius * 1.4) * signf(across)
	return (_h_dir * 0.45 + _h_dir.orthogonal() * swirl * 0.35) * speed * k


func _herald_wake(delta: float) -> void:
	var blend := 1.0 - exp(-5.0 * delta)
	for d in dust_field.dust:
		if d.idx < 0:
			continue
		var flow := _wake_flow(d.pos - _h_pos)
		if flow != Vector2.ZERO:
			dust_field.nudge(d, d.vel.lerp(flow, blend))
	var pf := _wake_flow(player.position - herald_center())
	if pf != Vector2.ZERO:
		player.velocity = player.velocity.lerp(pf, 1.0 - exp(-2.5 * delta))


## Галька в тысячи раз тяжелее: от неё отскакиваешь, её не сдвинуть.
func _herald_collide(c: Vector2) -> void:
	var to := player.position - c
	var d := to.length()
	var contact := herald_radius * 0.95 + player.radius
	if d >= contact or d < 0.001:
		return
	var n := to / d
	player.position = c + n * contact
	var into := (player.velocity - _h_vel).dot(n)
	if into < 0.0:
		player.velocity -= n * into * 1.4


# ---------------------------------------------------------------- рисунок

func _draw() -> void:
	if _h_warn >= 0.0:
		# Отблеск у края: мигающая искра и короткий штрих в сторону полёта.
		var k := 1.0 - _h_warn / HERALD_WARN
		var a := (0.35 + 0.65 * absf(sin(k * PI * 3.0))) * k
		var px := 1.0 / get_viewport().get_canvas_transform().get_scale().x
		draw_circle(_h_entry, 5.0 * px, Color(1.0, 0.9, 0.7, a))
		draw_circle(_h_entry, 14.0 * px, Color(1.0, 0.85, 0.6, a * 0.25))
		draw_line(_h_entry - _h_dir * 40.0 * px, _h_entry, Color(1.0, 0.9, 0.7, a * 0.6), 2.0 * px, true)
	if herald_active and _h_trail.size() > 1:
		# След: мягкие клубы закрученного газа с пылью, расходятся и гаснут к хвосту.
		var off := dust_field.frame_offset
		for i in range(_h_trail.size() - 1, 0, -1):
			var t := float(i) / TRAIL_POINTS
			var wob := _h_dir.orthogonal() * sin(i * 0.9 + _h_travel * 0.05) * herald_radius * 0.7 * t
			var p := _h_trail[i] + off + wob
			var r := herald_radius * (0.8 + 1.8 * t)
			draw_texture_rect(_glow, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(0.85, 0.9, 1.0, 0.16 * (1.0 - t)))
