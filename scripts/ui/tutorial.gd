class_name Tutorial
extends Control
## Обучение с рассказчиком: Звездочёт ведёт новичка по первым шагам.
##
## Карточка с его словами стоит внизу справа (слева стик, его не закрываем),
## а пока открыта книга знаний — внизу слева, чтобы не загораживать описание
## навыка. Золотая стрелка показывает, куда смотреть или нажать. Шаг либо
## ждёт действия в игре, либо кнопку «Дальше».

const CHARS_PER_SECOND := 45.0
const SPOT_SHADER := preload("res://shaders/spotlight.gdshader")
const GOLD := Color(1.0, 0.82, 0.45)
const CARD_WIDTH := 600.0
const STEPS := [
	{
		"id": "move",
		"text": "Здравствуй, путник. Я Звездочёт и буду рядом, пока ты осваиваешься. Коснись левой половины экрана и веди пальцем: так ты летишь.",
	},
	{
		"id": "absorb",
		"text": "Видишь крупицы вокруг? Подлети к ним: слабые электрические силы притянут их, и они прилипнут. Собери три пылинки.",
	},
	{
		"id": "currency",
		"text": "Каждая пылинка приносит звёздную пыль. Слева сверху видно, сколько её у тебя. За неё ты будешь узнавать новое.",
		"tap": true,
	},
	{
		"id": "composition",
		"text": "Ты состоишь из того же, что и пыль вокруг: силикатов, металла, углерода и льда. Сверху твой состав. Слева название зоны диска: ближе к звезде больше камня и металла, а за снеговой линией много льда.",
		"tap": true,
	},
	{
		"id": "big",
		"text": "Пылинки с тонким кольцом крупнее обычных. Пока тебе их не удержать, но знания помогут и с этим.",
		"tap": true,
	},
	{
		"id": "collect",
		"text": "Собери звёздную пыль на первое знание. Её хватит, когда счётчик внизу заполнится.",
	},
	{
		"id": "book",
		"text": "Хватает! Открой звёздную книгу справа сверху: в ней знания, которые делают тебя сильнее.",
	},
	{
		"id": "buy",
		"text": "Это древо знаний. Выбери «Начало» и изучи его: ты сможешь собирать пыль покрупнее.",
	},
	{
		"id": "close",
		"text": "Видишь, ветви потянулись дальше? Каждое знание открывает новые. Теперь возвращайся в полёт.",
	},
	{
		"id": "star",
		"text": "И последнее. Не подлетай близко к звезде: у неё так жарко, что пыль испаряется, а с ней и ты. Следи за надписью слева сверху. Дальше сам. Доброго пути, путник.",
		"tap": true,
		"button": "В путь",
	},
]
const NEEDS_START := ["collect", "book", "buy"]
# Звездочёт рассказывает о жизни гальки, когда пылинка дорастает до неё. Он не
# только говорит, но и показывает: останавливает время («pause»), ведёт камеру
# к тому, о чём речь («focus»), высвечивает и обводит это прямо в мире.
const PEBBLE_STEPS := [
	{
		"id": "p_intro",
		"text": "Поздравляю, путник: ты теперь галька, камешек размером с горошину. Я остановил время, чтобы показать тебе, как здесь всё устроено.",
		"tap": true,
		"pause": true,
		"focus": "player",
	},
	{
		"id": "p_drift",
		"text": "Ты уже так тяжёл, что отстаёшь от газа диска, и он дует тебе навстречу. Встречный ветер сносит тебя по спирали к звезде, туда, куда показывает стрелка. Чем крупнее галька, тем сильнее снос. Его скорость написана слева сверху.",
		"tap": true,
		"pause": true,
		"focus": "drift",
	},
	{
		"id": "p_small",
		"text": "Вот галька меньше тебя, её можно присоединить. Всё, что меньше тебя, тебе по силам. А совсем мелкие, меньше тебя в два с половиной раза, прилипают на любой скорости.",
		"tap": true,
		"pause": true,
		"focus": "small",
	},
	{
		"id": "p_big",
		"text": "А у этой кольцо пунктирное: она крупнее тебя. Её не удержать, от удара просто отскочишь. Подрастёшь, и придёт её черёд.",
		"tap": true,
		"pause": true,
		"focus": "big",
	},
	{
		"id": "p_join",
		"text": "Теперь попробуй сам. К гальке почти с тебя размером подлетай медленно и следи за дугой с твоей стороны: зелёная — вы слипнетесь, красная — удар слишком быстрый, от тебя отколются осколки. В пустоте тебя ничто не держит: отпустишь палец, и полетишь дальше по инерции, а тормозить надо, ведя палец назад.",
		"focus": "join",
	},
	{
		"id": "p_rings",
		"text": "Видишь светлое кольцо в диске? Это ловушка давления. Ветра там почти нет, поэтому гальки копятся. Хорошее место, чтобы расти.",
		"tap": true,
		"pause": true,
		"focus": "ring",
	},
	{
		"id": "p_book",
		"text": "В книге знаний проросла новая ветвь, «Галька». Её знания помогут бороться с ветром и мягче сталкиваться. Остальное я покажу, когда оно встретится. Твой путь к валуну начинается.",
		"tap": true,
		"button": "В путь",
	},
]
# Рассказ при превращении в валун.
const PLANET_STEPS := [
	{
		"id": "p_intro",
		"text": "Километр! Ты планетезималь: теперь тебя держит вместе собственная гравитация. Цель этапа — дорасти до тысячи километров и стать зародышем планеты.",
		"tap": true,
		"pause": true,
		"focus": "player",
	},
	{
		"id": "p_pull",
		"text": "Сплошной круг — зона захвата. Всё, что медленно вплывает в него, падает на тебя и прилипает.",
		"tap": true,
		"pause": true,
		"focus": "pull",
	},
	{
		"id": "p_hill",
		"text": "Пунктир — сфера Хилла, граница твоего притяжения. Мелочь внутри неё тянется к тебе и закручивается вокруг, а снаружи её держит звезда.",
		"tap": true,
		"pause": true,
		"focus": "hill",
	},
	{
		"id": "p_calm",
		"text": "Вся мелочь вокруг — это рой. Носишься быстро — твоя гравитация раскачивает его, мелочь мечется, и круг захвата сжимается. Крупные соседи раскачивают рой так же. Лети спокойно и держись подальше от больших тел: рой утихнет, и захват станет шире. Насколько — видно слева, в строке «Рой».",
		"tap": true,
		"pause": true,
		"focus": "pull",
	},
	{
		"id": "p_rivals",
		"text": "Это сосед, такая же планетезималь, над ним — его размер. Дуга у его края подсказывает исход: зелёная — сольётесь, жёлтая — отколете друг от друга куски, красная — раскол. Медленнее второй космической тела всегда сливаются, даже с крупным соседом.",
		"tap": true,
		"pause": true,
		"focus": "rival",
	},
	{
		"id": "p_zone",
		"text": "Ты летишь по орбите вокруг звезды. Светлое кольцо — твоя кормовая полоса, всё вещество на этой орбите. Ты его выедаешь, и кольцо тускнеет. Сменить орбиту можно, но медленно: держи стик к звезде или от неё.",
		"tap": true,
		"pause": true,
		"focus": "band",
	},
	{
		"id": "p_al",
		"text": "Внутри тебя распадается алюминий-26 и греет недра, а крупное тело держит тепло лучше. Вырастешь быстро, пока он не угас, — недра дойдут до 1250 K и расплавятся: появится железное ядро, ты станешь прочнее, а вещество заработает вдвое. Не успеешь — останешься хондритом: хондры будут попадаться вдвое чаще. Следи за строкой «Недра» слева.",
		"tap": true,
		"pause": true,
		"focus": "player",
	},
	{
		"id": "p_book",
		"text": "В книге знаний открылась глава «Планетезималь». Расти до тысячи километров: там тебя ждёт судьба зародыша планеты, и выберет её твой состав.",
		"tap": true,
		"pause": true,
		"focus": "player",
	},
]

const EMBRYO_STEPS := [
	{
		"id": "e_intro",
		"text": "Тысяча километров! Ты зародыш планеты. Состав и место в диске выбрали тебе путь — он написан вверху.",
		"tap": true,
		"pause": true,
		"focus": "player",
	},
	{
		"id": "e_next",
		"text": "Здесь наш путь пока обрывается: этап зародыша ещё строится. А ты можешь расти дальше и собирать всё, до чего дотянешься.",
		"tap": true,
		"pause": true,
		"focus": "player",
	},
]

const BOULDER_STEPS := [
	{
		"id": "b_intro",
		"text": "Ты стал валуном, камнем ростом с человека. Я снова остановил время: здесь всё устроено иначе.",
		"tap": true,
		"pause": true,
		"focus": "player",
	},
	{
		"id": "b_food",
		"text": "Гальки, с которыми ты недавно осторожно слипался, теперь мелочь. Они прилипают на любой скорости и приносят много звёздной пыли. Сметай их.",
		"tap": true,
		"pause": true,
		"focus": "food",
	},
	{
		"id": "b_drift",
		"text": "Но берегись: ты попал в метровый барьер. Тела твоего размера газ тормозит сильнее всего, и сносит тебя к звезде почти вдвое быстрее, чем гальку. Чем крупнее станешь, тем слабее снос.",
		"tap": true,
		"pause": true,
		"focus": "drift",
	},
	{
		"id": "b_small",
		"text": "По-настоящему расти помогают малые валуны. С ними всё как раньше: подлетай медленно, пока дуга зелёная.",
		"tap": true,
		"pause": true,
		"focus": "small",
	},
	{
		"id": "b_big",
		"text": "А этот валун тебе пока не по силам: пунктир значит, что не удержишь. Удар о такой отколет от тебя куски, обходи его.",
		"tap": true,
		"pause": true,
		"focus": "big",
	},
	{
		"id": "b_rings",
		"text": "В кольцах-ловушках ветра почти нет. Если снос станет слишком сильным, укройся там.",
		"tap": true,
		"pause": true,
		"focus": "ring",
	},
	{
		"id": "b_book",
		"text": "В книге знаний проросла ветвь «Валун». Первое знание поможет держаться против ветра. Твой путь к планетезимали начинается.",
		"tap": true,
		"button": "В путь",
	},
]
# Подсказки по ходу игры: Звездочёт показывает явление, когда оно впервые рядом.
const TIPS := {
	"rival": {
		"id": "t_rival",
		"text": "Сосед! Такая же планетезималь. Подходи медленно, пока дуга у его края зелёная, — и сольётесь. С разгону выйдет скол или раскол. Только помни: крупные соседи раскачивают рой вокруг.",
		"tap": true,
		"pause": true,
		"focus": "spot",
	},
	"twin": {
		"id": "t_twin",
		"text": "Близнец: тело почти твоего размера на твоей же орбите. Подойди к нему совсем медленно, и вы слипнетесь в контактную пару, как Аррокот на краю Солнечной системы.",
		"tap": true,
		"pause": true,
		"focus": "spot",
	},
	"zone": {
		"id": "t_zone",
		"text": "Кормовая полоса почти выедена: кольцо потускнело, добычи всё меньше. Держи стик к звезде или от неё и перейди на соседнюю орбиту — там кольцо ярче.",
		"tap": true,
		"pause": true,
		"focus": "band",
	},
	"al_warm": {
		"id": "t_al_warm",
		"text": "Недра раскаляются: строка «Недра» слева ползёт к 1250 K. Расти быстрее, пока алюминий не угас, — и расплавишься: железное ядро, прочность, вещество вдвое сильнее. Не успеешь — останешься хондритом, и хондры будут попадаться вдвое чаще. Оба пути годятся.",
		"tap": true,
		"pause": true,
		"focus": "player",
	},
	"melt": {
		"id": "t_melt",
		"text": "Недра расплавились! Тяжёлое железо стекло в центр и стало ядром, камень всплыл корой. Ты на 30% прочнее, бонус твоего вещества вдвое сильнее, а в книге открылось «Железное сердце». Состав застыл: по нему определится, какой планетой ты станешь.",
		"tap": true,
		"pause": true,
		"focus": "player",
	},
	"heat": {
		"id": "t_heat",
		"text": "Рой взбудоражен: мелочь носится, и круг захвата сжался. Раскачивает его твоя гравитация, когда ты летишь быстро, и крупные соседи рядом. Притормози или отойди от больших тел — рой утихнет, и круг снова станет широким.",
		"tap": true,
		"pause": true,
		"focus": "pull",
	},
	"hill": {
		"id": "t_hill",
		"text": "Сотня километров! Пунктир вокруг — сфера Хилла. Внутри неё твоё притяжение сильнее прилива звезды, и галька, что сюда залетит, твоя почти наверняка.",
		"tap": true,
		"pause": true,
		"focus": "hill",
	},
	"eddy": {
		"id": "t_eddy",
		"text": "Смотри: газ закрутился в вихрь. Гальки в нём несутся по кругу, стрелки показывают течение. Добыча внутри в полтора раза ценнее, но плыви по течению: встречный удар раскалывает. Вихрь продержится полминуты, нырять или нет, решай сам.",
		"tap": true,
		"pause": true,
		"focus": "eddy",
	},
	"swarm": {
		"id": "t_swarm",
		"text": "Потоковая неустойчивость! Газ согнал мелкие гальки в тесный рой. Все они тебе по силам, но через двадцать секунд рой рассеется. Поспеши.",
		"tap": true,
		"pause": true,
		"focus": "spot",
	},
	"chip": {
		"id": "t_chip",
		"text": "Ох! Удар был слишком быстрым, и от тебя откололись осколки. Видишь крошки вокруг? Это твоё вещество, его можно собрать обратно. Перед касанием сбрасывай скорость, пока дуга не станет зелёной.",
		"tap": true,
		"pause": true,
		"focus": "chip",
	},
	"chunks": {
		"id": "t_chunks",
		"text": "Ты врезался в гальку, которую пока не удержать, и отбил от неё куски. Они мелкие: собирай их на любой скорости. Только помни, что и сам при ударе теряешь вещество. Мелочь вроде этой прилипает всегда, как пыль.",
		"tap": true,
		"pause": true,
		"focus": "spot",
	},
	"shadow": {
		"id": "t_shadow",
		"text": "Видишь светлую полосу за этим валуном? Это ветровая тень: он заслоняет газ. В ней снос к звезде почти пропадает, и туда же прибивает мелочь. Держись за ним, только не врежься.",
		"tap": true,
		"pause": true,
		"focus": "spot",
	},
	"chondrule": {
		"id": "t_chondrule",
		"text": "Внутри гальки оказалась хондра: капля камня, которую расплавила вспышка звезды, и она застыла стеклянной бусиной. Хондры редкие. Копи их: за хондры в книге открываются способности, вроде пылевого гало, которое само собирает мелочь.",
		"tap": true,
		"pause": true,
		"focus": "spot",
	},
	"gravity": {
		"id": "t_gravity",
		"text": "Чувствуешь? Ты стал так тяжёл, что мелочь в этом круге сама плывёт к тебе. Это уже не липкость, а твоя собственная гравитация. Чем ближе к километру, тем сильнее она тянет.",
		"tap": true,
		"pause": true,
		"focus": "pull",
	},
	"material": {
		"id": "t_material",
		"text": "Вещество, которое ты собрал, теперь тоже работает на тебя. Под полосой состава написано, что оно даёт валуну. Металл тяжёлый и меньше сносится, камень прочный, лёд липкий, а пористый углерод гасит удары.",
		"tap": true,
		"pause": true,
		"focus": "material",
	},
	"herald": {
		"id": "t_herald",
		"text": "Смотри, галька! Она в тысячу раз крупнее тебя и в миллиард раз тяжелее. Вблизи её край кажется ровной стеной, и видно, из чего она слеплена: круглые застывшие капли-хондры, белые зёрна первого вещества диска и искры металла в тёмной пыли. Её не сдвинуть: от края ты отскочишь. Скоро и ты станешь такой.",
		"tap": true,
		"pause": true,
		"focus": "spot",
	},
	"giant": {
		"id": "t_giant",
		"text": "Осторожно, рядом Странник! Это валун в десятки раз крупнее тебя: в диске уже летают тела всех размеров, и когда-нибудь ты станешь таким же. Съесть его нельзя, и он твёрже тебя: лёгкий толчок собьёт с тебя крошку, а с разгону расколешься на куски.",
		"tap": true,
		"pause": true,
		"focus": "spot",
	},
	"crash": {
		"id": "t_crash",
		"text": "Видел? Два валуна врезались друг в друга и разлетелись облаком обломков. Обломки прилипают на любой скорости и стоят вдвое дороже, но они быстрые, а через полминуты рассыплются в пыль. Лови!",
		"tap": true,
		"pause": true,
		"focus": "spot",
	},
	"clump": {
		"id": "t_clump",
		"text": "Смотри, в кольце мелочь сбилась в сгусток, и он сжимается. Через 25 секунд всё, что не собрали, слипнется в новый валун. Кто успеет в центр, заберёт больше всех.",
		"tap": true,
		"pause": true,
		"focus": "spot",
	},
	"geode": {
		"id": "t_geode",
		"text": "Жеода! Внутри этой гальки были кристаллы, поэтому она принесла намного больше звёздной пыли. Такие попадаются редко, а знание «Жеоды» в книге поможет находить их чаще.",
		"tap": true,
		"pause": true,
		"focus": "spot",
	},
	"ice": {
		"id": "t_ice",
		"text": "Здесь, ближе к звезде, тепло, и лёд в тебе испаряется: видишь голубой пар? Сверху написано, сколько льда ты теряешь. За снеговой линией, дальше от звезды, лёд сохраняется.",
		"tap": true,
		"pause": true,
		"focus": "ice",
	},
}

var main: Node  # сцена игры: игрок, интерфейс, древо
var steps: Array = STEPS
var pebble := false  # рассказ о гальке, а не первое обучение
var boulder := false  # рассказ о валуне
var tip := ""  # подсказка по ходу игры: какое явление показываем
var tip_pos := Vector2.INF  # где оно в мире (рой, жеода)
var start_delay := 2.2
var _step := -1
var _card: PanelContainer
var _name: Label
var _text: Label
var _progress: Label
var _next: Button
var _emblem: Control
var _pointer: Control
var _shown := 0.0
var _time := 0.0
var _step_time := 0.0
var _absorbed := 0
var _moved := 0.0
var _target := Vector2.INF  # куда показывает стрелка (экран), INF — никуда
var _done := false
var _spot: ColorRect  # затемнение вокруг того, что показываем
var _spot_k := 0.0
var _spot_center := Vector2.ZERO
var _spot_r := 0.0
var _focus := {}  # что показываем в мире: pos (или pebble) и радиус r
var _marks: Array = []  # обводки и подписи в мире
var _cam_active := false
var _cam_zoom := 1.0
var _paused := false
var _busy := false  # камера возвращается к игроку
var _join_wait := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.get_theme()
	_build()
	GameState.absorbed.connect(func(_a, _b, _c): _absorbed += 1)
	main.pebble_field.pebble_absorbed.connect(_on_pebble_absorbed)
	modulate.a = 0.0
	# Рассказчик появляется, когда камера уже приблизилась к пылинке.
	var tw := create_tween()
	tw.tween_interval(start_delay)
	tw.tween_callback(_show_step.bind(0))
	tw.tween_property(self, "modulate:a", 1.0, 0.8)


func _build() -> void:
	_spot = ColorRect.new()
	_spot.set_anchors_preset(Control.PRESET_FULL_RECT)
	_spot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spot.material = ShaderMaterial.new()
	_spot.material.shader = SPOT_SHADER
	_spot.visible = false
	add_child(_spot)
	_pointer = Control.new()
	_pointer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pointer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pointer.draw.connect(_draw_marks)
	_pointer.draw.connect(_draw_pointer)
	add_child(_pointer)

	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", UiTheme.painted_panel(22))
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	# Карточка стоит на нижнем крае и растёт вверх под длину реплики.
	_card.anchor_top = 1.0
	_card.anchor_bottom = 1.0
	_card.offset_top = -20.0
	_card.offset_bottom = -20.0
	_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_card.gui_input.connect(_on_card_input)
	add_child(_card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(row)
	_emblem = Control.new()
	_emblem.custom_minimum_size = Vector2(64, 64)
	_emblem.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_emblem.draw.connect(_draw_emblem)
	row.add_child(_emblem)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	_name = Label.new()
	_name.text = "Звездочёт"
	_name.add_theme_font_override("font", UiTheme.FONT_SERIF_BOLD)
	_name.add_theme_font_size_override("font_size", 20)
	_name.add_theme_color_override("font_color", Color(1.0, 0.82, 0.48))
	col.add_child(_name)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	_text.add_theme_font_override("font", UiTheme.FONT_SERIF_ITALIC)
	_text.add_theme_font_size_override("font_size", 20)
	_text.add_theme_color_override("font_color", UiTheme.PARCHMENT)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_text)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(bottom)
	_progress = Label.new()
	_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_progress.add_theme_font_override("font", UiTheme.FONT_SERIF_BOLD)
	_progress.add_theme_font_size_override("font_size", 19)
	_progress.add_theme_color_override("font_color", Color(1.0, 0.82, 0.48))
	bottom.add_child(_progress)
	var skip := Button.new()
	skip.text = "Без подсказок" if tip != "" else "Пропустить обучение"
	skip.flat = true
	skip.focus_mode = Control.FOCUS_NONE
	skip.add_theme_font_override("font", UiTheme.FONT_SERIF_ITALIC)
	skip.add_theme_font_size_override("font_size", 16)
	for key in ["font_color", "font_hover_color", "font_pressed_color"]:
		skip.add_theme_color_override(key, Color(UiTheme.PARCHMENT, 0.5))
	for state in ["normal", "hover", "pressed", "focus"]:
		skip.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	skip.pressed.connect(_skip)
	bottom.add_child(skip)
	_next = Button.new()
	_next.text = "Дальше"
	_next.custom_minimum_size = Vector2(150, 48)
	UiTheme.paint_button(_next, true, 20)
	_next.pressed.connect(_advance)
	bottom.add_child(_next)


func _show_step(i: int) -> void:
	if i >= steps.size():
		_finish()
		return
	var step: Dictionary = steps[i]
	# Кто уже изучил «Начало» (старое сохранение), тому эти шаги не нужны.
	if step.id in NEEDS_START and Skills.is_owned("start"):
		_show_step(i + 1)
		return
	if not _prepare_focus(step):
		_show_step(i + 1)  # показывать нечего: рядом нет такой гальки
		return
	_step = i
	_step_time = 0.0
	_join_wait = 0.0
	if step.get("pause", false):
		_set_paused(true)
	elif _paused:
		_set_paused(false)
	_shown = 0.0
	_absorbed = 0
	_moved = 0.0
	_text.text = step.text
	_text.visible_characters = 0
	_next.text = step.get("button", "Дальше")
	_next.visible = false
	_progress.text = ""
	# Новая реплика: карточка чуть вздрагивает, привлекая взгляд.
	_card.pivot_offset = _card.size * 0.5
	_card.scale = Vector2(0.97, 0.97)
	create_tween().tween_property(_card, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _advance() -> void:
	if _step < 0 or _done or _busy:
		return
	var next := _step + 1
	var paused_next: bool = next < steps.size() and steps[next].get("pause", false)
	if _cam_active and not paused_next:
		# Сначала камера плавно возвращается к игроку, потом время идёт снова.
		_busy = true
		_focus = {}
		_marks = []
		_release_camera(func() -> void:
			_busy = false
			_show_step(next))
	else:
		_show_step(next)


func _on_card_input(event: InputEvent) -> void:
	var tap: bool = (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
		or (event is InputEventScreenTouch and event.pressed)
	# Касание карточки допечатывает реплику сразу.
	if tap and _step >= 0 and _shown < _text.text.length():
		_shown = _text.text.length()
		_text.visible_characters = -1


func _skip() -> void:
	if tip != "":
		# «Без подсказок»: больше ничего не показываем по ходу игры.
		for k in TIPS:
			if not k in GameState.tips_seen:
				GameState.tips_seen.append(k)
	_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	_focus = {}
	_marks = []
	_target = Vector2.INF
	if tip != "":
		if not tip in GameState.tips_seen:
			GameState.tips_seen.append(tip)
	elif boulder:
		GameState.boulder_intro_done = true
	elif pebble:
		GameState.pebble_intro_done = true
	else:
		GameState.tutorial_done = true
	GameState.save_game()
	if _cam_active:
		_release_camera(_fade_out)
	else:
		_fade_out()


func _fade_out() -> void:
	if _paused:
		_set_paused(false)
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.6)
	tw.tween_callback(queue_free)


func _process(delta: float) -> void:
	_time += delta
	var tree: SkillTreeScreen = main.tree_screen
	var hud: Hud = main.hud
	# В меню паузы и после гибели рассказчик молчит.
	visible = not main.player.dead and not main.pause_menu.visible
	_layout(tree.visible)
	_update_spot(delta)
	_pointer.queue_redraw()
	_emblem.queue_redraw()
	if _step < 0 or _done or not visible:
		return
	_step_time += delta
	var full := _text.text.length()
	if _shown < full:
		_shown = minf(_shown + CHARS_PER_SECOND * delta, full)
		_text.visible_characters = int(_shown)
	var step: Dictionary = steps[_step]
	# После паузы или книги знаний время снова останавливается, пока Звездочёт показывает.
	if step.get("pause", false) and not get_tree().paused and not tree.visible and not _busy:
		_set_paused(true)
	var typed := _shown >= full
	_next.visible = step.get("tap", false) and typed
	_target = Vector2.INF
	match step.id:
		"move":
			_target = Vector2(VirtualJoystick.RADIUS + 60.0, size.y - VirtualJoystick.RADIUS - 50.0)
			if main.joystick.output.length() > 0.3:
				_moved += delta
				_target = Vector2.INF
			if _moved > 1.2:
				_advance()
		"absorb":
			_progress.text = "%d / 3" % mini(_absorbed, 3)
			if _absorbed >= 3:
				_advance()
		"currency":
			_target = _center_of(hud._currency_label)
		"composition":
			_target = _center_of(hud._comp_bar)
		"collect":
			var cost := Skills.cost("start")
			_progress.text = "%d / %d" % [mini(int(GameState.currency), int(cost)), int(cost)]
			_target = _center_of(hud._currency_label)
			if GameState.currency >= cost:
				_advance()
		"book":
			_target = _center_of(hud._tree_button)
			if tree.visible:
				_advance()
		"buy":
			if Skills.is_owned("start"):
				_advance()
			elif tree._selected == "start":
				_target = _center_of(tree._buy_button)
			else:
				_target = tree._canvas.get_global_transform() * tree._node_pos("start")
		"close":
			_target = _center_of(tree.close_button)
			if not tree.visible:
				_advance()
		"p_drift":
			_target = _center_of(hud._wind_label)
		"p_join":
			_join_wait += delta
			_progress.text = "0 / 1"
			if _join_wait > 40.0:
				_next.visible = true  # не выходит — можно идти дальше
			var near := _nearest_pebble(true)
			_marks = []
			if near:
				_marks = [{"pebble": near, "label": "сюда", "color": GOLD}]
				var sp: Vector2 = get_viewport().get_canvas_transform() * main.pebble_field.world_pos(near)
				var rr: float = near.r * 1.45 * get_viewport().get_canvas_transform().get_scale().x
				if Rect2(Vector2.ZERO, size).grow(-40.0).has_point(sp):
					_target = sp + (size * 0.5 - sp).normalized() * maxf(rr - 30.0, 0.0)
				else:
					_target = sp.clamp(Vector2(60, 60), size - Vector2(60, 60))
		"p_book", "b_book":
			_target = _center_of(hud._tree_button)
		"b_drift":
			_target = _center_of(hud._wind_label)
		"t_ice":
			_target = _center_of(hud._heat_label) if hud._heat_label.visible else Vector2.INF


func _on_pebble_absorbed(_at: Vector2) -> void:
	if _step >= 0 and not _done and steps[_step].id == "p_join":
		_progress.text = "1 / 1"
		_advance()


func _center_of(c: Control) -> Vector2:
	return c.get_global_rect().get_center()


## Внизу справа в полёте, внизу слева над древом знаний.
func _layout(tree_open: bool) -> void:
	var w := CARD_WIDTH
	if tree_open:
		w = minf(CARD_WIDTH, size.x - SkillTreeScreen.INFO_WIDTH - 72.0)
	var x := 24.0 if tree_open else size.x - w - 24.0
	_card.offset_left = x
	_card.offset_right = x + w


## Медальон Звездочёта: тёмный круг, золотой обод и восьмилучевая звезда,
## вокруг которой по орбите бежит пылинка.
func _draw_emblem() -> void:
	var c := _emblem.size * 0.5
	var r := 30.0
	_emblem.draw_circle(c, r, Color(0.08, 0.05, 0.16))
	_emblem.draw_circle(c, r * 0.8, Color(0.14, 0.08, 0.24))
	_emblem.draw_arc(c, r, 0.0, TAU, 64, Color(1.0, 0.8, 0.45), 2.5, true)
	_emblem.draw_arc(c, r - 4.0, 0.0, TAU, 64, Color(1.0, 0.8, 0.45, 0.45), 1.0, true)
	var pts := PackedVector2Array()
	var spin := _time * 0.3
	for i in 16:
		var a := spin + i * TAU / 16.0
		var len := r * (0.62 if i % 4 == 0 else (0.36 if i % 2 == 0 else 0.16))
		pts.append(c + Vector2.from_angle(a) * len)
	_emblem.draw_colored_polygon(pts, Color(1.0, 0.86, 0.55))
	_emblem.draw_circle(c, 3.5, Color(1.0, 0.97, 0.88))
	var orbit := c + Vector2.from_angle(-_time * 1.4) * Vector2(r * 0.72, r * 0.72)
	_emblem.draw_circle(orbit, 2.2, Color(0.75, 0.88, 1.0))


## Стрелка покачивается и указывает на цель, вокруг цели расходятся кольца.
func _draw_pointer() -> void:
	if _target == Vector2.INF or not visible:
		return
	var t := _target
	var gold := Color(1.0, 0.82, 0.45)
	for k in 2:
		var p := fmod(_time * 0.8 + k * 0.5, 1.0)
		_pointer.draw_arc(t, 18.0 + 34.0 * p, 0.0, TAU, 48, Color(gold, 0.7 * (1.0 - p)), 2.5, true)
	var dir := (size * 0.5 - t).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.DOWN
	var bob := 8.0 * sin(_time * 5.0)
	var tip := t + dir * (44.0 + bob)
	var tail := tip + dir * 54.0
	var side := dir.orthogonal()
	var head := PackedVector2Array([tip, tip + dir * 22.0 + side * 15.0, tip + dir * 22.0 - side * 15.0])
	var outline := Color(0.12, 0.05, 0.0, 0.8)
	_pointer.draw_line(tip + dir * 18.0, tail, outline, 10.0, true)
	_pointer.draw_colored_polygon(PackedVector2Array([tip - dir * 3.0, head[1] + dir * 2.0 + side * 3.0, head[2] + dir * 2.0 - side * 3.0]), outline)
	_pointer.draw_line(tip + dir * 18.0, tail, gold, 6.0, true)
	_pointer.draw_colored_polygon(head, gold)


## Пока Звездочёт показывает, время стоит: мир замирает, а рассказчик и камера — нет.
func _set_paused(on: bool) -> void:
	_paused = on
	if on:
		main.joystick.reset()
		main.player.move_input = Vector2.ZERO
	get_tree().paused = on


## Что показать на шаге: точка в мире, обводки, подписи. false — показывать нечего.
func _prepare_focus(step: Dictionary) -> bool:
	_focus = {}
	_marks = []
	var kind: String = step.get("focus", "")
	if kind == "" or kind == "join":
		return true
	var pl: Player = main.player
	var pf: PebbleField = main.pebble_field
	var zoom: float = _cam_zoom if _cam_active else main.camera.zoom.x
	match kind:
		"player":
			_focus = {"pos": pl.position, "r": pl.radius * 2.4}
			_marks = [{"pos": pl.position, "r": pl.radius * 1.6, "label": "это ты", "color": GOLD}]
		"drift":
			var dir := pl.drift_velocity.normalized() if pl.drift_velocity.length() > 0.01 else -pl.position.normalized()
			var reach := pl.radius * 6.0
			_focus = {"pos": pl.position + dir * reach * 0.45, "r": reach * 0.85}
			_marks = [{"pos": pl.position, "r": pl.radius * 1.5, "color": GOLD},
				{"from": pl.position + dir * pl.radius * 1.9, "to": pl.position + dir * reach, "label": "снос к звезде", "color": Color(0.6, 0.85, 1.0)}]
		"food":
			var f := _nearest_pebble(true, true)
			if f == null:
				return false
			_focus = {"pebble": f, "r": pl.radius * 2.0}
			_marks = [{"pebble": f, "label": "еда", "color": Color(0.55, 1.0, 0.6)}]
		"small", "big":
			var p := _nearest_pebble(kind == "small")
			if p == null:
				# Рядом нет такой — подкладываем, чтобы было что показать. Ближе к звезде:
				# туда сносит, туда и смотреть.
				var side := Vector2.from_angle(pl.position.angle() + PI + randf_range(-0.8, 0.8))
				var r := pl.radius * (0.7 if kind == "small" else 1.3)
				p = pf.spawn_for_guide(pl.position + side * pl.radius * 7.0, r)
			_focus = {"pebble": p, "r": maxf(p.r * 2.6, pl.radius * 1.3)}
			if kind == "small":
				_marks = [{"pebble": p, "label": "можно присоединить", "color": Color(0.55, 1.0, 0.6)}]
			else:
				_marks = [{"pebble": p, "label": "не удержать", "color": Color(0.85, 0.9, 1.0), "dashed": true}]
		"ring":
			var d := pl.position.length()
			var best := INF
			for rc in GameData.PRESSURE_RINGS:
				if absf(rc - d) < absf(best - d):
					best = rc
			var dir := pl.position.normalized()
			var mid := (pl.position + dir * best) * 0.5
			var half := absf(best - d) * 0.5 + pl.radius * 8.0
			zoom = minf(zoom, size.y * 0.4 / half)
			_focus = {"pos": mid, "r": half, "zoom": zoom}
			_marks = [{"ring": best, "angle": dir.angle(), "label": "ловушка давления", "color": GOLD},
				{"pos": pl.position, "r": pl.radius * 1.5, "label": "ты", "color": Color(GOLD, 0.8)}]
		"eddy":
			if pf.eddy_left <= 0.0:
				return false
			var c: Vector2 = pf.eddy_center + main.dust_field.frame_offset
			zoom = minf(zoom, size.y * 0.42 / (pf.eddy_radius * 1.1))
			_focus = {"pos": c, "r": pf.eddy_radius * 1.05, "zoom": zoom}
			_marks = [{"pos": c, "r": pf.eddy_radius, "label": "вихрь", "color": Color(0.75, 0.9, 1.0), "flow": true}]
		"spot":
			if tip_pos == Vector2.INF:
				return false
			var r: float = main.dust_field.view_radius() * {"swarm": 0.25, "shadow": 0.18, "crash": 0.25, "clump": 0.3, "giant": 0.45, "herald": 0.2, "rival": 0.08, "twin": 0.1}.get(tip, 0.1)
			_focus = {"pos": tip_pos, "r": r}
			_marks = [{"pos": tip_pos, "r": r * 0.8, "label": {"swarm": "рой", "geode": "жеода", "chunks": "куски", "shadow": "ветровая тень", "crash": "обломки", "clump": "сгусток", "chondrule": "хондра", "giant": "Странник", "herald": "галька", "rival": "сосед", "twin": "близнец"}.get(tip, ""), "color": GOLD}]
		"rival":
			var at: Vector2 = main.rivals.nearest_spot()
			if at == Vector2.INF:
				at = main.rivals.spawn_for_guide()
			if at == Vector2.INF:
				return false
			var rr: float = pl.radius * 2.2
			_focus = {"pos": (at + pl.position) * 0.5, "r": at.distance_to(pl.position) * 0.6 + rr}
			_marks = [{"pos": at, "r": rr * 0.8, "label": "сосед", "color": GOLD}]
		"band":
			var d := pl.position.length()
			var r0: float = GameData.zone_bin(d) * GameData.ZONE_BIN
			var r1: float = r0 + GameData.ZONE_BIN
			var dir := pl.position.normalized()
			var half := GameData.ZONE_BIN * 0.6
			zoom = minf(zoom, size.y * 0.42 / half)
			_focus = {"pos": dir * (r0 + r1) * 0.5, "r": half, "zoom": zoom}
			_marks = [{"ring": r0 + GameData.ZONE_BIN * 0.02, "angle": dir.angle(), "label": "", "color": GOLD},
				{"ring": r1 - GameData.ZONE_BIN * 0.02, "angle": dir.angle(), "label": "кормовая полоса", "color": GOLD},
				{"pos": pl.position, "r": pl.radius * 1.5, "label": "ты", "color": Color(GOLD, 0.8)}]
		"hill":
			var hr: float = pl.hill_radius()
			zoom = minf(zoom, size.y * 0.42 / hr)
			_focus = {"pos": pl.position, "r": hr * 1.05, "zoom": zoom}
			_marks = [{"pos": pl.position, "r": hr, "label": "сфера Хилла", "color": Color(0.7, 0.9, 1.0), "dashed": true}]
		"pull":
			var pr: float = pl.pull_radius()
			_focus = {"pos": pl.position, "r": pr * 1.05}
			_marks = [{"pos": pl.position, "r": pr, "label": "захват" if GameState.is_planet() else "притяжение", "color": Color(0.75, 0.85, 1.0)}]
		"material":
			var type := GameState.body_type()
			_focus = {"pos": pl.position, "r": pl.radius * 3.0}
			_marks = [{"pos": pl.position, "r": pl.radius * 1.6, "label": GameData.BODY_TYPES[type].name.to_lower(),
				"color": GameData.MATERIALS[type].color if GameData.MATERIALS.has(type) else GOLD}]
		"chip":
			_focus = {"pos": pl.position, "r": pl.radius * 4.0}
			_marks = [{"pos": pl.position, "r": pl.radius * 3.2, "label": "осколки", "color": Color(1.0, 0.55, 0.4)}]
		"ice":
			_focus = {"pos": pl.position, "r": pl.radius * 3.0}
			_marks = [{"pos": pl.position, "r": pl.radius * 2.2, "label": "пар", "color": Color(0.6, 0.82, 1.0)}]
	_focus_camera(_focus_world(), _focus.get("zoom", zoom))
	return true


## Ближайшая галька, которую можно (или нельзя) присоединить, в том числе за краем экрана.
func _nearest_pebble(small: bool, food := false) -> PebbleField.Pebble:
	var pf: PebbleField = main.pebble_field
	var pp: Vector2 = main.player.position
	var lim: float = main.dust_field.view_radius() * 1.4
	var best: PebbleField.Pebble = null
	var bd := INF
	for p in pf.pebbles:
		if p.food != food:
			continue
		if not food and (pf.absorbable(p) != small or (small and pf.is_easy(p))):
			continue  # крошечную показывать не стоит: её легко спутать с пылью
		var d := pf.world_pos(p).distance_to(pp)
		if d < bd and d < lim:
			bd = d
			best = p
	return best


func _focus_world() -> Vector2:
	if _focus.has("pebble"):
		return main.pebble_field.world_pos(_focus.pebble)
	return _focus.get("pos", Vector2.ZERO)


## Камера плывёт к тому, что показываем. Пока время стоит, её ведёт рассказчик.
func _focus_camera(pos: Vector2, zoom: float) -> void:
	var cam: Camera2D = main.camera
	if not _cam_active:
		_cam_active = true
		_cam_zoom = cam.zoom.x
		cam.position_smoothing_speed = 2.4
	# Показанное встаёт чуть левее и выше центра: справа внизу карточка Звездочёта.
	cam.position = pos + Vector2(180.0, 70.0) / zoom
	create_tween().tween_property(cam, "zoom", Vector2(zoom, zoom), 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _release_camera(then: Callable) -> void:
	var cam: Camera2D = main.camera
	cam.position = main.player.position
	var tw := create_tween()
	tw.tween_property(cam, "zoom", Vector2(_cam_zoom, _cam_zoom), 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_interval(0.15)
	tw.tween_callback(func() -> void:
		cam.position_smoothing_speed = 6.0
		_cam_active = false
		then.call())


## Всё вокруг показанного чуть темнеет, оно само остаётся в круге света.
func _update_spot(delta: float) -> void:
	var on: bool = not _focus.is_empty() and visible and not main.tree_screen.visible
	_spot_k = move_toward(_spot_k, 1.0 if on else 0.0, delta * 2.5)
	_spot.visible = _spot_k > 0.0
	if not _spot.visible:
		return
	if on:
		var ct := get_viewport().get_canvas_transform()
		_spot_center = ct * _focus_world()
		_spot_r = float(_focus.r) * ct.get_scale().x
	var m: ShaderMaterial = _spot.material
	m.set_shader_parameter("rect_size", _spot.size)
	m.set_shader_parameter("center", _spot_center)
	m.set_shader_parameter("radius", _spot_r)
	m.set_shader_parameter("strength", _spot_k)


## Обводки и подписи прямо на объектах мира. Обводка дорисовывается кистью по кругу.
func _draw_marks() -> void:
	if _marks.is_empty() or not visible or main.tree_screen.visible:
		return
	var ct := get_viewport().get_canvas_transform()
	var sc := ct.get_scale().x
	var grow := 1.0 - pow(1.0 - clampf(_step_time / 0.8, 0.0, 1.0), 3.0)
	var pf: PebbleField = main.pebble_field
	for m in _marks:
		var col: Color = m.get("color", GOLD)
		var label: String = m.get("label", "")
		if m.has("ring"):
			var rr: float = m.ring
			var ang: float = m.angle
			var span := clampf(size.x / (sc * rr) * 0.75, 0.01, 0.6) * grow
			var pts := PackedVector2Array()
			for k in 41:
				pts.append(ct * (Vector2.from_angle(ang - span + 2.0 * span * k / 40.0) * rr))
			_pointer.draw_polyline(pts, Color(col, 0.18), 16.0, true)
			_pointer.draw_polyline(pts, Color(col, 0.9), 3.0, true)
			_label(ct * (Vector2.from_angle(ang) * rr) + Vector2(0, -40), label, col, grow)
			continue
		if m.has("from"):
			var a: Vector2 = ct * m.from
			var b: Vector2 = a.lerp(ct * m.to, grow)
			var dir := (b - a).normalized()
			var dash := 16.0
			var off := fmod(_time * 30.0, dash * 2.0)
			var len := a.distance_to(b) - 18.0
			var s := -off
			while s < len:
				var s0 := maxf(s, 0.0)
				var s1 := minf(s + dash, len)
				if s1 > s0:
					_pointer.draw_line(a + dir * s0, a + dir * s1, col, 4.0, true)
				s += dash * 2.0
			var side := dir.orthogonal()
			_pointer.draw_colored_polygon(PackedVector2Array([b, b - dir * 22.0 + side * 12.0, b - dir * 22.0 - side * 12.0]), col)
			_label(b + Vector2(0, 34), label, col, grow)
			continue
		var w: Vector2
		var r: float
		if m.has("pebble"):
			if not m.pebble in pf.pebbles:
				continue
			w = pf.world_pos(m.pebble)
			r = m.pebble.r * 1.45
		else:
			w = m.pos
			r = m.r
		var c: Vector2 = ct * w
		var rs := maxf(r * sc, 18.0)
		var start := -PI * 0.5
		if m.get("dashed", false):
			for k in 28:
				var a0 := start + k * TAU / 28.0
				if a0 - start > TAU * grow:
					break
				_pointer.draw_arc(c, rs, a0, a0 + TAU / 84.0, 3, col, 2.0, true)
		else:
			_pointer.draw_arc(c, rs + 2.0, start, start + TAU * grow, 64, Color(col, 0.22), 9.0, true)
			_pointer.draw_arc(c, rs, start, start + TAU * grow, 64, col, 2.5, true)
		var pulse := fmod(_time * 0.7, 1.0)
		_pointer.draw_arc(c, rs * (1.0 + 0.3 * pulse), 0.0, TAU, 48, Color(col, 0.45 * (1.0 - pulse) * grow), 2.0, true)
		if m.get("flow", false):
			# Стрелки течения по кругу вихря.
			for k in 8:
				var wp := w + Vector2.from_angle(k * TAU / 8.0 + _time * 0.4) * r * 0.72
				var f := pf.eddy_flow(wp)
				if f.length() < 0.001:
					continue
				var p0 := ct * wp
				var fd := (ct * (wp + f.normalized() * r * 0.1) - p0).normalized()
				var fs := fd.orthogonal()
				_pointer.draw_polyline(PackedVector2Array([p0 - fd * 12.0 + fs * 10.0, p0, p0 - fd * 12.0 - fs * 10.0]), Color(col, 0.9 * grow), 3.5, true)
		_label(c + Vector2(0, rs + 30.0), label, col, grow)


func _label(at: Vector2, text: String, col: Color, k: float) -> void:
	if text == "":
		return
	var font: Font = UiTheme.FONT_SERIF_BOLD
	var fs := 22
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := Vector2(clampf(at.x - w * 0.5, 12.0, size.x - w - 12.0), clampf(at.y, 30.0, size.y - 12.0))
	_pointer.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 7, Color(0.06, 0.02, 0.1, 0.85 * k))
	_pointer.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col, k))
