# Handoff — live work owed by the SCREEN-X sticky-tag fix

**Written:** 2026-08-22, end of the SCREEN-X fix round. **For:** the director, or
a fresh context running the next Studio session.

Read this, then `docs/guide/11-device-verification.md` §"The hands-on place".

---

## 0. The one-paragraph state

`syncTags` — the one function that owns every `facet-*` classification tag on an
instance — could not REMOVE one between 2026-08-18 and 2026-08-22. ADR-0038
renamed the tags `luau-*` -> `facet-*`, the sweep rewrote 395 literals and left
every hand-counted length, and a five-character `string.sub` against a
six-character literal is a CONSTANT: the removal half was dead code and the
function was purely additive. Every classification tag a node ever wore stayed on
it for the node's whole life — surface, selection, role, toggle, error, shape,
typography, skinned slot.

**It is fixed** (`src/render/tag_sync.luau`, a pure ruling both targets call, with
the length read off the literal). It is proved headlessly
(`tests/tag_sync.spec.luau` mounts, changes state and asserts the removal;
`tests/prefix_tests.spec.luau` scans the repository for the shape) and in a live
Roblox engine at the tag layer
(`artifacts/framework-gaps-phase2/screenx-tag-removal-live.txt`).

**What is NOT proved is paint.** Four things below need a session. Nothing here
blocks the fix; all four are confirmations and re-captures.

---

## 1. The tab-view demo, on glass — THE ONE THAT MATTERS

The reported symptom (FIX-SHOW round, Bugs A and B): the app bar's 4px underline
indicator and the page bar's pill were covered by opaque tab plates, because a
segment declared `surface = "plain"` kept `facet-surface-control` and the sheet
painted a `$Control` fill over the indicator `selection_indicator.luau` draws
BEHIND the strip.

```bash
cd GameStudio/ui/Facet
tools/build_places.sh          # already run 2026-08-22; re-run if the tree moved
```

Open `examples/places/Facet-Showcase.rbxl` **fresh** (a Studio session left open
from an earlier run holds pushed sources older than the tree), press Play, and
select the `tab-view` demo.

**Check, at rest AND mid-flight:** the app bar shows its full underline under the
selected tab; the page bar shows its pill; neither flashes or disappears while
the indicator slides between segments. Compare against
`artifacts/framework-gaps-phase2/bugAB-red-tabview.png` (the defect) and
`bugAB-green-tags-removed.png` (the same screen with the tags removed by hand —
which is what the fix now does by itself).

## 2. A sweep of the showcase's other demos

The defect was framework-wide, not tab-specific: selection, hover eligibility,
button role, toggle value, error state, shape, typography role and skinned-slot
tags were ALL sticky for four days. Every one of them un-applies now, which
changes paint anywhere a removal was intended. The tab strip is the one someone
reported; the rest were never looked at with this in mind. Walk the demo
catalogue once and look for anything that now paints differently — especially
pickers, toggles, destructive buttons and any control that changes `surface`.

## 3. A performance-lab re-capture — thirteen rows carry a blind census

`examples/gallery/scenarios/runner.luau`'s M3 instance census had the SAME defect
from the other direction (`LuauUI` -> `Facet`, six characters to five), so
Facet's own roots were filed as FOREIGN and the framework's `guiObjects` /
`screenGuis` came out ZERO. All thirteen
`artifacts/performance-stress-places/studio/rc-requal-row*.json` rows are
affected; seven have `Facet_PerfWorkload` sitting in `foreign.roots`, which is
the proof. Each row now carries an additive `censusCorrection` key and
`artifacts/performance-stress-places/studio-capture-2026-08-21.md` carries a
correction block above its headline table.

**Only the instance counts are affected.** Scopes, frame timings, solves,
creates/recycled/elided, haptics and the profiler rows were taken by instruments
the defect never touched and stand as recorded. Re-run the capture plan when the
lab is next open; the pre-rename control to compare against is
`studio/pl9-row3-luauui-1.json` (`screenGuis 1, guiObjects 470`).

## 4. A device-matrix run — it has judged nothing since 2026-08-18

`tools/studio/device_matrix.luau`'s root filter had the same six-against-five
test, so **every** tree was skipped and `judgedTrees` was always 0. No false
green shipped — the driver's own anti-vacuity clause (`judgedTrees > 0`) turns
that into a red row — but it means any matrix row closed in that window closed on
a red or was never run. Drive the five-view matrix once and confirm
`judgedTrees > 0`; that will be the first honest matrix result since the rename.

---

## 5. What is already done, so nobody redoes it

* the fix, its pure module and both specs — landed, suite green;
* the repository-wide scan for the defect class — three sites found, all three
  fixed, and the scan is a standing spec so a fourth cannot land quietly;
* the live tag-layer A/B in an Edit datamodel — the shipped adapter driving its
  own `syncTags`, transcript in
  `artifacts/framework-gaps-phase2/screenx-tag-removal-live.txt`;
* `tools/build_places.sh` — 15 place files rebuilt from the fixed tree;
* the in-band correction markers on the thirteen capture rows and their summary.

**No RascalRally work is owed.** RR names no `facet-*` classification tag (its
only `facet-` strings are dump schema names) and its own `CollectionService` use
is entirely `KartSim.TAG`. Recorded with the grep in
`.superpowers/sdd/framework-gaps-phase2/task-screenx-report.md`.
