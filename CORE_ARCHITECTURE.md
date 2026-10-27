# Core Systems Architecture

This diagram is based on the current Godot scripts under `systems/`, the
`data_modules/` runtime modules, and the scene scripts that call them. Arrows
show the primary code-level dependency or call direction, not every incidental
reference.

## Component relationships

```mermaid
flowchart TD
	subgraph Entry["Scene / application entry points"]
		Main["main.gd"]
		Map["map_menu.gd"]
		Loader["city_generator_loader.gd"]
		City["city_view.gd"]
		UI["filofax_ui.gd"]
		DocketUI["filofax_district_docket.gd"]
		Autoloads["Godot autoloads<br/>GameState + AppLogger"]
	end

	subgraph State["Canonical state and persistence"]
		GS["GameState<br/>world_state + signals"]
		Save["SaveManager"]
		DB["DBManager"]
		SQLite[("SQLite society DB<br/>districts, establishments,<br/>households, residents, relationships")]
	end

	subgraph World["World and society generation"]
		Crafter["CustomCityCrafter / CityCrafter"]
		Spatial["CitySpatialAdapter"]
		Society["SocialNetworkGenerator"]
		SocietyPasses["Society passes<br/>parcel planning<br/>premises/workplaces<br/>borough clustering<br/>demographics<br/>Dunbar graph"]
		Queries["SocietyQueries"]
		Auditor["CityAuditor<br/>read-only balance report"]
	end

	subgraph Runtime["Simulation runtime"]
		Docket["DocketManager"]
		Sim["SimController"]
		Verbs["VerbRouter"]
		Actions["Atomic action_*.gd<br/>buy, sell, make, travel,<br/>investigate, scout, ..."]
		Orders["OrderManager"]
		Calc["ImpactCalculator"]
		Conditions["ConditionEvaluator"]
		Impacts["ImpactRouter"]
		Sinks["sink_*.gd<br/>cash, time, fatigue, heat,<br/>inventory, population, ..."]
		Ambient["AmbientDecayProcessor"]
		Result["EngineResult"]
	end

	subgraph Content["Scenario and data modules"]
		Manifest["ScenarioManifestManager"]
		Config["business_rules.cfg<br/>scenario manifest JSON<br/>catalog JSON"]
		VerbData["data_modules/*/verbs"]
		ImpactData["data_modules/*/impacts"]
		Catalog["CommodityManager<br/>CatalogValidator<br/>TaxonomyHarvester"]
	end

	Main --> Save
	Main --> GS
	Map --> Loader
	Loader --> Crafter
	Loader --> GS
	Loader --> Spatial
	Loader --> Society
	Loader --> Save
	City --> GS
	City --> UI
	UI --> GS
	UI --> DocketUI
	UI --> Sim
	DocketUI --> Queries

	Autoloads --> GS
	GS --> DB
	GS --> Config
	Save --> GS
	Save --> DB
	DB --> SQLite
	Queries --> DB

	Spatial --> GS
	Society --> Manifest
	Society --> DB
	Society --> SocietyPasses
	SocietyPasses --> DB
	SocietyPasses --> GS
	Society --> Auditor
	Auditor --> DB
	Auditor --> GS

	UI --> Sim
	Docket --> Sim
	Docket --> Impacts
	Sim --> Verbs
	Sim --> Impacts
	Verbs --> Actions
	Verbs --> VerbData
	Actions --> Orders
	Actions --> Calc
	Actions --> Conditions
	Actions --> Catalog
	Actions --> Result
	Impacts --> Sinks
	Impacts --> Ambient
	Sinks --> GS
	Ambient --> GS
	ImpactData --> Sinks

	Manifest --> Config
	Manifest --> Catalog
	Catalog --> Config
```

## City creation and load sequence

```mermaid
sequenceDiagram
	participant Menu as MapMenu
	participant Loader as CityGeneratorLoader
	participant Crafter as CustomCityCrafter
	participant State as GameState
	participant Spatial as CitySpatialAdapter
	participant Society as SocialNetworkGenerator
	participant DB as DBManager / SQLite
	participant Save as SaveManager

	Menu->>Loader: change_scene + pending_city_settings
	Loader->>Crafter: generate_city_async(seed)
	Crafter-->>Loader: generated spatial layout
	Loader->>State: initialize_fresh_state()
	Loader->>Spatial: ingest_citycrafter_generation(...)
	Spatial->>State: populate districts / metadata
	Loader->>Society: generate_city_society(world_state, seed)
	Society->>DB: initialize_database(true)
	Society->>Society: run parcel, premises, borough,<br/>demographic, and social-graph passes
	Society->>DB: insert society records
	Loader->>Save: save_game(slot_01, city_crafter)
	Save->>DB: close, copy database, reopen
	Save->>State: write game_state.json and city_layout.json
	Loader->>Loader: change_scene(node_3d.tscn)
```

On a continue/load path, `MainMenu` calls `SaveManager.load_game()`, which
restores `game_state.json`, copies the slot's `society.db` into the active
database location, restores the optional visual layout, and reopens SQLite.

## Directive execution sequence

```mermaid
sequenceDiagram
    participant User as FilofaxUI
    participant Sim as SimController
    participant Verbs as VerbRouter
    participant Action as action_*.gd
    participant Calc as ImpactCalculator
    participant Order as OrderManager
    participant Impact as ImpactRouter
    participant Sink as sink_*.gd
    participant State as GameState.world_state

    User->>Sim: execute_directive(world_state, directive)
    Sim->>Verbs: dispatch(world_state, directive)
    Verbs->>Verbs: resolve aliases and mounted action
    Verbs->>Action: execute(world_state, directive)
    Action->>Order: create/update/archive order
    Action->>Calc: calculate configured deltas
    Calc-->>Action: impact_deltas
    Action-->>Verbs: EngineResult or Dictionary
    Verbs-->>Sim: normalized result
    Sim->>Impact: dispatch_delta(target, metric, delta)
    Impact->>Sink: apply_delta(world_state, target, delta)
    Sink->>State: mutate canonical state
    Sim-->>User: success/failure result
    Note over Sim: DocketManager uses the same SimController path<br/>for scheduled and staff tasks.
    User->>Sim: process_ambient_heartbeat()
    Sim->>Impact: dispatch_ambient_tick(world_state)
    Impact->>Sink: process_ambient(world_state)
```

## Important boundaries

- **`GameState.world_state` is the live source of truth for gameplay state.**
  UI, actions, orders, and impact sinks mutate or read it directly.
- **SQLite is the society persistence/query boundary.** `DBManager` owns the
  schema and connection; society generation writes it, while `GameState` and
  `SocietyQueries` read its views for district-level information.
- **`ScenarioManifestManager` is the content indirection boundary.** It
  resolves `business_rules.cfg` to scenario modules and caches parsed JSON or
  engine resources.
- **`VerbRouter` and `ImpactRouter` are plugin switchboards.** Verbs and sinks
  are discovered from filesystem directories, so new data modules can extend
  runtime behavior without changing the central dispatcher.
- **`EngineResult` is the action result normalization boundary.** Verbs may
  return an `EngineResult` or a `Dictionary`; `VerbRouter` converts the former
  to the latter for callers.

## Review observations

1. **High centrality of `GameState`:** It is intentionally the shared state
   boundary, but many systems retain direct references to its nested
   dictionaries. Changes to the state schema should therefore be treated as
   cross-cutting changes.
2. **Runtime registration is explicit:** `ImpactRouter.autoload_sinks()` is
   currently referenced by the test harnesses and the Filofax test scene, but
   not by the normal city-generation or main-scene path found in this review.
   Production startup should guarantee sink registration before directives or
   ambient ticks run; otherwise deltas produce the router's "No sink registered"
   warning and are not applied.
3. **Two persistence stores must remain coordinated:** a save consists of
   `game_state.json`, `society.db`, and optionally `city_layout.json`.
   Loading or saving only one of these produces an incomplete game state.
4. **The duplicate `social_network_generator copy.gd` is not part of the
   primary dependency path shown above.** It should be treated as a legacy or
   experimental implementation unless it is intentionally mounted elsewhere.
5. **The UI and staff automation converge correctly:** both Filofax commits
   and scheduled/staff tasks call `SimController.execute_directive()`, keeping
   verb, order, calculation, and impact behavior in one execution path.
6. **`CityAuditor` is intentionally separate from `SystemAuditor`:** it reads
   an already-open database and `world_state`, performs no gameplay or schema
   mutations, and writes only a Markdown inspection report. Its SQL is kept in
   `systems/city_auditor_queries.sql` for reuse or independent inspection.
