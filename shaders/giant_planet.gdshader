shader_type canvas_item;
// Газовый гигант вблизи: облачные пояса и зоны неровной ширины, сдвиговые
// течения на их границах с завитками, овальные вихри и большое пятно,
// хаотичные полярные области. Свет как у зародыша: звезда сбоку, мягкий
// терминатор, дымка по краю. Ночью у полюсов слабо светятся сияния, а у
// горячего юпитера тлеет раскалённая ночная сторона.
// Квадрат: тело — BODY его ширины, дымка выходит за край.

uniform vec2 light_dir = vec2(-1.0, -0.1);
uniform vec3 star_light : source_color = vec3(1.0, 0.92, 0.8);
uniform vec3 zone_col : source_color = vec3(0.92, 0.86, 0.74);   // светлые зоны
uniform vec3 belt_col : source_color = vec3(0.62, 0.44, 0.32);   // тёмные пояса
uniform vec3 storm_col : source_color = vec3(0.78, 0.42, 0.28);  // большое пятно
uniform vec3 haze_col : source_color = vec3(0.62, 0.74, 0.95);
uniform float spin = 0.0;
uniform float tilt = 0.12;
uniform float seed = 0.31;
uniform float aurora = 0.0;  // магнитное поле: сияния у полюсов на ночной стороне
uniform float heat = 0.0;    // жар горячего юпитера: светится ночная сторона
uniform float churn = 0.0;   // падающий газ будоражит облака

const float BODY = 0.36;
const float R_MAX = 1.25;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7)) + seed * 91.3) * 43758.5453);
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
		p = p * 2.07 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return s;
}

// Профиль поясов по широте: несколько гармоник с неровными частотами.
float bands(float lat) {
	float b = 0.0;
	b += 0.42 * sin(lat * 9.3 + seed * 3.0);
	b += 0.28 * sin(lat * 17.1 + 1.3 + seed * 5.0);
	b += 0.18 * sin(lat * 29.7 + 2.1);
	b += 0.12 * sin(lat * 47.0 + 0.4 + seed * 2.0);
	b += 0.07 * sin(lat * 83.0 + 1.7);
	return b;
}

mat3 body_to_view() {
	float ct = cos(tilt);
	float st = sin(tilt);
	return mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, ct, st), vec3(0.0, -st, ct));
}

vec3 clouds(vec3 d, out float spot_k) {
	float lat = d.y;
	float lon = atan(d.x, d.z) + spin;
	vec3 sp = vec3(sin(lon) * sqrt(1.0 - lat * lat), lat, cos(lon) * sqrt(1.0 - lat * lat));
	// Течения: облака растянуты вдоль широт, границы поясов закручены завитками.
	vec3 q = vec3(sp.x * 2.2, sp.y * 7.0, sp.z * 2.2);
	vec3 w = vec3(fbm(q * 1.3 + 3.0), fbm(q * 1.3 + 11.0), fbm(q * 1.3 + 23.0)) - 0.5;
	float edge = abs(cos(lat * 9.3 + seed * 3.0));
	float turb = fbm(q * 2.0 + w * (1.6 + 1.2 * churn));
	float lat_w = lat + (turb - 0.5) * (0.035 + 0.05 * edge) + w.x * 0.03;
	float b = bands(lat_w);
	float streak = fbm(vec3(sp.x * 6.0, sp.y * 60.0, sp.z * 6.0) + w * 3.0);
	vec3 col = mix(belt_col, zone_col, smoothstep(-0.35, 0.35, b + (streak - 0.5) * 0.5));
	// Тонкие тёмные и светлые нити в поясах.
	col *= 0.86 + 0.28 * streak;
	col = mix(col, col * vec3(1.04, 0.96, 0.9), smoothstep(0.55, 0.8, turb) * 0.5);
	// Мелкие белые овалы в южных поясах.
	float ov = fbm(vec3(sp.x * 9.0, sp.y * 22.0, sp.z * 9.0) + 40.0);
	col = mix(col, zone_col * 1.08, smoothstep(0.72, 0.8, ov) * smoothstep(0.1, 0.5, abs(lat)) * 0.7);
	// Большое пятно: вихрь в южных широтах, закрученный внутри.
	vec2 sc = vec2(mod(lon - 1.1, 6.2832) - 3.1416, (lat + 0.34) * 3.2);
	float sr = length(sc * vec2(1.0, 1.9));
	float ang = atan(sc.y * 1.9, sc.x) + 3.0 / (sr + 0.25);
	float swirl = fbm(vec3(cos(ang) * sr * 6.0, sin(ang) * sr * 6.0, 3.0));
	spot_k = (1.0 - smoothstep(0.16, 0.3, sr));
	vec3 spot = mix(storm_col * 0.85, mix(storm_col, zone_col, 0.35) * 1.05, swirl);
	col = mix(col, spot, spot_k * 0.9);
	col = mix(col, zone_col * 1.05, smoothstep(0.3, 0.34, sr) * (1.0 - smoothstep(0.34, 0.42, sr)) * 0.45);
	// Полярные области: пояса тают в серо-голубую рябь.
	float polar = smoothstep(0.62, 0.85, abs(lat));
	vec3 pole = mix(belt_col, haze_col * 0.6, 0.45) * (0.75 + 0.4 * fbm(sp * 9.0));
	col = mix(col, pole, polar);
	return col;
}

void fragment() {
	vec2 p = (UV - 0.5) / BODY;
	float r = length(p);
	if (r > R_MAX) discard;
	mat3 mi = transpose(body_to_view());
	vec3 L = normalize(vec3(light_dir, 0.6));
	float aa = fwidth(r) * 1.5;
	vec3 col = vec3(0.0);
	float alpha = 0.0;
	if (r < 1.0 + aa) {
		vec3 nv = vec3(p, sqrt(max(1.0 - r * r, 0.0)));
		vec3 d = mi * nv;
		float spot_k;
		vec3 alb = clouds(d, spot_k);
		float ndl = dot(nv, L);
		// Мягкий терминатор: облачный слой рассеивает свет за черту.
		float diff = smoothstep(-0.22, 0.9, ndl);
		float limb = pow(max(nv.z, 0.0), 0.35);  // к краю облака темнеют
		col = alb * star_light * (0.012 + 1.2 * pow(diff, 1.6)) * (0.55 + 0.45 * limb);
		// Дымка: по краю голубоватая, со стороны звезды светится.
		float rim = pow(1.0 - nv.z, 3.0);
		float wrap = clamp(ndl * 0.5 + 0.5, 0.0, 1.0);
		col = mix(col, haze_col * star_light * (0.08 + 0.9 * wrap * wrap), clamp(rim * 0.75, 0.0, 1.0) * (0.3 + 0.7 * wrap));
		// Ночь: горячий юпитер тлеет, у полюсов дрожат сияния.
		float night = 1.0 - smoothstep(-0.2, 0.15, ndl);
		col += vec3(0.85, 0.22, 0.06) * heat * night * (0.35 + 0.4 * fbm(d * 5.0 + vec3(TIME * 0.05)));
		float lat = abs(d.y);
		float oval = exp(-pow((lat - 0.86) / 0.035, 2.0));
		float curtain = 0.6 + 0.4 * sin(atan(d.x, d.z) * 11.0 + TIME * 1.7);
		col += vec3(0.3, 0.95, 0.55) * oval * curtain * aurora * night * 0.55;
		alpha = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, r);
	}
	// Дымка за краем: тонкий светящийся ободок со стороны звезды.
	if (r > 1.0 - aa) {
		float x = (r - 1.0) / 0.07;
		float halo = exp(-x * 3.0) * step(0.0, x + aa);
		float lit = clamp(dot(normalize(p), normalize(light_dir)) * 0.7 + 0.45, 0.0, 1.0);
		vec3 hc = haze_col * star_light * (0.2 + 1.1 * lit);
		float ha = halo * (0.15 + 0.6 * lit);
		col = mix(hc, col, alpha);
		alpha = max(alpha, ha);
	}
	if (alpha <= 0.0) discard;
	COLOR = vec4(col, alpha * COLOR.a);
}
