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
uniform float cam_rot = 0.0;    // камера поворачивается вместе с гигантом
uniform float gang = 0.0;       // угол гиганта на орбите
// Дыра фотоиспарения: внутри газа нет, край освещён звездой в лоб и
// отбрасывает тень на диск за собой, на кромке пылевая ловушка.
uniform float hole = 0.0;       // радиус дыры (0 — дыры нет)
uniform float rim_k = 0.0;      // кромка проявляется плавно


uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

// Шум из готовой бесшовной текстуры (NoiseTex): 256 пикселей на 16 единиц.
float fbm(vec2 p) {
	return texture(noise_tex, p * 0.0625).r;
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

// Край дыры не ровный круг: фронт рвётся неровно, языки газа.
float noise_edge(float th, float r, float hole_r) {
	float big = fbm(vec2(th * 2.2, hole_r * 0.0003)) - 0.5;
	float fine = fbm(vec2(th * 11.0, r * 0.0015 + 7.0)) - 0.5;
	return big * 420.0 + fine * 170.0;
}

void fragment() {
	vec2 sv = (UV - 0.5) * view_size / zoom;
	float cr = cos(cam_rot);
	float sr = sin(cam_rot);
	vec2 w = cam + vec2(cr * sv.x - sr * sv.y, sr * sv.x + cr * sv.y);
	float r = length(w);
	// Угол в сторону орбитального движения: гигант летит «вверх» по экрану.
	float th = -(mod(atan(w.y, w.x) - gang + PI, TAU) - PI);
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

	if (hole > 0.0) {
		float dh = r - hole;
		// Стенка: звезда светит в неё прямо, без пелены внутреннего диска.
		// Тёплый свет рассеяния, узкий, рваный по краю — без свечения.
		float edge = noise_edge(th, r, hole);
		float de = dh - edge;
		// Резкий подъём на самом краю и свет, гаснущий вглубь газа: звезде
		// видна только тонкая кожа стенки, дальше её закрывает сама стенка.
		float wall = smoothstep(-90.0, 30.0, de) * exp(-max(de, 0.0) / 380.0);
		float clump = 0.55 + 0.75 * n;   // стенка клочковатая, не ровная дуга
		float lit = wall * clump * smoothstep(0.0, 0.08, s) * rim_k;
		vec3 wall_col = mix(vec3(1.0, 0.84, 0.62), vec3(1.0, 0.93, 0.82), smoothstep(0.9, 1.4, clump));
		c = mix(c, wall_col * (0.7 + 0.3 * n), clamp(lit * 0.7, 0.0, 1.0));
		alpha = max(alpha, lit * 0.42 * clamp(s * 2.5, 0.0, 1.0));
		// За стенкой тень: раздутый край закрывает диск от звезды.
		float shadow = smoothstep(150.0, 450.0, dh) * (1.0 - smoothstep(600.0, 3200.0, dh)) * rim_k;
		c *= 1.0 - 0.25 * shadow;
		// Кромка — пылевая ловушка: камешки сгущаются в тёмные прожилки.
		float trap = exp(-pow((dh - 700.0) / 600.0, 2.0)) * rim_k;
		float grit = smoothstep(0.45, 0.8, fbm(vec2(r * 0.02, th * rp * 0.004) + 3.0 * n));
		c *= 1.0 - 0.25 * trap * grit;
		// В самой дыре — редкий ионизированный ветер, уходящий наружу:
		// бледно-розовый, как свечение водорода (Hα), еле видный.
		if (dh < 0.0) {
			float wind = fbm(vec2(r * 0.0016 - TIME * 0.05, th * 1.6));
			float wa = 0.05 * smoothstep(0.35, 0.85, wind) * smoothstep(-6000.0, -300.0, dh) * rim_k
				* smoothstep(disk_range.x, disk_range.x + 1500.0, r);
			c = mix(c, vec3(0.85, 0.5, 0.55), smoothstep(0.0, 0.02, wa) * (1.0 - smoothstep(0.0, 0.05, alpha)));
			alpha = max(alpha, wa);
		}
	}
	COLOR = vec4(c, alpha);
}
