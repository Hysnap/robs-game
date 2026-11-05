# How to add a commodity

1. Add or reuse a lowercase taxonomy path.
2. Add inherited defaults in `_base.json`, or create a leaf
   `item_profile.json`. A flat leaf may instead be a standalone JSON file in
   its parent directory.
3. Provide a unique uppercase `id`, `display_name`, `category`, and the
   fields needed by the action that will use the item.
4. Add `buy/`, `sell/`, or `make/` impact files only when the item has a
   consequence. Each file must contain `metric`, a supported `model`, and a
   numeric `factor`.

Example:

```text
commodities/consumables/foods/new_food/item_profile.json
commodities/consumables/foods/new_food/sell/police_heat.json
```

Loaders treat `_base.json` as inheritance, skip `_meta`, and register the
profile ID. Validate the result:

```powershell
godot --headless --path . --script res://tests/test_catalog_validator.gd
godot --headless --path . --script res://tests/test_hierarchy_audit.gd
```

If the item is used by a recipe, run `test_engine_harness.gd` as well.
