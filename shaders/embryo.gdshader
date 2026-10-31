shader_type canvas_item;
// Зародыш планеты: тело в тысячи километров уже шар. Поверхность по составу
// (каменная, железная, углистая, ледяная, слоистая), магматический океан после
// гигантских ударов и дымка атмосферы у тяжёлого тела. Квадрат как у гальки:
// тело — BODY его ширины, атмосфера выходит за край.

uniform vec2 light_dir = vec2(-1.0, 0.0);
uniform vec3 star_light : source_color = vec3(1.0, 0.9, 0.75);
uniform int style = 0;            // 0 камень, 1 железо, 2 углерод, 3 лёд, 4 слоистое, 5 живая
uniform float magma = 0.0;        // 0..1: свежий магматический океан светится трещинами
uniform float atmo = 0.0;         // 0..1: толщина дымки
uniform float veil = 0.0;         // 0..1: сплошной облачный покров (Венера, Титан)
uniform vec3 atmo_col : source_color = vec3(0.55, 0.75, 1.0);
uniform float ocean = 0.0;        // 0..1: вода в низинах (у живой планеты моря свои)
uniform float frost = 0.0;        // 0..1: холод: моря замерзают, растут полярные шапки
uniform float clouds = 0.0;       // 0..1: облака водяного пара над тёплым океаном
uniform float spin = 0.0;
uniform float tilt = 0.45;
uniform float seed = 0.37;

const float BODY = 0.36;
const float R_MAX = 1.38;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7)) + seed * 91.3) * 43758.5453);
}

vec3 hash33(vec3 p) {
	return vec3(hash3(p), hash3(p + 17.31), hash3(p + 41.7));
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
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return s;
}

// Тонкие хребты и трещины: 1 у линии, 0 вдали.
float ridge(vec3 p, float width) {
	float n = fbm(p);
	return 1.0 - smoothstep(0.0, width, abs(n - 0.5));
}

// Кратеры: ячейки Вороного, у каждой кратер своего размера. x — дно (0..1 к центру), y — вал.
vec2 craters(vec3 p) {
	vec3 i = floor(p);
	float floor_k = 0.0;
	float rim = 0.0;
	for (int x = -1; x <= 1; x++)
	for (int y = -1; y <= 1; y++)
	for (int z = -1; z <= 1; z++) {
		vec3 c = i + vec3(float(x), float(y), float(z));
		vec3 h = hash33(c);
		if (h.z > 0.3) continue;
		float r = 0.12 + 0.4 * h.x * h.x;
		float d = length(p - (c + h * 0.8 + 0.1)) / r;
		float age = 0.4 + 0.6 * fract(h.z * 7.3);  // старые кратеры сглажены
		floor_k = max(floor_k, (1.0 - smoothstep(0.6, 0.95, d)) * age);
		rim = max(rim, smoothstep(0.75, 0.97, d) * (1.0 - smoothstep(0.97, 1.4, d)) * age);
	}
	return vec2(floor_k, rim);
}

// Высота поверхности по направлению: из неё — рельефные нормали.
float height(vec3 d) {
	float h = fbm(d * 2.4) * 0.7 + fbm(d * 9.0) * 0.3;
	vec2 cr = craters(d * 6.0);
	h += 0.12 * cr.y - 0.1 * cr.x;
	if (style == 3 || style == 5) h = 0.5 + 0.25 * (h - 0.5);  // лёд и вода сглаживают рельеф
	return h;
}

mat3 body_to_view() {
	float cs = cos(spin);
	float ss = sin(spin);
	float ct = cos(tilt);
	float st = sin(tilt);
	mat3 ry = mat3(vec3(cs, 0.0, -ss), vec3(0.0, 1.0, 0.0), vec3(ss, 0.0, cs));
	mat3 rx = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, ct, st), vec3(0.0, -st, ct));
	return rx * ry;
}

vec3 albedo_at(vec3 d, float h, out float spec) {
	float big = fbm(d * 1.6 + vec3(seed * 7.0));
	vec2 cr = craters(d * 6.0);
	float fine = fbm(d * 22.0);
	vec3 col;
	spec = 0.05;
	if (style == 0) {
		// Каменный: светлые материки и тёмные базальтовые моря.
		vec3 high = mix(vec3(0.7, 0.58, 0.46), vec3(0.8, 0.72, 0.62), fine);
		high = mix(high, vec3(0.72, 0.48, 0.36), smoothstep(0.55, 0.75, fbm(d * 4.0 + 20.0)) * 0.6);
		vec3 low = mix(vec3(0.26, 0.24, 0.24), vec3(0.36, 0.32, 0.3), fine);
		col = mix(low, high, smoothstep(0.46, 0.56, big));
		col = mix(col, col * 1.25, cr.y * 0.5);
		col *= 1.0 - 0.18 * cr.x;
	} else if (style == 1) {
		// Железный: тёмный металл, гладкие равнины и уступы-трещины от сжатия.
		col = mix(vec3(0.34, 0.35, 0.38), vec3(0.58, 0.59, 0.63), smoothstep(0.35, 0.7, big + 0.3 * fine));
		col *= 1.0 - 0.35 * ridge(d * 3.0 + 5.0, 0.03);
		spec = 0.55;
	} else if (style == 2) {
		// Углистый: почти чёрный, ржаво-бурые пятна органики.
		col = mix(vec3(0.13, 0.12, 0.11), vec3(0.22, 0.19, 0.16), fine);
		col = mix(col, vec3(0.42, 0.24, 0.12), smoothstep(0.55, 0.7, big) * 0.85);
		col = mix(col, col * 1.6, cr.y * 0.5);
	} else if (style == 3) {
		// Ледяной: гладкий голубоватый лёд, рыжие трещины-линеи.
		col = mix(vec3(0.72, 0.8, 0.88), vec3(0.9, 0.94, 0.98), smoothstep(0.3, 0.7, big));
		float lin = max(ridge(d * 2.2 + 3.0, 0.025), ridge(d * 4.1 + 9.0, 0.018) * 0.7);
		col = mix(col, vec3(0.62, 0.42, 0.3), lin * 0.75);
		spec = 0.35;
	} else if (style == 5) {
		// Живая: синие океаны с бликом, зелёно-бурые материки, полярные шапки и облака.
		float land = smoothstep(0.5, 0.54, big + 0.08 * fine);
		vec3 deep = mix(vec3(0.03, 0.12, 0.32), vec3(0.07, 0.3, 0.52), smoothstep(0.3, 0.5, big));
		vec3 ground = mix(vec3(0.18, 0.4, 0.15), vec3(0.56, 0.47, 0.3), smoothstep(0.45, 0.7, fbm(d * 3.0 + 7.0)));
		col = mix(deep, ground, land);
		col = mix(col, vec3(0.92, 0.95, 1.0), smoothstep(0.8, 0.88, abs(d.y) + 0.06 * fine));
		float cloud = smoothstep(0.52, 0.72, fbm(vec3(d.x * 2.4, d.y * 5.0, d.z * 2.4) + 30.0));
		col = mix(col, vec3(0.96, 0.97, 1.0), cloud * 0.85);
		spec = 0.7 * (1.0 - land) * (1.0 - cloud);
	} else {
		// Слоистое: пёстрые полосы разных пород, изогнутые течением мантии.
		float band = sin((d.y + 0.25 * fbm(d * 3.0)) * 14.0 + seed * 6.0) * 0.5 + 0.5;
		vec3 a = mix(vec3(0.62, 0.5, 0.4), vec3(0.42, 0.42, 0.48), smoothstep(0.3, 0.7, band));
		vec3 b = mix(vec3(0.22, 0.18, 0.16), vec3(0.72, 0.78, 0.84), smoothstep(0.5, 0.8, big));
		col = mix(a, b, smoothstep(0.45, 0.6, fbm(d * 2.6 + 11.0)) * 0.6);
		col *= 0.85 + 0.3 * fine;
	}
	col *= 0.9 + 0.2 * h;
	return col;
}

void fragment() {
	vec2 p = (UV - 0.5) / BODY;
	float r = length(p);
	if (r > R_MAX) discard;
	mat3 mi = transpose(body_to_view());
	vec3 L = normalize(vec3(light_dir, 0.3));
	float aa = fwidth(r) * 1.5;
	vec3 col = vec3(0.0);
	float alpha = 0.0;
	if (r < 1.0 + aa) {
		vec3 nv = vec3(p, sqrt(max(1.0 - r * r, 0.0)));  // нормаль шара в осях экрана
		vec3 d = mi * nv;
		// Рельеф: наклон нормали по градиенту высоты.
		float e = 0.012;
		float h0 = height(d);
		vec3 t1 = normalize(cross(d, vec3(0.0, 1.0, 0.001)));
		vec3 t2 = cross(d, t1);
		float hx = height(normalize(d + t1 * e)) - h0;
		float hy = height(normalize(d + t2 * e)) - h0;
		float bump = style == 3 || style == 5 ? 1.2 : 3.0;
		vec3 nb = normalize(d - (t1 * hx + t2 * hy) / e * 0.02 * bump);
		vec3 n = transpose(mi) * nb;  // обратно в оси экрана
		float spec_k;
		vec3 alb = albedo_at(d, h0, spec_k);
		// Вода молодой планеты: заполняет низины, на холоде замерзает.
		if (ocean > 0.0 && style != 5) {
			float lvl = fbm(d * 1.3 + vec3(seed * 5.0 + 3.0));
			float th = mix(0.36, 0.62, ocean);
			float sea = 1.0 - smoothstep(th - 0.012, th + 0.012, lvl);
			float depth = clamp((th - lvl) * 6.0, 0.0, 1.0);
			vec3 water = mix(vec3(0.06, 0.24, 0.42), vec3(0.02, 0.08, 0.22), depth);
			vec3 ice = mix(vec3(0.78, 0.86, 0.92), vec3(0.92, 0.95, 0.98), fbm(d * 14.0));
			water = mix(water, ice, smoothstep(0.35, 0.7, frost));
			alb = mix(alb, water, sea);
			spec_k = mix(spec_k, 0.75 * (1.0 - frost), sea);
			n = normalize(mix(n, nv, sea * 0.85));
		}
		if (frost > 0.0) {
			float cap = smoothstep(1.0 - 0.45 * frost, 1.0 - 0.45 * frost + 0.05, abs(d.y) + 0.06 * fbm(d * 8.0));
			alb = mix(alb, vec3(0.9, 0.94, 0.98), cap);
		}
		if (clouds > 0.0) {
			float cl = smoothstep(0.55 - 0.12 * clouds, 0.75, fbm(vec3(d.x * 2.4, d.y * 5.0, d.z * 2.4) + 30.0 + spin * 0.3));
			alb = mix(alb, vec3(0.95, 0.96, 0.98), cl * 0.85 * clouds);
			spec_k *= 1.0 - cl * clouds;
		}
		float diff = max(dot(n, L), 0.0);
		float wrap = max(dot(nv, L) * 0.5 + 0.5, 0.0);
		col = alb * star_light * (0.04 + 1.5 * diff);
		vec3 hv = normalize(L + vec3(0.0, 0.0, 1.0));
		col += star_light * spec_k * pow(max(dot(n, hv), 0.0), 24.0) * 0.6;
		// Магматический океан: светящиеся трещины в остывающей корке и лавовые озёра.
		if (magma > 0.0) {
			// Плиты тёмной корки, между ними — светящиеся швы; свежее тело — больше лавы.
			// Мелкая сетка швов застывает первой, крупные разломы держатся дольше.
			float crack = max(ridge(d * 2.2 + 2.0, 0.018 + 0.02 * magma), ridge(d * 5.0 + 6.0, 0.012) * 0.6 * smoothstep(0.25, 0.7, magma));
			float pool = smoothstep(0.66, 0.72, 1.0 - fbm(d * 1.8 + 4.0)) * magma;
			float hot = clamp((crack + pool) * magma, 0.0, 1.0);
			// Остывая, лава темнеет до тусклого вишнёвого, а не просто тускнеет.
			vec3 lava = mix(vec3(0.9, 0.18, 0.03), vec3(1.0, 0.72, 0.3), hot * smoothstep(0.2, 0.8, magma)) * (0.45 + 0.75 * magma);
			col = mix(col * (1.0 - 0.6 * magma) * vec3(0.8, 0.75, 0.75), lava * 1.5, hot * 0.9);
			col += vec3(1.0, 0.35, 0.08) * 0.08 * magma * (1.0 - wrap);
		}
		// Дымка на диске: к краю гуще, днём светится цветом атмосферы.
		if (atmo > 0.0) {
			float limb = pow(1.0 - nv.z, 2.0);
			col = mix(col, atmo_col * star_light * (0.15 + 1.2 * wrap * wrap), clamp(limb * atmo * 0.9 + atmo * 0.08, 0.0, 1.0));
		}
		// Сплошные облака: поверхность скрыта, видны мягкие полосы и шевроны дымки.
		if (veil > 0.0) {
			float lat = d.y;
			float band = fbm(vec3(d.x * 1.5, lat * 9.0, d.z * 1.5) + vec3(fbm(d * 2.0) * 1.5));
			vec3 cloud = atmo_col * (0.78 + 0.32 * band);
			float soft = smoothstep(-0.15, 0.9, dot(nv, L));
			vec3 vc = cloud * star_light * (0.03 + 1.15 * soft) * (0.75 + 0.25 * pow(max(nv.z, 0.0), 0.4));
			col = mix(col, vc, veil);
		}
		alpha = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, r);
	}
	// Атмосфера за краем диска: светящийся ободок со стороны звезды.
	if (atmo > 0.0 && r > 1.0 - aa) {
		float thick = 0.06 + 0.16 * atmo;
		float x = (r - 1.0) / thick;
		float halo = exp(-x * 3.0) * step(0.0, x + aa);
		float lit = clamp(dot(normalize(p), light_dir) * 0.6 + 0.5, 0.0, 1.0);
		vec3 hc = atmo_col * star_light * (0.25 + 1.3 * lit);
		float ha = halo * atmo * (0.35 + 0.65 * lit);
		col = mix(hc, col, alpha);
		alpha = max(alpha, ha);
	}
	if (alpha <= 0.0) discard;
	COLOR = vec4(col, alpha * COLOR.a);
}
