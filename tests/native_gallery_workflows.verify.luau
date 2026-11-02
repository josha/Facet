--!strict
local Verify = require("../tools/vendor/verify/src/core")
local Bdd = require("../tools/vendor/verify/src/bdd")

return function(verifyHarness: Verify.Harness)
	local test = Bdd.create(verifyHarness)
	local describe, it, expect = test.describe, test.it, test.expect
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type Environment = typeof(require("@repo/tools/typecheck/aliases").ControlOptions.environment)
	type ExampleContext = typeof(require("@repo/examples/types").Context)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local Compose: ComposeModule = Facet.Compose

	local function nativeContext(environment: Environment)
		local engine = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local viewport = Compose.cell({ width = 1280, height = 720 })
		local target = engine.new("Folder")
		local guiService = engine.new("GuiService")
		local ctx: any = {
			Facet = Facet,
			Compose = Compose,
			runtime = runtime,
			Host = Facet.host(runtime),
			types = engine.types,
			viewport = viewport,
			inputTarget = target,
			worldTarget = engine.new("Folder"),
			guiService = guiService,
			runService = { Heartbeat = engine.heartbeat },
			UI = Facet.controls(runtime, {
				types = engine.types,
				viewport = viewport,
				guiService = guiService,
				services = { GuiService = guiService },
				inputParent = target,
				motionLevel = "none",
				environment = environment,
			}),
		}
		return ctx, engine, target
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

	type Screen = { read screen: () -> Instance, read dispose: (() -> ())? }
	local function mount<G>(definition: { read build: (ExampleContext) -> G & Screen }, environment: Environment)
		local ctx, engine, target = nativeContext(environment)
		local built: (G & Screen)? = nil
		local scope: ExampleContext = ctx
		local runtime: Facet.Runtime = ctx.runtime
		local stop, node = runtime.mount(function(): Instance
			local result = definition.build(scope)
			built = result
			if result.dispose then
				Compose.cleanup(result.dispose)
			end
			return scope.Host.ScreenGui "DemoScreen" { result.screen() }
		end, target)
		return assert(built), node, function()
			stop()
			ctx.runtime:dispose()
		end, ctx, engine
	end

	describe("native gallery workflows", function()
		it("keeps restored search results between Search and the next field", {
			id = "native_gallery_workflows::native gallery workflows::keeps restored search results between Search and the next field",
			run = function()
				local built, node, stop = mount(require("../examples/gallery/scenarios/text_controls"), nil)
				local search = find(node, "Search")
				local body = find(node, "Body")
				local function result()
					for _, child in body:GetChildren() do
						if child:IsA("TextLabel") and child.Text == "Coastal circuit" then
							return child
						end
					end
					return nil
				end
				expect(result().LayoutOrder > search.LayoutOrder):toBe(true)
				local field = search:FindFirstChildWhichIsA("TextBox", true)
				field:CaptureFocus()
				field.Text = "no matching record"
				field:ReleaseFocus()
				find(search, "Clear").Activated:Fire()
				local restored = result()
				expect(restored ~= nil):toBe(true)
				expect(restored.LayoutOrder > search.LayoutOrder):toBe(true)
				expect(restored.LayoutOrder < find(node, "Laps").LayoutOrder):toBe(true)
				stop()
			end,
		})
		it("allocates a natural rail slot", {
			id = "native_gallery_workflows::native gallery workflows::allocates a natural rail slot",
			run = function()
				local _, node, stop, ctx, engine =
					mount(require("../examples/gallery/scenarios/adaptive_controls"), nil)
				local row = find(node, "NavRailRow")
				expect(row:FindFirstChildWhichIsA("UIListLayout").FillDirection):toBe(
					ctx.types.Enum.FillDirection.Horizontal
				)
				expect(find(node, "NavRail").Size.X.Offset):toBe(0)
				expect(find(node, "NavRail").Size.X.Scale):toBe(0)
				expect(find(node, "NavRail").AutomaticSize):toBe(ctx.types.Enum.AutomaticSize.XY)
				local option = find(node, "NavRail"):FindFirstChild("browse")
				expect(option.Size.X.Scale):toBe(0)
				expect(option.AutomaticSize):toBe(ctx.types.Enum.AutomaticSize.XY)
				expect(find(node, "NavReadout"):FindFirstChildWhichIsA("UIFlexItem").FlexMode):toBe(
					ctx.types.Enum.UIFlexMode.Fill
				)
				stop()
			end,
		})
		it("bounds fixed Lab previews to their room", {
			id = "native_gallery_workflows::native gallery workflows::bounds fixed Lab previews to their room",
			run = function()
				local ctx, engine = nativeContext(nil)
				local available = Compose.cell(365)
				local factory = require("../examples/facet-lab/src/variant_cell")
				local root: Frame? = nil
				local scope: ExampleContext = ctx
				local runtime: Facet.Runtime = ctx.runtime
				local close = runtime.mount(function(): Instance
					local result = factory(scope.UI, { width = 460, height = 200 }, available)
					root = result
					return result
				end, engine.new("ScreenGui"))
				local bounds = assert(assert(root):FindFirstChildWhichIsA("UISizeConstraint"))
				expect(bounds.MaxSize.X):toBe(365)
				available:set(300)
				expect(bounds.MaxSize.X):toBe(300)
				close()
				ctx.runtime:dispose()
			end,
		})
		it("fits every word keyboard key and crossword rack slot in a narrow row", {
			id = "native_gallery_workflows::native gallery workflows::fits every word keyboard key and crossword rack slot in a narrow row",
			run = function()
				local word, node, stop, ctx = mount(require("../examples/gallery/examples/05_word_game"), nil)
				for row = 1, 2 do
					local keys = find(node, "kbrow" .. row)
					local layout = keys:FindFirstChildWhichIsA("UIListLayout")
					for _, width in { 240, 288, 369, 472 } do
						local total, count = 0, 0
						for _, key in keys:GetChildren() do
							if key:IsA("GuiButton") then
								expect(key.AutomaticSize):toBe(ctx.types.Enum.AutomaticSize.None)
								local extent = key.Size.X.Scale * width + key.Size.X.Offset
								expect(extent >= 20):toBe(true)
								total += extent
								count += 1
							end
						end
						expect(count):toBe(if row == 1 then 10 else 9)
						total += (count - 1) * layout.Padding.Offset
						expect(total <= width + 0.001 and total >= width - 10):toBe(true)
					end
				end
				local cap = find(node, "kb"):FindFirstChildWhichIsA("UISizeConstraint")
				expect(cap.MaxSize.X):toBe(640)
				expect(cap.MinSize.X):toBe(0)
				local finalRow = find(node, "kbrow3")
				expect(finalRow.Size.X.Scale):toBe(1)
				local count = 0
				for _, key in finalRow:GetChildren() do
					if key:IsA("GuiButton") then
						local command = key.Name == "key_Enter" or key.Name == "key_Back"
						expect(key.AutomaticSize):toBe(ctx.types.Enum.AutomaticSize.None)
						local flex = key:FindFirstChildWhichIsA("UIFlexItem")
						if command then
							expect(`{flex.FlexMode.Name} {flex.GrowRatio}`):toBe("Custom 1.5")
						else
							expect(flex.FlexMode):toBe(ctx.types.Enum.UIFlexMode.Fill)
						end
						expect(key.TextWrapped):toBe(false)
						expect(key.Size.Y.Offset):toBe(44)
						count += 1
					end
				end
				expect(count):toBe(9)

				find(node, "key_O").Activated:Fire()
				find(node, "key_P").Activated:Fire()
				expect((word.row(1))):toBe("OP")
				find(node, "key_Back").Activated:Fire()
				expect((word.row(1))):toBe("O")
				find(node, "key_Enter").Activated:Fire()
				expect((word.activeRow())):toBe(1)
				expect(word.status():find("Not enough letters", 1, true) ~= nil):toBe(true)
				stop()
				local crossword, cross, close, crossCtx =
					mount(require("../examples/gallery/examples/06_tile_game"), nil)
				local rack = find(cross, "rack")
				local grid = rack:FindFirstChildWhichIsA("UIGridLayout")
				for _, width in { 240, 288, 360 } do
					local total = 7 * (grid.CellSize.X.Scale * width + grid.CellSize.X.Offset)
						+ 6 * grid.CellPadding.X.Offset
					expect(total <= width + 0.001 and total >= width - 10):toBe(true)
				end
				for _, name in { "Stats", "Actions" } do
					local row = find(cross, name)
					expect((row:FindFirstChildWhichIsA("UIGridLayout"))):toBe(nil)
					expect(row:FindFirstChildWhichIsA("UIListLayout") ~= nil):toBe(true)
					expect(row.AutomaticSize):toBe(crossCtx.types.Enum.AutomaticSize.Y)
				end
				local letter = crossword.rackLetter(7)
				find(rack, "rt7").Activated:Fire()
				find(find(cross, "cell4_4"), "tap").Activated:Fire()
				expect((crossword.pendingAt(4, 4))):toBe(letter)
				find(find(cross, "Actions"), "Undo").Activated:Fire()
				expect((crossword.rackLetter(7))):toBe(letter)
				close()
			end,
		})

		it("keeps Basics settings and numeric layout order across viewport changes", {
			id = "native_gallery_workflows::native gallery workflows::keeps Basics settings and numeric layout order across viewport changes",
			run = function()
				local built, node, stop, ctx, engine =
					mount(require("../examples/gallery/scenarios/adaptive_controls"), nil)
				local volume = find(node, "Volume")
				find(volume, "Increase").Activated:Fire()
				local current = built.report().volume
				for _, width in { 390, 1280, 800, 1280 } do
					ctx.viewport:set({ width = width, height = 720 })
					expect((find(node, "Volume"))):toBe(volume)
					expect(built.report().volume):toBe(current)
					expect(find(node, "Settings").Size.X.Scale):toBe(if width >= 900 then 0.5 else 1)
				end
				for i = 1, 12 do
					expect(find(node, "Stat" .. i).LayoutOrder):toBe(i)
				end
				local footer = find(node, "Actions")
				expect(find(footer, "Save").LayoutOrder < find(footer, "Reset").LayoutOrder):toBe(true)
				find(node, "Save").Activated:Fire()
				expect(built.report().saved):toBe(true)
				find(node, "Reset").Activated:Fire()
				expect(built.report().volume):toBe(6)
				stop()
			end,
		})
		it("sizes the Basics action row from its buttons, not a fixed band (owner M6: TV clipped them)", {
			id = "native_gallery_workflows::native gallery workflows::sizes the Basics action row from its buttons, not a fixed band (owner M6: TV clipped them)",
			run = function()
				local distances: { "near" | "ten-foot" } = { "near", "ten-foot" }
				for _, distance in distances do
					local _, node, stop, ctx = mount(
						require("../examples/gallery/scenarios/adaptive_controls"),
						{ viewingDistance = distance }
					)
					local Enum = ctx.types.Enum
					local footer = find(node, "Actions")
					local cap = footer:FindFirstChildWhichIsA("UISizeConstraint")
					expect(footer.AutomaticSize):toBe(Enum.AutomaticSize.Y)
					expect((footer:FindFirstChildWhichIsA("UIGridLayout"))):toBe(nil)
					local floor = if distance == "ten-foot" then 66 else 44
					for _, name in { "Save", "Reset", "Delete" } do
						local button = find(footer, name)
						local height = button.Size.Y.Offset
						local room = math.max(footer.Size.Y.Offset, if cap then cap.MaxSize.Y else math.huge)
						expect(`{distance} {name} {height} fits {room >= height}`):toBe(
							`{distance} {name} {floor} fits true`
						)
					end
					local body = find(node, "BodyScroll")
					expect(body.Size.Y.Offset):toBe(0)
					expect(body:FindFirstChildWhichIsA("UIFlexItem") ~= nil):toBe(true)
					stop()
				end
			end,
		})

		it("reflows one recipe action set and preserves controlled checks and keyed chips", {
			id = "native_gallery_workflows::native gallery workflows::reflows one recipe action set and preserves controlled checks and keyed chips",
			run = function()
				local built, node, stop, ctx, engine =
					mount(require("../examples/gallery/scenarios/recipes_common"), nil)
				local actions = find(node, "Actions")
				local save = find(actions, "Save")
				engine.environment.poke(actions, "AbsoluteSize", ctx.types.Vector2.new(700, 44))
				for name, width in { Cancel = 48, Save = 200, Delete = 80 } :: { [string]: number } do
					engine.environment.poke(
						find(find(actions, name), "NaturalWidth"),
						"TextBounds",
						ctx.types.Vector2.new(width, 20)
					)
				end
				for _, form in { "column", "row", "column" } :: { "column" | "row" } do
					if form == "column" then
						built.steps.narrowActions()
					else
						built.steps.wideActions()
					end
					expect(built.report().actionsForm):toBe(form)
					expect((find(actions, "Save"))):toBe(save)
					expect(find(actions, "UIListLayout").FillDirection):toBe(
						if form == "row"
							then ctx.types.Enum.FillDirection.Horizontal
							else ctx.types.Enum.FillDirection.Vertical
					)
					save.Activated:Fire()
				end
				expect(built.report().activations):toBe(3)
				built.steps.wideActions()
				engine.environment.poke(actions, "AbsoluteSize", ctx.types.Vector2.new(309, 44))
				engine.environment.poke(find(save, "NaturalWidth"), "TextBounds", ctx.types.Vector2.new(324, 32))
				expect(built.report().actionsForm):toBe("column")
				expect(save.Size.X.Scale):toBe(1)
				expect(save.Size.X.Offset):toBe(0)
				expect(save.AutomaticSize):toBe(ctx.types.Enum.AutomaticSize.Y)
				expect(save.TextWrapped):toBe(true)
				expect(save.Text):toBe("Save changes to this profile")
				engine.environment.poke(actions, "AbsoluteSize", ctx.types.Vector2.new(700, 44))
				expect(built.report().actionsForm):toBe("row")
				engine.environment.poke(find(save, "NaturalWidth"), "TextBounds", ctx.types.Vector2.new(700, 32))
				expect(built.report().actionsForm):toBe("column")
				engine.environment.poke(find(save, "NaturalWidth"), "TextBounds", ctx.types.Vector2.new(200, 20))
				expect(built.report().actionsForm):toBe("row")
				expect((find(actions, "Save"))):toBe(save)
				local fuel = find(find(node, "CheckboxGroup"), "fuel")
				fuel.Activated:Fire()
				expect(built.report().checks.fuel):toBe(true)
				built.steps.rejectChecks()
				fuel.Activated:Fire()
				expect(built.report().checks.fuel):toBe(true)
				expect(built.report().requests):toBe(2)
				built.steps.disableChecks()
				fuel.Activated:Fire()
				expect(built.report().requests):toBe(2)
				local rain = find(find(node, "WrapChips"), "Rain")
				rain.Activated:Fire()
				built.steps.reorderTags()
				expect((find(find(node, "WrapChips"), "Rain"))):toBe(rain)
				expect(built.report().wrapSelected.Rain):toBe(true)
				expect(rain.LayoutOrder):toBe(2)
				local actions: { { name: string, counter: "createCount" | "clearCount" | "retryCount" } } = {
					{ name = "EmptyCollection", counter = "createCount" },
					{ name = "NoResults", counter = "clearCount" },
					{ name = "LoadFailed", counter = "retryCount" },
				}
				for _, action in actions do
					find(find(node, action.name), "Action").Activated:Fire()
					local report = built.report()
					local count = if action.counter == "createCount"
						then report.createCount
						elseif action.counter == "clearCount" then report.clearCount
						else report.retryCount
					expect(count):toBe(1)
				end
				stop()
			end,
		})
		it("opens one recipe accordion body at a time and restores its header focus", {
			id = "native_gallery_workflows::native gallery workflows::opens one recipe accordion body at a time and restores its header focus",
			run = function()
				local built, node, stop, ctx, engine =
					mount(require("../examples/gallery/scenarios/recipes_common"), nil)
				local accordion = find(node, "Accordion")
				local names = { "Rules", "Setup", "Rewards" }
				local text = {
					Rules = "Standard lap count, no shortcuts, collisions on.",
					Setup = "Tire compound, gear ratio and ride height for this track.",
					Rewards = "Podium finishes bank currency toward the next kart unlock.",
				}
				local headers = {}
				for _, name in names do
					headers[name] = find(find(accordion, name), "Header")
					expect(headers[name].Selectable):toBe(true)
					expect((find(find(accordion, name), "Body"))):toBe(nil)
				end
				local previousBody
				for _, name in { "Rules", "Setup", "Rewards", "Rewards" } do
					local expected = if built.report().openSection == name then nil else name
					ctx.guiService.SelectedObject = headers[name]
					headers[name].Activated:Fire()
					expect(built.report().openSection):toBe(expected)
					expect(ctx.guiService.SelectedObject):toBe(headers[name])
					if previousBody then
						expect((previousBody:isDestroyed())):toBe(true)
					end
					for _, other in names do
						local section = find(accordion, other)
						expect((find(section, "Header"))):toBe(headers[other])
						local body = find(section, "Body")
						expect(body ~= nil):toBe(other == expected)
						if body then
							expect(body.Text):toBe(text[other])
							expect(body.TextWrapped):toBe(true)
							expect(body.AutomaticSize):toBe(ctx.types.Enum.AutomaticSize.Y)
							previousBody = body
						end
					end
				end
				headers.Rules.Activated:Fire()
				local body = find(find(accordion, "Rules"), "Body")
				body.Selectable = true
				ctx.guiService.SelectedObject = body
				expect(ctx.guiService.SelectedObject):toBe(body)
				headers.Rules.Activated:Fire()
				expect(ctx.guiService.SelectedObject):toBe(headers.Rules)
				expect((body:isDestroyed())):toBe(true)
				headers.Setup.Activated:Fire()
				built.reset()
				expect(built.report().openSection):toBe(nil)
				expect((find(accordion, "Body"))):toBe(nil)
				stop()
				for _, header in headers do
					expect((header:isDestroyed())):toBe(true)
				end
				expect(#ctx.inputTarget:GetChildren()):toBe(0)
			end,
		})

		it("applies shared and per-plate CanvasGroup opacity and owns the arrival tween", {
			id = "native_gallery_workflows::native gallery workflows::applies shared and per-plate CanvasGroup opacity and owns the arrival tween",
			run = function()
				local built, node, stop, ctx, engine = mount(require("../examples/gallery/scenarios/canvas_group"), nil)
				for _, opacity in { 1, 0.7, 0.15 } do
					built.opacity:set(opacity)
					expect(find(node, "OneGroup").GroupTransparency):toBe(1 - opacity)
					for i = 1, 3 do
						expect(find(find(node, "OneGroup"), "Plate" .. i).GroupTransparency):toBe(0)
						expect(find(find(node, "ManyGroups"), "Plate" .. i).GroupTransparency):toBe(1 - opacity)
					end
				end
				find(node, "Show").Activated:Fire()
				for _ = 1, 30 do
					engine.heartbeat:Fire(1 / 30)
				end
				expect(find(node, "Arrival").GroupTransparency):toBe(0)
				stop()
			end,
		})
		it("expires passive toasts while retaining access to the underlying action", {
			id = "native_gallery_workflows::native gallery workflows::expires passive toasts while retaining access to the underlying action",
			run = function()
				local built, node, stop, _, engine = mount(require("../examples/gallery/scenarios/sponsor_toast"), nil)
				find(node, "Send").Activated:Fire()
				expect(built.report().messages):toBe(1)
				local toast = find(node, "Toast")
				expect(toast.Active):toBe(false)
				expect(toast.Selectable):toBe(false)
				find(node, "Beneath").Activated:Fire()
				expect(built.report().presses):toBe(1)
				engine.heartbeat:Fire(4.1)
				expect(built.report().messages):toBe(0)
				engine.heartbeat:Fire(0.3)
				expect((toast:isDestroyed())):toBe(true)
				find(node, "Send").Activated:Fire()
				find(node, "Clear").Activated:Fire()
				expect(built.report().messages):toBe(0)
				stop()
			end,
		})
		it("moves and hides native map markers without remounting their controls", {
			id = "native_gallery_workflows::native gallery workflows::moves and hides native map markers without remounting their controls",
			run = function()
				local built, node, stop, ctx, engine =
					mount(require("../examples/gallery/scenarios/world_markers"), nil)
				local map = find(node, "Map")
				engine.environment.poke(map, "AbsoluteSize", ctx.types.Vector2.new(309, 360))
				local objective, supplies = find(map, "A"), find(map, "C")
				objective.Activated:Fire()
				expect(built.report().selected):toBe("Objective")
				find(node, "Move").Activated:Fire()
				expect((find(map, "A"))):toBe(objective)
				expect(find(objective, "Direction").Visible):toBe(true)
				expect(objective.Position.X.Offset + objective.Size.X.Offset <= map.AbsoluteSize.X):toBe(true)
				find(node, "Hide").Activated:Fire()
				expect(supplies.Visible):toBe(false)
				expect(objective.Visible):toBe(true)
				stop()
				expect((objective:isDestroyed())):toBe(true)
				expect((supplies:isDestroyed())):toBe(true)
				expect(#ctx.worldTarget:GetChildren()):toBe(0)
			end,
		})

		it("swipes the native mail list and deletes exactly the chosen message", {
			id = "native_gallery_workflows::native gallery workflows::swipes the native mail list and deletes exactly the chosen message",
			run = function()
				local _, node, stop, ctx, engine = mount(require("../examples/gallery/scenarios/row_actions"), nil)
				local row = find(node, "Row_m1")
				engine.environment.poke(row, "AbsoluteSize", ctx.types.Vector2.new(300, 64))
				local detector = row:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
				detector.DragStart:Fire(ctx.types.Vector2.new(250, 20))
				detector.DragContinue:Fire(ctx.types.Vector2.new(10, 20))
				detector.DragEnd:Fire()
				expect((find(node, "Row_m1"))):toBe(nil)
				expect(find(node, "Row_m2") ~= nil):toBe(true)
				stop()
			end,
		})
		it("honors locked selection pinned movement and protected deletion in RunSheet", {
			id = "native_gallery_workflows::native gallery workflows::honors locked selection pinned movement and protected deletion in RunSheet",
			run = function()
				local built, node, stop, ctx, engine =
					mount(require("../examples/gallery/scenarios/row_capabilities"), nil)
				local body = find(find(node, "RunSheet"), "Body")
				engine.environment.poke(body, "AbsoluteWindowSize", ctx.types.Vector2.new(500, 400))
				find(find(body, "warmup"), "RowHit").Activated:Fire()
				expect(built.report().selection.warmup):toBe(true)
				find(find(body, "notes"), "RowHit").Activated:Fire()
				expect(built.report().selection.warmup):toBe(true)
				expect(built.report().selection.notes):toBe(nil)
				expect(find(find(body, "grid"), "Move").Interactable):toBe(false)
				local protected = find(find(body, "main"), "delete")
				expect(protected.Interactable):toBe(false)
				protected.Activated:Fire()
				expect(#built.report().rows):toBe(5)
				stop()
			end,
		})
	end)
end
