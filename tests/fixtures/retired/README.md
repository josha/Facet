# Retired example apps, kept as test evidence

Everything under this directory is a retired application. It is not a current example — plainly, because the whole point of the move is that
nothing here may be presented as one any more. It is not reachable from any
player-facing surface and it is not built into any publishable place. It lives under `tests/` — not under
`examples/` — because an earned gate row still cites it, and deleting a fixture
an earned gate depends on would erase evidence in order to tidy a directory.

**The standing rule.** A directory here is deleted the moment no gate row in
`tools/lune/gate_manifest.luau` cites it any more. Until then it stays, with the
citing rows named below. Historical proof does not entitle anything here to be
presented as a current example: nothing under this directory may be added back
to `examples/gallery/scenarios/init.luau`'s `ORDER`, to
`examples/gallery/client/demo_picker.luau`'s `DEMOS`, to
`tools/build_reference_places.sh`'s `PROOFS`, or to any Rojo project's
`ReplicatedStorage` mapping.

---

## `p5_wardrobe/` — deleted 2026-09-20

The Wardrobe reference proof (retired as a player example on 2026-08-30, per
`docs/plans/example-games-and-standalones.md` §"Retire Wardrobe; complete
Sipworks and Glade") was fully deleted along with its test evidence:
`tests/fixtures/retired/p5_wardrobe/`, `tests/reference/wardrobe_spec.luau`,
its registration in `tests/run.luau`, its row in `tests/lib/tiers.luau`, and
every citation of its case names in `tools/lune/verify/graph.json` and
`tools/lune/verify/repair_graph.py`. It was written end to end against the
removed legacy authoring surface (`Facet.UI`, `Facet.Controls.X(core, spec)`,
`Facet.newCore`/`Facet.newPresenter`) and was not portable to the native
Compose runtime. The `artifacts/swiftui-reference-app-validation/` and
`artifacts/example-games-and-standalones/wardrobe-inventory.md` records are
left as-is: historical evidence of what the gate was once earned against, not
rewritten.
