shader_type canvas_item;
// Пылинка игрока, освещённая звездой: зерно как шар, светлая сторона смотрит на звезду.
// light_dir задаёт player.gd в координатах спрайта с учётом его вращения.

uniform vec2 light_dir = vec2(-1.0, 0.0);
uniform vec3 star_light : source_color = vec3(1.0, 0.9, 0.75);
uniform float grain_radius = 0.36;  // радиус комка в долях текстуры

void fragment() {
	vec4 tex = texture(TEXTURE, UV) * COLOR;
	vec2 q = (UV - 0.5) / grain_radius;
	vec3 n = normalize(vec3(q, sqrt(max(1.0 - dot(q, q), 0.0)) + 0.05));
	float diff = max(dot(n, normalize(vec3(light_dir, 0.25))), 0.0);
	COLOR = vec4(tex.rgb * star_light * (0.25 + 1.5 * diff), tex.a);
}
