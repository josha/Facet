# D1 — the anchored-surface seam

`presenter.presentAnchored(panel, opts)` — a presented surface positioned against
a **source view's screen rect** instead of a parent corner. The substrate for D2
(Menu), D3a (`help`), D3b (Callout) and D7's overflow sink.

Brief: `docs/plans/navigation-and-menus-brief.md` §2 D1. Gate row:
`navigation-and-menus/d1-anchored-surface`.

## What shipped

| Thing | Where |
|---|---|
| The PURE placement solver | `src/layout/anchor_placement.luau` (new) |
| The presented surface + arrow tail | `src/present/anchored.luau` (new) |
| `presenter.presentAnchored` / `presenter.anchoredSurfaces` | `src/present/presenter.luau` |
| Precedent 1 migrated | `presenter.luau` `clampDisclosure` — the full-value disclosure plate |
| Precedent 2 migrated | `src/controls/row_actions.luau` `computeMenuAnchor` — the floating row menu |
| Specs | `tests/anchored_surface.spec.luau` (32 cases, registered in `tests/run.luau`) |
| Consumer rider | `games/RascalRally/code/tests/luauui_anchored_surface_contract.spec.luau` (5 cases) |
| Docs | `docs/reference/api.md` § Anchored surfaces; `docs/reference/swiftui-parity.md` `.popover` row + the row_actions "recipes" caveat |
| Lint scope | `tools/lune/check_theme_drift.luau` now scans `src/present/anchored.luau` |

## The public shape

```
presenter.presentAnchored(panel, opts) -> handle
```

`panel` is a **panel blueprint** — any node, *not* a `UI.Screen`. The Screen root,
the full-viewport anchor layer, the window-space offsets and the tail are
synthesized; the panel mounts at `/<id>/Layer/Surface`, the tail at
`/<id>/Layer/Tail`.

```
opts = {
  id?,      -- root id, default "Anchored"
  modal?,   -- true routes through presentModal (focus trap); default present()
  anchor = {
    source = { path = "/Screen/Row/More" } | { rect = { x, y, w, h } },
    edge?     = "bottom",  -- "top" | "bottom" | "leading" | "trailing"
    align?    = "center",  -- "start" | "center" | "end"
    gap?      = "s",       -- theme metric name or number
    tail?     = false,     -- true, or { size?, surface?, cornerInset? }
    overflow? = "clamp",   -- "clamp" | "keep"
  },
  -- ...plus every PresentOpts key, unchanged
}
```

Closed at three levels (`opts`, `opts.anchor`, `opts.anchor.source` /
`opts.anchor.tail`) through `specGuard.assertKnownKeys`; the opts key set is built
from the presenter's own `PRESENT_OPTS_KEYS` plus three, so it cannot drift from
it. `rootPolicy` is refused unless it is `"edgeToEdge"`: the offsets are window
space, and an inset root would silently re-base every one of them by the
safe-area inset.

## The pure solver

```
anchor_placement.solve({ source, size, safe, edge?, align?, gap?, tail?, tailInset?, overflow? })
  -> { x, y, w, h, edge, flipped, shift, fits, tailX?, tailY?, tailSuppressed }
```

Plain numbers in, a plain table out — no env, no signals, no theme, no engine, no
mounted tree. The `popup_button.resolvePresentation` shape, and the reason three
callers can share one answer.

1. **Place** on the preferred edge, `gap` px off the source.
   `leading`/`trailing` → `left`/`right` (no RTL fact exists in this framework;
   `resolveEdge` is the single place that changes when one lands).
2. **Flip** to the opposite edge when the preferred placement crosses the safe
   box **and** the opposite one fits entirely. Both halves are load-bearing —
   `row_actions`' ruling 4: *"it never flips into a worse place"*.
3. **Shift** along the edge until the surface is inside the safe box; `shift` is
   the signed distance it moved from its aligned position. A surface wider than
   the safe box pins to the leading inset rather than centring off-screen.
4. **Tail**: centre it on the SOURCE, clamp it clear of the panel's own corners,
   and **suppress** it in three cases — the clamped centre is no longer over the
   source (the shift took it off), the panel is too narrow to host it inside its
   own corners at all, or the overflow clamp pulled the panel off the edge it was
   placed on (an arrow with a gap under it points from somewhere the panel is not).

`overflow` decides only the fits-on-neither-edge case: `"clamp"` (default) pulls
the surface back inside the safe box — right for a plate nobody can read under a
notch; `"keep"` leaves it clipped where the preferred edge put it — right for a
menu that must never cover its own trigger.

## The arrow tail: a rotated Box, not a Path

`UI.Path` materializes as a Roblox `Path2D`. **`Path2D` strokes only — there is no
fill** — and `src/controls/path_shapes.luau` exports `arc`, `ring`, `needle` and
no triangle. A stroked outline cannot read as the solid, panel-coloured wedge the
`f1` plate has, so the tail is a **`UI.Box` with `rotation = 45`**:

- `rotation` is a shipped, paint-only prop on every rendered class (ADR-0026): it
  moves no layout, no hit geometry and no focus, which is exactly what a
  decoration should do;
- declared **before** the panel, so the renderer's document-order z walk
  (`syncZOrder`) paints it behind and the overlapping half is covered;
- it wears the panel's own `surface` role, so a theme swap moves both together —
  where an `UI.Image` nine-slice would need an uploaded asset per theme fill;
- it **eats its own gap**: a square of side `s` rotated 45° protrudes
  `s·√2/2`, so a tailed surface stands `gap + protrusion` off its source and the
  tip lands exactly `gap` short of it. Without that the wedge is painted over the
  control it points at.

Sizes are theme metrics, never pixels: `gap` = space step `s`, tail = space step
`m` (16px under Studio Neutral → an 11.3px protrusion, Apple's own popover-arrow
size), corner keep-out = `radii.panel`.

## Following a moving source added no watcher

`anchored.sync()` runs on two cadences that already exist:

- `presenter.refreshBody`, **after** the stack loop — every handle has
  re-rendered and re-fed its geometry, so the source rect read is this frame's.
  This is the cadence a real scroll already drives `syncGeometry` at, which
  `row_actions` re-aims its own menu on ("asking nothing new of any caller").
- `presenter.tickBody`, beside `clampDisclosure` — a surface's size is a solve
  output whose text measure can land after mount, so a surface placed once at
  mount would be placed from the placeholder height.

Both no-op when nothing moved (`core:signal`'s own same-value behaviour), and a
surface is pruned the moment it leaves the stack — `presenter.dismiss` calls
`anchoredSurfaces.prune()` right after `table.remove(stack, index)`, so the
record and the signals it owns die on the same call rather than a frame later.

## Both hand-rolled precedents migrated, and one of them was wrong

| Precedent | Before | After |
|---|---|---|
| `presenter.clampDisclosure` | prefer below; flip above whenever below did not fit; clamp | `anchor_placement.solve{ edge = "bottom", align = "start" }` |
| `row_actions.computeMenuAnchor` | prefer below; flip above only when below does not fit AND above does | `anchor_placement.solve{ edge = "bottom", align = "start", overflow = "keep" }` |

The disclosure plate's copy flipped **unconditionally** on a bad fit below —
including when above did not fit either, which is exactly the "worse place" the
row-actions ruling forbids. Unifying fixed it; the older copy was the wrong one.

`row_actions` is behaviour-preserving by construction, and two of its inputs are
deliberately not what the solver would prefer, each for a stated reason in source:
`size.w = 0` (the menu's width is never learned here — `MenuRows` goes
unconstrained-width by design — so there is no along-edge extent and this control
flips rather than shifts), and the safe box is the **raw viewport** rather than
`deviceSafeContent`, because ruling 4 was written against the viewport and
tightening it would make the menu flip earlier than the ruling that shipped it.

## The f1 fixture

`docs/plans/reference-media/2026-08-16-roblox-app-navigation/f1-avatar-editor.jpeg`
— the "Post Avatars to Marketplace" plate — reproduced at 390×844 as
`tests/anchored_surface.spec.luau` → *"f1: anchored under a top-right button,
arrow up at it, body shifted left"*. All three of its facts are placement
decisions and all three are asserted: the plate hangs BELOW a top-right 44px `+`
(`edge = "bottom"`, `flipped = false`), its body is SHIFTED LEFT (`shift < 0` — a
centred 260px plate under a button centred at x=368 would start at 238 and end at
498, 108px off the screen), and its arrow still points UP at the button
(`tailSuppressed = false`, and `tailX` inside the `+`'s own span).

## Evidence

| ID | Behaviour | Level | Driver | Status |
|---|---|---|---|---|
| NM-D1-1 | Preferred edge, gap, alignment, `leading`/`trailing` resolution | E1 | `tests/anchored_surface.spec.luau` "D1 placement solver: the preferred edge…" | PASS_AUTOMATED |
| NM-D1-2 | Safe-area flip, and it never lands somewhere worse | E1 | same file, "…the flip, and the rule that it never lands somewhere worse" | PASS_AUTOMATED |
| NM-D1-3 | Along-edge shift, reported | E1 | same file, "…the along-edge shift" | PASS_AUTOMATED |
| NM-D1-4 | Arrow tail: border, corner keep-out, suppression | E1 | same file, "…the arrow tail" | PASS_AUTOMATED |
| NM-D1-5 | The surface reuses the presenter's stack/focus/layering | E1 | same file, "D1 anchored surface: presented against a source view's screen rect" | PASS_AUTOMATED |
| NM-D1-5b | The tap-away catcher is the presenter's own, `consume = false` included | E1 | same file, "an anchored panel that declares outsideDismiss gets the presenter's catcher, non-consuming" — driven through a real Zone-B tap, not asserted from source | PASS_AUTOMATED |
| NM-D1-6 | A moving source is followed with no new watcher | E1 | same file, "a moving source is followed on the existing refresh cadence" | PASS_AUTOMATED |
| NM-D1-7 | Closed spec: unknown anchor key, bad rootPolicy, bad edge/align/overflow | E1 | same file, four refusal cases | PASS_AUTOMATED |
| NM-D1-8 | Deterministic dump, `luauui-anchored-dump/1` | E1 | same file, "the dump is deterministic and names the resolved edge" | PASS_AUTOMATED |
| NM-D1-9 | The f1 fixture | E1 | same file, "D1 fixture f1: the avatar-editor callout" | PASS_AUTOMATED |
| NM-D1-10 | Both precedents on one solver, both still green | E1 | same file + `tests/text_disclosure.spec.luau` + `tests/row_actions_input.spec.luau` | PASS_AUTOMATED |
| NM-D1-11 | The live RascalRally consumer is current | E1 | `games/RascalRally/code/tests/luauui_anchored_surface_contract.spec.luau` | PASS_AUTOMATED |
| NM-D1-12 | The tail as a player sees it: the wedge's paint under a real theme on a real device | E4 | a Studio/device pass once a D2/D3b construct puts one on screen | PENDING_PHYSICAL |

## Two mutations, both seen to bite

The gate-integrity sweep's standing rule: a check is worthless until a mutation
has been seen to fail it. Both were run against this implementation and both
reddened, and one of them proves the migration is genuinely wired rather than
merely present.

| Mutation | What reddened |
|---|---|
| `solve` flips **unconditionally** on a bad fit (the exact defect the disclosure plate's own copy had) | 3 cases — this file's *"never flips into a worse place"* and *"overflow 'clamp' pulls a surface that fits nowhere back inside the safe box"*, **and `row_actions`' own shipped `"NEGATIVE CONTROL: with no room ABOVE either, it stays BELOW rather than flipping"`**. A control's own regression spec failing when the shared solver breaks is the proof that the migration is live |
| `tailSuppressed = false` — the tail never withdraws | 3 cases — both solver suppression rules and the presented-surface one |

## Commands and results

```
lune run tests/run                            5705 passed / 0 failed (D1's own 32 cases)
python3 tools/check_source_size.py            PASS (KNOWN_OVER empty)
lune run tools/lune/check_registration_cli    PASS
lune run tools/lune/check_surface_ledger      PASS
lune run tools/lune/check_prop_parity_cli     PASS
lune run tools/lune/check_docs_cli            PASS
lune run tools/lune/check_theme_drift         PASS (with src/present/anchored.luau newly in scope)
lune run tools/lune/check_example_drift_cli   clean
stylua --check src tests examples             clean
python3 tools/check_manifest_integrity.py --transcript
                                              1220 greps, all anchored, all matched a green transcript
lune run tools/lune/gate navigation-and-menus d1-anchored-surface PASS, d0-* unchanged
cd ../../../games/RascalRally/code && lune run tests/run   3290 passed / 0 failed
```

(The suite and gate numbers are a shared working tree: D4 and D8 landed in the
same window, so the totals include their cases as well as this stage's 32 + 5.)

## What this row does NOT claim

- **No gesture trigger exists yet.** Long-press, right-click and pointer
  hover-dwell belong to D2 and D3a and stay `PENDING_PHYSICAL` under
  `physical-and-human-rows` — Studio cannot synthesize a real touch class, and an
  injected event arrives as `Touch` rather than `MouseButton1`.
- **No shipped screen consumes the seam.** Menu, `help` and Callout are the next
  three deliverables. RascalRally's rider proves the restraint by *measuring* it
  (zero `presentAnchored` hits under its `src/`), so the day the game adopts one
  that case changes with the adoption instead of a reviewer finding the drift.
- **No Studio capture.** The placement is pure arithmetic plus a headless mount;
  the visible claim that needs an engine is the tail's paint, which is NM-D1-12
  and stays pending until a construct puts one on screen.
- **No RTL.** `leading`/`trailing` resolve to `left`/`right` because the framework
  has no writing-direction fact; when one lands, `resolveEdge` is the one place
  that changes.
