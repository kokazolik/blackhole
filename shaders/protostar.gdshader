shader_type canvas_item;
render_mode blend_premul_alpha;
// Протозвезда в коконе, как HH 30 на снимках «Хаббла»: диск ребром даёт тёмную
// полосу поперёк ядра, над и под ней светятся два лепестка отражённого света,
// по оси бьют джеты с узлами Хербига–Аро. После зажигания кокон тает, и в
// центре остаётся звезда с короткими дифракционными лучами.
// Координаты квада: от −4 до 4 радиусов кокона.

uniform float heat = 0.3;        // свечение ядра до зажигания, 0..1
uniform float lit = 0.0;         // зажигание, 0..1
uniform vec3 star_col : source_color = vec3(1.0, 0.9, 0.72);
uniform vec3 cocoon_col : source_color = vec3(0.72, 0.6, 0.48);
uniform float cocoon = 1.0;      // плотность кокона
uniform float disk = 1.0;        // заметность диска
uniform float jets = 0.0;        // сила джетов
uniform float axis = 0.3;        // угол оси джетов, радианы
uniform float tilt = 0.25;       // насколько диск открыт к нам (0 — ребром)
uniform float time = 0.0;
uniform float flare = 0.0;       // вспышка FU Ориона
uniform float seed = 0.0;
uniform float detail = 1.0;      // 0 — дешёвый вид для соседей

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 p = (UV * 2.0 - 1.0) * 4.0;
	float r = length(p);
	float ca = cos(-axis);
	float sa = sin(-axis);
	vec2 q = vec2(ca * p.x - sa * p.y, sa * p.x + ca * p.y);   // x — плоскость диска, y — ось
	vec2 sd = vec2(seed * 17.0, seed * 31.0);
	float n = detail > 0.5 ? fbm(q * 1.6 + sd + vec2(0.0, time * 0.02)) : 0.5;
	float n2 = detail > 0.5 ? fbm(q * 4.2 - sd + vec2(time * 0.05, 0.0)) : 0.5;
	float clear = 1.0 - 0.85 * lit;   // зажигание сдувает кокон

	// Пылевой кокон: мягкий шар с клочьями.
	float env = exp(-r * r / 1.3) * (0.45 + 0.8 * n) * cocoon * clear;
	// Диск ребром: тёмная полоса поперёк ядра, чуть раскрыта наклоном.
	float lane_w = 0.1 + 0.18 * tilt + 0.05 * (n2 - 0.5);
	float lane = exp(-pow(q.y / lane_w, 2.0)) * smoothstep(1.9, 0.15, abs(q.x)) * disk * (1.0 - 0.6 * lit);
	// Два лепестка отражённого света над и под диском, вытянутые вдоль оси.
	float ay = abs(q.y);
	float lobe = exp(-pow(ay - 0.65, 2.0) / 0.3 - q.x * q.x / (0.16 + 0.5 * ay)) * (0.5 + 1.1 * n) * 1.6;
	// Нижний лепесток за диском, он тусклее (диск чуть наклонён к нам).
	lobe *= q.y > 0.0 ? 1.0 : 0.45 + 0.4 * tilt;
	float light = heat * 0.8 + lit * 1.6 + flare * 2.5;
	vec3 refl = mix(cocoon_col, star_col, 0.55) * lobe * light * cocoon * clear;

	// Ядро: видно сквозь полосу диска только после зажигания.
	float core = 0.025 / (r * r + 0.025);
	core *= mix(1.0 - 0.9 * lane * cocoon, 1.0, lit);
	float spikes = 0.0;
	if (lit > 0.01) {
		// Короткие лучи дифракции, как на снимках телескопов.
		vec2 a = abs(p);
		spikes = (exp(-a.x * 40.0) * exp(-a.y * 1.6) + exp(-a.y * 40.0) * exp(-a.x * 1.6)) * 0.6;
		vec2 d = abs(vec2(p.x + p.y, p.x - p.y)) * 0.7071;
		spikes += (exp(-d.x * 55.0) * exp(-d.y * 2.6) + exp(-d.y * 55.0) * exp(-d.x * 2.6)) * 0.22;
		spikes *= lit;
	}
	vec3 core_col = mix(vec3(1.0, 0.45, 0.18), star_col, lit);
	vec3 col = core_col * (core * (0.35 + light) + spikes * (0.6 + flare));
	// Внешнее свечение звезды после зажигания.
	col += star_col * lit * 0.35 * exp(-r * 1.4);

	// Джеты с узлами, бегущими от звезды, и дуга ударной волны на конце.
	float jet = 0.0;
	float knot = 0.0;
	if (jets > 0.01) {
		float wid = 0.02 + 0.05 * ay;
		float body = exp(-q.x * q.x / (wid * wid)) * smoothstep(3.7, 0.25, ay) * smoothstep(0.1, 0.35, ay);
		float k = pow(0.5 + 0.5 * sin(ay * 7.0 - time * 2.4 + seed * 6.28 + (q.y > 0.0 ? 0.0 : 1.7)), 8.0);
		jet = body * (0.25 + 0.6 * n2) * jets;
		knot = body * k * jets;
		// Дуга ударной волны: только внешняя половина, рваная и мягкая.
		float bow = exp(-pow((length(vec2(q.x * 1.3, ay - 2.9)) - 0.4) / 0.12, 2.0)) * smoothstep(2.85, 3.25, ay) * jets;
		jet += bow * (0.15 + 0.5 * n2) * 0.6;
	}
	col += vec3(1.0, 0.32, 0.38) * jet * 0.9 + vec3(1.0, 0.85, 0.8) * knot * 0.9;

	float dust = clamp(env * 0.9 + lane * 0.85 * cocoon, 0.0, 0.96);
	vec3 dust_col = cocoon_col * 0.18 * (0.4 + light * 0.5);
	col += refl;
	// Предварительно умноженная альфа: пыль заслоняет фон, свет складывается.
	float edge = smoothstep(4.0, 3.2, r);
	COLOR = vec4((col + dust_col * dust) * edge, dust * edge);
}
