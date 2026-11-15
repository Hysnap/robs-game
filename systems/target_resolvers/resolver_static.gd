# res://systems/target_resolvers/resolver_static.gd
extends RefCounted

const DOMAIN_TOKEN := "STATIC"
const ALIASES: Array[String] = ["CURRENCY", "NONE", "CONTACT"]

static func resolve(target_cat: Dictionary, _world_state: Dictionary, verb_code: String) -> Array[Dictionary]:
	var domain: String = str(target_cat.get("domain", target_cat.get("id", "STATIC"))).strip_edges().to_upper()

	if domain == "CURRENCY":
		return [{
			"id": "CASH",
			"label_token": str(target_cat.get("label_token", "UI_CAT_CURRENCY")),
			"unit_cost": 1.0,
			"category": "CURRENCY",
			"sub_category": "CASH",
			"taxonomy_path": []
		}]

	if domain == "CONTACT":
		return [{
			"id": "CONTACT_SELECTED",
			"label_token": str(target_cat.get("label_token", "UI_TARGET_CONTACT")),
			"unit_cost": 0.0,
			"category": "CONTACT",
			"sub_category": "",
			"taxonomy_path": []
		}]

	assert(target_cat.has("id") and not str(target_cat["id"]).is_empty(),
		"FATAL: [ResolverStatic] Category in verb '%s' must define an 'id'." % verb_code)
	assert(target_cat.has("label_token") and not str(target_cat["label_token"]).is_empty(),
		"FATAL: [ResolverStatic] Category '%s' in verb '%s' must define a 'label_token'." % [target_cat.get("id"), verb_code])

	return [{
		"id": str(target_cat["id"]),
		"label_token": str(target_cat["label_token"]),
		"unit_cost": float(target_cat.get("unit_cost", 0.0)),
		"category": str(target_cat.get("id", "")).to_upper(),
		"sub_category": "",
		"taxonomy_path": []
	}]