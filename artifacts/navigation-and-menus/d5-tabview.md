# D5 — the `TabView` construct

Brief: `docs/plans/navigation-and-menus-brief.md` §2 D5. Director call:
`artifacts/navigation-and-menus/additive-vs-net-new.md` §6 — **compose the D6 picker's
strip, do not reimplement the row.** Acceptance rows NM-5.1 … NM-5.7. Built 2026-08-16
against LuauUI `0.9.0`, on D4's seam (`0ad61ff`) and D6's picker (`74d040b`).

## The public surface

```lua
LuauUI.newTabView(LuauUI, core, {
    id?,
    selection,      -- owner-held Signal of a tab id            (required)
    tabs,           -- { { id, label?, icon?, badge?, content } } (required)
                    --   content = (tabScope) -> Blueprint       — a FACTORY
    placement?,     -- "automatic" (default) | "bottomBar" | "bottomBarCompact"
                    --                       | "topBar" | "sidebar"
    indicator?,     -- "automatic" (default, = "underline") | "underline" | "pill" | "none"
    sizing?,        -- "automatic" (default) | "fill" | "hug"
    iconOnly?,      -- boolean, the strip's group icon decision
    conditions?,    -- the table `LuauUI.adaptive.conditions(core, env)` returns
    env?, enabled?, onChange?,
})
-> { blueprint, placement, dump, dispose }
```

`placement` is published as a Readable so a screen with its own chrome to place reads
**one** answer instead of re-deriving the policy. `dump()` is
`"luauui-tab_view-dump/1"` and carries `placement` / `requestedPlacement` /
`placementSource` / `nested` / `sizing` / `axis` / `mountedTabs` / `contentMounts` /
`contentEvictions` / `reveals`, plus `strip` — the picker's own dump, nested rather than
paraphrased.

## The strip IS `newPicker`, and here is what that cost

Four things landed on the picker, all additive, all properties or type widenings, none
of them tab-specific. Every one is proved on the picker, through the public surface, in
`tests/picker_segments.spec.luau` — not only through the construct that needed it.

| Added to `newPicker` | Why the strip needed it |
|---|---|
| `sizing = "fill"` (default) `\| "hug"`, **reactive** | **A `fill` strip cannot overflow.** Five tabs at 320 px are 64 px each, so an autoscroll built on the default sizing tests nothing. `hug` gives the band and every segment its natural width, which is what makes `f1`'s strip wider than its offer and gives a scroll host something to scroll |
| `axis` accepts a **Readable** | A tab bar's home moves under a live rotation (`sidebar` → a vertical rail, `bottomBar` → a horizontal band) and the A-AL2 rule says an arrangement change is a RE-SOLVE, not a rebuild. A build-time axis would have forced two strips under two `When`s — the hand-assembly D5 exists to delete |
| `Option.badge` | The count seal. Not tab-specific at all: a segmented control over a message list wants one. `surface = "badge"` is a shipped Text token, so this added no primitive |
| `Option.label` accepts a **Readable** | The reference shells carry a SECOND localized string for the thumb zone and flip between them live. `compactLabel` is deliberately not reactive (a compact form is what a control HAS), so the binding has to be the label itself |

Plus `api.segments` — the `{ value, id }` pairs the strip gave its segments, the same
table the D4 indicator is handed. `controller.scrollToVisible` takes a mounted PATH, and
finding the node for a selection value means walking the tree for that id; string
arithmetic on `"Opt1"` is the assumption that breaks the day the picker's internals move.

**A badged option gains one wrapper node, and only a badged one.** The seal cannot be a
Button CHILD — a Button with children draws no text at all (`renderer.luau:913`, "a
content button's label is SEMANTICS, not paint"), which would take the word away from
every segment carrying a count and throw out the `compactLabel` degrade ladder with it.
It is an overlay SIBLING inside a per-segment `ZStack` (`p4_foyer`'s own `badgeBubble`
shape), the Button keeps its id, and an unbadged picker mounts no wrapper — so every path
that shipped before D5 is byte-identical.

## The nesting rule, as it is written in source

> **THE APP-LEVEL PLACEMENT BELONGS TO THE OUTERMOST TABVIEW. A TabView BUILT INSIDE
> ANOTHER TABVIEW'S CONTENT IS INNER BY CONSTRUCTION, AND AN INNER TABVIEW NEVER READS
> `adaptive.navPlacement`.**

`r2` is exactly that: a top tab bar inside a screen that is itself a tab of the app-level
bottom bar. If the inner one also asked the policy, a phone would answer `bottomBar` for
both and the page's tabs would be drawn in the thumb zone on top of the app's — two bars
claiming one home, the inner one winning because it is painted later.

It is decidable **without asking the caller**, because `content` is a factory this
control invokes (which is also what laziness requires): a TabView constructed during that
invocation is inside one. `BUILD_DEPTH` is that fact — a synchronous build stack raised
around the caller's factory and lowered under `pcall`, so a factory that throws cannot
leave it unbalanced. Two escapes stay open and both are explicit: a **declared**
`placement` never consults the policy, and an inner TabView built outside the factory is
telling the framework it is not inside anything. `dump().placementSource` reports which
of the three answered (`policy` / `declared` / `nested`).

**The other two things two live TabViews could fight over are never claimed at all.** A
TabView is a LAYOUT construct, not a presentation: it pushes no focus scope (no
`transientScope`), traps nothing, opens no presenter surface and never touches `back()`.
Its strip is ordinary Buttons read in document order and its content is a `When` branch.
There is no scope to arbitrate and no stack to unbalance.

**The two-level spec** (`tests/tab_view.spec.luau`, six cases) mounts an app-level
TabView whose `discover` tab builds a page-level one inside its content factory, and
asserts, on one 320×640 canvas:

| Claim | Assertion |
|---|---|
| the app takes the bottom bar, the page takes the top | `outer.placement = "bottomBar"` / `inner.placement = "topBar"`, and both bars really are mounted in different homes |
| the policy is never consulted by the inner one | on a 1200×900 pointer desktop the outer becomes `sidebar` and the inner is **still** `topBar` |
| no focus scope is claimed | one flat document order — inner strip (2), outer strip (3) — and nothing is trapped |
| the `back()` stack is untouched | `pres.depth()` is 1 before and after switching both levels four times |
| two Signals, two owners | moving the inner selection leaves the outer's alone |
| the inner one is CONTENT | switching the outer tab away disposes it; coming back rebuilds it and it is nested **again** (the depth is a stack, not a one-shot flag) |
| an exploding factory leaves the depth balanced | a TabView built after the explosion is not falsely nested |

## Lazy content, evicted state — and it is the framework's own `When`

`UI.When`'s `thenView` already receives a BRANCH SCOPE that `mount.luau:232-234` disposes
on unmount. So `content = function(tabScope) … end` gets a real disposal for free, and
**the escape hatch is ownership rather than a flag**: own it on `tabScope` and it dies
with the tab; own it on your screen's scope, outside the TabView, and it outlives every
switch — exactly as `selection` already does. There is deliberately no `retain` flag.

**The memory-neutrality spec, and its actual numbers.** `core:counters()` on a
three-tab TabView, after **one warm-up cycle** and then **thirty switches**:

| counter | baseline (after warm-up) | after 30 switches |
|---|---|---|
| `signals` | 42 | 42 |
| `memos` | 49 | 49 |
| `observers` | 40 | 40 |
| `effects` | 1 | 1 |
| `scopes` | 8 | 8 |
| `settles` | 2 | 2 |
| `contentMounts` | 3 | **33** |
| `contentEvictions` | 2 | **32** |

(measured on the spec's own three-tab fixture; the absolute numbers are the whole
mounted surface — presenter, screen, strip, indicator and one tab — and only the fact
that they do not move is the claim.)

The warm-up is stated rather than hidden: the D4 indicator builds its four springs
**lazily**, on the first slide, and they belong to the strip's scope for the control's
whole life. A baseline taken before any switch counts that one-time allocation as a leak.
The claim is that *switching* is neutral, not that the first switch allocates nothing.

**And the neutrality assertion is measuring something**, which is its own case: a tab
whose factory owns five memos and a disposer on `tabScope` drops **≥5 memos** on the way
out, fires its disposer exactly once, and restores the exact count on the way back in.

**The accepted cost, in the spec rather than only in prose:** returning to a tab replays
its entry cost (a case counts the factory running twice), and state held **outside**
survives it (a case reads a caller-owned Signal back after a round trip).

**The strip is never evicted.** A case switches six times and asserts the badge on the
*unselected* tab still reads `12` and every tab node is still mounted, while
`contentEvictions` climbs.

## Overflow scrolls — through the shared substrate, not a fifth clamp

**The brief named the wrong API and this deliverable verified it.**
`src/input/autoscroll.luau` is a drag-to-edge POINTER PROXIMITY model — band, dwell,
ramp, velocity, **vertical bands only** — whose own header says *"Non-pointer schemes
have no autoscroll path at all"*. It never scrolls anything into view.

`solver.keepVisibleOffset(spanStart, spanSize, offset, band, extent)` is the real
minimum-distance rule (A-SV2), and `controller.scrollToVisible(path)`
(`renderer.luau:3511`) is that rule already applied to a **mounted rect**: it finds the
nearest ScrollView ancestor, reads the live offset, handles the axis and the clamp, and
returns `false` when the target is already visible. A tab is mounted (the strip is never
evicted), so this substrate applies directly and re-deriving the arithmetic here would be
a fifth copy of a clamp that exists once on purpose.

**A keyboard or gamepad move onto a tab is already revealed** — the presenter calls
`scrollToVisible` on every focus move (`presenter.luau:2690`) — so this control adds
nothing for it. What is genuinely uncovered is a selection change that did *not* move
focus (a tap, or a caller writing the Signal), and that is the only case handled: in
`syncGeometry`, guarded on the selection having changed since the last reveal, because
`scrollToVisible` reads the last solved rects and `syncGeometry` is the callback that
runs immediately after a solve.

Five long-named tabs at 320 px in a `topBar`: the strip measures wider than its band,
selecting the last one moves the host's canvas offset above zero and lands the tab inside
the band, an already-visible selection issues **no** scroll, ten idle refreshes issue no
scroll, and a `bottomBar`'s `fill` strip reports `reveals = 0` because it has nothing to
scroll — which is correct, not a failure.

## Reachability

- **Four inputs**, each device-true: `adapter.tap`, `adapter.touchTap`, `Right`+`Return`,
  `DPadRight`×2+`ButtonA`.
- **The gamepad shoulders page**, and clamp rather than wrapping. They are bound
  **dynamically** through `adjustTargets` — only while the focused path is one of the
  strip's tabs — so a screen carrying a TabView never shadows gameplay bumpers off-target
  (the ADR-0013 hazard, with its own case).
- **`adjustTargets` deliberately does not claim the content's focusables.** Paging from
  anywhere inside the page would read well, but a tab's content holds Sliders and Tables
  that declare their own adjust targets, and claiming a path another control owns is a
  contention this construct has no business creating.
- **Document order**, and the strip reads where it is **painted** — a leading rail and a
  top band before the content, a bottom band after it (`p1_glade/init.luau:953`'s shipped
  rule).
- **44 px on both axes, in every home**, swept across three canvases. The floor is the
  picker's, which is the point of composing it.
- An **icon-only** tab draws the glyph and still carries `label` as its semantic name.

## Three defects this deliverable found in shipped machinery

**1. The selection indicator learned its mounted paths exactly once.** D5's strip is
re-homed between four `When`-gated positions as the placement changes; every reference
shell does the same by hand. `selection_indicator` guarded its path walk on
`layerPath == nil`, so after a re-home `rectOf` answered nil for a path that no longer
existed, `syncGeometry` returned early, and the bar froze at the rect it held before the
rotation — a chip painted where nobody measured. It is a real latent bug for *any*
consumer that mounts an indicated strip inside a `When` that toggles, so the fix is
there: the root's path is compared each sync and a different mount forgets everything
learned about the old one.

**2. A thin themed rule cannot wear a control's chrome.** The indicator's bar was
`surface = "accent"` for both skins. Right for the PILL — a ~40 px chip has room — and
wrong for the UNDERLINE, which is `space.xs` deep: the first swept consumer filed *"the
'control' chrome contentInsets could not be spent on y: 20px of border on a 4px height"*
**eighty-seven times** across the theme matrix. The underline now paints with `tint`
(a continuous colour blended between two theme roles, no chrome, still themable) — the
idiom `p4_foyer`'s own hand-rolled 3 px active bar already used. `spec.surface` still
overrides on either skin.

**3. An `AdaptiveStack` running along x navigated VERTICALLY on a pad.**
`focus_map`'s auto-group derivation matched `HStack` alone, in **three** places
(`autoGroups`, `layoutGroups`, and the `hasHorizontalStructure` gate). `AdaptiveStack`
exists so a row/column flip is a re-solve rather than a remount, which is exactly why
every adaptive row of controls the framework builds is one — `newPicker`'s segmented
option strip, and therefore this control's tab strip, are both `AdaptiveStack`s. **Every
segmented picker in the framework answered Up/Down and Right walked out of the control.**
One shared predicate now answers all three, and it reads the axis LIVE.

> **The rule is BOUNDED, and the bound is not a heuristic.** An `AdaptiveStack` is also
> how a construct flips a whole SCREEN between arrangements — this control's own root is
> one. A horizontal RUN is therefore a node **no child of which holds more than one
> focusable**: a strip of segments has one per child however each is wrapped (a badged tab
> wears a cell around its Button), and a container of REGIONS has a child holding several.
> Rascal Rally's only `AdaptiveStack` is exactly the second shape, which is why the game's
> rider pins the bound rather than the rule.

> **One honest limit, measured.** The presenter caches the whole derivation against the
> renderer's structure epoch, so an axis flip with no other consequence does not re-derive
> until the next structural change. Both shipped flips DO change structure and were
> checked live: a Picker resolving `segmented → inline` re-derives (horizontal → vertical),
> and a TabView re-homing `bottomBar → sidebar` re-derives (horizontal → vertical). A
> caller binding `axis` to a bare signal and changing nothing else keeps the previous
> group for one structural beat. Recorded in `focus_map.luau` beside the rule.

Two more, found in this control's own first draft by its first consumer: the content
region was a `ZStack`, which gives a child its NATURAL size — a real page measured wider
than a phone and the solver filed *"this child overflows its zstack by 512×0px"* at every
one of the five matrix viewports (it is a `VStack` with `align = "stretch"` now, which is
what every hand-built content host declared); and the bands carried a `padding = "xs"`
nobody asked for, which cost a 320 px-tall landscape eight of its pixels.

## The reference app: `p4_foyer` migrated

`examples/reference/p4_foyer` was the candidate whose chrome is cleanly separable — its
own comment says *"the top chrome bar, and the search that lives in it, is its own band
and stays where it is on every placement"* — so it could adopt the construct **whole**
(`nav.blueprint`) rather than borrowing pieces of it. `p1_glade`'s content lives inside a
`UI.Composition` region and `p3_sipworks`' search field has three different homes across
the placements; neither can use a construct that owns both the strip and the content
without a slot this deliverable did not add.

**What the diff removed — 155 lines of nav assembly, replaced by a `tabs` array:**

| Deleted | What it was |
|---|---|
| `navTopBar`, `navRail`, `bottomBarFull`, `bottomBarCompact` | four hand-built bars |
| four `When`s in the screen + four placement memos (`navSidebar` / `navTop` / `navBottomFull` / `navBottomCompact`) | the placement switch, written out |
| `navItem` / `navItems`, called **three times** | three copies of the wing list, one per presentation |
| the per-wing `ActiveBar` `UI.Box` | a hand-rolled 3 px selection rule → D4's sliding indicator |
| `NavTopFit`'s `ViewThatFits` ladder | a per-home title→icon ladder → `compactLabel`, measured |
| `RAIL_W = 144` | a hand-picked rail width → the theme's tap-target floor and the widest wing |
| `HomeWhen` + `StubWhen` | one branch for home and one for "everything else" → one branch per destination |

**Four visible changes, each a deliberate trade recorded in the file:**

1. the active bar is the framework's sliding indicator, and it **slides** rather than
   cross-fading two fills;
2. **icon-only is a FIT decision now, not a per-home one.** The bottom homes hard-coded
   it so no wing could ellipsize; `Option.icon` rides `compactLabel`, and a Button with
   one declared never ellipsizes — it draws the glyph. Same guarantee, one fewer rule, and
   the rail and top band keep their words for free. The foyer spec pins it across both
   bottom canvases at all four preferred-text offsets: **zero truncated strip text**;
3. **the wing names now follow a live locale flip.** `newLabel`'s title is a plain string
   by contract, so the old wings resolved at build locale and this proof's own loop could
   not move them; a picker option label may be a Readable, so they are `L(…)` memos;
4. **the top and compact bands LEAD rather than CENTRE.** This is the one regression, and
   it is measured rather than assumed: a bar that can OVERFLOW is a scroll host, and a
   `fill` child inside a horizontal ScrollView resolves to the **content** width (measured
   — 120 px inside a 400 px band), so there is no band width to centre within; a
   `ViewThatFits` ladder would mount the strip **twice** (both candidates are mounted;
   the loser gets a zero rect). Five wings that scroll beat five wings that centre and
   truncate — but the centred cluster the director refined on 2026-08-09 is gone from this
   proof, and that is the honest price of the migration.

The foyer's own spec was re-pointed, not weakened: the four-home geometry case, the
below-the-content case, the traversal walk, the pad walk, the stub case and the locale
case all still assert about the same behaviours through the construct's paths, and the
"no bottom wing carries a title" case became "no bottom wing is ever cut off: the ladder
degrades the WORD to the GLYPH", which is the claim that survived the change.

Three ledgers moved with it, and one row **closed**: the theme ledger's
`BottomBar/Nav_*` row (`content overflows this hstack by 30px`, four packages,
`row-cannot-shrink`) no longer fires anywhere — the wings degrade now — so it was deleted
rather than re-pointed, which is what that list exists to make possible. A second
(`FeedPage` collapsing under `compact-pointer` / `scifi-hud`) closed when the bands
stopped padding themselves. Two rows were re-recorded with new ceilings (16→19 px
unthemed, 86→96 px themed), and one **new** row was added for the construct's own root at
the single most extreme matrix cell.

## Mutation ledger — 17 run against the shipped source, 16 bit

Each was applied to the shipped source, the named specs re-run, and the source restored.

| # | Mutation | Reddens |
|---|---|---|
| M1 | eviction downgraded to a HIDE (every tab stays mounted) | 8 cases: laziness, the teardown, memory neutrality, the tab-scope disposal, the badge-survives case, the nested eviction |
| M2 | — folded into M1: "keep every tab mounted" *is* the hide, and a separate "the strip is torn down with the content" would have to move the strip into a tab branch, which M10 already covers as a declaration-order change | — |
| M3 | an inner TabView claims the app-level placement | 4 cases, the whole nesting block |
| M4 | the selected tab is never scrolled into view | `selecting an off-screen tab scrolls it into view`, and the idempotence case |
| M5 | shoulder paging lost (`handleAdjust` consumes nothing) | the keyboard and gamepad affordance cases |
| M6 | `adjustTargets` OVER-claims every focusable under the TabView | **NOTHING — recorded as an honest non-bite.** The over-claim is inert: `handleAdjust` still refuses a path that is not a tab, so pressing a shoulder in content does nothing either way. The real cost is a gameplay bumper bound while focus sits off the strip, and no headless instrument can observe a binding that produces no effect. The refusal is a design rule the source states, not a checked one |
| M7 | the content region back to a `ZStack` (no stretch) | `the content region STRETCHES its tab to the offer` |
| M8 | `resolveSizing` always FILLS | 6 cases: the sizing rule, the overflow width, both scroll cases |
| M9 | `resolveSizing` always HUGS | the sizing rule and `a FILLING thumb-zone band has nothing to scroll` |
| M10 | the strip declared FIRST in every home (paint/read order lost) | the two-level document-order case and the ADR-0013 hazard case |
| M11 | the indicator learns its paths ONCE again (no re-home) | `re-homing the strip re-resolves the layer and every segment` — **after the case was strengthened.** The first pass did NOT bite, because the case asserted counts that stay correct while the seam goes deaf; it now asserts `geometryUpdates` climbed, which is the thing a stale path stops |
| M12 | the underline paints with the control SURFACE again | the `p4_foyer` theme sweep (87 findings) |
| M13 | `focus_map` matches `HStack` alone again | 6 cases across two specs: both TabView key-driven cases, the bar's horizontal group, and all three picker group cases |
| M14 | the run BOUND is dropped | the TabView group case **and the Rascal Rally rider's `Split`-shaped case** |
| M15 | picker ignores `sizing` | the hug case and the reactive-sizing case |
| M16 | a badged option mounts no seal | 6 cases, the whole badge block |
| M17 | `dump()` reads the label it was BORN with | `a bound label … is what dump() announces` |

## Rascal Rally consumer impact

**No production edit, and it is audited rather than assumed.** The game builds no
`newTabView` (a tripwire in the new rider reads that off the shipped source every run and
fails the day it stops being true) and no `newPicker` (the D4 rider's tripwire, still
green), so nothing additive reaches a shipped screen.

**But one half of this deliverable is a behaviour change to shipped machinery, and the
game is inside its radius**: the `focus_map` horizontal-run rule. Rascal Rally mounts
exactly **one** `AdaptiveStack` — `TableScreen`'s `Split`, whose axis is reactive and
really does resolve to `"x"` on a landscape canvas. `tests/luauui_tab_view_contract.spec.luau`
(new, registered in the game's `tests/run.luau`) is six cases:

- `newTabView` is live through this package's own require path, with the documented dump
  and a closed spec that refuses an unknown key;
- two levels nest here too, and the inner one never claims the app-level placement;
- switching is a real disposal, counted on this package's core;
- the tripwire;
- **the `Split` case**, on the LIVE mounted sponsor table at the landscape viewport where
  the axis really is `"x"`: no navigation group is named after the split, and the racer
  list is still walked **vertically** — which is the behaviour a wrong rule would have
  taken away. It holds for two independent reasons, and the file pins both, because either
  alone would be a silence: the split's subtree declares its own contribution focus groups
  (so the derivation never reaches the stack), **and** the run bound excludes it anyway;
- **the bound itself**, on a `Split`-shaped tree with no contributions in it — the case
  that would bite the day a game screen mounts a bare `AdaptiveStack`;
- **a positive control**: a real x-axis run of three Buttons DOES become one horizontal
  group, so the two silences above are evidence rather than a rule that fires nowhere.

Suites: LuauUI **5925 passed / 0 failed**; Rascal Rally **3320 passed / 0 failed**.

## What this row does NOT claim

- **Everything here is E1.** No device and no human evidence. Whether the shoulders page
  a tab bar comfortably, whether a 4 px underline reads under a finger, and whether a
  leading-aligned scrolling band feels right where a centred cluster used to be are E3/E5
  rows. **The gamepad half is `PENDING_PHYSICAL` by construction** — Studio cannot
  synthesize a true gamepad input class, and a script-fired `ButtonR1` proves the
  downstream action path only.
- **No Studio canary was run.** NM-5.2's E3 half and NM-5.3's 320 px capture are owed.
- **No `accessory` slot, no `.page` style, no `TabSection`.** `p3_sipworks` and
  `p1_glade` cannot migrate onto `api.blueprint` without one of those, and this
  deliverable did not add one. That is why `p4_foyer` was the candidate.
- **The centred top/compact cluster is gone from `p4_foyer`** (§ "four visible changes",
  item 4). It is a measured trade, not an oversight, and it is the one thing a director
  might want reversed — which would mean giving up the scrolling band.
- **No performance claim.** The strip is one more `AdaptiveStack` and the content is one
  `When` per tab; nothing was benchmarked, and D4's caveat about a slide between unequal
  segments re-measuring once per animated frame now applies to every hugging tab strip,
  where the segments really are unequal.
