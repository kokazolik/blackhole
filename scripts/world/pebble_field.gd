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
signal chunks_broken(world_position: Vector2)
signal pebble_split(world_position: Vector2)
signal self_split(world_position: Vector2)
signal eddy_started(world_position: Vector2)
signal pebble_absorbed(world_position: Vector2)
signal crash_started(world_position: Vector2)  # два валуна летят друг в друга
signal crash_burst(world_position: Vector2)    # столкнулись: облако обломков
signal clump_started(world_position: Vector2)

const ATLAS := preload("res://assets/pebbles/pebble_atlas.png")
const SHADER := preload("res://shaders/pebble.gdshader")
const RIPPLE_SHADER := preload("res://shaders/pulse_ripple.gdshader")
const EDDY_SHADER := preload("res://shaders/eddy.gdshader")
const EDDY_EXTENT := 1.3  # половина стороны квадрата вихря в его радиусах (как EXTENT в шейдере)
const MAX_PEBBLES := 140
# Ветровая тень на валуне: за крупным телом (по ветру) газ почти стоит.
const SHADOW_LEN := 7.0     # длина тени в радиусах тела
const SHADOW_WIDTH := 1.25  # полуширина у самого тела, в радиусах
const SHADOW_CALM := 0.85   # насколько тень гасит снос в середине
const BASE_COUNT := 5               # галек в округе при плотности 1 (вне колец)
const RING_BOOST := 2.5               # в кольце-ловушке галек больше
# Радиусы чужих галек в долях радиуса игрока. Мелких обломков больше, чем крупных
# (распределение как после дробления), но встречаются и тела крупнее тебя.
const R_RANGE := Vector2(0.17, 1.25)
const R_SKEW := 2.2
const BOULDER_SKEW := 1.5
const BOULDER_COUNT := 1.5  # на валуне тел вокруг больше
# Съесть можно всё, что меньше тебя (до EAT_R твоего радиуса). Что меньше в
# 2,5 раза и больше (Skills.stat("grip"), база 0.4) — прилипает на любой скорости,
# остальное — только если подлетать медленно, пока дуга зелёная.
const EAT_R := 1.0
const EASY_MAX := 0.95       # навыки «Хватки» не поднимают порог «без дуги» выше этого
# Удар о крупную гальку откалывает от неё куски. Ты теряешь своё, а куски — мелочь,
# их можно доесть. Без навыков от сколов это всё же убыток.
const CHUNK_SHARE := 0.9     # масса отбитых кусков в долях твоей потери (до навыков)
const CHUNK_MAX := 0.25      # больше этой доли галька за удар не теряет
const CHUNK_R := Vector2(0.22, 0.3)
const SHARD_QUAD := 1.2    # квадрат обломка крупнее: острые углы выступают за круг
const SPLIT_FROM := 1.2      # удар быстрее предела слипания во столько раз — может расколоть
const SPLIT_RANGE := 1.0     # ещё на столько быстрее — шанс максимальный
const SPLIT_MAX := 0.6       # максимальный шанс расколоть гальку одного размера с тобой
const SPLIT_KEEP := 0.85     # доля вещества, что остаётся в частях (остальное — пыль)
const SELF_SPLIT_K := 0.2    # во сколько раз реже трескаешься ты сам
const GIANT_CHIP_FROM := 0.35   # удар о Странника быстрее этой доли предела слипания — сыплется крошка
const GIANT_SPLIT_FROM := 1.3   # а быстрее этого — раскалываешься
const GIANT_CHIP_LOSS := 0.012  # крошка: доля массы на каждый «предел слипания» скорости удара
const GIANT_SPLIT_LOSS := Vector2(0.15, 0.3)  # раскол: от сильного до лобового удара
const SELF_SPLIT_LOSS := 0.1 # сколько своей массы теряешь, треснув (куски можно подобрать)  # размер куска в долях твоего радиуса (рисуется крупнее, масса своя)
const SIZE_GAP := 0.15                 # вокруг твоего размера тел нет: либо заметно меньше, либо заметно больше
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
const PEBBLE_RESTITUTION := 0.15      # рыхлые гальки между собой почти не отпрыгивают: пыль гасит удар
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
# События этапа «Валун».
const CRASH_INTERVAL := 150.0         # столкновение валунов вдали: раз в пару минут
const CRASH_FLIGHT := 2.6             # секунд до удара после появления
const CRASH_PIECES := 11              # обломков с каждого валуна
const CRASH_MASS := 0.1               # масса облака в долях твоей
const CRASH_LIFE := 30.0              # облако живёт полминуты, потом рассыпается в пыль
const CRASH_VALUE := 2.0              # обломки ценнее обычной мелочи
const CLUMP_INTERVAL := 170.0         # сгусток: только в кольце-ловушке
const CLUMP_TIME := 25.0              # за столько он сжимается в валун
const CLUMP_COUNT := 30
const CLUMP_VALUE := 1.5
# Способности из дерева:
const MOON_ORBIT := 2.4    # «Пылевое гало»: орбита облачков в твоих радиусах
const MOON_R := 0.24       # радиус облачка (там, где оно подхватывает) в твоих радиусах
const MOON_SPIN := 1.3     # радиан в секунду
const CHAIN_R := 4.0       # «Цепная аккреция»: соседи в стольких радиусах съеденной гальки
const PULSE_EVERY := 15.0  # «Волна плотности» на первом уровне; дальше чаще
const PULSE_GROW := 0.6    # за столько волна доходит до края
const PULSE_REACH := 0.85  # доля радиуса притяжения, докуда бьёт волна
const DRIFT_EVERY := 0.2   # снос гальки пересчитываем несколько раз в секунду, а не каждый кадр
const PULLED_SPEED := 1.4  # притянутое летит к тебе с такой долей твоей скорости
# Хондры, вторая валюта: застывшие капли расплава внутри галек.
const CHONDRULE_CHANCE := 0.06  # с настоящего слипания (мелочь не в счёт)
const CHONDRULE_DEBRIS := 0.2   # с обломка столкновения или мелочи сгустка
const CHONDRULE_GEODE := 2      # в жеоде их сразу несколько
const CHONDRULE_BOULDER := 0.3  # валун ест в разы больше тел: шанс ниже, иначе хондр горы

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
	var chunk_mass := 0.0  # кусок, отбитый от крупной гальки: его масса задана при откалывании
	var hit_cd := 0.0      # пауза после удара, чтобы одно касание не било много раз
	var shard := false     # угловатый обломок (шейдер рисует гранёный камень вместо окатанной гальки)
	var shard_seed := 0.0  # форма обломка
	var own := false       # кусок, отколотый от тебя самого («Куча щебня» тянет его обратно)
	var life := 0.0        # >0 — обломок облака столкновения: рассыпется через столько секунд
	var crash := false     # валун, летящий на столкновение (газ его не тормозит)
	var clump := false     # из сгустка: стягивается к его центру
	var pulled := false    # сорвано цепной аккрецией или импульсом: летит к тебе и прилипает
	var drift := Vector2.ZERO  # снос встречным газом: меняется медленно, пересчитывается раз в DRIFT_EVERY
	var drift_t := 0.0

var player: Player
var dust_field: DustField
var camera: Camera2D
var pebbles: Array[Pebble] = []
var rng := RandomNumberGenerator.new()
var _mm := MultiMesh.new()
var _mm_node := MultiMeshInstance2D.new()
var _buf := PackedFloat32Array()
var _hint := Node2D.new()  # кольца-подсказки поверх галек
var giant := Giant.new()  # Странник: огромный валун проплывает мимо гальки
var _halo_glow := _make_glow()  # мягкое свечение облачков гало
var _ripple := ColorRect.new()  # рябь волны импульса (шейдер по картинке экрана)
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
var _crash_timer := 75.0
var _crash_pair: Array[Pebble] = []
var crash_left := 0.0   # сколько ещё живёт облако обломков
var crash_center := Vector2.ZERO  # в системе отсчёта пыли
var _clump_timer := 60.0
var clump_left := 0.0
var clump_center := Vector2.ZERO  # в системе отсчёта пыли
var clump_radius := 0.0
var _clump_r0 := 0.0
var _moon_angle := 0.0
var _pulse_timer := 4.0
var pulse_t := -1.0  # сколько идёт текущая волна импульса; <0 — волны нет


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
	giant.pebble_field = self
	add_child(giant)
	var ripple_mat := ShaderMaterial.new()
	ripple_mat.shader = RIPPLE_SHADER
	_ripple.material = ripple_mat
	_ripple.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ripple.visible = false
	add_child(_ripple)
	_hint.draw.connect(_draw_hints)
	add_child(_hint)


static func _make_glow() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	return tex


func world_pos(p: Pebble) -> Vector2:
	return p.pos + dust_field.frame_offset


func _process(delta: float) -> void:
	if player.pebble_k <= 0.0:
		return
	var to_star := -player.position.normalized()
	_mm_node.material.set_shader_parameter("light_dir", Vector2(to_star.x, -to_star.y))
	_mm_node.material.set_shader_parameter("star_light", DustField.STAR_LIGHT * (1.0 + 0.9 * Star.flare))
	_follow_world_scale()
	_maintain()
	_update_combo(delta)
	_update_swarm(delta)
	_update_eddy(delta)
	_update_crash(delta)
	_update_clump(delta)
	_update_abilities(delta)
	if giant.player == null:
		giant.player = player
		giant.dust_field = dust_field
	giant.update(delta)
	var drag := pow(DRAG, delta)
	var pull := Skills.stat("pebble_pull")
	var pull_cap := 0.5
	if GameState.is_boulder():
		# Своё притяжение валуна: само растёт к концу этапа, навыки «Тяготения»
		# включают его раньше и разгоняют притянутое быстрее.
		pull += GameData.self_gravity(GameState.mass) + Skills.stat("self_grav")
		pull_cap *= Skills.stat("grav_focus")
	var rubble := Skills.stat("rubble_pile") > 0.0
	var pull_r := player.pull_radius()  # не дальше края экрана, см. Player.pull_radius
	var evap := GameData.sublimation_distance()
	_update_casters()
	_cache_moons()
	var i := pebbles.size() - 1
	while i >= 0:
		var p := pebbles[i]
		var wp := world_pos(p)
		if not p.crash:
			p.vel *= drag
		if p.life > 0.0:
			p.life -= delta
			if p.life <= 0.0:
				# Облако рассеялось: несобранный обломок крошится в пыль.
				_debris(wp, Vector2.from_angle(rng.randf() * TAU), 10.0, p.material, 3)
				pebbles.remove_at(i)
				i -= 1
				continue
		if p.clump and clump_left > 0.0:
			_clump_pull(p, wp, delta)
		if p.eddy and eddy_left > 0.0:
			p.vel = p.vel.lerp(eddy_flow(wp), 1.0 - exp(-3.0 * delta))
		if p.pulled:
			var home := player.position - wp
			p.vel = home.normalized() * player.max_speed() * PULLED_SPEED
		elif rubble and p.own and p.hit_cd < 0.6:
			# «Куча щебня»: свои куски разлетелись и возвращаются, их держит твой вес.
			var back := player.position - wp
			p.vel = p.vel.move_toward(back.normalized() * player.max_speed() * 0.8, player.max_speed() * 2.0 * delta)
		elif pull > 0.0 and absorbable(p):
			# «Вихрь в газе» и притяжение валуна: подходящие гальки сами плывут к тебе.
			var to_p := player.position - wp
			var dl := to_p.length()
			if dl < pull_r and dl > 0.001:
				# Гальки подплывают, а не летят снарядом: тянем слабее, чем пыль, и не
				# разгоняем быстрее половины твоей скорости (с «Фокусировкой» — быстрее).
				p.vel += to_p / dl * player.radius * 4.0 * pull * (1.0 - dl / pull_r) * delta
				p.vel = p.vel.limit_length(player.max_speed() * pull_cap)
		p.drift_t -= delta
		if p.drift_t <= 0.0:
			p.drift = GameData.gas_drift(wp, p.r)
			p.drift_t = DRIFT_EVERY * rng.randf_range(0.8, 1.2)  # вразброс, чтобы не все в один кадр
		p.pos += (p.vel + calm_drift(wp, p.drift, p)) * delta
		p.angle += p.spin * delta
		p.hit_cd -= delta
		giant.shove(p, wp)
		if wp.length() < evap:
			evaporated.emit(wp, p.r)
			pebbles.remove_at(i)
		elif not player.dead and wp.distance_squared_to(player.position) < pow(_touch_r + p.r, 2):
			# Дальние гальки не трогают ни тебя, ни гало: им и проверки не нужны.
			if _moon_catch(p, wp):
				_eat(p, i, player.position + (wp - player.position).limit_length(player.radius), true)
			else:
				_collide(p, i)
		i -= 1
	_collide_pebbles(pull_r if pull > 0.0 else 0.0)
	_write()
	_hint.queue_redraw()


## Тела сталкиваются друг с другом: рыхлые комки отскакивают слабо, тяжёлое
## сдвигает лёгкое. Быстрый удар выбивает пыль. Летящие по сценарию (вихрь,
## сгусток, притянутые, только что отбитые куски) и мелочь валуна не мешаем.
## Гальки, что уже плывут к тебе по твоему притяжению (flow_r), идут потоком и не
## толкаются: иначе они застревали бы друг в друге на подлёте.
func _collide_pebbles(flow_r: float) -> void:
	var list: Array[Pebble] = []
	var max_r := 0.0
	var me := player.position - dust_field.frame_offset
	for p in pebbles:
		if p.food or p.pulled or p.crash or (p.clump and clump_left > 0.0) or (p.eddy and eddy_left > 0.0) \
				or (p.chunk_mass > 0.0 and p.hit_cd > 0.0):
			continue
		if flow_r > 0.0 and p.pos.distance_squared_to(me) < flow_r * flow_r and absorbable(p):
			continue
		list.append(p)
		max_r = maxf(max_r, p.r)
	if list.size() < 2:
		return
	# Сортировка по x: соседей ищем только в полосе ширины двух радиусов.
	list.sort_custom(func(a: Pebble, b: Pebble) -> bool: return a.pos.x < b.pos.x)
	var stick := player.stick_speed()
	for ia in list.size() - 1:
		var a := list[ia]
		var reach := (a.r + max_r) * 0.92
		for ib in range(ia + 1, list.size()):
			var b := list[ib]
			if b.pos.x - a.pos.x > reach:
				break
			var to := b.pos - a.pos
			var contact := (a.r + b.r) * 0.92
			var d2 := to.length_squared()
			if d2 >= contact * contact or d2 < 0.000001:
				continue
			var d := sqrt(d2)
			var n := to / d
			var ma := a.r * a.r * a.r
			var mb := b.r * b.r * b.r
			var wa := mb / (ma + mb)  # доля сдвига лёгкому — больше
			var overlap := contact - d
			a.pos -= n * overlap * wa
			b.pos += n * overlap * (1.0 - wa)
			var impact := (a.vel - b.vel).dot(n)  # скорость сближения
			if impact <= 0.0:
				continue
			var j := impact * (1.0 + PEBBLE_RESTITUTION)
			a.vel -= n * j * wa
			b.vel += n * j * (1.0 - wa)
			a.spin += rng.randf_range(-0.5, 0.5) * impact / maxf(a.r, 1.0) * wa
			b.spin += rng.randf_range(-0.5, 0.5) * impact / maxf(b.r, 1.0) * (1.0 - wa)
			a.spin = clampf(a.spin, -3.0, 3.0)
			b.spin = clampf(b.spin, -3.0, 3.0)
			if impact > stick and a.hit_cd <= 0.0 and b.hit_cd <= 0.0:
				a.hit_cd = 0.3
				b.hit_cd = 0.3
				var at := a.pos + n * a.r + dust_field.frame_offset
				_debris(at, n.orthogonal() * (1.0 if rng.randf() < 0.5 else -1.0), impact * 0.5, \
					a.material if a.r < b.r else b.material, clampi(int(impact / stick * 2.0), 2, 6))


## Крупные тела рядом, за которыми есть ветровая тень. Только на валуне: у гальки
## тела слишком мелкие, чтобы заслонить газ.
func _update_casters() -> void:
	_casters.clear()
	_shadow_wide = Skills.stat("shadow")
	if not GameState.is_boulder() or player.boulder_k < 1.0:
		return
	var reach := dust_field.view_radius() * 1.5
	for p in pebbles:
		if p.food or p.chunk_mass > 0.0 or absorbable(p) or p.r < player.radius * 0.7:
			continue
		var wp := world_pos(p)
		if wp.distance_to(player.position) > reach:
			continue
		var d := p.drift if p.drift_t > 0.0 else GameData.gas_drift(wp, p.r)
		if d.length_squared() < 0.0001:
			continue  # в кольце-ловушке ветра нет — и тени нет
		_casters.append([wp, d.normalized(), p.r, p, p.r * SHADOW_LEN * _shadow_wide])


## Середина ветровой тени ближайшего крупного тела на экране (для подсказки).
func shadow_spot() -> Vector2:
	var best := Vector2.INF
	var bd := dust_field.view_radius() * 0.6
	for c in _casters:
		var mid: Vector2 = c[0] + c[1] * c[2] * SHADOW_LEN * Skills.stat("shadow") * 0.35
		var d := mid.distance_to(player.position)
		if d < bd:
			bd = d
			best = mid
	return best


## Насколько точка в ветровой тени: 0 — на ветру, 1 — полное затишье.
func shadow_at(pos: Vector2, skip: Pebble = null) -> float:
	var best := 0.0
	var wide := _shadow_wide
	for c in _casters:
		if c[3] == skip:
			continue
		var v: Vector2 = pos - c[0]
		var length: float = c[4]
		# Дальше длины тени — сразу мимо, без остальной арифметики.
		if v.length_squared() > length * length:
			continue
		var r: float = c[2]
		var along := v.dot(c[1])
		if along < r * 0.5 or along > length:
			continue
		var across := absf(v.cross(c[1]))
		var t := along / length
		# Тень сужается к концу и гаснет: у самого тела шире и тише.
		var half := r * SHADOW_WIDTH * wide * (1.0 - 0.45 * t)
		var k := (1.0 - smoothstep(half * 0.55, half, across)) * (1.0 - t * t)
		best = maxf(best, k)
	return best


## Снос, ослабленный ветровой тенью.
func calm_drift(pos: Vector2, drift: Vector2, skip: Pebble = null) -> Vector2:
	if _casters.is_empty():
		return drift
	return drift * (1.0 - SHADOW_CALM * shadow_at(pos, skip))


## При превращении в валун мир вокруг мельчает (GameData.world_k): гальки
## уменьшаются и стягиваются к игроку вместе с камерой, сцена не дёргается.
var _world_k := -1.0
var _shadow_wide := 1.0
var _casters: Array = []  # [мир. позиция, направление ветра, радиус] — кто отбрасывает тень


func _follow_world_scale() -> void:
	var k := GameData.world_k
	if _world_k < 0.0:
		_world_k = k
	if is_equal_approx(k, _world_k):
		return
	var ratio := k / _world_k
	_world_k = k
	var c := player.position - dust_field.frame_offset
	for p in pebbles:
		p.r *= ratio
		p.pos = c + (p.pos - c) * ratio
		p.vel *= ratio
	if eddy_left > 0.0:
		eddy_radius *= ratio
		eddy_center = c + (eddy_center - c) * ratio


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
	var target := mini(int(BASE_COUNT * (BOULDER_COUNT if GameState.is_boulder() else 1.0) * clampf(density, 0.3, 2.5) * Skills.stat("pebbles") * player.pebble_k * thin + 0.5), MAX_PEBBLES)
	var food_target := int(FOOD_COUNT * clampf(density, 0.3, 2.5) * Skills.stat("pebbles") * player.boulder_k + 0.5)
	var bodies := 0
	var food := 0
	for p in pebbles:
		if p.food:
			food += 1
		elif p.chunk_mass <= 0.0:  # отбитые куски не в счёт: они не вместо новых галек
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
	# На валуне крупной съедобной добычи больше: за неё дают много.
	p.r = player.radius * lerpf(R_RANGE.x, R_RANGE.y, pow(rng.randf(), BOULDER_SKEW if GameState.is_boulder() else R_SKEW))
	# Чуть-чуть крупнее предела не бывает: несъедобная галька должна выглядеть
	# заметно крупнее самой большой съедобной, а не «такой же».
	# Тел почти с тебя ростом не бывает: съедобное должно быть видно меньше тебя,
	# несъедобное — видно крупнее.
	var rel := p.r / player.radius
	if absf(rel - EAT_R) < SIZE_GAP:
		p.r = player.radius * (EAT_R - SIZE_GAP if rel < EAT_R else EAT_R + SIZE_GAP)
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
	return p.food or p.r < player.radius * EAT_R


## Мелочь, которая прилипает на любой скорости: еда валуна, отбитые куски и крошечные гальки.
func is_easy(p: Pebble) -> bool:
	return p.food or p.pulled or p.chunk_mass > 0.0 or p.r < player.radius * easy_r()


## Доля твоего радиуса, мельче которой тела прилипают на любой скорости.
func easy_r() -> float:
	return minf(Skills.stat("grip"), EASY_MAX)


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
	for k in count:
		var p := Pebble.new()
		p.pos = center + Vector2(rng.randfn(0.0, spread), rng.randfn(0.0, spread)) - dust_field.frame_offset
		# Рой из галек, которые ты способен присоединить: гоняться за ним есть смысл.
		p.r = player.radius * rng.randf_range(R_RANGE.x, EAT_R * 0.7)
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
	var count := mini(EDDY_COUNT, MAX_PEBBLES - pebbles.size())
	for k in count:
		var p := Pebble.new()
		var a := rng.randf() * TAU
		var d := eddy_radius * sqrt(rng.randf_range(0.04, 1.0))
		p.pos = eddy_center + Vector2.from_angle(a) * d
		# Половина по зубам, остальные крупнее: сталкиваться с ними на ходу больно.
		if rng.randf() < 0.5:
			p.r = player.radius * rng.randf_range(R_RANGE.x, EAT_R - SIZE_GAP)
		else:
			p.r = player.radius * rng.randf_range(EAT_R + SIZE_GAP, 1.5)
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
	var rel := player.motion() - (p.vel + p.drift)
	var impact := rel.dot(n)  # скорость сближения вдоль линии удара
	var stick := player.stick_speed() * Skills.stat("glue_" + p.material)
	var at := player.position + n * player.radius
	if p.chunk_mass > 0.0 and p.hit_cd > 0.0:
		return  # только что отбитый кусок ещё разлетается
	var easy := is_easy(p)
	if easy or (absorbable(p) and impact <= stick):
		_eat(p, index, at, easy)
		_chain_from(p, wp)
		return
	if impact > stick and p.hit_cd <= 0.0:
		p.hit_cd = 0.3
		var excess := impact / stick
		var m_other := GameData.pebble_mass(p.r, GameState.mass)
		var cap := GameData.CHIP_MAX if absorbable(p) else GameData.CHIP_MAX_BIG
		var raw_loss := minf(GameData.CHIP_K * m_other * (excess * excess - 1.0), GameState.mass * cap)
		var loss := raw_loss * Skills.stat("chip")
		if not absorbable(p):
			# Ты тоже можешь треснуть, но ты крепче: шанс в разы меньше, чем у гальки.
			if p.r > player.radius * 0.6 and rng.randf() < split_chance(p, excess) * SELF_SPLIT_K:
				_self_split(at, n, impact)
			if rng.randf() < split_chance(p, excess):
				GameState.chip(loss, at)
				_debris(at, n * -1.0, impact, _main_material(), clampi(int(loss * 6.0), 3, 14))
				_split(p, index, wp, n, impact, m_other)
				_bounce(n, impact, p, 0.4)
				return
			_break_chunks(p, wp, n, impact, minf(raw_loss * CHUNK_SHARE, m_other * CHUNK_MAX), m_other)
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



## Спутники кружат вокруг и подбирают то, что прилипло бы к тебе само.
func moon_count() -> int:
	return int(Skills.stat("moons"))


func moon_pos(k: int) -> Vector2:
	var n := moon_count()
	var orbit := player.radius * MOON_ORBIT * sqrt(Skills.stat("moon_size"))
	return player.position + Vector2.from_angle(_moon_angle + k * TAU / n) * orbit


func moon_radius() -> float:
	return player.radius * MOON_R * Skills.stat("moon_size")


## Облачка гало на этот кадр: их проверяет каждая галька, считать один раз.
var _moon_pts := PackedVector2Array()
var _moon_r := 0.0
var _easy_r := 0.0
var _touch_r := 0.0  # дальше этого от тебя (плюс радиус гальки) ни удара, ни гало


func _cache_moons() -> void:
	_moon_pts.clear()
	_easy_r = player.radius * easy_r()
	_touch_r = player.radius
	for k in moon_count():
		_moon_pts.append(moon_pos(k))
	_moon_r = moon_radius()
	if not _moon_pts.is_empty():
		_touch_r = maxf(_touch_r, _moon_pts[0].distance_to(player.position) + _moon_r)
	# Запас на кадр движения: тела сближаются, пока мы считаем.
	_touch_r += player.max_speed() * 0.1 + 2.0


func _moon_catch(p: Pebble, wp: Vector2) -> bool:
	if _moon_pts.is_empty() or p.pulled or (p.chunk_mass > 0.0 and p.hit_cd > 0.0):
		return false
	if not (p.food or p.chunk_mass > 0.0 or p.r < _easy_r):
		return false
	for m in _moon_pts:
		var reach := _moon_r + p.r
		if wp.distance_squared_to(m) < reach * reach:
			return true
	return false


func _update_abilities(delta: float) -> void:
	_moon_angle = fmod(_moon_angle + MOON_SPIN * delta, TAU)
	var lvl := Skills.stat("pulse")
	if pulse_t >= 0.0:
		pulse_t += delta
		_pulse_wave()
		if pulse_t > PULSE_GROW + 0.5:
			pulse_t = -1.0
	if lvl <= 0.0 or player.dead:
		return
	_pulse_timer -= delta
	if _pulse_timer <= 0.0:
		_pulse_timer = PULSE_EVERY / (0.5 + 0.5 * lvl)
		pulse_t = 0.0
		(_ripple.material as ShaderMaterial).set_shader_parameter("seed", randf())


## Волна импульса расходится и срывает с места всё, что можно съесть.
func _pulse_wave() -> void:
	var r := pulse_radius() * clampf(pulse_t / PULSE_GROW, 0.0, 1.0)
	for p in pebbles:
		if not p.pulled and absorbable(p) and not p.crash and world_pos(p).distance_to(player.position) < r:
			p.pulled = true


func pulse_radius() -> float:
	return player.pull_radius() * PULSE_REACH


## «Цепная аккреция»: съеденная галька тянет за собой мелких соседей.
func _chain_from(p: Pebble, wp: Vector2) -> void:
	var chance := Skills.stat("chain_eat")
	if chance <= 0.0:
		return
	var reach := p.r * CHAIN_R + player.radius * 0.5
	for q in pebbles:
		if q.pulled or q.crash or q.r > p.r or not absorbable(q):
			continue
		if world_pos(q).distance_to(wp) < reach and rng.randf() < chance:
			q.pulled = true


func _draw_abilities() -> void:
	_draw_halo()
	# Волна плотности — уплотнение газа по картинке мира (см. pulse_ripple.gdshader).
	_ripple.visible = pulse_t >= 0.0
	if pulse_t >= 0.0:
		var k := clampf(pulse_t / PULSE_GROW, 0.0, 1.0)
		var fade := 1.0 - clampf((pulse_t - PULSE_GROW) / 0.5, 0.0, 1.0)
		var r := pulse_radius() * (1.0 - pow(1.0 - k, 2.0))
		var half := pulse_radius() * 1.15
		_ripple.position = player.position - Vector2(half, half)
		_ripple.size = Vector2(half, half) * 2.0
		var mat := _ripple.material as ShaderMaterial
		mat.set_shader_parameter("ring", r / half)
		mat.set_shader_parameter("fade", fade * minf(1.0, k * 4.0))
		var ice := smoothstep(GameData.SNOW_LINE - GameData.SNOW_LINE_WIDTH, GameData.SNOW_LINE + GameData.SNOW_LINE_WIDTH, player.position.length())
		mat.set_shader_parameter("tint", Color(0.92, 0.78, 0.6).lerp(Color(0.75, 0.86, 1.0), ice))


## Пылевое гало: облачка заряженной пыли кружат вокруг тебя, а по орбите —
## редкие парящие пылинки. Ни одного твёрдого тела, только пыль в свете звезды.
func _draw_halo() -> void:
	var n := moon_count()
	if n <= 0:
		return
	var px := 1.0 / camera.zoom.x
	var mr := moon_radius()
	var orbit := player.radius * MOON_ORBIT * sqrt(Skills.stat("moon_size"))
	var dust := Color(0.86, 0.78, 0.64)
	var t := Time.get_ticks_msec() * 0.001
	# Тонкое кольцо пылинок по всей орбите.
	for i in 36:
		var a := _moon_angle * 0.6 + i * TAU / 36.0 + sin(i * 7.3) * 0.08
		var rr := orbit * (1.0 + 0.12 * sin(i * 3.1 + t * 0.7))
		_hint.draw_circle(player.position + Vector2.from_angle(a) * rr, 0.6 * px + mr * 0.04, Color(dust, 0.22))
	for k in n:
		var c := moon_pos(k)
		var g := mr * 2.6
		_hint.draw_texture_rect(_halo_glow, Rect2(c - Vector2(g, g), Vector2(g, g) * 2.0), false, Color(dust, 0.16))
		# Пылинки облачка роятся вокруг его центра и чуть тянутся хвостом по орбите.
		for i in 16:
			var f := float(i) / 16.0
			var a := t * (0.9 + f) + i * 2.399
			var rr := mr * (0.25 + 0.85 * fmod(i * 0.618, 1.0))
			var trail := Vector2.from_angle(_moon_angle + k * TAU / n - PI * 0.5) * mr * 0.9 * f
			var sz := 0.7 * px + mr * (0.05 + 0.05 * fmod(i * 0.37, 1.0))
			_hint.draw_circle(c + Vector2.from_angle(a) * rr - trail, sz, Color(dust.lightened(0.15 * (1.0 - f)), 0.75 - 0.4 * f))


## Присоединить гальку: масса, звёздная пыль, серия. Зовут удар игрока,
## спутники и цепная аккреция. index — место гальки в pebbles, она удаляется.
func _eat(p: Pebble, index: int, at: Vector2, easy: bool) -> void:
	var wp := world_pos(p)
	var m := GameData.bite_mass(p.r * (FOOD_MASS_R if p.food else 1.0), GameState.mass)
	if p.chunk_mass > 0.0:
		m = p.chunk_mass
	m *= ACCRETION * Skills.stat("accretion") * GameData.boulder_gain(GameState.mass)
	if not easy:  # серию держат только настоящие слипания, мелочь её не продлевает
		chain += 1
		_chain_timer = GameData.COMBO_WINDOW
	var size_rel := p.r * (FOOD_MASS_R if p.food else 1.0) / player.radius
	var value := VALUE_PER_PEBBLE * pow(GameState.mass / 30.0, VALUE_MASS_EXP) * pow(size_rel / 0.2, 1.5) * combo_multiplier()
	if p.eddy:
		value *= EDDY_VALUE
	if p.life > 0.0:
		value *= CRASH_VALUE * Skills.stat("debris_value")
	if p.clump:
		value *= CLUMP_VALUE * Skills.stat("debris_value")
	if p.food:
		value *= FOOD_VALUE
	if GameState.is_boulder():
		value *= GameData.boulder_value(GameState.mass)
	if p.geode:
		value *= Skills.stat("geode_value")
		geode_found.emit(wp, value)
	GameState.absorb_mass(m, value, p.material, at)
	pebble_absorbed.emit(wp)
	var found := 0
	if p.geode:
		found = CHONDRULE_GEODE
	else:
		var k := CHONDRULE_BOULDER if GameState.is_boulder() else 1.0
		if (p.life > 0.0 or p.clump) and rng.randf() < CHONDRULE_DEBRIS * k:
			found = 1
		elif not easy and rng.randf() < CHONDRULE_CHANCE * k:
			found = 1
	if found > 0:
		GameState.add_chondrules(found, wp)
	if Skills.stat("combo") > 0.0 and chain >= 2 and not easy:
		combo_changed.emit(chain, combo_multiplier())
	pebbles.remove_at(index)


## Шанс расколоть крупную гальку целиком: нужен удар куда быстрее предела
## слипания, и чем галька крупнее тебя, тем она крепче.
func split_chance(p: Pebble, excess: float) -> float:
	var hard := clampf((excess - SPLIT_FROM) / SPLIT_RANGE, 0.0, 1.0)
	var size_k := clampf(1.6 - p.r / player.radius, 0.15, 1.0)
	return hard * SPLIT_MAX * size_k


## Галька раскалывается на несколько частей разбиением Вороного: мелкие можно
## доесть, крупные остаются крупными. Часть вещества уходит пылью.
func _split(p: Pebble, index: int, wp: Vector2, n: Vector2, impact: float, m_other: float) -> void:
	pebbles.remove_at(index)
	var shape := _silhouette()
	var seeds: Array[Vector2] = []
	var local_hit := (-n).rotated(-p.angle)  # точка удара в осях гальки
	for k in rng.randi_range(3, 5):
		# Зёрна гуще у места удара: там осколки мельче.
		var q := Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * 0.85
		seeds.append(q.lerp(local_hit * 0.7, 0.3 if k < 2 else 0.0))
	var cells := _voronoi(shape, seeds)
	var total_area := 0.0
	for cell in cells:
		total_area += absf(_area(cell))
	var mat_cell := GameData.MATERIAL_ORDER.find(p.material) * 4 + rng.randi() % 4
	var k := 0
	for cell in cells:
		if pebbles.size() >= MAX_PEBBLES:
			break
		var share := absf(_area(cell)) / total_area * SPLIT_KEEP
		var c := Pebble.new()
		c.r = p.r * pow(share, 1.0 / 3.0)
		var centre := _set_shape(c, cell)
		var out := centre.rotated(p.angle)
		c.pos = wp + out * p.r - dust_field.frame_offset
		var d := (out.normalized() * 0.6 + n * 0.4).normalized()  # разлетаются от центра и от удара
		c.vel = d * impact * rng.randf_range(0.3, 0.6)
		c.material = p.material
		c.cell = mat_cell  # одна текстура на все части: узор продолжается через изломы
		c.angle = p.angle
		c.spin = rng.randf_range(-1.2, 1.2)
		c.geode = p.geode and k == 0
		c.hit_cd = 0.6
		pebbles.append(c)
		k += 1
	_debris(wp, n, impact, p.material, clampi(int(p.r * 2.0), 6, 18))
	pebble_split.emit(wp)


## Контур гальки (в её радиусах, центр в нуле) — чуть неровный круг.
func _silhouette() -> PackedVector2Array:
	var pts := PackedVector2Array()
	var ph := rng.randf() * TAU
	for i in 22:
		var a := TAU * i / 22.0
		pts.append(Vector2.from_angle(a) * (1.0 + 0.06 * sin(3.0 * a + ph) + 0.03 * sin(5.0 * a + ph * 2.0)))
	return pts


## Ячейки Вороного внутри контура: каждой достаются точки, ближайшие к её зерну.
func _voronoi(shape: PackedVector2Array, seeds: Array[Vector2]) -> Array[PackedVector2Array]:
	var cells: Array[PackedVector2Array] = []
	for i in seeds.size():
		var cell := shape
		for j in seeds.size():
			if i == j or seeds[i].distance_squared_to(seeds[j]) < 1e-6:
				continue
			cell = _clip_half(cell, (seeds[i] + seeds[j]) * 0.5, (seeds[j] - seeds[i]).normalized())
			if cell.size() < 3:
				break
		if cell.size() >= 3 and absf(_area(cell)) > 0.01:
			cells.append(cell)
	return cells


## Оставляет часть многоугольника, где (x − m)·d ≤ 0 (отсечение Сазерленда — Ходжмана).
func _clip_half(poly: PackedVector2Array, m: Vector2, d: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var cnt := poly.size()
	for k in cnt:
		var a := poly[k]
		var b := poly[(k + 1) % cnt]
		var da := (a - m).dot(d)
		var db := (b - m).dot(d)
		if da <= 0.0:
			out.append(a)
		if (da <= 0.0) != (db <= 0.0):
			out.append(a.lerp(b, da / (da - db)))
	return out


func _area(poly: PackedVector2Array) -> float:
	var sum := 0.0
	for k in poly.size():
		sum += poly[k].cross(poly[(k + 1) % poly.size()])
	return sum * 0.5


func _centroid(poly: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	var a := 0.0
	for k in poly.size():
		var p0 := poly[k]
		var p1 := poly[(k + 1) % poly.size()]
		var w := p0.cross(p1)
		c += (p0 + p1) * w
		a += w
	return c / (3.0 * a) if absf(a) > 1e-6 else poly[0]


## Отмечает обломок и возвращает центр его ячейки (в радиусах исходного тела).
func _set_shape(c: Pebble, cell: PackedVector2Array) -> Vector2:
	c.shard = true
	c.shard_seed = rng.randf() * 0.99
	return _centroid(cell)


## Кусок, сколотый с поверхности тела радиуса 1 в сторону u: срезанная «шапка»,
## поделённая на parts частей. У каждой части есть дуга прежней поверхности.
func _cap_pieces(u: Vector2, parts: int) -> Array:
	var shape := _silhouette()
	var tilt := u.rotated(rng.randf_range(-0.45, 0.45))
	var depth := 1.0 - rng.randf_range(0.4, 0.65)
	var cap := _clip_half(shape, tilt * depth, -tilt)
	var seeds: Array[Vector2] = []
	var perp := tilt.orthogonal()
	for k in parts:
		var t := (float(k) + 0.5) / parts * 2.0 - 1.0
		seeds.append(tilt * (depth + (1.0 - depth) * rng.randf_range(0.3, 0.7)) + perp * (t * 0.55 + rng.randf_range(-0.12, 0.12)))
	var cells := _voronoi(cap, seeds) if parts > 1 else ([cap] as Array[PackedVector2Array])
	return [cells, shape]


## Ты треснул: от тебя откалывается край, и он разваливается на куски твоего вещества.
func _self_split(at: Vector2, n: Vector2, impact: float, share := SELF_SPLIT_LOSS) -> void:
	var lost := GameState.mass * share * clampf(Skills.stat("chip"), 0.3, 1.0)
	var mat := _main_material()
	GameState.chip(lost, at)
	var parts := rng.randi_range(3, 4)
	var res := _cap_pieces(n, parts)
	var cells: Array[PackedVector2Array] = res[0]
	var cell_id := GameData.MATERIAL_ORDER.find(mat) * 4 + rng.randi() % 4
	for cell in cells:
		if pebbles.size() >= MAX_PEBBLES:
			break
		var c := Pebble.new()
		c.r = player.radius * rng.randf_range(0.3, 0.42)
		var centre := _set_shape(c, cell)
		var d := (centre.normalized() * 0.7 + Vector2.from_angle(rng.randf() * TAU) * 0.3).normalized()
		c.pos = player.position + centre * player.radius + d * 3.0 - dust_field.frame_offset
		c.vel = (d - n * 0.5).normalized() * maxf(impact, player.stick_speed()) * rng.randf_range(0.4, 0.8)
		c.chunk_mass = lost / cells.size()
		c.own = true
		c.material = mat
		c.cell = cell_id
		c.angle = 0.0
		c.spin = rng.randf_range(-1.5, 1.5)
		c.hit_cd = 1.2
		pebbles.append(c)
	self_split.emit(at)


## Середина ещё не съеденных отбитых кусков (INF, если их нет).
func chunk_center() -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for p in pebbles:
		if p.chunk_mass > 0.0:
			sum += world_pos(p)
			n += 1
	return sum / n if n > 0 else Vector2.INF


## От крупной гальки откалывается край у места удара и разваливается на куски:
## она худеет, а куски можно доесть.
func _break_chunks(p: Pebble, wp: Vector2, n: Vector2, impact: float, total: float, m_other: float) -> void:
	if total <= 0.0:
		return
	p.r *= pow(maxf(1.0 - total / m_other, 0.05), 1.0 / 3.0)
	var avg_r := player.radius * (CHUNK_R.x + CHUNK_R.y) * 0.5
	var avg_m := GameData.pebble_mass(avg_r, GameState.mass)
	var count := clampi(int(round(total / maxf(avg_m, 0.0001))), 2, 5)
	count = mini(count, MAX_PEBBLES - pebbles.size())
	if count <= 0:
		return
	var at := wp - n * p.r  # точка удара на поверхности гальки
	var res := _cap_pieces((-n).rotated(-p.angle), count)
	var cells: Array[PackedVector2Array] = res[0]
	for cell in cells:
		var c := Pebble.new()
		c.r = player.radius * rng.randf_range(CHUNK_R.x, CHUNK_R.y)
		var centre := _set_shape(c, cell)
		var out := centre.rotated(p.angle)
		c.pos = wp + out * p.r - dust_field.frame_offset
		c.chunk_mass = total / cells.size()
		c.material = p.material
		c.cell = p.cell
		c.angle = p.angle
		c.spin = rng.randf_range(-1.5, 1.5)
		# Разлетаются в стороны от удара, а не прямо в тебя.
		var side := 1.0 if out.cross(-n) > 0.0 else -1.0
		var d := (-n).rotated(side * rng.randf_range(0.7, 1.5))
		c.vel = d * maxf(impact, player.stick_speed()) * rng.randf_range(0.6, 1.0)
		c.hit_cd = 1.0
		pebbles.append(c)
	chunks_broken.emit(at)


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


## Пыль брызгами от удара (о Странника и т. п.).
## Удар о Странника: он в десятки раз тяжелее и твёрже тебя. Слабый толчок
## сбивает горсть крошки, сильный раскалывает тебя на куски (их можно собрать).
func giant_hit(at: Vector2, n: Vector2, impact: float) -> void:
	var stick := player.stick_speed()
	if impact < stick * GIANT_CHIP_FROM:
		return
	if chain > 0:
		chain = 0
		combo_changed.emit(0, 1.0)
	if impact >= stick * GIANT_SPLIT_FROM:
		var share := lerpf(GIANT_SPLIT_LOSS.x, GIANT_SPLIT_LOSS.y, clampf((impact / stick - GIANT_SPLIT_FROM) / 1.5, 0.0, 1.0))
		_debris(at, n, impact, _main_material(), 12)
		_self_split(at, n, impact, share)
		return
	var loss := GameState.mass * GIANT_CHIP_LOSS * impact / stick * Skills.stat("chip")
	GameState.chip(loss, at)
	_debris(at, n, impact, _main_material(), clampi(int(impact / stick * 4.0), 3, 7))


func spray_from(at: Vector2, dir: Vector2, impact: float, material: String) -> void:
	_debris(at, dir, impact, material, 3)


## Осколки разлетаются веером от точки удара и становятся обычной пылью.
func _debris(at: Vector2, dir: Vector2, impact: float, material: String, count: int) -> void:
	for k in count:
		var d := dir.rotated(rng.randf_range(-1.3, 1.3))
		var speed := impact * rng.randf_range(0.5, 1.3) + 20.0 * GameData.world_k
		var level := 1 + int(rng.randf() < 0.45) + int(rng.randf() < 0.15)
		dust_field.add_debris(at + d * rng.randf_range(0.5, 2.5), d * speed, mini(level, Skills.max_dust_level()), material)


func _write() -> void:
	var off := dust_field.frame_offset
	for k in pebbles.size():
		var p := pebbles[k]
		var s := p.r * QUAD * (SHARD_QUAD if p.shard else 1.0)
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
		# 1 — жеода, 2 + доля — обломок с формой по этой доле.
		_buf[b + 11] = 2.0 + p.shard_seed if p.shard else (1.0 if p.geode else 0.0)
	_mm.buffer = _buf
	_mm.visible_instance_count = pebbles.size()


## Ветровая тень — едва заметная прохладная полоса за крупным телом.
func _draw_shadows() -> void:
	var wide := Skills.stat("shadow")
	for c in _casters:
		var wp: Vector2 = c[0]
		var dir: Vector2 = c[1]
		var r: float = c[2]
		var side := dir.orthogonal()
		var length := r * SHADOW_LEN * wide
		# Две половины: к середине светлее, к краям сходит на нет — мягкая полоса.
		for sgn in [1.0, -1.0]:
			var edge := PackedVector2Array()
			var core := PackedVector2Array()
			var ce := PackedColorArray()
			var cc := PackedColorArray()
			for k in 8:
				var t := lerpf(0.07, 1.0, k / 7.0)
				var half := r * SHADOW_WIDTH * wide * (1.0 - 0.45 * t) * 0.85
				var mid := wp + dir * length * t
				edge.append(mid + side * half * sgn)
				core.append(mid)
				ce.append(Color(0.6, 0.85, 1.0, 0.0))
				cc.append(Color(0.6, 0.85, 1.0, 0.09 * (1.0 - t * t)))
			core.reverse()
			cc.reverse()
			edge.append_array(core)
			ce.append_array(cc)
			_hint.draw_polygon(edge, ce)


## Дуга со стороны игрока подсказывает, чем кончится удар на текущей скорости:
## зелёная — слипнетесь, красная — полетят осколки. Слишком крупные гальки
## обведены пунктиром: их не присоединить, только оттолкнуть.
func _draw_hints() -> void:
	if player.dead:
		return
	var px := 1.0 / camera.zoom.x
	_draw_shadows()
	_draw_clump()
	_draw_abilities()
	var stick := player.stick_speed()
	# Пунктиры всех крупных галек — одним вызовом: по вызову на штрих телефон
	# не тянул, когда вокруг рой крупных галек.
	var dash_pts := PackedVector2Array()
	var dash_cols := PackedColorArray()
	for p in pebbles:
		if is_easy(p):
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
			if p.shard:
				continue  # круг вокруг угловатого обломка смотрится чужим: его видно и так
			# Мелкий пунктир вплотную к гальке: заметно, но не спорит с самой галькой.
			var dash_col := Color(0.8, 0.85, 1.0, 0.3 * fade)
			for k in 24:
				var a0 := k * TAU / 24.0
				dash_pts.append(wp + Vector2.from_angle(a0) * p.r * 1.1)
				dash_pts.append(wp + Vector2.from_angle(a0 + TAU / 72.0) * p.r * 1.1)
				dash_cols.append(dash_col)
			continue
		var n := to / maxf(dist, 0.001)
		var approach := (player.motion() - p.drift).dot(n)
		var ok := approach <= stick * Skills.stat("glue_" + p.material)
		var col := Color(0.5, 1.0, 0.55) if ok else Color(1.0, 0.32, 0.25)
		var face := (-to).angle()
		_hint.draw_arc(wp, rr, face - 1.1, face + 1.1, 20, Color(col, 0.85 * fade), w_face * px, true)
		# Остаток кольца — цвет материала: нужное вещество видно издалека.
		var mat_col: Color = GameData.MATERIALS[p.material].color
		_hint.draw_arc(wp, rr, face + 1.1, face + TAU - 1.1, 28, Color(mat_col, 0.55 * fade), w_mat * px, true)
	if not dash_pts.is_empty():
		_hint.draw_multiline_colors(dash_pts, dash_cols, -1.0)


## Столкновение валунов: вдали два крупных тела летят друг в друга и
## разбиваются в облако быстрых обломков. Собирать их выгодно, но они быстрые.
func _update_crash(delta: float) -> void:
	if crash_left > 0.0:
		crash_left -= delta
	if not GameState.is_boulder() or player.boulder_k < 1.0 or player.dead:
		return
	if not _crash_pair.is_empty():
		var a: Pebble = _crash_pair[0]
		var b: Pebble = _crash_pair[1]
		if not (a in pebbles and b in pebbles):
			for q in _crash_pair:
				q.crash = false
			_crash_pair.clear()
			return
		if a.pos.distance_to(b.pos) < (a.r + b.r) * 0.9:
			_crash_burst(a, b)
		return
	_crash_timer -= delta
	if _crash_timer <= 0.0:
		_crash_timer = CRASH_INTERVAL * rng.randf_range(0.8, 1.2)
		_start_crash()


func _start_crash() -> void:
	var view_r := dust_field.view_radius()
	var dir := player.velocity.normalized() if player.velocity.length() > 5.0 else Vector2.from_angle(rng.randf() * TAU)
	var center := player.position + dir.rotated(rng.randf_range(-0.8, 0.8)) * view_r * 0.45
	if center.length() < GameData.sublimation_distance() * 1.4 or pebbles.size() > MAX_PEBBLES - 2 * CRASH_PIECES - 2:
		_crash_timer = 20.0
		return
	var axis := Vector2.from_angle(rng.randf() * TAU)
	var gap := view_r * 0.32
	for side in [-1.0, 1.0]:
		var p := Pebble.new()
		p.r = player.radius * rng.randf_range(1.0, 1.35)
		p.pos = center + axis * side * gap - dust_field.frame_offset
		p.vel = -axis * side * (gap - p.r) / CRASH_FLIGHT
		p.material = _pick_material(center.length())
		p.cell = GameData.MATERIAL_ORDER.find(p.material) * 4 + rng.randi() % 4
		p.angle = rng.randf() * TAU
		p.spin = rng.randf_range(-0.3, 0.3)
		p.crash = true
		pebbles.append(p)
		_crash_pair.append(p)
	crash_started.emit(center)


func _crash_burst(a: Pebble, b: Pebble) -> void:
	var at := (world_pos(a) + world_pos(b)) * 0.5
	var mid_vel := (a.vel + b.vel) * 0.5
	var speed := a.vel.length() + b.vel.length()
	var total := GameState.mass * CRASH_MASS
	var count := CRASH_PIECES * 2
	var room := MAX_PEBBLES - pebbles.size() + 2
	for body: Pebble in [a, b]:
		pebbles.erase(body)
		var wp := body.pos + dust_field.frame_offset
		var seeds: Array[Vector2] = []
		for k in CRASH_PIECES:
			seeds.append(Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * 0.9)
		var cells := _voronoi(_silhouette(), seeds)
		var area := 0.0
		for cell in cells:
			area += absf(_area(cell))
		var mat_cell := GameData.MATERIAL_ORDER.find(body.material) * 4 + rng.randi() % 4
		for cell in cells:
			if room <= 0:
				break
			room -= 1
			var share := absf(_area(cell)) / area
			var c := Pebble.new()
			c.r = body.r * pow(share, 1.0 / 3.0) * 0.9
			var centre := _set_shape(c, cell).rotated(body.angle)
			c.pos = body.pos + centre * body.r
			var out := (wp + centre * body.r - at).normalized()
			c.vel = mid_vel + out * speed * rng.randf_range(0.5, 1.1)
			c.chunk_mass = total / count
			c.material = body.material
			c.cell = mat_cell
			c.angle = body.angle
			c.spin = rng.randf_range(-2.0, 2.0)
			c.life = CRASH_LIFE * rng.randf_range(0.85, 1.0)
			c.hit_cd = 0.8
			pebbles.append(c)
		_debris(wp, (wp - at).normalized(), speed, body.material, 16)
	_crash_pair.clear()
	crash_center = at - dust_field.frame_offset
	crash_left = CRASH_LIFE
	crash_burst.emit(at)


## Середина ещё не собранного облака обломков (INF, если его нет).
func crash_spot() -> Vector2:
	if crash_left <= 0.0:
		return Vector2.INF
	var sum := Vector2.ZERO
	var n := 0
	for p in pebbles:
		if p.life > 0.0:
			sum += world_pos(p)
			n += 1
	return sum / n if n >= 4 else Vector2.INF


## Сгусток: в кольце-ловушке мелочь сбивается в облако, которое сжимается
## (потоковая неустойчивость в полную силу). Кто успел в центр — забирает
## большую часть; что не собрали, к концу слипается в новый валун.
func _update_clump(delta: float) -> void:
	if clump_left > 0.0:
		clump_left -= delta
		clump_radius = _clump_r0 * lerpf(0.25, 1.0, clump_left / CLUMP_TIME)
		if clump_left <= 0.0:
			_clump_end()
		return
	if not GameState.is_boulder() or player.boulder_k < 1.0 or player.dead:
		return
	if GameData.trap_strength(player.position.length()) < 0.5:
		return  # сгусток бывает только там, где копятся гальки
	_clump_timer -= delta
	if _clump_timer <= 0.0:
		_clump_timer = CLUMP_INTERVAL * rng.randf_range(0.8, 1.2)
		_start_clump()


func _start_clump() -> void:
	var view_r := dust_field.view_radius()
	# Вдоль кольца, а не поперёк: сгусток остаётся в ловушке.
	var pp := player.position
	var along := pp.orthogonal().normalized() * (1.0 if rng.randf() < 0.5 else -1.0)
	var center := pp + along * view_r * 0.26
	center = center.normalized() * pp.length()
	var count := mini(CLUMP_COUNT, MAX_PEBBLES - pebbles.size())
	if count < 10:
		_clump_timer = 20.0
		return
	_clump_r0 = view_r * 0.17
	clump_radius = _clump_r0
	clump_center = center - dust_field.frame_offset
	clump_left = CLUMP_TIME
	for k in count:
		var p := Pebble.new()
		p.pos = clump_center + Vector2.from_angle(rng.randf() * TAU) * _clump_r0 * sqrt(rng.randf())
		p.r = player.radius * rng.randf_range(FOOD_R.x, FOOD_R.y)
		p.food = true
		p.clump = true
		p.material = _pick_material(center.length())
		p.cell = GameData.MATERIAL_ORDER.find(p.material) * 4 + rng.randi() % 4
		p.angle = rng.randf() * TAU
		p.spin = rng.randf_range(-0.6, 0.6)
		pebbles.append(p)
	clump_started.emit(center)


## Мелочь сгустка стягивается к центру и кружит; «Гравитационный коллапс»
## уводит её в тебя, если ты внутри.
func _clump_pull(p: Pebble, wp: Vector2, delta: float) -> void:
	var c := clump_center + dust_field.frame_offset
	var to_c := c - wp
	var d := to_c.length()
	if Skills.stat("collapse") > 0.0 and player.position.distance_to(c) < clump_radius * 1.3:
		var to_me := player.position - wp
		p.vel = p.vel.move_toward(to_me.normalized() * player.max_speed() * 0.9, player.max_speed() * 3.0 * delta)
		return
	var want := Vector2.ZERO
	if d > 0.001:
		# Внутрь, если за краем, и по кругу: облако живое, а не стоит.
		# Каждая галька держится своей орбиты (по её вращению): облако сплошное, а не кольцо.
		var orbit := clump_radius * (0.12 + 0.8 * absf(p.spin) / 0.6)
		want = to_c / d * (d - orbit) * 0.8 + to_c.orthogonal() / d * orbit * 0.5
	p.vel = p.vel.lerp(want, 1.0 - exp(-2.0 * delta))


func _clump_end() -> void:
	var left := 0
	var mat := ""
	for p in pebbles:
		if p.clump:
			left += 1
			mat = p.material
	var c := clump_center
	var i := pebbles.size() - 1
	while i >= 0:
		if pebbles[i].clump:
			pebbles.remove_at(i)
		i -= 1
	if left < 4:
		return
	# Несобранное слипается в одно тело: из сгустка родился валун.
	var p := Pebble.new()
	p.pos = c
	p.r = player.radius * clampf(0.35 + 0.03 * left, 0.5, 1.3)
	p.material = mat
	p.cell = GameData.MATERIAL_ORDER.find(mat) * 4 + rng.randi() % 4
	p.angle = rng.randf() * TAU
	p.spin = rng.randf_range(-0.3, 0.3)
	pebbles.append(p)


## Сгусток виден как тёплое облако газа, которое сжимается.
func _draw_clump() -> void:
	if clump_left <= 0.0:
		return
	var c := clump_center + dust_field.frame_offset
	var fade := clampf(clump_left / 2.0, 0.0, 1.0) * clampf((CLUMP_TIME - clump_left) / 1.5, 0.0, 1.0)
	for k in 4:
		var r := clump_radius * (1.25 - 0.22 * k)
		_hint.draw_circle(c, r, Color(1.0, 0.82, 0.55, 0.022 * fade))
	_hint.draw_arc(c, clump_radius * 1.25, 0.0, TAU, 64, Color(1.0, 0.85, 0.6, 0.22 * fade), 1.5 / camera.zoom.x, true)
