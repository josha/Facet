# Food Truck — Behavioral Feature Inventory

Source: Apple's "Food Truck: Building a SwiftUI multiplatform app" sample (app target `Food Truck`, package `FoodTruckKit`, extension `Widgets`). Compiled from source reading only, for a clean-room reimplementation study. All descriptions are behavioral paraphrases, not code copies.

Bundle ID root: `com.example.apple-samplecode.Food-Truck`. Platforms: iOS 16.4+, macOS 13.3+ (Catalyst 16.4+), and a Widgets/Live-Activity extension that also targets watchOS accessory families in places. Swift tools 5.7.

---

## 1. App structure & navigation

### Entry point
- `FoodTruckApp` (`App/App.swift`) is the single `@main` entry point shared by iOS and macOS. It owns two long-lived `@StateObject`s: `FoodTruckModel` (all business data) and `AccountStore` (sign-in state), constructed once and passed down.
- Root scene is a `WindowGroup` containing `ContentView`. On macOS, `.defaultSize(width: 1000, height: 650)`.
- macOS only: a second scene, `MenuBarExtra`, shows a menu-bar icon ("box.truck" symbol, label "Food Truck") whose popover is a `.window`-style `ScrollView` with a reduced-size `BrandHeader` and placeholder text — a stub/vestigial surface, not a fully built feature.

### Root navigation shell (`ContentView`)
- A single `NavigationSplitView` wraps the whole app: sidebar = `Sidebar`, detail = a `NavigationStack` (bound to a `NavigationPath`) whose root is `DetailColumn`.
- SwiftUI's `NavigationSplitView` automatically collapses to a stack-based push interface on compact-width iOS (iPhone) and stays a persistent two/three-pane split on iPad regular width and macOS — no manual per-platform branching is needed for that adaptation; the code only special-cases behavior, not the container.
- Sidebar selection is `@State var selection: Panel?` (typed enum, not raw string) shared via binding; changing `selection` triggers `.onChange` that clears the detail `NavigationPath` (`path.removeLast(path.count)`) so switching sidebar sections always resets any pushed sub-navigation.
- macOS: `.frame(minWidth: 600, minHeight: 450)` on the whole `ContentView`.
- iOS only:
  - Watches `scenePhase`; when it becomes `.active`, re-registers `StoreMessagesManager.shared.displayAction` from `\.displayStoreKitMessage` so StoreKit's system messages (billing issues, etc.) are re-armed each time the window is foregrounded.
  - Listens for a `StoreMessagesDeferredPreferenceKey` preference (set by any subview via `.storeMessagesDeferred(true)`, e.g. the donut editor) and forwards it into `StoreMessagesManager.shared.sensitiveViewIsPresented`, so StoreKit's interstitial messages are suppressed while sensitive UI (donut editing) is on screen.
  - `.onOpenURL` deep-link handler: any incoming URL is logged, the last path component is treated as an order number, and the app force-navigates to Truck → Orders → that order's detail by rebuilding the `NavigationPath` inside a `Task` (`selection = .truck`, then push `.orders`, then push the synthesized `"Order#<n>"` id string). This is also the target of `widgetURL` from the Live Activity/Dynamic Island (`foodtruck://order/<id>`).

### Sidebar (`Sidebar.swift`)
- A single `List(selection: $selection)` with `NavigationLink(value:)` rows (value-based navigation, no manual push calls):
  - Truck (icon `box.truck`)
  - Orders (`shippingbox`)
  - Social Feed (`text.bubble`)
  - Account (`person.crop.circle`) — **only compiled under the `EXTENDED_ALL` build flag**; absent from the default target.
  - Sales History (`clock`)
  - Section "Donuts": Donuts (custom `Image.donutSymbol`), Donut Editor (`slider.horizontal.3`), Top 5 (`trophy`)
  - Section "Cities": one row per `City.all` (Cupertino, San Francisco, London), icon `building.2`, tinted `.secondary` via `.listItemTint`
- `navigationTitle("Food Truck")`; macOS gets a fixed column width via `.navigationSplitViewColumnWidth(min: 200, ideal: 200)`.
- The `Panel` enum is the sole navigation-value type (`truck`, `socialFeed`, `account` (gated), `orders`, `salesHistory`, `donuts`, `donutEditor`, `topFive`, `city(City.ID)`) — City is an associated-value case so all three cities share one enum case.

### Detail column (`DetailColumn.swift`)
- A `switch selection ?? .truck` that renders the matching screen; defaults to `TruckView` when nothing is selected. This is the only place screen routing is centralized for the sidebar-driven path.

### Per-platform / size-class differences found throughout
- `WidthThresholdReader` (`App/General/WidthThresholdReader.swift`): a reusable `GeometryReader`-based helper that reports `isCompact` by combining three signals — iOS horizontal size class == `.compact`, Dynamic Type size ≥ a threshold (default `.xxLarge`), and raw width < a threshold (default 400pt, callers override, e.g. Truck cards use 520). This is the app's general-purpose "should I use the phone-narrow layout" primitive, used by `TruckView`, `DonutEditor`, `SocialFeedView`.
- `TruckView` grid: compact → cards stacked vertically (Orders, Weather, Donuts, Social Feed in one column via `Grid` rows of 1); regular → a 2×2 `Grid` (`GridRow`s of `[orders, weather]` / `[donuts, socialFeed]`).
- Card headers (`CardNavigationHeader`) choose between a real `NavigationLink` (iPad/macOS or push-based iPhone contexts) and a `Button` that sets a `Binding<Panel?>` selection directly — chosen per-call via `TruckCardHeaderNavigation` (`.navigationLink` vs `.selection(binding)`). `TruckView.cardNavigation` picks `.navigationLink` when `sizeClass == .compact` on iOS (because iPhone Truck view is pushed inside a `NavigationStack`, so a real push is correct) and `.selection` otherwise (because iPad/macOS Truck view lives in the split-view detail column, so tapping a card should update sidebar selection rather than push).
- `OrdersView`: compact iOS → a sectioned `List` (New/Preparing/Ready/Completed); iPad/macOS or regular iOS → `OrdersTable` (a `Table` with sortable columns). Toolbar-driven bulk actions (View Details / Complete) only show in table mode; list mode instead gets iOS `EditButton`/`Select` affordances for multi-select.
- `DonutEditor`: macOS uses `HSplitView` (drag-resizable) with donut viewer + `Form(.grouped)` side panel (fixed 300–350pt); iOS/iPadOS uses `WidthThresholdReader` to switch between a single scrolling `Form` (compact) and a fixed `HStack` split with a 350pt-wide form (regular).
- `DonutGallery`: `layout` state toggles between an adaptive `LazyVGrid` icon grid and a `Table` (name + thumbnail only); thumbnail/cell sizes shrink under compact size class, XXXLarge Dynamic Type, or narrow width (`DonutGalleryGrid.useReducedThumbnailSize`).
- `SubscriptionStoreView`: macOS gets a fixed vertical layout (header banner over cells over a bottom purchase bar); iOS uses a `GeometryReader` to pick portrait (same vertical stack) vs landscape (side-by-side header | cells+purchase).
- `SegmentedGauge` (widgets) explicitly reads `\.layoutDirection` and swaps leading/trailing corner rounding for right-to-left locales (the app ships an `ar.lproj` Arabic localization in three separate resource bundles: `App`, `FoodTruckKit/Resources`, `Widgets`).
- Account screen (`AccountView`): iOS routes "In-app purchase support" through a `NavigationLink`/`navigationDestination`; macOS instead shows a `LabeledContent` with an inline "Restore missing purchases" button and constrains the form to `maxWidth: 500`.

---

## 2. Screen-by-screen behavior

### 2.1 Truck dashboard (`TruckView`)
Landing page reached by default. Structure: `WidthThresholdReader` → `ScrollView(.vertical)` → `VStack` containing:
1. **`BrandHeader`** — an animated hero banner (see §7 for the custom `Canvas`/`Layout` mechanics). `animated: true` by default here (continuously running via `TimelineView(.animation)`).
2. A `Grid` of four cards (Orders, Weather, Donuts, Social Feed), 12pt spacing, laid out 1-column (compact) or 2×2 (regular) as above. The whole grid is clipped to a continuous 12pt-corner-radius container shape and capped at `maxWidth: 1200`.

Navigation destinations are declared once via `.navigationDestination(for: Panel.self)` on `TruckView` itself (Orders/Donuts/SocialFeed/City), meaning pushes originating from the truck cards land in the same `NavigationStack`.

**TruckOrdersCard** (`Cards/TruckOrdersCard.swift`):
- Header = `CardNavigationHeader` to `.orders`, label "New Orders" / `shippingbox`.
- Body: a custom `Layout` called `HeroSquareTilingLayout` showing up to 5 of the most-recent orders reversed (`orders.reversed().prefix(5)`) — subview 0 becomes one large "hero" square occupying the left half of the available width/height; subviews 1–4 tile as four small squares in the right half (2×2). Each tile is a `DonutStackView` (see §2.3) on a rounded-rect tinted background with a hairline stroke. Insertion/removal use an **asymmetric transition**: new orders slide in from the left combined with opacity fade-in; removed orders scale+fade out.
- Footer row: shows the most recent order's id, the donut glyph, and its total-sales count, dimmed to `.secondary`/regular weight normally.
- **Pulse animation**: `.onChange(of: orders.last)` spawns a background `Task` that sleeps 0.1s, then on the main actor animates (`.spring(response:0.25, dampingFraction:1)`) the footer text to bold/primary (`pulseOrderText = true`), holds for 1s, then springs back to secondary/regular. `.contentTransition(.interpolate)` smooths the accompanying numeric change. This is the "new order just arrived" flash-highlight.

**TruckWeatherCard** (`Cards/TruckWeatherCard.swift`):
- Header links to `.city(sanFrancisco.id)` (hard-coded city target regardless of the truck's actual city — a sample-app simplification).
- On `.task`, calls `WeatherService.shared.weather(for: location, including: .hourly)` (WeatherKit) and maps entries into a local `TruckWeatherForecast` (date, °F, `isDaylight`). Falls back to a **static hard-coded 25-hour placeholder forecast** (`placeholderForecast`, hourly readings 63°→83°→55°→62°F) both as the initial `@State` value shown before the task resolves, and implicitly on any WeatherKit error (the catch block only logs — the UI silently keeps whatever forecast it last had, which is the placeholder if the call never succeeds). This is the WeatherKit "static-data fallback" the task calls out.
- Chart: Swift Charts `Chart` with a temperature `AreaMark` (catmull-rom interpolation, teal→yellow vertical gradient), overlaid `RectangleMark`s for the night-time ranges masked to the area shape at 50% opacity, plus per-boundary vertical "day/night divider" `RectangleMark`s (indigo, 4pt wide, drop-shadowed, rounded) annotated with a moon-circle icon at sunset and a sun-circle icon at sunrise. X axis: 3-hour bins via `DateBins`. Y axis: automatic domain not including zero, 5° minimum stride, ~6 labels, "°F" suffix.

**TruckDonutsCard** (`Cards/TruckDonutsCard.swift`):
- Header links to `.donuts`.
- Body: a custom `Layout` named `DonutLatticeLayout` (nested inside this file) arranging up to 14 `DonutView`s in a **brick/honeycomb lattice**: 5 columns × 3 rows, odd rows offset horizontally by half a cell and one column short (5,4,5 pattern), producing a staggered lattice rather than a plain grid. Cell size is derived from `min(width/columns, height/rows)` and the whole lattice is right/bottom-anchored within its bounds.

**TruckSocialFeedCard** (`Cards/TruckSocialFeedCard.swift`):
- Header links to `.socialFeed`.
- Body: a reusable `FlowLayout` (see §7) wrapping 16 hard-coded `SocialFeedTag` chips (mix of donut icons, city icons, and plain text tags like "Warmed Up", "Gluten Free", "Donut vs Doughnut") using the `.socialFeedTag` label style (small icon + caption text on a rounded quaternary-fill chip). Footer caption: "Trending Topics".

**Card header chrome** (`CardNavigationHeader` + `CardNavigationHeaderLabelStyle`): every card header is an `HStack` with a leading icon+title (secondary icon tint, headline title, accent-color foreground) and a trailing chevron-forward at `.tertiary` — visually mimicking a disclosure row even when it's a `Button` rather than a real `NavigationLink`.

### 2.2 Orders (`OrdersView`, `OrderDetailView`, `OrdersTable`, `OrderRow`, `OrderCompleteView`)

**List/Table (`OrdersView`)**
- `@State sortOrder` defaults to sorting by `status` descending (so Completed-ish/high-status-value orders surface — note `OrderStatus` raw values are `placed=0 < preparing=1 < ready=2 < completed=3`, and default reverse sort puts `completed` first, which is arguably a quirk worth deciding on in a reimplementation, not obviously "New orders first").
- `orders` computed property filters by `searchText` against `order.matches(searchText:)` (currently only matches the order id — `Order.matches` has a `// Search donuts...` TODO stub that is never implemented) OR any of its donuts' `matches(searchText:)` (which does check donut name + ingredient names).
- `orderSections` buckets filtered orders by `OrderStatus` into a dictionary for the list layout.
- **List layout** (compact iOS): four possibly-empty `Section`s titled "New" (placed), "Preparing", "Ready", "Completed", each only rendered if it has at least one order; `.headerProminence(.increased)`. Rows are `OrderRow` badge-suffixed with `order.totalSales`.
- **Table layout** (`OrdersTable`, regular iOS/macOS): a `Table` with sort-order binding and 5 columns — Order (an `OrderRow`, sortable by id), Donuts (`totalSales`, monospaced digits, right-aligned+secondary on macOS), Status (`order.status.label`, a `Label(title, systemImage:)`), Date (`formattedDate`), and a fixed 60pt-wide "Details" column containing a borderless `Menu` (ellipsis-circle icon) with "View Details" (push) and, if the order isn't complete, a "Complete Order" action that calls `model.markOrderAsCompleted` and opens the completion sheet immediately.
- Both modes: `.searchable(text:)`, `.navigationDestination(for: Order.ID.self)` pushing `OrderDetailView` bound live to the model via `model.orderBinding(for:)`, and `.sheet(item: $completedOrder)` presenting `OrderCompleteView`.
- Toolbar (table mode only): "View Details" `NavigationLink` (disabled when selection empty) and a checkmark "View Details"-labeled button that actually **completes** every selected order (`model.markOrderAsCompleted` for each id in the multi-selection) and opens the completion sheet for the first one. (List mode instead exposes `Select`/`EditButton` for iOS multi-select editing — but no equivalent bulk-complete action is wired for list mode; only the table toolbar has it.)

**Order detail (`OrderDetailView`)**
- `List` with: a Status section (status title + icon; "Order Started" + formatted creation date), a Donuts section (one row per donut: name label with a `DonutView` icon, badged with that donut's per-item sale count from `order.sales[donut.id]`), and a "Total Donuts" row badged with the order's total.
- Toolbar has a single icon-only button whose label/icon is `order.status.buttonTitle`/`iconSystemName`, filled (`symbolVariant(.fill)`) once complete, and **disabled once the order is already complete**. Tapping it calls `order.markAsNextStep(completion:)`.
- **Status state machine** (`Order.markAsNextStep`, in `Order.swift`): `placed → preparing → completed` (there is no separate "ready" step reachable via this button in the detail view — `ready` only appears as a status seeded directly by the order generator for already-progressed demo orders, and as a UI section bucket; the interactive lifecycle exposed here is a 2-tap flow: Prepare → Complete). Button titles per status: placed→"Prepare", preparing→"Ready" (label text, but the transition actually jumps straight to `.completed`), ready→"Complete", completed→"Complete" (disabled).
- Side effects on transition (iOS/whenever `ActivityKit` is importable):
  - Entering `.preparing`: prints a log line and calls `prepareOrder()`, which starts a **60-second Live Activity** (`Activity<TruckActivityAttributes>.request`, initial `ContentState.timerRange = now...(now+60s)`, `staleDate` = now+2min) and schedules a **local notification** ("Donuts are done!" / "Time to take them out of the oven.") firing after the same 60 seconds via `UNTimeIntervalNotificationTrigger`.
  - Entering `.completed`: ends the matching Live Activity immediately (`activity.end(nil, dismissalPolicy: .immediate)`), matched by comparing `orderID` (order id string with its first 6 characters dropped, i.e. the numeric suffix after "Order#").
- `.onChange(of: order.status)`: whenever status becomes `.completed` **by any means** (including the toolbar table's bulk-complete action reaching this order while it's the active detail, or the OrdersView list flow), `presentingCompletionSheet` flips true and `OrderCompleteView` sheets in.

**Order completion celebration (`OrderCompleteView`)**
- A modal `NavigationStack` sheet showing a `DonutBoxView` (see §7) containing the first donut of the order, title "<OrderID> completed!", subtitle "<totalSales> donuts • <time>". Toolbar: "Done" confirmation-action button that dismisses.
- **Scripted animation on appear** (`.task`): wait 0.75s → `toggleBoxAnimation()` (closes the box lid with a slow no-bounce spring, `response:0.35, dampingFraction:1`; once closed, after 0.15s springs the box down 15pt as a "bounce", holds 0.15s, springs back up) → wait another 1.5s → conditionally requests an App Store review.
- The box can also be manually re-toggled by tapping it (`onTapGesture` re-runs the same animation function, so tapping toggles open/closed indefinitely).
- **Review-prompt gating** (`shouldRequestReview`): uses two `@AppStorage` values (`versionPromptedForReview: String?`, `datePromptedForReview: TimeInterval?`). If never asked before → true. Otherwise: only true if the current app version differs from the last-prompted version **and** at least 4 months have elapsed since the last prompt (via `Calendar.date(byAdding: DateComponents(month:4))`). On triggering, calls the `\.requestReview` environment action (`SKStoreReviewController`-backed) and persists the current version + now as the new "last asked" markers.

**`OrderRow`**: a small `HStack` combining a `DonutStackView` thumbnail (in a rounded-rect tinted/quaternary background with hairline stroke, 40×40 iOS / 20×20 macOS) and the order id text — the shared list-cell building block used by both the compact list and the table's Order column.

### 2.3 Donuts menu, editor, gallery (`DonutGallery`, `DonutEditor`, `DonutGalleryGrid`, related chart/lattice views)

**Donut Gallery (`DonutGallery.swift`)**
- Toggle between `.grid` (adaptive `LazyVGrid` via `DonutGalleryGrid`) and `.list` (a `Table` showing thumbnail + name only), both wrapped in a `ZStack`/`GeometryReader`.
- Sort state: `DonutSortOrder` = `.popularity(Timeframe)` (default, week), `.name`, `.flavor(Flavor)` (default sweet). A single trailing toolbar `Menu` bundles: a Layout picker (Icons/List, inline), a Sort picker (Name / Popularity / Flavor, inline), and a conditionally-shown secondary picker — a Timeframe picker (Today/Week/Month/Year) when sort is popularity, or a Flavor picker (all six flavors) when sort is flavor. `.onChange` handlers keep the composite sort value's associated parameter (`popularityTimeframe`/`sortFlavor`) synced whenever those secondary pickers change while that sort mode is active.
- `.searchable(text:)` filters by `donut.matches(searchText:)` (name or any ingredient name, case-insensitive).
- Toolbar "Create Donut" `NavigationLink` pushes value `"New Donut"`, which routes (via a `String.self` `navigationDestination`) to `DonutEditor(donut: $model.newDonut)` — i.e., creating a new donut edits a single shared scratch `Donut` on the model (id = `Donut.all.count`) rather than allocating a fresh one per tap; there's no "save/add to list" step visible in this code, so the new-donut flow is a stub/incomplete feature in the sample.
- `.navigationDestination(for: Donut.ID.self)` pushes `DonutEditor(donut: model.donutBinding(id:))` for existing donuts (bidirectional binding straight into the model array).

**Donut Gallery Grid (`DonutGalleryGrid.swift`)**
- `LazyVGrid` with a single adaptive `GridItem(.adaptive(minimum: cellSize), spacing: 20)`. `cellSize`/`thumbnailSize` shrink (150→100 cell, and iOS 100→60 / macOS 80→40 thumbnail) whenever `useReducedThumbnailSize` is true — computed from horizontal size class == compact (iOS), Dynamic Type ≥ `.xxxLarge`, or width ≤ 390 (iOS) / ≤ 520 (macOS).
- Each cell: `DonutView` thumbnail, name, and a secondary-styled `HStack` of the donut's most-potent flavor icon + name, all center-aligned; wrapped in a plain-style `NavigationLink` pushing the donut's id.

**Donut Editor (`DonutEditor.swift`)**
- Two-pane editor: a large `DonutView` preview (`donutViewer`, min 100×100, expands to fill) and a `Form(.grouped)` with three sections:
  1. **Donut** — a single `TextField` bound to `donut.name`.
  2. **Flavor Profile** — a `Grid` with one row per `Flavor` case (salty/sweet/bitter/sour/savory/spicy): flavor icon, flavor name, a `Gauge` (0...topFlavorValue, i.e. scaled relative to whichever flavor is currently strongest) with no visible label, and the numeric value. The row for the currently most-potent flavor is drawn in `.primary`/accent tint; all others are `.secondary`/gray-tinted. **This is a live, read-only computed summary** (`donut.flavors` sums the flavor contributions of dough+glaze+topping) — there is no direct flavor slider; flavor changes only through picking different ingredients below.
  3. **Ingredients** — three `Picker`s (menu-style by default in a Form):
     - **Dough**: required, one of 7 (`Donut.Dough.all` — Blueberry, Chocolate, Sour Candy, Strawberry, Plain, Powdered, Lemonade).
     - **Glaze**: optional (`nil` selectable as "None" in its own `Section`), one of 7 (`Donut.Glaze.all` — Blueberry, Chocolate, Sour Candy, Spicy, Strawberry, Lemon, Rainbow).
     - **Topping**: optional (`nil`/"None"), then four grouped `Section`s inside the picker — **Other** (Powdered Sugar, Sprinkles, Star Sprinkles), **Lattice** (7 flavors × criss-cross pattern), **Lines** (7 flavors × parallel-line pattern), **Drizzle** (7 flavors × zigzag pattern) — 3 + 7 + 7 + 7 = 24 topping options total.
- Layout: macOS uses a drag-resizable `HSplitView` (preview left, form right fixed-ish width 300–350); iOS/iPadOS uses `WidthThresholdReader` to choose a single scrolling `Form` (compact, preview embedded as a form row) vs a fixed `HStack` split (regular).
- A `ToolbarTitleMenu` exists with one placeholder "My Action" (star icon) button that does nothing — a stub, not implemented.
- iOS: `.navigationBarTitleDisplayMode(.inline)`, `.toolbarRole(.editor)`, and marks itself `.storeMessagesDeferred(true)` so StoreKit system messages never interrupt active editing.
- **There is no explicit "Save" action** — because the editor operates on a live `Binding<Donut>` straight into the model's array (or the scratch `newDonut`), every field edit is already persisted into `FoodTruckModel` as it happens.

**Ingredient/flavor data model** (`Donut.swift`, `Ingredients/{Dough,Glaze,Topping,Ingredient}.swift`, `FlavorProfile.swift`):
- `Ingredient` protocol: `name`, `flavors: FlavorProfile`, `imageAssetName`, static `imageAssetPrefix`; default `id` is `"<prefix>/<name>"`; provides `image(thumbnail:)` resolving to `"<prefix>/<assetName>-thumb"` or `"-full"` in the module's asset catalog.
- `FlavorProfile`: 6 signed integer axes (salty/sweet/bitter/sour/savory/spicy) with keyed subscript access, a `union(with:)`/`formUnion` additive combine, and `mostPotent`/`mostPotentFlavor`/`mostPotentValue` (ties favor whichever flavor is checked first in enum order, defaulting to `.sweet` if all zero). A `Donut`'s flavor profile is simply the summed profile of dough + glaze (if any) + topping (if any); every ingredient contributes fixed, hand-authored per-flavor integers (including some negative values, e.g. chocolate dough is `sour: -1`).
- 17 predefined `Donut.all` combos (The Classic, Blueberry Frosted, Strawberry Drizzle, Cosmos, Strawberry Sprinkles, Lemon Chocolate, Rainbow, Picnic Basket, Figure Skater, Powdered Chocolate, Powdered Strawberry, Custard, Super Lemon, Fire Zest, Black Raspberry, Daytime, Nighttime).

**Top 5 Donuts (`TopFiveDonutsView`, `TopFiveDonutsChart`, `TopDonutSalesChart`)**
- `TopFiveDonutsView`: a segmented `Picker` (Day/Week/Month/Year, i.e. `Timeframe`) driving `TopFiveDonutsChart`, plus (iOS only) a `SiriTipView` suggesting the `ShowTopDonutsIntent` App Shortcut for the current timeframe.
- `TopFiveDonutsChart`: pulls `model.donutSales(timeframe:)`, sorts ascending then reverses and takes the first 5 (i.e., top 5 by sales), and renders via `TopDonutSalesChart`.
- `TopDonutSalesChart`: shows "Total Sales" / "<n> Donuts" header, then a Swift Charts `Chart` of `BarMark`s (one per donut, x = donut name, y = sales count), rounded 6pt corners, a bottom-to-top gradient fill (`BarBottomColor` → accent), each bar annotated on top with its numeric sales count in a small capsule badge. Y axis: integer-formatted gridlines. X axis: **custom axis value labels** — instead of plain text, each x-axis tick renders a small `DonutView` icon (35pt tall) above a 2-line, center-aligned donut name (`donutFromAxisValue` looks the donut back up by matching its name string against the axis value, `fatalError`ing if not found — a hard assumption that donut names are unique and stable).

**"Show Top Donuts" App Intent** (`ShowTopDonutsIntent.swift`, `ShowTopDonutsIntentView.swift`): a Siri/Shortcuts `AppIntent` with one `@Parameter var timeframe: ShowTopDonutsIntentTimeframe` (today/week/month/year, each with a display string), returning `.result(view: ShowTopDonutsIntentView(timeframe:))` — a `ShowsSnippetView` result, i.e. Siri/Shortcuts renders `TopFiveDonutsChart` directly as the intent's visual snippet, backed by a **fresh, throwaway `FoodTruckModel()`** instantiated inside the intent view (not the app's shared model — running the intent regenerates a whole new random order history). `FoodTruckShortcuts: AppShortcutsProvider` registers one phrase template: "\(appName) Trends for \(timeframe)".

### 2.4 Socials / City views

**Social Feed (`SocialFeedView.swift`, `SocialFeedPostView.swift`, `SocialFeedContent.swift`)**
- A `List` with a conditional lead section:
  - If **not** subscribed to Social Feed+ (`subscriptionController.entitledSubscriptionID == nil`): a single-section **marketing banner** (`SocialFeedPlusMarketingView`) — "Get Social Feed+" title, tagline "The definitive social-feed experience", and a "Get Started" button that presents the `SubscriptionStoreView` sheet. Styled with an indigo gradient row background (iOS: `.listRowBackground`; macOS: `.background`+`.cornerRadius`).
  - If subscribed: a "Highlighted Posts" section showing the 3 `socialFeedPlusContent` posts (extra/bonus content gated behind the subscription).
- Always: a "Posts" section with the 7 `standardContent` posts, available regardless of subscription.
- Navigation title switches to "Social Feed+" once subscribed.
- Toolbar (only when subscribed): a "Subscription Options" button (icon `plus.bubble`) opening `SocialFeedPlusSettings` as a sheet.
- `SocialFeedPost` model: `favoriteDonut`, `message` (LocalizedStringKey — allows embedded formatting/localization), `date`, `tags: [SocialFeedTag]`. Both content arrays are hard-coded fixture data whose dates are backdated by repeatedly subtracting a random 5–30 minute interval per post (so the feed always looks "just happened", freshly regenerated relative to `Date.now` each app launch).
- `SocialFeedTag` is an enum over `.title(text)`, `.donut(Donut)`, `.city(City)`, each rendering as a `Label` with a matching icon (tag icon / mini `DonutView` / building icon).
- `SocialFeedPostView`: a post row = circular donut avatar (donut's dough background color as a gradient-filled circle behind it, with a light/dark-blend-mode hairline ring) + message text (title3) + a `FlowLayout` of that post's tags (chip style) + a relative date string ("Today, 3:45 PM" / "Yesterday, ..." / full date).
- `SocialFeedTagLabelStyle`: caption-sized chip, `@ScaledMetric` 14pt icon width (so icon scales with Dynamic Type), rounded-rect quaternary background.

**Store views reached from Social Feed** — see §2.5 (shared Store screens).

**City view (`CityView.swift`)**
- Reached via any of the sidebar's three city rows, or via the Weather card link (hard-coded to San Francisco), or via `RecommendedParkingSpotCard`.
- Layout: `ScrollView` → `VStack`:
  1. An animated "map" hero: `ParkingSpotShowcaseView` (an orbiting `MKMapView`, see §7) for the currently-chosen `spot`, masked with a top-to-bottom fade gradient on iOS so it blends into the page, overlaid bottom-trailing with a `CityWeatherCard` chip once weather data resolves.
  2. `RecommendedParkingSpotCard` — spot name, "Recommended"/"Parking Spot" labels, and a `ViewThatFits`-based responsive summary row (temperature+icon, "Popular" person icon, "Trending" chart icon — degrading through 3 fallback compositions from most to least information as width shrinks, down to just the temperature).
  3. Three static filler copy lines in a quaternary rounded card: cloud-cover percentage (from live weather data, formatted to whole percent), a hard-coded "Popular donuts this season include Custard, Super Lemon, and Rainbow" line, and a hard-coded ingredient-stocking recommendation line — **not derived from actual sales data**, purely flavor text.
  4. A WeatherKit legal-attribution footer: an `AsyncImage` of Apple's required attribution logo (light/dark variant chosen by `colorScheme`) plus a "Other data sources" `Link` to Apple's legal attribution page — falls back to a placeholder URL if the live attribution URL hasn't loaded yet.
- **Data loading** (`.task(id: city.id)`, re-runs whenever the selected city changes): iterates the city's parking spots **in order**, fetching `WeatherService.shared.weather(for:)` for each, until it finds one where `willRainSoon == false` (checked against `minuteForecast`, `precipitationChance >= 0.3`), and switches the displayed `spot` to that first rain-free location — i.e., **the app auto-picks whichever of a city's parking spots currently has the best weather** as the "recommended" spot. If the WeatherKit call throws, it hard-codes `condition = .clear`, `willRainSoon = false`, `cloudCover = 0.15` and stops (no retry across remaining spots on error). `spot` is also reset to the city's first parking spot both `onAppear` and via `.onChange(of: city)`.

**`DetailedMapView`** — a thin `UIViewControllerRepresentable`/`NSViewControllerRepresentable` wrapper around a raw `MKMapView`: realistic elevation, default emphasis, POI filter excluding all points of interest, no traffic, and **all interactivity disabled** (zoom/pitch/scroll/rotate off, compass hidden) — it's purely a camera-driven decorative backdrop, not an interactive map.

**`ParkingSpotShowcaseView`** — see §7 (custom `TimelineView`-driven orbit camera).

**`RecommendedParkingSpotCard`** — see above; its `RecommendedSpotSummaryLabelStyle` stacks icon-over-caption vertically for each summary item.

### 2.5 Account / Settings / Store

**Account (`AccountView.swift`, `EXTENDED_ALL`-gated in the sidebar)**
- `Form(.grouped)`:
  - If signed in: a header row showing a generic person-circle avatar (accent gradient fill) + username.
  - iOS: a "In-app purchase support" `NavigationLink` → `StoreSupportView`. macOS: an inline "Restore missing purchases" button (`AppStore.sync()`).
  - Sign-in section: if signed in, a destructive "Sign Out" button (behind a confirmation `Alert`, "Are you sure you want to sign out?"); if signed out, "Sign In" (calls `accountStore.signIntoPasskeyAccount`) and "Sign Up" (presents `SignUpView` sheet).
- macOS caps the form at `maxWidth: 500`.

**Sign up (`SignUpView.swift`)**
- `Form`: username field (`.textContentType(.username)`, iOS gets `.textInputAutocapitalization(.never)` + `.keyboardType(.emailAddress)`), a conditionally-shown password `SecureField` (only when not using a passkey), and a "Use Passkey" `Toggle` (defaults **on**). Footer explains passkeys ("all you need is a user name... available on all of your devices").
- Field focus auto-set to username `onAppear` via `@FocusState`.
- Toolbar: "Sign Up" (confirmation action, disabled unless the form is valid — username required always, password additionally required only if not using a passkey) and "Cancel" (cancellation action, just dismisses).
- Submission calls either `accountStore.createPasskeyAccount` (ASAuthorization passkey registration flow) or `accountStore.createPasswordAccount`, then dismisses.

**`AccountStore`** (`FoodTruckKit/Sources/Account/AccountStore.swift`, iOS/macOS only): wraps `ASAuthorizationController`-based passkey + password flows.
- `currentUser: User?` published, defaults to `.default` (a sentinel "not really signed in yet" case distinct from `nil`/signed-out and from `.authenticated(username:)`).
- Sign-in requests **both** a passkey assertion and a password credential simultaneously (`[passkeyAssertionRequest(), ASAuthorizationPasswordProvider().createRequest()]`), letting the system's account-chooser UI decide which credential type the user picks.
- Passkey relying-party identifier is the placeholder `"example.com"` — matching the entitlements' `webcredentials:example.com` Associated Domain.
- On success (password, passkey-assertion, or passkey-registration) sets `currentUser = .authenticated(username:)`; explicitly swallows user-cancellation as a no-op log line; other errors are logged via `os.Logger` and left unhandled (no user-facing error UI). Comment notes that a real app would persist an auth token to Keychain here — this sample does not.

**Store / subscriptions / purchases** (mix of `App/Store/*.swift` views and `FoodTruckKit/Sources/Store/*.swift` controllers):
- **Products**: one non-consumable premium unlock, `feature.annualhistory` (unlocks Month/Year Sales History), and two auto-renewable subscription tiers under one group, `socialfeedplus.monthly` / `socialfeedplus.yearly` (Social Feed+).
- `StoreActor` (a `@globalActor` actor, `StoreActor.shared`): loads all product IDs once via `Product.products(for:)`, exposes the loaded premium `Product` to a `StoreProductController` and the subscription `Product`s to a `StoreSubscriptionController`, and runs three concurrent background listener loops for the app's lifetime: `Transaction.updates` (re-checks entitlement per transaction type), `Product.SubscriptionInfo.Status.updates` (keeps subscription entitlement live), and `Storefront.updates` (re-loads all products if the user's App Store storefront/region changes, cancelling any in-flight load first).
- `StoreProductController`: `@Published product`, `isEntitled`, `purchaseError`; `purchase()` runs `product.purchase()` and sets `isEntitled = true` on verified success (does not itself verify the `VerificationResult` signature beyond unwrapping `payloadValue`, which force-unwraps under the hood — a sample-app simplification); tracks entitlement independently via `Transaction.currentEntitlement(for:)`.
- `StoreSubscriptionController`: tracks `subscriptions: [Subscription]`, `entitledSubscriptionID`, `autoRenewPreference`, `expirationDate`, `purchaseError`. Prefers the StoreKit 2 subscription-group **Status** API (covers grace periods: `state == .subscribed || .inGracePeriod`) and falls back to per-product `currentEntitlement` lookups if no group ID is yet known (e.g., offline at first launch).
- **UI surfaces**:
  - `SubscriptionStoreView` — a full custom (non-StoreKit-view) purchase sheet: indigo-gradient header (`SubscriptionStoreHeaderView`, 3 marketing bullet lines), a scrollable list of `SubscriptionOptionView` cells (one per subscription tier, each showing name/description/price, a computed "Save X%" badge on the yearly tier if it's cheaper than 12× the monthly price, a checkmark selection indicator, drop shadow, accent-color selection border — tap-to-select via `onTapGesture`), and a bottom purchase bar (`SubscriptionPurchaseView`: "Start trial offer" if eligible for an intro offer else "Subscribe"; iOS also offers "Redeem an offer" via `.offerCodeRedemption`). Successful purchase or explicit purchase-error dismisses/alerts respectively.
  - `SocialFeedPlusSettings` — subscription status summary (`SubscriptionStatusView`: current tier, renewal/expiration copy computed from whether the auto-renew preference differs from the current entitlement, a "Manage subscription" button routed through `.manageSubscriptionsSheet` on iOS or an `openURL` to the App Store subscriptions page on macOS) plus two `@AppStorage`-backed toggles ("Highlight Social Feed+ posts" default off, "Advanced engagement tools" default **on**) and a dead-end "Social-media providers" `NavigationLink` to an `EmptyView`. Auto-dismisses `onAppear` if the entitlement has since been lost.
  - `StoreSupportView` — iOS-only manage-subscription + refund-purchase entry points, plus a cross-platform "Restore missing purchases" action.
  - `RefundView` — lists the most recent 10 non-revoked `StoreKit.Transaction`s (via `Transaction.all`, an async sequence) with product name/purchase-or-subscribed date; a bottom "Request a refund" button (disabled until a row is selected) triggers `.refundRequestSheet` and dismisses on success.
  - `UnlockFeatureView` (used by Sales History) — a self-contained upsell card with two states: `UnlockFeatureExpandedView` (message, subtitle "Get the full picture...", capsule "Unlock" button, dismissible via an X) and, after dismissal, `UnlockFeatureSimpleView` (a compact single-line "Unlock a ... for only ..." row, tapping either the row or its own "Unlock" button both purchase and re-expand the card). Only renders at all while `product` is loaded and **not yet entitled**.

### 2.6 Sales History (`SalesHistoryView`, `SalesHistoryChart`)
- Segmented `Picker` bound to `@SceneStorage("historyTimeframe")` (so the choice survives scene restoration): "2 Weeks" (`.week`, calendar icon, always unlocked), "Month" and "Year" (calendar icon if `annualHistoryIsUnlocked` else a lock icon — icon itself signals gating state before the user even taps).
- "Total Sales" header (secondary caption + headline count) computed by summing every `SalesByCity` entry currently shown.
- `SalesHistoryChart`: one `LineMark` series per `City`, catmull-rom interpolated, colored/symbol-shaped `by: city.name`, legend on top; Y domain excludes zero; X axis suppresses the label on the very last tick (`value.index < value.count - 1`) to avoid crowding.
- **Paywall overlay**: if `timeframe != .week && !annualHistoryIsUnlocked`, the chart's marks are drawn at `opacity(0)` (so axes/legend still render but data is invisible) and a `.chartOverlay` draws a centered "🔒 Premium Feature" capsule badge over a translucent quaternary scrim.
- Below the chart: the `UnlockFeatureView` upsell card (same component used elsewhere), bound to the shared `StoreActor.shared.productController`.
- Underlying `sales` data is derived from `model.dailyOrderSummaries`/`monthlyOrderSummaries` per city, sliced to 14 (week — despite the label "2 Weeks"), 30 (month), or all 12 (year) entries, with each entry's calendar date computed backward from "now" by day or month offset.

---

## 3. Charts (Swift Charts usage inventory)

| Chart | File | Mark types | X axis | Y axis | Interaction / notable config |
|---|---|---|---|---|---|
| Hourly weather forecast (Truck card + implicitly City) | `TruckWeatherCard.swift` | `AreaMark` (catmull-rom, gradient fill) + masked `RectangleMark`s for night ranges + boundary `RectangleMark`s with icon `.annotation` | 3-hour `DateBins`, hour-only labels | automatic, excludes zero, min stride 5°, ~6 labels, "°F" suffix | No user interaction (no selection/tooltip); purely presentational; series-keyed area marks used as a **mask trick** rather than for legend grouping |
| Top-selling donuts bar chart | `TopDonutSalesChart.swift` | `BarMark`, rounded corners, gradient fill, numeric `.annotation` per bar | **custom** — each label is a rendered `DonutView` + 2-line name, not text | integer-formatted gridlines | X-axis label is a full mini SwiftUI view (icon+text), not a `Text`; `fatalError` if a bar's donut can't be re-resolved from its axis string |
| Sales-by-city history (weekly/monthly/yearly) | `SalesHistoryChart.swift` | `LineMark` per city, catmull-rom interpolation, per-series color + symbol | automatic, last tick label suppressed | automatic, excludes zero | Legend at top; whole chart content can be hidden (opacity 0) behind a lock overlay for gated timeframes |

No chart in the app uses `chartXSelection`/tap-to-inspect gestures or scrubbing — all three are read-only visualizations. Chart color is driven either by a literal gradient (weather, bars) or Swift Charts' automatic per-series palette keyed `by:` city name (sales history).

---

## 4. Core loop

### 4.1 Fake order-data engine (`OrderGenerator.swift`)
- Constructed once with the model's full `knownDonuts` list and a **fixed per-city seed table**: Cupertino → multiplier 0.5, seed 1; San Francisco → multiplier 1.0, seed 2; London → multiplier 0.75, seed 3 (so San Francisco is always the "busiest" city and Cupertino the quietest, deterministically).
- `SeededRandomGenerator` wraps libc's `srand48`/`drand48` to get a reproducible `RandomNumberGenerator` from an integer seed — used everywhere historical/deterministic data is needed; live "new order arriving" generation instead uses a system RNG (non-reproducible, since it's meant to feel spontaneous).
- **`todaysOrders()`** — seeds a `SeededRandomGenerator(seed: 1)` and produces exactly **24 orders** for "today": starting from `now`, walks backward in time by a random 60–180s gap per order (so times get progressively earlier/older toward the end of the array, then the array itself is built index-ascending 0..<24 meaning index 0 is the most time-shifted-into-the-past... concretely: `previousOrderTime` starts at `now - 4min` and is decremented by a random gap **before** each order is generated, so order 0 is the oldest, order 23 is the newest/closest to now). The **first 9 orders (index 0–8) are marked `.placed`**; the remaining 15 (index 9–23) are marked `.ready` with a synthetic `completionDate` = `min(orderTime + 14 minutes, now)` — i.e., on launch the order board is pre-seeded with a realistic mix of brand-new and already-finished-looking orders, but note none start as `.preparing` or already `.completed`.
- **`generateOrder(number:date:generator:)`** — picks a random 1–5 donuts (shuffled `knownDonuts.prefix(random count)`), assigns each a random 1–5 unit sale count, sums to `totalSales`, prices the order at `totalSales × $5.78` (a flat per-donut rate, hard-coded), always assigns **Cupertino / its first parking spot** as location (even orders nominally for other cities all get stamped Cupertino — a simplification), sets weather metadata to a hard-coded 72°F/no-rain, and formats the id as `"Order#<12><number:%02d>"` (i.e. ids always start with the literal prefix "12", e.g. "Order#1201".."Order#1224" for the initial 24, continuing "Order#1225" etc. for live-generated ones since `number` is passed as `orders.count + 1`).
- **Live order arrivals** (`FoodTruckModel.init`): a detached background `Task` seeded with `SeededRandomGenerator(seed: 5)` loops **20 times**, sleeping a random 3–8 seconds between each, then (back on the main actor) appends a freshly generated order to `model.orders` inside `withAnimation(.spring(response:0.4, dampingFraction:1))` — this is what drives the Truck card's insertion transition and the "pulse" flash on the newest-order footer text. After 20 arrivals (roughly 30–130s of app-runtime, cumulative), no more orders ever arrive automatically for that session.
- **Historical daily/monthly summaries** (`historicalDailyOrders`/`historicalMonthlyOrders`, used for Sales History and Top-5/popularity sorting): per city, walks 60 days (daily) or 13 months (monthly) backward from today, computing a random total order-count-ish baseline (`80...120` range, ±25% weekend/day multiplier for daily), then distributes that volume across all known donuts via an **exponential popularity falloff curve** — `percent = 1 - pow(offset/totalDonutCount, 0.15)` where `offset` is the donut's position in a per-city-seeded shuffle — so each city has its own consistent "most popular donut" ranking, with per-day random variance (0.9–1.0 multiplier) layered on top, and each day's sales additionally **smoothed 50% (daily) / 25% (monthly) toward the previous day's sales** for that same donut, to avoid noisy day-to-day jumps.

### 4.2 Order lifecycle end to end
1. App launches → 24 seeded orders exist immediately (9 `.placed`, 15 `.ready`); over the next ~30–130s, up to 20 more `.placed` orders trickle in with a spring-animated insertion and a footer pulse highlight on the Truck card.
2. User opens Orders (list on iPhone, table elsewhere), optionally searches/sorts, and either:
   - Taps into a `.placed` order's detail and taps the status button → order becomes `.preparing`; a 60s Live Activity + Dynamic Island timer starts, and a local notification is scheduled to fire when that minute elapses.
   - Taps the same button again while `.preparing` → order jumps straight to `.completed` (skipping any interactive `.ready` step); the Live Activity ends immediately; the `OrderCompleteView` celebration sheet auto-presents (`onChange(of: order.status)`).
   - Alternatively, from the table's row menu or the multi-select toolbar, the user can **force-complete** any not-yet-complete order directly (`markOrderAsCompleted`), bypassing `.preparing`/Live-Activity/notification entirely, and the same completion sheet shows.
3. The completion sheet plays the donut-box-closing animation, then (subject to the 4-month/version-change gate) may trigger the system App Store review prompt.
4. Nothing in the codebase auto-advances `.placed`→`.preparing`→`.completed` on its own — every transition requires a user action (or deep link into an order + manual tap); the "timer" that exists is purely a **60-second cosmetic countdown** tied to the Live Activity/notification, not a gameplay/economy timer that changes order state on expiry (order status doesn't auto-flip to "done" when the countdown reaches zero — that's still a manual button tap).

### 4.3 Donut popularity / stats loop
- `FoodTruckModel.donutSales(timeframe:)` and `donuts(sortedBy: .popularity)` both read from `combinedOrderSummary(timeframe:)`, which unions `OrderSummary`s: `.today` unions live `orders`; `.week`/`.month` union the first 7/30 daily historical summaries across **all** cities combined; `.year` unions all monthly summaries across all cities. So "popularity" everywhere (Donut Gallery sort, Top-5 chart) is a global cross-city aggregate, never scoped to one city, even though the underlying historical generator is city-specific.

---

## 5. Data model

Core value types (all in `FoodTruckKit/Sources/**`):

- **`Donut`** (`Identifiable` by `Int` id, `Hashable`): `name`, `dough: Dough` (required), `glaze: Glaze?`, `topping: Topping?`. Computed `ingredients: [any Ingredient]`, `flavors: FlavorProfile` (summed), `matches(searchText:)`. 17 static instances + one mutable `newDonut` scratch instance on the model. Exposes a custom `UTType` (`com.example.apple-samplecode.donut`) — declared for drag/drop or file-export interop, though no view in the traced code actually performs a drag session with it.
- **`Ingredient` protocol** + three conforming structs `Donut.Dough`, `Donut.Glaze`, `Donut.Topping` — each just `name` + `imageAssetName` + `flavors: FlavorProfile`, differentiated by a static `imageAssetPrefix` ("dough"/"glaze"/"topping") used to build asset-catalog lookup paths and identifiers. Not persisted/serializable (no `Codable`); all instances are compile-time constants.
- **`FlavorProfile`** (`Hashable`, `Codable`): 6 signed `Int` axes; the only `Codable` model type found, though nothing in the traced code actually encodes/decodes it to disk — likely future-proofing or Live-Activity payload support (`TruckActivityAttributes.ContentState` is separately `Codable`).
- **`Order`** (`Identifiable` by `String` id, `Equatable`): `status: OrderStatus`, `donuts: [Donut]`, `sales: [Donut.ID: Int]`, `grandTotal: Decimal`, `city: City.ID`, `parkingSpot: ParkingSpot.ID`, `creationDate`, `completionDate: Date?`, `temperature: Measurement<UnitTemperature>`, `wasRaining: Bool`. Note `city`/`parkingSpot`/`temperature`/`wasRaining` are captured **per order** but the generator always stamps the same hard-coded values (Cupertino, 72°F, no rain) — the fields exist for a richer simulation than the shipped generator actually produces.
- **`OrderStatus`** (`Int` raw, `Codable`, `Comparable` by raw value): `placed=0 < preparing=1 < ready=2 < completed=3`.
- **`OrderSummary`**: `sales: [Donut.ID: Int]` + derived `totalSales`; `union`/`formUnion` combinators (used to roll up daily → weekly/monthly/yearly and cross-city aggregates).
- **`DonutSales`** (`Identifiable` by donut id, `Comparable`): pairs a `Donut` with an `Int` sales count; comparison is by `sales`, tie-broken by donut id — used to feed the Top-5 chart.
- **`City`** (`Identifiable` by `name` string, `Hashable`): `name`, `[ParkingSpot]`. 3 static cities (Cupertino: 2 spots, San Francisco: 8 spots, London: 6 spots), each spot given a real-world `CLLocation` (Apple Park, Big Ben, Golden Gate Bridge, etc.) and a per-spot `cameraDistance` tuning value for the map showcase.
- **`ParkingSpot`** (`Identifiable` by `name`): `name`, `location: CLLocation`, `cameraDistance: Double = 1000`.
- **`Truck`**: `city: City = .cupertino`, `location: ParkingSpot = City.cupertino.parkingSpots[0]` — the truck's own position is never actually moved anywhere in the traced code (no method mutates it); it's effectively a fixed default.
- **`User`**: a bare enum, `.default` | `.authenticated(username: String)` — not `Codable`, not persisted across launches (a fresh app launch always starts at `.default`/signed-out, since `AccountStore.currentUser` is only ever set in-memory).
- **`Subscription`** / **`SubscriptionSavings`**: thin `@dynamicMemberLookup` wrapper over StoreKit's `Product`/`Product.SubscriptionInfo`, not app-authored persisted data.
- **`Timeframe`** (`String` raw, `CaseIterable`, `Sendable`): `today | week | month | year` — the one enum used consistently across Sales History, Donut Gallery sort, Top-5, and the App Intent.

**What's generated vs. persisted**: **Nothing in this app is persisted to disk or a server.** `FoodTruckModel` and `AccountStore` are plain in-memory `ObservableObject`s constructed fresh every launch (`FoodTruckModel()`), and all "history" (60 days, 13 months per city) plus "today's" 24+20 orders are procedurally regenerated from scratch — deterministically for historical data (seeded RNG) and semi-randomly for live order arrival (system RNG timing, seeded RNG content) each time the app starts. The only durable state anywhere is a handful of `@AppStorage`/`@SceneStorage` UI preferences (review-prompt gating dates/version, Sales-History timeframe selection, Social Feed+ display toggles) and whatever StoreKit itself persists (purchases/entitlements, which is Apple-server-backed, not app-local).

---

## 6. Host-OS-only surfaces

- **Live Activities / Dynamic Island** (`Widgets/TruckActivityWidget.swift`, `TruckActivityAttributes.swift`, gated `#if canImport(ActivityKit)`):
  - `TruckActivityAttributes`: static `orderID`, `order: [Donut.ID]`, `sales`, `activityName`; dynamic `ContentState` = a single `timerRange: ClosedRange<Date>`.
  - Lock-screen/banner presentation (`LiveActivityView`): leading app icon, `OrderInfoView` (order number + static "6 donuts" label — **not actually computed from the real order's donut count**, a hard-coded placeholder), trailing `OrderTimerView` (a native `Text(timerInterval:countsDown:true)` live countdown). Background tint switches light/dark via named colors; respects `isLuminanceReduced` (Always-On Display) by dimming secondary text to 50% opacity.
  - Dynamic Island: expanded region shows the same leading icon + trailing order-info/timer split (with `.dynamicIsland(verticalPlacement: .belowIfTooWide)` fallback); compact-leading/minimal both show a small branded icon on an indigo gradient; compact-trailing shows just the countdown text (`monospacedDigit`, fixed 40pt width). Custom `contentMargins` per region. All three presentations carry the same `widgetURL` deep link back into the app (`foodtruck://order/<id>`), which `ContentView.onOpenURL` resolves to the order detail.
  - Started from `OrderDetailView.prepareOrder()` (order enters `.preparing`) with a 60s countdown and a 2-minute stale-date; ended from the same view when the order becomes `.completed`.
  - **No in-app twin** — there's no persistent in-app countdown/timer widget mirroring the Live Activity; the app-side experience of "preparing" is just the disabled/updated toolbar button, the system notification, and (separately) the completion sheet once finished.

- **Widgets** (`Widgets/*.swift`, `WidgetBundle` named `Widgets`):
  - **Daily Donut Widget** (iOS + macOS; `.systemSmall/.medium/.large` everywhere, plus `.systemExtraLarge` on iOS only): shows one donut (`Donut.all[hourOffset % count]`, i.e. **cycles through the fixed list by the hour**, not by actual popularity) + its name; medium/large/extraLarge add a "Trend Data..." placeholder label — **stubbed, not real trend data**. 5-entry hourly timeline, `.atEnd` reload policy.
  - **Orders Widget** (iOS `.systemSmall`; iOS/watchOS `.accessoryCircular/.accessoryRectangular/.accessoryInline`): shows current orders-vs-quota as a `Gauge` (systemSmall: standard gauge with a `DonutView` current-value label on an accent gradient background; accessoryCircular: `.accessoryCircular` gauge style with the donut glyph as the label; accessoryRectangular: the app's own custom `SegmentedGauge` — see §7 — with a donut+"Orders" header; accessoryInline: plain text "N of M Orders" + donut glyph). Timeline entries are synthetic (`orders: 7 + hourOffset, quota: 25`), not backed by the live model at all — the widget process never talks to `FoodTruckModel`.
  - **Parking Spot Accessory** (iOS/watchOS accessory families only): shows the (hard-coded preview) current city/parking-spot name — `.accessoryInline` a label, `.accessoryCircular` a truck icon + fixed "CUP" abbreviation text (not derived from the actual city, always literally "CUP"), `.accessoryRectangular` a 3-line label (heading "Parking Spot" / spot name / city name). Single never-refreshing timeline entry (`.never` policy) — genuinely static once placed, matching real-world "the truck doesn't move that often" framing, though again backed only by the preview fixture, not live model state.
  - `SegmentedGauge` — a fully custom `Gauge` + `GaugeStyle`: renders N equal capsule/rounded segments (custom `Shape` with per-position corner rounding — square-ish in the middle, rounded only at the very first/last segment, and RTL-aware corner flipping) at fixed 11pt height / 3pt gaps, dimming unfilled segments to 35% opacity. Reused by the Orders widget's `accessoryRectangular` presentation.
  - `WidgetColors.swift`: two named-asset colors (`AccentColor`, `AccentColorDimmed`) and a shared `Gradient.widgetAccent`.

- **WeatherKit** (`TruckWeatherCard`, `CityView`, entitlement `com.apple.developer.weatherkit`):
  - Truck's forecast card and City's current-conditions card both call `WeatherService.shared`. **Static-data fallback confirmed in both places**: `TruckWeatherCard` initializes its `@State forecast` to a fully hand-authored 25-hour placeholder curve and only overwrites it on success (silently keeps the placeholder forever on failure, only logging to console); `CityView` explicitly hard-codes `condition = .clear, willRainSoon = false, cloudCover = 0.15` inside its `catch` block. Both patterns mean a WeatherKit outage or missing entitlement degrades to plausible-looking canned weather rather than an error state or empty state — there's no "weather unavailable" UI anywhere.
  - City view additionally fetches and displays WeatherKit's **required legal attribution** (logo + link), themed light/dark.
  - In-app twin: the Truck dashboard's Weather card *is* the in-app equivalent of a hypothetical weather widget — same WeatherKit data source, no separate widget target consumes weather data in this codebase (the shipped widgets are Daily Donut / Orders / Parking Spot / Truck Activity only — no Weather widget).

- **Passkeys / Associated Domains** (`Entitlements-All.entitlements`: `com.apple.developer.associated-domains = [webcredentials:example.com]`): backs `AccountStore`'s `ASAuthorizationPlatformPublicKeyCredentialProvider` calls (relying party `"example.com"`, matching the domain). Also present: `com.apple.security.app-sandbox` and `com.apple.security.files.user-selected.read-only` (macOS sandboxing baseline). The plain `Entitlements.entitlements` (non-`-All` target) omits Associated Domains and WeatherKit — implying there are two build configurations/targets, a full-featured "All" one and a reduced one (consistent with the `EXTENDED_ALL` compile flag gating the Account sidebar entry).
- **App Store surfaces**: `Environment(\.requestReview)` review prompt (OrderCompleteView, throttled — see §2.2), `AppStore.sync()` restore-purchases calls (Account, Store Support, Social Feed+ Settings), `.manageSubscriptionsSheet`/`.refundRequestSheet`/`.offerCodeRedemption` StoreKit 2 system sheets, and the passive `StoreMessagesManager` singleton that arms/displays StoreKit's system interstitial messages (billing problems etc.) except while "sensitive" UI (donut editor) is open.
- **Live Activity push**: `Activity.request(..., pushType: nil)` — explicitly **no remote push updates**; the Live Activity is purely locally driven by its initial content + a stale-date, never refreshed by a server.
- **watchOS accessory families**: `OrdersWidget` and `ParkingSpotAccessory` both compile their accessory-family cases (`.accessoryCircular/.accessoryRectangular/.accessoryInline`) under `#if os(iOS) || os(watchOS)`, implying a shared complication/widget surface intended for a paired Watch, even though there's no dedicated watchOS app target traced in this source tree — likely relying on the iOS widget extension's automatic Watch complication relay, or an untraced separate target.

---

## 7. Notable UI details

### Custom `Layout` protocol conformances (SwiftUI `Layout`)
1. **`DiagonalDonutStackLayout`** (`FoodTruckKit/Sources/Donut/DiagonalDonutStackLayout.swift`) — places 1–3 subviews diagonally within a square: 1 view = centered full-size; 2 views = each offset diagonally (∓15%/∓20% of side length) at 70% scale; 3 views = middle subview centered at 65% scale, the other two diagonally offset (∓15%/∓23%) at 70%×65% scale. Purpose-built for `DonutStackView`'s "stack of up to 3 donuts" icon used throughout Orders (order thumbnails, Truck Orders card hero tile).
2. **`FlowLayout`** (`App/General/FlowLayout.swift`) — a general reusable wrap-flow layout (like CSS flexbox `flex-wrap`), configurable alignment (affects both per-row horizontal justification and cross-axis vertical alignment within a row) and optional fixed spacing (falls back to each subview pair's natural `ViewSpacing` distance). Used for the Truck Social Feed card's tag cloud and each social post's own tag row.
3. **`HeroSquareTilingLayout`** (nested in `App/Truck/Cards/TruckOrdersCard.swift`) — one large "hero" square (subview 0) plus up to 4 small tiles arranged 2×2 alongside it; purpose-built for the Truck Orders card's "5 most recent orders" tray.
4. **`DonutLatticeLayout`** (nested in `App/Truck/Cards/TruckDonutsCard.swift`) — configurable columns/rows/spacing (default 5×3), staggers alternating rows by a half-cell offset and one fewer column, producing a honeycomb/brick lattice; purpose-built for the Truck Donuts card.

All four are genuine `Layout` protocol conformances (`sizeThatFits`/`placeSubviews`) rather than nested stacks — i.e., real custom layout math, matching the task's callout of "the diagonal donut-thumbnail custom Layout."

### Animated truck/city scene
- **`BrandHeader`** (`FoodTruckKit/Sources/Brand/BrandHeader.swift`) is the animated hero banner used at the top of the Truck dashboard (and, non-animated/reduced-size, in the macOS menu-bar extra). Implementation: a `TimelineView(.animation(paused: !animated))` driving a single `Canvas` that manually composites ~10 pre-rendered image layers using `context.drawLayer`/`translateBy`/`rotate`/`scaleBy`:
  - A radial sky gradient background.
  - 7 **background parallax layers** (small clouds, medium clouds, mountains, big clouds, ocean, balloons, trees), each continuously rotating at its own independent period (180–840 seconds per full revolution) around a point below the visible frame — producing a slow, layered drifting-past effect rather than literal horizontal scrolling.
  - A static road layer + drawn truck shadow.
  - The **truck itself**, animated as a 4-frame sprite flipbook at 12 fps (`Frame 1`–`Frame 4` images), looping continuously.
  - 1 **foreground layer** rotating on a fast 96-second period (appears closest to camera, moves fastest — reinforcing parallax depth).
  - Sized to a fixed 200pt height (scaled by a `headerSize` of `.standard`(1.0) or `.reduced`(0.5)) but painted with `.padding(.top, -200*scale)` so its content bleeds upward into the navigation bar / top safe area.
- **`ParkingSpotShowcaseView`** (City view's hero) is a second "animated scene": also `TimelineView(.animation)`-driven, but instead of a `Canvas` it continuously recomputes an `MKMapCamera` (heading rotates a full 360° every 240s; pitch eases 50↔60° every 60s via the custom `symmetricEaseInOut` triangle-wave helper; camera distance is width-responsive — zooms out as the view narrows below 1000pt down to 350pt) and feeds it into the otherwise-non-interactive `DetailedMapView` — an "orbiting drone shot" effect over a real MapKit scene.

### `ImageRenderer`-based caching
- **`DonutRenderer`** (`FoodTruckKit/Sources/Donut/DonutRenderer.swift`) offers a rasterized-and-cached alternative to `DonutView`: on first appearance for a given donut id, it renders `DonutView` off-tree via `ImageRenderer` (proposed size = `donutThumbnailSize` = 128pt, scaled to the current display scale) into a static `Image` cached in a `static` dictionary keyed by donut id, shown thereafter as a plain resizable `Image` instead of re-compositing three stacked layered images every time; shows a small `ProgressView` while the render hasn't happened yet. (Not used by every donut-showing view in the traced code — several call `DonutView` directly — implying this is an available-but-optional optimization path, likely intended for contexts rendering many donuts at once.)

### Other notable animation/interaction patterns
- **`DonutBoxView`** (used by `OrderCompleteView`): 3-layer `ZStack` (box interior image, arbitrary `content` — typically a `DonutView` — inset by 15% of the box's side length, box bottom image, and an optional lid image that only exists in the view tree while `isOpen` and animates in/out via a combined `.scale(anchor:.bottom)` + upward `.offset` + `.opacity` transition).
- **`WidthThresholdReader`** — see §1; the app's one general-purpose adaptive-layout primitive, reused by Truck, Donut Editor, and Social Feed.
- **`ViewThatFits`** used once, in `RecommendedParkingSpotCard`, to progressively drop summary chips (3 → 2 → 1) as available width shrinks — SwiftUI's built-in "try each alternative until one fits" primitive, distinct from the hand-rolled `Layout`s above.
- **`contentTransition(.interpolate)`** used on the Truck Orders card's sales-count text so numeral changes cross-fade/morph rather than hard-cut.
- **`.matchedGeometryEffect`**: not found anywhere in the traced source — transitions instead lean on `.transition(.asymmetric(...))`, `.scale`, `.offset`, and `.opacity` combinators.

### Accessibility
- Dynamic Type is a first-class layout input, not an afterthought: `WidthThresholdReader` treats `dynamicTypeSize >= .xxLarge` as equivalent to being width-compact; `DonutGalleryGrid` separately treats `.xxxLarge` the same way for its own thumbnail-shrink decision; `SocialFeedTagLabelStyle`'s icon uses `@ScaledMetric` so tag-chip icons grow with text size.
- `TopDonutSalesChart`'s x-axis donut names use `.lineLimit(2, reservesSpace: true)` so 1- vs 2-line names don't jitter the chart's plotted height.
- `Label`s are used pervasively over raw icon+text `HStack`s (sidebar rows, order status, card headers, widget rows), which gets automatic accessibility-label composition "for free"; several call sites explicitly apply `.labelStyle(.iconOnly)` (toolbar buttons) where only the icon should read audibly as the button's name plus its `Label`'s hidden title, and `.labelsHidden()` is used on paired-control rows (e.g. `SignUpView`'s `LabeledContent` + field pattern, the flavor-profile `Gauge`s) to avoid duplicate announcements alongside an adjacent visible label.
- `Live Activity`/Dynamic Island content explicitly checks `\.isLuminanceReduced` (Always-On Display) and dims secondary text to 50% opacity rather than leaving it full-brightness (a burn-in/battery consideration more than a strict accessibility one, but handled via the same environment-driven pattern).
- `SegmentedGauge`'s custom `Shape` explicitly reads `\.layoutDirection` and mirrors which end of the segment row gets fully-rounded (capsule) corners for right-to-left locales.

### Localization
- Every user-facing string in `FoodTruckKit` is wrapped in `String(localized:bundle:comment:)` with descriptive translator comments (e.g. "A donut-flavor name.", "Order status."), and the package declares `defaultLocalization: "en"`.
- Three separate resource/localization bundles exist for `en` and `ar` (Arabic): the app target (`App/{en,ar}.lproj`), the `FoodTruckKit` package resources (`Sources/Resources/{en,ar}.lproj`), and the Widgets extension (`Widgets/ar.lproj`) — each target localizes independently, consistent with SwiftUI package/module localization boundaries (a `bundle: .module` string in `FoodTruckKit` pulls from the package's own catalog, not the app's).
- Arabic is a real RTL localization target, not just a string-only translation: `SegmentedGauge`'s corner-rounding logic (used by the Orders accessory widget) is the one place in the traced code with explicit RTL-aware geometry.
- Several strings use `LocalizedStringKey` directly in model data (`SocialFeedPost.message`, `SocialFeedTag.title`) rather than plain `String`, allowing that fixture copy to carry markdown-like formatting/localization the same way literal `Text` would.
