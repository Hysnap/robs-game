# How to add an impact

## Add a data-driven impact

Create a JSON file in the relevant commodity or recipe `buy/`, `sell/`, or
`make/` folder:

```json
{
  "metric": "POLICE_HEAT",
  "model": "LINEAR_PER_UNIT",
  "factor": 0.02,
  "params": {}
}
```

The metric must match a registered sink. A child file with the same metric
replaces its inherited parent impact.

## Add a new sink

1. Create `sink_<name>.gd` under this directory or a variant impacts folder.
2. Extend the existing sink contract and implement `get_metric_key()`,
   `apply_delta()`, and any required `process_ambient()` behavior.
3. Ensure the returned key matches the JSON `metric` exactly.
4. Mount the directory with `ImpactRouter.autoload_sinks()` before testing.

Run `test_catalog_validator.gd` for model references and
`test_engine_harness.gd` or the focused impact test for state mutation.
