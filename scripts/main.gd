extends Node2D
## Сборка сцены: фон, звезда, пыль, игрок, камера и интерфейс.

const SCREEN_RADIUS_AT_START := 10.0  # радиус пылинки на экране в начале, px
const ZOOM_GROWTH_EXP := 0.75         # <1: камера отдаляется медленнее, чем растёт тело
const INTRO_ZOOM := 0.55              # на входе камера дальше и плавно приближается

var player: Player
var dust_field: DustField
var camera: Camera2D
var hud: Hud
var joystick: VirtualJoystick
var tree_screen: SkillTreeScreen
var pause_menu: PauseMenu
var pebble_field: PebbleField
var sky_events: Node2D
var _intro_time := 0.0
var _caption: Control


func _ready() -> void:
	# Камера двигается после игрока в том же кадре, иначе отстаёт на кадр и дёргается.
	process_priority = 100
	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0

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
	pebble_field.dust_field = dust_field
	pebble_field.camera = camera
	add_child(pebble_field)
	var wind := WindFx.new()
	wind.player = player
	wind.dust_field = dust_field
	wind.camera = camera
	add_child(wind)
	add_child(player)
	var fx := AbsorbFx.new()
	fx.player = player
	fx.camera = camera
	add_child(fx)
	var burn_fx := BurnFx.new()
	burn_fx.player = player
	add_child(burn_fx)
	burn_fx.finished.connect(_show_burned_screen)
	dust_field.evaporated.connect(burn_fx.puff)
	pebble_field.evaporated.connect(burn_fx.puff)
	GameState.stage_reached.connect(_on_stage_reached)

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

	# Вход в игру: камера издалека приближается к пылинке, проступает подпись.
	camera.zoom *= INTRO_ZOOM
	_show_caption("Протопланетный диск молодой звезды", "4,6 миллиарда лет назад")
	if not GameState.tutorial_done:
		var tutorial := Tutorial.new()
		tutorial.main = self
		ui.add_child(tutorial)
		ui.move_child(pause_menu, -1)
	elif GameState.is_pebble() and not GameState.pebble_intro_done:
		_start_pebble_intro(2.5)


## Пылинка доросла до гальки: вспышка, подпись и рассказ Звездочёта.
func _on_stage_reached(index: int) -> void:
	if index != GameData.PEBBLE_STAGE:
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
	_show_caption("Галька", "камешек размером с горошину")
	if not GameState.pebble_intro_done:
		_start_pebble_intro(4.5)


func _start_pebble_intro(delay: float) -> void:
	for c in $UI.get_children():
		if c is Tutorial:
			return
	var tutorial := Tutorial.new()
	tutorial.main = self
	tutorial.steps = Tutorial.PEBBLE_STEPS
	tutorial.pebble = true
	tutorial.start_delay = delay
	$UI.add_child(tutorial)
	$UI.move_child(pause_menu, -1)


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


func _target_zoom() -> float:
	var start_zoom := SCREEN_RADIUS_AT_START / GameData.BASE_RADIUS
	return start_zoom * pow(GameData.BASE_RADIUS / player.radius, ZOOM_GROWTH_EXP)


func _process(delta: float) -> void:
	player.move_input = joystick.output
	camera.position = player.position
	# Приближение идёт в логарифмах: вход издалека выглядит равномерным полётом.
	_intro_time += delta
	var rate := lerpf(0.9, 2.0, clampf(_intro_time / 3.0, 0.0, 1.0))
	var z := exp(lerpf(log(camera.zoom.x), log(_target_zoom()), 1.0 - exp(-rate * delta)))
	camera.zoom = Vector2(z, z)
	hud.star_screen_pos = get_viewport().get_canvas_transform() * Vector2.ZERO
	hud.set_temperature(player.temperature)
	hud.set_zone(GameData.zone_at(player.position.length()))
	hud.set_wind(player.drift_velocity, player.position, player.pebble_k)
