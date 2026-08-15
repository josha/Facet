# The camera still owns the arrow keys

**Measured live in Studio, 2026-08-14** (LuauUI-Showcase, Play mode, the
`table_columns` fixture, real engine).

`src/controls/table.luau`'s column model puts a selected column's resize on
**Left/Right** (`api.handleGrabNavigate`, `:2855-2862`): a device Activate on a
header selects the column, and while it is selected the stick owns the direction
keys — Left/Right resizes, Up/Down cycles the sort. `tests/paradigm_table.spec.
luau:147` and `tests/table_columns.spec.luau` both prove it, green.

**On the live showcase it does not happen.** Left and Right never reach LuauUI.

## The measurement

Focus on `Head-team/Column`, Return pressed (the fixture's hint line changed to
`Team has the keys…`, so the *selection* landed — the Activate path is fine):

| input | `RbxCameraKeypress` | result |
|---|---|---|
| `Right` ×3 | **bound** | Team width unchanged (`Team auto` — no override committed at all) |
| `.` ×2 | bound | Team **405 → 437px**, the readout followed |
| `Right` ×2 | **unbound** | Team **437 → 469px** |

The third row is the control that makes the first row mean something. Without it,
"Right did nothing" is equally explained by "the selection model is broken" — and
that is the story I would have written, because it is the one the code invites.

## The cause

```
RbxCameraKeypress[Enum.KeyCode.Left, Enum.KeyCode.Right, Enum.KeyCode.I, Enum.KeyCode.O] prio=2000
```

Roblox's own default camera script binds Left/Right through
`ContextActionService` at priority **2000** and **sinks** them. Nothing LuauUI
does is wrong; the key is consumed before any LuauUI handler is offered it.

`,` / `.` — the presenter's dynamically bound Adjust keys, live only while a
resizable header holds focus (`presenter.luau:2599-2639`) — are not contended,
which is why they work and why the fixture's on-screen hint names *them*.

## Why no test could see it

`tests/*.spec.luau` drive `system.deviceKey("Right", true/false)` straight into
`LuauUI.newActionSystem`. There is no camera script in a Lune process, no
ContextActionService, and therefore no contention: **the headless suite is
measuring a keyboard nobody has.** Every arrow-key assertion in this repo is a
proof about LuauUI's routing and says nothing about whether the key arrives.

This is the `an-instrument-nobody-runs` shape one level down: the instrument runs,
and it cannot see the thing.

## What already knew this

`examples/gallery/scenarios/runner.luau:1094-1100` unbinds `RbxCameraKeypress`
for any scenario declaring `keyboardFirst = true` — added during Step 8's desktop
keyboard round, recorded in `luauui-step8-desktop-keyboard`. So the repo has
known since 2026-08-03 that the camera eats arrows, and the knowledge lives in
**one host's opt-in flag**, not in the framework and not in the showcase. Every
surface reached through the demo picker — which is every surface a player can
reach in-experience — runs with the camera binding live.

## The open question, deliberately not answered here

Whether a UI framework may unbind the platform's camera keys is a design call,
not a patch:

- **The framework does it** — LuauUI would be silently changing camera behaviour
  in any experience that embeds it, which is exactly the "never shadow gameplay
  bindings" rule that `api.adjustTargets` exists to honour (it binds Adjust *only*
  while a resizable header holds focus, precisely so a bare Table never steals a
  bumper).
- **The surface does it** — the `keyboardFirst` precedent, one opt-in per screen,
  and every screen has to remember.
- **The model moves off the arrows** — Adjust (`,` `.` / bumpers) already reaches
  every resize with no contention and no selection step at all, which makes the
  select-a-column-then-steer model the redundant half.

Carried as a finding, not a fix. What must not happen again is a demo whose
on-screen instructions name a key that the platform eats.
