# Consumable recipes

Recipes in this branch are catalog leaves loaded by
`CommodityManager.load_hierarchical_commodities()`. A recipe directory uses
`recipe_profile.json`; optional `make/` JSON files describe process impacts.
The profile must provide an uppercase `id`, `output_item`,
positive `output_yield_units`, and an `inputs` dictionary. Inputs and output
must resolve to commodity registry IDs when the catalog validator runs.

Recipe impacts describe the process. Impacts attached to an ingredient's
commodity `make/` folder describe material handling. Both are available to
the make action through `impact_activations`.

See [HOWTOADD.md](HOWTOADD.md) for the authoring and test sequence.
