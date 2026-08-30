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

## `p5_wardrobe/` — reference proof "Wardrobe" (RA-P5)

A clean-room, Roblox-style avatar editor: category tabs over an item grid, a
`UI.Stage` try-on preview with an orbiting camera, try-on with an undo/redo
equip history, a Sparks wallet, and a purchase-shaped lifecycle with scripted
rejections. 4 files, ~2,060 lines.

**Retired as a player example on 2026-08-30**, per
`docs/plans/example-games-and-standalones.md` §"Retire Wardrobe; complete
Sipworks and Glade" and the binding design at
`artifacts/example-games-and-standalones/design/wardrobe-retirement.md`. The
coverage inventory that had to run *before* anything was deleted is at
`artifacts/example-games-and-standalones/wardrobe-inventory.md`; it is the
document that says, behaviour by behaviour, where each proof now lives.

### What was removed when it was retired

| Removed | Was |
|---|---|
| `examples/gallery/scenarios/ref_wardrobe.luau` | the showcase scenario (deleted) |
| `"ref_wardrobe"` in `examples/gallery/scenarios/init.luau` `ORDER` | the scenario registration (deleted) |
| `examples/places/Facet-Ref-Wardrobe.rbxl` | a publishable place (deleted) |
| `"ref_wardrobe\|Facet-Ref-Wardrobe"` in `tools/build_reference_places.sh` | the place-builder entry — `PROOFS` is now four (deleted) |
| `"p5_wardrobe"` in the two `PROOFS` arrays (`tests/overflow_sweep.spec.luau`, `tools/lune/triage_overflow_waivers.luau`) | the overflow/theme sweep corpus entry — both are now four (deleted) |
| four `surface = "p5_wardrobe"` rows in `tests/lib/theme_sweep_ledger.luau` | themed-sweep findings on a surface no longer swept (deleted, reason recorded in that file's header) |
| the `wardrobe-grids-phone` cell in `tools/studio/device_sweep_matrix.json` | a **planned, never-driven** device-sweep cell (retired into that file's `retiredCells`, with the reason) |
| five `examples/reference/p5_wardrobe/init.luau` rows in `tools/lune/check_example_drift.luau`'s `ALLOWLIST` | drift-lint exemptions for a tree that is no longer scanned (deleted) |

### Why it is still here

`reference-app-validation` is a **closed, earned** gate. Five of its rows cite
Wardrobe by name or by tree, and none of them can be re-earned without the
application:

| Gate row | What it needs from this fixture |
|---|---|
| `reference-app-validation` / `responsibility-ledger` | the forbidden-API grep (`Instance.new`, `GetService(`, `UserInputService`, wall clock, `math.random`) over every proof source — this fixture is now scanned at its new path |
| `reference-app-validation` / `proof-avatar-editor-loop` | seven suite greps for `wardrobe_spec` case names — the spec mounts this module |
| `reference-app-validation` / `device-matrix` | the five-view + keyboard Studio matrix recorded for `wardrobe` in `artifacts/swiftui-reference-app-validation/studio/` |
| `reference-app-validation` / `fixture-axes` | the theme/text/motion/locale axes recorded for `wardrobe` in the same artifact tree |
| the layout-parity round-3 stage / `reference-apps-reproved` | two suite greps for the worn-chips flow-wrap cases, which only this app's pane produces. The stage id is whatever `tools/lune/gate_manifest.luau` registers for that row — read it there rather than from this table |

`tests/reference/wardrobe_spec.luau` (22 cases) still runs on every suite pass,
registered in `tests/run.luau`, and now requires
`../fixtures/retired/p5_wardrobe`. Drive it alone with:

```
lune run tests/run_ref wardrobe
```

### When it may be deleted

When no row of `tools/lune/gate_manifest.luau` cites Wardrobe — by fixture path,
by suite-grep case name, or by artifact key. At that point delete
`tests/fixtures/retired/p5_wardrobe/`, `tests/reference/wardrobe_spec.luau`, its
registration in `tests/run.luau`, its row in `tests/lib/tiers.luau`, and this
section. The `artifacts/swiftui-reference-app-validation/` record is **never**
rewritten: it is what the gate was earned against.
