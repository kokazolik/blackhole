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

const float BODY = 0.36;  // радиус тела в долях квадрата

// Цвета ярче настоящих (это игра), но оттенки взяты из жизни: камень тёплый,
// металл серебристый, углистое вещество бурое, лёд голубовато-белый.
const vec3 SILICATE = vec3(0.76, 0.64, 0.47);
const vec3 METAL = vec3(0.62, 0.64, 0.7);
const vec3 CARBON = vec3(0.3, 0.22, 0.2);
const vec3 ICE = vec3(0.8, 0.9, 1.0);
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
	float r = length(p);
	float aa = fwidth(r) * 1.2;
	// Ледяная галька — рыхлый комок, как снежок: край пушистый и полупрозрачный.
	float fluff = smoothstep(0.3, 0.8, mix_w.w);
	float fr = r + fluff * 0.12 * (noise(p * 13.0 + seed * 5.0) - 0.5);
	float soft = aa + fluff * 0.09;
	float alpha = 1.0 - smoothstep(edge - soft, edge + soft * 0.6, fr);
	if (alpha <= 0.0) {
		discard;
	}

	// Нормаль: сплюснутый шар по силуэту плюс рельеф от шума.
	vec2 q = p / edge;
	vec3 n = vec3(q, sqrt(max(1.0 - dot(q, q), 0.0)) + 0.05);
	float h = height(p);
	float eps = 0.03;
	vec2 grad = vec2(height(p + vec2(eps, 0.0)) - h, height(p + vec2(0.0, eps)) - h) / eps;
	n = normalize(n - vec3(grad * 0.09, 0.0));

	// Основа (матрица) — спёкшаяся пыль цвета всего состава.
	vec3 base = SILICATE * mix_w.x + METAL * mix_w.y + CARBON * mix_w.z + ICE * mix_w.w;
	base *= 1.0 - 0.25 * mix_w.z;  // сажа темнит чуть сильнее своей доли
	float pores = noise(p * 19.0);
	base *= (0.8 + 0.35 * h) * (0.9 + 0.2 * pores);

	// Хондры: круглые застывшие капли силиката, светлее матрицы. Их больше,
	// чем больше в составе камня. С ростом тела видно больше и они мельче.
	float cells = 3.6 + 3.0 * growth + 8.0 * boulder;
	vec2 cp = p * cells + vec2(seed * 13.0);
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
	vec3 chondrule = mix(CHONDRULE, base * 1.3, 0.25) * (0.9 + 0.2 * noise(p * 30.0));
	vec3 albedo = mix(base, chondrule, chond * (1.0 - 0.6 * boulder));

	// Валун: глыба из слипшихся кусков, между ними тёмные трещины-швы.
	if (boulder > 0.0) {
		// Координаты чуть искривлены шумом: швы неровные, как у настоящих трещин.
		vec2 bp = p * 2.0 + vec2(seed * 7.0) + (vec2(noise(p * 3.1), noise(p * 3.1 + 5.2)) - 0.5) * 0.9;
		vec2 bi = floor(bp);
		vec2 bf = fract(bp);
		float f1 = 8.0;
		float f2 = 8.0;
		float shade = 0.0;
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec2 g = vec2(float(x), float(y));
				vec2 o = vec2(hash(bi + g + 3.3), hash(bi + g + 9.1));
				float d = length(g + o - bf);
				if (d < f1) {
					f2 = f1;
					f1 = d;
					shade = hash(bi + g + 21.7);
				} else if (d < f2) {
					f2 = d;
				}
			}
		}
		float seam = (1.0 - smoothstep(0.01, 0.06, f2 - f1)) * smoothstep(0.35, 0.65, noise(p * 4.0 + 11.0));
		albedo *= 1.0 - boulder * (0.4 * seam - 0.14 * (shade - 0.5));
		n = normalize(n + vec3((bf - 0.5) * 0.12 * boulder, 0.0));
	}
	n = normalize(n + vec3(dome * 0.35 * chond, 0.0));

	// Лёд: светлая пушистая изморозь поверх всего, гуще в ямках рельефа.
	float frost = smoothstep(0.4, 0.95, mix_w.w + 0.35 * (fbm(p * 7.0) - 0.5) + 0.2 * (0.5 - h));
	albedo = mix(albedo, ICE * (0.85 + 0.25 * pores), frost);

	vec3 L = normalize(vec3(light_dir, 0.25));
	float diff = max(dot(n, L), 0.0);
	vec3 col = albedo * star_light * (0.22 + 1.45 * diff);
	// Металл — мелкие крупинки, вспыхивают искрами, когда грань ловит свет.
	vec3 hv = normalize(L + vec3(0.0, 0.0, 1.0));
	float nh = max(dot(n, hv), 0.0);
	float speck = smoothstep(0.86 - 0.12 * mix_w.y, 0.95, noise(p * 26.0 + 3.0)) * (0.15 + 1.6 * mix_w.y);
	col += star_light * speck * (0.25 * diff + 1.6 * pow(nh, 12.0)) * (1.0 - frost);
	// Мягкий блик по всему телу и блеск изморози.
	col += star_light * pow(nh, 20.0) * 0.12;
	col += star_light * frost * pow(nh, 10.0) * 0.25;
	// Хондры — стекловатые капли: ловят свет искоркой.
	col += star_light * chond * pow(nh, 30.0) * 0.4;
	// Пушистый край ледяной гальки подсвечен звездой насквозь.
	col += vec3(0.6, 0.78, 1.0) * star_light * fluff * smoothstep(edge - 0.2, edge, fr) * (0.25 + 0.6 * diff);

	col *= COLOR.rgb;
	float luma = dot(albedo, vec3(0.3, 0.5, 0.2));
	vec3 glow = emission.rgb * emission.a * (0.55 + 0.45 * luma + 0.5 * diff);
	COLOR = vec4(col * (1.0 - 0.6 * emission.a) + glow * 1.6, alpha * COLOR.a);
}
