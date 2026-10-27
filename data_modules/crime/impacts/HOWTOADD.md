# How to add crime impact configuration

Crime impacts are an optional overlay. Place a new `sink_*.gd` handler or a
commodity/recipe impact JSON in the matching lowercase directory. The core
runtime does not mount this overlay unless the caller explicitly passes its
path to `ImpactRouter.autoload_sinks()` or loads the variant through the
relevant router.

For threshold and recovery tuning, update the local `rules.cfg` using the
existing section and key names. Do not assume a new CFG key is consumed until
the owning sink reads it.

Validate JSON and supported impact models with the core catalog validator,
then run the focused action test for the scenario that mounts the overlay.
