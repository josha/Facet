--!strict
local t = require("./lib/testkit")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local rb = require("@lune/roblox")
local styling = require("../src/tokens/styling")
local source = fs.readFile("src/client/screen_paint.luau")
local first = assert(source:find("\tlocal function applyCorners(", 1, true))
local last = assert(source:find("\n\t-- A STROKE NOBODY", first, true))
local factory = luau.load(
	"return function(styling, style, snapshot, UDim, Instance) local hasPerCornerRadii=true\n"
		.. source:sub(first, last - 1)
		.. "\nreturn applyCorners end"
)()
t.describe("native corners follow the installed theme", function()
	t.it("resolves an authored panel corner against the current snapshot", function()
		local corner = {}
		local instance = {
			IsA = function()
				return true
			end,
			FindFirstChildOfClass = function()
				return corner
			end,
		}
		local current = { radii = { panel = 0 } }
		local apply = factory(styling, { radii = { panel = 12 } }, function()
			return current
		end, rb.UDim, {})
		local data =
			styling.normalizeCorners({ topLeft = "panel", topRight = "panel", bottomLeft = 0, bottomRight = 0 })
		apply(instance, data, {})
		t.expect(corner.TopLeftRadius.Offset).toBe(0)
		current = { radii = { panel = 20 } }
		apply(instance, data, {})
		t.expect(corner.TopLeftRadius.Offset).toBe(20)
	end)
end)
