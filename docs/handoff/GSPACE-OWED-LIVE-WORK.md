# Handoff — live work owed by task G-SPACE (the missing spacing step)

**Written:** 2026-08-23, end of the G-SPACE round. **For:** the director, or a
fresh context running the next Studio session.

Read this, then ADR-0047 (`docs/adr/ADR-0047-the-missing-spacing-step.md`) for
the full decision, and `docs/guide/11-device-verification.md` §"The hands-on
place" for how to drive the showcase.

---

## 0. The one-paragraph state

`space.tight` — a new derived space step naming the value halfway between `xs`
(4) and `s` (8) — is implemented, tested (headless), and swept: 55 of 62 raw-6
sites converted across 22 example files, 1 refused with a documented reason
(`fantasy_parchment.luau`, a theme-package metric field that cannot take a
string name), and 6 handed off (`hud.luau`, the HUD round G8+G9's territory).
**Everything below is a device confirmation. Nothing here blocks the fix; the
headless suite is green on every file this round touched.**

---

## 1. Ten-foot on-glass check owed — `GetStyled`, not a plain read

The brief's requirement 8 names this explicitly. `space.tight` rides the
ten-foot metric ladder generically (`space` is an unconditional
`DENSITY_LENGTH_SECTIONS` member in `snapshot.densityClassOf`) and is proved
headlessly at 1.5x (`tests/space_tight_step.spec.luau`, `tests/
ten_foot_metrics.spec.luau`'s proportion-equality sweep) — but no session
confirmed it PAINTS at that scale on an actual `displaySize = "Large"`
render target. The prior campaign's own lesson (`luauui-tooltip-unified-shape`
memory) is exactly why this matters: **a plain `BackgroundColor3`/property read
reports the UNSTYLED value; `GetStyled` is the only instrument that sees
sheet-resolved paint.** A geometry-only headless proof cannot see whether the
native StyleSheet path (the default paint path since B-15) resolves the same
number the solver reserved.

**What to check, on glass:**

```bash
cd GameStudio/ui/Facet
tools/lune/studio_sync   # or the inject snippet in tools/studio/inject.luau
```

Open `examples/places/Facet-Showcase.rbxl`, set the viewport/display class to
the `Large` (ten-foot) rung, and open any of the swept demos — `adaptive_
controls`, `sensory_feedback`, `branch_scope` and `virtual_grid`/`virtual_
hgrid` (the two restored G4/G5 fixtures) are the highest-value picks, since
their gutters visibly grow from the neutral 6px reading to 9px at ten-foot.
Use `GetStyled` (never a plain property read) to confirm the PAINTED gutter
agrees with the SOLVED one. Capture via `tools/studio/capture_viewport.sh`
only — never full-screen.

## 2. `hud.luau`'s 6 hand-off sites — CLOSED by fix round 1 (commit `5504033`; lint fully green). Original text kept below for the record:

`examples/gallery/scenarios/hud.luau:991,1000,1320,2341,2385,2539` are all raw
`gap = 6` sites the purity lint now flags (all `[example, COUPLED]` — the file
predicts geometry from `HUD_FLOOR_PX`). They are the HUD round (G8+G9)'s
territory per the campaign's concurrent-lane rule and were listed, not edited.
**The purity lint (`check_theme_drift_cli`) will not read fully GREEN until
these six convert** (or are individually refused with `-- THEME-OPT-OUT:`,
since the file IS in the coupled set — whichever the HUD round's own
geometry review decides). Nothing else in this round depends on it; every
other file the audit named is closed.

## 3. What is already done, so nobody redoes it

* the token (`src/themes/package.luau`, `src/themes/snapshot.luau`) — derived,
  authored-beats-derived, zero content-stamp movement, headless-proven at
  neutral and at ten-foot;
* the 55-site sweep across 22 example files, plus the 1 documented refusal and
  the 6-site hand-off list above;
* the two G4/G5 fixture restorations (`virtual_grid.luau`/`virtual_hgrid.luau`,
  4px → 6px, ADR-0040 row B-25);
* `docs/reference/api.md`'s teaching table (four sites: the `padding`/`gap`
  prop rows, the canonical "Theme metric names" paragraph, `newVirtualList.
  rowGap`'s row);
* `flat-baseline` — verified PASS, zero new waiver entries;
* RR lockstep — **no production edit**, and the evidence is stronger than a
  clean grep: `TableMetrics.listRowGap = 6` feeding `newVirtualList.rowGap`
  directly is an ALREADY-DELIBERATE, ALREADY-TESTED game-side choice (`tests/
  facet_collection_extent_contract.spec.luau`, "the spellings this package
  ships are unmoved" — RR's own comment names the coupling: *"D1: legacy's 6
  px gutter, so the SLOT is 62 and the row stays 56/60"*). Migrating it to
  `"tight"` would let the gutter scale at ten-foot while the SLOT/row
  arithmetic beside it stays fixed — the exact coupled-constant hazard this
  round's own day-2 lesson warns against — so it stays raw, refused with that
  reason, and RR's suite (`facet_collection_extent_contract.spec.luau`,
  `facet_theme_paint_contract.spec.luau`) re-ran green against this round's
  Facet tree.
