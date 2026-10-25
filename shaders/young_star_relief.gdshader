shader_type canvas_item;
// Молодая активная звезда с рельефной поверхностью.
// Гранулы — выпуклые купола, межгранульные прожилки и пятна — впадины.
// Рельеф освещается через нормали, поэтому поверхность выглядит объёмной.
// Запасной стилизованный вариант: young_star_stylized.gdshader.

uniform float extent = 4.0;            // во сколько раз квад больше радиуса звезды
uniform float rotation_speed = 0.02;
uniform float granule_scale = 75.0;    // мелкие ячейки конвекции
uniform float relief = 0.45;           // сила рельефа
uniform float activity = 0.75;         // доля поверхности под яркими очагами
uniform float darkness = 0.6;          // насколько тёмные пятнистые области
uniform float prominence_amount = 0.85;
uniform float ray_amount = 0.45;
uniform vec3 light_dir = vec3(-0.45, -0.5, 0.74);  // откуда «подсвечен» рельеф

uniform vec3 color_dark : source_color = vec3(0.22, 0.04, 0.01);
uniform vec3 color_mid : source_color = vec3(0.82, 0.27, 0.03);
uniform vec3 color_bright : source_color = vec3(1.0, 0.62, 0.18);
uniform vec3 color_white : source_color = vec3(1.0, 0.95, 0.76);

vec3 hash3(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)),
			 dot(p, vec3(269.5, 183.3, 246.1)),
			 dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p) * 43758.5453123);
}

float hash(vec3 p) {
	return hash3(p).x;
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
				   mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
				   mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.02 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return v;
}

// Ячеистый шум: d1, d2 и вектор от точки к ближайшему центру ячейки.
void worley(vec3 p, out float d1, out float d2, out vec3 nearest) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	d1 = 8.0;
	d2 = 8.0;
	nearest = vec3(0.0);
	for (int x = -1; x <= 1; x++)
	for (int y = -1; y <= 1; y++)
	for (int z = -1; z <= 1; z++) {
		vec3 g = vec3(float(x), float(y), float(z));
		vec3 o = g + hash3(i + g) - f;
		float d = dot(o, o);
		if (d < d1) {
			d2 = d1;
			d1 = d;
			nearest = o;
		} else if (d < d2) {
			d2 = d;
		}
	}
	d1 = sqrt(d1);
	d2 = sqrt(d2);
}

vec3 rotate_y(vec3 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec3(c * p.x + s * p.z, p.y, -s * p.x + c * p.z);
}

vec3 ramp(float t) {
	t = clamp(t, 0.0, 1.0);
	if (t < 0.4) return mix(color_dark, color_mid, t / 0.4);
	if (t < 0.75) return mix(color_mid, color_bright, (t - 0.4) / 0.35);
	return mix(color_bright, color_white, (t - 0.75) / 0.25);
}

// Крупный рельеф: пятнистые впадины и приподнятые активные области.
float large_height(vec3 sp) {
	float mottling = fbm(sp * 3.5 + vec3(3.0, 1.0, 0.0));
	float act = fbm(sp * 4.5 + vec3(11.0, 5.0, 0.0));
	return -smoothstep(0.42, 0.62, mottling) * darkness + smoothstep(0.45, 0.7, act) * 0.4;
}

vec3 surface(vec2 p, float r) {
	float z = sqrt(max(1.0 - r * r, 0.0));
	vec3 n0 = vec3(p, z);
	float angle = TIME * rotation_speed;
	vec3 sp = rotate_y(n0, angle);

	// Гранулы: купол по расстоянию до центра ячейки, прожилки по d2 - d1.
	float d1;
	float d2;
	vec3 nearest;
	vec3 gp = sp * granule_scale + vec3(0.0, 0.0, TIME * 0.2);
	worley(gp, d1, d2, nearest);
	float lane = 1.0 - smoothstep(0.0, 0.18, d2 - d1);
	float dome = 1.0 - d1 * d1;
	// Градиент купола направлен к центру гранулы, у прожилок он круче.
	vec3 grad = normalize(nearest + 1e-4) * (0.6 + 1.4 * lane);

	// Градиент крупного рельефа по конечным разностям.
	float e = 0.01;
	float h0 = large_height(sp);
	vec3 g_large = vec3(
		large_height(sp + vec3(e, 0.0, 0.0)) - h0,
		large_height(sp + vec3(0.0, e, 0.0)) - h0,
		large_height(sp + vec3(0.0, 0.0, e)) - h0) / e;

	vec3 g = rotate_y(grad * 0.35 + g_large * 0.05, -angle);
	vec3 g_tan = g - dot(g, n0) * n0;
	vec3 n = normalize(n0 - g_tan * relief);

	float lambert = clamp(dot(n, normalize(light_dir)), 0.0, 1.0);
	float shade = mix(0.68, 1.22, lambert);

	// Яркость поверхности: купола светлее, прожилки и пятна темнее, очаги ярче.
	float act_detail = fbm(sp * 20.0 + vec3(0.0, TIME * 0.05, 0.0));
	float act = fbm(sp * 4.5 + vec3(11.0, 5.0, TIME * 0.02));
	float active = smoothstep(1.0 - activity * 0.62, 1.0 - activity * 0.4, act) * smoothstep(0.3, 0.6, act_detail);
	float dark = smoothstep(0.42, 0.62, fbm(sp * 3.5 + vec3(3.0, 1.0, 0.0))) * darkness;
	float heat = 0.42 + 0.18 * dome - 0.16 * lane - dark * 0.3 + active * 0.55;

	vec3 col = ramp(heat) * shade;
	// Блики на вершинах гранул, сильнее в активных областях.
	vec3 h = normalize(normalize(light_dir) + vec3(0.0, 0.0, 1.0));
	col += color_white * pow(max(dot(n, h), 0.0), 24.0) * (0.15 + 0.5 * active);

	// Потемнение к краю, но с горячим ободком атмосферы.
	col *= 0.65 + 0.35 * pow(z, 0.5);
	col += color_bright * pow(1.0 - z, 3.0) * 1.0;
	return col;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0 * extent;
	float r = length(p);
	float edge = max(r - 1.0, 0.0);
	float a = atan(p.y, p.x);
	vec2 dir = vec2(cos(a), sin(a));

	// Корона: мягкое свечение.
	float glow = exp(-edge * 3.5) * 0.8 + exp(-edge * 1.0) * 0.22;

	// Лучи: тонкие радиальные полосы разной длины.
	float ray_noise = noise(vec3(dir * 24.0, TIME * 0.08));
	float ray_len = noise(vec3(dir * 6.0, 4.0 + TIME * 0.05));
	float ray = pow(ray_noise, 3.0) * exp(-edge * (1.4 + 2.5 * (1.0 - ray_len))) * ray_amount;

	// Протуберанцы: плотные закрученные плазменные нити у края.
	vec3 q = vec3(dir * 3.0, edge * 2.5 - TIME * 0.06);
	vec3 warp = vec3(fbm(q + vec3(0.0, 0.0, TIME * 0.05)), fbm(q + vec3(5.2, 1.3, 0.0)), 0.0);
	float strands = fbm(vec3(dir * 5.0, edge * 6.0) + warp * 3.5);
	float filament = pow(1.0 - abs(sin(strands * 7.0)), 4.0);
	float region = smoothstep(0.3, 0.6, noise(vec3(dir * 2.5, 9.0 + TIME * 0.02)));
	float prom = filament * region * exp(-edge * 7.0) * smoothstep(0.0, 0.03, edge) * prominence_amount;

	float corona = (glow + ray + prom) * smoothstep(extent, extent * 0.55, r);
	vec3 corona_col = mix(color_mid, color_bright, clamp(prom + exp(-edge * 6.0) * 0.6, 0.0, 1.0));
	vec4 outside = vec4(corona_col * (1.0 + prom * 0.5), clamp(corona, 0.0, 1.0));

	if (r < 1.0) {
		vec3 inside = surface(p, r);
		float k = smoothstep(1.0, 0.99, r);
		COLOR = vec4(mix(outside.rgb, inside, k), max(k, outside.a));
	} else {
		COLOR = outside;
	}
}
