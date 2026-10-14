--!strict
local Loader = require("./loader")

local twin = Loader.new()

return {
	core = twin.require("src/vendor/compose/core") :: typeof(require("../../src/vendor/compose/core")),
	roblox = twin.require("src/vendor/compose/roblox") :: typeof(require("../../src/vendor/compose/roblox")),
}
