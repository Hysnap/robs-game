# res://systems/economy/org_record_ledger.gd
class_name OrgRecordLedger
extends RefCounted

const _DBManager = preload("res://systems/db_manager.gd")

## Inserts a new slip/record into org_records and returns its record_id (or -1 if DB is closed).
static func record_slip(
	org_id: String,
	slip: Dictionary,
	current_day: int,
	storage_establishment_id: int = 0,
	status: String = "PENDING",
	filing_domain: String = "",
	scope_type: String = "",
	scope_id: String = ""
) -> int:
	if not _DBManager.is_database_open():
		return -1

	var resolved_domain: String = filing_domain if not filing_domain.is_empty() else str(slip.get("destination", "DIARY")).to_upper().strip_edges()
	var resolved_status: String = status.to_upper().strip_edges()
	var sim_day: int = int(slip.get("tick", slip.get("day_offset", current_day)))
	var week_tick: int = int(slip.get("week", 1))
	var verb: String = str(slip.get("verb", "")).to_upper().strip_edges()
	var action_label: String = str(slip.get("action_label", "")).strip_edges()
	var author_res_id: int = int(slip.get("resident_id", slip.get("author_resident_id", 0)))
	var author_name: String = str(slip.get("author", "")).strip_edges()
	var target_node_id: String = str(slip.get("target_node_id", "")).strip_edges()
	var display_text: String = str(slip.get("display_text", slip.get("text", "")))
	var stationery_profile: String = str(slip.get("stationery_profile", "")).strip_edges()
	var standing_order_id: int = int(slip.get("standing_order_id", 0))
	var storage_medium: String = str(slip.get("storage_medium", "PAPER")).to_upper().strip_edges()
	var volume_units: float = float(slip.get("volume_units", 1.0))
	var evidence_weight: float = float(slip.get("evidence_weight", 0.0))
	var payload_json: String = JSON.stringify(slip)

	var storage_sql: String = str(storage_establishment_id) if storage_establishment_id > 0 else "NULL"
	var so_sql: String = str(standing_order_id) if standing_order_id > 0 else "NULL"
	var author_sql: String = str(author_res_id) if author_res_id > 0 else "NULL"
	var scope_type_sql: String = "'%s'" % _esc(scope_type.to_upper()) if not scope_type.is_empty() else "NULL"
	var scope_id_sql: String = "'%s'" % _esc(scope_id) if not scope_id.is_empty() else "NULL"
	var filed_day_sql: String = str(current_day) if resolved_status == "FILED" else "NULL"

	var insert_sql := """
		INSERT INTO org_records (
			org_id, storage_establishment_id, standing_order_id, status,
			filing_domain, scope_type, scope_id, sim_day, week_tick,
			verb, action_label, author_resident_id, author_name,
			target_node_id, display_text, stationery_profile,
			storage_medium, volume_units, evidence_weight, payload_json,
			created_day, filed_day
		) VALUES (
			'%s', %s, %s, '%s',
			'%s', %s, %s, %d, %d,
			'%s', '%s', %s, '%s',
			'%s', '%s', '%s',
			'%s', %f, %f, '%s',
			%d, %s
		);
	""" % [
		_esc(org_id), storage_sql, so_sql, _esc(resolved_status),
		_esc(resolved_domain), scope_type_sql, scope_id_sql, sim_day, week_tick,
		_esc(verb), _esc(action_label), author_sql, _esc(author_name),
		_esc(target_node_id), _esc(display_text), _esc(stationery_profile),
		_esc(storage_medium), volume_units, evidence_weight, _esc(payload_json),
		current_day, filed_day_sql
	]

	if not _DBManager.execute_batch([insert_sql]):
		return -1

	var rows: Array = _DBManager.query_rows("SELECT last_insert_rowid() AS rid;")
	return int(rows[0].get("rid", -1)) if not rows.is_empty() else -1

## Files an existing PENDING record into a domain/scope.
static func file_record(
	record_id: int,
	filing_domain: String,
	scope_type: String,
	scope_id: String,
	current_day: int
) -> bool:
	if not _DBManager.is_database_open() or record_id <= 0:
		return false

	var scope_type_sql: String = "'%s'" % _esc(scope_type.to_upper()) if not scope_type.is_empty() else "NULL"
	var scope_id_sql: String = "'%s'" % _esc(scope_id) if not scope_id.is_empty() else "NULL"

	var sql := """
		UPDATE org_records
		SET status = 'FILED',
			filing_domain = '%s',
			scope_type = %s,
			scope_id = %s,
			filed_day = %d
		WHERE record_id = %d;
	""" % [_esc(filing_domain.to_upper()), scope_type_sql, scope_id_sql, current_day, record_id]
	return _DBManager.execute_batch([sql])

## Soft-deletes a single record (BINNED -> DISCARDED, SHREDDED/BURNED -> DESTROYED, SEIZED -> SEIZED).
static func dispose_record(record_id: int, method: String, current_day: int) -> bool:
	if not _DBManager.is_database_open() or record_id <= 0:
		return false

	var m: String = method.to_upper().strip_edges()
	var next_status: String = _status_for_disposal_method(m)
	var sql := """
		UPDATE org_records
		SET status = '%s',
			disposed_day = %d,
			disposal_method = '%s'
		WHERE record_id = %d;
	""" % [_esc(next_status), current_day, _esc(m), record_id]
	return _DBManager.execute_batch([sql])

## Bulk soft-delete for retention purges (e.g., shred/burn all records older than cutoff_day).
static func purge_records_older_than(
	org_id: String,
	cutoff_day: int,
	method: String,
	current_day: int,
	filing_domain: String = ""
) -> bool:
	if not _DBManager.is_database_open():
		return false

	var m: String = method.to_upper().strip_edges()
	var next_status: String = _status_for_disposal_method(m)
	var domain_clause: String = " AND filing_domain = '%s'" % _esc(filing_domain.to_upper()) if not filing_domain.is_empty() else ""

	var sql := """
		UPDATE org_records
		SET status = '%s',
			disposed_day = %d,
			disposal_method = '%s'
		WHERE org_id = '%s'
		  AND status IN ('FILED', 'ARCHIVED', 'DISCARDED')
		  AND sim_day < %d%s;
	""" % [_esc(next_status), current_day, _esc(m), _esc(org_id), cutoff_day, domain_clause]
	return _DBManager.execute_batch([sql])

## Converts active stored records to a denser medium (e.g., PAPER -> MICROFICHE at 0.05 volume_units).
static func convert_storage_medium(
	org_id: String,
	target_medium: String,
	volume_per_record: float,
	storage_establishment_id: int = 0
) -> bool:
	if not _DBManager.is_database_open():
		return false

	var estab_clause: String = " AND storage_establishment_id = %d" % storage_establishment_id if storage_establishment_id > 0 else ""
	var sql := """
		UPDATE org_records
		SET storage_medium = '%s',
			volume_units = %f,
			status = CASE WHEN status = 'FILED' THEN 'ARCHIVED' ELSE status END
		WHERE org_id = '%s'
		  AND status IN ('FILED', 'ARCHIVED')%s;
	""" % [_esc(target_medium.to_upper()), maxf(0.0, volume_per_record), _esc(org_id), estab_clause]
	return _DBManager.execute_batch([sql])

## Hydrates unread PENDING slips for DesktopSlipStack on save/load.
static func get_pending_slips(org_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not _DBManager.is_database_open():
		return out

	var rows: Array = _DBManager.query_rows("""
		SELECT record_id, payload_json, filing_domain, sim_day, week_tick,
			   verb, action_label, author_resident_id, author_name,
			   target_node_id, display_text, stationery_profile
		FROM org_records
		WHERE org_id = '%s' AND status = 'PENDING'
		ORDER BY record_id ASC;
	""" % _esc(org_id))

	for row in rows:
		var parsed: Variant = JSON.parse_string(str(row.get("payload_json", "{}")))
		var card: Dictionary = parsed if parsed is Dictionary else {}
		card["record_id"] = int(row.get("record_id", 0))
		if not card.has("display_text"):
			card["display_text"] = str(row.get("display_text", ""))
		if not card.has("destination"):
			card["destination"] = str(row.get("filing_domain", "DIARY"))
		if not card.has("author"):
			card["author"] = str(row.get("author_name", ""))
		if not card.has("verb"):
			card["verb"] = str(row.get("verb", ""))
		if not card.has("action_label"):
			card["action_label"] = str(row.get("action_label", ""))
		if not card.has("stationery_profile"):
			card["stationery_profile"] = str(row.get("stationery_profile", ""))
		out.append(card)
	return out

## Queries filed inscriptions for DOSSIER (by district_id), ROSTER (by author_resident_id),
## DIARY (by sim_day), or FINANCE.
static func get_filed_inscriptions(
	org_id: String,
	filing_domain: String,
	scope_id: String = "",
	sim_day: int = -1,
	author_resident_id: int = 0
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not _DBManager.is_database_open():
		return out

	var clauses: Array[String] = [
		"org_id = '%s'" % _esc(org_id),
		"status IN ('FILED', 'ARCHIVED')",
		"filing_domain = '%s'" % _esc(filing_domain.to_upper())
	]
	if not scope_id.is_empty():
		clauses.append("scope_id = '%s'" % _esc(scope_id))
	if sim_day >= 0:
		clauses.append("sim_day = %d" % sim_day)
	if author_resident_id > 0:
		clauses.append("author_resident_id = %d" % author_resident_id)

	var sql := """
		SELECT record_id, sim_day, week_tick, verb, action_label,
			   author_resident_id, author_name, target_node_id, display_text
		FROM org_records
		WHERE %s
		ORDER BY sim_day DESC, record_id DESC;
	""" % " AND ".join(clauses)

	for row in _DBManager.query_rows(sql):
		out.append({
			"record_id": int(row.get("record_id", 0)),
			"tick": int(row.get("sim_day", 1)),
			"week": int(row.get("week_tick", 1)),
			"verb": str(row.get("verb", "")),
			"action_label": str(row.get("action_label", "")),
			"author_resident_id": int(row.get("author_resident_id", 0)),
			"author": str(row.get("author_name", "")),
			"target_node_id": str(row.get("target_node_id", "")),
			"text": str(row.get("display_text", ""))
		})
	return out

## Computes physical storage footprint and raid evidence exposure at a premises.
static func get_premises_storage_summary(storage_establishment_id: int) -> Dictionary:
	var summary := {"record_count": 0, "total_volume_units": 0.0, "total_evidence_weight": 0.0}
	if not _DBManager.is_database_open() or storage_establishment_id <= 0:
		return summary

	var rows: Array = _DBManager.query_rows("""
		SELECT COUNT(*) AS cnt,
			   COALESCE(SUM(volume_units), 0.0) AS vol,
			   COALESCE(SUM(evidence_weight), 0.0) AS ev
		FROM org_records
		WHERE storage_establishment_id = %d
		  AND status IN ('PENDING', 'FILED', 'ARCHIVED');
	""" % storage_establishment_id)

	if not rows.is_empty():
		summary["record_count"] = int(rows[0].get("cnt", 0))
		summary["total_volume_units"] = float(rows[0].get("vol", 0.0))
		summary["total_evidence_weight"] = float(rows[0].get("ev", 0.0))
	return summary

## Seizes discoverable records at a raided premises and marks them SEIZED.
static func seize_premises_records(
	storage_establishment_id: int,
	current_day: int,
	include_binned: bool = false
) -> Array[Dictionary]:
	var seized: Array[Dictionary] = []
	if not _DBManager.is_database_open() or storage_establishment_id <= 0:
		return seized

	var status_filter: String = "('PENDING', 'FILED', 'ARCHIVED', 'DISCARDED')" if include_binned else "('PENDING', 'FILED', 'ARCHIVED')"
	var rows: Array = _DBManager.query_rows("""
		SELECT record_id, org_id, standing_order_id, filing_domain, sim_day,
			   verb, author_resident_id, target_node_id, evidence_weight
		FROM org_records
		WHERE storage_establishment_id = %d
		  AND status IN %s;
	""" % [storage_establishment_id, status_filter])

	if rows.is_empty():
		return seized

	var id_tokens: Array[String] = []
	for r in rows:
		seized.append(r)
		id_tokens.append(str(int(r.get("record_id", 0))))

	_DBManager.execute_batch([
		"UPDATE org_records SET status = 'SEIZED', disposed_day = %d, disposal_method = 'SEIZED' WHERE record_id IN (%s);" % [current_day, ", ".join(id_tokens)]
	])
	return seized

static func _status_for_disposal_method(method_upper: String) -> String:
	match method_upper:
		"BINNED":
			return "DISCARDED"
		"SEIZED":
			return "SEIZED"
		_:
			return "DESTROYED"

static func _esc(raw: String) -> String:
	return raw.replace("'", "''")