# `src/core/` — the reactive core, and the two arms that lost

`custom.luau` is **candidate A**: the reactive core Facet ships. `Facet.newCore`
returns it, every module in `src/` above this directory depends only on
`contract.luau`'s shape, and it is the only one of the three that is on any
supported path.

`fusion_adapter.luau` (over `vendor/Fusion/`, **candidate B**) and
`imperative.luau` (**candidate C**) are the other two arms of the ADR-0002
foundation bake-off. **They do not ship and they are not dead code.**

## Why they are kept (RC review disposition, 2026-08-18)

ADR-0002 chose A over B and C on measured numbers. A decision whose losing arms
have been deleted cannot be re-run — not against a newer Fusion, not on a new
device, not when someone reasonably asks how much the choice actually bought.
`bench/` drives all three through `contract.luau`, which is the interface that
makes the comparison apples-to-apples, and that is the entire job these two
files do. Deleting them would convert a measured decision into an assertion, and
the cost of keeping them is two files nothing requires.

## They are not entry points, and the boundary checker enforces it

`tools/lune/check_boundary.luau`'s consumer scan refuses a require of anything
under `src/core/` (or `vendor/`) from a game or an example — the blessed surface
is the `Facet` table plus the twelve client entry points in
`docs/reference/api.md` §Client entry points. Nothing in `src/` outside this
directory mentions Fusion.

If either arm ever stops building, the fix is to repair it or to retire ADR-0002's
benchmark deliberately in an ADR — not to quietly delete the arm, which removes
the evidence and leaves the conclusion.
