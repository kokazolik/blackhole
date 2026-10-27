shader_type canvas_item;
render_mode blend_disabled;
// Поверхность огромной гальки на этапе пылинки, запекается один раз в бесшовную
// плитку (DustDrifters). Галька в сотню раз крупнее игрока, и вблизи видно, из
// чего сложен хондрит, как на распилах и снимках зёрен Рюгу и Итокавы:
// • тёмная тонкозернистая матрица, пористая, с зернистостью на всех масштабах;
// • хондры — застывшие капли от долей до пары радиусов игрока, светлее матрицы,
//   с тёмной каймой-оболочкой; внутри то пятнистые кристаллы (порфировые),
//   то параллельные полосы оливина (колосниковые), то веер пироксена (радиальные);
// • белые неровные включения CAI — первое твёрдое вещество диска;
// • искры металла и бронзовые зёрна сульфида;
// • поры, ямки и редкие трещины.
// pass_id 0: rgb — альбедо, a — металл. pass_id 1: r — высота рельефа.
// Весь шум периодичен по плитке, поэтому она укладывается без швов.

uniform int pass_id = 0;
uniform float seed = 0.37;
uniform vec4 mix_w = vec4(0.45, 0.12, 0.28, 0.15);  // силикаты, металл, углерод, лёд

const vec3 SILICATE = vec3(0.76, 0.64, 0.47);
const vec3 METAL = vec3(0.62, 0.64, 0.7);
const vec3 CARBON = vec3(0.3, 0.22, 0.2);
const vec3 ICE = vec3(0.8, 0.9, 1.0);
const vec3 CHONDRULE = vec3(0.7, 0.7, 0.62);   // серый оливин и пироксен
const vec3 CHONDRULE_DARK = vec3(0.46, 0.48, 0.42);
const vec3 CAI = vec3(0.93, 0.9, 0.86);
const vec3 SULFIDE = vec3(0.78, 0.62, 0.36);

float hashp(vec2 i, float per) {
	i = mod(i, per);
	return fract(sin(dot(i, vec2(127.1, 311.7)) + seed * 91.3) * 43758.5453);
}

float noisep(vec2 x, float per) {
	vec2 i = floor(x);
	vec2 f = fract(x);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hashp(i, per), hashp(i + vec2(1.0, 0.0), per), u.x),
			mix(hashp(i + vec2(0.0, 1.0), per), hashp(i + vec2(1.0, 1.0), per), u.x), u.y);
}

// uv в долях плитки, per — сколько клеток на плитку в первой октаве.
float fbmp(vec2 uv, float per, int oct) {
	float v = 0.0;
	float a = 0.5;
	float n = 0.0;
	for (int i = 0; i < 6; i++) {
		if (i >= oct) break;
		v += a * noisep(uv * per + float(i) * 17.0 * per, per);
		n += a;
		per *= 2.0;
		a *= 0.5;
	}
	return v / n;
}

// Периодический Вороного: f1, f2-f1 и случайное число ячейки.
vec3 voronoip(vec2 uv, float per) {
	vec2 x = uv * per;
	vec2 xi = floor(x);
	vec2 xf = fract(x);
	float f1 = 8.0;
	float f2 = 8.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int xx = -1; xx <= 1; xx++) {
			vec2 g = vec2(float(xx), float(y));
			vec2 c = xi + g;
			vec2 o = vec2(hashp(c + 3.3 * per, per), hashp(c + 9.1 * per, per));
			float d = length(g + o - xf);
			if (d < f1) {
				f2 = f1;
				f1 = d;
				id = hashp(c + 1.7 * per, per);
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	return vec3(f1, f2 - f1, id);
}

// Хондры одного размера: ищем каплю, накрывающую точку. Возвращает маску,
// высоту купола, вид и вектор от центра (в радиусах капли).
// out: kind — 0..1 случайный, тон — 0..1, d — смещение от центра / радиус.
float chondrules(vec2 uv, float per, float present, float rmin, float rmax,
		out float dome, out float kind, out float tone, out vec2 dir, out float rim) {
	vec2 x = uv * per;
	vec2 xi = floor(x);
	vec2 xf = fract(x);
	float best = 0.0;
	dome = 0.0;
	kind = 0.0;
	tone = 0.0;
	dir = vec2(0.0);
	rim = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int xx = -1; xx <= 1; xx++) {
			vec2 g = vec2(float(xx), float(y));
			vec2 c = xi + g;
			if (hashp(c + 41.7 * per, per) > present) continue;
			float rad = mix(rmin, rmax, pow(hashp(c + 5.1 * per, per), 1.6));
			vec2 o = 0.5 + (vec2(hashp(c, per), hashp(c + 17.3 * per, per)) - 0.5) * (1.0 - 2.0 * rad);
			vec2 d = g + o - xf;
			// Капли не идеально круглые: чуть сплюснуты и с неровным краем.
			float ang = hashp(c + 2.9 * per, per) * 6.283;
			vec2 ax = vec2(cos(ang), sin(ang));
			float squash = 1.0 + 0.25 * hashp(c + 6.6 * per, per);
			vec2 dl = vec2(dot(d, ax) * squash, dot(d, vec2(-ax.y, ax.x)));
			float a2 = atan(dl.y, dl.x);
			float wob = 1.0 + 0.025 * sin(a2 * 3.0 + ang * 3.0) + 0.015 * sin(a2 * 7.0 + ang * 5.0);
			float l = length(dl) / (rad * wob);
			// Четверть капель — обломки: срезаны по прямой, как расколотые в диске.
			float cut = 2.0;
			if (hashp(c + 31.3 * per, per) < 0.25) {
				float ca = hashp(c + 37.7 * per, per) * 6.283;
				cut = dot(dl / rad, vec2(cos(ca), sin(ca))) * -1.0 + mix(0.1, 0.6, hashp(c + 43.1 * per, per));
			}
			l = max(l, 1.0 - cut * 0.9);
			float rimw = 0.12;
			float k = 1.0 - smoothstep(1.0 - 0.04, 1.0, l);
			float rk = smoothstep(1.0 - 0.02, 1.0, l) * (1.0 - smoothstep(1.0 + rimw, 1.0 + rimw + 0.05, l));
			rim = max(rim, rk * (1.0 - k));
			if (k > best) {
				best = k;
				dome = sqrt(max(1.0 - l * l, 0.0)) * rad;
				kind = hashp(c + 13.1 * per, per);
				tone = hashp(c + 23.9 * per, per);
				dir = dl / rad;
			}
		}
	}
	return best;
}

void fragment() {
	vec2 uv = UV;
	vec3 base = SILICATE * mix_w.x + METAL * mix_w.y + CARBON * mix_w.z + ICE * mix_w.w;
	base *= 1.0 - 0.25 * mix_w.z;

	// Матрица: спёкшаяся тонкая пыль. Тёмная, зернистая, с пятнами тона.
	float m_big = fbmp(uv, 4.0, 4);
	float m_fine = fbmp(uv, 64.0, 4);
	float grit = noisep(uv * 512.0, 512.0);
	float grit2 = noisep(uv * 256.0 + 7.0, 256.0);
	vec3 mbase = mix(base, vec3(dot(base, vec3(0.3, 0.5, 0.2))), 0.45);
	vec3 matrix = mbase * 0.5 * (0.75 + 0.45 * m_big) * (0.85 + 0.3 * m_fine) * (0.88 + 0.24 * grit);
	// Мелкие светлые и тёмные зёрна минералов в матрице.
	float sp = noisep(uv * 384.0 + 3.0, 384.0);
	matrix *= 1.0 + 0.35 * smoothstep(0.78, 0.9, sp) - 0.3 * smoothstep(0.8, 0.92, 1.0 - sp);
	float h = 0.35 * m_big + 0.18 * m_fine + 0.06 * grit + 0.04 * grit2;

	// Хондры двух размеров: крупные и россыпь мелких.
	float d1, k1, t1, r1;
	vec2 v1;
	float c1 = chondrules(uv, 9.0, 0.5, 0.16, 0.42, d1, k1, t1, v1, r1);
	float d2, k2, t2, r2;
	vec2 v2;
	float c2 = chondrules(uv + 0.37, 23.0, 0.45, 0.15, 0.38, d2, k2, t2, v2, r2);
	bool big = c1 >= c2;
	float ch = max(c1, c2);
	float kind = big ? k1 : k2;
	float tone = big ? t1 : t2;
	vec2 cv = big ? v1 : v2;
	float dome = big ? d1 / 9.0 : d2 / 23.0;  // в долях плитки
	float rim = max(r1, r2) * (1.0 - ch);

	// Узор внутри капли по её виду.
	float inner;
	if (kind < 0.75) {
		// Порфировая: пятна кристаллов оливина в стекле.
		inner = 0.75 + 0.45 * smoothstep(0.45, 0.7, noisep(uv * (big ? 220.0 : 420.0) + kind * 50.0, big ? 220.0 : 420.0));
	} else if (kind < 0.86) {
		// Колосниковая: параллельные пластины оливина в тонкой оболочке.
		float a = kind * 40.0;
		float bars = sin(dot(cv, vec2(cos(a), sin(a))) * 26.0);
		inner = 0.82 + 0.25 * smoothstep(-0.2, 0.4, bars);
		inner = mix(inner, 1.05, smoothstep(0.82, 0.92, length(cv)));
	} else if (kind < 0.95) {
		// Радиальная: веер тонких волокон пироксена из точки у края.
		vec2 o = cv - vec2(cos(kind * 30.0), sin(kind * 30.0)) * 0.7;
		float fan = sin(atan(o.y, o.x) * 34.0);
		inner = 0.85 + 0.2 * smoothstep(-0.3, 0.6, fan);
	} else {
		// Скрытокристаллическая: гладкая, почти без узора.
		inner = 0.95 + 0.1 * noisep(uv * 60.0, 60.0);
	}
	vec3 chond_col = mix(CHONDRULE_DARK, CHONDRULE, tone) * mix(vec3(1.0), base / max(dot(base, vec3(0.33)), 0.01), 0.25) * inner;
	vec3 albedo = mix(matrix, chond_col, ch);
	// Тёмная кайма тонкой пыли вокруг хондры.
	albedo *= 1.0 - 0.38 * rim;
	h += ch * (0.2 + dome * 16.0) - rim * 0.06;

	// Включения CAI: белые неровные пятна, редкие и рыхлые по краю.
	float cai_n = fbmp(uv + 0.21, 6.0, 5);
	float cai = smoothstep(0.71, 0.735, cai_n) * (1.0 - ch);
	albedo = mix(albedo, CAI * (0.62 + 0.25 * noisep(uv * 300.0, 300.0)), cai * 0.85);
	h += cai * 0.12;

	// Металл и сульфид: мелкие яркие зёрна.
	float metal = smoothstep(0.93 - 0.06 * mix_w.y, 0.97, noisep(uv * 160.0 + 11.0, 160.0));
	float blob = smoothstep(0.8, 0.86, fbmp(uv + 0.6, 40.0, 2));
	metal = max(metal, blob * 0.9) * (1.0 - 0.7 * ch);
	float sulf = smoothstep(0.88, 0.94, noisep(uv * 140.0 + 29.0, 140.0)) * (1.0 - ch) * (1.0 - metal);
	albedo = mix(albedo, METAL * 0.9, metal * 0.8);
	albedo = mix(albedo, SULFIDE, sulf * 0.8);
	h += metal * 0.05;

	// Поры и ямки: тёмные впадинки, где матрица выкрошилась.
	// Круглые: ячейки Вороного, в части из них ямка своего размера.
	vec3 pv = voronoip(uv + 0.13, 70.0);
	float pit = (1.0 - smoothstep(0.12, 0.2, pv.x / (0.6 + pv.z))) * step(pv.z, 0.35) * (1.0 - ch);
	vec3 qv = voronoip(uv + 0.71, 190.0);
	float pore = (1.0 - smoothstep(0.1, 0.18, qv.x / (0.6 + qv.z))) * step(qv.z, 0.4) * (1.0 - ch);
	albedo *= 1.0 - 0.45 * pit - 0.3 * pore;
	h -= 0.22 * pit + 0.08 * pore;

	// Трещины: неровные линии по границам блоков, местами.
	vec2 w = vec2(fbmp(uv + 0.1, 6.0, 3), fbmp(uv + 0.5, 6.0, 3)) - 0.5;
	vec3 vk = voronoip(fract(uv + w * 0.06), 3.0);
	float crack = (1.0 - smoothstep(0.0, 0.025, vk.y)) * smoothstep(0.45, 0.6, fbmp(uv + 0.8, 3.0, 3));
	albedo *= 1.0 - 0.55 * crack;
	h -= 0.3 * crack;

	if (pass_id == 0) {
		COLOR = vec4(albedo, metal);
	} else {
		COLOR = vec4(h, ch, 0.0, 1.0);
	}
}
