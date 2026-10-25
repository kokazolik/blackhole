class_name BurnedScreen
extends Control
## Экран после гибели у звезды: что произошло и кнопка нового забега.

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiTheme.get_theme()
	modulate.a = 0.0

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.02, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(560, 0)
	box.position -= Vector2(280, 130)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	add_child(box)

	var title := Label.new()
	title.text = "Пылинка испарилась"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", UiTheme.FONT_NUMBERS)
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(1.0, 0.72, 0.4))
	box.add_child(title)

	var text := Label.new()
	text.text = "Огня в космосе нет: излучение звезды раскалило пылинку, вещество перешло в газ, и звёздный ветер унёс его прочь."
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.add_theme_font_size_override("font_size", 19)
	text.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	box.add_child(text)

	var again := Button.new()
	again.text = "Начать заново"
	again.custom_minimum_size = Vector2(260, 70)
	again.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	again.focus_mode = Control.FOCUS_NONE
	again.add_theme_font_size_override("font_size", 24)
	again.pressed.connect(_restart)
	box.add_child(again)

	create_tween().tween_property(self, "modulate:a", 1.0, 0.8)


func _restart() -> void:
	GameState.reset_run()
	get_tree().reload_current_scene()
