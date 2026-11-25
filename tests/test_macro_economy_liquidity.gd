# res://tests/test_macro_economy_liquidity.gd
extends SceneTree

const FiscalCalculatorScript = preload("res://systems/economy/fiscal_calculator.gd")
const MacroEconomyProcessorScript = preload("res://systems/economy/macro_economy_processor.gd")
const ObligationLedgerScript = preload("res://systems/economy/obligation_ledger.gd")
const CalendarHelperScript = preload("res://systems/calendar_helper.gd")
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
	print("--- [Test] Starting Macro/Micro Liquidity & Historical Fiscal Regime Suite (TestSocietyFactory) ---")
	FiscalCalculatorScript.reset_cache()

	_test_historical_regime_transitions_and_taxes()
	_test_household_benefits_pensions_and_housing()
	await _test_radial_society_liquidity_and_idiosyncratic_drains()
	_test_crime_victimization_socioeconomic_ripples()

	if DBManagerScript.is_database_open():
		DBManagerScript.close_database()

	print("--- [Test] ALL MACRO/MICRO LIQUIDITY & FISCAL REGIME TESTS PASSED ---")
	quit(0)

func _test_historical_regime_transitions_and_taxes() -> void:
	var r1975: Dictionary = FiscalCalculatorScript.get_active_regime(1975)
	var r1984: Dictionary = FiscalCalculatorScript.get_active_regime(1984)
	var r1998: Dictionary = FiscalCalculatorScript.get_active_regime(1998)
	var r2018: Dictionary = FiscalCalculatorScript.get_active_regime(2018)

	assert(str(r1975.get("regime_id", "")) == "UK_1970_1978", "Expected UK_1970_1978 for 1975.")
	assert(str(r1984.get("regime_id", "")) == "UK_1979_1990", "Expected UK_1979_1990 for 1984.")
	assert(str(r1998.get("regime_id", "")) == "UK_1991_2009", "Expected UK_1991_2009 for 1998.")
	assert(str(r2018.get("regime_id", "")) == "UK_2010_PRESENT", "Expected UK_2010_PRESENT for 2018.")

	# PAYE & NI comparison across 1975 vs 1984 on £120/wk baseline wage
	var pay75: Dictionary = FiscalCalculatorScript.compute_net_pay(120.0, 1975, {
		"apply_wage_index": true,
		"is_married_allowance_eligible": true
	})
	var pay84: Dictionary = FiscalCalculatorScript.compute_net_pay(120.0, 1984, {
		"apply_wage_index": true,
		"is_married_allowance_eligible": true
	})
	assert(is_equal_approx(float(pay75["gross_weekly"]), 66.0), "1975 wage index (0.55) should scale £120 to £66.00.")
	assert(is_equal_approx(float(pay84["gross_weekly"]), 120.0), "1984 wage index (1.00) should keep £120.00.")
	assert(float(pay84["paye_tax_weekly"]) > 0.0 and float(pay84["ni_employee_weekly"]) > 0.0,
		"1984 PAYE and Employee NI must both be positive on £120/wk.")
	assert(float(pay84["net_weekly"]) < float(pay84["gross_weekly"]), "Net pay must be strictly less than gross.")

	# Illicit cash-in-hand contract bypasses PAYE & NI
	var illicit_pay: Dictionary = FiscalCalculatorScript.compute_net_pay(120.0, 1984, {
		"apply_wage_index": false,
		"contract_class": "ILLICIT"
	})
	assert(is_equal_approx(float(illicit_pay["net_weekly"]), 120.0) and is_equal_approx(float(illicit_pay["paye_tax_weekly"]), 0.0),
		"ILLICIT contract must bypass PAYE and NI.")

	# Excise duty + VAT (HMRC levies VAT on top of net + excise duty)
	var spirits_profile: Dictionary = {
		"tax_class": "STANDARD",
		"duty_class": "EXCISE_ALCOHOL_SPIRITS",
		"unit_volume_litres": 0.70,
		"abv": 0.40
	}
	var legal_sale: Dictionary = FiscalCalculatorScript.compute_vat_and_duty(3.00, 10.0, spirits_profile, 1984, {
		"contract_class": "FORMAL",
		"seller_vat_registered": true
	})
	assert(is_equal_approx(float(legal_sale["excise_duty_total"]), 43.34),
		"Expected 1984 spirits excise duty £43.34, got %.2f" % float(legal_sale["excise_duty_total"]))
	assert(is_equal_approx(float(legal_sale["vat_total"]), 11.00),
		"Expected 1984 VAT £11.00 on net+duty, got %.2f" % float(legal_sale["vat_total"]))

	var bootleg_sale: Dictionary = FiscalCalculatorScript.compute_vat_and_duty(3.00, 10.0, spirits_profile, 1984, {
		"contract_class": "ILLICIT"
	})
	assert(is_equal_approx(float(bootleg_sale["gross_total"]), 30.00) and is_equal_approx(float(bootleg_sale["vat_total"]), 0.0),
		"Bootleg ILLICIT sale must bypass excise duty and VAT.")

	print("  PASS [1/4]: Historical fiscal regimes (1975/1984/1998/2018), PAYE/NI, and HMRC duty+VAT verified.")

func _test_household_benefits_pensions_and_housing() -> void:
	# 1. Retired couple in 1984 (Male 66, Female 62 -> both eligible under 65/60 rule)
	var pension_hh: Dictionary = FiscalCalculatorScript.compute_household_benefits({
		"household_typology": "COUPLE_NO_DEP",
		"dependent_children": 0,
		"net_earned_weekly": 0.0,
		"members": [
			{"age": 66, "sex": "M"},
			{"age": 62, "sex": "F"}
		]
	}, 1984)
	assert(is_equal_approx(float(pension_hh["state_pension_weekly"]), 57.30),
		"Expected 1984 couple State Pension £57.30, got %.2f" % float(pension_hh["state_pension_weekly"]))

	# In 2018, 62-year-old female is below equalized 66 pension age -> only 1 pensioner eligible
	var pension_2018: Dictionary = FiscalCalculatorScript.compute_household_benefits({
		"household_typology": "COUPLE_NO_DEP",
		"dependent_children": 0,
		"net_earned_weekly": 0.0,
		"members": [
			{"age": 66, "sex": "M"},
			{"age": 62, "sex": "F"}
		]
	}, 2018)
	assert(is_equal_approx(float(pension_2018["state_pension_weekly"]), 221.20),
		"Expected 2018 single State Pension £221.20 under equalized age 66.")

	# 2. Unemployed lone parent with 2 children in 1984 + social housing direct-to-landlord relief
	var lone_parent: Dictionary = FiscalCalculatorScript.compute_household_benefits({
		"household_typology": "LONE_PARENT",
		"dependent_children": 2,
		"net_earned_weekly": 0.0,
		"members": [ {"age": 28, "sex": "F", "is_unemployed_signed_on": true}]
	}, 1984)
	assert(float(lone_parent["child_benefit_weekly"]) > 0.0 and float(lone_parent["means_tested_support_weekly"]) > 0.0,
		"Unemployed lone parent must receive Child Benefit and Income Support top-up.")

	var social_housing: Dictionary = FiscalCalculatorScript.compute_housing_and_local_tax({
		"tenure_type": "SOCIAL_COUNCIL",
		"district_wealth_multiplier": 0.70,
		"receives_means_tested_support": true
	}, 1984)
	assert(float(social_housing["direct_to_landlord_weekly"]) > 0.0,
		"1984 social housing HB must pay direct to landlord.")
	assert(float(social_housing["net_tenant_cash_outflow_weekly"]) < 2.0,
		"Means-tested social housing tenant should have minimal cash rent/rates outflow.")

	print("  PASS [2/4]: State pension age equalization, household welfare, and direct-to-landlord housing relief verified.")

func _test_radial_society_liquidity_and_idiosyncratic_drains() -> void:
	# Generate/mount ~40-district concentric radial society with real SQLite households & scouted crew
	var ws: Dictionary = await TestSocietyFactoryScript.create_test_world_with_crew(4, 4, "macro-liquidity-radial-seed", "week")
	var total_districts: int = ws.get("districts", {}).size()
	assert(total_districts >= 10, "Expected concentric radial society from TestSocietyFactory, got %d districts." % total_districts)

	var residents: Dictionary = ws.get("residents", {})
	var res_keys: Array = residents.keys()
	res_keys.sort()
	assert(res_keys.size() >= 2, "Expected at least 2 scouted crew residents from TestSocietyFactory.")

	# Operative A: Unbanked working-class operative receiving formal weekly pay -> splits pocket CASH + CACHE:HOUSEHOLD_<id>
	var op_a_key: Variant = res_keys[0]
	var op_a: Dictionary = residents[op_a_key]
	var op_a_id: int = int(op_a.get("resident_id", op_a_key))
	var hh_a_id: int = int(op_a.get("household_id", op_a_id))
	op_a["socioeconomic_tier"] = "WORKING_CLASS_MANUAL"
	op_a["is_unbanked"] = true
	op_a["weekly_gross_wage"] = 110.0
	if not op_a.has("inventory") or not (op_a["inventory"] is Dictionary):
		op_a["inventory"] = {}
	var initial_pocket_a: float = float(op_a["inventory"].get("CASH", 0.0))

	# Operative B: Idiosyncratic compulsive gambler + secret affair skimming household stash
	var op_b_key: Variant = res_keys[1]
	var op_b: Dictionary = residents[op_b_key]
	var op_b_id: int = int(op_b.get("resident_id", op_b_key))
	var hh_b_id: int = int(op_b.get("household_id", op_b_id))
	op_b["socioeconomic_tier"] = "AFFLUENT_UPPER"
	op_b["is_unbanked"] = false
	op_b["weekly_gross_wage"] = 260.0
	if not op_b.has("inventory") or not (op_b["inventory"] is Dictionary):
		op_b["inventory"] = {}
	op_b["inventory"]["CASH"] = 80.0
	op_b["behavioral_tags"] = [
		{"tag_code": "ADDICTION_GAMBLING", "severity": 0.85},
		{"tag_code": "SECRET_AFFAIR_MISTRESS", "severity": 0.70}
	]

	if not ws.has("caches") or not (ws["caches"] is Dictionary):
		ws["caches"] = {}
	var stash_b_key: String = "HOUSEHOLD_%d" % hh_b_id
	ws["caches"][stash_b_key] = {
		"cache_id": stash_b_key,
		"cache_scope": "HOUSEHOLD",
		"household_id": hh_b_id,
		"district_id": str(op_b.get("current_district_id", "")),
		"inventory": {"CASH": 200.0}
	}

	var turn_res: Dictionary = SimControllerScript.process_turn_cycle(ws, [])
	assert(bool(turn_res.get("week_rollover", false)), "Expected week_rollover == true after 7-day step.")

	var econ: Dictionary = turn_res.get("economy_rollover", {})
	var active_cnt: int = int(econ.get("active_districts_processed", 0))
	var bg_cnt: int = int(econ.get("background_districts_processed", 0))
	assert(active_cnt >= 1 and bg_cnt >= 1,
		"Expected both active FINE districts (%d) and background COARSE_COHORT districts (%d)." % [active_cnt, bg_cnt])
	assert(active_cnt + bg_cnt == total_districts,
		"All %d radial districts must be accounted for in economy_rollover." % total_districts)

	# Verify Operative A received dual-layer pocket CASH + secreted CACHE:HOUSEHOLD_<id>
	var stash_a_key: String = "HOUSEHOLD_%d" % hh_a_id
	var pocket_a_after: float = float(ws["residents"][op_a_key]["inventory"].get("CASH", 0.0))
	var stash_a_after: float = float(ws["caches"].get(stash_a_key, {}).get("inventory", {}).get("CASH", 0.0))
	assert(pocket_a_after > initial_pocket_a and stash_a_after > 0.0,
		"Unbanked operative must split net pay across pocket CASH (%.2f -> %.2f) and %s (%.2f)." % [
			initial_pocket_a, pocket_a_after, stash_a_key, stash_a_after
		])

	# Verify Operative B's gambling & secret affair skimmed household stash
	assert(int(econ.get("idiosyncratic_actors_processed", 0)) >= 1,
		"Expected idiosyncratic detail actor to be evaluated.")
	var stash_b_after: float = float(ws["caches"][stash_b_key]["inventory"].get("CASH", 0.0))
	assert(stash_b_after < 200.0,
		"Gambling/mistress drain must skim from %s stash (200.00 -> %.2f)." % [stash_b_key, stash_b_after])

	print("  PASS [3/4]: Radial society (%d districts: %d active, %d background), dual-layer cash custody & idiosyncratic drains verified." % [
		total_districts, active_cnt, bg_cnt
	])

func _test_crime_victimization_socioeconomic_ripples() -> void:
	var uninsured_poor: Dictionary = FiscalCalculatorScript.compute_crime_victimization_ripple(
		35.0,
		40.0,
		"BENEFIT_DEPENDENT",
		false,
		false,
		1984
	)
	var insured_affluent: Dictionary = FiscalCalculatorScript.compute_crime_victimization_ripple(
		120.0,
		2000.0,
		"AFFLUENT_UPPER",
		true,
		true,
		1984
	)

	assert(float(uninsured_poor["household_strain_delta"]) >= 0.30 and float(uninsured_poor["desperation_delta"]) > 0.0,
		"Uninsured benefit-dependent victim must suffer acute household strain and desperation.")
	assert(float(uninsured_poor["zone_health_delta"]) < 0.0,
		"Uninsured loss must erode district ZONE_HEALTH.")
	assert(float(insured_affluent["insured_payout_amount"]) > 0.0 and float(insured_affluent["security_upgrade_delta"]) > 0.0,
		"Insured affluent victim must receive delayed payout and security hardening.")
	assert(float(insured_affluent["district_heat_delta"]) > float(uninsured_poor["district_heat_delta"]),
		"Reported affluent burglary must generate higher district POLICE_HEAT spike.")

	print("  PASS [4/4]: Socioeconomic crime victimization ripples (uninsured distress vs insured hardening & heat) verified.")