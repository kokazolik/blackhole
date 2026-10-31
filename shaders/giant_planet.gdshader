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
		if (use_map) {
			// Карта уже содержит пояса со своими скоростями; целиком шар крутит spin.
			float lon = atan(d.x, d.z) + spin;
			alb = texture(map, vec2(fract(lon / 6.2832 + 0.5), clamp(0.5 - asin(clamp(d.y, -1.0, 1.0)) / 3.1416, 0.0, 1.0))).rgb;
		} else {
			alb = clouds(d, spot_k);
		}
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
