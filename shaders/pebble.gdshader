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
		// Осколок шара: долька, у которой с одной стороны дуга прежней поверхности
		// (с корочкой), а с остальных — плоские свежие изломы, сходящиеся к острию.
		vec2 q = (sp - 0.5) / 0.36 * 0.85;
		float seed = fract(v_data.x * 0.618 + v_data.y * 0.137);
		float h1 = fract(sin(seed * 91.7) * 43758.5453);
		float h2 = fract(sin(seed * 47.3 + 1.3) * 43758.5453);
		float h3 = fract(sin(seed * 13.9 + 2.7) * 43758.5453);
		vec2 dir = vec2(cos(seed * 6.2832), sin(seed * 6.2832));
		vec2 perp = vec2(-dir.y, dir.x);
		// Прежняя поверхность: большой круг, его дуга — внешний край осколка.
		float rc = 1.25 + 0.6 * h1;
		vec2 c = dir * (0.95 - rc);
		float d_arc = length(q - c) - rc;
		// Два излома от острия, раскрываются к дуге; иногда острие сколото третьим.
		vec2 tip = -dir * (0.8 + 0.15 * h2) + perp * (h3 - 0.5) * 0.4;
		float w1 = 0.35 + 0.4 * h2;
		float w2 = 0.35 + 0.4 * h3;
		vec2 e1 = dir * cos(w1) + perp * sin(w1);
		vec2 e2 = dir * cos(w2) - perp * sin(w2);
		vec2 v = q - tip;
		float d1 = e1.x * v.y - e1.y * v.x;
		float d2 = -(e2.x * v.y - e2.y * v.x);
		float d3 = (h1 > 0.6 ? 0.25 * h1 : -1.0) - dot(v, dir);
		float sd = max(max(d_arc, d3), max(d1, d2));
		float aa = fwidth(q.x) * 1.5;
		float mask = 1.0 - smoothstep(-aa, aa, sd);
		vec3 ld = normalize(vec3(light_dir, 0.25));
		vec3 tex_c = tex.a > 0.05 ? tex.rgb : texture(atlas, (cell + vec2(0.5)) * 0.25).rgb;
		// Корочка у дуги — старая окатанная поверхность, освещена как часть шара.
		float crust = 1.0 - smoothstep(0.06, 0.2, -d_arc);
		vec3 n_crust = normalize(vec3((q - c) / rc * 0.85, 0.5));
		vec3 crust_col = tex_c * star_light * (0.2 + 1.4 * max(dot(n_crust, ld), 0.0));
		// Излом: две плоские грани по сторонам от гребня, светлее и ровнее корочки.
		float side = sign(perp.x * v.y - perp.y * v.x + 0.0001);
		vec3 n_face = normalize(vec3(perp * side * 0.55 - dir * 0.15, 0.8));
		vec3 fresh = mix(tex_c, vec3(dot(tex_c, vec3(0.33))), 0.25) * 1.25;
		vec3 face_col = fresh * star_light * (0.25 + 1.2 * max(dot(n_face, ld), 0.0));
		// Тонкая светлая кромка там, где излом встречается с корочкой.
		float rim = (1.0 - smoothstep(0.0, 0.05, abs(-d_arc - 0.13))) * 0.25;
		vec3 scol = mix(face_col, crust_col, crust) + star_light * rim * max(dot(n_crust, ld), 0.0);
		scol = mix(scol, vec3(0.82, 0.92, 1.0) * (dot(scol, vec3(0.3, 0.5, 0.2)) * 1.2 + 0.05), v_frost * 0.4);
		scol += mix(vec3(0.5, 0.05, 0.0), vec3(1.0, 0.45, 0.08), v_glow) * v_glow * 0.6;
		outc = vec4(scol, mask);
	}
	if (mod(v_data.w, 2.0) > 0.5) {
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
