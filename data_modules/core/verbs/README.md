# Core Verbs Architecture

## 1. Overview & Purpose
The `res://data_modules/core/verbs/` directory contains the atomic business actions and macro workflows of the simulation[cite: 8]. Following the decoupled command pattern, verbs encapsulate execution logic (*Actions*) separately from state storage (*Nouns*)[cite: 8].

Verbs are autonomous, stateless execution modules that:
1. Enforce preconditions and operational constraints using `ConditionEvaluator`[cite: 8].
2. Orchestrate business transactions (order ticketing, financial settlements, physical inventory movement)[cite: 8].
3. Compute quantitative consequence deltas (`impact_deltas`) via `ImpactCalculator` without mutating global state directly[cite: 8].
4. Return standardized `EngineResult` payloads alongside colocated `feedback.json` narrative mappings[cite: 8].

---

## 2. Directory Layout & Organization

Verbs are packaged into dedicated folders containing their execution script and narrative feedback matrix[cite: 8]:

```text
res://data_modules/core/verbs/
 ├── order/
 │    ├── action_order.gd             <-- Atomic: Creates persistent order slip & checks solvency
 │    └── feedback.json               <-- Outcome messages (e.g. ORDER_CREATED, INSUFFICIENT_CASH)
 ├── pay/
 │    ├── action_pay.gd               <-- Atomic: Financial settlement (CASH sink)
 │    └── feedback.json               <-- Outcome messages (e.g. PAID_IN_FULL, ALREADY_PAID)
 ├── receive/
 │    ├── action_receive.gd           <-- Atomic: Physical delivery & material impact activation
 │    └── feedback.json               <-- Outcome messages (e.g. STOCK_RECEIVED, GOODS_DAMAGED)
 ├── buy/
 │    ├── action_buy.gd               <-- Macro: Sequences ORDER -> PAY -> RECEIVE (Wholesale)
 │    └── feedback.json
 ├── sell/
 │    ├── action_sell.gd              <-- Macro: Sequences ORDER -> RECEIVE -> PAY (Retail/B2B)
 │    └── feedback.json
 └── make/
      ├── action_make.gd              <-- Production: Recipe transformation & ingredient consumption
      └── feedback.json

```

---

## 3. The Core Execution Contract

All action scripts inherit from `ActionBase` (`res://systems/action_base.gd`) and implement the standardized static interface:

```gdscript
class_name ActionBase extends RefCounted

## 1. HARVEST PHASE (Decentralized UI/Context Ingestion)
## Reads player inputs, sliders, or active UI forms without hardcoding logic in controllers
static func harvest(action: Dictionary, phase_config: Node, recipe_card: Node, db_mgr: Node) -> void:
    pass

## 2. EXECUTION PHASE (The Atomic Transaction)
## Asserts constraints, executes transaction, and computes impact deltas.
## Always returns a standardized EngineResult.
static func execute(world_state: Dictionary, action_directive: Dictionary) -> EngineResult:
    return EngineResult.fail("UNIMPLEMENTED", "VERB", "Unimplemented verb execution.")

```

---

## 4. Universal Atomic Symmetry (`ORDER` $\rightarrow$ `PAY` $\rightarrow$ `RECEIVE`)

To prevent code duplication and support both instant retail and delayed asynchronous logistics (such as beeper orders, cargo transit, or credit accounts), commercial trade is broken into three symmetrical atomic steps:

```
┌────────────────────────────────────────────────────────┐
│                        ORDER                           │
│  • Registers order slip in `world_state.pending_orders`│
│  • Verifies buyer solvency and vendor inventory        │
└───────────────────────────┬────────────────────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────┐
│                         PAY                            │
│  • Emits financial deltas (`CASH` sink)                │
│  • Updates slip status: ORDERED -> PAID                │
└───────────────────────────┬────────────────────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────┐
│                       RECEIVE                          │
│  • Moves physical goods: `ON_ORDER` -> `STOCK`         │
│  • Evaluates transacted commodity's impact activations │
│  • Archives completed order slip                       │
└────────────────────────────────────────────────────────┘

```

* **Immediate Face-to-Face Trade (`BUY`, `SELL`):** Execute all three atomic steps in sequence in a single tick.


* **Asynchronous Supply Chains:** Pipeline controllers schedule `ORDER` on Tick 1, `RECEIVE` on Tick 3, and `PAY` on Tick 4 without changing verb logic.


* **Actor Agnostic:** Verbs execute identically whether initiated by the player, a subordinate employee, or an autonomous NPC counterparty (`initiator_id` vs `counterparty_id`).



---

## 5. How Verbs Process Impacts

Verbs do not maintain hardcoded consequence formulas or execute local impact scripts. Instead, they delegate to `ImpactCalculator` using data definitions attached to commodities and recipes:

```gdscript
# Inside ActionReceive or ActionMake
var activations: Array = commodity.get("impact_activations", {}).get("BUY", [])

for entry in activations:
    var metric: String = entry.get("metric", "")
    var model: String = entry.get("model", "LINEAR_PER_UNIT")
    var factor: float = float(entry.get("factor", 0.0))
    var params: Dictionary = entry.get("params", {})
    
    var delta: float = ImpactCalculator.calculate(model, units_transacted, factor, params)
    if metric != "" and delta != 0.0:
        impact_deltas[metric] = impact_deltas.get(metric, 0.0) + delta

```

The resulting `impact_deltas` dictionary is packaged inside `EngineResult` and passed to `SimController`, which routes deltas to their respective sinks via `ImpactRouter`.

---

## 6. Narrative Feedback (`feedback.json`)

Verbs do not return hardcoded display strings. Narrative generation is decoupled across three cascading layers:

1. **Colocated Verb Overrides (`feedback.json`):** Defines outcome strings specific to that action (e.g. `INSUFFICIENT_CASH` for `BUY`).


2. **Shared Outcomes (`data_modules/shared/feedback/`):** Universal fallbacks for common codes (`OUTSIDE_HOURS`, `OPERATOR_BURNOUT`).


3. **Dialect Slang Replacement (`dialects/`):** Tokens such as `{boss}`, `{wedge}`, or `{stash}` are replaced dynamically based on the actor's regional dialect profile.



---

## 7. Development & Verification Rules

* **Adding a Verb:**
1. Create a dedicated folder in `res://data_modules/core/verbs/<verb_name>/`.


2. Implement `action_<verb_name>.gd` extending `ActionBase`.


3. Add `feedback.json` for outcome phrasing.


4. Register optional aliases in `verb_mappings.json` (e.g. `"RESTOCK": "BUY"`).


5. `VerbRouter` mounts the new action on boot automatically.




* **Headless Verification:**
Verbs must remain 100% headless and free of direct UI nodes (`$Control`, `Label`). Verify behavior using test harnesses:


```powershell
godot --headless --script res://tests/test_engine_harness.gd

```


