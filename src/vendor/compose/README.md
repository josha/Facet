# Compose source pin

Source: https://github.com/voidmeld/compose at
`cce9b99590fd3bec3bb9cb60f378184e28fab71d`, `src/core` (MIT).

Facet uses native cells, formulas, direct watches, effects, batching and owners.
It imports the pinned graph internals for explicit readable disposal. Facet
keeps its renderer settling and structural transitions/error boundaries.

`UPSTREAM.patch` records two lifetime fixes: the final static listener must let
Graph.release mark its sink released; reads after consumer disposal must not
attach new edges. It also adds the license ModuleScript for model distribution.
`tests/compose_lifetime.spec.luau` checks both failures and runaway re-registration.
The native million-watch cap abandons stale watches; dispose/re-register them
(or remount their owner) to resume. Native scheduling is dependency FIFO, not a
Facet-wide creation-order sort. Failed evaluations can retain partial dependency
changes; they do not restore an earlier successful dependency set.

`UPSTREAM.lock` pins every distributed source and metadata file by SHA-256.
