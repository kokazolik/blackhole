shader_type canvas_item;
// Вихрь у края щели (неустойчивость Россби): вытянутый вдоль орбиты
// антициклон, в котором копится пыль. Газ закручен по эллипсам: внутри
// быстрее, к краю медленнее. Пыль сгущается к центру тёмной/светлой
// спиралью. Квад: длинная ось — по y (вдоль орбиты), отношение aspect.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 gas_col : source_color = vec3(0.85, 0.72, 0.55);
uniform vec3 dust_col : source_color = vec3(0.55, 0.38, 0.24);
uniform vec2 light_dir = vec2(-1.0, 0.0);
uniform float aspect = 3.0;
uniform float time = 0.0;
uniform float seed = 0.0;
uniform float strength = 1.0;   // 0..1 растёт при рождении и гаснет в конце
uniform float dark = 0.0;       // углеродная туча: сажа вместо пыли

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;           // −1..1
	vec2 e = vec2(p.x, p.y);             // эллипс уже вписан в вытянутый квад
	float r = length(e);
	if (r > 1.0) discard;
	// Угол поворота растёт к центру: дифференциальное вращение вихря.
	// Шум берётся в закрученных координатах, и облака сами вытягиваются в рукава.
	float a = atan(e.y, e.x);
	float twist = (1.0 - r) * (2.2 + time * 0.25);
	vec2 sw = vec2(cos(a + twist), sin(a + twist)) * r;
	float n1 = texture(noise_tex, sw * vec2(1.0, aspect) * 0.11 + vec2(seed, 0.3)).r;
	float n2 = texture(noise_tex, sw * vec2(1.0, aspect) * 0.27 + vec2(0.7, seed)).r;
	float fib = smoothstep(0.25, 0.85, n1 * 0.65 + n2 * 0.45);
	// Плотность: к центру больше, края растворяются.
	float body = smoothstep(1.0, 0.3, r);
	float core = exp(-r * r * 5.0);
	float dust = core * (0.45 + 0.75 * n2) * (0.5 + 0.6 * fib);
	vec3 col = mix(gas_col, dust_col, clamp(dust * 1.3, 0.0, 1.0));
	col = mix(col, vec3(0.06, 0.045, 0.035), dark * clamp(dust * 1.6 + 0.3, 0.0, 1.0));
	// Свет звезды: обращённый к ней край светлее.
	float lit = 0.75 + 0.35 * dot(normalize(p + vec2(0.0001)), normalize(light_dir));
	col *= lit;
	// Край вихря подсвечен звездой: видно форму даже у тёмной тучи.
	float rim = smoothstep(0.55, 0.9, r) * (1.0 - smoothstep(0.9, 1.0, r)) * fib;
	col += gas_col * rim * (0.35 + 0.4 * dark) * max(lit, 0.0);
	float alpha = body * (0.28 + 0.4 * fib + 0.4 * dust) * strength + rim * 0.25 * strength;
	COLOR = vec4(col, alpha);
}
