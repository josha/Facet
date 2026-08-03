# Stage-start baseline — how it was produced, and what honestly failed

The prior-gates roll-up (`prior-gates-before.txt`) is **the direct output of
`tools/prior_gates.sh`, run in a git worktree pinned to the stage-start commit
`6a4b59c`** (`../LuauUI-baseline`), after architecture review ARCH-4 rejected an
earlier hand-spliced version of this file (the per-gate verdicts were identical;
the format was not the script's — the final artifact is the script's own run,
completed 2026-08-02 evening). It was not run in the live tree because the first
in-tree attempt was killed when the stage's implementation agents began editing
source under it, which would have made the "stage-start" claim a lie.

Two instrument corrections were required and are part of the record:

1. **Gitignored build assets** (`build/`, `sourcemap.json`) are not in git, so the
   worktree initially lacked them and `doctor` failed phase-0/phase-1 spuriously.
   Copied from the live tree (they are stage-independent toolchain outputs);
   both gates then PASS.
2. **PNG captures** are gitignored, and four gates sha-verify their captures
   (`check_matrix_rows`, TP-A13, RS matrix, XP matrix). The captures were copied
   from the live tree (they are frozen evidence from the stages that produced
   them, unchanged by any stage since); theme-packages-and-skinning,
   rich-skinning-v2, and cross-platform-proof then PASS in the script's own run.
   The phase-gate re-review (PG-A11) traced a THIRD case of the same class:
   part-2's `ws4-game-table-surface` last clause is `test -f` on a gitignored
   `artifacts/studio/part2-racer-list.json`, so ws4 also fails in any fresh
   checkout while being substantively green live — part-2's baseline FAIL row
   therefore carries two checks (ws1 = the real pin decay, ws4 = instrument)
   (an earlier batch also saw part-2's 14-serial-suite check flake once under
   load; the script run reproduced the true failure, which is the pin decay
   below, not the flake).

## The three TRUE stage-start failures (inherited, not created, by this stage)

| Gate | Failing check | Cause (verified) |
|---|---|---|
| `part-2-director` | `ws1-table-phase-b-suite` | a later stage renamed the pinned case "a focused **grip** resizes its column via the Adjust action" to "a focused **column handle** resizes…" (the column-resize-moved-to-header change) without updating part-2's grep. The behavior exists and passes; the PIN decayed. Repaired this stage (manifest grep updated to the shipped name) — part-2 passes at the final source |
| `authoring-adaptive-ui` | `physical-and-human-rows` (PENDING) | the standing physical/human row that has failed this gate identically since it was registered (same state recorded at the 5.5 baseline). Unchanged by this stage |
| `code-simplicity-cleanup` | `public-surface-unchanged`, `registration-and-drift` | Step 6 (whose own gate was never registered in phases.json) landed AFTER 5.5 froze its byte-exact surface dump: it added `UI.Composition`/`UI.Region`, the adaptive height half, `composition`, `text`, `motion.newValueReveal` — so 5.5's frozen-surface claim expired by design, and one Step-6 test file (`tests/layout.spec.luau`) failed `stylua --check`. The stylua half is fixed this stage; the frozen-dump half cannot pass again without rewriting 5.5's own artifact, which this stage deliberately does not do (see the decision note below) |

## Directional rule consequence

The `prior-gates-unregressed` check preserves every gate that PASSES here (14 of
17). `part-2-director` goes FAIL→PASS at final (the pin repair). The other two
remain FAIL for the reasons above — recorded, not silently absorbed.

**Decision note (for the reviewers):** 5.5's `public-surface-unchanged` check is
inherently time-scoped — it byte-compares the LIVE surface against a dump frozen
at 5.5's close, so the first later stage that adds any export breaks it forever.
The honest fixes are either (a) scope it to a stored before/after pair from 5.5's
own run, or (b) accept it as a standing FAIL with this note. This stage chose (b)
to avoid editing a closed stage's evidence; a decision packet is NOT filed
because the repair is mechanical and belongs to whichever stage next touches that
gate's manifest entry.
