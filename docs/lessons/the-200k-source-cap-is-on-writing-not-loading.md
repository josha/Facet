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
