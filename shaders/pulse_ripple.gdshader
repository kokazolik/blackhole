shader_type canvas_item;
// Волна плотности: от тебя расходится волна уплотнённого газа. На гребне газ
// гуще — мутная тёплая дымка с клочьями, а картинка за ней чуть плывёт, как
// сквозь нагретый воздух.
//
// Квадрат стороной 2 радиуса волны (с запасом); ring — где сейчас гребень, 0..1.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float ring = 0.5;
uniform float fade = 1.0;
uniform float strength = 5.0;  // сдвиг картинки на гребне, пикселей экрана
uniform vec3 tint : source_color = vec3(0.92, 0.78, 0.6);
uniform float seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 31.7) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 d = (UV - 0.5) * 2.0;
	float r = length(d);
	// Гребень неровный: клочья газа по окружности.
	float ang = atan(d.y, d.x);
	vec2 q = vec2(cos(ang), sin(ang)) * 3.0 + vec2(r * 4.0 - ring * 2.0);
	float clumps = noise(q * 1.7) * 0.65 + noise(q * 4.1) * 0.35;
	float x = (r - ring - (clumps - 0.5) * 0.05) / 0.09;
	float crest = exp(-x * x);
	float wave = -x * crest * fade;
	vec2 dir = r > 0.0001 ? d / r : vec2(0.0);
	vec2 offset = dir * wave * strength * SCREEN_PIXEL_SIZE;
	vec3 col = textureLod(screen_tex, SCREEN_UV + offset, 0.0).rgb;
	// Уплотнённый газ — мутная тёплая дымка, гуще в клочьях.
	float haze = crest * fade * (0.35 + 0.65 * clumps) * smoothstep(1.0, 0.85, r);
	col = mix(col, tint * 0.55, haze * 0.22) + tint * haze * 0.05;
	float band = exp(-x * x * 0.25);
	COLOR = vec4(col, band * step(r, 1.0));
}
