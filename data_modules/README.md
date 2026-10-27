# Data modules

`data_modules/` contains the records consumed by the generic systems. Data is
loaded from `res://` paths, so filenames and paths are case-sensitive in the
loader even when the host filesystem is not.

## Modules

* `core/` is the active baseline catalog and scenario.
* `shared/` contains reusable feedback data.
* `crime/` is an optional variant overlay. It currently contains impact data;
  it is not automatically active unless a caller mounts that variant.

Use the nearest authoring guide:

* [core/HOWTOADD.md](core/HOWTOADD.md)
* [core/commodities/HOWTOADD.md](core/commodities/HOWTOADD.md)
* [core/containers/HOWTOADD.md](core/containers/HOWTOADD.md)
* [core/recipes/consumables/HOWTOADD.md](core/recipes/consumables/HOWTOADD.md)
* [core/verbs/HOWTOADD.md](core/verbs/HOWTOADD.md)
* [core/impacts/HOWTOADD.md](core/impacts/HOWTOADD.md)
* [core/dialects/HOWTOADD.md](core/dialects/HOWTOADD.md)
* [core/spatial/society/HOWTOADD.md](core/spatial/society/HOWTOADD.md)

Do not put comments in JSON. Put authoring notes in `_meta`; the catalog
loader removes `_meta` before registering runtime data.
