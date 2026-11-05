shader_type canvas_item;
// Кольцо гиганта из разорванных тел: тонкие кольца-дорожки с щелями,
// сгустки кружат по Кеплеру (ближние быстрее), гигант бросает на кольцо тень.
// Вид сверху, в плоскости орбит: кольцо — круг, как орбиты лун.

uniform vec3 col = vec3(0.8, 0.8, 0.82);
uniform float opacity = 0.0;      // 0..1 — сколько вещества в кольце
uniform float half_size = 300.0;  // половина стороны квада, ед.
uniform float planet_r = 100.0;
uniform float r_in = 1.12;        // в радиусах гиганта
uniform float r_out = 1.48;
uniform vec2 light_dir = vec2(-1.0, -0.12);  // откуда свет
uniform float time = 0.0;
uniform float seed = 0.0;
uniform float bands = 0.0;        // переходное тело: кольцо из двух веществ, полосами
uniform vec3 col2 = vec3(0.6, 0.55, 0.5);

float hash(float x) { return fract(sin(x * 127.1 + seed * 31.7) * 43758.5453); }
float vnoise(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash(i), hash(i + 1.0), f);
}
float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + seed) * 43758.5453); }
float vnoise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 p = (UV * 2.0 - 1.0) * half_size;
	float r = length(p) / planet_r;
	if (r < r_in - 0.02 || r > r_out + 0.02 || opacity <= 0.001) {
		COLOR = vec4(0.0);
	} else {
		float x = (r - r_in) / (r_out - r_in);
		// Края мягкие, внешний край резче (там кольцо держат луны).
		float edge = smoothstep(0.0, 0.12, x) * (1.0 - smoothstep(0.9, 1.0, x));
		// Дорожки и щели: шум по радиусу на трёх масштабах.
		float d = 0.45 + 0.35 * vnoise(x * 14.0) + 0.25 * vnoise(x * 47.0) + 0.15 * vnoise(x * 130.0);
		// Широкая щель, как щель Кассини.
		d *= 1.0 - 0.85 * exp(-pow((x - 0.62) / 0.035, 2.0));
		// Мало вещества — кольцо узкое и рваное: держится только середина.
		float fill = smoothstep(0.0, 0.5, opacity);
		d *= mix(exp(-pow((x - 0.45) / 0.18, 2.0)), 1.0, fill);
		// Сгустки кружат по Кеплеру: ближние обгоняют дальние.
		float a = atan(p.y, p.x);
		float a2 = a + time * 0.35 * pow(r, -1.5);
		float clump = 0.82 + 0.3 * vnoise2(vec2(a2 * 7.0, x * 9.0));
		// Тень гиганта на кольце (за ним, со стороны от звезды).
		vec2 away = -normalize(light_dir);
		vec2 pn = p / planet_r;
		float along = dot(pn, away);
		float across = abs(pn.x * away.y - pn.y * away.x);
		float shadow = (along > 0.0) ? smoothstep(0.92, 1.04, across) : 1.0;
		float lit = mix(0.08, 1.0, shadow);
		vec3 c = col;
		if (bands > 0.0) {
			c = mix(col, col2, smoothstep(0.35, 0.65, vnoise(x * 9.0 + 3.0)) * bands);
		}
		c *= (0.75 + 0.35 * vnoise(x * 60.0 + 7.0)) * lit;
		// Кольцо полупрозрачное даже густым: сквозь него видны звёзды и диск.
		float al = clamp(opacity * 0.75, 0.0, 0.62) * d * edge * clump;
		COLOR = vec4(c, clamp(al, 0.0, 0.9));
	}
}
