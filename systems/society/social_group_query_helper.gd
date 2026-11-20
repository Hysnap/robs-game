# res://systems/society/social_group_query_helper.gd
class_name SocialGroupQueryHelper
extends RefCounted

const DB_MANAGER = preload("res://systems/db_manager.gd")

## Queries living residents grouped by their assigned church_id parish
static func query_residents_by_church() -> Array[Dictionary]:
	return DB_MANAGER.query_rows("""
		SELECT church_id, GROUP_CONCAT(resident_id) as member_ids, COUNT(*) as count
		FROM residents
		WHERE church_id IS NOT NULL AND dod IS NULL
		GROUP BY church_id
		HAVING count > 1;
	""")

## Queries living residents grouped by their assigned local_pub_id
static func query_residents_by_pub() -> Array[Dictionary]:
	return DB_MANAGER.query_rows("""
		SELECT local_pub_id, GROUP_CONCAT(resident_id) as member_ids, COUNT(*) as count
		FROM residents
		WHERE local_pub_id IS NOT NULL AND dod IS NULL
		GROUP BY local_pub_id
		HAVING count > 1;
	""")

## Queries active livelihood contracts grouped by employer establishment
static func query_residents_by_workplace() -> Array[Dictionary]:
	return DB_MANAGER.query_rows("""
		SELECT employer_establishment_id, GROUP_CONCAT(resident_id) as member_ids, COUNT(*) as count
		FROM livelihood_contracts
		WHERE employer_establishment_id IS NOT NULL AND valid_to IS NULL
		GROUP BY employer_establishment_id
		HAVING count > 1;
	""")