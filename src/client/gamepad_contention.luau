--!strict
-- Gamepad contention helper (CLIENT-ONLY; ui_todo.md §3 engine truths,
-- live-gamepad-probe-verified 2026-07-20). The one job of this module is to make
-- gamepad ButtonA reach the Input Action System in a UI-ONLY place.
--
-- SCOPE — UI-ONLY PLACES ONLY. `disableLegacyControls` turns OFF the avatar
-- control scripts. That is correct for a place that is nothing but UI (the
-- Facet gallery qualifies), and WRONG for a real game: a game must NOT disable
-- avatar input to win a button. A real game instead puts avatar input onto the
-- Input Action System (`Workspace.PlayerScriptsUseInputActionSystem = "Enabled"`,
-- declared in the place's Rojo project — ENGINE TRUTH 2) and lets UI-vs-gameplay
-- contention resolve through InputContext priority + Sink — the focus-aware
-- first-responder model (in progress). See the
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
-- ENGINE TRUTH 2 — that flag is NOT SCRIPT-READABLE, and it is NOT MISSING.
-- `Workspace.PlayerScriptsUseInputActionSystem` is not scriptable: code can
-- neither read nor set it, so this module cannot ASK whether it is on.
--
-- WHAT THIS PARAGRAPH USED TO SAY, AND WHY THE CORRECTION MATTERS (2026-08-18).
-- It said the property is "NOT script- OR ROJO-reflectable" and that "the human
-- must set it in Studio's Properties panel". The rojo half is FALSE with the
-- pinned toolchain: `tools/build_places.sh:12-16` records the 2026-08-15
-- measurement — a stale `/usr/local/bin/rojo` (7.7.0-rc.1) failed on the
-- property with "Unknown property" while the rokit-pinned 7.7.0 builds it fine —
-- and every Facet example project plus both Rascal Rally projects now declare
-- it. That wrong half is precisely why five shipped project files went without
-- the declaration for months: a place's input topology was left as an
-- unversioned, hand-ticked Studio property because this comment said versioning
-- it was impossible. Declare it in the Rojo project; only the READ is closed.
--
-- Re-probed live 2026-08-15 on 0.734.0.7340915, and the exact failure mode
-- matters because it has been misread before. A plain read
-- (`workspace.PlayerScriptsUseInputActionSystem`) errors with "is not a valid
-- member of Workspace", which reads like "this build does not have the property".
-- It is not. `workspace:GetPropertyChangedSignal(...)` answers **"is not a
-- scriptable property"** — and against a negative control
-- (`GetPropertyChangedSignal("TotallyMadeUpPropertyXyzzy")` → "is not a valid
-- PROPERTY NAME") those two error texts are provably different sentences. So the
-- property IS in this build's reflection database; its scriptability is off.
-- `StarterPlayer.CreateDefaultPlayerModule`, `Workspace.NextGenerationReplication`
-- and `Workspace.SignalBehavior` all answer identically — the same capability-gated
-- class (`GameStudio/specialists/ROBLOX.md`, Server Authority setup).
--
-- The consequence for design: this is NOT a rollout gap that a newer Studio build
-- will close. Scriptability is a reflection-level flag, so **no Facet version on
-- any build can read this property**, and every detector here is necessarily
-- BEHAVIOURAL — it observes the symptom, never the setting. Docs can tell an
-- integrator to DECLARE it (the Rojo half works); no code can ever assert from
-- the property itself that it was declared. `iasPlayerScriptsActive()` below is
-- the closest available reading, and it reads an artifact, not the flag.
--
-- ENGINE TRUTH 5 — CAS PRIORITY AND InputContext.Priority ARE NOT ONE
-- ARBITRATION SPACE (measured live in the showcase 2026-08-14, four readings in
-- one session). A sinking `ContextActionService` binding consumes a key BEFORE
-- any `InputContext` is offered it, at ANY priority: a CAS Sink at priority 100
-- beat a Facet `InputContext` at priority 10000 with `Sink = true` (the probe
-- fired twice; the InputContext action never fired). Unbinding the CAS action
-- made the identical presses reach the InputContext immediately.
--
-- The consequence is the one that matters for design: THERE IS NO NUMBER a
-- framework can put on an `InputContext` that takes a key back from a legacy
-- CoreScript CAS binding. `RbxCameraKeypress` (Left/Right/I/O, priority 2000,
-- Sink) is therefore un-outrankable from IAS. A claim built at priority 10000 was
-- measured inert and REMOVED rather than shipped (`3eb97fb`).
--
-- THE RESOLUTION IS TRUTH 2, NOT A NUMBER (director's ruling 2026-08-15). Facet
-- does not reach into ContextActionService — `src/client/roblox_input.luau`
-- deliberately never re-implements or reaches into arbitration. The
-- Input Action System is the whole story, and the property is what puts Roblox's
-- own player scripts on it: with `Workspace.PlayerScriptsUseInputActionSystem`
-- enabled the camera's keys are an `InputContext` like everyone else's, so
-- ordinary priority arbitration decides them and truth 5 stops biting. Truth 5
-- stays written down because it is exactly WHY the property is a requirement
-- rather than a nicety: with the flag off there is no in-framework remedy at all.
-- With the flag off, the camera still owns the arrow keys.
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
-- docs/guide/07-input.md.

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
		.. "arbitrate (focus-aware first-responder model, in progress).",
	"2. Workspace.PlayerScriptsUseInputActionSystem (which puts Roblox's own "
		.. "player scripts — camera included — onto IAS so they join normal "
		.. "priority arbitration) is REQUIRED by Facet. It is present in the "
		.. "reflection database but NOT scriptable, so no code on any build can "
		.. "read or set it (re-probed 0.734.0.7340915, 2026-08-15: a plain read "
		.. "says 'not a valid member', GetPropertyChangedSignal says 'not a "
		.. "scriptable property', and a made-up name says 'not a valid property "
		.. "name' — three different sentences). Only the READ is closed: a Rojo "
		.. "project file CAN declare it with the rokit-pinned toolchain "
		.. "(tools/build_places.sh:12-16, measured 2026-08-15), which is how every "
		.. "Facet place and both Rascal Rally places now carry it — so it need "
		.. "never be a hand-ticked Studio property again. Every probe here is "
		.. "still behavioral: it observes the symptom, never the setting.",
	"3. GuiService.CoreGuiNavigationEnabled re-enables itself if scripted off "
		.. "(CoreScripts fight back) and is not the eater anyway; do not rely on "
		.. "scripting it off.",
	"5. ContextActionService priority and InputContext.Priority are NOT one "
		.. "arbitration space (measured live 2026-08-14): a sinking CAS binding at "
		.. "priority 100 consumed Left/Right while a Facet InputContext at priority "
		.. "10000 with Sink=true never fired, and unbinding the CAS action let the "
		.. "identical presses through at once. So no number outranks a legacy "
		.. "CoreScript binding from IAS — RbxCameraKeypress (Left/Right/I/O, prio "
		.. "2000, Sink) is un-outrankable that way. THE FIX IS TRUTH 2, NOT A "
		.. "NUMBER: enable PlayerScriptsUseInputActionSystem and the camera's keys "
		.. "become an InputContext that ordinary arbitration can outrank. (A "
		.. "BindActionAtPriority claim of our OWN action above 2000, unbound on "
		.. "release, was also measured to work and to hand the key straight back — "
		.. "but Facet does not reach into ContextActionService, so it is not the "
		.. "route; roblox_input.luau never re-implements arbitration.)",
	"6. cameraKeysContended() reports whether ANY ContextActionService binding "
		.. "currently holds an arrow key. Measured live 2026-08-15 in a default "
		.. "place: RbxCameraKeypress holds Left/Right/I/O at priority 2000 while "
		.. "jumpAction was NOT bound at all — so legacyStackActive() answered false "
		.. "in the same session the arrows were owned. The two probes read "
		.. "different bindings and neither substitutes for the other.",
	"4. Tab is the CoreGui PLAYERS LIST shortcut, and while that CoreGuiType is "
		.. "enabled (the default) the platform documents it as reserved — so "
		.. "Facet's Tab/Shift+Tab focus traversal will not receive it. Roblox "
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

-- The default contexts the engine's own player scripts register once
-- `Workspace.PlayerScriptsUseInputActionSystem` is Enabled. They do not exist at
-- all under the legacy stack, which is what makes their presence a behavioural
-- read of a property no code may read. Consumers already rely on this shape:
-- Rascal Rally holds exactly these three disabled because they bind gamepad
-- codes for an avatar its kart game never controls.
local DEFAULT_IAS_CONTEXTS = { "CharacterContext", "CameraContext", "VehicleContext" }

-- Does the ENGINE's own player-script stack run on the Input Action System?
--
-- ENGINE TRUTH 2 says the deciding flag is not script-readable, so like every
-- other probe here this is behavioural: it looks for
-- `Player.InputContexts.{CharacterContext,CameraContext,VehicleContext}`, the
-- instances the IAS player scripts create and the legacy ones never do. `true`
-- is a fact about this client right now; ANY ONE of the three is enough, since a
-- game may have removed the others.
--
-- THE FALSE NEGATIVE IS THE HONEST RESIDUAL, and it is why the wait exists. The
-- folder replicates at player-add, so a bootstrap that asks the instant it runs
-- can miss it. `waitSeconds` (default 1) bounds one `WaitForChild` retry —
-- bounded because an unbounded wait in a place where the folder never arrives
-- would hang the caller's bootstrap forever (observed live 2026-07-21 for the
-- PlayerModule wait below). A miss degrades to the pre-existing legacy path,
-- which is today's behaviour: slower, not wronger.
--
-- `player` (optional) is the instance to probe; defaults to the local player.
-- Returns false headless / off the live client.
function gamepad_contention.iasPlayerScriptsActive(player: any?, waitSeconds: number?): boolean
	local ok, active = pcall(function(): boolean
		local subject = player
		if subject == nil then
			subject = game:GetService("Players").LocalPlayer
		end
		local folder = subject:FindFirstChild("InputContexts")
		if folder == nil then
			folder = subject:WaitForChild("InputContexts", waitSeconds or 1)
		end
		if folder == nil then
			return false
		end
		for _, name in DEFAULT_IAS_CONTEXTS do
			local context = folder:FindFirstChild(name)
			-- ClassName rather than IsA: the check has to run against a plain
			-- table in a headless spec, and InputContext has no subclasses. A
			-- same-named Folder must NOT answer true.
			if context ~= nil and context.ClassName == "InputContext" then
				return true
			end
		end
		return false
	end)
	return ok and active == true
end

-- The four codes Facet's focus navigation reads off the keyboard. Compared as
-- STRINGS (`tostring(Enum.KeyCode.Left)` == "Enum.KeyCode.Left") so the matching
-- rule below runs headless, where the `Enum` global does not exist at all.
local ARROW_CODES: { [string]: true } = {
	["Enum.KeyCode.Left"] = true,
	["Enum.KeyCode.Right"] = true,
	["Enum.KeyCode.Up"] = true,
	["Enum.KeyCode.Down"] = true,
}

-- Is ANY ContextActionService binding currently holding an arrow key?
--
-- WHY THIS IS NOT ANSWERED BY legacyStackActive(). Measured live 2026-08-15 in
-- the showcase: `RbxCameraKeypress` held Left/Right/I/O at CAS priority 2000
-- while `jumpAction` was not bound at all (a UI-only place had already called
-- disableLegacyControls). So `legacyStackActive()` returned false in the very
-- session the arrows were owned. Jump and camera are separate bindings from
-- separate CoreScripts; a probe for one says nothing about the other.
--
-- SAME SHAPE AS THE OTHER TWO PROBES, AND THE SAME CONTRACT: it is something a
-- game or a doctor check ASKS, never something Facet announces. It is
-- deliberately not wired to a boot-time warning, because in every place that has
-- not ticked `Workspace.PlayerScriptsUseInputActionSystem` it is true — which is
-- currently every default Studio session — and a warning that fires always is
-- noise that trains people to ignore it. Ask it when arrows look dead.
--
-- It reads the binding directly rather than inferring, so a `true` is a fact
-- about this client right now. A `false` is narrower than it looks: CAS exposes
-- no sink flag through `GetAllBoundActionInfo`, and a key can also be lost to
-- CoreGui (Tab — see `traversalKeyContended`), so `false` means "no CAS action
-- claims an arrow", not "arrows are guaranteed to arrive".
--
-- `boundActionInfo` (optional) is a `GetAllBoundActionInfo()`-shaped table —
-- the same injection seam `disableLegacyControls` offers, so the matching rule
-- can be tested against a recorded live reading. Returns false headless / off the
-- live client, where there is no ContextActionService to ask.
function gamepad_contention.cameraKeysContended(boundActionInfo: any?): boolean
	local bound = boundActionInfo
	if bound == nil then
		local ok, live = pcall(function()
			return game:GetService("ContextActionService"):GetAllBoundActionInfo()
		end)
		if not ok then
			return false
		end
		bound = live
	end
	for _, info in pairs(bound :: any) do
		for _, code in ipairs(info.inputTypes or {}) do
			if ARROW_CODES[tostring(code)] then
				return true
			end
		end
	end
	return false
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
-- and Facet never disables the players list on a consumer's behalf — hiding a
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
-- IT IS A NO-OP WHERE IAS ALREADY OWNS THE PLAYER SCRIPTS (2026-08-18).
-- The `jumpAction` measurement this remedy is built on was taken 2026-07-20,
-- BEFORE any Facet place declared `Workspace.PlayerScriptsUseInputActionSystem`.
-- Under that flag the player scripts ARE IAS contexts: there is no CAS
-- `jumpAction` to unbind, and `PlayerScripts.PlayerModule` is never inserted at
-- all — so the primary path spent its full bounded wait and then the fallback
-- found nothing. Both example bootstraps call this while their tracked project
-- files declare the flag, and nothing said which of the two mechanisms was live.
-- Now the call ASKS FIRST (`iasPlayerScriptsActive`) and returns an explicit
-- inert verdict instead of performing a remedy for a contention that cannot
-- exist. Where the flag is off — the eight tutorial places and any consumer that
-- has not declared it — the behaviour below is unchanged, byte for byte.
--
-- `playerModuleParent` (optional) is the instance that CONTAINS `PlayerModule`;
-- it defaults to the local player's `PlayerScripts`. `player` (optional) is the
-- instance the IAS probe reads; it defaults to the local player. Injecting
-- either lets a caller (or a test) supply the container explicitly.
--
-- Returns `(uncontended, status)`. The boolean is whether it believes ButtonA is
-- now UNCONTENDED; the status says WHY, because the boolean alone cannot
-- distinguish "I disabled the control module" from "there was nothing to
-- disable":
--   * true,  "inert: IAS owns PlayerScripts" — nothing was touched and nothing
--            needed to be; the legacy stack is not running in this place.
--   * true,  "disabled" — the control module was disabled (removes all its CAS
--            binds, jumpAction included).
--   * true,  "unbound" — the narrower jumpAction unbind fallback ran AND the
--            binding is confirmed gone.
--   * false, "unavailable" — neither engine path was reachable (running on the
--            server, in Studio Edit, or headless under Lune — there is no live
--            gamepad to free).
-- The return is a best-belief signal, not an end-to-end proof: only a physical
-- gamepad press can confirm ButtonA now reaches Activate (standing
-- FAIL_ENVIRONMENT rider `physical-device-confirmation`).
--[[ THE PURE HALF OF THE FALLBACK'S VERDICT, so the rule is provable
	without a live ContextActionService. Given the binding table before an unbind
	attempt and after it, did the attempt free `jumpAction`? Both halves matter:
	an action that was never bound was not freed by unbinding it, and an action
	still present afterwards was not freed either. ]]
function gamepad_contention.freedJumpAction(before: { [string]: any }, after: { [string]: any }): boolean
	return before["jumpAction"] ~= nil and after["jumpAction"] == nil
end

function gamepad_contention.disableLegacyControls(playerModuleParent: any?, player: any?): (boolean, string)
	-- DF-9: with the flag on there is no legacy stack to disable. Ask before
	-- acting, and say so — an inert call that reported the same `true` as a real
	-- remedy is how "one of these two mechanisms is dead" went unnoticed.
	if gamepad_contention.iasPlayerScriptsActive(player) then
		return true, "inert: IAS owns PlayerScripts"
	end
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
		return true, "disabled"
	end
	--[[ Fallback: unbind jumpAction directly. Narrower — the rest of the control
		module keeps running — but the specific ButtonA eater is gone.

		AND ONLY IF SOMETHING WAS ACTUALLY FREED. `UnbindAction` on an
		action nobody bound WARNS and returns normally, so the `pcall` succeeded on
		every live client and this answered "ButtonA is uncontended now" whether or
		not a single binding had been removed — the one signal a bootstrap has that
		the remedy worked was true unconditionally, which is worse than no signal.
		The binding table is the fact, and it is already how `describeContention`
		reads the same arbitration space. ]]
	local ok, freed = pcall(function(): boolean
		local ContextActionService = game:GetService("ContextActionService")
		local before = ContextActionService:GetAllBoundActionInfo()
		if before["jumpAction"] == nil then
			return false
		end
		ContextActionService:UnbindAction("jumpAction")
		return gamepad_contention.freedJumpAction(before, ContextActionService:GetAllBoundActionInfo())
	end)
	if ok and freed then
		return true, "unbound"
	end
	return false, "unavailable"
end

return gamepad_contention
