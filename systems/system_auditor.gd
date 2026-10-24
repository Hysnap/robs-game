# res://systems/system_auditor.gd
class_name SystemAuditor
extends RefCounted

const MANIFEST_MGR = preload("res://systems/scenario_manifest_manager.gd")

## Audits runtime state and database relational health after generation
static func audit_generation_health(world_state: Dictionary, db_manager) -> Dictionary:
	var report := {
		"timestamp": Time.get_datetime_string_from_system(),
		"is_healthy": true,
		"errors": [],
		"warnings": [],
		"metrics": {}
	}

	var cfg := ConfigFile.new()
	var strict_mode := true
	if cfg.load(MANIFEST_MGR.BUSINESS_RULES_PATH) == OK:
		strict_mode = bool(cfg.get_value("system_diagnostics", "strict_audit_mode", true))

	# 1. District Grid & Spatial Sanity
	var districts: Dictionary = world_state.get("districts", {})
	if districts.is_empty():
		report["errors"].append("CRITICAL: world_state has zero districts registered.")
		report["is_healthy"] = false
	else:
		var total_pop: int = 0
		var zero_pop_count: int = 0
		for dist_id in districts.keys():
			var d: Dictionary = districts[dist_id]
			var pop: int = int(d.get("population", 0))
			total_pop += pop
			if pop == 0 and not str(d.get("district_type", "")).begins_with("local_government") and not str(d.get("district_type", "")).begins_with("sports_arena"):
				zero_pop_count += 1
				
		report["metrics"]["total_districts"] = districts.size()
		report["metrics"]["total_population"] = total_pop
		
		if zero_pop_count * 2 > districts.size():
			report["warnings"].append("Unusually high number of zero-population residential districts: %d" % zero_pop_count)

	# 2. Database Relational Consistency Checks
		var db_ready: bool = false
		if db_manager != null:
			if db_manager.has_method("is_database_open"):
				db_ready = db_manager.is_database_open()
			elif "is_open" in db_manager:
				db_ready = bool(db_manager.is_open)
			else:
				# Direct fallback test query
				var test = db_manager.query_rows("SELECT 1;")
				db_ready = not test.is_empty()
		# Verify Establishments Exist
		var estab_res = db_manager.query_rows("SELECT COUNT(*) as count FROM establishments;")
		var estab_count: int = int(estab_res[0]["count"]) if not estab_res.is_empty() else 0
		report["metrics"]["total_establishments"] = estab_count
		if estab_count == 0:
			report["errors"].append("CRITICAL: Zero establishments committed to SQLite.")
			report["is_healthy"] = false

		# Verify Households Exist
		var house_res = db_manager.query_rows("SELECT COUNT(*) as count FROM households;")
		var house_count: int = int(house_res[0]["count"]) if not house_res.is_empty() else 0
		report["metrics"]["total_households"] = house_count
		if house_count == 0:
			report["errors"].append("CRITICAL: Zero households committed to SQLite.")
			report["is_healthy"] = false

		# Verify Orphaned Contracts (Contracts pointing to invalid establishments)
		var orphan_contracts = db_manager.query_rows("""
			SELECT COUNT(*) as count FROM livelihood_contracts 
			WHERE employer_entity_id LIKE 'ESTAB_%' 
			AND CAST(SUBSTR(employer_entity_id, 7) AS INTEGER) NOT IN (SELECT establishment_id FROM establishments);
		""")
		var orphan_count: int = int(orphan_contracts[0]["count"]) if not orphan_contracts.is_empty() else 0
		if orphan_count > 0:
			report["errors"].append("Database integrity error: %d contracts reference non-existent establishment IDs." % orphan_count)
			report["is_healthy"] = false

		# Verify Social Graph Connectivity (Ensure residents have at least 1 edge)
		var isolated_residents = db_manager.query_rows("""
			SELECT COUNT(*) as count FROM residents 
			WHERE resident_id NOT IN (
				SELECT from_resident_id FROM social_relationships 
				UNION 
				SELECT to_resident_id FROM social_relationships
			);
		""")
		var isolated_count: int = int(isolated_residents[0]["count"]) if not isolated_residents.is_empty() else 0
		if isolated_count > 0:
			report["warnings"].append("%d residents are completely isolated in the social graph (zero Dunbar edges)." % isolated_count)

	# 3. Output to Logger Autoload
	_log_audit_report(report)

	if strict_mode and not report["is_healthy"]:
		assert(false, "HALT: SystemAuditor detected fatal integrity violations. Inspect session_output.log.")

	return report

static func _log_audit_report(report: Dictionary) -> void:
	var status_text := "100% HEALTHY" if report["is_healthy"] else "DEFECTS DETECTED"
	SystemLogger.log_info("[SystemAuditor] --- RUNTIME HEALTH AUDIT RESULT: %s ---" % status_text)
	
	SystemLogger.log_info("[SystemAuditor] --- RUNTIME HEALTH AUDIT RESULT: %s ---" % ("100% HEALTHY" if report["is_healthy"] else "DEFECTS DETECTED"))
	for k in report["metrics"].keys():
		SystemLogger.log_debug("[SystemAuditor] • %s: %s" % [k.capitalize(), str(report["metrics"][k])])

	for w in report["warnings"]:
		SystemLogger.log_warn("[SystemAuditor] ⚠️ %s" % w)
	for e in report["errors"]:
		SystemLogger.log_error("[SystemAuditor] ❌ %s" % e)