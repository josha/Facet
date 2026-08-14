# Two InputContexts on one key: the engine's arbitration, measured

**Measured live in Studio, 2026-08-13** (LuauUI-Showcase, **Play / Client**, real
engine instances — `InputContext` / `InputAction` / `InputBinding` under
`Players.LocalPlayer`).

Parity round 3's owed row 9 gave `newVirtualList` a **stand-in** key context for
the focused row: a hosted row's own gesture engine is built by a pointer swipe,
so a row a keyboard-only or pad-only player had merely focused had no Delete and
no menu binding at all. The stand-in binds the same keys as the engine's own
context and sits **one priority below** it, so that a row which *does* have an
engine answers there and commits exactly once.

That whole design rests on one engine behaviour, and until this probe the repo's
only citation for it was a **headless** spike (`row_actions.luau`'s "spike T1: a
higher-priority Sink context blocks a lower one on the same key"). The headless
action system is a model of the engine, not evidence about it. So it was asked.

## The experiment

Two `InputContext`s parented to `LocalPlayer`, both `Sink = true`, both carrying
one Bool `InputAction` with an `InputBinding` on **Delete**; a third added later
for the modifier half. Keys injected with `user_keyboard_input`.

| state | pressed | fired |
|---|---|---|
| `HighSink` (Priority 10000) + `LowSink` (9999), both enabled | `Delete` | **`HighSink` only** |
| `HighSink.Enabled = false`, `LowSink` enabled | `Delete` | **`LowSink`** |
| a Priority-10000 binding with `PrimaryModifier = LeftShift` on `Return` | plain `Return` | **nothing** |
| the same binding | `LeftShift` held + `Return` | **fired, once** |

Rows 1 and 2 are each other's control: without row 2, "the low context never
fires" is equally explained by "this context was never live at all".

## What it licenses

1. **A higher-priority sinking context consumes the key.** The engine agrees with
   `src/input/actions.luau`'s model, so the two-binder design cannot double-fire
   while the engine's own context is enabled.
2. **A disabled context is transparent, not a wall.** The stand-in receives the
   key precisely in the state it exists for.
3. **`PrimaryModifier` really gates candidacy.** A shift-modified binding is not
   a candidate with shift up, which is what leaves plain `Return` to the base
   screen's Activate — the behaviour Rascal Rally's own Shift+Return watch
   depends on (`code/tests/luauui_row_actions_reach_contract.spec.luau`).

## …and it corrects a recorded truth

`docs/lessons/engine-input-truths-phaseb.md` truth 3 (2026-07-19) says:

> Under Studio injected input, key bindings do not fire while Shift is held —
> composite AND Bool both (probed both) … shift+key chords cannot be driven by
> `user_keyboard_input`.

**A chord declared through `InputBinding.PrimaryModifier` fires under injection
today** (row 4 above). That truth was written before this repo used
`PrimaryModifier` at all — round 8b's first design believed the engine had no
modifier concept, and the platform review corrected it — so it describes holding
Shift while pressing an *unmodified* binding, not a modified binding's own chord.
Do not skip a chord test on the strength of it.
