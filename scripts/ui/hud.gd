class_name Hud
extends Control
## Верхняя панель: валюта, масса, стадия, материалы, кнопка древа и указатель на звезду.

signal tree_requested

var star_screen_pos := Vector2.ZERO
var _currency_label: Label
var _mass_label: Label
var _stage_label: Label
var _stage_bar: ProgressBar
var _material_labels := {}
var _comp_bar: Control
var _body_label: Label
var _tree_button: Button
var _badge: Label
var _drawn_star_pos := Vector2(INF, INF)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	GameState.currency_changed.connect(_refresh.unbind(1))
	GameState.mass_changed.connect(_refresh.unbind(1))
	GameState.skills_changed.connect(_refresh)
	_refresh()


func _build() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(24, 18)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	_currency_label = _label(40, Color(1.0, 0.86, 0.5))
	box.add_child(_currency_label)
	_mass_label = _label(22, Color(0.85, 0.9, 1.0))
	box.add_child(_mass_label)
	_stage_label = _label(20, Color(0.7, 0.75, 0.9))
	box.add_child(_stage_label)
	_stage_bar = ProgressBar.new()
	_stage_bar.custom_minimum_size = Vector2(260, 10)
	_stage_bar.show_percentage = false
	_stage_bar.max_value = 1.0
	_stage_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_stage_bar)

	var mats := HBoxContainer.new()
	mats.add_theme_constant_override("separation", 14)
	mats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(mats)
	for key in GameData.MATERIAL_ORDER:
		var l := _label(16, GameData.MATERIALS[key].color)
		mats.add_child(l)
		_material_labels[key] = l

	_comp_bar = Control.new()
	_comp_bar.custom_minimum_size = Vector2(320, 14)
	_comp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_comp_bar.draw.connect(_draw_composition)
	box.add_child(_comp_bar)
	_body_label = _label(18, Color(0.85, 0.9, 1.0))
	box.add_child(_body_label)

	_tree_button = Button.new()
	_tree_button.text = "Древо"
	_tree_button.add_theme_font_size_override("font_size", 28)
	_tree_button.custom_minimum_size = Vector2(170, 76)
	_tree_button.anchor_left = 1.0
	_tree_button.anchor_right = 1.0
	_tree_button.offset_left = -194
	_tree_button.offset_right = -24
	_tree_button.offset_top = 20
	_tree_button.offset_bottom = 96
	_tree_button.focus_mode = Control.FOCUS_NONE
	_tree_button.pressed.connect(func(): tree_requested.emit())
	add_child(_tree_button)

	_badge = _label(26, Color(1.0, 0.7, 0.28))
	_badge.text = "●"
	_badge.position = Vector2(150, -12)
	_tree_button.add_child(_badge)


func _label(font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _refresh() -> void:
	_currency_label.text = "✦ " + GameData.format_number(GameState.currency)
	_mass_label.text = "Масса: " + GameData.format_mass(GameState.mass)
	var idx := GameData.stage_index(GameState.mass)
	var stage: Dictionary = GameData.STAGES[idx]
	if idx + 1 < GameData.STAGES.size():
		var next: Dictionary = GameData.STAGES[idx + 1]
		_stage_label.text = "%s → %s" % [stage.name, next.name]
		_stage_bar.value = inverse_lerp(stage.mass, next.mass, GameState.mass)
	else:
		_stage_label.text = stage.name
		_stage_bar.value = 1.0
	var shares := GameData.composition(GameState.materials)
	for key in _material_labels:
		_material_labels[key].text = "● %s %d%%" % [GameData.MATERIALS[key].name, roundi(shares[key] * 100.0)]
	var body: Dictionary = GameData.BODY_TYPES[GameState.body_type()]
	_body_label.text = "Тело: %s (%s)" % [body.name, body.desc]
	_comp_bar.queue_redraw()
	_badge.visible = Skills.any_affordable()


## Полоса состава с отметками порогов смеси (40%) и специализации (50%).
func _draw_composition() -> void:
	var w := _comp_bar.size.x
	var h := _comp_bar.size.y
	_comp_bar.draw_rect(Rect2(0, 0, w, h), Color(1, 1, 1, 0.08))
	var shares := GameData.composition(GameState.materials)
	# Крупнейшая доля идёт первой, чтобы её было удобно сравнить с отметками.
	var keys: Array = GameData.MATERIAL_ORDER.duplicate()
	keys.sort_custom(func(a, b): return shares[a] > shares[b])
	var x := 0.0
	for key in keys:
		var seg: float = shares[key] * w
		if seg > 0.0:
			_comp_bar.draw_rect(Rect2(x, 0, seg, h), GameData.MATERIALS[key].color)
		x += seg
	for share in [GameData.MIX_MAX_SHARE, GameData.SPECIALIZE_SHARE]:
		var mx: float = share * w
		_comp_bar.draw_line(Vector2(mx, -3), Vector2(mx, h + 3), Color(1, 1, 1, 0.8), 2.0)


func _process(_delta: float) -> void:
	# Перерисовываем стрелку только когда она сдвинулась.
	if star_screen_pos.distance_squared_to(_drawn_star_pos) > 1.0:
		_drawn_star_pos = star_screen_pos
		queue_redraw()


## Стрелка у края экрана в сторону звезды, пока её не видно.
func _draw() -> void:
	if size.x < 100.0 or size.y < 100.0:
		return
	var rect := Rect2(Vector2.ZERO, size).grow(-40.0)
	if rect.has_point(star_screen_pos):
		return
	var center := size * 0.5
	var dir := (star_screen_pos - center).normalized()
	var t := INF
	if absf(dir.x) > 0.001:
		t = minf(t, (rect.size.x * 0.5) / absf(dir.x))
	if absf(dir.y) > 0.001:
		t = minf(t, (rect.size.y * 0.5) / absf(dir.y))
	var tip := center + dir * t
	var side := dir.orthogonal() * 12.0
	var col := Color(1.0, 0.8, 0.45, 0.7)
	draw_colored_polygon(PackedVector2Array([tip, tip - dir * 24.0 + side, tip - dir * 24.0 - side]), col)
