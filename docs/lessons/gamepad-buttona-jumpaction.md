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
Games: run the IAS player-script stack (`StarterPlayer.
PlayerScriptsUseInputActionSystem` — Properties-panel-only; not reachable
from Luau reflection or rojo's database) or accept A-contention. Related:
`GuiService.CoreGuiNavigationEnabled` re-enables itself when scripted off.
