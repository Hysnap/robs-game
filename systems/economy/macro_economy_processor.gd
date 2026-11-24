# res://systems/economy/macro_economy_processor.gd
class_name MacroEconomyProcessor
extends RefCounted

const DBManagerScript = preload("res://systems/db_manager.gd")
const CalendarHelperScript = preload("res://systems/calendar_helper.gd")
const ScenarioManifestManagerScript = preload("res://systems/scenario_manifest_manager.gd")
const FiscalCalculatorScript = preload("res://systems/economy/fiscal_calculator.gd")
const RetailDemandProcessorScript = preload("res://systems/economy/retail_demand_processor.gd")
const ObligationLedgerScript = preload("res://systems/economy/obligation_ledger.gd")

## Processes macro cohort liquidity rollovers, fine-district household/payroll cashflows,
## and individual idiosyncratic behavioral tag drains on weekly/monthly boundary ticks.
static func process_cycle(
	world_state: Dictionary,
	current_sim_day: int,
	active_districts: Array,
	is_month_close: bool = false
) -> Dictionary:
	var sim_year: int = CalendarHelperScript.day_to_year(current_sim_day)
	var regime: Dictionary = FiscalCalculatorScript.get_active_regime(sim_year)

	var active_lookup: Dictionary = {}
	for d_id in active_districts:
		active_lookup[str(d_id)] = true

	var report: Dictionary = {
		"sim_day": current_sim_day,
		"sim_year": sim_year,
		"regime_id": str(regime.get("regime_id", "")),
		"is_month_close": is_month_close,
		"active_districts_processed": 0,
		"background_districts_processed": 0,
		"idiosyncratic_actors_processed": 0,
		"total_net_wages_disbursed": 0.0,
		"total_benefits_disbursed": 0.0,
		"total_idiosyncratic_drain": 0.0,
		"informal_debts_created": 0,
		"retail_gross_sales": 0.0,
		"vat_collected": 0.0,
		"excise_duty_collected": 0.0
	}

	var days_in_cycle: int = CalendarHelperScript.get_days_per_tick()
	var active_events: Array[String] = _resolve_active_calendar_events(world_state, current_sim_day)

	# 1. Process district macro cohort pools & retail demand fulfillment (background coarse vs active fine)
	var districts: Dictionary = world_state.get("districts", {})
	for d_key in districts.keys():
		var d_id: String = str(d_key)
		var d_rec: Dictionary = districts[d_key] if districts[d_key] is Dictionary else {}
		var is_active: bool = active_lookup.has(d_id)
		var cohort_res: Dictionary = _process_district_macro_cohort(world_state, d_id, d_rec, regime, sim_year, is_active)
		report["total_net_wages_disbursed"] += float(cohort_res.get("net_wages", 0.0))
		report["total_benefits_disbursed"] += float(cohort_res.get("benefits", 0.0))

		var retail_res: Dictionary = RetailDemandProcessorScript.process_district_retail_cycle(
			world_state,
			d_id,
			days_in_cycle,
			sim_year,
			active_events
		)
		report["retail_gross_sales"] = snappedf(float(report["retail_gross_sales"]) + float(retail_res.get("gross_sales", 0.0)), 0.01)
		report["vat_collected"] = snappedf(float(report["vat_collected"]) + float(retail_res.get("vat_collected", 0.0)), 0.01)
		report["excise_duty_collected"] = snappedf(float(report["excise_duty_collected"]) + float(retail_res.get("excise_duty_collected", 0.0)), 0.01)

		if is_active:
			report["active_districts_processed"] += 1
		else:
			report["background_districts_processed"] += 1

	# 2. Process fine-resolution active residents & dual-layer household caches
	_process_active_residents_and_caches(world_state, current_sim_day, sim_year, active_lookup, report)

	# 3. Always evaluate idiosyncratic detail actors (gamblers, addicts, secret affairs, corrupt officials)
	var idio_res: Dictionary = _process_idiosyncratic_detail_actors(world_state, current_sim_day, regime, sim_year, is_month_close)
	report["idiosyncratic_actors_processed"] = int(idio_res.get("actors_processed", 0))
	report["total_idiosyncratic_drain"] = float(idio_res.get("total_drained", 0.0))
	report["informal_debts_created"] = int(idio_res.get("debts_created", 0))

	return report

static func _resolve_active_calendar_events(world_state: Dictionary, current_sim_day: int) -> Array[String]:
	var events: Array[String] = []
	var dow: int = CalendarHelperScript.day_of_week(current_sim_day)
	if dow == 4 or dow == 5:
		events.append("WEEKLY_PAYDAY")
	var cal_events: Array = world_state.get("calendar_events", [])
	for ev in cal_events:
		if ev is Dictionary:
			var ev_day: int = int(ev.get("sim_day", -1))
			if ev_day == current_sim_day:
				var code: String = str(ev.get("event_code", ev.get("code", ""))).strip_edges().to_upper()
				if not code.is_empty() and not events.has(code):
					events.append(code)
	return events

## Aggregates SQLite household & livelihood cohorts for a district into macro liquidity pools
static func _process_district_macro_cohort(
	world_state: Dictionary,
	district_id: String,
	district_rec: Dictionary,
	regime: Dictionary,
	sim_year: int,
	is_active: bool
) -> Dictionary:
	var cohort_cfg: Dictionary = _get_macro_cohort_cfg(regime)
	var bracket_profiles: Dictionary = cohort_cfg.get("wealth_bracket_profiles", {})
	var default_bracket: String = str(cohort_cfg.get("default_wealth_bracket", "")).to_upper()
	assert(bracket_profiles.has(default_bracket),
		"FATAL: [MacroEconomyProcessor] Missing default_wealth_bracket '%s' in macro_cohort_model." % default_bracket)

	var raw_bracket: String = str(district_rec.get("wealth_bracket", default_bracket)).strip_edges().to_upper()
	var b_prof: Dictionary = bracket_profiles.get(raw_bracket, bracket_profiles[default_bracket])
	var socio_tier: String = str(b_prof.get("socioeconomic_tier", ""))
	var wealth_mult: float = float(b_prof.get("wealth_multiplier", 1.0))
	var default_tenure: String = str(b_prof.get("default_tenure", "SOCIAL_COUNCIL"))

	var employed_count: int = 0
	var avg_base_weekly_wage: float = float(cohort_cfg.get("fallback_base_weekly_wage", 0.0)) * wealth_mult
	var household_count: int = 0

	if DBManagerScript.is_database_open() and _has_table("households") and _has_table("establishments"):
		var d_esc: String = district_id.replace("'", "''")
		var hh_rows: Array = DBManagerScript.query_rows("""
			SELECT COUNT(*) AS hh_cnt
			FROM households h
			JOIN establishments e ON h.establishment_id = e.establishment_id
			WHERE e.district_id = '%s' AND h.valid_to IS NULL;
		""" % d_esc)
		if not hh_rows.is_empty():
			household_count = int(hh_rows[0].get("hh_cnt", 0))

		if _has_table("livelihood_contracts") and _has_table("residents"):
			var emp_rows: Array = DBManagerScript.query_rows("""
				SELECT COUNT(*) AS emp_cnt,
				       COALESCE(AVG(lc.compensation_rate * lc.weekly_hours), 0.0) AS avg_weekly
				FROM livelihood_contracts lc
				JOIN residents r ON lc.resident_id = r.resident_id
				JOIN households h ON r.household_id = h.household_id
				JOIN establishments e ON h.establishment_id = e.establishment_id
				WHERE e.district_id = '%s' AND lc.valid_to IS NULL AND r.dod IS NULL;
			""" % d_esc)
			if not emp_rows.is_empty():
				employed_count = int(emp_rows[0].get("emp_cnt", 0))
				var queried_avg: float = float(emp_rows[0].get("avg_weekly", 0.0))
				if queried_avg > 0.0:
					avg_base_weekly_wage = queried_avg

	if household_count <= 0:
		var persons_per_hh: int = maxi(1, int(cohort_cfg.get("avg_persons_per_household", 1)))
		var emp_rate: float = clampf(float(cohort_cfg.get("baseline_employment_rate", 0.0)), 0.0, 1.0)
		household_count = maxi(1, floori(float(district_rec.get("population", 0)) / float(persons_per_hh)))
		employed_count = int(round(float(household_count) * emp_rate))

	var unemployed_households: int = maxi(0, household_count - employed_count)

	var pay_res: Dictionary = FiscalCalculatorScript.compute_net_pay(avg_base_weekly_wage, sim_year, {
		"apply_wage_index": true,
		"contract_class": "FORMAL"
	})
	var net_wage_per_worker: float = float(pay_res.get("net_weekly", 0.0))
	var total_net_wages: float = net_wage_per_worker * float(employed_count)

	var ben_res: Dictionary = FiscalCalculatorScript.compute_household_benefits({
		"household_typology": "COUPLE_WITH_DEP",
		"dependent_children": 1,
		"net_earned_weekly": 0.0,
		"members": [ {"age": 34, "sex": "M", "is_unemployed_signed_on": true}]
	}, sim_year)
	var benefit_per_hh: float = float(ben_res.get("total_benefits_weekly", 0.0))
	var total_benefits: float = benefit_per_hh * float(unemployed_households)

	var housing_res: Dictionary = FiscalCalculatorScript.compute_housing_and_local_tax({
		"tenure_type": default_tenure,
		"district_wealth_multiplier": wealth_mult,
		"receives_means_tested_support": unemployed_households > employed_count
	}, sim_year)
	var total_housing_outflow: float = float(housing_res.get("net_tenant_cash_outflow_weekly", 0.0)) * float(household_count)

	var disposable_pool: float = maxf(0.0, (total_net_wages + total_benefits) - total_housing_outflow)
	var liq_split: Dictionary = FiscalCalculatorScript.compute_liquidity_split(
		disposable_pool,
		socio_tier,
		socio_tier == "BENEFIT_DEPENDENT",
		sim_year
	)
	var retail_ratio: float = clampf(float(cohort_cfg.get("disposable_to_retail_spending_ratio", 0.0)), 0.0, 1.0)

	district_rec["macro_liquidity"] = {
		"socioeconomic_tier": socio_tier,
		"resolution": "FINE" if is_active else "COARSE_COHORT",
		"net_wages_weekly": _round_currency(total_net_wages),
		"benefits_weekly": _round_currency(total_benefits),
		"housing_outflow_weekly": _round_currency(total_housing_outflow),
		"pocket_cash_pool": float(liq_split.get("pocket_cash_delta", 0.0)),
		"home_cash_pool": float(liq_split.get("home_cash_delta", 0.0)),
		"bank_deposit_pool": float(liq_split.get("bank_deposit_delta", 0.0)),
		"retail_spending_capacity": _round_currency(disposable_pool * retail_ratio)
	}
	world_state["districts"][district_id] = district_rec

	return {
		"net_wages": total_net_wages,
		"benefits": total_benefits
	}

## Materializes and updates individual pocket CASH, CACHE:HOUSEHOLD_<id>, and DEMAND_DEPOSIT for active residents
static func _process_active_residents_and_caches(
	world_state: Dictionary,
	current_sim_day: int,
	sim_year: int,
	active_lookup: Dictionary,
	report: Dictionary
) -> void:
	var residents: Dictionary = world_state.get("residents", {})
	if residents.is_empty():
		return

	if not world_state.has("caches") or not (world_state["caches"] is Dictionary):
		world_state["caches"] = {}
	var caches: Dictionary = world_state["caches"]

	var sorted_keys: Array = residents.keys()
	sorted_keys.sort()

	for r_key in sorted_keys:
		var rec = residents[r_key]
		if not (rec is Dictionary):
			continue
		var dist_id: String = str(rec.get("current_district_id", rec.get("base_district_id", ""))).strip_edges()
		if not active_lookup.is_empty() and not dist_id.is_empty() and not active_lookup.has(dist_id):
			continue

		var res_id: int = int(rec.get("resident_id", int(r_key) if str(r_key).is_valid_int() else 0))
		var base_weekly: float = float(rec.get("weekly_gross_wage", 0.0))
		var contract_class: String = str(rec.get("contract_class", "FORMAL")).to_upper()
		var socio_tier: String = str(rec.get("socioeconomic_tier", "WORKING_CLASS_MANUAL")).to_upper()
		if contract_class == "ILLICIT" or contract_class == "INFORMAL_GREY":
			socio_tier = "INFORMAL_ILLICIT_OPERATOR"

		var net_inflow: float = 0.0
		if base_weekly > 0.0:
			var pay: Dictionary = FiscalCalculatorScript.compute_net_pay(base_weekly, sim_year, {
				"apply_wage_index": false,
				"contract_class": contract_class
			})
			net_inflow = float(pay.get("net_weekly", 0.0))
			report["total_net_wages_disbursed"] += net_inflow
		else:
			var ben: Dictionary = FiscalCalculatorScript.compute_household_benefits({
				"household_typology": str(rec.get("household_typology", "SINGLE_PERSON")),
				"dependent_children": int(rec.get("dependent_children", 0)),
				"net_earned_weekly": 0.0,
				"members": [ {
					"age": int(rec.get("age", 30)),
					"sex": str(rec.get("sex", "M")),
					"is_unemployed_signed_on": bool(rec.get("is_unemployed_signed_on", true))
				}]
			}, sim_year)
			net_inflow = float(ben.get("total_benefits_weekly", 0.0))
			report["total_benefits_disbursed"] += net_inflow

		var is_unbanked: bool = bool(rec.get("is_unbanked", socio_tier in ["BENEFIT_DEPENDENT", "INFORMAL_ILLICIT_OPERATOR"]))
		var split: Dictionary = FiscalCalculatorScript.compute_liquidity_split(net_inflow, socio_tier, is_unbanked, sim_year)

		# 1. Pocket CASH on resident
		if not rec.has("inventory") or not (rec["inventory"] is Dictionary):
			rec["inventory"] = {}
		rec["inventory"]["CASH"] = _round_currency(float(rec["inventory"].get("CASH", 0.0)) + float(split.get("pocket_cash_delta", 0.0)))

		# 2. Secreted Household Stash (CACHE:HOUSEHOLD_<id>)
		var hh_id: int = int(rec.get("household_id", res_id))
		if hh_id > 0:
			var cache_key: String = "HOUSEHOLD_%d" % hh_id
			if not caches.has(cache_key) or not (caches[cache_key] is Dictionary):
				caches[cache_key] = {
					"cache_id": cache_key,
					"cache_scope": "HOUSEHOLD",
					"household_id": hh_id,
					"district_id": dist_id,
					"inventory": {}
				}
			var c_inv: Dictionary = caches[cache_key].get("inventory", {})
			c_inv["CASH"] = _round_currency(float(c_inv.get("CASH", 0.0)) + float(split.get("home_cash_delta", 0.0)))
			caches[cache_key]["inventory"] = c_inv

		# 3. Formal DEMAND_DEPOSIT in ObligationLedger when banked
		var bank_delta: float = float(split.get("bank_deposit_delta", 0.0))
		if not is_unbanked and bank_delta > 0.0 and res_id > 0 and DBManagerScript.is_database_open() and _has_table("obligations"):
			var holder_ref: String = ObligationLedgerScript.format_scoped_entity("RESIDENT", str(res_id))
			var dep_obl_id: int = ObligationLedgerScript.resolve_primary_deposit_obligation_id(holder_ref)
			if dep_obl_id > 0:
				ObligationLedgerScript.adjust_obligation_balance(dep_obl_id, bank_delta, current_sim_day, false)

## Evaluates individual compulsive/covert actors (gamblers, addicts, secret affairs, corrupt officials)
## across the entire city on weekly/monthly rollovers so they stay at full detail parity.
static func _process_idiosyncratic_detail_actors(
	world_state: Dictionary,
	current_sim_day: int,
	regime: Dictionary,
	_sim_year: int,
	is_month_close: bool
) -> Dictionary:
	var profile_defs: Dictionary = _get_behavioral_profile_defs()
	if profile_defs.is_empty():
		return {"actors_processed": 0, "total_drained": 0.0, "debts_created": 0}

	var cohort_cfg: Dictionary = _get_macro_cohort_cfg(regime)
	var shortfall_cfg: Dictionary = cohort_cfg.get("idiosyncratic_shortfall_defaults", {})
	var shortfall_trigger: float = float(shortfall_cfg.get("shortfall_trigger_threshold", 0.0))
	var base_debt: float = float(shortfall_cfg.get("base_shortfall_debt", 0.0))
	var debt_rate: float = float(shortfall_cfg.get("shortfall_interest_rate", 0.0))
	var debt_rec_days: int = int(shortfall_cfg.get("shortfall_recurrence_days", 7))
	var debt_due_offset: int = int(shortfall_cfg.get("shortfall_due_offset_days", 14))
	var default_desp_delta: float = float(shortfall_cfg.get("default_desperation_delta", 0.0))
	var price_mult: float = float(regime.get("price_index_multiplier", 1.0))

	var candidates: Dictionary = {}
	var residents: Dictionary = world_state.get("residents", {})
	for r_key in residents.keys():
		var rec = residents[r_key]
		if not (rec is Dictionary):
			continue
		var tags: Array = rec.get("behavioral_tags", [])
		if not tags.is_empty():
			var r_id: int = int(rec.get("resident_id", int(r_key) if str(r_key).is_valid_int() else 0))
			if r_id > 0:
				candidates[r_id] = {
					"resident_id": r_id,
					"household_id": int(rec.get("household_id", r_id)),
					"tags": tags
				}

	if DBManagerScript.is_database_open() and _has_table("resident_behavioral_tags") and _has_table("system_labels"):
		var tag_rows: Array = DBManagerScript.query_rows("""
			SELECT t.resident_id, l.code AS tag_code, t.severity, r.household_id
			FROM resident_behavioral_tags t
			JOIN system_labels l ON t.tag_label_id = l.label_id
			JOIN residents r ON t.resident_id = r.resident_id
			WHERE t.valid_to IS NULL AND r.dod IS NULL
			ORDER BY t.resident_id ASC;
		""")
		for row in tag_rows:
			var r_id: int = int(row.get("resident_id", 0))
			if r_id <= 0:
				continue
			if not candidates.has(r_id):
				candidates[r_id] = {
					"resident_id": r_id,
					"household_id": int(row.get("household_id", r_id)),
					"tags": []
				}
			candidates[r_id]["tags"].append({
				"tag_code": str(row.get("tag_code", "")),
				"severity": float(row.get("severity", 0.5))
			})

	var caches: Dictionary = world_state.get("caches", {})
	var actors_processed: int = 0
	var total_drained: float = 0.0
	var debts_created: int = 0
	var period_mult: float = 4.0 if is_month_close else 1.0

	var sorted_ids: Array = candidates.keys()
	sorted_ids.sort()

	for r_id in sorted_ids:
		var cand: Dictionary = candidates[r_id]
		var res_key: Variant = r_id if residents.has(r_id) else str(r_id)
		var res_rec: Dictionary = residents.get(res_key, {}) if residents.has(res_key) else {}
		var hh_id: int = int(cand.get("household_id", r_id))
		var cache_key: String = "HOUSEHOLD_%d" % hh_id
		var had_economic_effect: bool = false

		for tag_entry in cand.get("tags", []):
			var tag_code: String = str(tag_entry.get("tag_code", tag_entry) if tag_entry is Dictionary else tag_entry).to_upper()
			var severity: float = float(tag_entry.get("severity", 0.5)) if tag_entry is Dictionary else 0.5
			if not profile_defs.has(tag_code):
				continue
			var p_def: Dictionary = profile_defs[tag_code]
			var effects: Dictionary = p_def.get("effects", {})
			if effects.is_empty():
				continue

			had_economic_effect = true
			var sev_scale: float = clampf(0.5 + severity, 0.5, 1.5)
			var pocket_ratio: float = clampf(float(effects.get("weekly_pocket_drain_ratio", 0.0)) * sev_scale * period_mult, 0.0, 0.98)
			var stash_ratio: float = clampf(float(effects.get("weekly_home_stash_skim_ratio", 0.0)) * sev_scale * period_mult, 0.0, 0.95)
			var bank_ratio: float = clampf(float(effects.get("weekly_bank_draw_ratio", 0.0)) * sev_scale * period_mult, 0.0, 0.90)

			var drained_this_tag: float = 0.0
			if not res_rec.is_empty():
				var inv: Dictionary = res_rec.get("inventory", {})
				var p_cash: float = float(inv.get("CASH", 0.0))
				var p_take: float = _round_currency(p_cash * pocket_ratio)
				if p_take > 0.0:
					inv["CASH"] = _round_currency(maxf(0.0, p_cash - p_take))
					res_rec["inventory"] = inv
					drained_this_tag += p_take

			if stash_ratio > 0.0 and caches.has(cache_key) and caches[cache_key] is Dictionary:
				var c_inv: Dictionary = caches[cache_key].get("inventory", {})
				var h_cash: float = float(c_inv.get("CASH", 0.0))
				var h_take: float = _round_currency(h_cash * stash_ratio)
				if h_take > 0.0:
					c_inv["CASH"] = _round_currency(maxf(0.0, h_cash - h_take))
					caches[cache_key]["inventory"] = c_inv
					drained_this_tag += h_take

			if bank_ratio > 0.0 and DBManagerScript.is_database_open() and _has_table("obligations"):
				var holder_ref: String = ObligationLedgerScript.format_scoped_entity("RESIDENT", str(r_id))
				var dep_id: int = ObligationLedgerScript.resolve_primary_deposit_obligation_id(holder_ref)
				if dep_id > 0:
					var dep_obl: Dictionary = ObligationLedgerScript.get_obligation(dep_id)
					var b_bal: float = float(dep_obl.get("balance", 0.0))
					var b_take: float = _round_currency(b_bal * bank_ratio)
					if b_take > 0.0:
						ObligationLedgerScript.adjust_obligation_balance(dep_id, -b_take, current_sim_day, false)
						drained_this_tag += b_take

			total_drained += drained_this_tag

			if bool(effects.get("creates_informal_debt_on_shortfall", false)) and drained_this_tag < (shortfall_trigger * sev_scale):
				var desp_delta: float = float(effects.get("desperation_delta_on_shortfall", default_desp_delta))
				if not res_rec.is_empty():
					res_rec["desperation"] = clampf(float(res_rec.get("desperation", 0.0)) + desp_delta, 0.0, 1.0)
				if DBManagerScript.is_database_open() and _has_table("obligations") and base_debt > 0.0:
					var debt_amt: float = _round_currency(base_debt * sev_scale * price_mult)
					ObligationLedgerScript.create_obligation({
						"debtor": ObligationLedgerScript.format_scoped_entity("RESIDENT", str(r_id)),
						"creditor": "ORG:INFORMAL_LENDERS",
						"obligation_type": str(effects.get("shortfall_debt_obligation_type", "TERM_LOAN")),
						"principal": debt_amt,
						"balance": debt_amt,
						"interest_rate": debt_rate,
						"recurrence_days": debt_rec_days,
						"due_day": current_sim_day + debt_due_offset,
						"created_day": current_sim_day
					})
					debts_created += 1

		if had_economic_effect:
			actors_processed += 1
			if not res_rec.is_empty():
				residents[res_key] = res_rec

	return {
		"actors_processed": actors_processed,
		"total_drained": _round_currency(total_drained),
		"debts_created": debts_created
	}

static func _get_macro_cohort_cfg(regime: Dictionary) -> Dictionary:
	var cfg: Dictionary = regime.get("macro_cohort_model", {})
	assert(not cfg.is_empty(), "FATAL: [MacroEconomyProcessor] Active fiscal regime missing 'macro_cohort_model'.")
	return cfg

static func _get_behavioral_profile_defs() -> Dictionary:
	if not ScenarioManifestManagerScript.has_module("ocean_personality"):
		return {}
	var rules: Dictionary = ScenarioManifestManagerScript.load_module("ocean_personality")
	return rules.get("neurodivergence_and_clinical_profiles", {})

static func _has_table(table_name: String) -> bool:
	var rows: Array = DBManagerScript.query_rows(
		"SELECT COUNT(*) AS cnt FROM sqlite_master WHERE type='table' AND name='%s';" % table_name.replace("'", "''")
	)
	return not rows.is_empty() and int(rows[0].get("cnt", 0)) > 0

static func _round_currency(val: float) -> float:
	return roundf(val * 100.0) / 100.0