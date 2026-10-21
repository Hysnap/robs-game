# Core Transformation Recipes Specification

The `recipes/` directory establishes the manufacturing blueprints, resource transformation formulas, input-to-output ratios, and process-level labor/tool wear consequences for the simulation.

Recipes are loaded hierarchically by `CommodityManager` on engine boot and registered into `world_state["recipe_registry"]`.

---

## 1. Directory Structure & Naming Rules

Recipes follow the exact same $N$-tier cascading directory architecture as commodities:

- **Category / Family Baselines:** Any folder level can contain a `_base.json` defining shared input defaults, tool requirements, or baseline labor fatigue.
- **Leaf Recipe Folders:** Every distinct recipe transformation resides in its own folder named after the process in `lowercase_snake_case`.
- **Profile File:** The transformation definition inside that folder must be named **`recipe_profile.json`**.
- **Action Subfolder:** Process-level consequences caused by the execution of the recipe reside in a **`make/`** subfolder.

```text
res://data_modules/core/recipes/
  └── consumables/
        ├── _base.json                          <-- Tier 1 Archetype (General
                                                    batch yield & tool rules)
        └── tobacco/
              └── roll_cigarette/               <-- Leaf Recipe Folder
                    ├── recipe_profile.json     <-- Transformation
                                                    parameters & inputs
                    └── make/                   <-- Process-level consequences
                          └── worker_fatigue.json

```

---

## 2. Recipe Profile Schema (`recipe_profile.json`)

```json
{
  "_meta": {
    "tier": 3,
    "scope": "RECIPE_ROLL_CIGARETTE",
    "description": "Manual assembly of a single hand-rolled tobacco cigarette."
  },
  "id": "RECIPE_ROLL_CIGARETTE",
  "display_name": "Roll Cigarette",
  "output_item": "CIGARETTE_ROLLUP",
  "output_yield_units": 1.0,
  "required_tool_category": "NONE",
  "target_container": "NONE",
  "inputs": {
    "TOBACCO_ROLLING": 0.8,
    "ROLLING_PAPERS": 1.0
  }
}
```

### Property Reference

| Property                 | Format / Type                 | Purpose & Notes                                                                                       |
| ------------------------ | ----------------------------- | ----------------------------------------------------------------------------------------------------- |
| `id`                     | `SCREAMING_SNAKE_CASE` String | Unique recipe identifier used by directives (e.g. `RECIPE_ROLL_CIGARETTE`). Never in `_base.json`.    |
| `display_name`           | Natural Title String          | Human-readable label displayed on workbenches, order forms, and UI cards.                             |
| `output_item`            | `SCREAMING_SNAKE_CASE` String | Target commodity ID yielded by this recipe. **Must exist in `commodity_registry**`.                   |
| `output_yield_units`     | Positive Float                | Number of finished units produced per single batch execution.                                         |
| `inputs`                 | Dictionary (`ID: Quantity`)   | Key-value pairs of required ingredients consumed per batch. Keys must exist in `commodity_registry`.  |
| `required_tool_category` | String                        | Durable equipment category required in operational inventory (e.g. `BREW_VAT`, `PILL_PRESS`, `NONE`). |
| `target_container`       | String                        | Container ID required to package output units (e.g. `GLASS_BOTTLE_330ML`, `PAPER_WRAP`, `NONE`).      |

---

## 3. Critical Separation: Process Impacts vs. Ingredient Impacts

Consequences emitted during a `MAKE` directive originate from two separate sources:

### A. Process Impacts (Lives in `recipes/.../make/`)

Defines the consequences of the **transformation method itself**, regardless of what materials are used:

- Mechanical wear-and-tear on equipment (e.g. vat breakdown, blade dulling).
- Baseline operator physical exertion and fatigue from manual labor.
- Scaled by the **number of batches** processed.

### B. Ingredient Impacts (Lives in `commodities/.../make/`)

Defines the consequences of the **materials and chemical properties**:

- Toxic vapor emissions, acid burns, or odor leaking police heat.
- Physical shred/spillage loss during handling.
- Scaled by the **exact quantity of that specific ingredient consumed**.

> **Example:** Pressing lemons into juice causes base fatigue (from the recipe) but zero toxic odor. Boiling precursor acid in the exact same equipment emits pungent chemical fumes (defined in the chemical's `make/chemical_odor_heat.json`) that trigger `POLICE_HEAT`.

---

## 4. Execution Lifecycle (`ActionMake`)

When `ActionMake` executes a recipe directive:

1. **Assertion Sweep:** Queries `ConditionEvaluator.has_sufficient_resource()` to ensure the actor possesses all required input materials in `STOCK`.
2. **Resource Transfer:** Input materials are deducted from `STOCK`. Finished output units are deposited into `PREPPED`.
3. **Consolidated Delta Gathering:**

- Evaluates process-level impact rules from `recipe["impact_activations"]["MAKE"]`.
- Iterates through `inputs`, evaluates material impact rules from `commodity["impact_activations"]["MAKE"]`, and scales them by the consumed quantity.

4. **Dispatch:** Emits an `EngineResult` containing the combined deltas to `ImpactRouter`.

```


```
