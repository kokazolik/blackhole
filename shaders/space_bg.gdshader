shader_type canvas_item;
// Фон космоса: туманности и два слоя звёзд с разным параллаксом.
// Три выборки бесшовных текстур на пиксель — дёшево даже на слабом телефоне.

uniform sampler2D nebula : filter_linear, repeat_enable;
uniform sampler2D stars_far : filter_linear, repeat_enable;
uniform sampler2D stars_near : filter_linear, repeat_enable;
uniform vec2 view_size = vec2(1280.0, 720.0);
uniform vec2 offset;  // положение камеры в пикселях экрана
uniform vec3 base_color : source_color = vec3(0.010, 0.012, 0.028);

const float NEBULA_PARALLAX = 0.02;
const float FAR_PARALLAX = 0.06;
const float NEAR_PARALLAX = 0.22;
const float NEBULA_SCALE = 2048.0;  // туманность растянута вдвое: облака крупнее
const float STAR_SCALE = 1024.0;

void fragment() {
	vec2 px = UV * view_size;
	vec4 neb = texture(nebula, (px + offset * NEBULA_PARALLAX) / NEBULA_SCALE);
	vec4 far = texture(stars_far, (px + offset * FAR_PARALLAX) / STAR_SCALE);
	vec4 near = texture(stars_near, (px + offset * NEAR_PARALLAX + vec2(311.0, 97.0)) / STAR_SCALE);
	vec3 col = base_color + neb.rgb * neb.a + far.rgb * far.a + near.rgb * near.a;
	COLOR = vec4(col, 1.0);
}
