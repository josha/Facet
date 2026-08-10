# P3 "Sipworks" — build-ready UI spec (proof RA-P3)

Clean-room LuauUI reinterpretation of the in-app behavior of Apple's Fruta
sample (`sources/features-fruta.md` = behavioral reference only). Original
fantasy: **a craft tea-house** — browse house *blends*, inspect *botanicals*,
order a pour, earn *Steam Stamps*, unlock the *Blend Book* of recipes. No
smoothies, no fruit, no Apple copy or assets anywhere.

Binding documents: `capability-ledger.md` §A + §D (the named approximations are
contractual — do NOT build beyond them), `responsibility-ledger.md` (fake
services + forbidden list), `docs/reference/api.md` (every construct cited
exists there). Vocabulary: LuauUI primitives, token roles, semantic actions,
size classes — no pixels/hex/hardware keys/device names in screen specs; numbers
live only in the token table (§4) and service fixtures (§3), the sanctioned
definition sites.

## 1. Visual-language invariants (defend in every section)

- **Accent means "act here."** `accent` paints exactly one primary verb per view
  (order/redeem CTA, unlock buy, stamped seal). Never a second accent verb.
- **Hue carries no state.** State is form: selected = `selected` binding (style
  tag), pending = label swap + disabled, rejected = visible return + toast.
- **Every blocked verb explains itself at the point of action** (guard alert,
  rejection toast with reason, empty states with a next step). No silent states.
- **One focal plane.** Detail, botanical card, rewards, order-placed each own
  the moment (surface + scrim); lists never compete with an open card.
- **The named approximations are the ceiling**: hero-card =
  `presentModal`/`When` + `materialize` + `canvasGroup` fade (NOT a
  shared-element morph); card flip = width-collapse flip via `motion`;
  materials/blur = translucent surfaces + scrim; swipe-favorite = visible
  affordance on every input class; rich-text emphasis = split `Text` runs.

## 2. Fantasy, copy, and content (proof-owned, original)

15 blends; 3 with free recipes (*Amber Harvest*, *Mistral Mint*, *Copper Chai*),
12 recipe-gated behind the Blend Book (menu/ordering is NEVER gated): First
Frost, Moonpetal, Emberleaf, Quiet Meadow, Tidepool, Lantern Oolong, Velvet
Smoke, Summit Sencha, Bramble Hearth, Golden Hour, Nightporch, Cinder Chai.
18 botanicals (assam, sencha, oolong, rooibos, chamomile, peppermint, spearmint,
ginger, cardamom, cinnamon, clove, hibiscus, lemongrass, jasmine, lavender,
rosehip, licorice root, honeybush) plus **spring water** — excluded from every
menu/tile surface (filler; still in recipe measures). Blend = title,
description (1–3 paragraphs, per-paragraph emphasis flag), measured botanicals
`{ botanicalId, value, unit ∈ tsp|g|ml }`, derived caffeine mg. Botanical =
name, tile/card art ids, brew-facts rows (leaf mass g, caffeine mg, steep min,
warmth 1–5). Economy fixtures (Game-Designer-owned): 1 stamp per confirmed
order; redeem threshold 10; redeem costs a flat 10.

## 3. Services and state boundaries

Fake services per responsibility ledger (pure Luau, injected clock/seed,
command lifecycle `idle → pending → confirmed | rejected`, scripted rejection
fixtures, scenario-resettable): **CatalogService** (blends/botanicals/facts);
**FavoritesService** (`Set<blendId>`, toggle command); **RewardsService**
(`stampsEarned`, `stampsSpent`, `unstamped` set, `clearUnstamped()`);
**RecipeUnlockService** — non-consumable-shaped product `blend-book`
`{ name="The Blend Book", description="Every house recipe, yours to brew.",
price="149 Credits", availability pending → available at t+1.0 s }`, purchase
command, rejection fixture `declined`; **OrderService** —
`placeOrder(blendId, mode ∈ paid|redeem)`, price fixture `"49 Credits"`,
ready flip at **t+4.0 s** on the injected clock, rejection fixture
`counterClosed`, guard fixture `payments = { enabled=false,
reasonKey="guard.paymentsDisabled" }`; **I18nService** (§13). Production
mapping is the ledger's; no MarketplaceService/DataStore/network calls.

**Semantic state (shared model, server-shaped):** `currentSection ∈
menu|favorites|stamps|recipes`, `selectedBlendId?`, `searchString`, favorites
set, stamps, unlock entitlement, in-flight order + status, locale,
`entry ∈ "full" | "compact-link"`, `entryItemId?`. **Presentation state
(client-local, never replicated, dies with the surface):** focus, hover, scroll
offsets, flip progress, stamp-pop timeline, open-botanical id, recipe
"gathered" checks (session-local by design, reset when the recipe surface
dismisses — mirrors the reference), batch count (per recipe surface).

## 4. Token additions (proof theme package; the ONE place values live)

Studio Neutral base; standard vocabulary only (color roles `surface…hairline` +
`danger`; type `caption|label|body|heading|title|strong|numeral`; space
`xs…xl`; radii `control|panel|pill`; shadows `raised|overlay`; motion classes
`container|object|reward|decay`). Proof metrics (dotted-path names, legal in
any dim/offset):

| Metric | px | Used by |
|---|---|---|
| `metrics.sip.rowArt` | 60 | list-row thumbnail (square, `radii.control`, `hairline` stroke) |
| `metrics.sip.tileArt` | 96 | botanical tile art |
| `metrics.sip.cardW` / `cardH` | 360 / 460 | botanical card + facts face |
| `metrics.sip.headerArtW` / `headerArtH` | 220 / 250 | wide-header image |
| `metrics.sip.listPaneMin` / `listPaneMax` | 320 / 420 | regular/wide list pane |
| `metrics.sip.seal` / `sealCompact` | 44 / 32 | stamp-seal cell (full / compact) |
| `metrics.sip.orderCard` | 300 | order-placed flip disc (1:1) |
| `metrics.sip.ctaBand` | 64 | bottom action band height |

New tokens beyond metrics: none (no identity escalation needed).

## 5. Shell — compact tabs ⇄ regular sidebar, live flip, state survival

`UI.Composition{ id="Shell", arrangements={ {name="sidebar", lanes={{"lead"},{"main"}}},
"column" }, laneGap="m", groupGap="s", groups={ {id="content", lane="main",
sizing="fill"}, {id="nav", lane="lead", sizing="hug"} } }`. Declaration order
content-then-nav, so the `column` fallback stacks content above a **bottom tab
row** (touch thumb zone); the custom `sidebar` arrangement resolves at
`regular`/`wide` and leads with the nav rail.

- **Region `Nav`** — two ranked forms, richest first:
  1. *Sidebar*: `VStack{ gap="s", padding="m" }` of `Button{ selected }` rows
     (icon+title via `newLabel` children): Menu (`sip:menu`), Favorites
     (`sip:favorite`), Blend Book (`sip:book`); then `Spacer{fill}` and the
     **Stamps pocket** — `Button{ id="Pocket", label="Steam Stamps",
     corners=pill, surface="control" }` at the sidebar foot; Activate presents
     the Rewards modal (§9).
  2. *Tab row*: `HStack` of four equal-`fill` icon+label Buttons — Menu,
     Favorites, Stamps, Blend Book — `compactLabel={icon=…}` so a narrow band
     degrades to icons, never ellipses. Height `metrics.sip.ctaBand`;
     `hairline` top `Divider`.
- **Region `Content`** hosts the section bodies behind
  `UI.When(currentSection == …)`, `transition={ enter="fade" }` on a
  `ZStack{ canvasGroup=true }` child.
- **State survival contract:** the tabs⇄sidebar flip is a Composition re-solve
  — zero unmounts; the ACTIVE section keeps scroll offset, focus, and in-flight
  search text (RA-P3 asserts this). Section *switches* remount through `When`;
  semantics (search, selection, favorites) live on the shared model and
  restore; scroll offset is presentation and legitimately resets.
- **Detail placement rule:** `compact` → detail is its own presented base
  surface (`present`, `transition={enter="slide-left"}`); Cancel/Back dismisses
  to the shell. `regular`/`wide` → section content is `HStack{ gap="m" }`: list
  pane (`width={type="minMax", min="metrics.sip.listPaneMin",
  preferred="metrics.sip.listPaneMin", max="metrics.sip.listPaneMax"}`),
  `Divider`, detail pane (`fill`) showing the selection or centered
  `Text{ role="secondary", text=t("detail.empty") }` ("Pick a blend to see it
  here."). Widening with a compact detail up: dismiss it (`exit="instant"`) —
  `selectedBlendId` survives and the pane renders it. Narrowing never
  auto-presents; the row's `selected` state shows where you were.

## 6. Lists — Menu / Favorites / Recipes share ONE row blueprint

`BlendRow(blend)` (shared factory, identical in all three sections and the
compact entry shell): `Button{ id="Row-"..id, label=title }` content =
`HStack{ gap="m", padding="s" }`: `Image{ width/height="metrics.sip.rowArt",
scaleMode="crop" }` · `VStack{ gap="xs", fill }`: title `Text{
textSize="strong", lineLimit=1, disclose=true }`; botanicals line `Text{
role="secondary", textSize="caption", lineLimit=2, disclose=true }` (I18n
list-formatted "Assam, ginger, and clove"); caffeine line (same treatment,
lineLimit=1, "34 mg caffeine" via I18n measure format) · trailing **favorite**
`Button{ shape="circle", icon="sip:favorite", selected=isFavorite,
label=t("row.favorite") }` — this visible control IS the swipe-favorite
adaptation (ledger §A); no swipe gesture is built. Row Activate sets
`selectedBlendId` (compact: presents Detail). List = `ScrollView{ axis="y" }` +
`ForEach{ key=blendId, transition={ enter="materialize" } }` over a memo:
section set → `matches(searchString)` (title OR any non-water botanical name,
case-insensitive) → locale-aware title sort (I18nService collation).

**Search (shared across sections).** Above every list: `newTextInput{
id="Search", value=searchStringSignal, placeholder=t("search.placeholder"),
clearButtonMode="whileEditing" }`. Suggestions: `UI.When(editing and #sugg>0)`
→ `VStack` of up to 6 `Button{ label=botanicalName }` rows from a memo (name
contains query, excluding exact match); Activate sets `searchString` to the
name. The signal is model-owned, so section switches keep query + suggestions.

**Favorites empty state.** `When(#favorites==0)` full-pane overlay
(`ZStack{ canvasGroup=true }`, `transition={enter="fade"}`): centered
`Text{ role="secondary" }` t("favorites.empty") ("Mark a few blends to keep
them here.") + Button t("favorites.browse") ("Browse the menu") →
`currentSection = menu`.

**Recipes list**: same `BlendRow`, but the source set is *only* unlocked
recipes — **locked rows are absent, not disabled** (§10); rows push RecipeView
instead of Detail.

## 7. Blend detail — adaptive header, botanical tiles, facts flip, CTA band

Root `Screen{ padding=0 }` → `VStack`: `ScrollView` content over the bottom CTA
band (§8; the band never scrolls). Top bar `HStack{ padding="m" }`:
compact-only Back `Button{ shape="circle", icon="sip:back",
label=t("nav.back") }` · `Spacer{fill}` · favorite circle Button (row's twin,
same signal).

**Adaptive header** — `UI.ViewThatFits{ id="Header" }`, candidates in order:
1. *Wide card* (regular/wide): `Box{ surface="raised", corners=UI.corners
   ("panel"), stroke=hairline, height={type="fixed",
   px="metrics.sip.headerArtH"} }` → `HStack`: `VStack{ padding="l", fill }`
   (title `Text{ textSize="title" }`, description runs, caffeine line pinned
   via `Spacer{fill}`) + `Image{ width="metrics.sip.headerArtW",
   scaleMode="crop" }`.
2. *Full-bleed* (compact fallback): `VStack`: `Image{ width=fill,
   height={type="aspect", ratio=1.2}, scaleMode="crop" }` above
   `VStack{ padding="m", gap="s" }` with the same texts.
Both candidates stay mounted; resize re-chooses without losing scroll.

**Description emphasis (declared approximation).** Ordered paragraph runs,
each a `Text{ textSize = run.emphasis and "strong" or "body" }`. Emphasis
granularity is the paragraph, not the word — the split-`Text`-runs adaptation
(ledger §D); no rich-text engine is built.

**Botanical grid.** Header t("ingredients.menu") (`textSize="heading"`;
dedicated key — §13) over `UI.Grid{ minColumnWidth="intrinsic",
itemSizing="uniform", gap="m" }` of tiles: `Button{ label=name }` content =
`VStack{ gap="xs", align="center" }`: `Image{
width/height="metrics.sip.tileArt", scaleMode="crop", corners=control }` +
`Text{ textSize="label", lineLimit=1, disclose=true }`.

**Botanical card (the declared hero-card approximation).** Tile Activate →
`presentModal(card, { transition={ enter="materialize" }, scrim="scrim",
outsideTapCancel=true, initialFocus={id="CardClose"} })`. The card does NOT
fly from the tile — it materializes centered over the scrim (ledger §D). Card
root: `Box{ canvasGroup=true, width="metrics.sip.cardW",
height="metrics.sip.cardH", surface="raised", corners=panel,
shadow=UI.shadow("overlay") }` hosting the **FlipPlate recipe** (§12):
- *Front face*: card art `Image{ scaleMode="crop", fill }` + name
  `Text{ textSize="title" }` + two circle Buttons: `CardClose`
  (icon `close`, label t("card.close")) and `CardFacts` (icon `sip:facts`,
  label t("card.factsOpen") "Brew facts").
- *Back face (facts, measured rows)*: translucent plate `Box{
  surface="surfaceStrong", tint transparency 0.1 }` (materials adaptation) →
  `VStack{ padding="m", gap="s" }`: header t("facts.title"), then per fact row
  an `HStack`: label `Text{ textSize="body", fill }` + value
  `Text{ textSize="numeral", textAlign="end" }`, I18n-formatted and **scaled to
  this blend's measured quantity** (leaf mass, caffeine, steep, warmth);
  `Divider` between rows; `CardFactsClose` circle Button flips back. Faces swap
  interactivity at flip midpoint; the hidden face's `When` branch is unmounted,
  so it is never focusable. Cancel or outside tap dismisses the card.

## 8. Order flow — pay CTA / redeem CTA / guard / lifecycle

Bottom band (height `metrics.sip.ctaBand`, top `Divider`, `surfaceStrong` with
tint transparency 0.1 — the "bar material" adaptation):
- `When(canRedeem)` (`unspentStamps >= 10`) → **Redeem CTA**: `Button{
  id="OrderCTA", surface="accent", corners=pill, label=t("order.redeem") }`
  ("Redeem a free pour!"); else → **Pay-shaped CTA**: same id/geometry,
  `label=t("order.place", price)` ("Place order — 49 Credits"). Pay-shaped
  only: production = `PromptProductPurchase` (host sheet); no payment chrome
  imitated. Swap rides `When{ transition={enter="fade"} }` on
  `Box{ canvasGroup=true }`.

**Guard fixture (visible reason).** While `payments.enabled == false`: a
notice chip above the band — `Text{ surface="chip", role="secondary",
text=t("guard.paused") }` ("Ordering is paused — the counter can't take this
order.") — and the CTA stays visible and inspectable; Activate presents the
guard alert `presentModal(alert, { outsideTapCancel=false, scrim="scrim",
initialFocus={id="GuardOK"} })`: title t("guard.title") ("Ordering paused"),
body t("guard.paymentsDisabled") ("This kiosk code was scanned too far from
the shop, so ordering is off for your protection."), hard fallback
t("guard.fallback") ("Ordering is unavailable right now."), one
`Button{ id="GuardOK", label=t("common.ok") }`. Cancel = GuardOK; the order
never starts.

**Lifecycle (`placeOrder`).** idle → **pending**: CTA `enabled=false`, label
t("order.pending") ("Placing…"), focus stays on it → **confirmed**: feedback
`commit`; present Order-Placed; next Rewards visit animates the new stamp (§9)
→ **rejected** (fixture `counterClosed`): CTA visibly returns to idle,
feedback `reject`, `presentToast(t("order.rejected"), { key="order",
duration=4, position="bottom" })` ("Couldn't place your order — the counter is
closed.").

**Order-Placed screen.** `presentModal({ transition={enter="materialize"},
outsideTapCancel=true, initialFocus={id="Done"} })`. Root `ZStack{ fill }`:
ordered blend's art `Image{ scaleMode="crop", fill }` under a veil
`Box{ tint={role="surface", blend=1, transparency=0.35}, fill }`; centered
**flip disc** — FlipPlate (§12) on `Box{ canvasGroup=true,
width/height="metrics.sip.orderCard", corners=pill, surface="raised" }`: front
t("placed.thanks") ("Thanks for your order!") + t("placed.notify") ("This card
flips when your pour is ready."); back t("placed.ready") ("Your pour is
ready!") + t("placed.pickup", title) ("{title} is waiting at the counter.").
OrderService flips `isReady` at t+4.0 s → FlipPlate plays, feedback
`celebrate`. Top-trailing `Button{ id="Done", corners=pill }` dismisses. No
sign-up banner: host identity is ambient (ledger §D; §16).

## 9. Rewards — Steam Stamps card

Modal from the Pocket (sidebar) or the Stamps tab section (compact). One
blueprint `RewardsCard{ compact }`: `Box{ surface="raised", corners=panel,
padding/gap = compact and "s"/"xs" or "m"/"s" }` → `VStack`: header
t("rewards.title") ("Steam Stamps", `textSize="heading"`) ·
`Grid{ columns=5, gap = compact and "xs" or "s" }` of **10 seal cells**
(`width/height = "metrics.sip.seal"` / `sealCompact`), each `ZStack`:
unstamped ring `Box{ corners=pill, stroke=hairline }`; stamped seal
`Image{ tint={role="accent", blend=1} }` (`sip:seal` art); newly-earned seals
sit in `Box{ canvasGroup=true }` driven by the stamp-pop timeline (§12) ·
caption `When(not compact)` → `Text{ role="secondary", textSize="caption" }` =
plural fixture `rewards.away` (§13). Card sits over the ambient steam backdrop
(§12); non-interactive except Done. **Clear-on-leave:** dismissing the surface
(or leaving the Stamps section) issues `RewardsService.clearUnstamped()` — the
pop plays once per visit; returning shows those seals static. Compact variant
= same blueprint, `compact=true`: full-width in the tab, caption hidden, tight
gaps, small seals.

## 10. Blend Book — purchase-shaped unlock + recipe view

**Unlock card** (`When(not unlocked)` above the recipe list; `transition=
{ enter="materialize" }` mirror exit, on `Box{ canvasGroup=true }`):
`Box{ surface="raised", corners=panel }` → background art Image + translucent
`surfaceStrong` bottom bar: product name (`textSize="heading"`) + description
`Text{ role="secondary", lineLimit=2, disclose=true }` + price area — while
`availability=pending`: t("unlock.loading") ("Loading…"), **no buy button
mounted**; when available: `Button{ id="UnlockBuy", surface="accent",
corners=pill, label=t("unlock.buy", price) }` ("Unlock — 149 Credits", live
from the fake product fact). Purchase lifecycle: pending (t("unlock.pending"),
disabled) → confirmed: entitlement flips, card exits, **locked rows enter**
the `ForEach` with `enter="materialize"` (the animated reveal), feedback
`celebrate` → rejected (`declined`): card returns to idle + toast
t("unlock.rejected") + feedback `reject`.

**RecipeView** (per unlocked blend): `ScrollView` → hero `Image{ corners=panel,
width=fill, height={type="aspect", ratio=1.5} }` with an `Anchor`-pinned
**batch stepper** over its lower edge: `newStepper{ id="Batch",
value=batchSignal, min=1, max=9, step=1, format = plural "recipe.batches" }`
("1 pot" / "{n} pots"). Header t("ingredients.recipe") (distinct key — §13) →
one row per measured botanical (water included): `HStack{ gap="m",
padding="s" }`: thumbnail (`metrics.sip.rowArt`) · `VStack{fill}`: name
(`textSize="strong"`) + quantity `Text{ role="secondary" }` = I18n measure
format **× batch** (derived memo re-formats live on Adjust, no remount) ·
trailing `Toggle{ id="Got-"..id, label=t("recipe.gathered", name),
value=gatheredSignal }` — the gathered checklist, session-local, resets on
dismiss (§3). Favorite circle Button in the top bar, same shared signal.

## 11. Compact entry flow (second scenario, "compact-link")

Scenario `sipworks-compact`: facts `entry="compact-link"`,
`entryItemId="lantern-oolong"` (production analog = join `launchData`,
validated server-side — responsibility ledger). **Shared, byte-for-byte:**
`BlendRow`, menu list + search + suggestions, Blend Detail (§7) incl. card and
flip, the order flow (§8) incl. guard + Order-Placed, and Catalog/Order/I18n
services. **The compact shell hides:** the Composition shell (root = plain
`Screen` hosting only the Menu list); Favorites/Stamps/Blend Book and every
route to them; the favorite affordances (row + detail hearts sit behind one
shared `When(entry=="full")` — no dead verbs); the redeem branch (no rewards
context: CTA always pay-shaped); the stamp ceremony (stamps still accrue
silently in RewardsService). **Deep link:** on present set `selectedBlendId =
entryItemId`, `controller.scrollToVisible(rowPath)`, then open Detail through
the same path a row Activate takes. Menu→Detail→Order only; Cancel at the menu
root is a no-op (`cancelPolicy="none"` — nothing behind it).

## 12. Motion (classes are the vocabulary; durations only where timelines own them)

| Move | Mechanism | Full motion | Reduced motion |
|---|---|---|---|
| Section/branch swap, CTA swap, empty state | `When` `transition enter="fade"` on `canvasGroup` | fade | instant place (framework parity) |
| List insert/reveal, card/modal enter | `materialize` (+ mirror exit) | scale-in + fade | instant |
| Compact detail push | surface `transition enter="slide-left"` | slide | instant |
| **FlipPlate** (botanical facts; order-placed disc) | one `clock:spring(0→1, "object")`; presentation-transform scaleX: front `max(0,1−2t)`, back `max(0,2t−1)`; interactivity swaps via `When` at t=0.5 | width-collapse flip (declared approximation; no perspective) | `reducedMotion="fade"`: instant swap + crossfade at destination |
| **Stamp pop** | `clock:timeline` beats at `0.15·k` s per newly-earned seal (k = 1..n, slot order); each beat: seal `reward` spring scale 1.6→1 + fade-in via its `canvasGroup`; feedback `celebrate` on `onDone("complete")` | staggered pops | **pops become fades**: beats fire instantly in order, scale omitted, fade only; same events |
| **Ambient steam** (rewards backdrop) | 8 `Box{ corners=pill }` wisps in an `Anchor` at seeded fractional offsets; per-wisp `decay` spring on offsetY + opacity, re-targeted `onSettle` (ping-pong); seeds from the scenario seed, never `math.random` | slow drift + shimmer | **stills**: wisps placed at seeded rest positions; no travel, no shimmer |
| Order-ready flip | OrderService fact flip at t+4.0 s drives FlipPlate | as FlipPlate | as FlipPlate |
| Toasts | `presentToast` defaults (edge slide + fade) | — | instant (framework) |

All motion runs on the presenter's clock; no consumer `RunService` connections
(forbidden list). Sound/haptic hooks = the feedback bus: `activate`, `select`
(row/tab), `adjust` (stepper), `commit` (order/unlock confirmed), `reject`,
`cancel`, `dismiss`, `celebrate` (stamp pop, ready flip, unlock reveal).

## 13. Localization (I18nService; proof-owned tables)

Locales: `en` and pseudo-expansion `qps-ploc` (every string ≈1.4× longer,
bracketed, deterministic). The RA-P3 locale step flips the `locale` fact live;
every surface reflows with **no clipping** — guaranteed by the `lineLimit` +
`disclose` + wrap declarations; the text audit is the check. Two "ingredients"
keys on purpose (`ingredients.menu` = "In the pot" / `ingredients.recipe` =
"What you'll need") — the semantic-context split. List ("A, B, and C") and
measure ("1.5 tsp") formatting are I18nService calls, never concatenation.
**Plural fixtures** (zero/one/other), all exercised by the gate:

| Key | zero | one | other |
|---|---|---|---|
| `recipe.batches` | "No pots" | "1 pot" | "{n} pots" |
| `rewards.away` | "Your next pour is on the house!" | "You are 1 stamp from a free pour!" | "You are {n} stamps from a free pour!" |
| `rewards.progress` | — | "1 of 10 stamps" | "{n} of 10 stamps" |

**Disclose declarations (complete list):** row title, row botanicals line,
tile label, unlock-card description, and every `Toggle` label (built-in). All
other player-facing text wraps (uncapped) or is a single short token
(prices, counts) sized by its type role. BiDi/RTL: recorded LuauUI gap, out of
scope (ledger §A).

## 14. Focus, navigation, Cancel — per surface

`keyboardNavigation = true` at the presenter (UI-driven place; heed api.md's
default-camera Left/Right caveat). `traversalWrap` default everywhere.

| Surface | Navigation groups (axis) | Initial focus | Cancel |
|---|---|---|---|
| Shell | `nav` (sidebar: vertical; tab row: horizontal) ⇄ `content` (vertical: search → suggestions → rows incl. row hearts) | `"first"` (current section's nav item) | no-op at root (`cancelPolicy="none"` — nothing behind it) |
| Detail (compact surface / pane) | `topbar` (horizontal: Back, Favorite) → `content` (vertical: header → tiles grid (Grid-derived 2-axis) → CTA) | `"first"` (Back on the surface; first tile in the pane) | dismiss surface (pane: return focus to list) |
| Botanical card (modal) | flat ring per face | `{id="CardClose"}` | dismiss card; facts face open: `handleCancel` flips to front first, second Cancel dismisses |
| Guard alert (modal) | single control | `{id="GuardOK"}` | dismiss (same outcome as OK); `outsideTapCancel=false` |
| Order-Placed (modal) | flat: Done | `{id="Done"}` | dismiss |
| Rewards (modal / tab) | flat: Done (modal) / section inherits shell | `{id="Done"}` / shell rules | dismiss modal / shell rule |
| RecipeView | `topbar` → `content` (vertical: stepper → gathered toggles) | `"first"` | dismiss / return to list |
| Compact entry root | `content` only | `"first"` | no-op (`cancelPolicy="none"`) |

**Every verb on all four input classes** (Activate/Cancel/Navigate/Adjust are
the only bindings; no hardware keys in this spec):

| Verb | Pointer | Touch | Keyboard | Gamepad |
|---|---|---|---|---|
| Switch section | click nav item | tap tab | Navigate + Activate (Tab reaches nav band) | Navigate + Activate |
| Open blend / botanical / recipe | click row/tile | tap | Activate on focus | Activate |
| Favorite / unfavorite | click heart | tap heart | Activate on heart | Activate on heart |
| Search / clear | click field, type; × while editing | tap, OSK; × | Activate to edit; typing sinks nav; clear via × in ring | Activate; engine text entry; × |
| Accept suggestion | click | tap | Navigate + Activate | Navigate + Activate |
| Flip facts / back | click flip buttons | tap | Activate | Activate (Cancel = front-first, §table) |
| Order / redeem / unlock | click CTA | tap CTA | Activate | Activate |
| Batch count | click −/+ | tap −/+ | focus-gated Adjust (horizontal axis) | focus-gated Adjust (bumpers/d-pad per contract) |
| Gathered check | click toggle | tap | Activate flips | Activate flips |
| Dismiss / back | Close affordance or outside tap | same | Cancel-equivalent close affordance + Cancel | Cancel |
| Full-value disclosure | hover dwell | long-press | focus | focus |

No verb exists on only one class; nothing essential lives behind hover.

## 15. Five-view adaptation (one spec, size-class branches)

| View | sizeClass / facts | Shell | Detail | Rewards | Notes |
|---|---|---|---|---|---|
| Phone portrait | compact | bottom tab row | pushed surface, full-bleed header, CTA band bottom-third | Stamps tab, `compact` card | one column; suggestions overlay the list |
| Phone landscape | compact (short height) | bottom tab row | pushed surface; `ViewThatFits` may pick the wide-card header if it fits | Stamps tab, `compact` | header candidate order handles this — no special branch |
| Tablet | regular | sidebar + list pane + detail pane | in-pane, wide-card header | Pocket → modal, full card | placeholder pane when nothing selected |
| Desktop | wide | sidebar + panes | in-pane, wide card | Pocket → modal | hover previews = disclosure plates only; density from theme |
| Console / ten-foot | regular-capped, `distanceProfile="ten-foot"` | sidebar + panes | in-pane | Pocket → modal, full card | paint scale 1.5 automatic; content inside `effectiveOverscanInsets`; focus ring is the anchor; one accent verb per view (already invariant 1) |

Branches key only on `sizeClass` / `adaptive.conditions` / `ViewThatFits` /
Composition — never a device or platform name.

## 16. Out of scope — host-OS surfaces (never faked)

Per `responsibility-ledger.md` §"Apple host-OS behavior": widgets; App Clip
install overlay + location verification (nearest analog: join `launchData` =
our `compact-link` fact); Sign in with Apple (host identity is ambient); Apple
Pay chrome (CTA pay-shaped only; production = `PromptProductPurchase`);
StoreKit sheets/refund/revocation. Recorded in the capability ledger; the
audit claims no parity for any of them.

## 17. RA-P3 representative loop (the scenario the gate drives)

1. Launch full scenario → shell. 2. Resize across the compact/regular boundary
→ shell flips live; active section keeps scroll + focus + search text.
3. Search "gin" → suggestions; accept "ginger"; switch sections → query
persists. 4. Unfavorite all → Favorites empty state → Browse. 5. Open *Lantern
Oolong* → header adapts per view; open a tile → card materializes; flip to
Brew Facts (measured rows); Cancel twice. 6. Guard fixture on → chip visible;
Activate CTA → guard alert with reason; off. 7. Order → pending → rejected
fixture → CTA reverts + toast. 8. Order → confirmed → Order-Placed; disc flips
at t+4.0 s. 9. Stamps → new seal pops staggered; leave; return → static;
caption plurals correct at 9, 1-away, threshold (zero form). 10. At 10 stamps
→ CTA is Redeem; redeem → same path; debit 10. 11. Blend Book: locked rows
absent; price loads live; buy rejected → toast + revert; confirmed → card
exits, 12 rows materialize in. 12. Recipe → batch 1→4 → quantities re-format
×4; check two toggles; leave/return → checks reset (declared session-local).
13. Locale → `qps-ploc` → full sweep, no clipping, disclosure reachable.
14. Reduced motion → stills + fades, same events. 15. Reset → byte-identical
dump (seeded; ledger §G). Compact scenario: §11 flow, menu→detail→order only.
Engineer deviations return as spec amendments; never silent divergence.
