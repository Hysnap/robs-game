# Core Data Architecture Specification

## 1. Commodity and Recipe Hierarchy Checklist

| What are you making? | Folder Name | File Name inside |
| --- | --- | --- |
| Category / Family Baseline | Category name (e.g. beer/) | _base.json |
| Simple Leaf Item (No custom verb folders) | No folder needed | [item_name].json (e.g. rolling_papers.json) |
| Complex Leaf Item (Has buy/, sell/, etc.) | Item name (e.g. strong_lager/) | item_profile.json |
| Recipe (Has make/ impacts) | Recipe name (e.g. roll_cigarette/) | recipe_profile.json |

> **Folder Placement Rule:** Never place an item file named `[item_name].json` directly inside a folder also named `[item_name]/` alongside `_base.json` or subfolder impacts. In a dedicated folder, the entity profile must always be named `item_profile.json` (or `recipe_profile.json`) so the loader recognizes it as the entity descriptor.

---

## 2. Metadata Conventions

* **_meta Block:** Keys nested under `_meta` are strictly developer documentation (schema versions, tier tracking, author notes). They are discarded during ingestion and are never evaluated by simulation logic.
* **Identifiers (id):** Technical tokens (`id`, `metric`, `model`, `unit_type`) must always be **SCREAMING_SNAKE_CASE**.
* **Filesystem:** Directory names and filenames must always be **lowercase_snake_case**.
* **Categories:** Must be **singular** and uppercase (e.g. CONSUMABLE, DURABLE, SERVICE).

---

## 3. Catalog Properties Reference

| Property | Use and Notes |
| --- | --- |
| id | Unique technical token in SCREAMING_SNAKE_CASE (e.g. ROLLING_TOBACCO). Never exists in _base.json files. |
| display_name | Player-facing label displayed in the Filofax ledger and UI interfaces. |
| base_cost | Baseline unit cost in standard currency at period start; subject to inflation and market modifiers. |
| can_be_stored | Boolean (true/false) indicating if the item can be stored in inventory or warehouse containers. |
| category | High-level commodity classification (CONSUMABLE, DURABLE, SERVICE). Must be singular and uppercase. |
| storage_footprint_per_unit | Volume or cubic capacity occupied per unit; used by inventory and transport capacity limits. |
| unit_type | Standard measurement unit token (e.g. UNIT, GRAM, PACK, BOTTLE, PINT). |
| tags | Array of categorical classification flags (e.g. ["REGULATED", "AGE_RESTRICTED", "EXCISE_DUTY"]). |
| decay_properties | Grouped dictionary for product degradation and shelf life mechanics. |
| decay_properties.shelf_life_ticks | Number of simulation ticks product quality remains stable before decaying. |
| decay_properties.rot_rate_per_tick | Rate per tick at which item quality decays after exceeding shelf life. |
| decay_properties.degrades_to | Target commodity ID this item turns into upon full degradation (e.g. SPOILED_CONSUMABLES). |
| decay_properties.quantity_change_on_degrade | Multiplier or percentage adjustment to quantity/mass upon reaching degraded state. |
| decay_properties.params | Optional parameters configuring decay formulas evaluated by simulation systems. |
| metric | Target metric sink modified by an impact (e.g. POLICE_HEAT, WORKER_FATIGUE, ZONE_HEALTH). |
| model | Mathematical calculation model evaluated by ImpactCalculator (LINEAR_PER_UNIT, EXP_PER_UNIT, etc.). |
| factor | Base numeric scalar/multiplier applied to the delta per transacted unit. |
| params | Mathematical arguments passed to ImpactCalculator (e.g. step_size, exponent_base). |

---

## 4. Colocated Documentation

Detailed explanations of specific sub-mechanics, schemas, and usage examples are maintained directly within their respective directories:

* **Dialect lexicons and token replacement rules**: See `res://data_modules/core/dialects/`
* **Metric sink clamping, ambient decay, and state mutation**: See `res://data_modules/core/impacts/`
* **Input-to-output conversions, tool wear, and recipe curves**: See `res://data_modules/core/recipes/`
* **Execution preconditions, order slips, and verb lifecycle**: See `res://data_modules/core/verbs/`