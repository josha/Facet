--!strict
local Verify = require("../tools/vendor/verify/src/core")
local VerifyRoblox = require("../tools/vendor/verify/src/roblox")
local Facet = require("../src")
local Compose = require("../src/vendor/compose/core")
local Roblox = require("../src/vendor/compose/roblox")
local engines = require("./lib/native_engine")
local Navigation = require("../src/ui/navigation_props")

return function(harness: Verify.Harness)
	harness:case("the selection fill lands on the initial segment and slides later in scale", {
		limitations = {
			"Verify does not size an automatic ScrollingFrame from offset descendants inside a Folder. In Studio an offset-sized fill on the last flex-filled segment grows the strip by its padding every frame; scale components do not feed AutomaticSize (https://create.roblox.com/docs/reference/engine/classes/GuiObject#AutomaticSize).",
		},
		run = function(check)
			local engine, bridge = engines.new()
			check:defer(function()
				bridge.close()
			end)
			local runtime = Roblox.createRuntime(engine)
			check:defer(function()
				runtime:dispose()
			end)
			local Host = runtime.constructors
			local UI = Facet.controls(runtime, { types = engine.types })
			local selected = Compose.cell("sprint")
			local target = engine.new("Folder")
			local stop = runtime.mount(function()
				local spec: Navigation.SinglePickerSpec<string> = {
					style = "segmented",
					selected = selected,
					options = {
						{ value = "comet", label = "Comet coupe" },
						{ value = "trail", label = "Trail rover" },
						{ value = "sprint", label = "Sprint kart" },
					},
					Size = engine.types.UDim2.fromOffset(0, 50),
					AutomaticSize = engine.types.Enum.AutomaticSize.X,
				}
				return Host.ScreenGui {
					UI.Picker "Vehicle"(spec),
				}
			end, target)
			check:defer(stop)
			local rawPicker: VerifyRoblox.Instance = assert(target:FindFirstChild("Vehicle", true))
			local layout = assert(rawPicker:FindFirstChildWhichIsA("UIListLayout"))
			local unit = assert(rawPicker:FindFirstChild("SlideUnit", true))
			local fill: Frame = assert(target:FindFirstChild("SelectionFill", true))
			local poke, V2 = engine.environment.poke, engine.types.Vector2
			local origin = V2.new(103, 103)
			local whole = V2.new(400, 44)
			poke(unit, "AbsolutePosition", origin)
			poke(unit, "AbsoluteSize", whole)
			local x = origin.X
			for _, entry in
				{ { name = "comet", width = 150 }, { name = "trail", width = 120 }, { name = "sprint", width = 122 } }
			do
				local button = assert(rawPicker:FindFirstChild(entry.name))
				poke(button, "AbsolutePosition", V2.new(x, origin.Y))
				poke(button, "AbsoluteSize", V2.new(entry.width, 44))
				x += entry.width + 4
			end
			poke(layout, "AbsoluteContentSize", whole)
			for _ = 1, 60 do
				engine.heartbeat:Fire(1 / 60)
				check:expect(fill.Visible):toBe(true)
				check:expect(fill.Position.X.Scale):toBeFloat32(278 / 400)
				check:expect(fill.Size.X.Scale):toBeFloat32(122 / 400)
			end
			selected:set("comet")
			check:expect(fill.Position.X.Scale):toBeFloat32(278 / 400)
			engine.heartbeat:Fire(1 / 60)
			check:expect(fill.Position.X.Scale):toBeGreaterThan(0)
			check:expect(fill.Position.X.Scale):toBeLessThan(278 / 400)
			for _ = 1, 120 do
				engine.heartbeat:Fire(1 / 60)
			end
			check:expect(fill.Position.X.Scale):toBe(0)
			selected:set("sprint")
			for _ = 1, 120 do
				engine.heartbeat:Fire(1 / 60)
			end
			check:expect(fill.Position.X.Offset):toBe(0)
			check:expect(fill.Position.Y.Offset):toBe(0)
			check:expect(fill.Size.X.Offset):toBe(0)
			check:expect(fill.Size.Y.Offset):toBe(0)
			check:expect(fill.Position.X.Scale):toBeFloat32(278 / 400)
			check:expect(fill.Size.X.Scale):toBeFloat32(122 / 400)
			check:expect(fill.Size.Y.Scale):toBeFloat32(1)
		end,
	})
end
