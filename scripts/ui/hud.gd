class_name Hud
extends Control
## Интерфейс поверх игры без подложек: валюта и масса слева, стадия и состав
## сверху по центру, звёздная книга (древо) и сброс справа, указатель на звезду.

signal tree_requested

const TOP_WIDTH := 380.0
const BOOK_ICON := preload("res://assets/ui/book.png")
const RESET_ICON := preload("res://assets/ui/reset.png")

var star_screen_pos := Vector2.ZERO
var _currency_label: Label
var _currency_icon: Control
var _mass_label: Label
var _stage_label: Label
var _stage_bar: Control
var _stage_progress := 0.0
var _material_labels := {}
var _comp_bar: Control
var _body_label: Label
var _body_desc: Label
var _tree_button: Button
var _badge: Control
var _reset_button: Button
var _reset_armed := false
var _reset_hint: Label
var _last_currency := 0.0
var _bump_tween: Tween
var _time := 0.0
var _arrow_visible := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.get_theme()
	_build()
	_last_currency = GameState.currency
	GameState.currency_changed.connect(_on_currency_changed)
	GameState.mass_changed.connect(_refresh.unbind(1))
	GameState.skills_changed.connect(_refresh)
	_refresh()


func _build() -> void:
	# Слева сверху без подложки: валюта и масса.
	var left := VBoxContainer.new()
	left.position = Vector2(22, 14)
	left.add_theme_constant_override("separation", -4)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(left)
	var cur_row := HBoxContainer.new()
	cur_row.add_theme_constant_override("separation", 8)
	cur_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(cur_row)
	_currency_icon = Control.new()
	_currency_icon.custom_minimum_size = Vector2(34, 46)
	_currency_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_currency_icon.draw.connect(_draw_currency_icon)
	cur_row.add_child(_currency_icon)
	_currency_label = _label(40, UiTheme.GOLD, UiTheme.FONT_NUMBERS)
	cur_row.add_child(_currency_label)
	_mass_label = _label(16, UiTheme.TEXT_DIM, UiTheme.FONT_SEMI)
	_mass_label.custom_minimum_size = Vector2(0, 0)
	var mass_pad := MarginContainer.new()
	mass_pad.add_theme_constant_override("margin_left", 44)
	mass_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mass_pad.add_child(_mass_label)
	left.add_child(mass_pad)

	# Сверху по центру: стадия, прогресс до следующей, состав тела.
	var top := VBoxContainer.new()
	top.anchor_left = 0.5
	top.anchor_right = 0.5
	top.offset_left = -TOP_WIDTH * 0.5
	top.offset_right = TOP_WIDTH * 0.5
	top.offset_top = 12
	top.add_theme_constant_override("separation", 4)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	_stage_label = _label(15, UiTheme.TEXT, UiTheme.FONT_SEMI)
	_stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_stage_label)
	_stage_bar = Control.new()
	_stage_bar.custom_minimum_size = Vector2(0, 5)
	_stage_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_bar.draw.connect(_draw_stage_bar)
	top.add_child(_stage_bar)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 3)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(gap)
	_comp_bar = Control.new()
	_comp_bar.custom_minimum_size = Vector2(0, 7)
	_comp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_comp_bar.draw.connect(_draw_composition)
	top.add_child(_comp_bar)
	var mats := HBoxContainer.new()
	mats.alignment = BoxContainer.ALIGNMENT_CENTER
	mats.add_theme_constant_override("separation", 12)
	mats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(mats)
	for key in GameData.MATERIAL_ORDER:
		var l := _label(12, GameData.MATERIALS[key].color)
		mats.add_child(l)
		_material_labels[key] = l
	var body_row := HBoxContainer.new()
	body_row.alignment = BoxContainer.ALIGNMENT_CENTER
	body_row.add_theme_constant_override("separation", 6)
	body_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(body_row)
	_body_label = _label(13, UiTheme.TEXT, UiTheme.FONT_SEMI)
	body_row.add_child(_body_label)
	_body_desc = _label(12, UiTheme.TEXT_DIM)
	body_row.add_child(_body_desc)

	# Справа сверху: кнопка древа — звёздная книга, без текста.
	_tree_button = Button.new()
	_tree_button.icon = BOOK_ICON
	_tree_button.expand_icon = true
	_tree_button.flat = true
	_tree_button.anchor_left = 1.0
	_tree_button.anchor_right = 1.0
	_tree_button.offset_left = -112
	_tree_button.offset_right = -12
	_tree_button.offset_top = 4
	_tree_button.offset_bottom = 104
	_tree_button.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		_tree_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_tree_button.button_down.connect(func(): _press_anim(_tree_button, 0.9))
	_tree_button.button_up.connect(func(): _press_anim(_tree_button, 1.0))
	_tree_button.pressed.connect(func(): tree_requested.emit())
	add_child(_tree_button)

	# Пульсирующая точка: в древе есть что купить.
	_badge = Control.new()
	_badge.position = Vector2(76, 14)
	_badge.size = Vector2(14, 14)
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.draw.connect(_draw_badge)
	_tree_button.add_child(_badge)

	# Сброс прогресса: маленькая иконка, первое нажатие просит подтверждения.
	_reset_button = Button.new()
	_reset_button.icon = RESET_ICON
	_reset_button.expand_icon = true
	_reset_button.flat = true
	_reset_button.modulate = Color(1, 1, 1, 0.45)
	_reset_button.anchor_left = 1.0
	_reset_button.anchor_right = 1.0
	_reset_button.offset_left = -78
	_reset_button.offset_right = -46
	_reset_button.offset_top = 110
	_reset_button.offset_bottom = 142
	_reset_button.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		_reset_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_reset_button.pressed.connect(_on_reset_pressed)
	add_child(_reset_button)
	_reset_hint = _label(14, Color(1.0, 0.5, 0.4), UiTheme.FONT_SEMI)
	_reset_hint.text = "Нажми ещё раз для сброса"
	_reset_hint.anchor_left = 1.0
	_reset_hint.anchor_right = 1.0
	_reset_hint.offset_left = -300
	_reset_hint.offset_right = -84
	_reset_hint.offset_top = 116
	_reset_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_reset_hint.visible = false
	add_child(_reset_hint)


func _press_anim(button: Control, target: float) -> void:
	button.pivot_offset = button.size * 0.5
	var tw := create_tween()
	tw.tween_property(button, "scale", Vector2.ONE * target, 0.08)


func _on_reset_pressed() -> void:
	if not _reset_armed:
		_reset_armed = true
		_reset_button.modulate = Color(1.0, 0.5, 0.4, 1.0)
		_reset_hint.visible = true
		await get_tree().create_timer(3.0).timeout
		if is_instance_valid(_reset_button):
			_reset_armed = false
			_reset_button.modulate = Color(1, 1, 1, 0.45)
			_reset_hint.visible = false
		return
	GameState.reset_run()
	get_tree().reload_current_scene()


func _label(font_size: int, color: Color, font: Font = null) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if font:
		l.add_theme_font_override("font", font)
	# Без подложки текст держится на тени и обводке.
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Число валюты подпрыгивает при каждом поступлении.
func _on_currency_changed(value: float) -> void:
	var gained := value > _last_currency
	_last_currency = value
	_refresh()
	if not gained:
		return
	_currency_label.pivot_offset = Vector2(0, _currency_label.size.y * 0.5)
	if _bump_tween:
		_bump_tween.kill()
	_bump_tween = create_tween()
	_currency_label.scale = Vector2.ONE * 1.16
	_currency_label.modulate = Color(1.3, 1.25, 1.1)
	_bump_tween.set_parallel(true)
	_bump_tween.tween_property(_currency_label, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_bump_tween.tween_property(_currency_label, "modulate", Color.WHITE, 0.35)


func _refresh() -> void:
	_currency_label.text = GameData.format_number(GameState.currency)
	_mass_label.text = "масса " + GameData.format_mass(GameState.mass)
	var idx := GameData.stage_index(GameState.mass)
	var stage: Dictionary = GameData.STAGES[idx]
	if idx + 1 < GameData.STAGES.size():
		var next: Dictionary = GameData.STAGES[idx + 1]
		_stage_label.text = "%s → %s" % [stage.name, next.name]
		_stage_progress = clampf(inverse_lerp(stage.mass, next.mass, GameState.mass), 0.0, 1.0)
	else:
		_stage_label.text = stage.name
		_stage_progress = 1.0
	var shares := GameData.composition(GameState.materials)
	for key in _material_labels:
		_material_labels[key].text = "● %s %d%%" % [GameData.MATERIALS[key].name, roundi(shares[key] * 100.0)]
	var type := GameState.body_type()
	var body: Dictionary = GameData.BODY_TYPES[type]
	_body_label.text = body.name
	_body_label.add_theme_color_override("font_color", GameData.MATERIALS[type].color if GameData.MATERIALS.has(type) else UiTheme.TEXT)
	_body_desc.text = "· " + body.desc
	_comp_bar.queue_redraw()
	_stage_bar.queue_redraw()
	_badge.visible = Skills.any_affordable()


func _draw_currency_icon() -> void:
	# Четырёхлучевая искра с мягким ореолом.
	var c := _currency_icon.size * 0.5
	var pulse := 1.0 + 0.06 * sin(_time * 3.0)
	_currency_icon.draw_circle(c, 15.0 * pulse, Color(UiTheme.GOLD, 0.12))
	var r := 14.0 * pulse
	var w := 4.0
	var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(w, -w), c + Vector2(r, 0), c + Vector2(w, w),
		c + Vector2(0, r), c + Vector2(-w, w), c + Vector2(-r, 0), c + Vector2(-w, -w)])
	_currency_icon.draw_colored_polygon(pts, UiTheme.GOLD)
	_currency_icon.draw_circle(c, 3.0, Color(1, 1, 0.9))


func _draw_stage_bar() -> void:
	var rect := Rect2(Vector2.ZERO, _stage_bar.size)
	UiTheme.pill(Color(1, 1, 1, 0.08), 3).draw(_stage_bar.get_canvas_item(), rect)
	if _stage_progress > 0.0:
		var fill := Rect2(rect.position, Vector2(maxf(rect.size.x * _stage_progress, 6.0), rect.size.y))
		UiTheme.pill(UiTheme.ICE, 3).draw(_stage_bar.get_canvas_item(), fill)


## Полоса состава с отметками порогов смеси (40%) и специализации (50%).
func _draw_composition() -> void:
	var w := _comp_bar.size.x
	var h := _comp_bar.size.y
	var ci := _comp_bar.get_canvas_item()
	UiTheme.pill(Color(1, 1, 1, 0.08), 5).draw(ci, Rect2(0, 0, w, h))
	var shares := GameData.composition(GameState.materials)
	# Крупнейшая доля идёт первой, чтобы её было удобно сравнить с отметками.
	var keys: Array = GameData.MATERIAL_ORDER.duplicate()
	keys.sort_custom(func(a, b): return shares[a] > shares[b])
	var x := 0.0
	var first := true
	for key in keys:
		var seg: float = shares[key] * w
		if seg > 0.5:
			var s := StyleBoxFlat.new()
			s.bg_color = GameData.MATERIALS[key].color
			s.anti_aliasing = true
			# Скругляем только края всей полосы.
			if first:
				s.corner_radius_top_left = 5
				s.corner_radius_bottom_left = 5
			if x + seg >= w - 0.5:
				s.corner_radius_top_right = 5
				s.corner_radius_bottom_right = 5
			s.draw(ci, Rect2(x, 0, seg, h))
			first = false
		x += seg
	for share in [GameData.MIX_MAX_SHARE, GameData.SPECIALIZE_SHARE]:
		var mx: float = share * w
		_comp_bar.draw_line(Vector2(mx, -3), Vector2(mx, h + 3), Color(1, 1, 1, 0.85), 1.5)


func _draw_badge() -> void:
	var c := _badge.size * 0.5
	var k := 0.5 + 0.5 * sin(_time * 4.0)
	_badge.draw_circle(c, 7.0 + 4.0 * k, Color(UiTheme.GOLD_DEEP, 0.25 * (1.0 - k)))
	_badge.draw_circle(c, 6.0, UiTheme.GOLD)


func _process(delta: float) -> void:
	_time += delta
	_currency_icon.queue_redraw()
	if _badge.visible:
		_badge.queue_redraw()
	var rect := Rect2(Vector2.ZERO, size).grow(-50.0)
	_arrow_visible = size.x > 100.0 and not rect.has_point(star_screen_pos)
	queue_redraw()


## Указатель у края экрана в сторону звезды, пока её не видно, с расстоянием.
func _draw() -> void:
	if not _arrow_visible:
		return
	var rect := Rect2(Vector2.ZERO, size).grow(-50.0)
	var center := size * 0.5
	var dir := (star_screen_pos - center).normalized()
	var t := INF
	if absf(dir.x) > 0.001:
		t = minf(t, (rect.size.x * 0.5) / absf(dir.x))
	if absf(dir.y) > 0.001:
		t = minf(t, (rect.size.y * 0.5) / absf(dir.y))
	var tip := center + dir * t
	var k := 0.5 + 0.5 * sin(_time * 2.5)
	var glow := Color(1.0, 0.6, 0.25, 0.10 + 0.08 * k)
	draw_circle(tip - dir * 12.0, 22.0, glow)
	var side := dir.orthogonal()
	var col := Color(1.0, 0.8, 0.45, 0.75 + 0.2 * k)
	draw_colored_polygon(PackedVector2Array([tip, tip - dir * 22.0 + side * 11.0, tip - dir * 14.0, tip - dir * 22.0 - side * 11.0]), col)
	var dist := maxf(GameState.player_position.length() - GameData.STAR_RADIUS, 0.0)
	var text := GameData.format_number(dist)
	var font := UiTheme.FONT_SEMI
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var tp := tip - dir * 42.0 + Vector2(-tw * 0.5, 5.0)
	draw_string_outline(font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 3, Color(0, 0, 0, 0.6))
	draw_string(font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.85, 0.6, 0.8))
