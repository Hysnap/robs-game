# res://tools/importers/csv_bulk_importer.gd
extends SceneTree

const ScenarioManifestManagerScript = preload("res://systems/scenario_manifest_manager.gd")
const DevAuthoringValidatorScript = preload("res://systems/dev_authoring/dev_authoring_validator.gd")
const CatalogValidatorScript = preload("res://systems/catalog_validator.gd")

const DATA_MODULES_ROOT: String = "res://data_modules/"
const UI_STRINGS_PATH: String = "res://data_modules/core/localization/ui_strings.csv"

const COMMODITY_REQUIRED_COLS: Array[String] = ["id", "module", "category", "display_name_token", "base_cost"]
const VERB_REQUIRED_COLS: Array[String] = ["verb_token", "module", "label_token", "allowed_scopes"]
const VALID_DRIVERS: Array[String] = [
	"NEED_LED", "DEMAND_LED", "SUPPLIER_LED", "FOMO_LED", "HABIT_LED",
	"STATUS_LED", "EVENT_LED", "SUBSTITUTION_LED", "DERIVED_B2B", "CREDIT_TICK_LED"
]
const VALID_LEGALITIES: Array[String] = ["LEGAL", "GREY", "ILLEGAL"]

var _errors: Array[String] = []
var _warnings: Array[String] = []
var _created_files: Array[String] = []
var _appended_files: Array[String] = []
var _added_loc_keys: Array[String] = []

var _valid_primitives: Array[String] = []
var _valid_models: Array[String] = []
var _valid_scopes: Array[String] = []
var _valid_impacts: Array[String] = []
var _valid_categories: Array[String] = []

func _init() -> void:
	var args: Dictionary = _parse_cli_args(OS.get_cmdline_user_args())
	var commodities_csv: String = str(args.get("commodities", "")).strip_edges()
	var verbs_csv: String = str(args.get("verbs", "")).strip_edges()
	var report_path: String = str(args.get("report", "")).strip_edges()

	if args.has("overwrite"):
		_fail_fatal("Flag --overwrite is disabled by policy. Additive append is always active; existing keys/files cannot be overwritten.")
		return

	if commodities_csv.is_empty() and verbs_csv.is_empty():
		_fail_fatal("Missing input CSV arguments. Provide --commodities=<path.csv> and/or --verbs=<path.csv>.")
		return

	_hydrate_canonical_whitelists()

	var existing_loc: Dictionary = _load_ui_strings(UI_STRINGS_PATH)
	var pending_loc_rows: Dictionary = {}
	var staged_writes: Array[Dictionary] = []

	if not commodities_csv.is_empty():
		_plan_commodities_import(commodities_csv, existing_loc, pending_loc_rows, staged_writes)

	if not verbs_csv.is_empty():
		_plan_verbs_import(verbs_csv, existing_loc, pending_loc_rows, staged_writes)

	if not _errors.is_empty():
		_emit_summary_report(report_path, false)
		for err in _errors:
			push_error("[CsvBulkImporter] " + err)
		quit(1)
		return

	for op in staged_writes:
		var target_path: String = str(op["path"])
		var mode: String = str(op["mode"])
		var payload: Dictionary = op["data"]
		if not _write_json_file(target_path, payload):
			_errors.append("Failed to write JSON file: %s" % target_path)
			_emit_summary_report(report_path, false)
			quit(1)
			return
		if mode == "CREATE":
			_created_files.append(target_path)
		else:
			_appended_files.append(target_path)

	if not pending_loc_rows.is_empty():
		if not _append_ui_strings(UI_STRINGS_PATH, pending_loc_rows):
			_errors.append("Failed to append localization tokens to: %s" % UI_STRINGS_PATH)
			_emit_summary_report(report_path, false)
			quit(1)
			return
		for k in pending_loc_rows.keys():
			_added_loc_keys.append(str(k))

	_emit_summary_report(report_path, true)
	quit(0)

## Resolves active whitelists directly from canonical registries & ScenarioManifestManager (DRY)
func _hydrate_canonical_whitelists() -> void:
	for p in DevAuthoringValidatorScript.ALLOWED_PRIMITIVES:
		_valid_primitives.append(str(p).strip_edges().to_upper())

	for m in CatalogValidatorScript.get_discovered_models():
		var m_up: String = str(m).strip_edges().to_upper()
		if not m_up.is_empty() and not _valid_models.has(m_up):
			_valid_models.append(m_up)
	for m in DevAuthoringValidatorScript.ALLOWED_CALC_MODELS:
		var m_up: String = str(m).strip_edges().to_upper()
		if not m_up.is_empty() and not _valid_models.has(m_up):
			_valid_models.append(m_up)

	for imp in DevAuthoringValidatorScript.get_registered_impacts():
		var imp_up: String = str(imp).strip_edges().to_upper()
		if not imp_up.is_empty() and not _valid_impacts.has(imp_up):
			_valid_impacts.append(imp_up)

	for cat in CatalogValidatorScript.get_discovered_categories():
		var cat_low: String = str(cat).strip_edges().to_lower()
		if not cat_low.is_empty() and not _valid_categories.has(cat_low):
			_valid_categories.append(cat_low)

	var routing_cfg: Dictionary = ScenarioManifestManagerScript.load_module("impact_routing")
	var routes: Dictionary = routing_cfg.get("routes", {})
	for route_key in routes.keys():
		var sc_up: String = str(route_key).strip_edges().to_upper()
		if not sc_up.is_empty() and not _valid_scopes.has(sc_up):
			_valid_scopes.append(sc_up)
	if not _valid_scopes.has("COMMODITY"):
		_valid_scopes.append("COMMODITY")

# -----------------------------------------------------------------------------
# Planning & Validation: Commodities
# -----------------------------------------------------------------------------

func _plan_commodities_import(
	csv_path: String,
	existing_loc: Dictionary,
	pending_loc: Dictionary,
	staged_writes: Array[Dictionary]
) -> void:
	var table: Dictionary = _read_csv_table(csv_path)
	if not table.get("ok", false):
		_errors.append("Commodities CSV error (%s): %s" % [csv_path, str(table.get("error", "Unknown error"))])
		return

	var headers: Array[String] = table["headers"]
	for req_col in COMMODITY_REQUIRED_COLS:
		if not headers.has(req_col):
			_errors.append("Commodities CSV missing required column '%s'." % req_col)
			return

	var seen_ids: Dictionary = {}
	var rows: Array = table["rows"]
	for idx in range(rows.size()):
		var row: Dictionary = rows[idx]
		var row_num: int = idx + 2
		var item_id: String = str(row.get("id", "")).strip_edges().to_upper()
		var module_slug: String = str(row.get("module", "")).strip_edges().to_lower()
		var category_slug: String = str(row.get("category", "")).strip_edges().to_lower()
		var name_token: String = str(row.get("display_name_token", "")).strip_edges()
		var cost_raw: String = str(row.get("base_cost", "")).strip_edges()

		if item_id.is_empty() or not _is_valid_upper_token(item_id):
			_errors.append("Commodities row %d: Invalid or empty 'id' ('%s')." % [row_num, item_id])
			continue
		if seen_ids.has(item_id):
			_errors.append("Commodities row %d: Duplicate 'id' '%s' within CSV batch." % [row_num, item_id])
			continue
		seen_ids[item_id] = true

		if module_slug.is_empty() or not _is_valid_slug(module_slug):
			_errors.append("Commodities row %d (%s): Invalid 'module' ('%s')." % [row_num, item_id, module_slug])
			continue
		if category_slug.is_empty() or not _is_valid_slug(category_slug):
			_errors.append("Commodities row %d (%s): Invalid 'category' ('%s')." % [row_num, item_id, category_slug])
			continue
		if not _valid_categories.is_empty() and not _valid_categories.has(category_slug):
			_errors.append("Commodities row %d (%s): Unknown category '%s' (discovered: %s)." % [
				row_num, item_id, category_slug, ", ".join(_valid_categories)
			])
			continue
		if not cost_raw.is_valid_float() or float(cost_raw) < 0.0:
			_errors.append("Commodities row %d (%s): 'base_cost' must be a non-negative number, got '%s'." % [row_num, item_id, cost_raw])
			continue

		if not _validate_and_stage_loc_token(row, row_num, item_id, name_token, existing_loc, pending_loc):
			continue

		var subpath: String = str(row.get("subpath", "")).strip_edges().to_lower().trim_prefix("/").trim_suffix("/")
		var item_slug: String = item_id.to_lower()
		var profile_file: String = str(row.get("profile_filename", "item_profile.json")).strip_edges()
		if profile_file.is_empty():
			profile_file = "item_profile.json"

		var base_dir: String = DATA_MODULES_ROOT.path_join(module_slug).path_join("commodities").path_join(category_slug)
		if not subpath.is_empty():
			base_dir = base_dir.path_join(subpath)
		if profile_file == "item_profile.json":
			base_dir = base_dir.path_join(item_slug)
		var target_json_path: String = base_dir.path_join(profile_file)

		var incoming: Dictionary = {
			"_meta": {
				"version": "1.0.0",
				"scope": "COMMODITY_PROFILE",
				"module": module_slug
			},
			"id": item_id,
			"display_name": name_token,
			"category": category_slug.to_upper(),
			"base_cost": float(cost_raw)
		}

		if not str(row.get("tax_class", "")).strip_edges().is_empty():
			incoming["tax_class"] = str(row["tax_class"]).strip_edges().to_upper()
		if not str(row.get("duty_class", "")).strip_edges().is_empty():
			incoming["duty_class"] = str(row["duty_class"]).strip_edges().to_upper()
		if not str(row.get("abv", "")).strip_edges().is_empty():
			if not str(row["abv"]).strip_edges().is_valid_float():
				_errors.append("Commodities row %d (%s): Invalid float 'abv'." % [row_num, item_id])
				continue
			incoming["abv"] = float(row["abv"])
		if not str(row.get("unit_volume_litres", "")).strip_edges().is_empty():
			if not str(row["unit_volume_litres"]).strip_edges().is_valid_float():
				_errors.append("Commodities row %d (%s): Invalid float 'unit_volume_litres'." % [row_num, item_id])
				continue
			incoming["unit_volume_litres"] = float(row["unit_volume_litres"])
		if not str(row.get("units_per_pack", "")).strip_edges().is_empty():
			if not str(row["units_per_pack"]).strip_edges().is_valid_float():
				_errors.append("Commodities row %d (%s): Invalid float 'units_per_pack'." % [row_num, item_id])
				continue
			incoming["units_per_pack"] = float(row["units_per_pack"])

		var tags_raw: String = str(row.get("tags", "")).strip_edges()
		if not tags_raw.is_empty():
			var tag_list: Array[String] = []
			for t in tags_raw.split("|", false):
				var clean_t: String = t.strip_edges().to_upper()
				if not clean_t.is_empty():
					tag_list.append(clean_t)
			if not tag_list.is_empty():
				incoming["tags"] = tag_list

		var shelf_raw: String = str(row.get("shelf_life_ticks", "")).strip_edges()
		var degrades_to: String = str(row.get("degrades_to", "")).strip_edges().to_upper()
		if not shelf_raw.is_empty() or not degrades_to.is_empty():
			var decay_dict: Dictionary = {}
			if not shelf_raw.is_empty():
				if not shelf_raw.is_valid_int() or int(shelf_raw) <= 0:
					_errors.append("Commodities row %d (%s): 'shelf_life_ticks' must be a positive integer." % [row_num, item_id])
					continue
				decay_dict["shelf_life_ticks"] = int(shelf_raw)
			if not degrades_to.is_empty():
				decay_dict["degrades_to"] = degrades_to
			incoming["decay_properties"] = decay_dict

		var legality_raw: String = str(row.get("legality", "")).strip_edges().to_upper()
		var driver_raw: String = str(row.get("primary_driver", "")).strip_edges().to_upper()
		var daily_raw: String = str(row.get("base_per_capita_daily", "")).strip_edges()
		if not legality_raw.is_empty() or not driver_raw.is_empty() or not daily_raw.is_empty():
			var dp: Dictionary = {}
			if not legality_raw.is_empty():
				if not VALID_LEGALITIES.has(legality_raw):
					_errors.append("Commodities row %d (%s): Invalid legality '%s'." % [row_num, item_id, legality_raw])
					continue
				dp["legality"] = legality_raw
			if not driver_raw.is_empty():
				if not VALID_DRIVERS.has(driver_raw):
					_errors.append("Commodities row %d (%s): Invalid primary_driver '%s'." % [row_num, item_id, driver_raw])
					continue
				dp["primary_driver"] = driver_raw
			if not daily_raw.is_empty():
				if not daily_raw.is_valid_float() or float(daily_raw) < 0.0:
					_errors.append("Commodities row %d (%s): Invalid base_per_capita_daily '%s'." % [row_num, item_id, daily_raw])
					continue
				dp["base_per_capita_daily"] = float(daily_raw)
			incoming["demand_profile"] = dp

		if FileAccess.file_exists(target_json_path):
			var existing_dict: Dictionary = ScenarioManifestManagerScript.load_json_file(target_json_path)
			var merged_res: Dictionary = _additive_merge_dict(existing_dict, incoming, target_json_path)
			if not bool(merged_res.get("ok", false)):
				_errors.append("Commodities row %d (%s): %s" % [row_num, item_id, str(merged_res.get("error", "Conflict"))])
				continue
			if bool(merged_res.get("changed", false)):
				staged_writes.append({ "path": target_json_path, "mode": "APPEND", "data": merged_res["data"] })
		else:
			staged_writes.append({ "path": target_json_path, "mode": "CREATE", "data": incoming })

		var imp_verb: String = str(row.get("impact_verb", "")).strip_edges().to_lower()
		var imp_metric: String = str(row.get("impact_metric", "")).strip_edges().to_upper()
		if not imp_verb.is_empty() or not imp_metric.is_empty():
			var imp_model: String = str(row.get("impact_model", "LINEAR_PER_UNIT")).strip_edges().to_upper()
			var imp_factor_raw: String = str(row.get("impact_factor", "")).strip_edges()
			if imp_verb.is_empty() or imp_metric.is_empty() or not imp_factor_raw.is_valid_float():
				_errors.append("Commodities row %d (%s): Incomplete impact specification (requires impact_verb, impact_metric, numeric impact_factor)." % [row_num, item_id])
				continue
			if not _valid_impacts.is_empty() and not _valid_impacts.has(imp_metric):
				_errors.append("Commodities row %d (%s): Unregistered impact metric '%s'." % [row_num, item_id, imp_metric])
				continue
			if not _valid_models.has(imp_model):
				_errors.append("Commodities row %d (%s): Invalid impact_model '%s'." % [row_num, item_id, imp_model])
				continue
			var imp_path: String = base_dir.path_join(imp_verb).path_join("%s.json" % imp_metric.to_lower())
			if FileAccess.file_exists(imp_path):
				_errors.append("Commodities row %d (%s): Impact file '%s' already exists (overwrites disabled)." % [row_num, item_id, imp_path])
				continue
			staged_writes.append({
				"path": imp_path,
				"mode": "CREATE",
				"data": {
					"metric": imp_metric,
					"model": imp_model,
					"factor": float(imp_factor_raw),
					"params": {}
				}
			})

# -----------------------------------------------------------------------------
# Planning & Validation: Verbs & Flavour Overlays
# -----------------------------------------------------------------------------

func _plan_verbs_import(
	csv_path: String,
	existing_loc: Dictionary,
	pending_loc: Dictionary,
	staged_writes: Array[Dictionary]
) -> void:
	var table: Dictionary = _read_csv_table(csv_path)
	if not table.get("ok", false):
		_errors.append("Verbs CSV error (%s): %s" % [csv_path, str(table.get("error", "Unknown error"))])
		return

	var headers: Array[String] = table["headers"]
	for req_col in VERB_REQUIRED_COLS:
		if not headers.has(req_col):
			_errors.append("Verbs CSV missing required column '%s'." % req_col)
			return

	var rows: Array = table["rows"]
	for idx in range(rows.size()):
		var row: Dictionary = rows[idx]
		var row_num: int = idx + 2
		var verb_token: String = str(row.get("verb_token", "")).strip_edges().to_upper()
		var module_slug: String = str(row.get("module", "")).strip_edges().to_lower()
		var label_token: String = str(row.get("label_token", "")).strip_edges()
		var scopes_raw: String = str(row.get("allowed_scopes", "")).strip_edges()

		if verb_token.is_empty() or not _is_valid_upper_token(verb_token):
			_errors.append("Verbs row %d: Invalid or empty 'verb_token' ('%s')." % [row_num, verb_token])
			continue
		if module_slug.is_empty() or not _is_valid_slug(module_slug):
			_errors.append("Verbs row %d (%s): Invalid 'module' ('%s')." % [row_num, verb_token, module_slug])
			continue

		var parsed_scopes: Array[String] = []
		for sc in scopes_raw.split("|", false):
			var clean_sc: String = sc.strip_edges().to_upper()
			if not clean_sc.is_empty():
				if not _valid_scopes.has(clean_sc):
					_errors.append("Verbs row %d (%s): Unknown target scope '%s'." % [row_num, verb_token, clean_sc])
				elif not parsed_scopes.has(clean_sc):
					parsed_scopes.append(clean_sc)
		if parsed_scopes.is_empty():
			_errors.append("Verbs row %d (%s): 'allowed_scopes' must list at least one valid scope." % [row_num, verb_token])
			continue

		if not _validate_and_stage_loc_token(row, row_num, verb_token, label_token, existing_loc, pending_loc):
			continue

		var steps_arr: Array = []
		var steps_raw: String = str(row.get("steps_json", "")).strip_edges()
		if not steps_raw.is_empty():
			var parsed_steps = JSON.parse_string(steps_raw)
			if not (parsed_steps is Array):
				_errors.append("Verbs row %d (%s): 'steps_json' must be a valid JSON array." % [row_num, verb_token])
				continue
			for st in parsed_steps:
				if not (st is Dictionary):
					_errors.append("Verbs row %d (%s): Each step in 'steps_json' must be an object." % [row_num, verb_token])
					continue
				var prim: String = str(st.get("primitive", "")).strip_edges().to_upper()
				if not _valid_primitives.has(prim):
					_errors.append("Verbs row %d (%s): Unregistered primitive '%s' in steps_json." % [row_num, verb_token, prim])
					continue
				steps_arr.append(st)

		var verb_dir: String = DATA_MODULES_ROOT.path_join(module_slug).path_join("verbs").path_join(verb_token.to_lower())
		var def_path: String = verb_dir.path_join("verb_definition.json")
		var scope_path: String = verb_dir.path_join("target_scope.json")

		var def_payload: Dictionary = {
			"_meta": {
				"version": "1.0.0",
				"verb_token": verb_token,
				"module": module_slug
			},
			"steps": steps_arr
		}

		if FileAccess.file_exists(def_path):
			var existing_def: Dictionary = ScenarioManifestManagerScript.load_json_file(def_path)
			var merged_def: Dictionary = _additive_merge_verb_def(existing_def, def_payload, def_path)
			if not bool(merged_def.get("ok", false)):
				_errors.append("Verbs row %d (%s): %s" % [row_num, verb_token, str(merged_def.get("error", "Conflict"))])
				continue
			if bool(merged_def.get("changed", false)):
				staged_writes.append({ "path": def_path, "mode": "APPEND", "data": merged_def["data"] })
		else:
			staged_writes.append({ "path": def_path, "mode": "CREATE", "data": def_payload })

		var flags_raw: String = str(row.get("form_flags", "")).strip_edges().to_lower()
		var flag_list: Array[String] = []
		for fl in flags_raw.split("|", false):
			flag_list.append(fl.strip_edges())

		var scope_payload: Dictionary = {
			"_meta": {
				"entity_type": "VERB_TARGET_SCOPE",
				"verb": verb_token,
				"module": module_slug
			},
			"label_token": label_token,
			"target_scopes": parsed_scopes,
			"form_layout": {
				"amount_section": {
					"visible": flag_list.has("requires_amount"),
					"required": flag_list.has("requires_amount"),
					"label_token": "UI_LBL_QUANTITY",
					"mapped_field": "amount"
				},
				"location_section": {
					"visible": flag_list.has("requires_location") or parsed_scopes.has("DISTRICT") or parsed_scopes.has("ESTABLISHMENT"),
					"required": flag_list.has("requires_location"),
					"label_token": "UI_LBL_VENUE",
					"mapped_field": "target_node_id"
				},
				"contact_section": {
					"visible": flag_list.has("requires_contact") or parsed_scopes.has("RESIDENT"),
					"required": flag_list.has("requires_contact"),
					"label_token": "UI_LBL_RECIPIENT",
					"mapped_field": "counterparty_id"
				}
			}
		}

		var mode_val: String = str(row.get("mode", "")).strip_edges().to_upper()
		var intent_val: String = str(row.get("intent", "")).strip_edges().to_upper()
		if not mode_val.is_empty():
			scope_payload["form_layout"]["mode_section"] = {
				"visible": true,
				"required": true,
				"options": [{ "id": mode_val, "label_token": label_token }]
			}
		if not intent_val.is_empty():
			scope_payload["form_layout"]["intent_section"] = {
				"visible": true,
				"required": true,
				"options": [{ "id": intent_val, "label_token": label_token }]
			}

		if FileAccess.file_exists(scope_path):
			var existing_scope: Dictionary = ScenarioManifestManagerScript.load_json_file(scope_path)
			var merged_scope: Dictionary = _additive_merge_target_scope(existing_scope, scope_payload, scope_path)
			if not bool(merged_scope.get("ok", false)):
				_errors.append("Verbs row %d (%s): %s" % [row_num, verb_token, str(merged_scope.get("error", "Conflict"))])
				continue
			if bool(merged_scope.get("changed", false)):
				staged_writes.append({ "path": scope_path, "mode": "APPEND", "data": merged_scope["data"] })
		else:
			staged_writes.append({ "path": scope_path, "mode": "CREATE", "data": scope_payload })

		var imp_metric: String = str(row.get("impact_metric", "")).strip_edges().to_upper()
		if not imp_metric.is_empty():
			if not _valid_impacts.is_empty() and not _valid_impacts.has(imp_metric):
				_errors.append("Verbs row %d (%s): Unregistered impact metric '%s'." % [row_num, verb_token, imp_metric])
				continue
			var imp_delta_raw: String = str(row.get("impact_delta", "")).strip_edges()
			if not imp_delta_raw.is_valid_float():
				_errors.append("Verbs row %d (%s): 'impact_delta' must be numeric when 'impact_metric' is set." % [row_num, verb_token])
				continue
			var imp_slug: String = str(row.get("impact_file", "")).strip_edges().to_lower()
			if imp_slug.is_empty():
				var prefix: String = mode_val.to_lower() if not mode_val.is_empty() else (intent_val.to_lower() if not intent_val.is_empty() else verb_token.to_lower())
				imp_slug = "%s_%s.json" % [prefix, imp_metric.to_lower()]
			elif not imp_slug.ends_with(".json"):
				imp_slug += ".json"

			var imp_full_path: String = verb_dir.path_join("impacts").path_join(imp_slug)
			if FileAccess.file_exists(imp_full_path):
				_errors.append("Verbs row %d (%s): Impact file '%s' already exists (overwrites disabled)." % [row_num, verb_token, imp_full_path])
				continue

			var imp_doc: Dictionary = {
				"_meta": {
					"version": "1.0.0",
					"module": module_slug,
					"verb_token": verb_token
				},
				"metric_id": imp_metric,
				"delta": float(imp_delta_raw)
			}
			var target_role: String = str(row.get("impact_target_role", "")).strip_edges().to_upper()
			if not target_role.is_empty():
				imp_doc["target_role"] = target_role
			if not mode_val.is_empty():
				imp_doc["when"] = { "mode": mode_val }
			elif not intent_val.is_empty():
				imp_doc["when"] = { "intent": intent_val }

			staged_writes.append({ "path": imp_full_path, "mode": "CREATE", "data": imp_doc })

# -----------------------------------------------------------------------------
# Non-Destructive Additive Merge Helpers (Never Overwrite Existing Keys)
# -----------------------------------------------------------------------------

func _additive_merge_dict(existing: Dictionary, incoming: Dictionary, path: String) -> Dictionary:
	var result: Dictionary = existing.duplicate(true)
	var changed: bool = false
	for k in incoming.keys():
		if k == "_meta":
			continue
		if not result.has(k) or result[k] == null:
			result[k] = incoming[k]
			changed = true
		elif result[k] is Dictionary and incoming[k] is Dictionary:
			var sub: Dictionary = _additive_merge_dict(result[k], incoming[k], path + "." + str(k))
			if not bool(sub.get("ok", false)):
				return sub
			if bool(sub.get("changed", false)):
				result[k] = sub["data"]
				changed = true
		elif result[k] is Array and incoming[k] is Array:
			var arr: Array = result[k].duplicate(true)
			for item in incoming[k]:
				if not arr.has(item):
					arr.append(item)
					changed = true
			result[k] = arr
		elif str(result[k]) != str(incoming[k]):
			return {
				"ok": false,
				"error": "Conflict on existing key '%s' in '%s' (existing='%s', incoming='%s'). Overwrites are disabled." % [
					str(k), path, str(result[k]), str(incoming[k])
				]
			}
	return { "ok": true, "changed": changed, "data": result }

func _additive_merge_verb_def(existing: Dictionary, incoming: Dictionary, path: String) -> Dictionary:
	var result: Dictionary = existing.duplicate(true)
	var changed: bool = false
	var steps: Array = result.get("steps", []).duplicate(true)
	var existing_ids: Dictionary = {}
	for st in steps:
		if st is Dictionary and st.has("step_id"):
			existing_ids[str(st["step_id"])] = true

	for new_st in incoming.get("steps", []):
		if not (new_st is Dictionary):
			continue
		var sid: String = str(new_st.get("step_id", ""))
		if not sid.is_empty() and existing_ids.has(sid):
			return { "ok": false, "error": "Step '%s' already exists in '%s' (overwrites disabled)." % [sid, path] }
		if not sid.is_empty():
			existing_ids[sid] = true
		steps.append(new_st.duplicate(true))
		changed = true

	result["steps"] = steps
	return { "ok": true, "changed": changed, "data": result }

func _additive_merge_target_scope(existing: Dictionary, incoming: Dictionary, path: String) -> Dictionary:
	var result: Dictionary = existing.duplicate(true)
	var changed: bool = false

	var scopes: Array = result.get("target_scopes", []).duplicate()
	for sc in incoming.get("target_scopes", []):
		if not scopes.has(sc):
			scopes.append(sc)
			changed = true
	result["target_scopes"] = scopes

	var form_layout: Dictionary = result.get("form_layout", {}).duplicate(true)
	var inc_layout: Dictionary = incoming.get("form_layout", {})
	for sec_key in ["mode_section", "intent_section"]:
		if inc_layout.has(sec_key):
			var sec: Dictionary = form_layout.get(sec_key, { "visible": true, "required": true, "options": [] }).duplicate(true)
			var opts: Array = sec.get("options", []).duplicate(true)
			for opt in inc_layout[sec_key].get("options", []):
				var opt_id: String = str(opt.get("id", ""))
				var exists := false
				for cur in opts:
					if cur is Dictionary and str(cur.get("id", "")) == opt_id:
						exists = true
						break
				if exists:
					return { "ok": false, "error": "Option '%s' already exists in %s (%s)." % [opt_id, sec_key, path] }
				opts.append(opt)
				changed = true
			sec["options"] = opts
			form_layout[sec_key] = sec
	result["form_layout"] = form_layout
	return { "ok": true, "changed": changed, "data": result }

# -----------------------------------------------------------------------------
# Localization Validation & Appending (ui_strings.csv)
# -----------------------------------------------------------------------------

func _validate_and_stage_loc_token(
	row: Dictionary,
	row_num: int,
	entity_id: String,
	token: String,
	existing_loc: Dictionary,
	pending_loc: Dictionary
) -> bool:
	if token.is_empty() or not token.begins_with("UI_") or not _is_valid_upper_token(token):
		_errors.append("Row %d (%s): Localization token must start with 'UI_' (got '%s')." % [row_num, entity_id, token])
		return false

	var label_en: String = str(row.get("label_en", "")).strip_edges()
	if existing_loc.has(token) or pending_loc.has(token):
		return true

	if label_en.is_empty():
		_errors.append("Row %d (%s): New localization token '%s' is missing required 'label_en'." % [row_num, entity_id, token])
		return false

	var en_gb: String = str(row.get("en_GB", label_en)).strip_edges()
	var en_us: String = str(row.get("en_US", label_en)).strip_edges()
	var de_de: String = str(row.get("de_DE", label_en)).strip_edges()
	var fr_fr: String = str(row.get("fr_FR", label_en)).strip_edges()
	var es_es: String = str(row.get("es_ES", label_en)).strip_edges()
	var es_us: String = str(row.get("es_US", es_es)).strip_edges()
	pending_loc[token] = [token, label_en, en_gb, en_us, de_de, fr_fr, es_es, es_us]
	return true

func _load_ui_strings(path: String) -> Dictionary:
	var keys: Dictionary = {}
	var table: Dictionary = _read_csv_table(path)
	if not table.get("ok", false):
		return keys
	for row in table["rows"]:
		var k: String = str(row.get("keys", row.get("key", ""))).strip_edges()
		if not k.is_empty():
			keys[k] = true
	return keys

func _append_ui_strings(path: String, pending_rows: Dictionary) -> bool:
	var f := FileAccess.open(path, FileAccess.READ_WRITE)
	if f == null:
		return false
	var existing_text: String = f.get_as_text()
	f.seek_end()
	if not existing_text.is_empty() and not existing_text.ends_with("\n"):
		f.store_string("\n")
	for token in pending_rows.keys():
		var cols: Array = pending_rows[token]
		var quoted: Array[String] = []
		for col in cols:
			quoted.append("\"%s\"" % str(col).replace("\"", "\"\""))
		f.store_line(",".join(quoted))
	f.close()
	return true

# -----------------------------------------------------------------------------
# RFC-4180 CSV Reader, File Writers & Report Output
# -----------------------------------------------------------------------------

func _read_csv_table(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return { "ok": false, "error": "File not found: %s" % path }
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return { "ok": false, "error": "Unable to open file: %s" % path }
	var raw_text: String = f.get_as_text()
	f.close()

	var records: Array = _parse_csv_records(raw_text)
	if records.is_empty():
		return { "ok": false, "error": "CSV file is empty." }

	var headers: Array[String] = []
	for h in records[0]:
		headers.append(str(h).strip_edges())

	var rows: Array[Dictionary] = []
	for i in range(1, records.size()):
		var rec: Array = records[i]
		if rec.size() == 1 and str(rec[0]).strip_edges().is_empty():
			continue
		var row_dict: Dictionary = {}
		for c in range(headers.size()):
			row_dict[headers[c]] = str(rec[c]) if c < rec.size() else ""
		rows.append(row_dict)

	return { "ok": true, "headers": headers, "rows": rows }

func _parse_csv_records(text: String) -> Array:
	var records: Array = []
	var current_row: Array[String] = []
	var field: String = ""
	var in_quotes: bool = false
	var i: int = 0
	var length: int = text.length()

	while i < length:
		var ch: String = text[i]
		if in_quotes:
			if ch == "\"":
				if i + 1 < length and text[i + 1] == "\"":
					field += "\""
					i += 2
					continue
				in_quotes = false
			else:
				field += ch
		else:
			if ch == "\"":
				in_quotes = true
			elif ch == ",":
				current_row.append(field)
				field = ""
			elif ch == "\r":
				if i + 1 < length and text[i + 1] == "\n":
					i += 1
				current_row.append(field)
				records.append(current_row)
				current_row = []
				field = ""
			elif ch == "\n":
				current_row.append(field)
				records.append(current_row)
				current_row = []
				field = ""
			else:
				field += ch
		i += 1

	if in_quotes:
		_errors.append("Malformed CSV: unclosed quote at end of file.")
	if not field.is_empty() or not current_row.is_empty():
		current_row.append(field)
		records.append(current_row)
	return records

func _write_json_file(path: String, data: Dictionary) -> bool:
	var dir_path: String = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		var err: int = DirAccess.make_dir_recursive_absolute(dir_path)
		if err != OK:
			return false
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "\t") + "\n")
	f.close()
	return true

func _emit_summary_report(report_path: String, success: bool) -> void:
	var lines: Array[String] = [
		"=== CSV BULK IMPORTER SUMMARY REPORT ===",
		"Status: %s" % ("SUCCESS" if success else "FAILED (ABORTED — ZERO PARTIAL WRITES)"),
		"Files Created: %d" % _created_files.size(),
		"Files Appended (Additive): %d" % _appended_files.size(),
		"Localization Tokens Added: %d" % _added_loc_keys.size(),
		"Errors: %d | Warnings: %d" % [_errors.size(), _warnings.size()]
	]
	for p in _created_files:
		lines.append("  [CREATED] %s" % p)
	for p in _appended_files:
		lines.append("  [APPENDED] %s" % p)
	for k in _added_loc_keys:
		lines.append("  [LOC_ADDED] %s" % k)
	for w in _warnings:
		lines.append("  [WARNING] %s" % w)
	for e in _errors:
		lines.append("  [ERROR] %s" % e)

	var report_text: String = "\n".join(lines)
	print("\n" + report_text + "\n")
	if not report_path.is_empty():
		var f := FileAccess.open(report_path, FileAccess.WRITE)
		if f != null:
			f.store_string(report_text + "\n")
			f.close()

func _fail_fatal(msg: String) -> void:
	_errors.append(msg)
	_emit_summary_report("", false)
	push_error("[CsvBulkImporter] " + msg)
	quit(1)

func _parse_cli_args(raw_args: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	for raw in raw_args:
		var arg: String = str(raw).strip_edges()
		if arg.begins_with("--"):
			arg = arg.substr(2)
		var eq_idx: int = arg.find("=")
		if eq_idx >= 0:
			out[arg.substr(0, eq_idx).to_lower()] = arg.substr(eq_idx + 1)
		elif not arg.is_empty():
			out[arg.to_lower()] = true
	return out

func _is_valid_upper_token(token: String) -> bool:
	var rx := RegEx.new()
	rx.compile("^[A-Z0-9_]+$")
	return rx.search(token) != null

func _is_valid_slug(slug: String) -> bool:
	var rx := RegEx.new()
	rx.compile("^[a-z0-9_]+$")
	return rx.search(slug) != null