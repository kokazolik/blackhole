shader_type canvas_item;
// Газовый гигант вблизи: облачные пояса и зоны неровной ширины, сдвиговые
// течения на их границах с завитками, овальные вихри и большое пятно,
// хаотичные полярные области. Свет как у зародыша: звезда сбоку, мягкий
// терминатор, дымка по краю. Ночью у полюсов слабо светятся сияния, а у
// горячего юпитера тлеет раскалённая ночная сторона.
// Квадрат: тело — BODY его ширины, дымка выходит за край.

uniform vec2 light_dir = vec2(-1.0, -0.1);
uniform vec3 star_light : source_color = vec3(1.0, 0.92, 0.8);
uniform float aurora = 0.0;  // магнитное поле: сияния у полюсов на ночной стороне
uniform float heat = 0.0;    // жар горячего юпитера: светится ночная сторона

uniform bool use_map = false;     // облака из запечённой карты (этап гиганта)
uniform sampler2D map : filter_linear_mipmap, repeat_enable;
uniform vec4 scars[6];             // следы ударов: долгота, широта, размер (рад), сила
// Молодой гигант: оболочка только что сжалась и раскалена (свет сжатия).
// young 1 — светится сам, по нему бегут ячейки конвекции; остывая, тускнеет
// от жёлтого к тёмно-красному, и в нём конденсируются облака — сперва
// из того, чем богато ядро (veil_col), потом они вытягиваются в пояса.
uniform float envelope = 1.0;    // 0 — оболочка ещё рыхлая (шар не виден), 1 — готовый гигант
uniform float young = 0.0;       // 0..1 накал молодого гиганта
uniform float temp = 0.6;        // температура фотосферы, тыс. К
uniform vec3 veil_col : source_color = vec3(0.75, 0.8, 0.9);   // первые облака: конденсат по составу ядра

vec3 bb(float t) {
	vec3 c0 = vec3(0.12, 0.01, 0.0);
	vec3 c1 = vec3(0.55, 0.07, 0.01);
	vec3 c2 = vec3(0.95, 0.28, 0.05);
	vec3 c3 = vec3(1.0, 0.52, 0.18);
	vec3 c4 = vec3(1.0, 0.78, 0.52);
	if (t < 0.8) return mix(c0, c1, clamp((t - 0.5) / 0.3, 0.0, 1.0));
	if (t < 1.2) return mix(c1, c2, (t - 0.8) / 0.4);
	if (t < 2.0) return mix(c2, c3, (t - 1.2) / 0.8);
	return mix(c3, c4, clamp((t - 2.0) / 1.0, 0.0, 1.0));
}

const float BODY = 0.36;
const float R_MAX = 1.25;

#include "res://shaders/giant_clouds.gdshaderinc"

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
		vec3 alb;
		float cover = 1.0;
		float n_env = 0.5;
		if (use_map) {
			// Карта уже содержит пояса со своими скоростями; целиком шар крутит spin.
			float lon = atan(d.x, d.z) + spin;
			alb = texture(map, vec2(fract(lon / 6.2832 + 0.5), clamp(0.5 - asin(clamp(d.y, -1.0, 1.0)) / 3.1416, 0.0, 1.0))).rgb;
			// Тёмные пятна ударов: ядро, кольцо выброса и тонкий ободок, как у следов кометы в 1994-м.
			float lat0 = asin(clamp(d.y, -1.0, 1.0));
			vec3 here = vec3(sin(lon) * cos(lat0), sin(lat0), cos(lon) * cos(lat0));
			for (int i = 0; i < 6; i++) {
				vec4 sc = scars[i];
				if (sc.w <= 0.0) continue;
				vec3 c = vec3(sin(sc.x) * cos(sc.y), sin(sc.y), cos(sc.x) * cos(sc.y));
				float ang = acos(clamp(dot(here, c), -1.0, 1.0)) / max(sc.z, 0.001);
				// Пятно размыто ветрами: мягкое ядро и широкий тёмный ореол выброса,
				// вытянутый вдоль пояса (по долготе).
				vec3 dd = here - c;
				float stretch_lat = abs(dd.y) / max(sc.z, 0.001);
				float soft = ang * 0.7 + stretch_lat * 0.6;
				float core = exp(-soft * soft * 1.6);
				float halo = exp(-pow(max(soft - 1.0, 0.0) / 0.8, 2.0)) * 0.45 * smoothstep(0.3, 1.0, soft);
				alb = mix(alb, vec3(0.2, 0.14, 0.11), clamp((core * 0.8 + halo) * sc.w, 0.0, 0.7));
			}
			if (young > 0.001) {
				// Облака конденсируются по мере остывания: перья вдоль параллелей
				// (вращение уже тянет их в полосы), края мягкие и рваные.
				vec3 q = vec3(here.x * 1.5, here.y * 9.0, here.z * 1.5) + vec3(seed * 7.0);
				vec3 w = vec3(fbm(q * 0.6 + 3.0), 0.0, fbm(q * 0.6 + 8.0)) * 0.8;
				n_env = fbm(q + w) * 0.75 + fbm(q * 3.1 + 5.0) * 0.25;
				float th = mix(0.0, 1.0, smoothstep(0.05, 0.6, young));
				cover = smoothstep(th - 0.14, th + 0.16, n_env);
				vec3 plain = mix(veil_col, zone_col, 0.35) * (0.8 + 0.4 * n_env);
				alb = mix(alb, plain, smoothstep(0.0, 0.3, young));
			}
		} else {
			alb = clouds(d, spot_k);
		}
		float ndl = dot(nv, L);
		// Мягкий терминатор: облачный слой рассеивает свет за черту.
		float diff = smoothstep(-0.22, 0.9, ndl);
		float limb = pow(max(nv.z, 0.0), 0.35);  // к краю облака темнеют
		col = alb * star_light * (0.012 + 1.2 * pow(diff, 1.6)) * (0.55 + 0.45 * limb);
		// Пока оболочка рыхлая, края у шара нет: он проступает, когда она сжалась.
		float in_a = smoothstep(0.22, 0.42, envelope);
		vec3 emis = vec3(0.0);
		if (young > 0.001) {
			// Свой свет: конвекция выносит горячий газ ячейками (светлые
			// середины, тёмные края), к краю диска темнее (луч в холодных слоях).
			vec3 dq = d * 9.0 + vec3(seed * 3.0, TIME * 0.02, 0.0);
			float cell = fbm(dq + vec3(fbm(dq * 0.5 + 4.0) * 1.5));
			float gran = 0.55 + 0.9 * smoothstep(0.3, 0.75, cell);
			float ld = 0.35 + 0.65 * pow(max(nv.z, 0.0), 0.6);
			float lum = pow(young, 1.4) * 1.15;
			emis = bb(temp * (0.92 + 0.16 * cell)) * gran * ld * lum;
			// Облака — сначала редкие тёмные завесы на светящемся фоне.
			col = mix(col * (1.0 - 0.75 * young), col, cover) + emis * (1.0 - cover * 0.8);
		}
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
		alpha = (1.0 - smoothstep(1.0 - aa, 1.0 + aa, r)) * in_a;
	}
	// Дымка за краем: тонкий светящийся ободок со стороны звезды.
	if (r > 1.0 - aa) {
		float x = (r - 1.0) / 0.07;
		float halo = exp(-x * 3.0) * step(0.0, x + aa);
		float lit = clamp(dot(normalize(p), normalize(light_dir)) * 0.7 + 0.45, 0.0, 1.0);
		vec3 hc = haze_col * star_light * (0.2 + 1.1 * lit);
		float ha = halo * (0.15 + 0.6 * lit) * smoothstep(0.22, 0.42, envelope);
		col = mix(hc, col, alpha);
		alpha = max(alpha, ha);
	}
	if (alpha <= 0.0) discard;
	COLOR = vec4(col, alpha * COLOR.a);
}
