--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	local Roblox = require("@lune/roblox")
	local engineModule = require("./lib/native_engine")

	verifyHarness:suite("native enum fixture", function()
		verifyHarness:case("resolves names and values while preserving native enum items", {
			id = "native_engine_enums::native enum fixture::resolves names and values while preserving native enum items",
			run = function()
				local engine = engineModule.new()
				local keyCodes = engine.types.Enum.KeyCode
				Verify.expect((keyCodes:FromName("Space"))):toBe(Roblox.Enum.KeyCode.Space)
				Verify.expect((keyCodes:FromValue(Roblox.Enum.KeyCode.Space.Value))):toBe(Roblox.Enum.KeyCode.Space)
				Verify.expect((keyCodes:FromValue(0))):toBe((Roblox.Enum.KeyCode :: any).Unknown)
				Verify.expect((keyCodes:FromName("MissingKey"))):toBe(nil)
				Verify.expect((keyCodes:FromValue(-100))):toBe(nil)
				Verify.expect(keyCodes.Space):toBe(Roblox.Enum.KeyCode.Space)
				Verify.expect(#keyCodes:GetEnumItems()):toBe(#Roblox.Enum.KeyCode:GetEnumItems())
				Verify.expect(engine.types.Enum.KeyCode):toBe(keyCodes)
				local items = keyCodes:GetEnumItems()
				table.clear(items)
				Verify.expect(#keyCodes:GetEnumItems() > 0):toBe(true)
				Verify.expect((engine.types.Enum.UserInputType:FromName("Touch"))):toBe(Roblox.Enum.UserInputType.Touch)
			end,
		})
	end)
end
