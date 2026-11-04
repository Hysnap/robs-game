# Containers

Container profiles live in this directory and are loaded with the same
hierarchical catalog loader as commodities. The current tree is organised
under `liquid/` with profiles for bottles, cans, casks, kegs, and servings.

Profiles are ordinary JSON catalog leaves. They may inherit `_base.json` and
must have an `id`, `display_name`, `category` (`CONTAINER`), capacity data,
and tare data. The decay pipeline currently reads
`capacity`, `tare_footprint`, and `decay_modifiers`; keep those names aligned
with the existing profiles and tests.

Packaging and decay calculations are currently exercised by
`tests/test_container_decay_pipeline.gd`. There is no separate
`ContainerManager` or automatic package-composition service in this
repository; adding a profile makes it available to the loader, but does not
add a new gameplay operation by itself.

See [HOWTOADD.md](HOWTOADD.md).
