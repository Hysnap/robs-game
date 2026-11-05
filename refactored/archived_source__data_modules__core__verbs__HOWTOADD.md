# How to add a verb

1. Create a lowercase folder under `core/verbs/` (or the selected variant).
2. Add `action_<verb_name>.gd` with an `execute(world_state,
   action_directive)` method. Keep the action headless and return an
   `EngineResult` or its dictionary form.
3. Add feedback JSON in the feedback location used by the action if new
   outcome codes need narrative text.
4. Add aliases to `core/verb_mappings.json` only when a user-facing token
   should resolve to the new canonical verb.

`VerbRouter` discovers the script by filename; it does not infer a verb from a
folder alone. Verify mounting and execution with:

```powershell
godot --headless --path . --script res://tests/test_engine_harness.gd
godot --headless --path . --script res://tests/test_verbs_feedback_integration.gd
```
