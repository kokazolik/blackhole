shader_type canvas_item;
// Фон космоса: редкие туманности, далёкие звёзды, далёкие пылевые потоки самого
// диска и ближние яркие звёзды. У снеговой линии добавляется искрящаяся дымка инея.
// Четыре выборки бесшовных текстур на пиксель — дёшево даже на слабом телефоне.

uniform sampler2D nebula : filter_linear, repeat_enable;
uniform sampler2D stars_far : filter_linear, repeat_enable;
uniform sampler2D stars_near : filter_linear, repeat_enable;
uniform sampler2D disk_streams : filter_linear, repeat_enable;
uniform float orbit_angle = 0.0;  // угол игрока вокруг звезды: потоки идут вдоль орбиты
uniform vec2 star_dir = vec2(-1.0, 0.0);  // направление на звезду на экране
uniform float snow = 0.0;         // близость к снеговой линии, 0..1
uniform float flare = 0.0;        // вспышка на звезде подсвечивает потоки
uniform vec2 view_size = vec2(1280.0, 720.0);
uniform vec2 offset;  // положение камеры в пикселях экрана
uniform vec3 base_color : source_color = vec3(0.004, 0.005, 0.009);  // космос почти чёрный

const float NEBULA_PARALLAX = 0.02;
const float FAR_PARALLAX = 0.06;
const float NEAR_PARALLAX = 0.22;
const float STREAM_PARALLAX = 0.12;
const float STREAM_SCALE = 1800.0;
const float HAZE_PARALLAX = 0.5;
const float NEBULA_SCALE = 2048.0;  // туманность растянута вдвое: облака крупнее
const float STAR_SCALE = 1024.0;

void fragment() {
	// TIME растёт без конца, а на телефоне точность float невысокая: зацикливаем.
	float T = mod(TIME, 1000.0 * 6.2832);
	vec2 px = UV * view_size;
	vec4 neb = texture(nebula, (px + offset * NEBULA_PARALLAX) / NEBULA_SCALE);
	vec4 far = texture(stars_far, (px + offset * FAR_PARALLAX) / STAR_SCALE);
	vec4 near = texture(stars_near, (px + offset * NEAR_PARALLAX + vec2(311.0, 97.0)) / STAR_SCALE);
	// Мерцание ближних звёзд: фаза берётся из цвета самой звезды (у соседних
	// звёзд оттенок разный), без хеша на каждый пиксель экрана.
	near.a *= 0.7 + 0.3 * sin(T * 1.7 + (near.r - near.b) * 40.0 + near.g * 17.0);
	// Потоки диска: текстура повёрнута так, чтобы волокна шли по касательной к орбите.
	vec2 rel = px - view_size * 0.5 + offset * STREAM_PARALLAX;
	float ca = cos(orbit_angle);
	float sa = sin(orbit_angle);
	vec2 along = vec2(-sa * rel.x + ca * rel.y, ca * rel.x + sa * rel.y);
	vec4 stream = texture(disk_streams, along / STREAM_SCALE + vec2(0.37, 0.11));
	// Потоки светят отражённым светом звезды: со стороны звезды ярче.
	vec2 from_center = normalize(px - view_size * 0.5 + vec2(0.001));
	float lit = 0.55 + 0.45 * dot(from_center, star_dir);
	stream.a *= lit * (1.0 + 0.8 * flare);

	vec3 col = base_color + neb.rgb * neb.a + far.rgb * far.a;
	col = mix(col, stream.rgb, stream.a);
	col += near.rgb * near.a;

	// Иней у снеговой линии: голубая дымка и редкие вспыхивающие кристаллики.
	// У снеговой линии — только лёгкая голубая дымка, без искр.
	if (snow > 0.01) {
		vec2 hp = px + offset * HAZE_PARALLAX;
		float haze = 0.5 + 0.5 * sin(hp.x * 0.004 + hp.y * 0.003 + T * 0.2);
		col += vec3(0.35, 0.55, 0.8) * snow * 0.045 * haze;
	}
	COLOR = vec4(col, 1.0);
}
