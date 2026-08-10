# P1 "Glade" — UI build contract (RA-P1)

UI Designer spec, 2026-08-08. Clean-room reinterpretation of the behavioral reference
(`sources/features-backyard-birds.md`) as an original LuauUI proof. All names, copy,
data and art direction here are original; no reference identity or copy appears
anywhere in the proof. Everything named below is a public LuauUI construct
(`docs/reference/api.md` v0.9) or a proof-owned fake per the responsibility ledger.
Anything the capability ledger (§B) classifies as no-host-equivalent or proposal-level
is out of scope (§14) or uses the named approximation.

**Visual-language invariants** (defend in every amendment):
1. Hue carries supply identity only — nectar glow vs dew glow. State (low/empty/
   pending/rejected) is carried by *form*: chips, ring emptiness, copy. Never a second hue.
2. One scene per screen: the glade viewport is the only pictorial surface; every
   control sits on token surfaces, never over the scene art.
3. Pending never reads as success; every rejection has visible copy at the point of action.
4. One motion vocabulary: the four registered classes; overshoot only on `reward`.

## 1. The fantasy and the content set (proof-owned, seeded)

Keepers tend small moss gardens — **glades** — that glowing sprites — **wisps** —
visit when supplies are kept up. Two supplies per glade: **Dew** (a basin; instant
refill) and **Nectar** (chosen from varieties; some premium).

| Domain | Names (seed data, deterministic) |
|---|---|
| Glades (5) | Mossholm (favorite, Clover Nectar, dusk), Fernhollow, Lantern Dell, Bramble Rest, Stillpond — each with a fixed day-phase offset |
| Wisp species (6) | Emberwisp (scale 0.83), Palewisp (1.0), Frostwisp (0.71, **Lumen-only early arrival**), Duskwisp (1.0), Sunwisp (1.0), Tidewisp (0.76, hero species) |
| Standard nectars (6, free) | Clover, Meadow, Fern, Thistle, Bramble, Heather Nectar |
| Premium nectars (3) | Starlight Syrup (priority 3, "best value" hero), Moonpetal Nectar (2), Gilded Amber (1); packs = single + bundle-of-5 each; seed satchel = 3 Starlight Syrup |
| Charm ("subscription") | **Keeper's Charm**, tiers Ember < Grove < Lumen; Lumen unlocks Frostwisp early arrivals; taglines: Ember "Every glade, no limits" · Grove "Share the grove's warmth" · Lumen "The full glade at first light" |
| Prices | Service-published strings, spark glyph + number ("✶ 79"); never composed in UI copy |
| Drain constants (demo scale, visible in-session) | Nectar: full→empty 9 min, low at 7.5 min. Dew: full→empty 16 min, low at 13 min |

Services (responsibility ledger): `SupplyService` (refill stamps, drain constants,
injectable `now` fact), `CommerceService` (satchel ledger, charm tier, catalog,
purchase command with `idle→pending→confirmed|rejected` + scripted rejections),
`VisitScheduler` (seeded past/current/future visit windows; `currentVisitor` and
`needsPresent` derived). No wall clock, no `math.random`, no network.

## 2. Tokens, type, spacing, motion (Studio Neutral base + proof theme package)

- **Color roles used:** `surface`, `surfaceStrong`, `content`, `contentStrong`,
  `contentSecondary`, `accent`, `onAccent`, `control`, `controlSelected`, `hairline`,
  scrim at the theme's `scrimOpacity`. Destructive actions use the Button
  `role = "destructive"` pair — never a raw color.
- **Proposed extra tokens** (proof theme package `extra.*`; identity choice flagged to
  the Creative Director per role rules): `extra.nectarGlow`, `extra.dewGlow` — the two
  supply-identity hues (invariant 1). Consumed only by supply rings/gauge fills via
  `tint`; contrast-gated with the surfaces they sit on at token compile.
- **Sky ramp:** scene art data, not UI tokens — a proof-owned table of rgb gradient
  stops per day-phase bucket (night/dawn/day/dusk/eve), interpolated by a memo and fed
  to `UI.gradient` (2–3 stops, reactive). UI chrome never samples it.
- **Type ramp:** `title` (screen names), `heading` (section headers, product names),
  `body` (copy), `label` (buttons, rows), `caption` (remaining-time, footnotes).
- **Spacing:** steps only. Card padding `m`; grid gap `m`; section gap `l`; modal
  padding `l`; chip/inline gaps `s`/`xs`. Radii: cards/panels `panel`, controls
  `control`, chips/badges `pill`. Shadows: `raised` on cards, `overlay` on modals.
- **Motion:** the four registered classes — `container` (surfaces), `object`
  (glides), `reward` (pops, counters), `decay`. No inline physics literals. Reduced
  motion is the framework's parity contract; per-animation forms in §11.

## 3. Screen inventory and surface map

Presenter: one, `keyboardNavigation = true` (UI-driven proof place; engineering note —
the proof place must release the default camera's `RbxCameraKeypress` binding or
horizontal arrows die, per api.md `newPresenter`).

| # | Surface | Presented as | Enter/exit transition | Cancel does | Initial focus |
|---|---|---|---|---|---|
| S1 | Shell + Glades overview | base `present()`, `rootPolicy = coreSafeContent`, `cancelPolicy = "none"` | fade | nothing (base) | first glade card |
| S2 | Glade detail | wide/regular: shell detail Region (selection signal). compact: full `presentModal`, `outsideTapCancel = false`, transition `slide-left` (mirror exit), class `container` | slide-left | dismiss (back to S1); Back button top-leading | Nectar supply row |
| S3 | Nectar picker | sized `presentModal`, `scrim = "scrim"`, `outsideTapCancel = true` | slide-up + fade | dismiss | first premium card's action button |
| S4 | Provision Shop | sized `presentModal` above S3 | slide-up + fade | dismiss (returns to S3) | hero pack's buy button |
| S5 | Keeper's Charm shop | sized `presentModal` | materialize | dismiss | recommended tier's buy button |
| S6 | Wisp info | sized `presentModal`, `outsideTapCancel = true` | materialize | dismiss | Close button |
| S7 | Keeper screen | shell section (base) | per-section `When` fade | nothing (base) | first row (charm status) |
| S7a | Edit keeper form | sized `presentModal` | slide-up + fade | dismiss without saving | Display-name field |
| S7b | Fresh Start confirm | alert `presentModal`, `outsideTapCancel = false` | materialize | dismiss (keep world) | "Keep my glades" |
| — | Delight toast | `presentToast` (§12) | edge default | n/a (input-transparent) | n/a |

Sections: **Glades · Wisps · Flora · Keeper** (Flora is the Wisps grid skeleton with
plant species cards and no info modal beyond name + species line; browse-only, one
sentence of spec on purpose). Wisps grid is browse + Activate → S6.

## 4. Shell — one tree, five views

`UI.Composition` at the screen root; the section bodies live in one `nav` group and
one `content` group. Arrangements, richest first:

```
arrangements = { "twoLane", "column" }
groups = { { id = "nav",     lane = "lead", sizing = "hug" },
           { id = "content", lane = "main", sizing = "fill", minWidth = metrics.shell.contentMin } }
Regions (reading order):
  Region "Rail"    group nav     rank 2  forms: [sidebar list] → [icon rail] → [bottom tab bar]
  Region "Section" group content rank 1  sizing fill  mayScroll  forms: [active section body]
```

The Rail's forms: (a) sidebar — `VStack` of four `Button{selected}` rows (icon +
label, `newLabel` inside content), app wordmark `Text role=title` above; (b) icon
rail — same buttons `compactLabel { icon }`; (c) bottom tab bar — `HStack` of the
four as icon+caption stacks. Section bodies swap under `UI.When` keyed on the
selected-section signal (semantic, client-local), `transition = fade`.

**Adaptation table (size-class branches of this one tree + env facts):**

| View | Facts | Shell | Overview grid | Detail | Nectar picker |
|---|---|---|---|---|---|
| compact-phone-portrait | `sizeClass = compact`, touch | `column` fallback → bottom tab bar; content above | 1-col (`Grid minColumnWidth = metrics.glade.cardMin`) | S2 fullscreen modal | fullscreen-height modal, shelves as x-ScrollViews |
| compact-phone-landscape | compact, touch, short | `twoLane` with icon-rail form (lead lane hugs narrow) | 2-col | S2 fullscreen modal | sized modal, `maxMeasure` caps width |
| tablet | regular, touch | `twoLane`, sidebar form | 2–3 col (min width decides) | shell detail Region | sized modal, centered |
| desktop | regular/wide, pointer+keyboard | `twoLane`, sidebar form; hover previews live (§10) | 3–4 col | shell detail Region | sized modal, centered |
| console ten-foot | wide, gamepad, `tenFoot` type scale | `twoLane`, sidebar form; focus ring is the anchor; content kept inside safe insets by `coreSafeContent` | 2–3 col (bigger type re-columns via `minColumnWidth`) | shell detail Region | sized modal; one obvious Activate per view |

Reflow, never squeeze: every branch above is an arrangement/form change; nothing scales.

**Shell focus:** `navigationGroups`: `nav` (axis vertical in sidebar/rail forms,
horizontal in tab-bar form; `wrap = false`; exit toward content declared) and
`content` (vertical; grid cells arrow row-major). Tab order = declaration order
(search → cards → rail). Bumper-style section cycling is NOT specced (no such verb);
sections are reached by Navigate + Activate on every input class.

## 5. Component: GladeScene (the viewport)

A composite, used at card size (S1) and hero size (S2). `ZStack` (declared
`canvasGroup = true` so surface fades flatten):

```
ZStack "Scene" (corners panel, stroke hairline, clipChildren)
 ├ Box "Sky"        gradient = sky ramp memo (2–3 stops, reactive, rotation 90)
 ├ Image "TreesFar" (silhouette art, tint = phase silhouette rgb from the same table), scaleMode fill, Anchor bottom
 ├ Image "Floor"    moss floor art, Anchor bottom
 ├ Ferns: 2–3 Image per side via Anchor fractional offsets (x ≈ 0.08/0.16/0.24 and mirrored; staggered y for depth)
 ├ Image "Dewstone" basin art, Anchor { x = 0.5, y = 1.0, offset up by space m }
 └ When "Visitor" (currentVisitor present) → ZStack "Wisp": 3–4 tinted Image layers
     (core/glow/trail; per-species palette via tint), Anchor fractional offset bound
     to two motion springs (§11), scaled by species natural scale
```

Height: card form uses `aspectRatio` 5:3 inside the grid cell. Hero form steps by
width via `adaptive.conditions` — three declared steps (short/medium/tall) as a
size-class memo feeding `height` — the ledger's named approximation of the
reference's width-stepped custom layout. Layer budget ≤ 12 Images per scene.
Glade-name plate on cards: `Text` on a `Box surface = surfaceStrong, corners pill`,
top-leading, non-interactive. RTL mirroring of scene art: recorded gap, not claimed.

## 6. Component: SupplyRing

`ZStack`, fixed square (`metrics.supply.ring`): track `UI.Path` full circle
(`pathShapes` arc, role `secondary`, thickness `xs`), fill `UI.Path` arc 0→level
(thickness `xs`, `tint = extra.nectarGlow | extra.dewGlow`), centered `Image` (the
assigned nectar's art, or the dew droplet mark). Level = memo over `SupplyService`
refill stamp + drain constants + `now` fact; the painted arc binds a spring (§11).
Path culling rule respected: rings never overhang their clipping card. Ring emptiness
is the one time-remaining form everywhere (invariant 4 of the channel table).

States (drives, not paint-by-hand): full→draining (arc shrinks continuously);
**low** (past low stamp): "Low" `Text surface = chip` appears beside the caption
(`When`, fade); **empty**: arc zero + chip reads "Empty" + row caption `contentStrong`.
Hue never changes — form does (invariant 1).

## 7. S1 — Glades overview

`ScrollView` (the shell's one `mayScroll` region) containing:
1. Search `newTextInput{ clearButton }` (placeholder "Find a glade"). Suggestions
   while empty: memo rows over `VisitScheduler` current visits — "**Emberwisp** is
   visiting **Mossholm**" (bold via split Text runs) — Activate fills the filter with
   the glade name. Filter = case-insensitive contains on glade names.
2. `UI.Grid{ minColumnWidth = metrics.glade.cardMin, gap = m }` of glade cards,
   creation order; filtered set under `ForEach` keyed by glade id, transition fade.

**Glade card** (composite): `ZStack`: GladeScene card form; name plate (top-leading);
favorite star; bottom-trailing `HStack gap = s` of two mini SupplyRings on
`surfaceStrong` pill plates (glance-only, non-interactive). The card body is one
`Button` (children content) — Activate opens S2 / drives the detail Region selection.

| Element | States (semantic; hover/press/focus are framework-painted on `control`) |
|---|---|
| Card button | default · focused · pressed · (no disabled state exists) |
| Favorite star | off (`selected = false`, star outline glyph) · on (`selected = true`, filled, `controlSelected`) · toggling = `reward` pop (§11). Semantic label "Favorite". Not part of the card's activation surface — a sibling in the ZStack |
| Search field | empty (suggestions listed) · filtering (clear button live) · no-matches (inline empty state: `Text role = secondary` "No glades match \"{term}\"." + "Clear search" Button) |
| Mini rings | full · low · empty (per §6, glance form: no captions, chip replaced by ring emptiness only) |

## 8. S2 — Glade detail

`ScrollView`, `VStack gap = l`, padding `l`:
1. GladeScene hero form; happiness moment overlays its bottom edge (§12 toast is
   screen-level; the in-scene beat is the wisp glow pulse, §11).
2. Two **supply rows** (Nectar, then Dew), each a full-width `Button` (children):
   `HStack gap = m`: SupplyRing (large) · `VStack`: name `Text label`
   ("Starlight Syrup" / "Dew") + caption "{remaining} left — refills the glow"
   (remaining = proof-owned formatter, single largest unit: "6m", "40s") ·
   `Spacer` · trailing affordance `newLabel iconOnly` ("Choose nectar" /
   "Refill dew" — semantic titles preserved).
3. "Recent visitors" `Text heading` + `VStack` of visitor rows: wisp portrait
   (tinted layer stack in a circular `Box surface = surfaceStrong, corners pill`),
   name `Text label`, relative time `Text caption role = secondary` ("12m ago" —
   proof formatter). Row is a Button → S6. Empty state: "No visitors yet — keep the
   dew fresh." `Text role = secondary`.
4. Favorite star (same element contract as S7 card star) sits in the title row beside
   the glade name (`Text title`, `disclose = true`, lineLimit 1).

| Element | States |
|---|---|
| Nectar row | default · low · empty (per §6) · Activate → S3. Never disabled |
| Dew row | default · low · empty · Activate = **instant refill**: `SupplyService` stamp now; ring animates full (§11); feedback `activate` then `commit`; delight toast (§12). No confirmation |
| Visitor row | default · focused/pressed (framework) |
| Back (compact only) | Button, `compactLabel { icon = "chevron.leading" }`, top-leading; same outcome as Cancel |

Focus: groups `supplies` (vertical) → `visitors` (vertical); Tab order = document
order. `keepVisibleOffset` default keeps the focused row visible while scrolled.

## 9. S3 — Nectar picker · S4 — Provision Shop

**S3** `VStack gap = l`, padding `l`, inside the modal: title row (`Text heading`
"Choose nectar" + Done Button trailing) · "Premium" `Text heading` + x-`ScrollView`
(`axis = "x"`, bounded content) of premium **nectar cards** · "Standard" heading +
x-ScrollView of standard cards. Snap paging is not claimed (engine momentum only —
ledger §B). On compact-portrait the modal is full-height and the shelves stay
horizontal (thumb swipe); card width from `metrics.nectar.cardMin`.

**Nectar card** (composite, `Box surface = surface, corners panel, shadow raised`,
padding `m`, `VStack gap = s`): art `Image` in a circular `surfaceStrong` well —
premium cards overlay a count `Text surface = "badge"` bottom-trailing (owned count,
`textAlign = center`) · name `Text label` · summary `Text body role = secondary,
lineLimit = 2, disclose = true` (two lines reserved by layout so cards never jitter) ·
action Button (full card width).

| Card state | Action button | Behavior |
|---|---|---|
| Standard | label "Choose", `compactLabel { icon = "check" }` | assigns nectar + refill stamp; feedback `commit`; modal dismisses; toast (§12); gauge icon swap (§11) |
| Premium, owned ≥ 1 | label "Use 1" + count badge visible | same as Choose, and `CommerceService` decrements the satchel (the proof fixes the reference's untracked consumption — a design decision, recorded) |
| Premium, owned 0 | label "Shop", `role = "default"` | opens S4 |
| Any, while a purchase for it is pending in S4 | disabled, label "Confirming…" | pending never means success |

A "Provision Shop" row Button (icon + label) sits above the Premium shelf; Activate →
S4. Focus: groups `premiumShelf` (horizontal, wrap false) → `standardShelf`
(horizontal) → `footer` (Done). Arrowing down exits a shelf to the next group;
`scrollToVisible` keeps the focused card on screen.

**S4** `ScrollView` `VStack gap = l`: "Best value" hero — Starlight Syrup bundle as a
wide card with a "Best value" `Text surface = chip` pinned top-trailing (the chip
caps its own growth: `lineLimit 1`, no disclose — decorative, duplicated by the
hero's position) · "More provisions" heading · one shelf (x-ScrollView) per premium
nectar, priority order, packs ascending by quantity. **Pack card**: art (bundle art
differs from single art — proof assets) · name `Text label` · price `Text
surface = chip` (never truncates; service string) · buy Button.

**Buy button lifecycle** (every purchase-shaped verb in the proof, incl. S5):

| Phase | Button | Elsewhere |
|---|---|---|
| idle | label "Buy", price chip beside | — |
| pending | disabled, label "Confirming…" (`compactLabel "…"` is refused — one word: `compactLabel { icon = "hourglass" }`) | other buy buttons stay enabled; Cancel is refused politely: modal stays up until resolve (commands are short, scripted) |
| confirmed | returns to idle | satchel count badge counts up (`reward` counter, §11); feedback `commit` + `celebrate`; toast "Added to your satchel — 5× Starlight Syrup"; S3 card flips to "Use 1" live |
| rejected | returns to idle | **rejection notice** appears directly under the pack card (`When`, slide-down+fade): `Box surface = surfaceStrong, stroke hairline`, `Text body` = reason copy (§10 table); notice clears on next attempt or modal dismiss; feedback `reject`. Nothing silent, nothing reverts invisibly |

## 10. S5 — Keeper's Charm · S6 — Wisp info · S7 — Keeper · rejection copy

**S5**: marketing header — Tidewisp hero art floating over a soft `surfaceStrong`
glow ellipse, title `Text title` "Keeper's Charm", one-line pitch `Text body
role = secondary` — then tier cards (`VStack gap = m`): tier name `heading`, tagline
`body`, price chip, buy Button (§9 lifecycle). **Upgrade-only mode**: when the
current tier fact is Ember or Grove, only higher tiers render (`When` per card) and
the header pitch swaps to upgrade copy ("Go Lumen — Frostwisps arrive at first
light."). Confirmed purchase: tier fact updates → offer card on S1 unmounts
(`ForEach`/`When` exit, fade) → Frostwisp entries in S6/Wisps grid drop their
"Lumen only" chip → toast "You're a {tier} Keeper now." Entry points: an **offer
card** at the top of S1's scroll (only while tier = none; `Box raised` with pitch +
"See the Charm" Button + an explicit **Dismiss** Button — the ledger's visible-verb
adaptation of swipe-dismiss; dismissal is session-local presentation state) and the
S7 charm row.

**S6**: portrait (large tinted layer stack over a mini sky at the species' preferred
phase — the one avatar treatment reused everywhere) · name `heading` · species line
`body role = secondary` · "Last seen {relative} in {glade}" or "Not yet seen"
`caption` · favorite nectar chip · Frostwisp only, tier < Lumen: "Arrives early for
Lumen Keepers" chip + "See the Charm" Button → S5. Close Button top-trailing.

**S7** `ScrollView` form-style `VStack`: header (keeper portrait = linked wisp
avatar, display name `heading` + tier chip, joined date `caption`) · charm row
(tier none: "Get the Keeper's Charm" Button → S5; tiered below Lumen: "Check out
Lumen" Button → S5 upgrade mode; any tier: status line `caption` "Your Keeper's
Charm: {tier}") · "Restore provisions" Button (fake ledger re-sync command: pending =
disabled + "Restoring…", confirmed = toast "Satchel up to date.", rejected = inline
notice per §9) · Edit Button (pencil icon) → S7a (Display name + contact fields,
`newTextInput`; Done commits, Cancel discards; no validation — mirrors reference) ·
**Fresh Start** Button `role = "destructive"` → S7b confirm modal ("Start over?
Glades, satchel and charm return to a fresh morning." · "Keep my glades"
`role = "cancel"` / "Start over" `role = "destructive"`). Confirm = scenario reset:
services reseed from fixed seeds, all surfaces dismiss to S1, dump byte-identical.

**Rejection copy** (scripted `CommerceService` fixtures; hard fallback always last):

| Reason | Player-facing copy |
|---|---|
| `declined` | "The purchase didn't go through. You weren't charged." |
| `offline` | "Can't reach the shop right now. Try again in a moment." |
| `owned` (charm) | "You already have this charm tier." |
| fallback | "Something went wrong. You weren't charged." |

## 11. Motion spec (classes, not durations; reduced-motion per row)

| Moment | Mechanism | Class | Reduced motion |
|---|---|---|---|
| **Wisp fly-in** | `clock:timeline`; wisp Anchor offset = two scalar springs (x, y) + one scale spring. Beats: 0 s appear at trailing edge, small; 0.15 s glide toward basin (x/y retarget); 1.1 s overshoot hover + scale to natural; 1.8 s settle above the dewstone; ~2.8 s done. Runs once per `needsPresent` visit; `interrupt()` on navigation away | glide `object`, arrival pop `reward` | timeline `reduced`: beats fire instantly, wisp placed at rest; declared `reducedMotion = "fade"` — a fade-in at the perch. Same `onDone` fires |
| Favorite toggle | scale pop on the star | `reward` | instant state swap (framework parity) |
| Supply ring level | painted arc chases the level memo via spring; refill = retarget to full | `object` | snap to level |
| Gauge icon swap (nectar change) | `When` keyed on nectar id, `transition = "materialize"` | `container` | instant, same events |
| Satchel/count changes | `clock:counter` on the badge value | `reward` | final count placed instantly |
| Delight glow (post-refill) | wisp glow layer transparency spring up-then-down once | `decay` | skipped (decorative; toast carries the information) |
| Surface enters/exits | §3 table transitions, mirror exits | `container` | instant placement, same frames/events |
| Rejection notice | `When` slide-down + fade | `container` | instant |

No ambient loops: rest costs zero. Sound hooks ride the feedback bus taxonomy only
(`activate`, `commit`, `reject`, `celebrate`, `dismiss`); proof plays no audio.

## 12. Toasts

`presentToast`, position `top`, duration 4 s, default read floor. Keys supersede
same-subject repeats: refill delight = key `refill:{gladeId}`, copy "{Glade} is
glowing brighter." (fires on either supply's refill commit); purchase = key
`purchase`, copy per §9/§10; restore = key `restore`. Toasts are display-only and
input-transparent; nothing in the loop depends on reading one (the state itself is
always visible in place).

## 13. Text, preferred-text, localization

- **Wraps/reflows:** tier taglines, marketing pitch, empty states, rejection copy —
  unbounded wrap inside scrolls. Supply-row captions wrap to 2 lines before the row
  grows (rows are content-sized, never fixed-px — the fixed-px-height defect class).
- **Truncates with `disclose = true`:** glade names (cards, S2 title, toast subject
  interpolations are short-safe), nectar names on cards (lineLimit 1), nectar
  summaries (lineLimit 2), visitor/wisp names in rows (lineLimit 1).
- **Never truncates:** prices, counts, remaining-time captions (single-unit,
  numerals), chip states ("Low"/"Empty" — 1.4× checked in the string table).
- **compactLabel declarations:** Back `{ icon = "chevron.leading" }`, Close
  `{ icon = "close" }`, Done "OK", Choose `{ icon = "check" }`, Buy/Shop/"Use 1"
  fit at 1.4× by string-table constraint (compact forms declared anyway:
  `{ icon = "cart" }` for Shop, `{ icon = "check" }` for Use 1), pending
  `{ icon = "hourglass" }`.
- **Localization:** proof-owned `I18n` string table keyed on `env locale`, including
  the ~1.4× pseudo-expansion locale; every screen must pass the five-view matrix
  under it with zero clipped-essential findings from the text audit. Relative-time
  and remaining-time formatting are proof-owned (ledger: no host date formatter).
  Type scale 0.5–3: grids re-column via `minColumnWidth`, supply rows and shelves
  reflow (stacks, never squeeze), ten-foot type scale composes into the same
  size-class branches. BiDi/RTL mirroring: recorded gap, not claimed.

## 14. State split, input coverage, out of scope

**Semantic (service-owned, survives re-solve):** refill stamps, drain constants,
satchel counts, charm tier, visit windows, favorites, selected section, selected
glade, assigned nectar per glade, keeper profile, purchase command phases, offer-card
dismissed-this-session flag (client-local semantic). **Presentation (throwaway,
never replicated):** focus, hover, scroll offsets, ring spring positions, timeline
progress, toast schedule, disclosure plates. Optimistic UI: none — every mutation
waits its (short, scripted) confirm; pending is always visibly labeled.

**Every verb on every input class:** Activate = tap / click / Return + Space /
gamepad A. Cancel = gamepad B + on-screen Close/Back on every modal + outside tap
where the table says so (never a hardware Escape — platform-reserved). Navigate =
Tab/Shift-Tab + arrows / d-pad through the declared groups; no verb is hover-only
(hover adds only the disclosure dwell and control hover paint). Adjust: unused in
P1. No focus traps: every modal's group set reaches its Close; `traversalWrap`
default holds.

**Deliberately out of scope** (ledger §B, no-host-equivalent rows — recorded, never
simulated): home-screen widgets and the one-tap resupply-both intent, watch
app/complications, platform commerce sheets (purchase chrome, manage-subscription,
offer codes — production ends at the `MarketplaceService` prompt call), system
restore chrome (the S7 button is a fake ledger command, stated plainly), RTL scene
mirroring (shared BiDi gap row).

## 15. RA-P1 loop walkthrough (build acceptance)

1. S1: rings visibly drain (demo constants) → 2. Activate Mossholm → S2 →
3. Dew row Activate = instant refill (ring restores, resumes draining; toast) →
4. Nectar row → S3; premium "Use 1" path AND standard "Choose" path both exercised →
5. Visitor row → S6 info → 6. S3 "Provision Shop" → S4; buy a bundle → confirmed
path (count badge counts up, S3 flips to "Use 1") → buy again → scripted `declined`
rejection (notice + toast-free, button restored) → 7. S5 via S1 offer card; charm
purchase confirmed (offer card leaves, Frostwisp chip drops) and `owned` rejection
exercised → 8. S7 Fresh Start → S7b confirm → world reseeds, byte-identical dump.
Every state in §§6–10's tables must be reachable in the played slice.
