--!strict
local Verify = require("../tools/vendor/verify/src/core")
local Bdd = require("../tools/vendor/verify/src/bdd")
local VerifyRoblox = require("../tools/vendor/verify/src/roblox")
local ComposeTypes = require("../src/vendor/compose/core")

return function(verifyHarness: Verify.Harness)
	local test = Bdd.create(verifyHarness)
	local describe, it, expect = test.describe, test.it, test.expect
	local nativeDrag = require("./lib/native_drag")

	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	local requireDynamic = require :: (any) -> any
	type ExampleContext = typeof(require("@repo/examples/types").Context)
	type Screen = { read screen: () -> Instance }
	local scenarios = {
		table_virtualized = require("../examples/gallery/scenarios/table_virtualized"),
		row_actions = require("../examples/gallery/scenarios/row_actions"),
		virtual_grid = require("../examples/gallery/scenarios/virtual_grid"),
		virtual_hgrid = require("../examples/gallery/scenarios/virtual_hgrid"),
		variable_extents = require("../examples/gallery/scenarios/variable_extents"),
		measured_extents = require("../examples/gallery/scenarios/measured_extents"),
		card_rail = require("../examples/gallery/scenarios/card_rail"),
		collection_workbench = require("../examples/gallery/scenarios/collection_workbench"),
	}

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local Compose: ComposeModule = Facet.Compose

	local function find(node: any, name: string): any
		if node.Name == name then
			return node
		end
		for _, child in node:GetChildren() do
			local found = find(child, name)
			if found then
				return found
			end
		end
		return nil
	end

	local function mount<G>(
		definition: { read build: (ExampleContext) -> G & Screen },
		size: { width: number, height: number }?,
		nativePaint: boolean?
	)
		local engine = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local target, guiService = engine.new("Folder"), engine.new("GuiService")
		local inputService = engine.new("UserInputService")
		engine.environment.poke(inputService, "PreferredInput", engine.types.Enum.PreferredInput.KeyboardAndMouse)
		local keys: { [string]: boolean } = {}
		inputService.GetFocusedTextBox = function()
			return nil
		end
		inputService.IsKeyDown = function(_, code)
			local name = code.Name
			assert(type(name) == "string")
			return keys[name] == true
		end
		local runService = ({ Heartbeat = engine.heartbeat } :: unknown) :: RunService
		local viewport = Compose.cell(size or { width = 1280, height = 720 })
		local baseline = engine.census()
		local ctx: ExampleContext = {
			Facet = Facet,
			Compose = Compose,
			runtime = runtime,
			Host = Facet.host(runtime),
			types = engine.types,
			viewport = viewport,
			guiService = guiService,
			runService = runService,
			UI = Facet.controls(runtime, {
				types = engine.types,
				viewport = viewport,
				guiService = guiService,
				services = {
					GuiService = guiService,
					UserInputService = inputService,
					RunService = if nativePaint then runService else nil,
				},
				inputParent = target,
				motionLevel = "none",
				environment = {
					viewportSize = function(use)
						local size = use(viewport)
						return engine.types.Vector2.new(size.width, size.height)
					end,
				},
			}),
		}
		local built: (G & Screen)? = nil
		local stop, node: any = runtime.mount(function()
			local result = definition.build(ctx)
			built = result
			return ctx.Host.ScreenGui { result.screen() }
		end, target)
		return assert(built),
			node,
			function()
				stop()
				runtime:dispose()
			end,
			engine,
			{
				gui = guiService,
				keys = keys,
				input = inputService,
				target = target,
				baseline = baseline,
				viewport = viewport,
			}
	end

	local function action(root: Instance, name: string): InputAction?
		for _, child in root:GetChildren() do
			if child:IsA("InputContext") and child.Name == "Facet" .. name and child.Enabled then
				local found = child:FindFirstChild(name)
				if found and found:IsA("InputAction") then
					return found
				end
			end
		end
		return nil
	end

	local function contains(node, value)
		if (node:IsA("TextLabel") or node:IsA("TextButton")) and string.find(node.Text, value, 1, true) then
			return true
		end
		for _, child in node:GetChildren() do
			if contains(child, value) then
				return true
			end
		end
		return false
	end

	local function viewport(node, engine, width, height)
		engine.environment.poke(node, "AbsoluteSize", engine.types.Vector2.new(width, height))
		engine.environment.poke(node, "AbsoluteWindowSize", engine.types.Vector2.new(width, height))
	end

	local function swipe(row: any, engine: engineLib.Engine, startX: number, endX: number)
		engine.environment.poke(row, "AbsoluteSize", engine.types.Vector2.new(320, 112))
		local detector = row:FindFirstChildWhichIsA("UIDragDetector", true)
		detector.DragStart:Fire(engine.types.Vector2.new(startX, 20))
		detector.DragContinue:Fire(engine.types.Vector2.new(endX, 20))
		detector.DragEnd:Fire()
	end

	describe("native gallery collections", function()
		it("mounts table commands while native paint preparation owns the body", {
			id = "native_gallery_collections::native gallery collections::mounts table commands while native paint preparation owns the body",
			run = function()
				local _, node, stop, engine = mount(scenarios.table_virtualized, nil, true)
				local body = find(node, "Body")
				expect(body:IsA("ScrollingFrame")):toBe(true)
				viewport(body, engine, 800, 440)
				expect(find(node, "ToolbarScroll") ~= nil):toBe(true)
				stop()
			end,
		})
		it("reveals distant entrants selects an unmounted range and moves keyed rows", {
			id = "native_gallery_collections::native gallery collections::reveals distant entrants selects an unmounted range and moves keyed rows",
			run = function()
				local built, node, stop, engine, world = mount(scenarios.table_virtualized)
				local tableNode, body = find(node, "Collection"), find(node, "Body")
				engine.environment.poke(tableNode, "AbsoluteSize", engine.types.Vector2.new(800, 440))
				viewport(body, engine, 800, 400)
				nativeDrag.measure(body, engine.environment)
				expect(built.report().count):toBe(2000)
				expect(built.report().status.retained < 30):toBe(true)
				expect(contains(node, "Entrant") and contains(node, "Team") and contains(node, "Best lap")):toBe(true)
				expect(contains(node, "Rustbucket") and contains(node, "#1")):toBe(true)
				expect((find(node, "Columns"))):toBe(nil)
				expect((find(node, "TextSize"))):toBe(nil)
				find(node, "Range").Activated:Fire()
				expect(built.report().selectedCount):toBe(201)
				expect(built.report().selection.e900 and built.report().selection.e1100):toBe(true)
				expect((find(body, "e1500"))):toBe(nil)
				find(node, "Move").Activated:Fire()
				expect(built.report().rows[1499].id):toBe("e1500")
				expect(built.report().moves):toBe(1)
				find(node, "Reveal").Activated:Fire()
				expect(body.CanvasPosition.Y > 40000):toBe(true)
				expect(find(body, "e1500") ~= nil):toBe(true)
				expect(built.report().status.first > 1400):toBe(true)
				expect(string.find(find(node, "Status").Text, tostring(built.report().status.first), 1, true) ~= nil):toBe(
					true
				)
				expect((find(node, "Edit"))):toBeNil()
				engine.environment.poke(world.input, "PreferredInput", engine.types.Enum.PreferredInput.Touch)
				find(node, "Edit").Activated:Fire()
				expect(find(find(body, "e1500"), "Move").Visible):toBe(true)
				expect(built.report().selectedCount):toBe(201)
				find(node, "Reset").Activated:Fire()
				expect(built.report().selectedCount):toBe(0)
				expect(built.report().rows[1500].id):toBe("e1500")
				expect(body.CanvasPosition.Y):toBe(0)
				stop()
			end,
		})

		it("shows seeded mail state and applies idempotent read visible flag and chosen deletion", {
			id = "native_gallery_collections::native gallery collections::shows seeded mail state and applies idempotent read visible flag and chosen deletion",
			run = function()
				local built, node, stop, engine = mount(scenarios.row_actions)
				local list = find(node, "Mail_list")
				local body = find(list, "Collection")
				viewport(body, engine, 700, 240)
				local function mail(row)
					return {
						unread = find(row, "Unread").Visible,
						flagged = find(row, "Flag").Visible,
						from = find(row, "From").Text,
						subject = find(row, "Subject").Text,
						preview = find(row, "Preview").Text,
					}
				end
				expect((mail(find(list, "Row_m1")))):toEqual({
					unread = true,
					flagged = false,
					from = "Ari Foyer",
					subject = "Kickoff notes",
					preview = "Quick recap from the sync — three follow-ups, none urgent.",
				})
				expect(mail(find(list, "Row_m2")).unread):toBe(false)
				expect(mail(find(list, "Row_m3")).flagged):toBe(true)
				expect((contains(find(list, "Row_m1"), "Unread · "))):toBe(false)
				expect((find(find(list, "Row_m1"), "Flag"):IsA("ImageLabel"))):toBe(true)
				expect((find(find(list, "Row_m1"), "Unread"):IsA("GuiObject"))):toBe(true)
				expect((find(find(list, "Row_m1"), "Subject"):HasTag("facet-type-label"))):toBe(true)
				expect((find(find(list, "Row_m1"), "Preview"):HasTag("facet-type-caption"))):toBe(true)
				expect((find(find(list, "Row_m1"), "From"):HasTag("facet-type-body"))):toBe(true)
				expect(built.report().surfaces.list.status.extent):toBe(6 * 76 + 5 * 8)
				for _ = 1, 2 do
					swipe(find(list, "Row_m1"), engine, 10, 300)
				end
				expect(built.report().surfaces.list.read.m1):toBe(true)
				expect(mail(find(list, "Row_m1")).unread):toBe(false)
				local row = find(list, "Row_m1")
				swipe(row, engine, 240, 100)
				find(row, "flag").Activated:Fire()
				expect(mail(row).flagged):toBe(true)
				find(list, "Jump").Activated:Fire()
				expect(body.CanvasPosition.Y > 0):toBe(true)
				expect(built.report().surfaces.list.status.total):toBe(6)
				expect(built.report().surfaces.list.status.retained):toBe(6)
				expect((find(list, "Columns"))):toBe(nil)
				swipe(find(list, "Row_m4"), engine, 300, 10)
				expect(built.report().surfaces.list.count):toBe(5)
				expect((find(list, "Row_m4"))):toBe(nil)
				expect(find(list, "Row_m3") ~= nil and find(list, "Row_m5") ~= nil):toBe(true)
				stop()
			end,
		})

		it("uses mail table activation editing and native row reorder with independent state", {
			id = "native_gallery_collections::native gallery collections::uses mail table activation editing and native row reorder with independent state",
			run = function()
				local built, node, stop, engine, world = mount(scenarios.row_actions)
				find(node, "table").Activated:Fire()
				local page = find(node, "Mail_table")
				local tableNode, body = find(page, "Collection"), find(page, "Body")
				engine.environment.poke(tableNode, "AbsoluteSize", engine.types.Vector2.new(800, 440))
				viewport(body, engine, 800, 400)
				nativeDrag.measure(body, engine.environment)
				expect(contains(page, "From") and contains(page, "Subject")):toBe(true)
				expect((contains(find(body, "m1"), "Ari Foyer"))):toBe(true)
				find(find(body, "m1"), "RowHit").Activated:Fire()
				expect(built.report().surfaces.table.read.m1):toBe(true)
				expect(built.report().surfaces.list.read.m1):toBe(false)
				expect(find(find(body, "m1"), "Unread").Visible):toBe(false)
				expect(find(find(body, "m2"), "Subject").Text):toBe("Order confirmed")
				expect((find(find(body, "m1"), "Move"))):toBeNil()
				expect((find(page, "Edit"))):toBeNil()
				engine.environment.poke(world.input, "PreferredInput", engine.types.Enum.PreferredInput.Touch)
				find(page, "Edit").Activated:Fire()
				local handle = find(find(body, "m1"), "Move")
				expect(handle.Visible):toBe(true)
				local detector = handle:FindFirstChildWhichIsA("UIDragDetector")
				detector.DragStart:Fire(engine.types.Vector2.new(10, 10))
				detector.DragContinue:Fire(engine.types.Vector2.new(10, 250))
				detector.DragEnd:Fire()
				expect(built.report().surfaces.table.moves):toBe(1)
				expect(built.report().surfaces.table.rows[1].id ~= "m1"):toBe(true)
				find(page, "Jump").Activated:Fire()
				expect(body.CanvasPosition.Y > 0):toBe(true)
				expect(built.report().surfaces.table.status.first > 0):toBe(true)
				stop()
			end,
		})

		it("changes grid columns and rendered text through relevant native toolbar actions", {
			id = "native_gallery_collections::native gallery collections::changes grid columns and rendered text through relevant native toolbar actions",
			run = function()
				local entries: { { name: string, definition: typeof(scenarios.virtual_grid) } } = {
					{ name = "virtual_grid", definition = scenarios.virtual_grid },
					{ name = "virtual_hgrid", definition = scenarios.virtual_hgrid },
				}
				for _, entry in entries do
					local name = entry.name
					local built, node, stop, engine = mount(entry.definition)
					local body = find(node, "Collection")
					viewport(body, engine, 640, 320)
					local before = built.report().status.rowCount
					find(node, "Columns").Activated:Fire()
					expect(built.report().status.rowCount):toBe(before * 2)
					local item = find(body, "Item_1")
					find(node, "TextSize").Activated:Fire()
					expect(item.TextSize):toBe(24)
					find(node, "Jump").Activated:Fire()
					expect(if name == "virtual_hgrid" then body.CanvasPosition.X > 0 else body.CanvasPosition.Y > 0):toBe(
						true
					)
					expect(built.report().status.retained < 100):toBe(true)
					find(node, "Reverse").Activated:Fire()
					expect(built.report().rows[1].id):toBe("5000")
					stop()
				end
			end,
		})

		it("keeps variable and native measured posts anchored across all text offsets", {
			id = "native_gallery_collections::native gallery collections::keeps variable and native measured posts anchored across all text offsets",
			run = function()
				local entries: { { name: string, definition: typeof(scenarios.variable_extents) } } = {
					{ name = "variable_extents", definition = scenarios.variable_extents },
					{ name = "measured_extents", definition = scenarios.measured_extents },
				}
				for _, entry in entries do
					local name = entry.name
					local built, node, stop, engine = mount(entry.definition)
					local body = find(node, "Collection")
					viewport(body, engine, 600, 320)
					find(node, "Jump").Activated:Fire()
					local first = built.report().status.first
					local originalExtent = built.report().status.extent
					for _, offset in { 4, 10, 14, 0 } do
						find(node, "TextOffset" .. offset).Activated:Fire()
						expect(find(body, "PostTitle").TextSize):toBe(15 + offset)
						expect(find(body, "PostBody").TextSize):toBe(13 + offset)
						if name == "measured_extents" then
							local post = find(body, "Post_" .. first)
							engine.environment.poke(
								post,
								"AbsoluteSize",
								engine.types.Vector2.new(600, 100 + offset * 4)
							)
						end
						expect(built.report().status.first):toBe(first)
						expect(built.report().status.retained < 20):toBe(true)
					end
					if name == "variable_extents" then
						find(node, "TextOffset14").Activated:Fire()
						expect(built.report().status.extent > originalExtent):toBe(true)
						find(node, "Mode").Activated:Fire()
						expect(built.report().extents["1"]):toBe(84)
						expect(built.report().status.first):toBe(first)
					else
						expect(built.report().status.measured > 0):toBe(true)
					end
					expect(built.report().built >= built.report().mounted):toBe(true)
					expect(find(node, "Actions"):FindFirstChildWhichIsA("UIListLayout").Wraps):toBe(true)
					expect(find(node, "Toolbar").AutomaticSize):toBe(engine.types.Enum.AutomaticSize.Y)
					stop()
				end
			end,
		})

		it("moves the collection toolbar beside the rows when the page is short and wide", {
			id = "native_gallery_collections::native gallery collections::moves the collection toolbar beside the rows when the page is short and wide",
			run = function()
				local _, node, stop, engine = mount(scenarios.measured_extents)
				local scroll = find(node, "ToolbarScroll")
				local page = scroll.Parent
				local layout = page:FindFirstChildWhichIsA("UIListLayout")
				local collection = find(page, "Collection")
				expect(layout.FillDirection):toBe(engine.types.Enum.FillDirection.Vertical)
				engine.environment.poke(page, "AbsoluteSize", engine.types.Vector2.new(644, 213))
				expect(layout.FillDirection):toBe(engine.types.Enum.FillDirection.Horizontal)
				expect(math.abs(scroll.Size.X.Scale - 0.4) < 1e-6):toBe(true)
				expect(scroll.Size.Y.Scale):toBe(1)
				expect(scroll.AutomaticCanvasSize):toBe(engine.types.Enum.AutomaticSize.Y)
				expect(collection.Size.Y.Scale):toBe(1)
				engine.environment.poke(page, "AbsoluteSize", engine.types.Vector2.new(401, 560))
				expect(layout.FillDirection):toBe(engine.types.Enum.FillDirection.Vertical)
				expect(scroll.Size.X.Scale):toBe(1)
				expect(scroll.AutomaticSize):toBe(engine.types.Enum.AutomaticSize.Y)
				expect(collection.Size.X.Scale):toBe(1)
				stop()
			end,
		})

		it("renders three racing shelves with measured widths track art and native selection", {
			id = "native_gallery_collections::native gallery collections::renders three racing shelves with measured widths track art and native selection",
			run = function()
				local built, node, stop, engine = mount(scenarios.card_rail)
				for _, name in { "Rail", "WeekendRail", "RecommendedRail" } do
					local rail = find(node, name)
					viewport(rail, engine, 400, 300)
					expect(built.report().rails[name].itemExtent):toBe(352)
					expect(built.report().rails[name].status.total):toBe(400)
					expect(built.report().rails[name].status.retained < 12):toBe(true)
					expect(contains(rail, "Livery 001") and contains(rail, "Rally")):toBe(true)
					local preview = find(rail, "Preview")
					expect(preview:FindFirstChildWhichIsA("UIAspectRatioConstraint").AspectRatio):toBe(16 / 9)
					expect(#find(preview, "Track"):GetControlPoints()):toBe(17)
					find(rail, "Card_c1").Activated:Fire()
					expect(built.report().selectedKey):toBe("c1")
				end
				viewport(find(node, "Rail"), engine, 1000, 300)
				expect(built.report().rails.Rail.itemExtent):toBe(244)
				expect(built.report().rails.WeekendRail.itemExtent):toBe(352)
				expect((contains(find(node, "Selected"), "Selected: Livery 001 · Rally"))):toBe(true)
				expect(built.report().shelves):toBe(3)
				stop()
			end,
		})

		it("opens the mail row menu with Shift+Return on a selected row and runs a chosen item", {
			id = "native_gallery_collections::native gallery collections::opens the mail row menu with Shift+Return on a selected row and runs a chosen item",
			run = function()
				local built, node, stop, engine, world = mount(scenarios.row_actions)
				local list = find(node, "Mail_list")
				viewport(find(list, "Collection"), engine, 700, 240)
				local row = find(list, "Row_m1")
				engine.environment.poke(row, "AbsoluteSize", engine.types.Vector2.new(700, 112))
				local content = find(row, "Item_m1")
				expect((action(world.target, "RowActionsToggle"))):toBeNil()
				world.gui.SelectedObject = content
				expect(world.gui.SelectedObject):toBe(content)
				local toggle = assert(action(world.target, "RowActionsToggle"))
				expect(toggle ~= nil):toBe(true)
				local binding = toggle:FindFirstChildWhichIsA("InputBinding")
				assert(binding and binding:IsA("InputBinding"))
				expect(binding.KeyCode):toBe(engine.types.Enum.KeyCode.Return)
				expect(
					binding.PrimaryModifier == engine.types.Enum.KeyCode.LeftShift
						or binding.PrimaryModifier == engine.types.Enum.KeyCode.RightShift
				):toBe(true)
				expect((find(world.target, "MenuPanel"))):toBeNil()
				engine.environment.fire(VerifyRoblox.assertInstance(toggle), "Pressed")
				local panel = find(world.target, "MenuPanel")
				expect(panel ~= nil):toBe(true)
				for _, id in { "leading:read", "trailing:delete", "trailing:flag" } do
					expect(find(panel, id) ~= nil):toBe(true)
				end
				expect(contains(panel, "Mark read") and contains(panel, "Delete") and contains(panel, "Flag")):toBe(
					true
				)
				expect(built.report().surfaces.list.read.m1):toBe(false)
				expect(built.report().surfaces.list.count):toBe(6)
				find(panel, "trailing:flag").Activated:Fire()
				expect((find(world.target, "MenuPanel"))):toBeNil()
				expect(built.report().surfaces.list.flagged.m1):toBe(true)
				expect(built.report().surfaces.list.count):toBe(6)
				stop()
			end,
		})

		it("selects a mail table row in edit mode, deletes it from the toolbar and swipes a row open", {
			id = "native_gallery_collections::native gallery collections::selects a mail table row in edit mode, deletes it from the toolbar and swipes a row open",
			run = function()
				local built, node, stop, engine, world = mount(scenarios.row_actions)
				find(node, "table").Activated:Fire()
				local page = find(node, "Mail_table")
				local tableNode, body = find(page, "Collection"), find(page, "Body")
				engine.environment.poke(tableNode, "AbsoluteSize", engine.types.Vector2.new(800, 440))
				viewport(body, engine, 800, 400)
				nativeDrag.measure(body, engine.environment)
				expect(find(find(body, "m2"), "SelectMark").Visible):toBe(false)
				engine.environment.poke(world.input, "PreferredInput", engine.types.Enum.PreferredInput.Touch)
				find(page, "Edit").Activated:Fire()
				expect(find(find(body, "m2"), "SelectMark").Visible):toBe(true)
				find(find(body, "m2"), "RowHit").Activated:Fire(
					{ UserInputType = engine.types.Enum.UserInputType.Touch },
					1
				)
				expect(find(find(find(body, "m2"), "SelectMark"), "Check").Visible):toBe(true)
				find(page, "DeleteSelected").Activated:Fire({ UserInputType = engine.types.Enum.UserInputType.Touch })
				expect(built.report().surfaces.table.count):toBe(5)
				for _, item in built.report().surfaces.table.rows do
					expect(item.id ~= "m2"):toBe(true)
				end
				expect((find(body, "m2"))):toBeNil()
				find(page, "Edit").Activated:Fire()
				engine.environment.poke(
					world.input,
					"PreferredInput",
					engine.types.Enum.PreferredInput.KeyboardAndMouse
				)
				local order = {}
				for index, item in built.report().surfaces.table.rows do
					order[index] = item.id
				end
				local row = find(find(body, "m1"), "Row_m1")
				expect(find(row, "trailing").Visible):toBe(false)
				engine.environment.poke(row, "AbsoluteSize", engine.types.Vector2.new(800, 100))
				local detector = row:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
				detector.DragStart:Fire(engine.types.Vector2.new(700, 50))
				detector.DragContinue:Fire(engine.types.Vector2.new(520, 50))
				detector.DragEnd:Fire()
				expect(find(row, "trailing").Visible):toBe(true)
				expect(find(find(row, "trailing"), "delete") ~= nil):toBe(true)
				expect(built.report().surfaces.table.moves):toBe(0)
				expect(built.report().surfaces.table.count):toBe(5)
				for index, item in built.report().surfaces.table.rows do
					expect(item.id):toBe(order[index])
				end
				expect(built.report().surfaces.table.read.m1):toBe(false)
				stop()
			end,
		})

		it("mounts the virtual mail surface alone and swipes deletes and opens row menus from each input", {
			id = "native_gallery_collections::native gallery collections::mounts the virtual mail surface alone and swipes deletes and opens row menus from each input",
			run = function()
				local built, node, stop, engine, world = mount(scenarios.row_actions)
				expect(find(node, "Mail_list").Parent.Visible):toBe(true)
				expect((find(node, "Mail_virtual"))):toBeNil()
				find(node, "virtual").Activated:Fire()
				expect(built.report().active):toBe("virtual")
				local page = find(node, "Mail_virtual")
				expect(page.Parent.Visible):toBe(true)
				expect(find(node, "Mail_list").Parent.Visible):toBe(false)
				expect((find(node, "Mail_table"))):toBeNil()
				local body = find(page, "Collection")
				expect((body:IsA("ScrollingFrame"))):toBe(true)
				viewport(body, engine, 700, 480)
				expect(built.report().surfaces.virtual.count):toBe(6)
				local row = find(page, "Row_m1")
				engine.environment.poke(row, "AbsoluteSize", engine.types.Vector2.new(700, 112))
				local detector = row:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
				detector.DragStart:Fire(engine.types.Vector2.new(650, 50))
				detector.DragContinue:Fire(engine.types.Vector2.new(520, 50))
				detector.DragEnd:Fire()
				expect(find(row, "trailing").Visible):toBe(true)
				expect(built.report().surfaces.virtual.count):toBe(6)
				swipe(find(page, "Row_m4"), engine, 300, 10)
				expect(built.report().surfaces.virtual.count):toBe(5)
				expect((find(page, "Row_m4"))):toBeNil()
				local content = find(find(page, "Row_m3"), "Item_m3")
				world.gui.SelectedObject = content
				local delete = assert(action(world.target, "RowActionsDelete"))
				expect(delete ~= nil):toBe(true)
				engine.environment.fire(VerifyRoblox.assertInstance(delete), "Pressed")
				expect(built.report().surfaces.virtual.count):toBe(4)
				expect((find(page, "Row_m3"))):toBeNil()
				for _, item in built.report().surfaces.virtual.rows do
					expect(item.id ~= "m3" and item.id ~= "m4"):toBe(true)
				end
				local second = find(find(page, "Row_m2"), "Item_m2")
				world.gui.SelectedObject = second
				local reveal = assert(action(world.target, "RowActionsReveal"))
				local keys = {}
				for _, binding in reveal:GetChildren() do
					assert(binding:IsA("InputBinding"))
					table.insert(keys, binding.KeyCode.Name)
				end
				table.sort(keys)
				expect(keys):toEqual({ "ButtonX", "Menu" })
				engine.environment.fire(VerifyRoblox.assertInstance(reveal), "Pressed")
				local panel = find(world.target, "MenuPanel")
				expect(panel ~= nil):toBe(true)
				expect(find(panel, "leading:read") ~= nil and find(panel, "trailing:flag") ~= nil):toBe(true)
				expect(built.report().surfaces.virtual.count):toBe(4)
				local held = find(page, "Row_m5")
				engine.environment.poke(held, "AbsoluteSize", engine.types.Vector2.new(700, 112))
				local heldDetector = held:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
				heldDetector.DragStart:Fire(engine.types.Vector2.new(650, 50))
				heldDetector.DragContinue:Fire(engine.types.Vector2.new(560, 50))
				stop()
				expect((find(world.target, "MenuPanel"))):toBeNil()
				local after = engine.census()
				expect(after.live):toBe(world.baseline.live)
				expect(after.connections):toBe(world.baseline.connections)
			end,
		})

		it("drops the mail heading on a short landscape and keeps the first row on every surface", {
			id = "native_gallery_collections::native gallery collections::drops the mail heading on a short landscape and keeps the first row on every surface",
			run = function()
				local tall, tallNode, stopTall = mount(scenarios.row_actions, { width = 1280, height = 720 })
				expect(find(find(tallNode, "Mail_list"), "Title").Visible):toBe(true)
				expect(tall.report().surfaces.list.count):toBe(6)
				stopTall()
				local built, node, stop, engine, world = mount(scenarios.row_actions, { width = 844, height = 390 })
				for _, kind in { "list", "table", "virtual" } :: { "list" | "table" | "virtual" } do
					find(node, kind).Activated:Fire()
					local page = find(node, "Mail_" .. kind)
					local title = find(find(page, "Toolbar"), "Title")
					expect(title.Visible):toBe(false)
					expect(find(page, "Collection"):FindFirstChildWhichIsA("UIFlexItem").FlexMode):toBe(
						engine.types.Enum.UIFlexMode.Fill
					)
					local body = if kind == "table" then find(page, "Body") else find(page, "Collection")
					viewport(body, engine, 844, 200)
					expect(find(body, "Row_m1") ~= nil):toBe(true)
					expect(built.report().surfaces[kind].status.first):toBe(1)
				end
				world.viewport:set({ width = 844, height = 720 })
				expect(find(find(node, "Mail_virtual"), "Title").Visible):toBe(true)
				stop()
			end,
		})
	end)

	describe("file library workbench", function()
		local function file<T>(
			rows: { read [number]: T & { read id: string } },
			key: string | number
		): T & { read id: string }
			for _, item in rows do
				local identified: { read id: string } = item
				if identified.id == tostring(key) then
					return item
				end
			end
			error("Missing file " .. tostring(key))
		end
		it("keeps field permission independent of coarse selection mode with one demo permission toggle", {
			id = "native_gallery_collections::file library workbench::keeps field permission independent of coarse selection mode with one demo permission toggle",
			run = function()
				local built, node, stop, engine, world = mount(scenarios.collection_workbench)
				for _, input in { "KeyboardAndMouse", "Touch", "Gamepad" } do
					engine.environment.poke(
						world.input,
						"PreferredInput",
						(engine.types.Enum.PreferredInput :: any)[input]
					)
					for _, mode in { "icons", "list", "details" } do
						find(find(node, "ViewMode"), mode).Activated:Fire()
						local collection = find(node, "primary")
						engine.environment.poke(collection, "AbsoluteSize", engine.types.Vector2.new(800, 400))
						viewport(if mode == "details" then find(collection, "Body") else collection, engine, 800, 400)
						local coarse = input ~= "KeyboardAndMouse"
						expect(find(node, "Edit").Visible):toBe(coarse)
						expect(find(collection, "Rename") ~= nil):toBe(true)
						require("../src/ui/activation").edits(find(collection, "Rename"))[1].onActivate()
						expect(find(collection, "Rename"):FindFirstChildWhichIsA("TextBox", true).TextEditable):toBe(
							true
						)
						if coarse then
							find(node, "Edit").Activated:Fire()
							expect(find(collection, "Rename") ~= nil):toBe(true)
						end
						find(node, "EnableEditing").Activated:Fire()
						expect((built.model.editingEnabled:peek())):toBe(false)
						expect(find(collection, "Rename"):FindFirstChildWhichIsA("TextBox", true).TextEditable):toBe(
							false
						)
						expect(find(collection, "CellActions").Visible):toBe(false)
						expect(find(node, "Create").Interactable):toBe(false)
						expect(find(node, "LabelGreen").Interactable):toBe(false)
						find(node, "EnableEditing").Activated:Fire()
						expect(find(collection, "CellActions").Visible):toBe(coarse)
						if coarse then
							find(node, "Edit").Activated:Fire()
						end
						expect(find(collection, "Rename") ~= nil):toBe(true)
						if mode == "details" then
							expect((contains(collection, "Kind"))):toBe(true)
						end
						if coarse then
							find(node, "Edit").Activated:Fire()
						end
					end
				end
				stop()
			end,
		})

		it("keeps compact icons in multiple columns and binds the grid size slider", {
			id = "native_gallery_collections::file library workbench::keeps compact icons in multiple columns and binds the grid size slider",
			run = function()
				local built, node, stop, engine, world =
					mount(scenarios.collection_workbench, { width = 390, height = 844 })
				engine.environment.poke(world.input, "PreferredInput", engine.types.Enum.PreferredInput.Touch)
				local grid = find(node, "primary")
				viewport(grid, engine, 350, 400)
				local first, second = find(grid, "1"), find(grid, "2")
				expect(second.Position.Y.Offset):toBe(first.Position.Y.Offset)
				expect(second.Position.X.Offset > first.Position.X.Offset):toBe(true)
				find(node, "Edit").Activated:Fire()
				expect(find(first, "Cells").Size.X.Offset):toBe(0)
				find(node, "ShowFilters").Activated:Fire()
				world.gui.SelectedObject = find(world.target, "GridSize")
				expect(world.gui.SelectedObject):toBeNil()
				engine.environment.poke(
					world.input,
					"PreferredInput",
					engine.types.Enum.PreferredInput.KeyboardAndMouse
				)
				world.gui.SelectedObject = find(world.target, "GridSize")
				local increase = assert(action(world.target, "Increase"))
				expect(increase ~= nil):toBe(true)
				engine.environment.fire(VerifyRoblox.assertInstance(increase), "Pressed")
				engine.environment.fire(VerifyRoblox.assertInstance(increase), "Released")
				expect((built.model.gridSize:peek())):toBe(160)
				built.model.gridSize:set(260)
				expect(second.Position.Y.Offset > first.Position.Y.Offset):toBe(true)
				built.model.mode:set("list")
				expect(find(world.target, "GridSize").Visible):toBe(false)
				stop()
			end,
		})

		it("moves selected files through native collection reorder and gates all writes", {
			id = "native_gallery_collections::file library workbench::moves selected files through native collection reorder and gates all writes",
			run = function()
				local built, node, stop, engine, world = mount(scenarios.collection_workbench)
				local model = built.model
				model.mode:set("list")
				local body = find(node, "primary")
				viewport(body, engine, 700, 1200)
				viewport(find(node, "FileViewport"), engine, 700, 1200)
				nativeDrag.measure(body, engine.environment)
				for _, child in body:GetDescendants() do
					if child:IsA("GuiObject") then
						engine.environment.poke(child, "AbsoluteSize", engine.types.Vector2.new(700, 44))
						if child:IsA("TextLabel") or child:IsA("TextButton") or child:IsA("TextBox") then
							engine.environment.poke(child, "TextBounds", engine.types.Vector2.new(#child.Text * 7, 14))
						end
					end
				end
				for _ = 1, 6 do
					engine.heartbeat:Fire(1 / 60)
				end
				engine.environment.poke(world.input, "PreferredInput", engine.types.Enum.PreferredInput.Touch)
				find(node, "Edit").Activated:Fire()
				model.selection:set({ ["1"] = true, ["2"] = true })
				local detector = find(find(body, "1"), "Move"):FindFirstChildWhichIsA("UIDragDetector")
				detector.DragStart:Fire(engine.types.Vector2.new(10, 10))
				detector.DragContinue:Fire(engine.types.Vector2.new(10, 1000))
				detector.DragEnd:Fire()
				expect(model.rows:peek()[4].id ~= "1"):toBe(true)
				local moved: { number } = {}
				for i, item in model.rows:peek() do
					if item.id == "1" or item.id == "2" then
						table.insert(moved, i)
					end
				end
				expect(moved[2]):toBe(moved[1] + 1)
				local hiddenBefore: { string } = {}
				for _, item in model.rows:peek() do
					if not string.find(item.name, "Coast", 1, true) then
						table.insert(hiddenBefore, item.id)
					end
				end
				model.query:set("Coast")
				model.reorder({ "1" }, 0)
				local hiddenAfter: { string }, visible: { string } = {}, {}
				for _, item in model.rows:peek() do
					table.insert(if string.find(item.name, "Coast", 1, true) then visible else hiddenAfter, item.id)
				end
				expect(hiddenAfter):toEqual(hiddenBefore)
				expect(visible[1]):toBe("1")
				expect(visible[2]):toBe("5")
				local before = model.rows:peek()
				find(node, "EnableEditing").Activated:Fire()
				model.change("1", "name", "Blocked")
				model.change(nil, "color", "Green")
				model.remove({ "1" })
				model.reorder({ "1" }, 2)
				built.steps.create()
				built.steps.undo()
				expect((model.rows:peek())):toBe(before)
				stop()
			end,
		})

		it("labels the whole selection across filtering and deletes it once with undo", {
			id = "native_gallery_collections::file library workbench::labels the whole selection across filtering and deletes it once with undo",
			run = function()
				local built, node, stop = mount(scenarios.collection_workbench)
				local model, selected = built.model, {}
				local labeled = 0
				for _, item in model.rows:peek() do
					if item.color ~= "None" then
						labeled += 1
					end
				end
				expect(labeled):toBe(2)
				expect(find(node, "LabelGreen").Interactable):toBe(false)
				for i = 1, 10 do
					selected[tostring(i)] = true
				end
				model.selection:set(selected)
				expect(find(node, "LabelGreen").Interactable):toBe(true)
				model.query:set("001")
				find(node, "LabelGreen").Activated:Fire()
				for i = 1, 10 do
					expect(file(model.rows:peek(), i).color):toBe("Green")
				end
				model.change("11", "color", "Red")
				expect(file(model.rows:peek(), "11").color):toBe("Red")
				expect(file(model.rows:peek(), "1").color):toBe("Green")
				model.change(nil, "color", "None")
				for i = 1, 10 do
					expect(file(model.rows:peek(), i).color):toBe("None")
				end
				model.query:set("missing")
				find(node, "Delete").Activated:Fire()
				expect(built.report().count):toBe(17)
				expect((next(model.selection:peek()))):toBeNil()
				built.steps.undo()
				expect(built.report().count):toBe(27)
				for i = 1, 10 do
					expect(model.selection:peek()[tostring(i)]):toBe(true)
				end
				stop()
			end,
		})

		it("keeps Linked and Inbox in the visible compact Views menu", {
			id = "native_gallery_collections::file library workbench::keeps Linked and Inbox in the visible compact Views menu",
			run = function()
				local built, node, stop, _, world = mount(scenarios.collection_workbench, { width = 390, height = 844 })
				local menu = find(node, "ViewOptions")
				expect(menu.Parent.Name):toBe("Toolbar")
				expect(menu.Visible and menu.Parent.Visible):toBe(true)
				expect((find(node, "Filters"))):toBeNil()
				for _, name in { "linked", "inbox" } do
					find(menu, "Trigger").Activated:Fire()
					find(find(world.target, "MenuPanel"), name).Activated:Fire()
					expect((find(world.target, "MenuPanel"))):toBeNil()
				end
				expect(built.model.linked:peek() and built.model.transfers:peek()):toBe(true)
				stop()
			end,
		})

		it("opens compact file options in a sheet without consuming the file pane", {
			id = "native_gallery_collections::file library workbench::opens compact file options in a sheet without consuming the file pane",
			run = function()
				local _, node, stop, engine, world =
					mount(scenarios.collection_workbench, { width = 390, height = 640 })
				expect(find(node, "CollectionWorkbench").AutomaticSize):toBe(engine.types.Enum.AutomaticSize.Y)
				expect(find(node, "Contents"):FindFirstChildWhichIsA("UISizeConstraint").MinSize.Y):toBe(320)
				expect(find(node, "Create").Visible):toBe(false)
				expect(find(node, "FileActions").Visible):toBe(true)
				find(node, "ShowFilters").Activated:Fire()
				local filters = find(world.target, "Filters")
				expect(filters ~= nil):toBe(true)
				expect((filters:IsDescendantOf(find(node, "CollectionWorkbench")))):toBe(false)
				find(world.target, "CloseFileOptions").Activated:Fire()
				expect((find(world.target, "Filters"))):toBeNil()
				stop()
			end,
		})

		it("keeps split panes mounted with independent folder histories", {
			id = "native_gallery_collections::file library workbench::keeps split panes mounted with independent folder histories",
			run = function()
				for _, width in { 1280, 390 } do
					local built, node, stop, engine =
						mount(scenarios.collection_workbench, { width = width, height = 844 })
					local model = built.model
					model.linked:set(true)
					model.transfers:set(true)
					local views, primary = find(node, "Views"), find(node, "PrimaryViews")
					local linked, inbox = find(node, "LinkedView"), find(node, "InboxView")
					local linkedTable = find(linked, "linked")
					local body = find(linkedTable, "Body")
					viewport(body, engine, 440, 200)
					body.CanvasPosition = engine.types.Vector2.new(0, 80)
					local scroll = body.CanvasPosition
					model.openFolder(file(model.rows:peek(), "environments"))
					expect(find(node, "Views")):toBe(views)
					expect(find(node, "PrimaryViews")):toBe(primary)
					expect(find(node, "InboxView")):toBe(inbox)
					expect(find(node, "LinkedView")):toBe(linked)
					expect(find(linked, "linked")):toBe(linkedTable)
					expect(body.CanvasPosition):toBe(scroll)
					expect(#model.linkedPath:peek()):toBe(0)
					expect(find(node, "Folders"):IsDescendantOf(primary)):toBe(true)
					expect(find(node, "LinkedFolders"):IsDescendantOf(linked)):toBe(true)
					model.openFolder(file(model.rows:peek(), "materials"), "linked")
					expect(model.path:peek()[1].value):toBe("environments")
					expect(model.linkedPath:peek()[1].value):toBe("materials")
					model.path:set({})
					expect(model.linkedPath:peek()[1].value):toBe("materials")
					model.remove({ "materials" })
					expect(#model.linkedPath:peek()):toBe(0)
					expect(find(node, "Views")):toBe(views)
					stop()
				end
			end,
		})

		it("splits Files Inbox and Linked independently and navigates all three when compact", {
			id = "native_gallery_collections::file library workbench::splits Files Inbox and Linked independently and navigates all three when compact",
			run = function()
				local built, node, stop, engine = mount(scenarios.collection_workbench)
				local views, primary = find(node, "Views"), find(node, "PrimaryViews")
				built.model.linked:set(true)
				built.model.transfers:set(true)
				engine.environment.poke(views, "AbsoluteSize", engine.types.Vector2.new(1280, 600))
				engine.environment.poke(primary, "AbsoluteSize", engine.types.Vector2.new(760, 600))
				expect(views:FindFirstChild("Resize").Visible and primary:FindFirstChild("Resize").Visible):toBe(true)
				expect(views:FindFirstChild("Sidebar").Size.X.Offset):toBe(760)
				local detector = primary:FindFirstChild("Resize"):FindFirstChildWhichIsA("UIDragDetector")
				detector.DragStart:Fire(engine.types.Vector2.new(360, 200))
				detector.DragContinue:Fire(engine.types.Vector2.new(400, 200))
				detector.DragEnd:Fire(engine.types.Vector2.new(400, 200))
				expect(primary:FindFirstChild("Sidebar").Size.X.Offset):toBe(400)
				expect(views:FindFirstChild("Sidebar").Size.X.Offset):toBe(760)
				local files, inbox, linked =
					find(node, "PrimaryView"), find(node, "InboxView"), find(node, "LinkedView")
				engine.environment.poke(views, "AbsoluteSize", engine.types.Vector2.new(390, 700))
				engine.environment.poke(primary, "AbsoluteSize", engine.types.Vector2.new(390, 660))
				expect(views:FindFirstChild("Resize").Visible or primary:FindFirstChild("Resize").Visible):toBe(false)
				expect(views:FindFirstChild("Sidebar").Visible and primary:FindFirstChild("Sidebar").Visible):toBe(true)
				expect((find(views:FindFirstChild("NavigationBar"), "ShowDetail"):GetAttribute("label"))):toBe(
					"Open linked view"
				)
				find(views:FindFirstChild("NavigationBar"), "ShowDetail").Activated:Fire()
				expect(views:FindFirstChild("Detail").Visible and not views:FindFirstChild("Sidebar").Visible):toBe(
					true
				)
				find(views:FindFirstChild("NavigationBar"), "Back").Activated:Fire()
				find(primary:FindFirstChild("NavigationBar"), "ShowDetail").Activated:Fire()
				expect(primary:FindFirstChild("Detail").Visible):toBe(true)
				expect(
					find(node, "PrimaryView") == files
						and find(node, "InboxView") == inbox
						and find(node, "LinkedView") == linked
				):toBe(true)
				built.model.transfers:set(false)
				expect(primary:FindFirstChild("Sidebar").Visible):toBe(true)
				expect((find(node, "InboxView"))):toBeNil()
				stop()
			end,
		})
	end)

	describe("file library folders", function()
		it("opens folders with desktop double click or touch and gamepad activation, then goes back", {
			id = "native_gallery_collections::file library folders::opens folders with desktop double click or touch and gamepad activation, then goes back",
			run = function()
				for _, inputName in { "MouseButton1", "Touch", "Gamepad1" } do
					local built, node, stop, engine, world = mount(scenarios.collection_workbench)
					local model = built.model
					model.query:set("Environments")
					local body = find(node, "primary")
					viewport(body, engine, 700, 600)
					local hit = find(find(body, "environments"), "RowHit")
					local input = {
						UserInputType = if inputName == "MouseButton1"
							then engine.types.Enum.UserInputType.MouseButton1
							elseif inputName == "Touch" then engine.types.Enum.UserInputType.Touch
							else engine.types.Enum.UserInputType.Gamepad1,
					}
					hit.Activated:Fire(input, 1)
					if inputName == "MouseButton1" then
						expect(#model.path:peek()):toBe(0)
						hit.Activated:Fire(input, 2)
					end
					expect(model.path:peek()[1].value):toBe("environments")
					expect((next(model.selection:peek()))):toBeNil()
					world.gui.SelectedObject = find(find(node, "Folders"), "Back")
					local back = assert(action(world.target, "NavigationBack"))
					expect(back ~= nil):toBe(true)
					engine.environment.fire(VerifyRoblox.assertInstance(back), "Pressed")
					engine.environment.fire(VerifyRoblox.assertInstance(back), "Released")
					expect(#model.path:peek()):toBe(0)
					expect((action(world.target, "NavigationBack"))):toBeNil()
					stop()
				end
			end,
		})
	end);
	(function(verifyHarness: Verify.Harness)
		type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
		type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
		type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
		type MotionLevel = typeof(require("@repo/tools/typecheck/aliases").MotionLevel)
		type ReadOnlyValue<T> = typeof(require("@repo/src/vendor/compose/core").accumulator<<T, number>>(nil :: never))
		type Use = <T>(ReadOnlyValue<T>) -> T

		local Facet = require("../src")
		local engineLib = require("./lib/native_engine")
		local fs = require("@std/fs")
		local gallery = require("../examples/gallery/client/screen")
		local playlistExample = require("../examples/gallery/examples/02_playlist_table")
		local Compose: ComposeModule = Facet.Compose

		type World = {
			built: any,
			root: any,
			screen: any,
			engine: any,
			gui: any,
			runtime: any,
			stop: () -> (),
		}

		type Options = {
			reducedMotion: boolean?,
			heartbeat: boolean?,
			guiService: boolean?,
			viewport: any?,
			seed: number?,
		}

		local function world(module: any, options: Options?): World
			local settings: Options = options or {}
			local engine: any = engineLib.new()
			local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
			local gui = engine.new("GuiService")
			engine.environment.poke(gui, "ReducedMotionEnabled", settings.reducedMotion == true)
			local input = engine.new("UserInputService")
			input.GetFocusedTextBox = function()
				return nil
			end
			local screen = engine.new("ScreenGui")
			local built
			local stop, root: any = runtime.mount(function()
				built = module.build({
					Facet = Facet,
					Compose = Compose,
					runtime = runtime,
					Host = Facet.host(runtime),
					UI = Facet.controls(
						runtime,
						{
							types = engine.types,
							guiService = gui,
							services = { GuiService = gui, UserInputService = input },
						} :: any
					),
					types = engine.types,
					viewport = settings.viewport or Compose.cell({ width = 1000, height = 720 }),
					guiService = if settings.guiService or settings.reducedMotion ~= nil then gui else nil,
					heartbeat = if settings.heartbeat then engine.heartbeat else nil,
				})
				return built.screen()
			end, screen)
			return {
				built = built,
				root = root,
				screen = screen,
				engine = engine,
				gui = gui,
				runtime = runtime,
				stop = function()
					stop()
					runtime:dispose()
				end,
			}
		end

		local function find(node: any, name: string): any
			if node.Name == name then
				return node
			end
			for _, child in node:GetChildren() do
				local found = find(child, name)
				if found then
					return found
				end
			end
			return nil
		end

		local function within(node: any, ...: string): any
			local at = node
			for _, name in { ... } do
				at = find(at, name)
				if at == nil then
					return nil
				end
			end
			return at
		end

		local function press(node: any, ...: string)
			local target = assert(within(node, ...), `no {table.concat({ ... }, "/")}`)
			target.Activated:Fire()
		end

		describe("native parity reference applications", function()
			describe("Tables and radial menus", function()
				local function controlsFor(engine: any, target: any, extra: { [string]: any }?)
					local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
					local gui, input = engine.new("GuiService"), engine.new("UserInputService")
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
						inputParent = target,
						motionLevel = "none",
					}
					if extra then
						for key, value in extra do
							config[key] = value
						end
					end
					return runtime, Facet.controls(runtime, config :: any), gui, input
				end

				local function mountGallery()
					local engine = engineLib.new()
					local target = engine.new("Folder")
					local viewport = Compose.cell({ width = 1280, height = 720 })
					local runtime, UI, gui = controlsFor(engine, target, { viewport = viewport })
					local ctx: ExampleContext = {
						Facet = Facet,
						Compose = Compose,
						runtime = runtime,
						Host = Facet.host(runtime),
						types = engine.types,
						viewport = viewport,
						guiService = gui,
						UI = UI,
					}
					local built: typeof(playlistExample.build(ctx))? = nil
					local stop, node: any = runtime.mount(function()
						local result = playlistExample.build(ctx)
						built = result
						Compose.cleanup(result.dispose)
						return ctx.Host.ScreenGui "DemoScreen" { result.screen() }
					end, target)
					return {
						built = assert(built),
						node = node,
						engine = engine,
						target = target,
						stop = function()
							stop()
							runtime:dispose()
						end,
					}
				end

				local function vector(engine: any, x: number, y: number): any
					return engine.types.Vector2.new(x, y)
				end

				describe("Playlist example", function()
					local function prepare(world: any): any
						local body = find(world.node, "Body")
						world.engine.environment.poke(body, "AbsoluteSize", vector(world.engine, 900, 288))
						world.engine.environment.poke(
							body,
							"AbsoluteWindowSize",
							vector(world.engine, 900 - body.ScrollBarThickness, 288)
						)
						return body
					end

					local function click(world: any, kind: string, count: number?): any
						local E = world.engine.types.Enum
						return {
							UserInputType = if kind == "mouse"
								then E.UserInputType.MouseButton1
								elseif kind == "touch" then E.UserInputType.Touch
								else E.UserInputType.Keyboard,
							KeyCode = if kind == "key" then E.KeyCode.Return else E.KeyCode:FromValue(0),
							UserInputState = E.UserInputState.End,
						},
							count or 1
					end

					it("explains empty filter results and an empty playlist without losing Restore", {
						id = "native_gallery_collections::Playlist example::explains empty filter results and an empty playlist without losing Restore",
						run = function()
							local world = mountGallery()
							prepare(world)
							local message = find(world.node, "EmptyResult")
							expect(message ~= nil):toBe(true)
							expect(message.Visible):toBe(false)
							world.built.filterText:set("zz-no-match")
							expect(#world.built.from:peek()):toBe(0)
							expect(message.Visible):toBe(true)
							expect(message.Text):toBe(
								"No tracks match this filter. Clear the filter to show all tracks."
							)
							expect(message.TextWrapped):toBe(true)
							world.built.filterText:set("")
							expect(message.Visible):toBe(false)
							expect(#world.built.from:peek()):toBe(6)
							for _, id in { "neon", "drift", "turbo", "pit", "photo", "apex" } do
								world.built.removeTrack(id)
							end
							expect(message.Visible):toBe(true)
							expect(message.Text):toBe(
								"No tracks in this playlist. Restore the original playlist to add them again."
							)
							expect(find(world.node, "Restore").Visible):toBe(true)
							press(world.node, "Restore")
							expect(message.Visible):toBe(false)
							expect(#world.built.from:peek()):toBe(6)
							world.stop()
						end,
					})

					it("aligns name artist and rating columns under their headers", {
						id = "native_gallery_collections::Playlist example::aligns name artist and rating columns under their headers",
						run = function()
							local world = mountGallery()
							local body = prepare(world)
							for _, label in body:GetDescendants() do
								if label:IsA("TextLabel") then
									world.engine.environment.poke(label, "TextFits", true)
								end
							end

							local header = find(world.node, "Header")
							local row = find(body, "neon")
							local cells = find(row, "Row")
							expect(header.Position.X.Offset):toBe(find(row, "Cells").Position.X.Offset)
							expect(header.Size.X.Offset):toBe(
								body.AbsoluteWindowSize.X + find(row, "Cells").Size.X.Offset
							)
							local E = world.engine.types.Enum
							local allocated = 0
							for _, id in { "name", "artist", "rating" } do
								local width = header:FindFirstChild(id).Size.X.Offset
								allocated += width
								expect(width >= (if id == "rating" then 144 elseif id == "name" then 90 else 72)):toBe(
									true
								)
								expect(cells:FindFirstChild(id).Size):toBe(header:FindFirstChild(id).Size)
								expect(header:FindFirstChild(id):FindFirstChildWhichIsA("UIFlexItem").FlexMode):toBe(
									if id ~= "rating" then E.UIFlexMode.Fill else E.UIFlexMode.None
								)
							end
							expect(allocated):toBe(header.Size.X.Offset)
							world.built.columnWidths:set({ name = 290 })
							expect(header:FindFirstChild("name").Size.X.Offset):toBe(290)
							expect(cells:FindFirstChild("name").Size.X.Offset):toBe(290)
							expect(cells:FindFirstChild("rating").Size.X.Offset):toBe(144)
							expect(world.built.widths()):toBe("Name 290px · Artist auto · Rating locked")
							world.stop()
						end,
					})

					it("plays on a double click Return or touch tap while a single or slow click only selects", {
						id = "native_gallery_collections::Playlist example::plays on a double click Return or touch tap while a single or slow click only selects",
						run = function()
							local world = mountGallery()
							local body = prepare(world)
							local label = find(world.node, "NowPlaying")
							local function hit(id: string): any
								return find(find(body, id), "RowHit")
							end
							local function selected(id: string): boolean
								return find(find(body, id), "Row"):GetAttribute("FacetSelected") == true
							end
							expect(label.Text):toBe(
								"Nothing playing — double-click a row, or press Return on a focused one"
							)
							hit("neon").Activated:Fire(click(world, "mouse", 1))
							expect((selected("neon"))):toBe(true)
							expect((world.built.nowPlaying:peek())):toBeNil()
							expect(label.Text):toBe(
								"Nothing playing — double-click a row, or press Return on a focused one"
							)
							hit("neon").Activated:Fire(click(world, "mouse", 2))
							expect((world.built.nowPlaying:peek())):toBe("Neon Straightaway")
							expect(label.Text):toBe("Now playing — Neon Straightaway")
							expect((selected("neon"))):toBe(true)
							hit("drift").Activated:Fire(click(world, "mouse", 1))
							hit("drift").Activated:Fire(click(world, "mouse", 1))
							expect(label.Text):toBe("Now playing — Neon Straightaway")
							expect((selected("drift"))):toBe(true)
							expect((selected("neon"))):toBe(false)
							hit("turbo").Activated:Fire(click(world, "touch", 1))
							expect(label.Text):toBe("Now playing — Turbo Cascade")
							hit("pit").Activated:Fire(click(world, "key", 1))
							expect(label.Text):toBe("Now playing — Pit Lane Shuffle")
							press(world.node, "Restore")
							expect((world.built.nowPlaying:peek())):toBeNil()
							expect(label.Text):toBe(
								"Nothing playing — double-click a row, or press Return on a focused one"
							)
							world.stop()
						end,
					})
				end)
			end)
		end)
	end)(verifyHarness)
end
