# Tab traverses in document order, and the focus chain is inspectable

**Status:** Planned after roadmap Step 8 (`desktop-keyboard-navigation`), from a
director playtest of the shipped stage.
**Handoff:** [`docs/handoff/2026-08-03-traversal-document-order.md`](../handoff/2026-08-03-traversal-document-order.md)

## Purpose

Step 8 gave Facet Tab and Shift+Tab over the existing focus graph. It inherited one
thing it should not have: a focusable `UI.Grip` is deferred to the **end** of the
focus order, so a Slider between a button row and a list traverses *after* the whole
list. Tab means document order, on every platform that has ever had a Tab key.

The deferral itself is correct — for the **arrows**. Arrowing down a table should land
on rows, not on column-resize handles. This stage separates the two readings without
creating a second focus map, and gives an author the two things missing around it: a
way to *see* the resolved chain, and a way to *move one control* in it.

## Interaction contract

### Traversal follows document order

- Tab and Shift+Tab visit focusables in the order they are **mounted**, with Grips in
  their natural position.
- Directional Navigate keeps today's behavior **exactly**, including the Grip
  deferral, which exists for it.
- The two readings walk the same **set**. Everything the arrows skip — hidden,
  disabled, non-focusable, retiring, losing adaptive candidates, live focus-skip
  predicates — Tab still skips, through the same predicates.
- Every focusable Grip traverses in document position. There is no
  value-control-versus-resize-handle distinction (decision TDN-1).

### One focus map, read two ways

Constitution §9 forbids a second order "derived from Instances or maintained
alongside". This stage does not add one. The presenter supplies a **rank** —
`FocusScope.traversalRank : { [path]: number }` — and `graph.traverse` sorts the
members it already reads from `allIds(scope)` by that rank. Membership and eligibility
have exactly one source. A scope with no rank map traverses as it did before.

Every place the presenter writes an order into the graph must supply the matching
rank, and the rank must come from the **same call** that produced the order, so the
two cannot drift.

### Query

`handle.focusOrder()` returns a frozen, deterministic dump carrying
`schema = "facet-focus-order/1"`: the resolved traversal order with each entry's
priority and live eligibility, **and** the navigation groups. Reporting both readings
side by side is the point — a debugger has to be able to see that they differ, and
that they cover the same set. Safe to call after dispose.

### Customize

`traversalPriority` is a sort **tier**, not an absolute index: the key is
`(priority, document position)`, default `0`. Negative pulls a control forward,
positive pushes it back, and within a tier document order always wins. This is the
`tabindex` model an author already knows, and it moves one control without
redeclaring the map.

Construction-only (decision TDN-3). A traversal **exclusion** is not added: it is
already expressible as `focusable = false`.

## Public API rule

Two public items, both justified by real author intent named in the Step 8 plan
("a traversal exclusion or explicit order that the current graph cannot express").
Follow the API constitution: strict refusal at the boundary, `did-you-mean` where
possible, and a result object that matches the shipped `dump()` convention.

## Verification

Pure tests for: a Grip-bearing control **between** ordinary controls traversing
correctly (every Step 8 fixture put value controls alone or last, which is precisely
why this shipped); a companion proving the arrows still defer; priority tiers and
same-tier stability; a consumer-supplied `navigationGroups` keeping its declared order
verbatim; refusals; the dump's determinism, contents, and post-dispose safety;
structural churn; modal and transient scopes.

Studio: scenario `keyboard_navigation` already mounts the exact shape (field → button
row → slider → stepper → 12-row list). Drive it with `tools/studio/device_matrix.luau`
mode `keyboard` and compare the focus log against document order, and against a live
`handle.focusOrder()` dump.

**Then put a person in front of it.** The stage this one fixes passed its gate and
three fresh-context reviews; the director found the defect in a ten-minute playtest,
because the instruments measured the order they were told to expect.

## Gate

Register `traversal-document-order`. It passes only when Tab follows document order
through the real adapter, the arrows are provably unchanged, the two readings share
one set, both public items are documented and refuse correctly, the full suite and
affected gates are green, the RascalRally consumer is audited and green, and the
inherited Step 8 debt is cleared.
