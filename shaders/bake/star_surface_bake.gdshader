shader_type canvas_item;
// Запекание поверхности звезды в равнопромежуточную карту (долгота × широта).
// Каналы: R — яркость поверхности (heat), G — маска вспышек, B — фаза их пульсации.
// Формулы совпадают с young_star_procedural.gdshader при TIME = bake_time.


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

uniform float bake_time = 0.0;

const float HEAT_MIN = -0.3;
const float HEAT_RANGE = 1.6;

void fragment() {
	float lon = (UV.x - 0.5) * TAU;
	float lat = (0.5 - UV.y) * PI;
	vec3 sp = vec3(cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon));
	float t = bake_time;

	vec4 cells = worley(sp * granule_scale + vec3(0.0, 0.0, t * 0.2));
	float lanes = smoothstep(0.0, 0.35, cells.y - cells.x);
	float granule = mix(0.75, 1.0, lanes) * (0.8 + 0.2 * (1.0 - cells.x));
	granule *= 0.75 + 0.5 * fbm(sp * 14.0 + vec3(t * 0.03));

	float mottling = fbm(sp * 3.5 + vec3(3.0, 1.0, t * 0.01));
	float dark = smoothstep(0.42, 0.62, mottling) * darkness;

	float act = fbm(sp * 4.5 + vec3(11.0, 5.0, t * 0.02));
	float active = smoothstep(1.0 - activity * 0.62, 1.0 - activity * 0.4, act);
	float active_detail = fbm(sp * 20.0 + vec3(0.0, t * 0.05, 0.0));
	active *= smoothstep(0.3, 0.6, active_detail);

	vec4 flares = worley(sp * 5.0 + vec3(2.0, 7.0, 4.0));
	float flare_field = noise(sp * 3.0 + vec3(8.0, 2.0, t * 0.05));
	float fa = atan(flares.w, flares.z);
	float rays = pow(abs(cos(fa * 4.0)), 8.0);
	float flare = smoothstep(0.55, 0.7, flare_field) * (exp(-flares.x * 7.0) * 1.1 + rays * exp(-flares.x * 4.0) * 0.6);

	float heat = 0.5 * granule - dark * 0.3 + active * 0.6;
	COLOR = vec4(clamp((heat - HEAT_MIN) / HEAT_RANGE, 0.0, 1.0), clamp(flare * 0.5, 0.0, 1.0), flare_field, 1.0);
}
