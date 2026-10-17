# Systems / Verbs Architecture

## 1. Overview & Purpose

The `res://systems/verbs/` directory contains the atomic business commands of the simulation. Verbs encapsulate the procedural execution logic (*Verbs*) separately from state storage (*Nouns*). 

Each verb is an autonomous, stateless execution module that:
1. Validates local operational constraints (stock availability, liquidity, physical capacity).
2. Performs core economic transactions (deducting inputs, crediting yields, transferring cash).
3. Automatically scans and runs its own adjacent `impacts/` subfolder to emit quantitative consequence deltas (`impact_deltas`).

---

## 2. Directory Layout & Organization

Every verb lives in its own dedicated package directory or as an autoloaded script with an adjacent consequences subfolder:

```text
res://systems/verbs/
 ├── README.md                      <-- This document
 ├── verb_base.gd                   <-- Core static interface contract
 ├── verb_impact_base.gd            <-- Interface for local impact calculators
 ├── buy/
 │   ├── action_buy.gd              <-- Primary transaction logic
 │   └── impacts/                   <-- Local consequence calculators
 │       ├── impact_transport_fatigue.gd
 │       └── impact_supplier_coercion.gd
 ├── sell/
 │   ├── action_sell.gd
 │   └── impacts/
 │       ├── impact_police_heat.gd
 │       ├── impact_unpaid_credit.gd
 │       └── impact_zhi_erosion.gd
 └── make/
     ├── action_make.gd
     └── impacts/
         ├── impact_processing_fatigue.gd
         └── impact_batch_waste.gd
```

---

## 3. The Core Execution Contract

All action scripts conform to the unified static interface (`VerbBase`):

```gdscript
class_name VerbBase extends RefCounted

## 1. HARVEST PHASE (Decentralized UI/Context Ingestion)
## Pulls user configuration, sliders, or active UI input before execution
static func harvest(action: Dictionary, phase_config: Node, recipe_card: Node, db_mgr: Node) -> void:
    pass

## 2. EXECUTION PHASE (The Atomic Transaction)
## Enforces constraints, calculates primary deltas, and compiles local impacts.
## Returns a standardized outcome dictionary.
static func execute(world_state: Dictionary, action: Dictionary) -> Dictionary:
    return {
        "success": false,
        "verb": "",
        "target_node_id": "",
        "cash_delta": 0.0,
        "units_transacted": 0.0,
        "impact_deltas": {},
        "message": ""
    }
```

---

## 4. Subfolder Impact Delegation & Velocity Matching

Verbs do not calculate global police heat or worker fatigue directly in their main script. Instead, they delegate calculations to the scripts in their local `impacts/` directory.

The verb passes:
1. The execution summary (`units_transacted`, `gross_cash`, `target_node_id`).
2. The active commodity's `impact_velocities` profile (loaded from `commodities/<item>.json`).

```
┌────────────────────────────────────────────────────────┐
│                   ACTION: action_sell.gd               │
│  - Units Transacted: 50.0                              │
│  - Target Commodity: "RETAIL_WRAP"                     │
└───────────────────────────┬────────────────────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────┐
│       res://systems/verbs/sell/impacts/                │
│       impact_police_heat.gd                            │
│  - Queries RETAIL_WRAP["impact_velocities"]["SELL"]    │
│  - Velocity = 0.08                                     │
│  - Calculates: 50.0 * 0.08 = +4.0 Heat Delta           │
└───────────────────────────┬────────────────────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────┐
│          Standardized Action Result Output             │
│  { "impact_deltas": { "POLICE_HEAT": 4.0 } }           │
└────────────────────────────────────────────────────────┘
```

---

## 5. Reference Implementation: `action_sell.gd`

```gdscript
# res://systems/verbs/sell/action_sell.gd
extends VerbBase
class_name ActionSell

static var _impact_handlers: Array = []
static var _initialized: bool = false

static func _ensure_impacts_loaded() -> void:
    if not _initialized:
        _impact_handlers = load_subfolder_impacts("res://systems/verbs/sell/impacts")
        _initialized = true

static func harvest(action: Dictionary, _phase_config: Node, _recipe_card: Node, _db_mgr: Node) -> void:
    var config = action.get("config", {})
    action["target_item"] = config.get("target_item", "LEMONADE")
    action["amount"] = action.get("amount", config.get("order_amount", 10))

static func execute(world_state: Dictionary, action: Dictionary) -> Dictionary:
    _ensure_impacts_loaded()
    
    var params: Dictionary = action.get("config", {})
    var target_item: String = action.get("target_item", "")
    var requested_qty: float = float(action.get("amount", 0.0))
    
    # 1. Operational Constraint Checks
    var inventory = world_state.get("inventory_registry", {})
    if not inventory.has(target_item):
        return {"success": false, "verb": "SELL", "message": "Unknown commodity: %s" % target_item}
        
    var available_stock = world_state.get("stashes", {}).get(target_item, 0.0)
    var units_to_sell = min(requested_qty, available_stock)
    
    if units_to_sell <= 0.0:
        return {"success": false, "verb": "SELL", "message": "Zero inventory available to sell."}
        
    # 2. Primary Economic Transaction
    var unit_price = float(params.get("unit_price", 2.0))
    var gross_cash = units_to_sell * unit_price
    
    world_state["stashes"][target_item] -= units_to_sell
    world_state["finances"]["liquid_cash"] += gross_cash
    
    var summary = {
        "units_transacted": units_to_sell,
        "gross_cash": gross_cash,
        "target_node_id": action.get("target_node_id", "HQ")
    }
    
    # 3. Dynamic Impact Delta Compilation
    var commodity_profile: Dictionary = inventory.get(target_item, {})
    var compiled_deltas: Dictionary = compile_impact_deltas(
        _impact_handlers,
        params,
        summary,
        commodity_profile
    )
    
    return {
        "success": true,
        "verb": "SELL",
        "target_node_id": summary["target_node_id"],
        "cash_delta": gross_cash,
        "units_transacted": units_to_sell,
        "impact_deltas": compiled_deltas,
        "message": "Sold %.0f %s for £%.2f" % [units_to_sell, target_item, gross_cash]
    }
```

---

## 6. Development Workflow Rules

* **Adding a Verb:** Add a new subfolder under `res://systems/verbs/` containing `action_<verb>.gd`. Define `harvest()` and `execute()`. Register alias tokens in `verb_mappings.json`.
* **Adding a Consequence:** Drop an `impact_<metric>.gd` into the specific verb's `impacts/` folder. It will auto-load on the next engine boot.
* **Tuning Balance:** Modify the `impact_velocities` inside the commodity JSON file (`res://data_modules/<variant>/commodities/`) rather than altering the verb script code.
* **Headless Verification:** Verbs must never reference UI nodes (`$Control`, `Label`) inside `execute()`. Run standalone tests using:
  ```bash
  godot --headless --script res://tests/test_phase2_impacts.gd
  ```