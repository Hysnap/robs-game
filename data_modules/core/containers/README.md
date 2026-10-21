Fleshing out **Containers, Quantities, Packages, and Packaging** formalizes how physical bulk commodities transition into standardized, transportable, and retail-ready trade goods.

---

### 1. Conceptual Distinction: The 4 Terms Clarified

To prevent terminology confusion across your codebase, schemas, and UI, here is how the terms delineate:

| Term         | What It Represents in the Simulation                                                   | Architectural Role | Examples |
| ------------ | -------------------------------------------------------------------------------------- | ------------------ | -------- |
| **Quantity** | The numerical magnitude and measurement dimension of an uncontained or contained good. |

| State variable (`float`) paired with `unit_type`.

| `1000.0` (grams), `50.0` (litres), `24.0` (units).

|
| **Container** | The physical vessel, shell, or envelope with rigid or flexible capacity.

| Physical entity/profile (`container_id`) with tare weight, volume capacity, and decay shielding.

| `GLASS_BOTTLE_330ML`, `PAPER_WRAP`, `SEALED_KEG_50L`.

|
| **Packaging** | The operational action, materials, and labor required to marry a commodity into a container.

| Verb operation or recipe stage (`MAKE` / `PACKAGE`) consuming tare containers and labor fatigue.

| Bottling beer, folding wraps, vacuum-sealing bricks.

|
| **Package** | The resulting composite inventory asset (`PackagedGood`) ready for storage or sale.

| Runtime composite state: `Commodity ID` + `Container ID` + `Quantity`.

| 1x `BOTTLE_BEER_330ML`, 100x `1G_STREET_WRAPS`.

|

---

### 2. Directory Architecture

Following your standard 90/10 split:

- **~90% of containers** live in `data_modules/core/containers/` as universal physical formats (bottles, tins, kegs, generic wraps, boxes, crates).

- **~10% of scenario-specific containers** live in variant modules (e.g., `data_modules/crime/containers/` for decoy stash cans, booster bags, or 1g street wraps).

```text
res://data_modules/
├── core/containers/
│   ├── liquid/
│   │   ├── _base.json                     <-- Base liquid sealing & tare baselines
│   │   ├── glass_bottle_330ml.json        <-- Universal 330ml crown-cap bottle
│   │   ├── glass_bottle_750ml.json        <-- Wine / spirit format
│   │   ├── aluminum_can_330ml.json        <-- Standard beverage can
│   │   ├── open_pitcher_1000ml.json       <-- Table service / draught pour (zero seal)
│   │   └── sealed_keg_50l.json            <-- Bulk wholesale draught keg
│   │
│   ├── solid_bulk/
│   │   ├── _base.json
│   │   ├── standard_tin_400g.json         <-- Canned foods, coffee, tobacco
│   │   ├── burlap_sack_25kg.json          <-- Wholesale grain, lemons, sugar
│   │   └── plastic_crate_24slot.json      <-- Secondary transport packaging for bottles
│   │
│   └── flexible_wraps/
│       ├── _base.json
│       ├── paper_packet_small.json        <-- Folded paper wrap (spices, single portions)
│       └── vacuum_mylar_1kg.json          <-- Industrial airtight heat-sealed pouch
│
└── crime/containers/                      <-- Variant tradecraft containers
    ├── wrap_foil_1g.json                  <-- Corner retail wrap (sweat-permeable)
    ├── baggie_gripseal_small.json         <-- Gripseal retail pouch
    └── stash_can_false_bottom.json        <-- Anti-search decoy container

```

---

### 3. Container Schema Blueprint

Each container JSON file defines four primary mechanical dimensions: **Physical Capacity**, **Tare Footprint**, **Environmental Sealing (Decay Modifiers)**, and **Operational OpSec/Tamper Properties**.

#### Example: Universal Liquid Container (`glass_bottle_330ml.json`)

```json
{
  "_meta": {
    "tier": 2,
    "scope": "CONTAINER_GLASS_BOTTLE_330ML",
    "description": "Standard 330ml crown-capped amber glass beverage bottle."
  },
  "id": "CONTAINER_GLASS_BOTTLE_330ML",
  "display_name": "Glass Bottle (330ml)",
  "category": "CONTAINER",
  "accepted_phase": "LIQUID",
  "base_cost": 0.12,

  "capacity": {
    "volume_ml": 330.0,
    "mass_g": 0.0
  },

  "tare_footprint": {
    "empty_mass_g": 190.0,
    "storage_footprint_per_unit": 0.03
  },

  "decay_modifiers": {
    "shelf_life_multiplier": 3.0,
    "rot_rate_multiplier": 0.2,
    "ambient_loss_per_tick": 0.0
  },

  "handling_attributes": {
    "fragility": 0.08,
    "tamper_evident": true,
    "opsec_visibility": 0.1
  }
}
```

#### Example: Street Wrap (`wrap_foil_1g.json` in `crime/`)

```json
{
  "_meta": {
    "tier": 2,
    "scope": "CONTAINER_WRAP_FOIL_1G",
    "description": "Folded foil square for retail street distribution."
  },
  "id": "CONTAINER_WRAP_FOIL_1G",
  "display_name": "Foil Wrap (1g)",
  "category": "CONTAINER",
  "accepted_phase": "SOLID",
  "base_cost": 0.01,

  "capacity": {
    "volume_ml": 0.0,
    "mass_g": 1.5
  },

  "tare_footprint": {
    "empty_mass_g": 0.5,
    "storage_footprint_per_unit": 0.001
  },

  "decay_modifiers": {
    "shelf_life_multiplier": 0.6,
    "rot_rate_multiplier": 1.4,
    "ambient_loss_per_tick": 0.01
  },

  "handling_attributes": {
    "fragility": 0.02,
    "tamper_evident": false,
    "opsec_visibility": 0.45
  }
}
```

---

### 4. How Packaging Operates in the Engine

Packaging is executed via **`ActionMake`** using a recipe that specifies a `target_container`:

```
[ Unpackaged Bulk Stock ] ──► [ Recipe: target_container ] ──► [ Packaged Stock ]
   (e.g., 50L Lager)        (consumes bottles + labor)      (151x 330ml Bottles)

```

#### A. Yield & Batch Resolution Math (`systems/batch_calculator.gd`)

When batching liquids into bottles or dry goods into wraps, the yield is determined by capacity:

$$\text{Glass / Bottle Yield} = \left\lfloor \frac{\text{Total Fluid Produced (ml)}}{\text{Container Volume (ml)}} \right\rfloor$$

$$\text{Dry Wrap Yield} = \left\lfloor \frac{\text{Total Net Mass (g)}}{\text{Container Mass Capacity (g)}} \right\rfloor$$

#### B. Preservation Filter on Ambient Ticks

On the end-of-turn heartbeat, the simulation calculates shrinkage and spoilage by applying the container's modifiers to the commodity's baseline:

$$\text{Effective Rot Rate} = \text{Commodity Rot Rate} \times \text{Container Rot Rate Multiplier}$$

$$\text{Total Lost Units} = (Q \times \text{Effective Rot Rate}) + \text{Ambient Leakage}$$

- A bulk crate of unsealed, loose lemons rots at $100\%$ base speed.

- Lemons packed in `CONTAINER_VACUUM_MYLAR_1KG` rot at $0.05\times$ speed (a $95\%$ reduction in weekly spoilage).

---

### 5. Representation in `world_state["inventory_registry"]`

Uncontained bulk goods and finished packaged goods are cleanly delineated in the runtime inventory state:

```gdscript
world_state["inventory_registry"] = {
    # 1. Raw / Unpackaged Bulk Commodity Lane
    "BEER_STRONG_LAGER": {
        "STOCK": 50.0,            # 50 Litres loose in brewing vat
        "PREPPED": 0.0,
        "container": "NONE"
    },

    # 2. Packaged Retail Product Lane (Composite ID or nested container tag)
    "BEER_STRONG_LAGER::CONTAINER_GLASS_BOTTLE_330ML": {
        "STOCK": 151.0,           # 151 individual ready-to-sell bottles
        "PREPPED": 0.0,
        "commodity_id": "BEER_STRONG_LAGER",
        "container_id": "CONTAINER_GLASS_BOTTLE_330ML",
        "gross_unit_mass_g": 520.0 # 330g liquid + 190g tare glass
    }
}

```

Would you like to build out the `ContainerManager` auto-loader in `systems/` next, or draft the `README.md` and default container profiles for `data_modules/core/containers/`?
