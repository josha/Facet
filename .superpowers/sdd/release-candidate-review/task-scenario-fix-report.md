# The §5 scenario surface booted a silent no-op (INT-2)

## Symptom, as reported

`workspace.Facet_Scenario = "table_virtualized"` (or `"examples"`) set in Edit,
then Play, in the showcase place: no `workspace.FacetScenarioAPI`, no error, no
warning — just the ordinary `[Facet Showcase]` boot line. The same flow was
recorded working on 2026-08-17
(`artifacts/release-candidate-review/rename/studio-canary.md`).

## Root cause

**Not a scenario-host defect. A boot-order one — and none of the four suspected
waves introduced it.** `examples/gallery/client/init.client.luau` read
`Facet_Showcase`, mounted the showcase, and `return`ed **30,668 characters
above** where it would have read `Facet_Scenario`:

Character offsets below are measured in the bootstrap **as loaded in the open
Studio place** (48,846 chars total):

| Selector | Read at char | Reached in the showcase place |
|---|---|---|
| `Facet_Showcase` | 10,684 | yes — and returns |
| `Facet_Scenario` | 41,352 | **never** |
| `Facet_Example` | 43,161 | **never** |

`tools/build_places.sh` bakes `Facet_Showcase = true` into the showcase place's
Workspace, so in the one place a device pass opens, both §5 selectors below that
branch were unreachable. The ordering is unchanged since the initial commit
`6a4b59c` (2026-08-02) — verified by reading the file at `6a4b59c`, `664d974`,
`a97336f` and `HEAD`, where the three branches sit at the same relative
positions throughout.

### Why it looked like a regression

The rename wave (**`44b9e62`**, ADR-0036, `LuauUI_*` → `Facet_*`) renamed the
gate attribute. Between that commit and the place rebuild, the open showcase
place still carried the OLD `LuauUI_Showcase` attribute while the injected
sources read `Facet_Showcase` — so the branch did not match, the place fell
through to the gallery path, and the scenario mounted. The canary artifact
records exactly that: its boot line is `[Facet Gallery] running 0.9.0`, not a
showcase line, and it states it verified injected sources rather than the
rebuilt `.rbxl`. Rebuilding the place under the new name closed that accidental
escape hatch and exposed the latent defect.

The workaround had been tribal knowledge rather than a fix —
`docs/plans/device-bug-round-2026-08-12.md:441` reads "set `Facet_Showcase =
false` and `Facet_Scenario = "keyboard_navigation"` in Edit, then Play".

### Reproduction (read-only, on the live artifact)

Measured in the open Edit session of `Facet-Showcase.rbxl` without modifying it:

```
showcaseAttr      = true
scenarioAttr      = "table_virtualized"     <- the user's setting, still there
showcaseReadAtChar= 10684
scenarioReadAtChar= 41352
showcaseReadsFirst= true
hasBootMode       = false
build             = 5da7cba+dirty 2026-08-18 03:42
```

The build stamp dates the place to **2026-08-18** — after the 08-17 canary,
which is the timeline the rename explanation predicts.

Headless reproduction: transcribing the shipped precedence into
`boot_mode.decide` turned `tests/gallery_boot_mode.spec.luau` red on
`a scenario selector wins in the showcase place — expected showcase to be
scenario`, plus six sibling rows.

## The fix

`examples/gallery/client/boot_mode.luau` (new, pure) takes the three attribute
values and returns a decision. Two rules:

1. **A verification selector outranks the demo shell**, in every place, always.
   Scenario > example > showcase > plain demo.
2. **A selector that was set and cannot be honoured is never silent.** Every
   branch was previously `if type(x) == "string" and x ~= "" then` with no
   `else`. Now an unusable value becomes a `refusal` — one sentence naming the
   attribute, the reason, and the fact that the selector is §5 infrastructure —
   which the bootstrap warns.

`init.client.luau` calls it once, warns every refusal, and branches on
`bootDecision.mode`. It holds no second copy: the example module-name list moved
to `boot_mode.EXAMPLE_MODULES`, so "which numbers are legal" and "which module a
number names" have one owner.

The refusals `decide` cannot see (folder not replicated, name not registered,
runner throws) now speak in the same voice **and stamp
`Facet_ScenarioState = "refused:<reason>"`** — an external driver polling
`Facet_ScenarioReady` cannot otherwise tell "refused" from "still booting". A
throw is stamped, warned, and **re-raised**: a `pcall` that swallowed it would
reproduce the very defect the branch was rewired to fix.

The `Facet_Example` flow shared the identical break (same shadowed region) and
is fixed by the same decision. Both reported scenario names, `table_virtualized`
and `examples`, are registered — asserted against the shipped `ORDER` block.

## Consistency with the concurrent INT-1 work

Different root cause (that one is the demo-host core proxy hiding the published
environment; this one is branch shadowing), same doctrine. The fix follows
`demo_host.luau`'s host-publishes shape deliberately: the decision is a module
the spec **requires** rather than a copy that can drift, and the spec's last
describe block enforces that — each selector attribute must be read exactly once
in `init.client.luau`, and that once must be inside the `boot_mode.decide(...)`
argument. A count, not a presence check: "the literal never appears" would be
satisfied by splitting the string, and "it appears" would be satisfied by the
second reader that is the whole defect.

Note: commit `c247f1b` (the INT-1 wave) swept this task's
`require("./gallery_boot_mode.spec")` line into itself, leaving HEAD requiring a
spec file that was not yet tracked. This commit repairs that.

## Evidence

- Framework suite: **6721 passed, 0 failed** (baseline 6702 before this task —
  +19 rows; that baseline already included INT-1's 6 rows).
- Rascal Rally suite: **3431 passed, 0 failed** — unchanged, as expected:
  nothing under `src/` was touched, so the live consumer's contract is
  untouched. Re-measured after the fix.
- Mutation sweep, 7 of 7 bite:

  | # | Mutation | Rows red |
  |---|---|---|
  | M1 | showcase decided first (the shipped order) | 3 |
  | M2 | `error(result, 0)` deleted (throw swallowed) | 1 |
  | M3 | `warn(refusal)` deleted (refusals computed, never spoken) | 1 |
  | M4 | a second, independent `Facet_Scenario` reader added | 1 |
  | M5 | registry-missing refusal downgraded to a bare warn | 1 |
  | M6 | `pcall(runner.start, …)` removed | 1 |
  | M7 | refusals dropped inside `decide` | 5 |

- `stylua --check` clean; both files compile under `luau.load` (checks the local
  limit as well as syntax).
- `tools/check_source_size.py` PASS, `tools/check_brand_drift.py` PASS.
- `rojo build` of `examples/showcase.project.json` and
  `examples/gallery.project.json` succeeds; the built showcase place carries
  `boot_mode` (20 references) and 4 `bootDecision.mode ==` branches, so the
  module maps through `gallery/client` as a sibling of the bootstrap.

## Owed

**A live Studio canary of the mounted result.** Everything above proves the
decision and the wiring; the last step — Play in a place carrying the fix and
observe `workspace.FacetScenarioAPI` appear with `report/step/reset` — was not
run, because the only open Studio instance belongs to the concurrent INT-1
writer and their `studio_sync` server already holds the port (`Address already
in use`). Injecting would have pushed a tree into their in-flight session.

Recipe when the session is free:

```bash
tools/build_places.sh                 # or: lune run tools/lune/studio_sync + tools/studio/inject.luau
# open Facet-Showcase.rbxl, set workspace.Facet_Scenario = "table_virtualized" in Edit, Play
```

Expect: `[Facet Scenario] 'table_virtualized' ready (<version>); steps: …`,
`workspace.FacetScenarioAPI` present, `Facet_ScenarioState = "ready"`. The
negative control is worth taking in the same session: set
`Facet_Scenario = "nope"` and confirm the console names the unregistered
scenario instead of booting the showcase.
