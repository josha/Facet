# ADR-0053 — The presenter-seam family: a chrome bar, a re-band, and a chrome priority

**Date:** 2026-08-23
**Status:** Accepted
**Number:** 0053. 0040 is the unreleased-breaking-changes register; **this
decision adds no row there** and "Not a breaking change" below says why.
**Companions:** [ADR-0045](ADR-0045-tab-view-accessory-slots.md) (item 13's
sibling gap — why the accessory-slot shape does NOT reach these four sites),
`docs/handoff/SOURCE_CAP_LEDGER.md` (`presenter.luau`'s row — why items 23/24
were blocked until 2026-08-22's `surface_lifecycle` split cleared the band),
`.superpowers/sdd/framework-gaps-phase2/gap-registry.md` items 13/23/24,
`.superpowers/sdd/framework-gaps-phase2/task-g6-report.md` (item 13's
file:line evidence), `.superpowers/sdd/release-candidate-review/
task-dir4-report.md` (item 23/24's CONTESTED origin), `artifacts/
release-candidate-review/t16-triage.md` (the director's "ship as-is, band
re-spacing rides the extraction charter" ruling both items cash in here),
`src/present/nav_bar.luau`, `src/present/surface_lifecycle.luau`,
`src/present/presenter.luau`, `src/present/catchers.luau`,
`tests/nav_bar.spec.luau`, `tests/presenter.spec.luau`,
`tests/surface_lifecycle_seam.spec.luau`, `tests/gallery_chrome.spec.luau`.

## Context

Three phase-2 gap-registry items share one home (`src/present/*`) and one
mission (W3-D):

* **Item 13** — no navigation-bar chrome seam. `task-g6-report.md`'s item-13
  assessment (wave 2) found four hand-built back+title bars, with file:line
  pointers, and PROVED the shape `newTabView`'s accessory slots (ADR-0045)
  cannot host them: all four are a **presented or compact-open detail
  surface's own chrome**, never a tab strip's — three sit at the top of a
  modal, one is a compact-only header inside a screen's content, and the
  accessory matrix is keyed to `adaptive.navPlacement` homes none of them are.
* **Item 23** — `presenter.raise`: re-band a live surface without
  dismiss+re-present. `task-dir4-report.md` (DIR3-review MAJOR-2) named the
  seam and reported it CONTESTED — `presenter.luau` was extraction-locked at
  the time, so the shipped mitigation (`showcase_chrome.luau`'s `raisePanel`)
  dismissed and re-presented the panel instead, at the cost of a full
  remount: a fresh focus scope, a played transition, and a 4-frame
  focus-restore retry loop to put the ring back.
* **Item 24** — no priority band for app-level global chrome.
  `showcase_chrome.luau`'s own toggle context picked `3500`, which
  **exactly ties** `presenter.luau`'s `topModalPriority() + 500` for the
  first live modal — measured, and also CONTESTED in `task-dir4-report.md`
  ("a modal demo with a focused adjust target still double-fires").

`t16-triage.md` records the same disposition for both 23 and 24: "mitigation
shipped... band re-spacing rides the extraction charter." The charter is this
round — `SOURCE_CAP_LEDGER.md`'s presenter.luau row was RE-RECORDED
2026-08-22 at 178,325 characters, clearing the 190,000 band-trigger line by
11,675, once the surface-lifecycle split landed. The file is editable again;
this ADR is what it was owed.

## Decision

### 1. Item 13 — `Facet.navBar`, a PURE blueprint factory, not a presenter opt

`src/present/nav_bar.luau` exports `navBar.build(spec) -> Blueprint`, wired
to the top level as `Facet.navBar`. It takes no core, no scope, and no
presenter or handle reference:

```lua
Facet.navBar({
  id = "TopBar",
  onBack = onBackOrNil,        -- nil = no Back button (refuse, don't guess)
  backLabel = "Back",          -- required alongside onBack
  title = titleOrNil,
  titleSize = "title",
  titleWidth = dimOrNil,
  trailing = { ... },
  gap = "s",
  padding = paddingOrNil,
})
```

**Why a pure factory and not "a `present*` option that mounts chrome above
the body"** (the other shape `task-g6-report.md` floated). The four sites are
structurally incompatible with a single presenter-owned slot: one bar's
back verb reaches an app-level modal-stack wrapper that also bookkeeps a
`retired`-scope list and app state (`p1_glade`'s `nav.closeDetail`), another
reaches a plain app router (`p2_cartwheel`'s `app.actions.back`); one bar has
no title at all (`p3_sipworks/detail.luau`); one bar's title SCROLLED with
its body before this round (`p1_glade`) while the other three pin it above a
`ScrollView`. A presenter-owned slot would have to either standardize this
diversity away (a product decision this mission has no authority to make) or
grow a matrix as complex as the one ADR-0045 already rejected for exactly
this reason. A pure factory lets every site keep its own placement decision
and its own back-verb wiring, sharing only what the four genuinely share
(`task-g6-report.md`'s own words): "(a) a leading Back bound to the surface
stack's own verb, (b) a title that truncates into its disclosure rather than
widening its pane, and (c) optional trailing actions."

**`onBack` is refuse-don't-guess applied the only way a stateless construct
honestly can.** It never invents a verb — `nil` renders no Back button, full
stop. This is the same doctrine the accessory matrix uses (ADR-0045 §2:
"a slot the placement can never host REFUSES"), applied at the caller's
information boundary instead of the construct's.

**A disclosed visual harmonization.** Two of the four sites already drew
`compactLabel = { icon = "chevron.leading" }`; the other two
(`p3_sipworks/detail.luau`, `p3_sipworks/book.luau`) drew a circle-shaped
`Button` with a literal `"<"` Text child. `Facet.navBar` standardizes on the
framework's own chevron icon for all four. This is a real, visible change for
those two sites — recorded here rather than buried, per this campaign's own
comment-code discipline — and not one that needed a product decision: a
hand-typed glyph is exactly the kind of private DSL this campaign's other
waves (item 14, `UI.fill`/`UI.hug`) exist to retire in favour of the
framework's own vocabulary.

**Home: `src/present/*`, not `src/controls/`.** `task-g6-report.md`'s
recommendation, verbatim: "its real companion is registry item 12's sibling,
[...] not this gap" — meaning the presenter family, because the Back verb's
theme (a surface's own dismissal) is that family's, not `newTabView`'s.

### 2. Item 23 — `presenter.raise(handle)`, living in `surface_lifecycle.luau`

`presenter.raise` reserves the SAME next `displayLayer` slot `makeHandle`
would spend on a fresh present, writes it onto the SAME handle in place, and
pushes it to the adapter with the SAME `controller.setDisplayOrder` call
`makeHandle` already makes at creation — nothing else. The handle's tree,
scope, focus scope and transition state are never touched, so nothing
remounts, no enter transition replays, and focus never moves.

```lua
local function raise(handle: any)
	if type(handle) ~= "table" or table.find(stack, handle) == nil then
		return
	end
	displayLayer.value += 100
	handle.displayOrder = (if handle.kind == "modal" then SURFACE_LAYER.modal else SURFACE_LAYER.base)
		+ displayLayer.value
	if handle.controller.setDisplayOrder ~= nil then
		handle.controller.setDisplayOrder(handle.displayOrder)
	end
	syncScrim()
end
```

**Lives beside `dismiss`/`back` in `src/present/surface_lifecycle.luau`**,
not in `presenter.luau` itself — `SOURCE_CAP_LEDGER.md`'s row for
`presenter.luau` names `makeHandle` (85,693 characters, 48% of the file) as
never a candidate for further extraction and directs new room to come from
"around" it; a NEW capability is better added to the satellite module that
already owns the sibling surface-lifecycle verbs than grown directly inside
the host file. The seam costs one new ctx field, `SURFACE_LAYER`, threaded
the same way `displayLayer` already crosses (by reference, read-only on this
side) — `tests/surface_lifecycle_seam.spec.luau` pins the mechanics exactly
as it pinned the original three-verb split.

**Does not reduce the band cost, and says so.** `raise` still spends a
`displayLayer` slot, identically to a fresh present — bands only grow
forward, and no re-banding scheme can avoid that without breaking the
"later-presented is higher" invariant every existing modal/toast ordering
already depends on. What it removes is the mount/scope/transition/focus COST
a dismiss+re-present pays for the SAME re-band, not the slot. This is stated
precisely in `docs/reference/api.md`'s "standing rule" section (corrected in
this round — it previously said "There is no `presenter.raise(handle)`
today," which this round makes false) and in `showcase_chrome.luau`'s own
updated comment, so a future reader does not conflate "cheaper operation"
with "cheaper number."

**Catchers follow the raised surface.** `syncScrim`/`syncPopupCatcher`
(`src/present/catchers.luau`) used to remount their catcher only when its
OWNER changed — correct for present/dismiss, silently stale for a raise,
which changes the owner's `displayOrder` without ever changing which handle
owns it. Both now reposition (a single `setDisplayOrder` write, not a
remount) on every sync, whether or not the owner changed — cheap enough to
pay unconditionally rather than track a fourth field just to detect the case.

**Migrated the real consumer in the same round.**
`examples/gallery/client/showcase_chrome.luau`'s `raisePanel` — the DIR3
MAJOR-2 mitigation itself — now calls `presenter.raise(panelHandle)` directly.
This deleted the entire focus-restore retry mechanism the mitigation needed
(`pendingFocus`, `lastPanelFocus`, `pendingFocusTries`, the `isPanelPath`
prefix test, and a `presenter.focus.focused` observer that existed only to
remember where the ring was before a remount lost it) — real complexity this
round removes rather than leaves as a second, now-unnecessary code path.
`tests/gallery_chrome.spec.luau` describe (15) exercises the migrated
`raisePanel` end-to-end through the real InputAction/demo-picker path and
needed no behavioral change: the failed-mount-costs-nothing guard, the
successful-swap-costs-one-slot measurement, and the ring-survives-a-swap
case all still hold, now for a stronger reason (nothing capable of moving the
ring ever runs, rather than a retry loop that usually wins the race).

### 3. Item 24 — `presenter.APP_CHROME_PRIORITY`, a static ceiling with room

Census (this round): `RascalRally`'s `HudZoneModel`/`GearDockModel` and their
consumers (`FacetSettingsGui.luau`, `SettingsGui.luau`, `SponsorGui.luau`)
only ever set raw `DisplayOrder`/`ZIndex` — the PAINT-order axis, which
already has a documented, adequate mechanism (`host.new({ displayOrder })`,
per `docs/reference/api.md`). RR's one hand-rolled InputAction priority for
persistent chrome (`FacetSponsor.POSE_CONTEXT_PRIORITY = 1000`) is
non-sinking and sits below `BASE_SCREEN_PRIORITY` — it never contends for the
exclusive band at all. The **one** measured, real, CONTESTED consumer this
campaign found is `Facet`'s own showcase example.

```lua
local APP_CHROME_PRIORITY = ENGAGED_BASE_PRIORITY + 500 * 20 + 500 -- 13500
self.APP_CHROME_PRIORITY = APP_CHROME_PRIORITY
```

**Why a static ceiling, not a live query.** `topModalPriority()` is exposed
nowhere and stays that way: it is only safe to read at the instant it is
asked, and app-level global chrome's whole point is a context bound ONCE at
boot, before any modal the player will ever open — reading
`topModalPriority() + N` then would still tie a modal opened two levels deep
later. The only number safe for a context's WHOLE SESSION is one PROVABLY
above every value `topModalPriority()` can produce, which needs a bound on
modal depth. Twenty simultaneously-open nested modals is that bound — the
same "far past anything real" doctrine `displayLayer`'s own header already
claims for cross-surface z (~100 live surfaces before two collide), applied
to a shape nothing in this codebase exercises past two.

**Migrated the real consumer.** `showcase_chrome.luau`'s
`TOGGLE_PRIORITY = 3500` literal is gone; the toggle context now reads
`presenter.APP_CHROME_PRIORITY`. `tests/gallery_chrome.spec.luau`'s existing
priority assertion moved from the deleted constant to the presenter field.

## What was rejected

**A live-derived app-chrome priority (`topModalPriority() + margin`, read at
boot).** Rejected in "Why a static ceiling" above: session-lifetime chrome
cannot re-derive its own priority when a LATER modal opens, so any formula
that reads the CURRENT stack at construction time is exactly as fragile as
the literal it would replace, only harder to notice going wrong.

**A `presenter`-aware `Facet.navBar` that auto-derives `onBack`/visibility
from the live stack.** Considered and rejected for item 13: none of the four
migrated sites' back verbs are a plain `presenter.dismiss(handle)` call —
each wraps its own app-level bookkeeping around it — so a construct that
reached into the presenter directly would either bypass that bookkeeping
(a correctness bug) or need a second, parallel callback anyway (no
simplification). `onBack` stays a plain caller-supplied closure.

**Reducing `displayLayer`'s per-raise cost below a fresh present's.**
Considered for item 23 and rejected: any scheme that gives `raise` a CHEAPER
band number than a present (e.g. slotting it "between" two existing values)
breaks the "later action gets a higher number, always" invariant every
existing modal/toast/scrim ordering decision already reads. The real,
measurable win is operational (no remount), not numeric, and is stated as
such rather than oversold.

## Not a breaking change (no ADR-0040 row)

Every change is additive: `Facet.navBar` is a new top-level export;
`presenter.raise` and `presenter.APP_CHROME_PRIORITY` are new fields on the
`newPresenter` instance (covered by that row's existing surface-ledger
classification — no new top-level export). No required prop was added and no
documented default moved. `showcase_chrome.luau`'s migration to
`presenter.raise`/`presenter.APP_CHROME_PRIORITY` and the four sites'
migration to `Facet.navBar` are example-internal; the one disclosed visual
change (item 13's chevron-icon harmonization on two sites) is a rendering
detail of an EXAMPLE, never a framework default, and is recorded above rather
than through an ADR-0040 row, whose own definition is scoped to the
framework's public defaults.
