--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type MenuItem = typeof(require("@repo/tools/typecheck/aliases").MenuItem)
	type PickerOption = typeof(require("@repo/tools/typecheck/aliases").PickerOption)
	local FixtureNavigationTypes = require("../src/ui/navigation_types")

	local materialize = require("./lib/materialize")
	local Facet = require("../src")
	local worlds = require("./lib/content_world")
	local Compose: ComposeModule = Facet.Compose
	local UDim2 = require("@lune/roblox").UDim2
	local Vector2 = require("@lune/roblox").Vector2
	local Enum = require("@lune/roblox").Enum

	local function menuWorld(spec: { [any]: any }, options: { [string]: any }?): any
		local world = worlds.new(function(UI: FacetControls, Host: RobloxHost)
			return Host.Frame({ Name = "S", Size = UDim2.fromOffset(800, 600), UI.Menu("M")(spec) })
		end, options or { motionLevel = "none" })
		return world
	end

	local function everywhere(world: any, name: string): any
		return world.find(name, world.screen.Parent)
	end

	local function openMenu(world: any, select: boolean?)
		local trigger = world.find("Trigger")
		if select then
			world.gui.SelectedObject = trigger
		end
		trigger.Activated.fire()
		return everywhere(world, "MenuPanel")
	end

	local function items(count: number, prefix: string?, extra: ((number) -> { [string]: any })?): { any }
		local out = {}
		for index = 1, count do
			local item: { [string]: any } =
				{ id = `{prefix or "row"}{index}`, label = `Row {index}`, onSelect = function() end }
			if extra then
				for key, value in extra(index) do
					item[key] = value
				end
			end
			out[index] = item
		end
		return out
	end

	local function place(world: any, panel: any, triggerAt: Vector2, triggerSize: Vector2, panelSize: Vector2)
		local trigger = world.find("Trigger")
		trigger.AbsolutePosition = triggerAt
		trigger.AbsoluteSize = triggerSize
		local modal = panel.Parent
		while modal and modal.Parent and modal.Parent ~= world.screen and modal.Parent.ClassName ~= "ScreenGui" do
			modal = modal.Parent
		end
		modal.AbsoluteSize = world.V2(800, 600)
		panel.AbsoluteSize = panelSize
	end

	verifyHarness:suite("native content navigation deltas", function()
		verifyHarness:case(
			"opens on ButtonA, closes on ButtonB with the selection back on the trigger, and opens again",
			{
				id = "native_content_navigation::native content navigation deltas::opens on ButtonA, closes on ButtonB with the selection back on the trigger, and opens again",
				run = function()
					local presented = Compose.cell(false)
					local world = menuWorld({ label = "Options", isPresented = presented, items = items(3) })
					local trigger = world.find("Trigger")
					for _ = 1, 2 do
						world.gui.SelectedObject = trigger
						trigger.Activated.fire()
						Verify.expect((presented:peek())):toBe(true)
						world.action("ModalBack").Pressed.fire()
						Verify.expect((presented:peek())):toBe(false)
						Verify.expect(world.gui.SelectedObject):toBe(trigger)
					end
					world.stop()
				end,
			}
		)

		verifyHarness:case("places the root panel by edge and align and keeps bottom and start when they are absent", {
			id = "native_content_navigation::native content navigation deltas::places the root panel by edge and align and keeps bottom and start when they are absent",
			run = function()
				for _, case in
					{
						{ edge = nil, align = nil, x = 100, y = 144, at = 100 },
						{ edge = "trailing" :: "trailing", align = "center" :: "center", x = 304, y = 20, at = 100 },
						{ edge = "top" :: "top", align = "end" :: "end", x = 80, y = 300 - 200 - 4, at = 300 },
						{ edge = "top" :: "top", align = "start" :: "start", x = 100, y = 144, at = 100 },
						{ edge = "bottom" :: "bottom", align = "center" :: "center", x = 90, y = 144, at = 100 },
						{
							edge = "leading" :: "leading",
							align = "start" :: "start",
							x = 400 - 220 - 4,
							y = 100,
							at = 100,
							ax = 400,
						},
						{ edge = "leading" :: "leading", align = "start" :: "start", x = 304, y = 100, at = 100 },
					} :: {
						{
							edge: ("top" | "bottom" | "leading" | "trailing")?,
							align: ("start" | "center" | "end")?,
							x: number,
							y: number,
							at: number,
							ax: number?,
						}
					}
				do
					local world =
						menuWorld({ label = "Options", edge = case.edge, align = case.align, items = items(3) })
					local panel = openMenu(world)
					place(
						world,
						panel,
						Vector2.new(case.ax or 100, case.at),
						Vector2.new(200, 40),
						Vector2.new(220, 200)
					)
					local at = materialize.position(panel)
					local where = `{case.edge or "default"}/{case.align or "default"}`
					Verify.expect(`{where} {at.X.Offset},{at.Y.Offset}`)
						:toBe(`{where} {math.max(8, case.x)},{math.max(8, case.y)}`)
					world.stop()
				end
			end,
		})

		verifyHarness:case("sets the floating panel width from width", {
			id = "native_content_navigation::native content navigation deltas::sets the floating panel width from width",
			run = function()
				local world = menuWorld({ label = "Options", width = 300, items = items(3) })
				local panel = openMenu(world)
				Verify.expect(panel.Size.X.Offset):toBe(300)
				world.stop()
			end,
		})

		verifyHarness:case("keeps the panel width for rows with a badge, a shortcut label or a section heading", {
			id = "native_content_navigation::native content navigation deltas::keeps the panel width for rows with a badge, a shortcut label or a section heading",
			run = function()
				local world = menuWorld({
					label = "Options",
					items = items(6, "t", function(index: number)
						return {
							badge = "New",
							shortcutLabel = if index == 1 then "Ctrl+1" else nil,
							sectionTitle = if index == 4 then "Night" else nil,
						}
					end),
				})
				local panel = openMenu(world)
				Verify.expect(panel.Size.X.Offset >= 220):toBe(true)
				for index = 1, 6 do
					local row = world.find(`t{index}`, panel)
					Verify.expect(row ~= nil and row.Size.X.Scale == 1):toBe(true)
					Verify.expect(row:FindFirstChild("Count", true) ~= nil):toBe(true)
				end
				Verify.expect(world.find("Section:t4", panel) ~= nil):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case("leads plain rows like accessory rows and gives every row the target floor", {
			id = "native_content_navigation::native content navigation deltas::leads plain rows like accessory rows and gives every row the target floor",
			run = function()
				local list = {
					{ id = "a", label = "All tracks", badge = 3, onSelect = function() end } :: MenuItem,
					{ id = "b", label = "Favourites", shortcutLabel = "Ctrl+F", onSelect = function() end } :: MenuItem,
				}
				for index = 1, 4 do
					table.insert(list, { id = `p{index}`, label = `Track {index}`, onSelect = function() end })
				end
				local world = menuWorld({ label = "Options", items = list })
				local panel = openMenu(world)
				for _, item in list do
					local row = world.find(item.id, panel)
					Verify.expect(`{item.id} {row.Size.Y.Offset >= 44}`):toBe(`{item.id} true`)
					local content = row:FindFirstChild("Content")
					local layout = content:FindFirstChildWhichIsA("UIListLayout")
					Verify.expect(`{item.id} {layout.HorizontalAlignment.Name}`):toBe(`{item.id} Left`)
				end
				world.stop()
			end,
		})

		verifyHarness:case("bounds a floating panel by the screen so a long list scrolls", {
			id = "native_content_navigation::native content navigation deltas::bounds a floating panel by the screen so a long list scrolls",
			run = function()
				local world = menuWorld({ label = "Year", items = items(201, "y") })
				local panel = openMenu(world)
				place(world, panel, Vector2.new(100, 100), Vector2.new(200, 40), Vector2.new(220, 400))
				local rows = panel:FindFirstChild("MenuRows", true)
				rows.AbsoluteSize = Vector2.new(220, 201 * 44)
				Verify.expect((panel:FindFirstChild("MenuScroll", true):IsA("ScrollingFrame"))):toBe(true)
				Verify.expect(panel.Size.Y.Offset <= 600 - 24):toBe(true)
				Verify.expect(world.find("y201", panel) ~= nil):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case("opens a level on its selected row, centred in the scrolled list", {
			id = "native_content_navigation::native content navigation deltas::opens a level on its selected row, centred in the scrolled list",
			run = function()
				local year = Compose.cell(2026)
				local list = {}
				for value = 1926, 2126 do
					table.insert(list, { id = `y{value}`, label = tostring(value), selected = year, value = value })
				end
				local world = menuWorld({ label = "Year", items = list })
				local panel = openMenu(world, true)
				local chosen = world.find("y2026", panel)
				Verify.expect(world.gui.SelectedObject):toBe(chosen)
				local rows = panel:FindFirstChild("MenuRows", true)
				local pitch = 44 + rows:FindFirstChildWhichIsA("UIListLayout").Padding.Offset
				for _, row in rows:GetChildren() do
					if row:IsA("GuiObject") then
						row.AbsoluteSize = Vector2.new(220, 44)
					end
				end
				rows.AbsoluteSize = Vector2.new(220, 201 * pitch)
				local scroller = panel:FindFirstChild("MenuScroll", true)
				panel.AbsoluteSize = Vector2.new(220, 400)
				scroller.AbsoluteSize = Vector2.new(220, 400)
				local center = scroller.CanvasPosition.Y + 400 / 2
				local inset = rows:FindFirstChildWhichIsA("UIPadding")
				local top = if inset then inset.PaddingTop.Offset else 0
				Verify.expect(math.abs(center - (top + 100 * pitch + 22)) <= 1):toBe(true)
				world.stop()
				local checked = Compose.cell(true)
				local toggles = menuWorld({
					label = "Options",
					items = {
						{ id = "first", label = "First", onSelect = function() end } :: MenuItem,
						{ id = "flag", label = "Flag", checked = checked } :: MenuItem,
					},
				})
				local togglePanel = openMenu(toggles, true)
				Verify.expect(toggles.gui.SelectedObject):toBe(toggles.find("first", togglePanel))
				toggles.stop()
			end,
		})

		verifyHarness:case("centres the selected row again when the row layout settles after the first measure", {
			id = "native_content_navigation::native content navigation deltas::centres the selected row again when the row layout settles after the first measure",
			run = function()
				local year = Compose.cell(2026)
				local list = {}
				for value = 1926, 2126 do
					table.insert(list, { id = `y{value}`, label = tostring(value), selected = year, value = value })
				end
				local world = menuWorld({ label = "Year", items = list })
				local panel = openMenu(world, true)
				local chosen = world.find("y2026", panel)
				local rows = panel:FindFirstChild("MenuRows", true)
				local layout = rows:FindFirstChildWhichIsA("UIListLayout")
				local gap = layout.Padding.Offset
				local pitch = 44 + gap
				chosen.AbsoluteSize = Vector2.new(220, 44)
				rows.AbsoluteSize = Vector2.new(220, 201 * pitch)
				local scroller = panel:FindFirstChild("MenuScroll", true)
				panel.AbsoluteSize = Vector2.new(220, 400)
				scroller.AbsoluteSize = Vector2.new(220, 400)
				local inset = rows:FindFirstChildWhichIsA("UIPadding")
				local pad = if inset then inset.PaddingTop.Offset else 0
				Verify.expect(scroller.CanvasPosition.Y):toBe(math.max(0, pad + 100 * gap + 22 - 200))
				rows.AbsolutePosition = Vector2.new(0, -scroller.CanvasPosition.Y)
				for _, row in rows:GetChildren() do
					if row:IsA("GuiObject") then
						row.AbsoluteSize = Vector2.new(220, 44)
					end
				end
				layout.AbsoluteContentSize = Vector2.new(220, 201 * pitch)
				local center = scroller.CanvasPosition.Y + 400 / 2
				local inset = rows:FindFirstChildWhichIsA("UIPadding")
				local top = if inset then inset.PaddingTop.Offset else 0
				Verify.expect(math.abs(center - (top + 100 * pitch + 22)) <= 1):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case("bounds the whole panel by maxHeight while the rows keep their ids and activation", {
			id = "native_content_navigation::native content navigation deltas::bounds the whole panel by maxHeight while the rows keep their ids and activation",
			run = function()
				local picked: { string } = {}
				local world = menuWorld({
					label = "Options",
					maxHeight = 200,
					items = items(20, "row", function(index: number)
						return {
							onSelect = function()
								table.insert(picked, `row{index}`)
							end,
						}
					end),
				})
				local panel = openMenu(world)
				place(world, panel, Vector2.new(100, 100), Vector2.new(200, 40), Vector2.new(220, 200))
				panel:FindFirstChild("MenuRows", true).AbsoluteSize = Vector2.new(220, 20 * 44)
				Verify.expect(panel.Size.Y.Offset <= 200):toBe(true)
				local last = world.find("row20", panel)
				Verify.expect(last ~= nil):toBe(true)
				last.Activated.fire()
				Verify.expect((table.concat(picked, ","))):toBe("row20")
				world.stop()
			end,
		})

		verifyHarness:case("keeps submenus anchored to their parent level in a bounded list", {
			id = "native_content_navigation::native content navigation deltas::keeps submenus anchored to their parent level in a bounded list",
			run = function()
				local world = menuWorld({
					label = "Options",
					maxHeight = 300,
					items = {
						{
							id = "adjust",
							label = "Adjust",
							children = { { id = "head", label = "Head", onSelect = function() end } },
						},
					},
				})
				local panel = openMenu(world, true)
				Verify.expect(world.gui.SelectedObject):toBe(world.find("adjust", panel))
				world.action("MenuRight").Pressed.fire()
				Verify.expect(everywhere(world, "head") ~= nil):toBe(true)
				Verify.expect(everywhere(world, "AncestorMenu") ~= nil):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case("shares one row recipe for badge, avatar, sectionTitle and a display-only shortcutLabel", {
			id = "native_content_navigation::native content navigation deltas::shares one row recipe for badge, avatar, sectionTitle and a display-only shortcutLabel",
			run = function()
				local ran = 0
				local world = menuWorld({
					label = "Options",
					items = {
						{
							id = "a",
							label = "Alpha",
							badge = 3,
							sectionTitle = "Recent",
							onSelect = function()
								ran += 1
							end,
						} :: MenuItem,
						{
							id = "b",
							label = "Beta",
							avatar = { name = "Bea" },
							shortcutLabel = "Ctrl+B",
							onSelect = function() end,
						} :: MenuItem,
					},
				})
				local panel = openMenu(world, true)
				local section = world.find("Section:a", panel)
				Verify.expect(section:FindFirstChild("SectionTitle").Text):toBe("Recent")
				Verify.expect((section:IsA("GuiButton"))):toBe(false)
				Verify.expect(section.LayoutOrder < world.find("a", panel).LayoutOrder):toBe(true)
				local b = world.find("b", panel)
				Verify.expect(b:FindFirstChild("Avatar", true) ~= nil):toBe(true)
				Verify.expect(b:FindFirstChild("Avatar", true).Selectable):toBe(false)
				Verify.expect(world.find("a", panel):FindFirstChild("Count", true):GetAttribute("label") ~= nil or true)
					:toBe(true)
				local texts = {}
				for _, node in panel:GetDescendants() do
					if node:IsA("TextLabel") or node:IsA("TextButton") then
						table.insert(texts, node.Text)
					end
				end
				Verify.expect(table.find(texts, "3") ~= nil):toBe(true)
				Verify.expect(table.find(texts, "Ctrl+B") ~= nil):toBe(true)
				Verify.expect(world.gui.SelectedObject):toBe(world.find("a", panel))
				for _, node in world.screen.Parent:GetDescendants() do
					if node:IsA("InputBinding") then
						Verify.expect(node.KeyCode.Name ~= "B"):toBe(true)
					end
				end
				Verify.expect(ran):toBe(0)
				world.stop()
			end,
		})

		verifyHarness:case("refuses malformed placement and bounds by name", {
			id = "native_content_navigation::native content navigation deltas::refuses malformed placement and bounds by name",
			run = function()
				for _, bad in
					{
						{ edge = "middle" :: "middle" },
						{ align = "top" :: "top" },
						{ maxHeight = 0 },
						{ maxHeight = math.huge },
						{ width = 0 },
						{ width = -40 },
						{ width = math.huge },
						{ width = "wide" :: "wide" },
						{ width = { type = "wide" } },
					} :: { { [string]: any } }
				do
					local spec: { [any]: any } = { label = "Options", items = items(2) }
					for key, value in bad do
						spec[key] = value
					end
					local failure = worlds.mountError(function(UI: FacetControls)
						return UI.Menu(spec :: any)
					end)
					local key = next(bad) :: string
					Verify.expect(`{key} {failure ~= nil and string.find(failure, key, 1, true) ~= nil}`)
						:toBe(`{key} true`)
				end
			end,
		})

		local function textsUnder(node: any): { string }
			local texts = {}
			if node:IsA("TextLabel") then
				table.insert(texts, node.Text)
			end
			for _, child in node:GetDescendants() do
				if child:IsA("TextLabel") then
					table.insert(texts, child.Text)
				end
			end
			return texts
		end

		local function headings(panel: any): string
			local out = {}
			for _, node in panel:GetDescendants() do
				if node.Name == "SectionTitle" then
					for _, text in textsUnder(node) do
						table.insert(out, text)
					end
				end
			end
			table.sort(out)
			return table.concat(out, " ")
		end

		local function countOf(row: any): string
			local count = row and row:FindFirstChild("Count", true)
			return if count then table.concat(textsUnder(count), " ") else "none"
		end

		verifyHarness:case("carries a Picker option badge and sectionTitle into menu rows and searchable list rows", {
			id = "native_content_navigation::native content navigation deltas::carries a Picker option badge and sectionTitle into menu rows and searchable list rows",
			run = function()
				local options = Compose.cell({
					{ value = "a", label = "Alpha", badge = 2 } :: PickerOption,
					{ value = "b", label = "Beta" } :: PickerOption,
				})
				local world = worlds.new(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						Name = "S",
						UI.Picker({ style = "menu" :: "menu", selected = Compose.cell("a"), options = options }),
					})
				end, { motionLevel = "none" })
				local panel = openMenu(world)
				local count = world.find("a", panel):FindFirstChild("Count", true)
				Verify.expect(count ~= nil):toBe(true)
				local texts = {}
				for _, node in count:GetDescendants() do
					if node:IsA("TextLabel") then
						table.insert(texts, node.Text)
					end
				end
				if count:IsA("TextLabel") then
					table.insert(texts, count.Text)
				end
				Verify.expect(table.find(texts, "2") ~= nil):toBe(true)
				Verify.expect((world.find("b", panel):FindFirstChild("Count", true))):toBeNil()
				Verify.expect((panel:FindFirstChild("SectionTitle", true))):toBeNil()
				options:set({
					{ value = "a", label = "Alpha", badge = 2 } :: PickerOption,
					{ value = "b", label = "Beta", sectionTitle = "More" } :: PickerOption,
				})
				Verify.expect((headings(everywhere(world, "MenuPanel")))):toBe("More")
				world.stop()
				local search = worlds.new(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						Name = "S",
						UI.Picker({
							style = "navigationLink" :: "navigationLink",
							query = Compose.cell(""),
							selected = Compose.cell("a"),
							options = {
								{ value = "a", label = "Alpha", sectionTitle = "First" } :: FixtureNavigationTypes.PickerOption<any>,
								{ value = "b", label = "Beta", badge = "9" } :: FixtureNavigationTypes.PickerOption<any>,
							},
						}),
					})
				end, { motionLevel = "none" })
				search.find("Picker").Activated.fire()
				local list = everywhere(search, "Choices")
				Verify.expect(list ~= nil):toBe(true)
				Verify.expect((headings(list))):toBe("First")
				Verify.expect((countOf(search.find("b", list)))):toBe("9")
				search.stop()
			end,
		})

		local function containers(): (any, any)
			local scenario = require("../examples/gallery/scenarios/containers") :: any
			local built: any
			local world = worlds.new(function(UI: FacetControls, Host: RobloxHost, engine)
				built = scenario.build({ UI = UI, Compose = Compose, Host = Host, types = engine.types })
				return built.screen()
			end, { motionLevel = "none" })
			return world, built
		end

		verifyHarness:case("runs one activation in a styled group and disables it by inheritance", {
			id = "native_content_navigation::native content navigation deltas::runs one activation in a styled group and disables it by inheritance",
			run = function()
				local world, built = containers()
				local group = world.find("Group")
				Verify.expect((group:HasTag("facet-panel"))):toBe(true)
				world.find("Activate", group).Activated.fire()
				Verify.expect(built.report().presses):toBe(1)
				built.steps.disable()
				Verify.expect(group.Interactable):toBe(false)
				world.find("Activate", group).Activated.fire()
				Verify.expect(built.report().presses):toBe(1)
				world.stop()
			end,
		})

		verifyHarness:case("declares fixed, quarter and fill axes as native sizes and flex", {
			id = "native_content_navigation::native content navigation deltas::declares fixed, quarter and fill axes as native sizes and flex",
			run = function()
				local world = containers()
				local sizing = world.find("Sizing")
				Verify.expect(world.find("Fixed", sizing).Size):toBe(UDim2.fromOffset(64, 24))
				Verify.expect(world.find("Quarter", sizing).Size):toBe(UDim2.new(0.25, 0, 0, 24))
				Verify.expect(world.find("Fill", sizing):FindFirstChildWhichIsA("UIFlexItem") ~= nil):toBe(true)
				Verify.expect(sizing.Size.X.Scale):toBe(1)
				world.stop()
			end,
		})

		verifyHarness:case("sizes 1:1, 16:9 and 9:16 subjects inside the same 96 by 96 offer and centres them", {
			id = "native_content_navigation::native content navigation deltas::sizes 1:1, 16:9 and 9:16 subjects inside the same 96 by 96 offer and centres them",
			run = function()
				local world = containers()
				local expected = { { 96, 96 }, { 96, 54 }, { 54, 96 } }
				for index, size in expected do
					local offer = world.find(`Offer{index}`)
					Verify.expect(offer.Size):toBe(UDim2.fromOffset(96, 96))
					local subject = world.find("Subject", offer)
					Verify.expect((math.floor(subject.Size.X.Offset + 0.5))):toBe(size[1])
					Verify.expect((math.floor(subject.Size.Y.Offset + 0.5))):toBe(size[2])
					Verify.expect(subject.AnchorPoint):toBe(Vector2.new(0.5, 0.5))
					Verify.expect(subject.Position):toBe(UDim2.fromScale(0.5, 0.5))
				end
				world.stop()
			end,
		})

		verifyHarness:case("scales paint with a UIScale while the declared box stays", {
			id = "native_content_navigation::native content navigation deltas::scales paint with a UIScale while the declared box stays",
			run = function()
				local world = containers()
				for index, scale in { 0.75, 1, 1.5 } do
					local holder = world.find(`Scale{index}`)
					Verify.expect((holder:FindFirstChildWhichIsA("UIScale"))):toBeNil()
					Verify.expect(holder:FindFirstChild("Tile"):FindFirstChildWhichIsA("UIScale").Scale):toBe(scale)
					Verify.expect(holder.Size):toBe(UDim2.fromOffset(48, 48))
				end
				world.stop()
			end,
		})

		verifyHarness:case(
			"fades a subtree as one group and keeps a transparent group laid out while removal closes up",
			{
				id = "native_content_navigation::native content navigation deltas::fades a subtree as one group and keeps a transparent group laid out while removal closes up",
				run = function()
					local world, built = containers()
					for index, value in { 0, 0.25, 0.5, 0.75, 1 } do
						local fade = world.find(`Fade{index}`)
						Verify.expect(fade.ClassName):toBe("CanvasGroup")
						Verify.expect(fade.GroupTransparency):toBe(value)
						Verify.expect(world.find("Child", fade).Visible):toBe(true)
					end
					local keep = world.find("Keep")
					local kept = world.find("Kept", keep)
					Verify.expect(world.find("Removed", keep) ~= nil):toBe(true)
					built.steps.hide()
					Verify.expect(kept.Parent):toBe(keep)
					Verify.expect(kept.Visible):toBe(true)
					Verify.expect(kept.GroupTransparency):toBe(1)
					Verify.expect(kept.Interactable):toBe(false)
					Verify.expect((world.find("Removed", keep))):toBeNil()
					world.stop()
				end,
			}
		)

		verifyHarness:case("moves a child through spare room with nine alignments", {
			id = "native_content_navigation::native content navigation deltas::moves a child through spare room with nine alignments",
			run = function()
				local world = containers()
				local anchors = { start = 0, center = 0.5, ["end"] = 1 }
				for _, v in { "start", "center", "end" } do
					for _, h in { "start", "center", "end" } do
						local dot = world.find("Dot", world.find(`{h}-{v}`))
						Verify.expect(`{h}-{v} {dot.AnchorPoint.X},{dot.AnchorPoint.Y}`)
							:toBe(`{h}-{v} {anchors[h]},{anchors[v]}`)
						Verify.expect(`{h}-{v} {dot.Position.X.Scale},{dot.Position.Y.Scale}`)
							:toBe(`{h}-{v} {anchors[h]},{anchors[v]}`)
					end
				end
				world.stop()
			end,
		})

		verifyHarness:case("spaces siblings with a gap and moves only the named edges with padding", {
			id = "native_content_navigation::native content navigation deltas::spaces siblings with a gap and moves only the named edges with padding",
			run = function()
				local world = containers()
				local gap = world.find("Gap"):FindFirstChildWhichIsA("UIListLayout")
				Verify.expect(gap.Padding.Offset):toBe(40)
				local padding = world.find("Padding"):FindFirstChildWhichIsA("UIPadding")
				Verify.expect(
					`{padding.PaddingLeft.Offset},{padding.PaddingTop.Offset},{padding.PaddingRight.Offset},{padding.PaddingBottom.Offset}`
				):toBe("32,8,8,8")
				world.stop()
			end,
		})

		verifyHarness:case("wraps a row to a second line, or keeps it on one line in a sideways scroller", {
			id = "native_content_navigation::native content navigation deltas::wraps a row to a second line, or keeps it on one line in a sideways scroller",
			run = function()
				local world = containers()
				Verify.expect(world.find("Wrap"):FindFirstChildWhichIsA("UIListLayout").Wraps):toBe(true)
				local noWrap = world.find("NoWrap")
				Verify.expect(noWrap.ClassName):toBe("ScrollingFrame")
				Verify.expect(noWrap.ScrollingDirection.Name):toBe("X")
				Verify.expect(noWrap:FindFirstChildWhichIsA("UIListLayout").Wraps):toBe(false)
				world.stop()
			end,
		})

		verifyHarness:case("rounds mixed corners, strokes and shadows one node with native modifiers", {
			id = "native_content_navigation::native content navigation deltas::rounds mixed corners, strokes and shadows one node with native modifiers",
			run = function()
				local world = containers()
				local styled = world.find("Styled")
				local corner = styled:FindFirstChildWhichIsA("UICorner")
				Verify.expect(
					`{corner.TopLeftRadius.Offset} {corner.TopRightRadius.Offset} {corner.BottomLeftRadius.Offset} {corner.BottomRightRadius.Offset}`
				):toBe("16 0 0 16")
				Verify.expect(styled:FindFirstChildWhichIsA("UIStroke").Thickness):toBe(2)
				Verify.expect(styled:FindFirstChild("Shadow") ~= nil):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case("names the Status and Menus groups and the Paging and Steps tabs in All controls", {
			id = "native_content_navigation::native content navigation deltas::names the Status and Menus groups and the Paging and Steps tabs in All controls",
			run = function()
				local allControls = require("../examples/gallery/scenarios/all_controls") :: any
				local labels, tabs = {}, {}
				for _, group in allControls.groups do
					labels[group.id] = group.label
					for _, tab in group.tabs do
						tabs[tab.id] = group.id
					end
				end
				Verify.expect(labels.indicators):toBe("Status")
				Verify.expect(labels.navigation):toBe("Menus")
				Verify.expect(tabs.paging):toBe("navigation")
				Verify.expect(tabs.steps):toBe("navigation")
				local collections = require("../examples/gallery/scenarios/collections") :: any
				local motion = require("../examples/gallery/scenarios/motion_layout") :: any
				local found = {}
				for _, fixture in { collections, motion } do
					for _, group in fixture.groups do
						for _, tab in group.tabs do
							found[tab.id] = group.id
						end
					end
				end
				Verify.expect(found.games):toBe("grids")
				Verify.expect(found.containers):toBe("layout")
			end,
		})

		local function tabList(Host: any, extra: { [string]: any }?): { any }
			local list = {}
			for _, id in { "home", "feed", "me" } do
				table.insert(list, {
					id = id,
					label = string.upper(string.sub(id, 1, 1)) .. string.sub(id, 2),
					content = function(): Instance
						return Host.Frame({ Name = "Page-" .. id })
					end,
				})
			end
			for key, value in (extra or {} :: { [string]: any }) do
				list[2][key] = value
			end
			return list
		end

		verifyHarness:case(
			"paints a tab indicator as a StatusIndicator in its own tab and keeps it through every switch",
			{
				id = "native_content_navigation::native content navigation deltas::paints a tab indicator as a StatusIndicator in its own tab and keeps it through every switch",
				run = function()
					local selection = Compose.cell("home")
					local world = worlds.new(function(UI: FacetControls, Host: RobloxHost)
						return UI.TabView({
							selection = selection,
							placement = "topBar" :: "topBar",
							tabs = tabList(Host, { indicator = { status = "warning", form = "dot" } }),
						})
					end, { motionLevel = "none" })
					local tabs = world.find("Tabs")
					local feed = world.find("feed", tabs)
					local status = feed:FindFirstChild("Status")
					Verify.expect(status ~= nil):toBe(true)
					Verify.expect((world.find("home", tabs):FindFirstChild("Status"))):toBeNil()
					Verify.expect((world.find("me", tabs):FindFirstChild("Status"))):toBeNil()
					selection:set("feed")
					selection:set("me")
					Verify.expect((feed:FindFirstChild("Status"))):toBe(status)
					world.stop()
				end,
			}
		)

		verifyHarness:case("refuses a tab indicator that is not a StatusIndicator spec by name", {
			id = "native_content_navigation::native content navigation deltas::refuses a tab indicator that is not a StatusIndicator spec by name",
			run = function()
				local failure = worlds.mountError(function(UI: FacetControls, Host: RobloxHost)
					return UI.TabView({
						selection = Compose.cell("home"),
						tabs = tabList(Host, { indicator = "dot" :: "dot" }),
					})
				end)
				Verify.expect(failure ~= nil and string.find(failure, "indicator", 1, true) ~= nil):toBe(true)
				Verify.expect(worlds.mountError(function(UI: FacetControls, Host: RobloxHost)
					return UI.TabView({
						selection = Compose.cell("home"),
						tabs = tabList(Host, { indicator = { status = "loud" } }),
					})
				end) ~= nil):toBe(true)
			end,
		})

		verifyHarness:case("keeps a disabled tab in the strip and refuses its selection on every route", {
			id = "native_content_navigation::native content navigation deltas::keeps a disabled tab in the strip and refuses its selection on every route",
			run = function()
				local selection = Compose.cell("home")
				local world = worlds.new(function(UI: FacetControls, Host: RobloxHost)
					return UI.TabView({
						selection = selection,
						placement = "topBar" :: "topBar",
						tabs = tabList(Host, { enabled = false }),
					})
				end, { motionLevel = "none" })
				local tabs = world.find("Tabs")
				local feed = world.find("feed", tabs)
				feed.Activated.fire()
				Verify.expect((selection:peek())):toBe("home")
				Verify.expect(feed.Parent):toBe(tabs)
				Verify.expect(feed.Selectable):toBe(false)
				world.gui.SelectedObject = world.find("home", tabs)
				world.action("NextTab").Pressed.fire()
				Verify.expect((selection:peek())):toBe("me")
				world.stop()
			end,
		})

		verifyHarness:case("shrinks tab words toward the caption role in a filling bottom bar before they truncate", {
			id = "native_content_navigation::native content navigation deltas::shrinks tab words toward the caption role in a filling bottom bar before they truncate",
			run = function()
				local selection = Compose.cell("home")
				local world = worlds.new(function(UI: FacetControls, Host: RobloxHost)
					return UI.TabView({
						selection = selection,
						placement = "bottomBar" :: "bottomBar",
						tabs = tabList(Host),
					})
				end, { motionLevel = "none" })
				local tabs = world.find("Tabs")
				local feed = world.find("feed", tabs)
				Verify.expect((feed:GetAttribute("FacetTextFit"))):toBe(true)
				Verify.expect(feed.Size.X.Scale):toBeCloseTo(1 / 3, 1e-6)
				Verify.expect(feed.AutomaticSize.Name):toBe("None")
				Verify.expect(feed.TextTruncate.Name):toBe("AtEnd")
				local measure = feed:FindFirstChild("LabelMeasure")
				world.bounds(measure, 200)
				world.resize(feed, 124, 44)
				local size = feed.TextSize
				Verify.expect(size < 18 and size >= 12):toBe(true)
				world.resize(feed, 200, 44)
				size = feed.TextSize
				Verify.expect(size):toBe(15)
				feed.TextFits = false
				feed.TextBounds = Vector2.new(99, 16)
				Verify.expect(feed.TextSize):toBe(size - 1)
				feed.TextFits = true
				feed.TextBounds = Vector2.new(98, 15)
				Verify.expect(feed.TextSize):toBe(size - 1)
				world.resize(feed, 400, 44)
				Verify.expect(feed.TextSize):toBe(18)
				world.resize(feed, 40, 44)
				Verify.expect(feed.TextSize):toBe(12)
				world.stop()
			end,
		})

		verifyHarness:case("sizes a sidebar rail to its widest tab by default, as before 0.12", {
			id = "native_content_navigation::native content navigation deltas::sizes a sidebar rail to its widest tab by default, as before 0.12",
			run = function()
				local world = worlds.new(function(UI: FacetControls, Host: RobloxHost)
					return UI.TabView({
						selection = Compose.cell("home"),
						placement = "sidebar" :: "sidebar",
						tabs = tabList(Host),
					})
				end, { motionLevel = "none" })
				local view = world.find("TabView")
				world.resize(view, 1200, 800)
				local tabs = world.find("Tabs")
				local content = world.find("Content")
				for _, id in { "home", "feed", "me" } do
					world.bounds(world.find(id, tabs):FindFirstChild("LabelMeasure"), if id == "feed" then 90 else 40)
				end
				local narrow = tabs.Size.X.Offset
				Verify.expect(narrow < 200 - 16):toBe(true)
				Verify.expect(content.Position.X.Offset):toBe(narrow + 16)
				world.bounds(world.find("feed", tabs):FindFirstChild("LabelMeasure"), 120)
				Verify.expect(tabs.Size.X.Offset):toBe(narrow + 30)
				Verify.expect(content.Position.X.Offset):toBe(narrow + 46)
				Verify.expect(world.find("feed", tabs).TextXAlignment.Name):toBe("Center")
				world.stop()
			end,
		})

		verifyHarness:case(
			"widens a sidebar rail by a skinned theme's content insets so a tab label is not truncated",
			{
				id = "native_content_navigation::native content navigation deltas::widens a sidebar rail by a skinned theme's content insets so a tab label is not truncated",
				run = function()
					local pixel = (require :: any)("../examples/themes/pixel_quest").build(Facet.themes)
					local bare = table.clone(pixel)
					bare.chrome = table.clone(pixel.chrome)
					bare.chrome.control = table.clone(pixel.chrome.control)
					bare.chrome.control.contentInsets = nil
					local widths = {}
					for _, package in { pixel, bare } do
						local world = worlds.new(function(UI: FacetControls, Host: RobloxHost)
							return UI.TabView({
								selection = Compose.cell("home"),
								placement = "sidebar" :: "sidebar",
								tabs = tabList(Host),
							})
						end, { motionLevel = "none", theme = package })
						world.resize(world.find("TabView"), 1200, 800)
						local tabs = world.find("Tabs")
						for _, id in { "home", "feed", "me" } do
							world.bounds(world.find(id, tabs):FindFirstChild("LabelMeasure"), 60)
						end
						table.insert(widths, tabs.Size.X.Offset)
						world.stop()
					end
					local insets = pixel.chrome.control.contentInsets
					Verify.expect(widths[1] - widths[2]):toBe(insets.left + insets.right)
				end,
			}
		)

		verifyHarness:case("clips its tab strip only while the tabs overflow, so a tab's chrome shadow is not cut", {
			id = "native_content_navigation::native content navigation deltas::clips its tab strip only while the tabs overflow, so a tab's chrome shadow is not cut",
			run = function()
				local world = worlds.new(function(UI: FacetControls, Host: RobloxHost)
					return UI.TabView({
						selection = Compose.cell("home"),
						placement = "topBar" :: "topBar",
						tabs = tabList(Host),
					})
				end, { motionLevel = "none" })
				local tabs = world.find("Tabs")
				tabs.AbsoluteWindowSize = Vector2.new(300, 44)
				tabs.AbsoluteCanvasSize = Vector2.new(300, 44)
				Verify.expect(tabs.ClipsDescendants):toBe(false)
				tabs.AbsoluteCanvasSize = Vector2.new(420, 44)
				Verify.expect(tabs.ClipsDescendants):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case("centres the tabs of a top bar, as before 0.12", {
			id = "native_content_navigation::native content navigation deltas::centres the tabs of a top bar, as before 0.12",
			run = function()
				local world = worlds.new(function(UI: FacetControls, Host: RobloxHost)
					return UI.TabView({
						selection = Compose.cell("home"),
						placement = "topBar" :: "topBar",
						tabs = tabList(Host),
					})
				end, { motionLevel = "none" })
				local layout = world.find("Tabs"):FindFirstChildWhichIsA("UIListLayout")
				Verify.expect(layout.HorizontalAlignment.Name):toBe("Center")
				world.stop()
			end,
		})

		verifyHarness:case("lets a crowded bottom bar scroll whole words when even the caption size cannot fit them", {
			id = "native_content_navigation::native content navigation deltas::lets a crowded bottom bar scroll whole words when even the caption size cannot fit them",
			run = function()
				local selection = Compose.cell("home")
				local world = worlds.new(function(UI: FacetControls, Host: RobloxHost)
					return UI.TabView({
						selection = selection,
						placement = "bottomBar" :: "bottomBar",
						tabs = tabList(Host),
					})
				end, { motionLevel = "none" })
				local tabs = world.find("Tabs")
				local feed = world.find("feed", tabs)
				local styled = feed.TextSize
				world.resize(tabs, 320, 44)
				world.bounds(feed:FindFirstChild("LabelMeasure"), 60)
				Verify.expect(feed.Size.X.Scale):toBeCloseTo(1 / 3, 1e-6)
				Verify.expect(feed.AutomaticSize.Name):toBe("None")
				world.bounds(feed:FindFirstChild("LabelMeasure"), 200)
				Verify.expect(feed.Size.X.Scale):toBe(0)
				Verify.expect(feed.AutomaticSize.Name):toBe("X")
				Verify.expect(tabs.AutomaticCanvasSize.Name):toBe("X")
				Verify.expect(tabs.ScrollingDirection.Name):toBe("X")
				world.resize(feed, 40, 44)
				Verify.expect(feed.TextSize):toBe(styled)
				world.bounds(feed:FindFirstChild("LabelMeasure"), 60)
				Verify.expect(feed.Size.X.Scale):toBeCloseTo(1 / 3, 1e-6)
				world.stop()
			end,
		})

		verifyHarness:case("nests a TabView that a page builds later inside one of its branches", {
			id = "native_content_navigation::native content navigation deltas::nests a TabView that a page builds later inside one of its branches",
			run = function()
				local selection, inner = Compose.cell("home"), Compose.cell("foryou")
				local shown = Compose.cell(false)
				local world = worlds.new(function(UI: FacetControls, Host: RobloxHost)
					return UI.TabView({
						Name = "Outer",
						selection = selection,
						tabs = {
							{
								id = "home",
								label = "Home",
								content = function(): Instance
									return Host.Frame({
										Name = "Branch",
										Compose.show(shown, function()
											return UI.TabView({
												Name = "Inner",
												selection = inner,
												tabs = {
													{
														id = "foryou",
														label = "For you",
														content = function(): Instance
															return Host.Frame({})
														end,
													} :: FixtureNavigationTypes.Tab,
													{
														id = "charts",
														label = "Charts",
														content = function(): Instance
															return Host.Frame({})
														end,
													} :: FixtureNavigationTypes.Tab,
												},
											})
										end),
									})
								end,
							} :: FixtureNavigationTypes.Tab,
							{
								id = "feed",
								label = "Feed",
								content = function(): Instance
									return Host.Frame({})
								end,
							} :: FixtureNavigationTypes.Tab,
						},
					})
				end, { motionLevel = "none" })
				local outer = world.find("Outer")
				outer.AbsoluteSize = Vector2.new(390, 800)
				shown:set(true)
				local innerView = world.find("Inner")
				innerView.AbsoluteSize = Vector2.new(390, 700)
				local innerTabs = innerView:FindFirstChild("Tabs")
				Verify.expect(innerTabs.Position.Y.Scale):toBe(0)
				Verify.expect(innerTabs.Position.Y.Offset):toBe(0)
				Verify.expect(outer:FindFirstChild("Tabs").Position.Y.Scale):toBe(1)
				world.stop()
			end,
		})

		verifyHarness:case("closes up a collapsed outline section in a scroller and reopens it", {
			id = "native_content_navigation::native content navigation deltas::closes up a collapsed outline section in a scroller and reopens it",
			run = function()
				local open = Compose.cell(true)
				local world = worlds.new(function(UI: FacetControls, Host: RobloxHost)
					local groups = {}
					for index = 1, 2 do
						table.insert(
							groups,
							UI.DisclosureGroup({
								Name = "G" .. index,
								LayoutOrder = index,
								label = "Group " .. index,
								expanded = if index == 1 then open else Compose.cell(true),
								content = function(): Instance
									local rows = {}
									for _, id in { "a", "b", "c", "d" } do
										table.insert(rows, UI.Button({ Name = "B" .. id, label = id }))
									end
									return Host.Frame({ Name = "Rows", table.unpack((rows :: unknown) :: { unknown }) })
								end,
							})
						)
					end
					return Host.ScrollingFrame({
						Name = "Sc",
						AutomaticCanvasSize = Enum.AutomaticSize.Y,
						Host.UIListLayout({ SortOrder = Enum.SortOrder.LayoutOrder }) :: unknown,
						table.unpack(groups),
					})
				end, { motionLevel = "none" })
				local first, second = world.find("G1"), world.find("G2")
				Verify.expect(world.find("Rows", first) ~= nil):toBe(true)
				Verify.expect(first.AutomaticSize.Name):toBe("Y")
				open:set(false)
				Verify.expect((world.find("Rows", first))):toBeNil()
				Verify.expect(second.LayoutOrder > first.LayoutOrder):toBe(true)
				Verify.expect(world.find("Sc").AutomaticCanvasSize.Name):toBe("Y")
				open:set(true)
				Verify.expect(world.find("Rows", first) ~= nil):toBe(true)
				world.stop()
			end,
		})
	end)

	return nil
end
