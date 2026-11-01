extends Node2D
## События этапа гиганта: у каждого ядра своя игра.
##
## Ледяной гигант ловит кометный рой с окраин диска, Юпитер из камня
## глотает соседний зародыш, плотный железный гигант полем захватывает
## блуждающее тело в луны, тёмный держится в углеродной туче (вихрь сажи),
## а горячий у самой звезды уходит от её вспышки.
## Тип тела добавляет оттенок: хондрит, Титан и парниковый мир получают своё.
##
## Цели — настоящие тела и вихри мира (system_world.gd): их видно, их рвёт
## прилив, как всё остальное. HUD берёт отсюда метку на карте и подсказку.

const FIRST := 35.0          # первое событие, секунд от начала этапа
const GAP := Vector2(55.0, 80.0)
const STRAY_MOONS := 6       # больше лун не захватить даже сильным полем
const COMETS := 7
const COMETS_WIN := 3
const DEBRIS := 9
const DEBRIS_WIN := 4

const KINDS := {
	"comets": {
		"title": "Кометный рой",
		"sub": "с окраин диска падает рой ледяных комет: порви приливом хотя бы три, пока рой не ушёл к звезде",
		"time": 30.0, "color": Color(0.62, 0.86, 1.0),
		"fail": "Рой прошёл мимо",
	},
	"rival": {
		"title": "Соседний зародыш",
		"sub": "в щель вошёл чужой зародыш: догони и порви его, пока его не выбросило",
		"time": 30.0, "color": Color(0.9, 0.7, 0.5),
		"fail": "Сосед ушёл: его выбросило из щели",
	},
	"stray": {
		"title": "Блуждающее тело",
		"sub": "мимо идёт железное тело: подойди, и поле захватит его в луны, а не порвёт",
		"time": 30.0, "color": Color(0.8, 0.82, 0.86),
		"fail": "Тело ушло на свою орбиту",
	},
	"cloud": {
		"title": "Углеродная туча",
		"sub": "в диске закрутился вихрь сажи: держись в нём, пока он живёт, и пей газ быстрее",
		"time": 30.0, "color": Color(0.85, 0.55, 0.3),
		"fail": "",
	},
	"debris": {
		"title": "Обломки столкновения",
		"sub": "впереди по орбите столкнулись два зародыша: облако обломков ещё не разлетелось. Собери хотя бы четыре",
		"time": 35.0, "color": Color(0.95, 0.78, 0.55),
		"fail": "Обломки разлетелись",
	},
	"flare": {
		"title": "Вспышка звезды",
		"sub": "молодая звезда вспыхивает и сдувает газ вокруг себя: уйди дальше отмеченной границы",
		"time": 15.0, "color": Color(1.0, 0.5, 0.3),
		"fail": "Вспышка сдула газ вокруг тебя: диск рассеется раньше",
	},
}

var stage                    # giant_stage.gd
var kind := ""               # текущее событие, "" — нет
var r := 0.0                 # орбита цели
var t := 0.0                 # секунд до конца события
var inside := 0.0            # секунд внутри тучи
var caught := 0              # комет поймано
var _targets: Array = []     # тела мира, что относятся к событию
var _vortex: Dictionary = {}
var _next := FIRST
var _last := ""
var _time := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func bind(world: GiantWorld) -> void:
	world.body_eaten.connect(_on_eaten)


## Какое событие у этого гиганта: решает ядро (флейвор).
static func kind_for(flavor: String) -> String:
	match flavor:
		"giant_ice":
			return "comets"
		"giant_dense":
			return "stray"
		"giant_dark":
			return "cloud"
		"giant_hot":
			return "flare"
	return "rival"


## Что может случиться сейчас. В кормовой зоне только событие своего ядра,
## потом к нему добавляются чужие, но своё остаётся самым частым, и одно и то
## же не идёт два раза подряд.
func _pick() -> String:
	var own := kind_for(str(GameState.giant.get("flavor", "giant_cold")))
	if stage.era < 2:
		return own
	var w := {"rival": 1.0, "comets": 0.7, "stray": 0.7, "cloud": 0.6, "debris": 1.0, "flare": 0.0}
	if stage.orbit < GameData.HOT_ORBIT + 2500.0:
		w["flare"] = 0.8
	if stage.orbit < GameData.SNOW_LINE - 1500.0:
		w["comets"] *= 0.5
	w[own] = 2.5
	if w.has(_last) and _last != "":
		w[_last] = 0.0
	var total := 0.0
	for k in w:
		total += float(w[k])
	var x := _rng.randf() * total
	for k in w:
		x -= float(w[k])
		if x <= 0.0 and float(w[k]) > 0.0:
			return k
	return own


func active() -> bool:
	return kind != ""


func color() -> Color:
	return KINDS[kind]["color"] if active() else Color.WHITE


func title() -> String:
	return KINDS[kind]["title"] if active() else ""


## Допуск: насколько близко к цели надо подойти, в единицах диска.
func tol() -> float:
	if kind == "cloud" and not _vortex.is_empty():
		return float(_vortex.size)
	return maxf(1.15 * stage.hill(), 500.0)


func hint() -> String:
	match kind:
		"cloud":
			return "%s · %d с · ты в туче %d с" % [title(), ceili(t), int(inside)] if _in_cloud() \
				else "%s · %d с · зайди в тучу" % [title(), ceili(t)]
		"flare":
			return "%s · %d с · уйди за границу" % [title(), ceili(t)]
		"comets":
			return "%s · %d с · поймано %d из %d" % [title(), ceili(t), caught, COMETS_WIN]
		"debris":
			return "%s · %d с · собрано %d из %d" % [title(), ceili(t), caught, DEBRIS_WIN]
	return "%s · %d с · догони тело" % [title(), ceili(t)]


## Множители для этапа: аккреция.
func acc_mul() -> float:
	return 1.4 if kind == "cloud" and _in_cloud() else 1.0


func _in_cloud() -> bool:
	return not _vortex.is_empty() and stage.world.in_vortex() == _vortex


func step(delta: float) -> void:
	_time += delta
	queue_redraw()
	if not active():
		_next -= delta
		# В рыхлом облаке событий нет: сначала вокруг только газ.
		if _next <= 0.0 and stage.gas > 40.0 and stage.era >= 1:
			_start(_pick())
		return
	t -= delta
	# Цель — живое тело: метка на карте идёт за ним.
	var live := []
	for b in _targets:
		if b.state != "gone" and stage.world.bodies.has(b):
			live.append(b)
	_targets = live
	if not _targets.is_empty():
		r = float(_targets[0].r)
	match kind:
		"cloud":
			if _vortex.is_empty() or not stage.world.vortices.has(_vortex):
				t = 0.0
			else:
				r = float(_vortex.r)
				if _in_cloud():
					if inside == 0.0:
						stage.hud.toast("Ты в туче: газ гуще, сажа идёт в пыль", color())
					inside += delta
		"flare":
			if t <= 0.0:
				_flare_end()
			return
		"comets":
			if caught >= COMETS_WIN:
				_comets_win()
				return
			if _targets.is_empty():
				t = 0.0
		"debris":
			if caught >= DEBRIS_WIN:
				_debris_win()
				return
			if _targets.is_empty():
				t = 0.0
		"rival", "stray":
			if _targets.is_empty() and t > 0.0:
				# Тело ушло не к тебе (соперник, звезда): событие кончилось.
				t = 0.0
	if t <= 0.0:
		if kind == "cloud":
			_cloud_end()
		else:
			stage.hud.toast(KINDS[kind]["fail"], Color(1.0, 0.7, 0.55))
			_finish()


func _start(k: String) -> void:
	kind = k
	t = KINDS[k]["time"]
	inside = 0.0
	caught = 0
	_targets = []
	_vortex = {}
	var w: GiantWorld = stage.world
	var o: float = stage.orbit
	var g: float = stage.ang
	var lo := GameData.GIANT_ORBIT_MIN + 400.0
	var hi := GameData.GIANT_DISK.y - 1000.0
	var d := _rng.randf_range(1900.0, 3000.0)
	match k:
		"comets":
			# Кометы приходят с холодной окраины и летят к звезде.
			r = clampf(maxf(o + d, GameData.SNOW_LINE + 700.0), lo, hi)
			# Рой приходит издалека по орбите: его ещё надо догнать.
			var ahead := _rng.randf_range(0.3, 0.42) * (1.0 if _rng.randf() < 0.5 else -1.0)
			for i in COMETS:
				var b := w._add_body("comet", r + _rng.randf_range(-300.0, 900.0), g + ahead + _rng.randf_range(-0.05, 0.05), "ice")
				b.tag = "ev"
				_targets.append(b)
		"debris":
			# Облако обломков впереди или позади по орбите, чуть в стороне.
			r = clampf(o + _rng.randf_range(900.0, 1800.0) * (1.0 if _rng.randf() < 0.5 else -1.0), lo, hi)
			var ahead := _rng.randf_range(0.22, 0.34) * (1.0 if _rng.randf() < 0.5 else -1.0)
			var mat := w._material_at(r)
			for i in DEBRIS:
				var kd := "planetesimal" if i < 2 else "rubble"
				var b := w._add_body(kd, r + _rng.randfn(0.0, 220.0), g + ahead + _rng.randfn(0.0, 0.025), mat if _rng.randf() < 0.7 else w._material_at(r))
				# Обломки ещё разлетаются: у каждого своя скорость от удара.
				b.vr = _rng.randfn(0.0, 40.0)
				b.tag = "ev"
				_targets.append(b)
		"cloud":
			r = clampf(o + d * (1.0 if _rng.randf() < 0.5 else -1.0), lo, hi)
			_vortex = w.spawn_vortex(r, true, 34.0, true)
		"flare":
			r = minf(o + 1500.0, 9000.0)
		_:
			r = o + d * (1.0 if _rng.randf() < 0.5 else -1.0)
			if r > hi or r < lo:
				r = o - (r - o)
			r = clampf(r, lo, hi)
			var off := _rng.randf_range(0.08, 0.16) * (1.0 if _rng.randf() < 0.5 else -1.0)
			if k == "rival":
				var mat := "carbon" if GameState.body_type() == "venus" else "rock"
				var b := w._add_body("embryo", r, g + off, mat, clampf(w.eat_limit() * 0.8, 0.6, 6.0))
				b.tag = "ev"
				_targets.append(b)
			else:
				var b := w._add_body("embryo", r, g + off, "metal", clampf(w.eat_limit() * 0.5, 0.6, 3.0))
				b.tag = "ev"
				b["moon"] = stage.moons < STRAY_MOONS
				_targets.append(b)
	stage.hud.caption(KINDS[k]["title"], KINDS[k]["sub"], 3.5)


func _on_eaten(b: Dictionary) -> void:
	if not active() or not _targets.has(b):
		return
	match kind:
		"comets", "debris":
			caught += 1
		"rival":
			_rival_win()
		"stray":
			_stray_win(b)


func _finish() -> void:
	_last = kind
	kind = ""
	_targets = []
	_vortex = {}
	_next = _rng.randf_range(GAP.x, GAP.y) * (1.25 if stage.era < 2 else 1.0)


func _comets_win() -> void:
	var at: Vector2 = stage.body.position
	var gain: float = 2.0 + 0.04 * stage.earths
	stage.earths += gain
	stage.pay(gain * 3.0)
	GameState.add_chondrules(4, at)
	if GameState.body_type() == "titan":
		# Метановый лёд Титана: обломки комет слипаются в спутник.
		stage.moon_prog += 0.5
		stage.hud.toast("Рой пойман: +%s масс Земли, метановый лёд пошёл на луну" % String.num(gain, 1).replace(".", ","), color())
	else:
		stage.hud.toast("Рой пойман: +%s масс Земли, хондры +4" % String.num(gain, 1).replace(".", ","), color())
	_finish()


## Обломки собраны: у каждого ядра своя добыча.
func _debris_win() -> void:
	var type := GameState.body_type()
	var at: Vector2 = stage.body.position
	var gain: float = 1.5 + 0.03 * stage.earths
	var ch := 4
	var text := ""
	match type:
		"chondrite":
			ch = 9
			text = ", в обломках хондры"
		"metal":
			gain *= 1.5
			text = ", железо осело в ядро"
		"carbon", "venus":
			stage.value_boost = 20.0
			text = ", сажа: пыль ×1,5 на 20 с"
		"ice", "titan":
			stage.moon_prog += 0.5
			text = ", лёд пошёл на луну"
		_:
			if _rng.randf() < 0.4:
				stage.moon_prog += 1.0
				text = ", из остатка соберётся луна"
	stage.earths += gain
	stage.pay(gain * 2.5)
	GameState.add_chondrules(ch, at)
	stage.hud.toast("Обломки собраны: +%s масс Земли, хондры +%d%s" % [String.num(gain, 1).replace(".", ","), ch, text], color())
	_finish()


func _rival_win() -> void:
	var type := GameState.body_type()
	var at: Vector2 = stage.body.position
	var gain: float = _rng.randf_range(2.0, 5.0) + 0.05 * stage.earths
	stage.earths += gain
	stage.pay(gain * 2.0)
	var ch := 8 if type == "chondrite" else 4
	GameState.add_chondrules(ch, at)
	var text := "Сосед порван: ещё +%s масс Земли, хондры +%d" % [String.num(gain, 1).replace(".", ","), ch]
	if type == "venus":
		stage.value_boost = 25.0
		text += ", углерод соседа: пыль ×1,5 на 25 с"
	if _rng.randf() < 0.35:
		stage.moon_prog += 1.0
		text += ", из обломков соберётся луна"
	stage.hud.toast(text, color())
	_finish()


func _stray_win(b: Dictionary) -> void:
	GameState.add_chondrules(6, stage.body.position)
	if not b.get("moon", false):
		stage.hud.toast("Лунам тесно: тело порвало, хондры +6", color())
	_finish()


func _cloud_end() -> void:
	if inside > 3.0:
		var ch := clampi(int(inside / 4.0), 1, 6)
		GameState.add_chondrules(ch, stage.body.position)
		stage.hud.toast("Туча рассеялась: %d с в ней, хондры +%d" % [int(inside), ch], color())
	else:
		stage.hud.toast("Туча рассеялась без тебя", Color(1.0, 0.7, 0.55))
	_finish()


func _flare_end() -> void:
	if stage.orbit > r:
		GameState.add_chondrules(3, stage.body.position)
		stage.hud.toast("Вспышка позади: ты ушёл от неё, хондры +3", color())
	else:
		stage.gas = maxf(stage.gas - 45.0, 1.0)
		stage.hud.toast(KINDS[kind]["fail"], Color(1.0, 0.6, 0.45))
	_finish()


# --- Вид: граница вспышки. Остальные цели — тела и вихри мира. ---

func _draw() -> void:
	if kind != "flare" or stage == null:
		return
	var zoom: float = stage.camera.zoom.x
	var px := 1.0 / maxf(zoom, 0.01)
	var vp: Vector2 = get_viewport_rect().size
	var span := clampf(vp.y * 0.6 * px / r, 0.02, PI)
	var pulse := 0.6 + 0.4 * sin(_time * 3.0)
	var g: float = stage.ang
	draw_circle(Vector2.ZERO, r, Color(1.0, 0.45, 0.25, 0.05 + 0.04 * pulse))
	draw_arc(Vector2.ZERO, r, g - span, g + span, 96, Color(1.0, 0.55, 0.35, 0.55 * pulse), 3.0 * px, true)
