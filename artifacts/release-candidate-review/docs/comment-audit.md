# Plain source comments — the audit

**What this file records:** what was scanned, what was rewritten, what was
deliberately kept, and what is still owed.

## Scans used

Three targeted scans over maintained production code, tests, examples and tools,
excluding `artifacts/`, `docs/superpowers/` and `vendor/`:

```sh
# finding / gate / row codes in module headers (first 40 lines of every src file)
python3 - <<'PY'   # re: \b([A-Z]{2,5})-([A-Z]?\d{1,3})\b
PY
# vendor language (the other half of this wave)
python3 tools/check_brand_drift.py
# writing-style violations in the human-facing guide set
python3 tools/check_doc_style.py
```

## Before and after

| Scan | Before | After |
|---|---|---|
| Finding/gate/row codes in `src/` module headers | 88 | 29 |
| …of those 29, requirement ids that resolve in `requirements.json` | — | 22 |
| …true finding codes still present | — | 7, all in the five extraction-locked modules |
| Bare artifact row ids in `docs/guide` + `docs/extending` | 21 | 0 |
| Unexpanded acronyms in the same set | 9 | 0 |

## What was rewritten

The rule applied: a comment may keep an exact API name, a Roblox class name, a
mathematical term, a measured number and a platform constraint. It may not keep
a code that only resolves inside this repository's private ledgers.

- **Row and finding codes became the fact they stood for.** `row SF-A1` became
  "a failed image keeps its placeholder"; `platform verifier PLAT-6` became
  "measured on a real client"; `reuse audit REUSE-1, REUSE-39` became "one home
  for a shared predicate"; `verifier RT-1 / ARCH-2` became nothing, because the
  sentence around it already stated the measured fact. 63 source files changed.
- **`ADR-nnnn` citations were kept everywhere.** An ADR is a document a reader
  can open, it is numbered on purpose, and the writing checker allowlists it with
  that reason.
- **Requirement ids (`UI-INPUT-001`, `UI-STYLE-001`, …) were kept.** They resolve
  in `requirements.json`, which ships.
- **Two stale factual claims were corrected, not just reworded.**
  `src/client/roblox_input.luau` claimed both `InputAction:Fire()` and
  `GetState()` were deprecated; only `Fire()` is. The comment now says which,
  and dates the re-read.
- **One ghost class was removed.** `src/themes/package.luau` pointed at
  `UI.Custom`, a class that was reserved and never shipped. The class that did
  ship for that job is `UI.Foreign`.
- **Device identities in measurement records became device CLASSES plus the
  measured number.** "iPhone 16 Pro landscape (749x380)" became "a compact phone
  in landscape (749x380)": the number is the fact, the model name was decoration,
  and the dated report under `artifacts/` still holds the full identity.

## What was deliberately kept

- Exact API names, Roblox class names, engine property names, and the units and
  numbers a measurement produced.
- `docs/lessons/…` links, where a comment has one. The lesson is the durable
  history the plan asks for; the comment is the one short link to it.
- Long explanatory headers. The plan asks for plain language, not for fewer
  words: a header that states what a module owns, what it receives and returns,
  and what must clean it up is doing its job at any length.

## What is still owed

1. **The five extraction-locked modules** (`table`, `solver`, `renderer`,
   `presenter`, `virtual_list`) were not touched, because concurrent extraction
   work holds them. Together they carry the last 7 header finding codes and
   roughly 70 vendor-language comment lines. Both are named in the
   `check_brand_drift` allowlist with a removal trigger.
2. **The gate manifest's note prose** is exempt this wave by instruction: its
   restructure is owned by a later step. Its vendor language WAS swept, because
   that rule has no such exemption.
3. **A latent trap found while doing this work, and worth its own line.**
   `tools/lune/check_prop_parity.luau` derives an exported type's field set with
   a hand-rolled scanner that does not strip comments. Rewriting one comment
   inside `BoxProps` from "`hidden()`: keep the layout box" to "the
   space-reserving hide: keep the layout box" made the scanner see a field named
   `hide` on 22 spec types, and the suite went red on all 22. The comment was
   reworded to dodge it; the scanner still cannot tell a comment from a field.
