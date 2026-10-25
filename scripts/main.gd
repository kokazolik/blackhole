extends Node2D
## Сборка сцены: фон, звезда, пыль, игрок, камера и интерфейс.

const SCREEN_RADIUS_AT_START := 10.0  # радиус пылинки на экране в начале, px
const ZOOM_GROWTH_EXP := 0.75         # <1: камера отдаляется медленнее, чем растёт тело

var player: Player
var dust_field: DustField
var camera: Camera2D
var hud: Hud
var joystick: VirtualJoystick
var tree_screen: SkillTreeScreen
var sky_events: Node2D


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
	dust_field = DustField.new()
	dust_field.player = player
	dust_field.camera = camera
	add_child(dust_field)
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

	hud.tree_requested.connect(_open_tree)
	tree_screen.closed.connect(hud.play_purchase_spark)


func _show_burned_screen() -> void:
	joystick.visible = false
	hud.visible = false
	$UI.add_child(BurnedScreen.new())


func _unhandled_key_input(event: InputEvent) -> void:
	if event.pressed and not event.echo and event.physical_keycode == KEY_TAB:
		_open_tree()


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
	var z := lerpf(camera.zoom.x, _target_zoom(), 1.0 - exp(-2.0 * delta))
	camera.zoom = Vector2(z, z)
	hud.star_screen_pos = get_viewport().get_canvas_transform() * Vector2.ZERO
	hud.set_temperature(player.temperature)
	hud.set_zone(GameData.zone_at(player.position.length()))
