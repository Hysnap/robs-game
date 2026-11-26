# res://systems/society/premises_workplace_builder.gd
class_name PremisesWorkplaceBuilder
extends RefCounted

const DB_MANAGER = preload("res://systems/db_manager.gd")
const CALENDAR_HELPER = preload("res://systems/calendar_helper.gd")
const SPATIAL_RESOLVER = preload("res://systems/spatial_demand_resolver.gd")
const MANIFEST_MANAGER = preload("res://systems/scenario_manifest_manager.gd")

## Legacy single-call entry point (delegates to the 3 phased builders for zero duplication)
static func run(
	world_state: Dictionary,
	archetypes: Dictionary,
	building_classes: Dictionary,
	job_definitions: Dictionary,
	cultural: Dictionary,
	lexicon: Dictionary,
	rng: RandomNumberGenerator,
	on_progress: Callable
) -> Dictionary:
	var state: Dictionary = create_build_context(
		world_state, archetypes, building_classes, job_definitions, cultural, lexicon, rng
	)
	await build_districts_and_civics(state, on_progress)
	await build_residential_and_households(state, on_progress)
	await build_commercial_industrial_and_slots(state, on_progress)
	return finalize_physical_state(state)

## Initializes shared phased-builder state and config-driven batch sizing
static func create_build_context(
	world_state: Dictionary,
	archetypes: Dictionary,
	building_classes: Dictionary,
	job_definitions: Dictionary,
	cultural: Dictionary,
	lexicon: Dictionary,
	rng: RandomNumberGenerator
) -> Dictionary:
	var gen_cfg: Dictionary = DB_MANAGER.get_city_generation_config()
	var districts: Dictionary = world_state.get("districts", {})
	var boroughs: Dictionary = world_state.get("boroughs", {})
	var sim_start_day: int = CALENDAR_HELPER.get_simulation_start_day()
	var sim_start_year: int = int(world_state.get("metadata", {}).get("calendar_year", 1980))

	var street_cfg: Dictionary = lexicon.get("street_names", {})
	var street_roots: Array = street_cfg.get("roots", [])
	var street_suffixes: Array = street_cfg.get("suffixes", [])
	assert(not street_roots.is_empty() and not street_suffixes.is_empty(), "FATAL: [PremisesWorkplaceBuilder] Missing street_names in lexicon.")

	var street_cap_cfg: Dictionary = lexicon.get("street_property_cap", {"min": 40, "max": 200})
	var street_cap_min: int = maxi(1, int(street_cap_cfg.get("min", 40)))
	var street_cap_max: int = maxi(street_cap_min, int(street_cap_cfg.get("max", 200)))

	var bldg_cfg: Dictionary = lexicon.get("residential_building_names", {})
	var bldg_roots: Array = bldg_cfg.get("roots", [])
	var bldg_suffixes: Array = bldg_cfg.get("suffixes", [])
	assert(not bldg_roots.is_empty() and not bldg_suffixes.is_empty(), "FATAL: [PremisesWorkplaceBuilder] Missing residential_building_names in lexicon.")

	var address_fmts: Dictionary = lexicon.get("address_formats", {})
	var comm_naming: Dictionary = lexicon.get("commercial_naming", {})
	assert(not comm_naming.is_empty(), "FATAL: [PremisesWorkplaceBuilder] Missing 'commercial_naming' in spatial lexicon.")

	var block_estimates: Dictionary = {}
	var total_city_est_pop: float = 0.0
	for dist_id in districts.keys():
		var d_est: float = float(districts[dist_id].get("estimated_population", districts[dist_id].get("population", 0.0)))
		block_estimates[dist_id] = d_est
		total_city_est_pop += d_est

	var civic_cfg: Dictionary = MANIFEST_MANAGER.load_module("civic_hierarchy")
	var institutions_cfg: Dictionary = civic_cfg.get("institutions", {})
	var typed_households: Array[Dictionary] = []
	var typed_job_slots: Array[Dictionary] = []

	return {
		"world_state": world_state,
		"districts": districts,
		"boroughs": boroughs,
		"archetypes": archetypes,
		"building_classes": building_classes,
		"job_definitions": job_definitions,
		"cultural": cultural,
		"lexicon": lexicon,
		"rng": rng,
		"district_batch_size": maxi(1, int(gen_cfg.get("district_batch_size", 25))),
		"sim_start_day": sim_start_day,
		"sim_start_year": sim_start_year,
		"reason_world_gen_id": DB_MANAGER.get_label_id("CHANGE_REASON", "WORLD_GENERATION"),
		"res_unit_cat_id": DB_MANAGER.get_label_id("ESTABLISHMENT_CATEGORY", "RESIDENTIAL_UNIT"),
		"comm_classes": building_classes.get("commercial_tenants", {}),
		"ind_classes": building_classes.get("industrial_tenants", {}),
		"embedded_civic_classes": building_classes.get("civic_tenants", {}),
		"clandestine_classes": building_classes.get("clandestine_tenants", {}),
		"street_roots": street_roots,
		"street_suffixes": street_suffixes,
		"street_cap_min": street_cap_min,
		"street_cap_max": street_cap_max,
		"bldg_roots": bldg_roots,
		"bldg_suffixes": bldg_suffixes,
		"fmt_flat_unit": str(address_fmts.get("flat_unit", "Flat {door}, {building}")),
		"fmt_flat_door": str(address_fmts.get("flat_door", "Flat {door}")),
		"fmt_street_unit": str(address_fmts.get("street_unit", "{door} {street}")),
		"fmt_street_door": str(address_fmts.get("street_door", "{door}")),
		"civic_naming_formats": lexicon.get("civic_naming_formats", ["{district_name} {trade}", "{borough_name} {trade}", "{street_root} {trade}"]),
		"comm_naming": comm_naming,
		"institutions_cfg": institutions_cfg,
		"default_civic_org_id": str(institutions_cfg.get("default_civic_org_id", "ORG:CIVIC")),
		"site_wing_templates": institutions_cfg.get("site_wing_templates", {}),
		"brand_org_map": {},
		"category_org_map": {},
		"host_orgs_by_category": {},
		"org_pay_cadences": {},
		"borough_police_orgs": {},
		"block_estimates": block_estimates,
		"total_city_est_pop": total_city_est_pop,
		"by_cat": {},
		"commercial_instances_by_type": {},
		"generated_households": typed_households,
		"district_residents_map": {},
		"available_job_slots": typed_job_slots,
		"available_tied_housing": {},
		"proprietor_hints": {},
		"employer_wage_biases": {},
		"district_naming": {},
		"district_estab_counts": {},
		"est_id": 1,
		"current_household_id": 1,
		"current_slot_id": 1,
		"total_tied_units_count": 0
	}

## Phase A: Seeds organizations, inserts districts, and builds civic/institutional anchors + civic job slots + tied units
static func build_districts_and_civics(state: Dictionary, on_progress: Callable = Callable()) -> void:
	var districts: Dictionary = state["districts"]
	var boroughs: Dictionary = state["boroughs"]
	var archetypes: Dictionary = state["archetypes"]
	var job_definitions: Dictionary = state["job_definitions"]
	var rng: RandomNumberGenerator = state["rng"]
	var sim_start_day: int = int(state["sim_start_day"])
	var sim_start_year: int = int(state["sim_start_year"])
	var reason_world_gen_id: int = int(state["reason_world_gen_id"])
	var res_unit_cat_id: int = int(state["res_unit_cat_id"])
	var batch_size: int = int(state["district_batch_size"])

	var institutions_cfg: Dictionary = state["institutions_cfg"]
	var default_civic_org_id: String = str(state["default_civic_org_id"])
	var seeded_orgs: Array = institutions_cfg.get("seeded_organizations", [])
	var site_wing_templates: Dictionary = state["site_wing_templates"]

	var brand_org_map: Dictionary = state["brand_org_map"]
	var category_org_map: Dictionary = state["category_org_map"]
	var host_orgs_by_category: Dictionary = state["host_orgs_by_category"]
	var org_pay_cadences: Dictionary = state["org_pay_cadences"]
	var borough_police_orgs: Dictionary = state["borough_police_orgs"]

	# 0. Seed Hierarchical Public Organizations & Era-Brand Corporate Organizations
	var org_inserts: Array[String] = []
	for org_def in seeded_orgs:
		if not (org_def is Dictionary):
			continue
		var oid: String = str(org_def.get("org_id", "")).strip_edges()
		if oid.is_empty():
			continue
		var parent_raw = org_def.get("parent_org_id", null)
		var parent_sql: String = "NULL" if (parent_raw == null or str(parent_raw).is_empty()) else ("'%s'" % str(parent_raw).replace("'", "''"))
		var autonomy_mode: String = str(org_def.get("autonomy_mode", "DIRECT"))
		var dname: String = str(org_def.get("display_name", oid)).replace("'", "''")
		var otype: String = str(org_def.get("org_type", "INSTITUTION"))
		var lstatus: String = str(org_def.get("legal_status", "FORMAL"))
		var rclass: String = str(org_def.get("institution_rail_class", "STANDARD"))
		org_pay_cadences[oid] = str(org_def.get("default_pay_cadence", "MONTHLY_LAST_WORKING_DAY"))

		org_inserts.append("""
			INSERT OR IGNORE INTO organizations (
				org_id, parent_org_id, display_name, org_type, legal_status,
				institution_rail_class, autonomy_mode, valid_from, valid_to, change_reason_id
			) VALUES ('%s', %s, '%s', '%s', '%s', '%s', '%s', %d, NULL, %d);
		""" % [oid, parent_sql, dname, otype, lstatus, rclass, autonomy_mode, sim_start_day, reason_world_gen_id])

		for m_title in org_def.get("matched_titles", []):
			brand_org_map[str(m_title)] = oid
		for m_cat in org_def.get("matched_categories", []):
			category_org_map[str(m_cat)] = oid
		for h_cat in org_def.get("host_categories", []):
			var hc: String = str(h_cat)
			if not host_orgs_by_category.has(hc):
				host_orgs_by_category[hc] = []
			host_orgs_by_category[hc].append(oid)

		if org_def.has("per_borough_template") and org_def["per_borough_template"] is Dictionary:
			var tmpl: Dictionary = org_def["per_borough_template"]
			var id_pat: String = str(tmpl.get("org_id_pattern", "%s_{borough_slug}" % oid))
			var name_pat: String = str(tmpl.get("display_name_pattern", "{borough_name} %s" % dname))
			for b_id in boroughs.keys():
				var b_dict: Dictionary = boroughs[b_id]
				var b_name: String = str(b_dict.get("display_name", b_id))
				var b_slug: String = str(b_id).to_upper().replace("BOROUGH_", "").replace(" ", "_")
				var sub_oid: String = id_pat.replace("{borough_slug}", b_slug)
				var sub_name: String = name_pat.replace("{borough_name}", b_name).replace("'", "''")
				borough_police_orgs[str(b_id)] = sub_oid
				org_pay_cadences[sub_oid] = org_pay_cadences[oid]
				org_inserts.append("""
					INSERT OR IGNORE INTO organizations (
						org_id, parent_org_id, display_name, org_type, legal_status,
						institution_rail_class, autonomy_mode, valid_from, valid_to, change_reason_id
					) VALUES ('%s', '%s', '%s', '%s', '%s', '%s', '%s', %d, NULL, %d);
				""" % [sub_oid, oid, sub_name, otype, lstatus, rclass, autonomy_mode, sim_start_day, reason_world_gen_id])

	var era_brands_all: Dictionary = state["comm_naming"].get("era_brands", {})
	for brand_cat in era_brands_all.keys():
		var entries = era_brands_all[brand_cat]
		if not (entries is Array):
			continue
		for entry in entries:
			if not (entry is Dictionary):
				continue
			var b_org_id: String = str(entry.get("org_id", "")).strip_edges()
			var b_name: String = str(entry.get("name", "")).strip_edges()
			if b_org_id.is_empty() or b_name.is_empty():
				continue
			if not b_name.contains("{"):
				brand_org_map[b_name] = b_org_id
			if b_org_id == "ORG:POST_OFFICE":
				continue
			var b_rail: String = str(entry.get("institution_rail_class", "STANDARD"))
			var from_yr: int = int(entry.get("valid_from_year", 1900))
			var to_yr: int = int(entry.get("valid_to_year", 2099))
			var b_valid_from: int = sim_start_day if from_yr <= sim_start_year else sim_start_day + ((from_yr - sim_start_year) * 365)
			var b_valid_to_sql: String = "NULL" if to_yr >= 2020 else str(sim_start_day + (maxi(1, to_yr - sim_start_year + 1) * 365))
			org_pay_cadences[b_org_id] = "MONTHLY_LAST_WORKING_DAY"
			org_inserts.append("""
				INSERT OR IGNORE INTO organizations (
					org_id, parent_org_id, display_name, org_type, legal_status,
					institution_rail_class, autonomy_mode, valid_from, valid_to, change_reason_id
				) VALUES ('%s', NULL, '%s', 'CORPORATION', 'FORMAL', '%s', 'DIRECT', %d, %s, %d);
			""" % [b_org_id, b_name.replace("'", "''"), b_rail, b_valid_from, b_valid_to_sql, reason_world_gen_id])

	if not org_inserts.is_empty():
		DB_MANAGER.execute_batch(org_inserts)

	var dist_inserts: Array[String] = []
	var estab_inserts: Array[String] = []
	var job_slot_inserts: Array[String] = []

	var by_cat: Dictionary = state["by_cat"]
	var district_residents_map: Dictionary = state["district_residents_map"]
	var available_job_slots: Array[Dictionary] = state["available_job_slots"]
	var available_tied_housing: Dictionary = state["available_tied_housing"]
	var employer_wage_biases: Dictionary = state["employer_wage_biases"]
	var district_naming: Dictionary = state["district_naming"]
	var district_estab_counts: Dictionary = state["district_estab_counts"]

	var street_roots: Array = state["street_roots"]
	var street_suffixes: Array = state["street_suffixes"]
	var street_cap_min: int = int(state["street_cap_min"])
	var street_cap_max: int = int(state["street_cap_max"])
	var civic_naming_formats: Array = state["civic_naming_formats"]
	var total_city_est_pop: float = float(state["total_city_est_pop"])

	var est_id: int = int(state["est_id"])
	var current_slot_id: int = int(state["current_slot_id"])
	var total_tied_units_count: int = int(state["total_tied_units_count"])
	var block_idx: int = 0

	for dist_id in districts.keys():
		var d: Dictionary = districts[dist_id]
		var district_type: String = str(d.get("district_type", ""))
		assert(archetypes.has(district_type), "FATAL: Archetype '%s' not registered." % district_type)

		var arch: Dictionary = archetypes[district_type]
		var is_vacant_plot: bool = bool(d.get("is_vacant_plot", arch.get("is_vacant_plot", false)))
		var coords: Vector2i = d.get("grid_coords", Vector2i(0, 0))
		var g_size: Vector2i = d.get("grid_size", Vector2i(1, 1))
		var building_count: int = 0 if is_vacant_plot else maxi(1, int(d.get("actual_building_count", 1)))
		var pop_range: Array = arch.get("population_range", [0, 0])
		var exp_min: int = int(d.get("expected_pop_min", pop_range[0]))
		var exp_max: int = int(d.get("expected_pop_max", pop_range[1]))

		var borough_id: String = str(d.get("borough_id", "BOROUGH_UNASSIGNED"))
		var borough_name: String = str(boroughs.get(borough_id, {}).get("display_name", "")).replace(" Council", "").strip_edges()

		var used_streets_in_district: Dictionary = {}
		var first_street: Dictionary = _pick_unique_street(street_roots, street_suffixes, used_streets_in_district, rng)
		var street_root: String = first_street["root"]
		var parcel_street_name: String = first_street["full"]
		var active_street_cap: int = rng.randi_range(street_cap_min, street_cap_max)

		var district_display: String = str(d.get("display_name", dist_id))
		var district_prefix: String = district_display.split(" ")[0] if not district_display.is_empty() else street_root
		if borough_name.is_empty():
			borough_name = district_prefix

		district_naming[dist_id] = {
			"used_streets": used_streets_in_district,
			"street_root": street_root,
			"parcel_street_name": parcel_street_name,
			"active_street_cap": active_street_cap,
			"street_door_counter": 1,
			"district_display": district_display,
			"district_prefix": district_prefix,
			"borough_id": borough_id,
			"borough_name": borough_name,
			"used_names": {}
		}
		district_estab_counts[dist_id] = 0
		district_residents_map[dist_id] = []

		dist_inserts.append("""
			INSERT INTO districts (
				district_id, borough_id, display_name, district_type,
				grid_x, grid_z, grid_width, grid_height,
				target_building_count, expected_pop_min, expected_pop_max,
				base_unemployment_rate, base_disposable_income, base_zone_health, base_police_heat,
				is_home_turf, valid_from, valid_to, change_reason_id
			) VALUES (
				'%s', '%s', '%s', '%s',
				%d, %d, %d, %d,
				%d, %d, %d,
				%f, %f, %f, %f,
				0, %d, NULL, %d
			);
		""" % [
			dist_id, borough_id, district_display.replace("'", "''"), district_type,
			coords.x, coords.y, g_size.x, g_size.y,
			building_count, exp_min, exp_max,
			float(d.get("unemployment_rate", 0.0)), float(d.get("avg_disposable_income", 75.0)),
			float(d.get("zone_health_index", 50.0)), float(d.get("actual_police_heat", 0.20)),
			sim_start_day, reason_world_gen_id
		])

		if is_vacant_plot:
			block_idx += 1
			continue

		# Dedicated Institutional Anchor (resolved from building_classes via establishment_category)
		var building_classes: Dictionary = state["building_classes"]
		var anchor_cat_name: String = str(arch.get("establishment_category", "")).strip_edges().to_upper()
		var anchor_class_def: Dictionary = _lookup_building_class(building_classes, anchor_cat_name) if not anchor_cat_name.is_empty() else {}
		if not anchor_class_def.is_empty() and (str(arch.get("sector_class", "")).to_upper() == "CIVIC" or bool(arch.get("is_public_landmark", false))):
			var inst: Dictionary = anchor_class_def
			var cat_name: String = anchor_cat_name
			assert(arch.has("sector_class"), "FATAL: Archetype '%s' is missing mandatory 'sector_class'!" % district_type)
			var inst_sector: String = str(arch["sector_class"]).to_upper()
			var base_inst_label: String = str(inst.get("display_name", arch.get("display_name", cat_name)))
			var display_label: String = _format_civic_anchor_title(
				base_inst_label, district_display, borough_name, street_root, civic_naming_formats, rng
			).replace("'", "''")
			var capacity: int = int(inst.get("default_capacity", 250))
			var cat_id: int = DB_MANAGER.get_label_id("ESTABLISHMENT_CATEGORY", cat_name)
			var institution_estab_id: int = est_id
			var inst_owner_org: String = str(category_org_map.get(cat_name, default_civic_org_id))
			if cat_name == "POLICE_STATION" and borough_police_orgs.has(borough_id):
				inst_owner_org = str(borough_police_orgs[borough_id])

			estab_inserts.append("""
				INSERT INTO establishments (
					establishment_id, district_id, building_index, unit_door_number,
					owner_org_id, name, category_id, capacity, is_vacant, valid_from, valid_to, change_reason_id
				) VALUES (%d, '%s', 0, 'MAIN', '%s', '%s', %d, %d, 0, %d, NULL, %d);
			""" % [institution_estab_id, dist_id, inst_owner_org, display_label, cat_id, capacity, sim_start_day, reason_world_gen_id])

			_register_est_cat(by_cat, cat_name, institution_estab_id, dist_id, capacity)
			employer_wage_biases[institution_estab_id] = 0.0
			var inst_pop_ratio: float = float(arch.get("pop_ratio", 0.0))
			var inst_pop_scale: float = clampf(total_city_est_pop / inst_pop_ratio, 0.08, 1.0) if inst_pop_ratio > 0.0 else 1.0
			var hosted_orgs: Array = host_orgs_by_category.get(cat_name, [])
			current_slot_id = expand_staffing_slots(
				available_job_slots, job_slot_inserts, current_slot_id, institution_estab_id, dist_id,
				inst_sector, inst, job_definitions, 0.0, sim_start_day, reason_world_gen_id, rng,
				inst_owner_org, hosted_orgs, inst_pop_scale
			)
			est_id += 1
			district_estab_counts[dist_id] = int(district_estab_counts[dist_id]) + 1

			if site_wing_templates.has(cat_name):
				var wings: Array = site_wing_templates[cat_name]
				var wing_b_idx: int = 1
				for wing_def in wings:
					if not (wing_def is Dictionary):
						continue
					var wing_code: String = str(wing_def.get("wing_code", "WING_%d" % wing_b_idx))
					var wing_suffix: String = str(wing_def.get("name_suffix", wing_code))
					var wing_cat: String = str(wing_def.get("category_code", cat_name))
					var wing_cat_id: int = DB_MANAGER.get_label_id("ESTABLISHMENT_CATEGORY", wing_cat)
					var wing_owner: String = str(wing_def.get("owner_org_id", inst_owner_org))
					var wing_cap: int = maxi(10, int(round(float(capacity) * float(wing_def.get("capacity_ratio", 0.15)))))
					var wing_title: String = ("%s — %s" % [display_label, wing_suffix]).replace("'", "''")

					estab_inserts.append("""
						INSERT INTO establishments (
							establishment_id, district_id, building_index, unit_door_number,
							owner_org_id, name, category_id, capacity, is_vacant, valid_from, valid_to, change_reason_id
						) VALUES (%d, '%s', %d, '%s', '%s', '%s', %d, %d, 0, %d, NULL, %d);
					""" % [est_id, dist_id, wing_b_idx, wing_code, wing_owner, wing_title, wing_cat_id, wing_cap, sim_start_day, reason_world_gen_id])

					_register_est_cat(by_cat, wing_cat, est_id, dist_id, wing_cap)
					employer_wage_biases[est_id] = 0.0
					est_id += 1
					wing_b_idx += 1
					district_estab_counts[dist_id] = int(district_estab_counts[dist_id]) + 1

			var housing_profiles: Array[Dictionary] = _extract_housing_profiles(arch)
			for h_prof in housing_profiles:
				var res_type: String = str(h_prof.get("residence_type", "NONE"))
				if res_type == "NONE":
					continue
				var int_res_type_id: int = DB_MANAGER.get_label_id("RESIDENCE_TYPE", res_type)
				var int_tenure_type: String = str(h_prof.get("tenure_type", "EMPLOYMENT_TIED"))
				var int_wealth_bracket: int = int(h_prof.get("wealth_bracket", 3))

				var units_to_generate: int = 1
				if h_prof.has("capacity"):
					units_to_generate = maxi(1, int(round(float(h_prof["capacity"]) / 2.0)))
				elif arch.has("population_range"):
					var p_rng: Array = arch["population_range"]
					units_to_generate = maxi(1, int(round(float(p_rng[1]) / 2.5)))
				units_to_generate = mini(units_to_generate, 60)

				if not available_tied_housing.has(res_type):
					available_tied_housing[res_type] = []

				for u_idx in range(units_to_generate):
					var unit_num: int = u_idx + 1
					var unit_door: String = "Room %d" % unit_num
					var unit_title: String = "%s %s %s" % [display_label, res_type.replace("_", " ").capitalize(), unit_door]

					estab_inserts.append("""
						INSERT INTO establishments (
							establishment_id, district_id, building_index, unit_door_number,
							owner_org_id, name, category_id, capacity, is_vacant, valid_from, valid_to, change_reason_id
						) VALUES (%d, '%s', 0, '%s', '%s', '%s', %d, 2, 1, %d, NULL, %d);
					""" % [
						est_id, dist_id, unit_door, inst_owner_org,
						unit_title.replace("'", "''"), res_unit_cat_id, sim_start_day, reason_world_gen_id
					])

					available_tied_housing[res_type].append({
						"establishment_id": est_id,
						"district_id": dist_id,
						"residence_type": res_type,
						"residence_type_id": int_res_type_id,
						"wealth_bracket_id": int_wealth_bracket,
						"tenure_type": int_tenure_type,
						"parent_workplace_id": institution_estab_id,
						"require_unmarried": bool(h_prof.get("require_unmarried", false)),
						"relocates_family": bool(h_prof.get("relocates_family", false))
					})

					total_tied_units_count += 1
					est_id += 1
					district_estab_counts[dist_id] = int(district_estab_counts[dist_id]) + 1

		# Sub-Block Embedded Civics (resolved from building_classes via establishment_category)
		if d.has("embedded_civics"):
			for civic_key in d["embedded_civics"]:
				var c_arch: Dictionary = archetypes.get(civic_key, {})
				var c_cat_name: String = str(c_arch.get("establishment_category", civic_key.to_upper())).strip_edges().to_upper()
				var c_inst: Dictionary = _lookup_building_class(building_classes, c_cat_name)
				assert(not c_inst.is_empty(), "FATAL: [PremisesWorkplaceBuilder] Embedded civic category '%s' not found in building_classes!" % c_cat_name)
				assert(c_arch.has("sector_class"), "FATAL: Embedded civic archetype '%s' missing mandatory 'sector_class'!" % civic_key)
				var c_sector: String = str(c_arch["sector_class"]).to_upper()
				var c_base_label: String = str(c_inst.get("display_name", c_arch.get("display_name", c_cat_name)))
				var c_display: String = _format_civic_anchor_title(
					c_base_label, district_display, borough_name, street_root, civic_naming_formats, rng
				).replace("'", "''")
				var c_cap: int = int(c_inst.get("default_capacity", 250))
				var c_cat_id: int = DB_MANAGER.get_label_id("ESTABLISHMENT_CATEGORY", c_cat_name)
				var embedded_estab_id: int = est_id
				var c_owner_org: String = str(category_org_map.get(c_cat_name, default_civic_org_id))
				if c_cat_name == "POLICE_STATION" and borough_police_orgs.has(borough_id):
					c_owner_org = str(borough_police_orgs[borough_id])

				estab_inserts.append("""
					INSERT INTO establishments (
						establishment_id, district_id, building_index, unit_door_number,
						owner_org_id, name, category_id, capacity, is_vacant, valid_from, valid_to, change_reason_id
					) VALUES (%d, '%s', 0, 'CIVIC_PARCEL', '%s', '%s', %d, %d, 0, %d, NULL, %d);
				""" % [embedded_estab_id, dist_id, c_owner_org, c_display, c_cat_id, c_cap, sim_start_day, reason_world_gen_id])

				_register_est_cat(by_cat, c_cat_name, embedded_estab_id, dist_id, c_cap)
				employer_wage_biases[embedded_estab_id] = 0.0
				var c_pop_ratio: float = float(c_arch.get("pop_ratio", 0.0))
				var c_pop_scale: float = clampf(total_city_est_pop / c_pop_ratio, 0.08, 1.0) if c_pop_ratio > 0.0 else 1.0
				current_slot_id = expand_staffing_slots(
					available_job_slots, job_slot_inserts, current_slot_id, embedded_estab_id, dist_id,
					c_sector, c_inst, job_definitions, 0.0, sim_start_day, reason_world_gen_id, rng,
					c_owner_org, host_orgs_by_category.get(c_cat_name, []), c_pop_scale
				)
				est_id += 1
				district_estab_counts[dist_id] = int(district_estab_counts[dist_id]) + 1

				var embedded_h_profiles: Array[Dictionary] = _extract_housing_profiles(c_arch)
				for eh_prof in embedded_h_profiles:
					var e_res_type: String = str(eh_prof.get("residence_type", "NONE"))
					if e_res_type == "NONE":
						continue
					var e_res_type_id: int = DB_MANAGER.get_label_id("RESIDENCE_TYPE", e_res_type)
					var e_wealth: int = int(eh_prof.get("wealth_bracket", 2))
					var e_tenure: String = str(eh_prof.get("tenure_type", "EMPLOYMENT_TIED"))
					var e_door := "Lodge 1"
					var e_title := "%s %s" % [c_display, e_door]

					estab_inserts.append("""
						INSERT INTO establishments (
							establishment_id, district_id, building_index, unit_door_number,
							owner_org_id, name, category_id, capacity, is_vacant, valid_from, valid_to, change_reason_id
						) VALUES (%d, '%s', 0, '%s', '%s', '%s', %d, 4, 1, %d, NULL, %d);
					""" % [
						est_id, dist_id, e_door, c_owner_org,
						e_title.replace("'", "''"), res_unit_cat_id, sim_start_day, reason_world_gen_id
					])

					if not available_tied_housing.has(e_res_type):
						available_tied_housing[e_res_type] = []
					available_tied_housing[e_res_type].append({
						"establishment_id": est_id,
						"district_id": dist_id,
						"residence_type": e_res_type,
						"residence_type_id": e_res_type_id,
						"wealth_bracket_id": e_wealth,
						"tenure_type": e_tenure,
						"parent_workplace_id": embedded_estab_id,
						"require_unmarried": bool(eh_prof.get("require_unmarried", false)),
						"relocates_family": bool(eh_prof.get("relocates_family", false))
					})

					total_tied_units_count += 1
					est_id += 1
					district_estab_counts[dist_id] = int(district_estab_counts[dist_id]) + 1

		if block_idx > 0 and block_idx % batch_size == 0:
			DB_MANAGER.execute_batch(dist_inserts)
			DB_MANAGER.execute_batch(estab_inserts)
			if not job_slot_inserts.is_empty():
				DB_MANAGER.execute_batch(job_slot_inserts)
				job_slot_inserts.clear()
			dist_inserts.clear()
			estab_inserts.clear()
			if on_progress.is_valid():
				on_progress.call(float(block_idx), float(maxi(1, districts.size())), "Districts & Civics: %d / %d" % [block_idx, districts.size()])
				var loop = Engine.get_main_loop()
				if loop is SceneTree:
					await (loop as SceneTree).process_frame

		block_idx += 1

	if not dist_inserts.is_empty():
		DB_MANAGER.execute_batch(dist_inserts)
	if not estab_inserts.is_empty():
		DB_MANAGER.execute_batch(estab_inserts)
	if not job_slot_inserts.is_empty():
		DB_MANAGER.execute_batch(job_slot_inserts)

	state["est_id"] = est_id
	state["current_slot_id"] = current_slot_id
	state["total_tied_units_count"] = total_tied_units_count

## Phase B: Builds residential establishments and initial households without job/school allocation
static func build_residential_and_households(state: Dictionary, on_progress: Callable = Callable()) -> void:
	var districts: Dictionary = state["districts"]
	var archetypes: Dictionary = state["archetypes"]
	var cultural: Dictionary = state["cultural"]
	var rng: RandomNumberGenerator = state["rng"]
	var sim_start_day: int = int(state["sim_start_day"])
	var reason_world_gen_id: int = int(state["reason_world_gen_id"])
	var res_unit_cat_id: int = int(state["res_unit_cat_id"])
	var default_civic_org_id: String = str(state["default_civic_org_id"])
	var batch_size: int = int(state["district_batch_size"])

	var street_roots: Array = state["street_roots"]
	var street_suffixes: Array = state["street_suffixes"]
	var street_cap_min: int = int(state["street_cap_min"])
	var street_cap_max: int = int(state["street_cap_max"])
	var bldg_roots: Array = state["bldg_roots"]
	var bldg_suffixes: Array = state["bldg_suffixes"]
	var fmt_flat_unit: String = str(state["fmt_flat_unit"])
	var fmt_flat_door: String = str(state["fmt_flat_door"])
	var fmt_street_unit: String = str(state["fmt_street_unit"])
	var fmt_street_door: String = str(state["fmt_street_door"])

	var generated_households: Array[Dictionary] = state["generated_households"]
	var district_naming: Dictionary = state["district_naming"]
	var district_estab_counts: Dictionary = state["district_estab_counts"]

	var estab_inserts: Array[String] = []
	var household_inserts: Array[String] = []
	var est_id: int = int(state["est_id"])
	var current_household_id: int = int(state["current_household_id"])
	var block_idx: int = 0

	for dist_id in districts.keys():
		var d: Dictionary = districts[dist_id]
		var district_type: String = str(d.get("district_type", ""))
		var arch: Dictionary = archetypes[district_type]
		if bool(d.get("is_vacant_plot", arch.get("is_vacant_plot", false))):
			block_idx += 1
			continue

		var naming: Dictionary = district_naming[dist_id]
		var h_profiles: Array[Dictionary] = _extract_housing_profiles(arch)
		var housing_prof: Dictionary = h_profiles[0] if not h_profiles.is_empty() else {}
		var res_type_code: String = str(housing_prof.get("residence_type", "NONE"))
		var wealth_bracket: int = int(housing_prof.get("wealth_bracket", 2))
		var res_type_id: int = DB_MANAGER.get_label_id("RESIDENCE_TYPE", res_type_code)
		var tenure_type: String = str(housing_prof.get("tenure_type", "COUNCIL_TENANT"))
		var is_multi_flat_block: bool = (res_type_code == "COUNCIL_FLAT" or res_type_code == "FLAT_ABOVE_SHOP" or district_type == "high_density_high_rise")

		var allocations: Array = d.get("building_allocations", [])
		for alloc in allocations:
			var b_idx: int = int(alloc["building_index"])
			var num_homes: int = int(alloc["habitable_units"])
			if num_homes <= 0 or res_type_code == "NONE":
				continue

			var building_name := ""
			if is_multi_flat_block:
				var b_root: String = str(bldg_roots[rng.randi() % bldg_roots.size()])
				var b_suf: String = str(bldg_suffixes[rng.randi() % bldg_suffixes.size()])
				building_name = "%s %s" % [b_root, b_suf]

			for u_idx in range(num_homes):
				var unit_door := ""
				var unit_name := ""
				if is_multi_flat_block:
					var flat_num: int = u_idx + 1
					unit_door = fmt_flat_door.replace("{door}", str(flat_num))
					unit_name = fmt_flat_unit.replace("{door}", str(flat_num)).replace("{building}", building_name)
				else:
					if int(naming["street_door_counter"]) > int(naming["active_street_cap"]):
						var next_street: Dictionary = _pick_unique_street(street_roots, street_suffixes, naming["used_streets"], rng)
						naming["street_root"] = next_street["root"]
						naming["parcel_street_name"] = next_street["full"]
						naming["street_door_counter"] = 1
						naming["active_street_cap"] = rng.randi_range(street_cap_min, street_cap_max)

					var door_num: int = int(naming["street_door_counter"])
					naming["street_door_counter"] = door_num + 1
					unit_door = fmt_street_door.replace("{door}", str(door_num))
					unit_name = fmt_street_unit.replace("{door}", str(door_num)).replace("{street}", str(naming["parcel_street_name"]))

				var is_vacant: int = 1 if (rng.randf() < 0.03) else 0
				var res_owner_sql: String = "'%s'" % default_civic_org_id if tenure_type == "COUNCIL_TENANT" else "NULL"

				estab_inserts.append("""
					INSERT INTO establishments (
						establishment_id, district_id, building_index, unit_door_number,
						owner_org_id, name, category_id, capacity, is_vacant, valid_from, valid_to, change_reason_id
					) VALUES (%d, '%s', %d, '%s', %s, '%s', %d, 5, %d, %d, NULL, %d);
				""" % [
					est_id, dist_id, b_idx, unit_door, res_owner_sql,
					unit_name.replace("'", "''"), res_unit_cat_id, is_vacant, sim_start_day, reason_world_gen_id
				])

				if is_vacant == 0:
					var cult: Dictionary = roll_household_culture(cultural, rng, district_type)
					var eth_id: int = DB_MANAGER.get_label_id("ETHNICITY", cult["ethnicity"])
					var religion_id: int = DB_MANAGER.get_label_id("RELIGION", cult["religion"])

					household_inserts.append("""
						INSERT INTO households (
							household_id, establishment_id, head_resident_id, residence_type_id,
							wealth_bracket_id, ethnicity_id, religion_id,
							valid_from, valid_to, change_reason_id
						) VALUES (%d, %d, NULL, %d, %d, %d, %d, %d, NULL, %d);
					""" % [
						current_household_id, est_id, res_type_id,
						wealth_bracket, eth_id, religion_id, sim_start_day, reason_world_gen_id
					])

					generated_households.append({
						"household_id": current_household_id,
						"establishment_id": est_id,
						"district_id": dist_id,
						"district_type": district_type,
						"ethnicity": cult["ethnicity"],
						"ethnicity_id": eth_id,
						"religion": cult["religion"],
						"religion_id": religion_id,
						"surnames_pool": cult["surnames_pool"],
						"unemp_rate": float(arch.get("unemployment_rate_range", [0.10, 0.15])[0])
					})
					current_household_id += 1

				est_id += 1
				district_estab_counts[dist_id] = int(district_estab_counts[dist_id]) + 1

		if block_idx > 0 and block_idx % batch_size == 0:
			DB_MANAGER.execute_batch(estab_inserts)
			DB_MANAGER.execute_batch(household_inserts)
			estab_inserts.clear()
			household_inserts.clear()
			if on_progress.is_valid():
				on_progress.call(float(block_idx), float(maxi(1, districts.size())), "Residential & Households: %d / %d" % [block_idx, districts.size()])
				var loop = Engine.get_main_loop()
				if loop is SceneTree:
					await (loop as SceneTree).process_frame

		block_idx += 1

	if not estab_inserts.is_empty():
		DB_MANAGER.execute_batch(estab_inserts)
	if not household_inserts.is_empty():
		DB_MANAGER.execute_batch(household_inserts)

	state["est_id"] = est_id
	state["current_household_id"] = current_household_id

## Phase C: Allocates commercial & industrial establishments based on population/demand rules and generates job slots
static func build_commercial_industrial_and_slots(state: Dictionary, on_progress: Callable = Callable()) -> void:
	var districts: Dictionary = state["districts"]
	var archetypes: Dictionary = state["archetypes"]
	var job_definitions: Dictionary = state["job_definitions"]
	var cultural: Dictionary = state["cultural"]
	var lexicon: Dictionary = state["lexicon"]
	var rng: RandomNumberGenerator = state["rng"]
	var sim_start_day: int = int(state["sim_start_day"])
	var sim_start_year: int = int(state["sim_start_year"])
	var reason_world_gen_id: int = int(state["reason_world_gen_id"])
	var batch_size: int = int(state["district_batch_size"])

	var comm_classes: Dictionary = state["comm_classes"]
	var ind_classes: Dictionary = state["ind_classes"]
	var embedded_civic_classes: Dictionary = state["embedded_civic_classes"]
	var clandestine_classes: Dictionary = state["clandestine_classes"]
	var comm_naming: Dictionary = state["comm_naming"]
	var civic_naming_formats: Array = state["civic_naming_formats"]
	var default_civic_org_id: String = str(state["default_civic_org_id"])
	var brand_org_map: Dictionary = state["brand_org_map"]
	var category_org_map: Dictionary = state["category_org_map"]
	var borough_police_orgs: Dictionary = state["borough_police_orgs"]

	var block_estimates: Dictionary = state["block_estimates"]
	var by_cat: Dictionary = state["by_cat"]
	var commercial_instances_by_type: Dictionary = state["commercial_instances_by_type"]
	var available_job_slots: Array[Dictionary] = state["available_job_slots"]
	var proprietor_hints: Dictionary = state["proprietor_hints"]
	var employer_wage_biases: Dictionary = state["employer_wage_biases"]
	var district_naming: Dictionary = state["district_naming"]
	var district_estab_counts: Dictionary = state["district_estab_counts"]

	var estab_inserts: Array[String] = []
	var job_slot_inserts: Array[String] = []
	var est_id: int = int(state["est_id"])
	var current_slot_id: int = int(state["current_slot_id"])
	var block_idx: int = 0

	for dist_id in districts.keys():
		var d: Dictionary = districts[dist_id]
		var district_type: String = str(d.get("district_type", ""))
		var arch: Dictionary = archetypes[district_type]
		if bool(d.get("is_vacant_plot", arch.get("is_vacant_plot", false))):
			block_idx += 1
			continue

		var naming: Dictionary = district_naming[dist_id]
		var street_root: String = str(naming["street_root"])
		var district_display: String = str(naming["district_display"])
		var district_prefix: String = str(naming["district_prefix"])
		var borough_id: String = str(naming["borough_id"])
		var borough_name: String = str(naming["borough_name"])
		var used_names_in_district: Dictionary = naming["used_names"]
		var center_vec: Vector2 = SPATIAL_RESOLVER._resolve_vector2(d.get("spatial_anchor", Vector2.ZERO))

		var allocations: Array = d.get("building_allocations", [])
		var block_tenancy_counts: Dictionary = {}

		for alloc in allocations:
			var b_idx: int = int(alloc["building_index"])
			var num_comm: int = int(alloc["commercial_units"])
			var num_ind: int = int(alloc["industrial_units"])

			# Commercial Units
			if num_comm > 0:
				for _c in range(num_comm):
					var tenancy: Dictionary = pick_tenancy(rng, comm_classes, embedded_civic_classes, district_type)
					var cat_code: String = tenancy["code"]

					var max_per_block: int = 2 if cat_code in ["CORNER_SHOP", "LOCAL_PUB"] else 1
					var attempts := 0
					while block_tenancy_counts.get(cat_code, 0) >= max_per_block and attempts < 10:
						attempts += 1
						tenancy = pick_tenancy(rng, comm_classes, embedded_civic_classes, district_type)
						cat_code = tenancy["code"]

					block_tenancy_counts[cat_code] = block_tenancy_counts.get(cat_code, 0) + 1

					var name_result: Dictionary = _generate_business_name(
						cat_code, tenancy, false, district_type,
						street_root, district_prefix, district_display, borough_name, sim_start_year,
						comm_naming, civic_naming_formats, cultural, lexicon, used_names_in_district, rng
					)
					var display_title: String = str(name_result["title"])
					used_names_in_district[display_title] = true
					if name_result.has("proprietor"):
						proprietor_hints[est_id] = name_result["proprietor"]

					var cap: int = int(tenancy.get("default_capacity", 20))
					var travel_dist: float = float(tenancy.get("customer_travel_distance_m", 600.0))
					var req_threshold: float = float(tenancy.get("required_customer_threshold", 100))

					var existing_list: Array = commercial_instances_by_type.get(cat_code, [])
					var is_viable: bool = SPATIAL_RESOLVER.is_catchment_viable(
						center_vec, existing_list, districts, block_estimates, travel_dist, req_threshold
					)

					var is_vacant: int = 0
					if not is_viable and rng.randf() < 0.50:
						is_vacant = 1
						cap = 0

					var comm_owner_org: String = ""
					if category_org_map.has(cat_code):
						comm_owner_org = str(category_org_map[cat_code])
					elif cat_code == "LOCAL_POLICE_POST" and borough_police_orgs.has(borough_id):
						comm_owner_org = str(borough_police_orgs[borough_id])
					elif str(tenancy.get("sector", "")).to_upper() == "CIVIC_SERVICE" and not bool(tenancy.get("use_proprietor_name", true)):
						comm_owner_org = default_civic_org_id
					else:
						for b_title in brand_org_map.keys():
							if display_title == b_title or display_title.begins_with("%s (" % b_title):
								comm_owner_org = str(brand_org_map[b_title])
								break

					var comm_owner_sql: String = "'%s'" % comm_owner_org if not comm_owner_org.is_empty() else "NULL"
					var cat_id: int = DB_MANAGER.get_label_id("ESTABLISHMENT_CATEGORY", cat_code)

					estab_inserts.append("""
						INSERT INTO establishments (
							establishment_id, district_id, building_index, unit_door_number,
							owner_org_id, name, category_id, capacity, is_vacant, valid_from, valid_to, change_reason_id
						) VALUES (%d, '%s', %d, 'SHOP', %s, '%s', %d, %d, %d, %d, NULL, %d);
					""" % [est_id, dist_id, b_idx, comm_owner_sql, display_title.replace("'", "''"), cat_id, cap, is_vacant, sim_start_day, reason_world_gen_id])

					if not commercial_instances_by_type.has(cat_code):
						commercial_instances_by_type[cat_code] = []
					commercial_instances_by_type[cat_code].append(center_vec)

					_register_est_cat(by_cat, cat_code, est_id, dist_id, cap)
					_register_est_cat(by_cat, "COMMERCIAL", est_id, dist_id, cap)

					if is_vacant == 0:
						assert(tenancy.has("sector"), "FATAL: Commercial tenancy '%s' missing mandatory 'sector' field!" % cat_code)
						var comm_sector: String = str(tenancy["sector"]).to_upper()
						var wage_bias: float = 0.0 if comm_owner_sql != "NULL" else _roll_employer_wage_bias(rng)
						employer_wage_biases[est_id] = wage_bias
						current_slot_id = expand_staffing_slots(
							available_job_slots, job_slot_inserts, current_slot_id, est_id, dist_id,
							comm_sector, tenancy, job_definitions, wage_bias, sim_start_day, reason_world_gen_id, rng,
							comm_owner_org
						)

					est_id += 1
					district_estab_counts[dist_id] = int(district_estab_counts[dist_id]) + 1

			# Industrial Units
			if num_ind > 0:
				for _i in range(num_ind):
					var ind_tenancy: Dictionary = pick_tenancy(rng, ind_classes, {}, district_type)
					var i_code: String = ind_tenancy["code"]
					var ind_name_res: Dictionary = _generate_business_name(
						i_code, ind_tenancy, true, district_type,
						street_root, district_prefix, district_display, borough_name, sim_start_year,
						comm_naming, civic_naming_formats, cultural, lexicon, used_names_in_district, rng
					)
					var i_title: String = str(ind_name_res["title"])
					used_names_in_district[i_title] = true
					if ind_name_res.has("proprietor"):
						proprietor_hints[est_id] = ind_name_res["proprietor"]

					var i_cap: int = int(ind_tenancy.get("default_capacity", 40))
					var i_cat_id: int = DB_MANAGER.get_label_id("ESTABLISHMENT_CATEGORY", i_code)

					estab_inserts.append("""
						INSERT INTO establishments (
							establishment_id, district_id, building_index, unit_door_number,
							owner_org_id, name, category_id, capacity, is_vacant, valid_from, valid_to, change_reason_id
						) VALUES (%d, '%s', %d, 'WORKS', NULL, '%s', %d, %d, 0, %d, NULL, %d);
					""" % [est_id, dist_id, b_idx, i_title.replace("'", "''"), i_cat_id, i_cap, sim_start_day, reason_world_gen_id])

					_register_est_cat(by_cat, i_code, est_id, dist_id, i_cap)
					_register_est_cat(by_cat, "INDUSTRIAL", est_id, dist_id, i_cap)

					assert(ind_tenancy.has("sector"), "FATAL: Industrial tenancy '%s' missing mandatory 'sector' field!" % i_code)
					var ind_sector: String = str(ind_tenancy["sector"]).to_upper()
					var ind_wage_bias: float = _roll_employer_wage_bias(rng)
					employer_wage_biases[est_id] = ind_wage_bias
					current_slot_id = expand_staffing_slots(
						available_job_slots, job_slot_inserts, current_slot_id, est_id, dist_id,
						ind_sector, ind_tenancy, job_definitions, ind_wage_bias, sim_start_day, reason_world_gen_id, rng
					)
					est_id += 1
					district_estab_counts[dist_id] = int(district_estab_counts[dist_id]) + 1

		# Sparse Clandestine Establishments (only when crime flavour overlay provides clandestine_tenants)
		if not clandestine_classes.is_empty() and rng.randf() < 0.25:
			var clan_pool: Array[Dictionary] = []
			for c_code in clandestine_classes.keys():
				var c_def: Dictionary = clandestine_classes[c_code]
				var c_spawns: Array = c_def.get("spawns_in_archetypes", [])
				if c_spawns.has(district_type) or c_spawns.is_empty():
					clan_pool.append({"code": c_code, "weight": int(c_def.get("weight", 8)), "data": c_def})
			if not clan_pool.is_empty():
				var total_cw := 0
				for ce in clan_pool:
					total_cw += int(ce["weight"])
				var cr: int = rng.randi() % maxi(1, total_cw)
				var cacc := 0
				var chosen_clan: Dictionary = clan_pool[0]
				for ce in clan_pool:
					cacc += int(ce["weight"])
					if cr < cacc:
						chosen_clan = ce
						break
				var clan_code: String = str(chosen_clan["code"])
				var clan_def: Dictionary = chosen_clan["data"]
				var clan_name_res: Dictionary = _generate_business_name(
					clan_code, clan_def, false, district_type,
					street_root, district_prefix, district_display, borough_name, sim_start_year,
					comm_naming, civic_naming_formats, cultural, lexicon, used_names_in_district, rng
				)
				var clan_title: String = str(clan_name_res["title"])
				used_names_in_district[clan_title] = true
				if clan_name_res.has("proprietor"):
					proprietor_hints[est_id] = clan_name_res["proprietor"]

				var clan_cap: int = int(clan_def.get("default_capacity", 6))
				var clan_cat_id: int = DB_MANAGER.get_label_id("ESTABLISHMENT_CATEGORY", clan_code)
				estab_inserts.append("""
					INSERT INTO establishments (
						establishment_id, district_id, building_index, unit_door_number,
						owner_org_id, name, category_id, capacity, is_vacant, valid_from, valid_to, change_reason_id
					) VALUES (%d, '%s', 0, 'CLANDESTINE', NULL, '%s', %d, %d, 0, %d, NULL, %d);
				""" % [est_id, dist_id, clan_title.replace("'", "''"), clan_cat_id, clan_cap, sim_start_day, reason_world_gen_id])

				_register_est_cat(by_cat, clan_code, est_id, dist_id, clan_cap)
				_register_est_cat(by_cat, "ILLICIT_CLANDESTINE", est_id, dist_id, clan_cap)

				var clan_sector: String = str(clan_def.get("sector", "ILLICIT_CLANDESTINE")).to_upper()
				var clan_bias: float = _roll_employer_wage_bias(rng)
				employer_wage_biases[est_id] = clan_bias
				current_slot_id = expand_staffing_slots(
					available_job_slots, job_slot_inserts, current_slot_id, est_id, dist_id,
					clan_sector, clan_def, job_definitions, clan_bias, sim_start_day, reason_world_gen_id, rng
				)
				est_id += 1
				district_estab_counts[dist_id] = int(district_estab_counts[dist_id]) + 1

		# Single-Entity District Canonical Establishment Guarantee (backed by building_classes)
		if int(district_estab_counts[dist_id]) == 0:
			var building_classes_ref: Dictionary = state["building_classes"]
			var fallback_cat: String = str(arch.get("establishment_category", district_type.to_upper())).strip_edges().to_upper()
			var fallback_class_def: Dictionary = _lookup_building_class(building_classes_ref, fallback_cat)
			var fallback_cap: int = int(fallback_class_def.get("default_capacity", 25))
			var fallback_cat_id: int = DB_MANAGER.get_label_id("ESTABLISHMENT_CATEGORY", fallback_cat)
			var fallback_title: String = _format_civic_anchor_title(
				str(fallback_class_def.get("display_name", arch.get("display_name", fallback_cat))),
				district_display, borough_name, street_root, civic_naming_formats, rng
			).replace("'", "''")
			var fallback_sector: String = str(fallback_class_def.get("sector", arch.get("sector_class", "CIVIC"))).to_upper()
			var fallback_owner: String = str(category_org_map.get(fallback_cat, default_civic_org_id if fallback_sector == "CIVIC" else ""))
			var fallback_owner_sql: String = "'%s'" % fallback_owner if not fallback_owner.is_empty() else "NULL"

			estab_inserts.append("""
				INSERT INTO establishments (
					establishment_id, district_id, building_index, unit_door_number,
					owner_org_id, name, category_id, capacity, is_vacant, valid_from, valid_to, change_reason_id
				) VALUES (%d, '%s', 0, 'MAIN', %s, '%s', %d, %d, 0, %d, NULL, %d);
			""" % [est_id, dist_id, fallback_owner_sql, fallback_title, fallback_cat_id, fallback_cap, sim_start_day, reason_world_gen_id])
			_register_est_cat(by_cat, fallback_cat, est_id, dist_id, fallback_cap)
			employer_wage_biases[est_id] = 0.0
			if not fallback_class_def.is_empty():
				_record_establishment_footprint(d, fallback_class_def, building_classes_ref)
				current_slot_id = expand_staffing_slots(
					available_job_slots, job_slot_inserts, current_slot_id, est_id, dist_id,
					fallback_sector, fallback_class_def, job_definitions, 0.0, sim_start_day, reason_world_gen_id, rng,
					fallback_owner
				)
			est_id += 1
			district_estab_counts[dist_id] = 1

		if block_idx > 0 and block_idx % batch_size == 0:
			DB_MANAGER.execute_batch(estab_inserts)
			if not job_slot_inserts.is_empty():
				DB_MANAGER.execute_batch(job_slot_inserts)
				job_slot_inserts.clear()
			estab_inserts.clear()
			if on_progress.is_valid():
				on_progress.call(float(block_idx), float(maxi(1, districts.size())), "Commercial & Industrial: %d / %d" % [block_idx, districts.size()])
				var loop = Engine.get_main_loop()
				if loop is SceneTree:
					await (loop as SceneTree).process_frame

		block_idx += 1

	if not estab_inserts.is_empty():
		DB_MANAGER.execute_batch(estab_inserts)
	if not job_slot_inserts.is_empty():
		DB_MANAGER.execute_batch(job_slot_inserts)

	state["est_id"] = est_id
	state["current_slot_id"] = current_slot_id

## Returns the canonical physical_state dictionary consumed by CitizenDemographicsHydrator and DunbarGraphWeaver
static func finalize_physical_state(state: Dictionary) -> Dictionary:
	SystemLogger.log_info("  ✓ Pass 2: Generated %d establishments, %d active households, %d vacant tied living units, and %d workplace positions." % [
		int(state["est_id"]) - 1,
		int(state["current_household_id"]) - 1,
		int(state["total_tied_units_count"]),
		(state["available_job_slots"] as Array).size()
	])
	return {
		"districts": state["districts"],
		"by_cat": state["by_cat"],
		"households": state["generated_households"],
		"district_residents_map": state["district_residents_map"],
		"available_job_slots": state["available_job_slots"],
		"available_tied_housing": state["available_tied_housing"],
		"proprietor_hints": state["proprietor_hints"],
		"employer_wage_biases": state["employer_wage_biases"],
		"org_pay_cadences": state["org_pay_cadences"]
	}

## Looks up a class definition across any tenant group dictionary in building_classes (and flavour overlays)
static func _lookup_building_class(building_classes: Dictionary, cat_name: String) -> Dictionary:
	var key: String = cat_name.strip_edges().to_upper()
	if building_classes.has(key) and building_classes[key] is Dictionary:
		return building_classes[key]
	for top_key in building_classes.keys():
		if str(top_key).begins_with("_") or str(top_key).begins_with("default_"):
			continue
		var group = building_classes[top_key]
		if group is Dictionary and group.has(key) and group[key] is Dictionary:
			return group[key]
	return {}

## Updates district built_sqm and vacant_sqm when an establishment with a specific footprint_sqm spawns
static func _record_establishment_footprint(d: Dictionary, class_def: Dictionary, building_classes: Dictionary) -> void:
	var area_sqm: float = float(d.get("area_sqm", 0.0))
	if area_sqm <= 0.0:
		return
	var fp: float = float(class_def.get("footprint_sqm", building_classes.get("default_footprint_sqm", 0.0)))
	if fp <= 0.0:
		return
	var cur_built: float = float(d.get("built_sqm", 0.0))
	var new_built: float = minf(area_sqm, cur_built + fp)
	d["built_sqm"] = new_built
	d["vacant_sqm"] = maxf(0.0, area_sqm - new_built)

static func _pick_unique_street(
	street_roots: Array,
	street_suffixes: Array,
	used_streets: Dictionary,
	rng: RandomNumberGenerator
) -> Dictionary:
	for _attempt in range(40):
		var root: String = str(street_roots[rng.randi() % street_roots.size()])
		var suf: String = str(street_suffixes[rng.randi() % street_suffixes.size()])
		var full: String = "%s %s" % [root, suf]
		if not used_streets.has(full):
			used_streets[full] = true
			return {"root": root, "suffix": suf, "full": full}

	var fallback_root: String = str(street_roots[rng.randi() % street_roots.size()])
	var fallback_suf: String = str(street_suffixes[rng.randi() % street_suffixes.size()])
	var idx: int = used_streets.size() + 1
	var qualified: String = "%s %s (%d)" % [fallback_root, fallback_suf, idx]
	used_streets[qualified] = true
	return {"root": fallback_root, "suffix": fallback_suf, "full": qualified}

static func _format_civic_anchor_title(
	base_trade_name: String,
	district_display: String,
	borough_name: String,
	street_root: String,
	civic_formats: Array,
	rng: RandomNumberGenerator
) -> String:
	if civic_formats.is_empty():
		return "%s %s" % [district_display, base_trade_name]
	var fmt: String = str(civic_formats[rng.randi() % civic_formats.size()])
	return fmt.replace("{district_name}", district_display).replace("{borough_name}", borough_name).replace("{street_root}", street_root).replace("{trade}", base_trade_name)

## Rolls an employer-level wage generosity bias [-1.0..+1.0] representing owner generosity & future-planning vs. greed
static func _roll_employer_wage_bias(rng: RandomNumberGenerator) -> float:
	# Triangular/normal-ish draw centered around 0.0 (midpoint rate)
	return clampf((rng.randf() + rng.randf() - 1.0), -1.0, 1.0)

## Computes an establishment's wage generosity bias directly from a proprietor/manager's OCEAN personality traits
static func compute_ocean_wage_bias(ocean_traits: Dictionary) -> float:
	var agreeableness: float = float(ocean_traits.get("agreeableness", 0.5))
	var conscientiousness: float = float(ocean_traits.get("conscientiousness", 0.5))
	var openness: float = float(ocean_traits.get("openness", 0.5))
	return clampf((0.45 * agreeableness) + (0.35 * conscientiousness) + (0.20 * openness) - 0.50, -1.0, 1.0)

## Resolves an era-appropriate brand, pub, civic/location-anchored, or family proprietor business title
static func _generate_business_name(
	cat_code: String,
	tenancy: Dictionary,
	is_industrial: bool,
	district_type: String,
	street_root: String,
	district_prefix: String,
	district_display: String,
	borough_name: String,
	calendar_year: int,
	comm_naming: Dictionary,
	civic_naming_formats: Array,
	cultural: Dictionary,
	lexicon: Dictionary,
	used_names: Dictionary,
	rng: RandomNumberGenerator
) -> Dictionary:
	var base_trade_name: String = str(tenancy.get("display_name", cat_code))
	var allow_proprietor: bool = bool(tenancy.get("use_proprietor_name", true))
	var forced_ethnicity: String = str(tenancy.get("proprietor_ethnicity", "")).strip_edges()

	# 1. Era-Windowed Corporate / High-Street Chains (keyed directly by building_classes code)
	var era_brands: Dictionary = comm_naming.get("era_brands", {})
	if era_brands.has(cat_code):
		var active_brands: Array[String] = []
		for entry in era_brands[cat_code]:
			if entry is Dictionary:
				var from_yr: int = int(entry.get("valid_from_year", 1900))
				var to_yr: int = int(entry.get("valid_to_year", 2100))
				if calendar_year >= from_yr and calendar_year <= to_yr:
					active_brands.append(str(entry["name"]))
		if not active_brands.is_empty():
			var raw_brand: String = active_brands[rng.randi() % active_brands.size()]
			var resolved_brand: String = raw_brand.replace("{street_root}", street_root).replace("{district_prefix}", district_prefix)
			if used_names.has(resolved_brand) and not raw_brand.contains("{"):
				resolved_brand = "%s (%s)" % [resolved_brand, street_root]
			return { "title": resolved_brand }

	# 2. Data-Driven Proper Venue Name Pools (keyed directly by building_classes code, e.g. LOCAL_PUB)
	var named_pools: Dictionary = comm_naming.get("named_pools", {})
	if named_pools.has(cat_code) and named_pools[cat_code] is Array:
		var pool_names: Array = named_pools[cat_code]
		if not pool_names.is_empty():
			var candidate_title: String = str(pool_names[rng.randi() % pool_names.size()])
			if used_names.has(candidate_title):
				candidate_title = "%s (%s)" % [candidate_title, street_root]
			return { "title": candidate_title }

	# 3. Non-Proprietor / Civic Establishments (Police, Clinics, Courts, Libraries, Depots)
	if not allow_proprietor:
		var civic_title: String = _format_civic_anchor_title(
			base_trade_name, district_display, borough_name, street_root, civic_naming_formats, rng
		)
		if used_names.has(civic_title):
			civic_title = "%s (%s)" % [civic_title, street_root]
		return { "title": civic_title }

	# 4. Industrial Formats
	if is_industrial:
		var ind_formats: Array = comm_naming.get("industrial_formats", [])
		assert(not ind_formats.is_empty(), "FATAL: [PremisesWorkplaceBuilder] Missing 'industrial_formats' in commercial_naming.")
		var fmt: String = str(ind_formats[rng.randi() % ind_formats.size()])
		var cult: Dictionary = _resolve_proprietor_culture(cultural, rng, district_type, forced_ethnicity)
		var pool_key: String = str(cult.get("surnames_pool", "surnames"))
		var surnames_arr: Array = lexicon.get(pool_key, lexicon.get("surnames", ["Smith"]))
		var surname: String = str(surnames_arr[rng.randi() % surnames_arr.size()])
		var title: String = fmt.replace("{surname}", surname).replace("{district_prefix}", district_prefix).replace("{street_root}", street_root).replace("{trade}", base_trade_name)
		var res: Dictionary = { "title": title }
		if fmt.contains("{surname}"):
			res["proprietor"] = {
				"surname": surname,
				"ethnicity": cult["ethnicity"],
				"religion": cult["religion"],
				"surnames_pool": pool_key
			}
		return res

	# 5. Independent Commercial Trades (Family Proprietor vs Street/District Location)
	var fam_prob: float = 1.0 if not forced_ethnicity.is_empty() else float(comm_naming.get("family_trade_probability", 0.65))
	if rng.randf() < fam_prob:
		var fam_formats: Array = comm_naming.get("family_formats", [])
		assert(not fam_formats.is_empty(), "FATAL: [PremisesWorkplaceBuilder] Missing 'family_formats' in commercial_naming.")
		var fmt: String = str(fam_formats[rng.randi() % fam_formats.size()])
		var cult: Dictionary = _resolve_proprietor_culture(cultural, rng, district_type, forced_ethnicity)
		var pool_key: String = str(cult.get("surnames_pool", "surnames"))
		var surnames_arr: Array = lexicon.get(pool_key, lexicon.get("surnames", ["Smith"]))
		var surname: String = str(surnames_arr[rng.randi() % surnames_arr.size()])
		var initial_char: String = char(65 + (rng.randi() % 26))
		var title: String = fmt.replace("{initial}", initial_char).replace("{surname}", surname).replace("{trade}", base_trade_name)
		if used_names.has(title):
			title = "%s (%s)" % [title, street_root]
		return {
			"title": title,
			"proprietor": {
				"surname": surname,
				"ethnicity": cult["ethnicity"],
				"religion": cult["religion"],
				"surnames_pool": pool_key
			}
		}
	else:
		var loc_formats: Array = comm_naming.get("location_formats", [])
		assert(not loc_formats.is_empty(), "FATAL: [PremisesWorkplaceBuilder] Missing 'location_formats' in commercial_naming.")
		var fmt: String = str(loc_formats[rng.randi() % loc_formats.size()])
		var title: String = fmt.replace("{street_root}", street_root).replace("{district_prefix}", district_prefix).replace("{trade}", base_trade_name)
		if used_names.has(title):
			title = "%s (%s)" % [title, street_root]
		return { "title": title }

static func _resolve_proprietor_culture(
	cultural: Dictionary,
	rng: RandomNumberGenerator,
	district_type: String,
	forced_ethnicity: String
) -> Dictionary:
	if forced_ethnicity.is_empty():
		return roll_household_culture(cultural, rng, district_type)
	var ethnicities: Dictionary = cultural.get("ethnicities", {})
	if not ethnicities.has(forced_ethnicity):
		return roll_household_culture(cultural, rng, district_type)
	var eth_profile: Dictionary = ethnicities[forced_ethnicity]
	var defaults: Dictionary = cultural.get("defaults", {})
	var rel_weights: Dictionary = eth_profile.get("religion_distribution", {})
	var chosen_rel: String = str(defaults.get("secular_or_unaffiliated_religion_key", "UNAFFILIATED"))
	var roll: float = rng.randf()
	var cumulative: float = 0.0
	for rel in rel_weights.keys():
		cumulative += float(rel_weights[rel])
		if roll <= cumulative:
			chosen_rel = str(rel)
			break
	return {
		"ethnicity": forced_ethnicity,
		"religion": chosen_rel,
		"surnames_pool": eth_profile.get("surnames_pool", "surnames")
	}

static func _extract_housing_profiles(arch: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not arch.has("housing_profile"):
		return result
	var hp = arch["housing_profile"]
	if hp is Array:
		for item in hp:
			if item is Dictionary:
				result.append(item)
	elif hp is Dictionary and not hp.is_empty():
		result.append(hp)
	return result

## Resolves standardized schedule, wage bracket, and unsocial/shift uplift for a role
static func resolve_standardized_compensation(
	master_job: Dictionary,
	job_definitions: Dictionary,
	employer_wage_bias: float,
	estab_multiplier: float = 1.0,
	estab_bonus: float = 0.0
) -> Dictionary:
	var work_schedules: Dictionary = job_definitions.get("work_schedules", {})
	var wage_brackets: Dictionary = job_definitions.get("wage_brackets", {})
	var shift_uplifts: Dictionary = job_definitions.get("shift_uplifts", {})
	var shift_rotations: Dictionary = job_definitions.get("shift_rotations", {})

	var sched_key: String = str(master_job.get("work_schedule", ""))
	assert(not sched_key.is_empty() and work_schedules.has(sched_key), "FATAL: [PremisesWorkplaceBuilder] Role missing valid 'work_schedule' key '%s'." % sched_key)
	var sched_def: Dictionary = work_schedules[sched_key]

	var bracket_key: String = str(master_job.get("wage_bracket", ""))
	assert(not bracket_key.is_empty() and wage_brackets.has(bracket_key), "FATAL: [PremisesWorkplaceBuilder] Role missing valid 'wage_bracket' key '%s'." % bracket_key)
	var bracket_def: Dictionary = wage_brackets[bracket_key]

	var schedule_window: String = str(sched_def.get("schedule_window", "DAYTIME"))
	var weekly_hours: float = float(sched_def.get("weekly_hours", 37.5))
	var pay_cadence: String = str(sched_def.get("pay_cadence", "WEEKLY"))
	var pay_basis: String = str(bracket_def.get("pay_basis", "HOURLY"))

	var min_rate: float = float(bracket_def.get("min_rate", 0.0))
	var mid_rate: float = float(bracket_def.get("midpoint_rate", 0.0))
	var max_rate: float = float(bracket_def.get("max_rate", 0.0))

	if pay_basis == "FLAT_STIPEND":
		return {
			"schedule_window": schedule_window,
			"weekly_hours": weekly_hours,
			"pay_cadence": pay_cadence,
			"pay_basis": pay_basis,
			"hourly_rate": 0.0
		}

	# Employer OCEAN bias modulates rate around bracket midpoint
	var base_rate: float = mid_rate
	if employer_wage_bias >= 0.0:
		base_rate = mid_rate + (employer_wage_bias * (max_rate - mid_rate))
	else:
		base_rate = mid_rate + (employer_wage_bias * (mid_rate - min_rate))

	# Unsocial hours & rotating shift uplift applies to HOURLY roles
	var uplift_pct: float = 0.0
	if pay_basis == "HOURLY":
		if schedule_window == "SHIFTS_ROTATING":
			var rot_key: String = str(sched_def.get("rotation_pattern", "THREE_SHIFT_STANDARD"))
			var rot_def: Dictionary = shift_rotations.get(rot_key, {})
			var splits: Dictionary = rot_def.get("shift_splits", {})
			for s_win in splits.keys():
				uplift_pct += float(splits[s_win]) * float(shift_uplifts.get(s_win, 0.0))
		else:
			uplift_pct = float(shift_uplifts.get(schedule_window, 0.0))

	var final_rate: float = snappedf(((base_rate * (1.0 + uplift_pct)) * estab_multiplier) + estab_bonus, 0.05)
	return {
		"schedule_window": schedule_window,
		"weekly_hours": weekly_hours,
		"pay_cadence": pay_cadence,
		"pay_basis": pay_basis,
		"hourly_rate": final_rate
	}

static func expand_staffing_slots(
	slots_array: Array[Dictionary],
	sql_inserts: Array[String],
	starting_slot_id: int,
	estab_id: int, 
	dist_id: String, 
	sector_category_code: String, 
	host_def: Dictionary, 
	job_definitions: Dictionary,
	employer_wage_bias: float,
	sim_start_day: int,
	reason_id: int,
	rng: RandomNumberGenerator,
	primary_org_id: String = "",
	hosted_sub_orgs: Array = [],
	roster_scale: float = 1.0
) -> int:
	var slot_id_counter: int = starting_slot_id
	var estab_multiplier: float = float(host_def.get("wage_multiplier", 1.0))
	var estab_bonus: float = float(host_def.get("wage_bonus", 0.0))

	# Sector Category lookup - fail loud if missing or invalid
	assert(not sector_category_code.is_empty(), "FATAL: Empty sector_category provided for establishment ID %d!" % estab_id)
	var sector_category_id: int = DB_MANAGER.get_label_id("SECTOR_CATEGORY", sector_category_code)

	# Extract canonical master roles dictionary
	var master_roles: Dictionary = job_definitions.get("roles", job_definitions)

	if host_def.has("staffing_roster"):
		for item in host_def["staffing_roster"]:
			var job_code: String = str(item.get("job_id", item.get("role_title", "")))
			assert(not job_code.is_empty(), "FATAL: Staffing roster entry missing 'job_id' or 'role_title' in establishment %d!" % estab_id)
			assert(master_roles.has(job_code), "FATAL: Undefined job role '%s' referenced in staffing roster for establishment %d!" % [job_code, estab_id])
			var master_job: Dictionary = master_roles[job_code]

			# Resolve contract_type: Roster item override > Building Class override > Job definition baseline
			var contract_type_code: String = ""
			if item.has("contract_type"):
				contract_type_code = str(item["contract_type"])
			elif host_def.has("contract_type"):
				contract_type_code = str(host_def["contract_type"])
			elif master_job.has("contract_type"):
				contract_type_code = str(master_job["contract_type"])
			else:
				assert(false, "FATAL: Job role '%s' (establishment %d) is missing mandatory 'contract_type' in roster item, building_classes, or job_definitions!" % [job_code, estab_id])

			var contract_type_id: int = DB_MANAGER.get_label_id("CONTRACT_TYPE", contract_type_code)

			var contract_class: String = str(item.get("contract_class", master_job.get("contract_class", "")))
			assert(not contract_class.is_empty(), "FATAL: Role '%s' missing mandatory 'contract_class'!" % job_code)
			var class_id: int = DB_MANAGER.get_label_id("CONTRACT_CLASS", contract_class)

			var edu_req: String = str(item.get("education_required", master_job.get("education_required", "")))
			assert(not edu_req.is_empty(), "FATAL: Role '%s' missing mandatory 'education_required'!" % job_code)
			var edu_id: int = DB_MANAGER.get_label_id("EDUCATION_LEVEL", edu_req)

			var role_multiplier: float = float(item.get("wage_multiplier", estab_multiplier))
			var role_bonus: float = float(item.get("wage_bonus", estab_bonus))
			var comp: Dictionary = resolve_standardized_compensation(master_job, job_definitions, employer_wage_bias, role_multiplier, role_bonus)

			var schedule_code: String = str(item.get("schedule_window", comp["schedule_window"]))
			var sched_id: int = DB_MANAGER.get_label_id("SCHEDULE_WINDOW", schedule_code)
			var hours: float = float(item.get("weekly_hours", comp["weekly_hours"]))
			var resolved_rate: float = float(item["hourly_rate"]) if item.has("hourly_rate") else float(comp["hourly_rate"])

			var is_field: bool = bool(item.get("is_field_worker", master_job.get("is_field_worker", false)))
			var tied_res: String = str(item.get("tied_accomodation", ""))
			var social_tier: String = str(master_job.get("social_tier", "STAFF"))
			var intel_clearance: float = float(master_job.get("intel_clearance", 0.3))

			var count_range: Array = item.get("target_count", [1, 1])
			var scaled_min: int = maxi(1, int(round(float(count_range[0]) * roster_scale)))
			var scaled_max: int = maxi(scaled_min, int(round(float(count_range[1]) * roster_scale)))
			var count: int = rng.randi_range(scaled_min, scaled_max)
			var role_id: int = DB_MANAGER.get_label_id("ROLE_TITLE", job_code)

			for slot_idx in range(count):
				var s_id: int = slot_id_counter
				slot_id_counter += 1
				var slot_org_id: String = primary_org_id
				if not hosted_sub_orgs.is_empty():
					slot_org_id = str(hosted_sub_orgs[slot_idx % hosted_sub_orgs.size()])

				slots_array.append({
					"slot_id": s_id,
					"estab_id": estab_id,
					"district_id": dist_id,
					"employer_org_id": slot_org_id,
					"sector_category_id": sector_category_id,
					"role_title": job_code,
					"role_title_id": role_id,
					"contract_class": contract_class,
					"contract_class_id": class_id,
					"contract_type_id": contract_type_id,
					"edu_req": edu_req,
					"min_education_level_id": edu_id,
					"schedule_window_id": sched_id,
					"pay_cadence": comp["pay_cadence"],
					"pay_basis": comp["pay_basis"],
					"social_tier": social_tier,
					"intel_clearance": intel_clearance,
					"rate": resolved_rate,
					"hours": hours,
					"is_field_worker": is_field,
					"tied_accomodation": tied_res
				})

				sql_inserts.append("""
					INSERT INTO workplace_job_slots (
						slot_id, establishment_id, sector_category_id, role_title_id,
						contract_class_id, contract_type_id, min_education_level_id, schedule_window_id,
						weekly_hours, hourly_rate, is_field_worker,
						is_filled, active_resident_id, valid_from, valid_to, change_reason_id
					) VALUES (
						%d, %d, %d, %d,
						%d, %d, %d, %d,
						%.1f, %.2f, %d,
						0, NULL, %d, NULL, %d
					);
				""" % [
					s_id, estab_id, sector_category_id, role_id,
					class_id, contract_type_id, edu_id, sched_id,
					hours, resolved_rate, 1 if is_field else 0,
					sim_start_day, reason_id
				])

	else:
		var emp_range: Array = host_def.get("employee_range", host_def.get("default_employees", [1, 3]))
		var count: int = rng.randi_range(int(emp_range[0]), int(emp_range[1]))
		var fallback_job: String = "MANUAL_WORKS" if sector_category_code == "INDUSTRIAL" else "COMMERCIAL_SERVICE"
		assert(master_roles.has(fallback_job), "FATAL: Standard fallback role '%s' missing in job_definitions!" % fallback_job)
		var master: Dictionary = master_roles[fallback_job]

		# Resolve contract_type: Building Class override > Fallback role baseline
		var contract_type_code: String = ""
		if host_def.has("contract_type"):
			contract_type_code = str(host_def["contract_type"])
		elif master.has("contract_type"):
			contract_type_code = str(master["contract_type"])
		else:
			assert(false, "FATAL: Fallback role '%s' missing mandatory 'contract_type' in building_classes or job_definitions!" % fallback_job)

		var contract_type_id: int = DB_MANAGER.get_label_id("CONTRACT_TYPE", contract_type_code)
		var contract_class: String = str(master.get("contract_class", "FORMAL_LEGAL"))
		var formal_class_id: int = DB_MANAGER.get_label_id("CONTRACT_CLASS", contract_class)
		var default_edu: String = str(master.get("education_required", "NO_FORMAL"))
		var fallback_edu_id: int = DB_MANAGER.get_label_id("EDUCATION_LEVEL", default_edu)
		var fallback_role_id: int = DB_MANAGER.get_label_id("ROLE_TITLE", fallback_job)

		var comp: Dictionary = resolve_standardized_compensation(master, job_definitions, employer_wage_bias, estab_multiplier, estab_bonus)
		var fallback_sched_id: int = DB_MANAGER.get_label_id("SCHEDULE_WINDOW", str(comp["schedule_window"]))
		var default_hours: float = float(comp["weekly_hours"])
		var rate: float = float(comp["hourly_rate"])
		var social_tier: String = str(master.get("social_tier", "STAFF"))
		var intel_clearance: float = float(master.get("intel_clearance", 0.3))

		for _i in range(count):
			var s_id: int = slot_id_counter
			slot_id_counter += 1

			slots_array.append({
				"slot_id": s_id,
				"estab_id": estab_id,
				"district_id": dist_id,
				"employer_org_id": primary_org_id,
				"sector_category_id": sector_category_id,
				"role_title": fallback_job,
				"role_title_id": fallback_role_id,
				"contract_class": contract_class,
				"contract_class_id": formal_class_id,
				"contract_type_id": contract_type_id,
				"edu_req": default_edu,
				"min_education_level_id": fallback_edu_id,
				"schedule_window_id": fallback_sched_id,
				"pay_cadence": comp["pay_cadence"],
				"pay_basis": comp["pay_basis"],
				"social_tier": social_tier,
				"intel_clearance": intel_clearance,
				"rate": rate,
				"hours": default_hours,
				"is_field_worker": false,
				"tied_accomodation": ""
			})

			sql_inserts.append("""
				INSERT INTO workplace_job_slots (
					slot_id, establishment_id, sector_category_id, role_title_id,
					contract_class_id, contract_type_id, min_education_level_id, schedule_window_id,
					weekly_hours, hourly_rate, is_field_worker,
					is_filled, active_resident_id, valid_from, valid_to, change_reason_id
				) VALUES (
					%d, %d, %d, %d,
					%d, %d, %d, %d,
					%.1f, %.2f, 0,
					0, NULL, %d, NULL, %d
				);
			""" % [
				s_id, estab_id, sector_category_id, fallback_role_id,
				formal_class_id, contract_type_id, fallback_edu_id, fallback_sched_id,
				default_hours, rate,
				sim_start_day, reason_id
			])

	return slot_id_counter

static func pick_tenancy(rng: RandomNumberGenerator, primary_classes: Dictionary, secondary_classes: Dictionary, district_type: String) -> Dictionary:
	var pool: Array[Dictionary] = []
	for code in primary_classes.keys():
		var item: Dictionary = primary_classes[code]
		var spawns: Array = item.get("spawns_in_archetypes", [])
		if spawns.has(district_type) or spawns.is_empty():
			pool.append({"code": code, "display_name": item.get("display_name", code), "weight": item.get("weight", 10), "data": item})

	for code in secondary_classes.keys():
		var item: Dictionary = secondary_classes[code]
		var spawns: Array = item.get("spawns_in_archetypes", [])
		if spawns.has(district_type) or spawns.is_empty():
			pool.append({"code": code, "display_name": item.get("display_name", code), "weight": item.get("weight", 5), "data": item})

	if pool.is_empty():
		return {"code": "COMMERCIAL", "display_name": "Local Retail Unit", "sector": "COMMERCIAL", "default_capacity": 10, "required_customer_threshold": 50, "customer_travel_distance_m": 500.0}

	var total_w := 0
	for entry in pool:
		total_w += int(entry["weight"])

	var r: int = rng.randi() % max(1, total_w)
	var acc := 0
	for entry in pool:
		acc += int(entry["weight"])
		if r < acc:
			var res: Dictionary = entry["data"].duplicate()
			res["code"] = entry["code"]
			return res

	return pool[0]["data"]

static func _register_est_cat(by_cat: Dictionary, cat_name: String, est_id: int, dist_id: String, capacity: int = 100) -> void:
	if not by_cat.has(cat_name):
		by_cat[cat_name] = []
	by_cat[cat_name].append({"id": est_id, "district_id": dist_id, "capacity": capacity})

static func roll_household_culture(cultural: Dictionary, rng: RandomNumberGenerator, district_type: String) -> Dictionary:
	var weights_key := "high_density" if district_type.begins_with("high_density") else ("commercial" if district_type == "commercial" else "suburban_low_density")
	var dist_weights: Dictionary = cultural["district_ethnic_weights"][weights_key]
	var defaults: Dictionary = cultural["defaults"]

	var chosen_eth: String = defaults["fallback_ethnicity"]
	var roll := rng.randf()
	var cumulative := 0.0
	for eth in dist_weights.keys():
		cumulative += float(dist_weights[eth])
		if roll <= cumulative:
			chosen_eth = eth
			break

	var eth_profile: Dictionary = cultural["ethnicities"][chosen_eth]
	var rel_weights: Dictionary = eth_profile["religion_distribution"]
	var chosen_rel: String = defaults["secular_or_unaffiliated_religion_key"]

	roll = rng.randf()
	cumulative = 0.0
	for rel in rel_weights.keys():
		cumulative += float(rel_weights[rel])
		if roll <= cumulative:
			chosen_rel = rel
			break

	return {
		"ethnicity": chosen_eth,
		"religion": chosen_rel,
		"surnames_pool": eth_profile.get("surnames_pool", "surnames")
	}