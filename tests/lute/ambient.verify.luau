--!strict
local Verify = require("../../tools/vendor/verify/src/core")
local Lute = require("../../tools/vendor/verify/src/lute")

return function(harness: Verify.Harness)
	harness:case("ambient lookup reads the game global without environment access", function()
		local model = { Name = "Game" }
		local loader = Lute.loader.new({
			globals = { game = model },
			transform = function(_path, source)
				return "local getfenv = function() error('environment access is forbidden') end\n" .. source
			end,
		})
		local lookup = loader.require("src/ui/ambient.luau")
		assert(type(lookup) == "function")
		local read = lookup :: () -> unknown
		Verify.expect(read()):toBe(model)
	end)
	harness:case("ambient lookup remains absent under Lute", function()
		local loader = Lute.loader.new()
		local lookup = loader.require("src/ui/ambient.luau")
		assert(type(lookup) == "function")
		local read = lookup :: () -> unknown
		Verify.expect(read()):toBeNil()
	end)
end
