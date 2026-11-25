# res://tests/test_retail_demand_fulfillment.gd
extends SceneTree

const CatalogValidatorScript = preload("res://systems/catalog_validator.gd")
const FiscalCalculatorScript = preload("res://systems/economy/fiscal_calculator.gd")
const RetailDemandProcessorScript = preload("res://systems/economy/retail_demand_processor.gd")
const SimControllerScript = preload("res://systems/sim_controller.gd")
const DBManagerScript = preload("res://systems/db_manager.gd")
const TestSocietyFactoryScript = preload("res://tests/test_society_factory.gd")

var _frame_count: int = 0
var _started: bool = false

func _process(_delta: float) -> bool:
	if _started:
		return false
	_frame_count += 1
	if _frame_count < 2:
		return false
	_started = true
	_run_tests_async()
	return false

func _run_tests_async() -> void:
	print("--- [Test] Starting Path B Retail Demand, VAT/Duty & Spillover Suite (TestSocietyFactory) ---")
	FiscalCalculatorScript.reset_cache()
	RetailDemandProcessorScript.reset_cache()

	var ws: Dictionary = await TestSocietyFactoryScript.create_test_world_with_crew(4, 4, "retail-demand-radial-seed", "week")
	var total_districts: int = ws.get("districts", {}).size()
	assert(total_districts >= 10, "Expected concentric radial society from TestSocietyFactory, got %d districts." % total_districts)

	_test_catalog_validator_config_driven_rules(ws)
	_test_radial_retail_fulfillment_vat_and_duty(ws)
	_test_stockout_and_overtaxed_grey_spillover(ws)

	if DBManagerScript.is_database_open():
		DBManagerScript.close_database()

	print("--- [Test] ALL PATH B RETAIL DEMAND & VAT/DUTY FULFILLMENT TESTS PASSED ---")
	quit(0)

func _test_catalog_validator_config_driven_rules(ws: Dictionary) -> void:
	var clean_report: Dictionary = CatalogValidatorScript.validate_catalogs(ws, false)
	assert(bool(clean_report.get("is_clean", false)),
		"Expected live commodity catalog to pass config-driven validation, errors: %s" % str(clean_report.get("errors", [])))

	# Inject a malformed commodity to verify fail-loud rejection against demand_rules & fiscal_regimes
	var bad_ws: Dictionary = {
		"commodity_registry": {
			"INVALID_DRIVER_ITEM": {
				"category": "CONSUMABLE",
				"base_cost": 2.0,
				"tax_class": "FAKE_TAX_CLASS",
				"demand_profile": {
					"primary_driver": "BOGUS_DRIVER",
					"legality": "LEGAL"
				}
			}
		},
		"recipe_registry": {}
	}
	var bad_report: Dictionary = CatalogValidatorScript.validate_catalogs(bad_ws, false)
	assert(not bool(bad_report.get("is_clean", true)),
		"CatalogValidator must fail loud on invalid tax_class and demand_profile.primary_driver.")
	assert(bad_report.get("errors", []).size() >= 2,
		"Expected at least 2 validation errors for invalid tax_class and primary_driver.")

	print("  PASS [1/3]: Config-driven CatalogValidator (demand_rules + fiscal_regimes) verified.")

func _test_radial_retail_fulfillment_vat_and_duty(ws: Dictionary) -> void:
	var target_district_id: String = _find_populated_district_id(ws)
	assert(not target_district_id.is_empty(), "Expected at least one populated district in radial city.")

	var commodities: Dictionary = ws.get("commodity_registry", {})
	var food_id: String = _find_commodity_by_predicate(commodities, func(def: Dictionary) -> bool:
		return str(def.get("tax_class", "")).to_upper() == "ZERO_RATED" and str(def.get("demand_profile", {}).get("primary_driver", "")).to_upper() == "NEED_LED"
	)
	var excised_id: String = _find_commodity_by_predicate(commodities, func(def: Dictionary) -> bool:
		return str(def.get("tax_class", "")).to_upper() == "STANDARD" and str(def.get("duty_class", "NONE")).to_upper() != "NONE"
	)
	assert(not food_id.is_empty(), "Expected at least one ZERO_RATED NEED_LED food commodity in catalog.")
	assert(not excised_id.is_empty(), "Expected at least one STANDARD VAT + excise duty commodity in catalog.")

	if not ws.has("establishments") or not (ws["establishments"] is Dictionary):
		ws["establishments"] = {}

	var initial_food_stock: float = 500.0
	var initial_excised_stock: float = 500.0
	ws["establishments"]["TEST_CORNER_SHOP_01"] = {
		"establishment_id": "TEST_CORNER_SHOP_01",
		"district_id": target_district_id,
		"is_closed": false,
		"inventory": {
			"CASH": 0.0,
			food_id: initial_food_stock,
			excised_id: initial_excised_stock
		}
	}

	var turn_res: Dictionary = SimControllerScript.process_turn_cycle(ws, [])
	assert(bool(turn_res.get("week_rollover", false)), "Expected week_rollover == true after 7-day step.")

	var econ: Dictionary = turn_res.get("economy_rollover", {})
	var gross_sales: float = float(econ.get("retail_gross_sales", 0.0))
	var vat_collected: float = float(econ.get("vat_collected", 0.0))
	var duty_collected: float = float(econ.get("excise_duty_collected", 0.0))

	assert(gross_sales > 0.0, "Expected positive retail_gross_sales on weekly rollover, got %.2f." % gross_sales)
	assert(vat_collected > 0.0, "Expected positive vat_collected on excised standard-rated sales, got %.2f." % vat_collected)
	assert(duty_collected > 0.0, "Expected positive excise_duty_collected on excised alcohol/tobacco sales, got %.2f." % duty_collected)

	var shop_inv: Dictionary = ws["establishments"]["TEST_CORNER_SHOP_01"]["inventory"]
	var food_after: float = float(shop_inv.get(food_id, 0.0))
	var excised_after: float = float(shop_inv.get(excised_id, 0.0))
	var shop_cash_after: float = float(shop_inv.get("CASH", 0.0))

	assert(food_after < initial_food_stock, "Expected food stock '%s' to deplete (%.2f -> %.2f)." % [food_id, initial_food_stock, food_after])
	assert(excised_after < initial_excised_stock, "Expected excised stock '%s' to deplete (%.2f -> %.2f)." % [excised_id, initial_excised_stock, excised_after])
	assert(shop_cash_after > 0.0, "Expected establishment CASH to increase from retail sales, got %.2f." % shop_cash_after)

	var dist_liq: Dictionary = ws["districts"][target_district_id].get("macro_liquidity", {})
	assert(float(dist_liq.get("retail_gross_sales", 0.0)) > 0.0, "Expected district macro_liquidity.retail_gross_sales > 0.")
	assert(float(dist_liq.get("vat_collected", 0.0)) > 0.0, "Expected district macro_liquidity.vat_collected > 0.")
	assert(float(dist_liq.get("excise_duty_collected", 0.0)) > 0.0, "Expected district macro_liquidity.excise_duty_collected > 0.")

	print("  PASS [2/3]: Radial retail fulfillment verified (sales=£%.2f, VAT=£%.2f, duty=£%.2f, shop CASH=£%.2f)." % [
		gross_sales, vat_collected, duty_collected, shop_cash_after
	])

func _test_stockout_and_overtaxed_grey_spillover(ws: Dictionary) -> void:
	var target_district_id: String = _find_populated_district_id(ws)
	var dist: Dictionary = ws["districts"][target_district_id]
	var unfulfilled: Dictionary = dist.get("unfulfilled_demand", {})
	assert(not unfulfilled.is_empty(),
		"Expected unfulfilled_demand entries in district '%s' for unstocked or over-taxed commodities." % target_district_id)

	var found_grey_spillover: bool = false
	for item_id in unfulfilled.keys():
		var entry: Dictionary = unfulfilled[item_id]
		if float(entry.get("grey_spillover_units", 0.0)) > 0.0:
			found_grey_spillover = true
			break

	assert(found_grey_spillover,
		"Expected at least one heavily taxed excise commodity to generate grey_spillover_units > 0.0.")

	print("  PASS [3/3]: Stockout unfulfilled_demand (%d items) and over-taxed grey spillover verified." % unfulfilled.size())

static func _find_populated_district_id(ws: Dictionary) -> String:
	var districts: Dictionary = ws.get("districts", {})
	var keys: Array = districts.keys()
	keys.sort()
	for raw_k in keys:
		var d = districts[raw_k]
		if d is Dictionary and int(d.get("population", 0)) > 0:
			return str(raw_k)
	return ""

static func _find_commodity_by_predicate(commodities: Dictionary, predicate: Callable) -> String:
	var keys: Array = commodities.keys()
	keys.sort()
	for raw_k in keys:
		var item = commodities[raw_k]
		if item is Dictionary and predicate.call(item):
			return str(raw_k)
	return ""