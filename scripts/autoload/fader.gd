extends CanvasLayer
## Плавные переходы между экранами: затемнение, смена сцены, проявление.

const MENU := "res://scenes/menu.tscn"
const PROLOGUE := "res://scenes/prologue.tscn"
const GAME := "res://scenes/main.tscn"
const GIANT := "res://scenes/giant.tscn"
const YOUNG := "res://scenes/young.tscn"
const CLOUD := "res://scenes/cloud.tscn"

var _rect := ColorRect.new()
var _busy := false


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect.color = Color(0.0, 0.0, 0.01, 0.0)
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Прозрачный прямоугольник на весь экран всё равно заливается каждый кадр:
	# между переходами прячем его.
	_rect.visible = false
	add_child(_rect)


## Затемнить экран, сменить сцену и проявить новую.
func go(path: String, out_time := 0.6, in_time := 0.9, tint := Color(0.0, 0.0, 0.01)) -> void:
	if _busy:
		return
	# Этап гиганта — своя сцена: продолжение забега ведёт туда.
	if path == GAME and GameState.is_cloud() and GameState.ending == "":
		path = CLOUD
	elif path == GAME and GameState.is_giant() and GameState.ending == "":
		path = GIANT
	elif path == GAME and GameState.is_young() and GameState.ending == "":
		path = YOUNG
	_busy = true
	_rect.color = Color(tint.r, tint.g, tint.b, _rect.color.a)
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_rect.visible = true
	var tw := create_tween()
	tw.tween_property(_rect, "color:a", 1.0, out_time)
	await tw.finished
	get_tree().paused = false
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame
	tw = create_tween()
	tw.tween_property(_rect, "color:a", 0.0, in_time)
	await tw.finished
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.visible = false
	_busy = false


## Счётчик кадров в углу (настройка). Поверх всего, касаний не ловит.
var _fps: Label


func set_fps_counter(on: bool) -> void:
	if on and _fps == null:
		_fps = Label.new()
		_fps.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fps.position = Vector2(10, 6)
		_fps.add_theme_font_override("font", UiTheme.FONT_NUMBERS)
		_fps.add_theme_font_size_override("font_size", 14)
		_fps.add_theme_color_override("font_color", Color(0.75, 1.0, 0.75, 0.8))
		_fps.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		_fps.add_theme_constant_override("outline_size", 4)
		add_child(_fps)
	if _fps != null:
		_fps.visible = on


## Кнопка скриншота (настройка). Под затемнением перехода, над игрой.
var _shot: ShotButton


func set_shot_button(on: bool) -> void:
	if on and _shot == null:
		_shot = ShotButton.new()
		add_child(_shot)
		move_child(_shot, 0)
	if _shot != null:
		_shot.visible = on


func _process(_delta: float) -> void:
	if _fps != null and _fps.visible:
		_fps.text = "%d кадр/с" % Engine.get_frames_per_second()
