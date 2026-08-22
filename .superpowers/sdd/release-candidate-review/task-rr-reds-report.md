# The RR "3462/2" reds — bisected by pair, and RETRACTED

**Status: DONE. Verdict (c) — a harness/pairing artifact. No framework
regression, no stale game-side pin, no code change on either side.**

The two reds are real reds, they reproduce byte-for-byte, and they are **not the
tests the record names**. They are what a pair built with **Facet pinned seven
commits behind the RR commit that requires it** produces, and they vanish the
moment the pair is built honestly. The finding is retracted, the record is
corrected, and the recipe that prevents the fourth occurrence is written down.

---

## 1. Root cause

The overflow-guard round measured RascalRally in a mirrored tree whose Facet side
was **`git archive 4f86ac5`** while its RR side was the working tree at
**`4fdb0e6`**. Its own report says so in the sentence above the numbers:

> **RascalRally**, run in a mirrored tree (`GameStudio/ui/Facet` = archive at
> `4f86ac5`, RR at working tree)
> — `task-overflow-guard-report.md` §6

`4f86ac5` is **not** Facet HEAD at that moment. Facet HEAD was `3183740` (the
round's own repair commit, 18:24) and the report landed as `6addc5e` (18:29);
`4f86ac5` is 18:07, **seven commits earlier**. In particular it is one commit
*before* **`4110ba1`** (18:15, "the input primacy stops flapping"), the DIR5 fix
to `src/client/roblox_env.luau`.

RR `4fdb0e6` (18:15, "the pad that is merely plugged in stops seeding this game's
focus ring") is the **consumer rider for that exact fix**. Its two cases drive
Facet's real `roblox_env.bind` against a fake pad-desktop engine and assert the
predicate `FacetSponsor/init.luau:686` runs:

```luau
local function gameSeedsFocus(env: any): boolean
    return env:get("effectiveInput"):get() == "Gamepad"
end
```

Against a Facet that predates `4110ba1`, a merely-connected pad still claims
`effectiveInput == "Gamepad"`, so the game seeds the ring for a mouse player —
and the rider's positive control fails on its own precondition line too. Two
reds, **3462 passed / 2 failed**.

The pair was arranged so that the game's proof of a framework fix was run against
a framework that did not have the fix. That is the whole mechanism.

## 2. The culprit commit

**There is none — no commit broke anything.** The break was introduced by the
*measurement*, not by a change. Named precisely:

| | |
|---|---|
| the pin that fabricated the reds | Facet **`4f86ac5`** (should have been HEAD, `3183740`) |
| the Facet commit the RR side needs | **`4110ba1`** — `src/client/roblox_env.luau`, the DIR5 input-primacy fix |
| the RR commit that requires it | **`4fdb0e6`** — `tests/facet_composition_collision_contract.spec.luau:495-521` |
| the record that must be corrected | `task-overflow-guard-report.md` §6, and `progress.md` "post-close 15" |

The spec names in the record — `facet_large_text_sweep` (NameTag) and
`facet_large_text_results` (Ctas) — are a **misattribution**. Neither of those
files fails in that pair, or in any pair measured below.

## 3. Evidence

### 3.1 The reported failure reproduces exactly, at the reported pin

Pair rebuilt from two `git archive`s, nothing from any working tree:
Facet `4f86ac5c977ae254fc530b9c4eb6f6567c3d3c6c` + RR
`4fdb0e69cb88bb6d7c02c1f1e840a8633f904be6`, full `lune run tests/run`:

```
Facet consumer rider: a merely-connected pad no longer seeds this game's focus ring
  ✗ a mouse player with idle pads does NOT get the pad's seeded ring
      …/tests/facet_composition_collision_contract.spec:502: expected the game
      seeds focus: true to be the game seeds focus: false
  ✗ POSITIVE CONTROL: a real pad press still seeds it
      …/tests/facet_composition_collision_contract.spec:516: expected true to be false

2 failed, 3462 passed
```

**`2 failed, 3462 passed` — the reported number, to the unit.** The two reds are
in `facet_composition_collision_contract.spec`. `facet_large_text_sweep` and
`facet_large_text_results` are **green** in that same run, all 46 cases.

### 3.2 The bisect names the pin, not a regression

RR held at `4fdb0e6`; only the Facet side of the pair moves. Running only
`facet_composition_collision_contract.spec`:

| Facet pin | result |
|---|---|
| `b52d220` | **2 failed**, 15 passed |
| `fa0be0c` | **2 failed**, 15 passed |
| `4f86ac5` ← the round's pin | **2 failed**, 15 passed |
| `66b49de` | **2 failed**, 15 passed |
| **`4110ba1`** ← the DIR5 fix | **17 passed** |
| `5a43992` | 17 passed |
| `6addc5e` | 17 passed |
| `435dade` | 17 passed |

One clean edge, on the commit that carries the fix the RR rider was written
against. The transition is not a regression entering — it is the fix **arriving**.

### 3.3 The two accused specs are green everywhere

`facet_large_text_sweep.spec` + `facet_large_text_results.spec` (46 cases), RR
held at `4fdb0e6`, run against **every** Facet commit from `b52d220` through the
current HEAD:

```
b52d220 fa0be0c 4f86ac5 66b49de 4110ba1 5a43992 bb3b801 e74e5fe cb80693 06c6053
19dc1cb 3183740 6addc5e c289a6f 847ff3e 435dade 41e6829 7a09cb7 9cce13e c93e80e
                                                                   → 46 passed, every one
```

Twenty pins, spanning every candidate the brief listed (the overflow guard, the
constructor census, the flip fix, the DIR5 fix, the solver split, the plate-B
work) — **no red, ever**. The paint-family derivation and the constructor-census
`displaySize` wiring both pass through this window and neither moves a number
these fixtures measure.

### 3.4 …and green in the full suite too, at the round's own commits

Full RR suite, RR `4fdb0e6`, Facet side from `git archive`:

| Facet pin | RR suite |
|---|---|
| `19dc1cb` (the overflow guard itself) | **3464 passed, 0 failed** |
| `3183740` (its repair; HEAD at report time) | **3464 passed, 0 failed** |
| `6addc5e` (the report commit) | **3464 passed, 0 failed** |
| `435dade` (solver split + containment) | **3464 passed, 0 failed** |
| `368f69e` (HEAD at close) | **3464 passed, 0 failed** |

So at the tree the round actually committed, RR is **3464/0**. The "pre-existing
at Facet HEAD on an unmodified pair" claim is false in both halves: the pair was
not at HEAD, and the reds were not pre-existing.

### 3.5 Why "byte-identical with and without the change" was consistent with the wrong answer

It was — and it proved only that the overflow guard touched no `src/`, which is
true. Both arms of that A/B carried the same stale Facet, so the mis-pin was
common-mode and cancelled out of the difference. **A difference measurement
cannot see a defect that is in both arms.** That is why the absolute number, not
the delta, is the thing that has to be pinned.

## 4. Verdict — RETRACTION, in one sentence

> The RR reds recorded on 2026-08-21 were fabricated by a pair whose Facet side
> was pinned at `4f86ac5`, seven commits behind the `4110ba1` fix that RR
> `4fdb0e6`'s own rider exists to prove; RR is **3464/0** against every Facet
> commit from that round onward, `facet_large_text_sweep` and
> `facet_large_text_results` never failed, and there is nothing to fix.

No framework change. No RR re-verdict — the two RR cases that reddened are
**correct and load-bearing**, and their reddening under a stale framework is
exactly the tripwire they were written to be. Nothing is papered over: the reds
were real, they were caused by the harness, and the harness is what is corrected.

## 5. The root fix: build the pair, never assemble it

This class has now bitten **three times in one day** (the DIR5 review's three
`facet_theme_paint_contract` reds; this round's two; and the report notes a third).
Every occurrence is the same shape: a Facet archive pinned by hand at a sha that
was HEAD *when the agent started* rather than when it measured, against an RR side
that moved underneath. The measurement is the only place either repo's HEAD is
read, so the two reads have to happen in one step.

Recommended (offered, not landed — it is a shared-tools addition and belongs to
whoever owns `tools/`):

```bash
#!/usr/bin/env bash
# mkpair.sh <name> <facet-ref> <rr-ref>  — a content-pinned export PAIR.
# Both sides come from `git archive`; neither working tree is ever read.
set -euo pipefail
PAIR="$SCRATCH/pairs/$1"; rm -rf "$PAIR"
mkdir -p "$PAIR/GameStudio/ui/Facet" "$PAIR/games/RascalRally/code"
git -C "$FACET_REPO" archive "$2" | tar -x -C "$PAIR/GameStudio/ui/Facet"
git -C "$RR_REPO"    archive "$3" | tar -x -C "$PAIR/games/RascalRally/code"
git -C "$FACET_REPO" rev-parse "$2" > "$PAIR/PIN_FACET"   # the pin is an ARTIFACT
git -C "$RR_REPO"    rev-parse "$3" > "$PAIR/PIN_RR"      # not a memory
```

The layout is forced by RR's own resolution — every RR spec reaches the framework
as `require("../../../../GameStudio/ui/Facet/…")` — so a pair is exactly these two
directories under one root, and the two `PIN_*` files are what makes a mis-pin
visible in the artifact instead of invisible in a transcript.

Two smaller notes from this round, both worth keeping:

* **Run the accused specs alone first.** RR has no spec filter; a six-line
  `tests/run_two.luau` requiring only the two files turns a 45 s suite into a 4 s
  probe and made a 20-pin sweep affordable. It also immediately separated
  "order-dependent" from "not our specs at all".
* **`2 failed, 3462 passed` matching is not identification.** The count matched
  the record exactly while naming completely different tests. Read the `✗` lines,
  not the summary.

## 6. Suite tails — pinned pair of final HEADs

Pair: Facet **`368f69e6bf095913c6b6425f1cfa0b81b52d6a8d`** + RR
**`4fdb0e69cb88bb6d7c02c1f1e840a8633f904be6`**, both `git archive`, neither
working tree read (three rounds are mid-flight in Facet's).

**RascalRally** — `lune run tests/run`:

```
  ✓ THE PRESET DID NOT DRIFT: newRating is still count 5, ★/☆, starSize and dump/1
  ✓ the spec is CLOSED here too: an unknown key is an authoring error in this build
  ✓ TRIPWIRE: no shipped Rascal Rally source builds a rating or a level picker yet
  ✓ POSITIVE CONTROL: in THIS build the strip is a 44px thumb target with ONE focus stop

3464 passed
```

**Facet** — `lune run tests/run`, from the same archive:

```
  ✓ ...and a fixture that states WHY it is exempt is not
overflow guard: the waiver registry cannot rot
  ✓ a matching waiver silences its violation and is counted as used
  ✓ ...and the same waiver with a smaller cap refuses, naming itself in the message
  ✓ NEGATIVE CONTROL: a waiver that matches nothing is NAMED as unused
  ✓ every waiver in the shipped registry fired at least once across this suite

7000 passed
```

### 6.1 Re-measured after both HEADs moved underneath this task

Facet's HEAD moved **six** times while this task ran and RR's once, which is
precisely why every number here names its sha rather than saying "HEAD". After
this report's own commit landed, two later Facet commits touched `src/` —
`src/client/roblox_env.luau` and `src/layout/measure_facts.luau`, **comment text
only** (`check_comment_codes` prose), verified by reading the diff. Rather than
argue that a comment cannot move a number, the whole pair was rebuilt and both
suites re-run.

Pair: Facet **`ba5be7bf87ef5abaaecda364b8dfe1a1ceb72fce`** + RR
**`cae4c7a2b352a4363439b57bb1fc53749e3d41a4`**, both `git archive`.

| | |
|---|---|
| Facet | **7000 passed, 0 failed** |
| RascalRally | **3465 passed, 0 failed** |

RR is 3465 rather than 3464 because RR's own `cae4c7a` ("the plates this game
rounds by name now round at distance too") adds one case. Both numbers are green
on both pinned pairs, five minutes apart, across a `src/` change and an RR
commit — the retraction does not depend on which of them you take.

`stylua`: **N/A** — this task wrote no `.luau`. The only files it changes are this
report and an erratum block in `task-overflow-guard-report.md`.
`check_doc_style`: **PASS** (23 documents).

Commits: **`d0e554e`** — the report and the erratum — and one follow-up carrying
§6.1, the re-measurement forced by both HEADs moving underneath the first one.

## 7. Files touched

| file | why |
|---|---|
| `.superpowers/sdd/release-candidate-review/task-rr-reds-report.md` | this report |
| `.superpowers/sdd/release-candidate-review/task-overflow-guard-report.md` | an erratum block at §6, so the false finding cannot be read again as fact |

No `src/`, no `tests/`, no RR file. The in-flight files the brief fenced
(`src/region_expand.luau`, `src/layout/*`, `src/themes`, gallery init) were read
only, and none of them is implicated: §3.3 crosses every one of their landings
green.
