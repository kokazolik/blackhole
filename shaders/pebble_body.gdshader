shader_type canvas_item;
// Галька игрока целиком процедурная, по образцу хондритов и зёрен Рюгу и Бенну:
// тёмная матовая пористая матрица цвета состава, круглые светлые хондры,
// искры металлических крупинок, у ледяной — пушистая изморозь.
// Состав (mix) player.gd сглаживает, поэтому вид перетекает плавно.
// Рисуется один раз за кадр на одном теле, так что расчёт шума телефону не в тягость.

uniform vec2 light_dir = vec2(-1.0, 0.0);
uniform vec3 star_light : source_color = vec3(1.0, 0.9, 0.75);
uniform vec4 emission = vec4(0.0);   // тепловое свечение (rgb, сила в a)
uniform vec4 mix_w = vec4(0.25);     // доли: силикаты, металл, углерод, лёд
uniform float growth = 0.0;          // 0 — свежая галька, 1 — почти валун
uniform float boulder = 0.0;         // 0 — галька, 1 — крупный валун: угловатее, мельче зерно, трещины
uniform float seed = 0.37;
uniform float detail = 1.0;  // во сколько раз мельче узор: у огромного тела зёрна те же, что у гальки

const float BODY = 0.36;  // радиус тела в долях квадрата

// Цвета ярче настоящих (это игра), но оттенки взяты из жизни: камень тёплый,
// металл серебристый, углистое вещество бурое, лёд голубовато-белый.
const vec3 SILICATE = vec3(0.76, 0.64, 0.47);
const vec3 METAL = vec3(0.62, 0.64, 0.7);
const vec3 CARBON = vec3(0.3, 0.22, 0.2);
const vec3 ICE = vec3(0.74, 0.84, 0.94);  // изморозь с примесью пыли, не снег
const vec3 CHONDRULE = vec3(0.86, 0.87, 0.66);  // светлый оливин

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 91.3) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
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

// Ячейки Вороного: расстояния до ближайшей и второй точки и номер ячейки.
vec3 voronoi(vec2 x, out vec2 cell_id) {
	vec2 xi = floor(x);
	vec2 xf = fract(x);
	float f1 = 8.0;
	float f2 = 8.0;
	cell_id = xi;
	for (int y = -1; y <= 1; y++) {
		for (int xx = -1; xx <= 1; xx++) {
			vec2 g = vec2(float(xx), float(y));
			vec2 o = vec2(hash(xi + g + 3.3), hash(xi + g + 9.1));
			float d = length(g + o - xf);
			if (d < f1) {
				f2 = f1;
				f1 = d;
				cell_id = xi + g;
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	return vec3(f1, f2, f2 - f1);
}

// Силуэт валуна: выпуклая глыба из нескольких плоскостей скола.
// Возвращает «радиус» многоугольника в направлении u.
float block_edge(vec2 u) {
	float r = 10.0;
	for (int k = 0; k < 7; k++) {
		float fk = float(k);
		float a = fk * 0.8976 + seed * 6.0 + (hash(vec2(fk, 3.7)) - 0.5) * 0.7;
		vec2 nk = vec2(cos(a), sin(a));
		float dk = 0.86 + 0.14 * hash(vec2(fk, 8.1));
		float c = dot(u, nk);
		if (c > 0.05) {
			r = min(r, dk / c);
		}
	}
	return r;
}

float height(vec2 p) {
	return fbm(p * 2.2);
}

void fragment() {
	vec2 p = (UV - 0.5) / BODY;
	// Неровный силуэт: несколько гармоник по углу. С ростом тело комковатее.
	float th = atan(p.y, p.x);
	float amp = 0.07 + 0.05 * growth + 0.05 * boulder;
	float edge = 1.0 + amp * (0.55 * sin(2.0 * th + seed * 6.0) + 0.3 * sin(3.0 * th + seed * 11.0)
			+ 0.15 * sin(5.0 * th + seed * 17.0)) + 0.05 * (noise(vec2(cos(th), sin(th)) * 2.5 + seed * 10.0) - 0.5);
	if (boulder > 0.0) {
		// Валун угловатый: грани скола со скруглёнными рёбрами и сколами по краю.
		float poly = block_edge(vec2(cos(th), sin(th)));
		poly = min(poly, 1.12) * 0.97 + 0.04 * (noise(vec2(cos(th), sin(th)) * 7.0 + seed * 3.0) - 0.5);
		edge = mix(edge, poly, smoothstep(0.0, 0.6, boulder));
	}
	vec2 pt = p * detail;  // для узора поверхности, не для силуэта
	float r = length(p);
	float aa = fwidth(r) * 1.2;
	// Ледяная галька — рыхлый комок, как снежок: край пушистый и полупрозрачный.
	float fluff = smoothstep(0.3, 0.8, mix_w.w);
	float fr = r + fluff * 0.12 * (noise(pt * 13.0 + seed * 5.0) - 0.5);
	float soft = aa + fluff * 0.09;
	float alpha = 1.0 - smoothstep(edge - soft, edge + soft * 0.6, fr);
	if (alpha <= 0.0) {
		discard;
	}

	// Нормаль: сплюснутый шар по силуэту плюс рельеф от шума.
	vec2 q = p / edge;
	vec3 n = vec3(q, sqrt(max(1.0 - dot(q, q), 0.0)) + 0.05);
	float h = height(pt);
	float eps = 0.03;
	vec2 grad = vec2(height(pt + vec2(eps, 0.0)) - h, height(pt + vec2(0.0, eps)) - h) / eps;
	n = normalize(n - vec3(grad * 0.09, 0.0));

	// Основа (матрица) — спёкшаяся пыль цвета всего состава.
	vec3 base = SILICATE * mix_w.x + METAL * mix_w.y + CARBON * mix_w.z + ICE * mix_w.w;
	base *= 1.0 - 0.25 * mix_w.z;  // сажа темнит чуть сильнее своей доли
	float pores = noise(pt * 19.0);
	base *= (0.8 + 0.35 * h) * (0.9 + 0.2 * pores);

	// Хондры: круглые застывшие капли силиката, светлее матрицы. Их больше,
	// чем больше в составе камня. С ростом тела видно больше и они мельче.
	float cells = 3.6 + 3.0 * growth + 8.0 * boulder;
	vec2 cp = pt * cells + vec2(seed * 13.0);
	vec2 ci = floor(cp);
	vec2 cf = fract(cp);
	float chond = 0.0;
	vec2 dome = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 cell = ci + g;
			float rad = 0.2 + 0.18 * hash(cell + 5.1);
			float present = step(hash(cell + 41.7), 0.35 + 0.6 * mix_w.x);
			vec2 d = g + 0.25 + 0.5 * vec2(hash(cell), hash(cell + 17.3)) - cf;
			float k = (1.0 - smoothstep(rad - 0.04, rad, length(d))) * present;
			if (k > chond) {
				chond = k;
				dome = -d / rad;  // наклон купола капли к краю
			}
		}
	}
	// Под налётом пыли хондры не сияют пятнами: светлее матрицы, но в её тоне.
	vec3 chondrule = mix(CHONDRULE, base * 1.3, 0.45) * (0.9 + 0.2 * noise(pt * 30.0));
	vec3 albedo = mix(base, chondrule, chond * 0.75 * (1.0 - 0.85 * boulder));

	// Валун: как глыбы на Рюгу и Бенну и как брекчии-метеориты. Крупные плоские
	// грани скола, вкрапления угловатых обломков другого тона, трещины,
	// мелкие поры и светлая реголитовая пыль в углублениях.
	if (boulder > 0.0) {
		float b = boulder;
		// Мелкие детали гаснут, когда тело на экране маленькое: иначе рябят.
		float fine = clamp(1.4 - fwidth(pt.x) * 45.0, 0.0, 1.0);
		// Грани: тело — многогранник. Каждая крупная ячейка освещена как плоскость,
		// касательная к телу в своём центре, плюс небольшой случайный наклон скола.
		vec2 fid;
		vec2 fo = vec2(seed * 5.0);
		vec3 fv = voronoi(p * 2.1 + fo, fid);
		vec2 fc = (fid + vec2(hash(fid + 3.3), hash(fid + 9.1)) - fo) / 2.1;
		vec2 fq = fc / edge;
		fq *= min(1.0, 0.92 / max(length(fq), 0.001));
		vec3 nf = normalize(vec3(fq, sqrt(max(1.0 - dot(fq, fq), 0.0)) + 0.05));
		nf = normalize(nf + vec3((vec2(hash(fid + 1.3), hash(fid + 7.9)) - 0.5) * 0.35, 0.0));
		float ridge = 1.0 - smoothstep(0.0, 0.04, fv.z);
		n = normalize(mix(n, nf, 0.75 * b));
		// Обломки в цементе: угловатые зёрна светлее или темнее основы.
		vec2 cid;
		vec2 wp = pt * 5.5 + vec2(seed * 11.0) + (vec2(noise(pt * 6.0), noise(pt * 6.0 + 3.1)) - 0.5) * 0.35;
		vec3 cv = voronoi(wp, cid);
		float is_clast = step(hash(cid + 2.2), 0.3);
		float tone = hash(cid + 5.5);
		vec3 clast_col = base * mix(vec3(0.7, 0.68, 0.66), vec3(1.25, 1.22, 1.12), tone);
		float clast = is_clast * smoothstep(0.02, 0.06, cv.z);
		albedo = mix(albedo, clast_col, clast * b);
		albedo *= 1.0 - 0.35 * b * is_clast * (1.0 - smoothstep(0.0, 0.03, cv.z));  // тонкий шов вокруг обломка
		// Трещины: длинные неровные линии по границам крупных блоков.
		vec2 kid;
		vec2 kp = pt * 2.4 + vec2(seed * 7.0) + (vec2(noise(pt * 3.1), noise(pt * 3.1 + 5.2)) - 0.5) * 0.8;
		vec3 kv = voronoi(kp, kid);
		float crack = (1.0 - smoothstep(0.0, 0.035, kv.z)) * smoothstep(0.35, 0.6, noise(pt * 3.5 + 11.0));
		albedo *= 1.0 - 0.7 * b * crack;
		// Поры и ямки.
		float pit = smoothstep(0.78, 0.86, noise(pt * 22.0 + 7.0));
		albedo *= 1.0 - 0.45 * b * pit * fine;
		// Рельеф грубее, чем у гальки.
		float hb = fbm(pt * 9.0 + 4.0);
		vec2 gb = vec2(fbm(pt * 9.0 + 4.0 + vec2(0.02, 0.0)) - hb, fbm(pt * 9.0 + 4.0 + vec2(0.0, 0.02)) - hb) / 0.02;
		n = normalize(n - vec3(gb * 0.05 * b * fine, 0.0));
		// Рёбра граней ловят свет, а в ямках копится светлая пыль.
		albedo *= 1.0 + 0.18 * b * ridge;
		float dust = smoothstep(0.1, 0.5, 0.48 - h) * (1.0 - clast);
		albedo = mix(albedo, mix(base, vec3(0.72, 0.68, 0.62), 0.5), dust * 0.35 * b);
	}
	n = normalize(n + vec3(dome * 0.35 * chond * (1.0 - boulder), 0.0));

	// Лёд: светлая пушистая изморозь поверх всего, гуще в ямках рельефа.
	float frost = smoothstep(0.4, 0.95, mix_w.w + 0.35 * (fbm(pt * 7.0) - 0.5) + 0.2 * (0.5 - h));
	albedo = mix(albedo, ICE * (0.85 + 0.25 * pores), frost);

	vec3 L = normalize(vec3(light_dir, 0.25));
	float diff = max(dot(n, L), 0.0);
	// В космосе рассеянного света почти нет: ночную сторону подсвечивает
	// только пылевой диск, поэтому она тёмная, а освещённая — сочная.
	vec3 col = albedo * star_light * (0.11 + 1.6 * diff);
	// Металл — мелкие крупинки, вспыхивают искрами, когда грань ловит свет.
	vec3 hv = normalize(L + vec3(0.0, 0.0, 1.0));
	float nh = max(dot(n, hv), 0.0);
	float speck = smoothstep(0.86 - 0.12 * mix_w.y, 0.95, noise(pt * 26.0 + 3.0)) * (0.15 + 1.6 * mix_w.y);
	col += star_light * speck * (0.25 * diff + 1.6 * pow(nh, 12.0)) * (1.0 - frost);
	// Реголит матовый: общего блика нет, блестит только изморозь.
	col += star_light * frost * pow(nh, 10.0) * 0.25;
	// Хондры — стекловатые капли: ловят свет искоркой.
	col += star_light * chond * pow(nh, 30.0) * 0.15;
	// Пушистый край ледяной гальки подсвечен звездой насквозь.
	col += vec3(0.6, 0.78, 1.0) * star_light * fluff * smoothstep(edge - 0.2, edge, fr) * (0.25 + 0.6 * diff);

	col *= COLOR.rgb;
	float luma = dot(albedo, vec3(0.3, 0.5, 0.2));
	vec3 glow = emission.rgb * emission.a * (0.55 + 0.45 * luma + 0.5 * diff);
	COLOR = vec4(col * (1.0 - 0.6 * emission.a) + glow * 1.6, alpha * COLOR.a);
}
