shader_type canvas_item;
// Галька игрока целиком процедурная: неровный силуэт, рельеф и обломки-вкрапления.
// Тело — это слипшиеся крупинки разных веществ, поэтому доля обломков каждого цвета
// равна доле вещества в составе (mix). Состав меняется плавно: player.gd сглаживает mix,
// а обломок перекрашивается мягким переходом, а не скачком.
// Рисуется один раз за кадр на одном теле, так что расчёт шума телефону не в тягость.

uniform vec2 light_dir = vec2(-1.0, 0.0);
uniform vec3 star_light : source_color = vec3(1.0, 0.9, 0.75);
uniform vec4 emission = vec4(0.0);   // тепловое свечение (rgb, сила в a)
uniform vec4 mix_w = vec4(0.25);     // доли: силикаты, металл, углерод, лёд
uniform float growth = 0.0;          // 0 — свежая галька, 1 — почти валун
uniform float seed = 0.37;

const float BODY = 0.36;  // радиус тела в долях квадрата

const vec3 SILICATE = vec3(0.74, 0.63, 0.47);
const vec3 METAL = vec3(0.58, 0.6, 0.64);
const vec3 CARBON = vec3(0.12, 0.1, 0.09);
const vec3 ICE = vec3(0.78, 0.88, 0.98);
const vec3 MATRIX = vec3(0.34, 0.3, 0.27);  // тёмная пыль, склеившая обломки

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

// Ячейки-обломки: x — расстояние до центра обломка, y — его случайное число.
vec2 clasts(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash(i + g), hash(i + g + 17.3));
			float d = length(g + o - f);
			if (d < d1) {
				d1 = d;
				id = hash(i + g + 41.7);
			}
		}
	}
	return vec2(d1, id);
}

// Вещество обломка по его случайному числу: отрезки длиной в долю состава.
// На стыках отрезков — плавный переход, чтобы при смене состава цвет перетекал.
vec4 clast_material(float r) {
	float e = 0.04;
	float a = mix_w.x;
	float b = a + mix_w.y;
	float c = b + mix_w.z;
	float s = 1.0 - smoothstep(a - e, a + e, r);
	float m = smoothstep(a - e, a + e, r) - smoothstep(b - e, b + e, r);
	float k = smoothstep(b - e, b + e, r) - smoothstep(c - e, c + e, r);
	float i = smoothstep(c - e, c + e, r);
	return vec4(s, m, k, i);
}

float height(vec2 p) {
	return fbm(p * 2.2);
}

void fragment() {
	vec2 p = (UV - 0.5) / BODY;
	// Неровный силуэт: несколько гармоник по углу. С ростом тело комковатее.
	float th = atan(p.y, p.x);
	float amp = 0.07 + 0.05 * growth;
	float edge = 1.0 + amp * (0.55 * sin(2.0 * th + seed * 6.0) + 0.3 * sin(3.0 * th + seed * 11.0)
			+ 0.15 * sin(5.0 * th + seed * 17.0)) + 0.05 * (noise(vec2(th * 2.5, seed * 10.0)) - 0.5);
	float r = length(p);
	float aa = fwidth(r) * 1.2;
	float alpha = 1.0 - smoothstep(edge - aa, edge + aa, r);
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

	// Основа — спёкшаяся смесь всех веществ в пропорции состава. В ней сидят
	// обломки-вкрапления: каждый целиком из одного вещества. С ростом их больше и они мельче.
	vec3 base = SILICATE * mix_w.x + METAL * mix_w.y + CARBON * mix_w.z + ICE * mix_w.w;
	// Сажа красит сильнее своей доли: даже немного углерода заметно темнит камень.
	base *= 1.0 - 0.5 * mix_w.z;
	base = mix(base, MATRIX, 0.2) * (0.75 + 0.5 * h);
	float cells = 2.6 + 2.4 * growth;
	vec2 wob = vec2(noise(p * 4.0), noise(p * 4.0 + 7.0)) - 0.5;
	vec2 cl = clasts(p * cells + wob * 0.9 + vec2(seed * 13.0));
	float blob = 1.0 - smoothstep(0.3, 0.38, cl.x);
	vec4 w = clast_material(cl.y);
	vec3 albedo = SILICATE * w.x + METAL * w.y + CARBON * w.z + ICE * w.w;
	// Внутри обломка своя фактура: зернистость камня, трещины угля.
	float grain = noise(p * 11.0);
	albedo *= 0.85 + 0.25 * grain * (w.x + 0.5 * w.y);
	float crack = 1.0 - smoothstep(0.0, 0.05, abs(noise(p * 5.0 + 3.0) - 0.5));
	albedo = mix(albedo, albedo * 0.45, crack * w.z * 0.8);
	albedo *= 0.85 + 0.3 * h;
	// Тонкая тёмная кайма по краю обломка.
	float rim_dark = smoothstep(0.24, 0.32, cl.x) * blob;
	albedo = mix(base, albedo * (1.0 - 0.35 * rim_dark), blob);
	// Блеск и лёд считаем по смеси: в основе вещества тоже блестят, но слабее.
	w = mix(mix_w * 0.6, w, blob);

	vec3 L = normalize(vec3(light_dir, 0.25));
	float diff = max(dot(n, L), 0.0);
	vec3 col = albedo * star_light * (0.2 + 1.45 * diff);
	// Блеск: металл зеркалит резко, лёд мягко, камень и уголь почти матовые.
	vec3 hv = normalize(L + vec3(0.0, 0.0, 1.0));
	float nh = max(dot(n, hv), 0.0);
	float spec = w.y * pow(nh, 50.0) * 1.3 + w.w * pow(nh, 16.0) * 0.6 + (w.x + w.z) * pow(nh, 20.0) * 0.12;
	// Металлические блёстки вспыхивают, когда грань ловит свет.
	float fleck = smoothstep(0.88, 0.97, noise(p * 14.0)) * w.y * diff;
	col += star_light * (spec + fleck * 0.8) ;
	// Лёд просвечивает голубой каймой на освещённом краю.
	col += vec3(0.45, 0.65, 1.0) * pow(1.0 - n.z, 2.0) * diff * w.w  * 0.6;

	col *= COLOR.rgb;
	float luma = dot(albedo, vec3(0.3, 0.5, 0.2));
	vec3 glow = emission.rgb * emission.a * (0.55 + 0.45 * luma + 0.5 * diff);
	COLOR = vec4(col * (1.0 - 0.6 * emission.a) + glow * 1.6, alpha * COLOR.a);
}
