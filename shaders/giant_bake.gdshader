shader_type canvas_item;
// Странник — огромный валун, по снимкам Бенну (OSIRIS-REx) и Рюгу (Hayabusa2).
// Что делает их настоящими и что здесь повторено:
// • очень тёмный нейтрально-серый камень (альбедо 3–15%), без пёстрого цвета;
// • рельеф на всех масштабах: бугры, торчащие глыбы, бороздки, а не плоские грани;
// • редкие, но глубокие трещины с тенью внутри, а не сеточка тонких линий;
// • брекчия: светлые обломки-включения в тёмной матрице;
// • в пустоте нет рассеянного света: резкий терминатор, длинные тени от
//   неровностей при низком солнце, ночная сторона почти чёрная;
// • неровный, бугристый силуэт с отдельными выступающими блоками.
// Этот шейдер дорогой (шум Вороного, гребни, трещины), поэтому он рисуется один
// раз при появлении в текстуру (Giant: SubViewport), а свет и тени по ней
// считает дешёвый giant_rock.gdshader.
// Каналы: r — высота рельефа, g — альбедо (доля от ROCK), b — купол тела, a — силуэт.

uniform float seed = 0.37;

const float BODY = 0.36;  // радиус тела в долях квадрата (как у гальки: столкновение совпадает)

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 91.3) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p, int oct) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 6; i++) {
		if (i >= oct) break;
		v += a * noise(p);
		p = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6)) * p + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

// Острые гребни: бугристая, «цветная капуста» Бенну.
float ridged(vec2 p, int oct) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		if (i >= oct) break;
		float n = 1.0 - abs(noise(p) * 2.0 - 1.0);
		v += a * n * n;
		p = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6)) * p + vec2(5.1, 2.3);
		a *= 0.5;
	}
	return v;
}

// Вороного: f1, f2 и случайное число ячейки.
vec3 voronoi(vec2 x) {
	vec2 xi = floor(x);
	vec2 xf = fract(x);
	float f1 = 8.0;
	float f2 = 8.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int xx = -1; xx <= 1; xx++) {
			vec2 g = vec2(float(xx), float(y));
			vec2 o = vec2(hash(xi + g + 3.3), hash(xi + g + 9.1));
			float d = length(g + o - xf);
			if (d < f1) {
				f2 = f1;
				f1 = d;
				id = hash(xi + g + 17.0);
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	return vec3(f1, f2, id);
}

// Силуэт: крупные бугры по углу плюс несколько плоскостей скола.
float edge_at(float th) {
	vec2 u = vec2(cos(th), sin(th));
	float e = 1.0 + 0.09 * sin(2.0 * th + seed * 6.0) + 0.05 * sin(3.0 * th + seed * 13.0);
	e += 0.16 * (fbm(u * 1.8 + seed * 7.0, 4) - 0.5);
	// Мелкие глыбы по краю: профиль бугристый, а не гладкий.
	e += 0.06 * (ridged(u * 7.0 + seed * 3.0, 4) - 0.5);
	// Две плоскости скола: срезают купол, но рёбра потом размывает рельеф.
	for (int k = 0; k < 2; k++) {
		float fk = float(k);
		float a = fk * 2.6 + seed * 5.0 + (hash(vec2(fk, 2.1)) - 0.5) * 1.0;
		float d = dot(u, vec2(cos(a), sin(a)));
		if (d > 0.2) {
			e = min(e, (0.95 + 0.1 * hash(vec2(fk, 7.7))) / d + 0.04 * (noise(u * 9.0 + fk) - 0.5));
		}
	}
	return e;
}

// Высота поверхности в точке p (координаты тела, радиус ~1).
// Крупные глыбы, гребни, мелкая шероховатость и редкие глубокие трещины.
float height(vec2 p, bool fine) {
	// Искривляем координаты: без этого ячейки выходят ровной «черепашьей» плиткой.
	vec2 w = p + 0.22 * (vec2(fbm(p * 2.1 + seed * 5.0, 3), fbm(p * 2.1 + seed * 8.0 + 3.1, 3)) - 0.5);
	// Глыбы, вросшие в тело: разного размера, со скруглённым краем, низкие.
	vec3 b = voronoi(w * 2.6 + seed * 11.0);
	float block = smoothstep(0.0, 0.35, b.y - b.x) * (0.3 + 0.7 * b.z);
	float h = block * 0.06;
	// Бугристость «цветной капусты» и мелкие наплывы.
	h += ridged(w * 4.0 + seed * 4.0, fine ? 4 : 2) * 0.08;
	h += (fbm(w * 1.3 + seed * 6.0, 3) - 0.5) * 0.12;
	if (fine) {
		h += fbm(p * 24.0 + seed * 9.0, 3) * 0.02;
	}
	// Трещины: несколько длинных разломов, а не сеть. Берём лишь часть рёбер
	// крупных ячеек и даём им прерываться.
	vec3 c = voronoi(w * 1.1 + seed * 23.0);
	float crack = 1.0 - smoothstep(0.0, 0.03, c.y - c.x);
	crack *= smoothstep(0.45, 0.7, fbm(w * 3.0 + seed * 13.0, 3));
	h -= crack * 0.07;
	return h;
}

void fragment() {
	vec2 p = (UV - 0.5) / BODY;
	float th = atan(p.y, p.x);
	float r = length(p);
	float edge = edge_at(th);
	float aa = fwidth(r) * 1.3;
	float alpha = 1.0 - smoothstep(edge - aa, edge + aa, r);
	vec2 q = p / edge;
	float dome = sqrt(max(1.0 - dot(q, q), 0.0));
	float h = height(p, true);
	// Альбедо: тёмная матрица с пятнами, блоки чуть различаются, светлые обломки
	// брекчии (как на Рюгу) почти вдвое светлее.
	vec2 w = p + 0.22 * (vec2(fbm(p * 2.1 + seed * 5.0, 3), fbm(p * 2.1 + seed * 8.0 + 3.1, 3)) - 0.5);
	vec3 b = voronoi(w * 2.6 + seed * 11.0);
	float alb = (0.85 + 0.25 * b.z) * (0.82 + 0.36 * fbm(p * 9.0 + seed * 2.0, 4));
	vec3 cl = voronoi(p * 26.0 + seed * 31.0);
	float clast = (1.0 - smoothstep(0.12, 0.2, cl.x)) * step(0.86, cl.z);
	alb = mix(alb, 2.0, clast * 0.75);
	// Дно трещин и впадин темнее: туда не доходит даже отражённый свет.
	alb *= clamp((h + 0.05) * 6.0, 0.35, 1.0);
	COLOR = vec4(h + 0.2, alb * 0.5, dome, alpha);
}
