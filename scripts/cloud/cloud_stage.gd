extends Node2D
## Этап «Облако»: путь к звезде.
##
## Коричневый карлик (или супер-Юпитер) выброшен из системы и упал в
## молекулярное облако. Газ лежит волокнами, в их узлах гуще всего. Стоишь в
## газе — он падает на тебя, мчишься — срываешь аккрецию. Узел пустеет, и
## приходится искать следующий. Соседи-зародыши гонятся за тем же газом: мелкого
## можно проглотить, крупный обдирает тебя сам. Слева горячие звёзды скопления
## гонят фронт ультрафиолета: за ним газ выжжен, и тебя выпаривает. В середине
## этапа рядом взрывается сверхновая: её ударная волна сжимает газ.
##
## На пороге (у каждого состава свой, GameData.CLOUD_TYPES) загорается водород:
## киносцена и решение — спокойная звезда или «дожать» с риском вспышек
## FU Ориона. Масса к концу облака решает, какой звездой станешь.

const CloudHud := preload("res://scripts/cloud/cloud_hud.gd")
const NEBULA_SHADER := preload("res://shaders/nebula.gdshader")
const PROTO_SHADER := preload("res://shaders/protostar.gdshader")
const SAVE_EVERY := 3.0
const N := GameData.CLOUD_N
const CELL := GameData.CLOUD_CELL
const W := GameData.CLOUD_N * GameData.CLOUD_CELL
const MARGIN := 6000.0
const RIVALS := 10
const CAPTURE := 240.0      # радиус захвата газа при 13 массах Юпитера
const IGN_FLASH := 4.0      # секунда киносцены, когда загорается водород
const IGN_CHOICE := 8.0     # когда появляется выбор
const BURST_CHARGE := 3.4   # сколько копится вспышка FU Ориона
const BURST_WINDOW := 0.9   # окно, когда её можно сбросить

var camera := Camera2D.new()
var hud: CloudHud
var joystick: VirtualJoystick
var tree_screen: SkillTreeScreen
var pause_menu: PauseMenu
var type := "chondrite"
var params: Dictionary
var neutral := false
var mj := 13.0
var mj0 := 13.0
var pos := Vector2.ZERO
var vel := Vector2.ZERO
var time := 0.0
var lit := false
var push := ""                # "calm" | "push" после зажигания
var grid := PackedFloat32Array()
var orig := PackedFloat32Array()
var rivals: Array = []        # {p, v, mj, lit, seed, axis, node, target_t}
var front_x := -2600.0
var sn := {}                  # {c, r, done}
var sn_t := 0.0               # когда взорвётся сверхновая
var rate := 0.0               # прирост ln M в секунду сейчас
var local := 0.0              # плотность газа вокруг
var ionized := 0.0
var uv_loss := false
var in_shock := 0.0
var auto_input := Vector2.ZERO
var use_auto := false
var ign_t := -1.0             # время киносцены зажигания
var burst_t := -1.0           # время копящейся вспышки FU Ориона
var burst_timer := 0.0
var burst_tap := ""           # для бота: "hit" — сбросит в окно
var dawn_t := -1.0            # рассвет: облако рассеивается, конец этапа

var _seed := 0
var _tex: ImageTexture
var _img: Image
var _tex_t := 0.0
var _nebula := ColorRect.new()
var _neb_mat := ShaderMaterial.new()
var _me := ColorRect.new()
var _me_mat := ShaderMaterial.new()
var _fx := Node2D.new()       # кольца, ударные волны, вспышки поверх облака
var _rings: Array = []        # {p, t, col, r}
var _save_t := 0.0
var _said := {}
var _ending_t := -1.0
var _rng := RandomNumberGenerator.new()
var _shake := 0.0
var _zoom_k := 1.0
var _flash := 0.0
var _axis := 0.3
var _tilt := 0.25
var _choice: Control
var _respawn_t := 20.0


func _ready() -> void:
	process_priority = 100
	_rng.randomize()
	var c: Dictionary = GameState.cloud
	type = GameState.fate_type()
	neutral = GameState.body_type() == "neutral" and not GameState.is_melted
	params = GameData.cloud_params(type, neutral)
	mj = float(c.get("mj", 13.0))
	mj0 = float(c.get("mj0", mj))
	c["mj0"] = mj0
	time = float(c.get("t", 0.0))
	lit = bool(c.get("lit", false))
	push = str(c.get("push", ""))
	front_x = float(c.get("front", -2600.0))
	_seed = int(c.get("seed", 0))
	if _seed == 0:
		_seed = _rng.randi_range(1, 1 << 30)
		c["seed"] = _seed
	_axis = float(c.get("axis", _rng.randf_range(-0.6, 0.6)))
	c["axis"] = _axis
	sn_t = float(c.get("sn_t", _rng.randf_range(0.42, 0.6) * GameData.CLOUD_TIME))
	c["sn_t"] = sn_t
	GameState.stage = GameData.CLOUD_STAGE
	_generate()
	var saved: Array = c.get("grid", [])
	if saved.size() == N * N:
		for i in N * N:
			grid[i] = float(saved[i]) / 100.0
	if float(c.get("x", -1.0)) >= 0.0:
		pos = Vector2(float(c.x), float(c.y))
	else:
		pos = _start_spot()
	if bool(c.get("sn_done", false)):
		sn = {"done": true}
	burst_timer = _rng.randf_range(14.0, 22.0)

	var bg := CanvasLayer.new()
	bg.layer = -1
	add_child(bg)
	var starfield := preload("res://scripts/world/starfield.gd").new()
	starfield.camera = camera
	bg.add_child(starfield)

	_img = Image.create(N, N, false, Image.FORMAT_RG8)
	_tex = ImageTexture.create_from_image(_img)
	_upload()
	_neb_mat.shader = NEBULA_SHADER
	_neb_mat.set_shader_parameter("dens", _tex)
	_neb_mat.set_shader_parameter("world", W)
	_neb_mat.set_shader_parameter("origin", Vector2(-MARGIN, -MARGIN))
	_neb_mat.set_shader_parameter("ostar", Vector2(-5000.0, W * 0.45))
	_nebula.material = _neb_mat
	_nebula.position = Vector2(-MARGIN, -MARGIN)
	_nebula.size = Vector2.ONE * (W + 2.0 * MARGIN)
	_nebula.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_nebula)
	_spawn_rivals(RIVALS, true)
	_me_mat.shader = PROTO_SHADER
	_me_mat.set_shader_parameter("cocoon_col", params["cocoon"])
	_me_mat.set_shader_parameter("seed", fmod(float(_seed) * 0.000137, 1.0))
	_me_mat.set_shader_parameter("axis", _axis)
	_me_mat.set_shader_parameter("tilt", _tilt)
	_me.material = _me_mat
	_me.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_me)
	_fx.draw.connect(_draw_fx)
	add_child(_fx)

	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 5.0
	camera.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(camera)
	camera.position = pos
	camera.reset_smoothing()

	var ui := CanvasLayer.new()
	ui.name = "UI"
	ui.layer = 10
	add_child(ui)
	joystick = VirtualJoystick.new()
	ui.add_child(joystick)
	hud = CloudHud.new()
	hud.stage = self
	ui.add_child(hud)
	tree_screen = SkillTreeScreen.new()
	ui.add_child(tree_screen)
	pause_menu = PauseMenu.new()
	ui.add_child(pause_menu)
	hud.tree_requested.connect(func() -> void:
		joystick.reset()
		tree_screen.open())
	hud.menu_requested.connect(_open_pause)
	hud.burst_pressed.connect(tap_burst)
	_update_view(0.0)
	if not bool(c.get("story", false)):
		_show_story()
	elif lit and push == "":
		ign_t = IGN_CHOICE  # закрыли игру на выборе: показываем его снова
	else:
		hud.caption("Облако" if not lit else "Молодая звезда", str(params["goal"]), 4.0)


func _open_pause() -> void:
	if tree_screen.visible or _choice != null:
		return
	joystick.reset()
	pause_menu.open()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and tree_screen != null and not tree_screen.visible:
		if pause_menu.visible:
			pause_menu.close()
		else:
			_open_pause()


# --- Газ облака ---

func _generate() -> void:
	grid.resize(N * N)
	orig.resize(N * N)
	var a := FastNoiseLite.new()
	a.seed = _seed
	a.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	a.frequency = 0.035
	a.fractal_octaves = 3
	var b := FastNoiseLite.new()
	b.seed = _seed + 1
	b.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	b.frequency = 0.08
	b.fractal_octaves = 2
	var e := FastNoiseLite.new()
	e.seed = _seed + 2
	e.frequency = 0.025
	for j in N:
		for i in N:
			var x := float(i)
			var y := float(j)
			var r1 := pow(1.0 - absf(a.get_noise_2d(x, y)), 7.0)
			var r2 := pow(1.0 - absf(b.get_noise_2d(x, y)), 9.0)
			var c := Vector2(x / N - 0.55, y / N - 0.5)
			var env := clampf(1.3 - c.length() * 2.0 + e.get_noise_2d(x, y) * 0.6, 0.0, 1.0)
			var edge := clampf(minf(minf(x, N - 1.0 - x), minf(y, N - 1.0 - y)) / 6.0, 0.0, 1.0)
			var d := (r1 * 1.25 + r2 * 0.55 + r1 * r2 * 2.2 + 0.04) * env * edge
			grid[j * N + i] = clampf(d, 0.0, 2.0)
			orig[j * N + i] = grid[j * N + i]


## Плотность газа в мировой точке, билинейно.
func density(p: Vector2) -> float:
	var x := p.x / CELL - 0.5
	var y := p.y / CELL - 0.5
	var i := floori(x)
	var j := floori(y)
	var fx := x - i
	var fy := y - j
	return lerpf(lerpf(_cell(i, j), _cell(i + 1, j), fx), lerpf(_cell(i, j + 1), _cell(i + 1, j + 1), fx), fy)


func _cell(i: int, j: int) -> float:
	if i < 0 or j < 0 or i >= N or j >= N:
		return 0.0
	return grid[j * N + i]


## Кривая фронта ультрафиолета по высоте (та же в nebula.gdshader).
func front_at(y: float) -> float:
	return front_x + 600.0 * sin(y * 0.00031 + 1.3) + 350.0 * sin(y * 0.00093 + 0.4) + 160.0 * sin(y * 0.0027 + 2.1)


func ion_at(p: Vector2) -> float:
	return smoothstep(-150.0, 450.0, front_at(p.y) - p.x)


## Выпить газ из клеток вокруг точки: amount — доля за секунду в центре.
func _eat(p: Vector2, radius: float, amount: float) -> void:
	var r := int(ceil(radius / CELL))
	var ci := int(p.x / CELL)
	var cj := int(p.y / CELL)
	for j in range(maxi(cj - r, 0), mini(cj + r + 1, N)):
		for i in range(maxi(ci - r, 0), mini(ci + r + 1, N)):
			var d := Vector2((i + 0.5) * CELL, (j + 0.5) * CELL).distance_to(p)
			if d > radius:
				continue
			var w := 1.0 - d / radius
			var k := j * N + i
			grid[k] = maxf(grid[k] * (1.0 - amount * w), 0.0)


func _upload() -> void:
	var bytes := PackedByteArray()
	bytes.resize(N * N * 2)
	for k in N * N:
		bytes[k * 2] = mini(int(grid[k] * 127.5), 255)
		bytes[k * 2 + 1] = mini(int(orig[k] * 127.5), 255)
	_img.set_data(N, N, false, Image.FORMAT_RG8, bytes)
	_tex.update(_img)


func _start_spot() -> Vector2:
	var best := Vector2(W * 0.7, W * 0.5)
	var best_v := -1.0
	for n in 60:
		var p := Vector2(_rng.randf_range(0.55, 0.85) * W, _rng.randf_range(0.25, 0.75) * W)
		var d := density(p)
		# Не в самом узле: его ещё надо найти.
		var v := d if d < 0.5 else 1.0 - d
		if v > best_v:
			best_v = v
			best = p
	return best


# --- Соседи-зародыши ---

func _spawn_rivals(count: int, initial: bool) -> void:
	var chondrite := type == "chondrite"
	for n in count:
		var p := Vector2.ZERO
		for tries in 30:
			p = Vector2(_rng.randf_range(0.1, 0.95) * W, _rng.randf_range(0.08, 0.92) * W)
			if p.distance_to(pos) > 2600.0 and density(p) > 0.25 and p.x > front_at(p.y) + 800.0:
				break
		# Новые соседи: чаще мелкие (добыча), иногда крупнее тебя (угроза).
		var m := exp(_rng.randf_range(log(4.0), log(70.0))) if initial else mj * (_rng.randf_range(0.08, 0.45) if _rng.randf() < 0.7 else _rng.randf_range(1.3, 2.2))
		if chondrite and _rng.randf() < 0.5:
			m *= 0.6  # хондриту чаще попадаются мелкие соседи
		var node := ColorRect.new()
		var mat := ShaderMaterial.new()
		mat.shader = PROTO_SHADER
		mat.set_shader_parameter("detail", 0.0)
		mat.set_shader_parameter("seed", _rng.randf())
		mat.set_shader_parameter("axis", _rng.randf_range(-PI, PI))
		mat.set_shader_parameter("tilt", _rng.randf_range(0.1, 0.6))
		mat.set_shader_parameter("cocoon_col", Color(0.62, 0.55, 0.5))
		node.material = mat
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(node)
		if _me.get_parent() == self:
			move_child(node, _me.get_index())
		rivals.append({"p": p, "v": Vector2.ZERO, "mj": m, "lit": false, "node": node, "mat": mat,
			"goal": p, "target_t": 0.0, "touch": 0.0})


func body_r(m: float) -> float:
	return 70.0 * pow(maxf(m, 1.0) / 13.0, 0.22)


func _step_rivals(delta: float) -> void:
	var keep := []
	for r in rivals:
		var p: Vector2 = r.p
		var m: float = r.mj
		r.target_t -= delta
		if r.target_t <= 0.0:
			r.target_t = _rng.randf_range(0.8, 1.6)
			var best: Vector2 = p
			var best_v := density(p)
			for k in 10:
				var c := p + Vector2.from_angle(TAU * k / 10.0 + _rng.randf()) * _rng.randf_range(400.0, 1100.0)
				var v := density(c) - (0.6 if c.x < front_at(c.y) + 300.0 else 0.0)
				if v > best_v:
					best_v = v
					best = c
			# Крупный сосед тянется к тебе, если ты мельче: конкурентная аккреция.
			if m > mj * 1.25 and p.distance_to(pos) < 2600.0:
				best = best.lerp(pos, 0.55)
			r.goal = best
		var dir: Vector2 = (r.goal - p)
		var sp := 200.0 * pow(13.0 / maxf(m, 13.0), 0.12)
		var want := dir.normalized() * sp * clampf(dir.length() / 300.0, 0.0, 1.0)
		r.v = (r.v as Vector2).lerp(want, minf(delta * 1.5, 1.0))
		p += r.v * delta
		var rho := density(p) * (1.0 - ion_at(p))
		var vk := 1.0 / (1.0 + pow((r.v as Vector2).length() / 420.0, 2.0))
		m *= exp(GameData.CLOUD_K * 0.7 * rho * vk * delta * (pow(GameData.SUN_JUPITERS * 6.0 / m, 0.4) if m > GameData.SUN_JUPITERS * 6.0 else 1.0))
		_eat(p, body_r(m) * 3.0, GameData.CLOUD_EAT * 0.6 * pow(m / 13.0, 0.3) * delta)
		if ion_at(p) > 0.5 and density(p) < 0.25:
			m *= 1.0 - GameData.CLOUD_UV_LOSS * delta
		if not r.lit and m >= 80.0:
			r.lit = true
		r.p = p
		r.mj = m
		# Встреча с тобой.
		var dist := p.distance_to(pos)
		var touch := (body_r(m) + body_r(mj)) * 0.9
		if dist < touch and ign_t < 0.0:
			if mj > m * 1.2:
				var keep_k := float(params["merge"]) + Skills.stat("cloud_merge")
				var gain := m * keep_k
				mj += gain
				pay(gain)
				var ch := 4 if type == "chondrite" else 2
				GameState.add_chondrules(ch, p)
				hud.toast("Поглощён зародыш звезды: +%s · хондры +%d" % [GameData.format_star_mass(gain), ch], Color(0.7, 0.95, 1.0))
				_rings.append({"p": p, "t": 0.0, "col": Color(0.7, 0.9, 1.0), "r": body_r(mj) * 4.0})
				(r.node as Node).queue_free()
				if not _said.has("eat"):
					_said["eat"] = true
					hud.caption("Слияние", "зародыш мельче тебя падает в тебя целиком: в тебе остаётся %d%% его массы" % roundi(keep_k * 100.0), 3.5)
				continue
			elif m > mj * 1.2:
				# Крупный сосед перетягивает твой газ.
				var lost := mj * 0.05 * delta
				mj -= lost
				m += lost
				r.mj = m
				vel += (pos - p).normalized() * 600.0 * delta
				r.touch = float(r.touch) + delta
				if not _said.has("rip"):
					_said["rip"] = true
					hud.caption("Сосед крупнее тебя", "он перетягивает твой газ на себя: уходи, пока не стал его частью", 3.5)
			else:
				# Равные расталкивают друг друга, почти двойная звезда.
				var away := (pos - p).normalized()
				vel += away * 900.0 * delta * 6.0
				r.v = (r.v as Vector2) - away * 300.0
				if not _said.has("pair"):
					_said["pair"] = true
					hud.toast("Равный сосед: вы закружились и разошлись", Color(1.0, 0.88, 0.6))
		keep.append(r)
	rivals = keep
	_respawn_t -= delta
	if _respawn_t <= 0.0 and rivals.size() < RIVALS and time < GameData.CLOUD_TIME - 60.0:
		_respawn_t = _rng.randf_range(18.0, 30.0) * (0.6 if type == "chondrite" else 1.0)
		_spawn_rivals(1, false)


# --- Ход этапа ---

func _process(delta: float) -> void:
	if get_tree().paused:
		return
	_neb_mat.set_shader_parameter("time", Time.get_ticks_msec() / 1000.0)
	_flash = maxf(_flash - delta * 1.5, 0.0)
	_shake = maxf(_shake - delta * 2.0, 0.0)
	if dawn_t >= 0.0:
		dawn_t += delta
		_update_view(delta)
		if dawn_t > 4.5 and _ending_t < 0.0:
			_ending_t = 0.01
		if _ending_t >= 0.0:
			_ending_t -= delta
			if _ending_t < 0.0:
				_show_ending()
		return
	if ign_t >= 0.0:
		_ignition(delta)
		_update_view(delta)
		return

	time += delta
	front_x += GameData.CLOUD_FRONT_SPEED * delta
	_erode(delta)
	_move(delta)
	_accrete(delta)
	_step_rivals(delta)
	_supernova(delta)
	_bursts(delta)
	_step_rings(delta)
	_tex_t -= delta
	if _tex_t <= 0.0:
		_tex_t = 0.25
		_upload()
	_tell()
	_update_view(delta)

	if not lit and mj >= float(params["ignite"]):
		_start_ignition()
		return
	if time >= GameData.CLOUD_TIME:
		hud.caption("Облако рассеялось", "горячие звёзды выдули остатки газа: ты больше не растёшь", 3.0)
		dawn_t = 0.0
		joystick.reset()
		save()
		return
	_save_t += delta
	if _save_t >= SAVE_EVERY:
		_save_t = 0.0
		save()


func _move(delta: float) -> void:
	var input := auto_input if use_auto else joystick.output
	if not use_auto:
		input += Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
	input = input.limit_length(1.0)
	var sp := GameData.CLOUD_SPEED * float(params["speed"]) * Skills.stat("cloud_speed") * pow(13.0 / maxf(mj, 13.0), 0.06)
	vel = vel.lerp(input * sp, minf(delta * 3.0, 1.0))
	pos += vel * delta
	pos = pos.clamp(Vector2(CELL, CELL), Vector2(W - CELL, W - CELL))


func _accrete(delta: float) -> void:
	var reach := capture_r()
	var sum := density(pos)
	for k in 6:
		sum += density(pos + Vector2.from_angle(TAU * k / 6.0) * reach * 0.6)
	local = sum / 7.0
	ionized = ion_at(pos)
	var rho := local * (1.0 - ionized * (1.0 - float(params["ion"])))
	var cold := float(params["cold"]) * smoothstep(0.55, 1.1, rho)
	var vk := 1.0 / (1.0 + pow(vel.length() / (GameData.CLOUD_SPEED * 0.55), 2.0))
	var heat := 1.0
	if not lit:
		heat = 1.0 - float(params["heat"]) * pow(clampf(mj / float(params["ignite"]), 0.0, 1.0), 2.0)
	var feedback := 1.0
	if lit and mj > GameData.SUN_JUPITERS * 6.0:
		feedback = pow(GameData.SUN_JUPITERS * 6.0 / mj, 0.45)  # свет массивной звезды сам сдувает газ
	var pk := 1.6 if push == "push" else 1.0
	var shock := 1.0 + (float(params["shock"]) - 1.0 + 0.5) * in_shock
	rate = GameData.CLOUD_K * rho * (1.0 + cold) * float(params["acc"]) * Skills.stat("cloud_acc") * vk * heat * feedback * pk * shock
	var gained := mj * (exp(rate * delta) - 1.0)
	mj += gained
	pay(gained)
	_eat(pos, reach * 1.6, GameData.CLOUD_EAT * pow(mj / 13.0, 0.3) * (0.4 + 0.6 * vk) * (1.4 if lit else 1.0) * delta)
	# Ультрафиолет выпаривает, если ты в выжженной зоне без газа вокруг.
	uv_loss = ionized > 0.5 and local < 0.25
	if uv_loss:
		var shield := maxf(1.0 - Skills.stat("cloud_shield"), 0.2)
		mj = maxf(mj * (1.0 - GameData.CLOUD_UV_LOSS * float(params["uv"]) * shield * delta), mj0 * 0.85)


func capture_r() -> float:
	return CAPTURE * float(params["reach"]) * Skills.stat("cloud_reach") * pow(mj / 13.0, 0.18)


## Фронт ультрафиолета съедает газ, плотные сгустки держатся дольше: столбы.
func _erode(delta: float) -> void:
	var i0 := maxi(int((front_x - 4500.0) / CELL), 0)
	var i1 := mini(int((front_x + 1200.0) / CELL), N - 1)
	for j in N:
		var fy := front_at((j + 0.5) * CELL)
		for i in range(i0, i1 + 1):
			var x := (i + 0.5) * CELL
			if x > fy:
				continue
			var k := j * N + i
			var g := grid[k]
			if g <= 0.0:
				continue
			grid[k] = maxf(g - delta * 0.09 / (0.2 + g * 1.6), 0.0)


func _supernova(delta: float) -> void:
	if sn.has("done"):
		in_shock = maxf(in_shock - delta * 0.5, 0.0)
		return
	if sn.is_empty():
		if time < sn_t:
			return
		var ang := _rng.randf_range(-PI * 0.8, -PI * 0.2) if _rng.randf() < 0.5 else _rng.randf_range(PI * 0.2, PI * 0.8)
		var c := Vector2(W * 0.5, W * 0.5) + Vector2.from_angle(ang) * W * 0.62
		sn = {"c": c, "r": 0.0}
		_flash = 1.0
		_vibrate(250)
		hud.caption("Сверхновая!", "рядом взорвалась звезда: её ударная волна сжимает газ вдвое. Лови волну, но в пустоте она тебя сдует", 4.5)
		return
	var c: Vector2 = sn.c
	var r0: float = sn.r
	var r1 := r0 + GameData.CLOUD_SN_SPEED * delta
	sn.r = r1
	# Клетки, через которые прошла волна, сжимаются.
	# По строкам: в каждой волна прошла по двум коротким отрезкам.
	for j in N:
		var dy := (j + 0.5) * CELL - c.y
		if absf(dy) > r1:
			continue
		var x1 := sqrt(r1 * r1 - dy * dy)
		var x0 := sqrt(maxf(r0 * r0 - dy * dy, 0.0)) if absf(dy) < r0 else 0.0
		for seg in [[c.x - x1, c.x - x0], [c.x + x0, c.x + x1]]:
			var i0 := maxi(int(floor(float(seg[0]) / CELL - 0.5)), 0)
			var i1 := mini(int(ceil(float(seg[1]) / CELL - 0.5)), N - 1)
			for i in range(i0, i1 + 1):
				var d := Vector2((i + 0.5) * CELL, (j + 0.5) * CELL).distance_to(c)
				if d > r0 and d <= r1:
					grid[j * N + i] = minf(grid[j * N + i] * 1.9, 2.0)
	var dp := pos.distance_to(c)
	if dp < r1 and dp > r1 - 2400.0:
		in_shock = minf(in_shock + delta * 2.0, 1.0)
	else:
		in_shock = maxf(in_shock - delta * 0.5, 0.0)
	if absf(dp - r1) < 220.0 and not sn.has("hit"):
		sn["hit"] = true
		var shield := clampf(local / 0.8, 0.0, 1.0)
		var kick := 1300.0 * (1.0 - 0.7 * shield) / float(params["shock"])
		vel += (pos - c).normalized() * kick
		_shake = 1.0
		_vibrate(120)
		if shield < 0.5:
			var lost := mj * 0.06 / float(params["shock"])
			mj -= lost
			hud.toast("Волна сорвала часть газа: в пустоте от неё не спрятаться", Color(1.0, 0.7, 0.55))
		else:
			hud.toast("Плотный газ вокруг принял удар волны на себя", Color(0.7, 0.95, 1.0))
	for rv in rivals:
		var d2: float = (rv.p as Vector2).distance_to(c)
		if absf(d2 - r1) < 200.0:
			rv.v = (rv.v as Vector2) + ((rv.p as Vector2) - c).normalized() * 40.0
	if r1 > W * 1.7:
		sn = {"done": true}


## Вспышки FU Ориона: только у звезды, что решила «дожать».
func _bursts(delta: float) -> void:
	if push != "push":
		return
	if burst_t < 0.0:
		burst_timer -= delta
		if burst_timer <= 0.0:
			burst_t = 0.0
			if not _said.has("burst"):
				_said["burst"] = true
				hud.caption("Вспышка FU Ориона", "газ диска копится и вот-вот рухнет на звезду: нажми «Сбросить», когда кольцо сожмётся", 3.0)
		return
	burst_t += delta
	if burst_tap == "hit" and burst_window():
		tap_burst()
		return
	if burst_t > BURST_CHARGE + _window():
		_burst_end(false)


func _window() -> float:
	return BURST_WINDOW * (1.0 + Skills.stat("cloud_burst"))


func burst_window() -> bool:
	return burst_t >= BURST_CHARGE - _window() * 0.5 and burst_t <= BURST_CHARGE + _window() * 0.5


func tap_burst() -> void:
	if burst_t < 0.0:
		return
	_burst_end(burst_window())


func _burst_end(caught: bool) -> void:
	burst_t = -1.0
	burst_timer = _rng.randf_range(28.0, 42.0)
	_flash = 0.6
	if caught:
		var gain := mj * 0.04
		mj += gain
		pay(gain * 3.0)
		_vibrate(80)
		hud.toast("Вспышка укрощена: газ диска рухнул на звезду, +%s" % GameData.format_star_mass(gain), Color(0.7, 1.0, 0.75))
		_rings.append({"p": pos, "t": 0.0, "col": Color(1.0, 0.9, 0.6), "r": body_r(mj) * 6.0})
	else:
		var lost := mj * 0.07
		mj -= lost
		_vibrate(300)
		hud.toast("Вспышка FU Ориона сдула часть диска: −%s" % GameData.format_star_mass(lost), Color(1.0, 0.6, 0.5))
		_rings.append({"p": pos, "t": 0.0, "col": Color(1.0, 0.5, 0.4), "r": body_r(mj) * 9.0})


func _step_rings(delta: float) -> void:
	var keep := []
	for r in _rings:
		r.t += delta
		if r.t < 1.6:
			keep.append(r)
	_rings = keep


# --- Зажигание ---

func _start_ignition() -> void:
	ign_t = 0.0
	joystick.reset()
	vel = Vector2.ZERO
	hud.caption("Сжатие", "ядро сжимается и греется: миллион кельвинов, два, три…", 3.0)
	save()


func _ignition(delta: float) -> void:
	var before := ign_t
	ign_t += delta
	_shake = maxf(_shake, smoothstep(0.5, IGN_FLASH, ign_t) * 0.6 if ign_t < IGN_FLASH else 0.0)
	if before < IGN_FLASH and ign_t >= IGN_FLASH:
		lit = true
		GameState.cloud["lit"] = true
		_flash = 1.0
		_shake = 1.0
		_vibrate(600)
		_rings.append({"p": pos, "t": 0.0, "col": Color(1.0, 0.95, 0.85), "r": 2400.0})
		# Первый свет сдувает кокон и газ рядом.
		_eat(pos, 1300.0, 0.35)
		_upload()
		for r in rivals:
			var d: Vector2 = (r.p as Vector2) - pos
			if d.length() < 2000.0:
				r.v = (r.v as Vector2) + d.normalized() * 260.0
		hud.caption("Водород загорелся!", "%s: ты звезда. Джеты бьют из полюсов, свет сдувает кокон" % GameData.format_star_mass(mj), 3.5)
	if ign_t >= IGN_CHOICE and _choice == null and push == "":
		_show_choice()
	if push != "" and ign_t >= IGN_CHOICE:
		ign_t += delta  # выбор сделан: быстрый отъезд камеры
		if ign_t > IGN_CHOICE + 2.0:
			ign_t = -1.0
			save()


func _show_choice() -> void:
	_choice = preload("res://scripts/cloud/ignite_choice.gd").new()
	_choice.chosen.connect(func(which: String) -> void:
		push = which
		GameState.cloud["push"] = which
		_choice = null
		if which == "push":
			burst_timer = 12.0
			hud.caption("Дожимаем", "газ падает на звезду в полтора раза быстрее, но диск будет вспыхивать: лови вспышки", 3.5)
		else:
			hud.caption("Спокойная звезда", "ровный свет: звёздной пыли на четверть больше до конца облака", 3.5)
		save())
	$UI.add_child(_choice)
	if use_auto:
		get_tree().create_timer(1.0).timeout.connect(func() -> void:
			if _choice != null:
				_choice.pick(str(GameState.cloud.get("bot_push", "calm"))))


func pay(gained: float) -> void:
	if gained <= 0.0:
		return
	var k := (1.25 if push == "calm" else 1.0) * Skills.stat("value") * Skills.stat("value_mul") * GameState.value_bonus()
	GameState.add_currency(gained * GameData.CLOUD_VALUE * k)


# --- Подсказки ---

func _tell() -> void:
	if time > 6.0 and not _said.has("move"):
		_said["move"] = true
		hud.caption("Ищи узлы", "газ лежит волокнами, а где они сходятся, гуще всего. Стой в газе: на полном ходу он не успевает падать на тебя", 4.5)
	if time > 22.0 and local < 0.2 and not _said.has("empty") and not uv_loss:
		_said["empty"] = true
		hud.caption("Здесь пусто", "стрелка у края экрана показывает ближайший узел газа", 3.0)
	if uv_loss and not _said.has("uv"):
		_said["uv"] = true
		hud.caption("Ультрафиолет", "горячие звёзды выжгли здесь газ, и тебя выпаривает. Уходи вправо, в тёмное облако", 3.5)
	if time > 60.0 and front_at(pos.y) > pos.x - 1500.0 and not _said.has("front") and not uv_loss:
		_said["front"] = true
		hud.caption("Фронт близко", "ионизованный газ светится красным: там уже нечего есть", 3.0)
	if lit and not _said.has("grow") and ign_t < 0.0 and push != "":
		_said["grow"] = true
		hud.caption("Расти дальше", "чем больше масса к концу облака, тем ярче звезда: %s — с %s" % [GameData.ENDINGS["star_sun"]["name"],
			GameData.format_star_mass(0.45 * GameData.SUN_JUPITERS)], 4.0)
	if left() < 40.0 and not _said.has("last"):
		_said["last"] = true
		hud.caption("Облако рассеивается", "сорок секунд: какой массой встретишь рассвет, такой звездой и станешь", 3.0)


func left() -> float:
	return maxf(GameData.CLOUD_TIME - time, 0.0)


## Ближайший к тебе густой узел (для стрелки), если ты сам в пустоте.
func hub_target() -> Vector2:
	var best := Vector2(-1.0, -1.0)
	var best_v := 0.0
	var ci := int(pos.x / CELL)
	var cj := int(pos.y / CELL)
	for j in range(maxi(cj - 24, 0), mini(cj + 25, N), 2):
		for i in range(maxi(ci - 24, 0), mini(ci + 25, N), 2):
			var p := Vector2((i + 0.5) * CELL, (j + 0.5) * CELL)
			if p.x < front_at(p.y) + 500.0:
				continue
			var v := grid[j * N + i] - p.distance_to(pos) / 9000.0
			if v > best_v:
				best_v = v
				best = p
	return best


func _vibrate(ms: int) -> void:
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)


# --- Вид ---

func _update_view(delta: float) -> void:
	var vp := get_viewport_rect().size
	var base := vp.x / 2600.0 * pow(13.0 / maxf(mj, 13.0), 0.06)
	var want := 1.0
	if ign_t >= 0.0:
		want = 1.0 + 1.8 * smoothstep(0.0, 3.5, minf(ign_t, IGN_CHOICE)) * (1.0 - smoothstep(IGN_CHOICE, IGN_CHOICE + 2.0, ign_t))
	if dawn_t >= 0.0:
		want = 1.0 + 1.4 * smoothstep(0.0, 4.0, dawn_t)
	_zoom_k = lerpf(_zoom_k, want, minf(delta * 2.0, 1.0)) if delta > 0.0 else want
	var z := base * _zoom_k
	camera.zoom = Vector2(z, z)
	var shake := Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * 30.0 * _shake / z * 0.3
	camera.position = pos + shake
	var r := body_r(mj)
	var q := r * 8.0 * (1.0 + 0.6 * float(lit))
	_me.size = Vector2(q, q)
	_me.position = pos - _me.size * 0.5
	var ig := 1.0 if lit else 0.0
	if ign_t >= 0.0 and ign_t < IGN_FLASH:
		ig = 0.0
	var heat := clampf(mj / float(params["ignite"]), 0.5, 1.0)
	if ign_t >= 0.0 and not lit:
		heat = 1.0 + ign_t * 0.3
	var star: Color = GameData.star_color(mj) * (params["tint"] as Color)
	_me_mat.set_shader_parameter("heat", heat)
	_me_mat.set_shader_parameter("lit", ig)
	_me_mat.set_shader_parameter("star_col", star)
	var t := Time.get_ticks_msec() / 1000.0
	_me_mat.set_shader_parameter("time", t)
	_me_mat.set_shader_parameter("jets", clampf((mj - 25.0) / 40.0, 0.0, 1.0) * (1.0 - 0.5 * ig) + (0.8 if ign_t >= IGN_FLASH else 0.0))
	_me_mat.set_shader_parameter("cocoon", clampf(1.0 - 0.6 * ig, 0.2, 1.0))
	_me_mat.set_shader_parameter("disk", 1.0)
	var fl := 0.0
	if burst_t >= 0.0:
		fl = smoothstep(0.0, BURST_CHARGE, burst_t) * 0.8
	_me_mat.set_shader_parameter("flare", fl + _flash * 0.5)
	for rv in rivals:
		var rr := body_r(rv.mj) * 8.0
		var n: ColorRect = rv.node
		n.size = Vector2(rr, rr)
		n.position = (rv.p as Vector2) - n.size * 0.5
		var m: ShaderMaterial = rv.mat
		m.set_shader_parameter("time", t)
		m.set_shader_parameter("lit", 1.0 if rv.lit else 0.0)
		m.set_shader_parameter("heat", clampf(float(rv.mj) / 80.0, 0.2, 1.0))
		m.set_shader_parameter("star_col", GameData.star_color(rv.mj))
		m.set_shader_parameter("jets", clampf((float(rv.mj) - 25.0) / 40.0, 0.0, 0.8))
	_neb_mat.set_shader_parameter("front_x", front_x)
	_neb_mat.set_shader_parameter("me", pos)
	_neb_mat.set_shader_parameter("me_glow", (0.25 + 0.5 * heat) if not lit else minf(0.9 + 0.15 * log(maxf(mj / 80.0, 1.0)), 1.4))
	_neb_mat.set_shader_parameter("me_col", star if lit else Color(1.0, 0.5, 0.3))
	_neb_mat.set_shader_parameter("sn_flash", _flash)
	if sn.has("c"):
		_neb_mat.set_shader_parameter("sn_c", sn.c)
		_neb_mat.set_shader_parameter("sn_r", sn.r)
	else:
		_neb_mat.set_shader_parameter("sn_r", -1.0)
	_neb_mat.set_shader_parameter("fade", 1.0 - 0.85 * smoothstep(0.0, 4.0, dawn_t) if dawn_t >= 0.0 else 1.0)
	_fx.queue_redraw()


func _draw_fx() -> void:
	# Кольца слияний, вспышек и первого света.
	for r in _rings:
		var k: float = r.t / 1.6
		var col: Color = r.col
		var rr: float = float(r.r) * (0.2 + 0.8 * sqrt(k))
		# Мягкая полоса: несколько тонких колец, яркий фронт и тающий след за ним.
		for i in 6:
			var f := float(i) / 6.0
			_fx.draw_arc(r.p, rr * (1.0 - 0.06 * f * (0.3 + k)), 0.0, TAU, 96, Color(col, 0.3 * (1.0 - k) * (1.0 - f) * (1.0 - f)), 3.0 + 8.0 * k, true)
	# Вспышка FU Ориона копится: кольцо сжимается к звезде, в окне — золотое.
	if burst_t >= 0.0:
		var k := clampf(burst_t / BURST_CHARGE, 0.0, 1.2)
		var rr := body_r(mj) * lerpf(7.0, 1.6, minf(k, 1.0))
		var col := UiTheme.GOLD if burst_window() else Color(1.0, 0.55, 0.4)
		_fx.draw_arc(pos, rr, 0.0, TAU, 72, Color(col, 0.75), 6.0, true)
		_fx.draw_arc(pos, body_r(mj) * 1.6, 0.0, TAU, 72, Color(UiTheme.GOLD, 0.35), 3.0, true)
	# Радиус захвата: еле видный круг, где газ падает на тебя.
	if ign_t < 0.0 and dawn_t < 0.0:
		_fx.draw_arc(pos, capture_r(), 0.0, TAU, 64, Color(1.0, 0.85, 0.6, 0.08 + 0.12 * clampf(rate / 0.03, 0.0, 1.0)), 3.0, true)
	# Соседи крупнее тебя — красная кайма, мельче — голубая.
	for rv in rivals:
		var m: float = rv.mj
		var p: Vector2 = rv.p
		if p.distance_to(pos) > 3200.0:
			continue
		var col := Color(1.0, 0.4, 0.3, 0.5) if m > mj * 1.2 else (Color(0.5, 0.85, 1.0, 0.5) if mj > m * 1.2 else Color(1.0, 0.85, 0.5, 0.4))
		_fx.draw_arc(p, body_r(m) * 1.5, 0.0, TAU, 40, col, 3.0, true)


# --- Сохранение и конец ---

func save() -> void:
	var c := GameState.cloud
	c["mj"] = mj
	c["t"] = time
	c["x"] = pos.x
	c["y"] = pos.y
	c["lit"] = lit
	c["push"] = push
	c["front"] = front_x
	c["sn_done"] = sn.has("done") or sn.has("c")
	var arr := []
	arr.resize(N * N)
	for i in N * N:
		arr[i] = roundi(grid[i] * 100.0)
	c["grid"] = arr
	GameState.save_game()


func _show_story() -> void:
	var story := preload("res://scripts/cloud/cloud_story.gd").new()
	story.from = str(GameState.cloud.get("from", "brown_dwarf"))
	story.ignite = float(params["ignite"])
	story.goal = str(params["goal"])
	story.closed.connect(func() -> void:
		GameState.cloud["story"] = true
		get_tree().paused = false
		hud.caption("Облако", str(params["goal"]), 5.0)
		save())
	get_tree().paused = true
	$UI.add_child(story)
	if use_auto:
		story.call_deferred("close")


func _show_ending() -> void:
	var kind := GameData.star_class(mj, lit)
	var pts := GameState.finish(kind)
	joystick.visible = false
	hud.visible = false
	get_tree().paused = true
	$UI.add_child(EndingScreen.new(kind, pts))
