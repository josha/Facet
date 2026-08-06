# Rascal Rally consumer impact — performance stress places (Step 9)

**Date:** 2026-08-04. Required by the execution contract's "Rascal Rally consumer
lockstep": a LuauUI source, contract, default, behavior, asset or distribution change
is incomplete until its direct game consumer is synchronized in the same stage.

## The changed contracts, and what each does to a caller

| Change | Public contract? | Caller impact | Verdict |
|---|---|---|---|
| **NEW** `src/core/profile.luau` | No — internal module, no `LuauUI.*` export, not a blessed client entry point | None. No game code can reach it except through the named `examples/`-only exemption in `check_boundary`, which does not apply to the game. | No caller change is correct |
| **Profiler scopes** at nine call sites (`core/custom`, `layout/solver`, `render/renderer`, `mount`, `async/resources`) | No | Behaviour-preserving by construction: on a host without `debug.profilebegin` the span is a direct call; on Roblox it wraps the same body and re-raises any error value unchanged at level 0. The game gains free MicroProfiler phases in its own captures. | No caller change is correct |
| **`solver.measure` per-solve memo** | No — internal to the solve | Geometry is byte-identical (verified by differential fuzz over 800 seeded trees: `rectDiff = 0`). The game's UI gets **faster**: the shared measure path is what every Rascal Rally screen solves through. **A fresh-context architecture review found the first version of this change dropped `compact`/`textFacts` verdicts — including `truncated`, which the game's Sponsor surfaces consume for full-value disclosure. Fixed before landing (the cache replays them) and re-verified at 0 divergences.** | No caller change is correct |
| **`examples/gallery/scenarios/runner.luau`** gains `ctx.host` / `ctx.lab` passthrough | No — development verification surface, not shipped library code | The game does not use the gallery runner. `deps.host` and `deps.lab` are `nil` for every existing caller, so every existing scenario is unaffected. | No caller change is correct |
| **`tools/build_places.sh`**, `studio_sync perf` mode, new checkers, new bench scenes, gate manifest, `phases.json` | No | Tooling only. | No caller change is correct |

**No public API changed. No default changed. No asset changed. No distribution output
changed.** `LuauUI.VERSION` stays `0.8.0`; nothing was added to or removed from the
public surface (`check_surface_ledger` PASS, `check_registration` PASS, 84 exports
documented, unchanged).

## Why no production-game edit was manufactured

The contract is explicit that a compatible internal change must not produce churn:
"Do not manufacture a production-game edit for a compatible internal change. In that
case, update or add the game-side compatibility test/evidence and record why no caller
change was correct."

Every change above is either invisible to a consumer (internal module, internal memo,
scope annotations) or reaches only development tooling the game does not use. The
game-side evidence is therefore the **suite run at the judged source**, which
exercises the changed solve path through real game surfaces.

## Game-side verification, run live at the judged source

```
cd games/RascalRally/code && ./run-tests.sh
3089 passed
```

That suite is the compatibility evidence for the memo specifically: it contains the
Sponsor View layout, results, large-text sweep, hot-swing and contract families —
every one of which solves through `solver.measure` and asserts exact geometry. A memo
that returned a different answer, dropped a diagnostic, or changed a truncation
verdict would redden them. It did not.

The LuauUI suite is the other half: **3 367 passed**, including the layout,
`large_text_matrix`, `large_text_layout`, `large_text_hot_swap`, `composition`,
`icon_box` and `chrome_inset_yield` families that pin solved geometry directly.

## Studio canary

The affected path is layout + adapter commit, and it was driven live rather than
inferred — but in the **performance lab** place, not a Rascal Rally place, because the
lab is where this stage's surfaces live. What the canary shows for the shared code:

- the real `screen_target` adapter mounted, solved and committed a 2 000-row
  virtualized list with composite rows across nine source stamps and six Play
  sessions, with no warning or error in the console;
- geometry stayed correct across five device-simulator viewports (360×691 through
  1920×1080), with the mounted window bounded at every one;
- `reset` returned the session to zero GuiObjects.

**Honest boundary:** a Rascal Rally Sponsor-surface canary was NOT re-run in this
stage. The justification is that no contract the game consumes changed, and the game's
own 3 089-case suite — which is what would catch a solve-path regression on those
surfaces — was re-run at the judged source. A reviewer who disagrees should treat
"re-run one Sponsor Studio canary" as the cheapest way to close the gap; it is listed
in the review packet as an optional confirmation rather than claimed as done.

## Ownership ledger

Nothing in `examples/performance/` is game code and nothing in it belongs in
`src/`. Two things were considered and deliberately left where they are:

- the **raw-Roblox reference list** (`examples/performance/client/native_list.luau`)
  is a measurement floor, not a framework feature, and must never become one;
- the **profiler wrapper** is framework code and lives in `src/core/profile.luau`,
  which is why the lab reaches it through a declared exemption instead of copying it —
  a second implementation could disagree about naming or balance, and then the driver's
  scopes and the framework's would not be comparable.
