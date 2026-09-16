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

-- Execute the actual focus-corner branch with engine-shaped corner objects.
-- A per-corner UICorner's uniform alias does not describe its painted shape.
local focusSource = fs.readFile("src/client/screen_focus_visual.luau")
local focusFirst = assert(focusSource:find("local realCorner = host:FindFirstChildOfClass", 1, true))
local focusLast = assert(focusSource:find("\n\t\t\t\t\tend\n\t\t\t\t\tlocal f = float", focusFirst, true))
local syncFocus = luau.load(
	"return function(host, float, instance, handle, snapshot, style, UDim, Instance)\n"
		.. focusSource:sub(focusFirst, focusLast - 1)
		.. "\nend"
)()
t.describe("focus ring corner synchronization", function()
	t.it("retains all four segment corners when an already visible ring changes selection or theme", function()
		local source = { CornerRadius = rb.UDim.new(0.5, 0) }
		local dest = { CornerRadius = rb.UDim.new(0.5, 0) }
		local host = {
			FindFirstChildOfClass = function()
				return source
			end,
		}
		local float = {
			FindFirstChildOfClass = function()
				return dest
			end,
		}
		for _, radius in { 4, 0, 12 } do
			source.TopLeftRadius, source.BottomLeftRadius = rb.UDim.new(0, 0), rb.UDim.new(0, 0)
			source.TopRightRadius, source.BottomRightRadius = rb.UDim.new(0, radius), rb.UDim.new(0, radius)
			syncFocus(host, float, host, {}, function()
				return nil
			end, {}, rb.UDim, {})
			t.expect(dest.TopLeftRadius.Offset).toBe(0)
			t.expect(dest.BottomLeftRadius.Offset).toBe(0)
			t.expect(dest.TopRightRadius.Offset).toBe(radius)
			t.expect(dest.BottomRightRadius.Offset).toBe(radius)
		end
	end)
	t.it("uses a square theme highlight for unrounded skin art instead of the native button radius", function()
		local dest = {}
		local host = {
			FindFirstChildOfClass = function()
				return nil
			end,
		}
		local float = {
			FindFirstChildOfClass = function()
				return dest
			end,
		}
		syncFocus(host, float, {}, { nativeSurface = "control" }, function()
			return { radii = { control = 4, selection = 0 } }
		end, {}, rb.UDim, {})
		t.expect(dest.CornerRadius.Offset).toBe(0)
	end)
end)
