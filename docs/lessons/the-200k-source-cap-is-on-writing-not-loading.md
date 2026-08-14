# The 200k `Source` cap is on WRITING, not on loading

**Measured 2026-08-13, live Studio, `LuauUI-PerformanceLab.rbxl`.**

Two LuauUI modules are over 200,000 characters on disk:

| file | on disk |
|---|---|
| `src/client/screen_target.luau` | 229,860 |
| `src/controls/row_actions.luau` | 219,701 |

This session was carrying "two source files are over the 200k sync cap" as an
open risk that needed the files split. **It is not a risk, and they do not need
splitting for that reason.** Asked directly, the running Studio holds both in
full:

```
screen_target: 228676 chars, tail="ter\nend\n\nreturn screen_target\n"
row_actions:   219701 chars, tail="l,\n\t}\nend\n\nreturn row_actions\n"
```

Both end on their real final line. `screen_target` reads 1,184 characters
shorter than the file on disk — that is line-ending normalisation (one character
per line), not truncation.

## What the cap actually is

The limit we hit is on **assigning `Script.Source` from code** — the plugin /
Studio-MCP write path. A place file built by Rojo and opened by Studio does not
go through that path, so a module of any size loads intact.

So:

- **Writing** a >200k module via `execute_luau` / a plugin: refused. Split the
  write, or edit on disk and rebuild the place.
- **Loading** a >200k module from a `.rbxl`: fine, verified above.

## And Rojo live-sync is a WRITING path (2026-08-14)

This is the operational bite, found by measuring a live session rather than
assuming the connection worked.

The showcase Studio was connected to `rojo serve` and looked healthy. Probing the
Edit datamodel directly:

| module | on disk | in Studio | current? |
|---|---|---|---|
| `LuauUI.row_capability` (**added** this round) | 5,735 | 5,735 | **yes** |
| `LuauUI.core.contract` (modified, small) | 3.4k | 3,420 | **no** |
| `LuauUI.core.custom` (modified, small) | 15,267 | 13,748 | **no** |
| `LuauUI.render.renderer` (modified, **220,891**) | 220,891 | 207,117 | **no** |
| `LuauUIScenarios/*` (separately mapped path) | — | — | **yes** |

**Additions land; modifications do not.** A live-sync patch has to assign
`Script.Source`, and three files now exceed the cap on disk — `renderer.luau`
220,891, `screen_target.luau` 234,055, `row_actions.luau` 234,591. Studio was
holding a 207,117-char `renderer`, i.e. the source baked into the place at build
time, because `rojo build` writes the file directly and is NOT capped.

So the same cap that is harmless for loading silently breaks the whole Studio
verification workflow: an agent runs a live check, sees a result, and reports it
as evidence about code the session has never seen.

**How to tell, in one probe:** ask the Edit datamodel for a string you committed
minutes ago. Do not infer sync from a connected-looking plugin.

**The workaround is a rebuild, not a hand-patch.** `tools/build_places.sh`
regenerates the place uncapped; the session has to be reopened for it to take.
Hand-writing `Source` into a running datamodel fails outright on the oversized
files and leaves a half-old, half-patched place — one had to be thrown away on
2026-08-13 for exactly that.

**This turns "should we split the big files?" from a taste question into an
operational one.** Three files over the cap cost live sync, and live sync is how
every device-class defect in this project has been caught.

### FOUR files, later the same day (2026-08-14)

`src/present/presenter.luau` crossed the line while ruling 9 was being built:
**207,333 on disk against 198,387 in the running showcase session** — probed
directly rather than inferred, exactly as the paragraph above says to. The fix
was in the tree, the suite was green on it, and the live session could not be
made to carry it at all: the sanctioned route is `tools/build_places.sh` plus
reopening the place, which throws away whatever session is open, and a
concurrent agent was using that one.

So the practical bite is now on the framework's THIRD most-edited file, and it
lands as a straight loss: a change to the presenter can no longer be watched
happen. The number to watch is the file, not the feature — `presenter.luau` sat
at 205,909 before this round and no single change put it over; it crossed on
ordinary growth. The list is `renderer.luau`, `screen_target.luau`,
`row_actions.luau`, `presenter.luau`.

**A cheap operational half-measure worth having:** a check that fails when a
module crosses 200,000 characters, naming the live-sync consequence, so the
crossing is a decision somebody makes rather than something a session discovers
three files later.

## Why this is worth a file

A cap observed on one path was generalised to every path, and that generalisation
turned into a standing "these files must be extracted" item that would have cost
a large, risky refactor of the two most defect-dense files in the framework for
no correctness reason at all.

There are still good reasons to split those two files — they are hard to review
and hard to reason about, and `row_actions.luau` has a documented history of
repeat defects. **Split them for maintainability if and when that is the goal, on
its own evidence.** Do not split them because of this cap.

The general rule: a limit is a property of an *operation*, not of a *file*.
Before inheriting "X is too big", ask which operation refused it, and test the
operation you actually care about.
