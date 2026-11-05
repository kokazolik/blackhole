shader_type canvas_item;
render_mode blend_add;
// Комета: ядро в коме и два хвоста, всегда от звезды.
// Квад вытянут вдоль хвоста: ядро в точке (head, 0.5), ось +x — от звезды.
// Пылевой хвост широкий, жёлто-белый и загибается назад по орбите;
// ионный тонкий, голубой, прямой, в прожилках. Края квада гаснут мягко.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float head = 0.08;       // где ядро вдоль квада
uniform float aspect = 4.0;      // длина квада / ширина
uniform float bend = 0.25;       // изгиб пылевого хвоста (знак — куда отстаёт орбита)
uniform float bright = 1.0;      // ярче у звезды
uniform float time = 0.0;
uniform float seed = 0.0;

void fragment() {
	vec2 uv = UV;
	float x = (uv.x - head) / (1.0 - head);      // 0 у ядра, 1 в конце хвоста
	float y = (uv.y - 0.5) * 2.0;                 // −1..1 поперёк
	vec2 q = vec2((uv.x - head) * aspect, y);     // изотропные координаты у ядра
	float r = length(q * vec2(1.0, 0.5));
	// Кома: плотное свечение вокруг ядра.
	float coma = exp(-r * r * 60.0) * 1.4 + exp(-r * 9.0) * 0.35;
	float nucleus = exp(-r * r * 2200.0) * 2.0;
	float tail = 0.0;
	float ion = 0.0;
	if (x > -0.02) {
		float xx = max(x, 0.0);
		// Пылевой хвост: расширяется и загибается.
		float cy = bend * xx * xx;
		float w = 0.06 + 0.5 * xx;
		float n = texture(noise_tex, vec2(xx * 1.4 + seed, y * 0.6) * 0.25).r;
		tail = exp(-pow((y - cy) / w, 2.0)) * pow(1.0 - xx, 1.6) * (0.65 + 0.5 * n);
		// Ионный хвост: прямой, узкий, с прожилками, бежит быстрее.
		float streak = texture(noise_tex, vec2(xx * 0.5 - time * 0.08 + seed, y * 5.0) * 0.5).r;
		ion = exp(-pow(y / (0.025 + 0.12 * xx), 2.0)) * pow(1.0 - xx, 0.9) * (0.4 + 0.9 * streak * streak);
	}
	vec3 dust = vec3(1.0, 0.93, 0.8);
	vec3 blue = vec3(0.45, 0.68, 1.0);
	vec3 col = dust * (coma * 0.9 + tail * 0.55) + blue * ion * 0.5 + vec3(1.0) * nucleus;
	// Края квада не видны.
	float edge = smoothstep(0.0, 0.04, uv.x) * smoothstep(1.0, 0.85, uv.x) * smoothstep(0.0, 0.15, uv.y) * smoothstep(1.0, 0.85, uv.y);
	COLOR = vec4(col * bright * edge, 1.0);
}
