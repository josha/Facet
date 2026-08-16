# O-30 — the two capabilities no picker entry reached, and the bind the host forgot

**2026-08-15.** Two defects in `examples/gallery/`, worked together because they
share one file: the showcase host (`examples/gallery/client/init.client.luau`).

- **O-30** — `newAsyncImage` and `canvasGroup` were exercised everywhere and
  **selectable nowhere**. Now `async-images` and `canvas-group` are in
  `demo_picker.DEMOS` and in `scenarios/init.luau`'s `ORDER`, and swept.
- **The grid never bound the native scroll** — the fixture branch of `mountDemo`
  never wired `bindNativeScroll`, so five picker demos windowed the wrong rows.
  Fixed in the host; the API question it raises is booked as **O-31**.

Everything below is a transcript of something run for this file. The live halves
were driven in Studio (LuauUI-Showcase.rbxl, Rojo-connected, port 34873) on
2026-08-15; the headless halves in the isolated worktree described at the end.

---

## Part 1 — the O-30 claim, verified before it was acted on

The ledger's claim was **true on both halves**, and the census that checked it is
worth keeping because it also produced the second defect.

`newAsyncImage` callers: `scenarios/async_images.luau`,
`scenarios/sponsor_avatars.luau`, `examples/performance/lab/rows.luau`,
`examples/reference/p4_foyer`, `examples/reference/p5_wardrobe`
(`with_animation.luau` mentions it in a comment only — the ledger's "five
reference/sponsor surfaces" is generous but the conclusion holds).
`canvasGroup` callers: six `sponsor_*` fixtures, `p1_glade`, `p2_cartwheel`,
`p3_sipworks`, `p4_foyer`, `p5_wardrobe`, and `src/controls/progress_view.luau`
— which declares **no** group and says so at `:71-81`.

Against `demo_picker.DEMOS` as it stood: **no entry reached either.** Every
`sponsor_*` fixture and every `ref_*` proof is in `ORDER` and in the sweep and in
neither the picker nor any route a player has. So the ledger was right, and this
is the third time the same rule has been paid (`lifecycle-hidden`, O-15, was the
second).

## Part 2 — what shipped for O-30

**`async-images` (existing fixture, newly reachable).** It needed two things it
had never needed while only a sweep mounted it:

1. `ctx.bindResourceTransport` in the host's MINIMAL ctx. `async_images` calls
   that seam at **build**, not in a step, so without it the demo took the pcall
   in `show()` and warned. The host now hands it the real
   `client.roblox_resources` transport, exactly as `scenarios/runner.luau` does.
2. A page that scrolls. It carried a `page-not-scrollable` waiver (25px at
   640x320) and a themed ledger row (143px, every package) — acceptable while
   nothing but a sweep ever mounted it, and not acceptable for a surface a player
   can select. **Both records are deleted rather than re-recorded**, which is
   what the sweep's own stale-waiver case is for.

**`canvas-group` (new fixture).** `canvasGroup`/`opacity` had no surface whose
SUBJECT it was, so one was written: the same three concentric plates in two
panels, given the same opacity value, faded as ONE group on the left and one
plate at a time on the right. It is the one demonstration in this catalogue a
still screenshot can hold. Beside it: a `UI.When{ transition = { enter = "fade" }}`
over a `canvasGroup = true` node that writes no opacity of its own (a fading form
needs the arriving node to already BE a group), and the framework's refusal
sentence for `UI.Text{ opacity = … }` **captured at build from a real refused
construction** rather than quoted, so the panel cannot show a stale message.

### Live, in the showcase place (Studio, Play, 2026-08-15)

Both demos were reached the way a player reaches them — through the picker's own
`showNext`, which is the shipped selection path — and then read off the engine.

```
-- async-images, after selecting it from the picker
{"status":["1:ready 2:ready 3:failed"],
 "current":"async-images","screenPresent":true,
 "images":[{"image":"rbxthumb://type=AvatarHeadShot&id=1&w=48&h=48","loaded":true,"size":"48, 48"},
           {"image":"rbxthumb://type=AvatarHeadShot&id=156&w=48&h=48","loaded":true,"size":"48, 48"},
           {"image":"","loaded":false,"size":"48, 48"}]}
```

Two thumbnails resolved through the REAL `ContentProvider:PreloadAsync`
transport and the invalid asset failed — which is the whole fixture, and which
also proves the new host seam: without it the build throws before any of this.

```
-- canvas-group, after selecting it from the picker
{"current":"canvas-group","screenPresent":true,
 "canvasGroups":[{"name":"OneGroup",  "t":0.6,"size":"657, 132"},
                 {"name":"BackGroup", "t":0.6,"size":"132, 132"},
                 {"name":"MidGroup",  "t":0.6,"size":"92, 92"},
                 {"name":"FrontGroup","t":0.6,"size":"52, 52"}]}
-- and the plates themselves, concentric and opaque, two panels of three:
Back  132x132 at 282,233  rgb(0.17,0.38,0.82)   Back  132x132 at 282,431
Mid    92x92  at 302,253  rgb(0.69,0.16,0.16)   Mid    92x92  at 302,451
Front  52x52  at 322,273  rgb(0.93,0.94,0.96)   Front  52x52  at 322,471
```

FOUR real engine `CanvasGroup` instances: one over the whole left stack and one
per plate on the right, every one at `GroupTransparency = 0.6` for the opening
opacity of 0.4. That is the capability on the real engine, from the picker.

## Part 3 — the grid that never followed its own scroll

### The defect, reproduced by hand before it was fixed

A virtualized collection cannot reach the render controller at build, so the
CONSUMER wires the mirror after `present`. The tutorial branch of `mountDemo` did
that. The single-example path did. **The fixture branch did not**, and
`scenarios/virtual_grid.luau:318-321` publishes its control in as many words
"for the showcase host's native-scroll auto-bind" — against a loop that did not
exist for fixtures.

A/B in ONE Studio session, same instrument, with the loop commented out and then
restored. Freshness was gated on a token that exists in exactly one of the two
drafts plus `#Source`, per `docs/lessons/a-freshness-marker-must-discriminate.md`:

```
A (bind commented out)   Client Gallery: bytes=42759  hasABMarker=true   liveLoops=1
   window before scroll: c1 … c16
   CanvasPosition.Y := 2000
   window after  scroll: c1 … c16        moved = FALSE

B (bind restored)        Client Gallery: bytes=42662  hasABMarker=false  liveLoops=2
   window before scroll: c1 … c16
   CanvasPosition.Y := 2000
   window after  scroll: c69 … c92       moved = TRUE
```

The window is read from the engine instances themselves — the `[cN]` keys in the
mounted node names under `PlayerGui.LuauUI_VirtualGrid./VirtualGrid/GridPane/Cells`
— so nothing in the measurement goes through the framework's own bookkeeping.

### Demo bug, or API bug? The census that decided it

Every caller of a virtualized collection outside the tests:

| Caller | Binds? | Reachable from the picker? |
|---|---|---|
| `card_rail`, `row_actions`, `sponsor_list`, `sponsor_drop` | yes — itself, from `presenter.onTick` | yes (the first two) |
| `virtual_grid`, `virtual_hgrid`, `variable_extents`, `measured_extents`, `virtual_list_native` | only from `steps.bind`, which **only the scenario runner calls** | yes (four of them) |
| `table_virtualized` | **nowhere at all** | yes |
| `perf_capture` | nowhere at all | no |
| `examples/performance/lab/*` | yes (pcall-guarded) | n/a |
| Rascal Rally `LuauUISponsor/init.luau:2562` | yes | production |

**Five picker demos were dead on this path, not one.** The verdict is therefore
BOTH, and the two halves are booked separately:

- **It is a demo bug, and that half is fixed here.** The fixture branch is the
  third capability the host's own test rigs had and it did not (`present` opts,
  C2 2026-08-12; the `foreign` seam, ADR-0034; now the scroll mirror). The loop
  the tutorial branch already ran is now in the fixture branch, and it fixes all
  five demos at once because every one of them publishes its control.
- **It is also an API footgun, and that half is O-31.** Nine independent authors
  wrote a virtualized collection; five omitted the bind, and the failure mode is
  silent — the control renders, it just renders the wrong rows. The framework's
  standing pattern is that a refusal is legible at construction and names the
  alternative (`REFUSED_FADE` in `blueprint_schema.luau` is the model). This one
  refuses nothing and says nothing.
  **It is not fixed here, deliberately.** The seam that could fix it properly is
  `buildFocusGroups(rootNode)` — the presenter's contribution callback, which is
  already the one place a control learns its own mounted path
  (`src/controls/virtual_grid.luau:895-901`). Delivering the controller through
  that same call would make the bind unnecessary rather than merely loud. That
  lives in `src/present/focus_map.luau` and `src/present/presenter.luau`, which
  belonged to another agent this session, and it is a framework change with a
  Rascal Rally consumer obligation attached. Booked, with the census above.

## Part 4 — mutation evidence

Every check added here was broken on purpose and the named case watched to
redden. Run in the isolated worktree, one mutation at a time, each on a tree
restored to HEAD first (the first battery leaked M3 into M4-M6 and produced a
phantom red; the harness now restores every mutable path and refuses to report a
run whose sync failed — a measurement whose instrument moved is not a
measurement).

| Mutation | Named case that reddened |
|---|---|
| M1 the host drops the fixture-branch bind | *the shipped host runs the auto-bind loop in every demo branch* |
| M2 the host drops the resource-transport seam | *the shipped host's minimal ctx carries the seam a catalogue fixture calls at build* |
| M3 `virtual_grid` stops publishing its control | *the lazy grid's window follows an engine scroll — the live defect, headless* |
| M4 the fade is declared on the right STACK, not per plate | *the left panel is ONE engine CanvasGroup and the right panel is three* |
| M5 the refusal is quoted instead of captured | *the refusal on screen is the framework's own sentence, captured at build* |
| M6 `async_images`' page stops scrolling | *scenario 'async_images': the solver reports NOTHING at any swept viewport, at any text size* |

M1 is the honest one to read carefully: the behavioural cases transcribe the
host loop (a LocalScript cannot be required headlessly), so the mutation they
catch is a FIXTURE or CONTROL regression, and the SOURCE audit is what catches
the host. That is the same division the `present`-opts section above it uses,
and it is why both halves exist.

## Part 5 — suites

The shared working tree was not a usable signal: two other agents were mid-edit
in `src/render/`, `src/present/` and this same catalogue, and a run there showed
14 failures that had nothing to do with this work. So every number below comes
from a pristine `git worktree` at HEAD with **exactly the hunks this commit
carries** applied to it — built from `tools/commit_isolated.py --dry-run`'s own
patch, so the tree under test and the commit cannot disagree.

```
HEAD (8d7ce87), untouched                     5530 passed, 0 failed
HEAD + this work                              5539 passed, 0 failed
```

Nine new cases: four on the native-scroll bind, four on the fade group, and one
sweep surface (`canvas_group` at 8 viewports x 4 preferences x 8 packages).

Rascal Rally: see the commit message for the count; the LuauUI change here is
`examples/` only — no `src/` file was touched, so the consumer contract is
unchanged and the game's suite is the regression signal rather than the subject.
