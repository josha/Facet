# ADR-0027 — The platform's own chrome is an L, not a bounding box

**Date:** 2026-08-14
**Status:** Accepted
**Commissioned by:** the game director, 2026-08-14. First: *"let's make sure our hud system never
overlaps the roblox controls at the top left, too"* — prompted by a shipped Roblox FPS whose HUD
collapses into Roblox's own chrome when a browser URL bar shrinks the viewport. Then, after the
measurement below: *"we should be able to have things at top that are aligned with the controls but
don't overlap like the settings button in rascal rally or the top-middle controls in rivals."*
**Companions:** ADR-0025 (the screen-anchored HUD — this is its `topbar` row), ADR-0023
(`UI.Composition`), `docs/lessons/the-solver-already-told-you.md`.

## What the live engine actually says

Studio, showcase place, Play mode, viewport **735 x 413** (`mcp__Roblox_Studio__execute_luau`,
2026-08-14):

```
GetGuiInset            top = (0, 58)
CoreUISafeInsets  raw  min = (0, 0)     max = (735, 355)
DeviceSafeInsets  raw  min = (0, -58)   max = (735, 355)
TopbarSafeInsets  raw  min = (164, -58) max = (735, 0)
TopbarInset            min = (164, 0)   max = (735, 58)   571 x 58
probe Frame (ScreenInsets = None) placed at TopbarInset.Min
                       AbsolutePosition = (164, -58)  ->  physical (164, 0)
```

Three facts come out of that, and the third corrects this repo.

1. **Roblox's own controls occupy x 0..164 of a 58px band.** The rest of the band — x 164..735 — is
   explicitly the developer's, which is what `TopbarInset` is for.
2. **`CoreUISafeInsets` is that band's BOUNDING BOX**: a full-width 58px top inset. It is true and
   blunt. A surface that insets by it can never put anything level with the platform's buttons.
3. **`GuiService.TopbarInset` is stated in PHYSICAL WINDOW SPACE.** This repo recorded the opposite
   — `src/env/environment.luau` and `docs/reference/api.md` both said the rect was relative to the
   topbar-safe area and told authors to compute `topbarSafeInsets.left + topbarInset.x` — and
   `tests/adaptive.spec.luau`'s DV3-1 pinned that formula. It is wrong: the two facts are two
   encodings of ONE rect (both say x 164..735, y 0..58 here), and the probe row above places a Frame
   at `TopbarInset.Min` inside a `ScreenInsets = None` ScreenGui and lands exactly on the strip.
   Adding them double-counts the cluster and pushes a docked control a cluster-width too far right.
   The prior mission's own warning ("TopbarInset is NOT the same as physical space") was recorded
   with the sign flipped.

## Decision 1 — one derived fact: `platformChrome`

```
platformChrome = {
  band       = { x, y, w, h } | nil,   -- the FREE strip, window space
  rects      = { { x, y, w, h }, … },  -- what the platform's OWN controls occupy
  insets     = { top, bottom, left, right },  -- clear EVERYTHING
  bandInsets = { top, bottom, left, right },  -- clear everything EXCEPT the free band
}
```

- **`band` is `nil`, not a zero rect.** An engine without `GetInsetArea` keeps zeroes (the adapter's
  pcall belt), and "no strip" and "a strip at the window origin" are the same table with opposite
  meanings. The nil is the guard every consumer used to write by hand — Rascal Rally's
  `FacetSponsor:_topStrip` wrote it as `hasStrip = stripHeight > 0`.
- **`rects` is a LIST.** The top band minus a free strip is an L, and on a notched landscape phone
  it is two rects (the cluster on the left, the notch strip on the right). That is precisely what an
  inset cannot express, and it is the shape the never-overlap check needs.
- **`insets` is what `deviceSafeContent` applies** (per-edge max of core and device, plus the
  ten-foot overscan). It is a second reading of a number the renderer computes inline, so it is
  pinned against the live policy by a contract test — a drift there would silently mis-inset any
  surface that rides the band.
- **`bandInsets` equals `insets` when there is no band**, so a consumer needs no branch and a
  platform with no strip degrades to exactly today's geometry.
- **The band is derived by INTERSECTING** `topbarInset` (window space, per the probe) with the
  topbar-safe rect and with the platform's own top band. On a healthy platform the intersection is
  an identity; when one fact is missing or lying it is a belt. It is never a sum.

## Decision 2 — the HUD's tenth zone: `topbar`, a span row

ADR-0025's nine anchored zones partition the box the surface was given. The topbar band is *not in
that box* under any rect policy, so no anchor could reach it. The framework already had the right
word: a **`span = "above"` group** is "its own full-width ROW above the band of lanes, in every
arrangement". So `composition.ZONES` gains `topbar` and `composition.HUD_GROUPS` gains one span
group.

Two consequences fall out for free, and they are the whole reason this beats a per-zone offset:

- **the lanes start BELOW the row**, so the top-left cluster clears the platform's cluster by
  construction — not by an authored inset, and not by a rule that has to know the chrome is
  164px wide (on a 320px phone that is more than a third of the screen, so "topLeft stays clear" was
  never the right rule);
- **it costs nothing when nobody uses it**: a span group with no regions is inactive, takes no
  height and appears in no output. Pinned as a byte-identical resolution/dump comparison against the
  same HUD without the group, at three sizes.

**The `reserved` flag is load-bearing, and the check found it.** The showcase's topbar row shipped
`mayDrop` first. On a 213px-tall window the rank ladder dropped it (rank 6, 58px bought) — and every
lane then climbed into the space it left, **which is the platform's band**. The band is not the
HUD's to reclaim. Rule 7's `reserved` is the exact word for that, it is live, so the row reserves
nothing at all on the rung that is not riding.

## Decision 3 — the guarantee, asserted

`deviceSafeContent` was already safe, and **nothing asserted it**.
`tests/hud_composition.spec.luau` now drives the SHIPPED showcase fixture at five fact profiles —
the live 735x413 measurement, the same window with the director's 200px URL bar open, a notched
landscape phone, a 320px portrait phone (where the cluster is half the width), and an engine that
reports no strip at all — in four states each (riding / not riding × URL bar open / closed), and
asserts that **no painted node's rect intersects any `platformChrome.rects` rect**.

- The oracle is the ADAPTER's rects, not the composition's own idea of where it put things.
- A pure structural container is skipped (the target reports the live adapter's own elision verdict,
  plus the classes that only ever carry children) **only while it carries no decoration**, so a
  Screen with a backdrop or a Region with a plate is still checked.
- The insets are DRIVEN, never this machine's: `deviceSafeInsets` reads 0 in Studio and non-zero on
  a notched phone, so a check that trusted the local environment would pass everywhere.
- Two vacuity guards, because this project keeps finding checks that prove nothing: the profile must
  produce at least one chrome rect, and the sweep must have examined at least N painted nodes.

**Mutation evidence** (each break reverted immediately):

| break | what reddened |
|---|---|
| the HUD's top inset stops being applied (`margin.top = 0`) | 4 of 5 profiles, naming `/HudScreen/Hud/Rounds/RoundStrip/R1 [box 36x46 at 0,0] paints 36x46px into the platform's own controls` |
| the topbar row stops clearing the cluster (lead spacer → 0) | the 320px phone profile, naming the objective chip's text; and the positive case, which pins the chip's centre to the BAND's centre rather than the window's |
| `platformChrome.rects` stops reporting | every profile, on the vacuity guard — the check cannot silently become decoration |
| the `topbar` group's `span` flips to `"below"` | the span-row case, `expected below to be above` |
| the `topbar` group becomes a lane group | the byte-identical additivity pin |

## Consequences

- **Public surface added:** the `platformChrome` derived env fact; `composition.ZONES` gains
  `"topbar"` and `HUD_GROUPS` gains its span group. MINOR bump. Additive: a composition that
  declares no `topbar` region resolves and dumps byte-identically.
- **Corrected, not added:** the `topbarInset` semantics in `src/env/environment.luau`,
  `docs/reference/api.md` and DV3-1. Rascal Rally's shipped placement is unaffected, because it read
  `topbarSafeInsets.left` and never added the two — it was right for the wrong reason.
- **The showcase demonstrates it and the sweep watches it.** `examples/gallery/scenarios/hud.luau`
  presents `edgeToEdge`, insets itself from `platformChrome`, puts an objective chip in the `topbar`
  row level with Roblox's buttons, and carries a second toggle for the rung that does not ride. It
  MODELS a platform strip when the platform reports none (headless only, and `flags.noTopbarStrip`
  opts out), so the always-on overflow sweep exercises the mechanism at every viewport, in both
  orientations, at all four text sizes — otherwise the strip would be unexercised by the one thing
  that watches everything. The sweep earned its keep immediately: it failed the moment a second
  driver toggle was added, at 320px and the largest preference.
- **The consumer:** Rascal Rally's `FacetSponsor:_topStrip` (the production default since the
  2026-08-03 cutover) now reads `platformChrome.band` for the strip height, the cluster offset and
  the "is there a strip at all" guard it used to write itself. Identical numbers on a real client;
  its DV3-1 fixtures were corrected to state `topbarInset` in window space, because they had encoded
  the semantics this ADR corrected.
- **Not taken:** teaching `UI.Composition` to route its lanes around a list of reserved rects. It is
  the more general mechanism and it is written up here rather than built, because it needs the ROOT
  POLICY to hand a surface both the window box and the unsafe geometry — `renderer.luau` and
  `solver.luau` — and doing it from the composition alone would make it a second safe-area authority,
  which ADR-0025 refused for good reason. The span row gets the director's picture with no new
  plumbing; the reservation model is the upgrade path if a second consumer needs a hole somewhere
  other than the top.
## The Studio canary — real engine, 2026-08-14, and exactly what it covers

Two live readings on `Facet-Showcase` in Play, viewport 735 x 413.

1. **The engine's raw answers**, plus a probe Frame under a `ScreenInsets = None` ScreenGui — the
   table at the top of this ADR. That is what corrected the `TopbarInset` semantics.
2. **The SHIPPED adapter's published facts**, by binding `src/client/roblox_env.luau` to a fresh
   environment in the running client:

   ```
   viewportRect     = (0,0) 735x413
   coreSafeInsets   = (t58 b0 l0 r0)
   deviceSafeInsets = (t0  b0 l0 r0)
   topbarSafeInsets = (t0  b355 l164 r0)
   topbarInset      = (164,0) 571x58
   ```

   Those are **verbatim** the numbers the headless profile named "studio live 735x413" drives in
   `tests/hud_composition.spec.luau`, so the fixture that check runs on is this machine's engine
   rather than a plausible fiction — which is the usual place a device claim quietly becomes a
   self-portrait.

**What it does NOT cover, said plainly.** The showcase place's Rojo session is stale (its
`environment` module has no `platformChrome`), so the derived fact and the HUD fixture were **not
evaluated in-engine**; their evidence is headless, over the same adapter contract the live target
implements. Pushing the modules in by hand would have needed a Play restart in a session four agents
were sharing. Owed: a re-synced Studio canary of the demo, and a physical-device run.
