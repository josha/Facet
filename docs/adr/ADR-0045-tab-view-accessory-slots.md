# ADR-0045 — A nav bar's chrome is a SLOT the placement decides, not a second shell

**Date:** 2026-08-22
**Status:** Accepted
**Number:** 0045. 0040 is the unreleased-breaking-changes register; **this
decision adds no row there** and §"Not a breaking change" below says why.
**Companions:** [ADR-0037](ADR-0037-public-call-shapes.md) (the namespace the
control is reached through), [ADR-0040](ADR-0040-unreleased-breaking-changes.md)
§B-4/§B-12 (the placement policy and the centred-band contract this obeys),
`src/controls/tab_view.luau` and `src/controls/picker.luau` (home),
`tests/tab_view_accessories.spec.luau`, `tests/tab_view.spec.luau`,
`tests/picker_segments.spec.luau` (the guards),
`games/RascalRally/code/tests/facet_tab_view_contract.spec.luau` and
`facet_segmented_picker_contract.spec.luau` (the consumer's own evidence).

## Context — the construct shipped to kill a wheel, and only one app could use it

`Facet.Controls.TabView` exists *precisely* to remove the four-`When` nav wheel
every reference app was assembling by hand; `p4_foyer/init.luau:817-820` says so
in as many words. But its Spec had no leading, trailing or foot slot, so the only
app that could adopt it was the one whose chrome never moves. p4 did.

The other two did not, and the reason in each case was one piece of chrome:

* **`p1_glade`** puts a **wordmark at the rail's head**. It belongs to the rail
  form alone — a brand mark beside a centred cluster pushes the cluster off
  centre at the expansion locale — so it cannot simply ride above the whole
  control.
* **`p3_sipworks`** puts a **search field in three homes**: inline atop the list
  pane on the sidebar shape, on the top band's **trailing edge**, and directly
  **above the thumb-zone dock**. The first is content; the other two are chrome
  the placement moves.

So both kept ~300 hand-built lines apiece, and **the examples directory shipped
two contradictory teachings of the same thing** — which is worse than either.

## Decision

### 1. Four slots, homed by the placement the control already resolved

```lua
accessories = { head?, foot?, trailing?, aboveBar? }
```

Each is a **factory** `(placement, scope) -> Blueprint?`, invoked only by the
homes that host that slot, inside that home's own `When` branch — so the scope it
receives is disposed when the home goes away, and a factory that returns nothing
leaves no node at all.

| slot | hosted by | why not elsewhere |
|---|---|---|
| `head` | `sidebar` | a rail has ends; a band has edges |
| `foot` | `sidebar` | the rail's foot is the BOTTOM of the rail — the strip's scroller spends the slack |
| `trailing` | `topBar` | the centred band's strip hugs, so chrome at its trailing edge must OVERLAY it (B-12) |
| `aboveBar` | `bottomBar`, `bottomBarCompact` | a `fill` band divides its width among equal targets; an overlay would cover one. What a dock has room for is a strip above it |

`tab_view.accessoryPlacements(slot)` is that table, pure and exported, so the
refusal message and the mount obey one statement of the rule and the matrix is a
test over strings.

### 2. A slot the placement can never host REFUSES — at the one moment it is provable

A **declared** `placement` (or nesting, which always resolves `topBar`) narrows
the reachable homes to exactly one. Chrome declared for a home that can never
exist is then a bug whose only symptom is silence, so it raises at construction
and names the homes that do host it. Under `placement = "automatic"` every home
is reachable and nothing is refused; a factory declines a shape by returning
nothing. `railWidth` rides the same rule.

### 3. Declaring nothing mounts nothing, structurally

The wrappers appear only when a factory really returned a blueprint. Every path
that shipped before this — the four `p4_foyer` pins among them — is unchanged,
which is what let p4 keep working without an edit and is pinned in both repos.

### 4. Three smaller things the migration forced, each measured

None of these is chrome; all three are findings that would otherwise have been
lost in the move, and each is pinned by a case that reddens without it.

* **`railWidth`** — the sidebar rail was content-sized with no way to bound it.
  `p3_sipworks` had capped its own rail at 300px because a 1.4x locale at the
  largest text preference grew it past 400 and squeezed the content lane;
  migrating without the cap put the tablet two-pane row **82px** outside its box
  (six solver diagnostics, one per measure row). A rail states its band and the
  labels adapt inside it.
* **`textSize`** on `newPicker`, passed through by `newTabView` — a thumb-zone
  tab bar is caption-sized in tighter chrome, "which is what a tab bar is
  everywhere" (`p1_glade`'s own shipped comment). At body size a four-word band
  truncated **three of its four tabs** on a 320px phone at the +4 text
  preference, which is the exact director report ("I see a lot of cutoff text")
  the terse vocabulary answers. The construct carries the binding; it does NOT
  pick the ramp — which home takes which role is a design language, so the caller
  binds it against the placement.
* **`transition`** on the content branches — both shells declared
  `{ enter = "fade" }` on their own section hosts, and the construct had nowhere
  to say it, so adopting it swapped a fade for a hard cut in two shipped proofs.

### 5. Two behaviour fixes the migration exposed

* **A declared `sizing = "hug"` in the thumb zone now centres and scrolls.** The
  bottom band is deliberately not a scroller *because a `fill` strip has nothing
  to overflow with* — a statement about the DEFAULT that the code had applied to
  the HOME. A caller declaring `hug` there got natural-width segments parked at
  the band's leading edge with nothing able to scroll them.
* **A pick and its `onChange` are ONE transaction** (`newPicker`). The control's
  write used to flush on its own, so a caller that redirected or vetoed from
  inside `onChange` published a value it was about to undo: every observer saw
  it, and a `UI.When` over the selection mounted a whole subtree and evicted it
  in the same frame. `p3_sipworks`' Steam Stamps tab is exactly that caller — on
  a roomy shape it presents the rewards card rather than becoming the section —
  and the transient mount was measured on the migrated shell before the fix. A
  transaction defers the FLUSH, never a read, so an `onChange` still sees the new
  value.

## What was rejected

**A `foot` slot that hosts `p3`'s Steam Stamps pocket.** The audit named the
pocket as `foot`'s consumer and it is not one. The pocket is a nav DESTINATION
whose position moves — a spacer pushed it to the rail's foot in the sidebar form
and nowhere else — and moving a segment out of the strip is a strip concern: one
picker object serves every home by contract, which is what makes a re-home a
re-solve instead of a rebuild. An accessory is chrome BESIDE the tabs, and
serving the pocket through one would have meant either a duplicate entry in the
rail or a placement-dependent `tabs` array, neither of which the construct can
mean. So `foot` ships as the rail's other end (structurally the same node as
`head`, proved by the matrix spec) and **`p3` reads its pocket in declared order
instead** — the one deliberate behaviour change in this round, recorded here
rather than buried. What the pocket DOES is unchanged.

The honest shape for restoring it is a per-tab pin (`Tab.pocket`, a second strip
in the rail's foot sharing one selection Signal), which is a strip feature with
its own cost — three picker objects and a `relearn` over all of them — and wants
its own round and its own ruling.

**A framework-owned type ramp** (the construct choosing caption for the thumb
zone). It would have changed `p4_foyer`'s shipped bottom bar, which this round
was required to leave untouched, and it is a design-language call rather than a
layout rule. The vocabulary ships; the policy stays with the caller.

## Not a breaking change (no ADR-0040 row)

Every addition is an optional key with a nil default, and every default is
unchanged: no required prop was added, no documented default value moved, and the
no-accessory mounted tree is identical (pinned in `tests/tab_view_accessories.spec.luau`
and in the Rascal Rally rider). The two behaviour fixes in §5 change what happens
in cases that were previously broken or unreachable — a `hug` bottom band that
could not scroll, and a redirect that published a value the caller was undoing —
so neither moves a contract a caller could have depended on. The consumer repo
builds no `newTabView` and no `newPicker` under `src/` (tripwires read that off
the shipped source every run); both riders assert the new contract on the
framework this package requires.
