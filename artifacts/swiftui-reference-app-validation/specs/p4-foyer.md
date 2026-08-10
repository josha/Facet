# P4 "Foyer" — UI build spec (proof RA-P4)

**What this is.** A clean-room, in-experience reinterpretation of a discovery
home screen, as one adaptive LuauUI surface. Behavioral reference:
`../sources.md` §"Roblox desktop app — Home" — behavior only; original names,
copy, data, iconography (no platform branding, no real experience/creator
names). Binding: `../capability-ledger.md` §A/§E, `../responsibility-ledger.md`,
`docs/reference/api.md` — every construct cited exists there. **Engine notes
(scenario preconditions):** UI-driven place — presenter built with
`keyboardNavigation = true`; the scenario disables the CoreGui players list so
Tab is live, and runs no default camera so horizontal arrows reach the UI
(api.md § Desktop keyboard conventions / `RbxCameraKeypress`).

## 1. Purpose and hierarchy

The player's calm front door: "what shall I play?" Eye order: (1) the feed's
first card row, (2) friends carousel, (3) tab pair, (4) rail + top bar. One
primary verb per view: **Activate a tile → its detail surface → one accent
action.** Nothing here is destructive or timed.

## 2. Visual-language invariants (defend in every later amendment)

- `accent` = interactive emphasis / primary action / the selected-indicator
  form — never section identity, never decoration. Selection = **form + state**
  (`selected` paints `controlSelected`, plus the tab underline), never a hue.
- `badge` = a count; `chip` = read-only status ("Sponsored", rating). A chip is
  never tappable; anything tappable is a `Button`.
- One scroll authority on the base surface: the feed page `ScrollView`. Shelves
  and the friends carousel scroll only on x, inside it.

## 3. Content universe and services

Deterministic fakes per the responsibility ledger — seeded; commands run
`idle → pending → confirmed | rejected` with scripted rejection fixtures; no
wall clock, `math.random`, or network.

- **FeedService** — sections of tiles: `picked` "Picked for you" (8, grid),
  `continue` "Keep playing" (6, x-shelf), `new` "New this week" (8, grid),
  `friends` "Friends are in" (4, grid). Tile = `{ id, title, thumbKey, approval
  0–100, sponsored, blurb }`; original titles (Moss Kingdom, Rooftop Dash,
  Bumper Barge, Signal Lost, Pancake Tycoon, Gloamwood, …) and creators
  (Latchkey Labs, Bramble & Co, Nine Kites). Commands: `refresh()` (re-seeds
  from the next seed page; one scripted rejection, reason `feed.refresh.offline`),
  `visit(tileId)` (adds to `continue`), `clearNotices()` (≤5 seeded rows + count).
- **FriendsService** — 9 seeded friends `{ id, handle, portraitKey, presence
  "here"|"away" }` (Marrow, Tibbs, Juno, Pell, Okra, Vess, Halloway, Brindle,
  Sorrel) + `inviteCount` (2) for the add-tile badge.
- **SearchService** — `filter(query)` memo over the feed (title + creator
  substring, case-folded); synchronous, deterministic. Async art rides
  `newResourceProvider` + `newAsyncImage`: proof-owned 16:9 thumbnails and
  square portraits, plus two scripted `failed` keys visible in the seed.

## 4. State split (declared; violations are gate failures)

| Semantic (signals, survive everything) | Presentation (client-local, throwaway) |
|---|---|
| active destination, active tab, search query, feed/friends data, notice list + count, command statuses, `continue` membership | scroll offsets, focus + ring visibility, hover, transitions, disclosure plates, search `editing` |

Nothing replicates (no server); rejected commands visibly revert (§9).

## 5. Tokens

Shared roles only: `surface`/`surfaceStrong`/`content`/`contentStrong`/
`contentSecondary`/`accent`/`onAccent`/`control`/`controlSelected`/`hairline`/
`danger`; ramp `caption`/`label`/`body`/`heading`/`title` (+`strong`/`numeral`);
space `xs…xl`; radii `control`/`panel`/`pill`; shadows `raised`/`overlay`. No
literals below except inside these **proposed theme metrics** (proof theme
package; names escalate to the Creative Director with the theme PR; grid-of-4):
`metrics.foyer.tileMin` 220 (feed `Grid.minColumnWidth`) · `shelfTile` 96 ·
`portrait` 56 · `railW` 72 · `detailW` 560 · `searchW` 320.

**Proof icons** (namespaced, registered with original art + ASCII fallback):
`foyer:home H`, `crews C`, `forge F`, `mail M`, `you Y`, `search ?`,
`refresh @`, `bell !`, `approval ^`, `add +`; built-ins `close`,
`chevron.trailing`. Brand mark: proof-owned `Image` asset (a doorway
monogram), non-interactive, never a button.

## 6. Structure (one description; size-class branches inside it)

Present via `present(screen, { navigationGroups = §8, initialFocus =
"Tab.forYou", traversalWrap = true })`; default `rootPolicy`;
`adaptive.conditions(core, env, { scope })` supplies `sizeClass`/`isCompact`.

```
Screen  gap="m"
└ VStack
  ├ TopBar (HStack, padding="s", gap="m", surface="base")             — §6.1
  ├ HStack fill
  │ ├ When(not isCompact) → NavRail (VStack, width fixed railW)       — §6.2
  │ └ ContentHost (VStack fill)
  │   ├ When(destination == "home") → HomeBody                        — §6.3
  │   └ When(destination is a stub) → StubPlate                       — §6.6
  └ When(isCompact) → BottomBar (HStack, height "controlSizes.large.height")
```
Only nav chrome lives behind `When`s; **HomeBody never remounts on a size-class
flip**, so feed scroll, focus and in-flight images survive rotation;
destination/tab/query are signals (§4) and survive the chrome swap.

**6.1 TopBar.** Brand `Image` (height "l", `scaleMode="fit"`) · `Spacer` ·
SearchSlot · `Spacer` · Refresh = circle `Button{icon="foyer:refresh",
label="Refresh the feed"}` · ProfileChip · Bell.
- *SearchSlot* = `ViewThatFits{ field-form, icon-form }`. Field form:
  `newTextInput{ id="Search", value=query, placeholder=t("search.ph") "Search
  worlds", clearButtonMode="whileEditing" }`, width minMax at
  `metrics.foyer.searchW`, filtering live via `onChange` → SearchService. Icon
  form: circle `Button{icon="foyer:search", label="Search worlds"}` → Search
  modal (§6.5). Both share the one `query` signal — collapsing keeps the text.
- *ProfileChip* = `Button{ label="Your profile", children = HStack{ portrait
  newAsyncImage (portrait metric, corners pill), Text{ handle, "label",
  lineLimit=1, disclose=true } } }` → Profile modal: portrait, handle, caption
  "Exploring since day one", Close.
- *Bell* = `ZStack{ circle Button{icon="foyer:bell", label="Notifications"},
  Text{ surface="badge", text=bind(noticeCount), "caption", alignH="end",
  alignV="start" } }`, badge behind `When(noticeCount > 0)`. Activate →
  Notices modal: title, ≤5 read-only rows (`body` + `caption` relative time
  from the proof i18n table), Close; presenting fires `clearNotices()`.

**6.2 NavRail / BottomBar** — same five destinations, one selection signal.
Item = `Button{ selected=bind(dest==id), label=name, children = newLabel{
title=name, icon="foyer:<id>", presentation = rail "titleAndIcon" / bottom bar
"iconOnly" } }`. Rail: VStack gap "s", padding "s", stretch; active item paints
`controlSelected` + a leading accent bar (`Box` width "xs", tint
`{role="accent", blend = selected and 1 or 0}` — a binding, no remount). Bottom
bar: five equal `fill` items, accent bar under the icon. Destinations: Home
(live) + Crews, Forge, Mail, You (stubs → §6.6). Item states: default / hover /
focus / pressed / selected; never disabled.

**6.3 HomeBody.**
```
VStack gap="m"
├ TabRow (HStack, gap="l", padding-x="m")
├ FriendsRow (ScrollView axis="x", gap="s", padding-x="m")
└ FeedPage (ScrollView axis="y", fill, gap="l", padding="m")
   └ When(searchActive) → filtered | seeded:  ForEach(sections, key=id) → Section
```
- *TabRow*: two of `VStack{ Button{ label "For you"/"Charts", selected=bind },
  Box{ height "xs", tint {role="accent", blend = spring 0↔1, class "object"} } }`.
  Bodies swap via `When(tab)`; Charts = the same Section blueprint over an
  approval-ranked re-seed — real content, not a stub.
- *FriendsRow*: leading AddTile = `ZStack{ circle Button{icon="foyer:add",
  label="Invite friends", width/height portrait metric}, badge Text
  (inviteCount, as §6.1) }` → honest stub modal ("Inviting friends isn't part
  of this proof."). Then `ForEach(friends)` → `Button{ label=handle, children =
  VStack{ ZStack{ newAsyncImage portrait (pill corners), display-only presence
  dot = Box "xs", tint {role="accent", blend = here and 1 or 0}, alignH/alignV
  "end" }, Text{ handle, "caption", lineLimit=1, disclose=true } } }` → that
  friend's profile-card modal.
- *Section*: header `HStack{ Text{ title, "heading" }, Spacer, circle Button{
  icon="chevron.trailing", label="See all <title>" } }` → the section as a
  detail-shaped modal (title + full Grid of its tiles, own y-ScrollView, Close).
  Body: `continue` = x-`ScrollView` of square shelf tiles (`shelfTile`, thumb +
  1-line `caption` title, `lineLimit=1, disclose=true`); all others = `Grid{
  minColumnWidth="metrics.foyer.tileMin", itemSizing="uniform", gap="m",
  rowGap="l" }` of TileCards.

**6.4 TileCard** (a composite; one activation surface):
```
Button id=tile.id label=tile.title
└ VStack gap="xs" align="stretch"
  ├ newAsyncImage (thumbKey, width fill, height {type="aspect", ratio=16/9},
  │                scaleMode="crop", corners "control")
  ├ Text  title, textSize="label", lineLimit=2      (wraps, then ellipsizes)
  └ HStack gap="xs": newLabel{ icon="foyer:approval", title=approval.."%" } ·
      Spacer · When(sponsored) → Text{ surface="chip",
      text=t("chip.sponsored") "Sponsored", textSize="caption", role="secondary" }
```
States: default / hover (theme state; pointer-only, nothing essential) / focus
(framework ring) / pressed / image-pending (placeholder surface) / image-failed
(placeholder persists — never a broken glyph). The Sponsored chip shows whenever
`sponsored` and no adaptation may hide it. No `disclose` on the 2-line title —
the detail surface restates it in full.

**6.5 Detail + Search modals.** Detail (Activate on any tile): `presentModal`,
panel = `ZStack{ canvasGroup=true }` over a Box `surface="raised"`, shadow
`overlay`, corners `panel`, width `{type="percent", fraction=0.92,
max="metrics.foyer.detailW"}`, own y-ScrollView: hero 16:9 image, `title`
(wraps), approval + creator line (`caption`, `role="secondary"`), blurb `body`,
footer: primary `Button` t("detail.visit") "Visit" painted `accent` + Close
circle. Visit → `FeedService.visit`: pending = t("detail.visiting")
"Visiting…" + `enabled=false`; confirmed = dismiss, toast t("toast.visited")
"Added to Keep playing", tile joins `continue`. Cancel / outside tap / Close
all dismiss (two-zone model). Search modal (compact path): the same field
(autofocus via `initialFocus`), results as compact rows (thumb, title,
approval); row Activate stacks the Detail modal above. Empty query shows
nothing; no match shows §9's empty state.

**6.6 StubPlate** (stub destinations + AddTile): centered VStack — icon at
"xl", `heading` = destination name, `body` t("stub.body") "Nothing to show
yet.", `caption` secondary t("stub.honest") "This wing is a labeled stub in
this proof." No fake content.

## 7. Adaptation (five-view table; one tree, facts + size class only)

| View (env facts) | Nav | Search | Feed cols (tileMin 220) | Notes |
|---|---|---|---|---|
| Phone portrait — compact, touch | bottom bar, icon-only | icon → modal | 1 | verbs in thumb reach; cards full width |
| Phone landscape — compact/regular by width, touch | per class | usually icon | 2 | same tokens, no special case |
| Tablet — regular, touch | rail, icon+title | inline field | 2–3 | detail modal at preferred 560 |
| Desktop — wide, pointer+keyboard | rail | inline field | 4 (~1400 reference) | hover previews; Tab per §8 |
| Console — Large: sizeClass capped `regular`, ten-foot | rail | icon → modal (no 10-ft typing) | 2 | focus-first: ring is the anchor; framework applies 1.5× paint scale + overscan; initial focus = active tab |

Reflow only — nothing scales-to-fit or overlaps; compact is a different
arrangement of the same hierarchy (§6's `When`s + `Grid` + `ViewThatFits`).
Column counts are the declared expectation: verify with `adaptive.columnsFor`
at the matrix widths; `metrics.foyer.tileMin` is the only tuning knob.

## 8. Focus and input

**Navigation groups** (present-opt `navigationGroups`; declaration order = Tab
order; entry `"nearest"`, uncontained fall-through in this order): `topbar`
(horizontal: search, refresh, profile, bell) → `rail` (vertical; compact:
`bottombar`, horizontal) → `tabs` (horizontal) → `friends` (horizontal;
keep-visible scrolls the x-shelf) → `feed` (vertical: every chevron, card and
shelf tile in document/reading order — Up/Down walk reading order across grid
rows; keep-visible scrolls the page). Declared exits: `feed.exit.left = rail`
(non-compact), `rail.exit.right = feed`. Losing `ViewThatFits` candidates and
closed `When` branches are framework-excluded. Initial focus `Tab.forYou`;
`handle.focusOrder()` is the acceptance instrument (both readings, one set).

**Verbs × four input classes** (every verb on every class):

| Verb | Pointer | Touch | Keyboard | Gamepad |
|---|---|---|---|---|
| Open tile / any button | click | tap (44px floor) | Navigate + Return/Space | Navigate + ButtonA |
| Back / dismiss modal | Close, outside click | Close, outside tap | Close via focus+Activate (Esc is platform-reserved, never cited) | ButtonB (Cancel) |
| Move focus | click (ring hidden) | tap (ring hidden) | arrows + Tab/Shift-Tab (ring shown) | D-pad/stick (ring shown) |
| Scroll feed/shelves | wheel | pan/fling | focus move + keep-visible | focus move + keep-visible |
| Switch tab / destination | click | tap | Navigate + Activate | Navigate + Activate |
| Search | click field, type | tap icon → modal, type | Tab to field, Activate, type; Cancel reverts edit | Activate → modal; on-screen keyboard |
| Clear search | × (whileEditing) | × | × via focus / Cancel revert | × via focus |
| Refresh | click | tap | Activate | Activate |

Cancel on the base surface is a no-op (nothing to dismiss). Nothing essential
lives behind hover. Deliberate omission: no bumper tab-cycling — a 2-tab row
has not earned an Adjust contribution.

## 9. States, flows, no-silent-states

- **Refresh**: Activate → pending (button `enabled=false`; feed keeps current
  content — no skeleton) → confirmed: sections swap (§10), page scrolls to top
  (`controller.scrollTo`, declared intentional), toast t("toast.refreshed")
  "Feed refreshed" → rejected (fixture): feed unchanged, toast with reason
  t("err.feed.refresh.offline") "Can't refresh right now — the hallway is
  quiet. Try again." (hard fallback t("err.generic") "Something went wrong.
  Try again."); the button re-enables either way.
- **Search empty state** (feed or modal): centered `heading` t("search.none")
  "No worlds match", `body` = the query (quoted, `lineLimit=1, disclose=true`),
  `Button` t("search.clear") "Clear search". Never a blank page.
- **Async images**: pending = placeholder surface; failed = placeholder
  persists (silent by contract; two scripted failed keys visible in the seed).
  Pending/disabled buttons keep their label and dim via the theme's disabled
  treatment — the visible pending state is the explanation.

## 10. Motion (+ reduced motion — parity, never deletion)

| Moment | Motion | Reduced-motion form |
|---|---|---|
| modal enter/exit | surface `transition={enter="materialize"}` on the canvasGroup panel (exit mirrors) | instant, same events |
| feed refresh swap | `ForEach` `transition={enter="slide-up"}` (no fade — no per-card canvasGroup cost) | instant |
| tab underline / rail bar | tint-blend `spring` 0↔1, class `object` | snap |
| toast | `presentToast` defaults, duration 4 | instant, same schedule |
| badge appear | `When` `transition={enter="instant"}` (a count is a fact) | same |
| press/hover | theme-owned control states | unchanged |

No decorative overshoot (`reward` unused). All motion rides the presenter's
clock; nothing binds its own frame source.

## 11. Text scaling and localization

Scale 0.5–3: card titles wrap to `lineLimit 2` then ellipsize; handle/shelf/
profile labels are 1-line + `disclose`; headers and buttons wrap; every circle
button carries a semantic `label`. Cards grow in height (`itemSizing="uniform"`
keeps rows even); columns are width-driven, not type-driven; ten-foot 1.5×
factors are framework-applied. All copy ships in the proof string table
`foyer.*` with the ~1.4× pseudo-locale fixture; worst case shown fitting:
pseudo-loc "Keep playing" + the longest seeded title at scale 3 on phone
portrait — wrapped, never clipped. BiDi/RTL: recorded out-of-scope gap (§A).

## 12. Feedback / sound hooks (bus events → proof ids; LuauUI plays nothing)

`activate`→`sfx.foyer.tap` · `commit`→`sfx.foyer.done` · `reject`→
`sfx.foyer.deny` · `dismiss`→`sfx.foyer.close` · `arrive`/`supersede`→silent;
wired once via `presenter.onFeedback`; no haptics in this proof.

## 13. Acceptance hooks (RA-P4)

Scroll offset, focus path, tab/destination/query signals and in-flight image
handles survive reflow across all five views, a theme swap, and a
preferred-text step — assert via `controller.scrollPosition`,
`handle.focusOrder()`, zero factory reruns outside the declared `When` chrome
swaps, `controller.diagnostics()` clean in every fixture; detail → back
restores feed scroll and focus to the originating tile.

## 14. Deliberately left out

Pull-to-refresh (the explicit button is honest on all four classes); tile
context menus (no secondary-action model — ledger §A); infinite feed (bounded
seed; shelves are x-ScrollViews per ledger §A); a distinct charts visualization
(the re-ranked list keeps scope); theme-swap UI (RA-M3 drives it scenario-side);
the native app shell itself (no host equivalent — ledger §E).
