# TextBox reflection & injection truths (2026-07-20)

Found while probing real Studio TextBox behavior for the `UI.TextInput` expansion
(evidence: `artifacts/studio/expansion-textinput-probe.json`,
`docs/research/2026-07-20-textbox-engine-facts.md`). Each cost a retry.

1. **A bare `pcall(function() return inst[prop] end)` boolean cannot tell
   "member absent" from "member security-locked".** First pass recorded
   `TextInputType = false` and I nearly wrote "TextInputType does not exist on
   TextBox". Re-probing the **error string** flipped the conclusion: the read
   fails with `"The current thread cannot read 'TextInputType' (lacking
   capability RobloxScript)"` — the member is REAL but gated to
   CoreScript/RobloxScript security, so game/plugin scripts can neither read nor
   write it. Opposite design outcome (the property is "there but off-limits", not
   "missing"). **Always capture `err` on a capability probe**, and try a write too
   — `false` alone lies about why.

2. **MCP `user_keyboard_input` into a focused TextBox proves the gameProcessed
   handshake but does NOT type text.** Injected keys (H/I/Left) reached
   `UIS.InputBegan` with `gameProcessedEvent==true` while the box was focused —
   which is exactly the handshake fact worth probing — yet `Text` stayed `""` and
   the Text-changed signal never fired. Injection delivers InputObjects to the
   input pipeline but not to the engine's character-insertion layer. **Don't try
   to verify text entry / Return-submit / newline-insert by injection; they need
   a real human keypress.** Use injection only for the InputBegan/gameProcessed
   handshake, and `ReleaseFocus(true/false)` to drive `FocusLost(enterPressed)`
   scriptably.

3. **The clean unfocused negative control for the handshake is un-gettable via
   injection.** Injected keyboard delivery is coupled to game-viewport focus, and
   every `execute_luau` steals that focus (see `engine-input-truths-phaseb.md`
   #5). The only reliable re-focus was a mouse click *on the box*, which also
   focuses it — so "unfocused + inject" delivers 0 events (viewport unfocused),
   not "gp=false". Record the positive as PROBED and the negative as
   UNVERIFIED with the reason; do not burn attempts chasing a control the harness
   structurally cannot produce.
