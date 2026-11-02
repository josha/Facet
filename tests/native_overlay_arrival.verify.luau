--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type ScreenGuiConstructor = typeof(require("@repo/tools/typecheck/aliases").ScreenGuiConstructor)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local Compose: ComposeModule = Facet.Compose

	type Ticker = engineLib.Signal<number> & { count: () -> number }

	local function signal(): Ticker
		local handlers: { (number) -> () } = {}
		return {
			Connect = function(_: unknown, fn: (number) -> ())
				table.insert(handlers, fn)
				return {
					Disconnect = function(_: unknown)
						local index = table.find(handlers, fn)
						if index then
							table.remove(handlers, index)
						end
					end,
				}
			end,
			Fire = function(_self: unknown)
				for _, fn in table.clone(handlers) do
					fn(1 / 60)
				end
			end,
			count = function()
				return #handlers
			end,
		}
	end

	local function world(build: (Facet.Controls) -> Facet.Child, render: boolean?)
		local engine = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local gui = engine.new("GuiService")
		local frames: { Heartbeat: Ticker, PreRender: Ticker? } =
			{ Heartbeat = signal(), PreRender = if render then signal() else nil }
		if render then
			engine.heartbeat = assert(frames.PreRender)
		end
		local UI = Facet.controls(runtime, {
			types = engine.types,
			guiService = gui,
			motionLevel = "none",
			services = { GuiService = gui, RunService = frames :: any },
		})
		local stop, screen: any = runtime.mount(function()
			return Facet.host(runtime).ScreenGui({ build(UI) })
		end, engine.new("Folder"))
		return screen, frames, function()
			stop()
			runtime:dispose()
		end, engine
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
		verifyHarness:case("restores screen device clipping after the last modal closes", function()
			local first, second = Compose.cell(false), Compose.cell(false)
			local screen, _, stop = world(function(UI: FacetControls)
				local firstSpec: Facet.AlertSpec = {
					isPresented = first,
					title = "First",
					actions = { { id = "ok", label = "OK" } },
				}
				local secondSpec: Facet.AlertSpec = {
					isPresented = second,
					title = "Second",
					actions = { { id = "ok", label = "OK" } },
				}
				return UI.VStack {
					UI.Alert "First"(firstSpec),
					UI.Alert "Second"(secondSpec),
				}
			end)
			screen.ClipToDeviceSafeArea = true
			first:set(true)
			Verify.expect(screen.ClipToDeviceSafeArea):toBe(false)
			second:set(true)
			first:set(false)
			Verify.expect(screen.ClipToDeviceSafeArea):toBe(false)
			second:set(false)
			Verify.expect(screen.ClipToDeviceSafeArea):toBe(true)
			stop()
		end)

		verifyHarness:case("prepares a sliding row while its automatic layout slot has zero height", function()
			local screen, frames, stop, engine = world(function(UI: FacetControls)
				return UI.Toast { message = "Saved", duration = 10 }
			end, true)
			local row = screen:FindFirstChild("ToastRow", true)
			local slot = screen:FindFirstChild("ToastSlot", true)
			Verify.expect(slot.AbsoluteSize.Y):toBe(0)
			engine.environment.poke(row, "AbsoluteSize", engineLib.types.Vector2.new(210, 40))
			local render = assert(frames.PreRender)
			for _ = 1, 4 do
				render:Fire(1 / 60)
			end
			Verify.expect(require("./lib/fade").of(row)):toBe(0)
			stop()
			Verify.expect(render.count()):toBe(0)
		end)
		verifyHarness:case("waits for deferred geometry before the first painted frame", function()
			local screen, frames, stop, engine = world(function(UI: FacetControls)
				local stable: Facet.AlertSpec = {
					title = "Stable crop",
					isPresented = Compose.cell(true),
					actions = { { id = "ok", label = "Sell" } },
				}
				return UI.Alert(stable)
			end, true)
			local group = screen:FindFirstChild("OverlayArrival", true)
			Verify.expect(group:IsA("Frame")):toBe(true)
			Verify.expect(group.Visible):toBe(true)
			Verify.expect(group.Interactable):toBe(false)
			Verify.expect(group:FindFirstChildWhichIsA("CanvasGroup") ~= nil):toBe(true)
			Verify.expect(group.ClipsDescendants):toBe(false)
			Verify.expect(group.ZIndex):toBe(group:FindFirstChild("AlertModal", true).ZIndex)
			Verify.expect(require("./lib/fade").of(group)):toBe(1)
			for _, node in group:GetDescendants() do
				if node:IsA("GuiObject") then
					engine.environment.poke(node, "AbsoluteSize", engineLib.types.Vector2.new(210, 40))
				end
			end
			local render = assert(frames.PreRender)
			render:Fire(1 / 60)
			Verify.expect(require("./lib/fade").of(group)):toBe(1)
			engine.environment.poke(
				group:FindFirstChild("AlertModal", true),
				"AbsoluteSize",
				engineLib.types.Vector2.new(236, 40)
			)
			render:Fire(1 / 60)
			Verify.expect(require("./lib/fade").of(group)):toBe(1)
			for _ = 1, 4 do
				render:Fire(1 / 60)
			end
			Verify.expect(require("./lib/fade").of(group)):toBe(0)
			Verify.expect(group.Visible):toBe(true)
			Verify.expect(group.Interactable):toBe(true)
			Verify.expect(group:FindFirstChildWhichIsA("CanvasGroup") == nil):toBe(true)
			stop()
			Verify.expect(render.count()):toBe(0)
		end)
		verifyHarness:case("holds a newly presented surface hidden until the next frame, when the theme styles apply", {
			id = "native_overlay_arrival::presented surfaces arrive styled::holds a newly presented surface hidden until the next frame, when the theme styles apply",
			run = function()
				local kinds: { "Alert" | "Sheet" } = { "Sheet", "Alert" }
				for _, kind in kinds do
					local open = Compose.cell(false)
					local screen, frames, stop, engine = world(function(UI: FacetControls)
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
						local confirm: Facet.AlertSpec = {
							title = "Sell the crop?",
							isPresented = open,
							actions = { { id = "ok", label = "Sell" } },
						}
						return UI.Alert "Confirm"(confirm)
					end)
					local inner = if kind == "Sheet" then "SheetPanel" else "ok"
					open:set(true)
					Verify.expect(`{kind} hidden {hidden(screen, inner)}`):toBe(`{kind} hidden true`)
					frames.Heartbeat:Fire(1 / 60)
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
					local confirm: Facet.AlertSpec = {
						title = "Sell the crop?",
						isPresented = open,
						actions = { { id = "ok", label = "Sell" } },
					}
					return UI.Alert "Confirm"(confirm)
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
					local kinds: { "Dialog" | "RadialMenu" } = { "RadialMenu", "Dialog" }
					for _, kind in kinds do
						local engine = engineLib.new()
						local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
						local gui = engine.new("GuiService")
						local frames = { Heartbeat = signal() }
						local UI = Facet.controls(runtime, {
							types = engine.types,
							guiService = gui,
							motionLevel = "none",
							services = { GuiService = gui, RunService = frames :: any },
						})
						local open = Compose.cell(false)
						local alpha: Facet.RadialAction = { id = "alpha", label = "Alpha", onSelect = function() end }
						local radial: Facet.RadialMenuSpec = { launcher = false, isPresented = open, items = { alpha } }
						local stop, screen: any = runtime.mount(function()
							return Facet.host(runtime).ScreenGui({
								UI.Button "Opener" { label = "Open" },
								if kind == "RadialMenu"
									then (UI.RadialMenu :: any)(radial)
									else UI.Dialog {
										isPresented = open,
										closeButton = false,
										title = "Title",
										content = function(): Instance
											return UI.Button "Inside" { label = "Inside" }
										end,
									},
							})
						end, engine.new("Folder"))
						gui.SelectedObject = screen:FindFirstChild("Opener", true)
						open:set(true)
						frames.Heartbeat:Fire(1 / 60)
						Verify.expect(#engine.rejectedSelections()):toBe(0)
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
