# res://systems/target_resolvers/resolver_catalog.gd
extends RefCounted

const DOMAIN_TOKEN := "COMMODITY"
const ALIASES: Array[String] = ["RECIPE"]

static func resolve(target_cat: Dictionary, world_state: Dictionary, verb_code: String) -> Array[Dictionary]:
	var catalog_source: String = str(target_cat.get("catalog_source", "commodity_registry"))
	var catalog: Dictionary = world_state.get(catalog_source, {})
	if catalog.is_empty():
		push_warning("[ResolverCatalog] Catalog '%s' in world_state is empty for verb '%s'." % [catalog_source, verb_code])
		return []

	var results: Array[Dictionary] = []
	var sorted_keys: Array = catalog.keys()
	sorted_keys.sort()

	for item_id in sorted_keys:
		var item_data = catalog[item_id]
		var token: String = str(item_id)
		var cost: float = 0.0
		var cat: String = ""
		var subcat: String = ""
		var tax_path: Array = []

		if item_data is Dictionary:
			token = str(item_data.get("display_name", item_id))
			cost = float(item_data.get("base_cost", item_data.get("unit_cost", 0.0)))
			cat = str(item_data.get("category", "GENERAL")).strip_edges().to_upper()
			assert(not cat.is_empty(),
				"FATAL: [ResolverCatalog] Item '%s' in catalog '%s' has an empty category!" % [item_id, catalog_source])
			subcat = str(item_data.get("sub_category", "")).strip_edges().to_upper()
			tax_path = item_data.get("taxonomy_path", [])

		results.append({
			"id": str(item_id),
			"label_token": token,
			"unit_cost": cost,
			"category": cat,
			"sub_category": subcat,
			"taxonomy_path": tax_path
		})

	return results