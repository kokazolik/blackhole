shader_type canvas_item;
render_mode blend_premul_alpha;
// Молекулярное облако в мировых координатах. Крупную форму даёт сетка газа
// (R — плотность сейчас, G — плотность в начале, обе делённые на 2), мелкую —
// шум с искажением. Холодный газ — тёмная пыль, заслоняющая звёзды; за фронтом
// ультрафиолета газ ионизован и светится: красным водородом (Hα) и
// сине-зелёным кислородом (O III) ближе к горячим звёздам. Плотные сгустки,
// которые фронт не успел съесть, стоят столбами с яркими краями, как
// «Столпы творения».

uniform sampler2D dens : filter_linear, repeat_disable;
uniform float world = 24000.0;
uniform vec2 origin = vec2(0.0);       // мировая позиция левого верхнего угла квада
uniform float front_x = -3000.0;
uniform vec2 ostar = vec2(-4000.0, 12000.0);
uniform vec2 sn_c = vec2(0.0);
uniform float sn_r = -1.0;
uniform float sn_flash = 0.0;
uniform vec2 me = vec2(0.0);
uniform float me_glow = 0.0;
uniform vec3 me_col : source_color = vec3(1.0, 0.6, 0.3);
uniform float fade = 1.0;              // облако рассеивается в конце
uniform float time = 0.0;

varying highp vec2 wp;

void vertex() {
	wp = VERTEX + origin;
}

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p, int oct) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < oct; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

// Та же кривая фронта, что и в cloud_stage.gd (front_at).
float front(float y) {
	return front_x + 600.0 * sin(y * 0.00031 + 1.3) + 350.0 * sin(y * 0.00093 + 0.4) + 160.0 * sin(y * 0.0027 + 2.1);
}

vec2 grid(vec2 p) {
	vec2 uv = p / world;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return vec2(0.0);
	}
	return texture(dens, uv).rg * 2.0;
}

void fragment() {
	vec2 p = wp;
	vec2 q = p * 0.0012;
	vec2 warp = vec2(fbm(q * 0.6 + vec2(time * 0.004, 0.0), 2), fbm(q * 0.6 + vec2(5.2, 1.3 - time * 0.003), 2));
	float det = fbm(q * 1.4 + warp * 1.8, 4);
	float wisp = fbm(q * 4.0 + warp * 3.0, 3);
	// Тонкие пряди: гребни шума, как нити пыли на снимках «Уэбба».
	float fil = pow(1.0 - abs(fbm(q * 2.3 + warp * 2.6, 4) * 2.0 - 1.0), 5.0);
	vec2 g = grid(p + (warp - 0.5) * 500.0);
	float d = g.x * (0.2 + 0.95 * det + 1.1 * fil) * (0.75 + 0.5 * wisp);
	float d0 = g.y * (0.3 + 1.0 * det + 0.8 * fil);

	// Фронт ультрафиолета: 1 за ним, 0 перед ним.
	float fx = front(p.y);
	float ion = smoothstep(-150.0, 450.0, fx - p.x);
	float near_front = exp(-abs(fx - p.x) / 900.0);

	// Пыль заслоняет фон.
	float absorb = 1.0 - exp(-d * 2.3);
	// Свет горячих звёзд падает слева: освещены стороны сгустков, обращённые к ним.
	float dl = grid(p + (warp - 0.5) * 500.0 - vec2(320.0, 0.0)).x * (0.2 + 0.95 * det + 1.1 * fil);
	float rim = clamp((d - dl) * 1.6, 0.0, 1.0) * clamp(d, 0.0, 1.0);
	float lit_side = rim * (0.12 + 1.5 * near_front + 0.8 * ion);
	vec3 dust = vec3(0.05, 0.036, 0.03) * (0.5 + 0.9 * det);
	dust += vec3(1.0, 0.7, 0.42) * lit_side * 0.5;
	// Тонкие пряди на тёмном фоне слегка подсвечены рассеянным светом.
	dust += vec3(0.32, 0.2, 0.14) * fil * (0.25 + 0.75 * near_front) * 0.35;

	// Ионизованный газ светится там, где облако было, а теперь съедено.
	float ghost = clamp(d0 * 0.8 + 0.25 * smoothstep(0.0, 0.3, g.y), 0.0, 1.6) * (0.35 + 1.1 * wisp) * (0.6 + 0.8 * det);
	float em = ion * ghost * (1.0 - 0.7 * absorb);
	float to_star = clamp(1.0 - length(p - ostar) / 14000.0, 0.0, 1.0);
	vec3 ha = vec3(0.95, 0.24, 0.32);
	vec3 o3 = vec3(0.22, 0.72, 0.78);
	vec3 emis = mix(ha, o3, to_star * to_star * 0.85) * em * 0.55;
	// Яркая кромка там, где фронт врезается в плотный газ.
	emis += vec3(1.0, 0.82, 0.6) * exp(-abs(fx - p.x) / 220.0) * clamp(d, 0.0, 1.2) * 0.6;

	// Свет протозвезды игрока: отражательная туманность вокруг неё.
	float dm = length(p - me);
	emis += me_col * me_glow * clamp(d * 0.6 + 0.05, 0.0, 1.0) * (0.3 + 0.7 * det + 0.6 * fil) / (1.0 + pow(dm / 480.0, 2.0)) * 0.5;

	// Ударная волна сверхновой: тонкая рваная оболочка.
	if (sn_r > 0.0) {
		float ds = length(p - sn_c);
		float jag = (det - 0.5) * 420.0 + (wisp - 0.5) * 260.0;   // рваный край оболочки
		float shell = exp(-pow((ds - sn_r + jag) / (70.0 + 120.0 * wisp), 2.0));
		shell *= smoothstep(0.25, 0.7, fil + det * 0.6);
		vec3 sh_col = mix(vec3(0.55, 0.72, 1.0), ha, smoothstep(0.55, 0.85, wisp) * 0.6);
		emis += sh_col * shell * (0.15 + 0.55 * fil) * 0.8;
		float behind = smoothstep(sn_r, sn_r - 900.0, ds) * smoothstep(sn_r - 2600.0, sn_r - 900.0, ds);
		emis += vec3(0.6, 0.35, 0.8) * behind * 0.06 * (0.3 + wisp);
	}
	emis += vec3(0.8, 0.85, 1.0) * sn_flash * 0.35;

	float a = clamp(absorb * 0.92, 0.0, 0.97) * fade;
	COLOR = vec4((dust * absorb + emis) * fade, a);
}
