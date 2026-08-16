# Director call, 2026-08-16 — what is a property, and what is actually new

The director asked, of the constructs the reference screenshots name: *can this be done
with additive properties on existing controls, or does it need something net new?*

The answer is that **most of this round is properties**, and the two genuinely new
constructs are smaller than the brief implies because two of the four "missing" mechanisms
are already shipped as presenter-private machinery. Every row below was read in source at
`6bf6fce23`, not remembered.

## The call

| Screenshot behaviour | Verdict | What it actually costs |
|---|---|---|
| `r1` dropdown with icon rows and dividers | **Additive** | `icon` on `popup_button.Option`, plus a divider item kind |
| `r3` / `f1` segmented pill with icons | **Additive** | `icon` on `picker.Option` |
| `f1` **vertical** two-button pill (left rail) | **Additive** | a public `axis` prop on `newPicker` — see §1 |
| `f1` overflowing tab strip scrolls the selection into view | **Reuse, no new code** | `solver.keepVisibleOffset` (`src/layout/solver.luau:279`) already is "make this rect visible in its scroll ancestor". `LuauUI.newAutoscroll` is **not** this — it is a drag-to-edge pointer model (`src/input/autoscroll.luau`), and the brief names the wrong one |
| A badge on an unselected tab | **Reuse, no new code** | `surface = "badge"` is a shipped token (`blueprint_schema.luau:1741-1751`) |
| `r2` / `r3` sliding selection chip | **New, but INTERNAL** | the rect publisher + rect-to-rect animator is real new machinery; the public surface is one `indicator` property. See §2 |
| `f1` auto-popped coach-mark plate | **Mostly shipped** | `presenter.disclosure` already places against a source rect, flips, and clamps into the safe box; `toast_schedule` already gives it a capped queue. See §4 |
| `help` on hover | **Mostly a DELETION** | the hover-dwell and focus triggers already exist. See §3 |
| `f1` floating action menu | **NET NEW — but extract, do not rebuild** | see §5 |
| `r2` top tab bar nested inside an app-level tab | **NET NEW** | see §6 |

## 1. `axis` is not a public prop, so there is nothing to overload

`PICKER_KEYS` (`src/controls/picker.luau:56-64`) is exactly:
`enabled, id, label, onChange, options, presentation, selected, sizeClass`.

`axis` is a **private memo** at `:146-148`, derived from `presentation`
(`"x"` when segmented, `"y"` otherwise). The brief's warning — *"Today `axis = 'y'` means
the inline row list… Add it without overloading the existing meaning"* — describes that
internal variable, not a public contract. No caller can set `axis` today, so a new public
`axis = "x" | "y"` prop, meaningful only when the resolved presentation is `segmented`,
overloads nothing and breaks nobody.

**D6 becomes a properties-only stage.**

## 2. The sliding indicator is an internal seam, not a construct

The mechanism is genuinely new: nothing today publishes a selected child's solved rect
reactively so a sibling node can animate between rects. Selection is painted as a style
tag on a Button (`picker.luau:123-141`; Button's `selected` prop *"rides a style tag,
never a bespoke fill"*, `blueprint_schema.luau:1913-1919`).

But a decorative bar that can never take input must not be a registered control. It has no
honest four-input proof and no paradigm axis, and `check_registration` would demand both.
So: **internal module, consumed by Picker and TabView; public surface is
`indicator = "underline" | "pill" | "none"`**, and its state appears in the consuming
control's `dump()` rather than a schema of its own.

## 3. `help` is mainly an unbinding

`presenter.luau:1546-1549` already routes both `self._discloseHover(path)` and
`self._discloseLongPress(path)`; `DISCLOSE_DWELL = 0.45` is at `:819`, and focus
revalidation is already wired. The placement, the dwell timer and the safe-box clamp all
ship.

So D3a is: promote it to a public, content-authored surface — and **remove the long-press
binding**, because D2 needs that gesture and it is the one input class where neither
construct has an alternative. That is a behaviour change to shipped machinery, so it needs
its own regression, not just a new spec: something today relies on long-press showing a
truncated label's full value, and that route has to be re-provided or deliberately
retired.

## 4. `Callout` is two shipped mechanisms plus a tail

- Placement, edge flip, safe-box clamp, re-clamp every tick: `presenter.luau:976-1046`
  (`presentDisclosure`) and `:942-968` (`clampDisclosure`).
- Non-blocking, input-transparent, **capped queue**: `presentToast` (`:3764-3792`) over
  `src/present/toast_schedule.luau`, which the presenter's own comment says *"owns
  priority, the queue cap, read floors"*. That is "at most one on screen, a queue not a
  pile" already built.
- Non-consuming tap-away: `catchers.luau`, `consume = false`.

Net new for D3b: the **arrow tail** and the **eligibility/invalidation contract**. Not a
construct from scratch.

## 5. `Menu` is net new — and `row_actions` already wrote its rows

The contract really is different from `popup_button`: that control's `value` is a
`Signal<string>` and its `Option` is `{ id, label }` (`popup_button.luau:30-33`). A verb
list is not a value picker, and a control that sometimes owns a value Signal and sometimes
does not is two controls in one.

**But `src/controls/row_actions.luau:1759` `buildMenuRows()` already renders exactly the
f1 menu**: `UI.Button` rows carrying `label`, `compactLabel = { icon = … }`,
`role = "destructive" | "default"`, a `MENU_ROW_HEIGHT` token, presented as a sibling
surface with its own root and an edge-flipping anchor (`computeMenuAnchor`, `:1928-1946`).
It even carries a device-round director ruling in its comments about why a menu row keeps
its label while a tray inverts to icon-first.

So D2 **extracts** that row recipe and presents it on D1's seam. It does not author a
third menu. Three copies of a menu row is how the icon-first ruling gets silently lost.

## 6. `TabView` is net new, and should be built ON the upgraded Picker

It cannot be a property, because it owns things a picker never does: the **content**
subtree and its lifecycle (lazy, evicted, really disposed), the **placement** that
restructures the whole screen (`adaptive.navPlacement`), and **nesting**, which needs two
live instances to arbitrate focus scope, the presenter's `back()` stack, and which of them
may claim the app-level placement.

But its **strip** is precisely a segmented picker with an indicator. Compose it from the
D6 picker rather than reimplementing the row. That is what makes the brief's claim —
*"segmented used as a tab bar IS TabView with `indicator = 'pill'`"* — true in code instead
of true in a document.

## 7. D1 is neither additive nor new — it is a consolidation

The anchored surface already exists twice, hand-rolled: the disclosure plate (§4) and
`row_actions.computeMenuAnchor`. D1's value is that it **removes** a duplicate rather than
adding a third. That is also its acceptance test: a D1 that lands without migrating at
least one of the two existing copies onto it has made the problem worse.

## What this changes about the round

- **D6 is properties-only.** No new construct.
- **D3a is a promotion plus a deletion**, and the deletion needs a regression.
- **D3b is a tail plus an eligibility rule** over two shipped mechanisms.
- **D2 extracts** `buildMenuRows` instead of authoring menu rows.
- **D5 composes** the D6 picker for its strip.
- **D4 ships no public construct.**
- **D1's success condition is a migration**, not a new module standing alone.

The brief's shape survives; its cost does not. Two net-new constructs, one internal seam,
one consolidation, and a set of properties.
