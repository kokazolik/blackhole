shader_type canvas_item;
// Свой диск гиганта: газ, упавший по потокам, не садится сразу, а кружит
// вокруг плотным вихрем. Две спиральные руки — следы потоков из щели.
// У самого гиганта магнитное поле выметает полость: чем поле сильнее, тем она шире.
// Квад: центр — гигант, край квада — край диска.

uniform float inner = 0.3;     // край полости в долях радиуса квада
uniform float glow = 0.5;      // яркость: сколько газа падает сейчас
uniform float field = 0.3;     // магнитное поле 0..1
uniform float spin = 1.2;
uniform vec3 warm : source_color = vec3(1.0, 0.72, 0.42);
uniform vec3 hot : source_color = vec3(1.0, 0.93, 0.78);

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
	for (int i = 0; i < 4; i++) {
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
	// Кеплеров вихрь: внутри крутится быстрее, узор закручивается в спираль.
	float rot = TIME * spin * pow(max(r, 0.08), -1.5) * 0.25;
	float aa = a + rot;
	float arms = 0.5 + 0.5 * cos(2.0 * (aa - 4.0 * log(max(r, 0.05))));
	float n = fbm(vec2(cos(aa), sin(aa)) * (1.5 + 4.0 * r) + vec2(r * 9.0, 0.0));
	float dens = (0.35 + 0.65 * arms) * (0.55 + 0.6 * n);
	float edge = smoothstep(1.0, 0.55, r);
	float cav = smoothstep(inner, inner + 0.12, r);
	dens *= edge * cav;
	vec3 col = mix(warm, hot, smoothstep(0.6, 0.0, r) * arms);
	// Край полости: здесь поле срывает газ и гонит его к полюсам — светится.
	float lip = exp(-pow((r - inner - 0.04) / 0.035, 2.0)) * (0.4 + 0.6 * field);
	vec3 lip_col = mix(vec3(0.55, 0.85, 1.0), vec3(0.7, 0.55, 1.0), 0.5 + 0.5 * sin(a * 3.0 + TIME * 2.0));
	float alpha = clamp(dens * (0.25 + 0.75 * glow), 0.0, 0.85);
	vec3 c = col * (0.6 + 0.8 * glow) * dens + lip_col * lip * 0.55;
	COLOR = vec4(c, clamp(alpha + lip * 0.35, 0.0, 0.9));
}
