shader_type canvas_item;
// Далёкие гиганты на фоне (FarBodies): тела, до которых тебе расти и расти.
// kind 0 — протопланета: каменный шар с серпом света, на ночной стороне тлеют
// трещины расплава (её греет распад алюминия-26). kind 1 — зарождающийся
// газовый гигант: полосатый шар в собственном диске из газа и пыли.
// Всё за толщей пыли диска: края мягкие, цвета тонут в тёплой дымке.

uniform int kind = 0;
uniform vec2 light_dir = vec2(-1.0, 0.0);  // на экране, к звезде
uniform float seed = 0.3;
uniform float quad = 1.0;       // половина квадрата в радиусах тела
uniform float tilt = 0.4;       // наклон диска гиганта
uniform float haze = 0.35;      // сколько пыли между нами
uniform vec3 star_light : source_color = vec3(1.0, 0.9, 0.75);

const vec3 HAZE = vec3(0.32, 0.24, 0.17);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 91.3) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

// Диск гиганта: кольцо в наклонённой плоскости. front — ближняя половина.
vec4 disk(vec2 p, bool front, vec3 L) {
	float ca = cos(tilt * 2.0);
	float sa = sin(tilt * 2.0);
	vec2 q = vec2(ca * p.x + sa * p.y, -sa * p.x + ca * p.y);
	float incl = 0.22;
	if ((q.y > 0.0) != front) {
		return vec4(0.0);
	}
	float rr = length(vec2(q.x, q.y / incl));
	float band = smoothstep(1.15, 1.6, rr) * (1.0 - smoothstep(1.8, 2.65, rr));
	float gaps = 0.8 + 0.2 * sin(rr * 17.0 + seed * 10.0) * sin(rr * 5.0);
	float grain = 0.8 + 0.4 * noise(vec2(atan(q.y / incl, q.x) * 6.0, rr * 14.0));
	float a = band * gaps * grain * 0.55;
	// Тёплое свечение газа у самой планеты плюс свет звезды на пыли.
	float lit = 0.45 + 0.55 * max(dot(normalize(vec3(q.x, 0.0, -q.y)), L) * 0.5 + 0.5, 0.0);
	vec3 col = mix(vec3(0.85, 0.62, 0.42), vec3(1.0, 0.78, 0.5), smoothstep(2.2, 1.4, rr)) * lit;
	return vec4(col, a);
}

void fragment() {
	vec2 p = (UV * 2.0 - 1.0) * quad;
	float r = length(p);
	float aa = fwidth(r) * 1.5 + 0.035;
	vec3 L = normalize(vec3(light_dir, 0.35));
	vec4 outc = vec4(0.0);

	if (kind == 1) {
		vec4 back = disk(p, false, L);
		outc = back;
	}

	float body = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, r);
	if (body > 0.0) {
		float z = sqrt(max(1.0 - r * r, 0.0));
		vec3 n = vec3(p, z);
		float diff = dot(n, L);
		float lit = smoothstep(-0.08, 0.35, diff) * (0.35 + 0.65 * max(diff, 0.0));
		vec3 col;
		if (kind == 0) {
			// Каменная протопланета: пятна реголита, кратеры, бугристый край.
			vec2 sp = p / (0.6 + 0.4 * z);  // узор стягивается к краю шара
			float m = fbm(sp * 3.2 + seed * 7.0);
			float cr = smoothstep(0.62, 0.7, noise(sp * 9.0 + 3.0)) - smoothstep(0.7, 0.78, noise(sp * 9.0 + 3.0)) * 0.6;
			col = vec3(0.5, 0.44, 0.38) * (0.65 + 0.6 * m) * (1.0 - 0.25 * cr);
			col *= star_light * lit * 1.3;
			// Расплав в трещинах на ночной стороне.
			float crack = 1.0 - smoothstep(0.0, 0.05, abs(fbm(sp * 4.0 + 11.0) - 0.5));
			col += vec3(1.0, 0.32, 0.08) * crack * 0.55 * smoothstep(0.1, -0.3, diff) * z;
		} else {
			// Газовый гигант: полосы по широте, завихрения, тёмный лимб.
			float ct = cos(tilt * 2.0);
			float st = sin(tilt * 2.0);
			float lat = (-st * p.x + ct * p.y) / max(z * 0.3 + 0.7, 0.01);
			float w = fbm(vec2(lat * 3.0, (ct * p.x + st * p.y) * 1.5) + seed * 5.0);
			float bands = sin(lat * 11.0 + w * 3.0);
			col = mix(vec3(0.72, 0.56, 0.4), vec3(0.93, 0.85, 0.7), bands * 0.5 + 0.5);
			col = mix(col, vec3(0.55, 0.35, 0.25), smoothstep(0.65, 0.8, w) * 0.5);
			col *= star_light * lit * (0.55 + 0.45 * z) * 1.2;
			// Тёплое внутреннее свечение молодой планеты на ночной стороне.
			col += vec3(0.5, 0.18, 0.08) * 0.12 * smoothstep(0.1, -0.4, diff);
		}
		outc = mix(outc, vec4(col, 1.0), body);
	}

	if (kind == 1) {
		vec4 front = disk(p, true, L);
		outc.rgb = mix(outc.rgb, front.rgb, front.a);
		outc.a = max(outc.a, front.a);
	}
	// Толща пыли: цвета тонут в тёплой дымке, тело чуть просвечивает.
	outc.rgb = mix(outc.rgb * 0.8, HAZE * (0.4 + 0.6 * outc.a), haze);
	outc.a *= 1.0 - haze * 0.45;
	// Ореол рассеянного света вокруг освещённого края.
	float halo = exp(-max(r - 1.0, 0.0) * 9.0) * (1.0 - body) * max(dot(normalize(p + 1e-4), light_dir), 0.0);
	outc.rgb += HAZE * halo * 0.6;
	outc.a = max(outc.a, halo * 0.35);
	COLOR = outc;
}
