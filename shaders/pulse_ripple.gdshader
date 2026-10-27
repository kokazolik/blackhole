shader_type canvas_item;
// Волна импульса: не цветное кольцо, а рябь тяготения — фон, пыль и гальки
// на гребне волны чуть сдвигаются наружу и обратно, как сквозь линзу.
//
// Квадрат стороной 2 радиуса волны (с запасом); ring — где сейчас гребень, 0..1.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float ring = 0.5;
uniform float fade = 1.0;
uniform float strength = 9.0;  // сдвиг на гребне, пикселей экрана

void fragment() {
	vec2 d = (UV - 0.5) * 2.0;
	float r = length(d);
	float x = (r - ring) / 0.07;
	// Производная гауссианы: впереди гребня — наружу, позади — внутрь.
	float wave = -x * exp(-x * x) * fade;
	vec2 dir = r > 0.0001 ? d / r : vec2(0.0);
	vec2 offset = dir * wave * strength * SCREEN_PIXEL_SIZE;
	vec3 col = textureLod(screen_tex, SCREEN_UV + offset, 0.0).rgb;
	// Едва заметное просветление на самом гребне.
	col += vec3(0.6, 0.75, 0.9) * 0.05 * exp(-x * x) * fade;
	float band = exp(-x * x * 0.25);
	COLOR = vec4(col, band * step(r, 1.0));
}
