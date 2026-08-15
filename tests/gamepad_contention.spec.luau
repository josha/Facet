--!strict
-- Structural (headless) spec for src/client/gamepad_contention.luau.
--
-- What this CAN prove headless: the module is require-safe (nothing at module
-- scope touches an engine global — the same guarantee the boundary checker
-- assumes of a client module), its two entry points are callable off the live
-- client, and every engine call inside them is pcall-guarded so it returns a
-- verdict instead of throwing when there is no engine.
--
-- What this CANNOT prove (and does not claim to): that disabling the control
-- module actually frees gamepad ButtonA end-to-end. That is a live-engine fact
-- (jumpAction at CAS priority 2000, ui_todo.md §3) with no headless surface, and
-- confirming it needs a physical gamepad — the standing FAIL_ENVIRONMENT rider
-- `physical-device-confirmation` (tools/lune/gate_manifest.luau). See
-- docs/lessons/gamepad-contention-truths.md.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

describe("gamepad_contention (client module, headless structural spec)", function()
	it("requires cleanly under Lune — no engine global touched at module scope", function()
		local ok, mod = pcall(function()
			return require("../src/client/gamepad_contention")
		end)
		expect(ok).toBeTruthy()
		expect(type(mod)).toBe("table")
		expect(type(mod.disableLegacyControls)).toBe("function")
		expect(type(mod.describeContention)).toBe("function")
		expect(type(mod.legacyStackActive)).toBe("function")
		expect(type(mod.cameraKeysContended)).toBe("function")
		expect(type(mod.traversalKeyContended)).toBe("function")
	end)

	-- name keeps its "…carrying all three" prefix on purpose: the gate manifest
	-- greps this transcript line (tools/lune/gate_manifest.luau). The string has
	-- grown past the original three §3 truths — the arbitration truth (5), the
	-- arrow probe (6) and the resolution are asserted below the original block.
	it("describeContention() returns a string carrying all three §3 truths and the resolution", function()
		local mod = require("../src/client/gamepad_contention")
		local text = mod.describeContention()
		expect(type(text)).toBe("string")
		-- truth 1: the ButtonA / jumpAction eater and the remedy
		expect(string.find(text, "jumpAction", 1, true) ~= nil).toBeTruthy()
		expect(string.find(text, "disableLegacyControls", 1, true) ~= nil).toBeTruthy()
		-- truth 2: the Properties-panel-only, unreflectable flag
		expect(string.find(text, "PlayerScriptsUseInputActionSystem", 1, true) ~= nil).toBeTruthy()
		-- truth 3: the CoreGui nav flag that fights back
		expect(string.find(text, "CoreGuiNavigationEnabled", 1, true) ~= nil).toBeTruthy()
		--[[ truth 5 (2026-08-14): the two priority spaces do not compare.

			Measured live in the showcase, four readings in one session: a sinking
			ContextActionService binding at priority 100 consumed Left/Right while a
			LuauUI `InputContext` at priority 10000 with `Sink = true` never fired, and
			unbinding the CAS action let the identical presses through at once. It is
			pinned HERE, in the module this repo already keeps engine input truths in,
			because there is no headless surface for ContextActionService at all —
			which is exactly why a whole ruling was built on the assumption that a
			bigger number would work. What a check can hold is that the truth is still
			written down where the next agent will look for it. ]]
		expect(string.find(text, "NOT one", 1, true) ~= nil).toBeTruthy()
		expect(string.find(text, "arbitration space", 1, true) ~= nil).toBeTruthy()
		expect(string.find(text, "RbxCameraKeypress", 1, true) ~= nil).toBeTruthy()
		expect(string.find(text, "BindActionAtPriority", 1, true) ~= nil).toBeTruthy()
		--[[ …and the resolution, which is the property and not a bigger number
			(director's ruling 2026-08-15). Truth 5 explains WHY the property is a
			requirement rather than a nicety: with the flag off there is no
			in-framework remedy at all, because no InputContext priority outranks a
			CAS binding. Pinned so the ruling cannot quietly fall back out of the
			one string a doctor check prints. ]]
		expect(string.find(text, "THE FIX IS TRUTH 2, NOT A NUMBER", 1, true) ~= nil).toBeTruthy()
		expect(string.find(text, "REQUIRED by LuauUI", 1, true) ~= nil).toBeTruthy()
		expect(string.find(text, "NOT scriptable", 1, true) ~= nil).toBeTruthy()
		-- truth 6: the arrow probe, and that it is not the same reading as truth 1's
		expect(string.find(text, "cameraKeysContended", 1, true) ~= nil).toBeTruthy()
	end)

	it("disableLegacyControls() is guarded: headless it returns false, never throws", function()
		local mod = require("../src/client/gamepad_contention")
		-- no engine here, so both the disable path and the unbind fallback fail
		-- inside their pcalls; the function must swallow that and report false
		-- rather than error out of the caller's bootstrap.
		local ok, result = pcall(function()
			return mod.disableLegacyControls()
		end)
		expect(ok).toBeTruthy()
		expect(result).toBeFalsy()
	end)

	it("legacyStackActive() is a guarded probe: headless it returns false, never throws", function()
		local mod = require("../src/client/gamepad_contention")
		-- no ContextActionService here; the probe's pcall must catch that and
		-- report false (best-effort behavioral probe, not a flag read).
		local ok, result = pcall(function()
			return mod.legacyStackActive()
		end)
		expect(ok).toBeTruthy()
		expect(result).toBe(false)
	end)

	--[[ cameraKeysContended: the arrow-key half of the same story.

		The fixtures below are a VERBATIM transcription of one live reading —
		`ContextActionService:GetAllBoundActionInfo()` in a Play session of
		LuauUI-Showcase on 0.734.0.7340915, 2026-08-15 — because the point of this
		probe is that it matches what the engine actually hands back. Six actions
		were bound; exactly one of them held an arrow.

		The second fixture is the same reading with `RbxCameraKeypress` removed,
		which is what a place running `Workspace.PlayerScriptsUseInputActionSystem`
		gets: the camera's keys move onto an `InputContext` and leave CAS entirely.
		It is also the mutation guard — a probe that answered "contended" off any
		binding at all, or off the PageUp/PageDown/Home/End action sitting right
		next to the camera's, would pass the first case and fail this one. ]]
	local LIVE_BOUND_ACTIONS = {
		RbxCameraKeypress = {
			priorityLevel = 2000,
			inputTypes = {
				"Enum.KeyCode.Left",
				"Enum.KeyCode.Right",
				"Enum.KeyCode.I",
				"Enum.KeyCode.O",
			},
		},
		RbxCameraGamepadZoom = { priorityLevel = 2000, inputTypes = { "Enum.KeyCode.ButtonR3" } },
		ScrollSelectedElement = {
			priorityLevel = 2000,
			inputTypes = {
				"Enum.KeyCode.PageUp",
				"Enum.KeyCode.PageDown",
				"Enum.KeyCode.Home",
				"Enum.KeyCode.End",
			},
		},
		FreecamToggle = { priorityLevel = 1000, inputTypes = { "Enum.KeyCode.P" } },
		RbxCameraThumbstick = { priorityLevel = 2000, inputTypes = { "Enum.KeyCode.Thumbstick2" } },
		EnableKeyboardUINavigation = { priorityLevel = 2000, inputTypes = { "Enum.KeyCode.BackSlash" } },
	}

	it("cameraKeysContended() sees the camera holding the arrows in a live reading", function()
		local mod = require("../src/client/gamepad_contention")
		expect(mod.cameraKeysContended(LIVE_BOUND_ACTIONS)).toBe(true)
	end)

	it("cameraKeysContended() is false once the camera's binding leaves CAS", function()
		local mod = require("../src/client/gamepad_contention")
		local withoutCamera = {}
		for name, info in pairs(LIVE_BOUND_ACTIONS) do
			if name ~= "RbxCameraKeypress" then
				withoutCamera[name] = info
			end
		end
		-- five actions still bound, including one on PageUp/PageDown/Home/End
		expect(mod.cameraKeysContended(withoutCamera)).toBe(false)
	end)

	it("cameraKeysContended() answers each of the four arrows, not just Left/Right", function()
		local mod = require("../src/client/gamepad_contention")
		-- the camera binds Left/Right/I/O, but focus navigation reads all four, so
		-- a game's own CAS binding on Up or Down is the same defect
		for _, code in { "Enum.KeyCode.Up", "Enum.KeyCode.Down", "Enum.KeyCode.Left", "Enum.KeyCode.Right" } do
			expect(mod.cameraKeysContended({ Whatever = { inputTypes = { code } } })).toBe(true)
		end
		expect(mod.cameraKeysContended({ Whatever = { inputTypes = { "Enum.KeyCode.W" } } })).toBe(false)
	end)

	it("cameraKeysContended() is a guarded probe: headless it returns false, never throws", function()
		local mod = require("../src/client/gamepad_contention")
		-- no ContextActionService here; the pcall must catch that and report false
		local ok, result = pcall(function()
			return mod.cameraKeysContended()
		end)
		expect(ok).toBeTruthy()
		expect(result).toBe(false)
	end)

	it("cameraKeysContended() tolerates a bound action with no inputTypes", function()
		local mod = require("../src/client/gamepad_contention")
		expect(mod.cameraKeysContended({ Bare = {} })).toBe(false)
	end)

	it("disableLegacyControls(injectedParent) also stays guarded headless", function()
		local mod = require("../src/client/gamepad_contention")
		-- a stub parent whose WaitForChild yields something require() cannot load
		-- exercises the injection seam; still no throw, still false.
		local stubParent = {
			WaitForChild = function()
				return {}
			end,
		}
		local ok, result = pcall(function()
			return mod.disableLegacyControls(stubParent)
		end)
		expect(ok).toBeTruthy()
		expect(result).toBeFalsy()
	end)
end)
