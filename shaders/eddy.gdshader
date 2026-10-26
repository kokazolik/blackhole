shader_type canvas_item;
// Вихрь турбулентности: газ с пылью закручен вокруг центра. Внутренние слои
// вращаются быстрее внешних (профиль как у eddy_flow), поэтому узор сам
// наматывается в спираль. Чтобы за полминуты он не свернулся в тугую пружину,
// течение «перезапускается» двумя фазами, которые плавно сменяют друг друга.
//
// Квадрат стороной 2·EXTENT радиусов вихря; r = 1 — край вихря.

uniform float t = 0.0;       // время с начала вихря, с
uniform float fade = 1.0;    // появление и угасание
uniform vec3 tint : source_color = vec3(0.95, 0.8, 0.62);
uniform float seed = 0.3;

const float EXTENT = 1.3;
const float SPIN = 0.55;     // рад/с в самом быстром месте
const float CYCLE = 7.0;     // период перезапуска течения, с

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 57.3) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * noise(p);
		p = p * 2.07 + vec2(3.1, 7.7);
		a *= 0.5;
	}
	return v;
}

// Газ в одной фазе течения: облака плюс тонкие струи вдоль потока.
vec2 layer(float r, float th, float phase, float base) {
	float w = exp(1.0 - 2.0 * r * r);  // угловая скорость: быстрее у центра
	float a = th + SPIN * w * phase + base;
	vec2 q = vec2(cos(a), sin(a)) * r;
	float cloud = fbm(q * 2.6 + vec2(seed * 9.0, 0.0));
	// Струи: шум, растянутый вдоль окружностей (по радиусу меняется быстро,
	// по кругу медленно; через cos/sin, чтобы не было шва на стыке углов).
	float lane = noise(vec2(cos(a), sin(a)) * 1.6 + vec2(r * 12.0, r * 7.0) + seed * 4.0);
	float streak = pow(1.0 - abs(lane * 2.0 - 1.0), 8.0);
	return vec2(cloud, streak);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0 * EXTENT;
	float r = length(p);
	if (r > EXTENT) {
		discard;
	}
	float th = atan(p.y, p.x);
	// Две фазы течения со сдвигом в полцикла: пока одна «перезапускается», видна другая.
	float ph1 = mod(t, CYCLE);
	float ph2 = mod(t + CYCLE * 0.5, CYCLE);
	float k = abs(ph1 / CYCLE * 2.0 - 1.0);  // 1 у перезапуска первой фазы
	// Медленное общее вращение, чтобы смена фаз не смотрелась как топтание на месте.
	float spin_all = 0.12 * t;
	vec2 g = mix(layer(r, th, ph1, spin_all), layer(r, th, ph2, spin_all + 1.7), k);

	// Спиральные рукава поверх облаков.
	float arms = 0.55 + 0.45 * sin(3.0 * (th + spin_all * 1.6) + 5.0 * log(r + 0.08));
	float body = smoothstep(EXTENT, 0.55, r) * smoothstep(0.05, 0.35, r);  // край и «глаз»
	float dens = smoothstep(0.32, 0.8, g.x) * (0.45 + 0.55 * arms) * body;
	float streak = g.y * smoothstep(0.2, 0.7, g.x) * body;

	vec3 col = tint * (0.55 + 0.6 * dens) + vec3(1.0, 0.97, 0.9) * streak * 0.6;
	// Еле заметное тёмное кольцо пыли по краю: видно, где кончается течение.
	float rim = exp(-pow((r - 1.0) * 7.0, 2.0)) * 0.12;
	float alpha = clamp(dens * 0.42 + streak * 0.35 + rim, 0.0, 0.75) * fade;
	if (alpha < 0.004) {
		discard;
	}
	COLOR = vec4(col, alpha);
}
