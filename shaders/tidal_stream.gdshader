shader_type canvas_item;
render_mode blend_premul_alpha;
// Приливная струя: пыль и мелкие обломки разорванного тела, которые прилив
// гиганта вытянул в нить и закручивает к себе. Лента строится по заранее
// заданной траектории (tidal_streams.gd): гладкая, летит вместе с гигантом.
// Цвет — с текстуры самого тела (снимок в миг разрыва): камень остаётся
// камнем, лёд — льдом, суперземля с морями — с голубизной. Поверх пыли
// светится только то, что раскалено: вход в облака гиганта и искры.
// UV.x — координата вещества (0 — голова, 1 — хвост), UV.y — поперёк.
// Цвет вершин: r — накал, g — освещённость (0 — в тени гиганта), a — плотность.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D body_tex : filter_linear;
uniform bool use_body = false;
uniform float disc = 0.36;
uniform vec3 c_tail : source_color = vec3(0.85, 0.72, 0.55);
uniform vec3 c_glow : source_color = vec3(0.9, 0.55, 0.3);
uniform vec3 c_hot : source_color = vec3(1.0, 0.8, 0.5);
uniform float sparkle = 0.5;
uniform float haze = 0.0;
uniform float len = 20.0;
uniform float time = 0.0;
uniform float seed = 0.0;
uniform vec2 light = vec2(-1.0, 0.0);
uniform float frag_s[16];      // где в нити куски (координата вещества), −1 — нет
uniform float frag_k[16];      // их размер 0..1 (стачиваются)

float n2(vec2 p) {
	return texture(noise_tex, p).r;
}

// Цвет вещества тела: несколько точек снимка вдоль полосы, где это вещество
// было на теле (голова — ближний к гиганту край).
vec3 body_col(float s, float y) {
	vec3 acc = vec3(0.0);
	float w = 0.0;
	for (int i = 0; i < 5; i++) {
		float fi = float(i) - 2.0;
		float bx = mix(-0.8, 0.8, s) + fi * 0.05;
		float by = y * 0.75 * sqrt(max(1.0 - bx * bx, 0.05)) + fi * 0.04;
		vec4 t = texture(body_tex, vec2(0.5) + vec2(bx, by) * disc);
		acc += t.rgb * t.a;
		w += t.a;
	}
	return w > 0.05 ? acc / w : c_tail;
}

void fragment() {
	float x = UV.x;
	float y = UV.y * 2.0 - 1.0;
	float along = x * len;
	float wob = (n2(vec2(along * 0.03 + seed, 0.21)) - 0.5) * 0.8;
	float yy = y + wob * 0.5;
	float core = exp(-yy * yy * mix(3.6, 2.2, haze));
	// Кома у каждого куска: пыль сыплется с него и тянется хвостом назад.
	float coma = 0.0;
	for (int i = 0; i < 16; i++) {
		float fs = frag_s[i];
		if (fs < -0.5) continue;
		float d = x - fs;
		float k = d > 0.0 ? d / 0.09 : d / 0.018;
		coma += exp(-k * k) * frag_k[i];
	}
	coma = min(coma, 1.5) * exp(-yy * yy * 2.5);
	// Пыль: волокна вдоль потока и комки (рой обломков, не трубка).
	float f1 = n2(vec2(along * 0.04 + seed * 1.7, yy * 1.4 + 0.3));
	float f2 = n2(vec2(along * 0.13 - seed, yy * 2.8 + 5.0));
	float f3 = n2(vec2(along * 0.35 + seed * 0.3, yy * 5.0 + 2.0));
	float strands = smoothstep(0.2, 0.95, f1 * 0.6 + f2 * 0.4);
	float clumps = smoothstep(0.45, 0.9, f2 * 0.5 + f3 * 0.6);
	strands = mix(strands, 0.55, haze);
	// Зёрна: рой мелких обломков, каждый ловит свет звезды.
	float gr = n2(vec2(along * 1.3 + seed * 4.0, y * 7.0 + seed));
	float grains = smoothstep(0.7, 0.92, gr);
	// Пыль — облачко, а не мазки кисти: волокна мягкие, контраст небольшой.
	float dens = core * (0.6 + 0.4 * strands) * (0.75 + 0.45 * clumps) + grains * core * 0.3 + coma * (0.6 + 0.5 * strands);
	dens *= smoothstep(1.0, 0.55, abs(y));
	float a = clamp(dens * COLOR.a * 1.05, 0.0, 0.7);
	// Цвет: настоящий цвет тела, свет звезды с одной стороны нити.
	vec3 base = use_body ? body_col(1.0 - x, y) : c_tail;
	base = mix(base, c_tail, 0.3);
	// Пыль рассеивает свет звезды: светлее тела, край к звезде ярче.
	// Пыль матовая: светится отражённым светом звезды, не ярче самого тела.
	float lit = 0.95 + 0.25 * (0.5 - UV.y) * sign(light.x) + 0.25 * (f3 - 0.5);
	vec3 dust = base * lit + base * grains * 0.6;
	// Накал у облаков гиганта и мерцающие искры.
	float heat = COLOR.r;
	float g = n2(vec2(along * 0.6 + time * 0.07 + seed * 5.0, y * 4.0 + time * 0.05));
	// Блики: редкие гладкие грани льда и металла ловят звезду, без мигания.
	float spark = pow(smoothstep(0.7, 1.0, g), 6.0) * sparkle * 1.6 * core * COLOR.g;
	vec3 glow = c_hot * heat * heat * core * 1.2 + c_glow * heat * 0.3 * core;
	glow += mix(vec3(1.0), c_hot, 0.4) * spark;
	dust = mix(dust, c_hot, heat * heat * 0.6);
	COLOR = vec4(dust * a * COLOR.g + glow * COLOR.a, a);
}
