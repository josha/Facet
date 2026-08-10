# Reference-source inspection record — swiftui-reference-app-validation

**Stage start:** 2026-08-08 (all fetches and observations below performed this day).

## Intellectual-property boundary (binding for every artifact in this stage)

The sources below are **behavioral references only**. Every proof in this stage uses
original names, copy, data, and visual assets. No Apple or Roblox source code, art,
trade dress, or product identity is copied into this repository. The downloaded
Apple sample archives were inspected in a session-scratch directory outside the
repository and are not committed. Feature inventories describe behavior in our own
words and cite file/type names only as identifying references.

## Apple samples (official pages + downloadable source)

Fetched from developer.apple.com on 2026-08-08 via the documentation JSON endpoints;
source archives downloaded from docs-assets.developer.apple.com the same day.

| Sample | Official page | Published platform baseline | Archive identity |
|---|---|---|---|
| Backyard Birds: Building an app with SwiftData and widgets | developer.apple.com/documentation/SwiftUI/Backyard-birds-sample | iOS/iPadOS/Mac Catalyst 17.2, macOS 14.2, watchOS 10.2, Xcode 15.1 (WWDC23 session 102) | `7f06a68fb95e/BackyardBirdsBuildingAnAppWithSwiftDataAndWidgets.zip` (7.7 MB) |
| Food Truck: Building a SwiftUI multiplatform app | developer.apple.com/documentation/swiftui/food-truck-building-a-swiftui-multiplatform-app | iOS/iPadOS/Mac Catalyst 16.4, macOS 13.3, Xcode 14.3 (WWDC22) | `dd9087d16d30/FoodTruckBuildingASwiftUIMultiplatformApp.zip` (52 MB) |
| Fruta: Building a feature-rich app with SwiftUI | developer.apple.com/documentation/appclip/fruta-building-a-feature-rich-app-with-swiftui | iOS/iPadOS/Mac Catalyst 15.4, macOS 12.3, Xcode 13.3 (WWDC21/20) | `15035f283d6a/FrutaBuildingAFeatureRichAppWithSwiftUI.zip` (73 MB) |

Page-abstract behavior recorded at fetch time:

- **Backyard Birds** — garden/backyard environment with visiting birds; monitor and
  refill water and food supplies; SwiftData persistence; in-app purchase store shelf
  with a prominently featured item plus renewable-subscription page (StoreKit views);
  interactive widgets via App Intents (host-OS surface).
- **Food Truck** — one multiplatform target; `NavigationSplitView` sidebar + detail;
  Truck dashboard whose New Orders panel shows the five most recent orders with a
  diagonal donut-thumbnail stack built on the custom `Layout` protocol; order
  tracking; popularity/sales charts (Swift Charts); WeatherKit with a documented
  static-data fallback; Live Activities / Dynamic Island order-prep countdown
  (host-OS surfaces); passkeys in the full target.
- **Fruta** — smoothie catalog: browse and order, save favorites, collect rewards,
  browse recipes; deeply localized; widgets and an App Clip that reuses shared
  code for an instant entry flow (host-OS surfaces); StoreKit recipe unlock;
  Sign in with Apple / Apple Pay in the full target.

Full per-sample behavioral inventories (from reading the downloaded source):
`sources/features-backyard-birds.md`, `sources/features-food-truck.md`,
`sources/features-fruta.md` in this artifact directory.

## Roblox desktop app (macOS), observed live 2026-08-08

Director-supplied screenshots (home screen ~1425 px wide; Marketplace/Customize
avatar-editor view) plus a live launch of the installed macOS app in this session.

**Home (discovery) screen, wide (~1425 px):**

- Left icon nav rail (Home, Moments, Build, Chat, Me, More) with the active item
  emphasized; brand mark top-left; center search field; profile chip, settings
  gear, and a badged notification bell top-right.
- `For you | Charts` tab pair with an underline selection indicator.
- Friends row: horizontally scrolling carousel of circular avatar portraits with
  names; leading "Add Friends" affordance carrying a numeric badge.
- Sectioned vertical feed: "Recommended For You" as a 4-column card grid (large
  16:9 thumbnail, title, thumbs-up percent rating, an "Ad" disclosure on sponsored
  rows); "Continue" section header with a chevron affordance leading a horizontal
  shelf of square tiles. Further sections continue below the fold.

**Home screen, narrow (~700 px, observed live via window resize):**

- The card grid reflows 4 → 2 columns; the search field collapses to an icon; the
  nav rail persists with labels; the friends carousel and tab pair span the
  narrower width. (A beta-program "Update Required" modal appeared over the feed
  during observation — modal presentation with a scrim and single action — and the
  session was ended there; no account state was modified.)

**Marketplace / avatar editor (from the director's screenshot):**

- Top center segmented control `Marketplace | Customize | Profile`.
- Category tab row (All, Avatars, Body, Clothing, Accessories, Backgrounds,
  Animations, Makeup) with underline indicator and a trailing filter affordance;
  search icon.
- Item grid: cards with thumbnail, name, creator (verified badge), currency icon +
  price. Inline section header ("Just For You") inside the feed.
- Right pane (~40% width): live 3D avatar preview on a neutral 3D backdrop with
  floating controls — avatar chip, avatar-settings toggle, undo and redo buttons —
  and a currency balance pill top-right. Selecting an item try-equips it on the
  preview (undo/redo operate on the equip history); purchase is a separate
  explicit flow showing the price.
- Compact behavior (known from the phone app, to be treated as the compact
  arrangement of the same tree): preview on top, catalog as the scrolling region
  below, categories as a horizontally scrolling chip row.

**Host-platform note:** the Roblox app itself is a native/desktop shell, not an
in-experience surface. These two screens are treated exactly like the Apple
samples — behavioral references for clean-room, original-content proofs. The 3D
preview pane maps to an in-experience `ViewportFrame` (a Roblox-native capability),
and the production services a real game would own (catalog data, inventory,
purchase, friends/presence, recommendations) are mapped in the responsibility
ledger and faked deterministically in the proof.
