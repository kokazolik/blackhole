class_name ShotButton
extends Control
## Неприметная кнопка скриншота под правым большим пальцем (настройка «Кнопка
## скриншота»). Сама в кадр не попадает: прячется на кадр съёмки. Снимок —
## в галерею телефона (Pictures/DustToBlackhole), если нельзя — в user://shots.

const SIZE := 42.0
const DIR_NAME := "DustToBlackhole"

var _flash := 0.0
var _busy := false
var _note: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	_note = Label.new()
	_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_note.add_theme_font_override("font", UiTheme.FONT_TEXT)
	_note.add_theme_font_size_override("font_size", 14)
	_note.add_theme_color_override("font_color", Color(0.9, 0.92, 0.98, 0.9))
	_note.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_note.add_theme_constant_override("outline_size", 4)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_note.visible = false
	add_child(_note)
	get_viewport().size_changed.connect(_place)
	_place()


## У правого края, чуть ниже середины: там лежит большой палец в ландшафте.
func _place() -> void:
	var vp := get_viewport().get_visible_rect().size
	position = Vector2(vp.x - SIZE - 18.0, vp.y * 0.6)


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 1.6, 0.0)
		queue_redraw()
		if _flash <= 0.0:
			_note.visible = false


func _draw() -> void:
	var c := Vector2(SIZE, SIZE) * 0.5
	var a := 0.22 + 0.5 * _flash
	draw_circle(c, SIZE * 0.5, Color(0.04, 0.05, 0.09, 0.28))
	draw_arc(c, SIZE * 0.5 - 0.5, 0.0, TAU, 40, Color(0.85, 0.9, 1.0, a), 1.0, true)
	# Значок фотоаппарата волосяной линией.
	var body := Rect2(c + Vector2(-10, -6), Vector2(20, 14))
	draw_rect(body, Color(0.9, 0.93, 1.0, a + 0.1), false, 1.2, true)
	draw_rect(Rect2(c + Vector2(-4, -9), Vector2(8, 3)), Color(0.9, 0.93, 1.0, a + 0.1), false, 1.2, true)
	draw_arc(c + Vector2(0, 1), 4.0, 0.0, TAU, 20, Color(0.9, 0.93, 1.0, a + 0.1), 1.2, true)


func _gui_input(e: InputEvent) -> void:
	var pressed: bool = (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) \
		or (e is InputEventScreenTouch and e.pressed)
	if pressed:
		accept_event()
		take()


func take() -> void:
	if _busy:
		return
	_busy = true
	visible = false
	# Кадр без кнопки: ждём, пока он дорисуется.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	visible = GameState.shot_button
	var path := _save(img)
	_busy = false
	_flash = 1.0
	GameState.vibrate(15)
	_note.text = "скрин сохранён" if path != "" else "не удалось сохранить"
	_note.size = Vector2(220, 20)
	_note.position = Vector2(SIZE - 220.0, SIZE + 4.0)
	_note.visible = true
	queue_redraw()


func _save(img: Image) -> String:
	var name := "shot_%s.png" % Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var dirs: Array[String] = []
	var pics := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	if pics != "":
		dirs.append(pics.path_join(DIR_NAME))
	dirs.append(OS.get_user_data_dir().path_join("shots"))
	for d in dirs:
		if DirAccess.make_dir_recursive_absolute(d) != OK and not DirAccess.dir_exists_absolute(d):
			continue
		var p := d.path_join(name)
		if img.save_png(p) == OK:
			return p
	return ""
