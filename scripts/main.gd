extends Node2D
## Сборка сцены: фон, звезда, пыль, игрок, камера и интерфейс.

const SCREEN_RADIUS_AT_START := 5.0   # радиус пылинки на экране в начале, px
const ZOOM_GROWTH_EXP := 0.75         # <1: камера отдаляется медленнее, чем растёт тело

var player: Player
var dust_field: DustField
var camera: Camera2D
var hud: Hud
var joystick: VirtualJoystick
var tree_screen: SkillTreeScreen


func _ready() -> void:
	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0

	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -1
	add_child(bg_layer)
	var starfield := preload("res://scripts/world/starfield.gd").new()
	starfield.camera = camera
	bg_layer.add_child(starfield)

	add_child(preload("res://scripts/world/star.gd").new())

	player = Player.new()
	dust_field = DustField.new()
	dust_field.player = player
	dust_field.camera = camera
	add_child(dust_field)
	add_child(player)

	camera.position = player.position
	camera.zoom = Vector2.ONE * _target_zoom()
	add_child(camera)
	camera.reset_smoothing()

	var ui := CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	joystick = VirtualJoystick.new()
	ui.add_child(joystick)
	hud = Hud.new()
	ui.add_child(hud)
	tree_screen = SkillTreeScreen.new()
	ui.add_child(tree_screen)

	hud.tree_requested.connect(_open_tree)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.pressed and not event.echo and event.physical_keycode == KEY_TAB:
		_open_tree()


func _open_tree() -> void:
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
