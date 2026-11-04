# Dialects

Dialect JSON files provide replacement pools for procedural feedback. The
current profile shape is:

```json
{
  "id": "DIALECT_EXAMPLE",
  "name": "Example",
  "replacements": {
    "{boss}": ["boss", "manager"]
  },
  "affixes": {
    "openers": ["Listen {boss},"],
    "closers": ["All sorted."]
  }
}
```

`DialogueResolver` consumes a selected profile when resolving feedback text.
Tokens are ordinary strings; the profile must use the tokens referenced by
the feedback templates it is intended to service. The repository currently
ships `brummie_street.json`; adding a file alone does not select it for an
actor or scenario.

See [HOWTOADD.md](HOWTOADD.md) and
[tests/test_verbs_feedback_integration.gd](../../../tests/test_verbs_feedback_integration.gd)
for the supported headless integration path.
