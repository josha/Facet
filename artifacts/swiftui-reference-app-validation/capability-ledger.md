# Capability ledger — swiftui-reference-app-validation

**Written 2026-08-08, before any proof code**, against the current public surface
(`docs/reference/api.md`, v0.9.x line) and the stage-start source inventories in
`sources/`. Classifications:

- **available** — a first-class public LuauUI construct covers the behavior.
- **composable** — buildable from public LuauUI today with no framework change;
  the mechanism is named.
- **framework gap** — reusable behavior LuauUI should own. *(bounded)* = fixed in
  this stage behind a public API with tests/docs/live proof; *(proposal)* = a
  large subsystem written up as an evidence-backed follow-on, with the honest
  approximation the proof uses instead.
- **Roblox-service adaptation** — the behavior belongs to a platform/game
  service in production; the proof runs it on a deterministic fake and the
  responsibility ledger maps the real service.
- **no host equivalent** — a Roblox experience cannot reach this surface; the
  ledger row is the deliverable, never a simulated fixture.

"Evidence" cites E0 (api.md/source) now; rows that require live proof gain their
E3 citation at close. This is not a score and must not be summed.

## A. Shared UI vocabulary (all five proofs)

| Reference behavior | Classification | LuauUI mechanism / note |
|---|---|---|
| Stacked/columnar screens, cards, spacers, hairlines | available | `VStack`/`HStack`/`ZStack`/`Box`/`Spacer`/`Divider` |
| Size-class-adaptive shells (sidebar ⇄ tabs; compact vs regular) | available | `UI.Composition` arrangements + `env sizeClass`/`adaptive.conditions`; `AdaptiveStack` for axis flips |
| Try-candidates-until-fits rows (FT `ViewThatFits` parking chips) | available | `UI.ViewThatFits`, same declared-order contract |
| Scrolling pages/lists, both axes, keep-visible on focus | available | native `ScrollView`, `scrollToVisible` presenter service |
| Long virtualized lists | available (vertical) | `newVirtualList`; horizontal shelves use `ScrollView{axis="x"}` (bounded content) |
| Sortable multi-column table with selection (FT orders table) | available | `newTable` (sortable columns, `none/single/multi` selection, reorder) |
| Sectioned status lists (FT compact orders; Fruta lists) | composable | `ForEach` groups of header `Text` + rows in a `VStack`/`ScrollView` |
| Adaptive tile grids (BB backyards ≥300, Fruta ingredients ≥130, gallery grids) | available | `UI.Grid` `minColumnWidth` (+ `"intrinsic"`, `itemSizing="uniform"`) |
| Buttons incl. icon+label, roles, selected state | available | `UI.Button` (icon, role, shape, compactLabel) |
| Toggles / checklist rows (Fruta recipe "gathered") | available | `UI.Toggle` |
| Steppers (Fruta batch count 1–9) | available | `newStepper` (range clamp) |
| Sliders / adjustable values | available | `newSlider` + `valueModel` |
| Segmented/inline pickers (FT timeframe, sort menus) | available | `newPicker`; menu-style via `newPopupButton` |
| Search field + live filtering + suggestions | composable | `newTextInput{clearButton}` + memo filter; suggestion rows from a memo (gallery example 02 precedent) |
| Forms (BB account edit, FT sign-up, donut editor) | composable | `ScrollView`+`VStack` rows with `newTextInput`/pickers; focus order auto-derived |
| Modal sheets / alerts / confirmation flows | available | `presentModal` (+ `outsideTapCancel=false` for alerts); detents have no equivalent — sized modals instead |
| Toasts / transient banners (BB happiness toast) | available | `presentToast` (schedule, transitions, floor duration) |
| Structural show/hide with motion | available | `UI.When`/`ForEach` `transition` (fade/slide/materialize; mirror exits; reduced-motion parity) |
| Springs, counters, timers, timelines (pulse highlight, scripted sequences) | available | `motion` clock (`spring`/`counter`/`timer`/`timeline`/`chase`) |
| Numeric change emphasis (FT `contentTransition(.interpolate)` pulse) | composable | motion spring on role/scale + `Text` bind; exact cross-fade morph of glyphs is not claimed |
| Progress bars / capacity gauges (BB supply gauges, FT flavor rows) | available / composable | `newProgressView`; circular capacity ring via `UI.Path` + `pathShapes` arc |
| Ring/arc/needle art (gauges) | available | `UI.Path` (Path2D; ≤100 pts, stroke-only) |
| Badges, chips, tags, price pills | available | `Text{surface="badge"/"chip"}`, `newChip`, `newLabel` |
| Async images with pending/failed states | available | `newAsyncImage` + `newResourceProvider` |
| Image sizing/tint (thumbnails, cover crops) | available | `UI.Image` `scaleMode` + `tint` |
| Gradients (skies, hero washes, bar fills) | available | `UI.gradient` (2–3 stops, token or rgb, reactive); continuous time-of-day sky = reactive stops/`tint` |
| Layered composed art (BB birds = tinted layers) | composable | `ZStack` of tinted `Image` layers; per-part palette via `tint` |
| Shadows, corners, strokes | available | `UI.shadow`/`corners`/`stroke` |
| Theme swap without remount | available | theme packages (ADR-0019); proof axis RA-M3 |
| Preferred text sizes, reduced motion, hit floors, focus/keyboard/gamepad | available | Step 8/8.5 machinery; presenter `keyboardNavigation`; five-view matrix |
| Localization expansion + locale fact | composable | proof-owned string tables keyed on `env locale`; LuauUI measures/reflows. **BiDi/RTL mirroring is a known LuauUI gap (out of scope; recorded, not claimed)** |
| Drag & drop / reorder | available | `draggable`/`dropTarget`, `newDragSession`, Table reorder |
| Swipe-row actions (Fruta favorite swipe, BB offer dismiss) | framework gap (proposal) | no secondary-action/swipe model yet (parity §0). Proofs expose the same verbs as visible affordances on every input class — the cross-platform-correct adaptation — and the proposal covers a unified swipe/long-press/secondary-click model |
| Long-press / context menus (FT row ellipsis menu is a button — fine) | composable (button-triggered) | `newPopupButton`/menu recipe from an explicit affordance; bare long-press recognition remains in the same proposal as swipe |
| Hero shared-element transition (Fruta ingredient card `matchedGeometryEffect`) | framework gap (proposal) | no matched-geometry/shared-element subsystem. Proof uses `presentModal`/`When` + `materialize` + `canvasGroup` fade — honest approximation, not parity. Follow-on proposal with evidence from the proof |
| 3D card flip (Fruta flip, perspective) | no host equivalent (perspective) / composable (approximation) | Roblox 2D GUI has no perspective transform; a width-collapse flip (scale-X through zero via motion) is the declared approximation |
| UI-over-UI blur / vibrancy materials (Fruta materials) | no host equivalent | Roblox cannot blur UI behind UI (`BlurEffect` is 3D-only). Adaptation: translucent theme surfaces + scrims |
| Custom `Layout` protocol conformances (FT diagonal stack, hero tiling, lattice, flow) | composable | `Anchor` fractional offsets (diagonal stack, staggered lattice), `Composition` (hero+tiles), `Grid` (tag cloud). A general author-defined layout protocol is deliberately absent (constitution); if a proof cannot express one of these with public primitives, that becomes a named finding, never a local layout engine |
| Wrapping tag cloud (FT `FlowLayout`) | composable (approximation) | `Grid{minColumnWidth="intrinsic"}` — uniform columns, not ragged flow. If the ragged-flow reading is essential, candidate *bounded* gap (`wrap` on stacks); decided by the proof, not assumed |
| Live 3D content in a UI box (avatar preview; FT city orbit hero) | framework gap (bounded) | **new engine-content leaf backed by `ViewportFrame`** via the new-engine-feature playbook: LuauUI owns the box, lifecycle, style chrome, capability fallback; the proof owns camera/rig/content through a handle. E2 probe + E3 slice required |
| Charts — bars (FT top-five) | composable | `Grid`/`HStack` of `Box` columns + value badges; image-under-axis labels are plain cells |
| Charts — multi-series lines (FT sales history) | composable | `UI.Path` per series (≤100 pts each), legend chips |
| Charts — area fill with day/night bands (FT weather) | composable (approximation) | Path2D cannot fill: line `Path` + banded `Box` strip approximation; classified approximation, not parity |
| Chart interaction (none in FT — all read-only) | n/a | matches: proofs ship read-only charts |

## B. Backyard Birds → proof P1 "Glade"

| Feature (sources/features-backyard-birds.md) | Classification | Mechanism |
|---|---|---|
| Adaptive shell: tabs (phone) vs sidebar+detail (wide), per-section stacks | available | `Composition` arrangements + `When` per section |
| Backyards grid with live supply glances, favorite star toggle | available/composable | `Grid` + composed card; star = `Button{selected}` with motion pop |
| Search + suggestions ("X is currently in Y") | composable | TextInput + memos over visit state |
| Scene viewport (sky gradient, silhouettes, plants, fountain, visiting bird) | composable | `ZStack`+`Anchor` fractional offsets; width-stepped height via `ViewThatFits`/conditions; reactive `gradient` sky; tinted layer art (original assets) |
| Bird fly-in scripted sequence (~8s beats) | available | `motion` `timeline`/sequenced springs; reduced-motion = place instantly |
| Supply drain (dates + durations, derived remaining) | Roblox-service adaptation | fake service owns refill timestamps + drain constants; UI derives via clock fact — production: server time + DataStore |
| Instant water refill; food picker sheet with snap carousel | available | Button command; `presentModal` + `ScrollView{axis="x"}` carousel (snap-to-item is engine momentum, not claimed as paging) |
| Premium food ownership counts, "Use 1"/"Shop"/"Choose" states | Roblox-service adaptation | fake ledger; production: MarketplaceService developer products |
| Store shelf: hero "best value" product + shelves + prices | composable + adaptation | LuauUI cards/shelves; purchase = fake commerce command with confirm/reject; production: `MarketplaceService:PromptProductPurchase` (host sheet) |
| Subscription tiers page with marketing header + upgrade-only mode | composable + adaptation | LuauUI layout; production: Roblox Subscriptions (`PromptSubscriptionPurchase`) |
| Pass status gates (early-access species, premium badge, offer card + dismiss) | composable | domain facts drive `When`; offer dismiss = visible button (swipe row per §A) |
| Happiness toast on refill (8s auto-dismiss) | available | `presentToast` |
| Recent-visitors list, relative times | composable | rows + proof-owned time formatting (LuauUI has no date/locale formatter — proof-owned fake i18n table; recorded once here for all proofs) |
| Account form, edit sheet, restore-purchases button | available | TextInputs, modal, async command states |
| RTL mirroring of scene art | out of scope | recorded under the shared BiDi gap row |
| Widgets, App Intents resupply, watch app/complications, StoreKit system sheets, manage-subscription, offer codes | no host equivalent | ledger rows only; nearest production analogs: none for widgets/watch; commerce prompts are host sheets owned by MarketplaceService |

## C. Food Truck → proof P2 "Cartwheel"

| Feature (sources/features-food-truck.md) | Classification | Mechanism |
|---|---|---|
| Split navigation, sidebar sections incl. per-city rows; selection resets pushed detail | composable | `Composition` (sidebar/detail lanes ⇄ compact stack) + `When` stacks; selection signal clears detail state |
| Dashboard 2×2 ⇄ 1-col card grid, width-threshold compact logic (incl. large-type-counts-as-compact) | available | `Composition`/conditions; preferred-text fact composes into the compact decision — same rule FT encodes by hand |
| Hero-square + 2×2 tiling of recent orders (custom Layout) | composable | `Composition` lanes or `Grid`+`Anchor`; diagonal donut stack = `Anchor` fractional offsets |
| New-order arrival: slide-in insertion + footer pulse | available | `ForEach` transitions + motion spring pulse |
| Animated parallax brand header (Canvas, 10 layers, sprite truck) | composable | layered `Image`s + `Anchor` reactive offsets on the motion clock; flipbook via timed asset swap; reduced motion stills it. Not claimed as a Canvas equivalent |
| Weather card: area chart + night bands + sunrise/sunset markers | composable (approximation) | §A charts row; ambient "weather" is a deterministic fake fact (WeatherKit itself = no host equivalent) |
| Orders list ⇄ sortable table, search, bulk complete, row menus | available | `newTable` + toolbar affordances; menu = PopupButton |
| Order detail status machine placed→preparing→completed; sheet on complete | composable | domain state + commands; completion modal with scripted box motion (`timeline`) |
| 60s prep countdown surviving navigation | available | motion `timer` on domain fact; persists across screens because the service owns it |
| Donut gallery grid⇄table, composite sort (popularity/timeframe, name, flavor) | available/composable | Grid/Table + pickers driving memo sorts |
| Donut editor: live preview, flavor gauges (relative-max), ingredient pickers incl. sectioned "None" options, live binding (no save) | available/composable | layered-art preview; `newProgressView` rows; `newPicker`/PopupButton; signals are live-bound by nature |
| Top-five bar chart with image axis labels; Siri tip | composable / no host equivalent (Siri) | §A bars; App Shortcuts have no experience API |
| City view: orbiting 3D hero + recommended-spot card + `ViewThatFits` chips | framework gap (bounded: Viewport leaf) + available | Viewport leaf hosts proof-owned orbit camera scene; chips = `ViewThatFits` |
| Social feed, sub-gated highlighted section, marketing banner, settings toggles | composable + adaptation | `When` on entitlement fact; fake subscription service; production: Roblox Subscriptions |
| Sales-history chart with lock overlay + unlock upsell card (two states) | composable + adaptation | line paths at 0 opacity under lock badge scrim; fake non-consumable entitlement; production: game pass / dev product |
| Sign-up form (username/password/passkey toggle, focus autoset, validation-gated confirm) | composable / passkeys = no host equivalent | TextInputs + masked entry **← LuauUI has no secure/masked text mode: candidate bounded gap; if not bounded, proof labels the field non-masked and the gap ships in framework-fixes.md** |
| Live Activity / Dynamic Island / widgets / local notifications / App Store review-refund-restore / MenuBarExtra / deep-link URL | no host equivalent | ledger rows; deep-link analog in production = join `launchData` (mapped in responsibility ledger); notifications: no in-experience local-notification API |

## D. Fruta → proof P3 "Sipworks"

| Feature (sources/features-fruta.md) | Classification | Mechanism |
|---|---|---|
| Shell: compact tabs ⇄ regular sidebar, live flip on resize | available | `Composition`; state survives re-solve (no remount) |
| Menu/favorites/recipes lists sharing one row component + shared selection | available | one row blueprint; selection signal on the shared model |
| Search with ingredient suggestions, state shared across sections | composable | TextInput + memos on shared signal |
| Favorites toggle (list affordance + detail toolbar), empty state | available/composable | Button{selected}; `When` empty overlay; swipe per §A rule |
| Smoothie detail: adaptive header (full-bleed ⇄ wide card), markdown-emphasis copy | composable | `ViewThatFits`/conditions; emphasis via split `Text` runs (LuauUI has no rich-text spans — recorded; candidate proposal if the proofs show it reusable) |
| Ingredient hero-card open/close + 3D flip to nutrition facts | framework gap (proposal) + approximation | §A hero-transition + flip rows; nutrition face = table of measured rows |
| Order flow: pay-shaped button OR redeem-free button; payments-disabled guard alert | composable + adaptation | fake commerce; production: `PromptProductPurchase`; the Apple Pay chrome itself = no host equivalent (and was visual-only in the sample) |
| Order-placed screen: flip card pending→ready on 4s fake timer; sign-up banner | composable | motion + fake service; Sign in with Apple = no host equivalent (Roblox identity is ambient — recorded) |
| Rewards card: 10 stamp slots, staggered pop for newly-earned, clear-on-leave, compact variant | available/composable | Grid of seals + `timeline` staggered springs; `unstamped` fact cleared on dismiss |
| Recipes: unlock product card with live price, locked items absent until purchase, animated reveal | composable + adaptation | `When` + `ForEach` transitions; fake non-consumable |
| Recipe view: batch stepper ×N scaling measured ingredients, gathered checklist | available | `newStepper`, `Toggle` rows, derived quantities |
| Deep localization (plural rules, unit/list formatting, per-purpose tables) | Roblox-service adaptation / proof-owned | proof ships its own locale tables incl. a pseudo-expansion locale + plural-form fixture; production: LocalizationService/Translator. Roblox exposes no `ListFormatter`/`MeasurementFormatter` — the fake i18n layer owns it |
| Compact entry flow (App Clip): menu→detail→order only, reusing full components, deep-link to item | composable + adaptation | a second entry scenario presenting the same blueprints with a compact shell; production analog: join `launchData` deep link. App Clip install overlay + location verification = no host equivalent |
| Widgets (featured item / rewards card reuse) | no host equivalent | ledger rows |
| Ambient bubble background (randomized shimmer, off on macOS) | available | motion + reduced-motion parity; deterministic seeds (no `math.random` in proofs) |

## E. Roblox app home → proof P4 "Foyer"

| Observed behavior (sources.md) | Classification | Mechanism |
|---|---|---|
| Icon nav rail with active emphasis; top bar (brand, search, profile, badged bell) | available | HStack/VStack + Buttons + badge Text |
| `For you | Charts` underline tabs | composable | Buttons{selected} + underline Box; `When` bodies |
| Friends carousel (circular portraits, leading badged add tile) | available | `ScrollView{axis="x"}` + async images |
| Sectioned feed: responsive card grid (4→2 cols), horizontal continue shelf, section headers with chevron | available | `Grid{minColumnWidth}` + x-ScrollViews in a page ScrollView |
| Game cards: thumbnail, title, rating row, "Ad" disclosure | available | async image + rows; disclosure chip |
| Search collapses to icon at narrow width | available | `ViewThatFits` (field ⇄ icon button) |
| Tile → detail-shaped surface; refresh/reset | composable | modal or detail arrangement; fake feed service |
| Feed/recommendation/friends/presence data | Roblox-service adaptation | deterministic fake feed; production: game backend + `Players:GetFriendsAsync`/presence + platform search |
| Beta "Update Required" scrim modal (observed) | available | `presentModal` — recorded as observed modal grammar |
| The app's native shell itself (window chrome, account/system settings) | no host equivalent | the proof is an in-experience reinterpretation, stated plainly |

## F. Roblox app avatar editor → proof P5 "Wardrobe"

| Observed behavior | Classification | Mechanism |
|---|---|---|
| `Marketplace | Customize | Profile` segmented control | available | `newPicker` segmented |
| Category tab row with underline + trailing filter, horizontally scrollable when compact | composable | x-ScrollView of Buttons{selected} |
| Item grid: thumbnail, name, creator + verified badge, price pill; inline section headers | available | Grid + async images + chips |
| Live 3D preview pane with neutral backdrop | framework gap (bounded: Viewport leaf) | proof owns rig (blocky original mannequin + `HumanoidDescription`-shaped fake), camera; LuauUI owns box/lifecycle |
| Select-to-try-on updates preview; wearing indicators | composable | equip command → preview state; grid card selected state |
| Undo/redo over equip history | composable | proof-owned command stack (signals); buttons disable at stack ends |
| Currency pill; purchase-shaped flow with confirm/reject | Roblox-service adaptation | fake wallet/commerce; production: `MarketplaceService:PromptPurchase` + AvatarEditorService/inventory |
| Preview orbit/rotate (pointer drag; touch) | composable | `Grip` on the viewport box + focus-gated `Adjust` for keyboard/gamepad parity |
| Compact arrangement: preview stacked over catalog; state survives rotation/theme swap | available | `Composition`; RA-P5 asserts survival |
| Avatar-settings toggle, profile section stubs | composable | scoped to the representative loop; stubs declared, not faked as complete |

## G. Cross-cutting honesty rows

- **No percentage score is derivable from this ledger** (plan rule).
- Rows marked *approximation* are named as such in the proofs' on-screen copy?
  No — approximations are named in the ledger and audit only; proofs present
  their own coherent original design rather than imitating the reference pixel
  by pixel.
- Deterministic seeds: all "random" reference behavior (bubble shimmer, feed
  variety, generated orders) is seeded and injectable; proofs never call
  wall-clock/random APIs directly (scenario reset must reproduce byte-identical
  dumps).
- Candidate bounded framework gaps going into the build (final list lives in
  `framework-fixes.md` at close): **(1) ViewportFrame engine-content leaf**
  (required: P5, used by P2 city hero); **(2) masked/secure text entry**
  (P2 sign-up; engine `TextBox` capability must be probed first — may resolve to
  "engine makes it hard → recorded gap, unmasked field + disclosure in proof");
  **(3) stack `wrap`/flow** (only if P2's tag cloud reads wrong as a uniform
  grid). Everything else listed as *proposal* ships as a follow-on document,
  not code.
