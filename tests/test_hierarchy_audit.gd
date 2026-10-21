# res://tests/test_hierarchy_audit.gd
extends SceneTree

const CATALOG_VALIDATOR = preload("res://systems/catalog_validator.gd")

func _init() -> void:
	# 1. Audit Commodities N-Tier Structure
	print("\n--- Auditing Commodities Tree ---")
	var comm_audit = CATALOG_VALIDATOR.audit_hierarchy_properties("res://data_modules/core/commodities/", true)

	# 2. Audit Recipes N-Tier Structure
	if DirAccess.dir_exists_absolute("res://data_modules/core/recipes/"):
		print("\n--- Auditing Recipes Tree ---")
		var recipe_audit = CATALOG_VALIDATOR.audit_hierarchy_properties("res://data_modules/core/recipes/", false)

	# Audits commodities against code usage in systems, scenes, and data_modules
	CATALOG_VALIDATOR.audit_property_usage(
		"res://data_modules/core/commodities/",
		["res://systems/", "res://scenes/", "res://data_modules/core/dialects/"],
		true
	)


	print("\nAudit complete! Check 'user://n_tier_hierarchy_audit.log' for the full trace.\n")
	quit()