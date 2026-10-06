--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type ExampleContext = typeof(require("@repo/examples/types").Context)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local catalogue = require("../examples/gallery/client/demo_picker")
	local Compose: ComposeModule = Facet.Compose

	local function nativeContext(environment)
		local engine = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local viewport = Compose.cell({ width = 1280, height = 720 })
		local target = engine.new("Folder")
		local guiService = engine.new("GuiService")
		local ctx: ExampleContext = {
			Facet = Facet,
			Compose = Compose,
			runtime = runtime,
			Host = (runtime.constructors :: unknown) :: RobloxHost,
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

	local function load(kind, name)
		return (require :: (any) -> any)(
			"../examples/gallery/" .. (if kind == "example" then "examples/" else "scenarios/") .. name
		)
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

	local function mount(name: string, kind: string?, environment: { [string]: any }?)
		local ctx, engine, target = nativeContext(environment)
		local built
		local stop, node = ctx.runtime.mount(function()
			built = load(kind or "fixture", name).build(ctx)
			if built.dispose then
				Compose.cleanup(built.dispose)
			end
			return ctx.Host.ScreenGui "DemoScreen" { built.screen() }
		end, target)
		return built, node, function()
			stop()
			ctx.runtime:dispose()
		end, ctx, engine
	end

	verifyHarness:suite("native gallery workflows", function()
		verifyHarness:case("fits every word keyboard key and crossword rack slot in a narrow row", {
			id = "native_gallery_workflows::native gallery workflows::fits every word keyboard key and crossword rack slot in a narrow row",
			run = function()
				local word, node, stop, ctx = mount("05_word_game", "example")
				for row = 1, 2 do
					local keys = find(node, "kbrow" .. row)
					local layout = keys:FindFirstChildWhichIsA("UIListLayout")
					for _, width in { 240, 288, 369, 472 } do
						local total, count = 0, 0
						for _, key in keys:GetChildren() do
							if key:IsA("GuiButton") then
								Verify.expect(key.AutomaticSize):toBe(ctx.types.Enum.AutomaticSize.None)
								local extent = key.Size.X.Scale * width + key.Size.X.Offset
								Verify.expect(extent >= 20):toBe(true)
								total += extent
								count += 1
							end
						end
						Verify.expect(count):toBe(if row == 1 then 10 else 9)
						total += (count - 1) * layout.Padding.Offset
						Verify.expect(total <= width + 0.001 and total >= width - 10):toBe(true)
					end
				end
				Verify.expect((find(node, "kb"):FindFirstChildWhichIsA("UISizeConstraint"))):toBeNil()
				local finalRow = find(node, "kbrow3")
				Verify.expect(finalRow.Size.X.Scale):toBe(1)
				local count = 0
				for _, key in finalRow:GetChildren() do
					if key:IsA("GuiButton") then
						local command = key.Name == "key_Enter" or key.Name == "key_Back"
						Verify.expect(key.AutomaticSize):toBe(ctx.types.Enum.AutomaticSize.None)
						local flex = key:FindFirstChildWhichIsA("UIFlexItem")
						if command then
							Verify.expect(`{flex.FlexMode.Name} {flex.GrowRatio}`):toBe("Custom 1.5")
						else
							Verify.expect(flex.FlexMode):toBe(ctx.types.Enum.UIFlexMode.Fill)
						end
						Verify.expect(key.TextWrapped):toBe(false)
						Verify.expect(key.Size.Y.Offset):toBe(44)
						count += 1
					end
				end
				Verify.expect(count):toBe(9)

				find(node, "key_O").Activated.fire()
				find(node, "key_P").Activated.fire()
				Verify.expect((word.row(1))):toBe("OP")
				find(node, "key_Back").Activated.fire()
				Verify.expect((word.row(1))):toBe("O")
				find(node, "key_Enter").Activated.fire()
				Verify.expect((word.activeRow())):toBe(1)
				Verify.expect(word.status():find("Not enough letters", 1, true) ~= nil):toBe(true)
				stop()
				local crossword, cross, close, crossCtx = mount("06_tile_game", "example")
				local rack = find(cross, "rack")
				local grid = rack:FindFirstChildWhichIsA("UIGridLayout")
				for _, width in { 240, 288, 360 } do
					local total = 7 * (grid.CellSize.X.Scale * width + grid.CellSize.X.Offset)
						+ 6 * grid.CellPadding.X.Offset
					Verify.expect(total <= width + 0.001 and total >= width - 10):toBe(true)
				end
				for _, name in { "Stats", "Actions" } do
					local row = find(cross, name)
					Verify.expect((row:FindFirstChildWhichIsA("UIGridLayout"))):toBe(nil)
					Verify.expect(row:FindFirstChildWhichIsA("UIListLayout") ~= nil):toBe(true)
					Verify.expect(row.AutomaticSize):toBe(crossCtx.types.Enum.AutomaticSize.Y)
				end
				local letter = crossword.rackLetter(7)
				find(rack, "rt7").Activated.fire()
				find(find(cross, "cell4_4"), "tap").Activated.fire()
				Verify.expect((crossword.pendingAt(4, 4))):toBe(letter)
				find(find(cross, "Actions"), "Undo").Activated.fire()
				Verify.expect((crossword.rackLetter(7))):toBe(letter)
				close()
			end,
		})

		verifyHarness:case("keeps Basics settings and numeric layout order across viewport changes", {
			id = "native_gallery_workflows::native gallery workflows::keeps Basics settings and numeric layout order across viewport changes",
			run = function()
				local built, node, stop, ctx = mount("adaptive_controls")
				local volume = find(node, "Volume")
				find(volume, "Increase").Activated.fire()
				local current = built.report().volume
				for _, width in { 390, 1280, 800, 1280 } do
					ctx.viewport:set({ width = width, height = 720 })
					Verify.expect((find(node, "Volume"))):toBe(volume)
					Verify.expect(built.report().volume):toBe(current)
					Verify.expect(find(node, "Settings").Size.X.Scale):toBe(if width >= 900 then 0.5 else 1)
				end
				for i = 1, 12 do
					Verify.expect(find(node, "Stat" .. i).LayoutOrder):toBe(i)
				end
				local footer = find(node, "Actions")
				Verify.expect(find(footer, "Save").LayoutOrder < find(footer, "Reset").LayoutOrder):toBe(true)
				find(node, "Save").Activated.fire()
				Verify.expect(built.report().saved):toBe(true)
				find(node, "Reset").Activated.fire()
				Verify.expect(built.report().volume):toBe(6)
				stop()
			end,
		})
		verifyHarness:case(
			"sizes the Basics action row from its buttons, not a fixed band (owner M6: TV clipped them)",
			{
				id = "native_gallery_workflows::native gallery workflows::sizes the Basics action row from its buttons, not a fixed band (owner M6: TV clipped them)",
				run = function()
					for _, distance in { "near", "ten-foot" } do
						local _, node, stop, ctx = mount("adaptive_controls", nil, { viewingDistance = distance })
						local Enum = ctx.types.Enum
						local footer = find(node, "Actions")
						local cap = footer:FindFirstChildWhichIsA("UISizeConstraint")
						Verify.expect(footer.AutomaticSize):toBe(Enum.AutomaticSize.Y)
						Verify.expect((footer:FindFirstChildWhichIsA("UIGridLayout"))):toBe(nil)
						local floor = if distance == "ten-foot" then 66 else 44
						for _, name in { "Save", "Reset", "Delete" } do
							local button = find(footer, name)
							local height = button.Size.Y.Offset
							local room = math.max(footer.Size.Y.Offset, if cap then cap.MaxSize.Y else math.huge)
							Verify.expect(`{distance} {name} {height} fits {room >= height}`)
								:toBe(`{distance} {name} {floor} fits true`)
						end
						local body = find(node, "BodyScroll")
						Verify.expect(body.Size.Y.Offset):toBe(0)
						Verify.expect(body:FindFirstChildWhichIsA("UIFlexItem") ~= nil):toBe(true)
						stop()
					end
				end,
			}
		)
		verifyHarness:case("paints the adaptive chips, count tiles and layout bars with the theme's control plate", {
			id = "native_gallery_workflows::native gallery workflows::paints the adaptive chips, count tiles and layout bars with the theme's control plate",
			run = function()
				local ctx, _, target = nativeContext()
				ctx.theme = Compose.cell((require("../examples/themes/fantasy_parchment").build(Facet.themes)))
				local stop, node = ctx.runtime.mount(function()
					return ctx.Host.ScreenGui "DemoScreen" { load("fixture", "adaptive_controls").build(ctx).screen() }
				end, target)
				local names = { "Tile1", "Tile4", "Optional", "Useful", "Essential" }
				for i = 1, 12 do
					table.insert(names, "Stat" .. i)
				end
				for _, name in names do
					local plate = find(node, name)
					Verify.expect(`{name} {plate:HasTag("facet-control")} {plate:HasTag("facet-skinned")}`)
						:toBe(`{name} true true`)
					local art = find(plate, "control1")
					Verify.expect(art.Image):toBe("rbxassetid://87220434497053")
					local parent = art.Parent
					while parent ~= plate.Parent do
						local lettered = parent:IsA("TextLabel") or parent:IsA("TextButton")
						Verify.expect(`{name} art inside text {lettered and parent.Text ~= ""}`)
							:toBe(`{name} art inside text false`)
						parent = parent.Parent
					end
				end
				stop()
				ctx.runtime:dispose()
			end,
		})

		verifyHarness:case("reflows one recipe action set and preserves controlled checks and keyed chips", {
			id = "native_gallery_workflows::native gallery workflows::reflows one recipe action set and preserves controlled checks and keyed chips",
			run = function()
				local built, node, stop, ctx = mount("recipes_common")
				local actions = find(node, "Actions")
				local save = find(actions, "Save")
				actions.AbsoluteSize = ctx.types.Vector2.new(700, 44)
				for name, width in { Cancel = 48, Save = 200, Delete = 80 } :: { [string]: number } do
					find(find(actions, name), "NaturalWidth").TextBounds = ctx.types.Vector2.new(width, 20)
				end
				for _, form in { "column", "row", "column" } :: { "column" | "row" } do
					if form == "column" then
						built.steps.narrowActions()
					else
						built.steps.wideActions()
					end
					Verify.expect(built.report().actionsForm):toBe(form)
					Verify.expect((find(actions, "Save"))):toBe(save)
					Verify.expect(find(actions, "UIListLayout").FillDirection):toBe(
						if form == "row"
							then ctx.types.Enum.FillDirection.Horizontal
							else ctx.types.Enum.FillDirection.Vertical
					)
					save.Activated.fire()
				end
				Verify.expect(built.report().activations):toBe(3)
				built.steps.wideActions()
				actions.AbsoluteSize = ctx.types.Vector2.new(309, 44)
				find(save, "NaturalWidth").TextBounds = ctx.types.Vector2.new(324, 32)
				Verify.expect(built.report().actionsForm):toBe("column")
				Verify.expect(save.Size.X.Scale):toBe(1)
				Verify.expect(save.Size.X.Offset):toBe(0)
				Verify.expect(save.AutomaticSize):toBe(ctx.types.Enum.AutomaticSize.Y)
				Verify.expect(save.TextWrapped):toBe(true)
				Verify.expect(save.Text):toBe("Save changes to this profile")
				actions.AbsoluteSize = ctx.types.Vector2.new(700, 44)
				Verify.expect(built.report().actionsForm):toBe("row")
				find(save, "NaturalWidth").TextBounds = ctx.types.Vector2.new(700, 32)
				Verify.expect(built.report().actionsForm):toBe("column")
				find(save, "NaturalWidth").TextBounds = ctx.types.Vector2.new(200, 20)
				Verify.expect(built.report().actionsForm):toBe("row")
				Verify.expect((find(actions, "Save"))):toBe(save)
				local fuel = find(find(node, "CheckboxGroup"), "fuel")
				fuel.Activated.fire()
				Verify.expect(built.report().checks.fuel):toBe(true)
				built.steps.rejectChecks()
				fuel.Activated.fire()
				Verify.expect(built.report().checks.fuel):toBe(true)
				Verify.expect(built.report().requests):toBe(2)
				built.steps.disableChecks()
				fuel.Activated.fire()
				Verify.expect(built.report().requests):toBe(2)
				local rain = find(find(node, "WrapChips"), "Rain")
				rain.Activated.fire()
				built.steps.reorderTags()
				Verify.expect((find(find(node, "WrapChips"), "Rain"))):toBe(rain)
				Verify.expect(built.report().wrapSelected.Rain):toBe(true)
				Verify.expect(rain.LayoutOrder):toBe(2)
				for _, entry in
					{
						{ "EmptyCollection", "createCount" },
						{ "NoResults", "clearCount" },
						{ "LoadFailed", "retryCount" },
					}
				do
					find(find(node, entry[1]), "Action").Activated.fire()
					Verify.expect(built.report()[entry[2]]):toBe(1)
				end
				stop()
			end,
		})
		verifyHarness:case("opens one recipe accordion body at a time and restores its header focus", {
			id = "native_gallery_workflows::native gallery workflows::opens one recipe accordion body at a time and restores its header focus",
			run = function()
				local built, node, stop, ctx = mount("recipes_common")
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
					Verify.expect(headers[name].Selectable):toBe(true)
					Verify.expect((find(find(accordion, name), "Body"))):toBe(nil)
				end
				local previousBody
				for _, name in { "Rules", "Setup", "Rewards", "Rewards" } do
					local expected = if built.report().openSection == name then nil else name
					ctx.guiService.SelectedObject = headers[name]
					headers[name].Activated.fire()
					Verify.expect(built.report().openSection):toBe(expected)
					Verify.expect(ctx.guiService.SelectedObject):toBe(headers[name])
					if previousBody then
						Verify.expect((previousBody.isDestroyed())):toBe(true)
					end
					for _, other in names do
						local section = find(accordion, other)
						Verify.expect((find(section, "Header"))):toBe(headers[other])
						local body = find(section, "Body")
						Verify.expect(body ~= nil):toBe(other == expected)
						if body then
							Verify.expect(body.Text):toBe(text[other])
							Verify.expect(body.TextWrapped):toBe(true)
							Verify.expect(body.AutomaticSize):toBe(ctx.types.Enum.AutomaticSize.Y)
							previousBody = body
						end
					end
				end
				headers.Rules.Activated.fire()
				local body = find(find(accordion, "Rules"), "Body")
				body.Selectable = true
				ctx.guiService.SelectedObject = body
				Verify.expect(ctx.guiService.SelectedObject):toBe(body)
				headers.Rules.Activated.fire()
				Verify.expect(ctx.guiService.SelectedObject):toBe(headers.Rules)
				Verify.expect((body.isDestroyed())):toBe(true)
				headers.Setup.Activated.fire()
				built.reset()
				Verify.expect(built.report().openSection):toBe(nil)
				Verify.expect((find(accordion, "Body"))):toBe(nil)
				stop()
				for _, header in headers do
					Verify.expect((header.isDestroyed())):toBe(true)
				end
				Verify.expect(#ctx.inputTarget:GetChildren()):toBe(0)
			end,
		})

		verifyHarness:case("applies shared and per-plate CanvasGroup opacity and owns the arrival tween", {
			id = "native_gallery_workflows::native gallery workflows::applies shared and per-plate CanvasGroup opacity and owns the arrival tween",
			run = function()
				local built, node, stop, ctx, engine = mount("canvas_group")
				for _, opacity in { 1, 0.7, 0.15 } do
					built.opacity:set(opacity)
					Verify.expect(find(node, "OneGroup").GroupTransparency):toBe(1 - opacity)
					for i = 1, 3 do
						Verify.expect(find(find(node, "OneGroup"), "Plate" .. i).GroupTransparency):toBe(0)
						Verify.expect(find(find(node, "ManyGroups"), "Plate" .. i).GroupTransparency):toBe(1 - opacity)
					end
				end
				find(node, "Show").Activated.fire()
				for _ = 1, 30 do
					engine.heartbeat.fire(1 / 30)
				end
				Verify.expect(find(node, "Arrival").GroupTransparency):toBe(0)
				stop()
			end,
		})
		verifyHarness:case("expires passive toasts while retaining access to the underlying action", {
			id = "native_gallery_workflows::native gallery workflows::expires passive toasts while retaining access to the underlying action",
			run = function()
				local built, node, stop, _, engine = mount("sponsor_toast")
				find(node, "Send").Activated.fire()
				Verify.expect(built.report().messages):toBe(1)
				local toast = find(node, "Toast")
				Verify.expect(toast.Active):toBe(false)
				Verify.expect(toast.Selectable):toBe(false)
				find(node, "Beneath").Activated.fire()
				Verify.expect(built.report().presses):toBe(1)
				engine.heartbeat.fire(4.1)
				Verify.expect(built.report().messages):toBe(0)
				engine.heartbeat.fire(0.3)
				Verify.expect((toast.isDestroyed())):toBe(true)
				find(node, "Send").Activated.fire()
				find(node, "Clear").Activated.fire()
				Verify.expect(built.report().messages):toBe(0)
				stop()
			end,
		})
		verifyHarness:case("moves and hides native map markers without remounting their controls", {
			id = "native_gallery_workflows::native gallery workflows::moves and hides native map markers without remounting their controls",
			run = function()
				local built, node, stop, ctx = mount("world_markers")
				local map = find(node, "Map")
				map.AbsoluteSize = ctx.types.Vector2.new(309, 360)
				local objective, supplies = find(map, "A"), find(map, "C")
				objective.Activated.fire()
				Verify.expect(built.report().selected):toBe("Objective")
				find(node, "Move").Activated.fire()
				Verify.expect((find(map, "A"))):toBe(objective)
				Verify.expect(find(objective, "Direction").Visible):toBe(true)
				Verify.expect(objective.Position.X.Offset + objective.Size.X.Offset <= map.AbsoluteSize.X):toBe(true)
				find(node, "Hide").Activated.fire()
				Verify.expect(supplies.Visible):toBe(false)
				Verify.expect(objective.Visible):toBe(true)
				stop()
				Verify.expect((objective.isDestroyed())):toBe(true)
				Verify.expect((supplies.isDestroyed())):toBe(true)
				Verify.expect(#ctx.worldTarget:GetChildren()):toBe(0)
			end,
		})

		verifyHarness:case("swipes the native mail list and deletes exactly the chosen message", {
			id = "native_gallery_workflows::native gallery workflows::swipes the native mail list and deletes exactly the chosen message",
			run = function()
				local _, node, stop, ctx = mount("row_actions")
				local row = find(node, "Row_m1")
				row.AbsoluteSize = ctx.types.Vector2.new(300, 64)
				local detector = row:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
				detector.DragStart.fire(ctx.types.Vector2.new(250, 20))
				detector.DragContinue.fire(ctx.types.Vector2.new(10, 20))
				detector.DragEnd.fire()
				Verify.expect((find(node, "Row_m1"))):toBe(nil)
				Verify.expect(find(node, "Row_m2") ~= nil):toBe(true)
				stop()
			end,
		})
		verifyHarness:case("honors locked selection pinned movement and protected deletion in RunSheet", {
			id = "native_gallery_workflows::native gallery workflows::honors locked selection pinned movement and protected deletion in RunSheet",
			run = function()
				local built, node, stop, ctx = mount("row_capabilities")
				local body = find(find(node, "RunSheet"), "Body")
				body.AbsoluteWindowSize = ctx.types.Vector2.new(500, 400)
				find(find(body, "warmup"), "RowHit").Activated.fire()
				Verify.expect(built.report().selection.warmup):toBe(true)
				find(find(body, "notes"), "RowHit").Activated.fire()
				Verify.expect(built.report().selection.warmup):toBe(true)
				Verify.expect(built.report().selection.notes):toBe(nil)
				Verify.expect(find(find(body, "grid"), "Move").Interactable):toBe(false)
				local protected = find(find(body, "main"), "delete")
				Verify.expect(protected.Interactable):toBe(false)
				protected.Activated.fire()
				Verify.expect(#built.report().rows):toBe(5)
				stop()
			end,
		})
		verifyHarness:case("sorts filters reorders and restores playlist model and width bindings", {
			id = "native_gallery_workflows::native gallery workflows::sorts filters reorders and restores playlist model and width bindings",
			run = function()
				local built, node, stop = mount("02_playlist_table", "example")
				built.sort:set({ column = "name", direction = "descending" :: "descending" })
				local before = built.sortedRows:peek()[1].id
				built.filterText:set("Drift")
				Verify.expect(#built.from:peek()):toBe(1)
				built.reorder({ "apex" }, 0)
				Verify.expect(built.sort:peek().direction):toBe("descending")
				built.filterText:set("")
				built.reorder({ before }, 0)
				Verify.expect((built.sort:peek())):toBe(nil)
				Verify.expect(built.baseRows:peek()[1].id):toBe(before)
				built.columnWidths:set({ name = 290, artist = 150 })
				Verify.expect(find(node, "Widths").Text:find("290", 1, true) ~= nil):toBe(true)
				built.restore()
				Verify.expect((built.ratingFor("neon"):peek())):toBe(4)
				stop()
			end,
		})
	end)
end
