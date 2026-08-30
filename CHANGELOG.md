# Changelog

All notable changes to Facet are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and Facet's version
numbers follow the policy in
[`CONTRIBUTING.md` §6](CONTRIBUTING.md#6-versioning-and-deprecation): while the
library is pre-1.0, a minor bump may change public behavior, and every retiring
surface is listed in `Facet.DEPRECATIONS` with its replacement and the earliest
version that may remove it.

The version string lives in exactly one place, `src/init.luau`, and is readable at
runtime as `Facet.VERSION`.

## [Unreleased]

### Added

- **A Roblox Package distribution channel.** Facet is now published as one Roblox
  Package asset, which is the recommended install for creators who work in Studio
  without a file sync. The asset id does not exist yet; it is recorded in
  `package/facet-package.json` when the asset is created, and the maintainer
  interface is `tools/package.sh` with [`package/README.md`](package/README.md) as
  its reference.
  Installing, updating, and version checking are described in
  [guide 8](docs/guide/08-without-rojo.md).
- **A standalone consumer project**, `examples/consumer/`, that builds the
  five-minute screen from the public API alone and is proved headlessly by
  `tests/consumer_standalone.spec.luau`.
- **Public project files**: `LICENSE`, `THIRD_PARTY_NOTICES.md`, this changelog,
  [`CONTRIBUTING.md`](CONTRIBUTING.md), [`SECURITY.md`](SECURITY.md),
  [`AGENTS.md`](AGENTS.md), a `skills/use-facet/` skill, and continuous
  integration plus issue and pull-request templates under `.github/`.

### Changed

- **Facet is licensed under the MIT License.** Material this repository did not
  create is listed with its own notice in
  [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
- **Verification runs in four named tiers** — affected, fast, full, and release —
  through one command, `tools/verify.sh`. An ordinary change runs affected or
  fast; a change about to merge runs full; a release runs the release tier.
  `./run-tests.sh` and `./run-tests.sh --fast` still work and still mean the same
  thing.
- **The public documentation was refreshed end to end**: the README, the guide
  index and capability catalog, installation and upgrade instructions, the
  extension playbooks, and every link that pointed at internal material.

### Removed

- **The vendored copy of another reactive library, and its adapter.** Both were
  bake-off arms kept from the comparison that chose Facet's own core; neither
  ever shipped in Facet's runtime, model, or Package. Facet's reactive core is
  and remains its own, in `src/core/`.

## [0.10.0] — not yet published

The version this tree reports as `Facet.VERSION`. It has not been published, so
the deprecation window begins at its first release. Until then the register below
is the record of every behavior change riding this version. Recording the change
is what makes a breaking change legal before a version's first publish
([`CONTRIBUTING.md` §6](CONTRIBUTING.md#6-versioning-and-deprecation)).

### Added

- `Facet.Controls`, a frozen namespace of typed control constructors called as
  `Facet.Controls.<Name>(core, spec)`. Every older `Facet.new<Name>(Facet, core,
  spec)` builder still works and is listed in `Facet.DEPRECATIONS`.
- The world-fixed surface render target, `client.surface_target`: the same flat
  two-dimensional Facet screen on a `SurfaceGui` a player walks up to. It is a
  flat world target, not a spatial one — geometry in front of it blocks input,
  and it pins `AlwaysOnTop = false` so that stays true.

### Changed

- **Adaptation answers for itself.** Controls that need device facts and cannot
  find an environment now refuse to construct instead of quietly assuming a
  large screen with a pointer. A `UI.Grid` given neither `columns` nor
  `minColumnWidth` lanes itself from the box it was given, and
  `UI.AdaptiveStack` requires its `axis`.
- **The ten-foot display class scales type, theme metrics, and paint**, so a
  screen written the ordinary way is legible on a television.
- **Roblox `StyleSheet` paint is the default render path** rather than an opt-in.
- The library is named Facet, and its call shapes moved with the name.

### Behavior changes riding this unreleased version

Each row names the surface, what it did before, what it does now, and why the
move breaks a caller. A change to what the library promises is landed by adding
its row here in the same commit.

1. `UI.AdaptiveStack.axis` was optional and defaulted to `"y"`; it is now
   **required**. A bare `UI.AdaptiveStack{…}` was a permanent vertical stack and
   now raises at construction.
2. `UI.Grid` given neither `columns` nor `minColumnWidth` laid out one lane at
   every width; it now lanes itself from the box it was given
   (`minColumnWidth = "intrinsic"`). A bare grid silently re-lays out: the same
   six cards go from one column to two, four, six, nine, five, or seven across
   the audited viewport combinations.
3. `newPicker`, `newMenu`, `newPopupButton`, `newTabView`, `newTextInput`, and
   `newVirtualList` with `itemExtent = "cards"` each **refuse to construct** when
   no environment can be found. Each previously substituted the large-screen,
   near-distance, no-cutout answer in silence. The refusal replaced wrong
   behavior rather than working behavior: zero of the seventeen shipped `Picker`
   sites had reached the adaptive default.
4. `adaptive.navPlacement` on a tablet answered `bottomBar` and now answers
   `topBar`. A documented policy answers differently for a real device class;
   six shipped assertions were re-pinned because they had asserted the defect.
5. `adaptive.columnsFor` at the ten-foot distance was uncapped and is now capped
   against the wide breakpoint, so a television gets fewer columns than a desktop
   where it used to get more.
6. Unauthored text on a `Large` display scaled only at its authored size; the
   whole type ladder now scales by 1.5. Every screen written the natural way is
   1.5 times larger on a television.
7. Every theme metric on a `Large` display was unscaled and is now scaled by the
   type floor's own factor, so control heights, spacing, icon sizes and the 44px
   hit floor all move on a television.
8. `UI.Composition`'s content lane at the ten-foot distance took an uncapped
   share and is now capped at the lane measure times the metric scale (900px). A
   shipped composition re-measures on a television and nowhere else.
9. `newTable` narrower than its columns clipped; it now **collapses** a column by
   priority and discloses it. Shipped tables re-lay out at the compact size
   class, and a `fill` column's `minWidth` is honored — one playlist column went
   from 30px to 66px.
10. `newTable` selection and edit-mode keys had no modifier semantics: an arrow
    key replaced the selection. Control or Command now moves without selecting,
    Shift extends, and on a table with no `onPrimaryAction` a device Activate
    toggles.
11. A horizontal `UI.ScrollView`'s focus ring ran vertically and now runs
    **horizontally**: Left and Right step the rail, Up and Down leave it. That is
    the opposite of what shipped.
12. `newTabView` and `newPicker` band placement parked in the band's corner and
    are now centred in it. Shipped geometry moves on three placements.
13. The library's own name and call shapes changed: the require path is `Facet`,
    and `Facet.newTable(Facet, core, spec)` became
    `Facet.Controls.Table(core, spec)`. Nineteen call shapes moved; every old
    builder still works and is in the deprecation ledger.
14. The gallery example's `showcase_chrome.TOGGLE_GAMEPAD` was `"ButtonY"` and is
    **removed**. The showcase chrome bound the gamepad toggle to `ButtonY`, which
    is `newMenu`'s own gamepad trigger, so one press opened both. `ButtonY`
    belongs to the menu verb; the pad reaches the chrome through the two shoulder
    buttons instead. This is an example's export rather than a library surface,
    and it is recorded because a consumer copying the showcase's key map is
    exactly who this register is for.
15. `native_style.DEFAULT_ENABLED`, the library's default paint path, was opt-in
    (`false`) and is now default-on (`true`): a `screen_target.new({})` carrying
    no `nativeStyle` option paints through a Roblox `StyleSheet`. Every screen
    target that never named a paint path changes painter. Sheet rules and the
    `::UICorner` and `::UIStroke` modifiers replace the adapter's per-property
    writes, so no `UICorner` or `UIStroke` instance exists under a Facet root any
    more and a consumer reading those instances back finds nothing; the Style
    Editor becomes the paint authority for anyone who opens the place. The two
    paths were measured byte-equal on every mapped property, so the pixels are
    the same and the mechanism is what moved — which is exactly the kind of
    change a consumer's own code touches and a screenshot does not. The escape
    hatch is unchanged and still wins over everything: an explicit
    `nativeStyle = false` keeps the explicit-write path, which stays a
    first-class tested path rather than a corpse.
16. `UI.Region{ expand }` on a form that carries no control of its own
    synthesized a chevron beside the form; it now synthesizes a **cover** over
    the whole form. A passive compact form draws no mark at all and the whole of
    it becomes the tap or Activate target at the standard hit floor, where it
    used to draw a caret in a column the form's own measure reserved. Shipped
    geometry moves: the form gets the mark's column back — one demo's clock zone
    went from 100px to 80px at 360x691 — so a value that was being cut may now
    fit and a screen tuned against the reserved width re-lays out. The cover
    declares `zIndex = -1`, so it and the hit expander banded below it paint
    under every form within its own region. `UI.Foreign` and the lazy regions
    still force the chevron.
17. Corner radii and hairline strokes now scale with the metric ladder at the
    ten-foot display class, derived from the same metric scale so a later scale
    change moves them in lockstep. A radius rounds to a whole pixel because a
    `UDim` offset is an integer; a stroke keeps its fraction because thickness is
    a float. At a scale of 1.5: 12 becomes 18, 8 becomes 12, and 1 becomes 1.5.
    The capsule sentinel scales from 999 to 1499 and paints identically for every
    box up to 1998px on its shorter side. A theme package's ten-foot metrics may
    name a paint path and win on both sides. Near-distance density is
    byte-identical.
18. `UI.Region{ expand }`'s plate-or-sheet selection, and the resolved
    `plate.max`, were measured against the gutter allowance and are now measured
    against **the allowance minus the plate's own chrome** (at a 390px viewport,
    358 becomes 342). A form whose natural width lands in the last few pixels of
    the allowance now falls back to the full-width sheet instead of mounting an
    anchored panel that was wider than the allowance it had just been chosen
    against — reproduced at 390px, where a 320px form gave a 358px cap and a
    380px panel. No shipped screen moves today, which is exactly why the row is
    owed: the next reader tuning a form against the allowance has no other way to
    learn the band exists.
19. The hit expander a `role = "cover"` affordance receives inflated the solved
    rect by 44px unconditionally; it now **grows one side at a time, and each
    side stops at the first rect outside it that can sink a press**. Boxed in on
    every side it retracts, and the affordance is reached through the region's own
    box. A cover is its region's whole box, so the old floor took presses from
    neighbours: measured at 390x150, 960 square pixels of one neighbouring button
    and 828 of another — 26% of each — were delivered to the plate instead of the
    button the player aimed at. Only rects the author declared stop a floor: a
    framework affordance may not take the accessibility floor off another one. Of
    381 swept routes, 38 end below the effective floor and every one is cut by an
    author node; the smallest route is 35px and 31 covers retract.
20. `newPicker`'s activation order is now **one transaction** around both the
    control's own write to `selected` and the `onChange` it then calls. It used
    to be two turns: the write flushed on its own before the callback ran. A caller
    may redirect or veto a pick from inside `onChange` by writing the signal
    back, and until now the value it was about to undo was published first: every
    observer of `selected` saw it, and a `UI.When` over the selection mounted a
    whole subtree and evicted it in the same frame. An observer that counted
    selection changes now sees fewer of them, and an `onChange` inherits a
    transaction body's obligation not to yield. A read is unaffected: a
    transaction defers the flush, never a read.
21. `newTabView` with a declared `sizing = "hug"` resolving to the `bottomBar`
    placement parked the strip at the band's leading edge in a stack that could
    not scroll; it now gets the same **centred scroller** every other hugging
    home gets. The thumb-zone band is deliberately not a scroller because a
    `fill` strip divides the offer and has nothing to overflow with — a statement
    about the default that the code was applying to the home, so a caller who
    declared `hug` there got natural-width segments at the leading edge and a
    strip wider than the phone simply ran off it. The `fill` default is
    untouched.
22. `Facet.text.fit` and `Facet.text.size` decided a size "fits" when the wrapped
    form stayed inside `lines` (and `height` when given); the widest line must now
    also stay inside `width`. A single word has no legal break, so the wrapper
    reported one natural line at every size however far past the box the glyphs
    ran, and the function handed back the cap for a string that does not fit at
    all. For a multi-word phrase nothing moves, except the one case where it
    should not have: a phrase whose longest word is wider than the box, which the
    engine breaks mid-word and paints outside the column.
23. A `hug` dimension on a `UI.ViewThatFits` **candidate** was measured at the
    minimum of content and offer, like every other `hug`, so the width test was
    true at every width. It is now resolved as content, uncapped, for the
    duration of the fit probe; the author's own `min` and `max` still bind, and
    the winning candidate is capped by its offer exactly as before. A `hug`
    candidate could never report "does not fit", so the ladder pinned its first
    rung forever and the labels it exists to protect truncated anyway. Refusing
    `hug` at construction was rejected: a control that picks `hug` for itself
    would have been refused for a spelling its author never wrote.
24. A `topbar` region under `rootPolicy = "bandSafeContent"` was a row spanning
    the composition's full width, as tall as its own content. It is now laid into
    the platform's own free strip — that strip's x and width, reaching its bottom
    edge — and the lane band below it is floored at the platform's whole top
    reservation. The tenth zone is the one that is not an anchor, and its purpose
    is to sit level with the platform's own controls; until now its geometry was
    the consumer's, held open with spacers and a memo. A caller that declares a
    `topbar` region now gets a row whose x, width and height are all platform
    facts, so a hand-computed spacer beside it is a double reservation. Two
    further consequences: a span row's slack now goes to its `fill` regions, which
    is what lets a region centre in the strip rather than sit at the top of it;
    and the lane band's floor is the platform's whole reservation rather than the
    band's bottom edge, except for a composition that both rides the strip and
    declares `exclusions`, which has already said where its own chrome is per
    column and gets the platform's own row instead of the bounding box. A
    composition that declares no `topbar` region resolves exactly as
    `deviceSafeContent` would have resolved it.
25. The gallery's grid scenarios forced their cell and line gaps to `"xs"` (4px)
    at Studio Neutral, because no space step named 6. They are restored to
    `"tight"` (6px), the value both fixtures originally wanted, now that
    `space.tight` exists as a derived step naming the value halfway between `xs`
    and `s`. Both grids' rendered gutters grow from 4px to 6px in the shipped
    gallery: a deliberate value change, not a value-identical rewrite.
26. Two gallery viewports carried literal pixel heights (150 and 120, each a
    hand-guessed "roughly N rows with the next one peeking through"). They are
    now content-terms formulas — four rows of the compact control height (144px),
    and six lines (116px). Both render 6px and 4px shorter at Studio Neutral, in
    the safe direction for a viewport: the old 150 never held four full rows
    either, since the rows are 46px each. What actually changes is that both now
    grow at the ten-foot ladder and at a raised text preference, where the frozen
    literals never did: 144 becomes 216, and 116 becomes 173.
27. Under `rootPolicy = "bandSafeContent"` with both a declared `topbar` region
    and declared `exclusions`, the lane band used to start at the topbar row's own
    measured height with no platform-reservation floor under it whenever the
    platform band was absent. It now falls back to the same reservation the
    no-exclusions path already used. The platform band really is absent on a live
    device, both at boot before the first platform push and on a measured
    rotation-recovery frame, so this was a real lane-and-topbar overlap risk
    rather than a headless-only one.
28. The expand plate's close disc used a spacing step (`space.xs`) for its corner
    inset, which had no relationship to the focus ring it exists to clear. It now
    uses the larger of that step and the ring's own inset. Every package whose
    spacing already cleared the ring gets the identical inset back; the two
    packages that were short move from 3px to 4px at the ten-foot ladder, closing
    a measured 1px overrun by construction rather than by a named ratchet.
29. `surface = "badge"` had no intrinsic size at all — a bare glyph hugging its
    own pixels, or an empty zero-sized box. It now carries a theme-owned minimum
    (20px at Studio Neutral, scaling at the ten-foot ladder like every other
    control metric) on both axes when the author declared neither `width` nor
    `height`.
30. Two gallery motion fixtures sized their lane and puck with a raw 40, unscaled
    at every display class. Both now use the theme-owned decorative-chrome floor:
    identical 40 at Studio Neutral and Medium, and 60 at the ten-foot class — the
    first scaling either box has ever had. Both render 20px larger there, in the
    safe direction.
31. `UI.Composition{ exclusions }` shared a lane's slack out as the lane's budget
    without the chrome row, rather than as the lane's own already-inset height.
    An `end`-placed group landed exactly the give-way inset past the bottom of its
    own lane, a `center`-placed one half of it, a numeric placement a matching
    fraction of it, and a `fill` group took the same phantom pixels as height.
    Measured one-for-one from a 1px inset to a 300px one, and seen live at 141px
    on a console and 54px on a phone. It is a defect fix that restores the
    partition guarantee, and shipped geometry moves for every consumer that
    declares `exclusions`.
32. The themed-chrome family changed in four places. An inset was spent whenever
    any pixels remained; it is now spent only when the node's own line box still
    fits — a text-bearing leaf needs more than its text size, everything else is
    unchanged — on both the measure and the paint seam. A sibling plate's border
    is no longer spent twice. The pill selection indicator's inset is reduced by
    the plate slot's carved border. Shipped geometry moves under every package
    that carves a border: an ornate disc loses the frame it was reserving twice
    (60px becomes 52px under one package, 44px becomes 38px under another), and
    every pill indicator covers its whole segment rather than an inset chip.
    Studio Neutral and every flat package are byte-identical, because their carve
    insets are all zero.
33. `newMenu`'s automatic presentation at a **compact** size class with a
    pointer-primary interaction class resolved to its own answer, gated on live
    touch plus an item count; it is now forced to the sheet presentation whenever
    the size class is compact, unconditionally. A documented policy answered
    differently for a real, reachable environment — a compact width with no touch
    signal, which is a phone with a mouse, or Studio's own compact preset, which
    cannot inject touch at all. Every submenu now replaces the panel in place with
    a Back row instead of floating a second panel over a parent that does not have
    room for it. The regular and wide classes are unaffected, and an
    author-forced presentation is unaffected at any width.
34. `distanceProfile`, `typographyScale`, `typographyPaintScale`, `themeMetrics`,
    `sizeClass` and `effectiveOverscanInsets` resolved from the raw `displaySize`
    and now resolve from the derived `effectiveDisplaySize`, which downgrades
    `"Large"` to `"Medium"` when the session is touch-capable. On a
    `"Large"`-reporting, touch-capable session the ten-foot type and metric scale,
    the density cap and the console overscan margins now read off, 1, uncapped
    and zero, where they used to read on, 1.5, capped and 60 to 90px.
35. Under `scrollIndicatorPolicy = "auto"`, the solver's scroll-bar reserve was
    policy-blind: `"always"` and `"auto"` reserved the same thickness. It is
    policy-driven again. `"always"` is unchanged; `"auto"` now publishes zero, so
    content measures to the full cross-axis width instead of the width minus the
    bar. Content that used to stop 8px short of the scroller's own edge now runs
    to the full edge. A bare zero reserve alone would reproduce an older defect,
    because Roblox narrows a `ScrollingFrame`'s window by the bar's thickness
    whenever the scroll axis overflows regardless of paint policy — measured
    again this round, and a fully transparent bar image does not stop it — so the
    zero reserve is paired with widening the scroll host's own frame by the same
    thickness on the cross axis while it overflows. The overlap is the bar sitting
    in that borrowed space.
36. The float focus ring a focusable control draws inside a clipping or scrolling
    host read its corner radius from the target's construction-time style, which
    no theme swap ever reassigns; it now prefers the live theme snapshot's radii
    and falls back to the construction-time style only while no package is
    installed. The corner was also built only on first creation and is now
    re-synced on every focus-visual call, so a live swap's repaint reaches it. A
    focused control's ring corner moves under any installed package whose control
    or panel radius differs from the target's boot radius, on the first focus
    after a swap. With no package installed at all it is byte-identical.
37. Every badge overlay in the repository — the segmented picker's count seal and
    the gallery's hand-rolled tile badge, two independent implementations — was
    anchored flush at the raw corner under every package. Each now insets top and
    right by the theme's carved border for its slot, through one shared
    primitive rather than the same four-line loop written by hand three times.
    Shipped geometry moves under any package that carves a control or accent
    border; flat and Studio Neutral packages are byte-identical, because the
    computed inset is zero on both axes.
38. Every `UI.Path` wrote its normalized control points as pixel offsets and now
    writes them as scale. A `UDim` offset is a 32-bit integer — measured live on a
    round trip, `UDim2.new(0, 25.05, 0, 6.95)` reads back as 25 and 6, while the
    same pair survives to six decimals as scale — so every control point was
    truncated to a whole pixel. A 32px progress ring lost 0.8px at its 3 and 6
    o'clock extremes and 0.2px at 12 and 9, painting as an off-centre egg, and a
    closed ring's last point floored to 15 where its identical first point floored
    to 16, so the track closed one pixel left of where it opened. Separately, the
    showcase's glass plates now declare their own surface role and take the
    caller's gutter through one shared inset memo, instead of painting a raised
    box behind a sibling that wrote its own gutter.
39. The layout reserve every native scroll host spends under
    `scrollIndicatorPolicy = "always"` was exactly the bar instance's thickness
    (8px) and is now that thickness plus a one-pixel gutter (9px). The bar
    instance itself is untouched at 8px, and so is the engine's own window
    narrowing, which is what makes the extra pixel visible rather than painted
    over. Every overflowing `"always"` scroll host lays its content out 1px
    narrower on the cross axis, and the gutter a sibling pays — a table header
    aligning with its body — grows from 8 to 9 on the right for a vertical
    scroller and on the bottom for a horizontal one. `"auto"` is untouched: it
    reserves zero and deliberately overlaps. The earlier round had already
    measured that this boundary was not an overlap; the ruling is that
    exact-and-flush is the defect, because content on the bar's outermost pixel
    reads as a collision.

## Earlier versions

Versions 0.4.0 through 0.9.0 predate this file. Their public surfaces are
documented in [`docs/reference/api.md`](docs/reference/api.md), and the retiring
ones are listed with the version that may remove them in `Facet.DEPRECATIONS`.
