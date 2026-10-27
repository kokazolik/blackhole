shader_type canvas_item;
render_mode blend_mul;
// Тень огромной гальки (DustDrifters): всё позади неё от звезды темнеет —
// пыль, ты сам и далёкий фон. Край тени мягкий: звезда огромная, и полутень
// растёт с расстоянием от гальки.

uniform vec2 body;              // центр гальки в мировых координатах
uniform float radius;
uniform vec2 to_star = vec2(-1.0, 0.0);
uniform vec2 soft = vec2(20.0, 0.012);  // полутень: постоянная часть + доля расстояния
uniform float depth = 0.84;

varying vec2 world;

void vertex() {
	world = VERTEX;  // узел в начале координат мира
}

void fragment() {
	vec2 rel = world - body;
	float behind = dot(rel, -to_star);
	float lateral = abs(dot(rel, vec2(-to_star.y, to_star.x)));
	float pw = soft.x + max(behind - radius, 0.0) * soft.y;
	float k = 1.0 - smoothstep(radius - pw, radius + pw, lateral);
	k *= smoothstep(0.0, radius * 0.1, behind);
	COLOR = vec4(vec3(1.0 - depth * k), 1.0);
}
