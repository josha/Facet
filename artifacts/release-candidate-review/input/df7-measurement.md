# DF-7 — `InputBinding.PrimaryModifier` × `InputContext.Sink`

**STATUS: UNMEASURED.** This file exists so the gate row
`df7-modifier-sink-measured` has an evidence path and so the next agent finds the
question written down rather than re-deriving it. It holds no reading yet. The
row is a **bare PENDING** and cannot pass until the section marked *THE READING*
below is filled in from a live keyboard.

**No binding was changed in wave R3.** The inventory called this "the
highest-value open input question in the release candidate", and it is open in the
literal sense: the engine's behaviour is undocumented, both outcomes are silent,
and a change made without a measurement would be a guess wearing a fix's clothes.

---

## 1. The pair

| | binding | context | priority | sink |
|---|---|---|---|---|
| A | `RowActionsMenu` ← `Return` + `modifiers = { shift = true }` | `RowActionsKeys-<id>` | `10000` | **true** |
| B | `Activate` ← plain `Return` | the base screen's nav context | 1500 (3500 modal) | per surface |

Sources, current at 2026-08-18:
`src/controls/row_actions.luau:213` (`ROW_KEYS.menu`),
`src/controls/row_actions.luau:2225-2233` (the sinking context),
`src/present/presenter.luau:2251` (`activate.bind({ keyCode = "Return" })`).

The pad half is not at risk: `RowActionsMenu` also binds `ButtonX`, which nothing
else claims.

## 2. What the platform actually says

`InputContext.Sink`, verbatim from the class reference:

> "When Sink is set to true, inputs will not be processed for connected InputAction
> bindings within contexts of lower Priority. Contexts with the same priority will
> receive the input. For example, if multiple contexts contain an InputAction with
> a binding to `Enum.KeyCode.E` and a higher priority context has Sink set to true,
> the lower priority contexts will not receive the input signal for
> `Enum.KeyCode.E` and will fire no events for it."

`InputBinding.PrimaryModifier`, verbatim:

> "The InputBinding will only trigger the parent InputAction if this input is
> pressed prior to KeyCode, UIButton, or composite directions."

**The gap:** `Sink` is described **by KeyCode**. `PrimaryModifier` is described as
gating whether a binding *triggers its action*. Nothing anywhere states whether a
modifier narrows what its context **sinks**. The two sentences do not compose.

## 3. What the headless model does, and why that is not an answer

`src/input/actions.luau` filters modifier-mismatched bindings **out of candidacy
before** the sink loop runs (`modifierMatch` at `:341-352`, then `deviceKey` at
`:356-411`). So in the model, plain `Return` is sunk only while the modified
binding is genuinely eligible — outcome (a) below.

That is a **design decision recorded in a comment**, not a measurement:

> "PREEMPTION DECISION POINT (Task 8b): filtering a modifier-mismatched binding out
> of `candidates` HERE, before the untouched sort/sink loop below ever runs, is the
> whole mechanism."

The model was written to mirror the engine. Whether it does, here, is exactly what
is unmeasured — and the model passing its own tests is not evidence about the
engine. No gate row records a live reading of this pair;
`tools/lune/gate_manifest.luau:853` pins only the static DK-16 scan.

## 4. The three outcomes and the fallback

| # | plain `Return` on a focused row | `Shift+Return` | meaning | action |
|---|---|---|---|---|
| **a** | activates | menu only | sink is **per-binding-candidate**; the model is right | none — record and close |
| **b** | does **not** activate | menu only | sink is **per-KeyCode**; Enter stops activating rows while any row-actions context is alive | **rebind the menu to a distinct chord** |
| **c** | activates | menu **and** activate | the engine sinks only on match but still offers the unmodified sibling | **rebind the menu to a distinct chord** |

**The fallback, spelled out** so it is not re-invented under pressure: give
`RowActionsMenu` a keyboard chord that shares **no KeyCode** with `Activate`.
`ButtonX` already covers the gamepad, so only the keyboard side moves, and
`ROW_KEYS.menu` is one table in one file (`row_actions.luau:213`) with a pinned
count in `tools/check_no_screen_key_bindings.py` (`PINS`, 4 sites in
`row_actions.luau`) that moves with it. Outcome (b) is the dangerous one — it is
silent, it breaks a verb users already have, and it only manifests while a row is
focused.

## 5. How to measure it

`artifacts/release-candidate-review/input/studio-checklist.md` §5 — a real
keyboard, the showcase place, a Table with row actions mounted, four presses in a
fixed order with a control reading first.

## 6. THE READING

> *Not taken. Fill this section in from the Studio session: build stamp, Studio
> version, the four presses in order, what each did, and which of (a)/(b)/(c) the
> readings select. Then, and only then, the gate row earns a `run`.*
