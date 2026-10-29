shader_type canvas_item;
// Планетезималь игрока: свет, тени и настоящий объёмный поворот по запечённому
// рельефу (planetesimal_bake.gdshader). Луч из каждой точки экрана идёт вглубь,
// пока не упрётся в поверхность, — поэтому силуэт точный и бугристый, а не круг.
// От точки удара луч к звезде проверяет, не заслоняет ли её вал или глыба:
// у терминатора длинные тени, как на снимках зондов.

uniform sampler2D surf : filter_linear, repeat_enable;  // высота r + g/64, b — свежесть, a — тон
uniform sampler2D normal_map : filter_linear, repeat_enable;  // нормаль в осях тела
uniform vec2 light_dir = vec2(-1.0, 0.0);
uniform vec3 star_light : source_color = vec3(1.0, 0.9, 0.75);
uniform vec4 emission = vec4(0.0);
uniform vec4 mix_w = vec4(0.25);  // доли: силикаты, металл, углерод, лёд
uniform float spin = 0.0;         // поворот вокруг своей оси, рад
uniform float tilt = 0.45;        // наклон оси к нам
uniform float seed = 0.37;

const float BODY = 0.36;   // единичный радиус тела в долях квадрата (как у гальки)
const float R_MAX = 1.38;  // выше рельеф не поднимается

const vec3 SILICATE = vec3(0.62, 0.55, 0.46);
const vec3 METAL = vec3(0.6, 0.6, 0.62);
const vec3 CARBON = vec3(0.2, 0.18, 0.17);
const vec3 ICE = vec3(0.78, 0.86, 0.95);

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7)) + seed * 91.3) * 43758.5453);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), u.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), u.x), u.y),
			mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), u.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), u.x), u.y), u.z);
}

vec2 equirect(vec3 d) {
	return vec2(atan(d.z, d.x) / TAU + 0.5, acos(clamp(d.y, -1.0, 1.0)) / PI);
}

vec4 surf_at(vec3 d) {
	// Без мип-уровней: на шве долготы они дали бы полосу.
	return textureLod(surf, equirect(d), 0.0);
}

float height_at(vec3 d) {
	vec2 c = surf_at(d).rg;
	return c.r + c.g / 64.0;
}

// Та же высота, но смешанная вручную: видеокарта смешивает соседние пиксели
// долями по 1/256, и точка касания прыгает ступеньками — по поверхности
// бегут горизонтали. Нужна только для точного места касания.
float height_exact(vec3 d) {
	ivec2 size = textureSize(surf, 0);
	vec2 f = equirect(d) * vec2(size) - 0.5;
	ivec2 i = ivec2(floor(f));
	vec2 w = f - floor(f);
	ivec2 i1 = i + ivec2(1);
	i.x = (i.x + size.x) % size.x;
	i1.x = i1.x % size.x;
	i.y = clamp(i.y, 0, size.y - 1);
	i1.y = clamp(i1.y, 0, size.y - 1);
	vec2 a = texelFetch(surf, i, 0).rg;
	vec2 b = texelFetch(surf, ivec2(i1.x, i.y), 0).rg;
	vec2 c = texelFetch(surf, ivec2(i.x, i1.y), 0).rg;
	vec2 e = texelFetch(surf, i1, 0).rg;
	vec2 m = mix(mix(a, b, w.x), mix(c, e, w.x), w.y);
	return m.r + m.g / 64.0;
}

float outside_exact(vec3 q) {
	float l = length(q);
	return l - (1.0 + height_exact(q / l));
}

// Насколько точка снаружи тела (по радиусу).
float outside(vec3 q) {
	float l = length(q);
	return l - (1.0 + height_at(q / l));
}

mat3 body_to_view() {
	float cs = cos(spin);
	float ss = sin(spin);
	float ct = cos(tilt);
	float st = sin(tilt);
	mat3 ry = mat3(vec3(cs, 0.0, -ss), vec3(0.0, 1.0, 0.0), vec3(ss, 0.0, cs));
	mat3 rx = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, ct, st), vec3(0.0, -st, ct));
	return rx * ry;
}

void fragment() {
	vec2 p = (UV - 0.5) / BODY;
	float r2 = dot(p, p);
	if (r2 > R_MAX * R_MAX) {
		discard;
	}
	mat3 m = body_to_view();
	mat3 mi = transpose(m);
	vec3 dir = mi * vec3(0.0, 0.0, -1.0);
	float zb = sqrt(R_MAX * R_MAX - r2);
	vec3 o = mi * vec3(p, zb);
	// Луч к центру: шаг по высоте над поверхностью, но не крупнее доли рельефа.
	float t = 0.0;
	float t_end = 2.0 * zb;
	float f = outside(o);
	float f_min = f;
	float t_prev = 0.0;
	bool hit = false;
	for (int i = 0; i < 40; i++) {
		if (f < 0.0) {
			hit = true;
			break;
		}
		t_prev = t;
		t += clamp(f * 0.75, 0.004, 0.08);
		if (t > t_end) break;
		f = outside(o + dir * t);
		f_min = min(f_min, f);
	}
	// Сглаживаем только снаружи: луч прошёл мимо, но близко к краю. Попавший
	// луч всегда непрозрачен, иначе по склонам шли бы полупрозрачные полосы.
	float aa = fwidth(p.x) * 1.6;
	float alpha = hit ? 1.0 : 1.0 - smoothstep(0.0, aa, f_min);
	if (!hit) {
		if (alpha <= 0.0) discard;
		t = t_prev;
	} else {
		// Уточняем точку пересечения делением отрезка.
		float a = t_prev;
		float b = t;
		for (int i = 0; i < 11; i++) {
			float c = 0.5 * (a + b);
			if (outside_exact(o + dir * c) < 0.0) b = c; else a = c;
		}
		t = b;
	}
	vec3 s = o + dir * t;
	vec3 d = normalize(s);
	// Мелкий узор берём по направлению, а не по точке касания: та чуть дрожит
	// от пикселя к пикселю, и узор рвался бы пятнами.
	vec3 sp = d * 1.1;
	vec4 sd = surf_at(d);
	float h = height_exact(d);

	vec3 n = normalize(textureLod(normal_map, equirect(d), 0.0).xyz);

	// Мелкая зернистость реголита, когда тело на экране крупное.
	float fine = clamp(1.6 - fwidth(p.x) * 260.0, 0.0, 1.0);
	if (fine > 0.0) {
		vec3 q = sp * 160.0;
		float g0 = noise3(q);
		vec3 gn = vec3(noise3(q + vec3(0.4, 0.0, 0.0)), noise3(q + vec3(0.0, 0.4, 0.0)), noise3(q + vec3(0.0, 0.0, 0.4))) - g0;
		n = normalize(n - (gn - dot(gn, n) * n) * 0.35 * fine);
	}

	vec3 L = normalize(mi * vec3(light_dir, 0.25));
	vec3 V = mi * vec3(0.0, 0.0, 1.0);
	// Тени: луч к звезде над рельефом, мягкость по ближайшему зазору.
	// Старт чуть над поверхностью и с запасом: иначе сама поверхность, сглаженная
	// видеокартой ступеньками, затеняет себя полосами.
	float shade = 1.0;
	float ts = 0.02;
	vec3 s0 = s + n * 0.006;
	for (int i = 0; i < 12; i++) {
		float g = outside(s0 + L * ts) + 0.004;
		shade = min(shade, clamp(g * 9.0 / ts, 0.0, 1.0));
		if (shade <= 0.0) break;
		ts *= 1.55;
		if (ts > 1.6) break;
	}

	// Вещество: цвет по составу, старая поверхность выветрена (темнее, краснее),
	// свежий выброс светлее и холоднее. Свежесть видна на любом составе.
	float fresh = sd.b;
	float tone = sd.a;
	vec3 base = SILICATE * mix_w.x + METAL * mix_w.y + CARBON * mix_w.z + ICE * mix_w.w;
	base *= 1.0 - 0.25 * mix_w.z;
	vec3 weathered = base * vec3(0.92, 0.85, 0.78) * 0.85;
	vec3 young = base * vec3(1.05, 1.1, 1.18) * 1.55;
	vec3 albedo = mix(weathered, young, fresh) * (0.72 + 0.56 * tone);
	albedo *= 0.9 + 0.2 * noise3(sp * 40.0) * fine + 0.1 * (1.0 - fine);
	// Лёд: иней в низинах и на свежих сколах, гуще с долей льда.
	float frost = smoothstep(0.45, 0.95, mix_w.w + 0.35 * fresh + 0.25 * (tone - 0.5) - 1.5 * h * mix_w.w);
	albedo = mix(albedo, ICE * (0.9 + 0.2 * tone), frost);

	// Реголит рассеивает как Луна: смесь Ламберта и Ломмеля — Зеелигера, край
	// диска не темнеет, а у терминатора свет падает резко.
	float mu0 = max(dot(n, L), 0.0);
	float mu = max(dot(n, V), 0.05);
	float ls = 2.0 * mu0 / (mu0 + mu);
	float refl = mix(mu0, ls * 0.5, 0.55) * shade;
	// Ночную сторону чуть подсвечивает пылевой диск: силуэт не тонет в чёрном небе.
	float disk = 0.05 + 0.04 * max(dot(n, -L), 0.0);
	vec3 col = albedo * star_light * (disk + 2.1 * refl);
	// Металл искрит, иней блестит.
	vec3 hv = normalize(L + V);
	float nh = max(dot(n, hv), 0.0);
	float speck = smoothstep(0.9 - 0.1 * mix_w.y, 0.97, noise3(sp * 90.0)) * (0.1 + 1.4 * mix_w.y) * fine;
	col += star_light * speck * pow(nh, 14.0) * 1.4 * shade;
	col += star_light * frost * pow(nh, 12.0) * 0.3 * shade;

	col *= COLOR.rgb;
	float luma = dot(albedo, vec3(0.3, 0.5, 0.2));
	vec3 glow = emission.rgb * emission.a * (0.55 + 0.45 * luma + 0.5 * mu0);
	COLOR = vec4(col * (1.0 - 0.6 * emission.a) + glow * 1.6, alpha * COLOR.a);
}
