--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type MotionLevel = typeof(require("@repo/tools/typecheck/aliases").MotionLevel)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type SheetDetent = typeof(require("@repo/tools/typecheck/aliases").SheetDetent)
	local FixtureNavigationTypes = require("../src/ui/navigation_types")
	type Readable<T> = { peek: (Readable<T>) -> T }
	type Use = <T>(Readable<T>) -> T

	local materialize = require("./lib/materialize")
	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local LIFT = 16 * math.sqrt(2) / 2
	local function corner(panel: any): (number, number)
		return panel.Position.X.Offset - panel.AnchorPoint.X * panel.AbsoluteSize.X,
			panel.Position.Y.Offset - panel.AnchorPoint.Y * panel.AbsoluteSize.Y
	end
	local function near(actual: number, expected: number): boolean
		return math.abs(actual - expected) <= 1
	end
	local Compose: ComposeModule = Facet.Compose

	type World = {
		engine: any,
		runtime: any,
		gui: any,
		input: any,
		screen: any,
		stop: () -> (),
	}

	local function setup(build: (any, any, any, any, any) -> any, options: { [string]: any }?): World
		local engine: any = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local gui = engine.new("GuiService")
		local input = engine.new("UserInputService")
		input.GetFocusedTextBox = function()
			return nil
		end
		input.IsKeyDown = function()
			return false
		end
		local config: { [string]: any } = {
			types = engine.types,
			guiService = gui,
			services = { GuiService = gui, UserInputService = input },
		}
		for key, value in (options or {}) :: { [string]: any } do
			config[key] = value
		end
		local UI = Facet.controls(runtime, config :: any)
		local Host = (runtime.constructors :: unknown) :: RobloxHost
		local stop, screen: any = runtime.mount(function()
			return Host.ScreenGui({ build(UI, Host, engine, gui, runtime) })
		end, engine.new("Folder"))
		return {
			engine = engine,
			runtime = runtime,
			gui = gui,
			input = input,
			screen = screen,
			stop = function()
				stop()
				runtime:dispose()
			end,
		}
	end

	local function find(root: any, name: string): any
		if root.Name == name then
			return root
		end
		for _, child in root:GetChildren() do
			local found = find(child, name)
			if found then
				return found
			end
		end
		return nil
	end

	local function all(root: any, name: string): { any }
		local found = {}
		for _, node in root:GetDescendants() do
			if node.Name == name then
				table.insert(found, node)
			end
		end
		return found
	end

	local function action(root: any, name: string): any
		local winner, priority = nil, -math.huge
		for _, node in root:GetDescendants() do
			if node:IsA("InputContext") and node.Name == "Facet" .. name and node.Enabled then
				local candidate = node:FindFirstChild(name)
				if candidate and node.Priority > priority then
					winner, priority = candidate, node.Priority
				end
			end
		end
		return winner
	end

	local function enabledCount(root: any, name: string): number
		local count = 0
		for _, node in root:GetDescendants() do
			if node:IsA("InputContext") and node.Name == "Facet" .. name and node.Enabled then
				count += 1
			end
		end
		return count
	end

	local function within(node: any, ancestor: any): boolean
		local at = node
		while at do
			if at == ancestor then
				return true
			end
			at = at.Parent
		end
		return false
	end

	local function mountScenario(name: string, reduced: boolean?): (any, any, any, any, any, () -> ())
		local engine: any = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local target = engine.new("Folder")
		local gui = engine.new("GuiService")
		local input = engine.new("UserInputService")
		input.GetFocusedTextBox = function()
			return nil
		end
		local ctx: any = {
			Facet = Facet,
			Compose = Compose,
			Host = (runtime.constructors :: unknown) :: RobloxHost,
			runtime = runtime,
			types = engine.types,
			viewport = Compose.cell({ width = 1280, height = 720 }),
			guiService = gui,
			inputTarget = target,
			worldTarget = engine.new("Folder"),
			runService = { Heartbeat = engine.heartbeat },
			reducedMotion = Compose.cell(reduced == true),
			pageVisible = Compose.cell(true),
		}
		ctx.UI = Facet.controls(
			runtime,
			{
				types = engine.types,
				viewport = ctx.viewport,
				guiService = gui,
				services = { GuiService = gui, UserInputService = input },
				inputParent = target,
				motionLevel = (Compose.formula(function(use: Use): "normal" | "limited" | "none"
					return if ctx.reducedMotion and use(ctx.reducedMotion) then "none" else "normal"
				end) :: unknown) :: MotionLevel,
			} :: any
		)
		local built: any
		local stop, node: any = runtime.mount(function()
			built = (require :: any)("../examples/gallery/scenarios/" .. name).build(ctx)
			if built.dispose then
				Compose.cleanup(built.dispose)
			end
			return ctx.Host.ScreenGui({ built.screen() })
		end, target)
		return built, node, ctx, engine, target, function()
			stop()
			runtime:dispose()
		end
	end

	local function toasts(node: any): { any }
		local cards = {}
		for _, child in node:GetDescendants() do
			if child.Name == "ToastRow" then
				table.insert(cards, child)
			end
		end
		return cards
	end

	local function visibleTitles(node: any): string
		local titles = {}
		for _, card in toasts(node) do
			table.insert(titles, find(card, "Title").Text)
		end
		table.sort(titles)
		return table.concat(titles, ",")
	end

	local function advance(engine: any, seconds: number, step: number?)
		local size = step or 0.05
		local remaining = seconds
		while remaining > 1e-9 do
			local delta = math.min(size, remaining)
			engine.heartbeat:Fire(delta)
			remaining -= delta
		end
	end

	local function withMonitors(body: (any) -> ())
		local modelModule: any = require("../examples/virtual_monitors/model")
		local screens: any = require("../examples/virtual_monitors/screens")
		local engine: any = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local target = engine.new("ScreenGui")
		local gui, input = engine.new("GuiService"), engine.new("UserInputService")
		input.GetFocusedTextBox = function()
			return nil
		end
		input.IsKeyDown = function()
			return false
		end
		local lifetime = Compose.createRootOwner(function()
			local model = modelModule.new(Compose)
			Compose.cleanup(model.dispose)
			local views = screens.create(Facet, runtime, {
				model = model,
				types = engine.types,
				services = { GuiService = gui, UserInputService = input },
				motionLevel = "none",
			})
			local world: any = { model = model, engine = engine, target = target, gui = gui, input = input }
			for _, name in { "Discover", "Avatar" } do
				local _, node: any = runtime.mount(views[name], target)
				world[name] = node
			end
			body(world)
		end, runtime.reactor)
		lifetime.dispose()
		Verify.expect(#target:GetChildren()):toBe(0)
		runtime:dispose()
	end

	verifyHarness:suite("presented surface strength", function()
		verifyHarness:case("centers a content-sized alert card under its width bound and leads the row with cancel", {
			id = "native_parity_weaker_surfaces::presented surface strength::centers a content-sized alert card under its width bound and leads the row with cancel",
			run = function()
				for _, bound in { 440, 360 } do
					local world = setup(function(UI: FacetControls)
						return UI.Alert({
							isPresented = Compose.cell(true),
							title = "Delete this save?",
							message = "This cannot be undone.",
							maxWidth = if bound == 440 then nil else bound,
							actions = {
								{ id = "Delete", label = "Delete save", role = "destructive" :: "destructive" } :: FixtureNavigationTypes.AlertAction<any>,
								{ id = "Cancel", label = "Cancel", role = "cancel" :: "cancel" } :: FixtureNavigationTypes.AlertAction<any>,
							},
						})
					end)
					local V2 = world.engine.types.Vector2
					find(world.screen, "AlertModal").AbsoluteSize = V2.new(1280, 800)
					local panel = find(world.screen, "AlertPanel")
					Verify.expect(panel.AnchorPoint):toBe(V2.new(0.5, 0.5))
					Verify.expect(panel.Position.X.Scale):toBe(0.5)
					Verify.expect(panel.Position.Y.Scale):toBe(0.5)
					Verify.expect(panel.Position.X.Offset):toBe(0)
					Verify.expect(panel.Position.Y.Offset):toBe(0)
					Verify.expect(panel.AutomaticSize):toBe(world.engine.types.Enum.AutomaticSize.Y)
					Verify.expect(panel.Size.Y.Scale):toBe(0)
					Verify.expect(panel.Size.Y.Offset):toBe(0)
					local constraint = panel:FindFirstChildWhichIsA("UISizeConstraint")
					Verify.expect(constraint ~= nil):toBe(true)
					Verify.expect(constraint.MaxSize.X):toBe(bound)
					Verify.expect(bound < 1280 - 32):toBe(true)
					local layout = find(world.screen, "Actions"):FindFirstChildWhichIsA("UIListLayout")
					Verify.expect(layout.FillDirection):toBe(world.engine.types.Enum.FillDirection.Horizontal)
					Verify.expect(find(world.screen, "Cancel").LayoutOrder):toBe(0)
					Verify.expect(find(world.screen, "Delete").LayoutOrder):toBe(1)
					world.stop()
				end
			end,
		})

		verifyHarness:case("stacks more than two alert actions with the likely action on top and cancel last", {
			id = "native_parity_weaker_surfaces::presented surface strength::stacks more than two alert actions with the likely action on top and cancel last",
			run = function()
				local world = setup(function(UI: FacetControls, Host: RobloxHost, _, gui)
					local opener = UI.Button "Opener" { label = "Open" }
					gui.SelectedObject = opener
					return Host.Frame({
						opener :: unknown,
						UI.Alert({
							isPresented = Compose.cell(true),
							title = "Leave the race?",
							actions = {
								{ id = "Cancel", label = "Stay", role = "cancel" :: "cancel" } :: FixtureNavigationTypes.AlertAction<any>,
								{ id = "Save", label = "Save and leave" } :: FixtureNavigationTypes.AlertAction<any>,
								{
									id = "Delete",
									label = "Leave without saving",
									role = "destructive" :: "destructive",
								} :: FixtureNavigationTypes.AlertAction<any>,
							},
						}),
					})
				end)
				local Enum = world.engine.types.Enum
				find(world.screen, "AlertModal").AbsoluteSize = world.engine.types.Vector2.new(1280, 800)
				Verify.expect(find(world.screen, "Actions"):FindFirstChildWhichIsA("UIListLayout").FillDirection)
					:toBe(Enum.FillDirection.Vertical)
				local save, delete, cancel =
					find(world.screen, "Save"), find(world.screen, "Delete"), find(world.screen, "Cancel")
				Verify.expect(save.LayoutOrder < delete.LayoutOrder):toBe(true)
				Verify.expect(delete.LayoutOrder < cancel.LayoutOrder):toBe(true)
				for _, button in { save, delete, cancel } do
					Verify.expect(button.Size):toBe(world.engine.types.UDim2.new(1, 0, 0, 44))
				end
				Verify.expect(world.gui.SelectedObject):toBe(cancel)
				world.stop()
			end,
		})

		verifyHarness:case("binds alert presentation both ways without stacking or invoking action callbacks", {
			id = "native_parity_weaker_surfaces::presented surface strength::binds alert presentation both ways without stacking or invoking action callbacks",
			run = function()
				local shown, calls = Compose.cell(false), 0
				local world = setup(function(UI: FacetControls)
					return UI.Alert({
						title = "Continue?",
						isPresented = shown,
						actions = {
							{
								id = "cancel",
								label = "Cancel",
								role = "cancel" :: "cancel",
								onActivate = function()
									calls += 1
								end,
							} :: FixtureNavigationTypes.AlertAction<any>,
						},
					})
				end)
				Verify.expect(#all(world.screen, "AlertModal")):toBe(0)
				shown:set(true)
				Verify.expect(#all(world.screen, "AlertModal")):toBe(1)
				local panel = find(world.screen, "AlertPanel")
				shown:set(true)
				Verify.expect(#all(world.screen, "AlertModal")):toBe(1)
				Verify.expect((find(world.screen, "AlertPanel"))):toBe(panel)
				shown:set(false)
				Verify.expect(#all(world.screen, "AlertModal")):toBe(0)
				Verify.expect(calls):toBe(0)
				shown:set(true)
				find(world.screen, "ModalBack").Pressed:Fire()
				Verify.expect((shown:peek())):toBe(false)
				Verify.expect(calls):toBe(1)
				Verify.expect(#all(world.screen, "AlertModal")):toBe(0)
				world.stop()
			end,
		})

		verifyHarness:case(
			"owns alert content through repeated presentation and dismisses on the default action shortcut",
			{
				id = "native_parity_weaker_surfaces::presented surface strength::owns alert content through repeated presentation and dismisses on the default action shortcut",
				run = function()
					local shown, text = Compose.cell(false), Compose.cell("Name")
					local live, built, accepted = 0, 0, 0
					local world = setup(function(UI: FacetControls)
						return UI.Alert "Edit" {
							title = "Edit name",
							isPresented = shown,
							content = function(): Instance
								live += 1
								built += 1
								Compose.cleanup(function()
									live -= 1
								end)
								return UI.TextInput "Name" { value = text }
							end,
							actions = {
								{
									id = "Save",
									label = "Save",
									shortcut = "defaultAction",
									onActivate = function()
										accepted += 1
									end,
								} :: FixtureNavigationTypes.AlertAction<any>,
								{ id = "Cancel", label = "Cancel", role = "cancel" :: "cancel" } :: FixtureNavigationTypes.AlertAction<any>,
							},
						}
					end)
					Verify.expect(live):toBe(0)
					for round = 1, 2 do
						shown:set(true)
						Verify.expect(live):toBe(1)
						Verify.expect(built):toBe(round)
						Verify.expect(find(world.screen, "Name") ~= nil):toBe(true)
						local shortcut = action(world.screen, "Shortcut")
						Verify.expect(shortcut ~= nil):toBe(true)
						local keys = {}
						for _, binding in shortcut:GetChildren() do
							table.insert(keys, binding.KeyCode)
						end
						Verify.expect(table.find(keys, world.engine.types.Enum.KeyCode.Return) ~= nil):toBe(true)
						shortcut.Pressed:Fire()
						Verify.expect((shown:peek())):toBe(false)
						Verify.expect(live):toBe(0)
						Verify.expect(accepted):toBe(round)
					end
					shown:set(true)
					Verify.expect(live):toBe(1)
					world.stop()
					Verify.expect(live):toBe(0)
				end,
			}
		)

		verifyHarness:case("rebuilds sheet content on each presentation and disposes it on close and owner stop", {
			id = "native_parity_weaker_surfaces::presented surface strength::rebuilds sheet content on each presentation and disposes it on close and owner stop",
			run = function()
				local shown, detent = Compose.cell(false), Compose.cell("medium")
				local live, visits = 0, 0
				local world = setup(function(UI: FacetControls)
					return UI.Sheet "Details" {
						title = "Details",
						isPresented = shown,
						detent = detent,
						content = function(): Instance
							live += 1
							visits += 1
							Compose.cleanup(function()
								live -= 1
							end)
							return UI.Button "Body" {
								label = "Done",
								onActivate = function()
									shown:set(false)
								end,
							}
						end,
					}
				end)
				Verify.expect(live):toBe(0)
				for round = 1, 2 do
					shown:set(true)
					Verify.expect(live):toBe(1)
					Verify.expect(visits):toBe(round)
					Verify.expect(find(world.screen, "SheetPanel") ~= nil):toBe(true)
					detent:set("medium")
					find(world.screen, "Grabber").Activated:Fire()
					Verify.expect((detent:peek())):toBe("large")
					find(world.screen, "ModalBack").Pressed:Fire()
					Verify.expect((shown:peek())):toBe(false)
					Verify.expect(live):toBe(0)
					Verify.expect((find(world.screen, "SheetPanel"))):toBe(nil)
				end
				shown:set(true)
				Verify.expect(live):toBe(1)
				world.stop()
				Verify.expect(live):toBe(0)
			end,
		})

		verifyHarness:case("resolves every sheet detent to a height inside the measured available height", {
			id = "native_parity_weaker_surfaces::presented surface strength::resolves every sheet detent to a height inside the measured available height",
			run = function()
				local detent = Compose.cell("medium")
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return UI.Sheet({
						isPresented = Compose.cell(true),
						detent = detent,
						detents = { "medium", "large", { id = "tall", height = 2000 }, { id = "fixed", height = 300 } } :: { SheetDetent },
						content = function(): Instance
							return Host.Frame "Body" {}
						end,
					})
				end)
				world.gui.ReducedMotionEnabled = true
				local panel = find(world.screen, "SheetPanel")
				local function height(id: string): number
					detent:set(id)
					return panel.Size.Y.Offset
				end
				Verify.expect((height("medium"))):toBe(360)
				Verify.expect((height("large"))):toBe(684)
				Verify.expect((height("tall"))):toBe(720)
				Verify.expect((height("fixed"))):toBe(300)
				find(world.screen, "Modal").AbsoluteSize = world.engine.types.Vector2.new(390, 600)
				Verify.expect((height("medium"))):toBe(300)
				Verify.expect((height("large"))):toBe(570)
				Verify.expect((height("tall"))):toBe(600)
				Verify.expect((height("fixed"))):toBe(300)
				Verify.expect(panel.Size.X.Offset):toBe(390)
				find(world.screen, "Modal").AbsoluteSize = world.engine.types.Vector2.new(1280, 600)
				Verify.expect(panel.Size.X.Offset):toBe(560)
				world.stop()
			end,
		})

		verifyHarness:case("keeps a usable minimum panel and a reachable close for tiny sheet detents", {
			id = "native_parity_weaker_surfaces::presented surface strength::keeps a usable minimum panel and a reachable close for tiny sheet detents",
			run = function()
				local shown, detent = Compose.cell(true), Compose.cell("peek")
				local world = setup(function(UI: FacetControls)
					return UI.Sheet({
						isPresented = shown,
						detent = detent,
						detents = { { id = "peek", height = 60 }, { id = "sliver", fraction = 0.05 } } :: { SheetDetent },
						title = "Peek",
						dragIndicator = "hidden" :: "hidden",
						content = function(): Instance
							return UI.Button "Inside" { label = "Inside" }
						end,
					})
				end)
				world.gui.ReducedMotionEnabled = true
				local panel = find(world.screen, "SheetPanel")
				Verify.expect(panel.Size.Y.Offset):toBe(208)
				detent:set("sliver")
				Verify.expect(panel.Size.Y.Offset):toBe(208)
				find(world.screen, "Modal").AbsoluteSize = world.engine.types.Vector2.new(390, 180)
				Verify.expect(panel.Size.Y.Offset):toBe(180)
				Verify.expect((find(world.screen, "Inside"):IsDescendantOf(find(world.screen, "SheetContent"))))
					:toBe(true)
				Verify.expect(find(world.screen, "Close").Parent.Name):toBe("Header")
				find(world.screen, "Close").Activated:Fire()
				Verify.expect((shown:peek())):toBe(false)
				world.stop()
			end,
		})

		verifyHarness:case(
			"hangs a callout below a top-right anchor with its arrow at the anchor and its body shifted left",
			{
				id = "native_parity_weaker_surfaces::presented surface strength::hangs a callout below a top-right anchor with its arrow at the anchor and its body shifted left",
				run = function()
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						local anchor = UI.Button "Plus" { label = "+" }
						return Host.Frame({
							anchor :: unknown,
							UI.Callout({
								anchor = anchor :: GuiObject,
								onRetire = function() end,
								content = function(): Instance
									return Host.TextLabel "Tip" { Text = "Post avatars to the marketplace" }
								end,
							}),
						})
					end)
					local V = world.engine.types.Vector2
					world.screen.AbsoluteSize = V.new(390, 844)
					local anchor, panel, arrow =
						find(world.screen, "Plus"), find(world.screen, "CalloutPanel"), find(world.screen, "Arrow")
					anchor.AbsolutePosition = V.new(338, 12)
					anchor.AbsoluteSize = V.new(44, 44)
					panel.AbsoluteSize = V.new(280, 96)
					advance(world.engine, 1)
					Verify.expect(materialize.of(panel).Scale):toBe(1)
					local left, top = corner(panel)
					Verify.expect((near(top, 12 + 44 + 8 + LIFT))):toBe(true)
					Verify.expect(left + 280 <= 390 - 8 + 0.5):toBe(true)
					Verify.expect(left < 338 + 22 - 140):toBe(true)
					local arrowCenterX = arrow.Position.X.Offset
					Verify.expect(arrowCenterX >= 338 and arrowCenterX <= 338 + 44):toBe(true)
					Verify.expect((near(arrow.Position.Y.Offset, top))):toBe(true)
					Verify.expect(arrow.Position.Y.Offset - LIFT < top and arrow.Position.Y.Offset - LIFT >= 12 + 44)
						:toBe(true)
					world.stop()
				end,
			}
		)

		verifyHarness:case("carries the given callout content tree and bounds long copy to the viewport width", {
			id = "native_parity_weaker_surfaces::presented surface strength::carries the given callout content tree and bounds long copy to the viewport width",
			run = function()
				local long = string.rep("Pseudo-localized coaching copy that must wrap without clipping. ", 3)
				local world = setup(function(UI: FacetControls, Host: RobloxHost, engine)
					local anchor = UI.Button "Anchor" { label = "Anchor" }
					return Host.Frame({
						anchor :: unknown,
						UI.Callout({
							anchor = anchor :: GuiObject,
							onRetire = function() end,
							content = function(): Instance
								return Host.Frame "Content" {
									Size = engine.types.UDim2.new(1, 0, 0, 0),
									AutomaticSize = engine.types.Enum.AutomaticSize.Y,
									Host.TextLabel "Body" {
										Text = long,
										TextWrapped = true,
										Size = engine.types.UDim2.new(1, 0, 0, 0),
										AutomaticSize = engine.types.Enum.AutomaticSize.Y,
									} :: unknown,
									Host.TextLabel "Sub" { Text = "Anyone can wear it" },
								}
							end,
						}),
					})
				end)
				local V = world.engine.types.Vector2
				local panel = find(world.screen, "CalloutPanel")
				local content = find(panel, "Content")
				Verify.expect(content ~= nil):toBe(true)
				Verify.expect(find(content, "Body").Text):toBe(long)
				Verify.expect(find(content, "Body").TextWrapped):toBe(true)
				Verify.expect(find(content, "Sub").Text):toBe("Anyone can wear it")
				local anchor = find(world.screen, "Anchor")
				anchor.AbsolutePosition = V.new(150, 300)
				anchor.AbsoluteSize = V.new(60, 44)
				advance(world.engine, 1)
				Verify.expect(materialize.of(panel).Scale):toBe(1)
				for _, extent in { 390, 240, 120 } do
					world.screen.AbsoluteSize = V.new(extent, 844)
					local width = panel.Size.X.Offset
					Verify.expect(width):toBe(math.min(280, extent - 16))
					Verify.expect(panel.Size.X.Scale):toBe(0)
					Verify.expect(panel.AutomaticSize):toBe(world.engine.types.Enum.AutomaticSize.Y)
					panel.AbsoluteSize = V.new(width, 180)
					local left = corner(panel)
					Verify.expect(left >= 8 - 0.5):toBe(true)
					Verify.expect(left + width <= extent - 8 + 0.5):toBe(true)
				end
				world.stop()
			end,
		})

		verifyHarness:case("keeps a retired callout retired and unbuilt when it is presented again", {
			id = "native_parity_weaker_surfaces::presented surface strength::keeps a retired callout retired and unbuilt when it is presented again",
			run = function()
				local shown, used = Compose.cell(false), Compose.cell(false)
				local live, built, retired = 0, 0, 0
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					local anchor = UI.Button "Anchor" {
						label = "Add",
						onActivate = function()
							used:set(true)
						end,
					}
					return Host.Frame({
						anchor :: unknown,
						UI.Callout "Tip" {
							anchor = anchor :: GuiObject,
							isPresented = shown,
							featureUsed = used,
							onRetire = function()
								retired += 1
							end,
							content = function(): Instance
								live += 1
								built += 1
								Compose.cleanup(function()
									live -= 1
								end)
								return Host.TextLabel "TipText" { Text = "Add your first item" }
							end,
						},
					})
				end)
				Verify.expect(live):toBe(0)
				shown:set(true)
				Verify.expect(live):toBe(1)
				find(world.screen, "Anchor").Activated:Fire()
				Verify.expect(retired):toBe(1)
				Verify.expect(live):toBe(0)
				shown:set(false)
				shown:set(true)
				Verify.expect(live):toBe(0)
				Verify.expect(built):toBe(1)
				Verify.expect(retired):toBe(1)
				Verify.expect((find(world.screen, "CalloutPanel"))):toBe(nil)
				world.stop()
				Verify.expect(live):toBe(0)
			end,
		})

		verifyHarness:case("adds no full-viewport cover or modal scope while a nonmodal callout is showing", {
			id = "native_parity_weaker_surfaces::presented surface strength::adds no full-viewport cover or modal scope while a nonmodal callout is showing",
			run = function()
				local presses = 0
				local world = setup(function(UI: FacetControls, Host: RobloxHost, engine)
					local anchor = UI.Button "Anchor" { label = "Anchor" }
					return Host.Frame "Live" {
						Size = engine.types.UDim2.fromScale(1, 1),
						BackgroundTransparency = 1,
						anchor :: unknown,
						UI.Button "Elsewhere" {
							label = "Elsewhere",
							onActivate = function()
								presses += 1
							end,
						},
						UI.Callout({
							anchor = anchor :: GuiObject,
							onRetire = function() end,
							content = function(): Instance
								return Host.TextLabel "TipText" { Text = "Tip" }
							end,
						}),
					}
				end)
				Verify.expect(find(world.screen, "CalloutPanel") ~= nil):toBe(true)
				local live = find(world.screen, "Live")
				for _, node in world.screen:GetDescendants() do
					if node:IsA("GuiObject") and node ~= live and not within(node, live) then
						local covers = node.Size.X.Scale >= 1 and node.Size.Y.Scale >= 1
						local parent = node.Parent
						while covers and parent and parent ~= world.screen do
							if parent:IsA("GuiObject") then
								covers = parent.Size.X.Scale >= 1 and parent.Size.Y.Scale >= 1
							end
							parent = parent.Parent
						end
						Verify.expect(covers):toBe(false)
					end
				end
				Verify.expect((find(world.screen, "DismissOutside"))):toBe(nil)
				Verify.expect((find(world.screen, "ModalBack"))):toBe(nil)
				find(world.screen, "Elsewhere").Activated:Fire()
				Verify.expect(presses):toBe(1)
				world.stop()
			end,
		})

		verifyHarness:case(
			"makes the modal scrim the only full-viewport cover and keeps it translucent in every theme",
			{
				id = "native_parity_weaker_surfaces::presented surface strength::makes the modal scrim the only full-viewport cover and keeps it translucent in every theme",
				run = function()
					local world = setup(function(UI: FacetControls, Host: RobloxHost, engine)
						return Host.Frame "Live" {
							Size = engine.types.UDim2.fromScale(1, 1),
							BackgroundTransparency = 1,
							UI.Button "Trigger" { label = "Open" } :: unknown,
							UI.Alert({
								isPresented = Compose.cell(true),
								title = "Leave race?",
								actions = {
									{ id = "stay", label = "Stay", role = "cancel" :: "cancel" } :: FixtureNavigationTypes.AlertAction<any>,
								},
							}),
						}
					end)
					local live = find(world.screen, "Live")
					local covers = {}
					for _, node in world.screen:GetDescendants() do
						if
							node:IsA("GuiObject")
							and node ~= live
							and not within(node, live)
							and node.Size.X.Scale >= 1
							and node.Size.Y.Scale >= 1
							and node.Size.X.Offset >= 0
							and node.Size.Y.Offset >= 0
							and node.BackgroundTransparency < 1
						then
							table.insert(covers, node)
						end
					end
					Verify.expect(#covers):toBe(1)
					Verify.expect(covers[1].Name):toBe("DismissOutside")
					Verify.expect((covers[1]:HasTag("facet-scrim"))):toBe(true)
					Verify.expect(find(world.screen, "AlertModal").BackgroundTransparency):toBe(1)
					world.stop()
					local themes = Facet.themes
					local packages = { themes.neutralPackage() }
					for _, name in
						{
							"classic_desktop",
							"compact_pointer",
							"fantasy_parchment",
							"fantasy_ornate",
							"glossy_mobile",
							"glossy_touch",
							"pixel_quest",
							"scifi_hud",
						}
					do
						local module: any = (require :: any)("../examples/themes/" .. name)
						local package, report = module.build(themes)
						Verify.expect(report.ok):toBe(true)
						table.insert(packages, package)
					end
					for _, package in packages do
						local engine: any = engineLib.new()
						local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
						local stop, sheet: any = runtime.mount(function()
							return themes.createStyleSheet(runtime, package, { types = engine.types })
						end, engine.new("Folder"))
						local scrim
						for _, rule in sheet:GetChildren() do
							if rule.Selector == ".facet-scrim" then
								scrim = rule:GetProperties().BackgroundTransparency
							end
						end
						Verify.expect((type(scrim))):toBe("number")
						Verify.expect(scrim > 0 and scrim < 1):toBe(true)
						stop()
						runtime:dispose()
					end
				end,
			}
		)

		verifyHarness:case("closes every open menu level on a tap away from the automatic compact sheet", {
			id = "native_parity_weaker_surfaces::presented surface strength::closes every open menu level on a tap away from the automatic compact sheet",
			run = function()
				local shown = Compose.cell(true)
				local world = setup(function(UI: FacetControls)
					return UI.Menu({
						isPresented = shown,
						items = {
							{
								id = "adjust",
								label = "Adjust",
								children = {
									{
										id = "layer",
										label = "Layer",
										children = { { id = "leaf", label = "Leaf", onSelect = function() end } },
									},
								},
							} :: FixtureNavigationTypes.MenuItem<any>,
						},
					})
				end)
				find(world.screen, "Modal").AbsoluteSize = world.engine.types.Vector2.new(390, 844)
				local panel = find(world.screen, "MenuPanel")
				Verify.expect(panel.Size.X.Scale):toBe(1)
				Verify.expect(panel.Size.X.Offset):toBe(-24)
				find(world.screen, "adjust").Activated:Fire()
				find(world.screen, "layer").Activated:Fire()
				Verify.expect(find(world.screen, "leaf") ~= nil):toBe(true)
				Verify.expect(find(world.screen, "Back") ~= nil):toBe(true)
				local catcher = find(world.screen, "DismissOutside")
				catcher.Activated:Fire({ Position = world.engine.types.Vector2.new(4, 4) })
				Verify.expect((shown:peek())):toBe(false)
				Verify.expect((find(world.screen, "MenuPanel"))):toBe(nil)
				Verify.expect((find(world.screen, "leaf"))):toBe(nil)
				Verify.expect((find(world.screen, "DismissOutside"))):toBe(nil)
				world.stop()
			end,
		})

		verifyHarness:case("dismisses through a fully transparent menu catcher", {
			id = "native_parity_weaker_surfaces::presented surface strength::dismisses through a fully transparent menu catcher",
			run = function()
				local shown = Compose.cell(true)
				local world = setup(function(UI: FacetControls)
					return UI.Menu({
						isPresented = shown,
						items = {
							{ id = "Run", label = "Run", onSelect = function() end } :: FixtureNavigationTypes.MenuItem<any>,
						},
					})
				end)
				local catcher = find(world.screen, "DismissOutside")
				Verify.expect(catcher.BackgroundTransparency):toBe(1)
				Verify.expect((catcher:HasTag("facet-scrim"))):toBe(false)
				Verify.expect(catcher.Size):toBe(world.engine.types.UDim2.fromScale(1, 1))
				world.gui.PreferredTransparency = 0
				Verify.expect(catcher.BackgroundTransparency):toBe(1)
				catcher.Activated:Fire({ Position = world.engine.types.Vector2.new(4, 4) })
				Verify.expect((shown:peek())):toBe(false)
				Verify.expect((find(world.screen, "MenuPanel"))):toBe(nil)
				world.stop()
			end,
		})

		verifyHarness:case("fits the expanded content inside the plate's themed inset and grows the plate by it", {
			id = "native_parity_weaker_surfaces::presented surface strength::fits the expanded content inside the plate's themed inset and grows the plate by it",
			run = function()
				local expanded = Compose.cell(true)
				local world = setup(function(UI: FacetControls)
					return UI.CollapsibleView "View" {
						label = "Race settings",
						expanded = expanded,
						content = function(): Instance
							return UI.Button "One" { label = "Coastal circuit" }
						end,
					}
				end)
				local V2 = world.engine.types.Vector2.new
				world.screen.AbsoluteSize = V2(800, 600)
				local plate = find(world.screen, "Expanded")
				find(plate, "ExpandedBody").AbsoluteSize = V2(312, 200)
				local fade = find(plate, "ExpandedFade")
				Verify.expect(fade.Size.X.Offset):toBe(360)
				plate.AbsoluteSize = V2(360, 200)
				find(plate, "ContentBox").AbsoluteSize = V2(312, 152)
				Verify.expect(fade.Size.X.Offset):toBe(312)
				Verify.expect(fade.Size.Y.Offset):toBe(200)
				world.stop()
			end,
		})

		verifyHarness:case("updates the bound summary label on a choice and returns selection to the same trigger", {
			id = "native_parity_weaker_surfaces::presented surface strength::updates the bound summary label on a choice and returns selection to the same trigger",
			run = function()
				local expanded, label, chosen = Compose.cell(false), Compose.cell("Select course"), false
				local world = setup(function(UI: FacetControls, Host: RobloxHost, _, gui)
					local view = UI.CollapsibleView "View" {
						label = label,
						expanded = expanded,
						content = function(): Instance
							return UI.Button "One" {
								label = "Coastal circuit",
								onActivate = function()
									chosen = true
									label:set("Coastal circuit")
									expanded:set(false)
								end,
							}
						end,
					}
					gui.SelectedObject = view
					return Host.Frame({ view :: unknown, UI.Button "Other" { label = "Unrelated" } })
				end)
				local trigger = find(world.screen, "View")
				Verify.expect((trigger:GetAttribute("label"))):toBe("Select course")
				trigger.Activated:Fire()
				Verify.expect((expanded:peek())):toBe(true)
				local surface = find(world.screen, "Expanded")
				Verify.expect(surface ~= nil):toBe(true)
				Verify.expect((within(world.gui.SelectedObject, surface))):toBe(true)
				find(world.screen, "One").Activated:Fire()
				Verify.expect(chosen):toBe(true)
				Verify.expect((expanded:peek())):toBe(false)
				Verify.expect((find(world.screen, "Expanded"))):toBe(nil)
				Verify.expect((trigger:GetAttribute("label"))):toBe("Coastal circuit")
				Verify.expect((find(world.screen, "View"))):toBe(trigger)
				Verify.expect(world.gui.SelectedObject):toBe(trigger)
				world.stop()
			end,
		})

		verifyHarness:case("pops one modal per outside tap, routes inside taps and never clicks through to the base", {
			id = "native_parity_weaker_surfaces::presented surface strength::pops one modal per outside tap, routes inside taps and never clicks through to the base",
			run = function()
				local outer, inner, barrier = Compose.cell(true), Compose.cell(true), Compose.cell(false)
				local baseHits, topHits = 0, 0
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Button "Base" {
							label = "Base",
							onActivate = function()
								baseHits += 1
							end,
						} :: unknown,
						UI.Sheet({
							isPresented = outer,
							detent = Compose.cell("medium"),
							content = function(): Instance
								return UI.Button "OuterAction" { label = "Outer" }
							end,
						}),
						UI.Sheet({
							isPresented = inner,
							detent = Compose.cell("medium"),
							content = function(): Instance
								return UI.Button "InnerAction" {
									label = "Inner",
									onActivate = function()
										topHits += 1
									end,
								}
							end,
						}),
						UI.Alert({
							isPresented = barrier,
							title = "Decide",
							actions = {
								{ id = "Keep", label = "Keep", role = "cancel" :: "cancel" } :: FixtureNavigationTypes.AlertAction<any>,
								{ id = "Go", label = "Go" } :: FixtureNavigationTypes.AlertAction<any>,
							},
						}),
					})
				end)
				local base = find(world.screen, "Base")
				local catchers = all(world.screen, "DismissOutside")
				Verify.expect(#catchers):toBe(2)
				for _, catcher in catchers do
					Verify.expect(catcher.ClassName):toBe("TextButton")
					Verify.expect(catcher.Size):toBe(world.engine.types.UDim2.fromScale(1, 1))
					Verify.expect(catcher.ZIndex > base.ZIndex):toBe(true)
					Verify.expect(catcher.Selectable):toBe(false)
				end
				find(world.screen, "InnerAction").Activated:Fire()
				Verify.expect(topHits):toBe(1)
				Verify.expect((inner:peek())):toBe(true)
				base.Activated:Fire()
				Verify.expect(baseHits):toBe(0)
				catchers[2].Activated:Fire({ Position = world.engine.types.Vector2.new(2, 2) })
				Verify.expect((inner:peek())):toBe(false)
				Verify.expect((outer:peek())):toBe(true)
				base.Activated:Fire()
				Verify.expect(baseHits):toBe(0)
				catchers[1].Activated:Fire({ Position = world.engine.types.Vector2.new(2, 2) })
				Verify.expect((outer:peek())):toBe(false)
				base.Activated:Fire()
				Verify.expect(baseHits):toBe(1)
				barrier:set(true)
				local wall = find(world.screen, "DismissOutside")
				Verify.expect(wall.Size):toBe(world.engine.types.UDim2.fromScale(1, 1))
				wall.Activated:Fire({ Position = world.engine.types.Vector2.new(2, 2) })
				Verify.expect((barrier:peek())):toBe(true)
				base.Activated:Fire()
				Verify.expect(baseHits):toBe(1)
				find(world.screen, "ModalBack").Pressed:Fire()
				Verify.expect((barrier:peek())):toBe(false)
				base.Activated:Fire()
				Verify.expect(baseHits):toBe(2)
				world.stop()
			end,
		})

		verifyHarness:case("shows help for gamepad selection but never when a touch tap moves the selection", {
			id = "native_parity_weaker_surfaces::presented surface strength::shows help for gamepad selection but never when a touch tap moves the selection",
			run = function()
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame "Screen" {
						UI.Button "Plus" { label = "+", help = "Posts this avatar" } :: unknown,
						UI.Button "Other" { label = "Other" },
					}
				end)
				local plus, other = find(world.screen, "Plus"), find(world.screen, "Other")
				local Enum = world.engine.types.Enum
				world.input.PreferredInput = Enum.PreferredInput.Touch
				plus.GuiState = Enum.GuiState.Press
				world.gui.SelectedObject = plus
				plus.GuiState = Enum.GuiState.Idle
				world.engine.heartbeat:Fire(0.3)
				world.engine.heartbeat:Fire(0.3)
				Verify.expect((find(world.screen, "HelpText"))):toBe(nil)
				plus.GuiState = Enum.GuiState.Hover
				world.engine.heartbeat:Fire(0.6)
				Verify.expect((find(world.screen, "HelpText"))):toBe(nil)
				plus.GuiState = Enum.GuiState.Idle
				world.gui.SelectedObject = nil
				world.input.PreferredInput = Enum.PreferredInput.Gamepad
				world.gui.SelectedObject = plus
				world.engine.heartbeat:Fire(0.5)
				Verify.expect(find(world.screen, "HelpText").Text):toBe("Posts this avatar")
				world.gui.SelectedObject = other
				Verify.expect((find(world.screen, "HelpText"))):toBe(nil)
				world.engine.heartbeat:Fire(0.6)
				Verify.expect((find(world.screen, "HelpText"))):toBe(nil)
				world.gui.SelectedObject = nil
				world.input.PreferredInput = Enum.PreferredInput.KeyboardAndMouse
				plus.GuiState = Enum.GuiState.Hover
				world.engine.heartbeat:Fire(0.5)
				Verify.expect(find(world.screen, "HelpText") ~= nil):toBe(true)
				plus.GuiState = Enum.GuiState.Press
				Verify.expect((find(world.screen, "HelpText"))):toBe(nil)
				world.stop()
			end,
		})

		verifyHarness:case("keeps the top modal active when the covered surface beneath it is dismissed", {
			id = "native_parity_weaker_surfaces::presented surface strength::keeps the top modal active when the covered surface beneath it is dismissed",
			run = function()
				local outer, inner, shortcuts, confirmed = Compose.cell(true), Compose.cell(false), 0, 0
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Button "Background" {
							label = "Background",
							shortcut = { keyCode = "K" },
							onActivate = function()
								shortcuts += 1
							end,
						} :: unknown,
						UI.Sheet({
							isPresented = outer,
							detent = Compose.cell("medium"),
							content = function(): Instance
								return UI.Button "Covered" { label = "Covered" }
							end,
						}),
						UI.Alert({
							isPresented = inner,
							title = "Confirm",
							actions = {
								{
									id = "Ok",
									label = "Ok",
									onActivate = function()
										confirmed += 1
									end,
								} :: FixtureNavigationTypes.AlertAction<any>,
								{ id = "No", label = "No", role = "cancel" :: "cancel" } :: FixtureNavigationTypes.AlertAction<any>,
							},
						}),
					})
				end)
				world.gui.SelectedObject = find(world.screen, "Covered")
				inner:set(true)
				local ok = find(world.screen, "Ok")
				Verify.expect(world.gui.SelectedObject):toBe(ok)
				Verify.expect(#all(world.screen, "FacetModalBack")):toBe(2)
				Verify.expect((enabledCount(world.screen, "ModalBack"))):toBe(1)
				outer:set(false)
				Verify.expect((find(world.screen, "SheetPanel"))):toBe(nil)
				Verify.expect((inner:peek())):toBe(true)
				Verify.expect(find(world.screen, "AlertPanel") ~= nil):toBe(true)
				Verify.expect(world.gui.SelectedObject):toBe(ok)
				local panel = find(world.screen, "AlertPanel")
				for _, direction in { "Up", "Down", "Left", "Right" } :: { "Down" | "Left" | "Right" | "Up" } do
					Verify.expect(panel["SelectionBehavior" .. direction])
						:toBe(world.engine.types.Enum.SelectionBehavior.Stop)
				end
				find(world.screen, "Shortcut").Pressed:Fire()
				Verify.expect(shortcuts):toBe(0)
				Verify.expect((enabledCount(world.screen, "ModalBack"))):toBe(1)
				local activate = action(world.screen, "Activate")
				Verify.expect(activate ~= nil):toBe(true)
				activate.Pressed:Fire()
				Verify.expect(confirmed):toBe(1)
				Verify.expect((inner:peek())):toBe(false)
				find(world.screen, "Shortcut").Pressed:Fire()
				Verify.expect(shortcuts):toBe(1)
				world.stop()
			end,
		})

		verifyHarness:case(
			"routes activation to the selected control of the top modal and survives a re-entrant dismiss",
			{
				id = "native_parity_weaker_surfaces::presented surface strength::routes activation to the selected control of the top modal and survives a re-entrant dismiss",
				run = function()
					local presented, music, yes = Compose.cell(false), 0, 0
					local world = setup(function(UI: FacetControls, Host: RobloxHost, _, gui)
						local base = UI.Button "Music" {
							label = "Music",
							onActivate = function()
								music += 1
							end,
						}
						gui.SelectedObject = base
						return Host.Frame({
							base :: unknown,
							UI.Alert({
								isPresented = presented,
								title = "Apply?",
								actions = {
									{
										id = "Yes",
										label = "Yes",
										onActivate = function()
											yes += 1
											presented:set(false)
										end,
									} :: FixtureNavigationTypes.AlertAction<any>,
									{ id = "No", label = "No", role = "cancel" :: "cancel" } :: FixtureNavigationTypes.AlertAction<any>,
								},
							}),
						})
					end)
					local base = find(world.screen, "Music")
					presented:set(true)
					local yesButton = find(world.screen, "Yes")
					Verify.expect(world.gui.SelectedObject):toBe(yesButton)
					local activate = action(world.screen, "Activate")
					Verify.expect((within(activate.Parent, world.screen))):toBe(true)
					base.Activated:Fire()
					Verify.expect(music):toBe(0)
					activate.Pressed:Fire()
					Verify.expect(yes):toBe(1)
					Verify.expect(music):toBe(0)
					Verify.expect((presented:peek())):toBe(false)
					Verify.expect((find(world.screen, "AlertModal"))):toBe(nil)
					Verify.expect(world.gui.SelectedObject):toBe(base)
					local baseActivate = action(world.screen, "Activate")
					Verify.expect(baseActivate ~= nil):toBe(true)
					baseActivate.Pressed:Fire()
					Verify.expect(music):toBe(1)
					Verify.expect(yes):toBe(1)
					world.stop()
				end,
			}
		)

		verifyHarness:case("traps and cancels the confirmation tutorial and restores the delete trigger", {
			id = "native_parity_weaker_surfaces::presented surface strength::traps and cancels the confirmation tutorial and restores the delete trigger",
			run = function()
				local built: any
				local world = setup(function(UI: FacetControls, Host: RobloxHost, engine, _, runtime)
					built = require("../examples/gallery/examples/04_confirm_dialog").build({
						UI = UI,
						Host = Host,
						Compose = Compose,
						types = engine.types,
						runtime = runtime,
					})
					return built.screen()
				end)
				local delete = find(world.screen, "Delete")
				world.gui.SelectedObject = delete
				for round = 1, 2 do
					local open = action(world.screen, "Activate")
					Verify.expect(open ~= nil):toBe(true)
					open.Pressed:Fire()
					local panel = find(world.screen, "AlertPanel")
					Verify.expect(panel ~= nil):toBe(true)
					for _, direction in { "Up", "Down", "Left", "Right" } :: { "Down" | "Left" | "Right" | "Up" } do
						Verify.expect(panel["SelectionBehavior" .. direction])
							:toBe(world.engine.types.Enum.SelectionBehavior.Stop)
					end
					find(world.screen, "AlertModal").AbsoluteSize = world.engine.types.Vector2.new(1280, 800)
					local cancel, confirm = find(world.screen, "Cancel"), find(world.screen, "Confirm")
					Verify.expect(world.gui.SelectedObject):toBe(cancel)
					Verify.expect(cancel.LayoutOrder < confirm.LayoutOrder):toBe(true)
					Verify.expect(find(world.screen, "Actions"):FindFirstChildWhichIsA("UIListLayout").FillDirection)
						:toBe(world.engine.types.Enum.FillDirection.Horizontal)
					delete.Activated:Fire()
					Verify.expect(#all(world.screen, "AlertModal")):toBe(1)
					if round == 1 then
						find(world.screen, "ModalBack").Pressed:Fire()
					else
						action(world.screen, "Activate").Pressed:Fire()
					end
					Verify.expect((find(world.screen, "AlertModal"))):toBe(nil)
					Verify.expect((built.result())):toBe("cancelled")
					Verify.expect((built.hasSave())):toBe(true)
					Verify.expect(world.gui.SelectedObject):toBe(delete)
				end
				world.stop()
			end,
		})
	end)

	verifyHarness:suite("gallery toast strength", function()
		verifyHarness:case(
			"shows a burst through UI.Toast: three visible, eight waiting, the least urgent newest dropped",
			{
				id = "native_parity_weaker_surfaces::gallery toast strength::shows a burst through UI.Toast: three visible, eight waiting, the least urgent newest dropped",
				run = function()
					local built, node, _, engine, _, close = mountScenario("sponsor_toast", true)
					find(node, "Burst").Activated:Fire()
					engine.heartbeat:Fire(1 / 60)
					local report = built.report()
					Verify.expect(report.visible):toBe(3)
					Verify.expect(report.queued):toBe(8)
					Verify.expect(report.dropped):toBe(1)
					Verify.expect(#toasts(node)):toBe(3)
					for _, row in report.rows do
						Verify.expect(row.title ~= "Burst 12" or report.states[row.id] == "exiting"):toBe(true)
					end
					advance(engine, 8)
					report = built.report()
					Verify.expect(report.visible):toBe(0)
					Verify.expect(report.queued):toBe(0)
					Verify.expect(#report.rows):toBe(0)
					Verify.expect(#toasts(node)):toBe(0)
					close()
				end,
			}
		)

		verifyHarness:case("keeps reduced-motion toasts on screen for the same durations as animated ones", {
			id = "native_parity_weaker_surfaces::gallery toast strength::keeps reduced-motion toasts on screen for the same durations as animated ones",
			run = function()
				local function run(reduced: boolean): string
					local built, node, _, engine, _, close = mountScenario("sponsor_toast", reduced)
					find(node, "Burst").Activated:Fire()
					local samples = {}
					for _ = 1, 80 do
						advance(engine, 0.1)
						local report = built.report()
						table.insert(samples, report.visible .. "/" .. report.queued)
					end
					close()
					return table.concat(samples, ",")
				end
				local full = run(false)
				Verify.expect((run(true))):toBe(full)
				Verify.expect((string.sub(full, -3))):toBe("0/0")
			end,
		})

		verifyHarness:case("clears showing toasts and returns the rows, instances and frame clock", {
			id = "native_parity_weaker_surfaces::gallery toast strength::clears showing toasts and returns the rows, instances and frame clock",
			run = function()
				local built, node, _, engine, _, close = mountScenario("sponsor_toast", true)
				engine.heartbeat:Fire(1 / 60)
				local baseline = #node:GetDescendants()
				for i = 1, 3 do
					built.show("Held " .. i, "Long", { duration = 20 })
				end
				engine.heartbeat:Fire(1 / 60)
				Verify.expect(#toasts(node)):toBe(3)
				find(node, "Clear").Activated:Fire()
				engine.heartbeat:Fire(1 / 60)
				Verify.expect(built.report().visible):toBe(0)
				advance(engine, 0.5, 1 / 60)
				Verify.expect(#built.report().rows):toBe(0)
				Verify.expect(#toasts(node)):toBe(0)
				Verify.expect(#node:GetDescendants()):toBe(baseline)
				close()
				Verify.expect((engineLib.connections(engine.heartbeat))):toBe(0)
			end,
		})

		verifyHarness:case("leaves the selection and the control beneath untouched while a toast shows", {
			id = "native_parity_weaker_surfaces::gallery toast strength::leaves the selection and the control beneath untouched while a toast shows",
			run = function()
				local built, node, ctx, engine, target, close = mountScenario("sponsor_toast")
				local beneath = find(node, "Beneath")
				ctx.guiService.SelectedObject = beneath
				built.steps.send()
				advance(engine, 0.3)
				Verify.expect(ctx.guiService.SelectedObject):toBe(beneath)
				Verify.expect((find(node, "DismissOutside"))):toBe(nil)
				Verify.expect((find(node, "ModalBack"))):toBe(nil)
				local row = toasts(node)[1]
				Verify.expect(row.Interactable):toBe(false)
				for _, part in row:GetDescendants() do
					if part:IsA("GuiObject") then
						Verify.expect(part:IsA("GuiButton") or part:IsA("TextBox")):toBe(false)
						Verify.expect(part.Selectable):toBe(false)
					end
				end
				local activate = action(target, "Activate")
				Verify.expect(activate ~= nil):toBe(true)
				activate.Pressed:Fire()
				Verify.expect(built.report().presses):toBe(1)
				Verify.expect(built.report().visible):toBe(1)
				built.steps.clear()
				advance(engine, 0.5)
				Verify.expect(ctx.guiService.SelectedObject):toBe(beneath)
				close()
			end,
		})

		verifyHarness:case("a wide toast fills its edge; a fit-content toast hugs its lines up to the width cap", {
			id = "native_parity_weaker_surfaces::gallery toast strength::a wide toast fills its edge; a fit-content toast hugs its lines up to the width cap",
			run = function()
				local built, node, ctx, engine, _, close = mountScenario("sponsor_toast", true)
				local E = ctx.types.Enum
				node.AbsoluteSize = ctx.types.Vector2.new(1280, 720)
				built.show("Saved", "Done")
				engine.heartbeat:Fire(1 / 60)
				local wide = toasts(node)[1]
				Verify.expect(wide.AutomaticSize):toBe(E.AutomaticSize.Y)
				Verify.expect((wide:FindFirstChild("WidthCap"))):toBe(nil)
				for _, name in { "Title", "Detail" } do
					local text = find(wide, name)
					Verify.expect(text.Size.X.Scale):toBe(1)
					Verify.expect(text.TextWrapped):toBe(true)
				end
				built.steps.clear()
				advance(engine, 0.5)
				built.width:set("hug")
				built.show("Notice", "A single transient message")
				engine.heartbeat:Fire(1 / 60)
				local fit = toasts(node)[1]
				Verify.expect(fit.AutomaticSize):toBe(E.AutomaticSize.XY)
				Verify.expect(fit.AnchorPoint.X):toBe(0.5)
				Verify.expect(find(fit, "WidthCap").MaxSize.X):toBe(560)
				Verify.expect(find(fit, "Body").AutomaticSize):toBe(E.AutomaticSize.XY)
				for _, name in { "Title", "Detail" } do
					local text = find(fit, name)
					Verify.expect(text.Size.X.Scale):toBe(0)
					Verify.expect(text.AutomaticSize):toBe(E.AutomaticSize.XY)
					Verify.expect(text.TextWrapped):toBe(true)
				end
				close()
			end,
		})

		verifyHarness:case("docks each new toast on the chosen edge", {
			id = "native_parity_weaker_surfaces::gallery toast strength::docks each new toast on the chosen edge",
			run = function()
				local built, node, _, engine, _, close = mountScenario("sponsor_toast", true)
				built.show("Bottom", "Default edge", { duration = 20 })
				engine.heartbeat:Fire(1 / 60)
				Verify.expect(toasts(node)[1].AnchorPoint.Y):toBe(1)
				built.edge:set("top")
				built.show("Top", "Chosen edge", { duration = 20 })
				engine.heartbeat:Fire(1 / 60)
				local edges = {}
				for _, card in toasts(node) do
					edges[find(card, "Title").Text] = card.AnchorPoint.Y
				end
				Verify.expect(edges.Bottom):toBe(1)
				Verify.expect(edges.Top):toBe(0)
				close()
			end,
		})

		verifyHarness:case("a same-subject toast supersedes the showing one after its read floor", {
			id = "native_parity_weaker_surfaces::gallery toast strength::a same-subject toast supersedes the showing one after its read floor",
			run = function()
				local built, node, _, engine, _, close = mountScenario("sponsor_toast", true)
				built.show("lap 1", "first", { subject = "lap", duration = 30 })
				engine.heartbeat:Fire(1 / 60)
				built.show("lap 2", "second", { subject = "lap", duration = 30 })
				engine.heartbeat:Fire(1 / 60)
				Verify.expect((visibleTitles(node))):toBe("lap 1")
				advance(engine, 3)
				Verify.expect((visibleTitles(node))):toBe("lap 2")
				Verify.expect(built.report().superseded):toBe(1)
				close()
			end,
		})

		verifyHarness:case("dismisses showing and queued toasts by id, promotes the queue and ignores an unknown id", {
			id = "native_parity_weaker_surfaces::gallery toast strength::dismisses showing and queued toasts by id, promotes the queue and ignores an unknown id",
			run = function()
				local built, node, _, engine, _, close = mountScenario("sponsor_toast", true)
				local first = built.show("a", "a", { duration = 30 })
				for _, title in { "b", "c", "d" } do
					built.show(title, title, { duration = 30 })
				end
				local queued = built.show("e", "e", { duration = 30 })
				engine.heartbeat:Fire(1 / 60)
				Verify.expect(built.report().queued):toBe(2)
				built.dismiss(queued)
				engine.heartbeat:Fire(1 / 60)
				Verify.expect((visibleTitles(node))):toBe("a,b,c")
				Verify.expect(built.report().queued):toBe(1)
				built.dismiss(first)
				advance(engine, 0.1)
				Verify.expect((visibleTitles(node))):toBe("b,c,d")
				Verify.expect(built.report().queued):toBe(0)
				Verify.expect((pcall(built.dismiss, 9999))):toBe(true)
				built.steps.clear()
				advance(engine, 0.5)
				Verify.expect(built.report().visible):toBe(0)
				Verify.expect(#built.report().rows):toBe(0)
				close()
			end,
		})
	end)

	verifyHarness:suite("gallery surface page strength", function()
		verifyHarness:case("offers toasts under Indicators; a shown toast outlives the page and expires on time", {
			id = "native_parity_weaker_surfaces::gallery surface page strength::offers toasts under Indicators; a shown toast outlives the page and expires on time",
			run = function()
				local built, node, _, engine, _, close = mountScenario("all_controls")
				local function visibleInTree(part: any): boolean
					local at = part
					while at and at ~= node do
						if at:IsA("GuiObject") and not at.Visible then
							return false
						end
						at = at.Parent
					end
					return true
				end
				find(node, "indicators").Activated:Fire()
				find(node, "toasts").Activated:Fire()
				Verify.expect(built.report().active):toBe("toasts")
				local toastLab = built.report().example
				Verify.expect(toastLab ~= nil):toBe(true)
				find(node, "Send").Activated:Fire()
				local page = built.report()
				Verify.expect(page.example.visible):toBe(1)
				local messages = find(node, "Messages")
				Verify.expect((visibleInTree(toasts(node)[1]))):toBe(true)
				find(node, "Beneath").Activated:Fire()
				Verify.expect(built.report().example.presses):toBe(1)
				Verify.expect(built.report().example.visible):toBe(1)
				find(node, "progress").Activated:Fire()
				Verify.expect(built.report().active):toBe("progress")
				Verify.expect((visibleInTree(messages))):toBe(false)
				Verify.expect((visibleInTree(toasts(node)[1]))):toBe(true)
				advance(engine, 4.6)
				Verify.expect((find(node, "Messages"))):toBe(messages)
				Verify.expect(#toasts(node)):toBe(0)
				find(node, "toasts").Activated:Fire()
				Verify.expect(built.report().active):toBe("toasts")
				local back = built.report().example
				Verify.expect(back.visible):toBe(0)
				Verify.expect(back.queued):toBe(0)
				Verify.expect(back.presses):toBe(1)
				Verify.expect((find(node, "Messages"))):toBe(messages)
				Verify.expect((visibleInTree(messages))):toBe(true)
				close()
			end,
		})
	end)

	verifyHarness:suite("virtual monitors surface strength", function()
		verifyHarness:case(
			"names the live look in the rich HUD and degrades it to a compact summary under space pressure",
			{
				id = "native_parity_weaker_surfaces::virtual monitors surface strength::names the live look in the rich HUD and degrades it to a compact summary under space pressure",
				run = function()
					withMonitors(function(world)
						local avatar, model, V = world.Avatar, world.model, world.engine.types.Vector2
						local body = find(avatar, "AvatarBody")
						body.AbsoluteSize = V.new(1920, 1080)
						for _, id in { "Look", "Rotation", "Spin" } do
							Verify.expect(find(avatar, id .. "Rich") ~= nil):toBe(true)
							Verify.expect((find(avatar, "Expand" .. id))):toBe(nil)
						end
						Verify.expect(find(avatar, "LookRich").Text):toBe("Sage · Hat on")
						model.hat:set(false)
						Verify.expect(find(avatar, "LookRich").Text):toBe("Sage · Hat off")
						model.hat:set(true)
						body.AbsoluteSize = V.new(393, 852)
						for _, id in { "Look", "Rotation", "Spin" } do
							Verify.expect((find(avatar, id .. "Rich"))):toBe(nil)
							Verify.expect(find(avatar, "Expand" .. id) ~= nil):toBe(true)
						end
						Verify.expect(find(avatar, "LookHUD").Size.Y.Offset):toBe(32)
						Verify.expect(find(avatar, "ExpandLook").Text):toBe("Sage")
						find(avatar, "ExpandLook").Activated:Fire()
						Verify.expect((model.avatarSummary:peek())):toBe(true)
						Verify.expect(find(find(world.target, "SummaryPalette"), "Value").Text):toBe("Sage")
						Verify.expect(find(find(world.target, "SummaryHat"), "Value").Text):toBe("On")
						find(world.target, "DismissOutside").Activated:Fire({ Position = V.new(4, 4) })
						Verify.expect((model.avatarSummary:peek())):toBe(false)
						Verify.expect((find(world.target, "SheetPanel"))):toBe(nil)
					end)
				end,
			}
		)

		verifyHarness:case("presents the look summary from its button and collapses tips without a leftover overlay", {
			id = "native_parity_weaker_surfaces::virtual monitors surface strength::presents the look summary from its button and collapses tips without a leftover overlay",
			run = function()
				withMonitors(function(world)
					local avatar, model, V = world.Avatar, world.model, world.engine.types.Vector2
					find(avatar, "AvatarBody").AbsoluteSize = V.new(920, 1100)
					model.palette:set("clay")
					model.hat:set(false)
					model.angle:set(30)
					model.autoSpin:set(3)
					Verify.expect((find(world.target, "SheetPanel"))):toBe(nil)
					find(avatar, "Summary").Activated:Fire()
					local expected: { [string]: string } =
						{ Palette = "Clay", Hat = "Off", Rotation = "30°", AutoSpin = "Fast" }
					for id, value in expected do
						Verify.expect(find(find(world.target, "Summary" .. id), "Value").Text):toBe(value)
					end
					find(world.target, "Done").Activated:Fire()
					Verify.expect((find(world.target, "SheetPanel"))):toBe(nil)
					Verify.expect((find(world.target, "TurnTips"))):toBe(nil)
					find(avatar, "Tips").Activated:Fire()
					Verify.expect((model.avatarTipsExpanded:peek())):toBe(true)
					Verify.expect(find(world.target, "TurnTips").Text):toBe(
						"Turn step sets the increment for Rotation and both Turn buttons. Use the stepper to choose 15°, 30°, 45° or 90°."
					)
					find(world.target, "DismissOutside").Activated:Fire()
					Verify.expect((model.avatarTipsExpanded:peek())):toBe(false)
					Verify.expect((find(world.target, "TurnTips"))):toBe(nil)
					Verify.expect((find(world.target, "Expanded"))):toBe(nil)
					Verify.expect((find(world.target, "DismissOutside"))):toBe(nil)
					find(avatar, "Tips").Activated:Fire()
					Verify.expect(find(world.target, "TurnTips") ~= nil):toBe(true)
					find(find(world.target, "Expanded"), "Close").Activated:Fire()
					Verify.expect((find(world.target, "Expanded"))):toBe(nil)
				end)
			end,
		})

		verifyHarness:case("anchors the about this rating popover to its line and dismisses it on an outside tap", {
			id = "native_parity_weaker_surfaces::virtual monitors surface strength::anchors the about this rating popover to its line and dismisses it on an outside tap",
			run = function()
				withMonitors(function(world)
					local model, V, Enum = world.model, world.engine.types.Vector2, world.engine.types.Enum
					world.target.AbsoluteSize = V.new(920, 640)
					find(world.Discover, "Games").AbsoluteWindowSize = V.new(850, 260)
					model.selectGame(model.catalog.items:peek()[1])
					Verify.expect((find(world.target, "CalloutPanel"))):toBe(nil)
					local anchor = find(world.target, "AboutRating")
					anchor.AbsolutePosition = V.new(300, 200)
					anchor.AbsoluteSize = V.new(320, 36)
					anchor.Activated:Fire()
					local panel = find(world.target, "CalloutPanel")
					Verify.expect(panel ~= nil):toBe(true)
					Verify.expect(find(panel, "RatingMeaning") ~= nil):toBe(true)
					panel.AbsoluteSize = V.new(280, 90)
					local left, top = corner(panel)
					Verify.expect((near(top, 200 + 36 + 8 + LIFT))):toBe(true)
					Verify.expect(left):toBe(300 + (320 - 280) / 2)
					panel.AbsolutePosition = V.new(320, 244)
					world.input.InputBegan:Fire(
						{ UserInputType = Enum.UserInputType.MouseButton1, Position = V.new(400, 280) },
						false
					)
					Verify.expect((find(world.target, "CalloutPanel"))):toBe(panel)
					world.input.InputBegan:Fire(
						{ UserInputType = Enum.UserInputType.Touch, Position = V.new(20, 600) },
						false
					)
					Verify.expect((panel:isDestroyed())):toBe(true)
					Verify.expect((find(world.target, "RatingMeaning"))):toBe(nil)
					find(world.target, "AboutRating").Activated:Fire()
					Verify.expect(find(world.target, "RatingMeaning") ~= nil):toBe(true)
				end)
			end,
		})
	end)
end
