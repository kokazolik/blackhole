shader_type canvas_item;
// Кусок разорванного тела. Тело снимается в текстуру в миг разрыва (своим же
// шейдером: кратеры, моря, лёд, облака), потом режется на ячейки Вороного
// с рваными краями. Каждый кусок несёт свою часть настоящей поверхности.
// Прилив не плавит тело: свежий скол просто другого цвета — у льда чистый
// яркий лёд из недр, у камня серая пыль, у углерода чёрный излом. Светится
// только расплав у лавового тела. Прилив стачивает кусок с краёв в пыль.

uniform sampler2D body_tex : filter_linear;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec2 seeds[16];        // центры ячеек в радиусах тела
uniform int n = 8;
uniform int cell = 0;
uniform float disc = 0.36;     // радиус тела в долях ширины текстуры
uniform vec3 crack_col : source_color = vec3(1.0, 0.45, 0.15);
uniform float crack = 0.0;     // накал трещин 0..1
uniform float erode = 0.0;     // сколько сточено 0..1
uniform float seed = 0.0;
uniform float shade = 1.0;     // 1 — на свету, меньше — в тени гиганта
uniform float emit = 0.0;      // 1 — сколы светятся (расплав лавового тела)

void fragment() {
	vec2 q = (UV - 0.5) / disc;
	if (length(q) > 1.04) discard;
	// Рваные края: ячейки Вороного по зашумлённым координатам.
	vec2 jq = q + (vec2(texture(noise_tex, q * 0.35 + seed).r, texture(noise_tex, q * 0.35 + seed + 0.5).r) - 0.5) * 0.28;
	float d1 = 1e9;
	float d2 = 1e9;
	int best = 0;
	for (int i = 0; i < 16; i++) {
		if (i >= n) break;
		float d = distance(jq, seeds[i]);
		if (d < d1) { d2 = d1; d1 = d; best = i; }
		else if (d < d2) { d2 = d; }
	}
	if (best != cell) discard;
	float edge = d2 - d1;                 // расстояние до соседней ячейки
	vec4 tex = texture(body_tex, UV);
	if (tex.a < 0.02) discard;
	// Стачивание: сначала края и тонкие места, потом всё.
	float nn = texture(noise_tex, q * 0.8 + seed * 2.0).r;
	float keep = edge * 2.2 + (1.0 - length(q)) * 0.6 + nn * 0.5 - erode * 1.6;
	if (keep < 0.0) discard;
	// Обломок крутится, и тёмная сторона тела тоже выходит на свет:
	// поднимаем тени (рассеянный свет диска и звезды).
	vec3 col = tex.rgb * 1.1 + vec3(0.05, 0.045, 0.04) + tex.rgb * (1.0 - length(tex.rgb)) * 0.6;
	// Свежий скол: полоса по краю куска цвета недр, шероховатая.
	float rim = exp(-edge * 30.0) * crack * (0.6 + 0.5 * nn);
	col = mix(col, crack_col * (0.8 + 0.4 * nn), clamp(rim, 0.0, 0.85));
	// Край, который стачивается, пылит: светлее и прозрачнее.
	float dusty = smoothstep(0.12, 0.0, keep) * erode;
	col = mix(col, crack_col, dusty * 0.5);
	col *= shade;
	col += crack_col * emit * (rim * 1.4 + dusty * 0.6);
	COLOR = vec4(col, tex.a * smoothstep(0.0, 0.05, keep));
}
