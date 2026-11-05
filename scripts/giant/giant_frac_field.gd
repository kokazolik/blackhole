class_name GiantFracField
extends FracField
## Поле движка разрушения у гиганта, в его системе (узел — ребёнок гиганта,
## звезда слева, −x). Тяготение то же, что ведёт захваченные тела (задача
## Хилла), поэтому кусок в миг
## раскола летит ровно так, как летело тело (орбит нет: только тяготение
## гиганта, без прилива звезды и Кориолиса). Газ околопланетного диска
## кружит в ту же сторону чуть медленнее круговой скорости и понемногу
## стекает внутрь; у облаков — атмосфера: плотнее с глубиной, жжёт и рвёт.

const ETA := 0.06            # газ отстаёт от круговой скорости на эту долю (встречный ветер)
const ATM_TOP := 0.09        # верх атмосферы над облаками, в радиусах гиганта
const ATM_H := 0.025         # шкала высот атмосферы, в радиусах
const FALL_R := 1.75         # отсюда к облакам газ всё сильнее стекает внутрь
const FALL_K := 0.9          # у облаков скорость стока — эта доля круговой
const DIR := -1.0            # прямое вращение: угол убывает

var world                    # system_world.gd
var GM := 1.0
var R := 100.0
var W := 0.35
var soft2 := 0.0
var hill := 1000.0


func refresh() -> void:
	R = world._giant_r()
	var h: float = world.stage.hill()
	hill = h
	W = GiantWorld.HILL_W
	var g := 3.0 * pow(Skills.stat("giant_reach"), 3.0)
	GM = g * h * h * h * W * W
	soft2 = 0.02 * h * h


func accel(p: Vector2, v: Vector2) -> Vector2:
	var d2 := p.length_squared() + soft2
	var inv := GM / (d2 * sqrt(d2))
	# Орбит нет: только тяготение гиганта (без прилива звезды и Кориолиса).
	return -p * inv


## Рвёт тело прилив самого гиганта: прилив звезды и сила Кориолиса в
## системе Хилла почти одинаковы по всему телу и предел Роша не сдвигают.
func stress_accel(p: Vector2, _v: Vector2) -> Vector2:
	var d2 := p.length_squared() + soft2
	return -p * (GM / (d2 * sqrt(d2)))


func gas_v(p: Vector2, inflow: float) -> Vector2:
	var r := maxf(p.length(), R * 0.5)
	var rh := p / r
	var d2 := r * r + soft2
	# Круговая скорость вокруг гиганта, с отставанием газа.
	var vk := sqrt(GM * r * r / (d2 * sqrt(d2))) * (1.0 - ETA)
	# В атмосфере газ вращается с планетой (медленнее) и куски тонут.
	var a := atm(p)
	vk *= 1.0 - 0.35 * a
	# У самых облаков газ стекает в планету быстро (аккреционный поток):
	# пыль падает недалеко от места раскола, а не облетает гиганта по кругу.
	var fall := smoothstep(R * FALL_R, R * 1.05, r)
	var vr := -inflow * maxf(r - 0.9 * R, 0.0) - vk * (FALL_K * fall + 0.35 * a)
	return rh * vr + Vector2(rh.y, -rh.x) * (-DIR) * vk


func gas_rho(p: Vector2) -> float:
	var r := maxf(p.length(), R * 0.5)
	var base := pow(R / r, 2.0)
	if r < R * (1.0 + ATM_TOP):
		base += 60.0 * exp(-(r - R) / (ATM_H * R)) * atm(p)
	return base


func atm(p: Vector2) -> float:
	var r := p.length()
	return smoothstep(R * (1.0 + ATM_TOP), R * 0.985, r)


func sunk(p: Vector2, rad: float) -> bool:
	return p.length() < R - rad * 0.2


func lost(p: Vector2) -> bool:
	return p.length() > hill * 2.4


func shade(p: Vector2) -> float:
	return TidalStreams._shade(p, R)


## Молодой гигант светится сам: всё рядом освещено им со стороны планеты,
## спадает как квадрат расстояния.
func self_light(p: Vector2) -> Color:
	var c: Color = world.stage.body.self_light()
	if c.a <= 0.0:
		return c
	var k := clampf(pow(R * 1.15 / maxf(p.length(), R), 2.0), 0.0, 1.0)
	return Color(c.r * k, c.g * k, c.b * k, c.a * k)


func light_dir(_p: Vector2) -> Vector2:
	return Vector2(-1.0, 0.0)


func tide(p: Vector2) -> float:
	var r := maxf(p.length(), R * 0.3)
	return 2.0 * GM / (r * r * r)


func v_ref() -> float:
	return sqrt(GM / R)
