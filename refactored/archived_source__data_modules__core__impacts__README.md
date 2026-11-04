# Impact sinks and rules

This directory contains concrete metric sinks. `ImpactRouter.autoload_sinks()`
recursively discovers scripts named `sink_*.gd`; each script exposes a metric
key, applies action deltas, and may process an ambient tick. The engine sinks
currently include cash, heat, fatigue, time, waste, inventory, employment,
income, intoxication, scrutiny, and migration-related handlers.

JSON impact definitions live with the commodity or recipe that emits them.
They use `metric`, `model`, `factor`, and optional `params`. The supported
models are provided by `ImpactCalculator`: `LINEAR_PER_UNIT`,
`WEIGHTED_PER_UNIT`, `EXP_PER_UNIT`, `LOG_PER_UNIT`, and
`STEPPED_PER_UNIT`.

Some sinks have a sibling `rules.cfg` for thresholds or recovery. CFG files
are read by the sink that owns them; adding a CFG section does not register a
new sink. See [HOWTOADD.md](HOWTOADD.md).
