shader_type canvas_item;
render_mode blend_disabled;
// Второй проход печи планетезимали: нормаль поверхности по запечённой высоте.
// Считать её на лету по сглаженной текстуре нельзя: видеокарта смешивает соседние
// пиксели грубыми долями, и на пологом склоне свет ложится горизонталями.
// Здесь соседи берутся точно (texelFetch), а точки — настоящие точки поверхности.

uniform sampler2D height_map;

vec3 point_at(ivec2 c, ivec2 size) {
	c.x = (c.x + size.x) % size.x;
	c.y = clamp(c.y, 0, size.y - 1);
	vec4 t = texelFetch(height_map, c, 0);
	vec2 uv = (vec2(c) + 0.5) / vec2(size);
	float lon = (uv.x - 0.5) * TAU;
	float th = uv.y * PI;
	vec3 d = vec3(sin(th) * cos(lon), cos(th), sin(th) * sin(lon));
	return d * (1.0 + t.r + t.g / 64.0);
}

void fragment() {
	ivec2 size = textureSize(height_map, 0);
	ivec2 c = ivec2(floor(UV * vec2(size)));
	vec3 tx = point_at(c + ivec2(1, 0), size) - point_at(c - ivec2(1, 0), size);
	vec3 ty = point_at(c + ivec2(0, 1), size) - point_at(c - ivec2(0, 1), size);
	vec3 n = cross(tx, ty);
	vec3 d = normalize(point_at(c, size));
	if (dot(n, d) < 0.0) n = -n;
	n = length(n) > 1e-8 ? normalize(n) : d;
	COLOR = vec4(n, 1.0);
}
