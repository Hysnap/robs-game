# res://systems/society/society_generation_auditor.gd
class_name SocietyGenerationAuditor
extends RefCounted

const DB_MANAGER = preload("res://systems/db_manager.gd")

## Logs an audit breakdown of tied accommodation occupancy
static func log_tied_housing_audit(available_tied: Dictionary, local_count: int, external_count: int) -> void:
	SystemLogger.log_info("\n==========================================================================")
	SystemLogger.log_info("                  TIED ACCOMMODATION OCCUPANCY AUDIT                      ")
	SystemLogger.log_info("==========================================================================")
	SystemLogger.log_info("  Local Youth Relocated (Preserved Family Roots): %d" % local_count)
	SystemLogger.log_info("  External Migrants Influxed (Solo Intake Cohorts): %d" % external_count)
	SystemLogger.log_info("  Total Occupied Work-Tied Homes:                %d" % (local_count + external_count))
	SystemLogger.log_info("  ------------------------------------------------------------------------")
	SystemLogger.log_info("  Remaining Vacant Tied Units by Category:")
	for res_type in available_tied.keys():
		SystemLogger.log_info("    • %-24s: %d units vacant" % [res_type, available_tied[res_type].size()])
	SystemLogger.log_info("==========================================================================\n")

## Logs a comprehensive SQL audit of generated jobs, education levels, OCEAN personality means, and kinship bonds
static func audit_generated_jobs_by_education() -> void:
	SystemLogger.log_info("\n==========================================================================")
	SystemLogger.log_info("               SOCIETY LABOR & EDUCATION AUDIT REPORT                     ")
	SystemLogger.log_info("==========================================================================")

	var query := """
		SELECT 
			edu.code AS education_level,
			c_cls.code AS contract_class,
			role.code AS role_title,
			COUNT(c.resident_id) AS total_holders,
			AVG(c.compensation_rate) AS avg_hourly_rate,
			AVG(c.weekly_hours) AS avg_weekly_hours
		FROM livelihood_contracts c
		JOIN residents r ON c.resident_id = r.resident_id
		JOIN system_labels edu ON r.education_level_id = edu.label_id
		JOIN system_labels c_cls ON c.contract_class_id = c_cls.label_id
		JOIN system_labels role ON c.role_title_id = role.label_id
		GROUP BY edu.code, c_cls.code, role.code
		ORDER BY edu.code, c_cls.code, total_holders DESC;
	"""

	var results: Array = DB_MANAGER.query_rows(query)
	if results.is_empty():
		SystemLogger.log_info("  [Audit] No contract records found.")
		SystemLogger.log_info("==========================================================================\n")
		return

	var current_edu: String = ""
	var total_city_jobs: int = 0

	for row in results:
		var edu: String = str(row["education_level"])
		var cls: String = str(row["contract_class"])
		var role: String = str(row["role_title"])
		var count: int = int(row["total_holders"])
		var rate: float = float(row["avg_hourly_rate"])
		var hours: float = float(row["avg_weekly_hours"])
		total_city_jobs += count

		if edu != current_edu:
			current_edu = edu
			SystemLogger.log_info("\n▶ [Education Tier: %s]" % current_edu)
			SystemLogger.log_info("  %-24s | %-16s | %-6s | %-9s | %-8s" % ["Role Title", "Class", "Count", "Avg Rate", "Avg Hrs"])
			SystemLogger.log_info("  ------------------------------------------------------------------------")

		SystemLogger.log_info("  %-24s | %-16s | %-6d | £%-8.2f | %-5.1f hrs" % [role, cls, count, rate, hours])

	var summary_query := """
		SELECT 
			edu.code AS education_level,
			COUNT(r.resident_id) AS citizen_count,
			SUM(CASE WHEN c_cls.code = 'FORMAL_LEGAL' THEN 1 ELSE 0 END) AS formal_workers,
			SUM(CASE WHEN c_cls.code = 'ENCLAVE_STUDENT' THEN 1 ELSE 0 END) AS students_pupils,
			SUM(CASE WHEN c_cls.code = 'INFORMAL_GREY' AND role.code = 'PENSIONER' THEN 1 ELSE 0 END) AS pensioners,
			SUM(CASE WHEN c_cls.code = 'INFORMAL_GREY' AND role.code = 'HOME_MAKER' THEN 1 ELSE 0 END) AS homemakers,
			SUM(CASE WHEN c_cls.code = 'INFORMAL_GREY' AND role.code NOT IN ('PENSIONER', 'HOME_MAKER') THEN 1 ELSE 0 END) AS unemployed_or_informal
		FROM residents r
		JOIN system_labels edu ON r.education_level_id = edu.label_id
		LEFT JOIN livelihood_contracts c ON r.resident_id = c.resident_id
		LEFT JOIN system_labels c_cls ON c.contract_class_id = c_cls.label_id
		LEFT JOIN system_labels role ON c.role_title_id = role.label_id
		GROUP BY edu.code
		ORDER BY citizen_count DESC;
	"""
	var summary_results: Array = DB_MANAGER.query_rows(summary_query)

	SystemLogger.log_info("\n------------------------------------------------------------------------------------------------")
	SystemLogger.log_info("                                SUMMARY BY EDUCATION LEVEL                                      ")
	SystemLogger.log_info("------------------------------------------------------------------------------------------------")
	SystemLogger.log_info("  %-20s | %-8s | %-14s | %-10s | %-12s | %-16s | %-10s" % [
		"Education Level", "Pop", "Formal Workers", "Students", "Homemakers", "Unemployed/Other", "Pensioners"
	])
	SystemLogger.log_info("  ------------------------------------------------------------------------------------------------")
	for s_row in summary_results:
		SystemLogger.log_info("  %-20s | %-8d | %-14d | %-10d | %-12d | %-16d | %-10d" % [
			str(s_row["education_level"]),
			int(s_row["citizen_count"]),
			int(s_row["formal_workers"]),
			int(s_row["students_pupils"]),
			int(s_row["homemakers"]),
			int(s_row["unemployed_or_informal"]),
			int(s_row["pensioners"])
		])

	# OCEAN & Anchor Coverage Summary
	var ocean_query := """
		SELECT 
			COUNT(resident_id) AS total_pop,
			SUM(CASE WHEN church_id IS NOT NULL THEN 1 ELSE 0 END) AS church_members,
			SUM(CASE WHEN local_pub_id IS NOT NULL THEN 1 ELSE 0 END) AS pub_patrons,
			AVG(openness) AS avg_o,
			AVG(conscientiousness) AS avg_c,
			AVG(extraversion) AS avg_e,
			AVG(agreeableness) AS avg_a,
			AVG(neuroticism) AS avg_n
		FROM residents
		WHERE dod IS NULL;
	"""
	var ocean_rows: Array = DB_MANAGER.query_rows(ocean_query)
	if not ocean_rows.is_empty():
		var o_row: Dictionary = ocean_rows[0]
		SystemLogger.log_info("\n------------------------------------------------------------------------------------------------")
		SystemLogger.log_info("                         OCEAN PERSONALITY & VENUE COHORT SUMMARY                               ")
		SystemLogger.log_info("------------------------------------------------------------------------------------------------")
		SystemLogger.log_info("  Living Citizens: %d | Church Members: %d | Pub Regulars: %d" % [
			int(o_row["total_pop"]), int(o_row["church_members"]), int(o_row["pub_patrons"])
		])
		SystemLogger.log_info("  Mean OCEAN Vector -> O: %.3f | C: %.3f | E: %.3f | A: %.3f | N: %.3f" % [
			float(o_row["avg_o"]), float(o_row["avg_c"]), float(o_row["avg_e"]), float(o_row["avg_a"]), float(o_row["avg_n"])
		])

	SystemLogger.log_info("================================================================================================")
	SystemLogger.log_info("  Total Contracted Citizens: %d" % total_city_jobs)
	SystemLogger.log_info("================================================================================================\n")