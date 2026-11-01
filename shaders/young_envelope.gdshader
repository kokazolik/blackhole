shader_type canvas_item;
render_mode blend_premul_alpha;
// Рыхлая оболочка молодого гиганта. Пока ядро набирает газ, оболочка не
// шар с краем, а огромное облако до сферы Хилла: плотное и горячее у ядра,
// редкое и пыльное снаружи, сливается с газом диска. Когда газ идёт лавиной,
// она перестаёт держаться и падает к ядру: сжимается, густеет и раскаляется
// (свет — от сжатия), потом рассеивается, открывая горячий шар.
// Считаем честно: луч зрения через облако, плотность ρ ∝ r^-1.6 к краю на нет,
// излучение по температуре (внутри горячее), рассеяние звезды на пыли,
// поглощение спереди назад. Газ закручен: внутри вращается быстрее (Кеплер).
// Квад: центр — ядро, 1 — край квада.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float r_out = 0.95;      // край облака (доли половины квада)
uniform float r_in = 0.12;       // радиус фотосферы/ядра (там луч кончается)
uniform float dens = 1.0;        // оптическая толщина
uniform float glow = 1.0;        // светимость сжатия
uniform float temp = 1.5;        // температура в глубине, тыс. К
uniform vec3 dust_col : source_color = vec3(0.7, 0.62, 0.52);
uniform vec2 light_dir = vec2(-1.0, -0.12);
uniform float spin = 0.0;
uniform float seed = 0.0;

// Цвет абсолютно чёрного тела (приближённо), T в тысячах К.
vec3 bb(float t) {
	vec3 c0 = vec3(0.12, 0.01, 0.0);   // 0,5 кК — едва тлеет
	vec3 c1 = vec3(0.55, 0.07, 0.01);  // 0,8
	vec3 c2 = vec3(0.95, 0.28, 0.05);  // 1,2
	vec3 c3 = vec3(1.0, 0.52, 0.18);   // 2,0
	vec3 c4 = vec3(1.0, 0.78, 0.52);   // 3,0
	if (t < 0.8) return mix(c0, c1, clamp((t - 0.5) / 0.3, 0.0, 1.0));
	if (t < 1.2) return mix(c1, c2, (t - 0.8) / 0.4);
	if (t < 2.0) return mix(c2, c3, (t - 1.2) / 0.8);
	return mix(c3, c4, clamp((t - 2.0) / 1.0, 0.0, 1.0));
}

float n2(vec2 p) {
	return texture(noise_tex, p).r;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float b = length(p);
	if (b > r_out) discard;
	vec3 L = normalize(vec3(light_dir, 0.35));
	float zmax = sqrt(max(r_out * r_out - b * b, 0.0));
	float zmin = b < r_in ? sqrt(max(r_in * r_in - b * b, 0.0)) : -zmax;
	const int N = 9;
	float dz = (zmax - zmin) / float(N);
	float T = 1.0;
	vec3 acc = vec3(0.0);
	for (int i = 0; i < N; i++) {
		float z = zmax - (float(i) + 0.5) * dz;
		vec3 q = vec3(p, z);
		float r = length(q);
		// Закрутка: внутренние слои обгоняют внешние.
		float a = spin * pow(r_in / max(r, r_in), 1.5);
		vec2 sw = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * q.xy;
		float t1 = n2(sw * 0.9 + vec2(z * 0.6, seed));
		float t2 = n2(sw * 2.6 + vec2(seed * 1.7, z * 1.3));
		float turb = 0.45 + 0.75 * t1 + 0.35 * (t2 - 0.5);
		float edge = 1.0 - smoothstep(r_out * 0.55, r_out, r);
		float rho = pow(max(r, r_in) / r_in, -1.6) * edge * turb;
		float tau = rho * dens * dz * 9.0;
		// Тепло: глубже — горячее (адиабата), снаружи холодная пыль.
		float tl = temp * pow(r_in / max(r, r_in), 0.7);
		vec3 em = bb(tl) * glow * pow(r_in / max(r, r_in), 1.2) * 1.4;
		// Звезда освещает пыль сбоку; дальняя от звезды сторона в тени облака.
		float lit = 0.25 + 0.75 * smoothstep(-0.7, 0.8, dot(normalize(q), L));
		vec3 sc = dust_col * lit * 0.55;
		float absorb = 1.0 - exp(-tau);
		acc += T * absorb * (em + sc);
		T *= 1.0 - absorb;
	}
	float alpha = 1.0 - T;
	COLOR = vec4(acc, alpha);
}
