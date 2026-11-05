shader_type canvas_item;
render_mode blend_premul_alpha;
// Шлейф гигантского удара, как у фрагментов кометы Шумейкеров — Леви 9 на
// Юпитере: огненный шар прорывается из облаков, поднимается веером и
// опадает. Цвет — по температуре: бело-жёлтый в начале, оранжевый, тёмно-
// красный, а потом бурый дым из вещества тела. Квад: низ по центру — точка
// удара, вверх (−y) — наружу от гиганта.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float t = 0.0;          // 0..1 жизнь шлейфа
uniform float seed = 0.0;
uniform vec3 smoke : source_color = vec3(0.35, 0.28, 0.22);   // дым — цвет вещества тела

vec3 temp_col(float k) {
	// k: 1 — раскалено добела, 0 — остыло.
	vec3 c0 = smoke;
	vec3 c1 = vec3(0.55, 0.12, 0.04);
	vec3 c2 = vec3(1.0, 0.45, 0.12);
	vec3 c3 = vec3(1.0, 0.82, 0.45);
	vec3 c4 = vec3(1.0, 0.97, 0.9);
	if (k < 0.25) return mix(c0, c1, k / 0.25);
	if (k < 0.5) return mix(c1, c2, (k - 0.25) / 0.25);
	if (k < 0.75) return mix(c2, c3, (k - 0.5) / 0.25);
	return mix(c3, c4, (k - 0.75) / 0.25);
}

void fragment() {
	vec2 p = vec2((UV.x - 0.5) * 2.0, 1.0 - UV.y);   // x −1..1, y 0..1 вверх
	float r = length(p);
	float ang = atan(p.x, max(p.y, 0.001));
	// Подъём и опадание: фронт растёт, потом оседает.
	float front = 0.15 + 0.85 * sin(min(t * 1.25, 1.0) * 1.5708);
	float fan = exp(-pow(ang / mix(0.55, 1.15, t), 2.0));
	vec2 q = vec2(ang * 2.0, r * 3.0 - t * 1.5);
	float n = texture(noise_tex, q * 0.35 + seed).r * 0.6 + texture(noise_tex, q * 0.9 + seed * 2.0).r * 0.4;
	float body = smoothstep(front + 0.05, front * 0.55, r) * fan;
	// Шапка: на фронте вещество гуще (грибовидный край).
	float cap = exp(-pow((r - front * 0.92) / 0.08, 2.0)) * fan;
	float dens = (body * (0.35 + 0.8 * n) + cap * 0.8 * n) * smoothstep(0.0, 0.03, p.y);
	dens *= 1.0 - smoothstep(0.75, 1.0, t);
	// Температура: внизу и в начале горячее, на фронте и к концу остывает.
	float k = clamp(1.05 - t * 1.3 - r * 0.45 + n * 0.25, 0.0, 1.0);
	vec3 col = temp_col(k);
	float a = clamp(dens * 1.4, 0.0, 0.95);
	float glow = smoothstep(0.45, 1.0, k) * dens * 1.2;
	COLOR = vec4(col * a + col * glow, a);
}
