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
	vec3 col = vec3(0.0);
	for (int i = 0; i < 4; i++) {
		highp float x = (d - rings[i]) / width;
		float g = exp(-x * x / 1.44);
		// Тонкие кольца внутри полосы.
		float fine = 0.75 + 0.25 * sin(x * 9.0 + float(i) * 1.7);
		vec3 tint = rings[i] >= snow_line - 1.0 ? vec3(0.75, 0.9, 1.0) : vec3(1.0, 0.86, 0.62);
		col += tint * g * fine * 0.2;
		col += tint * exp(-x * x * 60.0) * 0.1;  // яркая середина
	}
	COLOR = vec4(col * strength, 1.0);
}
