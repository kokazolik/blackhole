shader_type canvas_item;
// Размытые пылинки у самой камеры: сдвигаются быстрее мира и дают ощущение глубины.
// Одна выборка текстуры на пиксель, почти везде прозрачно.

uniform sampler2D bokeh : filter_linear, repeat_enable;
uniform vec2 view_size = vec2(1280.0, 720.0);
uniform vec2 offset;  // положение камеры в пикселях экрана
uniform vec3 star_light : source_color = vec3(1.0, 0.88, 0.72);

const float PARALLAX = 1.7;
const float SCALE = 1400.0;

void fragment() {
	vec4 b = texture(bokeh, (UV * view_size + offset * PARALLAX) / SCALE);
	COLOR = vec4(b.rgb * star_light, b.a);
}
