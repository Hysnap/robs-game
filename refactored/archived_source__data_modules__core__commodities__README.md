# Commodities

`CommodityManager.load_hierarchical_commodities()` recursively loads this
directory into `world_state["commodity_registry"]`.

## File forms

* `_base.json` supplies inherited defaults and has no registry entry.
* A standalone file such as `rolling_papers.json` is a flat leaf item.
* A directory leaf uses `item_profile.json`.
* `buy/`, `sell/`, and `make/` contain impact JSON files with `metric`,
  `model`, `factor`, and optional `params`.

Directories inherit from their ancestors. Child properties deep-merge parent
properties. `_meta` is documentation only and is removed during merging.
The profile `id` is uppercased for the registry key. Impact folders are not
treated as taxonomy levels.

Common profile properties include `id`, `display_name`, `category`,
`base_cost`, `unit_type`, `can_be_stored`, `storage_footprint_per_unit`, and
`decay_properties`. Use the fields already present in the relevant branch;
the validator checks category values and impact calculation models.

See [HOWTOADD.md](HOWTOADD.md) for a complete item and impact example.
