--!strict
-- Responder engine effects (CLIENT-ONLY; ADR-0014). The presenter's first-
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
-- DEFERRED IN v1 (ADR-0014, pending a live Studio probe): this module does NOT
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

-- read GuiService.TouchControlsEnabled, or nil off the live client
local function readTouchControls(): boolean?
	local ok, value = pcall(function(): boolean
		return game:GetService("GuiService").TouchControlsEnabled
	end)
	if ok then
		return value
	end
	return nil
end

-- write GuiService.TouchControlsEnabled; returns whether the write landed
local function writeTouchControls(on: boolean): boolean
	return (pcall(function()
		game:GetService("GuiService").TouchControlsEnabled = on
	end))
end

-- bind(core, presenter): observe the presenter's exclusive-surface readable and
-- hide the mobile touch controls while an exclusive surface is up, restoring the
-- PRIOR value on release. Returns a disconnect function; call it to unbind and
-- restore. Safe to call from any context (no-ops where there is no live client).
function responder_effects.bind(core: any, presenter: any): () -> ()
	local priorValue: boolean? = nil
	local suppressing = false

	local function apply(active: boolean)
		if active and not suppressing then
			-- entering exclusive: remember the prior value, then hide controls
			priorValue = readTouchControls()
			if writeTouchControls(false) then
				suppressing = true
			end
		elseif not active and suppressing then
			-- leaving exclusive: restore whatever was there before we hid them
			writeTouchControls(if priorValue == nil then true else priorValue)
			suppressing = false
			priorValue = nil
		end
	end

	local disconnect = core:observe(presenter.exclusiveSurfaceActive, apply)
	apply(presenter.exclusiveSurfaceActive:get()) -- reconcile the current state

	return function()
		if type(disconnect) == "function" then
			disconnect()
		end
		-- restore on unbind so we never leave the touch controls hidden
		if suppressing then
			writeTouchControls(if priorValue == nil then true else priorValue)
			suppressing = false
			priorValue = nil
		end
	end
end

return responder_effects
