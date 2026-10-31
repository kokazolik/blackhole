shader_type canvas_item;
// Газовый диск вокруг гиганта, вид сверху во вращающейся вместе с ним системе:
// звезда в начале координат, гигант на оси +x. Внутренний газ обгоняет гиганта,
// внешний отстаёт — течение сдвиговое. Плотность по радиусу (со щелью) приходит
// текстурой sigma_tex, гигант гонит по газу две спиральные волны.
// Рисуется на весь экран: из пикселя восстанавливаем мировую точку по камере.

uniform vec2 view_size = vec2(1280.0, 720.0);
uniform vec2 cam = vec2(7000.0, 0.0);
uniform float zoom = 0.3;
uniform sampler2D sigma_tex : filter_linear, repeat_disable;
uniform vec2 disk_range = vec2(2200.0, 14000.0);
uniform float rp = 7000.0;      // орбита гиганта
uniform float hill = 400.0;     // радиус сферы Хилла (видимый)
uniform float h = 0.13;         // толщина диска в долях радиуса: задаёт закрутку волн
uniform float wake = 0.6;       // сила спиральных волн
uniform float gas = 1.0;        // сколько газа осталось
uniform float spin = 0.35;      // угловая скорость течения на орбите гиганта, рад/с
uniform float snow_line = 6800.0;
uniform float flare = 0.0;


float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return s;
}

float sigma_at(float r) {
	float u = (r - disk_range.x) / (disk_range.y - disk_range.x);
	return texture(sigma_tex, vec2(clamp(u, 0.0, 1.0), 0.5)).r;
}

// Клочья газа, унесённые сдвиговым течением. Чтобы узор не вытягивался в
// бесконечные нити, два слоя по очереди перезапускаются (как карта течений).
float flow_layer(float r, float th, float dom, float t, vec2 seed) {
	float a = th - dom * t;
	vec2 p = vec2(r * 0.0042, a * rp * 0.0011) + seed;
	float n = fbm(p);
	n += 0.5 * fbm(p * vec2(2.4, 1.3) + vec2(n * 1.5, 0.0));
	return n / 1.5;
}

void fragment() {
	vec2 w = cam + (UV - 0.5) * view_size / zoom;
	float r = length(w);
	// Угол в сторону орбитального движения: гигант летит «вверх» по экрану.
	float th = -atan(w.y, w.x);
	float u = (r - disk_range.x) / (disk_range.y - disk_range.x);
	float s = sigma_at(r) * smoothstep(0.0, 0.03, u) * smoothstep(1.0, 0.85, u);

	float x = r / rp;
	float dom = spin * (pow(x, -1.5) - 1.0);
	float T = 18.0;
	float t1 = fract(TIME / T);
	float t2 = fract(TIME / T + 0.5);
	float n1 = flow_layer(r, th, dom, t1 * T, vec2(0.0));
	float n2 = flow_layer(r, th, dom, t2 * T, vec2(37.0, 11.0));
	float f = abs(2.0 * t1 - 1.0);
	float n = mix(n1, n2, f);

	// Спиральные волны плотности (форма Огилви — Любова для кеплерова диска).
	float sg = sign(x - 1.0);
	float br = 0.8 * pow(x, 1.25) + 4.0 * pow(x, -0.25) - 4.8;
	float phw = -sg / h * br;
	float d = mod(th - phw + PI, TAU) - PI;
	float dr = abs(r - rp);
	float width = (60.0 + 0.08 * dr + 0.22 * hill) / r;
	float wk = exp(-pow(d / width, 2.0)) * wake
		* smoothstep(0.4 * hill, 1.2 * hill, dr) * exp(-dr / (rp * 0.7));
	// Подкова: газ в щели огибает гиганта по орбите, тонкая светлая дуга.
	float horse = exp(-pow(dr / (0.35 * hill), 2.0)) * smoothstep(0.25, 0.9, abs(th) * rp / hill) * 0.18;

	float dens = s * (0.45 + 0.75 * n) * (1.0 + 2.6 * wk) + horse * gas;
	dens *= mix(0.35, 1.0, gas);

	// Цвет: у звезды газ горячий и золотой, за снеговой линией холодный, синеватый.
	float temp = pow(snow_line / r, 0.9);
	vec3 cold = vec3(0.22, 0.26, 0.4);
	vec3 mid = vec3(0.5, 0.36, 0.27);
	vec3 hot = vec3(0.66, 0.46, 0.3);
	vec3 col = mix(cold, mid, smoothstep(0.65, 1.2, temp));
	col = mix(col, hot, smoothstep(1.35, 2.2, temp));
	col *= mix(1.0, 0.75, smoothstep(2.2, 4.0, temp));  // у звезды не выжигать картинку
	// Тёмные пылевые прожилки.
	float lanes = smoothstep(0.5, 0.75, fbm(vec2(r * 0.011, th * rp * 0.0025) + n));
	col *= 1.0 - 0.22 * lanes;
	// Свет звезды слабеет с расстоянием, но не выжигает картинку у звезды.
	float light = mix(0.8, 0.95, smoothstep(0.6, 1.8, temp)) * (1.0 + 0.4 * flare);
	// Края щели подсвечены: туда газ сгребают приливы гиганта.
	float ds = abs(sigma_at(r + 60.0) - sigma_at(r - 60.0));
	float rim = smoothstep(0.02, 0.25, ds) * gas;
	vec3 rim_col = vec3(1.0, 0.8, 0.5);
	float shade = 0.35 + 0.4 * clamp(dens, 0.0, 1.1);
	vec3 c = col * light * shade + vec3(0.9, 0.72, 0.5) * wk * s * 0.22 + rim_col * rim * 0.1;
	float alpha = clamp(0.07 + dens * 0.44 + wk * s * 0.15 + rim * 0.06, 0.0, 0.58) * smoothstep(0.0, 0.05, s + horse);
	COLOR = vec4(c, alpha);
}
