# Parity completeness audit — what `swiftui-parity.md` never looked at

**Report only. This audit changed no library, example, test, or shipped document.**
It does not edit `docs/reference/swiftui-parity.md`; other agents own that file.

**Headline: 39 genuinely unexamined capabilities.**

---

## 1. What this measures, and why it is a different question

`docs/reference/swiftui-parity.md` scores capabilities as Covered / Partial /
Composable / **Missing**. "Missing" is a *finding*: we looked, and we do not have
it. A SwiftUI capability that never entered the table is not Missing — it is
**unexamined**, and from inside the document the two are indistinguishable. The
governing roadmap concedes the bound explicitly:

> "Its original 69-item count is a bounded catalog, not a percentage score for all
> of SwiftUI." — `docs/plans/parity-next.md:43-44`

That concession lives in a *plan* file. The parity document itself never restates
it (see §6, meta-finding 1). This audit measures what lies outside the bound.

**The instrument.** Apple's DocC symbol index for SwiftUI —
`https://developer.apple.com/tutorials/data/index/swiftui` — pulled 2026-08-13.
It returned 1,378,939 bytes of JSON containing **10,988 nodes**: 3,076 methods,
2,230 properties, 1,043 initializers, 954 structs, 335 enum cases, 123 protocols,
96 enums, 76 collections, 27 macros, plus group markers and articles. The
human-facing root is <https://developer.apple.com/documentation/swiftui>.

---

## 2. The grouping rule

A raw symbol diff is useless: `func defaultSize(...)` alone appears five times,
`draggable` seven, `alert` ten. Every overload would read as a separate gap.

**The rule I used: one capability = one `groupMarker` heading on one of Apple's 49
SwiftUI collection landing pages.** These are Apple's own editorial groupings —
"Configuring a sheet's height", "Setting a layout direction", "Reordering items" —
and they are exactly the altitude a UI framework reasons at. They collapse
overload families automatically (all ten `alert` overloads sit under "Presenting an
alert") without collapsing genuinely distinct capabilities (`presentationDetents`
gets its own group, separate from `.sheet` itself).

That yields **392 capability groups across 49 collections**. Reproduction:

```python
import json, urllib.request
d = json.load(urllib.request.urlopen(
    "https://developer.apple.com/tutorials/data/index/swiftui"))
mod = d["interfaceLanguages"]["swift"][0]
for c in mod["children"]:
    if c.get("type") == "collection":
        for k in c.get("children", []):
            if k.get("type") == "groupMarker":
                print(c["title"], "|", k["title"])
```

**27 of the 392 are navigation scaffolding, not capabilities** — "Essentials",
"Deprecated types", "Supporting types", "Accessing geometric constructs",
"Choosing a layout" (article links only). Those are dropped from the denominator,
leaving **365 scored capability groups**.

**Where the rule is imperfect, and how I compensated.** Apple's groups are
uneven: "Preferences" splits one mechanism across five groups, while "Controlling
text style" packs seven distinct text attributes into one. So §5 reports the
*deduplicated* capability count (39) alongside §3's *group-level* count (64). The
group count is the mechanical, reproducible number; the deduplicated count is the
one a roadmap can consume. Both are stated so neither can be quoted as the other.

---

## 3. The three buckets — group-level counts

Every one of the 365 scored groups got exactly one verdict. Counts sum to 365.

| Bucket | Groups | Share |
|---|---:|---:|
| **Not applicable to Roblox** — no engine substrate exists | **120** | 33 % |
| **Applicable but deliberately out of scope** | **54** | 15 % |
| **Examined** — the parity doc names it under some verdict | **127** | 35 % |
| **Applicable and genuinely unexamined** | **64** | 18 % |

### 3.1 Not applicable to Roblox — 120 groups, and *why*

These are not assertions of "we don't need it." Each rests on a missing substrate.

| What | Groups | Why no Roblox substrate |
|---|---:|---|
| Scenes, Windows, Documents, App organization, Immersive spaces ([windows](https://developer.apple.com/documentation/swiftui/windows), [scenes](https://developer.apple.com/documentation/swiftui/scenes), [documents](https://developer.apple.com/documentation/swiftui/documents), [immersive-spaces](https://developer.apple.com/documentation/swiftui/immersive-spaces)) | 36 | A Roblox client is a single fullscreen viewport with no OS window model, no multi-window scene graph, no document architecture, and no ARKit-backed immersive space. `WindowGroup`, `defaultPosition`, `windowResizability`, `NSApplicationDelegateAdaptor` have nothing to bind to. |
| [Technology-specific views](https://developer.apple.com/documentation/swiftui/technology-specific-views) | 26 | WebKit, PassKit/Apple Pay, AuthenticationServices, HealthKit, StoreKit, MapKit, PhotosUI, TipKit, Translation, GroupActivities. Each is an Apple OS framework; Roblox exposes none of them. |
| [AppKit](https://developer.apple.com/documentation/swiftui/appkit-integration) / [UIKit](https://developer.apple.com/documentation/swiftui/uikit-integration) / [WatchKit](https://developer.apple.com/documentation/swiftui/watchkit-integration) interop | 10 | `NSViewRepresentable`, `UIHostingController`, gesture-recognizer bridging — there is no second UI toolkit on the other side of the bridge. Roblox's `GuiObject` tree *is* the substrate Facet targets. |
| [System events](https://developer.apple.com/documentation/swiftui/system-events) | 6 | `NSUserActivity`, Handoff, `onOpenURL`, background tasks — no OS activity/URL routing reaches a Roblox client script. |
| [App extensions](https://developer.apple.com/documentation/swiftui/app-extensions) | 6 | WidgetKit, control widgets, Dynamic Island. Host-OS surfaces; the reference-app ledger already classifies these as "no host equivalent" (`swiftui-parity.md:1021-1028`). |
| File dialogs (import/export/move/configure, in [modal-presentations](https://developer.apple.com/documentation/swiftui/modal-presentations)) | 4 | No user-visible filesystem is reachable from a Roblox client. |
| Metal shaders, `ImageRenderer`, `TextRenderer`, `blendMode`/colour filters ([drawing-and-graphics](https://developer.apple.com/documentation/swiftui/drawing-and-graphics)) | 5 | Roblox exposes no GUI shader entry point, no view→bitmap rasteriser, no custom glyph-rendering hook, and no per-node colour-filter or blend-mode channel on `GuiObject`. |
| [Clipboard](https://developer.apple.com/documentation/swiftui/clipboard) | 2 | I found no player-facing clipboard read/write API in the Roblox engine reference. `TextBox` accepts an OS paste into itself, but `copyable`/`pasteDestination` have no programmatic counterpart. *Stated as "found none", not as proof of absence.* |
| Dictation, Writing Tools, Digital Crown, Touch Bar, camera capture events, Apple Pencil, spatial events, assistive access, invert-colors, large content viewer, contrast preference, `visionOS` ornaments/glass backgrounds/passthrough, Xcode library items, preview scene contexts | 25 | Each depends on an Apple input device, an Apple OS accessibility signal, or Xcode itself. Roblox surfaces no equivalent preference or device channel. Note the asymmetry: Roblox *does* surface Reduce Motion and Preferred Text Size, and Facet reads both — the absent ones are absent from the platform, not from Facet. |

### 3.2 Applicable but deliberately out of scope — 54 groups

Plausible on Roblox, but not what this framework is for. The three reasons:

1. **Chrome for a navigation model that is already scored Missing (21 groups).**
   All ten remaining [Toolbars](https://developer.apple.com/documentation/swiftui/toolbars)
   groups past item-hosting, plus navigation-bar/sidebar/tab-customisation config,
   plus sheet styling and dialog icon/severity/suppression. `swiftui-parity.md:852`
   already scores `NavigationStack` as "Partial at best"; its decorations cannot be
   separate findings.
2. **Deliberate design decisions already on record (14 groups).** Every `*Style`
   protocol group ([view-styles](https://developer.apple.com/documentation/swiftui/view-styles))
   is out of scope by the §6.1 ruling; custom animation curves are out by the
   "springs come from four registered classes, inline literals are a hard error"
   rule (`swiftui-parity.md:713-717`); `accessibilityIdentifier` is out because
   node paths already serve that role.
3. **Genuinely peripheral to a game UI (19 groups).** Section-index scrubbers,
   find-and-replace navigators, type-select equivalents, `MultiDatePicker`,
   `EditButton`/`PasteButton`/`RenameButton`/`HelpLink`, `@AppStorage`-style
   persistence (Facet ships `replication` and game data is the game's job),
   list-item tint, chart descriptions, `resetFocus`, `focusedObject`.

### 3.3 Examined — 127 groups

The document's real coverage. It is strongest exactly where Facet is strongest:
[layout-fundamentals](https://developer.apple.com/documentation/swiftui/layout-fundamentals)
is 7/7 examined, [model-data](https://developer.apple.com/documentation/swiftui/model-data)
4/4, [accessible-descriptions](https://developer.apple.com/documentation/swiftui/accessible-descriptions)
7/8 (all rolled into one honest "no AT bridge" Missing),
[controls-and-indicators](https://developer.apple.com/documentation/swiftui/controls-and-indicators)
9/11, [animations](https://developer.apple.com/documentation/swiftui/animations) 7/13.

It is weakest in [view-groupings](https://developer.apple.com/documentation/swiftui/view-groupings)
(2/7), [custom-layout](https://developer.apple.com/documentation/swiftui/custom-layout)
(1/4), [preferences](https://developer.apple.com/documentation/swiftui/preferences)
(0/5), and [scroll-views](https://developer.apple.com/documentation/swiftui/scroll-views)
(3/12). Those four collections supply 19 of the 64 unexamined groups and,
notably, all four of the highest-cost findings in §5.

---

## 4. Before the findings: four things that are shipped but never rowed

These are **document defects, not roadmap gaps**. They belong to whoever next
edits the parity table, not to a mission. I verified each in source.

| Capability | Where it already ships | Where the doc mentions it |
|---|---|---|
| `AsyncImage` — async-loaded image with a placeholder phase ([images](https://developer.apple.com/documentation/swiftui/images)) | `Facet.newAsyncImage` (`src/init.luau`; `src/controls/async_image.luau`) — placeholder-on-pending, silent-failure-keeps-placeholder | Only as the name of a perf scene (`async-image-burst`, `swiftui-parity.md:894`). No capability row. |
| `compositingGroup()` / `drawingGroup()` — flatten a subtree into one composited layer | The `canvasGroup` prop on `Box`/`ZStack` (`src/blueprint_schema.luau:919,1047`) | Nowhere. |
| `.keyboardType` — soft-keyboard kind for text entry | `TextField.keyboardType` (`src/blueprint_schema.luau`, TextField class) | Nowhere. |
| `accessibilityReduceTransparency` — the OS "reduce transparency" preference | `effectiveTransparency` environment key (`src/env/environment.luau`) | Named once in a list of clamping env values (`swiftui-parity.md:150`), never as an accessibility capability. |

One near-miss worth recording so it is not re-filed as a gap: **`.onSubmit` is
reachable today.** `TextField.onFocusLost(reason)` takes `reason ∈ enter |
focusLost | cancel` (`src/blueprint_schema.luau:1787-1791`), so submit-on-Return is
a one-line consumer check. It is Composable, not Missing — but the doc says
neither.

---

## 5. The finding — 39 genuinely unexamined capabilities

The 64 unexamined groups deduplicate to **39 named capabilities** (Apple splits one
mechanism across several groups; `Preferences` alone is 5 groups for 1 capability).

**Ranked by how likely a real Roblox game screen is to want it**, not by how
interesting it is. Cost signals are `prop` / `control` / `solver` / `seam` /
`subsystem`, in ascending order of expense. **These are reconnaissance notes, not
designs.**

### Tier 1 — a common Roblox game screen wants this (1–13)

| # | Capability | What it does (SwiftUI) | Why a Roblox game UI wants it | Cost |
|---:|---|---|---|---|
| 1 | **Inline text run styling** — [`bold`/`italic`/`underline`/`strikethrough`/`monospaced`/`textCase`](https://developer.apple.com/documentation/swiftui/text-input-and-output) | Style spans *inside* one string, or the whole run. | "Press **[E]** to enter", rarity-coloured item names, damage numbers, tutorial copy with a highlighted key. Roblox ships the substrate: `TextLabel.RichText` renders bold/italic/colour spans ([`TextLabel`](https://create.roblox.com/docs/reference/engine/classes/TextLabel)). Facet has no `richText` prop — the only `RichText` reference in `src/` is a mirrored read in `screen_chrome.luau:653` for the disclosure clone. | **prop + solver** (the text-measure pass must measure marked-up strings, and `docs/lessons/roblox-text-bounds-boot-window.md` says that path is already delicate) |
| 2 | **2-D transform effects** — [`rotationEffect`, `scaleEffect`, anchors](https://developer.apple.com/documentation/swiftui/drawing-and-graphics) | Rotate or scale a painted node about an anchor without changing its layout box. | Spinners that actually spin (the shipped indeterminate `ProgressView` had to become five pulsing dots *because* "the blueprint has no rotation or trim channel", `swiftui-parity.md:399`), needle gauges, speedometer dials, press-pop juice, tilted cards. Substrate exists: `GuiObject.Rotation` is a real degrees property ([`GuiObject`](https://create.roblox.com/docs/reference/engine/classes/GuiObject)) and Facet already drives `UIScale` internally. | **prop + seam** — and the seam is the hard part: `src/render/authority.luau:250-253` records that the engine honours exactly one `UIScale` per object and the presentation channel already claims it |
| 3 | **Scoped environment overrides + consumer-defined environment keys** — [`.environment(_:_:)`, `EnvironmentKey`, `@Entry`](https://developer.apple.com/documentation/swiftui/environment-values) | Override an ambient value for one subtree; define your own ambient keys. | "This panel is compact regardless of screen size", "this section paints in the danger palette", "everything under here is in preview mode". Facet's environment is a **flat, surface-global table with a closed key set**: `env.get`/`set` assert on unknown keys (`src/env/environment.luau:316-333`) and there is no subtree scoping at all. Today the only route is threading a spec parameter down by hand — exactly what `picker.luau` and `popup_button.luau` do with `sizeClass` (`swiftui-parity.md:165-175`). | **subsystem** |
| 4 | **Programmatic scroll position** — [`scrollPosition(id:)`, `ScrollViewReader`, `defaultScrollAnchor`](https://developer.apple.com/documentation/swiftui/scroll-views) | Read and write which item is scrolled to, and restore it. | Jump to the equipped item, jump to the newest chat line, restore a shop's scroll on tab return, "scroll to your rank" on a leaderboard. The machinery exists but is private: `controller.scrollToVisible(path)` is called only by the presenter's keep-visible logic (`src/present/presenter.luau:3190-3197`), and `virtual_list`'s `scrollTop` signal is internal (`src/controls/virtual_list.luau:101-117`). | **seam** (mostly exposure of what exists) |
| 5 | **Scroll snapping / paging targets** — [`scrollTargetBehavior(.paging)`, `.viewAligned`, `scrollTargetLayout`](https://developer.apple.com/documentation/swiftui/scroll-views) | Scrolling settles on item or page boundaries instead of anywhere. | Character-select reels, banner carousels with page dots, weapon wheels, tutorial pagers. Sharpened by what shipped on 2026-08-13: `containerRelativeFrame`'s paging form gives a carousel the right *sizes* (`swiftui-parity.md:209`) with nothing to make it *land* on them. Roblox's `ScrollingFrame` has no native snapping. | **control + solver** |
| 6 | **Sections and section headers in collections** — [`Section`](https://developer.apple.com/documentation/swiftui/view-groupings), [list header/separator config](https://developer.apple.com/documentation/swiftui/lists) | Group rows under a header, optionally pinned while scrolling. | Settings grouped by category, a shop by tier, an inventory by item type, a friends list split online/offline. `swiftui-parity.md:218` names "no pinned section headers" as a `VirtualList` divergence; the broader absence of any `Section` construct is unstated. `grep -rn "sectionHeader" src/` returns nothing. | **control + solver** (pinning is a real arrange change) |
| 7 | **Localization surface** — [`LocalizedStringKey`, plural/gender rules, locale-aware formatting](https://developer.apple.com/documentation/swiftui/text-input-and-output) | Player-facing strings resolve through a catalog with grammatical agreement. | Every shipped Roblox game with a global audience. Roblox ships the substrate — `LocalizationService`, `LocalizationTable`, `Translator`, `GuiBase2d.AutoLocalize` ([`LocalizationService`](https://create.roblox.com/docs/reference/engine/classes/LocalizationService)). Facet has a `locale` env fact defaulting to `"en-us"` (`src/env/environment.luau:80`) and nothing else; the reference-app proof hand-rolled its own plural fixtures (`swiftui-parity.md:1005`). *Apple's docs do not describe Roblox's plural-rule support, and Roblox's own page does not mention plurals — recorded as unknown rather than inferred.* | **subsystem** |
| 8 | **`Form` / `LabeledContent`** — [labelled input rows](https://developer.apple.com/documentation/swiftui/view-groupings) | A container that gives every row a label-and-control arrangement with consistent alignment, automatically. | Every settings screen, every graphics-options panel, every audio mixer. Today each row is hand-built from `HStack + Text + control`, and label-column alignment across rows is the author's problem — which is precisely the case baseline alignment (`swiftui-parity.md:211`, Missing) would otherwise serve. `grep -rn "newForm\|LabeledContent" src/` returns nothing. | **control** |
| 9 | **`.disabled()` subtree cascade** — [view interaction](https://developer.apple.com/documentation/swiftui/view-configuration) | One modifier disables an entire subtree, cascading through the environment. | "Requires level 10" locking a whole panel; a section greyed until a purchase completes; a form disabled while a request is in flight. Facet has per-control `enabled` on `Button`/`Toggle`/`TextField` only — three separate leaves, no cascade. The engine even has the leaf-level substrate (`GuiObject.Interactable`), and `active` is only the input-sinking flag for modal backdrops (`src/blueprint_schema.luau`). | **prop + seam** (a cascading channel, plus paint for the disabled look) |
| 10 | **Empty-state control** — [`ContentUnavailableView`](https://developer.apple.com/documentation/swiftui/controls-and-indicators) | A standard "nothing here" view with icon, title, description, and optional action. | Empty inventory, no friends online, no search results, no daily quests left. Universally needed, universally hand-rolled inconsistently. Nothing in `src/controls/` addresses it. | **control** |
| 11 | **Pull-to-refresh** — [`refreshable`](https://developer.apple.com/documentation/swiftui/lists) | A downward over-drag on a collection triggers an async reload with a built-in indicator. | Leaderboards, friend lists, shop restock, server browsers. It is the touch-native idiom for "get me fresh data", and Facet's async story (`newResourceProvider`) already has the reload half. `grep -rn "pullToRefresh\|refreshable" src/` returns nothing. | **control + seam** (gesture arbitration against the scroller) |
| 12 | **View lifecycle hooks** — [`onAppear` / `onDisappear`](https://developer.apple.com/documentation/swiftui/view-fundamentals) | Run code when a view enters or leaves the tree. | Fire analytics when a screen opens, start a preview animation when a card scrolls in, stop an engine sound when a panel closes, begin a countdown only while visible. `grep -rn "onAppear" src/` returns **zero hits**. Mount scopes exist and own disposal (`src/core/scope_impl.luau`), so the lifetime is already tracked — what is missing is the author-facing hook. | **prop** |
| 13 | **Scroll observation** — [`onScrollGeometryChange`, `onScrollPhaseChange`, `onScrollVisibilityChange`](https://developer.apple.com/documentation/swiftui/scroll-views) | Observe offset, phase (dragging/decelerating/idle), and item visibility as the user scrolls. | Parallax headers, a title bar that condenses on scroll, infinite-scroll load triggers, "seen" analytics, pausing expensive art while flinging. Facet reads scroll geometry internally on the scroll cadence for the row-actions floating menu (`swiftui-parity.md:246-247`) — proof the cadence exists and is not exposed. | **seam** |

### Tier 2 — a specific but real screen wants this (14–26)

| # | Capability | One-sentence what | Why a Roblox game UI might want it | Cost |
|---:|---|---|---|---|
| 14 | **Tooltips** — [`.help()`](https://developer.apple.com/documentation/swiftui/view-configuration) | Attach explanatory text surfaced on hover or focus. | Stat explanations on desktop/console, "what does this perk do", icon-only toolbars. `presenter.disclosure()` (`swiftui-parity.md:860`) is an adjacent presenter-private surface — the mechanism is close, the capability is absent. **Update 2026-08-16 (navigation-and-menus D2):** the gesture question this row would otherwise have to answer is already settled. Touch long-press stays with the disclosure plate — it is the only touch route to a truncated label's full value — and `newMenu` carves out only its own trigger subtree. A tooltip therefore binds **no** gesture, matching Apple (`.help` is pointer-hover/focus only and invisible on touch), and `tests/menu.spec.luau` fails if it starts competing. **CLOSED 2026-08-16 (navigation-and-menus D3), and it took TWO constructs rather than one.** Apple separates a tooltip from a coach mark and this row conflated them: `.help(_:)` is player-PULLED, pointer-hover/focus only and invisible on touch, and ships as a PROP (`UI.Button{ help = "…" }`) presented through the anchored seam's chrome mode; the auto-popping plate with an arrow tail is TipKit's `popoverTip`, app-PUSHED from eligibility rules, and ships as `Facet.newCallout`. Because help shows nothing on touch it may never be the only route to something a player needs, so it arrived with the check that says so: `text_audit.helpRoutes` reports both a help string the screen paints nowhere else and — the half no waiver may silence — help that no live gesture reaches. | **control + seam** |
| 15 | **Tab-based navigation** — [`TabView` / `Tab` / `TabSection`](https://developer.apple.com/documentation/swiftui/navigation) | A container whose children are selectable tabs with a placement-adaptive bar. | The single most common Roblox menu shape (Shop / Inventory / Quests / Settings). `adaptive.navPlacement` decides *where* a tab bar goes (`swiftui-parity.md:206`) and all five reference apps built the bar by hand — the policy shipped, the construct did not. **CLOSED 2026-08-16 (navigation-and-menus D5): `Facet.newTabView`.** Placement from `adaptive.navPlacement`, a strip that IS `newPicker` rather than a second option row, lazy content EVICTED on switch through `UI.When`'s own branch scope, an overflowing strip that scrolls the selection into view through `controller.scrollToVisible`, and nesting with an explicit rule — an inner TabView never claims the app-level placement. `examples/reference/p4_foyer` is migrated onto it, which deleted its four `When`-gated bars, its three copies of the wing list and its hand-rolled active bar. | **control + seam — DONE** |
| 16 | **Authorable opacity, and a space-reserving hide** — [`opacity`, `hidden()`](https://developer.apple.com/documentation/swiftui/view-configuration) | Fade a node; or hide it while it still occupies its layout box. | Ghosted locked items, fading a HUD element out, reserving a slot for a value that is not ready yet. Facet's `transparency` is owned by the presentation channel (`src/render/authority.luau:59`), not authorable, and there is no `opacity` box prop. The distinction matters: `UI.When` removes the node, and Roblox's `Visible = false` **frees the layout space** ([`GuiObject`](https://create.roblox.com/docs/reference/engine/classes/GuiObject)) — neither is SwiftUI's `.hidden()`. | **prop** |
| 17 | **Text truncation and auto-shrink controls** — [`truncationMode`, `minimumScaleFactor`, `allowsTightening`](https://developer.apple.com/documentation/swiftui/text-input-and-output) | Choose where a too-long string breaks, or let it shrink instead. | Long player names in a leaderboard, item names in a fixed slot, localized strings that overflow their box — which the standing localization lesson says must never clip. Roblox ships `TextTruncate` (`None`/`AtEnd`/`SplitWord`) and `TextScaled` ([`TextLabel`](https://create.roblox.com/docs/reference/engine/classes/TextLabel)); Facet exposes `lineLimit` and `compactLabel` but neither of these. | **prop + solver** |
| 18 | **Consumer-authored layout containers** — [`Layout`, `LayoutSubview`, `ProposedViewSize`, `LayoutValueKey`](https://developer.apple.com/documentation/swiftui/custom-layout) | A third party writes a real layout algorithm that participates in measure and arrange as a first-class container. | Ranked low on "a game screen wants this" and high on leverage: **the two named layout gaps would stop being framework missions.** Flow-wrap (`swiftui-parity.md` §4.3 — "its own mission, not a prop", and the one place Facet is behind `UIListLayout`) and radial/arc layouts for weapon wheels would both become consumer code. Facet's arrange branches are closed and internal (`src/layout/solver.luau`), and `solver.auditPlacement` is built around a fixed table of parent kinds. `AnyLayout` is examined via `AdaptiveStack`; the protocol beneath it is not. | **subsystem** |
| 19 | **Upward preference channel** — [`PreferenceKey`, `anchorPreference`, `onPreferenceChange`, `overlayPreferenceValue`](https://developer.apple.com/documentation/swiftui/preferences) | A descendant publishes a value that ancestors read and aggregate — the exact inverse of the environment. | Child-declared screen titles, a badge count bubbling from a deep row to a tab, an overlay positioned from a descendant's anchor. Facet has the downward channel (environment) and three *push* geometry seams keyed by node path (`swiftui-parity.md:208`), but no general upward composition channel. **0 of 5 groups examined** — the largest single blind spot in the document. | **subsystem** |
| 20 | **Hit-region shaping** — [`contentShape`, `allowsHitTesting`](https://developer.apple.com/documentation/swiftui/input-events) | Decouple the tappable region from the painted region. | A skinned button whose art is smaller than its 44 px target; a chevron whose whole row is tappable; transparent decorative art that must not eat taps. Facet has an internal "hit expander" driven by the minimum-hit-target rule (`swiftui-parity.md:79`), but no author-facing control over it. | **prop** |
| 21 | **Sortable / customisable table columns** — [`TableColumnCustomization`, `tableColumnHeaders`](https://developer.apple.com/documentation/swiftui/tables) | Sort by clicking a header; let the player hide or reorder columns. | Leaderboards sorted by time/laps/wins; a stats screen the player configures. `swiftui-parity.md:406` scores `Table` on selection, reordering *of rows*, and cell rendering, and notes column resize remounts every row — column sorting is never scored either way. | **control** |
| 22 | **Hierarchical rows** — [`OutlineGroup`](https://developer.apple.com/documentation/swiftui/lists), [`DisclosureTableRow`](https://developer.apple.com/documentation/swiftui/tables) | Recursively expandable tree rows inside a list or table. | Skill trees, quest chains with sub-objectives, nested settings, crafting recipe trees. `DisclosureGroup` is Covered as a *single* collapsible section (`swiftui-parity.md:401`); recursion over a tree of data is a different capability and is unmentioned. | **control** |
| 23 | **Immediate-mode 2-D drawing** — [`Canvas`, `GraphicsContext`](https://developer.apple.com/documentation/swiftui/drawing-and-graphics) | Draw arbitrary shapes and strokes procedurally inside a laid-out box. | Minimaps, radar sweeps, telemetry graphs, ghost-lap traces, damage-over-time plots. Partially acknowledged: §12 records that "area-fill charts become banded strips (Roblox's `Path2D` is stroke-only)" — an approximation note, not a capability row. Roblox has since shipped `EditableImage`, which is a second substrate the document has never considered. | **subsystem** |
| 24 | **Geometry-driven paint** — [`visualEffect`](https://developer.apple.com/documentation/swiftui/drawing-and-graphics) | Apply a paint effect computed from the node's own resolved geometry. | Fade rows near a list's edge, scale the centre item of a carousel, dim content behind a bottom sheet. This is the general substrate under `.scrollTransition`, which the doc scores Missing (`swiftui-parity.md:732`) as a *point* feature without noting the composable form beneath it. | **seam** |
| 25 | **Colour-blind-safe differentiation** — [`accessibilityDifferentiateWithoutColor`](https://developer.apple.com/documentation/swiftui/accessible-appearance) | Signal state by shape or pattern, not only hue, when the player asks for it. | Team colours, red/green ready-states, minimap markers, buy/sell arrows — roughly 8 % of players cannot read hue-only status. Roblox surfaces no OS preference for this, so it would be a game-provided setting plus a framework channel. Adjacent and worth flagging in the same area: **`accessibilityDimFlashingLights`** (photosensitivity) sits inside the "Minimizing motion" group that the doc *does* examine via Reduce Motion, so it is examined-by-container but never named. | **prop + theme convention** |
| 26 | **Animated icon effects** — [`symbolEffect`](https://developer.apple.com/documentation/swiftui/images) | Bounce, pulse, or variable-fill an icon on a trigger. | A "new" pip that pulses, a notification bell that shakes, a loading icon that breathes. Facet's semantic icon set is static; the colour-blend `tint` channel used by the spinner (`swiftui-parity.md:581`) is the nearest existing mechanism. | **prop** |

### Tier 3 — real, but a specific screen has to ask (27–39)

| # | Capability | What / why, briefly | Cost |
|---:|---|---|---|
| 27 | **Text selection and copy** — [`textSelection`](https://developer.apple.com/documentation/swiftui/text-input-and-output) | Let a player select and copy a friend code, server ID, or error code. Roblox `TextBox` supports selection, so the substrate is there. | control |
| 28 | **Content margins for scrollers** — [`contentMargins`](https://developer.apple.com/documentation/swiftui/layout-adjustments) | Inset scroll *content* without insetting the scroller — the correct fix for a notch or home indicator over a list. Facet has safe-area insets at the surface root but no per-scroller content margin. | prop |
| 29 | **Split panes** — [`HSplitView` / `VSplitView`](https://developer.apple.com/documentation/swiftui/navigation) | Two panes with a user-draggable divider. Inventory-plus-detail on tablet; `Grip` is a 1-D value adjuster, not a pane splitter. | control |
| 30 | **`GroupBox` / `ControlGroup`** — [grouped-container chrome](https://developer.apple.com/documentation/swiftui/view-groupings) | A titled, bordered container and a compact cluster of related buttons. Options panels, HUD button clusters. | control |
| 31 | **List row chrome** — [`badge`, automatic row separators, `listRowInsets`/`listRowSpacing`](https://developer.apple.com/documentation/swiftui/lists) | Per-row count badges, automatic hairlines between rows, per-row inset control. A `badge` chrome *slot* exists for theming (`src/tokens/chrome_slots.luau`); a `badge` modifier does not. | prop |
| 32 | **Shape vocabulary** — [`Circle`, `Capsule`, `containerShape`](https://developer.apple.com/documentation/swiftui/shapes) | Circle/capsule as first-class leaves, and a container that hands its corner geometry to children so nested panels stay concentric. | prop |
| 33 | **Toolbar / chrome item host** — [`toolbar`, `ToolbarItemPlacement`](https://developer.apple.com/documentation/swiftui/toolbars) | Declare items and let the framework place them in the surface's chrome band. Facet has the `topbarInset` / `topbarSafeInsets` env facts — the geometry without the hosting construct. | control |
| 34 | **Search field construct** — [`searchable`, `searchSuggestions`](https://developer.apple.com/documentation/swiftui/search) | A search field bound to a collection, with suggestions. Inventory filter, catalog search, server browser — the p3 reference app built one by hand. | control |
| 35 | **Consumer-defined gesture recognisers** — [`highPriorityGesture`, `Gesture` composition](https://developer.apple.com/documentation/swiftui/gestures) | Let a consumer define a custom recogniser that participates in arbitration. `touchGestures` ships six kinds and an arbiter, exported and consumed by nothing (`swiftui-parity.md:619`); extending it is not a public capability. | seam |
| 36 | **Scroll behaviour props** — [`scrollDisabled`, `scrollBounceBehavior`, `scrollInputBehavior`](https://developer.apple.com/documentation/swiftui/scroll-views) | Freeze a scroller during a transition; control overscroll elasticity (Roblox `ScrollingFrame` has `ElasticBehavior`); differentiate mouse-wheel from touch scrolling. | prop |
| 37 | **Drag-and-drop polish** — [`dragPreviewsFormation`, `springLoadingBehavior`](https://developer.apple.com/documentation/swiftui/drag-and-drop) | Stacked previews for multi-item drags; hover-over-a-container-to-open. Inventory-to-container drags. | control |
| 38 | **Animation ergonomics** — [`.animation(_:value:)`, `Animatable`/`VectorArithmetic`](https://developer.apple.com/documentation/swiftui/animations) | The *implicit, view-attached* animation form (distinct from the explicit `withAnimation` that shipped 2026-08-13), and animating arbitrary custom value types rather than only scalars and 2-D chase. | prop + seam |
| 39 | **Introspection channels** — [`Subviews`/`containerValue`](https://developer.apple.com/documentation/swiftui/view-groupings), [`focusedValue`](https://developer.apple.com/documentation/swiftui/focus) | A container inspecting and re-arranging its own children; an ambient "what is focused" value driving context-sensitive chrome. | subsystem |

### 5.1 The calibration answer

The brief asked for the true number and said fewer than five would be a strong
positive result. **It is 39, not fewer than five.** That is a real result, and the
shape of it matters more than the count:

- **29 of 39 are props, controls, or seams** — additive work on existing
  machinery, not architecture.
- **4 more additionally need solver work** (#1 rich text, #5 scroll snapping,
  #6 sections, #17 truncation controls), which is where the cost steps up.
- **6 are subsystems** — #3 scoped environment, #7 localization, #18 custom
  `Layout`, #19 preference channel, #23 immediate-mode drawing, #39 introspection
  channels. Those six are the ones that could change the roadmap.
- **The blind spots cluster.** Four collections supply 19 of the 64 unexamined
  groups: [scroll-views](https://developer.apple.com/documentation/swiftui/scroll-views)
  (6 unexamined of 12), [view-groupings](https://developer.apple.com/documentation/swiftui/view-groupings)
  (5 of 7), [preferences](https://developer.apple.com/documentation/swiftui/preferences)
  (5 of 5), [custom-layout](https://developer.apple.com/documentation/swiftui/custom-layout)
  (3 of 4). This is not random omission — it is the document inheriting the shape
  of a framework built control-first and layout-first, where scroll *behaviour*,
  *grouping semantics*, and *extension points* were never their own areas.
- **None of the 39 contradicts a shipped claim.** This audit found no false row.
  Every finding is an absence of a row, which is exactly the failure mode the
  brief predicted.

---

## 6. Meta-finding 1 — the document's scope is **not** stated honestly

**Verdict: it implies a completeness it does not have.** Same defect class as a
false claim, though milder, and cheap to fix.

The promise, in §1 (`swiftui-parity.md:20-23`):

> "a developer (or an agent) picking up Facet can find out, **in one read**,
> whether the thing they need exists, exists-with-caveats, or **does not exist at
> all**."

That is a completeness claim about the *union* of SwiftUI capabilities. A reader
who consults it for `onAppear`, `Section`, `.disabled()`, rich text, or scroll
snapping finds nothing and reasonably concludes those were considered and found
irrelevant. All five were never considered.

Every scope caveat in the document is narrower than the promise:

| Where | What it bounds |
|---|---|
| `:528-529` "The full 69-item SwiftUI catalog comparison is not re-listed here. Items not named above were not independently re-examined in this pass." | §5's **controls catalog** only — and it bounds *re-examination*, not coverage |
| `:1122-1123` (same, in §15) | ditto |
| `:118-125` "155 capability rows… A count is not a score" | warns against reading the count as a percentage, but the denominator it disclaims is never named |
| `:1111-1121` "Things this pass could NOT verify" | three specific unverified *claims*; nothing about unconsidered *areas* |

The one sentence that would fix it — "a bounded catalog, not a percentage score
for all of SwiftUI" — exists, at `docs/plans/parity-next.md:43-44`, in a
file the parity document does not link.

**The fix is two edits, and I have deliberately not made them:** a paragraph in §1
stating that the document covers a bounded catalog and naming the areas it does not
reach, and a row in §15's verification appendix stating the SwiftUI-side
denominator (e.g. "365 of Apple's capability groups; 127 scored"). Both belong to
whoever holds the file next. Note the §15 gate constraint at `:1153-1157`: only
§12's heading text is grepped by `gate_manifest.luau`, so §1 and §15 are free to
edit.

---

## 7. Meta-finding 2 — repeatability

**Verdict: a day the first time, about an hour a year after — but only if the
group-marker list is checked in as a fixture. Without the fixture it is a day
every time.**

The three steps have very different costs:

| Step | Cost | Automatable? |
|---|---|---|
| Pull the index and extract the 392 group markers | seconds | **Fully.** One `curl` plus the 8-line script in §2. Schema path `interfaceLanguages.swift[0].children[*].children[?type=groupMarker]` has been stable across the DocC renderer's life. |
| Diff against the parity document | minutes | **Mostly.** A `grep -i` per group name gets ~80 % right; the misses are all synonymy (`AnyLayout` ↔ `AdaptiveStack`, `swipeActions` ↔ `newRowActions`, `Dynamic Type` ↔ `preferredTextOffset`) and need a human or a model. |
| **Classify NA / OOS / Examined / Unexamined** | **hours — this is the whole mission** | **No.** Each verdict needs a Roblox-substrate judgement and a Facet-source check. This is where this audit spent its time. |

The step-3 cost is one-time *per capability*, not per audit. So:

**Recommendation — turn this into a standing check, cheaply.** Commit the sorted
`collection | groupMarker` list (392 lines) plus its verdict column as an artifact
under `artifacts/parity-completeness/`. A yearly re-run then becomes:

1. Re-pull the index; regenerate the list.
2. `diff` against the committed fixture.
3. Classify **only the new lines.** The delta per WWDC is small relative to 392 —
   groups such as "Styling views with Liquid Glass", "Configuring scroll edge
   effects", and "Reordering items" are recent-looking arrivals in this pull, but
   I did not diff against a prior-year index to confirm which are new, so treat
   the per-year delta size as unmeasured until the first fixture exists.

That is an hour. Two caveats a future agent must know:

- **Apple renames groups.** "Deprecated" vs "Deprecated types" vs "Deprecated
  Types" all appear in this pull. A raw line diff will report renames as
  add-plus-delete; the new lines need eyeballing for renames before classifying.
- **The index URL is an undocumented DocC endpoint**, not a published API. If
  `/tutorials/data/index/swiftui` moves, the fallback is scraping the 49 collection
  landing pages listed in §3, which is slower but equivalent — the group markers on
  those pages are the same data.

**Do not automate a pass/fail gate on this.** The number is a research input, not
an invariant; a gate that fails because Apple shipped a new visionOS collection
would be noise, and the codebase already has a rule against checks that cannot bite
meaningfully.

---

## 8. Method and provenance

| | |
|---|---|
| Date | 2026-08-13 |
| SwiftUI source | `https://developer.apple.com/tutorials/data/index/swiftui`, pulled 2026-08-13 — HTTP 200, 1,378,939 bytes, 10,988 nodes, `includedArchiveIdentifiers: ["com.apple.SwiftUI"]`, i.e. the June 2026 / Xcode 27 shipping surface, the same baseline `swiftui-parity.md:1107` names |
| SwiftUI capability frame | The 392 `groupMarker` headings across the 49 collection landing pages linked in §3; 27 dropped as navigation scaffolding, 365 scored |
| Facet source read | `src/blueprint.luau`, `src/blueprint_schema.luau`, `src/init.luau`, `src/env/environment.luau`, `src/render/authority.luau`, `src/controls/`, plus targeted greps over all of `src/` |
| Parity document read | `docs/reference/swiftui-parity.md` in full, 1,157 lines, as of this session |
| Roblox facts verified live | [`GuiObject`](https://create.roblox.com/docs/reference/engine/classes/GuiObject) (`Rotation`, `Interactable`, `Visible` frees layout space), [`TextLabel`](https://create.roblox.com/docs/reference/engine/classes/TextLabel) (`RichText`, `TextScaled`, `LineHeight`, `TextTruncate`, `MaxVisibleGraphemes`), [`LocalizationService`](https://create.roblox.com/docs/reference/engine/classes/LocalizationService) (tables, translators, `AutoLocalize`) |
| Not verified, recorded as unknown | Whether Roblox's localization stack supports plural/gender rules (its own page does not say); whether any player-facing clipboard API exists (I found none in the engine reference, which is not proof of absence) |

**Things this audit deliberately did not do.** It did not design a solution for any
of the 39 — every "cost" column is a magnitude estimate from reading adjacent
source, not a plan. It did not re-verify any *existing* parity verdict; a row that
says Covered was taken at its word, because that is the other agents' current work.
It did not edit any shipped file.
