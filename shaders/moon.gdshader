shader_type canvas_item;
// Луна вблизи: настоящий шар, а не кружок. Рельеф по 3D-шуму на сфере,
// кратеры с валами и светлыми лучами, тёмные моря, мягкий терминатор,
// потемнение к краю. Свой вид у каждого состава:
// 0 — камень (серые кратеры и моря, как Луна),
// 1 — лёд (светлая корка в рыжих трещинах, как Европа),
// 2 — сера (жёлто-рыжие пятна вулканов, как Ио),
// 3 — углерод (тёмная, густо изрытая, как Каллисто),
// 4 — железо (серо-стальная, гладкие равнины с бликом),
// 5 — смесь (пёстрые светлые и тёмные области, как Ганимед).
// Квад — 2.2 радиуса луны.

uniform int style = 0;
uniform vec2 light_dir = vec2(-1.0, 0.0);   // к звезде, в координатах квада
uniform vec3 star_light : source_color = vec3(1.0, 0.93, 0.82);
uniform float seed = 0.0;
uniform float spin = 0.0;
uniform float shadow = 1.0;    // тень гиганта: 0 — затмение
uniform float heat = 0.0;      // накал при падении
uniform float form = 1.0;      // 0..1: луна ещё собирается, края рыхлые

const float BODY = 1.0 / 1.1;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7)) + seed * 57.3) * 43758.5453);
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

float fbm(vec3 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		s += a * noise3(p);
		p = p * 2.05 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return s;
}

// Кратеры: ячейки Вороного на сфере. x — чаша (тёмное дно), y — вал, z — лучи.
vec3 craters(vec3 p, float scale) {
	vec3 q = p * scale;
	vec3 i = floor(q);
	vec3 f = fract(q);
	float best = 9.0;
	float rad = 0.0;
	for (int x = -1; x <= 1; x++)
	for (int y = -1; y <= 1; y++)
	for (int z = -1; z <= 1; z++) {
		vec3 o = vec3(float(x), float(y), float(z));
		vec3 c = o + vec3(hash3(i + o), hash3(i + o + 7.1), hash3(i + o + 3.3)) - f;
		float d = length(c);
		float rr = 0.18 + 0.3 * hash3(i + o + 11.7);
		if (d / rr < best) {
			best = d / rr;
			rad = rr;
		}
	}
	float bowl = 1.0 - smoothstep(0.0, 0.85, best);
	float rim = exp(-pow((best - 0.95) / 0.12, 2.0));
	float rays = smoothstep(1.0, 2.6, best) * (1.0 - smoothstep(2.6, 3.2, best)) * step(0.4, rad);
	return vec3(bowl, rim, rays);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0 / BODY;
	float r = length(p);
	float edge = fwidth(r) * 1.5;
	// Рыхлая, ещё не собравшаяся луна: край рваный.
	float ragged = (1.0 - form) * 0.35 * (fbm(vec3(p * 4.0, seed)) - 0.5);
	if (r > 1.0 + edge + abs(ragged) + 0.05) discard;
	vec3 n = vec3(p, sqrt(max(1.0 - min(r * r, 1.0), 0.0)));
	float cs = cos(spin);
	float sn = sin(spin);
	vec3 d = vec3(cs * n.x + sn * n.z, n.y, -sn * n.x + cs * n.z) + seed * 3.0;

	float big = fbm(d * 1.6);
	float mid = fbm(d * 4.5);
	float fine = fbm(d * 14.0);
	vec3 cr1 = craters(d, 3.0);
	vec3 cr2 = craters(d + 5.0, 7.5);
	vec3 alb;
	float bump = 0.0;
	if (style == 1) {
		// Лёд: светлая корка, сеть рыжих трещин-линий, мало кратеров.
		alb = vec3(0.86, 0.88, 0.9) * (0.9 + 0.15 * mid);
		float l1 = 1.0 - smoothstep(0.0, 0.025, abs(fbm(d * 3.0) - 0.5));
		float l2 = 1.0 - smoothstep(0.0, 0.015, abs(fbm(d * 6.0 + 4.0) - 0.5));
		alb = mix(alb, vec3(0.62, 0.42, 0.3), max(l1 * 0.8, l2 * 0.5));
		alb = mix(alb, vec3(0.7, 0.6, 0.52), smoothstep(0.55, 0.75, big) * 0.5);
		bump = (cr2.y - cr2.x) * 0.15;
	} else if (style == 2) {
		// Сера: жёлто-рыжая поверхность в пятнах вулканов и тёмных кальдер.
		alb = mix(vec3(0.86, 0.74, 0.38), vec3(0.78, 0.5, 0.25), smoothstep(0.4, 0.7, big));
		alb = mix(alb, vec3(0.95, 0.92, 0.75), smoothstep(0.6, 0.8, mid) * 0.6);
		float vents = smoothstep(0.82, 0.9, fbm(d * 6.0 + 2.0));
		alb = mix(alb, vec3(0.12, 0.08, 0.05), vents);
		alb = mix(alb, vec3(0.75, 0.32, 0.15), smoothstep(0.7, 0.82, fbm(d * 6.0 + 2.0)) * (1.0 - vents) * 0.7);
		bump = (mid - 0.5) * 0.2;
	} else if (style == 3) {
		// Углерод: тёмная, густо изрытая, светлые валы свежих кратеров.
		alb = vec3(0.24, 0.22, 0.2) * (0.8 + 0.4 * mid);
		alb += vec3(0.4, 0.38, 0.35) * (cr1.y * 0.6 + cr2.y * 0.4 + cr1.z * 0.25);
		bump = (cr1.y - cr1.x) * 0.5 + (cr2.y - cr2.x) * 0.35;
	} else if (style == 4) {
		// Железо: стальные равнины, редкие кратеры, металлический блеск.
		alb = vec3(0.6, 0.6, 0.63) * (0.85 + 0.2 * big) * (0.95 + 0.1 * fine);
		bump = (cr1.y - cr1.x) * 0.3;
	} else if (style == 5) {
		// Смесь: светлые бороздчатые области и тёмные древние.
		float dark = smoothstep(0.45, 0.6, big);
		alb = mix(vec3(0.7, 0.68, 0.64), vec3(0.36, 0.33, 0.3), dark);
		float grooves = 0.5 + 0.5 * sin(dot(d, vec3(14.0, 9.0, 5.0)) + mid * 8.0);
		alb *= 0.92 + 0.12 * grooves * (1.0 - dark);
		alb += vec3(0.25) * cr2.z * 0.6;
		bump = (cr1.y - cr1.x) * 0.35 + (cr2.y - cr2.x) * 0.25;
	} else {
		// Камень: серые высокогорья, тёмные моря, кратеры с лучами.
		float mare = smoothstep(0.52, 0.6, big);
		alb = mix(vec3(0.66, 0.64, 0.61), vec3(0.3, 0.3, 0.31), mare);
		alb *= 0.88 + 0.2 * mid;
		alb += vec3(0.3) * (cr1.z * 0.5 + cr2.z * 0.3) * (1.0 - mare * 0.5);
		bump = (cr1.y - cr1.x) * 0.45 * (1.0 - mare * 0.6) + (cr2.y - cr2.x) * 0.3;
	}
	alb *= 0.92 + 0.12 * fine;

	// Свет: нормаль чуть наклонена рельефом, мягкий терминатор.
	vec3 L = normalize(vec3(light_dir, 0.35));
	vec2 grad = vec2(dFdx(bump), dFdy(bump)) / max(fwidth(r), 1e-4) * 0.04;
	vec3 nn = normalize(n - vec3(grad, 0.0));
	float ndl = dot(nn, L);
	float diff = smoothstep(-0.05, 0.6, ndl) * (0.25 + 0.75 * max(ndl, 0.0));
	float limb = 0.75 + 0.25 * pow(max(n.z, 0.0), 0.5);
	vec3 col = alb * star_light * (0.015 + 1.25 * diff) * limb * shadow;
	if (style == 4) {
		vec3 h = normalize(L + vec3(0.0, 0.0, 1.0));
		col += star_light * pow(max(dot(nn, h), 0.0), 30.0) * 0.25 * shadow;
	}
	// Отражённый свет гиганта слегка подсвечивает ночную сторону.
	col += alb * vec3(0.06, 0.05, 0.045) * (1.0 - smoothstep(-0.2, 0.2, ndl));
	// Накал при падении в гиганта.
	col = mix(col, vec3(1.0, 0.5, 0.2) * (0.6 + 0.6 * fine), heat * 0.8);
	float alpha = 1.0 - smoothstep(1.0 - edge + ragged, 1.0 + edge + ragged, r);
	alpha *= mix(0.55 + 0.45 * fine, 1.0, form);
	COLOR = vec4(col, alpha);
}
