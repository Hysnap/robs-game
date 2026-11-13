# res://systems/dev_authoring/dev_authoring_validator.gd
class_name DevAuthoringValidator
extends RefCounted

const FileSystemCrawlerScript = preload("res://systems/file_system_crawler.gd")
const CommodityManagerScript = preload("res://systems/commodity_manager.gd")

const DATA_MODULES_ROOT := "res://data_modules/"

const ALLOWED_PRIMITIVES: Array[String] = [
	"REQUIRE",
	"MOVE_ACTOR",
	"TRANSFER_ITEM",
	"DEDUCT_ITEM",
	"CREDIT_ITEM",
	"CALL_VERB"
]

const ALLOWED_LOGIC_GATES: Array[String] = [
	"AND",
	"OR",
	"NAND",
	"NOR",
	"XOR"
]

const ALLOWED_OPERATORS: Array[String] = [
	">=",
	"<=",
	"==",
	"!=",
	">",
	"<",
	"BETWEEN",
	"NOT_BETWEEN"
]

const ALLOWED_REQUIRE_DOMAINS: Array[String] = [
	"COMMODITY",
	"LOCATION",
	"ATTRIBUTE"
]

const ALLOWED_CALC_MODELS: Array[String] = [
	"LINEAR_PER_UNIT",
	"FLAT_DELTA",
	"EXPONENTIAL",
	"LOGARITHMIC",
	"DIMINISHING_RETURNS"
]

# =====================================================================
# 1. LIVE CATALOG & WHITELIST DISCOVERY
# =====================================================================

## Scans all data_modules/*/impacts/ directories to build the strict whitelist of existing impact metrics
static func get_registered_impacts() -> Array[String]:
	var metrics: Array[String] = []
	var all_json: Array[String] = FileSystemCrawlerScript.find_files_recursive(DATA_MODULES_ROOT, "", ".json")

	for path in all_json:
		if not path.contains("/impacts/"):
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed is Dictionary:
			var key: String = str(parsed.get("metric_key", parsed.get("metric", ""))).strip_edges().to_upper()
			if key.is_empty():
				var base_file: String = path.get_file().get_basename().to_upper()
				if base_file != "PROFILE":
					key = base_file
				else:
					key = path.get_base_dir().get_file().to_upper()
			if not key.is_empty() and not metrics.has(key):
				metrics.append(key)

	metrics.sort()
	return metrics

## Discovers all registered commodity IDs across core and flavour modules
static func get_registered_commodities() -> Array[String]:
	var ids: Array[String] = []
	var catalog: Dictionary = CommodityManagerScript.load_hierarchical_commodities(DATA_MODULES_ROOT.path_join("core/commodities/"))
	for k in catalog.keys():
		var clean_k: String = str(k).strip_edges().to_upper()
		if not clean_k.is_empty() and not ids.has(clean_k):
			ids.append(clean_k)

	if not ids.has("CASH"):
		ids.append("CASH")

	ids.sort()
	return ids

## Discovers all mounted declarative verb tokens across data_modules
static func get_registered_verbs() -> Array[String]:
	var verbs: Array[String] = []
	var verb_files: Array[String] = FileSystemCrawlerScript.find_files_recursive(DATA_MODULES_ROOT, "verb_definition.json")

	for vf in verb_files:
		var f := FileAccess.open(vf, FileAccess.READ)
		if f == null:
			continue
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed is Dictionary:
			var meta: Dictionary = parsed.get("_meta", {})
			var token: String = str(meta.get("verb_token", vf.get_base_dir().get_file())).strip_edges().to_upper()
			if not token.is_empty() and not verbs.has(token):
				verbs.append(token)

	verbs.sort()
	return verbs

## Discovers available data module namespaces (e.g. "core", "crime")
static func get_data_modules() -> Array[String]:
	var modules: Array[String] = []
	var dir := DirAccess.open(DATA_MODULES_ROOT)
	if dir != null:
		dir.list_dir_begin()
		var entry: String = dir.get_next()
		while entry != "":
			if dir.current_is_dir() and not entry.begins_with("."):
				modules.append(entry.to_lower())
			entry = dir.get_next()
		dir.list_dir_end()
	if not modules.has("core"):
		modules.append("core")
	modules.sort()
	return modules

# =====================================================================
# 2. TWO-TIER SCHEMA & WHITELIST VALIDATORS (DRAFT vs. LIVE)
# =====================================================================

## Helper to package the standardized two-tier validation response
static func _build_validation_result(blocking_errors: Array[String], publish_warnings: Array[String]) -> Dictionary:
	var can_draft: bool = blocking_errors.is_empty()
	var can_live: bool = blocking_errors.is_empty() and publish_warnings.is_empty()
	return {
		"valid": can_live,
		"can_save_draft": can_draft,
		"can_make_live": can_live,
		"blocking_errors": blocking_errors,
		"publish_warnings": publish_warnings,
		"errors": blocking_errors + publish_warnings
	}

## Validates a Commodity authoring payload (Hard blocks on path/ID, soft-locks on missing properties)
static func validate_commodity_spec(spec: Dictionary, allowed_impacts: Array[String]) -> Dictionary:
	var blocking_errors: Array[String] = []
	var publish_warnings: Array[String] = []

	var item_id: String = str(spec.get("id", "")).strip_edges().to_upper()
	if item_id.is_empty() or not item_id.is_valid_identifier():
		blocking_errors.append("Commodity ID must be a non-empty valid identifier (e.g. 'BEER_KEG').")

	var category: String = str(spec.get("category", "")).strip_edges().to_lower()
	if category.is_empty():
		blocking_errors.append("Category folder slug is required to determine save path (e.g. 'consumables').")

	var unit_mass: float = float(spec.get("unit_mass_kg", -1.0))
	if unit_mass < 0.0:
		publish_warnings.append("unit_mass_kg must be >= 0.0 before going live.")

	var unit_vol: float = float(spec.get("unit_volume_l", -1.0))
	if unit_vol < 0.0:
		publish_warnings.append("unit_volume_l must be >= 0.0 before going live.")

	var base_cost: float = float(spec.get("base_cost", -1.0))
	if base_cost < 0.0:
		publish_warnings.append("base_cost must be >= 0.0 before going live.")

	var impacts: Array = spec.get("impacts", [])
	for imp in impacts:
		if not (imp is Dictionary):
			blocking_errors.append("Malformed impact entry.")
			continue
		var metric: String = str(imp.get("metric_key", "")).strip_edges().to_upper()
		if not allowed_impacts.has(metric):
			blocking_errors.append("Unregistered impact metric '%s'. Only existing impacts may be allocated." % metric)
		var verb_ctx: String = str(imp.get("verb_context", "")).strip_edges().to_lower()
		if verb_ctx.is_empty():
			publish_warnings.append("Impact entry for '%s' is missing a verb_context (e.g. 'consume', 'buy')." % metric)

	return _build_validation_result(blocking_errors, publish_warnings)

## Validates a Recipe authoring payload (Allows draft save if input/output commodities are still being authored)
static func validate_recipe_spec(
	spec: Dictionary,
	allowed_commodities: Array[String],
	allowed_impacts: Array[String]
) -> Dictionary:
	var blocking_errors: Array[String] = []
	var publish_warnings: Array[String] = []

	var recipe_id: String = str(spec.get("recipe_id", "")).strip_edges().to_lower()
	if recipe_id.is_empty() or not recipe_id.is_valid_identifier():
		blocking_errors.append("Recipe ID must be a valid snake_case identifier (e.g. 'roll_cigarette').")

	var output_item: String = str(spec.get("output_commodity", "")).strip_edges().to_upper()
	if output_item.is_empty():
		publish_warnings.append("Output commodity is not yet assigned.")
	elif not allowed_commodities.has(output_item):
		publish_warnings.append("Output commodity '%s' does not exist yet in the commodity catalog." % output_item)

	var output_qty: float = float(spec.get("output_quantity", 0.0))
	if output_qty <= 0.0:
		publish_warnings.append("Output quantity must be > 0.0 before going live.")

	var inputs: Dictionary = spec.get("inputs", {})
	if inputs.is_empty():
		publish_warnings.append("Recipe requires at least one input commodity before going live.")
	else:
		for in_key in inputs.keys():
			var clean_in: String = str(in_key).strip_edges().to_upper()
			if not allowed_commodities.has(clean_in):
				publish_warnings.append("Input commodity '%s' is not yet registered in the commodity catalog." % clean_in)
			var in_qty: float = float(inputs[in_key])
			if in_qty <= 0.0:
				publish_warnings.append("Input commodity '%s' requires a quantity > 0.0." % clean_in)

	var impacts: Array = spec.get("impacts", [])
	for imp in impacts:
		if imp is Dictionary:
			var metric: String = str(imp.get("metric_key", "")).strip_edges().to_upper()
			if not allowed_impacts.has(metric):
				blocking_errors.append("Unregistered recipe impact metric '%s'. Only existing impacts may be allocated." % metric)

	return _build_validation_result(blocking_errors, publish_warnings)

## Validates a Macro Verb definition (Hard-blocks self-recursion; soft-locks unresolved branch steps for WIP saving)
static func validate_macro_verb_spec(
	spec: Dictionary,
	allowed_primitives: Array[String],
	allowed_verbs: Array[String],
	allowed_impacts: Array[String]
) -> Dictionary:
	var blocking_errors: Array[String] = []
	var publish_warnings: Array[String] = []

	var meta: Dictionary = spec.get("_meta", {})
	var verb_token: String = str(meta.get("verb_token", spec.get("verb_token", ""))).strip_edges().to_upper()
	if verb_token.is_empty() or not verb_token.is_valid_identifier():
		blocking_errors.append("Verb token must be a valid uppercase identifier (e.g. 'DELIVER_TO').")

	var sequence: Array = spec.get("sequence", spec.get("steps", []))
	if sequence.is_empty():
		publish_warnings.append("Macro verb sequence has no steps yet (saved as WIP draft).")
		return _build_validation_result(blocking_errors, publish_warnings)

	# 1. Gather all step IDs
	var step_ids: Dictionary = {}
	for i in range(sequence.size()):
		var step = sequence[i]
		if not (step is Dictionary):
			blocking_errors.append("Step at index %d is not a Dictionary." % i)
			continue
		var sid: String = str(step.get("step_id", "")).strip_edges()
		if sid.is_empty():
			blocking_errors.append("Step at index %d is missing 'step_id'." % i)
		elif step_ids.has(sid):
			blocking_errors.append("Duplicate step_id '%s' found in sequence." % sid)
		else:
			step_ids[sid] = true

	# 2. Validate each step
	for step in sequence:
		if not (step is Dictionary):
			continue
		var sid: String = str(step.get("step_id", "UNKNOWN")).strip_edges()
		var prim: String = str(step.get("primitive", "")).strip_edges().to_upper()

		if prim.is_empty():
			publish_warnings.append("Step '%s' has no primitive assigned yet." % sid)
			continue
		elif not allowed_primitives.has(prim):
			blocking_errors.append("Step '%s' uses unknown primitive '%s'." % [sid, prim])
			continue

		var params: Dictionary = step.get("params", {})

		if prim == "CALL_VERB":
			var target_verb: String = str(params.get("verb_token", "")).strip_edges().to_upper()
			if target_verb == verb_token:
				# Hard block: Self-recursion is never permitted even in draft
				blocking_errors.append("Step '%s' attempts recursive self-call to '%s'." % [sid, verb_token])
			elif target_verb.is_empty():
				publish_warnings.append("Step '%s' (CALL_VERB) has not selected a target verb yet." % sid)
			elif not allowed_verbs.has(target_verb):
				# Soft lock: allows developer to save WIP macro, build the missing sub-verb, and return
				publish_warnings.append("Step '%s' calls macro verb '%s' which has not been authored yet." % [sid, target_verb])

		elif prim == "REQUIRE":
			var logic_gate: String = str(params.get("logic_gate", step.get("logic_gate", "AND"))).strip_edges().to_upper()
			if not ALLOWED_LOGIC_GATES.has(logic_gate):
				blocking_errors.append("Step '%s' has unsupported logic_gate '%s'." % [sid, logic_gate])

			var cond_list: Array = params.get("conditions", step.get("conditions", []))
			if cond_list.is_empty():
				_validate_single_require_condition(params, sid, blocking_errors, publish_warnings)
			else:
				for c_idx in range(cond_list.size()):
					var cond = cond_list[c_idx]
					if cond is Dictionary:
						_validate_single_require_condition(cond, "%s[cond %d]" % [sid, c_idx], blocking_errors, publish_warnings)
					else:
						blocking_errors.append("Step '%s' condition %d is not a Dictionary." % [sid, c_idx])

		# Soft-lock check on branch jump targets (next_step, on_true, on_false)
		for branch_key in ["next_step", "on_true", "on_false"]:
			if step.has(branch_key) and step[branch_key] != null:
				var target_step: String = str(step[branch_key]).strip_edges()
				if not target_step.is_empty() and not (target_step.to_upper() in ["COMPLETE", "HALT"]):
					if not step_ids.has(target_step):
						publish_warnings.append("Step '%s' branch '%s' points to missing step_id '%s' (wire in before making live)." % [sid, branch_key, target_step])

	# 3. Validate verb-level impacts against strict whitelist (Hard Block)
	var impacts: Array = spec.get("impacts", [])
	for imp in impacts:
		if imp is Dictionary:
			var metric: String = str(imp.get("metric_key", "")).strip_edges().to_upper()
			if not allowed_impacts.has(metric):
				blocking_errors.append("Unregistered verb impact metric '%s'. Only existing impacts may be allocated." % metric)

	return _build_validation_result(blocking_errors, publish_warnings)

static func _validate_single_require_condition(
	cond: Dictionary,
	context_label: String,
	blocking_errors: Array[String],
	publish_warnings: Array[String]
) -> void:
	var domain: String = str(cond.get("domain", "COMMODITY")).strip_edges().to_upper()
	if not ALLOWED_REQUIRE_DOMAINS.has(domain):
		blocking_errors.append("%s uses invalid REQUIRE domain '%s'." % [context_label, domain])

	var op: String = str(cond.get("operator", ">=")).strip_edges().to_upper()
	if not ALLOWED_OPERATORS.has(op):
		blocking_errors.append("%s uses invalid operator '%s'." % [context_label, op])

	if str(cond.get("actor", "")).strip_edges().is_empty():
		publish_warnings.append("%s is missing 'actor' token." % context_label)

	if domain != "LOCATION" and str(cond.get("metric", "")).strip_edges().is_empty():
		publish_warnings.append("%s is missing 'metric' token." % context_label)

	if op in ["BETWEEN", "NOT_BETWEEN"]:
		var val = cond.get("value", null)
		var has_bounds: bool = (val is Array and val.size() >= 2) or (cond.has("lower") and cond.has("upper"))
		if not has_bounds:
			publish_warnings.append("%s uses '%s' operator but has not defined [lower, upper] bounds yet." % [context_label, op])