# res://systems/sim_controller.gd
class_name SimController extends RefCounted

const VerbRouterScript = preload("res://systems/verb_router.gd")
const ImpactRouterScript = preload("res://systems/impacts/impact_router.gd")

## Dispatches an action command through VerbRouter and routes resulting impacts
static func execute_directive(world_state: Dictionary, directive: Dictionary) -> Dictionary:
	var verb_key = directive.get("verb", "").to_upper()
	var verb_router = preload("res://systems/verb_router.gd")
	
	# 1. Run the action through VerbRouter
	var result = verb_router.dispatch(world_state, directive)
	
	# 2. If successful, route all resulting metrics (Fatigue, Heat, etc.) through ImpactRouter
	if result.get("success", false):
		apply_directive_impacts(world_state, directive, result)
		
	return result

## Routes non-financial physical/ambient side-effects through the Impact Router
static func apply_directive_impacts(world_state: Dictionary, directive: Dictionary, result_payload: Dictionary) -> void:
	var impact_router = preload("res://systems/impacts/impact_router.gd")
	
	# A. Pull fatigue/effort defined on the verb or recipe/commodity config
	var fatigue_cost: float = result_payload.get("fatigue_generated", 0.0)
	
	# Fallback: check config dictionary if verb didn't return an explicit fatigue delta
	if fatigue_cost == 0.0 and directive.has("config"):
		fatigue_cost = float(directive["config"].get("fatigue_cost", 0.0))
		
	if fatigue_cost != 0.0:
		var fatigue_event = {
			"target_metric": "FATIGUE",
			"delta": fatigue_cost,
			"source": directive.get("verb", "")
		}
		impact_router.route_impact(world_state, fatigue_event)

## Global Weekly/Tick Heartbeat
static func process_ambient_heartbeat(world_state: Dictionary) -> void:
	# Advance clock
	if world_state.has("metadata"):
		world_state["metadata"]["current_week_tick"] = world_state["metadata"].get("current_week_tick", 0) + 1
	
	# Delegate ambient drift, threshold checks, and passive decay to registered sinks
	ImpactRouterScript.dispatch_ambient_tick(world_state)