shader_type canvas_item;
// Сгусток газа в диске: рыхлое облако, вытянутое сдвиговым течением вдоль
// орбиты (ось x квада — по течению). Светит отражённым светом звезды, которая
// всегда слева на экране. Когда гигант его всасывает, сгусток сжимается,
// греется и вытягивается приливом в сторону гиганта (pull, tide_dir).

uniform vec3 col : source_color = vec3(0.85, 0.75, 0.62);
uniform float seed = 0.0;
uniform float pull = 0.0;        // 0..1: всасывание
uniform float dark = 0.0;        // пыльный сгусток: заслоняет свет, а не светится
uniform float hot = 0.0;         // раскалённый у звезды: светится сам
uniform float ice = 0.0;         // ледяной: искрится кристалликами
uniform vec2 light = vec2(-1.0, 0.0);  // к звезде, в координатах квада
uniform vec2 tide_dir = vec2(-1.0, 0.0); // к гиганту, в координатах квада
uniform float time = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 17.0) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		s += a * noise(p);
		p = p * 2.07 + vec2(1.3, 7.1);
		a *= 0.5;
	}
	return s;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	// Прилив: вещество вытягивается к гиганту, сгусток сжимается.
	float sq = 1.0 + 1.4 * pull;
	vec2 t = normalize(tide_dir);
	float along = dot(p, t);
	vec2 q = p - t * along * (1.0 - 1.0 / (1.0 + 1.6 * pull));
	q *= sq;
	q.x *= 0.85;   // сдвиг вытянул сгусток вдоль орбиты (квад и так шире)
	q *= 1.5;
	float r = length(q);
	vec2 w = vec2(fbm(q * 2.1 + seed * 9.0 + time * 0.03), fbm(q * 2.1 + seed * 5.0 + 11.0 - time * 0.03));
	float n = fbm(q * 3.2 + w * 1.6 + seed * 3.0);
	float fine = fbm(q * 9.0 + w * 2.0);
	float body = smoothstep(1.0, 0.15, r + (n - 0.5) * 0.7);
	float dens = body * (0.55 + 0.7 * n) * (0.85 + 0.3 * fine);
	// Хвост к гиганту при всасывании.
	float tail = pull * exp(-pow(dot(p, vec2(-t.y, t.x)) / (0.12 + 0.1 * (1.0 - pull)), 2.0)) * smoothstep(0.0, 0.9, along) * smoothstep(1.0, 0.4, along);
	dens = max(dens, tail * (0.5 + 0.5 * fine));
	// Свет: сторона к звезде ярче, тень на дальней стороне.
	float lit = 0.55 + 0.45 * clamp(dot(normalize(p + vec2(1e-4)), normalize(light)) * smoothstep(0.0, 0.6, r), -1.0, 1.0);
	vec3 c = col * (0.45 + 0.75 * lit) * (0.75 + 0.35 * fine);
	// Сжатие греет газ: ядро сгустка теплеет.
	c = mix(c, vec3(1.0, 0.78, 0.55), pull * 0.5 * body);
	c += vec3(1.0, 0.5, 0.2) * hot * (0.3 + 0.6 * n) * body;
	float sp = smoothstep(0.93, 0.99, hash(floor(UV * 90.0))) * (0.5 + 0.5 * sin(time * 4.0 + hash(floor(UV * 90.0)) * 30.0));
	c += vec3(0.8, 0.9, 1.0) * ice * sp * body * 0.9;
	// Края квада никогда не видны: окно по самому квадрату.
	float win = smoothstep(1.0, 0.55, length(p)) * smoothstep(1.0, 0.8, abs(p.x)) * smoothstep(1.0, 0.8, abs(p.y));
	float a = clamp(dens * (0.42 + 0.3 * dark + 0.2 * pull), 0.0, 0.8) * win;
	c = mix(c, c * 0.35, dark);
	COLOR = vec4(c, a);
}
