# Responsibility ledger — swiftui-reference-app-validation

Written 2026-08-08, before any proof code. Three columns of ownership, fixed for
every proof; violations are gate failures, not style notes.

## The split

**LuauUI owns (reusable, public API only):** layout + adaptation (stacks, Grid,
Composition/Region, ViewThatFits, AdaptiveStack), focus + traversal + keyboard
conventions, semantic actions (Activate/Cancel/Navigate/Adjust), presentation
(present/presentModal/presentToast, transitions, scrims, disclosure), motion
(clock, springs, timelines, reduced-motion parity), text measurement +
preferred-text reflow + lineLimit/disclose/reveal, theme packages + style
authority, drag/drop, async resources, scroll + keep-visible, diagnostics.

**Each proof owns (domain, deterministic):** all content and copy (original,
clean-room), domain state signals and commands, fake services (below), string
tables + pseudo-locale, seeds, scenario registration + reset, art assets
(original), and the 3D content handed to the Viewport leaf (P5/P2).

**Forbidden in proofs (gate check `responsibility-ledger`):** raw GuiObject
construction, `UserInputService`/local key listeners, a second focus or layout
system, device-name/platform-name branches (facts and size classes only),
wall-clock/`math.random` in domain logic, any network call, any real purchase or
player-data write, any workaround that re-implements framework behavior locally.

## Fake services and their production mapping

Every fake is: pure Luau, injectable clock/seed, command → `idle → pending →
confirmed | rejected` lifecycle with scripted rejection fixtures, and resettable
from the scenario runner.

| Proof | Fake service (deterministic) | Production Roblox service a real game would own |
|---|---|---|
| P1 Glade | `SupplyService` — refill timestamps, drain constants, derived levels | server-authoritative time + DataStore per player |
| P1 Glade | `CommerceService` — food-pack ledger, pass tiers, upgrade path | `MarketplaceService` developer products (consumables) + `PromptSubscriptionPurchase` (tiers); receipts server-processed; **prompt UI itself is a host sheet — the in-experience UI ends at the prompt call** |
| P1 Glade | `VisitScheduler` — seeded past/current/future visit windows | server sim + DataStore; tier-gated content via entitlement facts |
| P2 Cartwheel | `OrderService` — seeded backlog + scripted arrivals, status commands, prep countdown fact | MemoryStore queue / server sim; countdown = server time fact replicated |
| P2 Cartwheel | `StatsService` — per-city seeded popularity/history series | analytics/telemetry aggregation service |
| P2 Cartwheel | `AmbientService` — deterministic "weather-shaped" ambient series | none (WeatherKit has no host equivalent); a real game would own its own ambient sim |
| P2 Cartwheel | `EntitlementService` — social-plus subscription, history unlock | Roblox Subscriptions + game pass / developer product |
| P2 Cartwheel | `IdentityService` — signed-in fact, sign-up command | Roblox identity is ambient (`Players.LocalPlayer`); passkeys/password have no in-experience role — the sign-up form is kept as a UI-capability exercise and says so |
| P3 Sipworks | `CatalogService` — items, measured ingredients, nutrition-shaped facts | static content modules / backend catalog |
| P3 Sipworks | `FavoritesService`, `RewardsService` (points, threshold redeem), `RecipeUnlockService` | DataStore (favorites, points); `MarketplaceService` non-consumable-shaped product for the unlock |
| P3 Sipworks | `OrderService` — order command, scripted ready-flip | server command + replicated status |
| P3 Sipworks | `I18nService` — locale tables incl. plural fixtures + ~1.4× pseudo-locale, list/measure formatting | `LocalizationService`/`Translator:FormatByKey`; expansion axis stays a fixture |
| P3 Sipworks | compact entry context — `entry = "compact-link"` fact + item deep-link id | join `launchData` (`Player:GetJoinData`), validated server-side |
| P4 Foyer | `FeedService` — seeded sections/tiles/ratings/ad flags; `FriendsService` — seeded presence carousel; `SearchService` — filter over the feed | game backend + platform: `Players:GetFriendsAsync`, presence, experience search/discovery (platform-owned outside the experience) |
| P5 Wardrobe | `WardrobeCatalog` — categorized items, creators, prices; `InventoryService` — owned items; `EquipService` — equip/undo/redo history; `WalletService` — balance, purchase confirm/reject | AvatarEditorService (inspect/save), `MarketplaceService:PromptPurchase`, inventory via platform/DataStore; preview rig from `HumanoidDescription` |

## Apple host-OS behavior (never faked, never counted against LuauUI)

Widgets, watch complications, App Intents/Siri, Live Activities, Dynamic Island,
local notifications, App Clips (incl. location verification + install overlay),
WeatherKit, StoreKit system sheets (product/subscription purchase chrome, manage,
refund, offer codes, review prompts), Sign in with Apple, passkeys, Apple Pay
chrome, MenuBarExtra, `matchedGeometryEffect`-style cross-window continuity.
Each appears in the capability ledger as **no host equivalent** with its nearest
production analog named where one exists (join `launchData` for App-Clip entry;
`MarketplaceService`/Subscriptions prompts for commerce chrome). The proofs do
not simulate any of these and the audit never claims parity for them.

## Framework-fix protocol (RA-7)

A reusable defect or missing behavior found while building a proof is fixed in
LuauUI first — schema + tests + docs + live slice — then consumed by the proof;
the Rascal Rally consumer-lockstep rule applies to every such change. If the fix
is not bounded (see capability ledger §G), the proof ships the declared honest
approximation and the gap ships as an evidence-backed proposal in
`framework-fixes.md`. No proof may carry a local workaround past gate close.

**PolicyService (platform review T6, added at close):** a shipping experience
gates commerce and social surfaces on
`PolicyService:GetPolicyInfoForPlayerAsync` (`ArePaidRandomItemsRestricted`,
`AllowedExternalLinkReferences`, ads eligibility). Every purchase-shaped,
ad-disclosure, and social surface in these proofs would consult it in
production before presenting; the proofs' deterministic services stand in for
that consultation the same way they stand in for MarketplaceService.
