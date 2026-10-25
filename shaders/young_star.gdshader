shader_type canvas_item;
// Молодая активная звезда: запечённая поверхность + живая анимация.
// Поверхность (грануляция, пятна, очаги, вспышки) берётся из карты star_surface.png,
// которую делает tools/bake_star.tscn из young_star_procedural.gdshader.
// Вращение, кипение, пульсация вспышек и лучи считаются на лету дешёвыми
// выборками из бесшовной текстуры шума, протуберанцы — шумом в узком кольце у края.
// Дальнее свечение короны рисуется отдельной дешёвой текстурой (star.gd), поэтому
// этот квад небольшой: диск, протуберанцы и начало лучей.

uniform float extent = 1.8;            // во сколько раз квад больше радиуса звезды
uniform float rotation_speed = 0.02;
uniform float prominence_amount = 0.8;
uniform float ray_amount = 0.6;
uniform float boil_amount = 0.08;      // сила «кипения» поверхности

uniform sampler2D surface_tex : filter_linear, repeat_enable;
uniform sampler2D noise_tex : filter_linear, repeat_enable;

uniform vec3 color_dark : source_color = vec3(0.30, 0.06, 0.01);
uniform vec3 color_mid : source_color = vec3(0.88, 0.32, 0.04);
uniform vec3 color_bright : source_color = vec3(1.0, 0.68, 0.22);
uniform vec3 color_white : source_color = vec3(1.0, 0.96, 0.78);

const float HEAT_MIN = -0.3;
const float HEAT_RANGE = 1.6;

// Процедурный шум нужен только для протуберанцев в узком кольце у края.
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

// Три октавы вместо пяти: в узком кольце разницы не видно, а телефону легче.
float fbm(vec3 p, int octaves) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < octaves; i++) {
		v += a * noise(p);
		p = p * 2.02 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return v;
}

float nz(vec2 uv) {
	return texture(noise_tex, uv).r;
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
	vec2 uv = vec2(atan(sp.x, sp.z) / TAU + 0.5, 0.5 - asin(clamp(sp.y, -1.0, 1.0)) / PI);
	vec4 s = texture(surface_tex, uv);

	float heat = s.r * HEAT_RANGE + HEAT_MIN;
	// Кипение: медленно плывущая рябь яркости поверх запечённых гранул.
	float boil = nz(uv * vec2(16.0, 8.0) + vec2(TIME * 0.01, TIME * 0.013)) - 0.5;
	boil += 0.5 * (nz(uv * vec2(32.0, 16.0) - vec2(TIME * 0.017, TIME * 0.009)) - 0.5);
	heat += boil * boil_amount * 2.0;
	// Пульсация вспышек.
	float pulse = 0.7 + 0.3 * sin(TIME * 1.5 + s.b * 20.0);
	heat += s.g * 2.0 * 0.9 * pulse;

	// Яркий светящийся край.
	float rim = pow(1.0 - z, 2.0);
	heat += rim * 0.7;
	vec3 col = ramp(heat);
	col *= mix(0.75, 1.0, smoothstep(0.0, 0.25, z));
	return col;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0 * extent;
	float r = length(p);
	float edge = max(r - 1.0, 0.0);
	float ang = atan(p.y, p.x) / TAU + 0.5;  // 0..1 по кругу, шум бесшовный

	// Корона: ближнее свечение (дальнее — отдельной текстурой).
	float glow = exp(-edge * 3.0) * 0.85;

	// Лучи: тонкие радиальные полосы разной длины.
	float ray_noise = nz(vec2(ang * 12.0, 0.13 + TIME * 0.004));
	float ray_len = nz(vec2(ang * 2.0, 0.57 + TIME * 0.003));
	float ray = pow(ray_noise, 2.5) * exp(-edge * (1.2 + 2.5 * (1.0 - ray_len))) * ray_amount;

	// Протуберанцы: закрученные нити через искажение координат.
	// Считаются только в узком кольце у края, поэтому процедурный шум здесь недорог.
	float prom = 0.0;
	if (edge > 0.0 && edge < 0.6) {
		vec2 dir = normalize(p);
		vec3 q = vec3(dir * 3.0, edge * 2.5 - TIME * 0.06);
		vec3 warp = vec3(fbm(q + vec3(0.0, 0.0, TIME * 0.05), 2), fbm(q + vec3(5.2, 1.3, 0.0), 2), 0.0);
		float strands = fbm(vec3(dir * 5.0, edge * 6.0) + warp * 3.5, 3);
		float filament = pow(1.0 - abs(sin(strands * 7.0)), 4.0);
		float region = smoothstep(0.3, 0.6, noise(vec3(dir * 2.5, 9.0 + TIME * 0.02)));
		prom = filament * region * exp(-edge * 8.0) * smoothstep(0.0, 0.03, edge) * prominence_amount;
	}

	float corona = (glow + ray + prom) * smoothstep(extent, extent * 0.7, r);
	vec3 corona_col = mix(color_mid, color_bright, clamp(prom + exp(-edge * 6.0) * 0.6, 0.0, 1.0));
	vec4 outside = vec4(corona_col * (1.0 + prom * 0.6), clamp(corona, 0.0, 1.0));

	if (r < 1.0) {
		vec3 inside = surface(p, r);
		float k = smoothstep(1.0, 0.99, r);
		COLOR = vec4(mix(outside.rgb, inside, k), max(k, outside.a));
	} else {
		COLOR = outside;
	}
}
