shader_type canvas_item;
// Чужая галька из атласа для MultiMesh: освещена звездой как шар, медленно вращается,
// у снеговой линии покрывается инеем, у звезды тлеет.
//
// INSTANCE_CUSTOM: x — клетка атласа, y — угол поворота, z — 0,
//                  w — 1 у жеоды: сквозь трещины сверкают кристаллы, вокруг золотистый ореол;
//                  2 + доля — обломок; −(1 + доля) — бугристый валун (форма по доле).

uniform sampler2D atlas : filter_linear_mipmap;
uniform vec2 light_dir = vec2(-1.0, 0.0);
uniform vec3 star_light : source_color = vec3(1.0, 0.9, 0.75);
uniform float star_radius = 2000.0;
uniform float heat_start = 1.75;
uniform float snow_line = 6800.0;
uniform float snow_width = 700.0;
// Отдельно нарисованное сколотое тело или его кусок (не MultiMesh). Данные те
// же, что в INSTANCE_CUSTOM, плюс грани: выпуклые ячейки как полуплоскости
// (xy — нормаль наружу, z — отступ, w — номер ячейки) в осях текстуры тела.
// Режим 1 — тело с выемками на месте ячеек, 2 — кусок, сама ячейка.
uniform bool solo = false;
uniform vec4 solo_data = vec4(0.0);
uniform vec2 t_origin = vec2(0.0);
uniform float t_scale = 2.8;
uniform int solo_mode = 0;
uniform vec4 planes[48];
uniform int plane_count = 0;

varying vec4 v_data;
varying float v_glow;
varying float v_frost;

void vertex() {
	v_data = solo ? solo_data : INSTANCE_CUSTOM;
	vec2 world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	float heat = clamp((heat_start - length(world) / star_radius) / (heat_start - 1.0), 0.0, 1.0);
	float temp = 300.0 + 2700.0 * pow(heat, 1.3);
	v_glow = clamp((temp - 800.0) / 600.0, 0.0, 1.0);
	float ds = (length(world) - snow_line) / snow_width;
	v_frost = exp(-ds * ds);
}

float rnd(float x) {
	return fract(sin(x * 78.233) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = fract(sin(dot(i, vec2(127.1, 311.7))) * 43758.5453);
	float b = fract(sin(dot(i + vec2(1.0, 0.0), vec2(127.1, 311.7))) * 43758.5453);
	float d = fract(sin(dot(i + vec2(0.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	float g = fract(sin(dot(i + vec2(1.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	return mix(mix(a, b, u.x), mix(d, g, u.x), u.y);
}

float h2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Ячейки Вороного: x — разница расстояний до двух ближайших точек (у границы 0),
// yz — номер ячейки.
vec3 shard_vor(vec2 x) {
	vec2 xi = floor(x);
	vec2 xf = fract(x);
	float f1 = 8.0;
	float f2 = 8.0;
	vec2 id = xi;
	for (int y = -1; y <= 1; y++) {
		for (int xx = -1; xx <= 1; xx++) {
			vec2 g = vec2(float(xx), float(y));
			vec2 o = vec2(h2(xi + g + 3.3), h2(xi + g + 9.1));
			float d = length(g + o - xf);
			if (d < f1) {
				f2 = f1;
				f1 = d;
				id = xi + g;
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	return vec3(f2 - f1, id);
}

// Контур обломка: выпуклый многоугольник из плоскостей излома, вытянутый
// (оси примерно 1 : 0,7), с рваным краем. У части обломков одна сторона —
// дуга прежней округлой поверхности (crust = 1 на ней).
float shard_sd(vec2 q, float s, out float crust) {
	q *= vec2(0.8 + 0.15 * rnd(s * 7.31), 1.1 + 0.35 * rnd(s * 3.17));
	float nv = 4.0 + floor(rnd(s * 5.71) * 4.0);
	bool has_crust = rnd(s * 11.3) < 0.6;
	float sd = -10.0;
	crust = 0.0;
	for (int i = 0; i < 7; i++) {
		float k = float(i);
		if (k >= nv) {
			break;
		}
		float hh = rnd(k + s * 17.0);
		float ang = k * 6.2832 / nv + (hh - 0.5) * 0.8;
		vec2 n = vec2(cos(ang), sin(ang));
		float dist = 0.6 + 0.3 * rnd(hh * 9.7 + 1.0);
		float v = dot(q, n) - dist;
		if (i == 0 && has_crust) {
			float rc = 1.3;
			v = length(q + n * (rc - dist)) - rc;
		}
		if (v > sd) {
			sd = v;
			crust = (i == 0 && has_crust) ? 1.0 : 0.0;
		}
	}
	// Выщерблины по краю: крупные и мелкие.
	sd += (vnoise(q * 6.0 + s * 31.0) - 0.5) * 0.09 + (vnoise(q * 15.0 + s * 13.0) - 0.5) * 0.035;
	return sd;
}

// Высота поверхности обломка.
float shard_h(vec2 q, float s, out float crust) {
	float sd = shard_sd(q, s, crust);
	float d = -sd;
	// Крыша: несколько плоскостей излома под разными наклонами, сходятся рёбрами.
	float top = 10.0;
	for (int j = 0; j < 4; j++) {
		float fj = float(j);
		float a = 6.2832 * rnd(s * 29.0 + fj * 3.3);
		float g = 0.25 + 0.4 * rnd(s * 41.0 + fj * 5.1);
		top = min(top, 0.5 + 0.12 * rnd(s * 53.0 + fj) - dot(q, vec2(cos(a), sin(a)) * g));
	}
	// Боковые сколы крутые, старая поверхность скатывается полого и округло.
	float side = crust > 0.5 ? sqrt(max(d, 0.0) * 0.5) : d * 1.8;
	float h = min(top, side);
	// Зернистость породы.
	h += (vnoise(q * 9.0 + s * 7.0) - 0.5) * 0.035 + (vnoise(q * 24.0 + s * 3.0) - 0.5) * 0.014;
	return h;
}

// Валун метрового размера: не шар, а бугристая глыба. Контур — сумма нескольких
// гармоник по углу, рельеф — купол, срезанный пологими гранями, с буграми.
float lump_sd(vec2 q, float s) {
	float ang = atan(q.y, q.x);
	float rr = 0.88 + 0.07 * sin(2.0 * ang + s * 6.3) + 0.045 * sin(3.0 * ang + s * 11.1)
			+ 0.025 * sin(5.0 * ang + s * 17.7) + 0.012 * sin(9.0 * ang + s * 29.3);
	float sd = length(q) - rr;
	sd += (vnoise(q * 6.0 + s * 31.0) - 0.5) * 0.05 + (vnoise(q * 15.0 + s * 13.0) - 0.5) * 0.02;
	return sd;
}

float lump_h(vec2 q, float s) {
	float d = -lump_sd(q, s);
	float dome = sqrt(max(d, 0.0) * 1.6);
	float top = 10.0;
	for (int j = 0; j < 4; j++) {
		float fj = float(j);
		float a = 6.2832 * rnd(s * 29.0 + fj * 3.3);
		float g = 0.15 + 0.25 * rnd(s * 41.0 + fj * 5.1);
		top = min(top, 0.85 + 0.15 * rnd(s * 53.0 + fj) - dot(q, vec2(cos(a), sin(a)) * g));
	}
	float h = min(dome, top);
	h += (vnoise(q * 2.6 + s * 9.0) - 0.5) * 0.18 + (vnoise(q * 9.0 + s * 7.0) - 0.5) * 0.035
			+ (vnoise(q * 24.0 + s * 3.0) - 0.5) * 0.014;
	return h;
}

// Вид вещества поверх атласа, по снимкам Итокавы, Рюгу и ядер комет. Камень
// серо-бурый, а не золотой (насыщенность оставляем, убираем «металл»).
// Углистое — почти уголь со светлыми вкраплениями (хондры и CAI, как на Рюгу).
// Лёд у снеговой линии грязный: перемешан с пылью, голубоватый лишь местами.
// Россыпь круглых крапинок: в части ячеек сетки по одной точке случайного размера.
float spots(vec2 x, float share, float rad) {
	vec2 i = floor(x);
	vec2 f = fract(x);
	if (h2(i + 1.7) > share) {
		return 0.0;
	}
	vec2 c = 0.25 + 0.5 * vec2(h2(i + 4.1), h2(i + 8.3));
	float r = rad * (0.4 + 0.9 * h2(i + 2.9));
	return 1.0 - smoothstep(r * 0.45, r, length(f - c));
}

// Налёт тончайшей пыли на старой поверхности: светлее, серее и матовее. Внутри
// газового диска звёздный ветер камней не достаёт, «выветривания» тут нет:
// разницу между коркой и свежим сколом даёт именно пыль. Лёд налёт пачкает.
vec3 dust_coat(vec3 alb, int mat) {
	float l = dot(alb, vec3(0.33));
	if (mat == 3) {
		return alb;
	}
	return mix(alb, vec3(l) * vec3(1.04, 1.0, 0.95) * 1.12 + 0.03, 0.3);
}

vec3 material_look(vec3 alb, int mat, vec2 q, float s) {
	float l = dot(alb, vec3(0.33));
	if (mat == 0) {
		alb = mix(alb, vec3(l) * vec3(1.06, 0.97, 0.86), 0.3);
	} else if (mat == 1) {
		alb = mix(alb, vec3(l) * vec3(0.98, 0.99, 1.04), 0.25);
	} else if (mat == 2) {
		float inc = spots(q * 7.0 + s * 3.7, 0.35, 0.16) + 0.7 * spots(q * 15.0 + s * 1.9, 0.3, 0.12);
		alb = mix(alb * 0.85, vec3(0.64, 0.63, 0.58), clamp(inc, 0.0, 1.0) * 0.6);
	} else {
		float dirt = smoothstep(0.3, 0.75, vnoise(q * 3.0 + s * 5.1)) * 0.7 + 0.25 * vnoise(q * 12.0 + s);
		alb = mix(alb * vec3(0.92, 0.97, 1.0), vec3(0.3, 0.29, 0.28), clamp(dirt, 0.0, 0.85));
	}
	return alb;
}

// Металлические крупинки: у металлических тел их много, у каменных единицы.
float metal_glint(vec2 q, int mat, float s) {
	float share = mat == 1 ? 1.0 : (mat == 0 ? 0.25 : 0.0);
	return step(0.9 - 0.06 * share, vnoise(q * 30.0 + s * 7.0)) * share * 1.4;
}

void fragment() {
	vec2 p = UV - 0.5;
	float a = v_data.y;
	float c = cos(a);
	float s = sin(a);
	vec2 sp = vec2(c * p.x - s * p.y, s * p.x + c * p.y) + 0.5;
	if (solo) {
		// Квадрат куска может стоять не в центре тела: идём в оси текстуры тела.
		vec2 qt0 = t_origin + (sp - 0.5) * t_scale;
		sp = qt0 * 0.36 + 0.5;
		vec2 d0 = sp - 0.5;
		p = vec2(c * d0.x + s * d0.y, -s * d0.x + c * d0.y);
	}
	vec2 cell = vec2(mod(v_data.x, 4.0), floor(v_data.x / 4.0));
	vec4 tex = texture(atlas, (cell + clamp(sp, 0.0, 1.0)) * 0.25);
	int mat = int(cell.y);  // 0 камень, 1 металл, 2 углерод, 3 лёд
	// Галька занимает ~72% квадрата: нормаль как у шара этого радиуса.
	vec2 q = p / 0.36;
	vec3 n = normalize(vec3(q, sqrt(max(1.0 - dot(q, q), 0.0)) + 0.05));
	float diff = max(dot(n, normalize(vec3(light_dir, 0.25))), 0.0);
	// Тон и силуэт берём из атласа, а мелкий рисунок — свой: нарисованные в атласе
	// кольца читались как кратеры, а у сантиметровой гальки в диске их нет.
	// Атлас размытый (дальний мип), поверх — зерно и хондры: сплошные светлые
	// круглые капли с мягким краем, как в разрезе хондрита.
	vec2 uvc = (cell + clamp(sp, 0.0, 1.0)) * 0.25;
	vec4 soft = textureLod(atlas, uvc, 3.0);
	vec3 tone = soft.rgb / max(soft.a, 0.05);
	vec2 qs = (sp - 0.5) / 0.36;
	float fine = clamp(1.4 - fwidth(qs.x) * 10.0, 0.0, 1.0);
	tone *= 1.0 + (vnoise(qs * 13.0 + v_data.x * 3.1) - 0.5) * 0.35 * fine + (vnoise(qs * 4.0 + v_data.x) - 0.5) * 0.25;
	float chond_share = mat == 0 ? 0.5 : (mat == 2 ? 0.3 : (mat == 1 ? 0.15 : 0.0));
	// Хондры плотно и разного размера, под пылевым налётом — без резкого контраста.
	float chond = max(spots(qs * 4.0 + v_data.x * 5.3, chond_share, 0.34),
			0.8 * spots(qs * 8.5 + v_data.x * 2.1, chond_share * 0.9, 0.3)) * fine;
	tone = mix(tone, mix(tone, vec3(0.78, 0.76, 0.64), 0.4) * 1.08, chond * 0.8);
	vec3 alb0 = dust_coat(material_look(tone, mat, qs, v_data.x), mat);
	vec3 col = alb0 * star_light * (0.1 + 1.6 * diff);
	// Реголит матовый, общего блика нет. Блестят только металлические крупинки.
	vec3 h = normalize(normalize(vec3(light_dir, 0.25)) + vec3(0.0, 0.0, 1.0));
	col += metal_glint((sp - 0.5) / 0.36, mat, v_data.x) * star_light * pow(max(dot(n, h), 0.0), 8.0) * diff;
	// Иней у снеговой линии и тление у звезды.
	float lum = dot(col, vec3(0.3, 0.5, 0.2));
	col = mix(col, vec3(0.82, 0.92, 1.0) * (lum * 1.2 + 0.05), v_frost * 0.4);
	col += mix(vec3(0.5, 0.05, 0.0), vec3(1.0, 0.45, 0.08), v_glow) * v_glow * (0.5 + 0.6 * diff);
	vec4 outc = vec4(col, tex.a);
	if (v_data.w > 1.5 || v_data.w < -0.5) {
		bool lumpy = v_data.w < -0.5;
		// Обломок после удара. Как в опытах по разрушению и как валуны на Итокаве
		// и Рюгу: угловатый, вытянутый, с плоскими гранями излома, рваным краем
		// и той же зернистой породой, что у тела, от которого он откололся.
		// Рисуем рельеф высотой: крыша из нескольких плоскостей излома, крутые
		// боковые сколы, мелкая зернистость; нормаль берём из рельефа.
		float sd0 = fract(abs(v_data.w));
		vec2 q = (sp - 0.5) / 0.36;
		float e = 0.025;
		float on_crust = 1.0;
		float tmp;
		float hc;
		float hx;
		float hy;
		float sd;
		if (lumpy) {
			hc = lump_h(q, sd0);
			hx = lump_h(q + vec2(e, 0.0), sd0) - hc;
			hy = lump_h(q + vec2(0.0, e), sd0) - hc;
			sd = lump_sd(q, sd0);
		} else {
			hc = shard_h(q, sd0, on_crust);
			hx = shard_h(q + vec2(e, 0.0), sd0, tmp) - hc;
			hy = shard_h(q + vec2(0.0, e), sd0, tmp) - hc;
			sd = shard_sd(q, sd0, tmp);
		}
		float aa = fwidth(q.y) * 1.2;
		float mask = 1.0 - smoothstep(-aa, aa, sd);
		vec3 nl = normalize(vec3(-hx / e, -hy / e, 1.0));
		// Нормаль считалась в повёрнутых координатах обломка: возвращаем на экран.
		vec3 nrm = vec3(c * nl.x + s * nl.y, -s * nl.x + c * nl.y, nl.z);
		vec3 ld = normalize(vec3(light_dir, 0.25));
		float diff = max(dot(nrm, ld), 0.0);
		// Порода: тот же атлас и тот же масштаб зерна, что у гальки.
		vec2 tq = q * 0.3;
		tq *= min(1.0, 0.33 / max(length(tq), 0.001));
		vec3 raw = texture(atlas, (cell + 0.5 + tq) * 0.25).rgb;
		vec3 alb = material_look(raw, mat, q, sd0 * 13.0);
		// Свежий излом без пылевого налёта: порода темнее и насыщеннее корки,
		// а кристаллы на нём искрят. Лёд наоборот: внутри чистый, скол яркий.
		vec3 fresh;
		if (mat == 3) {
			fresh = mix(raw, vec3(0.8, 0.88, 0.96), 0.35) * 0.9;
		} else {
			float l = dot(alb, vec3(0.33));
			fresh = max(mix(vec3(l), alb, 1.25), vec3(0.0)) * 0.88;
		}
		vec3 crust = dust_coat(alb, mat);
		alb = lumpy ? crust : mix(fresh, crust, on_crust);
		// Та же порода, что у валуна: угловатые вкрапления другого тона,
		// трещины и поры. На мелком обломке детали гаснут, чтобы не рябить.
		float fine = clamp(1.4 - fwidth(q.x) * 12.0, 0.0, 1.0);
		vec3 cv = shard_vor(q * 3.2 + sd0 * 37.0);
		float is_clast = step(h2(cv.yz + 2.2), 0.3);
		float tone = h2(cv.yz + 5.5);
		alb *= mix(1.0, mix(0.7, 1.25, tone), is_clast * smoothstep(0.02, 0.07, cv.x) * fine);
		alb *= 1.0 - 0.3 * is_clast * (1.0 - smoothstep(0.0, 0.04, cv.x)) * fine;
		vec2 kq = q * 1.7 + sd0 * 23.0 + (vec2(vnoise(q * 2.5), vnoise(q * 2.5 + 5.2)) - 0.5) * 0.7;
		float crack = (1.0 - smoothstep(0.0, 0.05, shard_vor(kq).x)) * smoothstep(0.35, 0.6, vnoise(q * 3.0 + sd0 * 9.0));
		alb *= 1.0 - 0.65 * crack * fine;
		alb *= 1.0 - 0.4 * smoothstep(0.8, 0.88, vnoise(q * 14.0 + sd0 * 61.0)) * fine;
		vec3 scol = alb * star_light * (0.1 + 1.75 * diff);
		scol += metal_glint(q, mat, sd0 * 11.0) * star_light * pow(diff, 3.0) * 0.8;
		// Мелкие кристаллики на свежем сломе искрят под прямым светом.
		float gl = step(0.93, vnoise(q * 26.0 + sd0 * 50.0)) * (1.0 - on_crust);
		scol += star_light * gl * pow(diff, 2.0) * 0.45;
		// Лёгкое затенение у самого края: обломок не кажется вырезанным из бумаги.
		scol *= 0.8 + 0.2 * clamp(-sd * 6.0, 0.0, 1.0);
		scol = mix(scol, vec3(0.82, 0.92, 1.0) * (dot(scol, vec3(0.3, 0.5, 0.2)) * 1.2 + 0.05), v_frost * 0.4);
		scol += mix(vec3(0.5, 0.05, 0.0), vec3(1.0, 0.45, 0.08), v_glow) * v_glow * (0.5 + 0.6 * diff);
		outc = vec4(scol, mask);
	}
	if (solo && plane_count > 0) {
		// Выемка на месте отколотых кусков и сами куски — одна и та же порода:
		// тот же тон из атласа, зерно и хондры, но без пыльного налёта. Стенка
		// излома — склон в глубь выемки со своим светом; к корке она переходит
		// плавно, ребро — тонкое и неровное, как у настоящего скола.
		vec2 qt = (sp - 0.5) / 0.36;
		float aa = fwidth(qt.x) * 1.2;
		float best = 1e3;
		vec2 bn = vec2(1.0, 0.0);
		float cur = -1e3;
		vec2 cn = vec2(1.0, 0.0);
		float cid = planes[0].w;
		for (int i = 0; i < 48; i++) {
			if (i >= plane_count) {
				break;
			}
			vec4 pl = planes[i];
			if (pl.w != cid) {
				if (cur < best) {
					best = cur;
					bn = cn;
				}
				cur = -1e3;
				cid = pl.w;
			}
			float dk = dot(qt, pl.xy) - pl.z;
			if (dk > cur) {
				cur = dk;
				cn = pl.xy;
			}
		}
		if (cur < best) {
			best = cur;
			bn = cn;
		}
		// Рваный край: излом не по линейке.
		// Мелкие детали гасим, когда тело мелкое на экране: иначе рябят пиксели.
		float fine_c = clamp(1.2 - fwidth(qt.x) * 40.0, 0.0, 1.0);
		float jag = (vnoise(qt * 9.0 + v_data.x * 2.3) - 0.5) * 0.05 + (vnoise(qt * 26.0 + v_data.x) - 0.5) * 0.018 * fine_c;
		float sd = best + jag;
		// dist — глубина внутрь оставшейся породы от линии излома.
		float dist = solo_mode == 1 ? sd : -sd;
		vec2 face = solo_mode == 1 ? -bn : bn;  // куда смотрит стенка излома
		float keep = smoothstep(-aa, aa, dist);
		float wide = 0.07 + 0.06 * vnoise(qt * 3.0 + v_data.x * 7.0);
		float k_wall = 1.0 - smoothstep(wide * 0.55, wide, dist);
		if (k_wall > 0.0) {
			// Склон стенки: у ребра круче, к дну выемки положе; поверх — рябь
			// раковистого излома и зерно породы как нормаль.
			float tilt = mix(1.3, 0.5, clamp(dist / wide, 0.0, 1.0));
			float e = 0.02;
			float g0 = vnoise(qt * 14.0 + v_data.x * 3.3);
			float gx = vnoise((qt + vec2(e, 0.0)) * 14.0 + v_data.x * 3.3) - g0;
			float gy = vnoise((qt + vec2(0.0, e)) * 14.0 + v_data.x * 3.3) - g0;
			float rip = sin(dist * 90.0 + vnoise(qt * 5.0) * 6.0) * 0.08 * fine_c;
			vec3 wn = normalize(vec3(face * (tilt + rip), 1.0) - vec3(gx, gy, 0.0) / e * 0.08 * fine_c);
			vec3 ws = vec3(c * wn.x + s * wn.y, -s * wn.x + c * wn.y, wn.z);
			float wdiff = max(dot(ws, normalize(vec3(light_dir, 0.25))), 0.0);
			// Та же порода, что под коркой: тон и хондры тела, без налёта.
			vec3 fresh = material_look(tone, mat, qs, v_data.x);
			if (mat == 3) {
				fresh = mix(fresh, vec3(0.8, 0.88, 0.96), 0.3);
			} else {
				float fl = dot(fresh, vec3(0.33));
				fresh = max(mix(vec3(fl), fresh, 1.2), vec3(0.0)) * 0.8;
			}
			vec3 wcol = fresh * star_light * (0.1 + 1.6 * wdiff);
			wcol += star_light * step(0.93, vnoise(qt * 34.0 + v_data.x * 5.0)) * pow(wdiff, 2.0) * 0.35 * fine_c;
			wcol += metal_glint(qt, mat, v_data.x * 11.0) * star_light * pow(wdiff, 3.0) * 0.6;
			wcol = mix(wcol, vec3(0.82, 0.92, 1.0) * (dot(wcol, vec3(0.3, 0.5, 0.2)) * 1.2 + 0.05), v_frost * 0.4);
			wcol += mix(vec3(0.5, 0.05, 0.0), vec3(1.0, 0.45, 0.08), v_glow) * v_glow * (0.5 + 0.6 * wdiff);
			outc.rgb = mix(outc.rgb, wcol, k_wall);
		}
		outc.a *= keep;
	}
	if (v_data.w > 0.5 && v_data.w < 1.5) {
		// Жеода: кристаллы вспыхивают по очереди, вокруг мягкий ореол.
		vec3 gold = vec3(1.0, 0.85, 0.4);
		float cells = 0.0;
		for (int i = 0; i < 5; i++) {
			float fi = float(i);
			vec2 c2 = vec2(sin(fi * 2.4 + 0.7), cos(fi * 1.7 + 0.3)) * 0.22;
			float tw = pow(max(sin(mod(TIME, 28.56) * 2.2 + fi * 1.9), 0.0), 6.0);
			cells += exp(-dot(sp - 0.5 - c2, sp - 0.5 - c2) * 900.0) * (0.4 + 1.6 * tw);
		}
		outc.rgb += gold * cells * tex.a;
		// Ореол гаснет до нуля, не доходя до края квадрата: иначе на некоторых
		// телефонах квадрат проступал золотой плашкой.
		float d = length(p) / 0.36;
		float pulse = 0.55 + 0.25 * sin(mod(TIME, 6.2832) * 3.0);
		float halo = exp(-max(d - 0.9, 0.0) * 4.0) * pulse * (1.0 - smoothstep(1.0, 1.35, d));
		outc.rgb = mix(gold, outc.rgb, tex.a);
		outc.a = max(tex.a, halo * 0.6 * (1.0 - tex.a));
	}
	if (outc.a < 0.004) {
		discard;
	}
	COLOR = outc;
}
