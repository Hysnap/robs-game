# How to add a container

1. Choose the appropriate lowercase path beneath `containers/`.
2. Add a profile JSON or a directory with `item_profile.json`.
3. Set `id`, `display_name`, `category: "CONTAINER"`, `capacity`, and
   `tare_footprint`. Keep `decay_modifiers` and `handling_attributes` shaped
   like existing profiles when those behaviors apply.
4. Add shared defaults to `_base.json` only if every descendant should inherit
   them.

The catalog loader registers the profile, but there is no automatic
package-composition operation. Test capacity, tare, and decay assumptions with:

```powershell
godot --headless --path . --script res://tests/test_container_decay_pipeline.gd
```

Also run `test_catalog_validator.gd` when the profile is intended to be part
of a commodity or recipe workflow.
