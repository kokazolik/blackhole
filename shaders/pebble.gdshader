shader_type canvas_item;
// Чужая галька из атласа для MultiMesh: освещена звездой как шар, медленно вращается,
// у снеговой линии покрывается инеем, у звезды тлеет.
//
// INSTANCE_CUSTOM: x — клетка атласа, y — угол поворота, z — скорость вращения,
//                  w — 1 у жеоды: сквозь трещины сверкают кристаллы, вокруг золотистый ореол.

uniform sampler2D atlas : filter_linear_mipmap;
uniform vec2 light_dir = vec2(-1.0, 0.0);
uniform vec3 star_light : source_color = vec3(1.0, 0.9, 0.75);
uniform float star_radius = 2000.0;
uniform float heat_start = 1.75;
uniform float snow_line = 6800.0;
uniform float snow_width = 700.0;

varying vec4 v_data;
varying float v_glow;
varying float v_frost;

void vertex() {
	v_data = INSTANCE_CUSTOM;
	vec2 world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	float heat = clamp((heat_start - length(world) / star_radius) / (heat_start - 1.0), 0.0, 1.0);
	float temp = 300.0 + 2700.0 * pow(heat, 1.3);
	v_glow = clamp((temp - 800.0) / 600.0, 0.0, 1.0);
	float ds = (length(world) - snow_line) / snow_width;
	v_frost = exp(-ds * ds);
}

void fragment() {
	vec2 p = UV - 0.5;
	float a = v_data.y + v_data.z * TIME;
	float c = cos(a);
	float s = sin(a);
	vec2 sp = vec2(c * p.x - s * p.y, s * p.x + c * p.y) + 0.5;
	vec2 cell = vec2(mod(v_data.x, 4.0), floor(v_data.x / 4.0));
	vec4 tex = texture(atlas, (cell + clamp(sp, 0.0, 1.0)) * 0.25);
	// Галька занимает ~72% квадрата: нормаль как у шара этого радиуса.
	vec2 q = p / 0.36;
	vec3 n = normalize(vec3(q, sqrt(max(1.0 - dot(q, q), 0.0)) + 0.05));
	float diff = max(dot(n, normalize(vec3(light_dir, 0.25))), 0.0);
	vec3 col = tex.rgb * star_light * (0.2 + 1.45 * diff);
	// Блик на гладкой поверхности.
	vec3 h = normalize(normalize(vec3(light_dir, 0.25)) + vec3(0.0, 0.0, 1.0));
	col += star_light * pow(max(dot(n, h), 0.0), 24.0) * 0.25;
	// Иней у снеговой линии и тление у звезды.
	float lum = dot(col, vec3(0.3, 0.5, 0.2));
	col = mix(col, vec3(0.82, 0.92, 1.0) * (lum * 1.2 + 0.05), v_frost * 0.4);
	col += mix(vec3(0.5, 0.05, 0.0), vec3(1.0, 0.45, 0.08), v_glow) * v_glow * (0.5 + 0.6 * diff);
	vec4 outc = vec4(col, tex.a);
	if (v_data.w > 1.5) {
		// Обломок после удара. Как в лабораторных опытах по разрушению и как валуны
		// на Итокаве и Рюгу: угловатый, вытянутый (оси примерно 1 : 0,7 : 0,5),
		// с плоскими гранями излома и острыми рёбрами. Рисуем выпуклый многогранник
		// сверху: верх из двух граней по гребню, по краям скошенные боковые грани,
		// у части обломков одна сторона — кусок прежней округлой поверхности.
		float sd0 = fract(v_data.w);
		// Квадрат обломка в SHARD_QUAD раз больше, поэтому q доходит до ~1,6.
		vec2 q = (sp - 0.5) / 0.36;
		q *= vec2(0.78 + 0.12 * fract(sd0 * 7.31), 1.15 + 0.2 * fract(sd0 * 3.17));
		float nv = 5.0 + floor(fract(sd0 * 5.71) * 3.0);
		bool crust = fract(sd0 * 11.3) < 0.65;
		float sd = -10.0;
		vec2 nf = vec2(1.0, 0.0);
		float fi = 0.0;
		for (int i = 0; i < 7; i++) {
			float k = float(i);
			if (k >= nv) {
				break;
			}
			float hh = fract(sin((k + sd0 * 17.0) * 78.233) * 43758.5453);
			float ang = k * 6.2832 / nv + (hh - 0.5) * 0.9;
			vec2 n = vec2(cos(ang), sin(ang));
			float dist = 0.62 + 0.3 * fract(hh * 9.7);
			float v = dot(q, n) - dist;
			if (i == 0 && crust) {
				// Прежняя поверхность: дуга большого круга вместо плоского излома.
				float rc = 1.3;
				v = length(q + n * (rc - dist)) - rc;
			}
			if (v > sd) {
				sd = v;
				nf = n;
				fi = k;
			}
		}
		float aa = fwidth(q.y) * 1.3;
		float mask = 1.0 - smoothstep(-aa, aa, sd);
		bool on_crust = crust && fi < 0.5;
		// Скос: полоса у края — боковая грань, круто наклонённая наружу.
		float bw = 0.2 + 0.1 * fract(sd0 * 23.1);
		float side_k = smoothstep(-bw - aa, -bw + aa, sd);
		// Верх ломается по гребню на две грани с разным наклоном.
		vec2 ridge = vec2(cos(sd0 * 40.0), sin(sd0 * 40.0));
		float rs = dot(q, vec2(-ridge.y, ridge.x)) - 0.15 * (fract(sd0 * 13.7) - 0.5);
		float half_k = smoothstep(-aa, aa, rs);
		vec2 tilt = vec2(-ridge.y, ridge.x) * 0.38;
		vec3 n_top = normalize(vec3(mix(-tilt, tilt, half_k) + ridge * 0.12, 1.0));
		vec3 n_side = on_crust ? normalize(vec3(nf * 1.1, 0.75)) : normalize(vec3(nf * 1.6, 0.55));
		vec3 nrm = normalize(mix(n_top, n_side, side_k));
		vec3 ld = normalize(vec3(light_dir, 0.35));
		float diff = max(dot(nrm, ld), 0.0);
		// Вещество: узор гальки из атласа. Свежий излом светлее и зернистее,
		// старая поверхность темнее (космическое выветривание).
		vec3 alb = texture(atlas, (cell + vec2(0.5) + clamp(q * 0.22, vec2(-0.3), vec2(0.3))) * 0.25).rgb;
		alb = on_crust && side_k > 0.5 ? alb * 0.7 : mix(alb, vec3(dot(alb, vec3(0.33))), 0.2) * 1.15;
		vec3 scol = alb * star_light * (0.12 + 1.55 * diff);
		// Острые рёбра ловят свет тонкой линией.
		float edge_line = 1.0 - smoothstep(0.0, aa * 2.0, abs(sd + bw));
		scol += star_light * 0.18 * edge_line * diff;
		scol = mix(scol, vec3(0.82, 0.92, 1.0) * (dot(scol, vec3(0.3, 0.5, 0.2)) * 1.2 + 0.05), v_frost * 0.4);
		scol += mix(vec3(0.5, 0.05, 0.0), vec3(1.0, 0.45, 0.08), v_glow) * v_glow * (0.5 + 0.6 * diff);
		outc = vec4(scol, mask);
	}
	if (v_data.w > 0.5 && v_data.w < 1.5) {
		// Жеода: кристаллы вспыхивают по очереди, вокруг мягкий ореол.
		vec3 gold = vec3(1.0, 0.85, 0.4);
		float cells = 0.0;
		for (int i = 0; i < 5; i++) {
			float fi = float(i);
			vec2 c2 = vec2(sin(fi * 2.4 + 0.7), cos(fi * 1.7 + 0.3)) * 0.22;
			float tw = pow(max(sin(mod(TIME, 28.56) * 2.2 + fi * 1.9), 0.0), 6.0);
			cells += exp(-dot(sp - 0.5 - c2, sp - 0.5 - c2) * 900.0) * (0.4 + 1.6 * tw);
		}
		outc.rgb += gold * cells * tex.a;
		// Ореол гаснет до нуля, не доходя до края квадрата: иначе на некоторых
		// телефонах квадрат проступал золотой плашкой.
		float d = length(p) / 0.36;
		float pulse = 0.55 + 0.25 * sin(mod(TIME, 6.2832) * 3.0);
		float halo = exp(-max(d - 0.9, 0.0) * 4.0) * pulse * (1.0 - smoothstep(1.0, 1.35, d));
		outc.rgb = mix(gold, outc.rgb, tex.a);
		outc.a = max(tex.a, halo * 0.6 * (1.0 - tex.a));
	}
	if (outc.a < 0.004) {
		discard;
	}
	COLOR = outc;
}
