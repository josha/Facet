# Acceptance ledger — `desktop-keyboard-navigation` (roadmap Step 8)

**Stage plan:** [`docs/plans/desktop-keyboard-navigation.md`](../../docs/plans/desktop-keyboard-navigation.md)
**Contract:** [`docs/plans/agent-execution-contract.md`](../../docs/plans/agent-execution-contract.md) §2/§3
**Device matrix:** [`docs/plans/studio-device-verification.md`](../../docs/plans/studio-device-verification.md)
**Stage-start source:** `aeffc68`, suite floor **3028**, baseline pinned in `baseline/`

Written before implementation. Status values are the contract's: `PASS_AUTOMATED`,
`PASS_PHYSICAL`, `PASS_HUMAN`, `FAIL_PRODUCT`, `FAIL_ENVIRONMENT`,
`PENDING_PHYSICAL`, `PENDING_HUMAN`, and `PENDING` for a row not yet attempted.
A row may not pass through an easier row: a headless traversal test does not close
a raw-input row, and a capture does not close an input-routing row.

---

## Rows

| ID | User-visible behavior | Risk while a lower test still passes | Evidence | Driver | Artifact | Status |
|---|---|---|---|---|---|---|
| **DK-1** | Tab moves focus to the next control in the screen's order; Shift+Tab to the previous | Traversal invents its own order instead of reading the mounted focus graph, so it disagrees with the ring the arrows walk | E1 | `tests/keyboard_navigation.spec.luau` | suite | PASS_AUTOMATED |
| **DK-2** | Tab crosses navigation-group boundaries in mounted/group order — a row of buttons, then the next group | Traversal only walks the active group (the arrow model) and dead-ends at a group edge | E1 | same | suite | PASS_AUTOMATED |
| **DK-3** | Traversal wrap is the **scope's** declared policy (default: wraps), never a per-control invention | Each scope wraps differently, or a modal's last control dead-ends with nothing to say | E1 | same | suite | PASS_AUTOMATED |
| **DK-4** | Hidden, disabled, non-focusable, retiring, and losing-adaptive-candidate nodes are skipped by Tab exactly as they are by the arrows | Tab uses a second, unfiltered order and lands on a control the player cannot see or use | E1 | same | suite | PASS_AUTOMATED |
| **DK-5** | Traversal survives structural churn: rows appearing/disappearing between presses keep focus or pick the same nearest survivor the graph already picks | A cached order array traverses to a path that no longer exists | E1 | same | suite | PASS_AUTOMATED |
| **DK-6** | A modal traps Tab inside itself and restores the prior focus on dismiss; a transient popup scope behaves the same | Tab escapes a modal into the covered screen | E1 | same | suite | PASS_AUTOMATED |
| **DK-7** | A Tab move onto an off-screen control scrolls it into view through the one shared keep-visible service | Traversal re-implements scroll arithmetic, or silently leaves focus off-screen | E1 + E3 | same + Studio scroll trace | suite, `studio/keyboard.json` | PASS_AUTOMATED |
| **DK-8** | Return **and** Space each activate the focused control, once per press | Space stays a no-op gameplay guard, or double-activates alongside Return | E1 + E3 | same + Studio raw-input trace | suite, `studio/keyboard.json` | PASS_AUTOMATED |
| **DK-9** | One physical press produces exactly one Activate even when IAS and a native `GuiButton.Activated` both observe it | The engine-selection bridge doubles every keyboard activation on a modal | E1 + E3 | same | suite, `studio/keyboard.json` | PASS_AUTOMATED |
| **DK-10** | A focused Slider/Stepper consumes the arrows on its declared axis as Adjust; the other axis still Navigates | On a grouped screen the arrows stay with NavigateH and the value control is only reachable through Comma/Period | E1 + E3 | same | suite, `studio/keyboard.json` | PASS_AUTOMATED |
| **DK-11** | Adjust keys are bound only while focus sits on a declared adjust target; a screen whose focus is elsewhere shadows no gameplay key | A permanent Adjust binding steals a game's arrow/bumper input | E1 | same | suite | PASS_AUTOMATED |
| **DK-12a** | While a TextInput edits, Space does not activate and the arrows do not navigate | Space activates under the caret; arrows move the ring out of an open edit | E1 + E3 | same + Studio text trace | suite, `studio/keyboard.json` | PASS_AUTOMATED |
| **DK-12b** | Tab out of an editing field never types a tab character, never bypasses validation, and never advances out of an unfinished edit | Tab silently corrupts the value or strands a half-finished edit | E1 + E3 | same | suite, `studio/keyboard.json` | PASS_AUTOMATED |
| **DK-12c** | ...and it *commits* through the field's own path, then advances | The commit is skipped and the value is dropped | E3 | `studio/keyboard.json` row `DK17-F` | `studio/keyboard.json` | **FAIL_ENVIRONMENT** — the engine marks keyboard input `gameProcessed` while a TextBox holds focus and fires no developer binding, so the key never arrives. Headlessly proven and inert on this engine; procedure in `review-packet.md`, decision in `decisions.md` DKN-2 |
| **DK-13** | Keyboard bindings exist only while an interactive responder owns UI input **and** keyboard capability is live; plugging/unplugging a keyboard adds/removes them with no leaked binding or stuck sink | A one-frame window in which the sink is up with no owner, or bindings that survive a resign | E1 | same | suite | PASS_AUTOMATED |
| **DK-14** | Dismissing or disposing a surface removes every keyboard binding and its context | A dismissed screen keeps eating Tab/Space | E1 | same | suite | PASS_AUTOMATED |
| **DK-15** | A passive HUD binds no Tab, Space, or arrows: gameplay input is untouched until the surface engages | The HUD steals the jump key the moment it is on screen | E1 + E3 | same + Studio responder trace | suite, `studio/keyboard.json` | PASS_AUTOMATED |
| **DK-16** | A screen adds **zero** key listeners: mounting public controls and presenting is the whole setup | The behavior only works because the fixture wired an option | E0 + E1 | `no-screen-key-bindings` gate check | gate.json | PASS_AUTOMATED |
| **DK-17a** | Raw Tab / Shift+Tab / Space / Return / arrows driven by `VirtualInput` reach the intended semantic action and visible state, in a form, a scrollable list, a modal, a Slider and a Stepper, on an unconstrained **desktop** Studio window (no simulator preset; see the preflight) | A scriptable `binding:Fire()` proves the downstream path only — it proves nothing about native arbitration or delivery | E3 | `tools/studio/device_matrix.luau` `keyboard` mode + gallery scenario `keyboard_navigation` | `studio/keyboard.json` + `studio/dk17-fixture.png` | PASS_AUTOMATED (players list disabled — see DK-17c) |
| **DK-17b** | ...on a **keyboard-capable phone/tablet** profile | A desktop row is quietly reused for a device row | E4 | `review-packet.md` DK-P1 | review result | **PENDING_PHYSICAL** — the emulator cannot produce a keyboard-capable touch profile and never summons the mobile OS keyboard |
| **DK-17c** | Tab reaches the traversal action while the CoreGui **players list** is enabled (the default) | The headline convention is dead by default on any game with a leaderboard | E3→E4 | `review-packet.md` DK17-A | `studio/keyboard.json` row `DK17-A-tab-contended` | **FAIL_ENVIRONMENT** — the engine refuses to synthesize Tab at all while the players list is enabled (same refusal as `Escape`); disabling it frees the key, proven live. Decision in `decisions.md` DKN-1 |
| **DK-18** | RascalRally still behaves identically: its contracts are audited against the change, its suite is green at this source, and an affected Studio canary is re-run **in the game's own place** | The framework change is compatible in the library and broken at the one live consumer; or the row is closed by the game suite alone, which is not a boundary | E1 + E3 | `consumer-impact.md` + game suite + the game-place canary | `consumer-impact.md`, `studio/keyboard.json` row `DK18-consumer-canary` | PASS_AUTOMATED |
| **DK-P1** | A **real operating-system keyboard** on a phone/tablet drives the same traversal/activation the emulated profile does | The device emulator never summons a real mobile keyboard, so no Studio row can speak for this | E4 | `review-packet.md` | review result | PENDING_PHYSICAL |
| **DK-P2** | On a real client with a live avatar control stack, a physical keyboard hot-plug arbitrates as modeled — no stuck sink, no stolen jump | Studio cannot produce a genuine keyboard-capability transition against real player scripts | E4 | `review-packet.md` | review result | PENDING_PHYSICAL |

---

## What this stage explicitly does not claim

- **Escape as Cancel.** Engine-reserved (guide §7.4, ADR-0013). Unchanged here.
- **Type-ahead, Home/End, PageUp/PageDown.** Named gaps in the parity audit; the
  plan scopes this stage to Tab/Shift+Tab, Space/Return, and arrow Adjust.
- **Tab while the players list is enabled.** Roblox documents Tab as the
  players-list shortcut, reserved unless that CoreGui feature is disabled. The
  binding ships (it works wherever the list is off, proven live) with the limit
  documented and `gamepad_contention.traversalKeyContended()` to detect it, but
  this stage does **not** claim Tab works in a default-configured game.
- **Tab as a commit inside a focused field.** The engine does not deliver the key
  to any developer binding while a TextBox has focus. The framework's safety
  guarantees hold; the convenience does not, on this engine.
- **Grip traversal position.** A focusable `Grip` (a Slider's track, a Table's
  column handle) sorts last in the mounted focus order today, for directional
  navigation. Tab reads the same order rather than inventing a second one, so a
  Slider on a plain screen traverses after the ordinary controls. Recorded as an
  observation, not silently changed — see `decisions.md` if it becomes a defect
  under DK-17.
