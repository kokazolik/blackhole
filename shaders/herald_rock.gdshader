shader_type canvas_item;
// Огромная галька на этапе пылинки: в тысячу раз крупнее игрока, на экран
// попадает только её край, почти прямой. Поверхность — бесшовная плитка из
// herald_tile_bake (альбедо и рельеф). Вторая выборка той же плитки в 4–5 раз
// крупнее и под углом прячет повтор. Свет как у Странника: резкий терминатор,
// длинные тени от хондр при низкой звезде, ночная сторона почти чёрная.

uniform sampler2D color_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D height_tex : repeat_enable, filter_linear_mipmap;
uniform vec2 light_dir = vec2(-1.0, 0.0);
uniform vec3 star_light : source_color = vec3(1.0, 0.9, 0.75);
uniform vec3 tint = vec3(1.0);
uniform float quad = 1.08;     // половина квадрата в радиусах тела
uniform float tile = 0.05;     // плитка в радиусах тела
uniform float size_pr = 1000.0; // радиус тела в радиусах игрока
uniform vec2 offset = vec2(0.0);
uniform float lump_a[6];
uniform float lump_p[6];

const float LUMP_K[6] = float[](61.0, 97.0, 157.0, 241.0, 373.0, 587.0);
const float LIGHT_Z = 0.22;
const float HS = 0.012;        // рельеф: доля плитки на единицу высоты
const float TEX = 1.0 / 1024.0;

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

void fragment() {
	vec2 p = (UV * 2.0 - 1.0) * quad;
	float r = length(p);
	vec2 u = p / max(r, 1e-5);
	float th = atan(p.y, p.x);
	float edge = 1.0;
	for (int i = 0; i < 6; i++) {
		edge += lump_a[i] * sin(LUMP_K[i] * th + lump_p[i]);
	}
	// Мелкая неровность края в радиусах игрока: вблизи край не идеальная линия.
	vec2 ue = u * size_pr;
	float rough = (noise(ue * 0.3 + offset * 9.0) - 0.5) * 1.4 + (noise(ue * 1.1 + 7.0) - 0.5) * 0.5
			+ (noise(ue * 3.2 + 3.0) - 0.5) * 0.18;
	edge += rough / size_pr;
	float aa = fwidth(r) * 1.2;
	float alpha = 1.0 - smoothstep(edge - aa, edge + aa * 0.5, r);
	if (alpha <= 0.0) {
		discard;
	}

	// Тело в тысячу раз крупнее экрана: сверху видна почти плоская поверхность,
	// чуть наклонённая к краю, а у самого края она скругляется на несколько
	// твоих радиусов — там кромка ловит свет или уходит в тень.
	float e = (edge - r) * size_pr;  // до края, в радиусах игрока
	float rim = 1.0 - smoothstep(0.0, 7.0, e);
	float tilt = 0.3 + 1.8 * rim * rim;
	vec3 n0 = normalize(vec3(u * tilt, 1.0));
	vec2 ps = p;                              // точка на поверхности в радиусах тела
	vec3 tr = normalize(vec3(u, -tilt));      // касательная вдоль радиуса
	vec3 tt = vec3(-u.y, u.x, 0.0);           // касательная поперёк

	// Мелкий слой: хондры, зёрна, поры.
	vec2 t1 = ps / tile + offset;
	vec4 c1 = texture(color_tex, t1);
	vec4 hs = texture(height_tex, t1);
	float h = hs.r;
	float hx = texture(height_tex, t1 + vec2(TEX, 0.0)).r - texture(height_tex, t1 - vec2(TEX, 0.0)).r;
	float hy = texture(height_tex, t1 + vec2(0.0, TEX)).r - texture(height_tex, t1 - vec2(0.0, TEX)).r;
	vec2 g = vec2(hx, hy) * HS / (2.0 * TEX);
	// Крупный слой той же плитки: пятна тона и пологие бугры, прячет повтор.
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	vec2 t2 = rot * ps / (tile * 4.7) + offset.yx * 1.7;
	vec4 c2 = texture(color_tex, t2);
	float h2 = texture(height_tex, t2).r;
	float h2x = texture(height_tex, t2 + vec2(TEX * 4.0, 0.0)).r - h2;
	float h2y = texture(height_tex, t2 + vec2(0.0, TEX * 4.0)).r - h2;
	vec2 g2 = transpose(rot) * (vec2(h2x, h2y) * HS / (4.0 * TEX)) / 4.7;
	g += g2 * 2.2;

	float lum2 = dot(c2.rgb, vec3(0.3, 0.5, 0.2));
	float macro = 0.82 + 0.4 * lum2 + 0.18 * (noise(ps * 3.0 + offset * 5.0) - 0.5);
	vec3 albedo = c1.rgb * tint * macro;
	float metal = c1.a;

	// Нормаль: купол плюс рельеф в касательной плоскости.
	vec3 n = normalize(n0 - tr * dot(g, u) - tt * dot(g, vec2(-u.y, u.x)));

	vec3 L = normalize(vec3(light_dir, LIGHT_Z));
	float day = dot(n0, L);
	float mu0 = max(dot(n, L), 0.0);
	float mu = max(n.z, 0.05);
	float lit = mix(mu0, 2.0 * mu0 / (mu0 + mu), 0.5);

	// Тени от бугров и хондр: идём к звезде по плитке. Чем ниже звезда над
	// местной поверхностью, тем длиннее тени.
	float sinE = clamp(day, 0.0, 0.999);
	float tanE = sinE / sqrt(1.0 - sinE * sinE);
	vec2 sd = normalize(light_dir);
	float shadow = 1.0;
	for (int i = 1; i <= 7; i++) {
		float t = float(i * i) * TEX * 1.6;
		float hh = texture(height_tex, t1 + sd * t).r;
		shadow = min(shadow, smoothstep(-0.03, 0.06, h + t * tanE / HS - hh));
	}
	lit *= mix(0.15, 1.0, shadow) * smoothstep(-0.02, 0.06, day);

	vec3 col = albedo * star_light * lit * 1.5;
	// Металл и стекло хондр вспыхивают, когда грань ловит свет.
	vec3 hv = normalize(L + vec3(0.0, 0.0, 1.0));
	float nh = max(dot(n, hv), 0.0);
	col += star_light * (metal * (0.3 * mu0 + 2.2 * pow(nh, 40.0)) + hs.g * 0.25 * pow(nh, 60.0)) * shadow * step(0.0, day);
	// Едва заметная подсветка ночной стороны пылью диска.
	col += albedo * vec3(0.05, 0.05, 0.065) * (0.5 + 0.5 * n0.z);
	COLOR = vec4(col, alpha * COLOR.a);
}
