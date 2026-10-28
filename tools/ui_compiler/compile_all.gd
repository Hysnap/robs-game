extends SceneTree

func _init() -> void:
	var compiler = preload("res://tools/ui_compiler/ui_compiler.gd")
	compiler.compile_all()
	quit()