--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	local Facet = require("../src") :: any
	verifyHarness:suite("gamepad_contention (client module, headless structural spec)", function()
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

		verifyHarness:case("cameraKeysContended() sees the camera holding the arrows in a live reading", {
			id = "native_gamepad_contention::gamepad_contention (client module, headless structural spec)::cameraKeysContended() sees the camera holding the arrows in a live reading",
			run = function()
				local mod = Facet.gamepadContention
				Verify.expect((mod.cameraKeysContended(LIVE_BOUND_ACTIONS))):toBe(true)
			end,
		})

		verifyHarness:case("cameraKeysContended() is false once the camera's binding leaves CAS", {
			id = "native_gamepad_contention::gamepad_contention (client module, headless structural spec)::cameraKeysContended() is false once the camera's binding leaves CAS",
			run = function()
				local mod = Facet.gamepadContention
				local withoutCamera = {}
				for name, info in pairs(LIVE_BOUND_ACTIONS) do
					if name ~= "RbxCameraKeypress" then
						withoutCamera[name] = info
					end
				end
				Verify.expect((mod.cameraKeysContended(withoutCamera))):toBe(false)
			end,
		})

		verifyHarness:case("cameraKeysContended() answers each of the four arrows, not just Left/Right", {
			id = "native_gamepad_contention::gamepad_contention (client module, headless structural spec)::cameraKeysContended() answers each of the four arrows, not just Left/Right",
			run = function()
				local mod = Facet.gamepadContention
				for _, code in { "Enum.KeyCode.Up", "Enum.KeyCode.Down", "Enum.KeyCode.Left", "Enum.KeyCode.Right" } do
					Verify.expect((mod.cameraKeysContended({ Whatever = { inputTypes = { code } } }))):toBe(true)
				end
				Verify.expect((mod.cameraKeysContended({ Whatever = { inputTypes = { "Enum.KeyCode.W" } } })))
					:toBe(false)
			end,
		})

		verifyHarness:case("cameraKeysContended() is a guarded probe: headless it returns false, never throws", {
			id = "native_gamepad_contention::gamepad_contention (client module, headless structural spec)::cameraKeysContended() is a guarded probe: headless it returns false, never throws",
			run = function()
				local mod = Facet.gamepadContention
				local ok, result = pcall(function()
					return mod.cameraKeysContended()
				end)
				Verify.expect(ok):toBe(true)
				Verify.expect(result):toBe(false)
			end,
		})

		verifyHarness:case("cameraKeysContended() tolerates a bound action with no inputTypes", {
			id = "native_gamepad_contention::gamepad_contention (client module, headless structural spec)::cameraKeysContended() tolerates a bound action with no inputTypes",
			run = function()
				local mod = Facet.gamepadContention
				Verify.expect((mod.cameraKeysContended({ Bare = {} }))):toBe(false)
			end,
		})
	end)
end
