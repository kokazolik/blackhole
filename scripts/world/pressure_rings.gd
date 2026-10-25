class_name PressureRings
extends Node2D
## Кольца-ловушки давления на этапе «Галька»: светлые пыльные полосы вокруг звезды.
## Ветра в них почти нет, и гальки там копятся. Рисует шейдер на квадрате,
## покрывающем все кольца; проявляются вместе с обликом гальки.

var player: Player
var _mat := ShaderMaterial.new()


func _ready() -> void:
	_mat.shader = preload("res://shaders/pressure_rings.gdshader")
	var r: Array = GameData.PRESSURE_RINGS
	_mat.set_shader_parameter("rings", Vector4(r[0], r[1], r[2], r[3]))
	_mat.set_shader_parameter("width", GameData.RING_WIDTH)
	_mat.set_shader_parameter("snow_line", GameData.SNOW_LINE)
	material = _mat


func _process(_delta: float) -> void:
	visible = player.pebble_k > 0.0
	_mat.set_shader_parameter("strength", player.pebble_k)


func _draw() -> void:
	var extent: float = GameData.PRESSURE_RINGS.back() + GameData.RING_WIDTH * 3.0
	draw_rect(Rect2(-extent, -extent, extent * 2.0, extent * 2.0), Color.WHITE)
