shader_type canvas_item;
// Звезда сдувает оболочку: верх атмосферы, нагретый жёстким светом молодой
// звезды, уходит потоком прочь от неё (как водородный хвост HD 209458 b).
// Поток тусклый: светит только рассеянным светом звезды. Магнитное поле
// держит ионизированный газ: при сильном поле поток узкий и короткий, газ
// выходит лишь у полюсов, где линии поля открыты; при слабом — широкий
// конус, как у кометы.
// Квад: центр — гигант, ось +x — прочь от звезды; половина квада = reach
// радиусов планеты (pr — радиус планеты в долях половины квада).

uniform float strength = 0.0;  // сколько газа уходит, 0..1
uniform float field = 0.3;     // магнитное поле 0..1
uniform float pr = 0.16;       // радиус планеты в долях половины квада
// Квад обрезан: к звезде за шаром пусто, рисуем только хвостовую сторону.
uniform vec2 uv_off = vec2(-1.0, -1.0);
uniform vec2 uv_scale = vec2(2.0, 2.0);
uniform vec3 tint : source_color = vec3(0.8, 0.78, 0.74);

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

float fbm(vec2 p) {
	return texture(noise_tex, p * 0.0625).r;
}

void fragment() {
	vec2 p = UV * uv_scale + uv_off;
	vec2 q = p / pr;                 // в радиусах планеты
	float r = length(q);
	// Под шаром ничего не видно: шар рисуется сверху, но край пусть тает сам.
	float outside = smoothstep(0.98, 1.08, r);
	// Дневная сторона: тонкое светлое гало раздутой верхней атмосферы.
	float day = clamp(-q.x / max(r, 0.001), 0.0, 1.0);
	float halo = exp(-pow((r - 1.08) / 0.07, 2.0)) * (0.3 + 0.7 * day);
	// Поток: от дневного края обтекает шар и уходит назад конусом.
	float x = q.x + 0.4;
	float along = max(x, 0.0);
	float open = mix(1.0, 0.45, field);      // поле сжимает конус
	float len = mix(9.0, 3.2, field);        // и укорачивает его
	float w = (1.05 + 0.32 * along * open) * open + 0.25;
	float cone = exp(-pow(q.y / w, 2.0)) * smoothstep(-1.2, 0.6, x) * exp(-along / len);
	// Сильное поле: газ уходит двумя струями у полюсов (открытые линии поля).
	float pol = exp(-pow((abs(q.y) - 0.95 - 0.12 * along) / 0.32, 2.0)) * smoothstep(-0.6, 0.8, x)
		* exp(-along / (len * 0.8));
	float dens = mix(cone, max(cone * 0.4, pol), smoothstep(0.35, 0.85, field));
	// Волокна текут прочь: клочья газа, растянутые потоком.
	float flow = fbm(vec2(along * 0.9 - TIME * 0.35, q.y * 1.7));
	float fine = fbm(vec2(along * 2.6 - TIME * 0.6, q.y * 4.2 + 3.0));
	dens *= (0.45 + 0.75 * flow) * (0.8 + 0.4 * fine);
	dens = dens * outside + halo * 0.6;
	// Цвет: верх атмосферы на свету, к хвосту бледнее и холоднее (рассеяние).
	vec3 col = mix(tint, vec3(0.78, 0.84, 0.96), smoothstep(0.0, 6.0, along) * 0.6);
	float a = clamp(dens * strength * 0.36, 0.0, 0.45);
	COLOR = vec4(col, a);
}
