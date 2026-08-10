# P5 "Wardrobe" — UI build spec (proof RA-P5)

**What this is.** A clean-room, in-experience reinterpretation of an avatar-editor
surface: a catalog you browse, a mannequin you dress live, a purchase-shaped flow
with visible rejection. Behavioral reference: `../sources.md` §"Marketplace /
avatar editor" — behavior only; original names, copy, data, iconography, currency
(no platform branding, no real item/creator names, no Robux mark). Binding:
`../capability-ledger.md` §A/§F, `../responsibility-ledger.md`,
`docs/reference/api.md` — every construct cited exists there except
**PreviewPane**, the engine-content leaf landing this stage (§6.2), the one
declared bounded gap. **Engine notes:** same scenario preconditions as P4
(keyboard-navigable UI place; players-list CoreGui off for Tab; no default
camera contending for arrows).

## 1. Purpose and hierarchy

"Try it on, see it move, decide." Eye order: (1) the mannequin in the
PreviewPane, (2) the item grid, (3) category tabs, (4) chrome. Primary verb:
**Activate an item → it appears on the mannequin instantly.** Spending money is
always a second, explicit, confirmable step.

## 2. Visual-language invariants

- `accent` = the primary action (Buy, Confirm) + selection-indicator form + the
  pane's focused stroke — never category identity, never decoration.
- Wearing = **state + a text chip** (`selected` → `controlSelected` +
  "Wearing"), never hue alone. `chip` = read-only fact (price, Wearing, Owned);
  `badge` = a count; the currency mark appears only inside price/wallet pills.
- One scroll authority: the catalog grid. The preview pane never scrolls.
- Money truth is server-shaped: the wallet number changes only on `confirmed`;
  pending never looks like success.

## 3. Content universe and services

Deterministic fakes (responsibility ledger), injectable clock/seed, command
lifecycle `idle → pending → confirmed | rejected` with scripted rejection
fixtures, resettable; no wall clock, no `math.random`, no network.

- **Currency (original): "Sparks."** Mark = proof-owned original icon asset,
  name `wardrobe:spark` (a four-point spark inside an open ring — nothing
  hexagonal or platform-resembling), ASCII fallback glyph `S`. Copy style:
  mark + number; never a suffix word in pills.
- **WardrobeCatalog** — 28 seeded items across `all, hats, hair, faces, torso,
  legs, shoes, accents, backdrops`; item = `{ id, name, category, creator,
  verified, price (nil = owned/free), thumbKey }`. Original names (Cinder Hood,
  Puffin Beanie, Willow Crown, Static Halo, Cobalt Slickers, Marsh Boots, Moth
  Cloak, Tidepool Tee, …) and creators (Foldline ✓, Petal & Rust ✓, Kite Court,
  Gullwing).
- **InventoryService** — owned set (seed: 9 owned); `owns(id)` fact.
- **EquipService** — `worn` (one item per category slot, signal); `equip(id)` /
  `unequip(id)` commands (instant confirm — try-on is local); the **history**:
  an undo/redo stack (`undo()`/`redo()`, `canUndo`/`canRedo` Readables; a new
  equip after undo truncates the redo branch). Its preview seam publishes the
  worn set to the proof's 3D content handle (§6.2) — the UI never talks to the
  rig directly. History and worn state are semantic and survive everything.
- **WalletService** — `balance` (seed 240 Sparks); `purchase(id)` command.
  Fixtures: `Static Halo` (450) rejects with reason key `buy.insufficient`;
  `Moth Cloak` rejects once with `buy.soldout`, then confirms on retry (proves
  retry + reason swap on one surface).

## 4. State split

| Semantic | Presentation |
|---|---|
| section (`boutique` \| `outfits` \| `profile`), category, filter (owned-only bool, sort id), worn set + history, owned set, wallet balance, purchase status per item, auto-rotate preference | scroll offset, focus + ring, hover, orbit yaw/pitch of the preview camera, transitions, disclosure plates |

Orbit angle is presentation (throwaway); the worn set is semantic and must
survive rotation, size-class flips and theme swaps (RA-P5). Nothing replicates.

## 5. Tokens

Shared roles/ramp/space/radii/shadows only (as P4 §5). Proposed theme metrics
(proof theme package; grid-of-4; names escalate with the theme PR):
`metrics.wardrobe.cardMin` 148 (catalog `Grid.minColumnWidth`) ·
`previewLaneMin` 280 (Composition `minWidth`, preview lane) · `previewCompactH`
224 (stacked pane preferred height; minMax 160–320) · `buyBarH` 56 ·
`confirmW` 420. Proof icons (namespaced; original art + ASCII fallback):
`wardrobe:spark S`, `wardrobe:filter =`, `wardrobe:undo <`, `wardrobe:redo >`,
`wardrobe:verified v`, `wardrobe:hanger #`; built-ins `close`,
`chevron.trailing`.

## 6. Structure

Present via `present(screen, { navigationGroups = §8, initialFocus =
"Section.boutique", traversalWrap = true })`. One `UI.Composition` is the whole
adaptive story; a size-class flip is a re-solve, never a rebuild — the
mechanism behind §11's survival assertions.

```
Screen
└ Composition id="Wardrobe"
    arrangements = { {name="split",   lanes={ {"main"}, {"trail"} }},
                     {name="stacked", lanes={ {"trail","main"} }} }   -- last = fallback
    laneGap="m", groupGap="s"
    groups = { {id="chrome",  span="above"},
               {id="catalog", lane="main",  sizing="fill"},
               {id="preview", lane="trail", minWidth="metrics.wardrobe.previewLaneMin"} }
    children:
      Region "Segments" group=chrome  rank=3            → §6.1 (one form)
      Region "Preview"  group=preview rank=1            → §6.2 (two forms: tall, strip)
      Region "Catalog"  group=catalog rank=2 sizing="fill"
                        mayScroll=true floor={targets=2} → §6.3 (one form)
```
`split` (regular/wide): catalog left (fill), preview right, lane floored at
`previewLaneMin` — a viewport that can't afford it makes `split` illegal and
`stacked` wins, which is exactly the compact phone arrangement: preview strip on
top, catalog scrolling below. Focus order is the declaration's order and is
identical in both arrangements (Composition contract).

**6.1 Segments row** (span, full width): `newPicker{ id="Section", options =
Boutique/Outfits/Profile, selected=section, presentation="automatic",
sizeClass=conditions.sizeClass }` centered; the wallet pill (§6.5) sits at this
row's trailing end, visible in both arrangements. Bodies swap via
`When(section)`: `boutique` = §6.2–6.6; `outfits`/`profile` = honest stub
plates (icon `wardrobe:hanger` at "xl", `heading` = section name, `body`
t("stub.body") "Nothing to show yet.", `caption` secondary t("stub.honest")
"This section is a labeled stub in this proof.").

**6.2 Preview region — the PreviewPane leaf (bounded framework gap, this stage;
capability ledger §A "Live 3D content in a UI box" + §F; new-engine-feature
playbook).** The contract this spec builds against:
- **LuauUI owns the box**: a rendered leaf (working name `UI.PreviewPane{ id,
  width?, height?, surface?, corners?, stroke? }`) — solver-owned rect, style
  chrome applies, mount/unmount owns the engine-content lifecycle (backed by
  `ViewportFrame`). E2 probe + E3 slice are owed by the framework fix.
- **The proof owns the content through a handle**: an original blocky mannequin
  rig (proof-modeled, matte palette from the theme's `surfaceStrong` family,
  deliberately toy-like — no humanlike platform avatar) + its camera.
  EquipService's seam dresses the rig; the camera orbits at the yaw the UI hands it.
- **Declared capability fallback** (adapter without the seam: billboard /
  headless): the leaf renders its fallback plate — `surface="raised"`,
  proof-owned mannequin-silhouette `Image`, `caption` t("preview.unavailable")
  "Live preview isn't available here.", and the worn set as read-only `chip`
  Texts beneath — information parity: what is worn stays readable with no 3D.

Preview region composition (both forms are the same tree at different dims):
```
ZStack
├ PreviewPane  (tall form: width fill, height fill of the lane;
│               strip form: height {type="minMax", min=160,
│               preferred="metrics.wardrobe.previewCompactH", max=320})
├ Grip id="Orbit" fill overlay — focusable=true, focusVisual="none",
│      cursorHint (pointer)   → drag = orbit (yaw follows pointer/touch x-delta,
│      pitch clamped gently on y); capture-based, rectOf re-read per move
├ Anchor overlay (display-only markers exempt from targets; controls below are
│  real floored Buttons in the ZStack, not Anchor children):
│  top-start: Toggle{ id="Spin", label=t("preview.autorotate") "Auto-rotate",
│             value=autoRotate }        (idle turntable; §10)
│  bottom-start: HStack gap="xs": circle Button{icon="wardrobe:undo",
│             label=t("undo") "Undo", enabled=canUndo } · circle
│             Button{icon="wardrobe:redo", label=t("redo") "Redo", enabled=canRedo }
└ When(triedOn item is unowned) → BuyBar (§6.5)
```
- **Orbit on all four classes**: pointer/touch drag the Grip; keyboard/gamepad
  get the **focus-gated Adjust verb** — the Grip's contribution declares
  `adjustTargets` = the pane and `adjustAxis="horizontal"`, so while the pane
  holds focus, Left/Right (and Comma/Period, L1/R1) step yaw 30° per press;
  off-focus those keys navigate. Because `focusVisual="none"`, the focused pane
  paints its own treatment — an `accent` `stroke` on the pane box — shown only
  under the framework's ring-visible rule (ownership-gated, like every focus paint).
- Undo/redo walk the equip history; **disabled at stack ends** (`enabled` binds
  `canUndo`/`canRedo`; theme disabled treatment; the visible empty-history
  state is self-explanatory). Never hidden — the affordance location is stable.

**6.3 Catalog region.**
```
VStack gap="s"
├ CategoryRow: HStack gap="s"
│  ├ ScrollView axis="x" fill: ForEach(categories) → VStack{ Button{ label,
│  │   selected=bind(cat==id) }, underline Box (accent tint-blend, as P4 tabs) }
│  └ circle Button{ icon="wardrobe:filter", label=t("filter") "Refine" } → §6.6
└ ScrollView axis="y" fill (THE scroll region, mayScroll):
   └ ForEach(sections-of-category) → inline header Text{ heading }  +
      Grid{ minColumnWidth="metrics.wardrobe.cardMin", itemSizing="uniform",
            gap="s", rowGap="m" } of ItemCards
```
The category row scrolls on x whenever it overflows (compact); underline +
`selected` mark the active category; keep-visible scrolls the focused chip into
view. Inline headers ("Picked for you", 4 seeded items, above "Everything") are
plain Texts inside the one scroller — the observed inline-header grammar.

**6.4 ItemCard** (one activation surface; Activate = try-on):
```
Button id=item.id label=item.name selected=bind(worn[item.category]==item.id)
└ VStack gap="xs" align="stretch"
  ├ newAsyncImage (thumbKey, width fill, height {type="aspect", ratio=1},
  │                scaleMode="crop", corners "control")
  ├ Text name, textSize="label", lineLimit=1, disclose=true
  ├ HStack gap="xs": Text{ creator, textSize="caption", role="secondary",
  │   lineLimit=1, disclose=true } · When(verified) → newLabel{
  │   icon="wardrobe:verified", title=t("verified") "Verified creator",
  │   presentation="iconOnly" }
  └ HStack: When(unowned) → PricePill = HStack{ surface="chip", padding="xs",
      gap="xs": Image spark-mark ("s" square) + Text{ price, textSize="caption",
      textAlign="end" } }  ·  When(owned ∧ not worn) → Text{ surface="chip",
      text=t("chip.owned") "Owned", textSize="caption" }  ·
      When(worn) → Text{ surface="chip", text=t("chip.wearing") "Wearing",
      textSize="caption" }   (exactly one of the three shows)
```
States: default / hover / focus / pressed / **wearing** (selected + chip) /
owned / unowned (price pill) / image-pending / image-failed (placeholder
persists) / **purchase-pending** (`enabled=false`, dimmed, chip unchanged).
Activating a worn item unequips it (toggle; history records both directions).

**6.5 Wallet pill + BuyBar + purchase modal.**
- *Wallet pill* (Segments row, trailing; non-interactive): `HStack{
  surface="chip" }` of spark mark + `Text{ textSize="numeral", text =
  bind(walletCounter) }`, a `clock:counter` (class `reward` — arrives early,
  never overshoots a quantity) aimed at `balance`.
- *BuyBar* (mounts under the pane via `When(triedOn unowned item)`, height
  `metrics.wardrobe.buyBarH`, `transition={enter="slide-up"}`): full-width
  `Button{ role="default" }` painted `accent`: label = t("buy.cta") "Buy
  {name} — {mark} {price}" (name `lineLimit=1`; ViewThatFits inside the button
  content drops to compact form "Buy — {mark} {price}" when the full line
  cannot fit). Activate → confirm modal.
- *Confirm modal* (`presentModal`, canvasGroup panel, `surface="raised"`,
  shadow `overlay`, width `{type="percent", fraction=0.92,
  max="metrics.wardrobe.confirmW"}`): thumb + name + creator;
  price line (mark + `numeral`); balance-after line `caption` `role="secondary"`
  t("buy.after") "Leaves you {mark} {n}"; footer: `Button` t("buy.confirm")
  "Confirm" (accent) + `Button{ role="cancel" }` t("buy.cancel") "Not now" +
  Close circle. **Lifecycle** — pending: Confirm relabels t("buy.pending")
  "Confirming…", both buttons `enabled=false`; dismissal stays allowed and does
  NOT cancel the command (it resolves; a toast reports the outcome). confirmed:
  modal dismisses, toast t("buy.done") "{name} is yours", wallet counter counts
  down, owned set updates, chip flips; `celebrate` is NOT emitted (a purchase
  is a receipt, not a jackpot). rejected: modal stays; an inline reason strip
  above the footer (`body` Text on the theme's `danger` pair):
  t("err.buy.insufficient") "Not enough Sparks — you have {mark} {n}." /
  t("err.buy.soldout") "That one just sold out." / fallback t("err.generic")
  "Something went wrong. Try again."; Confirm re-enables (retry allowed), the
  try-on stays on the mannequin, the wallet never moved. No silent state.

**6.6 Refine modal** (filter affordance): `presentModal`, small panel: `Toggle`
t("filter.owned") "Owned only", `newPicker` sort (Featured / Price: low first /
Newest — `presentation="automatic"`), footer `Button` t("filter.done") "Done"
(dismiss; filters apply live — Done is just the exit). Cancel/outside tap
dismiss without reverting (the controls already committed; a filter, not a form).

## 7. Adaptation (five-view table)

| View | Arrangement | Categories | Grid cols (cardMin 148) | Notes |
|---|---|---|---|---|
| Phone portrait — compact, touch | stacked (preview strip 160–320 over catalog) | x-scrolling row | 2 | BuyBar directly under the pane = thumb zone; all controls ≥44px |
| Phone landscape — compact/regular, touch | usually split (lane floor decides — never a device branch) | x-scrolling | 2 | strip form only if split is illegal at this width |
| Tablet — regular, touch | split | fits, no scroll | 3 | preview lane at floor |
| Desktop — wide, pointer+keyboard | split | fits | 4 | hover states live; drag-orbit with cursorHint |
| Console — Large: sizeClass capped regular, ten-foot | split | fits at 1.5× paint scale, else x-scrolls | 2–3 | focus-first: initial focus on Segments, ring is the anchor; orbit via Adjust; overscan framework-applied |

The arrangement is never chosen by view name: `split` vs `stacked` falls out of
the lane floor against the real box (Composition rules), so a resized desktop
window and a rotated phone behave identically. Verify the declared column
counts with `adaptive.columnsFor`; `metrics.wardrobe.cardMin` is the only knob.

## 8. Focus and input

**Navigation groups** (declaration order = Tab order; entry `"nearest"`):
`sections` (horizontal: picker options; wallet is non-interactive) →
`categories` (horizontal: category buttons + filter; keep-visible scrolls the
x-row) → `grid` (vertical: cards in reading order across grid rows;
keep-visible scrolls the catalog) → `preview` (vertical: Auto-rotate, Orbit
pane, Undo, Redo, BuyBar-when-present). Declared exits — the grid ⇄ preview ⇄
tabs mesh: `grid.exit.right = preview`, `preview.exit.left = grid`,
`grid.exit.up = categories`, `preview.exit.up = sections`. One declaration
serves both arrangements (Composition keeps one focus order); in `stacked`,
up/down fall-through covers the vertical adjacency. Losing forms and closed
`When`s are framework-excluded. Initial focus `Section.boutique`;
`handle.focusOrder()` is the acceptance instrument.

**Verbs × four input classes:**

| Verb | Pointer | Touch | Keyboard | Gamepad |
|---|---|---|---|---|
| Try on / un-wear | click card | tap card (44px floor) | Navigate + Return/Space | Navigate + ButtonA |
| Orbit preview | drag the Grip | one-finger drag | focus pane, then Left/Right or Comma/Period (Adjust) | focus pane, then D-pad Left/Right or L1/R1 (Adjust) |
| Undo / Redo | click | tap | Navigate + Activate | Navigate + Activate |
| Buy | click BuyBar → Confirm | tap → Confirm | Activate → Activate | Activate → Activate |
| Back / dismiss modal | Close, outside click | Close, outside tap | Close via focus+Activate (Esc never cited) | ButtonB (Cancel) |
| Switch section / category | click | tap | Navigate + Activate (picker + buttons) | Navigate + Activate |
| Refine | click filter → controls | tap | Tab/arrows + Activate; Toggle auto-flips on Activate | D-pad + A |
| Auto-rotate | click Toggle | tap | Activate flips value | ButtonA flips value |

Every verb reaches every class; nothing essential is hover-only. Deliberate
omissions: no keyboard undo shortcut (hardware keys are never spec vocabulary),
no swipe gestures (ledger §A — visible affordances instead). Cancel on the
base surface: no-op. While a purchase is pending, Cancel still dismisses the
modal (the command resolves and toasts) — never a spinner trap.

## 9. No-silent-states ledger (this screen's full enumeration)

Rejected purchase → visible reason strip (§6.5); disabled undo/redo → visible,
self-explanatory empty history; purchase-pending → dimmed card + pending
labels; image failed → placeholder persists (contract); capability absent →
fallback plate + worn chips (§6.2); zero filtered items → centered empty
state: `heading` t("filter.none") "Nothing matches", `caption` naming the
active filters, `Button` t("filter.reset") "Reset filters". Every blocked
interaction explains itself on screen.

## 10. Motion (+ reduced motion)

| Moment | Motion | Reduced-motion form |
|---|---|---|
| try-on lands on rig | proof-owned: worn piece pops on the mannequin via `spring` scale, class `object` (driven through the content handle) | placed instantly |
| auto-rotate turntable | slow constant yaw on the presenter's clock, only while `autoRotate` and pane unfocused-by-Adjust | **off** — decorative; toggle stays honest (its value is unchanged, rotation just doesn't run) |
| orbit release | release velocity hands to a `decay`-class spring (gesture-inherited, no decorative bounce) | angle holds where released |
| wallet change | `clock:counter`, class `reward`, never overshoots | final count placed instantly |
| BuyBar in/out | `When` transition `slide-up` (mirror exit) | instant |
| modals | `materialize` on canvasGroup panels | instant |
| underline/selected blends | tint-blend springs, class `object` | snap |
| toasts | presenter defaults | instant, same schedule |

All motion is signal-driven on the presenter clock; the rig animation is
proof-owned content behind the PreviewPane handle and obeys the same
`motionPolicy` fact.

## 11. Text scaling, localization, survival

Type scale 0.5–3: item name and creator are 1-line + `disclose` (full value via
the framework plate on hover-dwell / focus / long-press); BuyBar runs its
declared ViewThatFits ladder before ever ellipsizing; chips grow with type and
cards grow uniformly (`itemSizing="uniform"`); the catalog floor
(`{targets=2}`) resolves against the live theme, so large type can legally
force `stacked`. All copy in the proof string table `wardrobe.*` with the ~1.4×
pseudo-locale fixture; worst case shown fitting: pseudo-loc "Buy {name} —
{mark} {price}" at scale 3 on phone portrait (compact BuyBar form). RTL/BiDi:
recorded out-of-scope gap (§A).

**Survival assertions (RA-P5):** worn set + history + wallet + section/
category/filter signals survive (a) rotation / any size-class flip (the
Composition re-solves; zero factory reruns; PreviewPane keeps its mount and
engine content), (b) a live theme swap (chrome re-themes without remount; the
rig palette re-reads its theme family through the handle), (c) preferred-text
steps. Assert via zero create/remove across (a)–(c), `compositionAt` reporting
the arrangement change, `handle.focusOrder()` stability, and
`controller.diagnostics()` clean in every fixture.

## 12. Feedback / sound hooks (bus → proof ids; LuauUI plays nothing)

`activate`→`sfx.wd.tap` · `select`→`sfx.wd.flip` · `adjust` (orbit
step)→`sfx.wd.tick` · `commit` (equip/undo/redo/purchase)→`sfx.wd.done` ·
`reject`→`sfx.wd.deny` · `dismiss`/`cancel`→`sfx.wd.close`. No haptics.

## 13. Deliberately left out

Outfit saving and profile editing (honest stubs — §6.1); catalog search (P4
owns the pattern; repeating it adds no capability evidence); item detail pages
(try-on IS the detail — the mannequin answers the question); color/variant
pickers (single SKUs); real commerce (the prompt boundary belongs to
`MarketplaceService` in production — responsibility ledger row P5); avatar body
sliders (fixed rig; the proof axis is UI ⇄ engine-content, not customization).
