# P2 "Cartwheel" — UI spec (build contract)

Proof P2: a clean-room LuauUI reinterpretation of the *behavior* of Apple's
Food Truck sample. Binds: `capability-ledger.md` §A + §C (named approximations
are the contract), `responsibility-ledger.md`, `sources/features-food-truck.md`
(behavior reference only). Every construct cited exists in
`docs/reference/api.md` (v0.9.x). No pixels/hex/hardware keys/device names —
tokens, primitives, actions, size classes; numbers only in §2's definitions.

## 1. Fantasy, naming, invariants

**Cartwheel** is a wandering **potion cart** operation; all copy and data
original (clean-room). Name map (reference concept → Cartwheel):

| Reference | Cartwheel |
|---|---|
| Truck dashboard | **The Cart** (dashboard) |
| Orders / donuts per order | **Brews** (`Brew #101`…); bottles per brew (1–5 potions × 1–5 bottles) |
| Order status placed/preparing/ready/completed | **New / Brewing / Ready / Done** (interactive machine: New → Brewing → Done; Ready is seed-only) |
| Donuts (17) / editor / Top 5 | **Potions** (17 originals: Emberdrop, Moonwell, Thistledown, Coppertonic, …) / **Workbench** / **Top Five** |
| Dough / glaze / topping | **Base** (required, 7) / **Essence** (optional, 7) / **Garnish** (optional, 24: 3 Simple + 7 Dust + 7 Ribbon + 7 Swirl) |
| Six flavor axes | Six **attributes**: Spark, Bloom, Frost, Ember, Murk, Zing (signed ints; potion = summed Base+Essence+Garnish) |
| Cities: Cupertino/SF/London | **Plazas**: Gullsgate Quay (quiet, seed 1, ×0.5), Willowmere Market (busiest, seed 2, ×1.0), Emberfall Rows (seed 3, ×0.75) |
| Weather card / WeatherKit | **Skyglow** card — `AmbientService` deterministic "sky-charge" series; night ranges = **lantern hours** |
| Social Feed / Social Feed+ | **Town Chatter** / **Chatter+** (fake subscription, `EntitlementService`) |
| Sales History / annual unlock | **The Ledger** / **Full Ledger** unlock (fake non-consumable) |
| Sign-up / passkey | **Guild Card** sign-up (`IdentityService`; UI-capability exercise, stated on-screen per responsibility ledger) |

**Visual-language invariants** (defend in every screen): (1) **hue =
identity only** — `accent` marks the primary verb; attribute/status meaning is
carried by *form* (icon + chip), never a second hue; (2) **one time form** —
every countdown is a depleting textual `M:SS` + thin bar; (3) **badge =
count, chip = state, icon = what**, never swapped; (4) one focal plane —
exactly one scroll region per screen (`Composition mayScroll`).

## 2. Design-system usage (tokens only; Studio Neutral base)

- **Color roles:** `surface`, `surfaceStrong`, `content`, `contentStrong`,
  `contentSecondary`, `accent`, `onAccent`, `control`, `controlSelected`,
  `hairline`. No new color roles (identity theming is the Creative Director's;
  this spec is legal on Studio Neutral as-is).
- **Type ramp:** `title` (screens), `heading` (cards), `body` (rows/copy),
  `label` (controls/cells), `caption` (chips, axes, footers). **Space:**
  `xs s m l xl`. Radii: `panel` / `control` / `pill`. Shadows: `raised`
  (cards), `overlay` (modals). Motion tokens `fast`/`normal`; motion classes
  `container`, `object`, `reward`, `decay` (registered set only).
- **Proposed theme metrics** (token definitions are the one legal home for
  numbers; added to the proof's token schema, `tokens.compile`-gated):

| Metric | Value | Used by |
|---|---|---|
| `metrics.cartwheel.sidebarMin` | 220 | shell sidebar lane `minWidth` |
| `metrics.cartwheel.detailMin` | 360 | shell detail lane `minWidth` |
| `metrics.cartwheel.cardMin` | 280 | dashboard card lane legality |
| `metrics.cartwheel.tileMin` | 96 | gallery `Grid.minColumnWidth` |
| `metrics.cartwheel.chartH` | 160 | Skyglow/Ledger/TopFive plot height |
| `metrics.cartwheel.previewMin` | 200 | Workbench + Plaza preview boxes |
| `metrics.cartwheel.heroH` | 120 | parallax header band height |

## 3. State ownership, services, command lifecycle

**Semantic state** (fake services, deterministic, injectable clock/seed;
production mapping per responsibility ledger): `OrderService` — seeded backlog
of 24 brews (#101–#109 New, #110–#124 Ready with synthetic done-times),
scripted arrivals (20 New brews at seeded 3–8 s intervals, then stop), status
commands, and **the 60 s brew-countdown fact per brew** (service ownership is
what makes the countdown survive navigation); `StatsService` — per-plaza
seeded daily/monthly series, "today" unions live brews; `AmbientService` —
25-sample sky-charge series + lantern-hour ranges + boundary marks;
`EntitlementService` — Chatter+ sub, Full Ledger unlock; `IdentityService` —
signed-in fact, sign-up command. No wall-clock or `math.random` in domain
logic; scenario reset reproduces byte-identical dumps. **Presentation state**
(client-local, never replicated): selection, focus, scroll, grid⇄table choice,
sort order, search text, upsell collapsed flag, animation progress.

**Every mutation is a command**: `idle → pending → confirmed | rejected`.
No silent states: while `pending`, the initiating control disables and gains a
`caption` chip "Working…"; on `rejected`, the optimistic change visibly reverts
(`fade`, class `container`), a `presentToast` (bottom edge, key = command id so
retries supersede) states the specific reason, and the bus emits `reject`.
Scripted reject fixtures: complete-brew "Brew already collected";
unlock/subscribe "Purchase declined — nothing was charged"; sign-up "That
guild name is taken". Hard fallback: "Something went wrong. Nothing was
changed." **Sound hooks** (game maps bus events; LuauUI plays nothing): `activate`→`sfx.ui.tap`, `select`→`sfx.ui.step`, `commit`→`sfx.cw.brew_start`, `celebrate`→`sfx.cw.cork_pop`, `reject`→`sfx.ui.deny`, `dismiss`→`sfx.ui.close`.

## 4. Shell — adaptive split navigation

One presenter (`keyboardNavigation = true` — a UI-driven place; the arrow-key
camera caveat in api.md is the engineer's to honor). One base surface,
`cancelPolicy = "none"` (Cancel handled in-screen, below), `initialFocus =
"first"` (first sidebar row).

```
Screen "Shell"
└─ Composition arrangements = { "twoLane", "column" }   -- last = fallback
   groups = { {id="nav", lane="lead", sizing="hug", minWidth="metrics.cartwheel.sidebarMin"},
              {id="detail", lane="main", sizing="fill", minWidth="metrics.cartwheel.detailMin"} }
   ├─ Region "Sidebar"  group=nav  rank=2  forms: full list ▸ icon rail
   └─ Region "Detail"   group=detail rank=1 sizing=fill mayScroll  forms: detail host
```

- **Sidebar** (VStack in a ScrollView): rows = `Button` (icon + `label` text,
  `selected` bound to the section signal): The Cart, Brews, Town Chatter, The
  Ledger; `Divider`; `caption` "Potions": Potions, Workbench, Top Five;
  `Divider`; `caption` "Plazas": one row per plaza (secondary icon tint). Row
  states: default / hover (`control`) / focus ring / press / `selected`
  (`controlSelected`). Icon-rail form: icon-only Buttons (`compactLabel`);
  full name via disclosure (focus / hover dwell / long-press).
- **Detail host**: a `When` per section (swap transition `fade`, `canvasGroup`
  plates; reduced motion instant). **Selection resets pushed detail**: changing
  the section signal clears that section's sub-detail signals (open brew, open
  potion) — a sidebar change always lands on the section root. Semantic:
  section + sub-detail ids; presentation: scroll offsets, per mounted identity.
- **Compact arrangement** (`column` wins): the sidebar *is* the root; picking
  a section swaps the lane to that section under a header band `HStack` [Back
  `Button` (chevron, label "Back"), `title` Text]. Depth ≤ 2 (section root →
  item detail). **Cancel** (shell `handleCancel` contribution) pops one level
  (item detail → section root → sidebar → no-op); the Back button is the same
  verb for pointer/touch.
- Focus groups (`navigationGroups`): `sidebar` (vertical, wrap, entry
  "restore", exit right → `detail`), `detail` (vertical, exit left →
  `sidebar`); compact = one group per level. Table/list internals self-wire.

## 5. The Cart (dashboard)

Purpose: at-a-glance operations. Eye order: hero band → newest brew → the
three glance cards. Detail-region form (regular/wide):

```
ScrollView (the one scroller)
├─ ZStack "HeroBand" height="metrics.cartwheel.heroH"      -- parallax header
└─ Composition "CardGrid" arrangements={"twoLane","column"} — 4 card Regions
   (rank: Brews 1, Skyglow 2, Rack 3, Chatter 4), each card = Box
   surface="surface" radius=panel shadow=raised padding=m
```

- **Parallax header** (ledger: layered Images on the motion clock, not a
  canvas equivalent): `ZStack` of a 2-stop `gradient` sky wash + 4 tinted
  `Image` layers (far hills, lanterns, the cart, near foreground), each on an
  `Anchor` with fractional `offsetX` driven by slow clock springs (class
  `decay`, independent long periods); the cart is a 4-frame asset-swap
  flipbook on a `clock:timer` loop. **Reduced motion: all layers still**
  (springs unaimed; flipbook parked on frame 1).
- **Recent Brews card** (hero + tiles; ledger: Composition lanes): header =
  `HStack` [icon, `heading` "New Brews", `Spacer`, chevron `contentSecondary`]
  as ONE `Button` (label "Open Brews") → Brews. Body: `Composition
  {"twoLane","column"}`: Region `Hero` (newest brew, large square) lane lead;
  Region `Tiles` (next 4, `Grid columns=2`) lane main; column form stacks
  them. Tile: `Box` (`surfaceStrong`, radius `control`, hairline `stroke`)
  holding the **diagonal thumb stack** (ledger: Anchor fractional offsets) —
  up to 3 potion `Image`s at `{scale=.30}/{scale=.50}/{scale=.70}` diagonal
  offsets, back-to-front. **Arrival**: keyed `ForEach` (key = brew id),
  `transition = { enter = "slide-left", fade = true }` (mirror exit,
  `canvasGroup` plates); reduced motion places instantly. Footer: `caption`
  "Brew #124 · " + bottle tally. **Numeric pulse** (ledger: no glyph morph
  claimed): on arrival the tally binds `clock:counter` (class `reward`), the
  footer `role` flips to `contentStrong` then back to `secondary`, and a
  presentation scale spring (`reward`) nudges the footer; reduced motion =
  final count placed, role flip only.
- **Skyglow card** (ledger: banded approximation, *not* an area fill): body =
  `ZStack` height `metrics.cartwheel.chartH`: (a) lantern-hour bands —
  `ForEach` of `surfaceStrong` `Box`es on Anchor fractional offsets; (b) the
  sky-charge line — one `UI.Path` (25 normalized points, `role="accent"`,
  thickness = a theme metric); (c) two boundary marker `Image`s (lantern-lit /
  lantern-out) on fractional Anchors; (d) `caption` axis labels (every 3rd
  sample bottom, values left). Read-only on every input class (matches
  reference). Header links to Willowmere's plaza view (fixed-target quirk kept).
- **Potion Rack card** (staggered lattice; ledger: Anchor fractional offsets):
  `Anchor` placing up to 14 potion `Image`s in a 5/4/5 brick pattern (odd rows
  offset half a cell; fractions precomputed, arrange-only). Display-only; the
  header `Button` ("Open Potions") is the sole target (markers sit below the
  target floor by contract).
- **Town Chatter card** (tag cloud; ledger: `Grid` intrinsic — uniform, not
  ragged flow; reads-wrong → escalate bounded gap #3, never a local layout
  engine): `Grid{ minColumnWidth = "intrinsic", itemSizing = "uniform",
  gap = "xs" }` of 16 fixture chips (`Text{surface="chip"}`; potion-icon,
  plaza-icon and plain tags: "Fresh Cork", "No-Sting", "Potion vs Philtre"…).
  Footer `caption` "What the town is saying". Chips read-only.
- **Compact / large-type rule** (ledger §C row 2): the two-lane card grid is
  legal only while each lane clears `metrics.cartwheel.cardMin` *and* each
  card Region's `floor = { lines }` resolves against the live theme — a raised
  typography scale raises floors and flips to one column by itself. **Large
  type counts toward compact; no hand-branch on the text fact.**

## 6. Brews (orders) — list ⇄ table, search, bulk complete

- **Toolbar** (horizontal nav group `brewsToolbar`): search `newTextInput`
  (placeholder "Search brews", `clearButtonMode = "whileEditing"`, live
  `onChange` filter over brew id + potion + ingredient names — the reference's
  id-only search deliberately completed); `Spacer`; table mode adds "Open"
  `Button` (disabled until a selection exists; inspectable — disclosure
  "Select a brew first") and "Collect Selected" `accent` `Button` (completes
  every selected brew via command; celebration opens for the first). Toolbar
  adapts via `ViewThatFits`: full labels ▸ icon + `compactLabel`.
- **Regular/wide: `newTable`** — columns: Brew (custom cell: thumb stack + id,
  sortable by id, `disclose = true`), Bottles (numeric, right-aligned,
  sortable), Status (`newLabel`, sortable), Placed (proof i18n time string,
  sortable), Actions (fixed: `newPopupButton` ellipsis — "Open"; "Collect"
  when not Done). Selection `multi`; `rowHeight` omitted (theme-derived).
  **Default sort decided** (reference quirk resolved): Status ascending (New
  first), ties Placed descending. Column resize per the api.md table contract.
- **Compact: sectioned list** (ledger: composable) — `ScrollView` of `ForEach`
  status groups: `heading` (New / Brewing / Ready / Done; empty groups absent)
  + rows (`Button`: thumb stack, id, trailing bottle `Text{surface="badge"}`).
  Toolbar "Select" enters selection mode: rows gain leading `Toggle`s and a
  bottom band shows "Collect Selected (n)" `accent` Button — **bulk complete
  exists in list mode too** (the reference's table-only gap is a cross-input
  defect). Cancel exits selection mode before popping navigation.
- Row activation opens Brew detail (§7). Focus: `brewsToolbar` (h) → body
  (self-wired; headers = the table's leading group). Initial focus: first
  body row (search never auto-focuses).

## 7. Brew detail + countdown + celebration

- Tree: `ScrollView` → status card (status `newLabel`, "Started" + time
  `caption`), bottles card (`ForEach` rows: potion `Image` + name +
  per-potion bottle `badge`; footer "Total bottles" + badge), action band.
- **Status machine** (one primary `accent` Button): New → "Start Brew"
  (command → Brewing; `commit` feedback; OrderService starts the **60 s
  countdown fact**); Brewing → "Finish Brew"; Done → "Collected", `enabled =
  false` (inspectable: "This brew is finished"). Rejections per §3.
- **Countdown** (invariant 2), visible only while Brewing: `caption` `M:SS`
  bound to a `clock:timer` seeded from the service's remaining-time fact +
  `newProgressView` (thin, depleting). The fact is service-owned, so leaving
  and returning re-seeds mid-flight — **the countdown survives navigation**.
  At zero the chip swaps to "Ready to finish" (`contentStrong`); status never
  auto-advances (reference kept). Timer `kind = "informational"`: reduced
  motion keeps counting in quantized steps — **stays textual, nothing dropped**.
- Any path to Done while this brew is the open detail presents the
  **celebration modal** (`presentModal`, `outsideTapCancel = true`,
  `materialize`): `VStack` [bottle `ZStack` (bottle art, potion `Image` inset,
  cork `Image` via `When` + `transition {enter="slide-down", fade=true}`),
  `title` "Brew #NNN collected!", `caption` "12 bottles · 4:02 PM", "Done"
  `accent` Button]. **Scripted motion** = `clock:timeline`: beat 0.75 cork
  enters (`container`); 1.05 bottle dips (presentation offset spring,
  `object`); 1.2 returns; `onDone` emits `celebrate`. Activate on the bottle
  re-toggles the cork (idempotent toy); Done / Cancel dismisses, mid-timeline
  dismissal calls `interrupt` (terminals run, nothing half-painted). Reduced
  motion: beats fire instantly, same events. Initial focus: "Done".
- Completed brews update StatsService "today" → Top Five and the Ledger
  reflect the change (RA-P2 loop closes; scenario reset restores the seeds).

## 8. Potions gallery — grid ⇄ table, composite sort

- Toolbar: layout `newPicker` (Icons/List), sort `newPopupButton`
  ("Popularity" / "Name" / "Attribute"), and a **conditional secondary**
  (`When`): Popularity → timeframe `newPicker` (Today/Week/Month/Year);
  Attribute → attribute `newPopupButton` (6). The secondary re-parameterizes
  the composite sort (memo over StatsService aggregates — popularity is the
  cross-plaza union, reference kept). Search `newTextInput` filters name +
  ingredients. "New Potion" `Button` opens Workbench on the shared scratch
  potion (no-save scratch kept; copy: "Draft potion — edits apply live").
- Grid form: `Grid{ minColumnWidth = "metrics.cartwheel.tileMin", gap = "m" }`;
  cell = one `Button`: potion `Image`, name `label` (`lineLimit = 2`,
  `disclose = true`), strongest-attribute `caption` row (`contentSecondary`).
  Table form: `newTable` (thumb + name, sortable by name), selection `single`,
  activation opens Workbench. Both forms share one selection signal.

## 9. Workbench (potion editor)

- `Composition {"twoLane","column"}`: Region `Preview` (lane lead, `minWidth =
  "metrics.cartwheel.previewMin"`) + Region `Form` (lane main, fill,
  **mayScroll**); compact puts the preview as the first form row. Live-bound:
  every edit writes the potion signals immediately — **no Save control**;
  header `caption`: "Changes apply as you brew."
- **Live preview** (layered art): `ZStack` of tinted `Image` layers — bottle +
  Base + Essence (`When` ≠ None) + Garnish (`When`), tints from proof-owned
  palette data. A name edit relabels the caption beneath.
- **Form** (`ScrollView` + `VStack`): (1) "Potion" — name `newTextInput`
  (`maxLength` per token schema, validate = trim, commit on Enter/focus-loss).
  (2) "Attributes" — six rows: `HStack` [icon, `label` name, `newProgressView`
  (`min = 0`, **`max` bound to the current strongest attribute value** —
  relative-max gauges, reference behavior), value Text]; the strongest row
  reads `contentStrong` + accent-tinted icon, others `secondary`; read-only
  (attributes change only via ingredients). (3) "Ingredients" — three
  `newPopupButton`s: Base (7, required); Essence (leading **"None"**, then 7);
  Garnish (leading **"None"**, then 24 with the family in the label — "Dust ·
  Rosewisp", "Ribbon · Coppertonic" — the flat-option adaptation of the
  reference's sectioned picker; `presentation = "automatic"` resolves sheet on
  touch/compact). Selection re-derives gauges + preview the same frame.

## 10. Top Five (bar chart, image-under-axis)

- Header: timeframe `newPicker` (Day/Week/Month/Year). Summary row: `caption`
  "Total bottles" + `heading` count (bound; `clock:counter` class `object`).
- Chart (ledger §A bars): `HStack align="end"` height
  `metrics.cartwheel.chartH` of five `VStack align="center"` cells: value
  `Text{surface="badge"}` atop a `Box` column (height ∝ value via fill
  weight; 2-stop `gradient` toward `accent`; radius `control`), then the axis
  label: potion `Image` + name `caption` (`lineLimit = 2`, `disclose = true`
  — two lines reserved so bar heights never jitter). Read-only; cells are not
  focusable.

## 11. Town Chatter (feed + entitlement gate)

- `ScrollView` list. **Not subscribed**: leading marketing card (`gradient`
  wash `Box`, `heading` "Get Chatter+", tagline `body`, "Get Started" `accent`
  Button → subscription modal: tier rows as selectable `Button{selected}`
  cards, yearly wears a computed "Save" `chip`, bottom "Subscribe" `accent`
  Button; purchase = fake command per §3; success flips the entitlement fact).
  **Subscribed** (`When` on the fact): "Highlighted Posts" section (3 bonus
  posts) + toolbar "Chatter+ Options" → settings modal (status summary + two
  `Toggle`s: "Highlight Chatter+ posts" off, "Engagement tools" on — client
  presentation prefs). Title binds "Town Chatter" ⇄ "Chatter+".
- Post row: circular avatar (potion `Image` on a gradient `Box`, hairline
  ring), `body` message, uniform-intrinsic `Grid` tag row of chips (as §5),
  relative-time `caption` (proof i18n table).

## 12. The Ledger (history chart + lock + upsell)

- Timeframe `newPicker`: "2 Weeks" (always), "Month", "Year" — locked options
  wear a lock icon while not entitled (signal before tap); selection is
  client presentation state, session-durable.
- Chart: `ZStack` height `metrics.cartwheel.chartH`: axis gridline `Box`es +
  `caption` labels (last tick suppressed), legend chips per plaza, one
  `UI.Path` per plaza (per-series `role`/`tint`). **Lock adaptation
  (declared; supersedes the ledger's "0-opacity" sketch — `Path` has no
  per-path transparency, api.md engine limit):** on a gated, unentitled
  timeframe the series Paths are **not mounted** (`When`); axes + legend stay;
  a `scrim` `Box` + centered lock `chip` "Premium — Full Ledger" overlays the
  plot. Same information shape, honest mechanism.
- **Upsell, two states** below the chart (only while not entitled): expanded
  card (`heading` "Unlock the Full Ledger", `body` subtitle, `accent` pill
  "Unlock", close "×") ⇄ post-dismiss one-line row ("Unlock the Full Ledger —
  79 credits" + small "Unlock"); collapsed flag = presentation state; both
  Unlocks run the same fake purchase command (§3; reject fixture wired).
  `When` `fade` between states, `canvasGroup` plates.

## 13. Plaza view (PreviewPane hero)

- Reached from sidebar plaza rows or the Skyglow header. `ScrollView`:
  1. **Hero = `PreviewPane`** (the new engine-content leaf, bounded gap #1):
     LuauUI owns the box (fill width, height derived off
     `metrics.cartwheel.previewMin`, radius `panel`), lifecycle, chrome; the
     **proof owns the content** via the handle — an original low-poly plaza
     diorama, slow orbit camera (long period, eased pitch), deterministic
     start angle. **Reduced motion: orbit parked** at a declared framing.
     **Capability-absent fallback plate (declared):** `ZStack` of plaza
     key-art `Image` (`scaleMode = "crop"`) + `gradient` wash + `caption`
     "Live view unavailable on this device." Non-interactive on all inputs
     (as the reference's decorative map is).
  2. **Recommended-pitch card**: pitch name `heading`, "Recommended · Pitch"
     `caption`s, and a `ViewThatFits` summary row: [sky-charge chip +
     "Popular" + "Trending"] ▸ [sky-charge + "Popular"] ▸ [sky-charge].
     Recommendation = first pitch whose AmbientService series shows no "damp
     spell" (deterministic analog of the rain rule).
  3. Flavor-copy card (`surfaceStrong` `Box`): three fixture `body` lines
     (cloud-cover analog %, seasonal potions, stocking tip).

## 14. Guild Card sign-up

- Reached from a sidebar footer row "Guild Card" while the signed-in fact is
  false (true → username row; "Sign out" behind a confirm modal). A form-sized
  `presentModal`, `initialFocus =` the username field's path (**focus
  autoset**); `caption` header: "A UI exercise — Roblox identity is ambient;
  nothing is stored."
- **Guild name** `newTextInput` (validate = lowercase-trim idempotent
  normalizer; `keyboardType = "email"` declared) and **Watchword**:
  **Variant A** (ships iff bounded framework fix #2 lands — masked entry):
  masked field + trailing "Show" `Toggle`; spec'd against the fix's public
  API, never re-implemented locally. **Variant B** (fallback, labeled as
  such): plain visible `newTextInput` with a permanent `caption` beneath:
  "Heads up — your watchword is visible as you type." Gap ships in
  `framework-fixes.md`.
- Toolbar: "Cancel" (dismisses, no command) and "Sign Up" `accent` Button —
  **validation-gated**: disabled unless both fields non-empty; inspectable
  ("Fill in both fields"). Submit = IdentityService command (§3; reject =
  field-level `contentStrong` `caption` error under the guild-name row +
  `reject` event; confirm = dismiss + toast "Welcome to the guild, <name>").

## 15. Verbs × four input classes (every verb, every class)

| Verb | Pointer | Touch | Keyboard | Gamepad |
|---|---|---|---|---|
| Open section/item | click | tap | Navigate + Activate | D-pad + Activate |
| Back (compact pop) | Back button | Back button | Cancel / Back button | Cancel (B) |
| Advance brew status | click button | tap | Activate | Activate |
| Bulk select | table multi-select / list Select mode | list Select mode toggles | table selection model | table selection model |
| Bulk complete | toolbar button | bottom band button | focus + Activate | focus + Activate |
| Search | click field, type | tap, OSK (occlusion keep-visible via `env`) | Activate field, type; Esc-as-cancel reverts | Activate field (engine entry) |
| Sort column | tap header | tap header | header focus, Activate → Up/Down | A on header → Up/Down |
| Resize column | drag header edge | drag header edge | header Activate → Adjust | A → Left/Right |
| Grid⇄table / pickers | click segment | tap / sheet | Navigate + Activate | Navigate + Activate |
| Dismiss modal | outside tap / Done / × | outside tap / Done | Cancel / Done | B / Done |
| Skip celebration | click Done | tap Done | Activate | Activate |
| Disclosure (truncated text) | hover dwell | long-press | focus containing focusable | focus containing focusable |

## 16. Five-view adaptation (environment facts, not devices)

| View (facts) | Shell | Dashboard | Brews | Workbench |
|---|---|---|---|---|
| compact · portrait · touch | column; depth-2 stack | 1-col cards; hero band short | sectioned list + Select mode | preview as first form row |
| compact/regular · landscape · short height · touch | twoLane if `sidebarMin`+`detailMin` fit, else column | 2-lane cards | table if regular, else list | twoLane if legal |
| regular · touch or pointer | twoLane | 2-lane cards | table, theme touch rows | twoLane |
| wide · pointer+keyboard | twoLane (sidebar full list) | 2-lane, `maxMeasure` centers | table, dense pointer rows | twoLane |
| `displaySize = Large` (ten-foot; sizeClass capped regular, overscan, gamepad) | twoLane; focus ring is the anchor | 2-lane; charts read-only, unfocusable | table; grouped focus | twoLane |

One tree: `Composition` legality + scoped `adaptive.conditions` +
theme-derived floors — no per-view layout exists.

## 17. Focus, initial focus, Cancel — per screen

| Screen | Groups (axis) | Initial focus | Cancel |
|---|---|---|---|
| Shell | `sidebar` (v, wrap, exit→detail), `detail` (v) | first sidebar row | pop compact level; root no-op (`cancelPolicy="none"`) |
| Brews | `brewsToolbar` (h) → table/list (self-wired; headers = table's h group) | first body row | exit Select mode, else pop |
| Brew detail | single vertical ring | primary status button | pop to Brews |
| Celebration modal | trap | "Done" | dismiss |
| Gallery / Top Five / Ledger / Chatter | toolbar (h) → body (v) | first body item | pop |
| Workbench | form ring (preview not focusable) | name field row | pop (edits already live — no discard prompt, stated) |
| Sign-up modal | trap; form ring | username field (`initialFocus` id) | dismiss = Cancel button semantics (no command) |

Tab traversal follows document order (`traversalWrap` default); hidden
`ViewThatFits`/Composition losers are excluded from every ring by contract.

## 18. Motion tokens + reduced-motion variants (named per animation)

| Animation | Mechanism / class | Reduced motion |
|---|---|---|
| Parallax header drift + flipbook | `decay` springs on Anchor offsets; timer flipbook | **stills** (frame 1, springs unaimed) |
| Brew arrival slide-in | ForEach `slide-left`+fade, class `container` | instant place, same events |
| Numeric pulse | `counter` class `reward` + role flip + presentation scale | final count placed; role flip only |
| Section swap | `When` fade (canvasGroup) | instant |
| Celebration | `timeline` beats (cork `container`, dip `object`) | beats fire instantly, `onDone("reduced")` |
| Countdown | `timer` informational + progress bar | keeps counting, quantized — stays textual |
| Toasts / modals | presenter defaults | placed instantly, same order/durations |

## 19. Preferred text, localization, disclose ledger

- **Preferred text**: all floors/row heights theme-derived (no pinned
  `rowHeight` anywhere); a raised preference makes rows taller and flips
  Compositions toward column — **large type counts toward compact** (§5).
  Nothing truncates undisclosed; headings wrap to 2 lines then disclose.
- **Localization worst case** (proof pseudo-locale, ~1.4× German-class),
  longest strings fitting by design: "Collect Selected (12)" (ViewThatFits →
  icon+`compactLabel`), "Willowmere Market" in the icon rail (disclosure),
  the Variant-B watchword caption (wraps, 2 lines reserved). BiDi/RTL:
  recorded gap, out of scope (ledger §A).
- **`disclose = true` on**: brew-id table cells (column `disclose`), potion
  names (gallery cells, Top Five axis), sidebar rail names, plaza/pitch names.
  Toast bodies are uncapped (wrap). `reveal` is not used in P2.

## 20. Out of scope (host OS — ledger rows, never simulated)

Per `responsibility-ledger.md` §"Apple host-OS behavior": Live Activities /
Dynamic Island, widgets, local notifications, Siri/App Intents tip, App Store
review prompt, StoreKit system sheets (manage/refund/offer-code/restore
chrome), passkeys, MenuBarExtra, deep-link URL open (production analog: join
`launchData`). None are simulated; the audit claims no parity for them.
