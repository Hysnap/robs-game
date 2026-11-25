# res://systems/economy/fiscal_calculator.gd
class_name FiscalCalculator
extends RefCounted

const ScenarioManifestManagerScript = preload("res://systems/scenario_manifest_manager.gd")

static var _merged_regimes_cache: Dictionary = {}

## Clears cached regime lookups (for test isolation or manifest reload)
static func reset_cache() -> void:
	_merged_regimes_cache.clear()

## Resolves and deep-merges the active fiscal regime for sim_year over 'defaults'
static func get_active_regime(sim_year: int) -> Dictionary:
	if _merged_regimes_cache.has(sim_year):
		return _merged_regimes_cache[sim_year]

	assert(ScenarioManifestManagerScript.has_module("fiscal_regimes"),
		"FATAL: [FiscalCalculator] 'fiscal_regimes' module not registered in active society manifest.")
	var raw_module: Dictionary = ScenarioManifestManagerScript.load_module("fiscal_regimes")
	var defaults: Dictionary = raw_module.get("defaults", {})
	var regimes: Array = raw_module.get("regimes", [])
	assert(not regimes.is_empty(), "FATAL: [FiscalCalculator] 'fiscal_regimes' module contains no regimes.")

	var matched: Dictionary = {}
	for entry in regimes:
		if not (entry is Dictionary):
			continue
		var from_yr: int = int(entry.get("valid_from_year", -9999))
		var to_yr: int = int(entry.get("valid_to_year", 9999))
		if sim_year >= from_yr and sim_year <= to_yr:
			matched = entry
			break

	assert(not matched.is_empty(),
		"FATAL: [FiscalCalculator] No fiscal regime configured for year %d." % sim_year)

	var merged: Dictionary = _deep_merge_dicts(defaults, matched)
	_merged_regimes_cache[sim_year] = merged
	return merged

## Computes weekly gross-to-net payroll, PAYE income tax, and Employee/Employer National Insurance
static func compute_net_pay(
	base_weekly_gross: float,
	sim_year: int,
	options: Dictionary = {}
) -> Dictionary:
	var regime: Dictionary = get_active_regime(sim_year)
	var apply_index: bool = bool(options.get("apply_wage_index", true))
	var wage_mult: float = float(regime.get("wage_index_multiplier", 1.0)) if apply_index else 1.0
	var gross_weekly: float = maxf(0.0, base_weekly_gross * wage_mult)

	var contract_class: String = str(options.get("contract_class", "FORMAL")).strip_edges().to_upper()
	if contract_class == "INFORMAL_GREY" or contract_class == "ILLICIT" or gross_weekly <= 0.0:
		return {
			"regime_id": str(regime.get("regime_id", "")),
			"gross_weekly": _round_currency(gross_weekly),
			"paye_tax_weekly": 0.0,
			"ni_employee_weekly": 0.0,
			"ni_employer_weekly": 0.0,
			"pension_employee_weekly": 0.0,
			"net_weekly": _round_currency(gross_weekly)
		}

	var paye_cfg: Dictionary = regime.get("paye_income_tax", {})
	var weeks_per_yr: float = maxf(1.0, float(paye_cfg.get("pay_period_weeks_per_year", 52.0)))
	var personal_allow: float = float(paye_cfg.get("personal_allowance_annual", 0.0))
	if bool(options.get("is_married_allowance_eligible", false)):
		personal_allow += float(paye_cfg.get("married_couple_allowance_annual", 0.0))

	var pension_rate: float = clampf(float(options.get("occupational_pension_rate", 0.0)), 0.0, 0.5)
	var pension_weekly: float = gross_weekly * pension_rate

	var annual_taxable: float = maxf(0.0, ((gross_weekly - pension_weekly) * weeks_per_yr) - personal_allow)
	var annual_tax: float = 0.0
	var prev_ceiling: float = 0.0
	for band in paye_cfg.get("bands", []):
		if not (band is Dictionary):
			continue
		var rate: float = float(band.get("rate", 0.0))
		var ceiling: float = float(band.get("up_to_taxable_annual", -1.0))
		if ceiling < 0.0:
			annual_tax += maxf(0.0, annual_taxable - prev_ceiling) * rate
			break
		if annual_taxable > prev_ceiling:
			var slice: float = minf(annual_taxable, ceiling) - prev_ceiling
			annual_tax += maxf(0.0, slice) * rate
			prev_ceiling = ceiling
		else:
			break
	var paye_weekly: float = annual_tax / weeks_per_yr

	var ni_cfg: Dictionary = regime.get("national_insurance", {})
	var lel: float = float(ni_cfg.get("lower_earnings_limit_weekly", 0.0))
	var uel: float = float(ni_cfg.get("upper_earnings_limit_weekly", 0.0))
	var emp_rate: float = float(ni_cfg.get("employee_rate", 0.0))
	var er_rate: float = float(ni_cfg.get("employer_rate", 0.0))
	if bool(options.get("is_contracted_out_pension", false)):
		emp_rate = maxf(0.0, emp_rate - float(ni_cfg.get("contracted_out_rebate", 0.0)))

	var ni_employee_weekly: float = 0.0
	var ni_employer_weekly: float = 0.0
	if gross_weekly >= lel:
		var ni_band_earnings: float = maxf(0.0, minf(gross_weekly, uel) - lel) if uel > lel else maxf(0.0, gross_weekly - lel)
		ni_employee_weekly = ni_band_earnings * emp_rate
		ni_employer_weekly = maxf(0.0, gross_weekly - lel) * er_rate

	var net_weekly: float = maxf(0.0, gross_weekly - paye_weekly - ni_employee_weekly - pension_weekly)
	return {
		"regime_id": str(regime.get("regime_id", "")),
		"gross_weekly": _round_currency(gross_weekly),
		"paye_tax_weekly": _round_currency(paye_weekly),
		"ni_employee_weekly": _round_currency(ni_employee_weekly),
		"ni_employer_weekly": _round_currency(ni_employer_weekly),
		"pension_employee_weekly": _round_currency(pension_weekly),
		"net_weekly": _round_currency(net_weekly)
	}

## Computes weekly household statutory benefits, state pension, child benefit, and means-tested support
static func compute_household_benefits(household_ctx: Dictionary, sim_year: int) -> Dictionary:
	var regime: Dictionary = get_active_regime(sim_year)
	var pension_cfg: Dictionary = regime.get("state_pension", {})
	var welfare_cfg: Dictionary = regime.get("welfare_benefits", {})

	var age_m: int = int(pension_cfg.get("pension_age_male", 65))
	var age_f: int = int(pension_cfg.get("pension_age_female", 60))
	var members: Array = household_ctx.get("members", [])

	var pensioner_count: int = 0
	var unemployed_claimants: int = 0
	var disabled_claimants: int = 0
	for m in members:
		if not (m is Dictionary):
			continue
		var age: int = int(m.get("age", 0))
		var sex: String = str(m.get("sex", "M")).strip_edges().to_upper()
		var req_age: int = age_f if sex == "F" else age_m
		if age >= req_age:
			pensioner_count += 1
		elif bool(m.get("is_unemployed_signed_on", false)):
			unemployed_claimants += 1
		if bool(m.get("is_disabled_eligible", false)):
			disabled_claimants += 1

	var state_pension_weekly: float = 0.0
	if pensioner_count == 1:
		state_pension_weekly = float(pension_cfg.get("single_weekly_rate", 0.0))
	elif pensioner_count >= 2:
		state_pension_weekly = float(pension_cfg.get("couple_weekly_rate", 0.0)) + float(pensioner_count - 2) * float(pension_cfg.get("single_weekly_rate", 0.0))

	var dependent_children: int = maxi(0, int(household_ctx.get("dependent_children", 0)))
	var child_benefit_weekly: float = float(dependent_children) * float(welfare_cfg.get("child_benefit_per_child_weekly", 0.0))

	var unemployment_weekly: float = float(unemployed_claimants) * float(welfare_cfg.get("unemployment_benefit_flat_weekly", 0.0))
	var disability_weekly: float = float(disabled_claimants) * (float(welfare_cfg.get("unemployment_benefit_flat_weekly", 0.0)) * 0.85)

	var typology: String = str(household_ctx.get("household_typology", "SINGLE_PERSON")).strip_edges().to_upper()
	var app_map: Dictionary = welfare_cfg.get("applicable_amounts_weekly", {})
	var applicable_amount: float = float(app_map.get(typology, app_map.get("SINGLE_PERSON", 0.0)))
	applicable_amount += float(dependent_children) * float(welfare_cfg.get("dependent_child_addition_weekly", 0.0))
	if typology == "LONE_PARENT" and dependent_children > 0:
		applicable_amount += float(welfare_cfg.get("lone_parent_premium_weekly", 0.0))

	var net_earned_weekly: float = maxf(0.0, float(household_ctx.get("net_earned_weekly", 0.0)))
	var disregard: float = float(welfare_cfg.get("earnings_disregard_weekly", 0.0))
	var countable_earnings: float = maxf(0.0, net_earned_weekly - disregard)
	var other_countable_benefits: float = state_pension_weekly + unemployment_weekly
	var total_countable: float = countable_earnings + other_countable_benefits

	var taper: float = float(welfare_cfg.get("taper_rate", 1.0))
	var means_tested_weekly: float = 0.0
	if pensioner_count == 0 and total_countable < applicable_amount:
		means_tested_weekly = maxf(0.0, (applicable_amount - other_countable_benefits) - (countable_earnings * taper))

	var total_weekly: float = state_pension_weekly + child_benefit_weekly + unemployment_weekly + disability_weekly + means_tested_weekly
	return {
		"regime_id": str(regime.get("regime_id", "")),
		"state_pension_weekly": _round_currency(state_pension_weekly),
		"child_benefit_weekly": _round_currency(child_benefit_weekly),
		"unemployment_benefit_weekly": _round_currency(unemployment_weekly),
		"disability_support_weekly": _round_currency(disability_weekly),
		"means_tested_support_weekly": _round_currency(means_tested_weekly),
		"total_benefits_weekly": _round_currency(total_weekly),
		"default_rail_code": str(welfare_cfg.get("default_rail_code", "BEARER_VOUCHER"))
	}

## Computes weekly housing rent/mortgage, local property tax, and Housing Benefit relief
static func compute_housing_and_local_tax(housing_ctx: Dictionary, sim_year: int) -> Dictionary:
	var regime: Dictionary = get_active_regime(sim_year)
	var h_cfg: Dictionary = regime.get("housing_and_local_tax", {})
	var tenure: String = str(housing_ctx.get("tenure_type", "SOCIAL_COUNCIL")).strip_edges().to_upper()
	var district_mult: float = maxf(0.4, float(housing_ctx.get("district_wealth_multiplier", 1.0)))

	var gross_rent_or_mortgage: float = 0.0
	match tenure:
		"SOCIAL_COUNCIL":
			gross_rent_or_mortgage = float(h_cfg.get("council_rent_weekly_base", 0.0)) * lerpf(0.85, 1.15, clampf(district_mult - 0.5, 0.0, 1.0))
		"PRIVATE_RENT":
			gross_rent_or_mortgage = float(h_cfg.get("private_rent_weekly_base", 0.0)) * district_mult
		"MORTGAGED":
			var principal: float = maxf(0.0, float(housing_ctx.get("mortgage_principal", 12000.0 * float(regime.get("price_index_multiplier", 1.0)))))
			var annual_rate: float = float(h_cfg.get("mortgage_base_interest_rate_annual", 0.10))
			gross_rent_or_mortgage = (principal * annual_rate) / 52.0
		_:
			gross_rent_or_mortgage = 0.0

	var local_tax_weekly: float = float(h_cfg.get("domestic_rates_weekly_base", 0.0)) * lerpf(0.75, 1.50, clampf(district_mult - 0.5, 0.0, 1.0))
	var is_on_means_tested: bool = bool(housing_ctx.get("receives_means_tested_support", false))
	var excess_income: float = maxf(0.0, float(housing_ctx.get("excess_weekly_income", 0.0)))
	var taper: float = float(h_cfg.get("housing_benefit_income_taper", 0.65))

	var eligible_rent: float = 0.0
	if tenure == "SOCIAL_COUNCIL":
		eligible_rent = gross_rent_or_mortgage * float(h_cfg.get("housing_benefit_social_coverage_ratio", 1.0))
	elif tenure == "PRIVATE_RENT":
		eligible_rent = gross_rent_or_mortgage * float(h_cfg.get("housing_benefit_private_cap_ratio", 0.80))

	var housing_benefit: float = 0.0
	var local_tax_rebate: float = 0.0
	if eligible_rent > 0.0:
		if is_on_means_tested:
			housing_benefit = eligible_rent
			local_tax_rebate = local_tax_weekly * 0.85
		else:
			housing_benefit = maxf(0.0, eligible_rent - (excess_income * taper))
			local_tax_rebate = maxf(0.0, (local_tax_weekly * 0.85) - (excess_income * 0.20))

	var direct_to_landlord: float = 0.0
	if tenure == "SOCIAL_COUNCIL" and bool(h_cfg.get("direct_to_landlord_social_housing", true)):
		direct_to_landlord = housing_benefit

	var net_tenant_housing_outflow: float = maxf(0.0, (gross_rent_or_mortgage - housing_benefit) + (local_tax_weekly - local_tax_rebate))
	return {
		"regime_id": str(regime.get("regime_id", "")),
		"local_tax_mode": str(h_cfg.get("local_tax_mode", "DOMESTIC_RATES")),
		"gross_rent_or_mortgage_weekly": _round_currency(gross_rent_or_mortgage),
		"local_tax_weekly": _round_currency(local_tax_weekly),
		"housing_benefit_weekly": _round_currency(housing_benefit),
		"local_tax_rebate_weekly": _round_currency(local_tax_rebate),
		"direct_to_landlord_weekly": _round_currency(direct_to_landlord),
		"net_tenant_cash_outflow_weekly": _round_currency(net_tenant_housing_outflow)
	}

## Computes Excise Duty + VAT on a commodity transaction (bypassing both for INFORMAL_GREY / ILLICIT channels)
static func compute_vat_and_duty(
	base_unit_price: float,
	quantity: float,
	item_profile: Dictionary,
	sim_year: int,
	options: Dictionary = {}
) -> Dictionary:
	var regime: Dictionary = get_active_regime(sim_year)
	var qty: float = maxf(0.0, quantity)
	var price_mult: float = float(regime.get("price_index_multiplier", 1.0)) if bool(options.get("apply_price_index", false)) else 1.0
	var net_base_total: float = maxf(0.0, base_unit_price * price_mult * qty)

	var contract_class: String = str(options.get("contract_class", "FORMAL")).strip_edges().to_upper()
	var seller_vat_registered: bool = bool(options.get("seller_vat_registered", true))
	if contract_class == "INFORMAL_GREY" or contract_class == "ILLICIT" or qty <= 0.0:
		return {
			"regime_id": str(regime.get("regime_id", "")),
			"net_base_total": _round_currency(net_base_total),
			"excise_duty_total": 0.0,
			"vat_total": 0.0,
			"gross_total": _round_currency(net_base_total)
		}

	var duty_class: String = str(item_profile.get("duty_class", "NONE")).strip_edges().to_upper()
	var duties_cfg: Dictionary = regime.get("excise_duties", {})
	var duty_total: float = 0.0
	if duty_class != "NONE" and duties_cfg.has(duty_class):
		var d_def: Dictionary = duties_cfg[duty_class]
		var mode: String = str(d_def.get("calc_mode", "PER_UNIT_VOLUME")).to_upper()
		var unit_vol: float = float(item_profile.get("unit_volume_litres", item_profile.get("unit_volume", 1.0)))
		var abv: float = float(item_profile.get("abv", 0.0))
		match mode:
			"PER_LITRE_PURE_ALCOHOL":
				duty_total = qty * unit_vol * abv * float(d_def.get("rate", 0.0))
			"SPECIFIC_PLUS_AD_VALOREM":
				var units_per_pack: float = float(item_profile.get("units_per_pack", 20.0))
				var spec: float = qty * units_per_pack * float(d_def.get("specific_per_unit", 0.0))
				var ad_val: float = net_base_total * float(d_def.get("ad_valorem_rate", 0.0))
				duty_total = spec + ad_val
			_:
				duty_total = qty * unit_vol * float(d_def.get("rate", 0.0))

	var tax_class: String = str(item_profile.get("tax_class", "STANDARD")).strip_edges().to_upper()
	var vat_rates: Dictionary = regime.get("vat", {}).get("rates", {})
	var vat_rate: float = float(vat_rates.get(tax_class, 0.0)) if seller_vat_registered else 0.0
	# HMRC rule: VAT is levied on net price + excise duty
	var vat_total: float = (net_base_total + duty_total) * vat_rate

	return {
		"regime_id": str(regime.get("regime_id", "")),
		"net_base_total": _round_currency(net_base_total),
		"excise_duty_total": _round_currency(duty_total),
		"vat_total": _round_currency(vat_total),
		"gross_total": _round_currency(net_base_total + duty_total + vat_total)
	}

## Splits net weekly cashflow across pocket_cash, home_cash (CACHE:HOUSEHOLD), and DEMAND_DEPOSIT bank account
static func compute_liquidity_split(
	net_weekly_inflow: float,
	socioeconomic_tier: String,
	is_unbanked: bool,
	sim_year: int
) -> Dictionary:
	var regime: Dictionary = get_active_regime(sim_year)
	var profiles: Dictionary = regime.get("socioeconomic_liquidity_profiles", {})
	var tier_key: String = socioeconomic_tier.strip_edges().to_upper()
	var prof: Dictionary = profiles.get(tier_key, profiles.get("WORKING_CLASS_MANUAL", {}))

	var pocket_ratio: float = float(prof.get("pocket_cash_target_ratio_of_weekly_net", 0.18))
	var home_ratio: float = float(prof.get("home_cash_target_ratio_of_weekly_net", 0.45))
	var bank_ratio: float = float(prof.get("bank_retention_ratio", 0.37))

	if is_unbanked:
		home_ratio += bank_ratio
		bank_ratio = 0.0

	var sum_r: float = maxf(0.0001, pocket_ratio + home_ratio + bank_ratio)
	var inflow: float = maxf(0.0, net_weekly_inflow)

	return {
		"pocket_cash_delta": _round_currency(inflow * (pocket_ratio / sum_r)),
		"home_cash_delta": _round_currency(inflow * (home_ratio / sum_r)),
		"bank_deposit_delta": _round_currency(inflow * (bank_ratio / sum_r)),
		"contents_insured_probability": float(prof.get("contents_insured_probability", 0.30)),
		"crime_reporting_probability": float(prof.get("crime_reporting_probability", 0.55))
	}

## Computes post-victimization socioeconomic ripple deltas (insurance recovery vs uninsured distress & district heat)
static func compute_crime_victimization_ripple(
	cash_stolen: float,
	goods_value_stolen: float,
	socioeconomic_tier: String,
	is_insured: bool,
	did_report: bool,
	sim_year: int
) -> Dictionary:
	var regime: Dictionary = get_active_regime(sim_year)
	var r_cfg: Dictionary = regime.get("crime_victimization_ripples", {})
	var total_loss: float = maxf(0.0, cash_stolen + goods_value_stolen)
	var tier_key: String = socioeconomic_tier.strip_edges().to_upper()

	var heat_delta: float = 0.0
	if did_report:
		heat_delta = float(r_cfg.get("reported_crime_district_heat_delta", 0.04))
		if tier_key == "AFFLUENT_UPPER":
			heat_delta *= float(r_cfg.get("affluent_reporting_heat_multiplier", 1.75))

	if is_insured:
		var excess: float = total_loss * float(r_cfg.get("insured_excess_ratio", 0.10))
		var payout: float = maxf(0.0, goods_value_stolen - excess)
		return {
			"insured_payout_amount": _round_currency(payout),
			"payout_delay_days": int(r_cfg.get("insured_recovery_delay_days", 21)),
			"security_upgrade_delta": float(r_cfg.get("insured_security_upgrade_delta", 0.12)),
			"household_strain_delta": 0.05,
			"desperation_delta": 0.0,
			"district_heat_delta": heat_delta,
			"retail_demand_delta": -excess * float(r_cfg.get("retail_demand_contraction_per_pound_lost", 0.0025)),
			"zone_health_delta": 0.0
		}

	return {
		"insured_payout_amount": 0.0,
		"payout_delay_days": 0,
		"security_upgrade_delta": 0.0,
		"household_strain_delta": float(r_cfg.get("uninsured_distress_strain_delta", 0.35)),
		"desperation_delta": float(r_cfg.get("uninsured_desperation_delta", 0.12)),
		"district_heat_delta": heat_delta,
		"retail_demand_delta": -total_loss * float(r_cfg.get("retail_demand_contraction_per_pound_lost", 0.0025)),
		"zone_health_delta": -total_loss * float(r_cfg.get("zone_health_erosion_per_uninsured_loss", 0.0015))
	}

static func _deep_merge_dicts(base: Dictionary, override: Dictionary) -> Dictionary:
	var out: Dictionary = base.duplicate(true)
	for k in override.keys():
		var val: Variant = override[k]
		if out.has(k) and out[k] is Dictionary and val is Dictionary:
			out[k] = _deep_merge_dicts(out[k], val)
		else:
			out[k] = val.duplicate(true) if (val is Dictionary or val is Array) else val
	return out

static func _round_currency(val: float) -> float:
	return roundf(val * 100.0) / 100.0