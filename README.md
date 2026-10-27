# RobsGame

RobsGame is a Godot 4.7, data-driven, turn-based economic and society
simulation. GDScript in `systems/` performs generic operations; JSON and CFG
files under `data_modules/` provide the scenario, catalog, and narrative data.

## Project layout

```text
systems/                         Runtime services and simulation mechanics
data_modules/core/               Active baseline catalog and 1980s Midlands data
data_modules/shared/             Shared feedback data
data_modules/crime/              Optional scenario overlay data
scenes/                          Godot scenes and UI controllers
addons/                          CityCrafter and godot-sqlite plugins
resources/                       Godot resources, including city configuration
tests/                            Headless SceneTree verification scripts
```

The active scenario is selected by
`data_modules/core/business_rules.cfg`. Its `[society] manifest_path` points
to `data_modules/core/spatial/society/society_manifest_1980s_midlands.json`,
which in turn registers the demographic, civic, building, job, name, and city
configuration modules.

## Runtime data flow

### Catalogs

`systems/commodity_manager.gd` recursively loads commodities, containers, and
recipes. A directory may contain:

* `_base.json` for inherited defaults;
* `item_profile.json` for a directory-based item;
* `recipe_profile.json` for a recipe; or
* a standalone JSON file for a flat item.

The loader deep-merges parent data, ignores `_meta`, and collects JSON files
inside `buy/`, `sell/`, and `make/` folders as `impact_activations`. Child
impact files replace a parent impact with the same metric and append new
metrics.

### Actions and impacts

`systems/verb_router.gd` discovers `action_*.gd` scripts under
`data_modules/core/verbs/`, then applies aliases from `verb_mappings.json`.
Optional variant verbs and aliases can overlay the core registry.

Actions return `EngineResult` data. They calculate deltas but do not own global
metric state. `systems/impacts/impact_router.gd` discovers `sink_*.gd` scripts
under a data-module impacts directory and dispatches action deltas and ambient
ticks to the matching sink.

### Society data

`systems/scenario_manifest_manager.gd` reads the CFG-selected manifest, checks
that each registered file exists, parses JSON dictionaries, and caches modules.
`systems/taxonomy_harvester.gd` turns manifest content into normalized labels.
`systems/db_manager.gd` stores those labels and generated society data in the
SQLite database at `user://game_society.db`.

## Adding data

Start with the guide closest to the data you are changing:

* [data_modules/HOWTOADD.md](data_modules/HOWTOADD.md) - choose an authoring area
* [data_modules/core/commodities/HOWTOADD.md](data_modules/core/commodities/HOWTOADD.md)
  - add catalog items and inherited impacts
* [data_modules/core/containers/HOWTOADD.md](data_modules/core/containers/HOWTOADD.md)
  - add container profiles
* [data_modules/core/recipes/consumables/HOWTOADD.md](data_modules/core/recipes/consumables/HOWTOADD.md)
  - add recipes and process impacts
* [data_modules/core/verbs/HOWTOADD.md](data_modules/core/verbs/HOWTOADD.md)
  - add an action script and feedback
* [data_modules/core/impacts/HOWTOADD.md](data_modules/core/impacts/HOWTOADD.md)
  - add metric sinks and impact definitions
* [data_modules/core/dialects/HOWTOADD.md](data_modules/core/dialects/HOWTOADD.md)
  - add a narrative dialect
* [data_modules/core/spatial/society/HOWTOADD.md](data_modules/core/spatial/society/HOWTOADD.md)
  - add manifest modules and society records

## Verification

Run tests with the Godot executable available on the machine:

```powershell
godot --headless --path . --script res://tests/test_catalog_validator.gd
godot --headless --path . --script res://tests/test_manifest_loader.gd
godot --headless --path . --script res://tests/test_container_decay_pipeline.gd
godot --headless --path . --script res://tests/test_engine_harness.gd
```

For changes affecting generated society data, also run
`res://tests/test_full_system_audit.gd`. Tests are `SceneTree` scripts and
terminate themselves after printing their result. A clean catalog audit is
required before using a new item or recipe in a directive.

## Requirements

* Godot 4.7 with the Forward Plus renderer
* The enabled `godot-sqlite` plugin for database-backed society tests
* The enabled `citycrafter` plugin for city generation features
