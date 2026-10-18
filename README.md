# Decision & Response Simulation Engine

A data-driven, turn-based economic and operational simulation engine built for **Godot 4.x (GDScript)**.

The engine maintains a strict architectural separation between **Mechanics** (pure execution scripts), **Flavor & Archetypes** (hierarchical data modules), and **Perception** (a dual-layer imperfect information model reflecting asynchronous communication drag).

---

## 1. Core Architecture Principles

1. **Pure Doing Code (`systems/`)**
   The execution engine contains zero narrative or scenario assumptions. It operates strictly on abstract dictionaries, action command verbs, condition evaluators, and mathematical delta sinks.

2. **Content & Flavor Modules (`data_modules/`)**
   Scenarios, trade goods, production recipes, and consequence weights live entirely within configuration trees. The default rules reside in `data_modules/core/`. Changing or modding scenarios (e.g., from legal trade to an illicit economy) is achieved by pointing the loader to an alternative module folder without modifying engine code.

3. **$N$-Tier Prototype Inheritance (Taxonomic Cascade)**
   Commodities, recipes, and entities are organized in cascading directory structures. Subdirectories automatically inherit and override properties defined in adjacent `_base.json` templates. An item only defines what makes it distinct; unspecified fields are inherited from its parent tiers.

4. **Discrete Verb Execution vs. Pluggable Metric Sinks**
   * **Verbs (`action_*.gd`)** control business rules, assertions, inventory transfers, and throughput.
   * Verbs query `ImpactCalculator` to calculate consequences, emitting an `impact_deltas` dictionary.
   * **Global Sinks (`ImpactSinkBase`)** receive these deltas via `ImpactRouter` and mutate the objective state.

5. **Universal Atomic Symmetry (`ORDER` $\rightarrow$ `PAY` $\rightarrow$ `RECEIVE`)**
   Trade interactions are symmetrical. Complex operations (`BUY`, `SELL`) are macro-verbs composed of three atomic sub-verbs:
   * **`ORDER`:** Registers an order slip, asserts solvency, and verifies counterparty stock.
   * **`PAY`:** Resolves financial settlement via the `CASH` sink.
   * **`RECEIVE`:** Resolves physical delivery via the inventory stock lanes and evaluates physical commodity impacts.

6. **Process vs. Material Impact Separation (`MAKE`)**
   Transformation processes separate mechanical impacts from chemical/ingredient impacts:
   * **Recipe Impacts (`recipes/.../make/`):** Consequences of the *process* itself (tool wear, machinery fatigue, power draw).
   * **Ingredient Impacts (`commodities/.../make/`):** Consequences of handling the *material* (toxic fumes, handling spillage, chemical odor heat).

7. **Dual-Trigger Consequence Contract**
   Consequences are triggered via two paths:
   * **Action Impulse:** Discrete deltas created immediately when an action runs (e.g., `SELL` creates police heat).
   * **Ambient Pulse:** An end-of-turn heartbeat where the environment acts on itself (e.g., passive heat dissipation, customer panic, zone health degradation, and inventory shrinkage).

8. **Standardized Error Handling (`EngineResult`)**
   The simulation never invents "ghost" entities or defaults missing actors silently. Actions return a standardized `EngineResult` containing status flags, error codes (`ENTITY_NOT_FOUND`, `INSUFFICIENT_RESOURCE`), deltas, and telemetry.

9. **Dual-Layer Reality (Objective Truth vs. Filofax Cache)**
   The player never inspects true state directly. State changes are delayed by era-accurate communication hardware (landline kiosks, VHF numeric pagers, GSM mobiles), filtered through subordinate agent skim/loyalty, and recorded as aged, smudged entries in the player's perceived Filofax ledger.

---

## 2. Directory Structure

```text
res://
├── systems/                                      # THE DOING CODE (Pure Engine Mechanics)
│   ├── action_base.gd                            # Base class for verbs; subfolder impact discovery
│   ├── verb_router.gd                            # Dynamic verb scanner & alias dispatcher
│   ├── verb_impact_base.gd                       # Interface for action impulse calculations
│   ├── commodity_manager.gd                      # Recursive N-tier JSON ingester & prototype merger
│   ├── condition_evaluator.gd                    # Read-only resource queries & threshold assertion gates
│   ├── order_manager.gd                          # Lifecycle tracker for order slips & historical archiving
│   ├── engine_result.gd                          # Unified result & error reporting object
│   ├── sim_controller.gd                         # Headless turn dispatcher & ambient heartbeat runner
│   └── impacts/                                  # Pure System Metric Plumbing
│       ├── impact_calculator.gd                  # 5 standard mathematical models (Linear, Exp, Log, etc.)
│       ├── impact_router.gd                      # Ingests, registers, and routes deltas to sinks
│       └── impact_sink_base.gd                   # Contract for metric sinks (clamping, state writes)
│
├── data_modules/                                 # THE GUIDING RECORDS & FLAVOR
│   ├── core/                                     # Canonical Baseline / Shared Content
│   │   ├── business_rules.cfg                    # Baseline ledger defaults & game pacing
│   │   ├── verb_mappings.json                    # Action verb aliasing dictionary
│   │   ├── verbs/                                # Canonical Atomic & Macro Actions
│   │   │   ├── order/
│   │   │   │   └── action_order.gd               # Atomic Order: checks funds/stock, creates slip
│   │   │   ├── pay/
│   │   │   │   └── action_pay.gd                 # Atomic Pay: financial settlement
│   │   │   ├── receive/
│   │   │   │   └── action_receive.gd             # Atomic Receive: physical stock transfer
│   │   │   ├── buy/
│   │   │   │   └── action_buy.gd                 # Macro Buy: executes Order -> Pay -> Receive
│   │   │   ├── sell/
│   │   │   │   └── action_sell.gd                # Macro Sell: executes Order -> Receive -> Pay
│   │   │   └── make/
│   │   │       └── action_make.gd                # Macro Make: recipe transformation & cutting
│   │   ├── impacts/                              # Metric Definitions & State Mutators
│   │   │   ├── cash/
│   │   │   │   └── sink_cash.gd                  # State writer for CASH deltas
│   │   │   ├── police_heat/
│   │   │   │   └── sink_heat.gd                  # State writer for POLICE_HEAT & ambient drift
│   │   │   └── worker_fatigue/
│   │   │       └── sink_fatigue.gd               # State writer for WORKER_FATIGUE deltas
│   │   ├── recipes/                              # N-Tier Transformation Recipes
│   │   │   └── tobacco/roll_cigarette/
│   │   │       ├── recipe_profile.json           # Recipe inputs, yield, and tool requirements
│   │   │       └── make/
│   │   │           └── worker_fatigue.json       # Process-level labor fatigue impact
│   │   └── commodities/                          # N-Tier Hierarchical Commodities
│   │       └── consumables/
│   │           ├── tobacco/loose_tobacco/
│   │           │   └── rolling_tobacco/
│   │           │       ├── item_profile.json     # Leaf item definition
│   │           │       └── make/
│   │           │           └── handling_loss.json# Material-specific handling waste impact
│   │           └── other/
│   │               └── rolling_papers.json       # Flat leaf commodity definition
│   │
│   └── crime/                                    # Scenario Variant / Risk Expansion Overlay
│       ├── business_rules.cfg                    # Pacing, heat limits, bail costs
│       ├── recipes/                              # Illicit recipes (e.g. roll_joint/)
│       └── commodities/                          # Illicit commodities (e.g. moroccan_hash/)
│
└── tests/                                        # Headless CLI Verification Suites
    └── test_engine_harness.gd                    # End-to-end headless CLI test harness
```

---

## 3. Core System Files Reference (`res://systems/`)

* **`sim_controller.gd`:** The central orchestrator. Executes incoming directives through `VerbRouter` and triggers global ambient heartbeats across all mounted sinks via `ImpactRouter`. Contains no scenario-specific logic.
* **`verb_router.gd`:** The command switchboard. Automatically crawls `data_modules/<variant>/verbs/` on boot, resolves aliases from `verb_mappings.json` (e.g., `SCORE` $\rightarrow$ `BUY`), and dispatches calls to the appropriate `action_*.gd` script.
* **`action_base.gd`:** Abstract base class for all verbs. Provides shared utilities for compiling commodity impact activations and reading subfolder impacts.
* **`order_manager.gd`:** Manages transaction slips (`ORD_XXXX`). Handles creation in `pending_orders`, status transitions (`ORDERED` $\rightarrow$ `PAID` $\rightarrow$ `DELIVERED`), and final migration to `completed_orders` for forensic history and player ledgers.
* **`condition_evaluator.gd`:** Universal, read-only assertion service. Inspects resource balances (`CASH`, `STOCK`) across the player, staff, or counterparties, and evaluates mathematical gates (`<`, `>`, `==`) without mutating state.
* **`engine_result.gd`:** Standardized outcome payload. Every verb returns an `EngineResult` containing a boolean `success`, `ErrorCode`, human-readable message, transacted quantity, and `impact_deltas`.
* **`commodity_manager.gd`:** Recursive inheritance loader. Crawls directories, deep-merging properties from higher-tier `_base.json` files down to leaf profiles (`item_profile.json`, `recipe_profile.json`, or standalone `<item>.json`) while stripping developer `_meta` blocks. Assembles action subfolder files (`buy/`, `sell/`, `make/`) into runtime `impact_activations`.
* **`impact_calculator.gd`:** Centralized math engine. Evaluates impact magnitudes using 5 standardized calculation models:
  1. `LINEAR_PER_UNIT`: $\Delta = q \cdot k$
  2. `WEIGHTED_PER_UNIT`: $\Delta = (q \cdot k) \cdot M_{\text{env}}$
  3. `EXP_PER_UNIT`: $\Delta = k \cdot (b^q - 1)$ (Punitive runaway volume)
  4. `LOG_PER_UNIT`: $\Delta = k \cdot \ln(1 + q)$ (Diminishing marginal returns)
  5. `STEPPED_PER_UNIT`: $\Delta = \lfloor q / S \rfloor \cdot k$ (Discrete bucket jumps)
* **`impact_router.gd`:** Sinks switchboard. Autoloads `sink_*.gd` scripts from `data_modules/` and routes emitted deltas directly to their matching sink. Dispatches end-of-turn `process_ambient()` calls.
* **`impact_sink_base.gd`:** Contract for systemic metrics. Enforces implementations of `get_metric_key()`, `apply_delta()`, and `process_ambient()`.

---

## 4. Setting Up New Commodities (Step-by-Step)

Adding a trade good is purely a file-drop operation requiring no code changes:

### Step 1: Choose or Create Category Folder
Navigate to `data_modules/<variant>/commodities/` and select or create the appropriate taxonomy path:
```text
data_modules/core/commodities/consumables/alcohol/beer/cider/
```

### Step 2: (Optional) Set Parent Defaults (`_base.json`)
If this is a new subcategory, drop a `_base.json` in the folder to establish shared defaults for all child items:
```json
{
  "_meta": { "tier": 3, "scope": "SUBCAT_CIDER" },
  "unit_type": "PINT",
  "base_cost": 0.90,
  "decay_properties": {
    "shelf_life_ticks": 12,
    "rot_rate_per_tick": 0.05
  }
}
```

### Step 3: Create the Leaf Item Directory & Profile
Create a folder for the specific product (e.g., `vintage_cider/`) and add `item_profile.json`:
```json
{
  "_meta": { "tier": 4, "scope": "LEAF_VINTAGE_CIDER" },
  "id": "CIDER_VINTAGE",
  "display_name": "Oak Aged Vintage Cider",
  "base_cost": 1.40
}
```
*(Note: It inherits `category = "CONSUMABLE"` from Tier 1 and `unit_type = "PINT"` from Tier 3 automatically.)*

### Step 4: Define Verb Impacts
To give the commodity specific consequences when acted upon, create verb subfolders inside the item's directory:

* Create `vintage_cider/sell/police_heat.json`:
```json
{
  "metric": "POLICE_HEAT",
  "model": "LINEAR_PER_UNIT",
  "factor": 0.03
}
```
* Create `vintage_cider/buy/worker_fatigue.json`:
```json
{
  "metric": "WORKER_FATIGUE",
  "model": "STEPPED_PER_UNIT",
  "factor": 2.0,
  "params": { "step_size": 12.0 }
}
```

On next boot, `CommodityManager` crawls the directory, merges the parent properties, attaches the `impact_activations`, and registers `CIDER_VINTAGE` into `world_state["commodity_registry"]` ready for immediate use.

---

## 5. Setting Up New Transformation Recipes

Recipes follow the exact same $N$-tier taxonomy under `data_modules/<variant>/recipes/`:

### Step 1: Create Recipe Folder & Profile
Create the folder path (e.g., `data_modules/core/recipes/tobacco/roll_cigarette/`) and add `recipe_profile.json`:
```json
{
  "_meta": {
    "tier": 3,
    "scope": "RECIPE_ROLL_CIGARETTE"
  },
  "id": "RECIPE_ROLL_CIGARETTE",
  "display_name": "Roll Cigarette",
  "output_item": "CIGARETTE_ROLLUP",
  "output_yield_units": 1.0,
  "required_tool_category": "NONE",
  "inputs": {
    "TOBACCO_ROLLING": 0.8,
    "ROLLING_PAPERS": 1.0
  }
}
```

### Step 2: Define Process Impacts
Add consequences of the physical transformation under the recipe's `make/` subfolder (e.g., `roll_cigarette/make/worker_fatigue.json`):
```json
{
  "metric": "WORKER_FATIGUE",
  "model": "LINEAR_PER_UNIT",
  "factor": 0.10
}
```

### Step 3: Define Ingredient Handling Impacts
If an ingredient itself carries intrinsic hazards (toxic fumes, chemical odors, spillage), place those impacts inside the **commodity's** `make/` subfolder (e.g., `rolling_tobacco/make/handling_loss.json`):
```json
{
  "metric": "MATERIAL_WASTE",
  "model": "LINEAR_PER_UNIT",
  "factor": 0.02
}
```

When `ActionMake` runs:
1. It validates raw inputs via `ConditionEvaluator`.
2. It consumes inputs from `STOCK` and adds the yield to `PREPPED`.
3. It compiles both process-level impacts from the recipe and material-handling impacts from the ingredients, routing them via `ImpactRouter`.

---

## 6. Headless Verification & Testing

The engine is decoupled from Godot's visual scene tree and runs completely headlessly via the command line:

```powershell
# Set executable alias (adjust path to your Godot installation)
Set-Alias godot "L:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"

# Run the complete headless test harness
godot --headless --script res://tests/test_engine_harness.gd
```

### What the Harness Validates:
1. Recursive $N$-tier commodity and recipe inheritance, prototype merging, and `_meta` stripping.
2. Complete economic lifecycle:
   * **`BUY`:** `ActionOrder` $\rightarrow$ `ActionPay` $\rightarrow$ `ActionReceive` (vault cash decr, stock incr).
   * **`MAKE`:** Raw inputs deducted from `STOCK`, finished units added to `PREPPED`, process + ingredient fatigue sunk.
   * **`SELL`:** `ActionOrder` $\rightarrow$ `ActionReceive` $\rightarrow$ `ActionPay` (stock decr, cash incr, heat emitted).
3. Mathematical delta calculations through `ImpactCalculator`.
4. State mutation through `SinkCash`, `SinkPoliceHeat`, and `SinkFatigue`.
5. Immutable order slip migration to `completed_orders`.
6. Ambient tick heartbeats and passive metric dissipation.