shader_type canvas_item;
// Приливная струя разорванного тела: лента вдоль нити обломков.
// Так рисуют хвосты и струи в играх и в научной визуализации: не стопкой
// пятен, а гладкой лентой по контрольным точкам (здесь они летят по задаче
// Хилла), поперёк — гауссов профиль, вдоль — прожилки шума, которые
// тянутся вместе с потоком. Пыль светит отражённым светом звезды, а у самой
// планеты, где струя врезается в облака, накаляется.
// Line2D: UV.x — вдоль ленты (0 — голова у планеты), UV.y — поперёк.
// Цвет вершин (градиент Line2D) несёт яркость и накал по длине.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 dust_col : source_color = vec3(0.8, 0.74, 0.66);
uniform float len = 10.0;      // длина ленты в ширинах: прожилки не растягиваются
uniform float time = 0.0;
uniform float seed = 0.0;
uniform float spread = 0.0;    // 0 — свежая узкая нить, 1 — расплылась

void fragment() {
	float x = UV.x;
	float y = UV.y * 2.0 - 1.0;
	float along = x * len;
	// Прожилки: несколько тонких нитей внутри ленты, чуть волнистых.
	float wob = (texture(noise_tex, vec2(along * 0.05 + seed, 0.37)).r - 0.5) * 0.6;
	float yy = y + wob * (0.4 + spread);
	float core = exp(-yy * yy * mix(5.0, 2.2, spread));
	float strands = texture(noise_tex, vec2(along * 0.04 - time * 0.02 + seed, yy * 1.1 + 3.0)).r;
	strands = smoothstep(0.3, 0.85, strands);
	float fine = texture(noise_tex, vec2(along * 0.16 + seed * 2.0, yy * 2.6)).r;
	// Плотность: ядро нити плюс волокна, края мягко тают.
	float dens = core * (0.45 + 0.75 * strands) * (0.7 + 0.5 * fine);
	dens *= smoothstep(1.0, 0.55, abs(y));
	// Концы ленты гаснут: голова уходит в облака, хвост рассеивается.
	dens *= smoothstep(0.0, 0.06, x) * smoothstep(1.0, 0.75, x);
	float heat = COLOR.r;          // накал у планеты (в красном канале градиента)
	float bright = COLOR.g;
	vec3 col = dust_col * (0.75 + 0.5 * fine) * bright;
	col = mix(col, vec3(1.0, 0.62, 0.32) * (1.0 + 0.6 * strands), heat * 0.85);
	COLOR = vec4(col, clamp(dens * COLOR.a, 0.0, 1.0));
}
