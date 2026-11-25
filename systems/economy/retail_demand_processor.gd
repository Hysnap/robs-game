# res://systems/economy/retail_demand_processor.gd
class_name RetailDemandProcessor
extends RefCounted

const FiscalCalculatorScript = preload("res://systems/economy/fiscal_calculator.gd")
const ScenarioManifestManagerScript = preload("res://systems/scenario_manifest_manager.gd")
const ImpactRouterScript = preload("res://systems/impacts/impact_router.gd")

static var _cached_demand_rules: Dictionary = {}

static func reset_cache() -> void:
	_cached_demand_rules.clear()

static func _get_demand_rules() -> Dictionary:
	if not _cached_demand_rules.is_empty():
		return _cached_demand_rules
	assert(ScenarioManifestManagerScript.has_module("demand_rules"),
		"FATAL: [RetailDemandProcessor] Active scenario manifest missing mandatory 'demand_rules' module.")
	_cached_demand_rules = ScenarioManifestManagerScript.load_module("demand_rules")
	assert(_cached_demand_rules.has("demand_drivers") and _cached_demand_rules.has("retail_fulfillment_parameters"),
		"FATAL: [RetailDemandProcessor] 'demand_rules' missing 'demand_drivers' or 'retail_fulfillment_parameters'.")
	return _cached_demand_rules

## Processes retail demand fulfillment, VAT/excise collection, stock depletion, and unfulfilled demand spillover
static func process_district_retail_cycle(
	world_state: Dictionary,
	district_id: String,
	days_elapsed: int,
	sim_year: int,
	active_events: Array[String] = []
) -> Dictionary:
	var districts: Dictionary = world_state.get("districts", {})
	if not districts.has(district_id) or not (districts[district_id] is Dictionary):
		return {}

	var dist: Dictionary = districts[district_id]
	var pop: int = maxi(0, int(dist.get("population", 0)))
	if pop <= 0 or days_elapsed <= 0:
		return {}

	var rules: Dictionary = _get_demand_rules()
	var drivers_cfg: Dictionary = rules["demand_drivers"]
	var params: Dictionary = rules["retail_fulfillment_parameters"]
	var ref_disp: float = maxf(0.01, float(params["reference_weekly_disposable_per_capita"]))
	var min_price_mult: float = float(params["min_price_demand_multiplier"])
	var max_price_mult: float = float(params["max_price_demand_multiplier"])
	var grey_tax_thresh: float = float(params["over_taxed_grey_spillover_threshold"])
	var desp_per_unit: float = float(params["need_shortfall_desperation_per_unit"])
	var zh_per_unit: float = float(params["need_shortfall_zone_health_per_unit"])

	var liq: Dictionary = dist.get("macro_liquidity", {})
	var remaining_budget: float = maxf(0.0, float(liq.get("retail_spending_capacity", 0.0)))
	var avg_weekly_disp: float = maxf(0.0, float(liq.get("avg_weekly_disposable", ref_disp)))
	var income_ratio: float = avg_weekly_disp / ref_disp

	var commodities: Dictionary = world_state.get("commodity_registry", {})
	var district_shops: Array[Dictionary] = _collect_district_retailers(world_state, district_id)

	var unfulfilled: Dictionary = {}
	var total_gross_sales: float = 0.0
	var total_vat_collected: float = 0.0
	var total_duty_collected: float = 0.0
	var total_units_sold: float = 0.0
	var total_unfulfilled_units: float = 0.0
	var total_desperation_shortfall_units: float = 0.0

	# Sort commodity IDs for deterministic execution order
	var item_ids: Array = commodities.keys()
	item_ids.sort()

	for raw_id in item_ids:
		var item_id: String = str(raw_id)
		var item_def = commodities[raw_id]
		if not (item_def is Dictionary):
			continue
		if not item_def.has("demand_profile") or not (item_def["demand_profile"] is Dictionary):
			continue

		var dp: Dictionary = item_def["demand_profile"]
		var driver: String = str(dp.get("primary_driver", "DEMAND_LED")).strip_edges().to_upper()
		if driver == "DERIVED_B2B":
			continue

		var legality: String = str(dp.get("legality", "LEGAL")).strip_edges().to_upper()
		var base_daily: float = maxf(0.0, float(dp.get("base_per_capita_daily", 0.0)))
		if base_daily <= 0.0:
			continue

		var base_cost: float = maxf(0.01, float(item_def.get("base_cost", 1.0)))
		var unit_tax_info: Dictionary = FiscalCalculatorScript.compute_vat_and_duty(
			base_cost,
			1.0,
			item_def,
			sim_year,
			{"contract_class": "FORMAL" if legality == "LEGAL" else "ILLICIT", "seller_vat_registered": true}
		)
		var gross_unit_price: float = maxf(0.01, float(unit_tax_info["gross_total"]))
		var unit_tax_total: float = float(unit_tax_info["vat_total"]) + float(unit_tax_info["excise_duty_total"])
		var effective_tax_burden: float = unit_tax_total / gross_unit_price

		# Income & Price Elasticity Scaling
		var inc_elast: float = float(dp.get("income_elasticity", 0.5))
		var price_elast: float = float(dp.get("price_elasticity", -0.5))
		var compulsion_floor: float = clampf(float(dp.get("compulsion_floor", 0.0)), 0.0, 1.0)

		var income_mult: float = clampf(pow(maxf(0.1, income_ratio), inc_elast), 0.25, 2.50)
		var price_ratio: float = gross_unit_price / base_cost
		var raw_price_mult: float = pow(maxf(0.1, price_ratio), price_elast)
		var price_mult: float = clampf(maxf(compulsion_floor, raw_price_mult), min_price_mult, max_price_mult)

		var event_mult: float = 1.0
		var ev_map: Dictionary = dp.get("event_multipliers", {})
		for ev_code in active_events:
			if ev_map.has(ev_code):
				event_mult *= float(ev_map[ev_code])

		var desired_units: float = snappedf(
			float(pop) * base_daily * float(days_elapsed) * income_mult * price_mult * event_mult,
			0.01
		)
		if desired_units <= 0.0:
			continue

		# Over-taxed grey/illicit spillover (consumers seeking untaxed alternatives when duty+VAT exceeds threshold)
		var grey_spillover_units: float = 0.0
		if legality == "LEGAL" and effective_tax_burden > grey_tax_thresh:
			var excess_tax: float = effective_tax_burden - grey_tax_thresh
			var fomo_sens: float = clampf(float(dp.get("fomo_sensitivity", 0.25)), 0.0, 1.0)
			var diversion_ratio: float = clampf(excess_tax * fomo_sens, 0.0, 0.50)
			grey_spillover_units = snappedf(desired_units * diversion_ratio, 0.01)
			desired_units = maxf(0.0, desired_units - grey_spillover_units)

		# Fulfill LEGAL demand from open district establishments up to available stock & retail budget
		var sold_units: float = 0.0
		if legality == "LEGAL" and remaining_budget >= gross_unit_price and not district_shops.is_empty():
			var affordable_units: float = floorf(remaining_budget / gross_unit_price)
			var target_buy_units: float = minf(desired_units, affordable_units)

			for shop in district_shops:
				if target_buy_units <= 0.0:
					break
				var inv: Dictionary = shop.get("inventory", {})
				var avail_stock: float = maxf(0.0, float(inv.get(item_id, 0.0)))
				if avail_stock <= 0.0:
					continue

				var bought: float = minf(target_buy_units, avail_stock)
				var sale_tax: Dictionary = FiscalCalculatorScript.compute_vat_and_duty(
					base_cost,
					bought,
					item_def,
					sim_year,
					{"contract_class": "FORMAL", "seller_vat_registered": true}
				)
				var sale_gross: float = float(sale_tax["gross_total"])
				if sale_gross > remaining_budget:
					bought = floorf(remaining_budget / gross_unit_price)
					if bought <= 0.0:
						break
					sale_tax = FiscalCalculatorScript.compute_vat_and_duty(
						base_cost,
						bought,
						item_def,
						sim_year,
						{"contract_class": "FORMAL", "seller_vat_registered": true}
					)
					sale_gross = float(sale_tax["gross_total"])

				inv[item_id] = snappedf(avail_stock - bought, 0.01)
				inv["CASH"] = snappedf(float(inv.get("CASH", 0.0)) + sale_gross, 0.01)
				shop["inventory"] = inv

				remaining_budget = maxf(0.0, remaining_budget - sale_gross)
				sold_units += bought
				target_buy_units -= bought
				total_gross_sales += sale_gross
				total_vat_collected += float(sale_tax["vat_total"])
				total_duty_collected += float(sale_tax["excise_duty_total"])

		var unmet_units: float = snappedf(maxf(0.0, (desired_units - sold_units) + grey_spillover_units), 0.01)
		total_units_sold += sold_units

		if unmet_units > 0.0:
			unfulfilled[item_id] = {
				"unmet_units": unmet_units,
				"grey_spillover_units": grey_spillover_units,
				"primary_driver": driver,
				"substitution_group": str(dp.get("substitution_group", "")),
				"legality": legality
			}
			total_unfulfilled_units += unmet_units
			var driver_meta: Dictionary = drivers_cfg.get(driver, {})
			if bool(driver_meta.get("generates_unmet_desperation", false)):
				total_desperation_shortfall_units += (desired_units - sold_units)

	dist["unfulfilled_demand"] = unfulfilled
	if liq is Dictionary and not liq.is_empty():
		liq["retail_spending_remaining"] = snappedf(remaining_budget, 0.01)
		liq["retail_gross_sales"] = snappedf(total_gross_sales, 0.01)
		liq["vat_collected"] = snappedf(total_vat_collected, 0.01)
		liq["excise_duty_collected"] = snappedf(total_duty_collected, 0.01)
		dist["macro_liquidity"] = liq

	# Dispatch ambient social stress impulses when essential NEED_LED / HABIT_LED goods suffer shortfalls
	if total_desperation_shortfall_units > 0.0:
		if ImpactRouterScript.has_sink("CONSUMER_DESPERATION"):
			ImpactRouterScript.dispatch_delta(
				world_state,
				district_id,
				"CONSUMER_DESPERATION",
				total_desperation_shortfall_units * desp_per_unit
			)
		if ImpactRouterScript.has_sink("ZONE_HEALTH"):
			ImpactRouterScript.dispatch_delta(
				world_state,
				district_id,
				"ZONE_HEALTH",
				total_desperation_shortfall_units * zh_per_unit
			)

	return {
		"district_id": district_id,
		"gross_sales": snappedf(total_gross_sales, 0.01),
		"vat_collected": snappedf(total_vat_collected, 0.01),
		"excise_duty_collected": snappedf(total_duty_collected, 0.01),
		"units_sold": snappedf(total_units_sold, 0.01),
		"unfulfilled_units": snappedf(total_unfulfilled_units, 0.01)
	}

static func _collect_district_retailers(world_state: Dictionary, district_id: String) -> Array[Dictionary]:
	var shops: Array[Dictionary] = []
	var estabs: Dictionary = world_state.get("establishments", {})
	var est_keys: Array = estabs.keys()
	est_keys.sort()
	for k in est_keys:
		var est = estabs[k]
		if not (est is Dictionary):
			continue
		if str(est.get("district_id", "")) != district_id:
			continue
		if bool(est.get("is_closed", false)):
			continue
		if est.has("inventory") and est["inventory"] is Dictionary:
			shops.append(est)
	return shops