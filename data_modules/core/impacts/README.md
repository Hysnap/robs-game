# Systems / Impacts Architecture

## 1. Overview & Purpose
The `impacts/` module acts as the decoupled consequence engine of the simulation. It provides dedicated sinks and state manipulators for systemic metrics—such as **Police Heat**, **Worker Fatigue**, **Zone Health (ZHI)**, and **Credit Default Risk**—without coupling them directly to Action Verbs or visual scene nodes.

This directory satisfies two core design imperatives:
1. **Verbs Calculate, Impacts Apply:** Verbs (`BUY`, `SELL`, `MAKE`) enforce constraints and calculate quantitative output deltas. Impact handlers consume these deltas and mutate the objective reality (`world_state`).
2. **Dual-Trigger Execution:** Accommodates both **Direct Impulses** (prompted by action verbs) and **Ambient Pulses** (unprompted world ticks such as passive cooling, desperation spikes, and availability shrinkage).

---

## 2. Directory Layout & Conventions

Impacts can be structured either as global metric sinks or grouped by their target dimension:

```text
res://systems/impacts/
 ├── README.md                      <-- This document
 ├── impact_base.gd                 <-- Core interface contract
 ├── impact_sink_heat.gd            <-- Global handler for "POLICE_HEAT"
 ├── impact_sink_fatigue.gd         <-- Global handler for "WORKER_FATIGUE"
 ├── impact_sink_zhi.gd             <-- Global handler for "ZONE_HEALTH_EROSION"
 └── impact_sink_receivables.gd     <-- Global handler for "UNPAID_RECEIVABLES"
```

### Adding a New Impact Metric
1. Create a new script extending `ImpactBase` (e.g., `impact_sink_corruption.gd`).
2. Define `get_target_metric()` to match the metric key (e.g., `"CORRUPTION_RISK"`).
3. Implement `apply_action_delta()` and/or `process_ambient_tick()`.
4. Any verb or sub-impact script can now output `"CORRUPTION_RISK": <value>` in its `impact_deltas` dictionary without breaking existing code.

### Removing an Impact Metric
Delete or disable the corresponding sink file, or bypass its logic in configuration. The rest of the engine will continue running safely.

---

## 3. The Contract Interface (`ImpactBase`)

Every impact script must conform to the unified static interface:

```gdscript
class_name ImpactBase extends RefCounted

## Target key matching entries in an action result's "impact_deltas"
static func get_target_metric() -> String:
    return ""

## 1. ACTION TRIGGER (Impulse)
## Consumes calculated deltas emitted from completed action verbs.
## - world_state: The objective reality dictionary
## - target_node_id: District, building, or operational node
## - delta_value: The pre-calculated impact amount
static func apply_action_delta(world_state: Dictionary, target_node_id: String, delta_value: float) -> void:
    pass

## 2. AMBIENT TRIGGER (Heartbeat)
## Evaluates unprompted environmental events during weekly/daily clock ticks
## (e.g., cooling off, crime flashpoints, container leakage).
## - world_state: The objective reality dictionary
## - node_id: Contextual node being ticked
static func process_ambient_tick(world_state: Dictionary, node_id: String) -> void:
    pass
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
│                      ACTION VERB (e.g. SELL)                 │
│  1. Verifies local inventory and operational constraints     │
│  2. Evaluates transacted commodity's "impact_velocities"     │
│  3. Compiles local impacts into `impact_deltas` dictionary    │
└──────────────────────────────┬───────────────────────────────┘
                               │
                    Returns `ActionResult`
            { "impact_deltas": { "POLICE_HEAT": 0.16 } }
                               │
                               ▼
┌──────────────────────────────────────────────────────────────┐
│                     IMPACT DISPATCHER                        │
│  Routes each delta key to its registered Impact Sink         │
└──────────────────────────────┬───────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────────┐
│               IMPACT SINK (e.g. impact_sink_heat.gd)         │
│  Mutates `world_state` directly (clamping, thresholds)       │
└──────────────────────────────┬───────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────────┐
│              INFORMATION LATENCY & TRANSIT QUEUE             │
│  Delayed and blurred before reaching the player's Filofax    │
└──────────────────────────────────────────────────────────────┘
```

---

## 5. Reference Examples

### A. Police Heat Sink (`impact_sink_heat.gd`)
```gdscript
extends ImpactBase

static func get_target_metric() -> String:
    return "POLICE_HEAT"

static func apply_action_delta(world_state: Dictionary, target_node_id: String, delta_value: float) -> void:
    if not world_state["districts"].has(target_node_id):
        return
        
    var district = world_state["districts"][target_node_id]
    district["actual_police_heat"] = clamp(district["actual_police_heat"] + delta_value, 0.0, 1.0)

static func process_ambient_tick(world_state: Dictionary, node_id: String) -> void:
    if not world_state["districts"].has(node_id):
        return
        
    var district = world_state["districts"][node_id]
    
    # Natural weekly dissipation
    district["actual_police_heat"] = max(0.0, district["actual_police_heat"] - 0.04)
    
    # Desperation flashpoint (unprompted customer crime)
    if district.get("zone_health_index", 100.0) < 40.0 and district.get("consumer_desperation_index", 0.0) > 0.70:
        if randf() < 0.20: # 20% weekly risk of street flashpoint
            district["actual_police_heat"] = clamp(district["actual_police_heat"] + 0.35, 0.0, 1.0)
```

### B. Worker Fatigue Sink (`impact_sink_fatigue.gd`)
```gdscript
extends ImpactBase

static func get_target_metric() -> String:
    return "WORKER_FATIGUE"

static func apply_action_delta(world_state: Dictionary, _target_node_id: String, delta_value: float) -> void:
    var ops = world_state.get("operations", {})
    ops["fatigue"] = clamp(ops.get("fatigue", 0.0) + delta_value, 0.0, 100.0)

static func process_ambient_tick(world_state: Dictionary, _node_id: String) -> void:
    # Ambient recovery over time when resting
    var ops = world_state.get("operations", {})
    ops["fatigue"] = max(0.0, ops.get("fatigue", 0.0) - 10.0)
```

---

## 6. Testing & Headless Verification

Impact handlers must remain 100% free of Godot UI nodes or Node3D spatial references. They can be verified in isolation headlessly:

```bash
godot --headless --script res://tests/test_phase3_sinks.gd
```