shader_type canvas_item;
// Газовый гигант для окна выбора пути: полосы облаков, вихри на их границах,
// большое пятно-шторм, мягкий терминатор, голубоватая дымка по краю и кольцо.
// Квадрат: тело — BODY его ширины, кольцо выходит за край тела.

uniform vec2 light_dir = vec2(-0.8, -0.35);
uniform vec3 band_light : source_color = vec3(0.95, 0.86, 0.68);
uniform vec3 band_dark : source_color = vec3(0.66, 0.42, 0.26);
uniform vec3 storm_col : source_color = vec3(0.82, 0.38, 0.22);
uniform float spin_speed = 0.02;
uniform float tilt = 0.32;
uniform float aspect = 1.0;   // ширина рамки к высоте: тело круглое в любой рамке

const float BODY = 0.34;  // в долях высоты рамки

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
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
		p = p * 2.07 + vec3(3.1, 1.7, 8.3);
		a *= 0.5;
	}
	return s;
}

// Кольцо: эллипс вокруг тела, наклонённый на tilt. Возвращает цвет и прозрачность.
vec4 ring(vec2 p) {
	float c = cos(tilt);
	float s = sin(tilt);
	vec2 q = vec2(c * p.x + s * p.y, -s * p.x + c * p.y);
	q.y /= 0.24;
	float r = length(q);
	if (r < 1.32 || r > 1.95) {
		return vec4(0.0);
	}
	float k = (r - 1.32) / 0.63;
	float dens = 0.55 + 0.45 * sin(k * 38.0) * sin(k * 11.0 + 1.3);
	dens *= smoothstep(0.0, 0.08, k) * smoothstep(1.0, 0.9, k);
	dens *= 1.0 - 0.75 * smoothstep(0.55, 0.6, k) * smoothstep(0.66, 0.61, k);  // щель Кассини
	vec3 col = mix(vec3(0.86, 0.78, 0.64), vec3(0.62, 0.52, 0.42), k);
	return vec4(col, dens * 0.8);
}

void fragment() {
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0) / BODY;
	float d = length(p);
	vec4 out_col = vec4(0.0);
	vec4 rg = ring(p);
	// Задняя половина кольца — за телом.
	float c = cos(tilt);
	float s = sin(tilt);
	float behind = step(0.0, -(-s * p.x + c * p.y));
	if (d > 1.0 || behind > 0.5) {
		out_col = vec4(rg.rgb * 0.95, rg.a);
	}
	if (d <= 1.0) {
		float z = sqrt(1.0 - d * d);
		vec3 n = vec3(p, z);
		// Ось вращения наклонена так же, как кольцо.
		vec3 a = vec3(c * n.x + s * n.y, -s * n.x + c * n.y, n.z);
		float lat = a.y;
		float lon = atan(a.x, a.z) + TIME * spin_speed * 6.2832;
		vec3 sp = vec3(sin(lon) * sqrt(1.0 - lat * lat), lat, cos(lon) * sqrt(1.0 - lat * lat));
		float turb = fbm(sp * 4.0 + vec3(0.0, 0.0, TIME * 0.03));
		float band = sin(lat * 19.0 + turb * 2.6) * 0.5 + 0.5;
		float fine = sin(lat * 57.0 + turb * 5.0) * 0.5 + 0.5;
		vec3 col = mix(band_dark, band_light, smoothstep(0.25, 0.75, band));
		col *= 0.9 + 0.12 * fine;
		col = mix(col, band_light * 1.04, smoothstep(0.75, 0.95, 1.0 - abs(lat)) * 0.25);
		// Большое пятно: овальный шторм в южных широтах.
		vec2 sc = vec2(mod(lon - 1.1, 6.2832) - 3.1416, (lat + 0.36) * 2.6);
		float spot = 1.0 - smoothstep(0.18, 0.34, length(sc * vec2(1.0, 1.7)));
		float swirl = fbm(vec3(sc * 6.0, TIME * 0.05));
		col = mix(col, storm_col * (0.85 + 0.3 * swirl), spot * 0.85);
		// Свет звезды: мягкий терминатор и затемнение к краю.
		vec3 l = normalize(vec3(light_dir, 0.55));
		float lit = clamp(dot(n, l), 0.0, 1.0);
		float shade = 0.07 + 0.93 * smoothstep(-0.05, 0.6, lit);
		col *= shade * (0.72 + 0.28 * z);
		// Дымка атмосферы по краю.
		float rim = pow(1.0 - z, 3.0);
		col += vec3(0.55, 0.7, 1.0) * rim * 0.45 * smoothstep(-0.2, 0.5, dot(p / max(d, 1e-4), light_dir));
		out_col = vec4(col, 1.0);
		// Передняя половина кольца — поверх тела, тень тела на кольце не рисуем.
		if (behind < 0.5) {
			out_col.rgb = mix(out_col.rgb, rg.rgb, rg.a);
		}
	}
	// Ореол атмосферы за краем.
	float halo = smoothstep(1.12, 1.0, d) * step(1.0, d);
	out_col = mix(out_col, vec4(0.55, 0.72, 1.0, 1.0), halo * 0.35 * (1.0 - out_col.a));
	if (out_col.a < 0.001 && halo > 0.0) {
		out_col = vec4(0.55, 0.72, 1.0, halo * 0.35);
	}
	COLOR = out_col;
}
