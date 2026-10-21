# Systems / Impacts Architecture

## 1. Overview & Purpose
The `systems/impacts/` directory contains the scenario-agnostic plumbing for the simulation consequence engine. It provides the routing infrastructure, calculation models, and base contracts for systemic metrics—such as **Police Heat**, **Worker Fatigue**, **Zone Health (ZHI)**, and **Cash Ledger mutations**—without coupling them directly to Action Verbs or visual scene nodes.

This module satisfies two core architectural imperatives:
1. **Verbs Calculate, Impacts Apply:** Action verbs (`BUY`, `SELL`, `MAKE`) verify operational constraints and evaluate throughput. Sinks consume pre-calculated quantitative deltas and mutate the objective reality (`world_state`).
2. **Dual-Trigger Execution:** Accommodates both **Action Impulses** (prompted immediately by transacted verbs) and **Ambient Heartbeats** (unprompted world ticks such as passive cooling, desperation spikes, and inventory decay).

---

## 2. Directory Layout & Engine Boundary

`res://systems/impacts/` contains **strictly pure engine plumbing**:

```text
res://systems/impacts/
 ├── README.md                      <-- This document
 ├── impact_sink_base.gd            <-- Abstract contract interface for all metric sinks
 ├── impact_router.gd               <-- Central switchboard: autoloads sinks, routes deltas & ticks
 └── impact_calculator.gd           <-- Centralized math engine (5 calculation models)

```

> **Important Boundary Rule:** Specific metric sinks (such as `sink_heat.gd`, `sink_fatigue.gd`, `sink_cash.gd`) do **not** live in this folder. They reside in their respective data modules under `res://data_modules/core/impacts/` or `res://data_modules/<variant>/impacts/`.

---

## 3. The Contract Interface (`ImpactSinkBase`)

Every concrete metric sink in `data_modules/` must inherit from `ImpactSinkBase`:

```gdscript
# res://systems/impacts/impact_sink_base.gd
class_name ImpactSinkBase extends RefCounted

## 1. IDENTITY
## Returns the string token matching the metric in commodity impact activations
## (e.g. "POLICE_HEAT", "ZONE_HEALTH", "WORKER_FATIGUE", "CASH")
static func get_metric_key() -> String:
    push_error("get_metric_key() must be overridden by concrete metric sink.")
    return ""

## 2. ACTION IMPULSE CONTRACT
## Consumes calculated deltas emitted from completed action verbs.
## Mutates the target state (district, operations, or actor) with bounds clamping.
static func apply_delta(_world_state: Dictionary, _target_id: String, _delta: float) -> void:
    push_error("apply_delta() must be overridden by concrete metric sink.")

## 3. AMBIENT HEARTBEAT CONTRACT
## Evaluates unprompted environmental events during weekly/turn clock ticks
## (e.g. passive dissipation, consumer desperation flashpoints, recovery).
static func process_ambient(_world_state: Dictionary) -> void:
    pass # Optional: not all metrics require ambient background drift

```

---

## 4. Execution Lifecycle & Data Flow

```
┌──────────────────────────────────────────────────────────────┐
│                    PLAYER / QUEUE DIRECTIVE                  │
└──────────────────────────────┬───────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────────┐
│                 SIM CONTROLLER / VERB ROUTER                 │
│  Dispatches directive to target Action Verb (e.g. SELL)      │
└──────────────────────────────┬───────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────────┐
│                      ACTION VERB (e.g. SELL)                 │
│  1. Verifies stock, cash, and operational constraints        │
│  2. Reads commodity's `impact_activations`                   │
│  3. Delegates formulas to `ImpactCalculator.calculate()`     │
│  4. Returns `impact_deltas` dictionary                       │
└──────────────────────────────┬───────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────────┐
│                        IMPACT ROUTER                         │
│  `ImpactRouter.dispatch_delta(world_state, target, k, v)`    │
│  Routes each delta key directly to its registered sink       │
└──────────────────────────────┬───────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────────┐
│            CONCRETE SINK (e.g. SinkPoliceHeat)               │
│  Mutates `world_state` directly (clamping, bounds, state)    │
└──────────────────────────────┬───────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────────┐
│              INFORMATION LATENCY & TRANSIT QUEUE             │
│  State is delayed and blurred before reaching Filofax cache  │
└──────────────────────────────────────────────────────────────┘

```

---

## 5. Adding & Removing Metric Sinks

### Adding a Metric Sink

1. Create a dedicated folder in `res://data_modules/core/impacts/<metric_name>/` (or inside a variant module).
2. Create a script extending `ImpactSinkBase` (e.g. `sink_corruption.gd`).
3. Define `get_metric_key()` to return the uppercase token (e.g. `"CORRUPTION_RISK"`).
4. Implement `apply_delta()` and optional `process_ambient()`.
5. On boot, `ImpactRouter.autoload_sinks()` mounts the file automatically. Commodities and recipes can now emit `"CORRUPTION_RISK"` deltas without touching engine code.

### Removing a Metric Sink

Delete or move the sink script out of the data module. `ImpactRouter` will emit a harmless diagnostic warning if an incoming delta targets an unmounted sink, and execution continues without crashing.

---

## 6. Mathematical Calculation Models (`ImpactCalculator`)

Quantitative deltas are evaluated via `ImpactCalculator.calculate(model, quantity, factor, params)` using 5 standardized curves:

1. **`LINEAR_PER_UNIT`**: Proportional scaling ($\Delta = q \cdot k$).
2. **`WEIGHTED_PER_UNIT`**: Linear base scaled by environmental weights ($\Delta = (q \cdot k) \cdot M_{\text{env}}$).
3. **`EXP_PER_UNIT`**: Compounding/punitive runaway spikes ($\Delta = k \cdot (b^q - 1)$). Configured with `params.exponent_base`.
4. **`LOG_PER_UNIT`**: Diminishing marginal returns ($\Delta = k \cdot \ln(1 + q \cdot r)$). Configured with `params.log_scale`.
5. **`STEPPED_PER_UNIT`**: Discrete bucket jumps ($\Delta = \lfloor q / S \rfloor \cdot k$). Configured with `params.step_size`.

---

## 7. Testing & Verification

Impact plumbing and individual sinks are 100% headless and decoupled from the scene tree. Run isolated headless verification via:

```powershell
godot --headless --script res://tests/test_engine_harness.gd

```
