shader_type canvas_item;
// Карта облаков гиганта в равнопромежуточной проекции (долгота × широта).
// Дорогие облака считаются здесь раз в полсекунды в текстуру 512×256,
// а шар каждый кадр только читает её (use_map в giant_planet.gdshader).

#include "res://shaders/giant_clouds.gdshaderinc"

void fragment() {
	float lon = (UV.x - 0.5) * 6.2832;
	float lat = (0.5 - UV.y) * 3.1416;
	vec3 d = vec3(sin(lon) * cos(lat), sin(lat), cos(lon) * cos(lat));
	float spot_k;
	COLOR = vec4(clouds(d, spot_k), 1.0);
}
