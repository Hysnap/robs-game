# res://systems/society/social_group_query_helper.gd
class_name SocialGroupQueryHelper
extends RefCounted

const DB_MANAGER = preload("res://systems/db_manager.gd")

## Queries living residents ordered by parish establishment category_code and church_id
static func query_residents_by_church() -> Array:
	return DB_MANAGER.query_rows("""
		SELECT sl.code AS category_code, r.church_id AS group_id, r.resident_id
		FROM residents r
		JOIN establishments e ON r.church_id = e.establishment_id
		JOIN system_labels sl ON e.category_id = sl.label_id
		WHERE r.church_id IS NOT NULL AND r.dod IS NULL
		ORDER BY e.category_id ASC, r.church_id ASC;
	""")

## Queries living residents ordered by pub/club establishment category_code and local_pub_id
static func query_residents_by_pub() -> Array:
	return DB_MANAGER.query_rows("""
		SELECT sl.code AS category_code, r.local_pub_id AS group_id, r.resident_id
		FROM residents r
		JOIN establishments e ON r.local_pub_id = e.establishment_id
		JOIN system_labels sl ON e.category_id = sl.label_id
		WHERE r.local_pub_id IS NOT NULL AND r.dod IS NULL
		ORDER BY e.category_id ASC, r.local_pub_id ASC;
	""")

## Queries active livelihood contracts ordered by employer establishment category_code and establishment_id
static func query_residents_by_workplace() -> Array:
	return DB_MANAGER.query_rows("""
		SELECT sl.code AS category_code, lc.employer_establishment_id AS group_id, lc.resident_id
		FROM livelihood_contracts lc
		JOIN establishments e ON lc.employer_establishment_id = e.establishment_id
		JOIN system_labels sl ON e.category_id = sl.label_id
		WHERE lc.employer_establishment_id IS NOT NULL AND lc.valid_to IS NULL
		ORDER BY e.category_id ASC, lc.employer_establishment_id ASC;
	""")