# THEME-UNBUNDLE — Rascal Rally consumer lockstep

Per `docs/plans/agent-execution-contract.md` "Rascal Rally consumer lockstep" and
the root constitution's "Facet and Rascal Rally move together".

## 1. The changed contract, and who depends on it

This wave changed a DISTRIBUTION contract: the eight player-facing theme packages
became separate artifacts (`build/themes/<Name>.rbxm`), none of them inside
`build/Facet.rbxm`. It also changed two shipped diagnostic strings in
`src/themes/package.luau` (the `identity.id` example slug, and the layered-`barFill`
refusal's fix line).

Both Rascal Rally Rojo projects mount `GameStudio/ui/Facet/src` directly, so the
census is over the whole game tree, not just its UI.

## 2. The census (measured 2026-08-21, RR at `655cbd7` + this wave)

| Question | Answer |
|---|---|
| RR production modules requiring an `examples/themes` package | **0** |
| RR production modules requiring any `build/themes` artifact | **0** |
| RR production modules installing ANY theme package | **0** (pre-existing guard) |
| RR specs using a reference package as test corpus | **2**, both declared |
| RR modules asserting either changed diagnostic string | **0** |

Rascal Rally's Sponsor surfaces ride Studio Neutral plus a GAME-OWNED type ramp
that `src/client/FacetSponsor/TableMetrics.luau` builds itself through
`themes.define` + `themes.neutralPackage()` — the same public surface a reference
package uses, with no reference package involved. So the unbundling is
behaviour-neutral for this game by construction, not by luck.

The two spec uses:

| File | Package | Why it is the right fixture |
|---|---|---|
| `tests/facet_theme_paint_contract.spec.luau` | `fantasy_parchment` | the DIRECTOR'S OWN package from the finding that file exists for; a hand-rolled palette would not move when the reference corpus moves |
| `tests/facet_racer_list.spec.luau` | `glossy_touch` | the differential control for the Table band gutters — a package with real chrome, so the gutter case cannot pass vacuously on a Facet that lost the alignment |

## 3. The game-side work (RR `e4f02a2`)

No production edit was correct here: nothing in the game's shipped code touches
the changed contract, and manufacturing one would be churn. What the contract
requires in that case is the game-side compatibility EVIDENCE, and this wave adds
it as a live guard rather than a note.

`tests/facet_theme_paint_contract.spec.luau` already asserted that nothing in
`src/` INSTALLS a theme package. It now also asserts that nothing in `src/` even
NAMES one — the stronger claim, and the one that would actually break against a
Facet distribution, because a require of `examples/themes/...` is a require of a
path that exists only because the two repositories sit beside each other on this
disk. The spec tree keeps its two uses, each declared with its reason, checked in
BOTH directions.

Mutation-proved, each reddening that case alone and nothing else:

1. a production module naming an optional artifact — `1 failed, 4 passed`;
2. an undeclared corpus use appearing under `tests/` — `1 failed, 4 passed`;
3. a declared use whose file stopped using the corpus — `1 failed, 4 passed`
   (the direction a list cannot catch about itself).

## 4. Commands and results

| Command | Result |
|---|---|
| `./run-tests.sh` (Rascal Rally, private multi-repo export) | **3440 passed**, green (base 3437; +1 this wave, +2 the concurrent LAYOUT-FIX wave) |
| `./run-tests.sh` (Facet, same export) | **6766 passed**, green (base 6750; +5 this wave, +11 concurrent) |
| `stylua --check` (RR spec) | clean |

Both suites were run in a private export built by `git archive HEAD` into the
multi-repo shape (`<root>/GameStudio/ui/Facet` beside
`<root>/games/RascalRally/code`, which is how RR's specs require the framework).
Nothing was measured in-tree, where two other agents are working.

## 5. Studio canary

NOT OWED and deliberately not claimed. This wave changes no visible, input,
layout, adapter or lifecycle behaviour in Rascal Rally: the game installs no theme
package, the two rewritten strings are compile-time diagnostics for a package
author, and the new artifacts are build outputs the game does not consume. The
distribution artifacts themselves are proven by
`tools/check_theme_artifacts.py`, which mounts each one headlessly.
