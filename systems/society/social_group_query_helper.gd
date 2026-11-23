# res://systems/society/social_group_query_helper.gd
class_name SocialGroupQueryHelper
extends RefCounted

const DB_MANAGER = preload("res://systems/db_manager.gd")

## Queries living residents ordered by their assigned church_id parish
static func query_residents_by_church() -> Array:
	return DB_MANAGER.query_rows("""
		SELECT church_id AS group_id, resident_id
		FROM residents
		WHERE church_id IS NOT NULL AND dod IS NULL
		ORDER BY church_id ASC;
	""")

## Queries living residents ordered by their assigned local_pub_id
static func query_residents_by_pub() -> Array:
	return DB_MANAGER.query_rows("""
		SELECT local_pub_id AS group_id, resident_id
		FROM residents
		WHERE local_pub_id IS NOT NULL AND dod IS NULL
		ORDER BY local_pub_id ASC;
	""")

## Queries active livelihood contracts ordered by employer establishment
static func query_residents_by_workplace() -> Array:
	return DB_MANAGER.query_rows("""
		SELECT employer_establishment_id AS group_id, resident_id
		FROM livelihood_contracts
		WHERE employer_establishment_id IS NOT NULL AND valid_to IS NULL
		ORDER BY employer_establishment_id ASC;
	""")