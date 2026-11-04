shader_type canvas_item;
// Куски движка разрушения. Вершинный цвет — не цвет, а данные:
// r — освещённость, g — жар (накал), a — прозрачность. Ячейки со снимком
// тела берут цвет из текстуры; полоски изломов и тела без снимка помечены
// uv < 0 и рисуются вершинным цветом как есть.

varying vec4 vc;

void vertex() {
	vc = COLOR;
}

vec3 incand(float h) {
	vec3 a = vec3(0.55, 0.06, 0.02);
	vec3 b = vec3(1.0, 0.42, 0.08);
	vec3 c = vec3(1.0, 0.86, 0.55);
	return h < 0.6 ? mix(a, b, h / 0.6) : mix(b, c, clamp((h - 0.6) / 0.6, 0.0, 1.0));
}

void fragment() {
	if (UV.x < -0.5) {
		COLOR = vc;
	} else {
		vec4 t = texture(TEXTURE, UV);
		vec3 c = t.rgb * vc.r;
		float h = vc.g;
		// Накал проступает в тёмных местах (трещины, ночная сторона) сильнее.
		float lum = dot(t.rgb, vec3(0.3, 0.5, 0.2));
		c = mix(c, incand(h) * (0.7 + 0.5 * h), clamp(h * 1.4 - 0.45, 0.0, 0.85) * (1.0 - 0.4 * lum));
		COLOR = vec4(c, t.a * vc.a);
	}
}
