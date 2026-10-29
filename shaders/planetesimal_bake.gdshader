shader_type canvas_item;
render_mode blend_disabled;  // пишем каналы как есть: в альфе лежит тон
// Планетезималь — тело в километр, по снимкам Бенну, Рюгу, Итокавы, Эроса и Аррокота.
// Что делает их настоящими и что здесь повторено:
// • форма уже не глыба, но и не шар: своя гравитация слабая, тело — комковатая
//   груда щебня, слегка вытянутая, с вмятинами от старых ударов;
// • кратеры всех размеров (крупных мало, мелких тьма): чаша, вал, выброс;
//   свежие — светлые, с лучами, старые — оплывшие и в тон поверхности;
// • глыбы, рассыпанные по склонам, и гладкие «пруды» мелкого реголита в низинах,
//   где глыб нет (как на Эросе и Итокаве);
// • космическое выветривание: старая поверхность темнее и краснее свежей.
// Это дорого, поэтому рельеф печётся один раз в развёртку сферы (долгота × широта),
// полосами по нескольку кадров, а свет, тени и поворот считает planetesimal.gdshader.
// Каналы: высота над единичной сферой = r + g / 64 (половинной точности одного
// канала мало: на пологом дне кратера свет ложился ступеньками; сумма каналов
// при сглаживании текстуры остаётся точной), b — свежесть (светлый выброс), a — тон камня.

uniform float seed = 0.37;
uniform vec4 region = vec4(0.0, 0.0, 1.0, 1.0);  // какую полосу развёртки рисует прямоугольник

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7)) + seed * 91.3) * 43758.5453);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), u.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), u.x), u.y),
			mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), u.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), u.x), u.y), u.z);
}

float fbm3(vec3 p, int oct) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 6; i++) {
		if (i >= oct) break;
		v += a * noise3(p);
		p = p * 2.07 + vec3(1.7, 9.2, 4.1);
		a *= 0.5;
	}
	return v;
}

// Кратеры одного масштаба: s — сколько ячеек на единицу радиуса, prob — доля занятых.
// Профиль по снимкам: чаша глубиной ~1/5 диаметра, приподнятый вал, выброс за валом.
void craters(vec3 d, float s, float prob, float tame, float ray_k, inout float h, inout float fresh) {
	vec3 x = d * s;
	vec3 xi = floor(x);
	for (int k = 0; k < 27; k++) {
		vec3 g = vec3(float(k % 3 - 1), float((k / 3) % 3 - 1), float(k / 9 - 1));
		vec3 cell = xi + g;
		if (hash3(cell + 0.7) > prob) continue;
		vec3 c = cell + 0.2 + 0.6 * vec3(hash3(cell + 3.1), hash3(cell + 5.3), hash3(cell + 7.9));
		// Кратер есть, только если центр ячейки лежит у самой поверхности. Центр
		// не двигаем: иначе он уходит из своей ячейки, и соседи его не видят —
		// кратер обрезается прямой линией.
		if (abs(length(c) - s) > 0.55) continue;
		vec3 v = x - c;
		float reach = 1.0 - smoothstep(1.0, 1.35, length(v));
		if (reach <= 0.0) continue;
		// Размеры по степенному закону: мелких больше.
		float rad = 0.16 + 0.32 * pow(hash3(cell + 11.3), 2.2);
		float dist = length(v) / rad;
		if (dist > 3.2) continue;
		float age = hash3(cell + 13.7);  // 0 — только что, 1 — древний
		float young = step(age, 0.22 * ray_k);
		float R = rad / s;
		float depth = R * (0.42 - 0.26 * age) * tame;
		float rim = R * (0.14 - 0.09 * age) * tame;
		float prof;
		if (dist < 1.0) {
			// Плоское дно у крупных и старых: чаша засыпана обвалами.
			prof = max(depth * (dist * dist - 1.0), -depth * (0.75 + 0.2 * age));
		} else {
			prof = rim * 0.35 * exp(-(dist - 1.0) * 2.4);
		}
		prof += rim * exp(-pow((dist - 1.0) / (0.2 + 0.1 * age), 2.0));
		h += prof * reach;
		// Свежий кратер: светлая чаша, выброс и лучи, гаснущие с расстоянием.
		if (young > 0.0) {
			vec3 nrm = normalize(c);
			vec3 a1 = normalize(cross(nrm, vec3(0.3, 1.0, 0.2)));
			vec3 a2 = cross(nrm, a1);
			float ang = atan(dot(v, a2), dot(v, a1));
			float rays = pow(noise3(vec3(cos(ang), sin(ang), 0.0) * 4.5 + cell * 1.3), 3.0) * 1.6;
			float f = dist < 1.0 ? 0.75 + 0.25 * (1.0 - dist) : exp(-(dist - 1.0) * 1.4) * (0.35 + 0.8 * rays);
			fresh = max(fresh, f * (1.0 - age * 3.0) * reach);
		}
	}
}

// Глыбы: округлые блоки, торчащие над реголитом. tone — их собственный оттенок.
void boulders(vec3 d, float s, float prob, float bare, inout float h, inout float tone) {
	vec3 x = d * s;
	vec3 xi = floor(x);
	float peak = 0.0;
	for (int k = 0; k < 27; k++) {
		vec3 g = vec3(float(k % 3 - 1), float((k / 3) % 3 - 1), float(k / 9 - 1));
		vec3 cell = xi + g;
		if (hash3(cell + 21.7) > prob) continue;
		vec3 c = cell + 0.15 + 0.7 * vec3(hash3(cell + 23.1), hash3(cell + 25.3), hash3(cell + 27.9));
		if (abs(length(c) - s) > 0.5) continue;
		vec3 v = x - c;
		// Чуть угловатая: расстояние по смеси евклидовой и «кубической» меры.
		vec3 av = abs(v);
		float boxy = max(av.x, max(av.y, av.z));
		float rad = 0.22 + 0.3 * pow(hash3(cell + 29.3), 1.6);
		float dist = mix(length(v), boxy * 1.25, 0.45) / rad;
		if (dist >= 1.0) continue;
		// Глыбы лежат, а не торчат иглами: высота меньше поперечника.
		float bh = rad / s * (0.3 + 0.25 * hash3(cell + 31.1)) * bare;
		float top = bh * sqrt(1.0 - dist * dist);
		if (top > peak) {
			peak = top;
			tone = mix(tone, hash3(cell + 33.3), step(0.02 * bh, top));
		}
	}
	h += peak;
}

void fragment() {
	vec2 uv = region.xy + UV * region.zw;
	float lon = (uv.x - 0.5) * TAU;
	float th = uv.y * PI;
	vec3 d = vec3(sin(th) * cos(lon), cos(th), sin(th) * sin(lon));

	// Форма: слегка вытянутая груда, плюс крупные бугры и вмятины.
	vec3 e = d / vec3(1.16, 0.86, 1.0);
	float h = 1.0 / length(e) - 1.0;
	float lump = fbm3(d * 1.15 + seed * 7.0, 3) * 2.0 - 1.0;
	h += 0.2 * lump + 0.07 * (fbm3(d * 2.6 + 3.0 + seed * 5.0, 3) * 2.0 - 1.0);
	// Пруды: в гравитационных низинах мелкий реголит стекает и всё засыпает.
	float pond = smoothstep(-0.08, -0.28, lump);
	float bare = 1.0 - pond;

	float fresh = 0.0;
	// Мелких кратеров на груде щебня мало: удар вязнет в рыхлом теле, сотрясения
	// засыпают их, поэтому мелкие слабее и реже, чем на Луне.
	// Свежих мелких мало заметно: их светлый выброс быстро выветривается.
	craters(d, 1.6, 0.55, 1.15, 1.0, h, fresh);
	craters(d, 3.4, 0.5, 1.0, 1.0, h, fresh);
	craters(d, 7.0, 0.6, 0.8 - 0.4 * pond, 0.6, h, fresh);
	craters(d, 14.0, 0.5, 0.6 - 0.5 * pond, 0.3, h, fresh);
	craters(d, 28.0, 0.25, 0.45 - 0.4 * pond, 0.15, h, fresh);

	// Тон: крупные пятна вещества и россыпь глыб на склонах.
	float tone = fbm3(d * 3.3 + 17.0 + seed * 3.0, 4);
	boulders(d, 22.0, 0.55, bare, h, tone);
	boulders(d, 45.0, 0.75, bare, h, tone);
	boulders(d, 90.0, 0.6, bare, h, tone);
	// Шероховатость щебня там, где нет пруда; пруд гладкий и чуть светлее.
	h += 0.005 * bare * (fbm3(d * 95.0, 3) - 0.5);
	tone = mix(tone, 0.62 + 0.08 * fbm3(d * 20.0, 2), pond * 0.7);

	float coarse = round(h * 64.0) / 64.0;
	COLOR = vec4(coarse, (h - coarse) * 64.0, clamp(fresh, 0.0, 1.0), clamp(tone, 0.0, 1.0));
}
