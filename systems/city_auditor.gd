class_name CityAuditor
extends SceneTree

const SQL_REFERENCE_PATH := "res://systems/city_auditor_queries.sql"
const DEFAULT_REPORT_DIR := "user://city_audits"
const DB_MANAGER = preload("res://systems/db_manager.gd")

## Allows this file to be launched directly with Godot's --script option.
## The audit intentionally stops if the active database has not already been opened.
func _init() -> void:
	call_deferred("_run_as_script")

func _run_as_script() -> void:
	var game_state = get_root().get_node_or_null("GameState")
	var world_state: Dictionary = {}
	if game_state != null and "world_state" in game_state:
		world_state = game_state.world_state

	var report := audit_and_save(world_state, DB_MANAGER)
	if report.has("report_path"):
		print("[CityAuditor] Report written to: %s" % report["report_path"])
	else:
		print("[CityAuditor] Audit did not write a report.")
		for error in report.get("errors", []):
			push_error("[CityAuditor] %s" % error)
	quit(0 if report.get("is_healthy", false) else 1)

## Read-only post-generation audit for social and environmental balance.
## This class never mutates world_state or the database.
static func audit_city(world_state: Dictionary, db_manager) -> Dictionary:
	var report := {
		"timestamp": Time.get_datetime_string_from_system(),
		"is_healthy": true,
		"errors": [],
		"warnings": [],
		"metrics": {},
		"distributions": {},
		"checks": []
	}

	_audit_world_state(report, world_state)

	if db_manager == null or not db_manager.has_method("query_rows"):
		_add_error(report, "A database manager with query_rows(sql) is required.")
	elif not db_manager.has_method("is_database_open") or not db_manager.is_database_open():
		_add_error(report, "The database must already be open; the auditor will not initialize it.")
	else:
		_audit_database(report, db_manager)

	return report

## Runs the audit and writes only the Markdown report to output_path.
static func audit_and_save(
	world_state: Dictionary,
	db_manager,
	output_path: String = ""
) -> Dictionary:
	var report := audit_city(world_state, db_manager)
	var resolved_path := output_path
	if resolved_path.is_empty():
		resolved_path = "%s/city_audit_%s.md" % [
			DEFAULT_REPORT_DIR,
			str(report["timestamp"]).replace(":", "-").replace(" ", "_")
		]

	var parent_dir := resolved_path.get_base_dir()
	if not parent_dir.is_empty() and not DirAccess.dir_exists_absolute(parent_dir):
		var dir_error := DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(parent_dir)
		)
		if dir_error != OK:
			_add_error(report, "Could not create report directory: %s" % parent_dir)
			return report

	var file := FileAccess.open(resolved_path, FileAccess.WRITE)
	if file == null:
		_add_error(report, "Could not open report path for writing: %s" % resolved_path)
		return report

	file.store_string(to_markdown(report))
	file.close()
	report["report_path"] = resolved_path
	return report

static func to_markdown(report: Dictionary) -> String:
	var lines: Array[String] = []
	var status := "PASS" if report.get("is_healthy", false) else "FAIL"
	lines.append("# City Audit Report")
	lines.append("")
	lines.append("- **Status:** %s" % status)
	lines.append("- **Generated:** `%s`" % report.get("timestamp", "unknown"))
	lines.append("- **Mode:** Read-only; no generated data was changed")
	lines.append("")

	_append_section(lines, "Summary", report.get("errors", []), report.get("warnings", []))
	_append_metrics(lines, report.get("metrics", {}))
	_append_distributions(lines, report.get("distributions", {}))
	_append_checks(lines, report.get("checks", []))

	return "\n".join(lines) + "\n"

static func _audit_world_state(report: Dictionary, world_state: Dictionary) -> void:
	var districts: Dictionary = world_state.get("districts", {})
	report["metrics"]["world_state_districts"] = districts.size()
	_add_check(report, "world_state_has_districts", not districts.is_empty())

	var zero_population_districts := 0
	for district_id in districts:
		var district: Dictionary = districts[district_id]
		if int(district.get("population", 0)) == 0:
			zero_population_districts += 1
	report["metrics"]["world_state_zero_population_districts"] = zero_population_districts

	if not districts.is_empty() and zero_population_districts * 2 > districts.size():
		_add_warning(report, "More than half of world_state districts have zero population.")

static func _audit_database(report: Dictionary, db_manager) -> void:
	var queries := _load_queries()
	if queries.is_empty():
		_add_error(report, "No SQL queries could be loaded from %s." % SQL_REFERENCE_PATH)
		return

	var counts := _query_rows(db_manager, queries, "entity_counts")
	for row in counts:
		var entity := str(row.get("entity", "unknown"))
		report["metrics"]["db_%s" % entity] = int(row.get("count", 0))

	_add_check(report, "database_has_districts", _metric(report, "db_districts") > 0)
	_add_check(report, "database_has_establishments", _metric(report, "db_establishments") > 0)
	_add_check(report, "database_has_households", _metric(report, "db_households") > 0)
	_add_check(report, "database_has_residents", _metric(report, "db_residents") > 0)

	var world_districts := _metric(report, "world_state_districts")
	var db_districts := _metric(report, "db_districts")
	if world_districts > 0 and world_districts != db_districts:
		_add_error(report, "world_state district count (%d) differs from SQLite (%d)." % [
			world_districts, db_districts
		])

	var district_rows := _query_rows(db_manager, queries, "district_distribution")
	report["distributions"]["districts"] = district_rows
	_audit_district_distribution(report, district_rows)

	var borough_rows := _query_rows(db_manager, queries, "borough_distribution")
	report["distributions"]["boroughs"] = borough_rows
	_audit_borough_distribution(report, borough_rows)

	report["distributions"]["establishment_categories"] = _query_rows(
		db_manager, queries, "establishment_categories"
	)
	report["distributions"]["employment_classes"] = _query_rows(
		db_manager, queries, "employment_classes"
	)
	report["distributions"]["social_degree"] = _query_rows(
		db_manager, queries, "social_degree"
	)

	var integrity := _query_rows(db_manager, queries, "integrity_checks")
	for row in integrity:
		var check_name := str(row.get("check_name", "integrity_check"))
		var failures := int(row.get("failures", 0))
		report["metrics"][check_name] = failures
		_add_check(report, check_name, failures == 0)
		if failures > 0:
			_add_error(report, "%s reported %d invalid records." % [check_name, failures])

	var capacity_rows := _query_rows(db_manager, queries, "district_capacity")
	report["distributions"]["district_capacity"] = capacity_rows
	for row in capacity_rows:
		var active_population := int(row.get("active_population", 0))
		var residential_capacity := int(row.get("residential_capacity", 0))
		if active_population > residential_capacity and residential_capacity > 0:
			_add_warning(report, "District %s has %d residents but capacity for %d." % [
				row.get("district_id", "unknown"), active_population, residential_capacity
			])

static func _audit_district_distribution(report: Dictionary, rows: Array) -> void:
	var zero_population := 0
	for row in rows:
		if int(row.get("active_population", 0)) == 0:
			zero_population += 1
	report["metrics"]["db_zero_population_districts"] = zero_population
	if not rows.is_empty() and zero_population * 2 > rows.size():
		_add_warning(report, "More than half of SQLite districts have zero active population.")

static func _audit_borough_distribution(report: Dictionary, rows: Array) -> void:
	var empty_boroughs := 0
	for row in rows:
		if int(row.get("active_population", 0)) == 0:
			empty_boroughs += 1
	report["metrics"]["empty_boroughs"] = empty_boroughs
	if empty_boroughs > 0:
		_add_warning(report, "%d boroughs have zero active population." % empty_boroughs)

static func _load_queries() -> Dictionary:
	if not FileAccess.file_exists(SQL_REFERENCE_PATH):
		return {}
	var file := FileAccess.open(SQL_REFERENCE_PATH, FileAccess.READ)
	if file == null:
		return {}

	var queries := {}
	var current_name := ""
	var current_lines: Array[String] = []
	for line in file.get_as_text().split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("-- QUERY:"):
			if not current_name.is_empty():
				queries[current_name] = "\n".join(current_lines).strip_edges()
			current_name = trimmed.trim_prefix("-- QUERY:").strip_edges()
			current_lines.clear()
		elif not current_name.is_empty():
			current_lines.append(line)
	if not current_name.is_empty():
		queries[current_name] = "\n".join(current_lines).strip_edges()
	file.close()
	return queries

static func _query_rows(db_manager, queries: Dictionary, query_name: String) -> Array:
	if not queries.has(query_name):
		return []
	return db_manager.query_rows(queries[query_name])

static func _metric(report: Dictionary, key: String) -> int:
	return int(report.get("metrics", {}).get(key, 0))

static func _add_check(report: Dictionary, name: String, passed: bool) -> void:
	report["checks"].append({"name": name, "passed": passed})
	if not passed:
		report["is_healthy"] = false

static func _add_error(report: Dictionary, message: String) -> void:
	report["errors"].append(message)
	report["is_healthy"] = false

static func _add_warning(report: Dictionary, message: String) -> void:
	report["warnings"].append(message)

static func _append_section(lines: Array[String], title: String, errors: Array, warnings: Array) -> void:
	lines.append("## %s" % title)
	lines.append("")
	if errors.is_empty() and warnings.is_empty():
		lines.append("No errors or warnings.")
	else:
		for error in errors:
			lines.append("- **ERROR:** %s" % error)
		for warning in warnings:
			lines.append("- **WARNING:** %s" % warning)
	lines.append("")

static func _append_metrics(lines: Array[String], metrics: Dictionary) -> void:
	lines.append("## Metrics")
	lines.append("")
	lines.append("| Metric | Value |")
	lines.append("|---|---:|")
	for key in metrics.keys():
		lines.append("| `%s` | %s |" % [key, metrics[key]])
	lines.append("")

static func _append_distributions(lines: Array[String], distributions: Dictionary) -> void:
	lines.append("## Distributions")
	lines.append("")
	for name in distributions.keys():
		lines.append("### %s" % str(name).replace("_", " ").capitalize())
		lines.append("")
		var rows: Array = distributions[name]
		if rows.is_empty():
			lines.append("_No rows returned._")
			lines.append("")
			continue
		var columns: Array = rows[0].keys()
		lines.append("| %s |" % " | ".join(columns))
		var separators: Array[String] = []
		for _column in columns:
			separators.append("---")
		lines.append("| %s |" % " | ".join(separators))
		for row in rows:
			var values: Array[String] = []
			for column in columns:
				values.append(str(row.get(column, "")).replace("|", "\\|"))
			lines.append("| %s |" % " | ".join(values))
		lines.append("")

static func _append_checks(lines: Array[String], checks: Array) -> void:
	lines.append("## Checks")
	lines.append("")
	lines.append("| Check | Result |")
	lines.append("|---|---|")
	for check in checks:
		lines.append("| `%s` | %s |" % [
			check.get("name", "unknown"),
			"PASS" if check.get("passed", false) else "FAIL"
		])
	lines.append("")
