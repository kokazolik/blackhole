shader_type canvas_item;
// Пылинка внутри Пушистого великана (MultiMesh): то же зерно из атласа, что и у
// свободной пыли, но без кольца уровня и ореола. Комок рыхлый, и свет звезды
// проходит его не насквозь: зёрна с дальней от звезды стороны в тени соседей.
//
// INSTANCE_CUSTOM: x — клетка атласа, y — 1 съедобная / 0.4 пока не по силам,
// z — уровень, w — начальный угол. COLOR — цвет материала.

uniform sampler2D atlas : filter_linear_mipmap;
uniform vec2 light_dir = vec2(-1.0, 0.0);  // в координатах квадрата (Y перевёрнут, как у пыли), узел вращается
uniform vec3 star_light : source_color = vec3(1.0, 0.9, 0.75);
uniform float radius = 50.0;               // радиус комка: насколько глубоко зерно

const float QUAD = 3.8;
const float SPRITE = 3.4;

varying vec4 v_data;
varying vec4 v_color;
varying float v_shade;

void vertex() {
	v_data = INSTANCE_CUSTOM;
	v_color = COLOR;
	// Вершина уже сдвинута на место зерна в комке. Чем дальше от звезды по лучу,
	// тем больше зёрен заслоняют свет: тень мягко сгущается к обратной стороне.
	vec2 lp = VERTEX / radius;
	float facing = dot(lp, normalize(vec2(light_dir.x, -light_dir.y)));
	v_shade = 0.18 + 0.82 * smoothstep(-0.7, 0.75, facing);
}

void fragment() {
	vec2 p = (UV - 0.5) * QUAD;
	float phase = v_data.w;
	float a = phase + (fract(phase * 13.7) - 0.5) * 0.3 * TIME;
	float c = cos(a);
	float s = sin(a);
	vec2 sp = vec2(c * p.x - s * p.y, s * p.x + c * p.y) / SPRITE + 0.5;
	vec4 col = vec4(0.0);
	if (sp.x > 0.0 && sp.x < 1.0 && sp.y > 0.0 && sp.y < 1.0) {
		vec2 cell = vec2(mod(v_data.x, 4.0), floor(v_data.x / 4.0));
		col = texture(atlas, (cell + sp) * 0.25);
		vec2 q = p / (SPRITE * 0.4);
		vec3 n = normalize(vec3(q, sqrt(max(1.0 - dot(q, q), 0.0)) + 0.05));
		float diff = max(dot(n, normalize(vec3(light_dir, 0.25))), 0.0);
		col.rgb *= star_light * (0.12 + 1.3 * diff) * v_shade;
		col.a *= v_data.y > 0.9 ? 1.0 : 0.6;
	}
	// Лёгкая дымка цвета материала: комок читается целиком, а не россыпью точек.
	float g = exp(-dot(p, p) * 0.9);
	col.rgb += v_color.rgb * g * 0.08 * v_shade;
	col.a = max(col.a, g * 0.1);
	COLOR = col;
}
