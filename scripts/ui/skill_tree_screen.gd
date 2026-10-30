class_name SkillTreeScreen
extends Control
## Экран древа: игра на паузе, древо двигается пальцем и масштабируется щипком.
##
## Фон — рисованный космос. Видны только узлы, которые уже можно купить:
## ветки никуда не ведут заранее, а вырастают к новым узлам после покупки.

signal closed

const SPACING := 170.0
const INFO_WIDTH := 360.0
const NODE_RADIUS := 42.0
const TAP_SLOP := 14.0
const ZOOM_RANGE := Vector2(0.5, 1.8)

const BG_TEXTURE := preload("res://assets/ui/tree_bg.png")
const BG_PARALLAX := 0.15
const GROW_TIME := 0.9    # сколько растёт ветка к новому узлу
const APPEAR_TIME := 0.55  # сколько узел «распускается» после ветки
const BRANCH_STAGGER := 0.25

const COLOR_AVAILABLE := Color(0.62, 0.72, 0.95)
const COLOR_AFFORDABLE := Color(1.0, 0.82, 0.45)
const COLOR_OWNED := Color(0.78, 0.62, 0.42)
const COLOR_MAXED := Color(0.55, 0.88, 0.72)
const COLOR_BLOCKED := Color(0.42, 0.4, 0.46)
# Цвет ободка у веток веществ: путь виден сразу, ещё до выбора.
const PATH_COLORS := {
	"silicate": Color(0.87, 0.77, 0.58), "metal": Color(0.75, 0.8, 0.9),
	"carbon": Color(0.72, 0.5, 0.42), "ice": Color(0.6, 0.85, 1.0),
}
const BRANCH_COLOR := Color(0.95, 0.78, 0.45)

var _canvas: Node2D  # общий сдвиг и масштаб древа; рисуют три слоя внутри
# Слои: под узлами — свечение и искры (каждый кадр), сами узлы, ветки и подписи
# (только когда что-то поменялось), поверх — вращающиеся украшения (каждый кадр).
# Подписи с обводкой и сглаженные дуги дороги, поэтому у каждого узла и каждой ветки
# свой холст: перерисовывается только тот, что поменялся или сейчас растёт.
var _layer_under := Node2D.new()
var _layer_static := Node2D.new()
var _layer_over := Node2D.new()
var _edges_root := Node2D.new()
var _nodes_root := Node2D.new()
var _fork_item := Node2D.new()
var _items := {}        # узел или ветка -> его холст
var _sigs := {}         # узел или ветка -> как нарисован сейчас
var _static_dirty := true
var _g: CanvasItem  # слой, в который сейчас рисуем
var _colors := {}   # цвет узла, считается при перерисовке статичного слоя
var _anim_until := 0.0  # до этого времени ветки растут и узлы распускаются
var _view := Rect2()    # видимая часть древа в его координатах (с запасом)
var _currency_label: Label
var _chondrule_label: Label
var _info: PanelContainer
var _info_title: Label
var _info_desc: RichTextLabel
var _info_level: Label
var _info_change: RichTextLabel  # «было → станет» для каждого параметра узла
var _buy_button: Button
var _price_row: HBoxContainer   # цена на кнопке: иконки валют с числами
var _price_dust: Label
var _price_chondrules: Label
var _price_bead: Control
var _price_word: Label
var _price_col := Color.WHITE  # цвет искры на кнопке
var close_button: Button
var _stats_button: Button
var _stats_panel: PanelContainer  # «Мои параметры»: что даёт каждый узел
var _stats_list: VBoxContainer
var _stats_scroll: ScrollContainer
var _selected := ""
var _press_pos := Vector2.ZERO
var _dragging := false
var _pressed := false
var _touches := {}
var _pinch_dist := 0.0
var _time := 0.0
var _bg: TextureRect
var _glow := _make_glow()
var _edges := {}       # "родитель>узел" -> время начала роста
var _node_shown := {}  # узел -> время, когда начинает появляться
var _bursts := {}      # узел -> время покупки (вспышка)
# Плавный пролёт камеры к новой ветви: откуда, куда, когда начался и сколько длится.
var _cam_from := Vector3.ZERO  # x, y — сдвиг древа, z — масштаб
var _cam_to := Vector3.ZERO
var _cam_t0 := 0.0
var _cam_dur := 0.0
const CAM_FLY_TIME := 1.4


static func _make_glow() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.3, Color(1, 1, 1, 0.35))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	return tex


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiTheme.get_theme()
	visible = false
	_build()
	GameState.currency_changed.connect(_refresh.unbind(1))
	GameState.skills_changed.connect(_on_skills_changed)


func open() -> void:
	visible = true
	get_tree().paused = true
	_cam_dur = 0.0
	# Камера там, где игрок её оставил; в первый раз — на «Начале».
	var v := GameState.tree_view
	if v.size() == 3:
		var k := clampf(float(v[2]), ZOOM_RANGE.x, ZOOM_RANGE.y)
		_canvas.scale = Vector2(k, k)
		_canvas.position = _area_center() - Vector2(v[0], v[1]) * k
	else:
		_canvas.scale = Vector2.ONE
		_canvas.position = _area_center() - _node_pos("start")
	_select("" if Skills.is_owned("start") else "start")
	if GameState.tree_seen == null or GameState.tree_seen.is_empty():
		GameState.tree_seen = []
		_sync_branches(false)
	else:
		# Новые ветви (открылась стадия) не появляются молча: камера летит к ним,
		# и они вырастают у игрока на глазах.
		_sync_branches(false, true)
		var fresh := _unseen()
		if not fresh.is_empty():
			_fly_to(fresh)
			_sync_branches(true, false, CAM_FLY_TIME * 0.8)
			_select(fresh[0])
	_refresh()


func _area_center() -> Vector2:
	return Vector2((size.x - INFO_WIDTH) * 0.5, size.y * 0.5)


## Узлы, которые уже видны в книге, но игрок их ещё не видел.
func _unseen() -> Array:
	var out := []
	for id in Skills.order:
		if id in GameState.tree_seen or not _would_show(id):
			continue
		out.append(id)
	return out


func _would_show(id: String) -> bool:
	if Skills.nodes[id].get("path", "") == "" and not Skills.is_unlocked(id):
		return false
	var reqs: Array = Skills.nodes[id].get("requires", [])
	if reqs.is_empty():
		return true
	for req in reqs:
		if Skills.is_owned(req):
			return true
	return false


## Камера плавно перелетает к новым узлам: они по центру, а ветка тянется к ним
## от родителя из-за края.
func _fly_to(ids: Array) -> void:
	var box := Rect2(_node_pos(ids[0]), Vector2.ZERO)
	for id in ids:
		box = box.expand(_node_pos(id))
	box = box.grow(NODE_RADIUS * 3.0)
	var area := Vector2(size.x - INFO_WIDTH - 48.0, size.y - 160.0)
	var k := clampf(minf(maxf(_canvas.scale.x, 0.8), minf(area.x / box.size.x, area.y / box.size.y)), ZOOM_RANGE.x, ZOOM_RANGE.y)
	var pos := _area_center() - box.get_center() * k
	_cam_from = Vector3(_canvas.position.x, _canvas.position.y, _canvas.scale.x)
	_cam_to = Vector3(pos.x, pos.y, k)
	_cam_t0 = _time
	_cam_dur = CAM_FLY_TIME


func _update_camera() -> void:
	if _cam_dur <= 0.0:
		return
	var t := clampf((_time - _cam_t0) / _cam_dur, 0.0, 1.0)
	var e := t * t * (3.0 - 2.0 * t)
	var c := _cam_from.lerp(_cam_to, e)
	_canvas.position = Vector2(c.x, c.y)
	_canvas.scale = Vector2(c.z, c.z)
	if t >= 1.0:
		_cam_dur = 0.0


func _store_view() -> void:
	var k := _canvas.scale.x
	var c := (_area_center() - _canvas.position) / k
	GameState.tree_view = [c.x, c.y, k]


func _on_skills_changed() -> void:
	# Закрытая книга ветви не трогает: новое покажется при открытии (см. open).
	if visible:
		_sync_branches(true)
	_refresh()
	if _stats_panel.visible:
		_fill_stats()


## Ветка идёт от купленного узла к узлу, который стал доступен. Новые ветки
## растут по очереди, а узел на конце распускается, когда ветка дотянется.
## only_seen — без анимации показать лишь то, что игрок уже видел; остальное
## потом вырастет с задержкой delay (пока камера летит к новой ветви).
func _sync_branches(animate: bool, only_seen := false, delay := 0.0) -> void:
	if not animate:
		_edges.clear()
		_node_shown.clear()
		_sigs.clear()
	for id in Skills.order:
		# Пути веществ видны сразу, как только открыта «Избирательность»: игрок
		# заранее видит развилку. Закрытые пути остаются на виду — серыми, с замком.
		var is_path: bool = Skills.nodes[id].get("path", "") != ""
		if not Skills.is_unlocked(id) and not is_path:
			continue
		if only_seen and id not in GameState.tree_seen:
			continue
		var reqs: Array = Skills.nodes[id].get("requires", [])
		if reqs.is_empty() and not _node_shown.has(id):
			_node_shown[id] = -INF
		for req in reqs:
			var key: String = req + ">" + id
			if _edges.has(key) or not Skills.is_owned(req):
				continue
			var start := _time + delay if animate else -INF
			_edges[key] = start
			if animate:
				delay += BRANCH_STAGGER
			if not _node_shown.has(id):
				_node_shown[id] = start + GROW_TIME
				_anim_until = maxf(_anim_until, start + GROW_TIME + APPEAR_TIME + 0.1)
	for id in _node_shown:
		if id not in GameState.tree_seen:
			GameState.tree_seen.append(id)
	_static_dirty = true


func close() -> void:
	_cam_dur = 0.0
	_store_view()
	if _stats_panel.visible:
		_toggle_stats()
	visible = false
	get_tree().paused = false
	closed.emit()


func _build() -> void:
	var under := ColorRect.new()
	under.color = Color(0.02, 0.02, 0.06)
	under.set_anchors_preset(Control.PRESET_FULL_RECT)
	under.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(under)
	# Рисованный космос чуть больше экрана: сдвигается вслед за древом (параллакс).
	_bg = TextureRect.new()
	_bg.texture = BG_TEXTURE
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	# Node2D, а не Control: Control отсекает рисование по своему (нулевому) размеру,
	# и древо пропадало целиком, когда его начало уезжало за верх экрана.
	_canvas = Node2D.new()
	add_child(_canvas)
	for layer in [_layer_under, _layer_static, _layer_over]:
		_canvas.add_child(layer)
	_layer_under.draw.connect(_draw_under)
	for root in [_edges_root, _nodes_root, _fork_item]:
		_layer_static.add_child(root)
	_fork_item.draw.connect(_draw_fork_item)
	_layer_over.draw.connect(_draw_over)

	_currency_label = Label.new()
	_currency_label.position = Vector2(28, 20)
	_currency_label.add_theme_font_size_override("font_size", 40)
	_currency_label.add_theme_font_override("font", UiTheme.FONT_NUMBERS)
	_currency_label.add_theme_color_override("font_color", UiTheme.GOLD)
	add_child(_currency_label)
	_chondrule_label = Label.new()
	_chondrule_label.add_theme_font_size_override("font_size", 30)
	_chondrule_label.add_theme_font_override("font", UiTheme.FONT_NUMBERS)
	_chondrule_label.add_theme_color_override("font_color", UiTheme.CHONDRULE)
	_chondrule_label.draw.connect(func() -> void:
		UiTheme.draw_chondrule(_chondrule_label, Vector2(-16, _chondrule_label.size.y * 0.5 + 2), 9.0))
	add_child(_chondrule_label)

	var close_btn := Button.new()
	close_button = close_btn
	close_btn.text = "Закрыть книгу"
	UiTheme.paint_button(close_btn, false, 22)
	close_btn.anchor_left = 1.0
	close_btn.anchor_right = 1.0
	close_btn.offset_left = -INFO_WIDTH - 24
	close_btn.offset_right = -24
	close_btn.offset_top = 24
	close_btn.offset_bottom = 90
	close_btn.pressed.connect(close)
	add_child(close_btn)

	_build_stats()

	_info = PanelContainer.new()
	# Панель справа: в горизонтальном режиме не перекрывает древо.
	_info.anchor_left = 1.0
	_info.anchor_right = 1.0
	_info.anchor_top = 0.0
	_info.anchor_bottom = 1.0
	_info.offset_left = -INFO_WIDTH - 24
	_info.offset_right = -24
	_info.offset_top = 104
	_info.offset_bottom = -24
	_info.add_theme_stylebox_override("panel", UiTheme.painted_panel(28))
	add_child(_info)

	# Заголовок книги по центру над древом.
	var heading := Label.new()
	heading.text = "Книга звёздных знаний"
	heading.anchor_right = 1.0
	heading.offset_right = -INFO_WIDTH - 48
	heading.offset_top = 22
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_theme_font_override("font", UiTheme.FONT_SERIF_BOLD)
	heading.add_theme_font_size_override("font_size", 32)
	heading.add_theme_color_override("font_color", Color(1.0, 0.84, 0.5))
	heading.add_theme_color_override("font_outline_color", Color(0.1, 0.04, 0.0, 0.8))
	heading.add_theme_constant_override("outline_size", 6)
	add_child(heading)

	var text_box := VBoxContainer.new()
	text_box.add_theme_constant_override("separation", 12)
	_info.add_child(text_box)

	_info_title = Label.new()
	_info_title.add_theme_font_size_override("font_size", 32)
	_info_title.add_theme_font_override("font", UiTheme.FONT_SERIF_BOLD)
	text_box.add_child(_info_title)
	_info_desc = RichTextLabel.new()
	_info_desc.bbcode_enabled = true
	_info_desc.fit_content = true
	_info_desc.scroll_active = false
	_info_desc.add_theme_font_override("normal_font", UiTheme.FONT_SERIF)
	_info_desc.add_theme_font_size_override("normal_font_size", 21)
	_info_desc.add_theme_color_override("default_color", UiTheme.PARCHMENT)
	# Описание занимает всё свободное место, а длинное уменьшает шрифт (см. _fit_desc).
	_info_desc.fit_content = false
	_info_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_box.add_child(_info_desc)
	_info_change = RichTextLabel.new()
	_info_change.bbcode_enabled = true
	_info_change.fit_content = true
	_info_change.scroll_active = false
	_info_change.add_theme_font_override("normal_font", UiTheme.FONT_SERIF)
	_info_change.add_theme_font_override("bold_font", UiTheme.FONT_SERIF_BOLD)
	_info_change.add_theme_font_size_override("normal_font_size", 20)
	_info_change.add_theme_font_size_override("bold_font_size", 20)
	_info_change.add_theme_color_override("default_color", Color(UiTheme.PARCHMENT, 0.75))
	text_box.add_child(_info_change)
	_info_level = Label.new()
	_info_level.add_theme_font_override("font", UiTheme.FONT_SERIF_ITALIC)
	_info_level.add_theme_font_size_override("font_size", 19)
	_info_level.add_theme_color_override("font_color", Color(UiTheme.PARCHMENT, 0.6))
	text_box.add_child(_info_level)

	_buy_button = Button.new()
	_buy_button.custom_minimum_size = Vector2(0, 70)
	# Длинная цена («… и 10 хондр») переносится, а не раздувает панель за край экрана.
	_buy_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiTheme.paint_button(_buy_button, true, 24)
	_buy_button.pressed.connect(_on_buy)
	text_box.add_child(_buy_button)
	# «Изучить» и цена иконками валют — одной строкой по центру кнопки.
	_price_row = HBoxContainer.new()
	_price_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_price_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_price_row.add_theme_constant_override("separation", 6)
	_price_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buy_button.add_child(_price_row)
	_price_word = Label.new()
	_price_word.text = "Изучить"
	_price_word.add_theme_font_override("font", UiTheme.FONT_SERIF_BOLD)
	_price_word.add_theme_font_size_override("font_size", 24)
	_price_word.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_price_row.add_child(_price_word)
	var word_gap := Control.new()
	word_gap.custom_minimum_size = Vector2(10, 0)
	word_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_price_row.add_child(word_gap)
	var spark := Control.new()
	spark.custom_minimum_size = Vector2(24, 0)
	spark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spark.draw.connect(func() -> void: UiTheme.draw_spark(spark, spark.size * 0.5, 11.0, _price_col))
	_price_row.add_child(spark)
	_price_dust = _price_label()
	_price_row.add_child(_price_dust)
	_price_bead = Control.new()
	_price_bead.custom_minimum_size = Vector2(30, 0)
	_price_bead.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_price_bead.draw.connect(func() -> void: UiTheme.draw_chondrule(_price_bead, _price_bead.size * 0.5 + Vector2(4, 0), 9.0))
	_price_row.add_child(_price_bead)
	_price_chondrules = _price_label()
	_price_row.add_child(_price_chondrules)


## «Скорость 1,6 → 1,7» по каждому параметру узла; изученный до конца — только итог.
func _change_text(id: String) -> String:
	var effects: Dictionary = Skills.nodes[id].get("effects", {})
	var lines := PackedStringArray()
	var show_next := not Skills.is_maxed(id) and Skills.blocked_by(id) == ""
	var after := Skills.preview(id) if show_next else {}
	for key in effects:
		if not StatInfo.INFO.has(key):
			continue
		var was := Skills.stat(key)
		var line := StatInfo.title(key) + "  [b]" + StatInfo.format(key, was) + "[/b]"
		if show_next and not is_equal_approx(float(after[key]), was):
			var col := "#9fe08a" if StatInfo.better(key, was, float(after[key])) else "#ff9a80"
			line = StatInfo.title(key) + "  " + StatInfo.format(key, was) + " → [b][color=%s]%s[/color][/b]" % [col, StatInfo.format(key, float(after[key]))]
		lines.append(line)
	return "\n".join(lines)


## Кнопка внизу слева и лист «Мои параметры» поверх древа (панель узла остаётся справа).
func _build_stats() -> void:
	_stats_button = Button.new()
	_stats_button.text = "Мои параметры"
	UiTheme.paint_button(_stats_button, false, 22)
	_stats_button.anchor_top = 1.0
	_stats_button.anchor_bottom = 1.0
	_stats_button.offset_left = 24
	_stats_button.offset_right = 284
	_stats_button.offset_top = -90
	_stats_button.offset_bottom = -24
	_stats_button.pressed.connect(_toggle_stats)
	add_child(_stats_button)

	_stats_panel = PanelContainer.new()
	_stats_panel.anchor_right = 1.0
	_stats_panel.anchor_bottom = 1.0
	_stats_panel.offset_left = 24
	_stats_panel.offset_right = -INFO_WIDTH - 48
	_stats_panel.offset_top = 104
	_stats_panel.offset_bottom = -104
	_stats_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_stats_panel.add_theme_stylebox_override("panel", UiTheme.painted_panel(28))
	_stats_panel.visible = false
	# Древо под листом притушено, чтобы не мешало читать.
	_stats_panel.draw.connect(func() -> void:
		_stats_panel.draw_rect(Rect2(Vector2(8, 8), _stats_panel.size - Vector2(16, 16)), Color(0.02, 0.01, 0.05, 0.75)))
	add_child(_stats_panel)
	_stats_scroll = ScrollContainer.new()
	_stats_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_stats_panel.add_child(_stats_scroll)
	_stats_list = VBoxContainer.new()
	_stats_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats_list.add_theme_constant_override("separation", 6)
	_stats_scroll.add_child(_stats_list)


func _toggle_stats() -> void:
	_stats_panel.visible = not _stats_panel.visible
	_stats_button.text = "К древу" if _stats_panel.visible else "Мои параметры"
	if _stats_panel.visible:
		_fill_stats()
		_stats_scroll.scroll_vertical = 0


## Параметр показываем, если его что-то меняет; главные — всегда, со своего этапа.
const CORE_STATS := ["value", "speed", "gravity", "reach", "drift", "stick", "thrust", "chip"]


func _fill_stats() -> void:
	for c in _stats_list.get_children():
		c.queue_free()
	var stage := mini(GameState.stage, 2)
	var income := Skills.stat("value") * Skills.stat("value_mul") * (1.0 if GameState.is_boulder() else Skills.stat("pebble_value_mul"))
	_stats_row("Доход с добычи", "×" + StatInfo.num(income), "всё, что прибавляет к звёздной пыли, перемножено", true)
	for g in StatInfo.GROUPS.size():
		var rows := []
		for key in StatInfo.INFO:
			if StatInfo.group(key) != g:
				continue
			var contrib := Skills.contributions(key)
			if contrib.is_empty() and not (key in CORE_STATS and g <= stage):
				continue
			rows.append([key, contrib])
		if rows.is_empty():
			continue
		var head := Label.new()
		head.text = StatInfo.GROUPS[g]
		head.add_theme_font_override("font", UiTheme.FONT_SERIF_ITALIC)
		head.add_theme_font_size_override("font_size", 22)
		head.add_theme_color_override("font_color", Color(UiTheme.GOLD, 0.7))
		_stats_list.add_child(head)
		for r in rows:
			var key: String = r[0]
			var parts := PackedStringArray()
			for c in r[1]:
				parts.append("%s%s %s" % [c[0], " ур. %d" % c[1] if c[1] > 1 else "", StatInfo.format_delta(key, c[2])])
			_stats_row(StatInfo.title(key), StatInfo.format(key, Skills.stat(key)), " · ".join(parts) if not parts.is_empty() else "пока ничего не прибавлено")


func _stats_row(title: String, value: String, note: String, big := false) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var line := HBoxContainer.new()
	var name := Label.new()
	name.text = title
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.add_theme_font_override("font", UiTheme.FONT_SERIF_BOLD)
	name.add_theme_font_size_override("font_size", 26 if big else 22)
	name.add_theme_color_override("font_color", UiTheme.PARCHMENT)
	line.add_child(name)
	var val := Label.new()
	val.text = value
	val.add_theme_font_override("font", UiTheme.FONT_NUMBERS)
	val.add_theme_font_size_override("font_size", 28 if big else 22)
	val.add_theme_color_override("font_color", UiTheme.GOLD)
	line.add_child(val)
	box.add_child(line)
	var sub := Label.new()
	sub.text = note
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_override("font", UiTheme.FONT_SERIF_ITALIC)
	sub.add_theme_font_size_override("font_size", 17)
	sub.add_theme_color_override("font_color", Color(UiTheme.PARCHMENT, 0.6))
	box.add_child(sub)
	_stats_list.add_child(box)


func _price_label() -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", UiTheme.FONT_NUMBERS)
	l.add_theme_font_size_override("font_size", 24)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Размер панели известен только после раскладки: подбираем шрифт на следующем кадре.
func _fit_desc_later() -> void:
	await get_tree().process_frame
	_fit_desc()


## Длинное описание не должно уходить за край: уменьшаем шрифт, пока текст не влезет.
func _fit_desc() -> void:
	for fs in [21, 20, 19, 18, 17, 16, 15, 14]:
		_info_desc.add_theme_font_size_override("normal_font_size", fs)
		if _info_desc.get_content_height() <= _info_desc.size.y:
			return


func _node_pos(id: String) -> Vector2:
	var p: Array = Skills.nodes[id].pos
	return Vector2(p[0], p[1]) * SPACING


func _select(id: String) -> void:
	_selected = id
	_refresh()


func _on_buy() -> void:
	if _selected != "" and Skills.buy(_selected):
		_bursts[_selected] = _time


func _refresh() -> void:
	if not is_node_ready():
		return
	_currency_label.text = "✦ " + GameData.format_number(GameState.currency)
	_chondrule_label.visible = GameState.chondrules > 0
	_chondrule_label.text = str(GameState.chondrules)
	_chondrule_label.position = Vector2(28 + _currency_label.get_minimum_size().x + 46, 27)
	_info.visible = _selected != ""
	if _selected != "":
		var node: Dictionary = Skills.nodes[_selected]
		_info_title.text = node.title
		# Длинное название уменьшается, чтобы влезть в панель.
		var title_size := 32
		while title_size > 22 and UiTheme.FONT_SERIF_BOLD.get_string_size(node.title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x > INFO_WIDTH - 60.0:
			title_size -= 1
		_info_title.add_theme_font_size_override("font_size", title_size)
		_info_title.add_theme_color_override("font_color", UiTheme.GOLD)
		_info_desc.text = node.desc
		if _selected == "boulder_root":
			var bonus: Dictionary = GameData.BOULDER_MATERIAL.get(GameState.body_type(), {})
			_info_desc.text += "\n\nВещество продолжает путь. " + (
				"Твоё тело — %s: %s." % [GameData.BODY_TYPES[GameState.body_type()].name.to_lower(), bonus.text] if not bonus.is_empty()
				else "Состав ещё не сложился, и бонуса от вещества нет: металл, камень, лёд и углерод дают валуну каждый своё.")
		elif _selected == "t_root":
			var type := GameState.body_type()
			var bonus: Dictionary = GameData.PLANET_MATERIAL[GameData.planet_type(type)]
			var path: Dictionary = GameData.EMBRYO_PATHS.get(GameData.embryo_path(type, GameState.player_position.length()), {})
			if not bonus.is_empty():
				_info_desc.text += "\n\nТвоё тело — %s: %s." % [GameData.BODY_TYPES[type].name.to_lower(), bonus.text]
			if not path.is_empty():
				_info_desc.text += "\nЕсли так и останется, на тысяче километров тебя ждёт путь «%s»: %s." % [path.name, path.desc]
		elif _selected == "t_iron_core" and not GameState.is_melted:
			_info_desc.text += "\n\nСначала нужно расплавиться: вырасти до 20 км, пока алюминий-26 ещё греет."
		_info_change.text = _change_text(_selected)
		_info_change.visible = _info_change.text != ""
		_info_level.text = "Изучено %d из %d" % [Skills.level(_selected), Skills.max_level(_selected)]
		if node.get("legendary", false):
			_info_level.text = "Легендарный навык" + (" · изучен" if Skills.is_owned(_selected) else "")
		elif node.get("ability", false):
			_info_level.text = "Способность · изучено %d из %d" % [Skills.level(_selected), Skills.max_level(_selected)]
		_price_row.visible = false
		var blocker := Skills.blocked_by(_selected)
		if blocker != "":
			_info_level.text = "Путь закрыт: выбрано «%s»" % Skills.nodes[blocker].title
			_buy_button.text = "Путь закрыт"
			_buy_button.disabled = true
		elif Skills.is_maxed(_selected):
			_buy_button.text = "Изучено"
			_buy_button.disabled = true
		else:
			_buy_button.disabled = not Skills.can_buy(_selected)
			_buy_button.text = ""
			_price_row.visible = true
			# Чего не хватает, то красным. На тусклой кнопке цвета светлее, иначе не прочесть.
			var short := Color(0.62, 0.12, 0.08) if not _buy_button.disabled else Color(1.0, 0.5, 0.4)
			var ok := Color(0.28, 0.16, 0.04) if not _buy_button.disabled else Color(0.88, 0.82, 0.7)
			_price_col = ok if GameState.currency >= Skills.cost(_selected) else short
			_price_row.get_child(2).queue_redraw()
			_price_word.add_theme_color_override("font_color", ok)
			_price_dust.text = GameData.format_short(Skills.cost(_selected))
			_price_dust.add_theme_color_override("font_color", ok if GameState.currency >= Skills.cost(_selected) else short)
			var c2 := Skills.cost2(_selected)
			_price_bead.visible = c2 > 0
			_price_chondrules.visible = c2 > 0
			_price_chondrules.text = str(c2)
			_price_chondrules.add_theme_color_override("font_color", ok if GameState.chondrules >= c2 else short)
			if not Skills.is_unlocked(_selected):
				_price_row.visible = false
				var req: Array = node.get("requires", [])
				var lv := int(node.get("requires_level", 1))
				if not req.is_empty():
					_buy_button.text = "Сначала «%s»%s" % [Skills.nodes[req[0]].title, " ур. %d" % lv if lv > 1 else ""]
		_fit_desc_later()
	_static_dirty = true


func _process(delta: float) -> void:
	# Узлы пульсируют, ветки растут и по ним бегут искры, поэтому перерисовка каждый кадр.
	if visible:
		_time += delta
		_update_camera()
		_layout_bg()
		var inv := 1.0 / _canvas.scale.x
		_view = Rect2(-_canvas.position * inv, size * inv).grow(NODE_RADIUS * 4.0)
		_layer_under.queue_redraw()
		_layer_over.queue_redraw()
		if _static_dirty or _time < _anim_until + 0.1:
			_sync_static()


func _layout_bg() -> void:
	var margin := size * 0.12
	_bg.size = size + margin * 2.0
	var shift := (_canvas.position - size * 0.5) * BG_PARALLAX
	_bg.position = -margin + shift.clamp(-margin, margin)


func _is_visible_node(id: String) -> bool:
	return _node_shown.has(id) and _time >= float(_node_shown[id])


func _draw_under() -> void:
	_g = _layer_under
	for key in _edges:
		var t: float = (_time - float(_edges[key])) / GROW_TIME
		if t > 0.0:
			var parts: PackedStringArray = (key as String).split(">")
			var a := _node_pos(parts[0])
			var b := _node_pos(parts[1])
			if _view.intersects(Rect2(a, Vector2.ZERO).expand(b)):
				_draw_branch_fx(a, b, minf(t, 1.0), absi((key as String).hash()))
	for id in Skills.order:
		if _is_visible_node(id) and _view.has_point(_node_pos(id)):
			_draw_node_under(id, _node_pos(id), _appear(id))
	_g.draw_set_transform(Vector2.ZERO)


## Перерисовывает только те холсты, что поменялись: растущую ветку и распускающийся
## узел каждый кадр, остальные — когда меняется цвет или уровень.
func _sync_static() -> void:
	var full := _static_dirty
	_static_dirty = false
	for key in _edges:
		var t: float = (_time - float(_edges[key])) / GROW_TIME
		var sig := "" if t <= 0.0 else ("done" if t >= 1.0 else str(t))
		if _sigs.get(key, null) == sig:
			continue
		_sigs[key] = sig
		_item(key, _edges_root, Vector2.ZERO).queue_redraw()
	for id in Skills.order:
		if not _node_shown.has(id):
			if _items.has(id):
				_items[id].visible = false
			continue
		var k := _appear(id) if _time >= float(_node_shown[id]) else -1.0
		var sig := ""
		if k >= 0.0:
			if k < 1.0:
				sig = str(k)
			elif full or not (_sigs.get(id, "") as String).begins_with("s|"):
				_colors[id] = _node_color(id)
				sig = "s|%s|%d|%s" % [_colors[id].to_html(), Skills.level(id), Skills.blocked_by(id)]
			else:
				continue
		if _sigs.get(id, null) == sig:
			continue
		_sigs[id] = sig
		var item := _item(id, _nodes_root, _node_pos(id))
		item.visible = k >= 0.0
		item.queue_redraw()
	if full:
		_fork_item.queue_redraw()
		# Ветки, которых больше нет (новый забег), стираются.
		for key in _items:
			if ">" in key and not _edges.has(key) and _sigs.get(key, "") != "gone":
				_sigs[key] = "gone"
				_items[key].queue_redraw()


func _item(key: String, root: Node2D, at: Vector2) -> Node2D:
	if not _items.has(key):
		var item := Node2D.new()
		item.position = at
		root.add_child(item)
		_items[key] = item
		if ">" in key:
			item.draw.connect(_draw_edge_item.bind(key, item))
		else:
			item.draw.connect(_draw_node_item.bind(key, item))
	return _items[key]


func _draw_edge_item(key: String, item: Node2D) -> void:
	var t: float = (_time - float(_edges.get(key, INF))) / GROW_TIME
	if t <= 0.0:
		return
	_g = item
	var parts := key.split(">")
	_draw_branch(_node_pos(parts[0]), _node_pos(parts[1]), minf(t, 1.0), absi(key.hash()))


func _draw_node_item(id: String, item: Node2D) -> void:
	if not _is_visible_node(id):
		return
	_g = item
	_draw_node(id, Vector2.ZERO, _appear(id))


func _draw_fork_item() -> void:
	_g = _fork_item
	_draw_path_fork()


func _draw_over() -> void:
	_g = _layer_over
	for id in Skills.order:
		if _is_visible_node(id) and _view.has_point(_node_pos(id)):
			_draw_node_over(id, _node_pos(id), _appear(id))
	_g.draw_set_transform(Vector2.ZERO)


func _appear(id: String) -> float:
	return clampf((_time - float(_node_shown[id])) / APPEAR_TIME, 0.0, 1.0)


## Над четырьмя ветками веществ — надпись о развилке: выбрать можно только одну.
func _draw_path_fork() -> void:
	var xs: Array[float] = []
	var y := INF
	for id in Skills.order:
		if Skills.nodes[id].get("path", "") != "" and _is_visible_node(id):
			var p := _node_pos(id)
			if p.y <= y + 1.0:
				if p.y < y - 1.0:
					xs.clear()
				y = minf(y, p.y)
				xs.append(p.x)
	if xs.size() < 2:
		return
	var a: float = xs.min()
	var b: float = xs.max()
	var chosen := Skills.chosen_path()
	var text := "развилка: выбери одно вещество" if chosen == "" else "путь выбран"
	var col := Color(1.0, 0.85, 0.55, 0.85) if chosen == "" else Color(0.7, 0.66, 0.6, 0.6)
	var ly := y - NODE_RADIUS - 30.0
	# Пунктирная скобка над ветками.
	var x := a
	while x < b:
		_g.draw_line(Vector2(x, ly + 12.0), Vector2(minf(x + 10.0, b), ly + 12.0), col, 2.0, true)
		x += 18.0
	_g.draw_line(Vector2(a, ly + 12.0), Vector2(a, ly + 22.0), col, 2.0, true)
	_g.draw_line(Vector2(b, ly + 12.0), Vector2(b, ly + 22.0), col, 2.0, true)
	var font: Font = UiTheme.FONT_SERIF_ITALIC
	var fs := 20
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var mid := (a + b) * 0.5
	_g.draw_rect(Rect2(mid - w * 0.5 - 8.0, ly - 10.0, w + 16.0, 28.0), Color(0.05, 0.03, 0.1, 0.85))
	_g.draw_string(font, Vector2(mid - w * 0.5, ly + 10.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## Ветка — изогнутый золотой стебель с почками. Пока растёт, на кончике искра;
## выросшая ветка изредка пропускает по себе огонёк от родителя к узлу.
func _draw_branch(a: Vector2, b: Vector2, t: float, seed_hash: int) -> void:
	var grow := 1.0 - pow(1.0 - t, 3.0)
	var bend := (b - a).orthogonal() * (0.16 if seed_hash % 2 == 0 else -0.16)
	var ctrl := (a + b) * 0.5 + bend
	# Ветка выходит из ободка узла, а не из центра, и упирается в ободок нового.
	a += (ctrl - a).normalized() * NODE_RADIUS
	b += (ctrl - b).normalized() * NODE_RADIUS
	var pts := PackedVector2Array()
	var n := 24
	var last := 0
	for i in n + 1:
		var u := float(i) / n
		if u > grow:
			break
		pts.append(a.lerp(ctrl, u).lerp(ctrl.lerp(b, u), u))
		last = i
	var tip := a.lerp(ctrl, grow).lerp(ctrl.lerp(b, grow), grow)
	if last < n:
		pts.append(tip)
	if pts.size() < 2:
		return
	_g.draw_polyline(pts, Color(BRANCH_COLOR, 0.10), 12.0, true)
	_g.draw_polyline(pts, Color(BRANCH_COLOR, 0.25), 6.0, true)
	_g.draw_polyline(pts, Color(BRANCH_COLOR.lightened(0.2), 0.9), 2.5, true)
	# Почки-завитки вдоль ветки.
	for j in 3:
		var u := 0.25 + 0.22 * j
		if u > grow:
			break
		var p := a.lerp(ctrl, u).lerp(ctrl.lerp(b, u), u)
		var side := (b - a).normalized().orthogonal() * (1.0 if j % 2 == 0 else -1.0)
		var bud := p + side * 11.0
		_g.draw_line(p, bud, Color(BRANCH_COLOR, 0.7), 1.5, true)
		_g.draw_circle(bud, 2.6, Color(BRANCH_COLOR.lightened(0.3), 0.9))


## Живая часть ветки: искра на растущем кончике, огонёк по выросшей ветке.
func _draw_branch_fx(a: Vector2, b: Vector2, t: float, seed_hash: int) -> void:
	var grow := 1.0 - pow(1.0 - t, 3.0)
	var bend := (b - a).orthogonal() * (0.16 if seed_hash % 2 == 0 else -0.16)
	var ctrl := (a + b) * 0.5 + bend
	a += (ctrl - a).normalized() * NODE_RADIUS
	b += (ctrl - b).normalized() * NODE_RADIUS
	if t < 1.0:
		var tip := a.lerp(ctrl, grow).lerp(ctrl.lerp(b, grow), grow)
		_g.draw_texture_rect(_glow, Rect2(tip - Vector2(18, 18), Vector2(36, 36)), false, Color(1.0, 0.9, 0.6, 0.9))
		_g.draw_circle(tip, 3.0, Color.WHITE)
	else:
		var run := fmod(_time * 0.45 + float(seed_hash % 97) / 97.0, 1.0)
		if run < 0.6:
			var u := run / 0.6
			var p := a.lerp(ctrl, u).lerp(ctrl.lerp(b, u), u)
			var a_run := sin(u * PI)
			_g.draw_texture_rect(_glow, Rect2(p - Vector2(10, 10), Vector2(20, 20)), false, Color(1.0, 0.92, 0.7, 0.7 * a_run))


## Узел: свечение, тёмный медальон с двойным золотым ободком, значок навыка,
## точки уровней снизу. k — прогресс появления (упругое «распускание»).
## Рисуется в три слоя: _draw_node_under (свечение, венец), _draw_node (сам медальон
## и подпись, кешируется), _draw_node_over (вращающиеся украшения, выбор, вспышки).
func _node_color(id: String) -> Color:
	var owned := Skills.is_owned(id)
	var affordable := Skills.can_buy(id)
	# Порядок важен: изученный до конца — спокойный нефритовый, доступный к покупке —
	# пульсирующее золото (даже если часть уровней уже куплена), начатый — тусклая бронза.
	var maxed := Skills.is_maxed(id)
	var blocked := Skills.blocked_by(id) != ""
	var path: String = Skills.nodes[id].get("path", "")
	var col: Color = PATH_COLORS.get(path, COLOR_AVAILABLE)
	if blocked:
		col = COLOR_BLOCKED
	elif maxed:
		col = COLOR_MAXED
	elif affordable:
		col = COLOR_AFFORDABLE
	elif owned:
		col = COLOR_OWNED
	return col


func _pop(p: Vector2, k: float) -> void:
	var c1 := k - 1.0
	var pop := 1.0 + 2.70158 * c1 * c1 * c1 + 1.70158 * c1 * c1  # упругий выход за 1 и назад
	_g.draw_set_transform(p, 0.0, Vector2(pop, pop))


func _draw_node_under(id: String, p: Vector2, k: float) -> void:
	var owned := Skills.is_owned(id)
	var affordable := Skills.can_buy(id)
	var maxed := Skills.is_maxed(id)
	var col: Color = _colors.get(id, COLOR_AVAILABLE)
	_pop(p, k)
	var legendary: bool = Skills.nodes[id].get("legendary", false)
	var r := NODE_RADIUS * (1.3 if legendary else 1.0)
	var pulse := 0.5 + 0.5 * sin(_time * 3.0)
	if legendary:
		# Легендарный навык: золотой венец из медленно вращающихся лучей.
		var gold := Color(1.0, 0.78, 0.3, 0.75 if owned else 0.45)
		for i in 16:
			var ang := _time * 0.15 + i * TAU / 16.0
			var ray_len := r * (1.45 + (0.2 if i % 2 == 0 else 0.0) + 0.06 * pulse)
			_g.draw_line(Vector2.from_angle(ang) * (r + 6.0), Vector2.from_angle(ang) * ray_len, gold, 2.0, true)
		_g.draw_arc(Vector2.ZERO, r + 5.0, 0.0, TAU, 56, gold, 2.5, true)
	elif Skills.nodes[id].get("ability", false):
		# Способность: голубые камешки на орбите вокруг узла.
		var sky := Color(0.55, 0.85, 1.0, 0.8 if owned else 0.5)
		_g.draw_arc(Vector2.ZERO, r + 8.0, 0.0, TAU, 56, Color(sky, sky.a * 0.5), 1.5, true)
		for i in 3:
			_g.draw_circle(Vector2.from_angle(_time * 0.7 + i * TAU / 3.0) * (r + 8.0), 4.0, sky)

	var glow_a := 0.25 + 0.2 * pulse if affordable else (0.3 if maxed else (0.2 if owned else 0.12))
	var gr := r * (2.6 + (0.25 * pulse if affordable else 0.0))
	_g.draw_texture_rect(_glow, Rect2(-Vector2(gr, gr), Vector2(gr, gr) * 2.0), false, Color(col, glow_a))


func _draw_node_over(id: String, p: Vector2, k: float) -> void:
	var owned := Skills.is_owned(id)
	var col: Color = _colors.get(id, COLOR_AVAILABLE)
	_pop(p, k)
	var legendary: bool = Skills.nodes[id].get("legendary", false)
	var r := NODE_RADIUS * (1.3 if legendary else 1.0)
	if k < 1.0:
		# Вспышка при появлении.
		var fr := r * (1.0 + 1.5 * k)
		_g.draw_arc(Vector2.ZERO, fr, 0.0, TAU, 48, Color(1.0, 0.9, 0.65, 1.0 - k), 3.0, true)
	if _bursts.has(id):
		var bt: float = (_time - float(_bursts[id])) / 0.7
		if bt < 1.0:
			_g.draw_arc(Vector2.ZERO, r * (1.1 + 1.4 * bt), 0.0, TAU, 48, Color(1.0, 0.9, 0.6, 0.9 * (1.0 - bt)), 4.0 * (1.0 - bt) + 1.0, true)
			_g.draw_texture_rect(_glow, Rect2(-Vector2(r, r) * 3.0, Vector2(r, r) * 6.0), false, Color(1.0, 0.9, 0.6, 0.5 * (1.0 - bt)))
		else:
			_bursts.erase(id)

	if id == _selected:
		_g.draw_arc(Vector2.ZERO, r + 13.0, 0.0, TAU, 56, Color(col, 0.85), 2.0, true)
		# Бегущие засечки вокруг выбранного узла.
		for i in 12:
			var ang := _time * 0.6 + i * TAU / 12.0
			_g.draw_line(Vector2.from_angle(ang) * (r + 9.0), Vector2.from_angle(ang) * (r + 17.0), Color(col, 0.6), 1.5, true)

	if owned:
		# Орнамент: ромбики вокруг купленного узла медленно вращаются.
		for i in 8:
			var ang := -_time * 0.25 + i * TAU / 8.0
			var c := Vector2.from_angle(ang) * (r + 4.0)
			var d := Vector2.from_angle(ang) * 3.5
			var o := d.orthogonal() * 0.6
			_g.draw_colored_polygon(PackedVector2Array([c - d, c + o, c + d, c - o]), col)


func _draw_node(id: String, p: Vector2, k: float) -> void:
	var owned := Skills.is_owned(id)
	var affordable := Skills.can_buy(id)
	var blocked := Skills.blocked_by(id) != ""
	var col := _node_color(id)
	_colors[id] = col
	_pop(p, k)
	var legendary: bool = Skills.nodes[id].get("legendary", false)
	var r := NODE_RADIUS * (1.3 if legendary else 1.0)
	_g.draw_circle(Vector2.ZERO, r, Color(0.07, 0.045, 0.13))
	_g.draw_circle(Vector2(-r * 0.12, -r * 0.15), r * 0.78, Color(0.16, 0.1, 0.26, 0.6))
	_g.draw_circle(Vector2(-r * 0.2, -r * 0.25), r * 0.45, Color(0.26, 0.17, 0.38, 0.35))
	_g.draw_arc(Vector2.ZERO, r, 0.0, TAU, 56, col, 3.0, true)
	_g.draw_arc(Vector2.ZERO, r - 6.0, 0.0, TAU, 48, Color(col, 0.45), 1.2, true)
	_draw_icon(Skills.nodes[id].get("icon", id), col.lightened(0.15) if owned or affordable else Color(col, 0.85))

	var max_lvl := Skills.max_level(id)
	if max_lvl > 1:
		var lvl := Skills.level(id)
		for i in max_lvl:
			var ang := PI * 0.5 + (i - (max_lvl - 1) * 0.5) * 0.22
			var dp := Vector2.from_angle(ang) * (r - 12.0)
			if i < lvl:
				_g.draw_circle(dp, 3.2, col.lightened(0.3))
			else:
				_g.draw_arc(dp, 2.8, 0.0, TAU, 12, Color(col, 0.5), 1.0, true)
	if blocked:
		# Путь закрыт: тёмная вуаль, перечёркнутый круг и замочек.
		_g.draw_circle(Vector2.ZERO, r, Color(0.03, 0.02, 0.06, 0.55))
		var dg := Vector2(r, -r) * 0.62
		_g.draw_line(-dg, dg, Color(0.75, 0.35, 0.35, 0.8), 3.0, true)
		var lp := Vector2(r * 0.62, r * 0.62)
		_g.draw_rect(Rect2(lp - Vector2(8, 4), Vector2(16, 12)), Color(0.8, 0.75, 0.7))
		_g.draw_arc(lp - Vector2(0, 4), 5.0, PI, TAU, 12, Color(0.8, 0.75, 0.7), 2.5, true)

	var font: Font = UiTheme.FONT_SERIF_BOLD
	var title: String = Skills.nodes[id].title
	var w := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 21).x
	var tp := Vector2(-w * 0.5, r + 30.0)
	_g.draw_string_outline(font, tp, title, HORIZONTAL_ALIGNMENT_LEFT, -1, 21, 5, Color(0.03, 0.02, 0.06, 0.85))
	_g.draw_string(font, tp, title, HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color(col.lightened(0.2), 0.95))
	_g.draw_set_transform(Vector2.ZERO)


## Значки навыков рисуются линиями, в стиле гравюры.
func _draw_icon(id: String, col: Color) -> void:
	var w := 2.2
	match id:
		"start":
			var pts := PackedVector2Array()
			for i in 40:
				var t := i / 39.0
				pts.append(Vector2.from_angle(t * TAU * 2.2 + _time * 0.3) * (2.0 + 15.0 * t))
			_g.draw_polyline(pts, col, w, true)
			_g.draw_circle(Vector2.ZERO, 3.0, col)
		"gravity_1":
			_g.draw_circle(Vector2.ZERO, 4.5, col)
			_g.draw_arc(Vector2.ZERO, 11.0, 0.0, TAU, 32, Color(col, 0.6), 1.4, true)
			for i in 4:
				var d := Vector2.from_angle(i * TAU / 4.0 + PI / 4.0)
				var tip := d * 9.0
				_g.draw_line(d * 19.0, tip, col, w, true)
				_g.draw_line(tip, tip + d.rotated(0.6) * 5.0, col, w, true)
				_g.draw_line(tip, tip + d.rotated(-0.6) * 5.0, col, w, true)
		"reach_1":
			_g.draw_circle(Vector2.ZERO, 4.0, col)
			for i in 10:
				var a0 := i * TAU / 10.0
				_g.draw_arc(Vector2.ZERO, 17.0, a0, a0 + TAU / 20.0, 6, col, w, true)
			_g.draw_arc(Vector2.ZERO, 10.0, 0.0, TAU, 28, Color(col, 0.5), 1.2, true)
		"drift_1":
			for i in 3:
				var y := -8.0 + i * 8.0
				_g.draw_line(Vector2(-18.0 + i * 3.0, y), Vector2(4.0 - i * 2.0, y), Color(col, 0.5 + 0.25 * i), w, true)
			_g.draw_circle(Vector2(10.0, 0.0), 6.0, col)
		"density_1":
			for v in [Vector2(0, 0), Vector2(-9, -6), Vector2(8, -8), Vector2(11, 5), Vector2(-7, 9), Vector2(2, 13), Vector2(-14, 2), Vector2(3, -15)]:
				_g.draw_circle(v, 2.8 if v == Vector2.ZERO else 2.0, col)
		"value_1":
			var top := Vector2(0, -16)
			var bottom := Vector2(0, 16)
			var l := Vector2(-11, -3)
			var rr := Vector2(11, -3)
			_g.draw_polyline(PackedVector2Array([top, rr, bottom, l, top]), col, w, true)
			_g.draw_line(l, rr, Color(col, 0.7), 1.4, true)
			_g.draw_line(top, Vector2(-4, -3), Color(col, 0.6), 1.2, true)
			_g.draw_line(top, Vector2(4, -3), Color(col, 0.6), 1.2, true)
			_g.draw_line(Vector2(-4, -3), bottom, Color(col, 0.6), 1.2, true)
			_g.draw_line(Vector2(4, -3), bottom, Color(col, 0.6), 1.2, true)
		"cluster_1":
			for v in [Vector2(-6, 4), Vector2(6, 4), Vector2(0, -6)]:
				_g.draw_arc(v, 7.5, 0.0, TAU, 24, col, w, true)
			_g.draw_circle(Vector2.ZERO, 2.5, col)
		"dust_3":
			_g.draw_line(Vector2(-9, 6), Vector2(9, 6), Color(col, 0.7), w, true)
			_g.draw_line(Vector2(-9, 6), Vector2(0, -9), Color(col, 0.7), w, true)
			_g.draw_line(Vector2(9, 6), Vector2(0, -9), Color(col, 0.7), w, true)
			for v in [Vector2(-9, 6), Vector2(9, 6), Vector2(0, -9)]:
				_g.draw_circle(v, 5.0, col)
		"pebble_root":
			# Гладкая галька, газ обтекает её линиями.
			_ellipse(Vector2(4, 0), Vector2(9.0, 6.5), 0.0, col)
			for y in [-12.0, 12.0]:
				var pts := PackedVector2Array()
				for i in 12:
					var x := -18.0 + i * 3.4
					pts.append(Vector2(x, y * (0.55 + 0.45 * absf(x - 4.0) / 22.0)))
				_g.draw_polyline(pts, Color(col, 0.7), 1.6, true)
			_g.draw_line(Vector2(-18, 0), Vector2(-8, 0), Color(col, 0.7), 1.6, true)
		"toughness":
			# Плотно спечённый камень: многогранник с внутренними гранями.
			var pts := PackedVector2Array()
			for i in 7:
				pts.append(Vector2.from_angle(i * TAU / 6.0 + 0.3) * 14.0)
			_g.draw_polyline(pts, col, w, true)
			for i in 3:
				_g.draw_line(Vector2.ZERO, pts[i * 2], Color(col, 0.6), 1.4, true)
			_g.draw_circle(Vector2.ZERO, 3.0, col)
		"thrust":
			_g.draw_circle(Vector2(6, 0), 6.5, col)
			_g.draw_arc(Vector2(6, 0), 12.0, PI * 0.65, PI * 1.35, 14, Color(col, 0.7), w, true)
			_g.draw_line(Vector2(-6, -12), Vector2(-16, -12), Color(col, 0.6), w, true)
			_g.draw_line(Vector2(-6, 12), Vector2(-16, 12), Color(col, 0.6), w, true)
		"ice_crust":
			_g.draw_circle(Vector2.ZERO, 7.0, col)
			for i in 6:
				var d := Vector2.from_angle(i * TAU / 6.0)
				_g.draw_line(d * 10.0, d * 17.0, col, w, true)
				_g.draw_line(d * 14.0, d * 14.0 + d.rotated(0.9) * 4.0, Color(col, 0.7), 1.4, true)
				_g.draw_line(d * 14.0, d * 14.0 + d.rotated(-0.9) * 4.0, Color(col, 0.7), 1.4, true)
		"pebble_swarm":
			for v in [Vector2(-8, -5), Vector2(7, -8), Vector2(9, 7), Vector2(-6, 9), Vector2(0, 0)]:
				var rr := 4.2 if v == Vector2.ZERO else 3.2
				_ellipse(v, Vector2(rr, rr * 0.7), v.x * 0.1, col)
		"grip":
			# Крупное тело обволакивает камешек поменьше.
			_g.draw_circle(Vector2(-3, 2), 9.0, col)
			_g.draw_arc(Vector2(-3, 2), 13.0, -0.9, 1.6, 16, Color(col, 0.7), w, true)
			_ellipse(Vector2(11, -9), Vector2(4.5, 3.6), 0.4, col)
		"armor":
			var pts := PackedVector2Array()
			for i in 7:
				pts.append(Vector2.from_angle(i * TAU / 6.0) * 15.0)
			_g.draw_polyline(pts, col, w, true)
			_g.draw_arc(Vector2.ZERO, 9.0, 0.0, TAU, 24, Color(col, 0.7), 1.6, true)
			_g.draw_circle(Vector2.ZERO, 3.5, col)
		"combo":
			# Цепочка камешков, каждый следующий ярче.
			for i in 4:
				var v := Vector2(-15 + i * 10, 8 - i * 5)
				_g.draw_circle(v, 2.5 + i * 0.9, Color(col, 0.45 + 0.18 * i))
		"halo":
			# Тело в облачке парящих пылинок: точки кружат, ближние ярче.
			_g.draw_circle(Vector2.ZERO, 6.0, col)
			for i in 14:
				var ang := _time * (0.5 + 0.03 * i) + i * 2.4
				var rr := 10.0 + 7.0 * fmod(i * 0.37, 1.0)
				_g.draw_circle(Vector2.from_angle(ang) * rr, 1.1 + 0.6 * fmod(i * 0.61, 1.0), Color(col, 0.9 - (rr - 10.0) * 0.07))
		"chain":
			# Съеденная галька тянет за собой соседей.
			var pts := [Vector2(-13, 9), Vector2(-3, -2), Vector2(8, 6), Vector2(14, -9)]
			for i in 3:
				_g.draw_line(pts[i], pts[i + 1], Color(col, 0.55), 1.6, true)
			for i in 4:
				_g.draw_circle(pts[i], 3.0 + i * 0.6, Color(col, 0.55 + 0.15 * i))
		"pulse":
			# Волна расходится от тела.
			_g.draw_circle(Vector2.ZERO, 4.5, col)
			var t := fmod(_time * 0.6, 1.0)
			for i in 3:
				var k := fmod(t + i / 3.0, 1.0)
				_g.draw_arc(Vector2.ZERO, 7.0 + 12.0 * k, 0.0, TAU, 32, Color(col, 1.0 - k), w, true)
		"geode":
			# Расколотая жеода: кристаллы внутри скорлупы.
			_g.draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 28, col, w, true)
			for i in 7:
				var d := Vector2.from_angle(i * TAU / 7.0 + 0.2)
				_g.draw_colored_polygon(PackedVector2Array([d * 3.0 + d.orthogonal() * 2.2, d * 11.0, d * 3.0 - d.orthogonal() * 2.2]), Color(col, 0.85))
		"swarm":
			# Рой галек стягивается в сгусток.
			for i in 9:
				var a := i * TAU / 9.0 + _time * 0.4
				var r := 8.0 + 8.0 * fmod(i * 0.37, 1.0)
				_g.draw_circle(Vector2.from_angle(a) * r, 2.2, Color(col, 0.8))
			_g.draw_circle(Vector2.ZERO, 4.0, col)
		"selective":
			# Сито: из потока проходит только нужное.
			_g.draw_polyline(PackedVector2Array([Vector2(-16, -12), Vector2(16, -12), Vector2(4, 4), Vector2(4, 15), Vector2(-4, 15), Vector2(-4, 4), Vector2(-16, -12)]), col, w, true)
			for v in [Vector2(-8, -17), Vector2(1, -19), Vector2(10, -16)]:
				_g.draw_circle(v, 2.2, Color(col, 0.75))
		"mat_metal":
			# Подкова магнита.
			_g.draw_arc(Vector2(0, 2), 11.0, 0.0, PI, 20, col, 5.0, true)
			_g.draw_line(Vector2(-11, 2), Vector2(-11, -12), col, 5.0, true)
			_g.draw_line(Vector2(11, 2), Vector2(11, -12), col, 5.0, true)
			_g.draw_line(Vector2(-14, -12), Vector2(-8, -12), Color(col, 0.6), 3.0, true)
			_g.draw_line(Vector2(8, -12), Vector2(14, -12), Color(col, 0.6), 3.0, true)
		"mat_ice":
			for i in 3:
				var d := Vector2.from_angle(i * PI / 3.0)
				_g.draw_line(-d * 16.0, d * 16.0, col, w, true)
				for sgn in [-1.0, 1.0]:
					var t: Vector2 = d * 10.0 * sgn
					_g.draw_line(t, t + (d * sgn).rotated(0.8) * 5.0, Color(col, 0.75), 1.5, true)
					_g.draw_line(t, t + (d * sgn).rotated(-0.8) * 5.0, Color(col, 0.75), 1.5, true)
		"mat_silicate":
			# Кристалл кварца: вытянутая шестигранная призма.
			var pts := PackedVector2Array([Vector2(0, -17), Vector2(8, -9), Vector2(8, 10), Vector2(0, 17), Vector2(-8, 10), Vector2(-8, -9), Vector2(0, -17)])
			_g.draw_polyline(pts, col, w, true)
			_g.draw_line(Vector2(0, -17), Vector2(0, 17), Color(col, 0.55), 1.3, true)
		"mat_carbon":
			# Бензольное кольцо — знак органики.
			var pts := PackedVector2Array()
			for i in 7:
				pts.append(Vector2.from_angle(i * TAU / 6.0 + PI / 6.0) * 15.0)
			_g.draw_polyline(pts, col, w, true)
			_g.draw_arc(Vector2.ZERO, 8.0, 0.0, TAU, 24, Color(col, 0.75), 1.6, true)
		_:
			for i in 4:
				var d := Vector2.from_angle(i * TAU / 4.0)
				_g.draw_colored_polygon(PackedVector2Array([Vector2.ZERO + d.orthogonal() * 3.0, d * 16.0, -d.orthogonal() * 3.0]), col)


func _ellipse(c: Vector2, radii: Vector2, rot: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 20:
		pts.append(c + (Vector2.from_angle(i * TAU / 20.0) * radii).rotated(rot))
	_g.draw_colored_polygon(pts, col)



func _ellipse_arc(c: Vector2, radii: Vector2, rot: float, col: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for i in 33:
		pts.append(c + (Vector2.from_angle(i * TAU / 32.0) * radii).rotated(rot))
	_g.draw_polyline(pts, col, width, true)

func _hit_test(screen_pos: Vector2) -> String:
	var local := (screen_pos - _canvas.position) / _canvas.scale.x
	for id in Skills.order:
		if _is_visible_node(id) and local.distance_to(_node_pos(id)) <= NODE_RADIUS + 12.0:
			return id
	return ""


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_cam_dur = 0.0
				_pressed = true
				_dragging = false
				_press_pos = event.position
			elif _pressed:
				_pressed = false
				if not _dragging and _touches.size() < 2:
					_select(_hit_test(event.position))
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(event.position, 1.1)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(event.position, 1.0 / 1.1)
	elif event is InputEventMouseMotion and _pressed and _touches.size() < 2:
		if not _dragging and event.position.distance_to(_press_pos) > TAP_SLOP:
			_dragging = true
		if _dragging:
			_canvas.position += event.relative
	elif event is InputEventMagnifyGesture:
		_zoom_at(event.position, event.factor)


func _notification(what: int) -> void:
	# Кнопка «назад» на Android закрывает древо.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and visible:
		close()


## Щипок двумя пальцами, а на ПК Tab/Esc закрывают древо.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_TAB, KEY_ESCAPE]:
		close()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		_pinch_dist = _current_pinch_dist()
		if _touches.size() >= 2:
			_dragging = true
	elif event is InputEventScreenDrag and _touches.has(event.index):
		_touches[event.index] = event.position
		if _touches.size() >= 2:
			var d := _current_pinch_dist()
			if _pinch_dist > 0.0:
				var mid: Vector2 = (_touches.values()[0] + _touches.values()[1]) * 0.5
				_zoom_at(mid, d / _pinch_dist)
			_pinch_dist = d


func _current_pinch_dist() -> float:
	if _touches.size() < 2:
		return 0.0
	var v := _touches.values()
	return (v[0] as Vector2).distance_to(v[1])


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	_cam_dur = 0.0
	var old := _canvas.scale.x
	var new_scale := clampf(old * factor, ZOOM_RANGE.x, ZOOM_RANGE.y)
	_canvas.position = screen_pos - (screen_pos - _canvas.position) * (new_scale / old)
	_canvas.scale = Vector2(new_scale, new_scale)
