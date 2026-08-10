# Backyard Birds — Behavioral Feature Inventory

Source: Apple sample app "Backyard Birds" (SwiftUI, SwiftData, StoreKit 2, WidgetKit, App Intents).
Compiled from source only. Written in original wording for clean-room reimplementation.

Targets/packages found in the checkout:
- **BackyardBirdsData** (SwiftPM library) — SwiftData models + seeded fake-data generation
- **LayeredArtworkLibrary** (SwiftPM library) — image-asset composition views for birds/plants/backyard scenery
- **BackyardBirdsUI** (SwiftPM library) — shared, cross-platform UI components (backyard viewport, bird icon, supply gauge, visitor list, pass offer card, style helpers)
- **Multiplatform** — the iOS / iPadOS / macOS app (`Backyard Birds` target); also builds for tvOS per package platform lists though no tvOS-specific UI code exists
- **Watch** — the watchOS app (`Backyard Birds (Watch)` / companion, standalone `WindowGroup`)
- **Widgets** — a WidgetKit extension shared by iOS/macOS/watchOS via an App Group

---

## 1. App structure & navigation

### 1.1 Root scene
`BackyardBirdsApp` (Multiplatform) and `BackyardBirdsWatchApp` (Watch) are each a `@main App` with a single `WindowGroup` wrapping `ContentView()`. Both apply two view modifiers app-wide:
- `.backyardBirdsShop()` — wires up StoreKit transaction observation (see §3.5)
- `.backyardBirdsDataContainer()` — creates/attaches the SwiftData `ModelContainer` and triggers first-run data generation (`DataGeneration.generateAllData`)

### 1.2 Top-level navigation adapts to platform (Multiplatform target)
`ContentView` reads `@Environment(\.prefersTabNavigation)` and picks one of two shells:

- **Tab navigation** (`AppTabView`) when `prefersTabNavigation == true`. This environment key is read from `UITraitCollection.userInterfaceIdiom`: **iPhone only** (the `Multiplatform/PrefersTabNavigationEnvironmentKey.swift` copy checks `== .phone`; a stray duplicate file `Multiplatform/General/PrefersTabNavigationEnvironmentKey.swift` also exists and additionally treats `.tv` as tab-preferring — both define the same key so only one is actually compiled/used per target membership). Result: iPhone gets a bottom `TabView`; other idioms fall through to the split view.
- **Split view** (`NavigationSplitView`) otherwise — used on iPad and macOS. Sidebar = `AppSidebarList`, detail = `AppDetailColumn`.

Both shells are driven by the same `AppScreen` enum (`.backyards`, `.birds`, `.plants`, `.account`), each with a `label` (icon+title) and a `destination` view (`BackyardNavigationStack`, `BirdsNavigationStack`, `PlantsNavigationStack`, `AccountNavigationStack`). Each destination is its own `NavigationStack`, so push navigation inside a tab/column is independent per section.

- `AppSidebarList`: a `List(AppScreen.allCases, selection:)` of `NavigationLink(value:)` rows; sets `.navigationTitle("Backyard Birds")`.
- `AppDetailColumn`: shows `screen.destination` or, if nothing is selected, `ContentUnavailableView("Select a Backyard", …)`. On macOS it forces `.frame(maxWidth:.infinity, maxHeight:.infinity)` plus an opaque `.background()` so the split-view detail pane fills the window.
- `AppTabView`: `TabView(selection:)` over `AppScreen.allCases`, each screen tagged and given a `.tabItem`.

### 1.3 watchOS navigation (separate, simpler shell)
`Watch/ContentView` is its own `NavigationSplitView` (not reusing `ContentView`/`AppScreen`): sidebar = `BackyardList` (shared UI component from BackyardBirdsUI), detail = `ContentUnavailableView` until a backyard is picked, then `navigationDestination(for: Backyard.ID.self)` pushes `BackyardTabView`. There is no Birds/Plants/Account section on watch — those live only inside a backyard's per-backyard tabs, or (Account/RestorePurchases) are simply absent on watch UI. Watch shows a `.sheet` presenting `SubscriptionStoreView` directly, triggered by tapping the Backyard Birds Pass offer card in the backyard list, and listens via `.onInAppPurchaseCompletion` to auto-dismiss on success.

### 1.4 Per-screen navigation summary

| Screen | Reached via | Presentation |
|---|---|---|
| Backyards grid | Sidebar/tab "Backyards" | `NavigationStack` root |
| Backyard detail | Tap a backyard card/row | `navigationDestination(for: Backyard.ID.self)` push |
| Bird Food picker | Tap a supply gauge/food row in backyard detail | `.sheet` |
| Bird Food Shop | "Bird Food Shop" row inside food picker | push (`navigationDestination(isPresented:)`) on iOS/iPad/mac; on watch it's a separate `NavigationStack` destination pushed the same way |
| Backyard Birds Pass shop | Offer card in list, or Account screen buttons | `.sheet` presenting `SubscriptionStoreView` |
| Manage subscription | Account screen, once subscribed | iOS: `.manageSubscriptionsSheet`; macOS: opens `https://apps.apple.com/account/subscriptions` via `openURL` (no in-app sheet) |
| Birds grid | Sidebar/tab "Birds" | `NavigationStack` root, no push destination (grid only) |
| Plants list | Sidebar/tab "Plants" | `NavigationStack` root, no push destination |
| Account | Sidebar/tab "Account" | `NavigationStack` root |
| Edit Account form | Pencil toolbar button on Account | `.sheet` |
| Watch: Backyard tabs (Summary/Content/Visitors) | Tap backyard in watch sidebar | push, then horizontally-paged `TabView` (`.tabViewStyle(.carousel)`) |

---

## 2. Screen-by-screen behavior

### 2.1 Backyards Grid (`BackyardGrid`, wrapped by `BackyardNavigationStack`)
- Layout: `ScrollView` → optional `NewBirdIndicatorCard` → `LazyVGrid` with adaptive columns (`minimum: 300`) populated by `BackyardsSearchResults`.
- `.searchable(text:)` with `.searchSuggestions` — when the search field is empty, shows `BackyardsSearchSuggestions`: one suggestion row per backyard's *current* visitor (`Set` of `currentVisitorEvent`s, de-duplicated, sorted by backyard name then species name), rendered as bold Markdown-ish `Text("**species** is currently in **backyard**")` with `.searchCompletion(backyardName)` so tapping fills the search field with the backyard's name.
- Search itself (`BackyardsSearchResults`) is a live `@Query` — empty search text queries all backyards sorted by creation date; non-empty text queries `#Predicate { backyard.name.contains(term) }` sorted by name.
- `NewBirdIndicatorCard` (behind a static flag `DataGenerationOptions.showNewBirdIndicatorCard`, hard-coded `false` — dead in shipped build) would show a pulsing `NewBirdIndicator` icon (a `PhaseAnimator` scaling/rotating between two phases) plus "‹Species› is visiting" / "Arrived in ‹Backyard›" text with a chevron, in a capsule background.
- Content margins differ per platform: macOS uses a flat 10pt scroll-content margin; other platforms use `[.horizontal, .bottom]` 10pt (no top margin, since the search bar sits there).
- Uses `Environment(\.passStatus)`/`passStatusIsLoading` to compute (unused directly in body, but retained) `backyardsLimit`/`canPresentSubscriptionOfferCard` helpers.

### 2.2 Backyard Grid Item (`BackyardGridItem`)
- `ZStack`: a `NavigationLink(value: backyard.id)` wrapping `BackyardViewport` (see §2.9) as the tappable background, `.buttonStyle(.plain)`, overlaid with a `VStack` of `Header` (top) and `SupplyGauges` (bottom).
- **Header**: backyard name in a padded background chip (non-interactive — `.allowsHitTesting(false)`), plus a favorite-star `Button` that toggles `backyard.isFavorite` with a `.contentTransition(.symbolEffect(.replace.upUp/.downUp))` depending on direction of the toggle.
- **SupplyGauges**: two small `BackyardSupplyGauge`s (food, water) scaled to 0.65 in circular material backgrounds; `.allowsHitTesting(false)` — tapping anywhere on the card (except the star) navigates into the backyard; gauges here are read-only glances.
- `.containerShape(.rect(cornerRadius: 20))` for hit-testing/clip shape consistency with sibling rows.

### 2.3 Backyard List (watchOS-shared component, `BackyardList` in BackyardBirdsUI)
- A plain SwiftUI `List`; on watchOS uses `.listStyle(.carousel)`.
- If not subscribed and the offer wasn't dismissed this session, shows a `Button` wrapping `BackyardBirdsPassOfferCard` at the top, with a leading `.swipeActions` "Dismiss" button (sets local `@State offerWasDismissed`) and an `.easeInOut` animation on dismissal.
- Each row: `NavigationLink(value: backyard.id)` around `BackyardViewport` with the backyard name overlaid top-leading (shadowed text over the artwork), `.buttonStyle(.borderless)`, zero list-row insets, rounded container shape.
- Accepts `isSubscribed`, an optional `backyardLimit` (unused visually beyond being passed in), and an `onOfferSelection` callback fired when the offer card is tapped.

### 2.4 Backyard Detail (`BackyardDetailView`)
- `ScrollView` containing:
  1. `BackyardViewport` (rounded corners) with a bottom overlay: when a bird is present and `presentingHappinessIndicator` is true, shows `BirdFoodHappinessIndicator`.
  2. `LazyVGrid` (adaptive, min 400) with two `BackyardSupplyIndicator` rows — food and water.
  3. "Recent Visitors" section header (secondary/tertiary styled caps-like subheadline).
  4. `LazyVStack` of `RecentBackyardVisitorsView`.
- **Happiness indicator trigger**: `.onChange(of: backyard.foodRefillDate)` — i.e., every time food is refilled (a new food chosen), the happiness toast is shown via a bouncy spring animation, then automatically dismissed 8 seconds later via `DispatchQueue.main.asyncAfter`.
- Toolbar: a favorite-star button identical in behavior to the grid item's.
- `.contentMargins(20, for: .scrollContent)`, `.navigationTitle(backyard.name)`.

### 2.5 Backyard Supply Indicator (`BackyardSupplyIndicator`)
- A full-width `Button` row: `BackyardSupplyGauge` (large control size) + label column (food name, or "Water") + a formatted "‹time› remaining" secondary caption + a trailing icon-only affordance label ("Choose Food" / "Refill Water").
- Tapping the **water** row instantly refills water in place (`backyard.waterRefillDate = .now`, animated) — no confirmation, no sheet.
- Tapping the **food** row presents `.sheet(BirdFoodPickerSheet)`.
- Non-macOS gets `.hoverEffect(.highlight)` on the whole row (tvOS/iPadOS pointer/remote affordance).
- Remaining-time text uses `Duration(secondsComponent:)` formatted via `.units(allowed:[.hours,.minutes,.seconds], width:.abbreviated, maximumUnitCount: 1)` — i.e. shows only the single largest non-zero unit (e.g. "1h", "33m", "12s").

### 2.6 Bird Food Picker Sheet (`BirdFoodPickerSheet`)
Two layout variants gated by `#if os(watchOS)`:
- **watchOS**: a `List` with a "Bird Food Shop" link row, then two `Section`s ("Premium"/"Standard") each listing `BirdFoodCard`s.
- **iOS/iPad/mac**: a `GeometryReader`-sized `ScrollView` with a premium-food horizontal carousel (`ScrollView(.horizontal)` + `LazyHStack`, `.scrollTargetBehavior(.viewAligned)`, snap-scrolling card width computed as `min(width*0.7, 240) - 40`), then a "Standard" section with another horizontal carousel of non-premium foods.
- Both variants push `BirdFoodShop` via `navigationDestination(isPresented: $presentingBirdFoodShop)` when the "Bird Food Shop" link/row is tapped, and have a "Done" confirmation-action toolbar button that dismisses the sheet.
- **`BirdFoodCard`** (nested type): food image in a circular tertiary-fill background; if premium, a `BirdFoodQuantityBadge` (owned count) overlaid bottom-trailing; food name + 2-line (space-reserving) summary; an action button whose label/behavior depends on state:
  - Premium food the user owns 0 of → button reads "Shop" and sets `presentingBirdFoodShop = true` (routes into the paid store instead of selecting).
  - Premium food owned ≥1 → button reads "Use 1" (styled with a foreground pill showing quantity) and, on tap, assigns `backyard.birdFood = food`, sets `backyard.foodRefillDate = .now` (delayed 0.35s to let the button animate), then dismisses the sheet. **Note**: selecting/"using" premium food does not visibly decrement `ownedQuantity` in this code path — only StoreKit purchase/refund flows mutate `ownedQuantity` (see §3.5); "using" a food item is not consumption-tracked here.
  - Standard (free) food → button reads "Choose", same assign+refill+dismiss behavior.

### 2.7 Bird Food Shop (`BirdFoodShop`)
- watchOS: native `StoreView(ids:)` (system-provided catalog UI) driven by all bird-food product IDs; each row rendered via `BirdFoodProductIcon`. `.storeButton(.hidden, for: .cancellation)`.
- iOS/iPad/mac: custom `ScrollView` layout:
  - "Best value" hero: the largest-quantity `Nutrition Pellet` product shown via `ProductView(id:).productViewStyle(.large)` with a `bestBirdFoodValueBadge()` overlay ("Best Value ✨" capsule, tinted `premiumBirdFood`, offset below the icon).
  - "Other Bird Food" section header.
  - One `BirdFoodShopShelf` per premium food (sorted by descending `priority`; Nutrition Pellet=3, Nectar=2, Golden Acorn=default 1), each shelf a horizontally-scrolling, view-aligned-snapping row of that food's `orderedProducts` (ascending by quantity) rendered as native `ProductView`s wrapping `BirdFoodProductIcon`.
- Toolbar "Done" (image+label, title hidden) dismisses; absent on watch (uses system cancellation button instead).
- `BirdFoodProductIcon`: shows `food.image` for quantity 1, `food.alternateImage` (a distinct "Shop Alternates" asset bucket) for quantity >1 (i.e., box/bottle/pile art differs from the single-item art), padded more generously for multi-item Nectar specifically (`quantity>1 && id=="Nectar"` gets 18pt vs 10pt padding — a one-off visual tweak), circular tertiary-fill background.
- `BirdFoodQuantityBadge`: pill showing owned count, `.premiumBirdFood`-tinted, `@ScaledMetric` so it grows with Dynamic Type.

### 2.8 Backyard Birds Pass Shop (`BackyardBirdsPassShop`)
- Wraps the **system** `SubscriptionStoreView(groupID:visibleRelationships:)` (StoreKit 2's built-in subscription store UI) — this is largely host-OS chrome, not custom SwiftUI layout, but the app supplies marketing content and background:
  - `visibleRelationships` is `.upgrade` if already `.individual`/`.family` (shows only the upgrade path to Premium), else `.all`.
  - Custom marketing header (`PassMarketingContent`): the premium golden hummingbird bird (`ComposedBird`, tag `premiumGoldenHummingbird`) floating above title/description text over a blurred indigo capsule glow; title/description text swap between generic "Backyard Birds Pass" copy and "Premium" upgrade-specific copy depending on `showPremiumUpgrade`.
  - Background (`SkyBackground`, unavailable on watchOS): `BackyardSkyView` at a fixed dusk time (20:45) plus a blurred white "ground glow" ellipse and a hue-rotated cloud image — used as the `.containerBackground(for: .subscriptionStoreFullHeight)`.
  - `.subscriptionStoreControlIcon` swaps the plan icon per level (bird / person.3.sequence / wallet.pass) using `PassStatus(levelOfService:)`.
  - iOS additionally exposes `.storeButton(.visible, for: .redeemCode)` (offer-code redemption entry point — a StoreKit sheet, no custom UI).

### 2.9 Backyard Viewport (`BackyardViewport`, `BackyardViewportLayout`) — the core scene render
- A **custom `Layout`** (`BackyardViewportLayout`, conforms to SwiftUI's `Layout` protocol) positions differently-tagged child views (via `layoutValue(key:)`/`LayoutValueKey`) at hand-computed rects, purely from the proposed width:
  - `height` is a step function of `width` (0 / 50 / 120 / 180 / 240 at width breakpoints 0/150/300/600).
  - Derives `birdAssetSize`, `fountainAssetSize` (2×bird), `plantAssetSize` (1.5×bird), and rects for bird, fountain, silhouette, floor, and each leading/trailing plant (staggered by index for a faked depth offset).
  - Categorizes subviews by a `BackyardViewportContent` enum (`.silhouette`, `.floor`, `.plant(edge)`, `.fountain`, `.bird`) and places each bucket in its computed rect.
  - Bird's placed rect additionally shrinks/repositions based on `birdNaturalScale` (per-species natural size, e.g., swallow 0.83, hummingbird 0.76) so smaller species render smaller but pivot-correct.
- Content stack composed inside the layout: two mirrored `SilhouetteArtwork` images (building/tree silhouette variants, colorized by time-of-day), `FloorArtwork`, leading `PlantView`s, `FountainArtwork` (zIndex 5), the visiting bird as `ComposedBird` (zIndex 6, only if present), trailing `PlantView`s.
- `.flipsForRightToLeftLayoutDirection(true)` on the whole viewport (mirrors for RTL locales).
- `.colorMultiply(backyard.colorData.atmosphereTint.color)` tints everything by time-of-day atmosphere.
- Background = `BackyardSkyView` (gradient, see §6).
- Outline via `ContainerRelativeShape().strokeBorder(.separator)`, clipped to `.containerRelative`, `.compositingGroup()` (so blend modes/opacity apply as one flattened layer).
- **Bird arrival animation**: on `.task`, if `backyard.needsToPresentVisitor` (a bird is currently visiting but hasn't been "presented" yet), runs a scripted multi-step animated sequence (~8.5s total) that flies the bird in from off-screen: starts tiny/rotated/offset far right, springs to an overshoot position enlarged+rotated, springs to a settle position, flips horizontally (quick spring), springs to a mirrored perch position, flips back, springs to final centered rest position. Uses `Task.sleep` between `withAnimation(.spring(duration:bounce:))` calls to sequence beats. (Note: nothing in view code sets `presentingVisitor = true` after this sequence in the app UI — that flag is set by the data-generation layer/backend when a visit event begins.)
- `BackyardSkyView`, `BackyardSupplyGauge` and everything else (see §6) are pure BackyardBirdsData/LayeredArtworkLibrary-driven.

### 2.10 Birds grid (`BirdsNavigationStack`)
- `NavigationStack` → `ScrollView` → `LazyVGrid` (adaptive, min 110, top-aligned) of `BirdsSearchResults` rendering `BirdGridItem` per bird.
- `.searchable` + `.searchSuggestions` (species names only, when search empty) via `BirdsSearchSuggestions` — sorted unique species names as bold `Text` `.searchCompletion` suggestions.
- `BirdsSearchResults` queries all birds sorted by `creationDate`; filters client-side by `speciesName.contains(searchText)` when non-empty (no SwiftData predicate here, unlike Backyards search).
- `BirdGridItem`: `BirdIcon` (circular portrait, see §6) + species name + `bird.visitStatus.title` ("Not yet seen" or "Seen ‹relative time› ago").
- No detail/push screen exists for a bird in this codebase — tapping a bird card has no `NavigationLink`; it's browse-only. (`BirdSortCriteria` enum exists in the data layer — recentlyVisited/favoriteFood/dislikedFoods/favorites/species — but no UI in this checkout actually applies a sort picker to the Birds grid; it's unused API surface.)

### 2.11 Plants list (`PlantsNavigationStack`)
- Same shape as Birds: `NavigationStack` → `ScrollView` → adaptive `LazyVGrid` of `PlantsSearchResults` → `PlantSummaryRow`.
- `PlantSummaryRow`: `ComposedPlant` clipped to a circle over tertiary fill, with the plant's pot cropped by negative bottom padding (`-20`) so only the foliage top shows in the circular avatar, plus species name below.
- Search/suggestions mirror Birds exactly (species-name based). No plant detail screen exists.

### 2.12 Account (`AccountNavigationStack`)
- `Form` (`.formStyle(.grouped)`):
  - Header block: `BirdIcon` of the account's linked bird, display name with an inline Premium/Standard badge (`bird.fill`/`bird` icon in tint color, positioned via a custom `alignmentGuide`), join date ("Joined ‹Month DD, YYYY›").
  - Section 1 (pass status):
    - If `.individual`/`.family`: a callout nudging Premium upgrade with a "Check out Premium ›" borderless button.
    - If `.notSubscribed`: "Get Backyard Birds Pass" button (wallet.pass icon) → opens the pass sheet.
    - Else (already subscribed at any tier): "Your Backyard Birds Pass: ‹status›" button → iOS opens `.manageSubscriptionsSheet`; macOS opens the App Store account-subscriptions web URL.
    - Section footer shows the current pass status string when subscribed.
  - Section 2: `RestorePurchasesButton` — a "Restore Purchases" button that disables itself while in flight and calls `AppStore.sync()`.
  - Toolbar: pencil "Edit Account" button → `.sheet(EditAccountForm)`.
  - Empty state: `ContentUnavailableView("No Account Found", …)` if no `Account` model exists.
- `EditAccountForm`: a `Form` with Display Name and Email Address `TextField`s (autocapitalization/autocorrection/content-type tuned per platform), committing via `.onSubmit` (return-key on keyboard/enter), pre-filled via `.onAppear`. "Done" toolbar button dismisses. No client-side validation on the email field.

### 2.13 Watch-only screens

- **`BackyardTabView`**: a `.tabViewStyle(.carousel)` `TabView` with three pages — Summary, Content (Amenities), Visitors — swiped horizontally, each with a distinct `.containerBackground` gradient color (teal / green / — none set on Visitors, defaults to system).
- **`BackyardSummaryTab`**: current visiting bird portrait + name; a hard-coded "(2) others recently" line (not wired to real data — a stub/placeholder using literal `2`); Water/Sunflower-seeds labels as static icons (also not data-driven — hard-coded labels, unlike the live gauges used elsewhere).
- **`BackyardContentTab`** ("Amenities"): static "Food is running low"/"Water is okay" labels (hard-coded, not derived from `BackyardSupplies`), a "Refill" button that presents the same `BirdFoodPickerSheet` sheet used elsewhere, and two bottom-bar circular gauges (food/water) with **hard-coded** progress values (0.5, 0.25) and hard-coded remaining-time text — i.e. this tab is not wired to the live `Backyard` model's actual supply state; it's static/demo content.
- **`BackyardVisitorsTab`**: `List` — "Here Now" section (current bird icon+name, if any) and "Recent" section (`RecentBackyardVisitorsView`).

Note the internal inconsistency: the Summary/Content tabs on watch show static, non-live numbers while the phone/iPad/mac supply UI is fully live — this is a genuine quirk of the sample, not a design choice to preserve necessarily, but documented as observed behavior.

---

## 3. Core loops

### 3.1 The garden/backyard monitoring loop
Each `Backyard` tracks two independent consumable timers — food and water — each defined purely by two `Date`s (`foodRefillDate`, `waterRefillDate`) plus static duration constants in `BackyardSupplies`:
- Food: considered "low" 8h after refill, fully empty 9h after refill (`durationUntilLow` = 8h, `totalDuration` = 9h).
- Water: "low" 15h after refill, empty 16h after refill.
- No polling/timer loop exists in-app; remaining time is always derived on-demand as `Date.now.distance(to: backyard.expectedEmptyDate(for:))`, so gauges just re-evaluate whenever SwiftUI re-renders (driven by system clock views like `Text(date, style:)`/Gauges, or view appearance).
- `BackyardSupplyGauge` renders each as a `Gauge(value:in:).gaugeStyle(.accessoryCircularCapacity)` — for food, the label is the current food's image (with a `.scale+.opacity` transition and `.id(birdFood.id)` when food type changes); for water, a static droplet icon. Tint is a 2-color gradient (orange→pink for food, cyan→blue for water). The gauge's `layoutDirection` is deliberately forced to `.rightToLeft` (the "clock hand" reads backward visually since it's counting down / representing "how much is left"?) while its label content is forced back to the original layout direction so the food icon/text doesn't mirror.
- **Refill actions**: Water refills instantly and unconditionally via a single tap on its row (`backyard.waterRefillDate = .now`). Food refill requires going through the Bird Food Picker sheet and choosing/using a food (sets both `backyard.birdFood` and `backyard.foodRefillDate = .now`).
- **Widget resupply**: an App-Intents button inside the widget (`ResupplyBackyardIntent`) refills **both** food and water at once via `backyard.refillSupplies()` — a coarser, one-tap action not available inside the main app UI (in-app there is no "refill everything" button; only per-supply actions).

### 3.2 Bird visits — how they're "simulated"
There is no live/real-time simulation engine; all visits are **pre-generated fake data** created once at first launch (or whenever `DataGeneration.generateVisitorEvents` is (re-)invoked, which additionally happens whenever the subscription-status task resolves, since it needs to know whether to include early-access species):
- `BackyardVisitorEvent.generateHistoricalEvents`: for each of several "minutesAgo" checkpoints (5 through 300, step 40 — i.e. 8 waves), pairs each backyard with a shuffled bird and inserts a past visit of random 5–30 minute duration, seeded by `SeededRandomGenerator(seed: 1)`. Also calls `bird.updateVisitStatus(visitedOn:)` to stamp `lastKnownVisit` (only advances forward in time, never regresses).
- `BackyardVisitorEvent.generateCurrentEvents`: pairs each backyard with a bird starting **right now**, duration = `DataGenerationOptions.currentBirdsVisitingDuration` (1 hour, constant). The very first backyard gets special-cased to always host a **hummingbird** (`firstHummingbird`), and its `presentingVisitor` flag is set per `DataGenerationOptions.firstBackyardBirdStatus` (`.alreadyVisible` in the shipped default → shown as already there; `.fliesIn` → arrival animation plays via `BackyardViewport`'s `.task`; `.notVisiting` → skipped entirely). Every other backyard gets `presentingVisitor = true` immediately (no fly-in for them).
- `BackyardVisitorEvent.generateFutureEvents`: schedules more visits every 3 hours from 0–48h out (16 waves), 15–50 min duration each, seeded generator with seed 1.
- A `Backyard.currentVisitorEvent` computed property just finds the first visitor event whose `dateRange` contains `.now` — so as real wall-clock time passes, the "current" visitor silently changes to whichever pre-generated event's window now contains the current moment (no push/refresh mechanism forces the UI to update exactly at the boundary — it's recomputed lazily on next render).
- `Backyard.historicalEvents` = events whose `endDate < .now`, sorted most-recent-first — this is what "Recent Visitors" lists show.
- Includes/excludes "early access" bird species (chickadee is `isEarlyAccess: true`) depending on subscription tier (`Premium` unlocks early-access birds in visit generation).
- `BackyardSnapshot`/`Backyard.snapshots(through:total:)` is a separate mechanism (used only by the widget timeline, §5) that synthesizes a merged, prioritized timeline of "interesting moments" (visitor arrive/depart, day/night transitions, low-supply crossings) by walking future visitor events and hourly time-of-day boundaries, then merging near-duplicate events within a 5-minute window and keeping only the highest-`priority` dozen.

### 3.3 Bird detail
There is **no dedicated bird-detail screen** in this codebase — `BirdGridItem` is a terminal leaf (no `NavigationLink`). All bird info exposed anywhere is: species name/summary, visit status, palette-colored composed artwork, and (in the account/pass-shop contexts) its `tag` (used only to special-case the two named "hero" hummingbirds — `classicGreenHummingbird` for the free account's linked bird, `premiumGoldenHummingbird` for pass-shop marketing art).

### 3.4 Plants
Plants are purely decorative set-dressing: 3 leading + 3 trailing `Plant` instances per backyard, each referencing a `PlantSpecies` (5 species: Foxglove, Snake Plant, Colocasia, Kentia Palm, Alocasia) and a random `variant` index (variant art count varies per part, generally 4). There is no watering/growth/interaction loop for plants at all — the "Plants" tab is a pure species-encyclopedia grid with no per-instance state or actions. Individual (unassigned-to-backyard) `Plant`s are also generated (`Plant.generateIndividualPlants`, 1–3 per species) purely to populate the Plants tab even independent of backyard assignment.

### 3.5 The in-app purchase / subscription flow

**Products** (from `Misc/Store.storekit`, matching `BirdFood.generateAll`):

| Bird food | Products | Prices |
|---|---|---|
| Nutrition Pellet (priority 3, the "best value" hero) | `pellet.single` (qty 1, $1.99), `pellet.box` (qty 5, $3.99) | consumable |
| Nectar (priority 2) | `nectar.cup` (qty 1, $0.99), `nectar.bottle` (qty 5, $1.99) | consumable |
| Golden Acorn (priority default→1) | `acorns.individual` (qty 1, $0.99), `acorns.collection` (qty 5, $1.99) | consumable |
| Sunflower Seeds, Corn, Millet Seeds, Peanuts, Safflower Seeds, Sorghum Seeds | none — free/standard foods, no IAP | n/a |

Only Nutrition Pellet, Nectar, and Golden Acorn are "premium" (`isPremium = !products.isEmpty`); the other six are always-available standard foods with zero purchase gating. The player starts owning 3 Nutrition Pellets (`DataGenerationOptions.initialOwnedBirdFoods`).

**Subscription** ("Backyard Birds Pass", subscription group `6F3A93AB`, 3 auto-renewing monthly tiers, each with a 1-month free intro offer):
- Individual — `pass.individual`, $4.99/mo, not family-shareable — "Unlimited backyards and more decorations"
- Family — `pass.family`, $7.99/mo, family-shareable — "Share your pass with up to 6 accounts"
- Premium — `pass.premium`, $11.99/mo, family-shareable — "The full backyard experience"

`PassStatus` is `Comparable` (`notSubscribed < individual < family < premium`) and is derived each time from StoreKit's `Product.SubscriptionInfo.Status` array by picking the **highest-level** active status (family sharing can yield multiple statuses). `PassStatus.backyardLimit` is `8` when not subscribed and `nil` (unlimited) at any paid tier — this is the mechanic behind "Unlimited backyards"; **however**, no UI in this checkout actually enforces/reads this limit against the live backyard count (no gate blocks creating/viewing beyond 8; the offer card's presence is the only surface tied to `.notSubscribed`).

**What "premium" changes**:
1. Access to 3 premium consumable bird-food types (bought via IAP, tracked as an `ownedQuantity` ledger per `BirdFood`).
2. Early-access bird species inclusion (currently just the Chickadee, `isEarlyAccess`) in generated visitor events — gated on `passStatus == .premium` specifically (Individual/Family do not unlock this; only the top Premium subscription tier does).
3. Nominal unlimited backyards (`backyardLimit`), not actually enforced anywhere in this build.
4. Account screen surfaces a Premium/Standard badge on the linked bird's display name (tied to `Account.isPremiumMember`, a separate flag from `PassStatus` — hard-coded `true` for the seeded demo account, not derived from live subscription state).

**Purchase mechanics** (`BirdBrain`, a `@ModelActor actor` — the store's business-logic singleton, created once and started in `.backyardBirdsShop()`):
- On app launch: `observeTransactionUpdates()` (subscribes to `Transaction.updates` for cross-device purchase notifications) and `checkForUnfinishedTransactions()` (drains `Transaction.unfinished`).
- `process(transaction:)`: verifies the `VerificationResult`; unverified transactions are logged and dropped. For **consumable** products, looks up the matching `BirdFood`/`Product` pair, computes `delta = product.quantity * transaction.purchasedQuantity`, and either adds (`revocationDate == nil`) or subtracts (revoked/refunded) that delta from `birdFood.ownedQuantity`, then calls `transaction.finish()` and saves the model context. Non-consumable/subscription transactions are simply finished (their access is derived live from subscription status, not ledgered). A commented-out `finishedTransactions` de-dup mechanism is present but disabled ("SwiftData crashes when we do this") — i.e., the shipped code has a **known re-grant risk** if the same unrevoked transaction is processed twice (acknowledged in a code comment as a stubbed-out safeguard).
- `status(for:ids:)`: picks the highest `PassStatus` among all `Product.SubscriptionInfo.Status`, resolves the winning transaction (unverified → treated as not subscribed), and maps its product ID to a tier via `PassIdentifiers`.
- All of this is explicitly done **on-device only** — comments note that production apps should validate server-side; this sample trusts StoreKit's local verification.
- `PassStatusTaskModifier`/`subscriptionPassStatusTask()`: a view modifier applied at the shop-integration root that runs `.subscriptionStatusTask(for: passGroupID)`, funnels results through `BirdBrain.status(for:ids:)`, publishes `passStatus`/`passStatusIsLoading` into the environment, and — as a side effect — re-triggers `DataGeneration.generateVisitorEvents(includeEarlyAccessSpecies:)` every time the status resolves (success or failure) so the fake-data generator can decide whether to seed early-access species.
- `RestorePurchasesButton`: `AppStore.sync()` inside a detached `Task`, with a `isRestoring` flag disabling the button meanwhile.

---

## 4. Data model

Built on **SwiftData** (`@Model` classes) with all persistence declared in one `BackyardBirdsData` package. Container config: `DataGenerationOptions.inMemoryPersistence = true` — **the shipped sample never actually persists to disk**; every launch regenerates the whole world from scratch via seeded RNGs (deterministic within a run, but not saved across launches).

### Entities (`@Model` = SwiftData-persisted; struct = value type / not its own table)

- **`DataGeneration`** (`@Model`) — singleton bookkeeping row: `initializationDate`, `lastSimulationDate`, transient `includeEarlyAccessSpecies`. Gate for "have we generated the world yet" and "have we generated visitor events yet."
- **`Account`** (`@Model`) — `id`, `bird: Bird?` (the one linked "your bird"), `joinDate`, `displayName`, `emailAddress`, `isPremiumMember: Bool`. Exactly one is generated (`"Ravi Patel"`, joined 2023-06-05, premium=true, linked to the first-created bird).
- **`Backyard`** (`@Model`) — `id`, `name`, `waterRefillDate`, `foodRefillDate`, `creationDate`, `presentingVisitor: Bool`, `isFavorite: Bool`, `timeIntervalOffset` (a fake "time of day" that's independent of real time — offsets a virtual 24h clock), `birdFood: BirdFood?` (currently assigned food), `visitorEvents: [BackyardVisitorEvent]`, `leadingPlants`/`trailingPlants: [Plant]` (SwiftData inverse relationships from `Plant.backyard`), variant indices for floor/fountain/silhouette-left/silhouette-right/foreground-plant-left/right (currently unused foreground-plant variants — declared but not read anywhere in the viewport). Computed: `currentVisitorEvent`, `hasVisitor`, `needsToPresentVisitor`, `historicalEvents`, `colorData` (time-of-day-interpolated color set), `expectedEmptyDate`/`lowSuppliesDate`/`refillDate` per `BackyardSupplies` case, `refillSupplies()`. 5 backyards generated: "Bird Springs" (favorite, hard-coded Sunflower Seeds, 8h offset), "Feathered Friends" (12h), "Calm Palms" (20h), "Chirp Center" (21h), "Quiet Haven" (6h) — the latter four random per a seeded generator (seed 8).
- **`BackyardVisitorEvent`** (`@Model`) — `id`, `backyard: Backyard?`, `bird: Bird?`, `startDate`, `endDate` (derived from `startDate + duration` at init), `duration`. `dateRange` computed convenience.
- **`Bird`** (`@Model`) — `id`, `creationDate`, `species: BirdSpecies?`, `favoriteFood: BirdFood?`, `dislikedFoods: [BirdFood]`, `colors: BirdPalette` (struct, see below), `tag: String?` (raw `BirdTag`), `lastKnownVisit: Date?`, `backgroundTimeInterval: Double` (fixed "preferred" time-of-day used to render its portrait background in `BirdIcon`). Computed `visitStatus: BirdVisitStatus` (`.never` / `.recently(date)`). ~35–50 birds generated total (2 named/tagged hummingbirds + 1 of each of the 6 species + 5–7 more random instances per species, seed 1).
- **`BirdSpecies`** (`@Model`) — `id` (maps 1:1 to `BirdSpeciesInfo` raw values `"Bird 1"`…`"Bird 6"`), `naturalScale` (relative render size), `isEarlyAccess: Bool`, `parts: [BirdPart]` (struct list — anatomy layers to composite), cascade-deleting inverse relationship to its `birds`. 6 species: Swallow (0.83 scale), Dove (1.0), Chickadee (0.71, early-access), Petrel (1.0), Cardinal (1.0), Hummingbird (0.76, animated 2-frame wings front+back).
- **`BirdFood`** (`@Model`) — `id`, `name`, `summary`, `priority: Int`, `products: [BirdFood.Product]` (struct: `id`, `quantity` — the StoreKit product IDs), `ownedQuantity: Int` (mutated only by StoreKit transactions). Computed `isPremium`, `orderedProducts` (ascending by quantity), `image`/`alternateImage` (asset-catalog lookups by ID).
- **`Plant`** (`@Model`) — `id`, `creationDate`, `species: PlantSpecies?`, `backyard: Backyard?`, `variant: Int`.
- **`PlantSpecies`** (`@Model`) — `id` (maps to `PlantSpeciesInfo`), `parts: [PlantPart]` (struct — e.g. pot + variant-art plant body), cascade-deleting inverse to `plants`.

### Value/struct types (not SwiftData entities)
- `BirdPalette` — 5 `ColorData` slots (body/wing/beak/belly/accent) with a lookup-by-`BirdPartColorStyle` accessor; a curated static palette table per species (7 palettes each for swallow/dove/chickadee/petrel/cardinal, 6 for hummingbird), randomly assigned at generation time.
- `ColorData` — HSB triple + `Color` conversion, `interpolate`, `darken`, and pastel/vibrant/white helper constructors; used for both bird palettes and time-of-day sky/atmosphere colors.
- `BirdPart` / `PlantPart` — anatomy/foliage layer descriptors: image-name suffix, color style, pivot point, flags (`isBody`/`isEye`/`isWing`), optional flipbook frame count (wings) or variant count (plant foliage).
- `BackyardTimeOfDay` (enum: night/sunrise/morning/afternoon/sunset) — derived purely from an hour bucket of a `TimeInterval`; carries an SF Symbol (`moon`/`sunrise`/`sun.min`/`sun.max`/`sunset`), an optional `colorSchemeOverride` (forces `.dark` at night), and a `colorData` (per-time-of-day sky-gradient-start/end, silhouette tint, atmosphere tint — all hand-authored HSB values). `BackyardTimeOfDayColorData.colorData(timeInterval:)` interpolates hour-to-hour for smooth transitions.
- `BackyardSnapshot` — ephemeral (non-persisted) projection used only for widget timelines: backyard + optional visiting bird/duration + time interval + date + a `Set<NotableEvent>` (significant time-of-day / low-supply-severity / visitor-arrive / visitor-depart), each with a numeric `priorityValue` used to keep the most interesting dozen snapshots.
- `BackyardSupplies` (enum: food/water) — the two duration-constant tables described in §3.1.
- `FountainVariant` (enum: terracotta/stone/marble) — declared in the data layer but the actual `Backyard.fountainVariant` field is a raw `Int` index into `LayeredArtworkLibrary`'s `variants` array rather than this enum — i.e., the enum exists as documentation/typed API but isn't the type actually stored.
- `BirdEatFoodResult` — a would-be reaction-computation type (favorite/dislike/neutral/enjoy → title string + SF Symbol) that appears to be intended for a "feed and see reaction" moment, but nothing in the UI constructs one — it's unused, dead API in this checkout (the happiness indicator toast text is hard-coded, not built from this type).
- `BirdSortCriteria` (enum) — same story: fully localized titles defined, but no sort picker UI consumes it.
- `PassIdentifiers` — environment-injected struct of the subscription group ID + the three product IDs, defaulted to the real Store.storekit IDs.

### Generated vs. persisted
Nothing survives an app relaunch (`inMemoryPersistence = true`): every cold start re-runs the full seeded generation pipeline (`DataGeneration.generateAllData` → foods → species → individual plants → birds → backyards → account, then, once subscription status resolves, visitor events: historical → current → future). All RNG is seeded (`SeededRandomGenerator`, wrapping `srand48`/`drand48` with small integer seeds like 1, 4, 8) so the *shape* of a fresh run is stable, but wall-clock-relative fields (visit windows, refill dates) are always anchored to `Date.now` at generation time.

---

## 5. Host-OS-only surfaces

These have **no in-app UI equivalent** — reachable only through system surfaces (Home/Lock Screen, Watch Face, App Store subscription management), backed by the same SwiftData container via an App Group (`group.example.apple-samplecode.Backyard-Birds`).

### 5.1 WidgetKit widget (`Widgets` target, `BackyardWidget` in `WidgetsBundle`)
- Families: `.accessoryRectangular` everywhere (works on watch complications and iOS Lock Screen), plus `.systemSmall/.systemMedium/.systemLarge` on iOS and macOS (home screen / desktop widgets). Not offered on watchOS home screen beyond the rectangular complication.
- Configured via **`BackyardWidgetIntent`** (an `AppIntentConfiguration`, i.e. an interactive widget users configure by long-press/edit): a `backyards` parameter (`BackyardWidgetContent`: all / favorites / specific) plus an optional `specificBackyard: BackyardEntity?`. A dynamic `parameterSummary` shows the backyard picker field only when "Specific" is chosen. `BackyardEntityQuery` resolves/suggests backyards straight from the shared SwiftData container.
- `BackyardSnapshotTimelineProvider`: builds its own throwaway `ModelContext` off `DataGeneration.container`, re-running `generateAllData` on init (so the widget's fake world is generated independently from the app's, sharing the App Group's on-disk store — but since persistence is in-memory in this config, widget and app instances are actually **separate in-memory worlds** unless `inMemoryPersistence` were flipped to `false`). Provides `placeholder`, `snapshot(for:)` (single current-moment snapshot), and `timeline(for:)` (a `Backyard.snapshots(through: now+36h)` sequence with `.atEnd` refresh policy — i.e. iOS reloads the widget once the last precomputed snapshot's date passes). Also declares `recommendations()` for the widget gallery (All Backyards / Favorite Backyards).
- `BackyardWidgetView` → `BackyardSnapshotWidgetView`: header (fountain icon, backyard name, time-of-day SF Symbol with a scale+opacity transition), a `Spacer`, the visiting bird (full-color `ComposedBird` in `.fullColor` rendering mode, or a flattened tint-only `VibrantBird` in accented/monochrome widget rendering modes — e.g. Lock Screen), and a bottom region that swaps between three mutually exclusive states by priority: low-supply detail (with an **interactive "Refill Water" button wired to the `ResupplyBackyardIntent` App Intent** — this is the one genuinely interactive, no-app-launch-required affordance in the whole app), an arrival message, or default food/water gauges (`Grid` of two `Gauge`s). Forces the environment `colorScheme` to `.dark` at night regardless of system setting. Background is `BackyardSkyView` at the snapshot's time interval, dimmed slightly in dark mode.
- **`ResupplyBackyardIntent`** (App Intent, button-only — no in-app control does the equivalent "refill both at once" action): looks the backyard up fresh from the shared container by ID and calls `backyard.refillSupplies()` (food **and** water together), then saves. This is strictly more convenient than any in-app control, which only refills one supply at a time.

### 5.2 watchOS app (`Watch` target)
Effectively a fully separate lightweight app reusing the same shared packages, described in §1.3/§2.13. Notable watch-only elements:
- `.tabViewStyle(.carousel)` paging inside a backyard (Digital Crown/swipe navigation) — a UI shape with no iOS/mac counterpart.
- `.listStyle(.carousel)` on the backyard list.
- Static/hard-coded numbers in the Summary and Content tabs (documented in §2.13) — the watch app's per-backyard "amenities" screen isn't wired to live model state the way the phone/iPad/mac equivalents are.
- Accessory-rectangular widget family (complications) is the watch face's twin of the phone/mac widgets — no separate watch-specific widget code exists; it's the same `BackyardWidget` target with family filtering.

### 5.3 StoreKit system sheets (host-rendered, not custom SwiftUI)
- `SubscriptionStoreView` (pass shop) — Apple's subscription marketing/purchase UI; the app only supplies marketing content/background/icon, not the purchase flow chrome itself.
- `StoreView`/`ProductView` (bird food shop, watch and iOS/mac respectively) — same relationship: native purchase buttons/pricing/loading states are system-rendered.
- `.manageSubscriptionsSheet` (iOS) — native subscription management (cancel/change plan), no custom UI, no in-app equivalent screen.
- `.storeButton(.visible, for: .redeemCode)` (iOS pass shop) — native offer-code redemption sheet.
- Restore Purchases has no visual sheet (it's a silent `AppStore.sync()` call), but is included here because its effect (re-driving `Transaction.updates`) is host-managed.

---

## 6. Notable UI details

### 6.1 Composed/layered art (image compositing, not procedural drawing)
- **`ComposedBird`** (LayeredArtworkLibrary): for each `BirdPart` in the species definition, loads an asset named `"<speciesID>/<partName>"` (or `"<speciesID>/<partName>1"` for the first frame of any flipbook-animated part, e.g. hummingbird wings — though the frame-advance logic `frameIndex(date:frameCount:)` exists but is **never called**, so wings are statically frame-1 despite the flipbook data model existing for animation), scales to fit, and `.colorMultiply`s it by the bird's `BirdPalette` color for that part's `colorStyle`. All parts stack in a `ZStack`; the whole bird flips horizontally via `.scaleEffect(x:)` based on a `HorizontalEdge direction` parameter, and respects RTL layout mirroring. This is a from-scratch, per-instance colorized bird built from ~6–8 grayscale/maskable PNG layers.
- **`ComposedPlant`**: same idea, one asset per `PlantPart`, appending `" <variant+1>"` to the part name when the part has variants — no color multiplication (plants use pre-colored art per variant, not palette tinting).
- **`VibrantBird`**: a single flattened, pre-rendered "Vibrant <speciesID>" image asset (used only where a colorized composited bird would be too visually heavy or where widget rendering mode forces monochrome/accent — see §5.1) rather than the multi-layer composite.
- **`FloorArtwork`/`FountainArtwork`/`SilhouetteArtwork`**: simple variant-indexed `Image` lookups into fixed static arrays (4 floor variants; 3 fountain variants — terracotta/stone/marble; 10 silhouette variants — 5 buildings + 5 tree clusters).
- **`BirdIcon`** (BackyardBirdsUI): wraps `ComposedBird` in a padded circular portrait with its own mini sky background (`BackyardSkyView` at the bird's fixed `backgroundTimeInterval`, 0.8 opacity, tertiary fill behind that), a hairline tertiary border, and `.compositingGroup()` for correct blend-mode flattening — this is the canonical "avatar" treatment reused across bird grid, account header, visitor rows, and pass-shop marketing.

### 6.2 Custom Layout
- `BackyardViewportLayout` is the one genuine custom `Layout` conformance in the app (see §2.9) — hand-computed placement math (no auto-layout/stacks) driving a believable "scene" composition (silhouette horizon line, floor plane, side-staggered plants suggesting depth, centered fountain, bird perched above it) purely from available width, with a `LayoutValueKey`-tagged content-role system so the same layout works whether it's rendering a tiny list-row viewport or a full detail-view hero.

### 6.3 Sky & color system
- `BackyardSkyView` is a two-stop `LinearGradient` (top-to-bottom) computed from `BackyardTimeOfDayColorData.colorData(timeInterval:)`, which linearly interpolates hue/saturation/brightness between the current and next named time-of-day bucket (night/sunrise/morning/afternoon/sunset) based on fractional progress through the current hour — i.e. the sky **continuously** shifts hue rather than snapping between 5 discrete looks.
- Every backyard also multiplies its whole viewport by an `atmosphereTint` color (near-white most of the day, a cool blue-violet tint at night) and tints its two silhouette layers by a `silhouette` color — so night scenes read as a cohesive cool-toned scene rather than just a darker sky behind unchanged foreground art.
- `BackyardTimeOfDay.colorSchemeOverride` forces the widget (and only the widget) into dark mode's color scheme at night regardless of system appearance, so text/material contrast stays legible against a dark sky background.
- `VibrantShapeStyle`/`VibrantlyBlendedShapeStyle` (BackyardBirdsUI `Styles.swift`): a reusable "vibrant" text/icon treatment — resolves to black (light mode) or white (dark mode) at a given opacity, blended with `.plusDarker`/`.plusLighter` blend mode respectively — used throughout the widget's secondary/tertiary text so it reads against the arbitrary live sky-gradient background without a fixed color choice.

### 6.4 Animation & transition inventory
- Bird arrival: multi-step scripted `withAnimation(.spring(duration:bounce:))` sequence with `Task.sleep` pacing (§2.9) — not a single spring but a hand-authored flight path.
- Favorite star toggle: `.contentTransition(.symbolEffect(.replace.upUp / .replace.downUp))` — SF Symbols' built-in morph transition, direction depends on whether the star is being filled or unfilled.
- Food-gauge icon swap: `.transition(.scale(scale: 0.5).combined(with: .opacity))` + `.id(birdFood.id)` forces a full transition replay whenever the assigned food changes.
- Happiness indicator (`BirdFoodHappinessIndicator`): heart icon and text callout each fade/scale in and out on independent timers via a scripted `Task` (`showingHeart` for ~7.5s total, `showingCallout` for a 4s window nested inside it), triggered by `.onChange(of: backyard.foodRefillDate)`, auto-dismissed by the parent view after a flat 8s delay.
- `NewBirdIndicator`: `PhaseAnimator` over two phases (idle/scale) — a self-looping pulse (scale 1↔1.2, slight rotation, background opacity 0.5↔1.0). (Currently unreachable in shipped UI — gated behind an always-false flag, §2.1.)
- Widget bird transitions: `.asymmetric(insertion: .offset(x:100), removal: .offset(x:-100))` combined with scale+opacity — birds "fly across" when the widget's timeline advances to a new visitor.
- Widget low-supply/arrival banners animate in via `.transition(.offset(y:50).combined(with:.scale(0.9)).combined(with:.opacity))` or plain `.scale.combined(with:.opacity)`.

### 6.5 Contextual/system interactions
- `.swipeActions` "Dismiss" on the pass offer card row (`BackyardList`).
- `.hoverEffect(.highlight)` on backyard-supply rows for non-macOS pointer/remote input (tvOS/iPadOS trackpad-and-Siri-Remote affordance) — notable since the package targets include tvOS in its platform list even though no tvOS-specific view code exists; this appears to be latent/forward-compatible styling rather than an actual tvOS-tuned experience.
- `ContainerRelativeShape()` used repeatedly (viewport border stroke, bird-icon border) so the stroke shape always matches whatever `.containerShape` the parent declared, rather than hard-coding a corner radius per usage site.

### 6.6 Accessibility & Dynamic Type
- `@ScaledMetric` used for the happiness-indicator's fixed height and the bird-food quantity badge's padding/min-width, so both scale with Dynamic Type rather than staying pixel-fixed.
- `BestBirdFoodValueBadge` explicitly caps itself at `.dynamicTypeSize(...(.xLarge))` and `.fixedSize()` — a deliberate exception where a decorative badge refuses to grow past a ceiling size to avoid overwhelming the hero product card.
- Icon-only labels throughout use `Label(...)` + `.labelStyle(.iconOnly)` (never a bare `Image`) so VoiceOver still reads a real accessibility label (e.g. "Favorite", "Choose Food", "Refill Water") even though only the SF Symbol is visible.
- `.symbolVariant(.fill)` is applied instead of maintaining two separate icon names for filled/unfilled logical states (favorite star, pass-status section icons).
- Text summaries deliberately `.lineLimit(2, reservesSpace: true)` (bird-food card) so layout doesn't jump between 1-line and 2-line summaries — a reflow-stability choice, not an accessibility feature per se, but relevant to Dynamic Type/localization robustness.

### 6.7 Localization
- Every user-facing string in the shared packages (`BackyardBirdsData`, `BackyardBirdsUI`) explicitly routes through `String(localized:table:bundle:comment:)` with a **per-feature-area string table** (`"Birds"`, `"Backyards"`, `"BirdFood"`, `"PlantSpecies"`) rather than one monolithic Localizable file — mirrored by dedicated `.xcstrings` catalogs (`Birds.xcstrings`, `Backyards.xcstrings`, `BirdFood.xcstrings`, `PlantSpecies.xcstrings` inside `BackyardBirdsData`, plus general `Localizable.xcstrings`/`InfoPlist.xcstrings` per app target: `Multiplatform`, `Watch`, `Widgets`, and one shared one in `BackyardBirdsUI`). Every localized call site carries a `comment:` describing the interpolated variables' meaning for translators (e.g. "The variable is a shorthand formatted duration...").
- Bidirectional layout is explicitly handled, not just tolerated: `ComposedBird`/`VibrantBird`/`BackyardViewport` all call `.flipsForRightToLeftLayoutDirection(true)` on top of their manual `.scaleEffect(x:)` mirroring, and `BackyardSupplyGauge` deliberately fights the ambient layout direction (forces RTL for the gauge arc itself, then forces the original direction back just for its label) so the capacity ring always reads the same visual "draining" direction regardless of locale while the food-name/icon label stays correctly oriented.
- Currency/quantity/time strings are formatted via system formatters (`Duration.TimeFormatStyle`/`UnitsFormatStyle`, `Date.FormatStyle`, `.formatted(.relative(...))`), never hand-built strings — so plurals, units, and calendars localize automatically through Foundation rather than the app's own string interpolation.

---

## SwiftUI framework-capability index (where each is used)

| Capability | Where |
|---|---|
| `NavigationSplitView` | `ContentView` (iPad/mac), `Watch/ContentView` |
| `TabView` (screen-level) | `AppTabView` (iPhone) |
| `TabView` `.tabViewStyle(.carousel)` | `Watch/BackyardTabView` |
| `NavigationStack` + `navigationDestination(for:)` | `BackyardNavigationStack`, `Birds/Plants/AccountNavigationStack`, `Watch/ContentView`, `BirdFoodPickerSheet`'s shop push |
| `navigationDestination(isPresented:)` | `BirdFoodPickerSheet` → `BirdFoodShop` |
| Custom `Layout` protocol | `BackyardViewportLayout` |
| `LayoutValueKey` | `BackyardViewportContentKey` |
| `.searchable` / `.searchSuggestions` / `.searchCompletion` | Backyards, Birds, Plants grids |
| `@Query` (SwiftData) | pervasive — every list/grid/search-results/offer-card view |
| `#Predicate` | `BackyardsSearchResults`, `BirdFoodPickerSheet`-adjacent queries, widget `BackyardEntityQuery`, `BackyardBirdsPassOfferCard`/`BackyardBirdsPassShop` bird-tag lookups |
| `@ModelActor` | `BirdBrain` |
| `Gauge` / `.gaugeStyle(.accessoryCircularCapacity)` | `BackyardSupplyGauge`, watch bottom-bar gauges, widget gauges |
| `PhaseAnimator` | `NewBirdIndicator` |
| `.spring(duration:bounce:)` sequenced animation | `BackyardViewport` bird-arrival flight |
| `.contentTransition(.symbolEffect(...))` | favorite-star toggle |
| `ContentUnavailableView` | detail-column empty state, account-missing state, watch detail placeholder, `ModelPreview` preview-load-failure state |
| `SubscriptionStoreView` | `BackyardBirdsPassShop`, watch pass sheet |
| `StoreView` / `ProductView` | `BirdFoodShop` (watch / non-watch respectively) |
| `.subscriptionStatusTask` | `PassStatusTaskModifier` |
| `.manageSubscriptionsSheet` | `AccountNavigationStack` (iOS) |
| `.onInAppPurchaseCompletion` | `Watch/ContentView` |
| StoreKit 2 `Transaction.updates` / `.unfinished` / `VerificationResult` | `BirdBrain` |
| WidgetKit `AppIntentTimelineProvider`, `Timeline`, `TimelineEntry` | `BackyardSnapshotTimelineProvider` |
| `AppIntentConfiguration` / `WidgetConfigurationIntent` | `BackyardWidget`, `BackyardWidgetIntent` |
| `AppEntity` / `EntityQuery` | `BackyardEntity`, `BackyardEntityQuery` |
| Interactive widget `Button(intent:)` (App Intents in widgets) | `ResupplyBackyardIntent` button in `BackyardWidgetView` |
| `.containerBackground(for:)` | widget background, watch tab backgrounds, pass-shop `.subscriptionStoreFullHeight` background |
| `widgetRenderingMode` environment | `BackyardWidgetView` (full-color vs. vibrant/accented bird rendering) |
| `.compositingGroup()` | `BackyardViewport`, `BirdIcon` |
| `ContainerRelativeShape()` / `.containerShape` | viewport border, bird-icon border, grid-item hit shapes |
| `GeometryReader` | `BirdFoodPickerSheet` (non-watch layout sizing) |
| `.scrollTargetBehavior(.viewAligned)` / `.scrollTargetLayout()` | horizontal food carousels, `BirdFoodShopShelf` |
| `.contentMargins(_:for:)` | most `ScrollView`s |
| `@ScaledMetric` | `BirdFoodHappinessIndicator`, `BirdFoodQuantityBadge` |
| `.dynamicTypeSize(...)` cap | `BestBirdFoodValueBadge` |
| `ShapeStyle` custom conformances (`VibrantShapeStyle`, `VibrantlyBlendedShapeStyle`) | `BackyardBirdsUI/Styles.swift`, used in widget text |
| `UITraitBridgedEnvironmentKey` | `PrefersTabNavigationEnvironmentKey` |
| `.flipsForRightToLeftLayoutDirection` | bird/plant/viewport art |
| `Duration` / `Duration.TimeFormatStyle` / `.UnitsFormatStyle` | supply remaining-time labels, widget remaining-time labels |
| `String(localized:table:bundle:comment:)` + `.xcstrings` catalogs | all shared-package strings |
| `#Preview` macro | present in nearly every view file for Xcode canvas previews |

Not found anywhere in this checkout: `Charts` framework, `TimelineView`, `matchedGeometryEffect`, `ScrollTransition`/`.scrollTransition` (a stray unused `ScrollTransitionPhase` extension exists in `RecentBackyardVisitorsView.swift` but nothing calls `.scrollTransition` itself — dead code), Core Data (SwiftData only), CloudKit sync, `NavigationSplitView` column customization/collapsing APIs, `Canvas`/`SwiftUI.Path` custom drawing (all art is composited pre-made image assets, never drawn).
