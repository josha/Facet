# RascalRally consumer-impact ledger — `row-actions` (hosted-mode plan)

Rascal Rally mounts `GameStudio/ui/LuauUI/src` directly through both of its Rojo
projects, so this stage is incomplete until every changed contract is audited
against the game's real callers. Audited 2026-08-12 against
`games/RascalRally/code` at its current source (branch
`luauui/example-quality-pass-consumer`, pins `92cd062`, `1f8560c`, `30ca16a`).

**Result: zero production edits required, and none were made.** RascalRally has
no call site for the feature this mission ships. What follows is the audit that
earns that claim, not an assumption of it.

Scope note: this ledger covers the **row-actions-hosted-mode-plan** (Tasks 1-8
on branch `row-actions-perf`) — hosted `rowActions` on `newVirtualList`/`Table`,
the two shared-engine fixes, and the trash/flag icon upload. The EARLIER
row-actions feature itself (standalone `newRowActions`, Table's own
`rowActions` composite) was already audited against RascalRally in
`artifacts/row-actions/rr-compat.md` (Task 13, 2026-08-11, live Studio canary
OBTAINED against RR's one Table caller) — that document stands and is not
superseded; this one is additive, for what this later mission changed.

---

## What this mission changed, and RascalRally's exposure to each

| # | Change | RR exposure | Action |
|---|---|---|---|
| 1 | `newVirtualList` gains a `rowActions(item)` spec field — VirtualList now HOSTS the feature (shared per-list pointer dispatcher on the row's `Hit`, lazy per-row gesture engine) | **None.** Grepped `rowActions\|newRowActions\|standard_icons\|standardIcons` across every `*.luau` in `games/RascalRally/code`: the only hits are inside the NEW test file this mission's own guard commits added (`tests/luauui_sponsor_table.spec.luau`, comments and case names) — zero production call sites. RR's one `newVirtualList` caller (`LuauUISponsor/RacerList.luau:912`) declares no `rowActions` key. | none |
| 2 | `Table`'s existing `rowActions` integration is unchanged by this mission (it shipped in the earlier row-actions branch, audited in `rr-compat.md`) | **None**, unchanged from that audit. RR's one `newTable` caller (`LuauUIRacerListScreen.luau:159-180`) still declares no `rowActions` key. | none |
| 3 | Shared engine fix D1: a re-swipe DURING a commit's return-flight latch can no longer double-fire the action (`close()` now no-ops while `committed`) | **None reachable.** This is `row_actions.luau` engine behavior; RR builds no `newRowActions` composite and no `Table`/`VirtualList` `rowActions` field, so the engine is never constructed from RR code. Standalone-covered by this branch's own tests (`"a re-swipe DURING the commit's return flight cannot fire the action twice"`), not hosted-only. | none |
| 4 | Shared engine fix: the reused close spring is now re-seeded, so a SECOND and third short swipe on the same row also snaps back closed | **None reachable**, same reason as #3 — the engine that carries the spring is never built from any RR call site. | none |
| 5 | New icon content ids: `trash` = `rbxassetid://84398508341623`, `flag` = `rbxassetid://109067109704366` (`src/themes/standard_icons.luau`) | **None.** Grepped both literal asset ids and every `standard_icons`/`standardIcons` reference across RR — zero hits. RR draws its own icons (`iconFor`, `LuauUIRacerListScreen.luau`); it does not consume LuauUI's standard icon set at all, so these new content ids cannot reach it by any path. | none |
| 6 | `list.engagedKey` / `list.engagedOffset` — two new public reads on `newVirtualList`'s returned handle | **None.** Additive reads, nil on a list without `rowActions`; RR's `VirtualList` handle never reads either name (grepped `engagedKey`, `engagedOffset` — zero hits). | none |
| 7 | Gate/workload/doc-only changes (`perf_workload.luau`, `check_row_actions_matrix.py`, `docs/reference/api.md`, `examples/gallery/scenarios/row_actions.luau`) | **None** — none of these ship in `src/`, so none of it is part of what RascalRally's Rojo projects mount. | none |

---

## The verified-zero-call-site finding, and how it was checked

`grep -rn "rowActions\|newRowActions\|standard_icons\|standardIcons" --include="*.luau" games/RascalRally/code` returns exactly seven lines, and every one of
them is inside `tests/luauui_sponsor_table.spec.luau` — the test file this
mission's own three RascalRally commits (below) added, either as a comment
explaining the framework contract being pinned or as a test-case name. **Zero
matches in any production `src/` file.** RascalRally's single `newTable`
caller and single `newVirtualList` caller (the racer list panel and the
Sponsor racer list respectively) each pass a closed, enumerated spec table with
no `rowActions` key.

## The three pinned RascalRally guard tests (this mission's own commits)

A green suite alone would not show a regression here — these are pinned
directly, against the live framework promise that a list/table which declares
no `rowActions` builds exactly what it always did:

| commit | test file | what it pins |
|---|---|---|
| `92cd062` | `tests/luauui_sponsor_table.spec.luau` | "FRAMEWORK: no rowActions declared, so the row Hit is not a pointer-capture surface" — the racer row's `Hit` carries none of the four hosted-dispatcher handler props and is not a pointer-capture surface at all. Verified biting: with the framework mutated to wire the dispatcher unconditionally, this case goes red first, plus ten more in the file. |
| `1f8560c` | `tests/luauui_sponsor_table.spec.luau` | "FRAMEWORK: no rowActions declared, so no row-actions tray overlay mounts" — swept over the WHOLE mounted path set (not one expected path, so a rename can't make it vacuous) for any `RowActions`-named node; zero found. Verified biting: mounting the tray overlay unconditionally reddens it first. |
| `30ca16a` | `tests/luauui_sponsor_table.spec.luau` | "FRAMEWORK: no rowActions declared, so the focus group is row hits and nothing else" — DPadDown down the whole mounted window, asserting every landing is a row hit; a hosted tray's focus-group splice would show up as a landing that is not a row. |

These three commits are **committed to the RascalRally repo but not yet
pushed** (branch `luauui/example-quality-pass-consumer`, 3 commits ahead of
`origin/luauui/example-quality-pass-consumer`) — pushing is a merge-time
action for this LuauUI branch, not part of this ledger.

---

## Live suite

```
$ cd games/RascalRally/code && ./run-tests.sh
```

**3097 passed, 0 failed** — run fresh, at this LuauUI source, immediately
before writing this ledger. Unchanged from the count Task 5's own guard-test
commit (`30ca16a`) landed at (3096 → 3097); Tasks 6-8 (docs, workload de-bias,
gate ceilings) touched no RascalRally-reachable surface, so the count held.

---

## What this ledger does NOT claim

- **No Studio canary was run for the row-actions-hosted-mode surfaces**
  (hosted `VirtualList.rowActions`, the D1/spring-re-seed fixes, the new
  icons). The earlier `rr-compat.md` canary (Task 13, 2026-08-11) exercised
  RR's one `Table` caller live in Studio, but that was against the *original*
  row-actions feature, before this mission's hosted-mode work existed — it is
  not re-claimed as evidence for what this mission shipped.
- **No physical-device pass.** This ledger is grep-verified zero-exposure plus
  a live headless suite run, not a live-device confirmation.
- **Not a migration.** RascalRally uses none of this mission's new surface;
  nothing here recommends or stages RR adopting hosted `rowActions`.

No RascalRally gameplay, content, feature flag, or Sponsor default was
changed. No RascalRally file outside `tests/luauui_sponsor_table.spec.luau`
was touched by this mission.
