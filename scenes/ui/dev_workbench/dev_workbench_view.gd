# res://scenes/ui/dev_workbench/dev_workbench_view.gd
class_name DevWorkbenchView
extends Control

const ControllerScript = preload("res://systems/dev_authoring/dev_authoring_controller.gd")

var _catalog: Dictionary = {}

# Current working specs bound to UI
var _comm_spec: Dictionary = {}
var _recipe_spec: Dictionary = {}
var _verb_spec: Dictionary = {}

# Top-level UI containers
var _tabs: TabContainer
var _status_label: RichTextLabel

# Commodity Tab Nodes
var _comm_load_opt: OptionButton
var _comm_module_opt: OptionButton
var _comm_id_edit: LineEdit
var _comm_cat_edit: LineEdit
var _comm_subcat_edit: LineEdit
var _comm_tier_spin: SpinBox
var _comm_mass_spin: SpinBox
var _comm_vol_spin: SpinBox
var _comm_cost_spin: SpinBox
var _comm_legal_opt: OptionButton
var _comm_impacts_box: VBoxContainer

# Recipe Tab Nodes
var _rec_load_opt: OptionButton
var _rec_module_opt: OptionButton
var _rec_cat_edit: LineEdit
var _rec_id_edit: LineEdit
var _rec_output_opt: OptionButton
var _rec_out_qty_spin: SpinBox
var _rec_facility_edit: LineEdit
var _rec_dur_spin: SpinBox
var _rec_inputs_box: VBoxContainer
var _rec_impacts_box: VBoxContainer

# Macro Verb Tab Nodes
var _verb_load_opt: OptionButton
var _verb_module_opt: OptionButton
var _verb_token_edit: LineEdit
var _verb_visible_chk: CheckBox
var _verb_steps_box: VBoxContainer
var _verb_impacts_box: VBoxContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_reset_specs()
	_build_ui_hierarchy()
	refresh_catalogs()

func _reset_specs() -> void:
	_comm_spec = {
		"module": "core",
		"id": "",
		"category": "consumables",
		"subcategory": "",
		"tier": 1,
		"unit_mass_kg": 0.5,
		"unit_volume_l": 0.5,
		"base_cost": 5.0,
		"legal_status": "LEGAL",
		"impacts": []
	}
	_recipe_spec = {
		"module": "core",
		"category": "general",
		"recipe_id": "",
		"inputs": {},
		"output_commodity": "CASH",
		"output_quantity": 1.0,
		"required_facility": "",
		"duration_ticks": 1.0,
		"impacts": []
	}
	_verb_spec = {
		"module": "core",
		"verb_token": "",
		"visible_in_composer": true,
		"sequence": [],
		"impacts": []
	}

## Refreshes all dropdown whitelists from disk via DevAuthoringController
func refresh_catalogs() -> void:
	_catalog = ControllerScript.get_workbench_catalog_snapshot()
	_populate_header_loaders()
	_rebind_commodity_tab()
	_rebind_recipe_tab()
	_rebind_verb_tab()
	_log_status("[color=cyan][WORKBENCH READY][/color] Mounted %d whitelisted impacts, %d commodities, %d verbs." % [
		_catalog.get("impacts", []).size(),
		_catalog.get("commodities", []).size(),
		_catalog.get("verbs", []).size()
	])

# =====================================================================
# 1. UI HIERARCHY CONSTRUCTION (PURE PRESENTATION)
# =====================================================================

func _build_ui_hierarchy() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.11, 0.12, 0.14, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 8)
	add_child(main_vbox)

	# Header Row
	var header_panel := PanelContainer.new()
	main_vbox.add_child(header_panel)
	var header_hbox := HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 16)
	header_panel.add_child(header_hbox)

	var title_lbl := Label.new()
	title_lbl.text = "  DEVELOPER AUTHORING WORKBENCH (MVC / WHITELISTED IMPACTS / LOGIC TREES)"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(title_lbl)

	var refresh_btn := Button.new()
	refresh_btn.text = "Refresh Disk Catalogs"
	refresh_btn.pressed.connect(refresh_catalogs)
	header_hbox.add_child(refresh_btn)

	# Main TabContainer
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(_tabs)

	_build_commodity_tab()
	_build_recipe_tab()
	_build_verb_tab()

	# Bottom Validation & Status Feedback Console
	var console_panel := PanelContainer.new()
	console_panel.custom_minimum_size = Vector2(0, 130)
	main_vbox.add_child(console_panel)

	_status_label = RichTextLabel.new()
	_status_label.bbcode_enabled = true
	_status_label.scroll_following = true
	console_panel.add_child(_status_label)

# =====================================================================
# 2. TAB 1: COMMODITY SETUP
# =====================================================================

func _build_commodity_tab() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "1. Commodity Setup"
	_tabs.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(vbox)

	# Loader bar
	var load_hbox := HBoxContainer.new()
	vbox.add_child(load_hbox)
	load_hbox.add_child(_make_label("Load Existing Commodity:", 200))
	_comm_load_opt = OptionButton.new()
	_comm_load_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_hbox.add_child(_comm_load_opt)
	var load_btn := Button.new()
	load_btn.text = "Load Selected"
	load_btn.pressed.connect(_on_load_commodity_pressed)
	load_hbox.add_child(load_btn)
	var new_btn := Button.new()
	new_btn.text = "New / Clear"
	new_btn.pressed.connect(func(): _reset_specs(); _rebind_commodity_tab())
	load_hbox.add_child(new_btn)

	# Core Fields Grid
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(grid)

	grid.add_child(_make_label("Data Module:"))
	_comm_module_opt = OptionButton.new()
	grid.add_child(_comm_module_opt)

	grid.add_child(_make_label("Commodity ID (UPPER):"))
	_comm_id_edit = LineEdit.new()
	_comm_id_edit.placeholder_text = "e.g. SPICED_RUM"
	grid.add_child(_comm_id_edit)

	grid.add_child(_make_label("Category Folder:"))
	_comm_cat_edit = LineEdit.new()
	_comm_cat_edit.text = "consumables"
	grid.add_child(_comm_cat_edit)

	grid.add_child(_make_label("Subcategory Folder:"))
	_comm_subcat_edit = LineEdit.new()
	_comm_subcat_edit.placeholder_text = "e.g. alcohol"
	grid.add_child(_comm_subcat_edit)

	grid.add_child(_make_label("Tier:"))
	_comm_tier_spin = _make_spin(1, 10, 1, 1)
	grid.add_child(_comm_tier_spin)

	grid.add_child(_make_label("Legal Status:"))
	_comm_legal_opt = OptionButton.new()
	for st in ["LEGAL", "RESTRICTED", "CONTRABAND"]:
		_comm_legal_opt.add_item(st)
	grid.add_child(_comm_legal_opt)

	grid.add_child(_make_label("Unit Mass (kg):"))
	_comm_mass_spin = _make_spin(0.0, 1000.0, 0.05, 0.5)
	grid.add_child(_comm_mass_spin)

	grid.add_child(_make_label("Unit Volume (L):"))
	_comm_vol_spin = _make_spin(0.0, 1000.0, 0.05, 0.5)
	grid.add_child(_comm_vol_spin)

	grid.add_child(_make_label("Base Cost (£):"))
	_comm_cost_spin = _make_spin(0.0, 100000.0, 0.5, 5.0)
	grid.add_child(_comm_cost_spin)

	# Whitelisted Impacts Section
	var imp_header := HBoxContainer.new()
	vbox.add_child(imp_header)
	imp_header.add_child(_make_label("Allocated Verb Impacts (Restricted to Existing Sinks):", 420))
	var add_imp_btn := Button.new()
	add_imp_btn.text = "+ Add Whitelisted Impact"
	add_imp_btn.pressed.connect(_on_add_commodity_impact)
	imp_header.add_child(add_imp_btn)

	_comm_impacts_box = VBoxContainer.new()
	vbox.add_child(_comm_impacts_box)

	# Save Bar
	vbox.add_child(_build_action_bar(
		func(): _sync_commodity_from_ui(); _show_validation("COMMODITY", _comm_spec),
		func(): _sync_commodity_from_ui(); _execute_save("COMMODITY", _comm_spec, false),
		func(): _sync_commodity_from_ui(); _execute_save("COMMODITY", _comm_spec, true)
	))

# =====================================================================
# 3. TAB 2: RECIPE SETUP
# =====================================================================

func _build_recipe_tab() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "2. Recipe Setup"
	_tabs.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(vbox)

	var load_hbox := HBoxContainer.new()
	vbox.add_child(load_hbox)
	load_hbox.add_child(_make_label("Load Existing Recipe:", 200))
	_rec_load_opt = OptionButton.new()
	_rec_load_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_hbox.add_child(_rec_load_opt)
	var load_btn := Button.new()
	load_btn.text = "Load Selected"
	load_btn.pressed.connect(_on_load_recipe_pressed)
	load_hbox.add_child(load_btn)
	var new_btn := Button.new()
	new_btn.text = "New / Clear"
	new_btn.pressed.connect(func(): _reset_specs(); _rebind_recipe_tab())
	load_hbox.add_child(new_btn)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(grid)

	grid.add_child(_make_label("Data Module:"))
	_rec_module_opt = OptionButton.new()
	grid.add_child(_rec_module_opt)

	grid.add_child(_make_label("Category Folder:"))
	_rec_cat_edit = LineEdit.new()
	_rec_cat_edit.text = "general"
	grid.add_child(_rec_cat_edit)

	grid.add_child(_make_label("Recipe ID (snake_case):"))
	_rec_id_edit = LineEdit.new()
	_rec_id_edit.placeholder_text = "e.g. cut_mixed_spirits"
	grid.add_child(_rec_id_edit)

	grid.add_child(_make_label("Required Facility:"))
	_rec_facility_edit = LineEdit.new()
	_rec_facility_edit.placeholder_text = "Optional facility tag"
	grid.add_child(_rec_facility_edit)

	grid.add_child(_make_label("Output Commodity:"))
	_rec_output_opt = OptionButton.new()
	grid.add_child(_rec_output_opt)

	grid.add_child(_make_label("Output Yield Qty:"))
	_rec_out_qty_spin = _make_spin(0.1, 1000.0, 0.5, 1.0)
	grid.add_child(_rec_out_qty_spin)

	grid.add_child(_make_label("Duration (Ticks):"))
	_rec_dur_spin = _make_spin(1.0, 100.0, 1.0, 1.0)
	grid.add_child(_rec_dur_spin)

	# Inputs Section
	var in_header := HBoxContainer.new()
	vbox.add_child(in_header)
	in_header.add_child(_make_label("Input Commodities (Ingredients):", 350))
	var add_in_btn := Button.new()
	add_in_btn.text = "+ Add Input Ingredient"
	add_in_btn.pressed.connect(_on_add_recipe_input)
	in_header.add_child(add_in_btn)

	_rec_inputs_box = VBoxContainer.new()
	vbox.add_child(_rec_inputs_box)

	# Whitelisted Impacts Section
	var imp_header := HBoxContainer.new()
	vbox.add_child(imp_header)
	imp_header.add_child(_make_label("Recipe Production Impacts (Whitelisted):", 350))
	var add_imp_btn := Button.new()
	add_imp_btn.text = "+ Add Whitelisted Impact"
	add_imp_btn.pressed.connect(_on_add_recipe_impact)
	imp_header.add_child(add_imp_btn)

	_rec_impacts_box = VBoxContainer.new()
	vbox.add_child(_rec_impacts_box)

	vbox.add_child(_build_action_bar(
		func(): _sync_recipe_from_ui(); _show_validation("RECIPE", _recipe_spec),
		func(): _sync_recipe_from_ui(); _execute_save("RECIPE", _recipe_spec, false),
		func(): _sync_recipe_from_ui(); _execute_save("RECIPE", _recipe_spec, true)
	))

# =====================================================================
# 4. TAB 3: MACRO VERB & DECISION TREE COMPOSER
# =====================================================================

func _build_verb_tab() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "3. Macro Verb & Logic Composer"
	_tabs.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(vbox)

	var load_hbox := HBoxContainer.new()
	vbox.add_child(load_hbox)
	load_hbox.add_child(_make_label("Load Existing Verb / WIP Draft:", 230))
	_verb_load_opt = OptionButton.new()
	_verb_load_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_hbox.add_child(_verb_load_opt)
	var load_btn := Button.new()
	load_btn.text = "Load Verb"
	load_btn.pressed.connect(_on_load_verb_pressed)
	load_hbox.add_child(load_btn)
	var new_btn := Button.new()
	new_btn.text = "New Macro Verb"
	new_btn.pressed.connect(func(): _reset_specs(); _rebind_verb_tab())
	load_hbox.add_child(new_btn)

	var meta_hbox := HBoxContainer.new()
	meta_hbox.add_theme_constant_override("separation", 12)
	vbox.add_child(meta_hbox)

	meta_hbox.add_child(_make_label("Module:"))
	_verb_module_opt = OptionButton.new()
	meta_hbox.add_child(_verb_module_opt)

	meta_hbox.add_child(_make_label("Verb Token (UPPER):"))
	_verb_token_edit = LineEdit.new()
	_verb_token_edit.placeholder_text = "e.g. SMART_RESTOCK"
	_verb_token_edit.custom_minimum_size = Vector2(220, 0)
	meta_hbox.add_child(_verb_token_edit)

	_verb_visible_chk = CheckBox.new()
	_verb_visible_chk.text = "Visible in Player Order Pad (when Live)"
	_verb_visible_chk.button_pressed = true
	meta_hbox.add_child(_verb_visible_chk)

	# Step Sequencer Header
	var step_bar := HBoxContainer.new()
	step_bar.add_theme_constant_override("separation", 8)
	vbox.add_child(step_bar)
	step_bar.add_child(_make_label("Step Pipeline & Decision Tree:", 240))

	for prim in ControllerScript.ValidatorScript.ALLOWED_PRIMITIVES:
		var btn := Button.new()
		btn.text = "+ " + prim
		var bound_prim: String = prim
		btn.pressed.connect(func(): _on_add_verb_step(bound_prim))
		step_bar.add_child(btn)

	_verb_steps_box = VBoxContainer.new()
	_verb_steps_box.add_theme_constant_override("separation", 10)
	vbox.add_child(_verb_steps_box)

	# Whitelisted Verb Impacts
	var imp_header := HBoxContainer.new()
	vbox.add_child(imp_header)
	imp_header.add_child(_make_label("Macro Verb Impacts (Restricted to Existing Sinks):", 380))
	var add_imp_btn := Button.new()
	add_imp_btn.text = "+ Add Whitelisted Impact"
	add_imp_btn.pressed.connect(_on_add_verb_impact)
	imp_header.add_child(add_imp_btn)

	_verb_impacts_box = VBoxContainer.new()
	vbox.add_child(_verb_impacts_box)

	vbox.add_child(_build_action_bar(
		func(): _sync_verb_from_ui(); _show_validation("MACRO_VERB", _verb_spec),
		func(): _sync_verb_from_ui(); _execute_save("MACRO_VERB", _verb_spec, false),
		func(): _sync_verb_from_ui(); _execute_save("MACRO_VERB", _verb_spec, true)
	))

# =====================================================================
# 5. DYNAMIC BINDING & STEP CARD RENDERERS
# =====================================================================

func _populate_header_loaders() -> void:
	_fill_option_button(_comm_load_opt, _catalog.get("commodities", []))
	_fill_option_button(_rec_load_opt, _catalog.get("recipes", []))
	_fill_option_button(_verb_load_opt, _catalog.get("verbs", []))
	_fill_option_button(_comm_module_opt, _catalog.get("modules", ["core"]))
	_fill_option_button(_rec_module_opt, _catalog.get("modules", ["core"]))
	_fill_option_button(_verb_module_opt, _catalog.get("modules", ["core"]))
	_fill_option_button(_rec_output_opt, _catalog.get("commodities", ["CASH"]))

func _rebind_commodity_tab() -> void:
	_comm_id_edit.text = str(_comm_spec.get("id", ""))
	_comm_cat_edit.text = str(_comm_spec.get("category", "consumables"))
	_comm_subcat_edit.text = str(_comm_spec.get("subcategory", ""))
	_comm_tier_spin.value = float(_comm_spec.get("tier", 1))
	_comm_mass_spin.value = float(_comm_spec.get("unit_mass_kg", 0.5))
	_comm_vol_spin.value = float(_comm_spec.get("unit_volume_l", 0.5))
	_comm_cost_spin.value = float(_comm_spec.get("base_cost", 5.0))
	_rebuild_impact_rows(_comm_impacts_box, _comm_spec.get("impacts", []), true)

func _rebind_recipe_tab() -> void:
	_rec_cat_edit.text = str(_recipe_spec.get("category", "general"))
	_rec_id_edit.text = str(_recipe_spec.get("recipe_id", ""))
	_rec_facility_edit.text = str(_recipe_spec.get("required_facility", ""))
	_rec_out_qty_spin.value = float(_recipe_spec.get("output_quantity", 1.0))
	_rec_dur_spin.value = float(_recipe_spec.get("duration_ticks", 1.0))
	_select_option_by_text(_rec_output_opt, str(_recipe_spec.get("output_commodity", "CASH")))

	_clear_children(_rec_inputs_box)
	var inputs: Dictionary = _recipe_spec.get("inputs", {})
	for item_key in inputs.keys():
		_add_recipe_input_row_ui(str(item_key), float(inputs[item_key]))

	_rebuild_impact_rows(_rec_impacts_box, _recipe_spec.get("impacts", []), false)

func _rebind_verb_tab() -> void:
	_verb_token_edit.text = str(_verb_spec.get("verb_token", ""))
	_verb_visible_chk.button_pressed = bool(_verb_spec.get("visible_in_composer", true))

	_clear_children(_verb_steps_box)
	var seq: Array = _verb_spec.get("sequence", [])
	for i in range(seq.size()):
		if seq[i] is Dictionary:
			_build_step_card_ui(i, seq[i])

	_rebuild_impact_rows(_verb_impacts_box, _verb_spec.get("impacts", []), false)

func _build_step_card_ui(step_idx: int, step_dict: Dictionary) -> void:
	var panel := PanelContainer.new()
	_verb_steps_box.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	# Top bar of step card
	var top_hbox := HBoxContainer.new()
	vbox.add_child(top_hbox)

	var prim: String = str(step_dict.get("primitive", "REQUIRE")).to_upper()
	top_hbox.add_child(_make_label("Step #%d [%s] — ID:" % [step_idx + 1, prim], 180))

	var sid_edit := LineEdit.new()
	sid_edit.text = str(step_dict.get("step_id", "step_%d" % (step_idx + 1)))
	sid_edit.custom_minimum_size = Vector2(180, 0)
	sid_edit.text_changed.connect(func(new_txt: String): step_dict["step_id"] = new_txt.strip_edges())
	top_hbox.add_child(sid_edit)

	top_hbox.add_child(_make_label("Next/True Step:"))
	var true_edit := LineEdit.new()
	true_edit.placeholder_text = "next step_id or COMPLETE"
	true_edit.text = str(step_dict.get("on_true", step_dict.get("next_step", "")))
	true_edit.custom_minimum_size = Vector2(160, 0)
	true_edit.text_changed.connect(func(t: String):
		step_dict["on_true"] = t.strip_edges()
		step_dict["next_step"] = t.strip_edges()
	)
	top_hbox.add_child(true_edit)

	top_hbox.add_child(_make_label("On False Branch:"))
	var false_edit := LineEdit.new()
	false_edit.placeholder_text = "step_id or HALT"
	false_edit.text = str(step_dict.get("on_false", "HALT"))
	false_edit.custom_minimum_size = Vector2(150, 0)
	false_edit.text_changed.connect(func(t: String): step_dict["on_false"] = t.strip_edges())
	top_hbox.add_child(false_edit)

	var del_btn := Button.new()
	del_btn.text = "Remove Step"
	del_btn.pressed.connect(func():
		_verb_spec["sequence"].remove_at(step_idx)
		_rebind_verb_tab()
	)
	top_hbox.add_child(del_btn)

	var params: Dictionary = step_dict.get("params", {})
	step_dict["params"] = params

	# Primitive-specific body
	if prim == "REQUIRE":
		_build_require_decision_ui(vbox, params)
	elif prim == "CALL_VERB":
		var row := HBoxContainer.new()
		vbox.add_child(row)
		row.add_child(_make_label("Sub-Verb to Execute:", 180))
		var verb_opt := OptionButton.new()
		_fill_option_button(verb_opt, _catalog.get("verbs", []))
		row.add_child(verb_opt)
		var custom_verb_edit := LineEdit.new()
		custom_verb_edit.placeholder_text = "Or type planned WIP verb token"
		custom_verb_edit.text = str(params.get("verb_token", ""))
		custom_verb_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		custom_verb_edit.text_changed.connect(func(t: String): params["verb_token"] = t.strip_edges().to_upper())
		row.add_child(custom_verb_edit)
		verb_opt.item_selected.connect(func(idx: int):
			var chosen: String = verb_opt.get_item_text(idx)
			custom_verb_edit.text = chosen
			params["verb_token"] = chosen
		)
	else:
		# Generic parameter key-value row editor for MOVE_ACTOR, TRANSFER_ITEM, DEDUCT_ITEM, CREDIT_ITEM
		var p_hbox := HBoxContainer.new()
		vbox.add_child(p_hbox)
		for p_key in params.keys():
			p_hbox.add_child(_make_label(str(p_key) + ":"))
			var val_edit := LineEdit.new()
			val_edit.text = str(params[p_key])
			val_edit.custom_minimum_size = Vector2(140, 0)
			var bound_key: String = str(p_key)
			val_edit.text_changed.connect(func(nv: String): params[bound_key] = nv.strip_edges())
			p_hbox.add_child(val_edit)

func _build_require_decision_ui(parent_vbox: VBoxContainer, params: Dictionary) -> void:
	var gate_hbox := HBoxContainer.new()
	parent_vbox.add_child(gate_hbox)
	gate_hbox.add_child(_make_label("Decision Logic Gate (ConditionEvaluator):", 280))

	var gate_opt := OptionButton.new()
	var gates: Array = _catalog.get("logic_gates", ["AND", "OR", "NAND", "NOR", "XOR"])
	_fill_option_button(gate_opt, gates)
	_select_option_by_text(gate_opt, str(params.get("logic_gate", "AND")))
	gate_opt.item_selected.connect(func(idx: int): params["logic_gate"] = gate_opt.get_item_text(idx))
	gate_hbox.add_child(gate_opt)

	if not params.has("conditions") or not (params["conditions"] is Array):
		params["conditions"] = [ControllerScript.create_condition_template()]

	var cond_list: Array = params["conditions"]
	var add_cond_btn := Button.new()
	add_cond_btn.text = "+ Add Condition Row"
	add_cond_btn.pressed.connect(func():
		cond_list.append(ControllerScript.create_condition_template())
		_rebind_verb_tab()
	)
	gate_hbox.add_child(add_cond_btn)

	for c_idx in range(cond_list.size()):
		var cond: Dictionary = cond_list[c_idx]
		var c_row := HBoxContainer.new()
		parent_vbox.add_child(c_row)

		var dom_opt := OptionButton.new()
		_fill_option_button(dom_opt, _catalog.get("require_domains", ["COMMODITY", "LOCATION", "ATTRIBUTE"]))
		_select_option_by_text(dom_opt, str(cond.get("domain", "COMMODITY")))
		dom_opt.item_selected.connect(func(i: int): cond["domain"] = dom_opt.get_item_text(i))
		c_row.add_child(dom_opt)

		var actor_edit := LineEdit.new()
		actor_edit.text = str(cond.get("actor", "ORDER_ACTOR"))
		actor_edit.custom_minimum_size = Vector2(120, 0)
		actor_edit.text_changed.connect(func(t: String): cond["actor"] = t.strip_edges())
		c_row.add_child(actor_edit)

		var metric_edit := LineEdit.new()
		metric_edit.placeholder_text = "Metric / Item ID"
		metric_edit.text = str(cond.get("metric", "CASH"))
		metric_edit.custom_minimum_size = Vector2(130, 0)
		metric_edit.text_changed.connect(func(t: String): cond["metric"] = t.strip_edges())
		c_row.add_child(metric_edit)

		var op_opt := OptionButton.new()
		_fill_option_button(op_opt, _catalog.get("operators", [">=", "<=", "==", "!=", ">", "<", "BETWEEN", "NOT_BETWEEN"]))
		_select_option_by_text(op_opt, str(cond.get("operator", ">=")))
		c_row.add_child(op_opt)

		var val_edit := LineEdit.new()
		val_edit.placeholder_text = "Value or Symbol"
		val_edit.text = str(cond.get("value", 1.0))
		val_edit.custom_minimum_size = Vector2(110, 0)
		val_edit.text_changed.connect(func(t: String):
			if t.is_valid_float():
				cond["value"] = float(t)
			else:
				cond["value"] = t.strip_edges()
		)
		c_row.add_child(val_edit)

		var low_spin := _make_spin(-100000.0, 100000.0, 1.0, float(cond.get("lower", 0.0)))
		var high_spin := _make_spin(-100000.0, 100000.0, 1.0, float(cond.get("upper", 100.0)))
		low_spin.prefix = "Min:"
		high_spin.prefix = "Max:"
		var is_between: bool = str(cond.get("operator", ">=")) in ["BETWEEN", "NOT_BETWEEN"]
		low_spin.visible = is_between
		high_spin.visible = is_between
		low_spin.value_changed.connect(func(v: float): cond["lower"] = v)
		high_spin.value_changed.connect(func(v: float): cond["upper"] = v)
		c_row.add_child(low_spin)
		c_row.add_child(high_spin)

		op_opt.item_selected.connect(func(i: int):
			var chosen_op: String = op_opt.get_item_text(i)
			cond["operator"] = chosen_op
			var show_bounds: bool = chosen_op in ["BETWEEN", "NOT_BETWEEN"]
			low_spin.visible = show_bounds
			high_spin.visible = show_bounds
		)

		var rm_c_btn := Button.new()
		rm_c_btn.text = "X"
		rm_c_btn.pressed.connect(func():
			cond_list.remove_at(c_idx)
			_rebind_verb_tab()
		)
		c_row.add_child(rm_c_btn)

# =====================================================================
# 6. WHITELISTED IMPACT ROW BUILDER (SHARED ACROSS TABS)
# =====================================================================

func _rebuild_impact_rows(container: VBoxContainer, impacts_list: Array, include_verb_ctx: bool) -> void:
	_clear_children(container)
	var allowed_impacts: Array = _catalog.get("impacts", [])
	var models: Array = _catalog.get("calc_models", ["LINEAR_PER_UNIT", "FLAT_DELTA"])

	for idx in range(impacts_list.size()):
		var imp: Dictionary = impacts_list[idx]
		var row := HBoxContainer.new()
		container.add_child(row)

		if include_verb_ctx:
			row.add_child(_make_label("Verb Folder:"))
			var ctx_edit := LineEdit.new()
			ctx_edit.text = str(imp.get("verb_context", "consume"))
			ctx_edit.custom_minimum_size = Vector2(100, 0)
			ctx_edit.text_changed.connect(func(t: String): imp["verb_context"] = t.strip_edges().to_lower())
			row.add_child(ctx_edit)

		row.add_child(_make_label("Whitelisted Impact:"))
		var metric_opt := OptionButton.new()
		_fill_option_button(metric_opt, allowed_impacts)
		_select_option_by_text(metric_opt, str(imp.get("metric_key", "")))
		if metric_opt.selected >= 0 and metric_opt.item_count > 0:
			imp["metric_key"] = metric_opt.get_item_text(metric_opt.selected)
		metric_opt.item_selected.connect(func(i: int): imp["metric_key"] = metric_opt.get_item_text(i))
		row.add_child(metric_opt)

		row.add_child(_make_label("Model:"))
		var mod_opt := OptionButton.new()
		_fill_option_button(mod_opt, models)
		_select_option_by_text(mod_opt, str(imp.get("model", "LINEAR_PER_UNIT")))
		mod_opt.item_selected.connect(func(i: int): imp["model"] = mod_opt.get_item_text(i))
		row.add_child(mod_opt)

		row.add_child(_make_label("Factor/Delta:"))
		var fac_spin := _make_spin(-1000.0, 1000.0, 0.05, float(imp.get("factor", 0.0)))
		fac_spin.value_changed.connect(func(v: float):
			imp["factor"] = v
			imp["delta"] = v
		)
		row.add_child(fac_spin)

		var rm_btn := Button.new()
		rm_btn.text = "Remove"
		rm_btn.pressed.connect(func():
			impacts_list.remove_at(idx)
			_rebuild_impact_rows(container, impacts_list, include_verb_ctx)
		)
		row.add_child(rm_btn)

# =====================================================================
# 7. EVENT HANDLERS & CONTROLLER DISPATCH
# =====================================================================

func _on_add_commodity_impact() -> void:
	var default_metric: String = _catalog.get("impacts", ["WORKER_FATIGUE"])[0] if not _catalog.get("impacts", []).is_empty() else ""
	_comm_spec["impacts"].append({
		"verb_context": "consume",
		"metric_key": default_metric,
		"model": "LINEAR_PER_UNIT",
		"factor": 0.1
	})
	_rebuild_impact_rows(_comm_impacts_box, _comm_spec["impacts"], true)

func _on_add_recipe_input() -> void:
	var comms: Array = _catalog.get("commodities", ["CASH"])
	var pick: String = comms[0] if not comms.is_empty() else "CASH"
	_add_recipe_input_row_ui(pick, 1.0)

func _add_recipe_input_row_ui(item_id: String, qty: float) -> void:
	var row := HBoxContainer.new()
	_rec_inputs_box.add_child(row)
	var opt := OptionButton.new()
	_fill_option_button(opt, _catalog.get("commodities", ["CASH"]))
	_select_option_by_text(opt, item_id)
	row.add_child(opt)
	var spin := _make_spin(0.1, 1000.0, 0.1, qty)
	row.add_child(spin)
	var rm := Button.new()
	rm.text = "Remove"
	rm.pressed.connect(func(): row.queue_free())
	row.add_child(rm)

func _on_add_recipe_impact() -> void:
	var default_metric: String = _catalog.get("impacts", ["WORKER_FATIGUE"])[0] if not _catalog.get("impacts", []).is_empty() else ""
	_recipe_spec["impacts"].append({
		"metric_key": default_metric,
		"model": "FLAT_DELTA",
		"factor": 0.1
	})
	_rebuild_impact_rows(_rec_impacts_box, _recipe_spec["impacts"], false)

func _on_add_verb_step(primitive: String) -> void:
	var seq: Array = _verb_spec.get("sequence", [])
	var next_id: String = "step_%d_%s" % [seq.size() + 1, primitive.to_lower()]
	seq.append(ControllerScript.create_step_template(next_id, primitive))
	_rebind_verb_tab()

func _on_add_verb_impact() -> void:
	var default_metric: String = _catalog.get("impacts", ["WORKER_FATIGUE"])[0] if not _catalog.get("impacts", []).is_empty() else ""
	_verb_spec["impacts"].append({
		"metric_key": default_metric,
		"model": "FLAT_DELTA",
		"factor": 0.1
	})
	_rebuild_impact_rows(_verb_impacts_box, _verb_spec["impacts"], false)

func _on_load_commodity_pressed() -> void:
	if _comm_load_opt.selected < 0:
		return
	var cid: String = _comm_load_opt.get_item_text(_comm_load_opt.selected)
	var loaded: Dictionary = ControllerScript.load_existing_commodity(cid)
	if not loaded.is_empty():
		_comm_spec = loaded
		_rebind_commodity_tab()
		_log_status("[color=green]Loaded Commodity '%s' (Status: %s)[/color]" % [cid, "LIVE" if loaded.get("is_live", true) else "WIP_DRAFT"])

func _on_load_recipe_pressed() -> void:
	if _rec_load_opt.selected < 0:
		return
	var rid: String = _rec_load_opt.get_item_text(_rec_load_opt.selected)
	var loaded: Dictionary = ControllerScript.load_existing_recipe(rid)
	if not loaded.is_empty():
		_recipe_spec = loaded
		_rebind_recipe_tab()
		_log_status("[color=green]Loaded Recipe '%s' (Status: %s)[/color]" % [rid, "LIVE" if loaded.get("is_live", true) else "WIP_DRAFT"])

func _on_load_verb_pressed() -> void:
	if _verb_load_opt.selected < 0:
		return
	var vtok: String = _verb_load_opt.get_item_text(_verb_load_opt.selected)
	var loaded: Dictionary = ControllerScript.load_existing_verb(vtok)
	if not loaded.is_empty():
		_verb_spec = loaded
		_rebind_verb_tab()
		_log_status("[color=green]Loaded Macro Verb '%s' (Status: %s)[/color]" % [vtok, "LIVE" if loaded.get("is_live", true) else "WIP_DRAFT"])

func _sync_commodity_from_ui() -> void:
	_comm_spec["module"] = _comm_module_opt.get_item_text(maxi(0, _comm_module_opt.selected)) if _comm_module_opt.item_count > 0 else "core"
	_comm_spec["id"] = _comm_id_edit.text.strip_edges().to_upper()
	_comm_spec["category"] = _comm_cat_edit.text.strip_edges().to_lower()
	_comm_spec["subcategory"] = _comm_subcat_edit.text.strip_edges().to_lower()
	_comm_spec["tier"] = int(_comm_tier_spin.value)
	_comm_spec["unit_mass_kg"] = _comm_mass_spin.value
	_comm_spec["unit_volume_l"] = _comm_vol_spin.value
	_comm_spec["base_cost"] = _comm_cost_spin.value
	_comm_spec["legal_status"] = _comm_legal_opt.get_item_text(maxi(0, _comm_legal_opt.selected))

func _sync_recipe_from_ui() -> void:
	_recipe_spec["module"] = _rec_module_opt.get_item_text(maxi(0, _rec_module_opt.selected)) if _rec_module_opt.item_count > 0 else "core"
	_recipe_spec["category"] = _rec_cat_edit.text.strip_edges().to_lower()
	_recipe_spec["recipe_id"] = _rec_id_edit.text.strip_edges().to_lower()
	_recipe_spec["required_facility"] = _rec_facility_edit.text.strip_edges()
	_recipe_spec["output_commodity"] = _rec_output_opt.get_item_text(maxi(0, _rec_output_opt.selected)) if _rec_output_opt.item_count > 0 else "CASH"
	_recipe_spec["output_quantity"] = _rec_out_qty_spin.value
	_recipe_spec["duration_ticks"] = _rec_dur_spin.value

	var inputs_dict: Dictionary = {}
	for row in _rec_inputs_box.get_children():
		if row is HBoxContainer and row.get_child_count() >= 2:
			var opt: OptionButton = row.get_child(0)
			var spin: SpinBox = row.get_child(1)
			if opt.selected >= 0:
				inputs_dict[opt.get_item_text(opt.selected)] = spin.value
	_recipe_spec["inputs"] = inputs_dict

func _sync_verb_from_ui() -> void:
	_verb_spec["module"] = _verb_module_opt.get_item_text(maxi(0, _verb_module_opt.selected)) if _verb_module_opt.item_count > 0 else "core"
	_verb_spec["verb_token"] = _verb_token_edit.text.strip_edges().to_upper()
	_verb_spec["visible_in_composer"] = _verb_visible_chk.button_pressed

func _show_validation(domain: String, spec: Dictionary) -> void:
	var val: Dictionary = ControllerScript.preview_validation(domain, spec)
	_render_validation_report(domain, val)

func _execute_save(domain: String, spec: Dictionary, request_live: bool) -> void:
	var res: Dictionary = {}
	match domain:
		"COMMODITY": res = ControllerScript.save_commodity(spec, request_live)
		"RECIPE": res = ControllerScript.save_recipe(spec, request_live)
		"MACRO_VERB": res = ControllerScript.save_macro_verb(spec, request_live)

	if res.has("catalog"):
		_catalog = res["catalog"]
		_populate_header_loaders()

	var val: Dictionary = res.get("validation", {})
	_render_validation_report(domain, val)

	if bool(res.get("success", false)):
		var status_str: String = "LIVE (Active in Game)" if bool(res.get("is_live", false)) else "WIP DRAFT (Soft-Locked from Live Composer)"
		_log_status("[color=green]SAVED %s -> %s [%s][/color]" % [domain, str(res.get("path", "")), status_str])
	else:
		_log_status("[color=red]SAVE BLOCKED for %s — Fix Blocking Errors above.[/color]" % domain)

func _render_validation_report(domain: String, val: Dictionary) -> void:
	var blocking: Array = val.get("blocking_errors", [])
	var warnings: Array = val.get("publish_warnings", [])
	var lines: PackedStringArray = []
	lines.append("[b]Validation Report (%s):[/b] Can Save WIP Draft: %s | Ready for Live: %s" % [
		domain,
		"[color=green]YES[/color]" if val.get("can_save_draft", false) else "[color=red]NO[/color]",
		"[color=green]YES[/color]" if val.get("can_make_live", false) else "[color=yellow]SOFT-LOCKED (WIP)[/color]"
	])
	for b in blocking:
		lines.append("  [color=red]• [HARD BLOCK] %s[/color]" % str(b))
	for w in warnings:
		lines.append("  [color=yellow]• [SOFT-LOCK WARNING] %s[/color]" % str(w))
	if blocking.is_empty() and warnings.is_empty():
		lines.append("  [color=green]✓ All schema, impact whitelist, and branch target checks passed![/color]")
	_log_status("\n".join(lines))

# =====================================================================
# 8. SMALL WIDGET FACTORY HELPERS
# =====================================================================

func _build_action_bar(on_validate: Callable, on_save_draft: Callable, on_make_live: Callable) -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 16)
	var val_btn := Button.new()
	val_btn.text = "Validate Check"
	val_btn.pressed.connect(on_validate)
	bar.add_child(val_btn)

	var draft_btn := Button.new()
	draft_btn.text = "Save WIP Draft (Soft-Locked)"
	draft_btn.pressed.connect(on_save_draft)
	bar.add_child(draft_btn)

	var live_btn := Button.new()
	live_btn.text = "Publish & Make Live"
	live_btn.pressed.connect(on_make_live)
	bar.add_child(live_btn)
	return bar

func _make_label(txt: String, min_w: float = 0.0) -> Label:
	var l := Label.new()
	l.text = txt
	if min_w > 0.0:
		l.custom_minimum_size = Vector2(min_w, 0)
	return l

func _make_spin(min_v: float, max_v: float, step_v: float, def_v: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step_v
	s.value = def_v
	s.custom_minimum_size = Vector2(110, 0)
	return s

func _fill_option_button(opt: OptionButton, items: Array) -> void:
	if opt == null:
		return
	opt.clear()
	for it in items:
		opt.add_item(str(it))

func _select_option_by_text(opt: OptionButton, target: String) -> void:
	if opt == null:
		return
	for i in range(opt.item_count):
		if opt.get_item_text(i).to_upper() == target.to_upper():
			opt.select(i)
			return

func _clear_children(node: Node) -> void:
	if node == null:
		return
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()

func _log_status(bbcode_msg: String) -> void:
	if _status_label != null:
		_status_label.text = bbcode_msg