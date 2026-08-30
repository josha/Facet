# Retiring Wardrobe — the inventory, then the deletions

Binding scope: `docs/plans/example-games-and-standalones.md`, "Retire Wardrobe;
complete Sipworks and Glade":

> Wardrobe is no longer a player example. Remove it from the tutorial gallery, showcase
> picker, curated standalone manifest, public example catalog, screenshots, publishable
> places, and player-facing build. Do not select it as a replacement for another
> example. **First inventory the framework behaviors and tests it covers.** Preserve
> useful Facet coverage with smaller focused fixtures or another selected experience.
> If the old app is still required by the Step 11 reference-validation record, move it
> out of the public `examples/` surface into clearly owned test evidence and explain why
> it remains. Delete it when nothing still requires it. Do not let historical proof keep
> Wardrobe presented as a current example.

**Inventory first, deletions second.** That ordering is the plan's, and it is the whole
risk: Wardrobe is `p5_wardrobe`, a Roblox-style avatar editor, and it is the only
example driving several framework behaviours.

---

## 1. Where Wardrobe is reachable from today

It is **not** in the tutorial gallery and **not** in `demo_picker.DEMOS` — that part of
the plan's instruction is already satisfied. It is reachable through exactly three
doors:

| Door | Path |
|---|---|
| The showcase scenario | `examples/gallery/scenarios/ref_wardrobe.luau` (122 lines), named in `scenarios/init.luau`'s ordered `ORDER` list |
| A standalone place | `examples/places/Facet-Ref-Wardrobe.rbxl` (3.9 MB), built from `tools/build_reference_places.sh`'s `PROOFS` array |
| The suite | `tests/reference/wardrobe_spec.luau` (685 lines), registered in `tests/run.luau` |

The application itself is `examples/reference/p5_wardrobe/` — 4 files, 2,051 lines.

## 2. What holds a reference to it

Fifty-eight files mention it. Most are prose. These are the ones that are **load-bearing
code or gate state**:

| Holder | What it holds |
|---|---|
| `examples/gallery/scenarios/init.luau:77` | `"ref_wardrobe"` in the ordered scenario list |
| `tools/build_reference_places.sh:24` | `"ref_wardrobe\|Facet-Ref-Wardrobe"` in `PROOFS` |
| `tools/lune/triage_overflow_waivers.luau:144` | `p5_wardrobe` in a five-entry `PROOFS` array |
| `tests/overflow_sweep.spec.luau:481` | the same five-entry array, independently |
| `tests/lib/theme_sweep_ledger.luau` | nine waiver rows keyed `surface = "p5_wardrobe"` |
| `tests/lib/tiers.luau:125` | its timing-tier record |
| `tests/run.luau:727` | the spec registration |
| `tools/studio/device_sweep_matrix.json:126,129` | a `wardrobe-grids-phone` row |
| `tools/lune/check_example_drift.luau` | seven `metrics.wardrobe.*` exemptions and file entries |
| `tools/lune/gate_manifest.luau:93-96,174` | **five gate rows** in `reference-app-validation`: device-matrix rows, fixture axes, a place-existence assertion, and a suite grep requiring `examples/places/Facet-Ref-Wardrobe.rbxl` |

Three `src/` files mention it in **comments only** — provenance for a defect it found
(`render/transitions.luau:537`, `layout/solver.luau:1334`, `render/renderer.luau:3255`).
No framework code branches on it. Those comments stay: they record where a measurement
came from, and a measurement's provenance does not expire when its fixture does.

## 3. The Step 11 record does still require it

`reference-app-validation` is a **closed, earned gate** with five rows citing Wardrobe
by name, and `artifacts/swiftui-reference-app-validation/` holds its whole record
including `specs/p5-wardrobe.md`.

So the plan's conditional fires: **it moves rather than deletes.** Out of the public
`examples/` surface, into clearly owned test evidence, with the reason written down.

The alternative — deleting it and rewriting five rows of an earned gate — would erase
evidence to tidy a directory. `artifacts/` is never rewritten in this repository, and a
gate row that cannot be re-earned should not be quietly re-worded.

## 4. What it uniquely covers, and where that coverage goes

This is the half the plan puts first, and it is the half that decides whether the move
is safe. Each row is a framework behaviour Wardrobe is currently the only, or the
richest, example of:

| Behaviour | Why Wardrobe carries it | Where it goes |
|---|---|---|
| `UI.Stage` — a live `ViewportFrame` preview | The try-on avatar is the only `UI.Stage` consumer in the example tree | Must be preserved. Either the relocated fixture keeps proving it, or a small focused fixture takes it. **Decide by measurement, not by assumption** — check whether any other example or scenario mounts a Stage. |
| Undo/redo equip history | A real command-history surface | The relocated fixture |
| Category tabs filtering a grid | Also covered by the playlist table and the reference dashboards | Already redundant |
| Purchase confirm/reject | Also in Glade's commerce path and Sipworks' order path | Already redundant |
| Nine theme-sweep waiver rows | `theme_sweep_ledger.luau` rows keyed to its surfaces | Move with the fixture, or retire each row with its reason |
| A device-sweep matrix row (`wardrobe-grids-phone`) | One grid-density row on a phone | Check whether another proof's grid covers the same density; retire the row with its reason if so |

**Nothing is deleted before its row here says where the coverage went.** A behaviour
with no surviving owner means the fixture stays, not that the behaviour stops being
proved.

## 5. The move

`examples/reference/p5_wardrobe/` → out of `examples/`, into a location that reads as
test evidence rather than as a shipped example. `tests/fixtures/` is where shared test
data lives today, so `tests/fixtures/retired/p5_wardrobe/` is the natural home, with a
`README.md` beside it saying: what it is, which earned gate rows require it, that it is
**not** a current example, and the condition under which it may finally be deleted (when
no gate row cites it).

Then:

- `examples/gallery/scenarios/ref_wardrobe.luau` — deleted, and `"ref_wardrobe"` removed
  from `scenarios/init.luau`'s `ORDER`.
- `tools/build_reference_places.sh` — `PROOFS` drops to four.
- `examples/places/Facet-Ref-Wardrobe.rbxl` — deleted. It is a **publishable place**,
  which is exactly what the plan says must not still exist.
- The two five-entry `PROOFS` arrays (`triage_overflow_waivers.luau`,
  `overflow_sweep.spec.luau`) drop to four. Both are hand-maintained copies of the same
  list, which is the parallel-list problem this stage is also fixing — they should end
  up reading the manifest rather than being edited twice.
- `tests/run.luau` keeps its registration, pointed at the new location; `tests/lib/tiers.luau`
  keeps its timing row with the new name.
- The five `reference-app-validation` gate rows are **updated with a recorded reason**,
  not silently. Each says what it now asserts and why the change is a relocation rather
  than a weakening.

## 6. The negative controls

A retirement is easy to claim and easy to get wrong. Three things must be *proved*, not
asserted:

1. **Wardrobe is absent from every publishable build.** Build every place from the
   manifest and grep the outputs. A `.rbxl` that still contains it fails the row.
2. **No player-facing surface names it.** The showcase picker, the scenario list, the
   guide, and every place's own chrome.
3. **The relocated fixture still proves what it was kept for.** Its spec runs, from its
   new location, registered, and the gate rows citing it pass.

And the plan's own last sentence on this, which is the point of the whole exercise:
*do not let historical proof keep Wardrobe presented as a current example.* Moved and
labelled is fine. Left in `examples/` with a note is not.
