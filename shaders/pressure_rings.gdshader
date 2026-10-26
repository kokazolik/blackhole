shader_type canvas_item;
render_mode blend_add;
// Кольца-ловушки давления: мягкие пыльные полосы вокруг звезды с тонкой
// внутренней структурой, как на снимках дисков ALMA. Считается по расстоянию
// до звезды, поэтому полосы гладкие на любом приближении.

uniform vec4 rings = vec4(5300.0, 6800.0, 8700.0, 11000.0);
uniform float width = 300.0;
uniform float snow_line = 6800.0;
uniform float strength = 1.0;

varying highp vec2 world;

void vertex() {
	world = VERTEX;
}

void fragment() {
	highp float d = length(world);
	// Кольца далеко друг от друга: на пиксель влияет только ближайшее. Считаем
	// одно, а не все четыре: слой на весь экран, на телефоне это заметно.
	highp float rc = rings.x;
	if (abs(d - rings.y) < abs(d - rc)) rc = rings.y;
	if (abs(d - rings.z) < abs(d - rc)) rc = rings.z;
	if (abs(d - rings.w) < abs(d - rc)) rc = rings.w;
	highp float x = (d - rc) / width;
	if (abs(x) > 4.0) {
		discard;
	}
	float g = exp(-x * x / 1.44);
	// Тонкие кольца внутри полосы.
	float fine = 0.75 + 0.25 * sin(x * 9.0 + rc * 0.00113);
	vec3 tint = rc >= snow_line - 1.0 ? vec3(0.75, 0.9, 1.0) : vec3(1.0, 0.86, 0.62);
	vec3 col = tint * (g * fine * 0.2 + exp(-x * x * 60.0) * 0.1);  // полоса и яркая середина
	COLOR = vec4(col * strength, 1.0);
}
