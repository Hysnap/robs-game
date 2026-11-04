# RobsGame Development Architecture Guide

## Purpose

This is the default guide for planning, implementing, reviewing, and testing
future changes. It defines where a change belongs, which layer owns a
responsibility, and which boundaries must not be crossed.

The project is data-driven. Code supplies reusable mechanics and orchestration;
configuration supplies scenario content, limits, labels, feedback, and
presentation contracts.

## The core rule

Every change must have one clear owner:

1. **Data modules** describe content, limits, contracts, and scenario choices.
2. **Systems** implement reusable domain mechanics and state transitions.
3. **World scripts** build the city model and connect generation passes.
4. **Controllers** coordinate requests between state, systems, and views.
5. **Scenes and views** present already-prepared data and emit user intent.
6. **Tests** verify contracts without becoming runtime dependencies.

Do not solve a data problem by adding a view workaround, or solve a
presentation problem by changing simulation state.

## Repository map

| Location | Ownership | Allowed responsibility | Prohibited responsibility |
|---|---|---|---|
| `data_modules/core/` | Core authored content and configuration | Baseline scenario rules, catalogs, labels, UI contracts, spatial manifests, actions, and impact definitions. | Directly mutating runtime state or containing presentation logic. |
| `data_modules/<flavour>/` | Optional flavour/scenario overlays | Domain-specific additions such as crime, dialect, feedback, verbs, and impacts. | Bypassing the core contracts or duplicating generic mechanics. |
| `data_modules/*/commodities/` | Commodity catalog | Consumables, durables, services, inheritance, and activation metadata. | Implementing inventory mutation. |
| `data_modules/*/containers/` | Packaging catalog | Container definitions and capacity/packaging metadata. | Implementing transfer or stock mutation. |
| `data_modules/*/dialects/` | Narrative content | Tone, slang, and feedback phrasing variants. | Deciding whether an action succeeds. |
| `data_modules/*/feedback/` | Feedback presentation data | User-facing field definitions, labels, templates, and feedback composition data. | Reading state or enforcing simulation rules. |
| `data_modules/*/impacts/` | Impact configuration | Metric-specific definitions and trigger/decay parameters consumed by impact sinks. | Owning the global state mutation pipeline. |
| `data_modules/*/localization/` | Text and translation data | Database labels, UI strings, and generated language translations. | Hard-coded UI text in systems. |
| `data_modules/*/recipes/` | Make-action content | Recipes, inputs, outputs, and make-action impact activations. | Implementing the make action itself. |
| `data_modules/*/spatial/` | World-generation manifests | Society, district, building, demographic, civic, and map-generation definitions. | Creating scene nodes or rendering the map. |
| `data_modules/*/theme_profiles/` | Theme configuration | Reusable colors, typography, spacing, and visual profiles. | Owning Godot scene lifecycle. |
| `data_modules/*/ui_schemas/` | UI contracts | Structure, fields, formatting, routes, and widget contracts consumed by the UI compiler. | Directly building controls or querying gameplay state. |
| `data_modules/*/verbs/` | Action definitions and action entry points | User/staff action declarations and the associated action scripts/metadata. | Applying global metric deltas directly; route those through impacts. |
| `systems/` | Runtime domain services | State, persistence, manifests, routing, conditions, simulation, queries, and shared mechanics. | Rendering controls or embedding flavour-specific copy. |
| `systems/impacts/` | Impact execution framework | Dispatching metric changes and applying tick/ambient changes through sinks. | Deciding which UI initiated the action. |
| `systems/multilayer_info_loop/` | Imperfect-information policy | Fog of war, survey state, staleness, delay, masking, fuzzing, rounding, and perceived projections. | Rendering or exposing raw model data to views. |
| `systems/society/` | Society/world data construction | Creating and populating the city’s social, demographic, building, and map-related model data. | Presenting the result or applying UI formatting. |
| `scripts/world/` | CityCrafter/world implementation | Custom city layout generation and world-model construction using system instructions. | Owning UI state or user-facing formatting. |
| `scripts/world/camera/` | Camera behavior | RTS/camera movement, focus, zoom, and input interpretation. | Changing economic or society state. |
| `scenes/` | Presentation layer | Godot nodes, scene composition, input signals, binding prepared data, and visual updates. | Domain rules, database queries, raw simulation calculations, or hidden-state filtering. |
| `resources/` | Reusable Godot presentation resources | Fonts, colors, materials, theme resources, and other scene-consumed assets. | Runtime business rules or state mutation. |
| `tools/` | Build and authoring tools | UI compilation, code generation, validation, previews, and developer utilities. | Becoming part of the game’s runtime path. |
| `generated/ui/` | Compiler output | Generated views and bindings produced from `data_modules/*/ui_schemas/`. | Manual edits; change the source schema and regenerate. |
| `tests/` | Headless verification | SceneTree tests for data, systems, contracts, and integration behavior. | Supplying production behavior or relying on visual interaction. |
| `reports/` and `refactored/` | Non-production investigation area | Audits, prototypes, migration experiments, and obsolete implementations. | New final-game dependencies unless explicitly promoted. |

### Important classification notes

`data_modules` is primarily authored data/configuration, but the verbs area may
contain action scripts that are runtime entry points. Treat those scripts as
thin adapters: they validate and calculate an action request, then return a
normalized result for the simulation pipeline.

The target rule is that scene scripts are presentation-only. Existing
orchestration code such as `city_view.gd` may still be present for historical
reasons; do not extend that pattern. New coordination belongs in a controller
under `systems/`, with scenes limited to wiring signals and rendering data.

## MVC responsibilities

### Model

The model is the authoritative game and society state plus the services that
read or transform it:

- `GameState` owns live gameplay state.
- `DBManager` owns the SQLite connection and persistence boundary.
- `SocietyQueries` reads authoritative society records.
- `systems/society/` and `scripts/world/` create world data.
- `systems/impacts/` applies state changes.
- `systems/multilayer_info_loop/` creates player-permitted projections.

Model code must not create controls, choose fonts, format labels for a
particular view, or bypass the configured data contracts.

### View

Views include Godot scenes, controls, indicators, generated UI, theme resources,
and view-specific presenters. They may:

- bind a prepared dictionary or typed payload;
- format it according to a UI schema/theme;
- show loading, empty, stale, masked, and error states;
- emit user intent through signals.

Views must not:

- query SQLite or raw society services;
- mutate `GameState` directly;
- calculate action impacts;
- decide whether information is visible;
- duplicate configuration thresholds;
- contain alternate gameplay rules in event handlers.

### Controller

Controllers coordinate intent and data flow. They may select the correct system,
call a model service, normalize a result, and send a view payload. They must not
become a second model or a second view.

Preferred flow:

```text
user input
  -> scene emits intent
  -> controller validates/routes intent
  -> model/system reads or mutates state
  -> controller builds a view payload
  -> scene/view renders the payload
```

## Required data flows

### Actions and impacts

```text
UI/action request
  -> SimController
  -> VerbRouter / action script
  -> EngineResult or normalized result
  -> ImpactRouter
  -> metric sink
  -> GameState/world model
  -> tick/ambient processing
  -> feedback report
  -> ViewHost/generated view
```

Action scripts may describe what should happen, but metric sinks own how the
underlying measure changes. Tick and ambient changes must use the same impact
boundary rather than being hidden in a view or verb.

### City creation

```text
scenario manifest
  -> city/world generator
  -> spatial adapter
  -> society generation passes
  -> GameState + SQLite
  -> scene presentation
```

Generation passes may populate the model and database. They must not instantiate
presentation controls or decide how a player sees imperfect information.

### Imperfect information

```text
raw world/society truth
  -> perception/fog-of-war service
  -> masked/rounded/fuzzed projection
  -> controller/ViewHost
  -> scene or generated UI
```

No scene, generated view, or legacy UI may bypass the perception service to
obtain raw district, census, establishment, or telemetry data.

### UI compilation

```text
data_modules/*/ui_schemas/
  -> tools/ui_compiler/
  -> generated/ui/
  -> ViewHost
  -> scene shell
```

Generated files are disposable outputs. A UI change must normally update the
source schema, run the compiler, inspect the generated diff, and run the
relevant headless UI contract test.

## Configuration ownership rules

For every configurable value:

1. Define it in the appropriate `data_modules` file.
2. Load it through the owning runtime service.
3. Validate its type, range, ordering, and required fields.
4. Apply it in exactly one authoritative implementation.
5. Test the default and at least one changed value.
6. Fail explicitly when malformed configuration could weaken a limit.

Do not duplicate a threshold in a scene, generated view, action script, or
test fixture unless the duplicate is explicitly labelled as test input.

The tagged file
`data_modules/core/feedback/spatial/district_ui.json` is a presentation
contract. It owns field labels, formatting, text templates, and styling values;
it does not own whether a field is visible or what the field’s gameplay value
is. Visibility and value preparation belong to the relevant model service.

## Planning workflow for future work

Before editing:

1. Identify the user-visible behavior and the authoritative state it affects.
2. Locate the owning data module, system service, controller, view/schema, and
   existing test.
3. Trace the full path from input to state change to presentation.
4. Decide whether the change is data, model, controller, view, tool, or test
   work.
5. Check whether an existing helper or contract already owns the behavior.

During implementation:

1. Change the narrowest authoritative layer first.
2. Update directly related configuration/schema documentation.
3. Keep raw and perceived/ formatted data as separate types or payloads where
   practical.
4. Keep error handling explicit; do not silently fall back to permissive
   behavior.
5. Regenerate generated UI instead of editing generated output.
6. Keep production code out of `reports/` and `refactored/`.

Before completion:

1. Validate the changed configuration/schema.
2. Run the smallest relevant headless test.
3. Run generation/compiler checks when inputs or generated files changed.
4. Confirm no view now reads raw state or database data.
5. Confirm all limits are enforced at their owning boundary.
6. Review the diff for unrelated changes and generated artifacts.

## Review checklist

- Is the change in the correct directory?
- Is there one authoritative owner for each rule?
- Does any scene query, mutate, or calculate domain state?
- Does any view bypass a controller or perception service?
- Does any action bypass `ImpactRouter`/metric sinks?
- Is a config value loaded, validated, and actually used?
- Does a new UI field exist in the source schema rather than only generated
  code?
- Are core and flavour data separated correctly?
- Are raw model data and player-visible projections distinct?
- Are stale, masked, empty, and error cases tested?
- Are `reports/` and `refactored/` kept out of the production dependency graph?

## Definition of done

A change is architecturally complete only when its data/configuration,
runtime owner, controller/view contract, generated output (if applicable),
tests, and documentation all agree. A feature that works in one scene but
bypasses the owning service is not complete.
