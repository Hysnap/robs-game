# Core data module

`core/` is the default content mounted by the tests and by the runtime. It
contains:

* `commodities/` - inherited catalog profiles and action impact definitions;
* `containers/` - physical container profiles loaded by the same catalog
  loader;
* `recipes/` - transformation profiles;
* `verbs/` - canonical `action_*.gd` implementations and feedback data;
* `impacts/` - concrete `sink_*.gd` metric handlers and CFG rules;
* `dialects/` - JSON replacement lexicons;
* `feedback/` - shared outcome and UI feedback data;
* `spatial/society/` - the manifest and its registered society modules;
* `business_rules.cfg` - runtime switches and manifest path; and
* `verb_mappings.json` - aliases resolved by `VerbRouter`.

The core module is not a generic plugin manifest. Commodity and recipe trees
are loaded explicitly by callers, while society JSON files must be registered
in the active manifest. See [HOWTOADD.md](HOWTOADD.md) before adding a new
record.
