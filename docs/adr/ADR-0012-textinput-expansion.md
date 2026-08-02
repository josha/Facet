# ADR-0012 — UI.TextInput: the first Phase-5 expansion gate

Date: 2026-07-20 · Status: accepted (gate: `expansion-textinput`) · Spec: design §17 Phase 5, ui_todo.md §0/§1

## Decision

Build `UI.TextInput` as the library's first post-Phase-4 expansion, governed by its own
gate (`lune run tools/lune/gate expansion-textinput`), registered in `phases.json` and
`tools/lune/gate_manifest.luau`. The shape is the split approved in ui_todo.md §1:

- a **signal-backed value model** in a composite control (`LuauUI.newTextInput`) that owns
  editing state, live (`onChange`) and commit (`onCommit` on Enter/FocusLost) modes,
  placeholder, disabled, keyboard-type hint, optional in-field clear affordance, max
  length, and a validation hook — fully provable headlessly;
- a new leaf primitive (`TextField`) that is the **only** place the engine `TextBox`
  enters, through the render-adapter seam (`setTextInputHandlers` in the target
  contract) with capability detection in `src/client/screen_target.luau`;
- a **text-entry-mode handshake**: while editing, a high-priority sinking InputContext
  removes keystrokes from the semantic-action space (typing never navigates); gamepad
  gets an explicit enter/edit/exit story (A enters, B cancels — D1: Escape is
  engine-core-reserved, engine escape arrives as the adapter's cancel reason);
- **occlusion awareness**: the control consumes the environment's
  `keyboardOcclusionRect` so a focused field stays visible above the on-screen keyboard
  (keep-visible offset through the presentation authority).

## The §17 Phase-5 expansion contract

| Requirement | How it is met |
|---|---|
| Use case | Director-approved (ui_todo §1): example 01 needs a real numeric temperature field (commit + live modes); example 02 needs an iTunes-style filter-as-you-type field; both already route through signals. Steppers were the stopgap. |
| Inability with current primitives | Real text entry requires the engine `TextBox` (OS keyboard, IME, focus capture). No composite of shipped primitives can summon a keyboard or receive typed text; the stopgap (steppers) cannot express free-form/filter entry. |
| Benchmark | `textinput-typing-storm` scene in the bench suite (per-keystroke paint/semantic writes, no remount) vs the pinned baseline; gate check `expansion-adr-bench-rollback`. |
| Conformance extension | `TextField`/`TextInput` rows in `src/controls/contract.luau` + the registration checker; the §10.2 control contract (build/render, per-input interaction, no factory reruns, dump determinism, registry neutrality) encoded as specs. |
| Rollback/fallback | The control is additive — no existing surface depends on it; examples can revert to steppers/no-filter by dropping the field. Engine capabilities are detected per feature (keyboard-type hint, multi-line wrapping): missing capability degrades to plain single-line `TextBox` behavior, headless targets keep declarations as data. Multi-line wrapping stays **gated off** behind capability detection because engine text layout is known-broken on mobile (devforum 1014598, wrap-while-typing) — single-line is the first-class, robust path; mitigations documented in `docs/research/2026-07-20-textbox-engine-facts.md`. |

## Why this edits the gate manifest despite new-control.md's rule

`docs/extending/new-control.md` forbids gate-manifest/phases edits **for a composite
control** — those ride the existing phase-4 checks. TextInput is not that: it is an
expansion gate (new engine instance class + input-mode design work), and the design's
expansion rules require its own gated evidence trail. The manifest entry follows the
house keep-honest rule: checks land as `PENDING` and flip to `run` only when their
implementation exists.

## Consequences

- The action system gains one new (documented) pattern: a control-owned sinking
  InputContext for modal text entry, priority above modals.
- The target contract gains optional `setTextInputHandlers`; adapters that do not
  implement it simply never report text events (headless default).
- `physical-device-confirmation` remains the standing non-blocking environment gap,
  consistent with phase-4.
