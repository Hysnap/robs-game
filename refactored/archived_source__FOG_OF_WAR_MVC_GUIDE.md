# Fog-of-War and District Intelligence MVC Guide

## Purpose and scope

This guide documents the district intelligence path configured by
`systems/multilayer_info_loop/fog_of_war_rules.cfg`. It is intended for
developers extending district telemetry, survey state, census presentation, or
map indicators.

The central rule is:

> Raw society data may be read by the model/query layer, but only the
> perception policy may decide what the player is allowed to see. Views must
> consume the resulting projection and must never query raw society data.

## Responsibilities

| Element | MVC role | Responsibility | Must not do |
|---|---|---|---|
| `fog_of_war_rules.cfg` | Configuration/model input | Declare thresholds, masking, fuzzing, rounding, tokens, and indicator presentation values. | Contain rules that have no runtime consumer or duplicate hard-coded policy. |
| `systems/society_queries.gd` | Model/data access | Read authoritative census and establishment records from SQLite. | Decide player visibility, apply UI formatting, or return raw data directly to a view. |
| `systems/game_state.gd` | Model/state facade | Own canonical `world_state`, selection state, and the public `get_district_view()` entry point. | Expose raw society records as a presentation shortcut. |
| `systems/multilayer_info_loop/district_perception_filter.gd` | Model policy/service | Resolve configuration, determine known/home/stale status, mask unknown data, round values, fuzz ratios, bucket metrics, and produce the player-facing district projection. | Render controls, colors, labels, or query SQLite from callers other than its controlled model boundary. |
| `systems/condition_evaluator.gd` | Model policy helper | Perform reusable comparisons, fuzzing, bucket evaluation, and adaptive rounding. | Load UI or scenario data unrelated to its calculation contract. |
| `scenes/3d_scenes/city_view.gd` | Controller/view orchestrator | React to map selection, request a filtered projection, and pass it to the indicator/view host. | Load or interpret gameplay policy independently of the perception service. |
| `scenes/3d_scenes/indicators/district_indicator.gd` | View | Convert `view_data` status into marker visibility, color, scale, and billboard text. | Query `GameState`, SQLite, or reconstruct intelligence status. |
| `generated/ui/gen_district_docket.gd` | View | Render the projection supplied through `ViewHost.bind_data()`. | Query raw society data or apply a second masking/rounding policy. |
| `refactored/filofax/filofax_district_docket.gd` | Legacy view | If retained, render a filtered dossier only. | Call `SocietyQueries` directly for establishments or dossiers. |

## Interaction contract

The intended request path is:

1. A player selects a district in `city_view.gd`.
2. The controller updates the selected district in `GameState`.
3. `GameState.get_district_view()` delegates to
   `DistrictPerceptionFilter.get_perceived_district_view()`.
4. The filter reads canonical district state and, for known districts, obtains
   raw census/establishment data through `SocietyQueries`.
5. The filter applies all configured visibility and precision limits.
6. The filter returns a new projection dictionary containing only player-visible
   values and status tokens.
7. `city_view.gd` passes that projection to `DistrictIndicator` and the
   `ViewHost`; the views render it without further data access.

This keeps the raw-to-perceived boundary in one place. A new UI, map overlay,
automation feature, or API must call `GameState.get_district_view()` rather
than calling `SocietyQueries` directly.

## Configuration and limit ownership

| Config section | Intended enforced limit | Current consumer/status |
|---|---|---|
| `[fog_of_war]` | Unknown-district masks, status tokens, stale threshold, decay toggle. | Partly consumed by `DistrictPerceptionFilter`; see breaches below. |
| `[demographic_rounding]` | General/home population and household precision. | Consumed by the filter for known districts. |
| `[telemetry_fuzziness]` | Jitter range, home-turf reduction, minimum error floor. | Consumed for unemployment ratio fuzzing. |
| `[familiarity_scaling]` | Scout/action familiarity gains and progressive fuzz reduction. | No consumer was found; currently not enforced. |
| `[establishment_headcount_rounding]` | Establishment worker-count precision tiers. | Consumed by the filter and `ConditionEvaluator`. |
| `[unemployment_buckets]` | Ordered unemployment thresholds and UI tokens. | The file declares buckets, but the loader requires an absent `bucket_count`; configured values are therefore ignored. |
| `[metric_descriptors.disposable_income]` | Income-specific jitter, home modifier, floor, and buckets. | No filter ingestion or transformation was found; income is not safely projected. |
| `[spatial_indicators]` | Verified/stale colors and marker elevations. | Loaded by `city_view.gd`; indicator elevation is not applied in the visible path and the indicator retains hard-coded color defaults. |

## Confirmed breaches and investigation targets

### 1. Configured mask switches are ignored

`DistrictPerceptionFilter` loads `mask_unexplored_establishments` and
`mask_unexplored_census`, but the unknown-district branch always removes
metrics and always sets census values to `null` and establishments to `[]`.
Changing either configuration switch cannot change behavior.

**Investigate:** `systems/multilayer_info_loop/district_perception_filter.gd:51-52`
and the unconditional unknown branch around lines `133-157`.

**Impact:** configuration is misleading and the declared limits are not
actually runtime controls. Either honor the switches in the branch or remove
them and document the invariant as unconditional.

### 2. Unemployment configuration is silently bypassed

The loader reads `unemployment_buckets.bucket_count`, but
`fog_of_war_rules.cfg` defines `bucket_1` through `bucket_5` without a
`bucket_count`. The parsed list remains empty, so the built-in fallback bucket
list remains active. A designer changing the configured thresholds or tokens
will not get the requested behavior.

**Investigate:** `systems/multilayer_info_loop/district_perception_filter.gd:87-98`
and `systems/multilayer_info_loop/fog_of_war_rules.cfg:43-54`.

**Impact:** the configuration is not authoritative. Prefer parsing sequential
keys until no bucket is present, or add and validate `bucket_count`; reject
malformed/unsorted buckets rather than silently falling back.

### 3. Disposable-income limits are declared but not applied

The configuration defines a complete `metric_descriptors.disposable_income`
policy, and the UI schema expects `avg_disposable_income`, but the perception
filter never loads that section, queries a raw income value for the projection,
or calls `ConditionEvaluator.transform_measure()` for it.

**Investigate:** `systems/multilayer_info_loop/fog_of_war_rules.cfg:60-71`,
`systems/multilayer_info_loop/district_perception_filter.gd:182-234`, and
`generated/ui/gen_district_docket.gd` in `bind_data()`.

**Impact:** the UI field can be absent, stale, or supplied from an unfiltered
district dictionary. Income must be transformed in the perception layer before
being exposed to any view.

### 4. Familiarity scaling has no implementation path

`[familiarity_scaling]` declares scout/action gains and a dampener, but no
consumer of these keys was found. The filter only uses a known-district boolean
and a survey timestamp; it does not calculate progressive familiarity.

**Investigate:** `systems/multilayer_info_loop/fog_of_war_rules.cfg:34-37` and
`systems/multilayer_info_loop/district_perception_filter.gd:161-176`.

**Impact:** the declared precision progression is not enforced. Either implement
familiarity as model state and apply it to every fuzzed metric, or remove the
unused section until the feature exists.

### 5. Legacy docket bypasses the perception boundary

`refactored/filofax/filofax_district_docket.gd` correctly obtains the district
projection for its main data, but then calls
`SocietyQueries.get_district_establishments()` directly and opens raw
establishment dossiers. If this scene remains mountable, an unexplored
district can expose establishment data outside the filter.

**Investigate:** `refactored/filofax/filofax_district_docket.gd:33` and
`refactored/filofax/filofax_district_docket.gd:161-198`.

**Impact:** this is a direct MVC/privacy boundary breach. Retire the legacy
scene, or route all establishment lists and dossiers through a perception
service that verifies district knowledge and applies the configured limits.

### 6. View orchestration owns part of presentation policy

`city_view.gd` parses `fog_of_war_rules.cfg` itself, while
`district_indicator.gd` has its own hard-coded fallback colors and status-token
interpretation. This duplicates policy ownership across the view and service.
The configured marker elevations are loaded but are not visibly applied when
the indicator is instantiated.

**Investigate:** `scenes/3d_scenes/city_view.gd:81-92` and
`scenes/3d_scenes/indicators/district_indicator.gd:7-48`.

**Impact:** changing configuration can produce inconsistent map and dossier
behavior. Resolve indicator presentation settings through one presentation
configuration object or pass them explicitly from the controller; do not make
the indicator infer gameplay state.

### 7. Raw SQL query boundary needs hardening

`SocietyQueries` interpolates `district_id` into SQL strings. Although this is
primarily a data-validation/security concern rather than an MVC violation, it
weakens the model boundary and can make invalid input reach the database.

**Investigate:** `systems/society_queries.gd:6-30` and
`systems/society_queries.gd:35-56`.

**Impact:** validate identifiers and use the repository’s parameterized query
facility if available. Keep this hardening in the query layer, not in views.

## Rules for future changes

1. Add a configuration key only with a loader, validation, runtime consumer, and
   focused test for both default and changed values.
2. Treat `SocietyQueries` results as truth, never as player-visible data.
3. Add new player-visible metrics to the perception projection first; then add
   them to UI schemas/views.
4. Keep masking, rounding, fuzzing, bucketing, and stale-status decisions in
   `DistrictPerceptionFilter`/`ConditionEvaluator`.
5. Keep `GameState.get_district_view()` as the public read API for district
   intelligence.
6. Views may format, hide controls based on supplied status, and render
   placeholders, but may not fetch or derive hidden values.
7. Avoid silent fallback for malformed limit configuration. Log or fail
   explicitly, because a fallback can weaken an intended information boundary.
8. When a district becomes known or stale, verify every consumer receives the
   same `intel_status` and projection, including the 3D indicator, dossier, and
   any future automation.

## Minimum validation checklist

- Unknown district: no census, income, unemployment, or establishment detail is
  present in the projection.
- Known district: population/households use the correct home/general step.
- Headcounts: each threshold uses the configured ascending tier.
- Unemployment: changing a configured threshold changes the returned token.
- Income: the returned value is fuzzed/bucketed according to its descriptor and
  is absent or masked when the district is unknown.
- Stale district: the threshold boundary is tested at exactly `N` and `N+1`
  days, with the intended inclusive/exclusive rule documented.
- Map and dossier: both render the same projection without raw SQLite calls.
- Configuration errors: malformed or incomplete buckets produce an explicit
  error/warning and do not silently weaken masking or precision limits.
