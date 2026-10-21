# Core Data Module Specification

The `core/` directory establishes universal baseline archetypes, commodities, recipes, atomic verbs, and systemic impact sinks. Scenario variants inherit and selectively override definitions configured here.

---

## 1. Directory Structure & Folder Notes

Detailed specifications, rules, and local mechanics are colocated directly within their respective folders:

* **commodities/**: Multi-tier taxonomic hierarchies (Consumables, Durables, Services). Contains baseline definitions and leaf products.
* **recipes/**: Transformation recipes, ingredient consumption ratios, output yields, container requirements, and process-level labor impacts.
* **verbs/**: Canonical atomic actions (`order/`, `pay/`, `receive/`) and macro-actions (`buy/`, `sell/`, `make/`). Each verb folder contains its execution script, colocated `feedback.json` outcome matrices, and local action impact definitions.
* **impacts/**: Systemic consequence handlers and metric sinks (`cash/`, `police_heat/`, `worker_fatigue/`). Each subfolder defines bounds, clamping rules, and ambient decay behavior.
* **dialects/**: Vernacular profiles, regional slang replacements, and phrase affixes for procedural memo generation.

---

## 2. Configuration & Mapping Files

### business_rules.cfg
The primary configuration file for baseline runtime diagnostics, starting states, and engine integrity checks:

```ini
[system_diagnostics]
enable_startup_audit = true
write_audit_to_disk = true
strict_halt_on_error = true
```
enable_startup_audit: Toggles automated catalog and recipe integrity sweeps during initialization.
write_audit_to_disk: When true, outputs diagnostic audit findings to user://catalog_audit.log and hierarchy audits to user://n_tier_hierarchy_audit.log.
strict_halt_on_error: When true, aborts engine execution if corrupted references, missing output commodities, or invalid categories are detected on disk.

### verb_mappings.json
Enables core verbs to be referenced by user-friendly, business-specific, or situational aliases:

JSON
{
  "RESTOCK": "BUY",
  "MARKET": "SELL",
  "MANUFACTURE": "MAKE",
  "PROCURE": "ORDER",
  "SETTLE": "PAY",
  "UNLOAD": "RECEIVE"
}
The engine dispatches actions using the resolved canonical verb while allowing UI dropdowns, scenario scripts, and ledger records to use natural thematic terms.

Scenario variants can provide their own verb_mappings.json to introduce domain-specific jargon without modifying underlying action scripts.