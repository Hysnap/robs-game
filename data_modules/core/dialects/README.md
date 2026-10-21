# Core Dialects & Vernacular Replacement Architecture

## 1. Overview & Purpose

The `res://data_modules/core/dialects/` directory contains regional, socio-economic, and role-based dialect configuration files.

The dialect system works as the final narrative filter in the procedural text pipeline:

1. **Verbs Emit Semantic Codes:** Execution scripts (`ActionBuy`, `ActionSell`, `ActionMake`, etc.) never output hardcoded dialogue. They emit semantic status codes (e.g. `SUCCESS`, `INSUFFICIENT_RESOURCE`, `OUTSIDE_HOURS`) packed in an `EngineResult`.

2. **Action Templates Resolve Base Phrasing:** The outcome code matches against templates in `feedback.json` (either colocated within the verb or in shared fallbacks).

3. **Dialects Inject Personality:** `DialogueResolver` takes the chosen raw template and replaces bracketed placeholder tokens (e.g. `{wedge}`, `{shut}`, `{done}`, `{tired}`) with authentic slang selected from the assigned dialect profile.

This keeps game mechanics, scenario balancing, and narrative voice completely decoupled: new accents and slang lexicons can be created without altering a single line of GDScript.

---

## 2. Directory Layout & File Conventions

All dialect definitions are stored as standalone JSON files in `res://data_modules/core/dialects/` using `lowercase_snake_case` filenames:

```text
res://data_modules/core/dialects/
 ├── README.md                      <-- This document
 ├── brummie_street.json            <-- Midlands / Birmingham street distribution slang
 ├── formal_clerk.json              <-- Standard commercial / accounting vernacular
 └── cockney_dockside.json          <-- East London trade / dockside vernacular

```

---

## 3. Dialect Schema (`dialect_profile.json`)

Each dialect JSON profile consists of an identity block, token replacement pools, and optional sentence affixes:

```json
{
  "id": "DIALECT_BRUMMIE_STREET",
  "name": "Midlands / Brummie Street",
  "replacements": {
    "{boss}": ["boss", "gaffer", "chief"],
    "{wedge}": ["wedge", "readies", "notes", "cash"],
    "{shut}": [
      "the shutters was down",
      "locked up tight",
      "all closed up",
      "doors was bolted"
    ],
    "{done}": ["sorted", "put away", "bang on", "in the lockup"],
    "{tired}": ["knackered", "proper done in", "wiped out"],
    "{waiting}": [
      "kicking me heels",
      "hanging about",
      "stood around like a spare part"
    ],
    "{night}": ["half the night", "gone past dark", "ungodly hours"]
  },
  "affixes": {
    "openers": ["Listen {boss},", "Tell you what,", "Right then {boss},"],
    "closers": ["Know what I mean?", "Proper nightmare.", "All safe though."]
  }
}
```

### Schema Properties

| Key  | Type                            | Description                                                                                                                   |
| ---- | ------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `id` | String (`SCREAMING_SNAKE_CASE`) | Unique technical token referenced by staff records, NPC profiles, or district dialogue pools (e.g. `DIALECT_BRUMMIE_STREET`). |

|
| `name` | String | Readable display label for tools, debug inspectors, and character generation.

|
| `replacements` | Dictionary (`Token: Array[String]`) | Slang glossary. Each key is a bracketed token (e.g. `{wedge}`); the value is an array of regional variations randomly chosen during resolution.

|
| `affixes.openers` | Array[String] | Optional introductory phrases prepended to memos or verbal reports based on staff loyalty or agitation. May include embedded replacement tokens.

|
| `affixes.closers` | Array[String] | Optional trailing phrases appended to the end of a report.

|

---

## 4. Standard Token Glossary

To ensure universal compatibility across all action feedback files (`feedback.json`) and shared outcome matrices, dialect profiles should implement the standard token set:

| Token    | Semantic Intent                           | Example Brummie Replacement | Example Formal Replacement |
| -------- | ----------------------------------------- | --------------------------- | -------------------------- |
| `{boss}` | Direct address to the player / supervisor |

| "gaffer", "chief"

| "Sir", "Manager" |
| `{wedge}` | Cash, operating capital, currency

| "wedge", "readies"

| "capital", "funds", "liquidity" |
| `{shut}` | Venue or supplier closed / locked out

| "the shutters was down"

| "closed outside operational hours" |
| `{done}` | Task or transaction completed

| "sorted", "bang on"

| "executed", "finalised" |
| `{tired}` | Operator exhaustion / burnout

| "knackered", "proper done in"

| "fatigued", "exhausted" |
| `{waiting}` | Idle operational delay

| "kicking me heels"

| "delayed in transit" |
| `{night}` | Overtime / late-shift operations

| "half the night"

| "outside scheduled shift hours" |

---

## 5. Resolution Lifecycle (`DialogueResolver.gd`)

Narrative resolution runs through a 4-pass replacement pipeline in `DialogueResolver`:

```
┌────────────────────────────────────────────────────────┐
│               1. RAW FEEDBACK TEMPLATE                 │
│  "Turned up to buy {target_item}, but short on {wedge}"│
└───────────────────────────┬────────────────────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────┐
│             2. CONTEXT VARIABLE INGESTION              │
│  Injects dynamic amounts, commodity names, and venues  │
│  "Turned up to buy Rolling Tobacco, but short on {wedge}"
└───────────────────────────┬────────────────────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────┐
│             3. DIALECT SLANG REPLACEMENT               │
│  Selects random synonym from dialect["replacements"]   │
│  "Turned up to buy Rolling Tobacco, but short on readies"
└───────────────────────────┬────────────────────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────┐
│               4. AFFIX & LOYALTY STYLING               │
│  Optionally prepends openers / appends overtime notes  │
│  BILLY: "Listen gaffer, Turned up to buy Rolling       │
│  Tobacco, but short on readies."                       │
└────────────────────────────────────────────────────────┘

```

---

## 6. Authoring Guidelines for New Dialects

1. **Keep Tokens Focused:** Tokens represent parts of speech or thematic slang categories, not entire clauses. Keep template text in `feedback.json` grammatical so any synonym fits naturally.

2. **Provide Multiple Synonyms:** Include at least 3 variations per replacement token to minimize repetitive dialogue across long shift cycles.

3. **Avoid Punctuation in Replacements:** Punctuation belongs in the parent feedback template or affix strings, not inside individual glossary terms (e.g. use `"readies"`, not `"readies."`).

4. **Recursive Token Safety:** Opener and closer affixes may contain tokens (e.g. `"Listen {boss},"`); the engine executes a secondary pass to resolve nested tokens before finalizing output.
