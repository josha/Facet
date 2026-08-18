# ADR-0037 — Composite controls live at `Facet.Controls.<Name>(core, spec)`

**Date:** 2026-08-17 · **Status:** Accepted · **Stage:** release-candidate review
(this is the later decision point the API-consistency stage deferred; it
authorizes a compatible migration, not a breaking cleanup)

## The problem, in plain words

Every built-in composite control is created like this today:

```luau
local tbl = Facet.newTable(Facet, core, { … })
```

The author writes `Facet` twice in every call. The first argument is the library
handing itself to its own control builder — boilerplate that teaches nothing and
that autocomplete cannot explain. Measured across the maintained tree: **317
call sites** in the framework's examples/tools/tests and **32** in Rascal Rally
repeat this shape, over **19 composite controls** (`newTable`, `newSlider`,
`newPicker`, `newProgressView`, …). A second cost is discoverability: those 19
control builders share the top level with 11 infrastructure constructors
(`newCore`, `newPresenter`, `newDragSession`, …), so completion on `Facet.`
mixes "things a screen author wants" with "things an integrator wires once".

## Decision

Add one namespace table:

```luau
local tbl = Facet.Controls.Table(core, spec)
```

- `Facet.Controls.<Name>` exists for exactly the composite controls whose
  current builder signature is `(library, core, spec)`: Table, Slider, Stepper,
  Picker, PopupButton, Menu, TabView, Label, Chip, Rating, TextInput,
  ProgressView, LevelPicker, DisclosureGroup, VirtualList, VirtualGrid,
  RowActions, Callout, AsyncImage. The namespace closes over the library, so
  the redundant first argument disappears.
- `Facet.UI.<Name> { … }` stays the blueprint-primitive vocabulary, unchanged.
- `Facet.new<X>` stays the vocabulary for infrastructure whose creation and
  ownership IS the important fact (`newCore`, `newEnvironment`, `newPresenter`,
  `newActionSystem`, `newFocusGraph`, `newDragRegistry`, `newDragSession`,
  `newDragVelocity`, `newResourceProvider`, `newAutoscroll`,
  `newRowActionsCoordinator`). These take no library argument today and do not
  move.
- We do NOT prefix items with the product name (`Facet.FacetTable` repeats the
  namespace) and we do NOT rename any stable identifier merely because another
  framework uses the same generic word.

## The alternative we tested and rejected

A consistent flat repair — keep the names, drop the self-argument:
`Facet.newTable(core, spec)`. Same authoring win, same migration count, but the
same symbol would then have two live arities during migration, and the only way
to keep old callers working is sniffing whether argument 1 is the library table.
Arity-sniffing on a public constructor is exactly the "accepted-but-ignored /
magic argument" defect class the API constitution bans, and autocomplete still
leaves 30 constructors mixed at the top level. The namespace form adds new
symbols instead of overloading old ones, so the old form stays intact, unwarped,
and mechanically detectable.

Representative-screen comparison (playlist-table example, the plan's own
worst case): the screen makes 7 composite calls; the namespace form removes 7
redundant `Facet` arguments and zero other edits; the flat form removes the same
7 but changes the meaning of 7 existing symbols. Autocomplete: `Facet.Controls.`
lists exactly the 19 controls; today's `Facet.` completion lists 44 mixed
entries. Types: `Controls` is one exported typed table; per-control spec types
are unchanged.

## Migration (compatible, this stage)

1. `Facet.Controls` lands with typed entries for the 19 controls.
2. Every old-form call keeps working identically. Each `new<Control>` gains a
   DEPRECATIONS-ledger entry: `since=0.10.0`, `removeNoEarlierThan=0.12.0`,
   `replacement=Facet.Controls.<Name>(core, spec)`. No runtime warning beyond
   the ledger, matching existing policy.
3. All maintained call sites (framework examples/tools/tests and Rascal Rally)
   move to the canonical form in the same change; the suite counts stay
   accounted.
4. A drift check refuses NEW old-form call sites in maintained code (pattern:
   `.new<UpperCamel>(Facet,` and the `:new<UpperCamel>(` colon spelling outside
   the deprecation-compatibility tests), with its own planted-violation
   selftest.
5. `VERSION` moves per the repository's own api-surface semver rules for a
   compatible addition, and the public-surface dump, guide, API reference, and
   scaffold emit the canonical shape.

## Consequences

A screen author discovers every composite in one completion list and never
writes the library's name twice; infrastructure keeps its ownership-signaling
`new` names; nothing published breaks; and the retirement of the old form is a
decision the DEPRECATIONS ledger can hold for a later stage — not this one.
