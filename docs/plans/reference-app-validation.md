# Validate SwiftUI-scale reference apps with Facet

**Status:** Planned after keyboard support and the tutorial quality pass.

## Question

Can a Roblox developer use Facet to build the in-experience parts of Apple's
Backyard Birds, Food Truck, and Fruta samples from one declarative description that
adapts across Roblox devices?

The answer must separate three things:

1. **Facet behavior** — layout, controls, navigation, input, styling, motion, state
   binding, and presentation inside a Roblox experience;
2. **game or Roblox-service behavior** — persistence, commerce, network data,
   localization, timers, and domain rules;
3. **Apple host-OS behavior** — widgets, App Clips, Live Activities, Dynamic Island,
   WeatherKit, and other surfaces Roblox does not expose to an experience.

An unavailable host-OS surface is not a Facet defect. The core in-experience flow
may still be fully achievable through a Roblox-shaped design.

## Source and intellectual-property boundary

Re-read the current official Apple documentation and downloadable sample source at
the start of the stage. Record the source date and exact features observed. Apple is
the behavioral reference only.

Create clean-room Roblox proofs with original names, copy, data, and visual assets.
Do not copy Apple source, art, trade dress, or product identity into the repository.
Link to the official samples in the audit.

Official references:

- [Backyard Birds](https://developer.apple.com/documentation/SwiftUI/Backyard-birds-sample)
- [Food Truck](https://developer.apple.com/documentation/swiftui/food-truck-building-a-swiftui-multiplatform-app)
- [Fruta](https://developer.apple.com/documentation/appclip/fruta-building-a-feature-rich-app-with-swiftui)

## Required proofs

Build three self-contained, deterministic sample places or equally isolated place
scenarios. Each must exercise a complete representative loop, not a static screen:

- a garden/collection experience with persistent-looking resources, refill actions,
  detail, and a purchase/subscription-shaped flow using deterministic fake services;
- an operations dashboard with adaptive split navigation, recent orders, detail and
  status changes, a timer, a custom thumbnail layout, and charts;
- a catalog experience with browse/search, favorites, rewards, recipes, ordering,
  localization expansion, and a compact entry flow that reuses the full experience's
  components.

The proofs test UI capability, so they must not make real purchases, write live player
data, call private services, or require a network. Map the production Roblox service
that a real game would use and state what remains game-owned.

## Framework responsibility

Use only public Facet APIs for UI composition. Each proof owns its domain state,
content, and commands, and declares style/control/layout intent. Facet owns reusable
layout, focus, input, accessibility, presentation, motion, and platform adaptation.

Create a responsibility and capability ledger before coding. If a core interaction
needs reusable framework behavior, fix and prove it in Facet rather than adding raw
GuiObjects, local input listeners, a parallel focus graph, or imperative responsive
layout. Small compatible framework fixes are in scope. A large new subsystem becomes
an evidence-backed follow-on proposal; do not disguise it as sample code.

## Evidence

For every feature in the official samples, classify it as available, composable,
framework gap, Roblox-service adaptation, or no Roblox host equivalent. Cite the
running proof or source evidence. Do not turn the matrix into a percentage score.

Play each proof across the five-view Studio matrix and relevant keyboard, pointer,
touch-shaped, gamepad-shaped, preferred-text, reduced-motion, and localization rows.
Use public theme packages and prove the same semantic tree survives reflow, live
state, focus, and theme changes. Pair captures with geometry, input/action, focus,
state, lifecycle, and performance evidence.

## Gate

Register `swiftui-reference-app-validation`. The gate passes when all three clean-room
proofs run from self-contained builds, their representative loops work, the complete
feature ledgers are honest, reusable defects are fixed in Facet, no local workaround
substitutes for framework behavior, existing gates remain green, and the parity and
authoring documentation explain both what Roblox can reproduce and what has no host
equivalent. Physical and subjective rows may remain explicitly pending.

