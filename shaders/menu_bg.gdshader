shader_type canvas_item;
// Фон главного меню: живой протопланетный диск у молодой звезды.
// Диск наклонён к нам; газ и пыль в нём вращаются по Кеплеру (внутри быстрее,
// ω ∝ r^-1.5), поэтому узоры сами закручиваются в спирали. В диске щели,
// которые выметают растущие планеты, — как на снимках HL Тельца (ALMA).
// Ближняя половина диска тёмной полосой ложится на звезду, дальняя
// светится над ней. Позади — туманность и мерцающие звёзды.

uniform vec2 aspect = vec2(1.7778, 1.0);
uniform vec2 center = vec2(1.18, 0.56);   // звезда в координатах (x·aspect, y)
uniform float tilt = 0.30;                // сжатие диска по вертикали (наклон)
uniform float roll = -0.16;               // поворот диска, радианы
uniform float speed = 1.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		s += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return s;
}

// Звёзды: решётка со случайной звездой в клетке, мерцают каждая в своём ритме.
vec3 stars(vec2 uv, float t) {
	vec3 c = vec3(0.0);
	for (int layer = 0; layer < 2; layer++) {
		float sc = layer == 0 ? 70.0 : 150.0;
		vec2 g = uv * sc;
		vec2 id = floor(g);
		vec2 f = fract(g) - 0.5;
		float h = hash(id + float(layer) * 31.0);
		if (h > (layer == 0 ? 0.86 : 0.8)) {
			vec2 o = vec2(hash(id + 3.1), hash(id + 7.7)) - 0.5;
			float d = length(f - o * 0.7);
			float tw = 0.6 + 0.4 * sin(t * (0.6 + 2.0 * hash(id + 1.3)) + h * 40.0);
			float b = smoothstep(0.09, 0.0, d) * tw * (layer == 0 ? 1.0 : 0.55);
			vec3 tint = mix(vec3(1.0, 0.85, 0.7), vec3(0.75, 0.85, 1.0), hash(id + 5.5));
			c += tint * b;
		}
	}
	return c;
}

// Угловая скорость по Кеплеру, рад/с, r — в долях радиуса диска.
float omega(float r) {
	return 0.035 * speed * pow(max(r, 0.04) / 0.3, -1.5);
}

void fragment() {
	float t = TIME;
	vec2 uv = UV * aspect;
	// Камера медленно плывёт: как будто мы облетаем систему.
	vec2 drift = vec2(sin(t * 0.021), cos(t * 0.017)) * 0.012;
	vec2 p = uv - center - drift;

	// --- Туманность и звёзды позади ---
	vec2 nq = uv * 1.4 + vec2(t * 0.004, -t * 0.002);
	float n1 = fbm(nq);
	float n2 = fbm(nq * 1.9 + vec2(n1 * 1.5, 3.0));
	vec3 neb = vec3(0.0);
	neb += vec3(0.34, 0.07, 0.15) * smoothstep(0.38, 0.85, n1) * 0.9;    // H-альфа: красноватый газ
	neb += vec3(0.07, 0.17, 0.3) * smoothstep(0.42, 0.9, n2) * 0.8;       // отражённый голубой
	// Отражательная туманность: остатки облака светятся тёплым вокруг звезды.
	neb += vec3(0.5, 0.3, 0.16) * 0.22 * smoothstep(0.35, 0.8, n2) * exp(-length(p) * 1.8);
	neb *= 0.6 + 0.4 * smoothstep(1.6, 0.2, length(p));
	// Тёмные пылевые прожилки поверх туманности.
	neb *= 1.0 - 0.6 * smoothstep(0.55, 0.75, fbm(nq * 2.6 + 11.0));
	vec3 col = vec3(0.006, 0.006, 0.016) + neb + stars(uv, t) * 0.9;

	// --- Диск в своей плоскости ---
	float cr = cos(roll);
	float sr = sin(roll);
	vec2 q = vec2(p.x * cr - p.y * sr, p.x * sr + p.y * cr);
	vec2 d = vec2(q.x, q.y / tilt);
	float r = length(d) / 1.15;          // 1 — внешний край диска
	float th = atan(d.y, d.x);
	// Вращение: каждый радиус поворачивается со своей скоростью.
	float a = th - omega(r) * t;
	vec2 polar = vec2(cos(a), sin(a)) * r;
	float lr = log(max(r, 0.02));
	// Спиральные рукава из шума, закрученные сдвигом.
	float sw = fbm(vec2(lr * 5.0 + a * 0.8, a * 1.6) + polar * 3.0);
	float fine = fbm(polar * 14.0 + vec2(lr * 9.0, 0.0));
	float dens = exp(-r * 2.4) * smoothstep(1.0, 0.72, r) * smoothstep(0.035, 0.085, r);
	dens *= 0.55 + 0.75 * sw + 0.25 * (fine - 0.5);
	// Щели, выметенные планетами, и светлые кольца по их краям.
	float gap1 = exp(-pow((r - 0.27) / 0.018, 2.0));
	float gap2 = exp(-pow((r - 0.5) / 0.028, 2.0));
	float gap3 = exp(-pow((r - 0.69) / 0.02, 2.0));
	dens *= (1.0 - 0.85 * gap1) * (1.0 - 0.8 * gap2) * (1.0 - 0.7 * gap3);
	dens *= 1.0 + 0.35 * exp(-pow((r - 0.3) / 0.02, 2.0)) + 0.3 * exp(-pow((r - 0.54) / 0.03, 2.0));
	// Свет звезды падает как 1/r², у края его мало; внутри газ горячий.
	// Диск раздут к краю, его поверхность ловит свет под углом: спад мягче, ~r^-1.3.
	float light = 0.3 / (pow(r, 1.3) + 0.02);
	vec3 hot = vec3(1.0, 0.62, 0.3);
	vec3 warm = vec3(0.95, 0.78, 0.55);
	vec3 cool = vec3(0.48, 0.55, 0.74);
	vec3 dcol = mix(hot, warm, smoothstep(0.05, 0.25, r));
	dcol = mix(dcol, cool, smoothstep(0.3, 0.8, r));
	// Ближняя половина освещена со спины (рассеяние вперёд), дальняя — в лоб.
	float near = smoothstep(-0.02, 0.06, q.y);
	float phase = mix(1.0, 0.7, near);
	vec3 disk = dcol * dens * min(light, 6.0) * 0.3 * phase;
	float alpha = clamp(dens * 2.2, 0.0, 0.92);

	// --- Звезда ---
	float rs = length(p);
	vec3 star = vec3(1.0, 0.95, 0.85) * smoothstep(0.024, 0.0, rs) * 3.0;
	star += vec3(1.0, 0.78, 0.5) * 0.045 / (rs * rs * 60.0 + 0.04);
	star += vec3(1.0, 0.6, 0.3) * 0.02 / (rs * 4.0 + 0.02) * 0.25;
	// Слабые лучи дифракции, как на снимках телескопа.
	vec2 sp = abs(p);
	float spikes = exp(-sp.y * 700.0) * exp(-sp.x * 22.0) + exp(-sp.x * 700.0) * exp(-sp.y * 22.0);
	star += vec3(1.0, 0.9, 0.8) * spikes * 0.3;
	// Звезда чуть дышит: молодые звёзды неспокойны.
	star *= 0.94 + 0.06 * sin(t * 0.7) * sin(t * 0.31);

	// Дальняя половина диска — за звездой, ближняя — перед ней и гасит её свет.
	vec3 back = col * (1.0 - alpha * (1.0 - near)) + disk * (1.0 - near);
	back += star * (1.0 - alpha * near * 0.95);
	col = back + disk * near;

	// Растущая планета в первой щели: тёмный шар с серпом, освещённым звездой.
	float pa = omega(0.27) * t + 1.3;
	vec2 pd = vec2(cos(pa), sin(pa)) * 0.27 * 1.15;
	vec2 pp = vec2(pd.x, pd.y * tilt);
	pp = vec2(pp.x * cr + pp.y * sr, -pp.x * sr + pp.y * cr);
	vec2 dp = p - pp;
	float pr = 0.006;
	float pdist = length(dp);
	if (pdist < pr * 4.0) {
		float body = smoothstep(pr, pr * 0.85, pdist);
		vec2 ldir = normalize(-pp);
		float lit = clamp(dot(dp / pr, ldir) * 0.8 + 0.25, 0.0, 1.0);
		vec3 pc = vec3(0.6, 0.45, 0.32) * lit * 0.9;
		col = mix(col, pc, body);
		col += vec3(1.0, 0.7, 0.45) * 0.015 / (pdist * pdist * 2000.0 + 0.3) * (1.0 - body);
	}

	// Мягкая виньетка и тёмный левый край под заголовок и кнопки.
	vec2 v = UV - 0.5;
	col *= 1.0 - 0.55 * dot(v, v);
	col *= mix(0.45, 1.0, smoothstep(0.0, 0.5, UV.x));
	// Тонировка: слегка поджимаем светлое, чтобы не выгорало.
	col = col / (1.0 + col * 0.35);
	COLOR = vec4(col, 1.0);
}
