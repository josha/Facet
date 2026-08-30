# `src/core/` — the reactive core Facet ships

`custom.luau` is the reactive core Facet ships, and the only core in this
directory. `Facet.newCore` returns it, every module in `src/` above this
directory depends only on `contract.luau`'s shape, and it has no dependencies of
its own.

Facet's reactive core is its own. It is not built on, wrapped around, or derived
from another framework, and nothing under `src/` requires anything outside
`src/`.

## The losing arms of the ADR-0002 bake-off are not here

ADR-0002 chose this core over two other arms on measured numbers. Neither arm is
in the product tree:

- the retained imperative baseline lives at **`bench/cores/imperative.luau`**. It
  is a development fixture — `tests/conformance/cli`, `bench/scenarios.luau` and
  one case in `tests/table.spec.luau` run against it, because a second
  conforming implementation is what keeps `contract.luau` an interface rather
  than a description of one implementation. It sits under `bench/` because
  `tools/build_model.sh` maps `src/` and nothing else, so the distributed
  Package contains runtime only;
- the third arm and its vendored third-party sources were removed from this
  repository on 2026-08-30 and archived privately, with checksums, alongside the
  benchmark and conformance JSON that decided the rubric. ADR-0002 records the
  decision and points at the archive.

## This directory is not an entry point, and the boundary checker enforces it

`tools/lune/check_boundary.luau`'s consumer scan refuses a require of anything
under `src/core/` from a game or an example — the blessed surface is the `Facet`
table plus the client entry points listed in `docs/reference/api.md` §Client
entry points. The same checker refuses any require that leaves `src/`, and
`tools/check_no_fusion.py` refuses the removed material by name in the sources,
in the built model, and in the consuming game.
