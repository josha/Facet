# Task — navigation-and-menus gate repair (pin re-point round)

`tools/gate.sh navigation-and-menus` was **FAIL_RECOVERABLE on six rows**. It is
now **PASS, 14 of 14**. No row was a real regression: **nothing had to be
reported under class (c)**.

**Commits** (both on `main`, via `tools/commit_isolated.py`):

| Commit | Subject | Files |
|---|---|---|
| `84bf1fb` | two gate instruments that could not see their own blind spots | 2 |
| `d7d97bf` | five gate rows that had stopped asking, and the one export nobody filed | 5 |
| `a762cd9` | the four re-pointed rows say, in place, which ruling moved the world | 1 |
| `8594ef1` | three gate clauses that ran a module and called it a check | 2 |

`d3a-help` was not touched. Each re-pointed row records its own supersession in
its manifest `note` (`a762cd9`), so the next reader does not have to find this
file to know why the pin says what it says.

---

## Per-row outcomes

| Row | Was | Class | What it actually was | Now |
|---|---|---|---|---|
| `d0-cache-guards-bite` | FAIL_RECOVERABLE | instrument race | one selftest case (`a transcript mutated on disk after caching is refused`) measured a cache MISS instead of a refusal | **PASS** (28/28) |
| `d0-greps-still-match` | FAIL_RECOVERABLE | (a)+(b) ×3 | three stale patterns in **other** gates: one product-language rename, two under ruling R20 | **PASS** (1518/1518) |
| `d2-menu` | FAIL_RECOVERABLE | (b) | `check_surface_ledger` red on a new public member nobody filed | **PASS** |
| `d3b-callout` | FAIL_RECOVERABLE | (b) | same `check_surface_ledger` clause | **PASS** |
| `d5-tabview` | FAIL_RECOVERABLE | (a) | ADR-0037 restructured `src/init.luau`; the export pin named the old shape | **PASS** |
| `d6-segmented` | FAIL_RECOVERABLE | typo | a dropped `"` made the whole run string a bash syntax error | **PASS** |

Method: every red row's `run` string was extracted from the manifest (Lua
escapes unescaped exactly as `gate.luau`'s `process.exec("bash", {"-c", run})`
hands them to the shell), split at top-level `&&`, and executed clause by clause
in one shell so `cd` and `out=` state survived. That is what located each fault
to a single clause rather than to a row.

---

## 1. `d6-segmented` — a dropped quote, and twenty-two dead clauses

The failing clause was not a pin. It was this, in the manifest:

```
grep -qF "all options in a group, or none of them src/controls/picker.luau && …
```

The closing quote is missing. `1482571` ("a directory is a filing decision…",
2026-08-21) deleted it, and the diff of that commit against this run string
contains **nothing else** — a pure typo in a commit about file locations.

The consequence is larger than one pin. bash refused the entire run string
(`unexpected EOF while looking for matching '"'`), so **every clause after the
typo had not run since 2026-08-21**: three picker source pins, two api.md pins,
the parity-document pin, the negated device-name scan, the theme-baseline pin,
`check_docs`, `check_theme_drift_cli`, `check_source_size`, and **all eight
Rascal Rally suite greps**.

Quote restored. With the tail alive again, **all 52 clauses pass unchanged** —
nothing behind the typo had drifted, which is the only reason this was one day's
damage rather than a week's.

**Noted, and closed mechanically** (see §6): neither existing guard could see
this. `check_gate_pins` compares needles to files and every needle it could
parse was fine; `check_manifest_integrity` checks anchoring and matching and
every pattern was anchored and matching. A row can be *syntactically dead* while
both of its guardians report green.

## 2. `d5-tabview` — ADR-0037 moved the export, not the control

Failing clause: `grep -q "newTabView = require" src/init.luau`.

`8691380` ("the library stopped introducing itself to its own builders",
ADR-0037) hoisted every control's `require` to the top of the file and added the
`Facet.Controls` namespace. The line the pin named no longer exists; the control
is exported twice over, in both the compatible and the canonical spelling.

Verified before re-pinning: `newTabView` is live (`src/init.luau:549`), the
module is bound (`:75`), the canonical entry is typed (`:394`), the deprecation
row names its replacement (`:231`, `:234`), and the suite's own TabView cases —
28 of them in this row — all pass.

Re-pinned to four literals, which is **stronger** than what it replaced:

```
grep -qF "local tabView = require(" src/init.luau
grep -qF "@self/controls/tab_view" src/init.luau
grep -qF "newTabView = tabView.build" src/init.luau
grep -qF "TabView = function(core: any, spec: tabView.Spec)" src/init.luau
```

The old pin proved one assignment existed. These prove the module is bound, the
compatible alias is exported, and the `Controls` entry is present and typed
against the control's own `Spec` — the wrong-builder wiring ADR-0037's own
commit message calls the thing a test has to catch.

**A trap met en route, and it is worth writing down.** The first re-pin was
written with `\"` inside the needle. That is a valid Lua escape, so Lua hands
bash a *bare* quote and the shell concatenates — `require("@self/x")` becomes the
needle `require(@self/x)`, which matches nothing. It measured green only because
the extraction harness had not yet unescaped the way Lua does. **A gate pin must
never contain a nested quote**; the shipped pin uses none.

## 3. `d2-menu` and `d3b-callout` — one unfiled export, two rows

Both rows run `lune run tools/lune/check_surface_ledger`, which was red on:

```
nested member 'themes.paintForDisplay' is not classified in the surface ledger
```

This is a **real new public member**, not a rename: `c4d0591` ("one number owns
the corners now…") added `themes.paintForDisplay` under **ADR-0040 row B-17**
(director ruling, 2026-08-21) as `themes.forDisplay`'s paint-side twin — one
derivation for radii and strokes, spent by `sheet_model`, `screen_target` and
`theme_controller`. It is documented in `docs/reference/api.md:5630` and guarded
by `tests/ten_foot_metrics.spec.luau`; the only thing missing was its ledger row.

The instructive comparison is one day earlier: `35f7348` added
`themes.forDisplay` **and its ledger row in the same commit**. That is the
discipline; `c4d0591` is the one that skipped it, and skipping it turned two
navigation-and-menus rows red for a change neither row is about.

`artifacts/api-architecture-consistency/surface-ledger.md` now carries
`themes.paintForDisplay` in the Styling row, with the superseding commit and
ruling named in the dispositions cell. `check_surface_ledger: PASS`.

## 4. `d0-greps-still-match` — the meta-check working exactly as intended

This row runs `check_manifest_integrity.py --transcript` over the **whole**
manifest, so it was red on three patterns belonging to *other* gates. All three
are renames by ruling, and each was checked against the spec body before being
re-pointed.

**`swiftui-parity-round2` / `parity-doc-falsifiable`**

`the live parity document passes…` → `the live comparison document passes…`
(`tests/theme_docs.spec.luau:361`). Renamed by `fa5c889`, the product-language
sweep: the framework may not use another vendor's name as the name or the reason
for a feature, and the one dedicated **comparison** document is the single
carve-out. Same case, same assertion, one word of product language. The sibling
pattern in this row that still says *parity* (`fails when the parity document
loses the citation convention itself`) is untouched and still matches.

**`swiftui-parity-round3` / `chrome-four-inputs-and-settings`, two patterns**

Both are **ruling R20** (2026-08-21), which took `ButtonY` off the showcase
chrome because it is `menu.luau`'s gamepad menu verb.

- `the pad.s toggle button opens the panel and engages it — with no keyboard
  anywhere` → `the pad.s shoulder opens …`. The case body
  (`tests/gallery_chrome.spec.luau:548`) still asserts exactly the old property —
  a pad-only capability set opens the panel, engages it, and lands focus inside
  it — driven through `SECTION_GAMEPAD.demos`, which is the route the chips now
  advertise with a glyph. Strictly the same claim on the route a pad-only player
  is actually told about.
- `binds exactly the two documented keys` → `three documented keys`
  (`:720`). This one got **stronger**: the keys are now one keyboard toggle plus
  two pad section doors, and `ButtonY` **moved into the contended set** the case
  sweeps — so the case now also proves the chrome does not steal the framework's
  menu verb. R20 backs it with three further cases (`a context bound exactly as
  menu.luau binds it still receives ButtonY`, the live `menu` scenario, and `the
  export says so: there is no gamepad toggle key to name`).

Both rows re-run green end to end (7/7 and 19/19 clauses).
`check_manifest_integrity --transcript`: **1518 of 1518** patterns match a green
transcript, 0 matching zero lines.

## 5. `d0-cache-guards-bite` — a race in the instrument, not a drift

The row ran green on the first standalone re-run, which is itself the finding.
The gate's stored detail names the single failing case: `a transcript mutated on
disk after caching is refused`.

Read against `tools/test.sh`, the case has exactly two outcomes and no third:

- the synthetic entry is a **HIT** → the corrupted transcript is read, `passed`
  is empty, `--ensure-cache` refuses, `suite_transcript.sh` prints nothing and
  exits 1 → the case passes, deterministically;
- the entry is a **MISS** → `tools/test.sh` re-runs the real suite, which is
  green, and serves it → the case fails, deterministically.

So the only way it fails is a fingerprint change between keying the entry and
reading it — the window `suite_fingerprint`'s own header documents (a sibling
agent's temp file, listed by `find` and gone before `shasum` opens it, measured
2026-08-16 with four agents in one tree). **Five other cases and three Rascal
Rally cases share the identical shape**, and the Rascal Rally ones have a wider
surface still, because their fingerprint covers `GameStudio/ui/Facet` too.

Fixed rather than re-run: the race is detectable **exactly**, after the fact. A
miss is the only path on which either helper writes, and it writes an entry keyed
by the *current* fingerprint — so a case dir holding a **second** entry is a case
that raced. All ten cases now re-key and retry (3), and a tree that keeps moving
reports `nothing was measured` rather than a verdict.

Both directions of the discriminator are asserted as named cases, without paying
for a suite run. Mutation: stubbing `served_a_miss` to always-true reddens all
ten cases with the retry message — the loop is wired everywhere it claims to be.

Selftest **26 → 28 assertions, 0 failed**.

## 6. The malformed-quote class, closed

`tools/check_gate_pins.py` now **parses every run string with `bash -n`**, which
executes nothing. Supporting fix: two `studio-evidence` rows build their command
from Lua literals joined by `..`, so `run_strings` concatenates fragments —
reading only the first truncates a command mid-quote and would report the
reader's fault as the manifest's.

Mutation, on a scratch copy of the **live** manifest with `1482571`'s exact typo
replanted:

| Arm | Result |
|---|---|
| typo replanted | `malformed = 1` — `unexpected EOF while looking for matching '"'` |
| restored tree | `malformed = 0`, `broken = 0` |

`--selftest` gains the dropped-quote case and passes. Live:
`check_gate_pins: PASS — 260 gate file pins match the tree, and all 487 run
strings parse`.

---

## 7. Scope addendum — three clauses that ran a module and called it a check

Purity-sweep review MED-1, folded in mid-round. `lune run tools/lune/check_docs`
and `lune run tools/lune/check_theme_drift` name modules that end in
`return checker`: lune builds the module, returns it, and exits 0 whatever the
tree says. `check_theme_drift_cli`'s own header already records that trap for its
own file — these were the three call sites still standing in it.

**Measured, not reasoned about**, in a content-pinned copy (`tools/mkpair.sh`,
`PIN_FACET 1c0103b`), so no live file was ever mutated:

| Mutation planted in the pinned copy | Clause | Result |
|---|---|---|
| `docs/reference/api.md` drops one public export (`themes.paintForDisplay`) | `lune run tools/lune/check_docs` | **exit 0**, 0 bytes |
| " | `lune run tools/lune/check_docs_cli` | exit 1, names the undocumented export |
| `textSize = 17` in `src/controls/chip.luau` | `test -f tools/lune/check_theme_drift.luau` | **exit 0** ← what the row did |
| " | `lune run tools/lune/check_theme_drift` | **exit 0**, 0 bytes |
| " | `lune run tools/lune/check_theme_drift_cli` | exit 1, names `chip.luau:25` |

A note on the first mutation, because it nearly produced a false green: renaming
`paintForDisplay` to `paintForDisplayXX` did **not** redden the cli — the
documentation anchor is a substring match, so the mutated name still contained
the real one. The mutation only bites when the replacement shares no prefix. A
mutation that does not bite is not evidence, and this one had to be redesigned
before it was.

Swapped:

- `d3b-callout` and `d6-segmented` → `lune run tools/lune/check_docs_cli`;
- `controls-semantic-roles` (gate `theme-packages-and-skinning`) →
  `lune run tools/lune/check_theme_drift_cli`.

The third is the worst of the three and its note now says so: the row asserted
that the **linter file exists** while its headline claim is that the lint fired
on 21 real violations. A control hardcoding a theme-owned metric tomorrow would
not have reddened it. `controls-semantic-roles` runs the lint for the first time
as of this round.

All three rows re-run green on their own run strings (52, 52 and 4 clauses),
`check_manifest_integrity` (both modes) and `check_gate_pins` are clean, and the
navigation-and-menus gate re-runs PASS 14/14 after the swap.

---

## Verdict

```
tools/gate.sh navigation-and-menus
  PASS  d0-one-run-per-sweep        PASS  d4-sliding-indicator
  PASS  d0-cache-guards-bite        PASS  d5-tabview
  PASS  d0-greps-still-match        PASS  d6-segmented
  PASS  d1-anchored-surface         PASS  d7-elision-discloses
  PASS  d2-menu                     PASS  d8-playlist-sort-resize
  PASS  d3a-help                    PASS  rider-rascalrally-consumer
  PASS  d3b-callout                 PASS  physical-and-human-rows
gate: PASS -> artifacts/navigation-and-menus/gate.json
```

`check_manifest_integrity` (both modes) and `check_gate_pins` (plus
`--selftest`) run clean after the manifest edits, as the standing rule requires.

**Rascal Rally.** No `src/` change, no public-contract change, no defaults or
behaviour moved, so no production-game edit is owed. The consumer evidence this
round produces is that the **fifteen game-side suite greps in `d5` and `d6` now
actually execute** — eight of them had been dead behind the typo — and pass
against the game's own cached transcript (`3469 passed`).

**Prior sweep.** `tools/prior_gates.sh … release-candidate-review` was started in
the background at the close of this task; its roll-up is the input the release
gate's re-run wants. Result recorded at the bottom of this file when it lands.
