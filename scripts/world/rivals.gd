class_name Rivals
extends Node2D
## Соседи-планетезимали и события этапа «Планетезималь».
##
## Рядом растут такие же тела, как ты: они едят тот же рой и растут по той же
## формуле, поэтому отставший отстаёт всё сильнее (убегающий рост). Столкновение
## решает энергия удара: медленнее второй космической — слияние, быстрее —
## скол и обломки, а удар с энергией выше прочности Q* раскалывает меньшее тело
## (Leinhardt & Stewart 2012). Тебя раскалывает не насмерть: ты остаёшься
## крупнейшим осколком, остальное летит рядом, и его можно доесть.
##
## События: раскрутка светом (YORP), контактная пара, пролёт олигарха с
## гравитационной пращой, гигантский удар, поток гальки из внешнего диска.

signal merged(world_position: Vector2, kind: String)
signal shattered(world_position: Vector2)     # ты расколол соседа
signal broken(world_position: Vector2)        # тебя раскололо
signal grazed(world_position: Vector2)        # удар быстрее убегания: скол
signal event_started(kind: String, world_position: Vector2)

const SHADER := preload("res://shaders/planetesimal.gdshader")
const PEBBLE_SCALE := 2.78   # как у тела игрока: видимый радиус — ровно r
const NAMES := ["Ида", "Матильда", "Гаспра", "Лютеция", "Эрос", "Паллада", "Юнона", "Гигия", "Психея", "Веста",
	"Аррокот", "Итокава", "Рюгу", "Бенну", "Церера", "Фебa", "Дактиль", "Клото", "Сильвия", "Европа"]
const SPAWN_MIN := 60.0       # пауза между новыми соседями, с
const SPAWN_MAX := 90.0
const REL_MIN := 0.3         # масса соседа в долях твоей
const REL_MAX := 0.7
const BIG_CHANCE := 0.15      # доля соседей крупнее тебя
const STIR := 0.03           # как сильно сосед твоей массы раскачивает рой вблизи
const SHEAR_AGE := 60.0      # через сколько секунд сосед уплывает по своей орбите
const GROWTH := 0.0015       # соседи растут сами (едят свой рой), доля массы в секунду
const WANDER := 0.25         # их собственная скорость, в твоих предельных скоростях
const SHEAR_SPAN := 0.4      # на какой разнице орбит (в радиусах экрана) сосед плывёт со скоростью WANDER
const PULL := 0.3            # притяжение к тебе, в долях WANDER
const FLOW_GRIP := 0.8       # как быстро гаснет толчок от удара
const MERGE_KEEP := 0.8      # доля массы соседа, что остаётся в тебе при слиянии
const MERGE_KEEP_BIG := 0.6  # если сосед крупнее: больше вещества разлетается
const CRATER_LOSS := 0.08    # скол при ударе на пороге раскола, в долях массы
const KICK := 0.55           # праща олигарха, в твоих предельных скоростях
const YORP_RAMP := 14.0

class Rival:
	var pos: Vector2   # в системе отсчёта пыли
	var vel: Vector2
	var mass: float
	var r := 1.0
	var kind := "rival"  # rival, twin, oligarch, impactor
	var name := ""
	var sprite: Sprite2D
	var spin := 0.0
	var spin_rate := 0.1
	var hit_cd := 0.0
	var kicked := false
	var age := 0.0

var player: Player
var pebble_field: PebbleField
var dust_field: DustField
var camera: Camera2D
var rivals: Array[Rival] = []
var yorp_t := -1.0  # идёт раскрутка светом: сколько секунд
var rng := RandomNumberGenerator.new()
var _blank: ImageTexture
var _spawn_t := 3.0
var _eat_t := 0.0
var _twin_t := 70.0
var _olig_t := 120.0
var _impact_t := 150.0
var _yorp_t := 90.0
var _flow_t := 60.0
var _name_i := 0


func _ready() -> void:
	rng.randomize()
	_name_i = rng.randi() % NAMES.size()
	var img := Image.create(256, 256, false, Image.FORMAT_L8)
	img.fill(Color.WHITE)
	_blank = ImageTexture.create_from_image(img)


func active() -> bool:
	return GameState.is_planet() and player.planet_k > 0.9 and not player.dead and not player.planet_surface().is_empty()


## Радиус соседа на экране: в той же пропорции к тебе, что и размеры в км над
## вами (GameData.planet_km), чтобы тело вдвое больше по подписи и выглядело вдвое крупнее.
func screen_r(mass: float) -> float:
	return player.radius * GameData.planet_km(mass) / GameData.planet_km(GameState.mass)


## Звездочёт хочет показать соседа, а рядом никого: подкладываем мелкого. INF — нельзя.
func spawn_for_guide() -> Vector2:
	if not active():
		return Vector2.INF
	var dir := Vector2.from_angle(rng.randf() * TAU)
	var at := player.position + dir * player.radius * 7.0
	var rv := _add("rival", at, GameState.mass * 0.5)
	rv.vel = Vector2.ZERO
	return at


func world_pos(rv: Rival) -> Vector2:
	return rv.pos + dust_field.frame_offset


## Ближайший сосед на экране (для подсказки Звездочёта), INF — нет.
func nearest_spot(kind := "") -> Vector2:
	var best := Vector2.INF
	var bd := dust_field.view_radius() * 0.8
	for rv in rivals:
		if kind != "" and rv.kind != kind:
			continue
		var d := world_pos(rv).distance_to(player.position)
		if d < bd:
			bd = d
			best = world_pos(rv)
	return best


func _process(delta: float) -> void:
	if not active():
		for rv in rivals:
			rv.sprite.visible = false
		queue_redraw()
		return
	_follow_world_scale()
	_stir(delta)
	_events(delta)
	_maintain(delta)
	_eat_t -= delta
	var eat_now := _eat_t <= 0.0
	if eat_now:
		_eat_t = 0.3
	var i := rivals.size() - 1
	while i >= 0:
		var rv := rivals[i]
		_move(rv, delta)
		if eat_now and rv.kind != "impactor":
			_rival_eat(rv)
		if rivals.has(rv):
			_check_player(rv)
		i -= 1
	_draw_sprites()
	queue_redraw()


## Соседи тоже раскачивают рой своей гравитацией: крупный рядом — сильно, мелкий
## вдалеке — едва. Поэтому рядом с большими телами расти труднее (так убегающий
## рост переходит в олигархический).
func _stir(delta: float) -> void:
	var view_r := dust_field.view_radius()
	for rv in rivals:
		var d := world_pos(rv).distance_to(player.position)
		if d < view_r:
			var near := 1.0 - d / view_r
			pebble_field.heat += STIR * clampf(rv.mass / GameState.mass, 0.0, 3.0) * near * near * delta
	pebble_field.heat = minf(pebble_field.heat, 1.0)


# --- Масштаб мира: на 10 и 100 км всё вокруг мельчает вдвое, вместе с соседями ---
var _world_k := -1.0


func _follow_world_scale() -> void:
	var k := GameData.world_k
	if _world_k < 0.0:
		_world_k = k
	if is_equal_approx(k, _world_k):
		return
	var ratio := k / _world_k
	_world_k = k
	var c := player.position - dust_field.frame_offset
	for rv in rivals:
		rv.pos = c + (rv.pos - c) * ratio
		rv.vel *= ratio


# --- Соседи ---

func _target_count() -> int:
	if Skills.stat("oligarch") > 0.0:
		return 1
	return 2 if GameData.planet_km(GameState.mass) < 10.0 else 3


func _maintain(delta: float) -> void:
	var view_r := dust_field.view_radius()
	var i := rivals.size() - 1
	while i >= 0:
		var rv := rivals[i]
		var far := world_pos(rv).distance_to(player.position)
		if far > view_r * (3.2 if rv.kind == "rival" else 2.4) or (rv.kind == "impactor" and rv.hit_cd < -12.0):
			_remove(rv)
		i -= 1
	var count := 0
	for rv in rivals:
		if rv.kind == "rival":
			count += 1
	_spawn_t -= delta
	if count < _target_count() and _spawn_t <= 0.0:
		_spawn_t = rng.randf_range(SPAWN_MIN, SPAWN_MAX)
		# Сосед на соседней орбите: кто ближе к звезде, догоняет тебя сзади,
		# кто дальше — ты сам нагоняешь его. Поэтому он выплывает из-за края
		# экрана вдоль орбиты, а не сбоку.
		var axes := _orbit_axes()
		var dr := rng.randf_range(0.15, 0.6) * (1.0 if rng.randf() < 0.5 else -1.0)
		var at: Vector2 = player.position + (axes[0] * dr + axes[1] * signf(dr) * 1.2) * view_r
		if at.length() > GameData.sublimation_distance() * 1.3:
			# Убегающий рост: почти все соседи заметно мельче тебя, изредка — крупнее.
			var rel := exp(rng.randf_range(log(REL_MIN), log(REL_MAX)))
			if rng.randf() < BIG_CHANCE:
				rel = rng.randf_range(1.1, 2.0)
			var rv := _add("rival", at, GameState.mass * rel)
			rv.vel = _orbit_flow(rv)


func _add(kind: String, at: Vector2, mass: float) -> Rival:
	var rv := Rival.new()
	rv.kind = kind
	rv.mass = mass
	rv.pos = at - dust_field.frame_offset
	rv.r = screen_r(mass)
	rv.name = NAMES[_name_i % NAMES.size()]
	_name_i += 1
	rv.spin = rng.randf() * TAU
	rv.spin_rate = rng.randf_range(0.05, 0.2)
	var sprite := Sprite2D.new()
	sprite.texture = _blank
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("seed", rng.randf())
	mat.set_shader_parameter("tilt", rng.randf_range(0.2, 0.8))
	var surf := player.planet_surface()
	mat.set_shader_parameter("surf", surf[0])
	mat.set_shader_parameter("normal_map", surf[1])
	# Состав соседа — что водится в его зоне диска.
	var w := GameData.material_weights(at.length())
	var mix := Vector4(w.get("silicate", 0.0), w.get("metal", 0.0), w.get("carbon", 0.0), w.get("ice", 0.0))
	mix += Vector4(rng.randf(), rng.randf(), rng.randf(), rng.randf()) * 0.15
	mat.set_shader_parameter("mix_w", mix / (mix.x + mix.y + mix.z + mix.w))
	sprite.material = mat
	add_child(sprite)
	rv.sprite = sprite
	rivals.append(rv)
	return rv


## Оси орбиты в точке игрока: [от звезды, вдоль орбиты].
func _orbit_axes() -> Array[Vector2]:
	var out := player.position.normalized()
	return [out, GameData.orbit_velocity(player.position).normalized()]


## Как сосед движется относительно тебя. Кеплеров сдвиг: тело ближе к звезде
## летит быстрее и обгоняет, дальше — отстаёт; чем больше разница орбит,
## тем быстрее. Пока сосед молод, твоё притяжение подтягивает его к тебе,
## потом сдвиг орбит уносит его прочь — и вместо него приходит новый.
func _orbit_flow(rv: Rival) -> Vector2:
	var axes := _orbit_axes()
	var d := world_pos(rv) - player.position
	var dr := d.dot(axes[0])
	var span := SHEAR_SPAN * dust_field.view_radius()
	var speed := player.max_speed() * WANDER
	var flow := axes[1] * -clampf(dr / span, -1.5, 1.5) * speed
	var dist := d.length()
	if dist < 0.001:
		return flow
	if Skills.stat("oligarch") > 0.0 or rv.age > SHEAR_AGE:
		# «Своя полоса» / сдвиг орбит: сосед расходится с тобой по радиусу.
		flow += axes[0] * signf(dr if absf(dr) > 0.001 else 1.0) * speed * PULL
	else:
		# Притяжение растёт вблизи: издали сосед плывёт вдоль орбиты, а у тебя
		# его траектория загибается к тебе.
		flow -= d / dist * speed * PULL * clampf(span / dist, 0.25, 2.0)
	return flow


func _remove(rv: Rival) -> void:
	rv.sprite.queue_free()
	rivals.erase(rv)


func _move(rv: Rival, delta: float) -> void:
	rv.hit_cd -= delta
	rv.spin += rv.spin_rate * delta
	rv.age += delta
	if rv.kind == "rival":
		# Соседи растут сами: едят свой рой. Крупный растёт быстрее.
		rv.mass *= exp(GROWTH * pow(rv.mass / GameState.mass, 0.33) * delta)
		# Скорость сходится к орбитальному течению; толчки от ударов гаснут.
		rv.vel = rv.vel.lerp(_orbit_flow(rv), 1.0 - exp(-FLOW_GRIP * delta))
	rv.r = screen_r(rv.mass)
	rv.pos += rv.vel * delta
	if rv.kind == "oligarch":
		_sling(rv, delta)


## Сосед ест мелочь своего роя: так он и растёт на глазах.
func _rival_eat(rv: Rival) -> void:
	var c := rv.pos
	var reach := rv.r * 2.2
	var list := pebble_field.pebbles
	var k := list.size() - 1
	while k >= 0:
		var p: PebbleField.Pebble = list[k]
		if not p.pulled and p.r < rv.r * 0.8 and p.pos.distance_squared_to(c) < reach * reach:
			rv.mass += GameState.mass * GameData.BITE_K * pow(p.r / player.radius, 2.0) * 0.5
			list.remove_at(k)
		k -= 1


# --- Столкновения с тобой ---

func _check_player(rv: Rival) -> void:
	var c := world_pos(rv)
	var to := c - player.position
	var d := to.length()
	# Приливный разрыв: мелкий сосед, прошедший совсем близко, рвётся на куски.
	if Skills.stat("tidal") > 0.0 and rv.kind != "oligarch" and rv.mass < GameState.mass * 0.8 \
			and d < (player.radius + rv.r) * 1.7 and d > (player.radius + rv.r):
		var mat := _rival_material(rv)
		pebble_field.spawn_fragments(c, -to.normalized(), 10, rv.mass * 0.5, mat, 0.3, true)
		shattered.emit(c)
		_remove(rv)
		return
	var contact := (player.radius + rv.r) * 0.95
	if d >= contact or d < 0.001:
		return
	var n := to / d
	# Тела не входят друг в друга: лёгкое сдвигается больше.
	var share := rv.mass / (GameState.mass + rv.mass)
	player.position -= n * (contact - d) * share
	rv.pos += n * (contact - d) * (1.0 - share)
	if rv.hit_cd > 0.0:
		return
	var impact := maxf((player.motion() + player.kick - rv.vel).dot(n), 0.0)
	var m1 := GameState.mass
	var m2 := rv.mass
	var esc := GameData.escape_game(maxf(m1, m2))
	var at := player.position + n * player.radius
	if rv.kind != "oligarch" and impact <= esc:
		_merge(rv, at)
		return
	# Удельная энергия удара против прочности меньшего тела: Q = ½·μ·v²/M.
	# На пороге (Q = Q*) равные тела разносит при скорости disrupt_ratio убеганий.
	var small := minf(m1, m2)
	var mu := m1 * m2 / pow(m1 + m2, 2.0)
	var q := mu / 0.25 * pow(impact / (GameData.disrupt_ratio(small) * esc), 2.0)
	var player_small := m1 <= m2 or rv.kind == "oligarch"
	if player_small:
		q /= Skills.stat("qstar")
	rv.hit_cd = 1.0
	pebble_field.impact_shake.emit(clampf(q, 0.3, 1.0))
	if q >= 1.0 and not player_small:
		_shatter(rv, at, n, impact)
	elif q >= 1.0:
		_break_player(rv, at, n, q)
	else:
		_crater(rv, at, n, q)
	# Отскок: вещество гасит удар, тела расходятся медленно.
	var j := impact * 1.3
	player.velocity -= n * j * share
	rv.vel += n * j * (1.0 - share)


func _rival_material(rv: Rival) -> String:
	var w := GameData.material_weights((rv.pos + dust_field.frame_offset).length())
	return GameData.pick_weighted(w, rng)


func _merge(rv: Rival, at: Vector2) -> void:
	var keep := MERGE_KEEP if rv.mass <= GameState.mass else MERGE_KEEP_BIG
	var rel := clampf(rv.r / player.radius, 0.2, 2.0)
	var value := PebbleField.VALUE_PER_PEBBLE * pow(GameState.mass / 30.0, PebbleField.VALUE_MASS_EXP) \
		* pow(rel / 0.2, 1.5) * GameData.boulder_value(GameState.mass) * GameData.PLANET_VALUE
	var mat := _rival_material(rv)
	GameState.absorb_mass(rv.mass * keep, value, mat, at)
	pebble_field.heat = minf(pebble_field.heat + 0.25, 1.0)
	if rv.kind == "twin":
		GameState.add_chondrules(3, at)
	merged.emit(at, rv.kind)
	_remove(rv)


## Ты сильнее: сосед раскалывается, обломки летят семейством вдоль орбиты.
func _shatter(rv: Rival, at: Vector2, n: Vector2, impact: float) -> void:
	var c := world_pos(rv)
	pebble_field.spawn_fragments(c, n, 14, rv.mass * 0.6, _rival_material(rv), 0.32)
	GameState.chip(GameState.mass * 0.02, at)
	shattered.emit(c)
	_remove(rv)


## Тебя раскололо: ты — крупнейший осколок, около половины массы. Остальное
## летит рядом твоими кусками, их можно собрать обратно.
func _break_player(rv: Rival, at: Vector2, n: Vector2, q: float) -> void:
	var keep := clampf(1.0 - 0.5 * q, 0.4, 0.6)
	var lost := GameState.mass * (1.0 - keep)
	GameState.chip(lost, at)
	pebble_field.spawn_fragments(player.position, -n, 12, lost * 0.5, pebble_field._main_material(), 0.3, true)
	if rv.kind != "oligarch":
		rv.mass += lost * 0.3
	broken.emit(at)


## Удар быстрее убегания, но слабее раскола: оба теряют кусок, обломки рядом.
func _crater(rv: Rival, at: Vector2, n: Vector2, q: float) -> void:
	var m1 := GameState.mass
	var m2 := rv.mass
	var mine := m1 * CRATER_LOSS * q * 2.0 * m2 / (m1 + m2) / Skills.stat("qstar")
	var theirs := m2 * CRATER_LOSS * q * 2.0 * m1 / (m1 + m2)
	if rv.kind == "oligarch":
		theirs = 0.0
	GameState.chip(mine, at)
	rv.mass -= theirs
	pebble_field.spawn_fragments(at, n.orthogonal() * (1.0 if rng.randf() < 0.5 else -1.0), 6, (mine + theirs) * 0.6, _rival_material(rv), 0.2)
	grazed.emit(at)


# --- События ---

func _events(delta: float) -> void:
	var km := GameData.planet_km(GameState.mass)
	var view_r := dust_field.view_radius()
	# Раскрутка светом: у тел меньше ~10 км свет звезды раскручивает их всё быстрее,
	# пока щебень не начнёт срываться с экватора (форма «волчка», как у Бенну и Рюгу).
	if yorp_t >= 0.0:
		yorp_t += delta
		player.yorp = clampf(yorp_t / YORP_RAMP, 0.0, 1.0)
		if yorp_t >= YORP_RAMP:
			yorp_t = -1.0
			pebble_field.shed_equator(0.03)
			event_started.emit("yorp_shed", player.position)
	else:
		player.yorp = maxf(player.yorp - delta / 3.0, 0.0)
	_yorp_t -= delta
	if km < 10.0 and _yorp_t <= 0.0 and yorp_t < 0.0:
		_yorp_t = rng.randf_range(100.0, 150.0)
		yorp_t = 0.0
		event_started.emit("yorp", player.position)
	# Контактная пара: почти на твоей орбите плывёт тело твоего размера.
	_twin_t -= delta
	if km < 100.0 and _twin_t <= 0.0:
		_twin_t = rng.randf_range(130.0, 180.0)
		# Почти на твоей орбите: подплывает спереди или сзади, чуть сбоку.
		var axes := _orbit_axes()
		var ahead := 1.0 if rng.randf() < 0.5 else -1.0
		var dir: Vector2 = (axes[1] * ahead + axes[0] * rng.randf_range(-0.15, 0.15)).normalized()
		var at := player.position + dir * view_r * 1.1
		var rv := _add("twin", at, GameState.mass * rng.randf_range(0.75, 0.9))
		rv.vel = -dir * player.escape_speed() * 0.5
		event_started.emit("twin", at)
	# Пролёт олигарха: тело в десять раз крупнее проходит мимо, его притяжение
	# сдвигает твою орбиту — к звезде или от неё, смотря с какой стороны пройдёт.
	_olig_t -= delta
	if km >= 10.0 and _olig_t <= 0.0:
		_olig_t = rng.randf_range(180.0, 240.0)
		# Он на соседней орбите: ближе к звезде — обгоняет, дальше — ты его нагоняешь.
		var axes := _orbit_axes()
		var side: Vector2 = axes[0] * (1.0 if rng.randf() < 0.5 else -1.0)
		var dir: Vector2 = axes[1] * -signf(side.dot(axes[0]))
		var mass := GameState.mass * 10.0
		var r := screen_r(mass)
		var at := player.position + side * (r + player.radius * rng.randf_range(3.0, 6.0)) - dir * (view_r + r * 1.2)
		var rv := _add("oligarch", at, mass)
		rv.vel = dir * (view_r + r) * 2.0 / 30.0
		event_started.emit("oligarch", at)
	# Гигантский удар: сосед почти твоего размера идёт прямо на тебя.
	_impact_t -= delta
	if km >= 100.0 and _impact_t <= 0.0:
		_impact_t = rng.randf_range(200.0, 260.0)
		var dir := Vector2.from_angle(rng.randf() * TAU)
		var at := player.position + dir * view_r * 1.15
		var rv := _add("impactor", at, GameState.mass * rng.randf_range(0.5, 1.1))
		rv.vel = -dir * player.escape_speed() * 2.6
		event_started.emit("impactor", at)
	# Поток гальки из внешнего диска: у тел в сотни км его ловит сфера Хилла.
	_flow_t -= delta
	if km >= 100.0 and _flow_t <= 0.0:
		_flow_t = rng.randf_range(100.0, 130.0)
		pebble_field.start_flow()
		event_started.emit("flow", player.position + player.position.normalized() * view_r)


## Праща: пока олигарх рядом, твоя орбита уходит в его сторону от звезды.
func _sling(rv: Rival, delta: float) -> void:
	var c := world_pos(rv)
	var d := c.distance_to(player.position)
	var near := rv.r * 6.0
	if d > near:
		return
	var out := player.position.normalized()
	var side := signf(player.position.length() - c.length())  # снаружи — выносит наружу
	if side == 0.0:
		side = 1.0
	player.kick += out * side * player.max_speed() * KICK * Skills.stat("sling") * (1.0 - d / near) * delta * 2.0
	if not rv.kicked:
		rv.kicked = true
		event_started.emit("sling_out" if side > 0.0 else "sling_in", player.position)


# --- Рисование ---

func _draw_sprites() -> void:
	var light := Color(1.0, 0.9, 0.75) * (1.0 + 0.9 * Star.flare)
	var view_r := dust_field.view_radius() * 1.3
	for rv in rivals:
		var c := world_pos(rv)
		var on := c.distance_to(player.position) < view_r + rv.r
		rv.sprite.visible = on
		if not on:
			continue
		rv.sprite.position = c
		rv.sprite.scale = Vector2.ONE * rv.r * PEBBLE_SCALE / _blank.get_width()
		var mat := rv.sprite.material as ShaderMaterial
		mat.set_shader_parameter("light_dir", (-c).normalized())
		mat.set_shader_parameter("spin", rv.spin)
		mat.set_shader_parameter("star_light", light)


## Чем кончится удар на текущей скорости — по тому же правилу, что и сам удар:
## зелёная дуга — слияние, жёлтая — скол, красная — раскол (твой или соседа).
func outcome(rv: Rival) -> String:
	var to := world_pos(rv) - player.position
	var n := to.normalized()
	var impact := maxf((player.motion() + player.kick - rv.vel).dot(n), 0.0)
	var esc := GameData.escape_game(maxf(GameState.mass, rv.mass))
	if rv.kind != "oligarch" and impact <= esc:
		return "merge"
	var small := minf(GameState.mass, rv.mass)
	var mu := GameState.mass * rv.mass / pow(GameState.mass + rv.mass, 2.0)
	var q := mu / 0.25 * pow(impact / (GameData.disrupt_ratio(small) * esc), 2.0)
	var player_small := GameState.mass <= rv.mass or rv.kind == "oligarch"
	if player_small:
		q /= Skills.stat("qstar")
	if q < 1.0:
		return "crater"
	return "break" if player_small else "shatter"


func _draw_outcome(rv: Rival, c: Vector2, px: float) -> void:
	var to := c - player.position
	var reach := (player.radius + rv.r) * 4.0
	if to.length() > reach:
		return
	var fade := clampf((reach - to.length()) / (reach * 0.4), 0.0, 1.0)
	var col: Color = {"merge": Color(0.5, 1.0, 0.55), "crater": Color(1.0, 0.82, 0.3),
		"shatter": Color(1.0, 0.55, 0.3), "break": Color(1.0, 0.32, 0.25)}[outcome(rv)]
	var face := (-to).angle()
	draw_arc(c, rv.r * 1.12 + 2.0 * px, face - 1.1, face + 1.1, 24, Color(col, 0.85 * fade), 2.5 * px, true)


func _draw() -> void:
	if not active():
		return
	var px := 1.0 / camera.zoom.x
	var font := ThemeDB.fallback_font
	for rv in rivals:
		if not rv.sprite.visible:
			continue
		var c := world_pos(rv)
		var km := GameData.planet_km(rv.mass)
		var title := "%s · %s км" % [rv.name, str(roundi(km)) if km >= 10.0 else String.num(km, 1)]
		var col := Color(0.85, 0.88, 1.0, 0.75)
		match rv.kind:
			"twin":
				title = "Пара · " + title
				col = Color(0.6, 1.0, 0.65, 0.85)
			"oligarch":
				title = "Олигарх · " + title
				col = Color(1.0, 0.8, 0.5, 0.85)
			"impactor":
				title = "Удар! · " + title
				col = Color(1.0, 0.45, 0.35, 0.95)
		var w := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		draw_set_transform(c + Vector2(-w * 0.5 * px, -rv.r - 10.0 * px), 0.0, Vector2(px, px))
		draw_string(font, Vector2.ZERO, title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)
		draw_set_transform(Vector2.ZERO)
		_draw_outcome(rv, c, px)
		# Удар на подлёте: пунктир его пути до тебя.
		if rv.kind == "impactor" and rv.hit_cd > -4.0:
			var dir := rv.vel.normalized()
			for k in 10:
				var a := c + dir * (rv.r + k * 2.0 * rv.r * 0.4)
				draw_line(a, a + dir * rv.r * 0.4, Color(1.0, 0.45, 0.35, 0.5), 1.5 * px)
