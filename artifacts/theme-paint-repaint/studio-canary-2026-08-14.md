# Studio canary — a theme commit repaints the tint channel and a Path's role

**2026-08-14.** Director report: *"when i changed to the parchment theme, the
spinner stayed blue. i'd expect to make it a similar color?"*

Instrument: a self-contained probe mounted through the REAL pipeline (blueprint →
mount → solver → `ScreenTarget`) into a disabled `ScreenGui`, sampled, then
destroyed and confirmed absent in the same call. Nothing on the director's
screen at any point.

Fantasy Parchment's Daylight accent, read out of the compiled package rather than
restated: **0.478431, 0.282353, 0.101961** = rgb(122, 72, 26), the illuminator's
gold.

## BEFORE the fix (Play session, `LuauUI_TintThemeProbe` / `LuauUI_SpinnerThemeProbe`)

Install Fantasy Parchment over a live surface, refresh, advance a frame:

| surface | channel | neutral | after the swap |
|---|---|---|---|
| `UI.Box` static tint `{role="accent", blend=1}` | `tint` | `0.172549, 0.384314, 0.823529` | **unchanged** |
| `UI.Box` tint `{role="accent", from="control", blend=0.5}` | `tint` | `0.166667, 0.280392, 0.525490` | **unchanged** |
| circular ProgressView `Arc` `role="accent"` | `role` | `0.172549, 0.384314, 0.823529` | **unchanged** |
| circular ProgressView `Track` `role="secondary"` | `role` | `0.619608, 0.647059, 0.713726` | **unchanged** |

`0.172549, 0.384314, 0.823529` is rgb(44, 98, 210) — Studio Neutral's accent.
Every one of them stayed blue on a parchment screen.

**The one that self-heals.** With the animation clock advanced one tick, the dot
spinner's five dots DID recolour (Dot4 `0.478431, 0.282353, 0.101961`), because
its tint is a memo over the phase and its next write re-resolves against the live
palette. A bound tint that is not re-written (`BoundTint`) stayed blue until the
signal driving it was set. That is why the defect presented as "only some things
are stale" — nothing repaints on the commit; some things repaint themselves
afterwards.

## AFTER the fix (Edit session, `LuauUI_ThemePaintProbe`, CoreGui-parented)

Same probe, nothing re-written after the install — no animation tick, no signal
set, no re-solve of the node:

| surface | before | after |
|---|---|---|
| circular ProgressView `Arc` (`role="accent"`) | `0.172549, 0.384314, 0.823529` | **`0.478431, 0.282353, 0.101961`** |
| circular ProgressView `Track` (`role="secondary"`) | `0.619608, 0.647059, 0.713726` | `0.431373, 0.360784, 0.258824` |
| `UI.Box` static tint (`{role="accent", blend=1}`) | `0.172549, 0.384314, 0.823529` | **`0.478431, 0.282353, 0.101961`** |
| dot spinner `Dot1` (dynamic tint) | `0.166549, 0.278314, 0.519529` | `0.662431, 0.526353, 0.361961` |

The arc and the static tint are Parchment's accent **exactly**, to six decimals.
The dot now moves ON THE COMMIT rather than one animation tick later.

## Session notes

- Play was already stopped by another agent's traversal work when the after-run
  came due; this canary did NOT start or stop Play. The after-run is an Edit-mode
  probe, which is a supported path (`src/client/edit_preview` exists for exactly
  this), parented to `CoreGui` so nothing can be saved into the place.
- Rojo was not pushing into that session. `src/client/screen_paint.luau` and
  `src/client/screen_target.luau` were pushed byte-exact over the local HTTP
  source-push recipe (both are under the 200,000-character `Source` write cap;
  `renderer.luau` at 242,943 is not, and was untouched). Verified after the write:
  the DataModel carries `refreshThemedPaint` and `PATH_ROLE_TOKEN`, which disk
  gained minutes earlier.
- Both probes destroyed on the error path as well as the success path, and the
  absence re-read in the same invocation: `probeAbsent = true`, `leftovers = []`.
