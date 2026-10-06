--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	local Facet = require("../src") :: any
	verifyHarness:suite("gamepad_contention (client module, headless structural spec)", function()
		verifyHarness:case("requires cleanly under Lune — no engine global touched at module scope", {
			id = "native_gamepad_contention::gamepad_contention (client module, headless structural spec)::requires cleanly under Lune — no engine global touched at module scope",
			run = function()
				local ok, mod = pcall(function()
					return Facet.gamepadContention
				end)
				Verify.expect(ok):toBe(true)
				Verify.expect((type(mod))):toBe("table")
				Verify.expect((type(mod.disableLegacyControls))):toBe("function")
				Verify.expect((type(mod.describeContention))):toBe("function")
				Verify.expect((type(mod.legacyStackActive))):toBe("function")
				Verify.expect((type(mod.cameraKeysContended))):toBe("function")
				Verify.expect((type(mod.traversalKeyContended))):toBe("function")
				Verify.expect((type(mod.iasPlayerScriptsActive))):toBe("function")
			end,
		})

		verifyHarness:case("describeContention() returns a string carrying all three §3 truths and the resolution", {
			id = "native_gamepad_contention::gamepad_contention (client module, headless structural spec)::describeContention() returns a string carrying all three §3 truths and the resolution",
			run = function()
				local mod = Facet.gamepadContention
				local text = mod.describeContention()
				Verify.expect((type(text))):toBe("string")
				Verify.expect(string.find(text, "jumpAction", 1, true) ~= nil):toBe(true)
				Verify.expect(string.find(text, "disableLegacyControls", 1, true) ~= nil):toBe(true)
				Verify.expect(string.find(text, "PlayerScriptsUseInputActionSystem", 1, true) ~= nil):toBe(true)
				Verify.expect(string.find(text, "CoreGuiNavigationEnabled", 1, true) ~= nil):toBe(true)

				Verify.expect(string.find(text, "NOT one", 1, true) ~= nil):toBe(true)
				Verify.expect(string.find(text, "arbitration space", 1, true) ~= nil):toBe(true)
				Verify.expect(string.find(text, "RbxCameraKeypress", 1, true) ~= nil):toBe(true)
				Verify.expect(string.find(text, "BindActionAtPriority", 1, true) ~= nil):toBe(true)

				Verify.expect(string.find(text, "THE FIX IS TRUTH 2, NOT A NUMBER", 1, true) ~= nil):toBe(true)
				Verify.expect(string.find(text, "REQUIRED by Facet", 1, true) ~= nil):toBe(true)
				Verify.expect(string.find(text, "NOT scriptable", 1, true) ~= nil):toBe(true)

				Verify.expect(string.find(text, "a Rojo project file CAN declare it", 1, true) ~= nil):toBe(true)
				Verify.expect(string.find(text, "cameraKeysContended", 1, true) ~= nil):toBe(true)
			end,
		})

		verifyHarness:case("disableLegacyControls() is guarded: headless it returns false, never throws", {
			id = "native_gamepad_contention::gamepad_contention (client module, headless structural spec)::disableLegacyControls() is guarded: headless it returns false, never throws",
			run = function()
				local mod = Facet.gamepadContention
				local ok, result = pcall(function()
					return mod.disableLegacyControls()
				end)
				Verify.expect(ok):toBe(true)
				Verify.expect(result):toBe(false)
			end,
		})

		verifyHarness:case("legacyStackActive() is a guarded probe: headless it returns false, never throws", {
			id = "native_gamepad_contention::gamepad_contention (client module, headless structural spec)::legacyStackActive() is a guarded probe: headless it returns false, never throws",
			run = function()
				local mod = Facet.gamepadContention
				local ok, result = pcall(function()
					return mod.legacyStackActive()
				end)
				Verify.expect(ok):toBe(true)
				Verify.expect(result):toBe(false)
			end,
		})

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

		local function fakePlayer(contextNames: { string }?): any
			local folder = { children = {} :: { [string]: any } }
			local names: { string } = contextNames or {}
			for _, name in names do
				folder.children[name] = { ClassName = "InputContext" }
			end
			function folder.FindFirstChild(_self: any, name: string): any
				return folder.children[name]
			end
			return {
				FindFirstChild = function(_self: any, name: string): any
					return if name == "InputContexts" and contextNames ~= nil then folder else nil
				end,
				WaitForChild = function(): any
					return nil
				end,
			}
		end

		verifyHarness:case("iasPlayerScriptsActive() sees the engine's default IAS contexts", {
			id = "native_gamepad_contention::gamepad_contention (client module, headless structural spec)::iasPlayerScriptsActive() sees the engine's default IAS contexts",
			run = function()
				local mod = Facet.gamepadContention
				Verify.expect(
					(mod.iasPlayerScriptsActive(fakePlayer({ "CharacterContext", "CameraContext", "VehicleContext" })))
				)
					:toBe(true)
				Verify.expect((mod.iasPlayerScriptsActive(fakePlayer({ "CameraContext" })))):toBe(true)
			end,
		})

		verifyHarness:case("iasPlayerScriptsActive() is false under the legacy stack, and headless", {
			id = "native_gamepad_contention::gamepad_contention (client module, headless structural spec)::iasPlayerScriptsActive() is false under the legacy stack, and headless",
			run = function()
				local mod = Facet.gamepadContention
				Verify.expect((mod.iasPlayerScriptsActive(fakePlayer(nil)))):toBe(false)
				Verify.expect((mod.iasPlayerScriptsActive(fakePlayer({})))):toBe(false)
				local imposter = fakePlayer({ "CharacterContext" })
				local folder = imposter.FindFirstChild(imposter, "InputContexts")
				folder.children.CharacterContext = { ClassName = "Folder" }
				Verify.expect((mod.iasPlayerScriptsActive(imposter))):toBe(false)
				local ok, result = pcall(function()
					return mod.iasPlayerScriptsActive()
				end)
				Verify.expect(ok):toBe(true)
				Verify.expect(result):toBe(false)
			end,
		})

		verifyHarness:case("disableLegacyControls() is INERT when IAS owns the player scripts (DF-9)", {
			id = "native_gamepad_contention::gamepad_contention (client module, headless structural spec)::disableLegacyControls() is INERT when IAS owns the player scripts (DF-9)",
			run = function()
				local mod = Facet.gamepadContention
				local touched = false
				local parent = {
					WaitForChild = function()
						touched = true
						return {}
					end,
				}
				local freed, status = mod.disableLegacyControls(
					parent,
					fakePlayer({ "CharacterContext", "CameraContext", "VehicleContext" })
				)
				Verify.expect(freed):toBe(true)
				Verify.expect(status):toBe("inert: IAS owns PlayerScripts")
				Verify.expect(touched):toBe(false)
			end,
		})

		verifyHarness:case("disableLegacyControls() is UNCHANGED where the legacy stack still runs", {
			id = "native_gamepad_contention::gamepad_contention (client module, headless structural spec)::disableLegacyControls() is UNCHANGED where the legacy stack still runs",
			run = function()
				local mod = Facet.gamepadContention
				local freed, status = mod.disableLegacyControls(nil, fakePlayer(nil))
				Verify.expect(freed):toBe(false)
				Verify.expect(status):toBe("unavailable")
			end,
		})

		verifyHarness:case("disableLegacyControls(injectedParent) also stays guarded headless", {
			id = "native_gamepad_contention::gamepad_contention (client module, headless structural spec)::disableLegacyControls(injectedParent) also stays guarded headless",
			run = function()
				local mod = Facet.gamepadContention
				local stubParent = {
					WaitForChild = function()
						return {}
					end,
				}
				local ok, result = pcall(function()
					return mod.disableLegacyControls(stubParent)
				end)
				Verify.expect(ok):toBe(true)
				Verify.expect(result):toBe(false)
			end,
		})
	end)

	verifyHarness:suite("inputPriority: the band Facet's own input contexts live in", function()
		verifyHarness:case("every Facet binding sits between belowControls and aboveFacet", {
			id = "native_gamepad_contention::inputPriority: the band Facet's own input contexts live in::every Facet binding sits between belowControls and aboveFacet",
			run = function()
				local fs = require("@lune/fs")
				local band = Facet.inputPriority
				Verify.expect((table.isfrozen(band))):toBe(true)
				local lowest, highest, seen = math.huge, -math.huge, 0
				for _, file in fs.readDir("src/ui") do
					if string.sub(file, -5) == ".luau" then
						local source = fs.readFile("src/ui/" .. file)
						for value in string.gmatch(source, "[pP]riority = (%d+)") do
							local number = tonumber(value) :: number
							lowest, highest, seen = math.min(lowest, number), math.max(highest, number), seen + 1
						end
					end
				end
				Verify.expect(seen > 50):toBe(true)
				Verify.expect(band.belowControls < lowest):toBe(true)
				Verify.expect(band.aboveFacet > highest):toBe(true)
			end,
		})
	end)
end
