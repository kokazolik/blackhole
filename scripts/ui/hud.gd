class_name Hud
extends Control
## Интерфейс поверх игры без подложек: валюта и масса слева, стадия и состав
## сверху по центру, звёздная книга (древо) и меню справа, указатель на звезду.

signal tree_requested
signal menu_requested

const TOP_WIDTH := 380.0
const BOOK_ICON := preload("res://assets/ui/book.png")

var star_screen_pos := Vector2.ZERO
static var show_fps := false  # включается в меню разработчика
var _fps_label: Label
var _fps_t := 0.0
var _fps_worst := 0.0
var _currency_label: Label
var _currency_icon: Control
var _chondrule_box: HBoxContainer
var _chondrule_label: Label
var _mass_label: Label
var _stage_label: Label
var _stage_bar: Control
var _stage_progress := 0.0
var _material_labels := {}
var _comp_bar: Control
var _body_label: Label
var _heat_label: Label
var _ice_label: Label
var _zone_label: Label
var _zone_desc: Label
var _zone_name := ""
var _wind_label: Label
var _disc_map := Control.new()  # полоска диска от звезды наружу: где какое вещество
var _map_dist := 0.0
var _map_rings := 0.0  # видимость колец-ловушек на карте (появляются у гальки)
var _map_tex: ImageTexture
var _map_drawn := Vector2(-1.0, -1.0)  # положение метки и видимость колец при последней отрисовке
const MAP_RANGE := Vector2(2600.0, 12500.0)
const MAP_SIZE := Vector2(250.0, 36.0)
var _heat_time := 0.0
var _body_desc: Label
var _tree_button: Button
var _badge: Control
var menu_button: Button
var _last_currency := 0.0
var _bump_tween: Tween
var _time := 0.0
var _arrow_visible := false
var _shown_currency := 0.0   # число на экране плавно догоняет настоящее
var _shown_progress := 0.0   # так же плавно растёт полоса стадии
var _spark: Control          # золотая искра на книге после покупки навыка
var _spark_t := -1.0
var _spark_pending := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.get_theme()
	_build()
	_fps_label = Label.new()
	_fps_label.add_theme_font_size_override("font_size", 13)
	_fps_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	_fps_label.position = Vector2(12.0, 300.0)
	_fps_label.visible = false
	add_child(_fps_label)
	_last_currency = GameState.currency
	_shown_currency = GameState.currency
	GameState.skills_changed.connect(func(): _spark_pending = true)
	GameState.currency_changed.connect(_on_currency_changed)
	GameState.chondrules_changed.connect(_on_chondrules_changed)
	_on_chondrules_changed(GameState.chondrules)
	# Масса меняется почти каждый кадр (рост, тающий лёд): подписи обновляем
	# не чаще REFRESH_EVERY, а не на каждый сигнал.
	GameState.mass_changed.connect(func(_m): _refresh_pending = true)
	GameState.skills_changed.connect(_refresh)
	_refresh()
	_shown_progress = _stage_progress


const REFRESH_EVERY := 0.1
var _refresh_pending := false
var _refresh_t := 0.0
var _body_col := Color(0, 0, 0, 0)


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
	# Хондры — вторая валюта для способностей; видно, когда первая уже найдена.
	_chondrule_box = HBoxContainer.new()
	_chondrule_box.add_theme_constant_override("separation", 6)
	_chondrule_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bead_gap := Control.new()
	bead_gap.custom_minimum_size = Vector2(14, 0)
	bead_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chondrule_box.add_child(bead_gap)
	var bead := Control.new()
	bead.custom_minimum_size = Vector2(22, 46)
	bead.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bead.draw.connect(func() -> void: UiTheme.draw_chondrule(bead, bead.size * 0.5 + Vector2(0, 2), 9.0))
	_chondrule_box.add_child(bead)
	_chondrule_label = _label(28, UiTheme.CHONDRULE, UiTheme.FONT_NUMBERS)
	_chondrule_box.add_child(_chondrule_label)
	cur_row.add_child(_chondrule_box)
	_mass_label = _label(16, UiTheme.TEXT_DIM, UiTheme.FONT_SEMI)
	_mass_label.custom_minimum_size = Vector2(0, 0)
	var mass_pad := MarginContainer.new()
	mass_pad.add_theme_constant_override("margin_left", 44)
	mass_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mass_pad.add_child(_mass_label)
	left.add_child(mass_pad)

	# Зона диска, где сейчас игрок: от неё зависит, какая пыль вокруг.
	var zone_pad := MarginContainer.new()
	zone_pad.add_theme_constant_override("margin_left", 6)
	zone_pad.add_theme_constant_override("margin_top", 14)
	zone_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(zone_pad)
	var zone_box := VBoxContainer.new()
	zone_box.add_theme_constant_override("separation", -2)
	zone_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zone_pad.add_child(zone_box)
	_zone_label = _label(17, UiTheme.TEXT, UiTheme.FONT_SEMI)
	zone_box.add_child(_zone_label)
	_zone_desc = _label(13, UiTheme.TEXT_DIM)
	zone_box.add_child(_zone_desc)
	var map_pad := MarginContainer.new()
	map_pad.add_theme_constant_override("margin_top", 8)
	map_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_disc_map.custom_minimum_size = MAP_SIZE
	_disc_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_disc_map.draw.connect(_draw_disc_map)
	map_pad.add_child(_disc_map)
	zone_box.add_child(map_pad)
	# У гальки: встречный ветер газа и снос к звезде.
	_wind_label = _label(14, Color(0.75, 0.88, 1.0), UiTheme.FONT_SEMI)
	_wind_label.visible = false
	var wind_pad := MarginContainer.new()
	wind_pad.add_theme_constant_override("margin_top", 6)
	wind_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wind_pad.add_child(_wind_label)
	zone_box.add_child(wind_pad)

	# Сверху по центру: стадия, прогресс до следующей, состав тела.
	var top := VBoxContainer.new()
	top.anchor_left = 0.5
	top.anchor_right = 0.5
	top.offset_left = -TOP_WIDTH * 0.5
	top.offset_right = TOP_WIDTH * 0.5
	top.offset_top = 12
	# Длинная строка расширяет колонку в обе стороны, а полоски стадии и
	# состава остаются фиксированной ширины.
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.add_theme_constant_override("separation", 4)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	_stage_label = _label(15, UiTheme.TEXT, UiTheme.FONT_SEMI)
	_stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_stage_label)
	_stage_bar = Control.new()
	_stage_bar.custom_minimum_size = Vector2(TOP_WIDTH, 5)
	_stage_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_stage_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_bar.draw.connect(_draw_stage_bar)
	top.add_child(_stage_bar)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 3)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(gap)
	_comp_bar = Control.new()
	_comp_bar.custom_minimum_size = Vector2(TOP_WIDTH, 7)
	_comp_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
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

	# Нагрев у звезды: видно только в горячей зоне.
	_heat_label = _label(15, Color(1.0, 0.6, 0.3), UiTheme.FONT_SEMI)
	_heat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heat_label.visible = false
	top.add_child(_heat_label)
	# Испарение льда — своя строка: при нагреве обе видны сразу.
	_ice_label = _label(13, Color(0.6, 0.82, 1.0), UiTheme.FONT_SEMI)
	_ice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ice_label.visible = false
	top.add_child(_ice_label)

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
	_spark = Control.new()
	_spark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_spark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spark.draw.connect(_draw_spark)
	_tree_button.add_child(_spark)

	# Меню паузы: три золотые черты под книгой.
	menu_button = Button.new()
	menu_button.flat = true
	menu_button.anchor_left = 1.0
	menu_button.anchor_right = 1.0
	menu_button.offset_left = -86
	menu_button.offset_right = -38
	menu_button.offset_top = 108
	menu_button.offset_bottom = 152
	menu_button.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		menu_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	menu_button.draw.connect(_draw_menu_icon)
	menu_button.button_down.connect(func(): _press_anim(menu_button, 0.9))
	menu_button.button_up.connect(func(): _press_anim(menu_button, 1.0))
	menu_button.pressed.connect(func(): menu_requested.emit())
	add_child(menu_button)


func _draw_menu_icon() -> void:
	var c := menu_button.size * 0.5
	menu_button.draw_circle(c, 21.0, Color(0.05, 0.03, 0.1, 0.45))
	menu_button.draw_arc(c, 21.0, 0.0, TAU, 48, Color(UiTheme.GOLD, 0.55), 1.5, true)
	for i in 3:
		var y := c.y + (i - 1) * 7.0
		menu_button.draw_line(Vector2(c.x - 9, y), Vector2(c.x + 9, y), Color(UiTheme.GOLD, 0.9), 2.5, true)


func _press_anim(button: Control, target: float) -> void:
	button.pivot_offset = button.size * 0.5
	var tw := create_tween()
	tw.tween_property(button, "scale", Vector2.ONE * target, 0.08)


func set_zone(zone: Dictionary) -> void:
	if zone.name == _zone_name:
		return
	var first := _zone_name == ""
	_zone_name = zone.name
	_zone_label.text = zone.name
	_zone_label.add_theme_color_override("font_color", zone.color)
	_zone_desc.text = zone.desc
	if not first:
		# Новая зона: подпись вспыхивает и плавно возвращается.
		_zone_label.modulate = Color(2.0, 2.0, 2.0)
		create_tween().tween_property(_zone_label, "modulate", Color.WHITE, 1.2)


## Встречный ветер у гальки: сила сноса к звезде или затишье в ловушке давления.
func set_wind(drift: Vector2, pos: Vector2, pebble_k: float, shadow := 0.0) -> void:
	_map_dist = pos.length()
	_map_rings = pebble_k
	# Перерисовываем карту, только когда метка сдвинулась хотя бы на полпикселя.
	var state := Vector2(_map_x(_map_dist), _map_rings)
	if absf(state.x - _map_drawn.x) > 0.5 or absf(state.y - _map_drawn.y) > 0.02:
		_map_drawn = state
		_disc_map.queue_redraw()
	_wind_label.visible = pebble_k > 0.5
	if not _wind_label.visible:
		return
	var radial := -drift.dot(pos.normalized())  # > 0 — сносит к звезде
	if GameData.trap_strength(pos.length()) > 0.6:
		_set_wind_text("Ловушка давления: затишье", Color(0.7, 1.0, 0.75))
	elif shadow > 0.4:
		_set_wind_text("Ветровая тень: снос слабее на %d%%" % roundi(PebbleField.SHADOW_CALM * shadow * 100.0), Color(0.7, 1.0, 0.75))
	elif radial > 0.0:
		_set_wind_text("Встречный ветер: снос к звезде %d м/с" % roundi(radial), Color(0.75, 0.88, 1.0))
	else:
		_set_wind_text("Газ выносит к кольцу: %d м/с" % roundi(-radial), Color(0.7, 1.0, 0.75))


## Смена цвета пересобирает тему подписи: делаем это, только когда цвет и правда меняется.
func _set_wind_text(text: String, col: Color) -> void:
	_wind_label.text = text
	if _wind_label.get_theme_color("font_color") != col:
		_wind_label.add_theme_color_override("font_color", col)


func set_temperature(temp: float) -> void:
	_heat_label.visible = temp > GameData.SPACE_TEMP + 100.0
	if not _heat_label.visible:
		return
	var state := "нагрев"
	if temp >= GameData.SUBLIMATION_TEMP:
		state = "испарение! улетай от звезды"
	elif temp >= GameData.GLOW_TEMP:
		state = "раскаляется"
	_heat_label.text = "%d K · %s" % [roundi(temp / 10.0) * 10, state]
	var col := GameData.thermal_color(temp)
	# Тёмно-красный цвет каления на тёмном фоне не читается: подсветляем.
	var base := Color(col.r, col.g, col.b).lerp(Color(1.0, 0.8, 0.6), 0.45) if col.a > 0.0 else Color(1.0, 0.75, 0.5)
	if temp >= GameData.SUBLIMATION_TEMP:
		# Мигает, пока пылинка тает.
		_heat_time += get_process_delta_time()
		base = base.lerp(Color.WHITE, 0.35 * (0.5 + 0.5 * sin(_heat_time * 8.0)))
	_heat_label.add_theme_color_override("font_color", base)


## Отдельная строка: лёд тает внутри снеговой линии.
func set_ice_vapor(rate: float) -> void:
	_ice_label.visible = rate > 0.0
	if rate <= 0.0:
		return
	_ice_label.text = "Лёд испаряется: −%.1f%% льда в минуту · за снеговую линию" % (rate * 60.0 / maxf(GameState.materials.get("ice", 0.0), 0.001) * 100.0)


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
func _on_chondrules_changed(value: int) -> void:
	_chondrule_box.visible = value > 0
	_chondrule_label.text = str(value)


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


## Вызывается при закрытии древа: если что-то купили, книга вспыхивает искрой.
func play_purchase_spark() -> void:
	if _spark_pending:
		_spark_pending = false
		_spark_t = 0.0


func _refresh() -> void:
	_refresh_pending = false
	_refresh_t = REFRESH_EVERY
	_mass_label.text = "масса %s · %s" % [GameData.format_mass(GameState.mass), GameData.format_size(GameState.mass)]
	var idx := maxi(GameData.stage_index(GameState.mass), GameState.stage)
	var stage: Dictionary = GameData.STAGES[idx]
	if idx + 1 < GameData.STAGES.size():
		var next: Dictionary = GameData.STAGES[idx + 1]
		_stage_label.text = "%s → %s" % [stage.name, next.name]
		# Рост экспоненциальный, поэтому шкала этапа логарифмическая.
		if stage.mass > 0.0:
			var lo := log(stage.mass)
			_stage_progress = clampf((log(maxf(GameState.mass, 1.0)) - lo) / (log(next.mass) - lo), 0.0, 1.0)
		else:
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
	var body_col: Color = GameData.MATERIALS[type].color if GameData.MATERIALS.has(type) else UiTheme.TEXT
	if body_col != _body_col:
		# Смена цвета темы пересчитывает стиль подписи: только когда он и правда другой.
		_body_col = body_col
		_body_label.add_theme_color_override("font_color", body_col)
	_body_desc.text = "· " + body.desc
	if GameState.is_boulder() and GameData.BOULDER_MATERIAL.has(type):
		_body_desc.text = "· валуну: " + GameData.BOULDER_MATERIAL[type].text
	_comp_bar.queue_redraw()
	_stage_bar.queue_redraw()
	_badge.visible = Skills.any_affordable()


## Полоска диска не меняется за игру: печём её в текстуру один раз, а не рисуем
## каждый кадр 240 прямоугольниками.
func _bake_disc_map() -> ImageTexture:
	var steps := 120
	var h := 24
	var img := Image.create(steps, h, false, Image.FORMAT_RGBA8)
	for i in steps:
		var dist := MAP_RANGE.x + (i + 0.5) / steps * (MAP_RANGE.y - MAP_RANGE.x)
		# Столбик делится по долям материалов: видно, чего здесь больше.
		var weights := GameData.material_weights(dist)
		var total := 0.0
		for key in weights:
			total += weights[key]
		var yy := 0.0
		for key in GameData.MATERIAL_ORDER:
			if not weights.has(key):
				continue
			var hh: float = h * weights[key] / total
			var col: Color = GameData.MATERIALS[key].color
			if dist < GameData.sublimation_distance():
				col = col.lerp(Color(1.0, 0.35, 0.1), 0.75)
			for py in range(roundi(yy), mini(roundi(yy + hh), h)):
				img.set_pixel(i, py, Color(col, 0.9))
			yy += hh
	return ImageTexture.create_from_image(img)


func _map_x(dist: float) -> float:
	return clampf((dist - MAP_RANGE.x) / (MAP_RANGE.y - MAP_RANGE.x), 0.0, 1.0) * MAP_SIZE.x


## Карта диска: полоса окрашена в цвета вещества, которое водится на этом расстоянии.
## Слева звезда и зона испарения, отметка снеговой линии, кольца-ловушки, маркер «ты здесь».
func _draw_disc_map() -> void:
	var h := 12.0
	var y := 12.0
	if _map_tex == null:
		_map_tex = _bake_disc_map()
	_disc_map.draw_texture_rect(_map_tex, Rect2(0, y, MAP_SIZE.x, h), false)
	_disc_map.draw_rect(Rect2(0, y, MAP_SIZE.x, h), Color(1, 1, 1, 0.25), false, 1.0)
	var font: Font = UiTheme.FONT_SEMI
	# Снеговая линия.
	var sx := _map_x(GameData.SNOW_LINE)
	_disc_map.draw_line(Vector2(sx, y - 3), Vector2(sx, y + h + 3), Color(0.85, 0.95, 1.0), 1.5)
	_disc_map.draw_string(font, Vector2(sx + 3, y + h + 12), "снеговая линия", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.8, 0.9, 1.0, 0.75))
	_disc_map.draw_string(font, Vector2(0, y + h + 12), "← звезда", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.75, 0.5, 0.75))
	if _map_rings > 0.01:
		for ring in GameData.PRESSURE_RINGS:
			var rx := _map_x(ring)
			_disc_map.draw_circle(Vector2(rx, y + h * 0.5), 2.2, Color(0.9, 1.0, 0.75, 0.8 * _map_rings))
	# Ты здесь.
	var px := _map_x(_map_dist)
	var marker := PackedVector2Array([Vector2(px, y - 1), Vector2(px - 5, y - 9), Vector2(px + 5, y - 9)])
	_disc_map.draw_colored_polygon(marker, UiTheme.GOLD)


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
	if _shown_progress > 0.001:
		var fw := maxf(rect.size.x * _shown_progress, 6.0)
		var fill := Rect2(rect.position, Vector2(fw, rect.size.y))
		UiTheme.pill(UiTheme.ICE, 3).draw(_stage_bar.get_canvas_item(), fill)
		# По заполненной части пробегает отблеск света.
		var band := 40.0
		var x := fmod(_time * 90.0, fw + band * 3.0) - band
		var x0 := clampf(x - band, 0.0, fw)
		var x1 := clampf(x, 0.0, fw)
		var x2 := clampf(x + band, 0.0, fw)
		var h := rect.size.y
		var clear := Color(1, 1, 1, 0.0)
		var bright := Color(1, 1, 1, 0.75)
		if x1 > x0:
			_stage_bar.draw_polygon(PackedVector2Array([Vector2(x0, 0), Vector2(x1, 0), Vector2(x1, h), Vector2(x0, h)]),
				PackedColorArray([clear, bright, bright, clear]))
		if x2 > x1:
			_stage_bar.draw_polygon(PackedVector2Array([Vector2(x1, 0), Vector2(x2, 0), Vector2(x2, h), Vector2(x1, h)]),
				PackedColorArray([bright, clear, clear, bright]))


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


## Искра покупки: вспыхивает над книгой, разлетается лучами и гаснет.
func _draw_spark() -> void:
	if _spark_t < 0.0:
		return
	var k := _spark_t
	var c := _spark.size * 0.5
	var a := 1.0 - k
	_spark.draw_circle(c, 10.0 + 50.0 * k, Color(UiTheme.GOLD, 0.25 * a))
	_spark.draw_arc(c, 8.0 + 46.0 * k, 0.0, TAU, 40, Color(1.0, 0.9, 0.6, 0.8 * a), 2.0, true)
	var r := 26.0 * sin(minf(k * 2.0, 1.0) * PI * 0.5) * (1.0 - k * 0.5)
	var w := 4.0 * a + 1.0
	var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(w, -w), c + Vector2(r, 0), c + Vector2(w, w),
		c + Vector2(0, r), c + Vector2(-w, w), c + Vector2(-r, 0), c + Vector2(-w, -w)])
	_spark.draw_colored_polygon(pts, Color(1.0, 0.95, 0.75, a))
	for i in 8:
		var d := Vector2.from_angle(i * TAU / 8.0 + 0.2)
		var p := c + d * (14.0 + 40.0 * k)
		_spark.draw_circle(p, 2.5 * a + 0.5, Color(UiTheme.GOLD, a))


func _draw_badge() -> void:
	var c := _badge.size * 0.5
	var k := 0.5 + 0.5 * sin(_time * 4.0)
	_badge.draw_circle(c, 7.0 + 4.0 * k, Color(UiTheme.GOLD_DEEP, 0.25 * (1.0 - k)))
	_badge.draw_circle(c, 6.0, UiTheme.GOLD)


func _process(delta: float) -> void:
	_time += delta
	_refresh_t -= delta
	if _refresh_pending and _refresh_t <= 0.0:
		_refresh()
	_fps_label.visible = show_fps
	if show_fps:
		_fps_worst = maxf(_fps_worst, delta)
		_fps_t += delta
		if _fps_t > 1.0:
			var cs := get_tree().current_scene
			var pf: Variant = cs.get("pebble_field") if cs else null
			_fps_label.text = "FPS %d · худший кадр %d мс · скрипты %.1f мс · вызовов %d · гальки %d" % [
				Engine.get_frames_per_second(), int(_fps_worst * 1000.0),
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				pf.pebbles.size() if pf else 0]
			_fps_t = 0.0
			_fps_worst = 0.0
	_currency_icon.queue_redraw()
	# Валюта «докручивается» до нового значения, полоса стадии плавно растёт.
	var target := GameState.currency
	if absf(target - _shown_currency) < 0.05:
		_shown_currency = target
	else:
		_shown_currency = lerpf(_shown_currency, target, 1.0 - exp(-8.0 * delta))
	_currency_label.text = GameData.format_number(_shown_currency)
	_shown_progress = lerpf(_shown_progress, _stage_progress, 1.0 - exp(-5.0 * delta))
	_stage_bar.queue_redraw()
	if _spark_t >= 0.0:
		_spark_t += delta
		_spark.queue_redraw()
		if _spark_t > 1.0:
			_spark_t = -1.0
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
