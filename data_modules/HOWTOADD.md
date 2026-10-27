# How to add data

1. Choose the narrowest module directory:
   * catalog item or container: `core/commodities/` or `core/containers/`;
   * recipe: `core/recipes/`;
   * action: `core/verbs/`;
   * metric sink: `core/impacts/`; or
   * society module: `core/spatial/society/`.
2. Follow that directory's `HOWTOADD.md`.
3. Keep IDs uppercase with underscores and paths/files lowercase with
   underscores. Put explanatory metadata in `_meta`; it is not runtime data.
4. For a society JSON file, add its `res://` path to the active manifest's
   `modules` object. A file that is not registered is not available through
   `ScenarioManifestManager`.
5. Run the smallest relevant headless test, then the catalog or full audit if
   the change crosses module boundaries.

Do not edit generated `.godot` files or `user://` database files as part of a
data change.
