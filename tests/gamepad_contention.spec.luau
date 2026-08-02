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
	end)

	it("describeContention() returns a string carrying all three §3 truths", function()
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
