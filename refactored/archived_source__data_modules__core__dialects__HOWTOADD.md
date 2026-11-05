# How to add a dialect

1. Create a lowercase JSON filename.
2. Add an uppercase `id`, display `name`, and a `replacements` dictionary.
3. Use the exact placeholder keys expected by the feedback templates. Add
   optional `affixes.openers` and `affixes.closers` arrays only when needed.
4. Select the profile from the actor/scenario code that resolves dialogue;
   discovery of a file does not select it automatically.

Keep replacement values short and grammatical. Verify a selected profile
through the feedback integration test:

```powershell
godot --headless --path . --script res://tests/test_verbs_feedback_integration.gd
```
