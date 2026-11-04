# How to add a consumable recipe

1. Create a lowercase recipe directory under the relevant branch.
2. Add `recipe_profile.json` with `id`, `display_name`, `output_item`,
   positive `output_yield_units`, and positive input quantities.
3. Ensure every input and the output are existing commodity IDs. The catalog
   validator rejects unresolved references.
4. Add process impacts beneath the recipe's `make/` directory. Put
   ingredient-specific impacts beneath the ingredient commodity's `make/`
   directory instead.

Example layout:

```text
recipes/consumables/example/recipe_profile.json
recipes/consumables/example/make/worker_fatigue.json
```

Run:

```powershell
godot --headless --path . --script res://tests/test_catalog_validator.gd
godot --headless --path . --script res://tests/test_engine_harness.gd
```
