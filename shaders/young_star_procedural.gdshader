shader_type canvas_item;
// Стилизованная версия звезды (сохранена как запасной вариант).
// Ячеистая грануляция, яркие очаги со вспышками, лучи и протуберанцы.


uniform float extent = 4.0;            // во сколько раз квад больше радиуса звезды
uniform float rotation_speed = 0.02;
uniform float granule_scale = 70.0;    // мелкие ячейки конвекции
uniform float activity = 0.8;          // доля поверхности под яркими очагами
uniform float darkness = 0.55;         // насколько тёмные пятнистые области
uniform float prominence_amount = 0.8;
uniform float ray_amount = 0.6;

uniform vec3 color_dark : source_color = vec3(0.30, 0.06, 0.01);
uniform vec3 color_mid : source_color = vec3(0.88, 0.32, 0.04);
uniform vec3 color_bright : source_color = vec3(1.0, 0.68, 0.22);
uniform vec3 color_white : source_color = vec3(1.0, 0.96, 0.78);

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

// Ячеистый шум: x = расстояние до ближайшей точки, y = до второй,
// zw = смещение до ближайшей точки (для лучей вспышек).
vec4 worley(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	vec3 nearest = vec3(0.0);
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
	return vec4(sqrt(d1), sqrt(d2), nearest.xy);
}

vec3 rotate_y(vec3 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec3(c * p.x + s * p.z, p.y, -s * p.x + c * p.z);
}

// Тёмный → оранжевый → жёлтый → белый.
vec3 ramp(float t) {
	t = clamp(t, 0.0, 1.0);
	if (t < 0.4) return mix(color_dark, color_mid, t / 0.4);
	if (t < 0.75) return mix(color_mid, color_bright, (t - 0.4) / 0.35);
	return mix(color_bright, color_white, (t - 0.75) / 0.25);
}

vec3 surface(vec2 p, float r) {
	float z = sqrt(max(1.0 - r * r, 0.0));
	vec3 sp = rotate_y(vec3(p, z), TIME * rotation_speed);

	// Грануляция: светлые ячейки и тёмные прожилки между ними.
	vec4 cells = worley(sp * granule_scale + vec3(0.0, 0.0, TIME * 0.2));
	float lanes = smoothstep(0.0, 0.35, cells.y - cells.x);
	float granule = mix(0.75, 1.0, lanes) * (0.8 + 0.2 * (1.0 - cells.x));
	// Средний масштаб: неровная «пена», чтобы ячейки не выглядели мозаикой.
	granule *= 0.75 + 0.5 * fbm(sp * 14.0 + vec3(TIME * 0.03));

	// Крупные тёмные пятнистые области.
	float mottling = fbm(sp * 3.5 + vec3(3.0, 1.0, TIME * 0.01));
	float dark = smoothstep(0.42, 0.62, mottling) * darkness;

	// Активные очаги: яркие рваные пятна с мелкой структурой внутри.
	float act = fbm(sp * 4.5 + vec3(11.0, 5.0, TIME * 0.02));
	float active = smoothstep(1.0 - activity * 0.62, 1.0 - activity * 0.4, act);
	float active_detail = fbm(sp * 20.0 + vec3(0.0, TIME * 0.05, 0.0));
	active *= smoothstep(0.3, 0.6, active_detail);

	// Точечные вспышки с лучами.
	vec4 flares = worley(sp * 5.0 + vec3(2.0, 7.0, 4.0));
	// Включены вспышки только в части областей; гладкий шум, чтобы не было швов.
	float flare_field = noise(sp * 3.0 + vec3(8.0, 2.0, TIME * 0.05));
	float flare_on = smoothstep(0.55, 0.7, flare_field) * (0.7 + 0.3 * sin(TIME * 1.5 + flare_field * 20.0));
	float fa = atan(flares.w, flares.z);
	float rays = pow(abs(cos(fa * 4.0)), 8.0);
	float flare = flare_on * (exp(-flares.x * 7.0) * 1.1 + rays * exp(-flares.x * 4.0) * 0.6);

	float heat = 0.5 * granule - dark * 0.3 + active * 0.6 + flare * 0.9;

	// Яркий светящийся край, как на референсе.
	float rim = pow(1.0 - z, 2.0);
	heat += rim * 0.7;
	vec3 col = ramp(heat);
	// Лёгкое затемнение по самому краю диска, чтобы шар читался объёмным.
	col *= mix(0.75, 1.0, smoothstep(0.0, 0.25, z));
	return col;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0 * extent;
	float r = length(p);
	float edge = max(r - 1.0, 0.0);
	float a = atan(p.y, p.x);
	vec2 dir = vec2(cos(a), sin(a));

	// Корона: мягкое свечение вокруг.
	float glow = exp(-edge * 3.0) * 0.85 + exp(-edge * 0.9) * 0.25;

	// Лучи: тонкие радиальные полосы разной длины.
	float ray_noise = noise(vec3(dir * 24.0, TIME * 0.08));
	float ray_len = noise(vec3(dir * 6.0, 4.0 + TIME * 0.05));
	float ray = pow(ray_noise, 3.0) * exp(-edge * (1.2 + 2.5 * (1.0 - ray_len))) * ray_amount;

	// Протуберанцы: закрученные нити через искажение координат.
	vec3 q = vec3(dir * 3.0, edge * 2.5 - TIME * 0.06);
	vec3 warp = vec3(fbm(q + vec3(0.0, 0.0, TIME * 0.05)), fbm(q + vec3(5.2, 1.3, 0.0)), 0.0);
	float strands = fbm(vec3(dir * 5.0, edge * 6.0) + warp * 3.5);
	float filament = pow(1.0 - abs(sin(strands * 7.0)), 5.0);
	float region = smoothstep(0.3, 0.6, noise(vec3(dir * 2.5, 9.0 + TIME * 0.02)));
	float prom = filament * region * exp(-edge * 8.0) * smoothstep(0.0, 0.03, edge) * prominence_amount;

	float corona = (glow + ray + prom) * smoothstep(extent, extent * 0.55, r);
	vec3 corona_col = mix(color_mid, color_bright, clamp(prom + exp(-edge * 6.0) * 0.6, 0.0, 1.0));
	vec4 outside = vec4(corona_col * (1.0 + prom * 0.6), clamp(corona, 0.0, 1.0));

	if (r < 1.0) {
		vec3 inside = surface(p, r);
		// Мягкий переход диска в корону.
		float k = smoothstep(1.0, 0.99, r);
		COLOR = vec4(mix(outside.rgb, inside, k), max(k, outside.a));
	} else {
		COLOR = outside;
	}
}
