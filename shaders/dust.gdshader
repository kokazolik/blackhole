shader_type canvas_item;
// Пылинка из атласа для MultiMesh: свечение, спрайт и кольцо уровня в одном квадрате.
// Вращение считается здесь по времени, поэтому неподвижную пыль процессор не трогает.
//
// Данные экземпляра:
//   COLOR            — цвет материала (для свечения)
//   INSTANCE_CUSTOM  — x: номер клетки атласа (−1 у облачка), y: прозрачность (1 или 0.4
//                      у недоступной), z: уровень пыли, w: начальный угол поворота
//
// Рядом с галькой (этап «Галька») пылинки — крохотные крапинки, их рисуем дёшево:
// точка со свечением без атласа, освещения и бликов. Облачко — дымка с горсткой искр.

uniform sampler2D atlas : filter_linear_mipmap;
uniform vec4 level_colors[3];
// Направление на звезду в координатах квадрата. Задаёт dust_field.gd каждый кадр:
// игрок летит по орбите, и освещённая сторона пыли поворачивается вместе с ним.
uniform vec2 light_dir = vec2(-1.0, 0.0);
uniform vec3 star_light : source_color = vec3(1.0, 0.9, 0.75);
uniform float star_radius = 2000.0;
// Нагрев как в GameData.temperature_at: у границы испарения пыль тлеет.
uniform float heat_start = 1.75;
uniform float snow_line = 6800.0;
uniform float snow_width = 700.0;
uniform bool simple = false;  // упрощённые крапинки на этапе «Галька»

const float QUAD = 3.8;    // сторона квадрата в радиусах пылинки
const float SPRITE = 3.4;  // сторона спрайта в радиусах пылинки
const float RING = 1.75;   // радиус кольца уровня
const float GLOW = 1.9;    // радиус свечения

varying vec4 v_data;
varying vec4 v_color;
varying float v_glow;   // свечение от нагрева, 0..1
varying float v_frost;  // иней у снеговой линии, 0..1

void vertex() {
	v_data = INSTANCE_CUSTOM;
	v_color = COLOR;
	// Расстояние до звезды: вершина уже сдвинута на положение экземпляра,
	// MODEL_MATRIX добавляет сдвиг узла (орбитальную систему отсчёта).
	vec2 world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	float heat = clamp((heat_start - length(world) / star_radius) / (heat_start - 1.0), 0.0, 1.0);
	float temp = 300.0 + 2700.0 * pow(heat, 1.3);
	v_glow = clamp((temp - 800.0) / 600.0, 0.0, 1.0);  // от точки Дрейпера до испарения
	float ds = (length(world) - snow_line) / snow_width;
	v_frost = exp(-ds * ds);
}

// Цвет тления: тёмно-красный → оранжевый.
vec3 ember(float t) {
	return mix(vec3(0.5, 0.05, 0.0), vec3(1.0, 0.45, 0.08), t);
}

vec4 level_tint(float level) {
	return level_colors[int(clamp(level, 1.0, 3.0)) - 1];
}

void fragment() {
	vec2 p = (UV - 0.5) * QUAD;  // в радиусах пылинки
	float d = length(p);
	float alpha = v_data.y;
	float level = v_data.z;

	if (v_data.x < -0.5) {
		// Облачко: мягкая дымка цвета материала и несколько медленно кружащих искр.
		vec3 base = level > 1.5 ? mix(v_color.rgb, level_tint(level).rgb, 0.45) : v_color.rgb;
		float haze = exp(-d * d * 1.1);
		vec4 col = vec4(base * 0.9, haze * 0.45);
		vec2 lit = normalize(light_dir);
		for (int i = 0; i < 7; i++) {
			float fi = float(i);
			float ang = v_data.w * 3.0 + fi * 2.4 + TIME * (0.08 + 0.04 * fract(fi * 0.37));
			float rad = 0.15 + 0.75 * fract(sin(v_data.w * 12.9 + fi * 78.2) * 437.5);
			vec2 sp = vec2(cos(ang), sin(ang)) * rad;
			float spark = exp(-dot(p - sp, p - sp) * 90.0);
			float side = 0.55 + 0.45 * dot(normalize(sp + 0.001), lit);
			col.rgb += base * star_light * spark * side * 1.8;
			col.a = max(col.a, spark * 0.9);
		}
		col.rgb = mix(col.rgb, ember(v_glow), haze * v_glow * 0.6);
		col.a *= alpha < 0.9 ? 0.45 : 1.0;
		COLOR = col;
	} else if (simple) {
		// Крапинка рядом с крупным телом: серая крошка породы с лёгким оттенком
		// вещества, без цветного ореола (это не угольки, ничего не раскалено).
		vec3 base = level > 1.5 ? mix(v_color.rgb, level_tint(level).rgb, 0.5) : v_color.rgb;
		base = mix(base, vec3(dot(base, vec3(0.33))) + 0.12, 0.8);
		float core = exp(-d * d * 5.0);
		float g = 1.0 - smoothstep(0.0, GLOW * 0.6, d);
		vec4 col = vec4(base * star_light * 0.95, max(core, g * g * 0.08) * alpha);
		col.rgb = mix(col.rgb, ember(v_glow), v_glow * 0.7);
		COLOR = col;
	} else {
		// Свечение цвета материала, чтобы мелкая пыль читалась на тёмном фоне.
		float g = 1.0 - smoothstep(0.0, GLOW, d);
		// Ореол цвета материала: еду видно издалека и не спутать со звездой.
		vec4 col = vec4(v_color.rgb, (g * g * 0.3 + g * 0.16) * (alpha > 0.9 ? 1.0 : 0.38));

		// Спрайт поворачивается со своей скоростью, она выводится из начального угла.
		float phase = v_data.w;
		float spin = (fract(phase * 13.7) - 0.5) * 1.2;
		float a = phase + spin * TIME;
		float c = cos(a);
		float s = sin(a);
		vec2 sp = vec2(c * p.x - s * p.y, s * p.x + c * p.y) / SPRITE + 0.5;
		if (sp.x > 0.0 && sp.x < 1.0 && sp.y > 0.0 && sp.y < 1.0) {
			vec2 cell = vec2(mod(v_data.x, 4.0), floor(v_data.x / 4.0));
			vec4 tex = texture(atlas, (cell + sp) * 0.25);
			tex.a *= alpha;
			// Освещение звездой: зерно как шар, светлая сторона смотрит на звезду, обратная в тени.
			// Звезда лежит в плоскости диска, поэтому свет почти сбоку и граница тени резкая.
			vec2 q = p / (SPRITE * 0.4);
			vec3 n = vec3(q, sqrt(max(1.0 - dot(q, q), 0.0)));
			n = normalize(n + vec3(0.0, 0.0, 0.05));
			float diff = max(dot(n, normalize(vec3(light_dir, 0.25))), 0.0);
			tex.rgb *= star_light * (0.18 + 1.4 * diff);
			// Тление у звезды: зерно светится само, сильнее с горячей стороны.
			tex.rgb += ember(v_glow) * v_glow * (0.6 + 0.6 * diff) * 0.9;

			// Блик: при вращении грань на миг ловит свет звезды. Лёд блестит чаще и голубее.
			// У снеговой линии на любой пыли намерзает иней и блестит как лёд.
			bool ice = v_data.x >= 11.5 || v_frost > 0.45;
			float facets = ice ? 5.0 : 3.0;
			float glint = pow(max(sin(a * facets + phase * 7.0), 0.0), ice ? 40.0 : 90.0);
			vec2 spot = normalize(light_dir) * 0.6;
			vec2 dp = p - spot;
			float star4 = max(0.0, 1.0 - abs(dp.x) * 6.0 - abs(dp.y) * 0.9) + max(0.0, 1.0 - abs(dp.y) * 6.0 - abs(dp.x) * 0.9);
			float core = exp(-dot(dp, dp) * 30.0);
			float sparkle = glint * (core * 1.5 + star4 * 0.8) * alpha;
			vec3 glint_col = ice ? vec3(0.75, 0.9, 1.0) : vec3(1.0, 0.95, 0.85);
			// Иней: голубоватая каёмка на освещённом краю.
			float rim = pow(1.0 - n.z, 2.0) * diff;
			float lum = dot(tex.rgb, vec3(0.3, 0.5, 0.2));
			tex.rgb = mix(tex.rgb, vec3(0.8, 0.9, 1.0) * (lum * 1.3 + 0.05), v_frost * 0.45);
			tex.rgb += vec3(0.55, 0.75, 1.0) * v_frost * rim * 1.4;
			if (ice) {
				// Иней мерцает мелкой рябью.
				float shimmer = 0.5 + 0.5 * sin(TIME * 3.0 + phase * 20.0 + (sp.x + sp.y) * 18.0);
				tex.rgb += vec3(0.25, 0.35, 0.45) * shimmer * shimmer * diff * 0.35;
			}

			col.rgb = mix(col.rgb, tex.rgb, tex.a);
			col.a = tex.a + col.a * (1.0 - tex.a);
			col.rgb += glint_col * star_light * sparkle;
			col.a = max(col.a, clamp(sparkle, 0.0, 1.0));
		}
		// Ореол тления вокруг нагретой пылинки.
		col.rgb = mix(col.rgb, ember(v_glow), g * g * v_glow * 0.6);
		col.a = max(col.a, g * g * v_glow * 0.5);

		// Кольцо уровня: у пыли выше первого уровня и у недоступной. Толщина ~1.5 px на экране.
		if (level > 1.5 || alpha < 0.9) {
			float w = fwidth(d) * 1.5;
			float ring = 1.0 - smoothstep(0.0, w, abs(d - RING));
			vec4 rc = level_tint(level);
			float ra = ring * (alpha < 0.9 ? 0.5 : 0.6);
			col.rgb = mix(col.rgb, rc.rgb, ra);
			col.a = ra + col.a * (1.0 - ra);
		}
		COLOR = col;
	}
}
