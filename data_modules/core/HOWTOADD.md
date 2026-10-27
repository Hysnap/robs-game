# How to add core configuration

`business_rules.cfg` controls runtime settings and selects the active society
manifest. Preserve the existing section names and types. In particular,
`[society] manifest_path` must point to an existing JSON file whose root has a
`modules` dictionary.

`verb_mappings.json` maps user-facing uppercase aliases to canonical verb
tokens, for example `"RESTOCK": "BUY"`. It does not create an action; the
target action must already be mounted by `VerbRouter`.

After changing either file, run:

```powershell
godot --headless --path . --script res://tests/test_manifest_loader.gd
godot --headless --path . --script res://tests/test_verbs_feedback_integration.gd
```

For changes to the manifest's society modules, also run
`res://tests/test_full_system_audit.gd`.
