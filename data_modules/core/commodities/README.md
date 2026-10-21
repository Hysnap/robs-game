Here is the comprehensive, enhanced `README.md` for `res://data_modules/core/commodities/`, integrating the core category archetypes, the file taxonomy, action-to-impact attachment mechanics, and mathematical velocity curves.

---

# Core Commodities Architecture

This directory establishes the baseline taxonomies and leaf item specifications for all trade goods and operational resources in the simulation.

---

## 1. High-Level Archetypes

Top-level subdirectories establish fundamental physical behavior and lifecycle rules:

| Category Folder | Canonical Token | Economic State & Lifecycle Behavior | Storable? |
| --- | --- | --- | --- |
| `consumables/` | `CONSUMABLE` | Physical goods that degrade, rot, or are destroyed/depleted upon use (e.g. tobacco, beverages, raw ingredients, medical supplies). Moves through `STOCK` $\rightarrow$ `PREPPED` $\rightarrow$ Sold/Used.

 | Yes

 |
| `durables/` | `DURABLE` | Reusable physical capital assets and equipment that do not disappear upon use but incur mechanical wear-and-tear or breakdown risk (e.g. pill presses, scales, delivery vehicles, brewing vats).

 | Yes

 |
| `services/` | `SERVICE` | Intangible agreements, professional retainers, legal counsel, or labor shifts. Consumed instantly or renewed per simulation tick; cannot sit in physical storage bins.

 | No

 |

---

## 2. File Organization & Naming Rules

Every directory level represents a tier in the $N$-tier cascade. Files must follow strict naming conventions:

| What Are You Making? | Location | File Name | `"id"` Field Required? |
| --- | --- | --- | --- |
| **Category / Family Baseline** | Any folder tier (e.g. `tobacco/`, `beer/`)

 | `_base.json`<br> | **NO** (Inherited template only)

 |
| **Simple Leaf Item** (No custom verb impacts) | Parent category folder (e.g. `consumables/`)

 | `[item_name].json` (e.g. `rolling_papers.json`)

 | **YES** (`SCREAMING_SNAKE_CASE`)

 |
| **Complex Leaf Item** (Has `buy/`, `sell/`, `make/`) | Dedicated product folder (e.g. `strong_lager/`)

 | `item_profile.json`<br> | **YES** (`SCREAMING_SNAKE_CASE`)

 |

> **Naming Guardrail:** Never place `[item_name].json` directly inside a folder named `[item_name]/` alongside subfolder action impacts. The entity descriptor in a dedicated folder must always be named `item_profile.json`.
> 
> 

---

## 3. How to Attach Impacts to Commodities

Rather than hardcoding consequences into verb scripts, **consequences are attached to commodities using verb subfolders**. When an action runs (e.g. `BUY`, `SELL`, `MAKE`), the engine evaluates that verb's subfolder inside the commodity directory.

### Directory Layout Example

```text
res://data_modules/core/commodities/consumables/alcohol/beer/strong_lager/
  ├── item_profile.json               <-- Core pricing, name, and unit defs
  ├── buy/                            <-- Consequences when BUY acts on this
  │     │                                    commodity
  │     └── worker_fatigue.json       <-- Handling / lifting strain[cite: 9]
  ├── sell/                           <-- Consequences when SELL acts on this 
  │     │                                    commodity
  │     ├── police_heat.json          <-- Surveillance & enforcement risk
  │     └── zone_health.json          <-- Neighborhood stability erosion
  └── make/                           <-- Material hazards when MAKE 
        │                                    processes this input
        └── toxic_fumes.json          <-- Chemical/burn hazards to 
                                            the operator

```

### Impact File Structure

Each impact JSON file represents an individual consequence sink:

```json
{
  "metric": "POLICE_HEAT",
  "model": "LINEAR_PER_UNIT",
  "factor": 0.04,
  "params": {}
}

```

* **`metric`**: Target sink registered in `ImpactRouter` (e.g. `POLICE_HEAT`, `WORKER_FATIGUE`, `ZONE_HEALTH`, `UNPAID_RECEIVABLES`).


* **`model`**: Standard calculation curve evaluated by `ImpactCalculator`.


* **`factor`**: Base numerical scalar applied per transacted unit. Positive numbers increase the metric; negative numbers decrease it.


* **`params`**: Optional curve configuration parameters (e.g. exponents, step thresholds).



---

## 4. Supported Calculation Models

`ImpactCalculator` evaluates quantitative impact deltas based on 5 standardized mathematical archetypes:

| Model | Formula | Behavior & Best Use Cases |
| --- | --- | --- |
| `LINEAR_PER_UNIT`<br> | $\Delta = q \cdot k$<br> | Steady, direct accumulation. Ideal for standard retail turnover, straightforward handling fatigue, or wholesale volume. |
| `WEIGHTED_PER_UNIT`<br> | $\Delta = (q \cdot k) \cdot M_{\text{env}}$<br> | Proportional delta scaled by an environmental multiplier passed in runtime context (e.g. district density, police alert level, active operational opsec). |
| `EXP_PER_UNIT`<br> | $\Delta = k \cdot (b^q - 1)$<br> | Exponential compounding. Small batches cause negligible fallout, but large transactions trigger rapid consequence spikes (e.g. moving massive illicit supply that alerts task forces). Configured with `params.exponent_base`.
| `LOG_PER_UNIT`<br> | $\Delta = k \cdot \ln(1 + q \cdot r)$<br> | Diminishing marginal returns. The first few units yield noticeable changes, but subsequent volume tapers off (e.g. customer reputation, market discovery). Configured with `params.log_scale`.
| `STEPPED_PER_UNIT`<br> | $\Delta = \lfloor q / S \rfloor \cdot k$<br> | Discrete threshold jumps. Emits no delta until a threshold `step_size` $S$ is reached, then steps up in increments (e.g. courier pack capacity, carton shrinkage, pallet fatigue). Configured with `params.step_size`.|

---

## 5. Cascading $N$-Tier Inheritance Rules

Impact folders and `_base.json` files cascade downward through the directory tree:

1. **High-Tier Inheritance:** If `consumables/buy/worker_fatigue.json` is set at the category root, **all** consumables automatically generate worker fatigue on purchase without requiring duplicate files in every subfolder.


2. **Category Layering:** If `alcohol/sell/police_heat.json` is defined at Tier 2, all beers, wines, and spirits inherit police heat when sold.


3. **Leaf Overrides:** If `strong_lager/sell/police_heat.json` exists in the leaf directory, it cleanly **overwrites** the higher-level alcohol heat factor.


4. **Impact Additions:** Adding `strong_lager/sell/zone_health.json` appends local social decay to the existing inherited consequences.



---

## 6. Distinction: Process Impacts vs. Ingredient Impacts

When configuring production via `make/`:

* **Recipe Impacts (`recipes/.../make/`):** Define consequences caused by the **transformation process or machinery** (e.g. mechanical vat wear, base operator strain). These are independent of specific ingredients used.


* **Ingredient Impacts (`commodities/.../make/`):** Define consequences caused by the **materials themselves** (e.g. chemical odor leaking heat, caustic acid fumes causing stress, handling spillage). These scale dynamically against the quantity of that specific ingredient consumed by the recipe.