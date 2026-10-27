# Core verbs

`VerbRouter` recursively mounts scripts named `action_*.gd` and uses the
filename (without `action_`) as the uppercase verb token. Core aliases are
defined in `../verb_mappings.json`; a variant can overlay both scripts and
aliases.

An action receives `(world_state, action_directive)` and returns either an
`EngineResult` or a dictionary accepted by the router. It should remain
headless and report failures through the existing `EngineResult` error codes.
Feedback text is kept separate from action code in the applicable feedback
JSON directories.

The current core actions cover buy, sell, make, order, pay, receive,
communicate, investigate, and travel/scout flows. A new folder is not enough:
the folder must contain an `action_<verb>.gd` script with `execute()`.

See [HOWTOADD.md](HOWTOADD.md) and
[tests/test_verbs_feedback_integration.gd](../../../tests/test_verbs_feedback_integration.gd).
