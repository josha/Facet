# Wardrobe: the coverage inventory, taken before anything was deleted

Stage `example-games-and-standalones`, rows WARD-1..WARD-3. Binding design:
`design/wardrobe-retirement.md`. Plan:
`docs/plans/example-games-and-standalones.md` §"Retire Wardrobe; complete
Sipworks and Glade".

The plan puts the inventory **first**, and that ordering is the whole risk: the
design named `UI.Stage` as the behaviour Wardrobe might be the only example of,
and a fixture that is the only example of a shipped capability cannot simply
evaporate. So every candidate below was **measured**, not assumed, and nothing
was deleted before its row said where the coverage went.

Subject: `examples/reference/p5_wardrobe/` — 4 files, 2,051 lines, a clean-room
Roblox-style avatar editor (RA-P5).

---

## The headline: the design's lead candidate was refuted

**`UI.Stage` is not unique to Wardrobe, and it is not even richest there.**

Measured by grepping the whole example, scenario, bench and test tree for
`Stage` (excluding the Wardrobe files themselves):

| Owner | What it holds |
|---|---|
| `tests/stage.spec.luau` | the dedicated framework spec — **22 cases** across five labelled axes: strict authoring, mount/dump/dispose, the four `ViewportFrame` authority properties, layout (a Stage measures 0x0 with no dims), and the refusals |
| `examples/reference/p2_cartwheel/screens/plaza.luau:178` | a **live consumer**: `UI.Stage({ id = "Stage", … })` inside the Plaza hero, with an orbiting camera and a declared fallback plate |
| `tests/reference/cartwheel_spec.luau:940-1015` | the consumer's proof — `describe("Cartwheel — the Plaza stage and its fallback")` |

Cartwheel's Stage cases assert the same five things Wardrobe's pane asserted:

| Wardrobe's Stage claim (`wardrobe_spec`) | Cartwheel's equivalent (`cartwheel_spec`) |
|---|---|
| the stage host is live headlessly; lighting + camera recorded | `declares its stage content against the Stage node's own path`; `dump().stage == "present"`, host non-nil |
| an orbit step drives a new camera write through the public host | `the proof drives the orbit through the PUBLIC handle` — asserts `setCamera` **and** that `position.x` actually changed ("an orbit that never re-aims is a still") |
| reduced motion stops the turntable | the same case's second half: with `reducedMotion`, `#parked.calls` does not grow after 8s |
| the fallback closes when there is no host | `PAINTS THE DECLARED FALLBACK PLATE when stageHost answers nil` |
| the Stage node exists in the tree | `adapter.node(built.paths.stage) ~= nil`, plus the first-frame case |

**Verdict: no coverage moves.** `UI.Stage` keeps a dedicated 22-case framework
spec and a live, proved consumer that is a current example. The design's
instruction to "decide by measurement, not by assumption" is what turned this
row from "must be preserved somewhere" into "already preserved twice."

---

## The inventory table

`Only?` answers: **is Wardrobe the only example of this?**

| # | Behaviour | Only? | Where the coverage goes |
|---|---|---|---|
| 1 | **`UI.Stage`** — an engine-content `ViewportFrame` leaf, its host seam, camera/lighting writes, and the fallback plate | **No** | Stays where it already was: `tests/stage.spec.luau` (22 cases) + `examples/reference/p2_cartwheel` proved by `tests/reference/cartwheel_spec.luau`. See the table above. |
| 2 | **Stage orbit + reduced-motion parking** | **No** | `cartwheel_spec.luau` — *"the proof drives the orbit through the PUBLIC handle, and parks it when motion is reduced"*, which asserts a genuine camera move and then a frozen call count. Wardrobe's two equivalent cases (`an orbit step drives a new camera write`, `REDUCED MOTION STOPS THE TURNTABLE`) survive as well, from the relocated fixture. |
| 3 | **Undo/redo equip history, disabling at both stack ends** | **YES — no other owner** | **The relocated fixture.** `tests/reference/wardrobe_spec.luau` — *"undo/redo walk the equip history and disable at the stack ends"*. `p2_cartwheel/services/commands.luau` is the nearest thing in the tree and it is a *different* mechanism: an optimistic `idle → pending → confirmed \| rejected` command with `apply`/`revert`, not a user-visible history stack with disabled ends. **This row is one of the two reasons the fixture moved instead of being deleted.** |
| 4 | **Category tabs filtering a grid** | No | `examples/reference/p4_foyer` — *"the charts tab swaps the feed to the approval-ranked section and back"*, *"search filters by title and creator; clearing restores the feed"*, plus the honest stub tab. Lane-reflow over a large collection is additionally in the `virtual_grid` scenario. |
| 5 | **Purchase confirm / reject with visible reasons** | No | Three surviving owners: `p1_glade` (*"idle → pending → confirmed"*, *"the second attempt is the scripted `declined` rejection, with its copy under the card"*, *"every declared rejection reason has player-facing copy"*), `p3_sipworks` §8 (*"the CTA runs idle -> pending -> rejected, shows a toast, and returns to idle"*), and `p2_cartwheel`'s command lifecycle. |
| 6 | **The split ⇄ stacked `Composition` flip with state survival** | No | The Composition family is proved by `tests/composition.spec.luau` and by Foyer's adaptive navigation. Wardrobe's own case survives from the relocated fixture. |
| 7 | **Nine `theme_sweep_ledger` waiver rows** (measured: **four**, not nine) | n/a — findings, not coverage | **Deleted, with the reason recorded** in `tests/lib/theme_sweep_ledger.luau`'s header. Three were `theme-inset-yield` on 44px icon discs — a class `p4_foyer`'s top bar still carries in that file, so the class stayed recorded. One was a `layer-overlap` on the preview Controls. They had to go in the same change: `p5_wardrobe` left `tests/overflow_sweep.spec.luau`'s `PROOFS`, and that spec's *"every ledger row still fires — a stale waiver is a fixed defect, delete the line"* case would otherwise have gone red. The design said nine; the file said four. |
| 8 | **The `wardrobe-grids-phone` device-sweep row** | n/a — a plan, not a proof | **Retired into `tools/studio/device_sweep_matrix.json`'s new `retiredCells`, with the reason.** Measured: it sat in `plannedCells` with `"status": "not reached this round"` — it was **never driven**, so it held no evidence. Its claim (grid cards not cramped at a phone width) is pinned headlessly and still runs, in the spec's `Picked-for-you cards fill their lane` block: the catalog column claims the whole phone viewport, every card is the same width, the row tiles the grid exactly, and the thumbnail never paints past its own Col at the floor lane. The remaining live phone-grid cell is `glade-corner-rings-phone`. |
| 9 | **Overflow / theme-axis sweep over the Wardrobe surface** | n/a | **Dropped deliberately.** A sweep asserts a *shipped surface* is clean; a retired surface has nobody to be clean for. The sweep's framework-level claims are unaffected — its corpus is 44 surfaces and the axis's own mutation control is a synthetic case, not a proof app. |
| 10 | **Five `check_example_drift` `ALLOWLIST` exemptions** | No | **Deleted, with the reason recorded at the deletion site.** The retired tree is neither `SCANNED_DIR` nor `REFERENCE_DIR`, so those five entries could never fire again, and an allowlist entry that cannot fire is a claim nobody checks. Each *ruling* they carried is still stated on a line the lint reads: the two `minMax` panel-structure rows and the 3px selection underline duplicate `p4_foyer`'s; the two stage-light rows duplicate `p2_cartwheel`'s. |
| 11 | **`tests/lib/tiers.luau` timing row (`reference/wardrobe_spec`, 497 ms)** | n/a | **Unchanged, deliberately.** The spec keeps its name, its path and its cost; only the module it requires moved. Editing it would be churn. |
| 12 | **`tests/icon_ns_glyph.spec.luau`'s `iconGlyph("wardrobe:undo")`** | n/a — not a Wardrobe reference | **Unchanged.** The case proves the namespaced-icon ASCII floor derives `U` from the first letter after the namespace; the string is an arbitrary example and the case passes with any namespace. No shipped `wardrobe:` icon namespace exists. |

**Rows with no surviving owner: exactly one (#3).** That, plus the earned gate
rows below, is why the plan's conditional fired and the fixture **moved**
instead of being deleted.

---

## What still requires it

`reference-app-validation` is a closed, earned gate. These rows cite Wardrobe:

| Gate / row | Cites it as | Can it be re-earned without the app? |
|---|---|---|
| `reference-app-validation` / `responsibility-ledger` | a tree the forbidden-API grep walks | No — the grep must scan every proof source |
| `reference-app-validation` / `proof-avatar-editor-loop` | seven `wardrobe_spec` case names | No — the spec must mount the app |
| `reference-app-validation` / `device-matrix` | `wardrobe` in a Studio-driven artifact | No — the artifact is a live device record, never re-cuttable in CI |
| `reference-app-validation` / `fixture-axes` | `wardrobe` in the same artifact tree | No — same reason |
| `swiftui-parity-round3` / `reference-apps-reproved` | two worn-chips flow-wrap case names | No — only this app's pane produces them |

New home: `tests/fixtures/retired/p5_wardrobe/`, with
`tests/fixtures/retired/README.md` stating what it is, which earned rows require
it, that it is not a current example, and the deletion condition (no gate row
cites it).
