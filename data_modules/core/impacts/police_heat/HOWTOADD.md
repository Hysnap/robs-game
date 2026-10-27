# How to tune police heat

`profile.json` contains the data profile for this metric and `rules.cfg`
contains the threshold and recovery values read by the heat sink. Preserve
the existing section and key names; changing a key requires a corresponding
code change in the owning sink.

After changing either file, run the catalog validator and the focused action
test that emits `POLICE_HEAT`:

```powershell
godot --headless --path . --script res://tests/test_catalog_validator.gd
godot --headless --path . --script res://tests/test_engine_harness.gd
```
