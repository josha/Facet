--!strict
local t = require("./lib/testkit")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local rb = require("@lune/roblox")
local source = fs.readFile("src/client/screen_presentation.luau")
local first = assert(source:find("\tlocal function applyRect(", 1, true))
local last = assert(source:find("\n\t-- the paint half", first, true))
local apply = luau.load(
	"return function(UDim2, Vector2) local engineWriteCount=0; local function hostOriginOf() return 0,0 end; local function applyHitExpander() end; local function refitIconArt() end;\n"
		.. source:sub(first, last - 1)
		.. "\nreturn applyRect end"
)()({
	fromOffset = function(x, y)
		return { X = { Offset = math.floor(x) }, Y = { Offset = math.floor(y) } }
	end,
}, rb.Vector2)
t.describe("motion pixel settling", function()
	for _, pivot in { { 0, 0 }, { 0.5, 0.5 }, { 1, 0 }, { 0, 1 }, { 1, 1 } } do
		for _, size in { { 351, 139 }, { 352, 140 }, { 351, 140 } } do
			t.it(`preserves the resting origin for {size[1]}x{size[2]} at {pivot[1]},{pivot[2]}`, function()
				local instance = { AnchorPoint = rb.Vector2.new(pivot[1], pivot[2]) }
				local handle = {
					instance = instance,
					windowRect = { x = 100, y = 101, w = size[1], h = size[2] },
					motionAnchorCentered = true,
					motionPivotX = pivot[1],
					motionPivotY = pivot[2],
				}
				apply(handle)
				local x = instance.Position.X.Offset - instance.Size.X.Offset * instance.AnchorPoint.X
				local y = instance.Position.Y.Offset - instance.Size.Y.Offset * instance.AnchorPoint.Y
				handle.motionAnchorCentered = nil
				instance.AnchorPoint = rb.Vector2.zero
				apply(handle)
				t.expect(math.abs(x - instance.Position.X.Offset) < 0.001).toBe(true)
				t.expect(math.abs(y - instance.Position.Y.Offset) < 0.001).toBe(true)
			end)
		end
	end
	t.it("reflow cancels a stale focus-ring tween and resizes to the current lift", function()
		local canceled = false
		local float = {
			Parent = {},
			FindFirstChild = function()
				return nil
			end,
		}
		local h = {
			instance = {},
			windowRect = { x = 10, y = 20, w = 330, h = 240 },
			focusRingFloat = float,
			focusFloatGeom = { w = 200, h = 150, t = 2 },
			focusScale = { Scale = 1.05 },
			focusFloatTween = {
				Cancel = function()
					canceled = true
				end,
			},
		}
		apply(h)
		t.expect(canceled).toBe(true)
		t.expect(h.focusFloatGeom.w).toBe(330)
		t.expect(float.Size.X.Offset).toBe(math.floor(330 * 1.05 - 4))
	end)
	t.it("a float ring grows with its node's own paint scale about the pivot", function()
		local float = {
			Parent = {},
			FindFirstChild = function()
				return nil
			end,
		}
		local h = {
			instance = { AnchorPoint = rb.Vector2.new(0.5, 0.5) },
			windowRect = { x = 100, y = 100, w = 200, h = 100 },
			focusRingFloat = float,
			motionScale = { Scale = 1.1 },
			motionAnchorCentered = true,
		}
		apply(h)
		-- 10% of 200x100 about the centre: 10 and 5 px out on each side, less the 2px inset
		t.expect(`{float.Position.X.Offset},{float.Position.Y.Offset}`).toBe("92,97")
		t.expect(`{float.Size.X.Offset}x{float.Size.Y.Offset}`).toBe("216x106")
	end)
end)
