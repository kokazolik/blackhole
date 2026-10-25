extends CanvasLayer
## Плавные переходы между экранами: затемнение, смена сцены, проявление.

const MENU := "res://scenes/menu.tscn"
const PROLOGUE := "res://scenes/prologue.tscn"
const GAME := "res://scenes/main.tscn"

var _rect := ColorRect.new()
var _busy := false


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect.color = Color(0.0, 0.0, 0.01, 0.0)
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)


## Затемнить экран, сменить сцену и проявить новую.
func go(path: String, out_time := 0.6, in_time := 0.9) -> void:
	if _busy:
		return
	_busy = true
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
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
	_busy = false
