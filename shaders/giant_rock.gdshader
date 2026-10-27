shader_type canvas_item;
// Свет на Страннике: рельеф и альбедо запечены в текстуру giant_bake.gdshader
// (r — высота, g — альбедо, b — купол, a — силуэт), здесь только освещение.
// Как на снимках Бенну и Рюгу: тёмный нейтральный камень, резкий терминатор,
// длинные тени от бугров при низком солнце, ночная сторона почти чёрная.

uniform vec2 light_dir = vec2(-1.0, 0.0);
uniform vec3 star_light : source_color = vec3(1.0, 0.9, 0.75);
uniform vec4 mix_w = vec4(0.5, 0.15, 0.25, 0.1);  // силикаты, металл, углерод, лёд: лёгкий оттенок

const vec3 ROCK = vec3(0.30, 0.285, 0.27);  // темнее любой гальки, почти нейтральный
const float LIGHT_Z = 0.22;                 // звезда в плоскости диска: свет почти скользящий
const float BODY = 0.36;
const float DOME_H = 0.35;                  // высота купола в единицах рельефа

void fragment() {
	vec4 s = texture(TEXTURE, UV);
	if (s.a <= 0.0) {
		discard;
	}
	vec2 px = TEXTURE_PIXEL_SIZE;
	float h0 = s.r + s.b * DOME_H;
	float hx = texture(TEXTURE, UV + vec2(px.x, 0.0)).r + texture(TEXTURE, UV + vec2(px.x, 0.0)).b * DOME_H;
	float hy = texture(TEXTURE, UV + vec2(0.0, px.y)).r + texture(TEXTURE, UV + vec2(0.0, px.y)).b * DOME_H;
	float hxm = texture(TEXTURE, UV - vec2(px.x, 0.0)).r + texture(TEXTURE, UV - vec2(px.x, 0.0)).b * DOME_H;
	float hym = texture(TEXTURE, UV - vec2(0.0, px.y)).r + texture(TEXTURE, UV - vec2(0.0, px.y)).b * DOME_H;
	// Шаг текселя в единицах тела (радиус ~1).
	float step_u = px.x / BODY * 2.0;
	vec2 grad = vec2(hx - hxm, hy - hym) / step_u;
	// Край купола крутой: без этого кромка выглядела бы плоской.
	vec2 p = (UV - 0.5) / BODY;
	vec3 n = normalize(vec3(-grad * 0.9 + p * (1.0 - s.b) * 1.2, 1.0));

	vec3 L = normalize(vec3(light_dir, LIGHT_Z));
	float mu0 = max(dot(n, L), 0.0);
	float mu = max(n.z, 0.05);
	// Тёмный реголит рассеивает по Ломмелю — Зеелигеру: ровнее Ламберта на свету,
	// но к терминатору гаснет резко.
	float lit = mix(mu0, 2.0 * mu0 / (mu0 + mu), 0.5);

	// Тени от бугров: идём к звезде по текстуре и смотрим, не заслоняет ли рельеф.
	vec2 sd = normalize(light_dir) * BODY;
	float shadow = 1.0;
	for (int i = 1; i <= 8; i++) {
		float t = float(i) * 0.03;
		vec4 o = texture(TEXTURE, UV + sd * t);
		float hh = o.r + o.b * DOME_H;
		float rise = t * LIGHT_Z / length(light_dir);
		shadow = min(shadow, smoothstep(-0.004, 0.012, h0 + rise - hh));
	}
	lit *= shadow;

	vec3 tint = vec3(1.0) + vec3(0.06, 0.02, -0.04) * mix_w.x - vec3(0.06) * mix_w.z + vec3(-0.02, 0.0, 0.04) * mix_w.y;
	vec3 albedo = ROCK * tint * s.g * 2.0;
	vec3 col = albedo * star_light * lit * 1.35;
	// Едва заметная подсветка ночной стороны пылью диска.
	col += albedo * vec3(0.08, 0.08, 0.1) * (0.4 + 0.6 * s.b);
	COLOR = vec4(col, s.a * COLOR.a);
}
