# res://scenes/menus/city_generator_loader.gd
extends Control

@onready var progress_bar: ProgressBar = $CenterContainer/VBoxContainer/ProgressBar
@onready var title_label: Label = $CenterContainer/VBoxContainer/TitleLabel
@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel

var _progress_tween: Tween = null

func _ready() -> void:
	# 1. Extract settings passed from MapMenu
	var settings: Dictionary = {}
	if get_tree().has_meta("pending_city_settings"):
		settings = get_tree().get_meta("pending_city_settings")
		get_tree().remove_meta("pending_city_settings")

	var gen_seed: String = str(settings.get("seed_id", settings.get("seed", "midlands-1984"))).strip_edges()
	var target_slot: String = str(settings.get("save_slot", SaveManager.get_next_available_slot()))

	# 2. Trigger Controller Pipeline
	_execute_generation(gen_seed, target_slot, settings)

func _execute_generation(gen_seed: String, slot_id: String, settings: Dictionary) -> void:
	var success = await CityGenerationController.run_pipeline(
		gen_seed, 
		slot_id, 
		settings, 
		Callable(self, "_on_pipeline_progress")
	)

	if success:
		await get_tree().create_timer(0.3).timeout
		get_tree().change_scene_to_file("res://scenes/3d_scenes/node_3d.tscn")
	else:
		status_label.text = "ERROR: Generation Failed. See Logs."

func _on_pipeline_progress(percent: float, stage_title: String, detail_text: String) -> void:
	if _progress_tween and _progress_tween.is_valid():
		_progress_tween.kill()

	_progress_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_progress_tween.tween_property(progress_bar, "value", percent, 0.2)

	status_label.text = "%s: %s" % [stage_title, detail_text] if detail_text != "" else stage_title