shader_type canvas_item;
// Свой диск гиганта: газ, упавший по потокам, не садится сразу, а кружит
// вокруг тонким полупрозрачным вихрем. Он тусклый: светит только отражённым
// светом звезды и слабым нагревом там, где в него бьют струи.
// У самого гиганта магнитное поле выметает полость: чем поле сильнее, тем она шире.
// Квад: центр — гигант, край квада — край диска.

uniform float inner = 0.3;     // край полости в долях радиуса квада
uniform float glow = 0.5;      // сколько газа падает сейчас
uniform float field = 0.3;     // магнитное поле 0..1
uniform float spin = 1.2;
uniform vec2 light_dir = vec2(-1.0, -0.12);
uniform vec3 dusk : source_color = vec3(0.46, 0.38, 0.32);
uniform vec3 warm : source_color = vec3(0.95, 0.72, 0.5);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		s += a * noise(p);
		p = p * 2.1 + vec2(3.1, 7.7);
		a *= 0.5;
	}
	return s;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float a = atan(p.y, p.x);
	// Кеплеров вихрь: внутри крутится быстрее, клочья тянутся в тугую спираль.
	float rot = TIME * spin * pow(max(r, 0.1), -1.5) * 0.12;
	float aa = a + rot;
	vec2 q = vec2(log(max(r, 0.05)) * 3.0, aa * 1.6);
	float n = fbm(vec2(q.x * 2.2 + q.y * 0.35, cos(aa) * 1.3) + vec2(0.0, sin(aa) * 1.3));
	float fine = fbm(vec2(r * 22.0, aa * 3.0));
	float arms = 0.5 + 0.5 * cos(2.0 * (aa - 2.5 * log(max(r, 0.05))));
	float dens = (0.55 + 0.45 * n) * (0.8 + 0.2 * arms) * (0.85 + 0.3 * fine);
	// Плотнее к гиганту, мягко тает к краю сферы Хилла.
	dens *= pow(1.0 - smoothstep(0.25, 1.0, r), 1.4) * (1.0 + 0.6 * smoothstep(0.6, 0.2, r));
	float cav = smoothstep(inner, inner + 0.08, r);
	dens *= cav;
	// Свет звезды падает сбоку: ближняя к звезде сторона диска светлее.
	float lit = 0.55 + 0.45 * dot(normalize(p + vec2(1e-4)), normalize(light_dir));
	vec3 col = dusk * (0.5 + 0.7 * lit);
	// Нагрев от ударов струй: тёплый, но приглушённый, ярче у полости.
	col = mix(col, warm, clamp(glow * 0.45 * smoothstep(0.7, 0.25, r) * arms, 0.0, 0.5));
	// Край полости: поле срывает газ к полюсам, тонкая холодная кромка.
	float lip = exp(-pow((r - inner - 0.02) / 0.02, 2.0)) * field * 0.5;
	float alpha = clamp(dens * (0.22 + 0.2 * glow), 0.0, 0.5);
	vec3 c = col + vec3(0.6, 0.78, 1.0) * lip * 0.4;
	COLOR = vec4(c, clamp(alpha + lip * 0.12, 0.0, 0.55));
}
