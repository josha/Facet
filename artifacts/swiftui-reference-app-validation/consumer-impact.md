# Rascal Rally consumer-impact ledger — swiftui-reference-app-validation

**Date:** 2026-08-08. Rascal Rally mounts `GameStudio/ui/LuauUI/src` directly
through both Rojo projects, so every framework change this stage made is live in
the game the moment it lands.

## Framework changes this stage and their consumer impact

| Change | Consumer impact analysis |
|---|---|
| `UI.Stage` engine-content leaf (new class + `controller.stageHost` + seam-owned authority set) | **Additive.** No existing game surface names `Stage`; no game code can have depended on the seam existing. The authority additions (`Ambient`/`LightColor`/`CurrentCamera`/`LightDirection` as seam-owned) affect only nodes of the new class. |
| Grid measure fixed-point fix (`minColumnWidth` floor + trailing-gap report) | **Bounded to** grids with a literal `minColumnWidth`, uniform-narrower cells, in a content-sized parent. The game's sponsor surfaces use grids in fill-width bodies; the fix agent's consumer sweep plus `check_flat_baseline` (1773 flat nodes byte-compared) report zero rect drift, and the game suite passes at the judged source. |
| ScrollView bar-reserve measure fix | **Bounded to** hug-cross scrollers whose scroll axis overflows on adapters that publish a bar thickness. Headless adapters publish none (twin unchanged); the live adapter's behavior becomes self-consistent (the box grows by the bar it was already reserving). Game suite green at the judged source. |
| Namespaced-icon ASCII floor (`package.iconGlyph`) | **Additive.** Curated names keep their glyphs (pinned); only previously-nil `ns:name` lookups now return a derived letter. The game ships art for its own icon names, which win above this rung. |
| Scenario runner: `textPolicies` in reports, stage-content materializer, `keyboardFirst`, `referenceModules`, `ctx.stage` | **Development tooling only** — the runner is the verification surface, not shipped game code. |
| Park-corpse guards (`parkEligible` refuses an unparented instance; `adopt` guards its reparent write) | **Strictly protective.** Both guards only REFUSE operations that previously crashed (adopting a destroyed instance) or pooled a corpse; a refusal falls through to the ordinary remove / fresh create the renderer always supported. The game's theme swaps + navigation get the crash fix for free. |
| ZStack overflow diagnostic per-axis fill gate (solver) | **Diagnostic-only.** No measure/arrange output changes — the comparison that EMITS the diagnostic now skips axes the child does not size itself on. Game layouts are unchanged; game surfaces with fill children in ZStacks stop logging false overflow reports. |

## Verification at the judged source

- LuauUI suite: green at close (final count in `artifacts/test.json`).
- Rascal Rally suite: `./run-tests.sh` → **3094 passed, exit 0** — re-run live
  2026-08-08 at the FINAL judged source (after the park-corpse guards, the
  ZStack diagnostic axis gate, and every earlier solver fix); the gate re-runs
  it again at exit.
- Studio canary: the architecture review (F4) correctly observed that the
  ScrollView bar-reserve fix is visible ONLY on the live adapter — the
  headless twin publishes no scrollBarThickness, so the game suite and the
  flat baseline are structurally blind to exactly this change. The five
  reference proofs' live matrix rows exercise the changed path on the live
  adapter (that is where the fix was found and proven), but the GAME's own
  surfaces deserve one live look: a Rascal Rally Studio canary of the sponsor
  overlay + settings (the game's hug-cross scrollers) was attempted at close:
  the mounted-source check PASSED (the open Studio session named "Rascal
  Rally" carries today's LuauUI source via rojo live-sync — both fresh guard
  strings verified in its ReplicatedStorage), but that session hosts a LuauUI
  test place, not the game world, and booting the full game (publish/TT/FTUE
  sponsor drive) is its own mission. The canary is therefore an OWED RIDER to
  the game's next Sponsor round with the director — recorded beside the Step
  10 canary the prior-gates analysis already carries, not silently dropped.
  The automated evidence stands: game suite 3094 exit 0 at this exact source,
  and the changed live-adapter path is exercised by five proofs' matrix rows. Every other framework change this stage
  remains invisible to the game by construction (see table above). The prior in-flight game edit
  found uncommitted at stage start (the sponsor hand played-card pin,
  2026-08-08 director fix) was completed by its own tests and is green; it is
  the game's change, not this stage's.

## What this ledger does NOT claim

It does not claim a live Studio session of Rascal Rally was played this stage
(no game-visible change demanded one); it does not claim device evidence; and it
does not claim the sponsor-hand fix's own director sign-off — that belongs to
the game's Sponsor round, where it was authored.
