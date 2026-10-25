shader_type canvas_item;
// Дальнее свечение звезды, считается формулой, а не растянутой текстурой:
// маленькая текстура на таком огромном круге давала прямые изломы и полосы.
// Яркость спадает как exp(-2.2 · расстояние от края в радиусах).

uniform float extent = 3.0;
uniform float star_radius = 2000.0;
uniform vec3 halo_color : source_color = vec3(1.0, 0.45, 0.12);

varying highp vec2 star_pos;

void vertex() {
	star_pos = VERTEX / star_radius;
}

void fragment() {
	float r = length(star_pos);
	float a = 0.35 * exp(-2.2 * max(r - 1.0, 0.0)) * smoothstep(extent, extent * 0.5, r);
	a += (fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453) - 0.5) / 255.0;
	COLOR = vec4(halo_color, clamp(a, 0.0, 1.0));
}
