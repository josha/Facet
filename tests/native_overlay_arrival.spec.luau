--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type ScreenGuiConstructor = typeof(require("@repo/tools/typecheck/aliases").ScreenGuiConstructor)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	local FixtureRadialTypes = require("../src/ui/radial_types")
	local FixtureNavigationTypes = require("../src/ui/navigation_types")

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local Compose: ComposeModule = Facet.Compose

	local function signal()
		local handlers: { () -> () } = {}
		return {
			Connect = function(_: any, fn: () -> ())
				table.insert(handlers, fn)
				return {
					Disconnect = function()
						local index = table.find(handlers, fn)
						if index then
							table.remove(handlers, index)
						end
					end,
				}
			end,
			fire = function()
				for _, fn in table.clone(handlers) do
					fn()
				end
			end,
			count = function()
				return #handlers
			end,
		}
	end

	local function world(build: (any) -> any)
		local engine = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local gui = engine.new("GuiService")
		local frames = { Heartbeat = signal() }
		local UI = Facet.controls(
			runtime,
			{
				types = engine.types,
				guiService = gui,
				motionLevel = "none",
				services = { GuiService = gui, RunService = frames },
			} :: any
		)
		local stop, screen: any = runtime.mount(function()
			return ((runtime.constructors.ScreenGui :: unknown) :: ScreenGuiConstructor)({ build(UI) })
		end, engine.new("Folder"))
		return screen, frames, function()
			stop()
			runtime:dispose()
		end
	end

	local function hidden(screen: any, name: string): boolean?
		local node = screen:FindFirstChild(name, true)
		if node == nil then
			return nil
		end
		local at = node
		while at and at ~= screen do
			if at:IsA("GuiObject") and not at.Visible then
				return true
			end
			at = at.Parent
		end
		return false
	end

	verifyHarness:suite("presented surfaces arrive styled", function()
		verifyHarness:case("holds a newly presented surface hidden until the next frame, when the theme styles apply", {
			id = "native_overlay_arrival::presented surfaces arrive styled::holds a newly presented surface hidden until the next frame, when the theme styles apply",
			run = function()
				for _, kind in { "Sheet", "Alert" } :: { "Alert" | "Sheet" } do
					local open = Compose.cell(false)
					local screen, frames, stop = world(function(UI: FacetControls)
						if kind == "Sheet" then
							return UI.Sheet "Market" {
								title = "Seeds",
								isPresented = open,
								detent = Compose.cell("medium"),
								content = function(): Instance
									return UI.Text { text = "Wheat" }
								end,
							}
						end
						return UI.Alert "Confirm" {
							title = "Sell the crop?",
							isPresented = open,
							actions = { { id = "ok", label = "Sell" } :: FixtureNavigationTypes.AlertAction<any> },
						}
					end)
					local inner = if kind == "Sheet" then "SheetPanel" else "ok"
					open:set(true)
					Verify.expect(`{kind} hidden {hidden(screen, inner)}`):toBe(`{kind} hidden true`)
					frames.Heartbeat.fire()
					Verify.expect(`{kind} hidden {hidden(screen, inner)}`):toBe(`{kind} hidden false`)
					Verify.expect((frames.Heartbeat.count())):toBe(0)
					stop()
				end
			end,
		})

		verifyHarness:case("releases its frame hook when the surface closes before the first frame", {
			id = "native_overlay_arrival::presented surfaces arrive styled::releases its frame hook when the surface closes before the first frame",
			run = function()
				local open = Compose.cell(false)
				local _, frames, stop = world(function(UI: FacetControls)
					return UI.Alert "Confirm" {
						title = "Sell the crop?",
						isPresented = open,
						actions = { { id = "ok", label = "Sell" } :: FixtureNavigationTypes.AlertAction<any> },
					}
				end)
				open:set(true)
				Verify.expect(frames.Heartbeat.count() >= 1):toBe(true)
				open:set(false)
				Verify.expect((frames.Heartbeat.count())):toBe(0)
				stop()
			end,
		})

		verifyHarness:case(
			"selects a presented surface's first control only once it is shown, never the hidden or panel node",
			{
				id = "native_overlay_arrival::presented surfaces arrive styled::selects a presented surface's first control only once it is shown, never the hidden or panel node",
				run = function()
					for _, kind in { "RadialMenu", "Dialog" } :: { "Dialog" | "RadialMenu" } do
						local engine = engineLib.new()
						local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
						local gui = engine.new("GuiService")
						local frames = { Heartbeat = signal() }
						local UI = Facet.controls(
							runtime,
							{
								types = engine.types,
								guiService = gui,
								motionLevel = "none",
								services = { GuiService = gui, RunService = frames },
							} :: any
						)
						local open = Compose.cell(false)
						local stop, screen: any = runtime.mount(function()
							return ((runtime.constructors.ScreenGui :: unknown) :: ScreenGuiConstructor)({
								UI.Button "Opener" { label = "Open" } :: unknown,
								if kind == "RadialMenu"
									then UI.RadialMenu {
										launcher = false,
										isPresented = open,
										items = {
											{ id = "alpha", label = "Alpha", onSelect = function() end } :: FixtureRadialTypes.RadialItem<any>,
										},
									}
									else UI.Dialog {
										isPresented = open,
										closeButton = false,
										title = "Title",
										content = function(): Instance
											return UI.Button "Inside" { label = "Inside" }
										end,
									} :: unknown,
							})
						end, engine.new("Folder"))
						gui.SelectedObject = screen:FindFirstChild("Opener", true)
						open:set(true)
						frames.Heartbeat.fire()
						Verify.expect(#engine.rejectedSelections):toBe(0)
						local selected = gui.SelectedObject
						Verify.expect(selected.Name):toBe(if kind == "RadialMenu" then "alpha" else "Inside")
						stop()
						runtime:dispose()
					end
				end,
			}
		)
	end)

	return nil
end
