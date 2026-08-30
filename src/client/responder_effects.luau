--!strict
-- Responder engine effects (CLIENT-ONLY). The presenter's first-
-- responder model (passive vs engaged-exclusive surfaces) is engine-free and
-- resolves purely through IAS InputContext priority + Sink. This module is the
-- thin CLIENT-LOCAL seam that applies the one engine-level side effect the
-- headless presenter cannot: while an EXCLUSIVE (sinking) Facet surface is up,
-- hide the mobile touch controls so the thumbstick + jump button do not sit
-- under the surface. It observes the presenter's `exclusiveSurfaceActive`
-- readable and drives `GuiService.TouchControlsEnabled` (the current, non-
-- deprecated replacement for `UserInputService.ModalEnabled` — platform
-- research 2026-07-21), restoring the prior value on release.
--
-- DEFERRED IN v1 (pending a live Studio probe): this module does NOT
-- touch `GuiService.SelectedObject`. `SelectedObject` and IAS are parallel,
-- undocumented-linkage systems (research Open risk 4); driving engine gamepad
-- focus alongside Facet's own focus graph risks a double-drive, so it waits on
-- a probe. `TouchControlsEnabled` as the modal touch recipe is inferred from
-- the effect and itself carries a physical-touch-device confirmation rider
-- (research Open risk 6).
--
-- REQUIRE-SAFE: nothing at module scope touches an engine global, so this file
-- `require()`s cleanly under Lune and in Studio Edit. Every engine call lives
-- inside a function and is `pcall`-guarded, so binding it off the live client
-- (server, Edit, headless) never throws — the observer still runs; only the
-- engine write no-ops. Like `gamepad_contention`, it is deliberately NOT
-- exported on the `Facet` table (see docs/guide/07-input.md §7.3): require it
-- directly from a client script.

local responder_effects = {}

-- read GuiService.TouchControlsEnabled, or nil off the live client. A module
-- FIELD rather than a local so the headless suite can drive the refcount below
-- against a fake property (the `preferred_text`/`text_premeasure` seam idiom).
function responder_effects.readTouchControls(): boolean?
	local ok, value = pcall(function(): boolean
		return game:GetService("GuiService").TouchControlsEnabled
	end)
	if ok then
		return value
	end
	return nil
end

-- attempt a write; returns whether the CALL succeeded (see `acquire` for why
-- that is not the same as "the property took the value")
function responder_effects.writeTouchControls(on: boolean): boolean
	return (pcall(function()
		game:GetService("GuiService").TouchControlsEnabled = on
	end))
end

local function readTouchControls(): boolean?
	return responder_effects.readTouchControls()
end
local function writeTouchControls(on: boolean): boolean
	return responder_effects.writeTouchControls(on)
end

--[[ THE SUPPRESSION IS REFCOUNTED, BECAUSE THE PROPERTY IS SHARED.

	`GuiService.TouchControlsEnabled` is ONE engine property and `bind` can be
	called more than once — a game with two Facet targets, or a rebind across a
	scene change. Held per binder, the second binder read the value the FIRST one
	had already suppressed, recorded `false` as "the prior value", and restored
	the controls to HIDDEN when it released: the touch controls stayed gone for
	the rest of the session with every binder believing it had put them back.

	And pcall success is not proof a write landed — an engine that refuses the
	assignment (or a platform where the property is inert) succeeds and keeps the
	old value — so the acquire confirms by READING BACK, and the release re-reads
	before restoring so a host that took the property back while we held it keeps
	it. The count and the remembered value live at module scope because the thing
	they describe does. ]]
local suppressCount = 0
local priorValue: boolean? = nil

local function acquireSuppression(): boolean
	if suppressCount == 0 then
		priorValue = readTouchControls()
		if not writeTouchControls(false) then
			return false
		end
		local landed = readTouchControls()
		if landed ~= nil and landed ~= false then
			return false -- the call succeeded and the property did not move
		end
	end
	suppressCount += 1
	return true
end

local function releaseSuppression()
	if suppressCount == 0 then
		return
	end
	suppressCount -= 1
	if suppressCount > 0 then
		return
	end
	local current = readTouchControls()
	if current == nil or current == false then
		writeTouchControls(if priorValue == nil then true else priorValue)
	end
	priorValue = nil
end

-- diagnostics/tests: how many live binders are holding the suppression
function responder_effects.suppressionCount(): number
	return suppressCount
end

-- bind(core, presenter): observe the presenter's exclusive-surface readable and
-- hide the mobile touch controls while an exclusive surface is up, restoring the
-- PRIOR value on release. Returns a disconnect function; call it to unbind and
-- restore. Safe to call from any context (no-ops where there is no live client).
function responder_effects.bind(core: any, presenter: any): () -> ()
	-- this binder's OWN share of the module-level suppression, so a binder can
	-- never take two references or release one it does not hold
	local suppressing = false

	local function apply(active: boolean)
		if active and not suppressing then
			suppressing = acquireSuppression()
		elseif not active and suppressing then
			releaseSuppression()
			suppressing = false
		end
	end

	local disconnect = core:observe(presenter.exclusiveSurfaceActive, apply)
	apply(presenter.exclusiveSurfaceActive:get()) -- reconcile the current state

	return function()
		if type(disconnect) == "function" then
			disconnect()
		end
		-- restore on unbind so we never leave the touch controls hidden — but only
		-- once the LAST holder is gone
		if suppressing then
			releaseSuppression()
			suppressing = false
		end
	end
end

return responder_effects
