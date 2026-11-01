extends Node2D
## Гигант на этапе газа: сам шар (giant_planet.gdshader), свой диск вокруг
## (giant_cpd.gdshader), потоки газа из щели и луны.
##
## Потоки считаются честно, в задаче Хилла: во вращающейся вместе с гигантом
## системе газ течёт мимо по сдвигу, гравитация гиганта разворачивает его в
## подковы, а ближние струи закручивает и роняет в свой диск.
## Единица длины потоков — видимый радиус Хилла (hill), время — оборот газа.

const GIANT_SHADER := preload("res://shaders/giant_planet.gdshader")
const CPD_SHADER := preload("res://shaders/giant_cpd.gdshader")
const MOON_NAMES := ["Ио", "Европа", "Ганимед", "Каллисто", "Амальтея", "Фемисто"]

var body_r := 200.0
var hill := 440.0
var reach := 1.0
var inflate := 1.0           # раздувание оболочки на входе в этап
var flow := 0.5              # сколько газа падает сейчас, 0..1
var field := 0.3
var moons := 0
var impact_heat := 0.0       # жар оболочки после гигантского удара, 0..1
var heat_hold := 1.0         # во сколько раз дольше держится жар (расплав)
var soot := 0.0              # сажа углеродного тела в облаках, 0..1
var zoom := 0.3
var sigma_at: Callable       # плотность газа по смещению от орбиты в радиусах Хилла

var _planet := ColorRect.new()
var _cpd := ColorRect.new()
var _map_vp := SubViewport.new()   # карта облаков: печётся раз в BAKE_EVERY
var _map_mat := ShaderMaterial.new()
var _bake_t := 0.0
const BAKE_EVERY := 0.4
const SPIN := 0.12
const MOON_W := 0.22          # угловая скорость ближней луны у поверхности, рад/с
const FALL_TIME := 7.0
var gas := GasParticles.new()   # газ частицами: струи и сгустки
var _planet_mat := ShaderMaterial.new()
var _cpd_mat := ShaderMaterial.new()
var _birth := {}                      # луна -> {t, from}: рождение или захват на глазах
var _falling: Array = []              # луны, что падают в гиганта
var _impacts: Array = []
var _stolen: Array = []               # луны, которые увёл тяжёлый сосед
var _scars: Array = []                # тёмные следы ударов в облаках, как у Юпитера в 1994-м
var _flash_nodes: Array = []
var _flash_tex := GiantWorld._make_flash_tex()
var _views: Array = []                # MoonView на каждую видимую луну
var _used := 0
var _time := 0.0
var _cpd_flash := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_cpd_mat.shader = CPD_SHADER
	_cpd_mat.set_shader_parameter("noise_tex", NoiseTex.get_tex())
	_cpd.material = _cpd_mat
	_cpd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cpd)
	gas.material = CanvasItemMaterial.new()  # газ светит отражённым светом: обычное смешение
	gas.particle_eaten.connect(func(_id: int) -> void: _cpd_flash = minf(_cpd_flash + 0.02, 1.0))
	add_child(gas)
	_planet_mat.shader = GIANT_SHADER
	_planet_mat.set_shader_parameter("light_dir", Vector2(-1.0, -0.12))
	var sd := _rng.randf()
	_planet_mat.set_shader_parameter("seed", sd)
	# Облака дорогие: считаем их в карту 512×256 пару раз в секунду, а шар
	# каждый кадр только читает карту и крутит её.
	_map_vp.size = Vector2i(512, 256)
	_map_vp.disable_3d = true
	_map_vp.transparent_bg = false
	_map_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var mr := ColorRect.new()
	mr.size = Vector2(512, 256)
	_map_mat.shader = preload("res://shaders/giant_map.gdshader")
	_map_mat.set_shader_parameter("seed", sd)
	mr.material = _map_mat
	_map_vp.add_child(mr)
	add_child(_map_vp)
	_planet_mat.set_shader_parameter("use_map", true)
	_planet_mat.set_shader_parameter("map", _map_vp.get_texture())
	_planet.material = _planet_mat
	_planet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_planet)
	var moons_layer := Node2D.new()
	moons_layer.draw.connect(_draw_moons.bind(moons_layer))
	moons_layer.set_meta("moons", true)
	add_child(moons_layer)


## Цвета полос по ядру; у самой звезды (hot до 1) облака раскаляются.
func set_look(flavor: String, hot := 0.0) -> void:
	var look: Array = (GameData.GIANT_LOOK.get(flavor, GameData.GIANT_LOOK["giant_cold"]) as Array).duplicate()
	var burn: Array = GameData.GIANT_LOOK["giant_hot"]
	# Удар раскаляет оболочку, как у звезды под боком; сажа темнит облака.
	hot = maxf(hot, impact_heat)
	if soot > 0.0:
		var ash := Color(0.13, 0.11, 0.1)
		for i in look.size():
			look[i] = (look[i] as Color).lerp(ash, soot * (0.9 if i == 0 else 0.8))
	_planet_mat.set_shader_parameter("zone_col", _muted((look[0] as Color).lerp(burn[0], hot * 0.6), 0.35))
	_map_mat.set_shader_parameter("zone_col", _muted((look[0] as Color).lerp(burn[0], hot * 0.6), 0.35))
	_planet_mat.set_shader_parameter("belt_col", _muted((look[1] as Color).lerp(burn[1], hot * 0.6), 0.3))
	_map_mat.set_shader_parameter("belt_col", _muted((look[1] as Color).lerp(burn[1], hot * 0.6), 0.3))
	_planet_mat.set_shader_parameter("storm_col", _muted((look[2] as Color).lerp(burn[2], hot * 0.6), 0.2))
	_map_mat.set_shader_parameter("storm_col", _muted((look[2] as Color).lerp(burn[2], hot * 0.6), 0.2))
	_planet_mat.set_shader_parameter("heat", hot)


## Природные облака не бывают кричащими: цвет наполовину к своей яркости.
static func _muted(c: Color, k: float) -> Color:
	var l := c.r * 0.3 + c.g * 0.55 + c.b * 0.15
	return c.lerp(Color(l, l, l), k)


## Струя газа упала в свой диск: он вспыхивает.
func flash() -> void:
	_cpd_flash = minf(_cpd_flash + 0.08, 1.0)


func _process(delta: float) -> void:
	_time += delta
	_cpd_flash = maxf(_cpd_flash - delta * 0.8, 0.0)
	impact_heat = maxf(impact_heat - delta * 0.035 / heat_hold, 0.0)
	if impact_heat <= 0.0:
		heat_hold = 1.0
	soot = maxf(soot - delta * 0.012, 0.0)
	var r := body_r * inflate
	var q := r * 2.0 / 0.72  # тело — BODY (0.36) ширины квада
	_planet.size = Vector2(q, q)
	_planet.position = -_planet.size * 0.5
	_planet_mat.set_shader_parameter("aurora", field)
	_planet_mat.set_shader_parameter("churn", clampf(flow + _cpd_flash * 0.5, 0.0, 1.0))
	_planet_mat.set_shader_parameter("spin", _time * SPIN)  # оборот меньше чем за минуту: вращение видно
	_update_scars(delta)
	_bake_t -= delta
	if _bake_t <= 0.0:
		_bake_t = BAKE_EVERY
		# Пояса со своими скоростями: соседние полосы скользят друг по другу.
		_map_mat.set_shader_parameter("spin_jet", _time * SPIN)
		_map_mat.set_shader_parameter("churn", clampf(flow + _cpd_flash * 0.5, 0.0, 1.0))
		_map_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var cr := hill * 0.95
	_cpd.size = Vector2(cr, cr) * 2.0
	_cpd.position = -_cpd.size * 0.5
	# Полость поля: от поверхности гиганта и шире с полем.
	_cpd_mat.set_shader_parameter("inner", clampf(r / cr * (1.05 + 0.6 * field), 0.2, 0.75))
	_cpd_mat.set_shader_parameter("glow", clampf(0.25 + flow * 0.6 + _cpd_flash, 0.0, 1.4))
	_cpd_mat.set_shader_parameter("field", field)
	for i in _birth.keys():
		_birth[i].t = float(_birth[i].t) + delta / 4.0
		if float(_birth[i].t) >= 1.0:
			_birth.erase(i)
	var keep := []
	for f in _falling:
		f.t = float(f.t) + delta / FALL_TIME
		if f.t >= 1.0:
			var an := _fall_angle(f, r, 1.0)
			var at := Vector2(cos(an), sin(an)) * r * 0.95
			_impacts.append({"t": 0.0, "p": at})
			scar(at.normalized(), r * 0.07)
			flash()
		else:
			keep.append(f)
	_falling = keep
	var ik := []
	for j in range(_used, _views.size()):
		(_views[j] as MoonView).visible = false
	for im in _impacts:
		im.t = float(im.t) + delta / 1.4
		if im.t < 1.0:
			ik.append(im)
	_impacts = ik
	var sk := []
	for st in _stolen:
		st.t = float(st.t) + delta / 3.0
		if st.t < 1.0:
			sk.append(st)
	_stolen = sk
	gas.hill = hill
	gas.reach = reach
	gas.flow = flow
	gas.sigma_at = sigma_at
	gas.step(delta)
	for c in get_children():
		if c.has_meta("moons"):
			c.queue_redraw()


## Новая луна собирается на глазах: из пыли своего диска или из захваченного тела.
func birth(i: int, from := Vector2.INF) -> void:
	_birth[i] = {"t": 0.0, "from": from}


## Лишняя луна падает в гиганта по спирали.
func fall() -> void:
	var r := body_r * inflate
	_falling.append({"t": 0.0, "a": r * (1.55 + 0.55 * moons), "ang": _rng.randf() * TAU})


func _moon_ball(ci: Node2D, p: Vector2, mr: float, i: int, shadow: float, heat := 0.0, form := 1.0) -> void:
	if _used >= _views.size():
		var v := MoonView.new()
		ci.add_child(v)
		_views.append(v)
	var view: MoonView = _views[_used]
	_used += 1
	var style := MoonView.style_for_giant(str(GameState.giant.get("flavor", "giant_cold")), i)
	view.put(p, mr, style, Vector2(-1.0, -0.12), float(i) * 1.37, _time * 0.04 + i, shadow, heat, form)


func _moon_orbit(i: int, r: float) -> Vector2:
	var a := r * (1.55 + 0.55 * i)
	var ang := _time * MOON_W * pow(a / r, -1.5) + i * 2.1
	return Vector2(cos(ang), sin(ang)) * a


func _fall_angle(f: Dictionary, r: float, e: float) -> float:
	var a2: float = lerpf(float(f.a), r * 0.98, e)
	return float(f.ang) + _time * MOON_W * pow(a2 / r, -1.5) + e * 1.6


func _draw_moons(ci: Node2D) -> void:
	var r := body_r * inflate
	var px := 1.0 / maxf(zoom, 0.01)
	_used = 0
	for i in moons:
		var a := r * (1.55 + 0.55 * i)
		var p := _moon_orbit(i, r)
		var ang := p.angle()
		var mr := maxf(r * (0.06 + 0.02 * (i % 3)), 2.0 * px)
		var grow := 1.0
		var form := 1.0
		var ring := 0.035
		if _birth.has(i):
			var b: Dictionary = _birth[i]
			var e := smoothstep(0.0, 1.0, float(b.t))
			var from: Vector2 = b.from
			ring *= e
			if from.x == INF:
				# Пыль своего диска стягивается в комок: дуга пыли по орбите
				# сжимается, а рыхлый шар уплотняется (шейдер луны, form).
				var spread := (1.0 - e) * 2.2
				ci.draw_arc(Vector2.ZERO, a, ang - spread, ang, 48, Color(0.8, 0.76, 0.68, 0.1 * (1.0 - e)), mr * (1.6 - e), true)
				grow = smoothstep(0.15, 1.0, e)
				form = smoothstep(0.3, 1.0, e)
			else:
				# Захваченное тело подходит по дуге и садится на орбиту.
				var bend := (p - from).orthogonal().normalized() * sin(e * PI) * from.distance_to(p) * 0.25
				p = from.lerp(p, e) + bend
		ci.draw_arc(Vector2.ZERO, a, 0.0, TAU, 128, Color(0.75, 0.82, 0.95, ring), px, true)
		if grow <= 0.01:
			continue
		# Тень гиганта: луна за ним гаснет.
		var shadow := 1.0
		if p.x > 0.0 and absf(p.y) < r:
			shadow = 0.18 + 0.82 * smoothstep(r * 0.8, r, absf(p.y))
		_moon_ball(ci, p, maxf(mr * grow, 2.0 * px) * 1.3, i, shadow, 0.0, form)
	# Падающие луны: медленная спираль вниз, накал у самых облаков.
	for f in _falling:
		var e := smoothstep(0.0, 1.0, float(f.t))
		var a2: float = lerpf(float(f.a), r * 0.98, e)
		var an := _fall_angle(f, r, e)
		var p2 := Vector2(cos(an), sin(an)) * a2
		_moon_ball(ci, p2, r * 0.07 * (1.0 - 0.3 * e) * 1.3, moons + 1, 1.0, smoothstep(0.55, 1.0, e))
	# Уведённые луны: уходят к тому, кто их сорвал.
	for st in _stolen:
		var e := smoothstep(0.0, 1.0, float(st.t))
		var from: Vector2 = st.from
		var to: Vector2 = st.to
		var q := from.lerp(to, e) + (to - from).orthogonal().normalized() * sin(e * PI) * from.distance_to(to) * 0.2
		_moon_ball(ci, q, r * 0.08, int(st.i), 1.0, 0.0, 1.0)
	_draw_flashes(ci, r)


## Тяжёлый сосед увёл крайнюю луну.
func steal(to: Vector2) -> void:
	var r := body_r * inflate
	_stolen.append({"t": 0.0, "from": _moon_orbit(moons, r), "to": to, "i": moons})


## Тёмный след удара в облаках: на карте облаков, крутится вместе с шаром
## и расплывается за минуту. dir — точка удара на диске (локально, длина 1).
func scar(dir: Vector2, size: float) -> void:
	var r := body_r * inflate
	var tl := 0.12
	var nv := Vector3(dir.x * 0.9, dir.y * 0.9, sqrt(1.0 - 0.81))
	var d := Vector3(nv.x, cos(tl) * nv.y + sin(tl) * nv.z, -sin(tl) * nv.y + cos(tl) * nv.z)
	var lon := atan2(d.x, d.z) + _time * SPIN
	var lat := asin(clampf(d.y, -1.0, 1.0))
	_scars.append({"lon": lon, "lat": lat, "size": clampf(size / r, 0.04, 0.2), "t": 0.0})
	if _scars.size() > 6:
		_scars.pop_front()


func _update_scars(delta: float) -> void:
	var arr: Array[Vector4] = []
	var keep := []
	for sc in _scars:
		sc.t = float(sc.t) + delta / 70.0
		if float(sc.t) < 1.0:
			keep.append(sc)
	_scars = keep
	for i in 6:
		if i < _scars.size():
			var sc: Dictionary = _scars[i]
			var k := float(sc.t)
			arr.append(Vector4(float(sc.lon), float(sc.lat), float(sc.size) * (1.0 + 1.5 * k), (1.0 - k) * minf(k * 20.0, 1.0)))
		else:
			arr.append(Vector4(0.0, 0.0, 0.0, 0.0))
	_planet_mat.set_shader_parameter("scars", arr)


## Вспышки ударов в облаках: мягкий спрайт, складывается со светом.
func _draw_flashes(ci: Node2D, r: float) -> void:
	var used := 0
	for im in _impacts:
		if used >= _flash_nodes.size():
			var sp := Sprite2D.new()
			sp.texture = _flash_tex
			var mat := CanvasItemMaterial.new()
			mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			sp.material = mat
			ci.add_child(sp)
			_flash_nodes.append(sp)
		var spr: Sprite2D = _flash_nodes[used]
		used += 1
		var t := float(im.t)
		spr.visible = true
		spr.position = im.p
		spr.scale = Vector2.ONE * r * 0.3 * (0.5 + 1.5 * sqrt(t)) * 2.0 / 128.0
		spr.modulate = Color(1.0, 0.8, 0.6, (1.0 - t) * (1.0 - t))
	for i in range(used, _flash_nodes.size()):
		(_flash_nodes[i] as Sprite2D).visible = false


static func moon_name(i: int) -> String:
	return MOON_NAMES[i % MOON_NAMES.size()]
