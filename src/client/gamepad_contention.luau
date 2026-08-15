--!strict
-- Gamepad contention helper (CLIENT-ONLY; ui_todo.md §3 engine truths,
-- live-gamepad-probe-verified 2026-07-20). The one job of this module is to make
-- gamepad ButtonA reach the Input Action System in a UI-ONLY place.
--
-- SCOPE — UI-ONLY PLACES ONLY. `disableLegacyControls` turns OFF the avatar
-- control scripts. That is correct for a place that is nothing but UI (the
-- LuauUI gallery qualifies), and WRONG for a real game: a game must NOT disable
-- avatar input to win a button. A real game instead puts avatar input onto the
-- Input Action System (`Workspace.PlayerScriptsUseInputActionSystem = true`,
-- a Properties-panel-only flag — ENGINE TRUTH 2) and lets UI-vs-gameplay
-- contention resolve through InputContext priority + Sink — the focus-aware
-- first-responder model being designed under ADR-0014 (in progress). See the
-- "Gamepad in real places" section of docs/guide/07-input.md. This module gives
-- a real game only `legacyStackActive()` — a detector to WARN with, not a fix.
--
-- ENGINE TRUTH 1 — jumpAction eats ButtonA unconditionally. The LEGACY control
-- scripts bind gamepad ButtonA to `jumpAction` at ContextActionService priority
-- 2000 UNCONDITIONALLY — even with `Players.CharacterAutoLoads = false` and no
-- character — and silently consume it (`gameProcessedEvent == true`, the IAS
-- Activate action never fires). D-pad and thumbsticks pass through, which MASKS
-- the problem until a gamepad user presses A on a button. A UI-ONLY place may
-- therefore disable the control module (fallback: unbind `jumpAction`). A real
-- game keeps its controls and relies on IAS arbitration (Truth 2), NOT on this.
--
-- ENGINE TRUTH 2 — that flag is Properties-panel-only. `PlayerScriptsUse-
-- InputActionSystem` is NOT script- or rojo-reflectable (re-verified 2026-07-20);
-- code can neither read nor set it. This module cannot detect or toggle it — the
-- human must set it in Studio's Properties panel. Surfaced in docs, not here.
--
-- ENGINE TRUTH 5 — CAS PRIORITY AND InputContext.Priority ARE NOT ONE
-- ARBITRATION SPACE (measured live in the showcase 2026-08-14, four readings in
-- one session). A sinking `ContextActionService` binding consumes a key BEFORE
-- any `InputContext` is offered it, at ANY priority: a CAS Sink at priority 100
-- beat a LuauUI `InputContext` at priority 10000 with `Sink = true` (the probe
-- fired twice; the InputContext action never fired). Unbinding the CAS action
-- made the identical presses reach the InputContext immediately.
--
-- The consequence is the one that matters for design: THERE IS NO NUMBER a
-- framework can put on an `InputContext` that takes a key back from a legacy
-- CoreScript CAS binding. `RbxCameraKeypress` (Left/Right/I/O, priority 2000,
-- Sink) is therefore un-outrankable from IAS, and a control that wants those
-- arrows must either accept losing them or claim them IN CAS
-- (`BindActionAtPriority` above 2000, unbound again on release — measured to
-- work, and to hand the key straight back). That second option is a framework
-- architecture decision, not a patch: `src/client/roblox_input.luau` deliberately
-- never re-implements or reaches into arbitration. Recorded here so the next
-- agent does not spend a round discovering that a bigger number does nothing.
-- Full story: docs/lessons/the-camera-still-owns-the-arrow-keys.md.
--
-- ENGINE TRUTH 3 — CoreGuiNavigationEnabled fights back. `GuiService.
-- CoreGuiNavigationEnabled` re-enables itself if scripted off (CoreScripts
-- reassert it) and is NOT the ButtonA eater anyway. This module deliberately
-- does NOT touch it: a scripted-off "solution" would not hold. Recorded so no
-- one wires one expecting it to stick.
--
-- REQUIRE-SAFE: nothing at module scope touches an engine global, so this file
-- `require()`s cleanly under Lune and in Studio Edit. Every engine call lives
-- inside a function and is `pcall`-guarded, so requiring or calling it off the
-- live client (server, Edit, headless) never throws. See the full story in
-- docs/guide/07-input.md and docs/lessons/gamepad-contention-truths.md.

local gamepad_contention = {}

local CONTENTION_DESCRIPTION = table.concat({
	"Gamepad ButtonA contention (ui_todo.md §3, live-probe-verified 2026-07-20):",
	"1. The legacy control scripts bind gamepad ButtonA to jumpAction at "
		.. "ContextActionService priority 2000 unconditionally (even with "
		.. "CharacterAutoLoads=false and no character) and consume it "
		.. "(gameProcessedEvent=true); the Input Action System's Activate never "
		.. "fires. D-pad/thumbsticks pass through, masking it. Remedy for a "
		.. "UI-ONLY place ONLY: gamepad_contention.disableLegacyControls() "
		.. "(PlayerModule:GetControls():Disable(), fallback UnbindAction "
		.. "'jumpAction'). A real game must NOT disable avatar input — it puts "
		.. "avatar input on IAS (truth 2) and lets InputContext priority+Sink "
		.. "arbitrate (focus-aware first-responder model, ADR-0014 in progress).",
	"2. Workspace.PlayerScriptsUseInputActionSystem (which puts avatar input "
		.. "onto IAS so it joins arbitration) is a Properties-panel-only flag: "
		.. "NOT readable or settable from code or Rojo. A human must toggle it in "
		.. "Studio. legacyStackActive() is only a behavioral probe of the symptom.",
	"3. GuiService.CoreGuiNavigationEnabled re-enables itself if scripted off "
		.. "(CoreScripts fight back) and is not the eater anyway; do not rely on "
		.. "scripting it off.",
	"5. ContextActionService priority and InputContext.Priority are NOT one "
		.. "arbitration space (measured live 2026-08-14): a sinking CAS binding at "
		.. "priority 100 consumed Left/Right while a LuauUI InputContext at priority "
		.. "10000 with Sink=true never fired, and unbinding the CAS action let the "
		.. "identical presses through at once. So no number outranks a legacy "
		.. "CoreScript binding from IAS — RbxCameraKeypress (Left/Right/I/O, prio "
		.. "2000, Sink) is un-outrankable that way. The only measured lever is a "
		.. "BindActionAtPriority claim of our OWN action above it, unbound on release "
		.. "(the camera receives the very next press) — a framework architecture "
		.. "decision, since roblox_input.luau never reaches into arbitration.",
	"4. Tab is the CoreGui PLAYERS LIST shortcut, and while that CoreGuiType is "
		.. "enabled (the default) the platform documents it as reserved — so "
		.. "LuauUI's Tab/Shift+Tab focus traversal will not receive it. Roblox "
		.. "files Tab under 'reserved unless you disable the respective feature' "
		.. "rather than in its hard-reserved set (Esc/F9/F11/F12/PrintScreen), "
		.. "and documents exactly one remedy: StarterGui:SetCoreGuiEnabled("
		.. "Enum.CoreGuiType.PlayerList, false). No InputContext priority is "
		.. "documented to outrank CoreGui. traversalKeyContended() probes it.",
}, "\n")

-- The three engine truths as a diagnostic string (for logs / doctor output).
function gamepad_contention.describeContention(): string
	return CONTENTION_DESCRIPTION
end

-- Behavioral probe: does the legacy avatar control stack appear to be active?
-- ENGINE TRUTH 2 means the deciding flag (PlayerScriptsUseInputActionSystem) is
-- NOT script-readable, so we cannot ask it directly. Instead we look for the
-- symptom: a `jumpAction` binding in ContextActionService's bound-action table
-- (that is the exact binding that eats ButtonA — ENGINE TRUTH 1). This is a
-- best-effort BEHAVIORAL probe, not a flag read: a game that rebinds jump under
-- a different name, or the IAS stack routing jump differently, can make it wrong
-- in either direction. Its intended use is a real game (or doctor tooling)
-- WARNING that ButtonA may be contended, so the loss is visible instead of
-- silent — never as a hard gate. Returns false headless / off the live client.
function gamepad_contention.legacyStackActive(): boolean
	local ok, active = pcall(function(): boolean
		local ContextActionService = game:GetService("ContextActionService")
		local bound = ContextActionService:GetAllBoundActionInfo()
		return bound["jumpAction"] ~= nil
	end)
	return ok and active == true
end

-- Is the Tab focus-traversal key contended by CoreGui right now? (roadmap Step 8)
--
-- SAME SHAPE AS legacyStackActive, DIFFERENT KEY. Roblox's own documentation
-- puts Tab in the table of inputs that are "reserved unless you disable the
-- respective feature", and Tab's feature is the CoreGui players list; the hard
-- table that "cannot be overridden" is Esc/F9/F11/F12/PrintScreen and Tab is
-- deliberately not in it. So unlike ButtonA there IS a flag to read, and this is
-- a real read rather than a behavioral guess: the players list being enabled is
-- the documented condition under which Tab does not reach a developer
-- InputContext.
--
-- Its intended use is the same: a game (or doctor tooling) WARNING that keyboard
-- traversal may be silently dead, so the loss is visible. It is never a gate,
-- and LuauUI never disables the players list on a consumer's behalf — hiding a
-- game's leaderboard to win a key is exactly the trade this module's SCOPE note
-- refuses to make for the avatar controls.
--
-- Returns false headless / off the live client, and false once the players list
-- is disabled. It reports the DOCUMENTED contention condition, not an
-- end-to-end proof: only a physical Tab press on a real client can confirm the
-- key reaches Activate either way (standing PENDING_PHYSICAL rider).
function gamepad_contention.traversalKeyContended(): boolean
	local ok, contended = pcall(function(): boolean
		local StarterGui = game:GetService("StarterGui")
		return StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.PlayerList) == true
	end)
	return ok and contended == true
end

-- Disable the legacy control scripts so gamepad ButtonA reaches the Input Action
-- System instead of being eaten by jumpAction (ENGINE TRUTH 1). UI-ONLY PLACES
-- ONLY — this turns off avatar input; a real game must NOT call it (see the
-- SCOPE note in the module header and docs/guide/07-input.md). Call it once from
-- a UI-only place's client bootstrap.
--
-- `playerModuleParent` (optional) is the instance that CONTAINS `PlayerModule`;
-- it defaults to the local player's `PlayerScripts`. Injecting it lets a caller
-- (or a test) supply the container explicitly.
--
-- Returns whether it believes ButtonA is now UNCONTENDED:
--   * true  — the control module was disabled (removes all its CAS binds,
--             jumpAction included), or the narrower jumpAction unbind fallback ran.
--   * false — neither engine path was reachable (running on the server, in Studio
--             Edit, or headless under Lune — there is no live gamepad to free).
-- The return is a best-belief signal, not an end-to-end proof: only a physical
-- gamepad press can confirm ButtonA now reaches Activate (standing
-- FAIL_ENVIRONMENT rider `physical-device-confirmation`).
function gamepad_contention.disableLegacyControls(playerModuleParent: any?): boolean
	-- Primary: disable the whole control module. This is the correct move for a
	-- UI-only place — it removes ALL of the control scripts' CAS bindings,
	-- jumpAction included, in one call.
	local disabled = pcall(function()
		local parent = playerModuleParent
		if parent == nil then
			local Players = game:GetService("Players")
			parent = Players.LocalPlayer:WaitForChild("PlayerScripts")
		end
		-- bounded wait: a place running the IAS player-script stack (or a
		-- stripped test place) may never insert PlayerModule at all — an
		-- unbounded WaitForChild would hang this thread forever (observed
		-- live 2026-07-21: infinite-yield warning in the gallery places)
		local PlayerModule = require(assert(parent:WaitForChild("PlayerModule", 5), "no PlayerModule")) :: any
		PlayerModule:GetControls():Disable()
	end)
	if disabled then
		return true
	end
	-- Fallback: unbind jumpAction directly. Narrower — the rest of the control
	-- module keeps running — but the specific ButtonA eater is gone.
	local unbound = pcall(function()
		game:GetService("ContextActionService"):UnbindAction("jumpAction")
	end)
	return unbound
end

return gamepad_contention
