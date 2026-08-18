# Gamepad ButtonA is eaten by jumpAction — character or not

> Expanded: `gamepad-contention-truths.md` covers all three §3 truths, the
> UI-only vs. real-game remedies (helper + IAS arbitration / ADR-0014), and the
> encoding map. This file is the original truth-1-only note.

Live-gamepad probe (2026-07-20, demo place, no character): every raw ButtonA
reached the client with gameProcessed=true and the bound IAS Activate action
never fired, while D-pad bindings on the SAME context worked. Cause (from
`ContextActionService:GetAllBoundActionInfo()`): the legacy control scripts
bind `jumpAction` to `Enum.KeyCode.ButtonA` at priority 2000 UNCONDITIONALLY
— `Players.CharacterAutoLoads = false` does not prevent it; the jump no-ops
invisibly and consumes the button. Fix for UI-only places: disable the
control module (`require(PlayerScripts.PlayerModule):GetControls():Disable()`;
fallback `CAS:UnbindAction("jumpAction")`) — the gallery bootstrap does this.
Games: run the IAS player-script stack or accept A-contention. That flag is
`Workspace.PlayerScriptsUseInputActionSystem = "Enabled"` — **on Workspace, not
StarterPlayer**, and it IS declarable from rojo
(`"Workspace": { "$properties": { "PlayerScriptsUseInputActionSystem": "Enabled" } }`),
which is what `docs/guide/07-input.md` tells every consumer to do. This note
carried the earlier session's two errors — the wrong class, and
"Properties-panel-only; not reachable from Luau reflection or rojo's database" —
after both were corrected in
`docs/research/2026-07-21-first-responder-platform-research.md` (platform
verifier P2). It is still not settable at RUNTIME from Luau; a game declares it
in its project, and Facet detects the mode rather than setting it. Related:
`GuiService.CoreGuiNavigationEnabled` re-enables itself when scripted off.
