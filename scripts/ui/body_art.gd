class_name BodyArt
extends RefCounted
## Портрет тела шейдером, как в игре: для концовок и этапов коллекции.
## Каменные миры — шейдер зародыша по составу, гиганты — шейдер гиганта,
## звёзды и облако — протозвезда, мелочь от пылинки до планетезимали — шейдер луны.

const EMBRYO := preload("res://shaders/embryo.gdshader")
const GIANT := preload("res://shaders/giant_planet.gdshader")
const STAR := preload("res://shaders/protostar.gdshader")
const MOON := preload("res://shaders/moon.gdshader")

# Типичная масса звезды каждого класса, масс Юпитера: по ней цвет и размер.
const STAR_MJ := {"star_red": 300.0, "star_sun": 1050.0, "star_white": 3000.0, "star_blue": 12000.0, "star_titan": 32000.0}


## Квадрат с шейдером; размер ставит quad_size().
static func make(id: String) -> ColorRect:
	var art := ColorRect.new()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	art.material = m
	var light := Vector2(-1.0, -0.25)
	match id:
		"dust", "pebble", "boulder", "plsim":
			m.shader = MOON
			m.set_shader_parameter("style", {"dust": 5, "pebble": 0, "boulder": 0, "plsim": 3}[id])
			m.set_shader_parameter("light_dir", light)
			m.set_shader_parameter("seed", {"dust": 0.3, "pebble": 2.1, "boulder": 4.7, "plsim": 7.3}[id])
			# Пылинка — рыхлый комок, ещё не шар.
			m.set_shader_parameter("form", 0.25 if id == "dust" else 1.0)
			return art
		"embryo":
			m.shader = EMBRYO
			m.set_shader_parameter("style", 0)
			m.set_shader_parameter("magma", 0.55)
			m.set_shader_parameter("atmo", 0.35)
			m.set_shader_parameter("light_dir", light)
			return art
		"young":
			m.shader = EMBRYO
			m.set_shader_parameter("style", 5)
			m.set_shader_parameter("ocean", 0.6)
			m.set_shader_parameter("clouds", 0.5)
			m.set_shader_parameter("atmo", 0.45)
			m.set_shader_parameter("light_dir", light)
			m.set_shader_parameter("seed", 0.81)
			return art
		"giant":
			return _giant(art, m, "giant_cold", light)
		"cloud", "next":
			m.shader = STAR
			m.set_shader_parameter("lit", 0.0 if id == "cloud" else 1.0)
			m.set_shader_parameter("heat", 0.6)
			m.set_shader_parameter("cocoon", 0.85 if id == "cloud" else 0.0)
			m.set_shader_parameter("disk", 1.0)
			m.set_shader_parameter("jets", 0.6 if id == "cloud" else 0.0)
			m.set_shader_parameter("detail", 1.0)
			return art
	if id.begins_with("star_") and id != "star_failed":
		var mj: float = STAR_MJ.get(id, 1000.0)
		m.shader = STAR
		m.set_shader_parameter("lit", 1.0)
		m.set_shader_parameter("heat", 1.0)
		m.set_shader_parameter("cocoon", 0.0)
		m.set_shader_parameter("disk", 0.0)
		m.set_shader_parameter("star_col", GameData.star_color(mj))
		m.set_shader_parameter("detail", 0.0)
		return art
	if id.begins_with("giant") or id in ["super_jupiter", "brown_dwarf", "star_failed", "super_neptune"]:
		return _giant(art, m, id, light)
	m.shader = EMBRYO
	var style := 0
	match id:
		"planet_iron", "super_iron":
			style = 1
		"planet_dark", "super_diamond":
			style = 2
		"planet_layered":
			style = 4
		"planet_living", "planet_ocean":
			style = 5
	m.set_shader_parameter("style", style)
	m.set_shader_parameter("light_dir", light)
	m.set_shader_parameter("seed", 0.37 + 0.13 * float(absi(id.hash()) % 7))
	var atmo := 0.0
	match id:
		"planet_living":
			atmo = 0.5
			m.set_shader_parameter("ocean", 0.7)
			m.set_shader_parameter("clouds", 0.7)
		"planet_ocean":
			atmo = 0.45
			m.set_shader_parameter("ocean", 1.0)
			m.set_shader_parameter("clouds", 0.5)
		"planet_titan", "super_titan":
			atmo = 1.0
			m.set_shader_parameter("veil", 1.0)
			m.set_shader_parameter("atmo_col", Color(0.9, 0.6, 0.3))
			m.set_shader_parameter("wind", 0.6)
		"planet_venus", "super_venus":
			atmo = 1.0
			m.set_shader_parameter("veil", 1.0)
			m.set_shader_parameter("atmo_col", Color(0.95, 0.85, 0.6))
			m.set_shader_parameter("wind", 2.2)
		"super_earth", "planet_rock":
			atmo = 0.3
	m.set_shader_parameter("atmo", atmo)
	return art


static func _giant(art: ColorRect, m: ShaderMaterial, id: String, light: Vector2) -> ColorRect:
	m.shader = GIANT
	var look: Array = GameData.GIANT_LOOK.get(id, GameData.GIANT_LOOK["giant_cold"])
	if id == "star_failed":
		look = GameData.GIANT_LOOK["brown_dwarf"]
	elif id == "super_neptune":
		look = GameData.GIANT_LOOK["giant_ice"]
	m.set_shader_parameter("zone_col", look[0])
	m.set_shader_parameter("belt_col", look[1])
	m.set_shader_parameter("storm_col", look[2])
	m.set_shader_parameter("heat", 0.7 if id in ["giant_hot", "brown_dwarf", "star_failed"] else 0.0)
	m.set_shader_parameter("light_dir", light)
	return art


## Сторона квада для тела радиусом r на экране: у каждого шейдера своя доля шара.
static func quad_size(id: String, r: float) -> float:
	if id in ["dust", "pebble", "boulder", "plsim"]:
		return r * 2.2
	if id in ["cloud", "next"]:
		return r * 3.4
	if id.begins_with("star_") and id != "star_failed":
		var mj: float = STAR_MJ.get(id, 1000.0)
		return r * (3.0 + 0.35 * clampf(log(mj / 300.0), 0.0, 4.0))
	return r / 0.36


## Медленное вращение: оборот за минуты, как у настоящих тел.
static func tick(art: ColorRect, id: String, t: float) -> void:
	var m := art.material as ShaderMaterial
	if m.shader == STAR:
		m.set_shader_parameter("time", t)
	else:
		m.set_shader_parameter("spin", t * 0.08)
		m.set_shader_parameter("spin_jet", t * 0.08)
