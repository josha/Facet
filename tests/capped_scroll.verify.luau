--!strict

local Verify = require("../tools/vendor/verify/src/core")
local VerifyRoblox = require("../tools/vendor/verify/src/roblox")
local Facet = require("../src")
local engines = require("./lib/native_engine")

return function(harness: Verify.Harness)
	local Compose = Facet.Compose
	local function mount(context: Verify.Context, body: (Facet.Controls, Facet.Host) -> Instance)
		local engine = engines.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		context:defer(function()
			runtime:dispose()
		end)
		local UI = Facet.controls(runtime, {
			types = engine.types,
			services = { GuiService = engine.new("GuiService") },
		})
		local root: Instance? = nil
		local stop = runtime.mount(function()
			local Host = runtime.constructors :: Facet.Host
			root = body(UI, Host)
			return root
		end, engine.new("ScreenGui"))
		context:defer(stop)
		return assert(root), engine
	end

	local builders: { [string]: (Facet.Controls, Facet.ValueNumber?, Facet.ValueNumber?) -> GuiObject } = {
		ScrollView = function(UI, width, height)
			return UI.ScrollView { height = "hug", maxWidth = width, maxHeight = height }
		end,
		VStack = function(UI, width, height)
			return UI.VStack { maxWidth = width, maxHeight = height }
		end,
		HStack = function(UI, width, height)
			return UI.HStack { maxWidth = width, maxHeight = height }
		end,
		ZStack = function(UI, width, height)
			return UI.ZStack { maxWidth = width, maxHeight = height }
		end,
		AdaptiveStack = function(UI, width, height)
			return UI.AdaptiveStack { maxWidth = width, maxHeight = height }
		end,
	}

	for name, build in builders do
		harness:case(`{name} binds both native maximum dimensions without changing automatic sizing`, function(context)
			local width, height = Compose.cell(320), Compose.cell(240)
			local root, engine = mount(context, function(UI)
				return build(UI, width, function(use: Facet.Use): number
					return use(height)
				end)
			end)
			assert(root:IsA("GuiObject"))
			local constraint = assert(root:FindFirstChildWhichIsA("UISizeConstraint"))
			local E = engine.types.Enum
			Verify.expect(constraint.MaxSize.X):toBe(320)
			Verify.expect(constraint.MaxSize.Y):toBe(240)
			Verify.expect(root.AutomaticSize)
				:toBe(if name == "ScrollView" or name == "AdaptiveStack" then E.AutomaticSize.Y else E.AutomaticSize.XY)
			width:set(180)
			height:set(0)
			Verify.expect(constraint.MaxSize.X):toBe(180)
			Verify.expect(constraint.MaxSize.Y):toBe(0)
			Verify.expect(root:FindFirstChildWhichIsA("UISizeConstraint")):toBe(constraint)
			if root:IsA("ScrollingFrame") then
				Verify.expect(root.AutomaticCanvasSize):toBe(E.AutomaticSize.Y)
				Verify.expect(root.CanvasSize.Y.Offset):toBe(0)
				Verify.expect(root.ScrollingDirection):toBe(E.ScrollingDirection.Y)
			end
		end)

		harness:case(`{name} leaves an omitted maximum dimension unbounded`, function(context)
			for _, heightOnly in { false, true } do
				local root = mount(context, function(UI)
					return build(UI, if heightOnly then nil else 300, if heightOnly then 200 else nil)
				end)
				local constraint = assert(root:FindFirstChildWhichIsA("UISizeConstraint"))
				Verify.expect(constraint.MaxSize.X):toBe(if heightOnly then math.huge else 300)
				Verify.expect(constraint.MaxSize.Y):toBe(if heightOnly then 200 else math.huge)
			end
		end)
	end

	harness:case("ScrollView reserves horizontal scroll bar room within its maximum height", function(context)
		local height = Compose.cell(80)
		local root, engine = mount(context, function(UI)
			return UI.ScrollView { axis = "x", maxWidth = 200, maxHeight = height, ScrollBarThickness = 6 }
		end)
		local constraint = assert(root:FindFirstChildWhichIsA("UISizeConstraint"))
		local layout = assert(root:FindFirstChildWhichIsA("UIListLayout"))
		engine.environment.poke(
			VerifyRoblox.assertInstance(root),
			"AbsoluteWindowSize",
			engine.types.Vector2.new(200, 40)
		)
		engine.environment.poke(
			VerifyRoblox.assertInstance(layout),
			"AbsoluteContentSize",
			engine.types.Vector2.new(400, 40)
		)
		Verify.expect(constraint.MinSize.Y):toBe(46)
		height:set(30)
		Verify.expect(constraint.MinSize.Y):toBe(30)
		Verify.expect(constraint.MaxSize.Y):toBe(30)
		engine.environment.poke(
			VerifyRoblox.assertInstance(layout),
			"AbsoluteContentSize",
			engine.types.Vector2.new(100, 20)
		)
		Verify.expect(constraint.MinSize.Y):toBe(0)
	end)

	harness:case("ScrollView rejects nonfinite and negative maxima", function(context)
		for _, value in { -1, math.huge, -math.huge, 0 / 0 } do
			for _, heightOnly in { false, true } do
				local ok, message = pcall(function()
					mount(context, function(UI)
						return UI.ScrollView {
							maxWidth = if heightOnly then nil else value,
							maxHeight = if heightOnly then value else nil,
						}
					end)
				end)
				Verify.expect(ok):toBe(false)
				Verify.expect(tostring(message)):toContain(if heightOnly then "maxHeight" else "maxWidth")
			end
		end
	end)
end
