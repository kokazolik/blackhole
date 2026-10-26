shader_type canvas_item;
// Затемнение вокруг того, что показывает Звездочёт: сам предмет остаётся в круге света.

uniform vec2 rect_size = vec2(1.0);
uniform vec2 center = vec2(0.0);
uniform float radius = 100.0;
uniform float strength = 0.0;

void fragment() {
	float d = length(UV * rect_size - center);
	float k = smoothstep(radius, radius * 1.4 + 30.0, d);
	COLOR = vec4(0.02, 0.0, 0.06, 0.55 * k * strength);
}
