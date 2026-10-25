extends Node
## Запекает поверхность звезды в assets/star/star_surface.png.
## Запуск: открыть tools/bake_star.tscn в редакторе и нажать F6.

const SIZE := Vector2i(2048, 1024)
const OUT_PATH := "res://assets/star/star_surface.png"


func _ready() -> void:
	var vp := SubViewport.new()
	vp.size = SIZE
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	var rect := ColorRect.new()
	rect.size = Vector2(SIZE)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/bake/star_surface_bake.gdshader")
	rect.material = mat
	vp.add_child(rect)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	var err := img.save_png(ProjectSettings.globalize_path(OUT_PATH))
	print("Звезда запечена: ", OUT_PATH, " ошибка=", err)
	get_tree().quit()
