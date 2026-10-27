extends Node2D
## Сборка сцены: фон, звезда, пыль, игрок, камера и интерфейс.

const SCREEN_RADIUS_AT_START := 10.0  # радиус пылинки на экране в начале, px
const ZOOM_GROWTH_EXP := 0.75         # <1: камера отдаляется медленнее, чем растёт тело
const INTRO_ZOOM := 0.55              # на входе камера дальше и плавно приближается
const BOULDER_ZOOM := 0.99            # валун: камера дальше — гальки вокруг стали мелочью
const PEBBLE_ZOOM := 1.65             # на этапе «Галька» камера чуть ближе: тело крупнее и заметнее

var player: Player
var dust_field: DustField
var camera: Camera2D
var hud: Hud
var joystick: VirtualJoystick
var tree_screen: SkillTreeScreen
var _hidden_world: Array[Node] = []
var pause_menu: PauseMenu
var pebble_field: PebbleField
var fx: AbsorbFx
var sky_events: Node2D
var _intro_time := 0.0
var _zoom_ease := 0.0  # с какого момента камера снова плавно приближается
var _caption: Control
var guide: Tutorial  # Звездочёт сейчас что-то рассказывает
var _chip_time := -10.0
var _chunk_time := -10.0
var _boulder_time := 0.0  # когда стал валуном (для подсказки о веществе)
var _chunk_pos := Vector2.ZERO
var _geode_time := -10.0
var _geode_pos := Vector2.ZERO
var _chondrule_time := -10.0
var _chondrule_pos := Vector2.ZERO
var _swarm_pos := Vector2.ZERO


func _ready() -> void:
	# Камера двигается после игрока в том же кадре, иначе отстаёт на кадр и дёргается.
	process_priority = 100
	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	# Звездочёт ведёт камеру, пока время остановлено.
	camera.process_mode = Node.PROCESS_MODE_ALWAYS

	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -1
	add_child(bg_layer)
	var starfield := preload("res://scripts/world/starfield.gd").new()
	starfield.camera = camera
	bg_layer.add_child(starfield)
	sky_events = preload("res://scripts/world/sky_events.gd").new()
	sky_events.camera = camera
	bg_layer.add_child(sky_events)

	add_child(preload("res://scripts/world/star.gd").new())

	player = Player.new()
	var rings := PressureRings.new()
	rings.player = player
	add_child(rings)
	dust_field = DustField.new()
	dust_field.player = player
	dust_field.camera = camera
	add_child(dust_field)
	pebble_field = PebbleField.new()
	pebble_field.player = player
	player.pebble_field = pebble_field
	pebble_field.dust_field = dust_field
	pebble_field.camera = camera
	add_child(pebble_field)
	var wind := WindFx.new()
	wind.player = player
	wind.dust_field = dust_field
	wind.pebble_field = pebble_field
	wind.camera = camera
	add_child(wind)
	add_child(player)
	fx = AbsorbFx.new()
	fx.player = player
	fx.camera = camera
	add_child(fx)
	var burn_fx := BurnFx.new()
	burn_fx.player = player
	add_child(burn_fx)
	burn_fx.finished.connect(_show_burned_screen)
	dust_field.evaporated.connect(burn_fx.puff)
	pebble_field.evaporated.connect(burn_fx.puff)
	pebble_field.combo_changed.connect(_on_combo)
	GameState.chondrule_found.connect(func(at: Vector2, amount: int) -> void:
		_chondrule_time = _intro_time
		_chondrule_pos = at
		fx.popup_sum(at + Vector2(0, -player.radius * 1.6), amount, "Хондра +%d", UiTheme.CHONDRULE, 22, "chondrule"))
	pebble_field.geode_found.connect(func(at: Vector2, value: float) -> void:
		_geode_time = _intro_time
		_geode_pos = at
		fx.popup(at + Vector2(0, -player.radius * 2.0), "Жеода! +%s" % GameData.format_number(value), GameData.GEODE_GLOW, 26))
	pebble_field.swarm_started.connect(func(at: Vector2) -> void:
		_swarm_pos = at
		if "swarm" in GameState.tips_seen:
			_show_caption("Потоковая неустойчивость", "рядом сбился рой галек: 20 секунд, чтобы его собрать"))
	pebble_field.eddy_started.connect(func(_at: Vector2) -> void:
		if "eddy" in GameState.tips_seen:
			_show_caption("Вихрь турбулентности", "добыча внутри в полтора раза ценнее. Плыви по течению: против него удары раскалывают"))
	GameState.stage_reached.connect(_on_stage_reached)
	GameState.chipped.connect(func(_at: Vector2, _lost: float) -> void: _chip_time = _intro_time)
	pebble_field.pebble_split.connect(func(at: Vector2) -> void:
		fx.popup(at + Vector2(0, -player.radius * 2.0), "Раскол!", Color(1.0, 0.75, 0.45), 24, "split"))
	pebble_field.self_split.connect(func(_at: Vector2) -> void:
		fx.popup(player.position + Vector2(0, -player.radius * 2.6), "Ты треснул!", Color(1.0, 0.45, 0.35), 24, "selfsplit"))
	pebble_field.chunks_broken.connect(func(at: Vector2) -> void:
		_chunk_time = _intro_time
		_chunk_pos = at)
	pebble_field.crash_burst.connect(func(at: Vector2) -> void:
		fx.popup(at + Vector2(0, -player.radius * 2.5), "Столкновение!", Color(1.0, 0.7, 0.4), 26)
		if "crash" in GameState.tips_seen:
			_show_caption("Столкновение валунов", "облако обломков на полминуты: они вдвое ценнее, но быстрые"))
	pebble_field.giant.appeared.connect(func(_at: Vector2) -> void:
		if "giant" in GameState.tips_seen:
			_show_caption("Странник", "валун в десятки раз крупнее тебя: с разгону о него расколешься, а пыль за ним — твоя"))
	pebble_field.clump_started.connect(func(_at: Vector2) -> void:
		if "clump" in GameState.tips_seen:
			_show_caption("Сгусток", "мелочь в кольце сжимается: успей в центр за 25 секунд"))

	camera.position = player.position
	camera.zoom = Vector2.ONE * _target_zoom()
	add_child(camera)
	camera.reset_smoothing()

	var ui := CanvasLayer.new()
	ui.name = "UI"
	ui.layer = 10
	add_child(ui)
	joystick = VirtualJoystick.new()
	ui.add_child(joystick)
	hud = Hud.new()
	ui.add_child(hud)
	tree_screen = SkillTreeScreen.new()
	ui.add_child(tree_screen)

	pause_menu = PauseMenu.new()
	ui.add_child(pause_menu)

	hud.tree_requested.connect(_open_tree)
	hud.menu_requested.connect(_open_pause)
	tree_screen.closed.connect(hud.play_purchase_spark)
	tree_screen.closed.connect(_set_world_visible.bind(true))

	# Вход в игру: камера издалека приближается к пылинке, проступает подпись.
	camera.zoom *= INTRO_ZOOM
	_show_caption("Протопланетный диск молодой звезды", "4,6 миллиарда лет назад")
	if not GameState.tutorial_done:
		var tutorial := Tutorial.new()
		tutorial.main = self
		ui.add_child(tutorial)
		guide = tutorial
		ui.move_child(pause_menu, -1)
	elif GameState.is_boulder() and not GameState.boulder_intro_done:
		_start_pebble_intro(2.5, true)
	elif GameState.stage >= GameData.PLANETESIMAL_STAGE and not "planetesimal" in GameState.tips_seen:
		_start_finale(2.5)
	elif GameState.is_pebble() and not GameState.pebble_intro_done:
		_start_pebble_intro(2.5)


## Пылинка доросла до гальки: вспышка, подпись и рассказ Звездочёта.
func _on_stage_reached(index: int) -> void:
	if index < GameData.PEBBLE_STAGE or index > GameData.PLANETESIMAL_STAGE:
		return
	var flash := ColorRect.new()
	flash.color = Color(1.0, 0.92, 0.75, 0.0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$UI.add_child(flash)
	$UI.move_child(flash, hud.get_index() + 1)
	var tw := flash.create_tween()
	tw.tween_property(flash, "color:a", 0.55, 0.25)
	tw.tween_property(flash, "color:a", 0.0, 1.6)
	tw.tween_callback(flash.queue_free)
	# Скачок масштаба: камера отъезжает и плавно возвращается, пыль вокруг мельчает —
	# видно, насколько ты вырос.
	camera.zoom *= 0.55
	_zoom_ease = 0.0
	if index == GameData.PLANETESIMAL_STAGE:
		_show_caption("Планетезималь", "тело в километр: его держит собственная гравитация")
		if not "planetesimal" in GameState.tips_seen:
			_start_finale(4.5)
		return
	if index == GameData.BOULDER_STAGE:
		_boulder_time = _intro_time
		_show_caption("Валун", "камень ростом с человека")
		if not GameState.boulder_intro_done:
			_start_pebble_intro(4.5, true)
		return
	_show_caption("Галька", "камешек размером с горошину")
	if not GameState.pebble_intro_done:
		_start_pebble_intro(4.5)


## Финал этапа «Валун»: Звездочёт рассказывает о планетезимали.
func _start_finale(delay: float) -> void:
	for c in $UI.get_children():
		if c is Tutorial:
			return
	var tutorial := Tutorial.new()
	tutorial.main = self
	tutorial.steps = Tutorial.PLANET_STEPS
	tutorial.tip = "planetesimal"
	tutorial.start_delay = delay
	$UI.add_child(tutorial)
	guide = tutorial
	$UI.move_child(pause_menu, -1)


func _start_pebble_intro(delay: float, boulder := false) -> void:
	for c in $UI.get_children():
		if c is Tutorial:
			return
	var tutorial := Tutorial.new()
	tutorial.main = self
	tutorial.steps = Tutorial.BOULDER_STEPS if boulder else Tutorial.PEBBLE_STEPS
	tutorial.pebble = not boulder
	tutorial.boulder = boulder
	tutorial.start_delay = delay
	$UI.add_child(tutorial)
	guide = tutorial
	$UI.move_child(pause_menu, -1)


func _on_combo(chain: int, multiplier: float) -> void:
	if chain >= 2:
		fx.popup(player.position + Vector2(0, -player.radius * 2.6), "Серия %d · ×%.2f" % [chain, multiplier], Color(1.0, 0.8, 0.45), 22, "combo")


func _show_caption(title: String, subtitle: String) -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	box.offset_left = -400
	box.offset_right = 400
	box.offset_top = 150
	box.offset_bottom = 230
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.modulate.a = 0.0
	if is_instance_valid(_caption):
		_caption.queue_free()
	_caption = box
	$UI.add_child(box)
	$UI.move_child(box, hud.get_index() + 1)  # под книгой и меню, не поверх них
	for line in [[title, UiTheme.FONT_SERIF_BOLD, 30], [subtitle, UiTheme.FONT_SERIF_ITALIC, 22]]:
		var l := Label.new()
		l.text = line[0]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_override("font", line[1])
		l.add_theme_font_size_override("font_size", line[2])
		l.add_theme_color_override("font_color", Color(1.0, 0.86, 0.6))
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
		l.add_theme_constant_override("outline_size", 6)
		box.add_child(l)
	var tw := box.create_tween()
	tw.tween_interval(0.6)
	tw.tween_property(box, "modulate:a", 1.0, 1.2)
	tw.tween_interval(2.4)
	tw.tween_property(box, "modulate:a", 0.0, 1.2)
	tw.tween_callback(box.queue_free)


func _open_pause() -> void:
	if player.dead or tree_screen.visible:
		return
	joystick.reset()
	player.move_input = Vector2.ZERO
	pause_menu.open()


func _notification(what: int) -> void:
	# Кнопка «назад» на Android: древо закрывается само, иначе открывается пауза.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and not tree_screen.visible:
		if pause_menu.visible:
			pause_menu.close()
		else:
			_open_pause()


func _show_burned_screen() -> void:
	joystick.visible = false
	hud.visible = false
	$UI.add_child(BurnedScreen.new())


func _unhandled_key_input(event: InputEvent) -> void:
	if event.pressed and not event.echo and event.physical_keycode == KEY_TAB:
		_open_tree()
	elif event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE and not tree_screen.visible:
		_open_pause()


func _open_tree() -> void:
	if player.dead:
		return
	joystick.reset()
	player.move_input = Vector2.ZERO
	tree_screen.open()
	_set_world_visible(false)


## Под книгой навыков мир не виден, но рисовался бы каждый кадр: пыль, гальки,
## фон с шейдерами. Пока книга открыта, прячем его — книга идёт плавнее.
func _set_world_visible(on: bool) -> void:
	if not on:
		_hidden_world.clear()
		for c in get_children():
			if c is CanvasLayer and (c as CanvasLayer).layer >= 10:
				continue  # интерфейс
			if (c is CanvasItem or c is CanvasLayer) and c.visible:
				c.visible = false
				_hidden_world.append(c)
	else:
		for c in _hidden_world:
			if is_instance_valid(c):
				c.visible = true
		_hidden_world.clear()


func _target_zoom() -> float:
	var start_zoom := SCREEN_RADIUS_AT_START / GameData.BASE_RADIUS
	var z := start_zoom * pow(GameData.BASE_RADIUS / player.radius, ZOOM_GROWTH_EXP)
	return z * lerpf(1.0, PEBBLE_ZOOM, player.pebble_k) * lerpf(1.0, BOULDER_ZOOM, player.boulder_k)


func _process(delta: float) -> void:
	player.move_input = joystick.output
	camera.position = player.position
	# Приближение идёт в логарифмах: вход издалека выглядит равномерным полётом.
	_intro_time += delta
	_zoom_ease += delta
	var rate := lerpf(0.9, 2.0, clampf(_zoom_ease / 3.0, 0.0, 1.0))
	var z := exp(lerpf(log(camera.zoom.x), log(_target_zoom()), 1.0 - exp(-rate * delta)))
	camera.zoom = Vector2(z, z)
	hud.star_screen_pos = get_viewport().get_canvas_transform() * Vector2.ZERO
	hud.set_temperature(player.temperature)
	hud.set_ice_vapor(player.ice_vapor)
	hud.set_zone(GameData.zone_at(player.position.length()))
	hud.set_wind(player.drift_velocity, player.position, player.pebble_k, player.shadow)
	_check_tips()


## Звездочёт показывает явление, когда оно впервые встретилось, по одному за раз.
func _check_tips() -> void:
	if GameState.is_boulder() and not GameState.boulder_intro_done:
		return
	if is_instance_valid(guide) or not GameState.pebble_intro_done or player.pebble_k < 0.95 \
			or player.dead or tree_screen.visible or pause_menu.visible:
		return
	var found := {
		"chip": _intro_time - _chip_time < 0.8,
		"geode": _intro_time - _geode_time < 1.5,
		"chondrule": _intro_time - _chondrule_time < 1.5,
		"eddy": pebble_field.eddy_left > 5.0,
		"swarm": pebble_field.swarm_left > 5.0,
		"chunks": _intro_time - _chunk_time > 0.7 and _intro_time - _chunk_time < 5.0 \
				and pebble_field.chunk_center() != Vector2.INF,  # дать кускам разлететься
		"ice": player.ice_vapor > 0.0 and hud._ice_label.visible,
		"shadow": GameState.is_boulder() and pebble_field.shadow_spot() != Vector2.INF,
		"crash": pebble_field.crash_spot() != Vector2.INF,
		"giant": pebble_field.giant.active and pebble_field.giant.world_center().distance_to(player.position) < dust_field.view_radius() * 0.75,
		"gravity": GameState.is_boulder() and GameState.stage < GameData.PLANETESIMAL_STAGE \
				and GameData.self_gravity(GameState.mass) + Skills.stat("self_grav") > 0.05,
		"material": GameState.is_boulder() and _intro_time - _boulder_time > 40.0 \
				and GameData.BOULDER_MATERIAL.has(GameState.body_type()),
		"clump": pebble_field.clump_left > 3.0 and pebble_field.clump_left < PebbleField.CLUMP_TIME - 1.0,
	}
	for kind in found:
		if found[kind] and not kind in GameState.tips_seen:
			var tip := Tutorial.new()
			tip.main = self
			tip.steps = [Tutorial.TIPS[kind]]
			tip.tip = kind
			tip.tip_pos = {"geode": _geode_pos, "chondrule": _chondrule_pos, "swarm": _swarm_pos, "chunks": pebble_field.chunk_center(),
					"shadow": pebble_field.shadow_spot(), "crash": pebble_field.crash_spot(), "giant": pebble_field.giant.world_center() if pebble_field.giant.active else Vector2.INF,
					"clump": pebble_field.clump_center + dust_field.frame_offset}.get(kind, Vector2.INF)
			tip.start_delay = 0.1
			$UI.add_child(tip)
			$UI.move_child(pause_menu, -1)
			guide = tip
			return
