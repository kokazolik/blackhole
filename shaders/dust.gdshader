shader_type canvas_item;
// Пылинка из атласа для MultiMesh: свечение, спрайт и кольцо уровня в одном квадрате.
// Вращение считается здесь по времени, поэтому неподвижную пыль процессор не трогает.
//
// Данные экземпляра:
//   COLOR            — цвет материала (для свечения)
//   INSTANCE_CUSTOM  — x: номер клетки атласа, y: прозрачность (1 или 0.4 у недоступной),
//                      z: уровень пыли, w: начальный угол поворота

uniform sampler2D atlas : filter_linear_mipmap;
uniform vec4 level_colors[3];

const float QUAD = 3.8;    // сторона квадрата в радиусах пылинки
const float SPRITE = 3.4;  // сторона спрайта в радиусах пылинки
const float RING = 1.75;   // радиус кольца уровня
const float GLOW = 1.9;    // радиус свечения

varying vec4 v_data;
varying vec4 v_color;

void vertex() {
	v_data = INSTANCE_CUSTOM;
	v_color = COLOR;
}

void fragment() {
	vec2 p = (UV - 0.5) * QUAD;  // в радиусах пылинки
	float d = length(p);
	float alpha = v_data.y;
	float level = v_data.z;

	// Свечение цвета материала, чтобы мелкая пыль читалась на тёмном фоне.
	float g = 1.0 - smoothstep(0.0, GLOW, d);
	vec4 col = vec4(v_color.rgb, g * g * (alpha > 0.9 ? 0.32 : 0.12));

	// Спрайт поворачивается со своей скоростью, она выводится из начального угла.
	float phase = v_data.w;
	float spin = (fract(phase * 13.7) - 0.5) * 1.2;
	float a = phase + spin * TIME;
	float c = cos(a);
	float s = sin(a);
	vec2 sp = vec2(c * p.x - s * p.y, s * p.x + c * p.y) / SPRITE + 0.5;
	if (sp.x > 0.0 && sp.x < 1.0 && sp.y > 0.0 && sp.y < 1.0) {
		vec2 cell = vec2(mod(v_data.x, 4.0), floor(v_data.x / 4.0));
		vec4 tex = texture(atlas, (cell + sp) * 0.25);
		tex.a *= alpha;
		col.rgb = mix(col.rgb, tex.rgb, tex.a);
		col.a = tex.a + col.a * (1.0 - tex.a);
	}

	// Кольцо уровня: у пыли выше первого уровня и у недоступной. Толщина ~1.5 px на экране.
	if (level > 1.5 || alpha < 0.9) {
		float w = fwidth(d) * 1.5;
		float ring = 1.0 - smoothstep(0.0, w, abs(d - RING));
		vec4 rc = level_colors[int(clamp(level, 1.0, 3.0)) - 1];
		float ra = ring * (alpha < 0.9 ? 0.5 : 0.6);
		col.rgb = mix(col.rgb, rc.rgb, ra);
		col.a = ra + col.a * (1.0 - ra);
	}
	COLOR = col;
}
