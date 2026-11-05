# How to add society configuration

Society JSON modules are not discovered by directory scanning. Add the file's
`res://` path to the active manifest's `modules` dictionary, then use the
module key from `ScenarioManifestManager.load_module()`.

Keep the root object a dictionary and preserve the shape expected by the
consumer. For example, demographic records are read by
`TaxonomyHarvester`, while job and building records are validated by
`CatalogValidator` and consumed by the society builders.

After adding or changing a module:

```powershell
godot --headless --path . --script res://tests/test_manifest_loader.gd
godot --headless --path . --script res://tests/test_full_system_audit.gd
```

The manifest loader fails explicitly for missing files, malformed JSON,
missing `modules`, or unregistered module keys.
