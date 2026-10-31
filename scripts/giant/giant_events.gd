extends Node2D
## События этапа гиганта: у каждого ядра своя игра.
##
## Ледяной гигант ловит кометный рой с окраин диска, Юпитер из камня
## глотает соседний зародыш, плотный железный гигант полем захватывает
## блуждающее тело в луны, тёмный гонится за углеродной тучей, что сползает
## к звезде, а горячий у самой звезды уходит от её вспышки.
## Тип тела добавляет оттенок: хондрит, Титан и парниковый мир получают своё.
##
## Рисуется в мире (полоса цели вдоль орбиты и сам объект); HUD берёт
## отсюда метку на карте газа и стрелку к цели за краем экрана.

const FIRST := 35.0          # первое событие, секунд от начала этапа
const GAP := Vector2(55.0, 80.0)
const STRAY_MOONS := 6       # больше лун не захватить даже сильным полем

const KINDS := {
	"comets": {
		"title": "Кометный рой",
		"sub": "с окраин диска падает рой ледяных тел: дотянись до их орбиты, пока он не прошёл мимо",
		"time": 24.0, "color": Color(0.62, 0.86, 1.0),
		"fail": "Рой прошёл мимо",
	},
	"rival": {
		"title": "Соседний зародыш",
		"sub": "в щель вошёл чужой зародыш: дойди до его орбиты и проглоти, пока его не выбросило",
		"time": 24.0, "color": Color(0.9, 0.7, 0.5),
		"fail": "Сосед ушёл: его выбросило из щели",
	},
	"stray": {
		"title": "Блуждающее тело",
		"sub": "мимо идёт тело на вытянутой орбите: подойди, и железное поле захватит его в луны",
		"time": 26.0, "color": Color(0.8, 0.82, 0.86),
		"fail": "Тело ушло на свою орбиту",
	},
	"cloud": {
		"title": "Углеродная туча",
		"sub": "густая тёмная туча сползает к звезде: держись в ней, пока она идёт, и пей газ вдвое быстрее",
		"time": 30.0, "color": Color(0.85, 0.55, 0.3),
		"fail": "",
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
var _base := 0.0             # центр колебаний блуждающего тела
var _next := FIRST
var _time := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


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


func active() -> bool:
	return kind != ""


func color() -> Color:
	return KINDS[kind]["color"] if active() else Color.WHITE


func title() -> String:
	return KINDS[kind]["title"] if active() else ""


## Допуск: насколько близко к цели надо подойти, в единицах диска.
func tol() -> float:
	if kind == "cloud":
		return maxf(1.4 * stage.hill(), 650.0)
	return maxf(1.15 * stage.hill(), 500.0)


func hint() -> String:
	match kind:
		"cloud":
			return "%s · %d с · ты в туче %d с" % [title(), ceili(t), int(inside)] if absf(stage.orbit - r) < tol() \
				else "%s · %d с · догони тучу" % [title(), ceili(t)]
		"flare":
			return "%s · %d с · уйди за границу" % [title(), ceili(t)]
	return "%s · %d с · дотянись до метки" % [title(), ceili(t)]


## Множители для этапа: аккреция и звёздная пыль.
func acc_mul() -> float:
	return 2.0 if kind == "cloud" and absf(stage.orbit - r) < tol() else 1.0


func step(delta: float) -> void:
	_time += delta
	queue_redraw()
	if not active():
		_next -= delta
		if _next <= 0.0 and stage.gas > 40.0:
			_start(kind_for(str(GameState.giant.get("flavor", "giant_cold"))))
		return
	t -= delta
	var lo := GameData.GIANT_ORBIT_MIN
	var hi := GameData.GIANT_DISK.y - 600.0
	match kind:
		"stray":
			r = clampf(_base + 650.0 * sin(_time * 0.7), lo, hi)
		"cloud":
			r -= 85.0 * delta
			if absf(stage.orbit - r) < tol():
				if inside == 0.0:
					stage.hud.toast("Ты в туче: газ вдвое гуще", color())
				inside += delta
			if r < lo + 200.0:
				t = 0.0
	if kind == "flare":
		if t <= 0.0:
			_flare_end()
		return
	if kind != "cloud" and absf(stage.orbit - r) < tol():
		_win()
		return
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
	var o: float = stage.orbit
	var lo := GameData.GIANT_ORBIT_MIN + 400.0
	var hi := GameData.GIANT_DISK.y - 1000.0
	var d := _rng.randf_range(1900.0, 3200.0)
	match k:
		"comets":
			# Кометы приходят с холодной окраины: цель снаружи, за снеговой линией.
			r = maxf(o + d, GameData.SNOW_LINE + 700.0)
			if r > hi:
				r = o - d
		"cloud":
			r = o + d + 600.0
			if r > hi:
				r = hi
		"flare":
			r = minf(o + 1500.0, 9000.0)
		_:
			r = o + d * (1.0 if _rng.randf() < 0.5 else -1.0)
			if r > hi or r < lo:
				r = o - (r - o)
	r = clampf(r, lo, hi)
	_base = r
	stage.hud.caption(KINDS[k]["title"], KINDS[k]["sub"], 3.5)


func _finish() -> void:
	kind = ""
	_next = _rng.randf_range(GAP.x, GAP.y)


func _win() -> void:
	var col := color()
	var type := GameState.body_type()
	var at: Vector2 = stage.body.position
	match kind:
		"comets":
			stage.clumps.shred_now("rubble", "ice", Vector2(stage.hill() * 1.2, -stage.hill() * 0.6).rotated(stage.ang), 7)
			var gain: float = 3.0 + 0.06 * stage.earths
			stage.earths += gain
			stage.pay(gain * 3.0)
			GameState.add_chondrules(4, at)
			if type == "titan":
				# Метановый лёд Титана: обломки комет слипаются в спутник.
				stage.moon_prog += 0.5
				stage.hud.toast("Рой пойман: +%.1f M⊕, метановый лёд пошёл на луну" % gain, col)
			else:
				stage.hud.toast("Рой пойман: +%.1f масс Земли, хондры +4" % gain, col)
		"rival":
			stage.clumps.shred_now("embryo", "rock", Vector2(0.0, -stage.hill() * 1.3).rotated(stage.ang))
			var gain: float = _rng.randf_range(4.0, 8.0) + 0.08 * stage.earths
			stage.earths += gain
			stage.pay(gain * 2.0)
			var ch := 8 if type == "chondrite" else 4
			GameState.add_chondrules(ch, at)
			var text := "Сосед проглочен: +%.1f масс Земли, хондры +%d" % [gain, ch]
			if type == "venus":
				stage.value_boost = 25.0
				text += ", углерод соседа: пыль ×1,5 на 25 с"
			if _rng.randf() < 0.35:
				stage.moon_prog += 1.0
				text += ", из обломков соберётся луна"
			stage.hud.toast(text, col)
		"stray":
			GameState.add_chondrules(6, at)
			if stage.moons < STRAY_MOONS:
				stage.moons += 1
				stage.body.moons = stage.moons
				# Тело подходит со своей орбиты и садится на лунную, а не возникает.
				stage.body.birth(stage.moons - 1, Vector2(clampf(r - stage.orbit, -2.0 * stage.hill(), 2.0 * stage.hill()) + 0.01, -stage.hill() * 0.8))
				stage.hud.toast("Поле захватило луну %s! Хондры +6" % stage.body.moon_name(stage.moons - 1), col)
			else:
				stage.earths += 1.5
				stage.body.fall()
				stage.hud.toast("Лунам тесно: тело упало в тебя, +1,5 массы Земли", col)
	_finish()


func _cloud_end() -> void:
	if inside > 3.0:
		var ch := clampi(int(inside / 4.0), 1, 6)
		GameState.add_chondrules(ch, stage.body.position)
		stage.hud.toast("Туча прошла: %d с в ней, хондры +%d" % [int(inside), ch], color())
	else:
		stage.hud.toast("Туча прошла мимо", Color(1.0, 0.7, 0.55))
	_finish()


func _flare_end() -> void:
	if stage.orbit > r:
		GameState.add_chondrules(3, stage.body.position)
		stage.hud.toast("Вспышка позади: ты ушёл от неё, хондры +3", color())
	else:
		stage.gas = maxf(stage.gas - 45.0, 1.0)
		stage.hud.toast(KINDS[kind]["fail"], Color(1.0, 0.6, 0.45))
	_finish()


# --- Вид ---

func _draw() -> void:
	if not active() or stage == null:
		return
	var zoom: float = stage.camera.zoom.x
	var px := 1.0 / maxf(zoom, 0.01)
	var vp: Vector2 = get_viewport_rect().size
	var span := clampf(vp.y * 0.6 * px / r, 0.02, PI)
	var col := color()
	var pulse := 0.6 + 0.4 * sin(_time * 3.0)
	var w := tol()
	var g: float = stage.ang  # гигант не всегда на оси x: цель рисуем рядом с ним
	if kind == "flare":
		# Горячая зона вокруг звезды: всё, что ближе границы.
		draw_circle(Vector2.ZERO, r, Color(1.0, 0.45, 0.25, 0.05 + 0.04 * pulse))
		draw_arc(Vector2.ZERO, r, g - span, g + span, 96, Color(1.0, 0.55, 0.35, 0.55 * pulse), 3.0 * px, true)
		return
	# Полоса цели вдоль орбиты: мягкая, с яркими краями.
	draw_arc(Vector2.ZERO, r, g - span, g + span, 128, Color(col, 0.06 + 0.04 * pulse), w * 2.0, true)
	draw_arc(Vector2.ZERO, r - w, g - span, g + span, 128, Color(col, 0.3 * pulse), 1.5 * px, true)
	draw_arc(Vector2.ZERO, r + w, g - span, g + span, 128, Color(col, 0.3 * pulse), 1.5 * px, true)
	var ang := g + 0.35 * span * sin(_time * 0.25)
	var p := Vector2(cos(ang), sin(ang)) * r
	var light := -p.normalized()
	match kind:
		"comets":
			for i in 7:
				var q := p + Vector2(sin(i * 2.4) * 45.0, cos(i * 1.7) * 120.0) * px
				var tail := -light * (90.0 + 40.0 * (i % 3)) * px
				for k in 6:
					var f := float(k) / 6.0
					draw_line(q + tail * f, q + tail * (f + 1.0 / 6.0), Color(0.7, 0.88, 1.0, 0.22 * (1.0 - f)), (3.0 - 2.4 * f) * px, true)
				_ball(q, (2.5 + (i % 3)) * px, Color(0.82, 0.9, 1.0), light)
		"rival":
			_ball(p, 14.0 * px, Color(0.62, 0.5, 0.4), light)
		"stray":
			# Вытянутая орбита: тело качается туда-сюда поперёк орбит.
			draw_arc(Vector2.ZERO, _base - 650.0, g - span * 0.5, g + span * 0.5, 64, Color(col, 0.12), px, true)
			draw_arc(Vector2.ZERO, _base + 650.0, g - span * 0.5, g + span * 0.5, 64, Color(col, 0.12), px, true)
			_ball(p, 9.0 * px, Color(0.6, 0.6, 0.62), light)
		"cloud":
			for i in 26:
				var f := float(i) / 26.0
				var off := Vector2(sin(i * 3.1 + _time * 0.2) * w * 0.7, cos(i * 1.9 + _time * 0.15) * w * 1.6)
				draw_circle(p + off, w * (0.35 + 0.4 * f), Color(0.3, 0.19, 0.11, 0.1) if i % 2 == 0 else Color(0.06, 0.04, 0.03, 0.16))
			for i in 8:
				var off := Vector2(sin(i * 2.3) * w * 0.5, cos(i * 1.3 + _time * 0.3) * w * 1.2)
				draw_circle(p + off, 4.0 * px, Color(1.0, 0.6, 0.3, 0.35 + 0.2 * sin(_time * 4.0 + i)))


## Шар, освещённый со стороны звезды.
func _ball(c: Vector2, rad: float, col: Color, light: Vector2) -> void:
	var steps := 9
	for k in steps:
		var f := float(k) / steps
		var lum := 0.07 + 0.93 * pow(f, 0.7)
		draw_circle(c + light * rad * 0.5 * f, rad * (1.0 - f * 0.85), Color(col.r * lum, col.g * lum, col.b * lum))
