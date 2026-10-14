--!strict
local Lute = require("../../tools/vendor/verify/src/lute")

local requireHost = (require :: unknown) :: (string) -> unknown

local function new(): Lute.Loader
	return Lute.loader.new({
		aliases = { repo = "" },
		hostPaths = { "tools/vendor/", "tools/facet/" },
		requireHost = function(module: string): unknown
			return requireHost("../../" .. module)
		end,
	})
end

return { new = new }
