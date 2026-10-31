class_name Hud
extends Control
## Интерфейс поверх игры без подложек: валюта и масса слева, стадия и состав
## сверху по центру, звёздная книга (древо) и меню справа, указатель на звезду.

signal tree_requested
signal menu_requested

const TOP_WIDTH := 380.0
const BOOK_ICON := preload("res://assets/ui/book.png")

var star_screen_pos := Vector2.ZERO
var cluster_screen_pos := Vector2.INF  # скопление пыли за краем экрана (ставит main)
var cluster_material := ""
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
var _planet_label: Label  # планетезималь: рой (пока строкой)
var _core_box: HBoxContainer  # медальон недр: разрез тела и подписи
var _core_icon: Control
var _core_title: Label
var _core_value: Label
var _core_sub: Label
var _core_flash := 0.0   # вспышка в момент плавления
var _core_was_melted := false
var _map_depl := -1.0    # выеденность кормовой полосы на карте
var _map_temp := -1.0    # жар поверхности: им светится метка на карте (планетезималь)
var _swarm_heat := 0.0
var _swarm_capture := 1.0
var _disc_map := Control.new()  # полоска диска от звезды наружу: где какое вещество
var _map_dist := 0.0
var _map_rings := 0.0  # видимость колец-ловушек на карте (появляются у гальки)
var _map_tex: ImageTexture
var _map_drawn := Vector2(-1.0, -1.0)  # положение метки и видимость колец при последней отрисовке
const MAP_RANGE := Vector2(2600.0, 12500.0)
const MAP_SIZE := Vector2(250.0, 36.0)
const CORE_R := 28.0     # радиус медальона недр
const SWARM_ORBIT := Vector2(8.0, 22.0)  # орбита роя за кольцом: при захвате ×1.3 и ×6
const FEED_DOTS := 5     # точки корма на полосе карты
var _heat_time := 0.0
var _body_desc: Label
var _tree_button: Button
var _badge: Control
var menu_button: Button
var _last_currency := 0.0
var _bump_tween: Tween
var _time := 0.0
var _desc_key := ""      # тип тела и этап: при смене бонус показываем заново
var _desc_until := 0.0
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
	_zone_desc = _label(14, UiTheme.TEXT_DIM)
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
	# Планетезималь: медальон недр — разрез твоего тела.
	_core_box = HBoxContainer.new()
	_core_box.add_theme_constant_override("separation", 10)
	_core_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_core_box.visible = false
	var core_pad := MarginContainer.new()
	core_pad.add_theme_constant_override("margin_top", 10)
	core_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	core_pad.add_child(_core_box)
	zone_box.add_child(core_pad)
	_core_icon = Control.new()
	_core_icon.custom_minimum_size = Vector2.ONE * (CORE_R + 6.0 + SWARM_ORBIT.y + 6.0) * 2.0
	_core_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_core_icon.draw.connect(_draw_core)
	_core_box.add_child(_core_icon)
	var core_text := VBoxContainer.new()
	core_text.alignment = BoxContainer.ALIGNMENT_CENTER
	core_text.add_theme_constant_override("separation", -3)
	core_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_core_box.add_child(core_text)
	_core_title = _label(15, UiTheme.TEXT, UiTheme.FONT_SEMI)
	core_text.add_child(_core_title)
	_core_value = _label(24, UiTheme.GOLD, UiTheme.FONT_NUMBERS)
	core_text.add_child(_core_value)
	_core_sub = _label(14, UiTheme.TEXT_DIM, UiTheme.FONT_SEMI)
	core_text.add_child(_core_sub)
	_planet_label = _label(14, Color(0.85, 0.9, 1.0), UiTheme.FONT_SEMI)
	_planet_label.visible = false
	core_text.add_child(_planet_label)

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
	_stage_label = _label(17, UiTheme.TEXT, UiTheme.FONT_SEMI)
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
		var l := _label(15, GameData.MATERIALS[key].color)
		mats.add_child(l)
		_material_labels[key] = l
	var body_row := HBoxContainer.new()
	body_row.alignment = BoxContainer.ALIGNMENT_CENTER
	body_row.add_theme_constant_override("separation", 6)
	body_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(body_row)
	_body_label = _label(16, UiTheme.TEXT, UiTheme.FONT_SEMI)
	body_row.add_child(_body_label)
	_body_desc = _label(14, UiTheme.TEXT_DIM)
	body_row.add_child(_body_desc)

	# Нагрев у звезды: видно только в горячей зоне.
	_heat_label = _label(15, Color(1.0, 0.6, 0.3), UiTheme.FONT_SEMI)
	_heat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heat_label.visible = false
	top.add_child(_heat_label)
	# Испарение льда — своя строка: при нагреве обе видны сразу.
	_ice_label = _label(15, Color(0.6, 0.82, 1.0), UiTheme.FONT_SEMI)
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
	_wind_label.visible = pebble_k > 0.5 and not GameState.is_planet()
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


## Планетезималь: медальон недр, раскачка роя, выеденность полосы на карте.
func set_planet(on: bool, heat: float, capture: float, depletion: float) -> void:
	_core_box.visible = on
	_planet_label.visible = on
	if not on:
		return
	if absf(depletion - _map_depl) > 0.01:
		_map_depl = depletion
		_disc_map.queue_redraw()
	if GameState.is_melted and not _core_was_melted:
		_core_flash = 1.0
	_core_was_melted = GameState.is_melted
	if GameState.is_embryo() and GameState.gas_left >= 0.0:
		_set_embryo_text()
	elif GameState.is_melted:
		_set_core_text("Железное ядро", "%d%% массы" % roundi(GameState.core_share * 100.0), GameData.core_note(GameState.core_share), UiTheme.GOLD)
	elif GameState.core_too_cold():
		_set_core_text("Недра остыли", "хондрит", "хондры ×2", UiTheme.CHONDRULE)
	else:
		var t := GameState.core_temp()
		var melt := GameState.melt_t()
		var cool := GameState.core_cooling()
		# Лёд уносит тепло: видно, насколько выше порог из-за воды в недрах.
		var sub := "плавится при %d K" % (roundi(melt / 10.0) * 10)
		if cool >= 10.0:
			sub += " · лёд +%d K" % (roundi(cool / 10.0) * 10)
		_set_core_text("Недра · греет алюминий", "%d K" % (roundi(t / 10.0) * 10), sub, UiTheme.GOLD)
	_swarm_heat = heat
	_swarm_capture = capture
	# Чем спокойнее рой, тем шире круг захвата: показываем, во сколько раз.
	var swarm := "рой спокоен · захват ×%.1f" % capture if heat < 0.3 \
		else "рой взбудоражен %d%% · захват ×%.1f" % [roundi(heat * 100.0), capture]
	if _planet_label.text != swarm:
		_planet_label.text = swarm
		_planet_label.add_theme_color_override("font_color", Color(0.5, 0.92, 0.82).lerp(Color(1.0, 0.65, 0.4), clampf(heat, 0.0, 1.0)))


## Зародыш: медальон показывает гонку с газом диска.
var second_chance := -1.0  # секунд второго шанса суперземли (ставит main), <0 — нет


func _set_embryo_text() -> void:
	var e := GameState.earth_masses()
	if second_chance >= 0.0:
		_set_core_text("Второй шанс · %s" % _clock(second_chance), "нырни в гиганта", "или останься: %s" % GameData.ENDINGS[GameData.super_earth_ending(GameState.fate_type())]["name"], UiTheme.GOLD)
	elif GameState.gas_left > 0.0:
		var goal := "планета — с массы Земли" if GameState.planet_route() else "гигант — с %d масс Земли" % roundi(GameData.GIANT_EARTHS)
		_set_core_text("Газ диска · %s" % _clock(GameState.gas_left), GameData.format_earths(GameState.mass),
			goal, Color(0.6, 0.9, 1.0) if e < GameData.SUPER_EARTHS else UiTheme.GOLD)
	else:
		_set_core_text("Газ рассеялся", GameData.format_earths(GameState.mass), "каменная планета", UiTheme.PARCHMENT)


static func _clock(t: float) -> String:
	var sec := ceili(maxf(t, 0.0))
	return "%d:%02d" % [sec / 60, sec % 60]


func _set_core_text(title: String, value: String, sub: String, col: Color) -> void:
	if _core_title.text != title:
		_core_title.text = title
	if _core_value.text != value:
		_core_value.text = value
		_core_value.add_theme_color_override("font_color", col)
	if _core_sub.text != sub:
		_core_sub.text = sub


## Медальон недр: разрез тела. Пока греется — светящееся ядро и кольцо с искрой,
## ползущей к температуре плавления; расплавился — железный шар в центре;
## остыл — хондры в толще камня.
func _draw_core() -> void:
	var ci := _core_icon
	var c := ci.size * 0.5
	var r := CORE_R
	var ring := r + 6.0
	ci.draw_arc(c, ring, 0.0, TAU, 64, Color(1, 1, 1, 0.12), 3.0, true)
	var melted := GameState.is_melted
	var cold := not melted and GameState.core_too_cold()
	var t := GameState.core_temp()
	var prog := clampf((t - GameData.CORE_COLD) / (GameState.melt_t() - GameData.CORE_COLD), 0.0, 1.0)
	if GameState.is_embryo() and GameState.gas_left >= 0.0:
		# Кольцо газа диска: тает по часовой, как песочные часы гонки.
		var gas := GameState.gas_frac() if second_chance < 0.0 else second_chance / GameData.SECOND_CHANCE_TIME
		var gas_col := Color(0.55, 0.85, 1.0) if second_chance < 0.0 else UiTheme.GOLD
		if gas > 0.0:
			ci.draw_arc(c, ring, -PI * 0.5, -PI * 0.5 + gas * TAU, maxi(int(64 * gas), 3), Color(gas_col, 0.85), 3.0, true)
			var tip := c + Vector2.from_angle(-PI * 0.5 + gas * TAU) * ring
			ci.draw_circle(tip, 3.2, Color(gas_col.lightened(0.5), 0.95))
	elif melted:
		ci.draw_arc(c, ring, 0.0, TAU, 64, Color(UiTheme.GOLD, 0.9), 3.0, true)
	elif cold:
		ci.draw_arc(c, ring, 0.0, TAU, 64, Color(UiTheme.CHONDRULE, 0.8), 3.0, true)
	else:
		# Кольцо от холодного синего к раскалённому: путь до плавления.
		var steps := maxi(int(48.0 * prog), 1)
		var a0 := -PI * 0.5
		for i in steps:
			var f0 := float(i) / steps * prog
			var f1 := float(i + 1) / steps * prog
			ci.draw_arc(c, ring, a0 + f0 * TAU, a0 + f1 * TAU + 0.02, 3, _core_color(f1), 3.0, true)
		var tip := c + Vector2.from_angle(a0 + prog * TAU) * ring
		ci.draw_circle(tip, 6.0, Color(1.0, 0.75, 0.4, 0.25))
		ci.draw_circle(tip, 3.2, Color(1.0, 0.95, 0.8))
		UiTheme.draw_spark(ci, c + Vector2(0, -ring), 5.0, Color(UiTheme.GOLD, 0.9))
	_draw_swarm(c, ring)
	# Каменная кора: тёмный диск со светлым бликом и вкраплениями.
	ci.draw_circle(c, r, Color(0.24, 0.18, 0.14))
	ci.draw_circle(c + Vector2(-0.15, -0.15) * r, r * 0.82, Color(0.36, 0.29, 0.23))
	ci.draw_circle(c + Vector2(-0.3, -0.3) * r, r * 0.45, Color(0.45, 0.37, 0.3, 0.6))
	for i in 26:
		var a := i * 2.39996
		var d := r * 0.92 * sqrt(fposmod(i * 0.377, 1.0))
		var dark := i % 3 != 0
		ci.draw_circle(c + Vector2.from_angle(a) * d, 0.9 + (i % 4) * 0.45,
			Color(0.12, 0.09, 0.07, 0.45) if dark else Color(0.7, 0.62, 0.52, 0.35))
	var pulse := 0.5 + 0.5 * sin(_time * 2.4)
	if melted:
		# Железо собралось в центре; вокруг ещё светится остывающая магма.
		var fe := r * (0.3 + 0.35 * clampf(GameState.core_share / 0.4, 0.0, 1.0))
		ci.draw_circle(c, fe * 1.5, Color(1.0, 0.55, 0.25, 0.18 + 0.08 * pulse))
		ci.draw_circle(c, fe, Color(0.35, 0.39, 0.48))
		ci.draw_circle(c + Vector2(-0.1, -0.1) * fe, fe * 0.82, Color(0.62, 0.67, 0.76))
		ci.draw_circle(c + Vector2(-0.35, -0.35) * fe, fe * 0.3, Color(0.95, 0.97, 1.0, 0.9))
		# Капли железа ещё тонут к центру.
		for i in 4:
			var ph := fposmod(_time * 0.25 + i * 0.25, 1.0)
			var a := i * 1.7 + 0.4
			var p := c + Vector2.from_angle(a) * lerpf(r * 0.85, fe, ph)
			ci.draw_circle(p, 1.8, Color(0.75, 0.8, 0.88, 1.0 - ph))
	elif cold:
		for i in 8:
			var a := i * 2.1 + 0.3
			var d := r * (0.2 + 0.6 * fposmod(i * 0.53, 1.0))
			UiTheme.draw_chondrule(ci, c + Vector2.from_angle(a) * d, 2.6 + (i % 3) * 0.9)
	else:
		# Ядро греется: свечение растёт с температурой и дышит.
		var glow := lerpf(0.25, 0.75, prog) * r
		var col := _core_color(prog)
		for k in 6:
			var f := 1.0 - k / 6.0
			ci.draw_circle(c, glow * (0.35 + 0.65 * f) * (1.0 + 0.05 * pulse), Color(col, 0.12 + 0.1 * (1.0 - f)))
		ci.draw_circle(c, glow * 0.3, Color(1.0, 0.92, 0.7, 0.6 + 0.3 * prog))
		# Жилки жара расходятся от ядра.
		for k in 6:
			var a := k * 1.047 + _time * 0.1
			var pts := PackedVector2Array()
			for j in 5:
				var f := j / 4.0
				pts.append(c + Vector2.from_angle(a + 0.35 * f) * lerpf(glow * 0.4, r * 0.85, f))
			ci.draw_polyline(pts, Color(1.0, 0.65, 0.3, 0.25 + 0.35 * prog), 1.2, true)
	ci.draw_arc(c, r, 0.0, TAU, 48, Color(0, 0, 0, 0.45), 1.5, true)
	if _core_flash > 0.0:
		ci.draw_circle(c, ring + 8.0 * (1.0 - _core_flash), Color(1.0, 0.9, 0.6, 0.5 * _core_flash))


## Рой — камешки на орбите вокруг медальона. Радиус орбиты — круг захвата.
## Спокойный рой кружит ровно; взбудораженный — орбиты вытягиваются, камни
## дёргаются и оставляют рыжие штрихи.
func _draw_swarm(c: Vector2, ring: float) -> void:
	var ci := _core_icon
	var heat := clampf(_swarm_heat, 0.0, 1.0)
	var col := UiTheme.CHONDRULE.lerp(Color(1.0, 0.6, 0.32), heat)
	var k := clampf((_swarm_capture - 1.3) / 4.7, 0.0, 1.0)
	var rr := ring + lerpf(SWARM_ORBIT.x, SWARM_ORBIT.y, k)
	var n := 40
	for i in n:
		if i % 2 == 0:
			var a := TAU * i / n
			ci.draw_arc(c, rr, a, a + TAU / n, 2, Color(col, 0.35), 1.0, true)
	var spin := _time * lerpf(0.35, 0.9, heat)
	for i in 12:
		var a := TAU * i / 12.0 + spin
		var e := heat * (0.12 + 0.08 * sin(i * 1.7))
		var d := rr * (1.0 + e * sin(a * 2.0 + i))
		var jit := Vector2(sin(_time * 13.0 + i * 5.0), cos(_time * 11.0 + i * 7.0)) * 1.8 * heat
		var p := c + Vector2.from_angle(a) * d + jit
		if heat > 0.1:
			var tang := Vector2.from_angle(a + PI * 0.5)
			ci.draw_line(p, p - tang * 8.0 * heat, Color(col, 0.55), 1.3, true)
		var pr := 1.7 + (i % 3) * 0.5
		ci.draw_circle(p, pr, Color(0.84, 0.77, 0.67) if i % 3 else Color(0.67, 0.59, 0.5))


## Цвет нагрева недр: от холодного синего через багровый к белому калению.
static func _core_color(f: float) -> Color:
	var stops := [Color(0.35, 0.5, 0.9), Color(0.8, 0.25, 0.15), Color(1.0, 0.55, 0.2), Color(1.0, 0.95, 0.75)]
	var x := clampf(f, 0.0, 1.0) * (stops.size() - 1)
	var i := mini(int(x), stops.size() - 2)
	return (stops[i] as Color).lerp(stops[i + 1], x - i)


static func _num(v: float) -> String:
	return "%.1f" % v if v < 10.0 else str(roundi(v))


## Смена цвета пересобирает тему подписи: делаем это, только когда цвет и правда меняется.
func _set_wind_text(text: String, col: Color) -> void:
	_wind_label.text = text
	if _wind_label.get_theme_color("font_color") != col:
		_wind_label.add_theme_color_override("font_color", col)


func set_temperature(temp: float) -> void:
	# У планетезимали жар показывает метка на карте диска; строка — только в опасности.
	var on_map := _core_box.visible
	if on_map and absf(temp - _map_temp) > 5.0:
		_map_temp = temp
		_disc_map.queue_redraw()
	elif not on_map:
		_map_temp = -1.0
	_heat_label.visible = temp > (GameData.GLOW_TEMP if on_map else GameData.SPACE_TEMP + 100.0)
	if not _heat_label.visible:
		return
	var state := "нагрев"
	if temp >= GameData.SUBLIMATION_TEMP:
		state = "испарение! улетай от звезды"
	elif temp >= GameData.GLOW_TEMP:
		state = "раскаляется"
	_heat_label.text = "Поверхность: %d K (греет звезда) · %s" % [roundi(temp / 10.0) * 10, state]
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
	var pct := rate * 60.0 / maxf(GameState.materials.get("ice", 0.0), 0.001) * 100.0
	_ice_label.visible = pct >= 1.0  # мелкие потери не стоят строки на экране
	if not _ice_label.visible:
		return
	_ice_label.text = "Лёд тает: −%.0f%% в минуту · уйди за снеговую линию" % pct


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
	if GameState.is_embryo():
		_mass_label.text = "масса %s · %s" % [GameData.format_earths(GameState.mass), GameData.format_size(GameState.mass)]
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
	elif GameState.is_embryo():
		# Цель пути: гиганту — 10 масс Земли, каменной планете — одна; шкала логарифмическая.
		if GameState.planet_route():
			_stage_label.text = "%s → %s: масса Земли" % [stage.name, GameData.ENDINGS[GameState.composition_ending()]["name"].to_lower()]
		else:
			_stage_label.text = "%s → газовый гигант: %d масс Земли" % [stage.name, roundi(GameData.GIANT_EARTHS)]
		var lo := log(GameData.earth_masses(stage.mass))
		_stage_progress = clampf((log(maxf(GameState.earth_masses(), 1e-6)) - lo) / (log(GameState.embryo_goal()) - lo), 0.0, 1.0)
	else:
		_stage_label.text = stage.name
		_stage_progress = 1.0
	var shares := GameData.composition(GameState.materials)
	for key in _material_labels:
		_material_labels[key].text = "● %s %d%%" % [GameData.MATERIALS[key].name, roundi(shares[key] * 100.0)]
	var type := GameState.body_type()
	# После плавления тип застыл (в старых сохранениях состав мог уплыть).
	if GameState.is_melted and GameState.melt_type != "" and GameData.planet_type(type) != GameState.melt_type:
		type = GameState.melt_type
	var body: Dictionary = GameData.BODY_TYPES[type]
	_body_label.text = body.name + (" · застыло" if GameState.is_melted else "")
	if type == "neutral":
		_body_label.text = "Переходное, ведёт %s" % GameData.MATERIALS[GameData.lead_material(GameState.materials)].name.to_lower()
	var body_col: Color = GameData.MATERIALS[type].color if GameData.MATERIALS.has(type) else body.get("color", UiTheme.TEXT)
	if body_col != _body_col:
		# Смена цвета темы пересчитывает стиль подписи: только когда он и правда другой.
		_body_col = body_col
		_body_label.add_theme_color_override("font_color", body_col)
	_body_desc.text = "· " + body.desc
	if GameState.is_planet():
		_body_desc.text = ("· зародышу: " if GameState.is_embryo() else "· планетезимали: ") + GameData.stage_material(type, GameState.is_embryo()).text
	elif GameState.is_boulder() and not GameData.boulder_material(type).is_empty():
		_body_desc.text = "· валуну: " + GameData.boulder_material(type).text
	# Бонус вещества — подсказка, а не постоянная строка: видна 10 с после смены
	# типа или этапа, дальше остаётся только название типа (полностью — в книге).
	var key := "%s/%d/%s" % [type, GameState.stage, GameState.is_melted]
	if key != _desc_key:
		_desc_key = key
		_desc_until = _time + 10.0
	_body_desc.visible = _time < _desc_until
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
	# Кормовая полоса планетезимали: подсвечена вокруг метки, точки корма гаснут.
	if _core_box.visible and _map_depl >= 0.0:
		var bin := GameData.zone_bin(_map_dist)
		var x0 := _map_x(bin * GameData.ZONE_BIN)
		var x1 := _map_x((bin + 1) * GameData.ZONE_BIN)
		var band := Rect2(x0, y - 2, maxf(x1 - x0, 4.0), h + 4)
		_disc_map.draw_rect(band, Color(UiTheme.GOLD, 0.22))
		_disc_map.draw_rect(band, Color(UiTheme.GOLD, 0.85), false, 1.0)
		var left := ceili((1.0 - _map_depl) * FEED_DOTS - 0.001)
		for i in FEED_DOTS:
			var dx := band.position.x + band.size.x * (i + 0.5) / FEED_DOTS
			var lit := i < left
			_disc_map.draw_circle(Vector2(dx, y + h * 0.5), 1.6 if lit else 1.1,
				UiTheme.GOLD if lit else Color(1, 1, 1, 0.25))
	# Ты здесь.
	var px := _map_x(_map_dist)
	var mark_col := UiTheme.GOLD
	if _map_temp > 0.0:
		# Зона испарения у звезды и метка, светящаяся жаром поверхности.
		var sub := _map_x(GameData.sublimation_distance())
		for i in 6:
			var fi := i / 6.0
			_disc_map.draw_rect(Rect2(sub * fi, y - 2, sub / 6.0 + 0.5, h + 4), Color(1.0, 0.25, 0.12, 0.75 * (1.0 - fi)))
		var f := clampf((_map_temp - GameData.SPACE_TEMP) / (GameData.SUBLIMATION_TEMP - GameData.SPACE_TEMP), 0.0, 1.0)
		mark_col = UiTheme.GOLD.lerp(Color(1.0, 0.5, 0.2), clampf(f * 2.0, 0.0, 1.0)).lerp(Color(1.0, 0.97, 0.9), clampf(f * 2.0 - 1.0, 0.0, 1.0))
		var glow := 7.0 + 12.0 * f
		for k in 4:
			_disc_map.draw_circle(Vector2(px, y + h * 0.5), glow * (1.0 - k * 0.22), Color(mark_col, 0.1 + 0.05 * k))
		_disc_map.draw_string(font, Vector2(px + 7, y - 2), "%d K" % (roundi(_map_temp / 10.0) * 10), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, mark_col)
	var marker := PackedVector2Array([Vector2(px, y - 1), Vector2(px - 5, y - 9), Vector2(px + 5, y - 9)])
	_disc_map.draw_colored_polygon(marker, mark_col)


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
	if _body_desc.visible and _time >= _desc_until:
		_body_desc.visible = false
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
	if _core_box.visible:
		_core_flash = maxf(_core_flash - delta * 0.8, 0.0)
		_core_icon.queue_redraw()
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


func _draw() -> void:
	if _arrow_visible:
		_draw_star_arrow()
	_draw_cluster_arrow()


## Скопление пыли за краем экрана: стрелка цвета его материала. Если материал
## тот же, что ведёт твоё тело, подпись говорит «твой» — состав решает, лететь ли.
func _draw_cluster_arrow() -> void:
	if cluster_screen_pos == Vector2.INF or size.x < 100.0:
		return
	var rect := Rect2(Vector2.ZERO, size).grow(-60.0)
	if rect.has_point(cluster_screen_pos):
		return
	var center := size * 0.5
	var dir := (cluster_screen_pos - center).normalized()
	var t := INF
	if absf(dir.x) > 0.001:
		t = minf(t, (rect.size.x * 0.5) / absf(dir.x))
	if absf(dir.y) > 0.001:
		t = minf(t, (rect.size.y * 0.5) / absf(dir.y))
	var tip := center + dir * t
	# Слева вверху карта зон и строки HUD: стрелку опускаем под них.
	if tip.x < 330.0 and tip.y < 220.0:
		tip.y = 220.0
	var info: Dictionary = GameData.MATERIALS.get(cluster_material, {"name": "пыль", "color": Color.WHITE})
	var mc: Color = info["color"]
	var k := 0.5 + 0.5 * sin(_time * 3.0)
	draw_circle(tip - dir * 12.0, 20.0, Color(mc, 0.10 + 0.08 * k))
	var side := dir.orthogonal()
	draw_colored_polygon(PackedVector2Array([tip, tip - dir * 20.0 + side * 10.0, tip - dir * 13.0, tip - dir * 20.0 - side * 10.0]), Color(mc, 0.7 + 0.25 * k))
	var own := GameState.body_type() != "unformed" and GameData.lead_material(GameState.materials) == cluster_material
	var text := "скопление: %s%s" % [str(info["name"]).to_lower(), " · твой" if own else ""]
	var font := UiTheme.FONT_SEMI
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var tp := tip - dir * 44.0 + Vector2(-tw * 0.5, 5.0)
	tp.x = clampf(tp.x, 8.0, size.x - tw - 8.0)
	draw_string_outline(font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 3, Color(0, 0, 0, 0.65))
	draw_string(font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(mc.lerp(Color.WHITE, 0.3), 0.92))


## Указатель у края экрана в сторону звезды, пока её не видно, с расстоянием.
func _draw_star_arrow() -> void:
	var rect := Rect2(Vector2.ZERO, size).grow(-50.0)
	var center := size * 0.5
	var dir := (star_screen_pos - center).normalized()
	var t := INF
	if absf(dir.x) > 0.001:
		t = minf(t, (rect.size.x * 0.5) / absf(dir.x))
	if absf(dir.y) > 0.001:
		t = minf(t, (rect.size.y * 0.5) / absf(dir.y))
	var tip := center + dir * t
	# Слева вверху карта зон и строки HUD: стрелку опускаем под них.
	if tip.x < 330.0 and tip.y < 220.0:
		tip.y = 220.0
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
