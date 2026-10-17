# Decision & Response Simulation Engine

A data-driven, turn-based economic and operational simulation engine built for **Godot 4.x (GDScript)**.

The engine uses a strict separation between **Mechanics** (pure execution scripts), **Flavour & Archetypes** (hierarchical data modules), and **Perception** (a dual-layer imperfect information model modeling asynchronous physical communication).

---

## 1. Core Architecture Principles

1. **The Pure Doing Code (`systems/`)**
   The execution engine contains zero narrative or scenario assumptions. It does not know whether it is simulating commercial retail, supply chains, or street-level distribution. It operates strictly on abstract dictionaries, action command verbs, and mathematical delta sinks.

2. **The Content & Flavor Modules (`data_modules/`)**
   Scenarios, trade goods, production recipes, and consequence weights live entirely within configuration trees. The default rules reside in `data_modules/core/`. Changing or modding scenarios (e.g., from legal trade to an illicit economy) is achieved by pointing the loader to an alternative module folder without modifying engine code.

3. **$N$-Tier Commodity Inheritance (Taxonomic Cascade)**
   Commodities are classified into **Consumables**, **Durables**, and **Services**. Subdirectories automatically inherit and override properties defined in adjacent `_base.json` templates, allowing deep cascades (e.g., `consumables/alcohol/beer/strong_lager.json`) with minimal boilerplate.

4. **Action Calculation vs. Impact Sinks**

- **Verbs (`action_*.gd`)** control transaction logic, stock constraints, pricing, and throughput.

- Verbs automatically query their private `impacts/` subfolder, passing the commodity's velocity matrix to compile discrete `impact_deltas`.

- **Global Sinks (`SimController`)** receive these deltas and mutate the objective state.

5. **Dual-Trigger Consequence Contract**
   Consequences are triggered via two paths:

- **Action Impulse:** Discrete deltas created immediately when an action runs (e.g., `SELL` creates police heat).

- **Ambient Pulse:** An end-of-turn heartbeat where the environment acts on itself (e.g., passive heat dissipation, customer panic, zone health degradation, and inventory shrinkage).

6. **Dual-Layer Reality (Objective Truth vs. Filofax Cache)**
   The player never inspects true state directly. State changes are delayed by era-accurate communication hardware (landline kiosks, VHF numeric pagers, GSM mobiles), filtered through subordinate agent skim/loyalty, and recorded as aged, smudged entries in the player's perceived Filofax ledger.

---

## 2. Directory Structure

```text
res://
├── systems/                                      # THE DOING CODE (Pure Engine Mechanics)
│   ├── action_base.gd                            # Base class for verbs; scans subfolder impacts
│   ├── verb_impact_base.gd                       # Interface for dual-trigger impacts (action + ambient)
│   ├── commodity_manager.gd                      # Recursive N-tier JSON ingester & prototype merger
│   ├── sim_controller.gd                         # Headless turn dispatcher & impact sink router
│   └── city_spatial_adapter.gd                   # Decoupled bridge to CityCrafter / spatial meshes
│
├── data_modules/                                 # THE GUIDING RECORDS & FLAVOR
│   ├── core/                                     # Canonical Baseline / Shared Content
│   │   ├── business_rules.cfg                    # Baseline ledger defaults & game pacing
│   │   ├── verb_mappings.json                    # Action verb aliasing dictionary
│   │   ├── pipeline_blueprint.json               # Default automated schedule pipeline
│   │   ├── verbs/                                # Canonical Atomic Actions
│   │   │   ├── buy/
│   │   │   │   ├── action_buy.gd                 # Procurement logic & liquidity checks
│   │   │   │   └── impacts/                      # Impacts local to BUY
│   │   │   ├── sell/
│   │   │   │   ├── action_sell.gd                # Retail execution & revenue calculations
│   │   │   │   └── impacts/                      # Impacts local to SELL (heat, bad debt, ZHI)
│   │   │   └── make/
│   │   │       ├── action_make.gd                # Batch processing & recipe yields
│   │   │       └── impacts/                      # Impacts local to MAKE (worker fatigue, waste)
│   │   └── commodities/                          # N-Tier Hierarchical Commodities
│   │       ├── consumables/                      # Perishables, single-use, batch goods
│   │       │   ├── _base.json                    # Tier 1 Consumables Archetype
│   │       │   └── alcohol/
│   │       │       ├── _base.json                # Tier 2 Alcohol Category
│   │       │       └── beer/
│   │       │           ├── _base.json            # Tier 3 Beer Subcategory
│   │       │           └── strong_lager.json     # Tier 4 Leaf Item
│   │       ├── durables/                         # Tools, machinery, vehicles, persistent assets
│   │       │   └── _base.json
│   │       └── services/                         # Intangibles, legal retainers, contracted muscle
│   │           └── _base.json
│   │
│   └── illicit_market/                           # Scenario Variant / Risk Expansion Overlay
│       ├── business_rules.cfg                    # Street pacing, bail rates, laundering caps
│       └── commodities/                          # Illicit commodities & cut-ratio profiles
│
└── tests/                                        # Headless CLI Verification Suites
    └── test_engine_harness.gd                    # End-to-end headless CLI test harness

```

---

## 3. Data Ingestion & Inheritance Flow

### Commodity Cascading Schema

When loading a leaf item such as `strong_lager.json`, `CommodityManager` performs a top-down recursive merge:

1. Ingests `consumables/_base.json` (Sets `category = "CONSUMABLE"`, decay physics, storage footprints).

2. Merges `alcohol/_base.json` (Appends licensing tags and excise duty exposure).

3. Merges `beer/_base.json` (Sets draught serving units, shelf-life rot rates).

4. Merges `strong_lager.json` (Sets final unit cost, intoxication index, and verb impact velocities).

5. Strips all developer documentation headers (`_meta`) from memory.

### Impact Velocity Matrix

Every commodity defines how it reacts when targeted by specific actions:

```json
"impact_velocities": {
  "BUY": {
    "WORKER_FATIGUE": 0.02
  },
  "SELL": {
    "POLICE_HEAT": 0.05,
    "ZONE_HEALTH_EROSION": 0.08
  }
}

```

---

## 4. Headless Verification & Testing

The engine is decoupled from Godot's visual scene tree and can be validated entirely via the command line:

```bash
# Run the complete decision & response simulation harness
godot --headless --script res://tests/test_engine_harness.gd

```

The harness tests:

- Recursive commodity inheritance and tag cascading.
- Verb execution (`ActionSell`) and liquid cash adjustments.

- Local impact calculation and state sinking (`POLICE_HEAT`, `ZONE_HEALTH_INDEX`).

- Ambient heartbeat ticks and passive metric decay.

---

## 5. Development Workflow Rules

- **Adding a Commodity:** Create a new `.json` file inside the appropriate category path under `data_modules/<variant>/commodities/`. The engine auto-discovers it on boot.

- **Modifying Balancing:** Tweak velocity constants in the corresponding `.json` or `_base.json` file. Do not hardcode rates in `.gd` scripts.

- **Adding an Impact to an Action:** Drop a new script extending `VerbImpactBase` into `data_modules/core/verbs/<action>/impacts/`. The verb will pick it up automatically.

- **Removing an Impact:** Delete or disable the impact script in the verb's subfolder. The engine will skip it with zero missing-reference errors.
