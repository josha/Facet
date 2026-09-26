--!strict
local t = require("./lib/testkit")
local Facet = require("../src") :: any
t.describe("gamepad_contention (client module, headless structural spec)", function()
	t.it("requires cleanly under Lune — no engine global touched at module scope", function()
		local ok, mod = pcall(function()
			return Facet.gamepadContention
		end)
		t.expect(ok).toBe(true)
		t.expect(type(mod)).toBe("table")
		t.expect(type(mod.disableLegacyControls)).toBe("function")
		t.expect(type(mod.describeContention)).toBe("function")
		t.expect(type(mod.legacyStackActive)).toBe("function")
		t.expect(type(mod.cameraKeysContended)).toBe("function")
		t.expect(type(mod.traversalKeyContended)).toBe("function")
		t.expect(type(mod.iasPlayerScriptsActive)).toBe("function")
	end)

	t.it("describeContention() returns a string carrying all three §3 truths and the resolution", function()
		local mod = Facet.gamepadContention
		local text = mod.describeContention()
		t.expect(type(text)).toBe("string")
		t.expect(string.find(text, "jumpAction", 1, true) ~= nil).toBe(true)
		t.expect(string.find(text, "disableLegacyControls", 1, true) ~= nil).toBe(true)
		t.expect(string.find(text, "PlayerScriptsUseInputActionSystem", 1, true) ~= nil).toBe(true)
		t.expect(string.find(text, "CoreGuiNavigationEnabled", 1, true) ~= nil).toBe(true)

		t.expect(string.find(text, "NOT one", 1, true) ~= nil).toBe(true)
		t.expect(string.find(text, "arbitration space", 1, true) ~= nil).toBe(true)
		t.expect(string.find(text, "RbxCameraKeypress", 1, true) ~= nil).toBe(true)
		t.expect(string.find(text, "BindActionAtPriority", 1, true) ~= nil).toBe(true)

		t.expect(string.find(text, "THE FIX IS TRUTH 2, NOT A NUMBER", 1, true) ~= nil).toBe(true)
		t.expect(string.find(text, "REQUIRED by Facet", 1, true) ~= nil).toBe(true)
		t.expect(string.find(text, "NOT scriptable", 1, true) ~= nil).toBe(true)

		t.expect(string.find(text, "a Rojo project file CAN declare it", 1, true) ~= nil).toBe(true)
		t.expect(string.find(text, "cameraKeysContended", 1, true) ~= nil).toBe(true)
	end)

	t.it("disableLegacyControls() is guarded: headless it returns false, never throws", function()
		local mod = Facet.gamepadContention
		local ok, result = pcall(function()
			return mod.disableLegacyControls()
		end)
		t.expect(ok).toBe(true)
		t.expect(result).toBe(false)
	end)

	t.it("legacyStackActive() is a guarded probe: headless it returns false, never throws", function()
		local mod = Facet.gamepadContention
		local ok, result = pcall(function()
			return mod.legacyStackActive()
		end)
		t.expect(ok).toBe(true)
		t.expect(result).toBe(false)
	end)

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

	t.it("cameraKeysContended() sees the camera holding the arrows in a live reading", function()
		local mod = Facet.gamepadContention
		t.expect(mod.cameraKeysContended(LIVE_BOUND_ACTIONS)).toBe(true)
	end)

	t.it("cameraKeysContended() is false once the camera's binding leaves CAS", function()
		local mod = Facet.gamepadContention
		local withoutCamera = {}
		for name, info in pairs(LIVE_BOUND_ACTIONS) do
			if name ~= "RbxCameraKeypress" then
				withoutCamera[name] = info
			end
		end
		t.expect(mod.cameraKeysContended(withoutCamera)).toBe(false)
	end)

	t.it("cameraKeysContended() answers each of the four arrows, not just Left/Right", function()
		local mod = Facet.gamepadContention
		for _, code in { "Enum.KeyCode.Up", "Enum.KeyCode.Down", "Enum.KeyCode.Left", "Enum.KeyCode.Right" } do
			t.expect(mod.cameraKeysContended({ Whatever = { inputTypes = { code } } })).toBe(true)
		end
		t.expect(mod.cameraKeysContended({ Whatever = { inputTypes = { "Enum.KeyCode.W" } } })).toBe(false)
	end)

	t.it("cameraKeysContended() is a guarded probe: headless it returns false, never throws", function()
		local mod = Facet.gamepadContention
		local ok, result = pcall(function()
			return mod.cameraKeysContended()
		end)
		t.expect(ok).toBe(true)
		t.expect(result).toBe(false)
	end)

	t.it("cameraKeysContended() tolerates a bound action with no inputTypes", function()
		local mod = Facet.gamepadContention
		t.expect(mod.cameraKeysContended({ Bare = {} })).toBe(false)
	end)

	local function fakePlayer(contextNames: { string }?): any
		local folder = { children = {} :: { [string]: any } }
		for _, name in contextNames or {} do
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

	t.it("iasPlayerScriptsActive() sees the engine's default IAS contexts", function()
		local mod = Facet.gamepadContention
		t.expect(mod.iasPlayerScriptsActive(fakePlayer({ "CharacterContext", "CameraContext", "VehicleContext" })))
			.toBe(true)
		t.expect(mod.iasPlayerScriptsActive(fakePlayer({ "CameraContext" }))).toBe(true)
	end)

	t.it("iasPlayerScriptsActive() is false under the legacy stack, and headless", function()
		local mod = Facet.gamepadContention
		t.expect(mod.iasPlayerScriptsActive(fakePlayer(nil))).toBe(false)
		t.expect(mod.iasPlayerScriptsActive(fakePlayer({}))).toBe(false)
		local imposter = fakePlayer({ "CharacterContext" })
		local folder = imposter.FindFirstChild(imposter, "InputContexts")
		folder.children.CharacterContext = { ClassName = "Folder" }
		t.expect(mod.iasPlayerScriptsActive(imposter)).toBe(false)
		local ok, result = pcall(function()
			return mod.iasPlayerScriptsActive()
		end)
		t.expect(ok).toBe(true)
		t.expect(result).toBe(false)
	end)

	t.it("disableLegacyControls() is INERT when IAS owns the player scripts (DF-9)", function()
		local mod = Facet.gamepadContention
		local touched = false
		local parent = {
			WaitForChild = function()
				touched = true
				return {}
			end,
		}
		local freed, status =
			mod.disableLegacyControls(parent, fakePlayer({ "CharacterContext", "CameraContext", "VehicleContext" }))
		t.expect(freed).toBe(true)
		t.expect(status).toBe("inert: IAS owns PlayerScripts")
		t.expect(touched).toBe(false)
	end)

	t.it("disableLegacyControls() is UNCHANGED where the legacy stack still runs", function()
		local mod = Facet.gamepadContention
		local freed, status = mod.disableLegacyControls(nil, fakePlayer(nil))
		t.expect(freed).toBe(false)
		t.expect(status).toBe("unavailable")
	end)

	t.it("disableLegacyControls(injectedParent) also stays guarded headless", function()
		local mod = Facet.gamepadContention
		local stubParent = {
			WaitForChild = function()
				return {}
			end,
		}
		local ok, result = pcall(function()
			return mod.disableLegacyControls(stubParent)
		end)
		t.expect(ok).toBe(true)
		t.expect(result).toBe(false)
	end)
end)

t.describe("inputPriority: the band Facet's own input contexts live in", function()
	t.it("every Facet binding sits between belowControls and aboveFacet", function()
		local fs = require("@lune/fs")
		local band = Facet.inputPriority
		t.expect(table.isfrozen(band)).toBe(true)
		local lowest, highest = math.huge, -math.huge
		for _, file in fs.readDir("src/ui") do
			if string.sub(file, -6) == ".luau" then
				local source = fs.readFile("src/ui/" .. file)
				for value in string.gmatch(source, "[pP]riority = (%d+)") do
					local number = tonumber(value) :: number
					lowest, highest = math.min(lowest, number), math.max(highest, number)
				end
			end
		end
		t.expect(band.belowControls < lowest).toBe(true)
		t.expect(band.aboveFacet > highest).toBe(true)
	end)
end)
