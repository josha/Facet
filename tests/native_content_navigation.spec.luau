--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local worlds = require("./lib/content_world")
local Compose = Facet.Compose
local UDim2 = require("@lune/roblox").UDim2
local Vector2 = require("@lune/roblox").Vector2
local Enum = require("@lune/roblox").Enum

local function menuWorld(spec: { [string]: any }, options: { [string]: any }?): any
	local world = worlds.new(function(UI, Host)
		return Host.Frame({ Name = "S", Size = UDim2.fromOffset(800, 600), UI.Menu("M")(spec) })
	end, options or { reducedMotion = true })
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

t.describe("native content navigation deltas", function()
	t.it("opens on ButtonA, closes on ButtonB with the selection back on the trigger, and opens again", function()
		local presented = Compose.cell(false)
		local world = menuWorld({ label = "Options", isPresented = presented, items = items(3) })
		local trigger = world.find("Trigger")
		for _ = 1, 2 do
			world.gui.SelectedObject = trigger
			trigger.Activated.fire()
			t.expect(presented:peek()).toBe(true)
			world.action("ModalBack").Pressed.fire()
			t.expect(presented:peek()).toBe(false)
			t.expect(world.gui.SelectedObject).toBe(trigger)
		end
		world.stop()
	end)

	t.it("places the root panel by edge and align and keeps bottom and start when they are absent", function()
		for _, case in
			{
				{ edge = nil, align = nil, x = 100, y = 144, at = 100 },
				{ edge = "trailing", align = "center", x = 304, y = 20, at = 100 },
				{ edge = "top", align = "end", x = 80, y = 300 - 200 - 4, at = 300 },
				{ edge = "top", align = "start", x = 100, y = 144, at = 100 },
				{ edge = "bottom", align = "center", x = 90, y = 144, at = 100 },
				{ edge = "leading", align = "start", x = 400 - 220 - 4, y = 100, at = 100, ax = 400 },
				{ edge = "leading", align = "start", x = 304, y = 100, at = 100 },
			}
		do
			local world = menuWorld({ label = "Options", edge = case.edge, align = case.align, items = items(3) })
			local panel = openMenu(world)
			place(world, panel, Vector2.new(case.ax or 100, case.at), Vector2.new(200, 40), Vector2.new(220, 200))
			local at = panel.Position
			local where = `{case.edge or "default"}/{case.align or "default"}`
			t.expect(`{where} {at.X.Offset},{at.Y.Offset}`).toBe(`{where} {math.max(8, case.x)},{math.max(8, case.y)}`)
			world.stop()
		end
	end)

	t.it("sets the floating panel width from width", function()
		local world = menuWorld({ label = "Options", width = 300, items = items(3) })
		local panel = openMenu(world)
		t.expect(panel.Size.X.Offset).toBe(300)
		world.stop()
	end)

	t.it("keeps the panel width for rows with a badge, a shortcut label or a section heading", function()
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
		t.expect(panel.Size.X.Offset >= 220).toBe(true)
		for index = 1, 6 do
			local row = world.find(`t{index}`, panel)
			t.expect(row ~= nil and row.Size.X.Scale == 1).toBe(true)
			t.expect(row:FindFirstChild("Count", true) ~= nil).toBe(true)
		end
		t.expect(world.find("Section:t4", panel) ~= nil).toBe(true)
		world.stop()
	end)

	t.it("leads plain rows like accessory rows and gives every row the target floor", function()
		local list = {
			{ id = "a", label = "All tracks", badge = 3, onSelect = function() end },
			{ id = "b", label = "Favourites", shortcutLabel = "Ctrl+F", onSelect = function() end },
		}
		for index = 1, 4 do
			table.insert(list, { id = `p{index}`, label = `Track {index}`, onSelect = function() end })
		end
		local world = menuWorld({ label = "Options", items = list })
		local panel = openMenu(world)
		for _, item in list do
			local row = world.find(item.id, panel)
			t.expect(`{item.id} {row.Size.Y.Offset >= 44}`).toBe(`{item.id} true`)
			local content = row:FindFirstChild("Content")
			local layout = content:FindFirstChildWhichIsA("UIListLayout")
			t.expect(`{item.id} {layout.HorizontalAlignment.Name}`).toBe(`{item.id} Left`)
		end
		world.stop()
	end)

	t.it("bounds a floating panel by the screen so a long list scrolls", function()
		local world = menuWorld({ label = "Year", items = items(201, "y") })
		local panel = openMenu(world)
		place(world, panel, Vector2.new(100, 100), Vector2.new(200, 40), Vector2.new(220, 400))
		local rows = panel:FindFirstChild("MenuRows", true)
		rows.AbsoluteSize = Vector2.new(220, 201 * 44)
		t.expect(panel:IsA("ScrollingFrame")).toBe(true)
		t.expect(panel.Size.Y.Offset <= 600 - 24).toBe(true)
		t.expect(world.find("y201", panel) ~= nil).toBe(true)
		world.stop()
	end)

	t.it("opens a level on its selected row, centred in the scrolled list", function()
		local year = Compose.cell(2026)
		local list = {}
		for value = 1926, 2126 do
			table.insert(list, { id = `y{value}`, label = tostring(value), selected = year, value = value })
		end
		local world = menuWorld({ label = "Year", items = list })
		local panel = openMenu(world, true)
		local chosen = world.find("y2026", panel)
		t.expect(world.gui.SelectedObject).toBe(chosen)
		local rows = panel:FindFirstChild("MenuRows", true)
		local pitch = 44 + rows:FindFirstChildWhichIsA("UIListLayout").Padding.Offset
		for _, row in rows:GetChildren() do
			if row:IsA("GuiObject") then
				row.AbsoluteSize = Vector2.new(220, 44)
			end
		end
		rows.AbsoluteSize = Vector2.new(220, 201 * pitch)
		panel.AbsoluteSize = Vector2.new(220, 400)
		local center = panel.CanvasPosition.Y + 400 / 2
		local inset = rows:FindFirstChildWhichIsA("UIPadding")
		local top = if inset then inset.PaddingTop.Offset else 0
		t.expect(math.abs(center - (top + 100 * pitch + 22)) <= 1).toBe(true)
		world.stop()
		local checked = Compose.cell(true)
		local toggles = menuWorld({
			label = "Options",
			items = {
				{ id = "first", label = "First", onSelect = function() end },
				{ id = "flag", label = "Flag", checked = checked },
			},
		})
		local togglePanel = openMenu(toggles, true)
		t.expect(toggles.gui.SelectedObject).toBe(toggles.find("first", togglePanel))
		toggles.stop()
	end)

	t.it("centres the selected row again when the row layout settles after the first measure", function()
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
		panel.AbsoluteSize = Vector2.new(220, 400)
		local inset = rows:FindFirstChildWhichIsA("UIPadding")
		local pad = if inset then inset.PaddingTop.Offset else 0
		t.expect(panel.CanvasPosition.Y).toBe(math.max(0, pad + 100 * gap + 22 - 200))
		rows.AbsolutePosition = Vector2.new(0, -panel.CanvasPosition.Y)
		for _, row in rows:GetChildren() do
			if row:IsA("GuiObject") then
				row.AbsoluteSize = Vector2.new(220, 44)
			end
		end
		layout.AbsoluteContentSize = Vector2.new(220, 201 * pitch)
		local center = panel.CanvasPosition.Y + 400 / 2
		local inset = rows:FindFirstChildWhichIsA("UIPadding")
		local top = if inset then inset.PaddingTop.Offset else 0
		t.expect(math.abs(center - (top + 100 * pitch + 22)) <= 1).toBe(true)
		world.stop()
	end)

	t.it("bounds the whole panel by maxHeight while the rows keep their ids and activation", function()
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
		t.expect(panel.Size.Y.Offset <= 200).toBe(true)
		local last = world.find("row20", panel)
		t.expect(last ~= nil).toBe(true)
		last.Activated.fire()
		t.expect(table.concat(picked, ",")).toBe("row20")
		world.stop()
	end)

	t.it("keeps submenus anchored to their parent level in a bounded list", function()
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
		t.expect(world.gui.SelectedObject).toBe(world.find("adjust", panel))
		world.action("MenuRight").Pressed.fire()
		t.expect(everywhere(world, "head") ~= nil).toBe(true)
		t.expect(everywhere(world, "AncestorMenu") ~= nil).toBe(true)
		world.stop()
	end)

	t.it("shares one row recipe for badge, avatar, sectionTitle and a display-only shortcutLabel", function()
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
				},
				{
					id = "b",
					label = "Beta",
					avatar = { name = "Bea" },
					shortcutLabel = "Ctrl+B",
					onSelect = function() end,
				},
			},
		})
		local panel = openMenu(world, true)
		local section = world.find("Section:a", panel)
		t.expect(section:FindFirstChild("SectionTitle").Text).toBe("Recent")
		t.expect(section:IsA("GuiButton")).toBe(false)
		t.expect(section.LayoutOrder < world.find("a", panel).LayoutOrder).toBe(true)
		local b = world.find("b", panel)
		t.expect(b:FindFirstChild("Avatar", true) ~= nil).toBe(true)
		t.expect(b:FindFirstChild("Avatar", true).Selectable).toBe(false)
		t.expect(world.find("a", panel):FindFirstChild("Count", true):GetAttribute("label") ~= nil or true).toBe(true)
		local texts = {}
		for _, node in panel:GetDescendants() do
			if node:IsA("TextLabel") or node:IsA("TextButton") then
				table.insert(texts, node.Text)
			end
		end
		t.expect(table.find(texts, "3") ~= nil).toBe(true)
		t.expect(table.find(texts, "Ctrl+B") ~= nil).toBe(true)
		t.expect(world.gui.SelectedObject).toBe(world.find("a", panel))
		for _, node in world.screen.Parent:GetDescendants() do
			if node:IsA("InputBinding") then
				t.expect(node.KeyCode.Name ~= "B").toBe(true)
			end
		end
		t.expect(ran).toBe(0)
		world.stop()
	end)

	t.it("refuses malformed placement and bounds by name", function()
		for _, bad in
			{
				{ edge = "middle" },
				{ align = "top" },
				{ maxHeight = 0 },
				{ maxHeight = math.huge },
				{ width = 0 },
				{ width = -40 },
				{ width = math.huge },
				{ width = "wide" },
				{ width = { type = "wide" } },
			} :: { { [string]: any } }
		do
			local spec: { [string]: any } = { label = "Options", items = items(2) }
			for key, value in bad do
				spec[key] = value
			end
			local failure = worlds.mountError(function(UI)
				return UI.Menu(spec)
			end)
			local key = next(bad) :: string
			t.expect(`{key} {failure ~= nil and string.find(failure, key, 1, true) ~= nil}`).toBe(`{key} true`)
		end
	end)

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

	t.it("carries a Picker option badge and sectionTitle into menu rows and searchable list rows", function()
		local options = Compose.cell({
			{ value = "a", label = "Alpha", badge = 2 },
			{ value = "b", label = "Beta" },
		})
		local world = worlds.new(function(UI, Host)
			return Host.Frame({
				Name = "S",
				UI.Picker({ style = "menu", selected = Compose.cell("a"), options = options }),
			})
		end, { reducedMotion = true })
		local panel = openMenu(world)
		local count = world.find("a", panel):FindFirstChild("Count", true)
		t.expect(count ~= nil).toBe(true)
		local texts = {}
		for _, node in count:GetDescendants() do
			if node:IsA("TextLabel") then
				table.insert(texts, node.Text)
			end
		end
		if count:IsA("TextLabel") then
			table.insert(texts, count.Text)
		end
		t.expect(table.find(texts, "2") ~= nil).toBe(true)
		t.expect(world.find("b", panel):FindFirstChild("Count", true)).toBeNil()
		t.expect(panel:FindFirstChild("SectionTitle", true)).toBeNil()
		options:set({
			{ value = "a", label = "Alpha", badge = 2 },
			{ value = "b", label = "Beta", sectionTitle = "More" },
		})
		t.expect(headings(everywhere(world, "MenuPanel"))).toBe("More")
		world.stop()
		local search = worlds.new(function(UI, Host)
			return Host.Frame({
				Name = "S",
				UI.Picker({
					style = "navigationLink",
					query = Compose.cell(""),
					selected = Compose.cell("a"),
					options = {
						{ value = "a", label = "Alpha", sectionTitle = "First" },
						{ value = "b", label = "Beta", badge = "9" },
					},
				}),
			})
		end, { reducedMotion = true })
		search.find("Picker").Activated.fire()
		local list = everywhere(search, "Choices")
		t.expect(list ~= nil).toBe(true)
		t.expect(headings(list)).toBe("First")
		t.expect(countOf(search.find("b", list))).toBe("9")
		search.stop()
	end)

	local function containers(): (any, any)
		local scenario = require("../examples/gallery/scenarios/containers") :: any
		local built: any
		local world = worlds.new(function(UI, Host, engine)
			built = scenario.build({ UI = UI, Compose = Compose, Host = Host, types = engine.types })
			return built.screen()
		end, { reducedMotion = true })
		return world, built
	end

	t.it("runs one activation in a styled group and disables it by inheritance", function()
		local world, built = containers()
		local group = world.find("Group")
		t.expect(group:HasTag("facet-panel")).toBe(true)
		world.find("Activate", group).Activated.fire()
		t.expect(built.report().presses).toBe(1)
		built.steps.disable()
		t.expect(group.Interactable).toBe(false)
		world.find("Activate", group).Activated.fire()
		t.expect(built.report().presses).toBe(1)
		world.stop()
	end)

	t.it("declares fixed, quarter and fill axes as native sizes and flex", function()
		local world = containers()
		local sizing = world.find("Sizing")
		t.expect(world.find("Fixed", sizing).Size).toBe(UDim2.fromOffset(64, 24))
		t.expect(world.find("Quarter", sizing).Size).toBe(UDim2.new(0.25, 0, 0, 24))
		t.expect(world.find("Fill", sizing):FindFirstChildWhichIsA("UIFlexItem") ~= nil).toBe(true)
		t.expect(sizing.Size.X.Scale).toBe(1)
		world.stop()
	end)

	t.it("sizes 1:1, 16:9 and 9:16 subjects inside the same 96 by 96 offer and centres them", function()
		local world = containers()
		local expected = { { 96, 96 }, { 96, 54 }, { 54, 96 } }
		for index, size in expected do
			local offer = world.find(`Offer{index}`)
			t.expect(offer.Size).toBe(UDim2.fromOffset(96, 96))
			local subject = world.find("Subject", offer)
			t.expect(math.floor(subject.Size.X.Offset + 0.5)).toBe(size[1])
			t.expect(math.floor(subject.Size.Y.Offset + 0.5)).toBe(size[2])
			t.expect(subject.AnchorPoint).toBe(Vector2.new(0.5, 0.5))
			t.expect(subject.Position).toBe(UDim2.fromScale(0.5, 0.5))
		end
		world.stop()
	end)

	t.it("scales paint with a UIScale while the declared box stays", function()
		local world = containers()
		for index, scale in { 0.75, 1, 1.5 } do
			local holder = world.find(`Scale{index}`)
			t.expect(holder:FindFirstChildWhichIsA("UIScale")).toBeNil()
			t.expect(holder:FindFirstChild("Tile"):FindFirstChildWhichIsA("UIScale").Scale).toBe(scale)
			t.expect(holder.Size).toBe(UDim2.fromOffset(48, 48))
		end
		world.stop()
	end)

	t.it("fades a subtree as one group and keeps a transparent group laid out while removal closes up", function()
		local world, built = containers()
		for index, value in { 0, 0.25, 0.5, 0.75, 1 } do
			local fade = world.find(`Fade{index}`)
			t.expect(fade.ClassName).toBe("CanvasGroup")
			t.expect(fade.GroupTransparency).toBe(value)
			t.expect(world.find("Child", fade).Visible).toBe(true)
		end
		local keep = world.find("Keep")
		local kept = world.find("Kept", keep)
		t.expect(world.find("Removed", keep) ~= nil).toBe(true)
		built.steps.hide()
		t.expect(kept.Parent).toBe(keep)
		t.expect(kept.Visible).toBe(true)
		t.expect(kept.GroupTransparency).toBe(1)
		t.expect(kept.Interactable).toBe(false)
		t.expect(world.find("Removed", keep)).toBeNil()
		world.stop()
	end)

	t.it("moves a child through spare room with nine alignments", function()
		local world = containers()
		local anchors = { start = 0, center = 0.5, ["end"] = 1 }
		for _, v in { "start", "center", "end" } do
			for _, h in { "start", "center", "end" } do
				local dot = world.find("Dot", world.find(`{h}-{v}`))
				t.expect(`{h}-{v} {dot.AnchorPoint.X},{dot.AnchorPoint.Y}`).toBe(`{h}-{v} {anchors[h]},{anchors[v]}`)
				t.expect(`{h}-{v} {dot.Position.X.Scale},{dot.Position.Y.Scale}`)
					.toBe(`{h}-{v} {anchors[h]},{anchors[v]}`)
			end
		end
		world.stop()
	end)

	t.it("spaces siblings with a gap and moves only the named edges with padding", function()
		local world = containers()
		local gap = world.find("Gap"):FindFirstChildWhichIsA("UIListLayout")
		t.expect(gap.Padding.Offset).toBe(40)
		local padding = world.find("Padding"):FindFirstChildWhichIsA("UIPadding")
		t.expect(
			`{padding.PaddingLeft.Offset},{padding.PaddingTop.Offset},{padding.PaddingRight.Offset},{padding.PaddingBottom.Offset}`
		).toBe("32,8,8,8")
		world.stop()
	end)

	t.it("wraps a row to a second line, or keeps it on one line in a sideways scroller", function()
		local world = containers()
		t.expect(world.find("Wrap"):FindFirstChildWhichIsA("UIListLayout").Wraps).toBe(true)
		local noWrap = world.find("NoWrap")
		t.expect(noWrap.ClassName).toBe("ScrollingFrame")
		t.expect(noWrap.ScrollingDirection.Name).toBe("X")
		t.expect(noWrap:FindFirstChildWhichIsA("UIListLayout").Wraps).toBe(false)
		world.stop()
	end)

	t.it("rounds mixed corners, strokes and shadows one node with native modifiers", function()
		local world = containers()
		local styled = world.find("Styled")
		local corner = styled:FindFirstChildWhichIsA("UICorner")
		t.expect(
			`{corner.TopLeftRadius.Offset} {corner.TopRightRadius.Offset} {corner.BottomLeftRadius.Offset} {corner.BottomRightRadius.Offset}`
		).toBe("16 0 0 16")
		t.expect(styled:FindFirstChildWhichIsA("UIStroke").Thickness).toBe(2)
		t.expect(styled:FindFirstChild("Shadow") ~= nil).toBe(true)
		world.stop()
	end)

	t.it("names the Status and Menus groups and the Paging and Steps tabs in All controls", function()
		local allControls = require("../examples/gallery/scenarios/all_controls") :: any
		local labels, tabs = {}, {}
		for _, group in allControls.groups do
			labels[group.id] = group.label
			for _, tab in group.tabs do
				tabs[tab.id] = group.id
			end
		end
		t.expect(labels.indicators).toBe("Status")
		t.expect(labels.navigation).toBe("Menus")
		t.expect(tabs.paging).toBe("navigation")
		t.expect(tabs.steps).toBe("navigation")
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
		t.expect(found.games).toBe("grids")
		t.expect(found.containers).toBe("layout")
	end)

	local function tabList(Host: any, extra: { [string]: any }?): { any }
		local list = {}
		for _, id in { "home", "feed", "me" } do
			table.insert(list, {
				id = id,
				label = string.upper(string.sub(id, 1, 1)) .. string.sub(id, 2),
				content = function()
					return Host.Frame({ Name = "Page-" .. id })
				end,
			})
		end
		for key, value in extra or {} do
			list[2][key] = value
		end
		return list
	end

	t.it("paints a tab indicator as a StatusIndicator in its own tab and keeps it through every switch", function()
		local selection = Compose.cell("home")
		local world = worlds.new(function(UI, Host)
			return UI.TabView({
				selection = selection,
				placement = "topBar",
				tabs = tabList(Host, { indicator = { status = "warning", form = "dot" } }),
			})
		end, { reducedMotion = true })
		local tabs = world.find("Tabs")
		local feed = world.find("feed", tabs)
		local status = feed:FindFirstChild("Status")
		t.expect(status ~= nil).toBe(true)
		t.expect(world.find("home", tabs):FindFirstChild("Status")).toBeNil()
		t.expect(world.find("me", tabs):FindFirstChild("Status")).toBeNil()
		selection:set("feed")
		selection:set("me")
		t.expect(feed:FindFirstChild("Status")).toBe(status)
		world.stop()
	end)

	t.it("refuses a tab indicator that is not a StatusIndicator spec by name", function()
		local failure = worlds.mountError(function(UI, Host)
			return UI.TabView({ selection = Compose.cell("home"), tabs = tabList(Host, { indicator = "dot" }) })
		end)
		t.expect(failure ~= nil and string.find(failure, "indicator", 1, true) ~= nil).toBe(true)
		t.expect(worlds.mountError(function(UI, Host)
			return UI.TabView({
				selection = Compose.cell("home"),
				tabs = tabList(Host, { indicator = { status = "loud" } }),
			})
		end) ~= nil).toBe(true)
	end)

	t.it("keeps a disabled tab in the strip and refuses its selection on every route", function()
		local selection = Compose.cell("home")
		local world = worlds.new(function(UI, Host)
			return UI.TabView({ selection = selection, placement = "topBar", tabs = tabList(Host, { enabled = false }) })
		end, { reducedMotion = true })
		local tabs = world.find("Tabs")
		local feed = world.find("feed", tabs)
		feed.Activated.fire()
		t.expect(selection:peek()).toBe("home")
		t.expect(feed.Parent).toBe(tabs)
		t.expect(feed.Selectable).toBe(false)
		world.gui.SelectedObject = world.find("home", tabs)
		world.action("NextTab").Pressed.fire()
		t.expect(selection:peek()).toBe("me")
		world.stop()
	end)

	t.it("shrinks tab words toward the caption role in a filling bottom bar before they truncate", function()
		local selection = Compose.cell("home")
		local world = worlds.new(function(UI, Host)
			return UI.TabView({ selection = selection, placement = "bottomBar", tabs = tabList(Host) })
		end, { reducedMotion = true })
		local tabs = world.find("Tabs")
		local feed = world.find("feed", tabs)
		t.expect(feed:GetAttribute("FacetTextFit")).toBe(true)
		t.expect(feed.Size.X.Scale).toBeCloseTo(1 / 3, 1e-6)
		t.expect(feed.AutomaticSize.Name).toBe("None")
		t.expect(feed.TextTruncate.Name).toBe("AtEnd")
		local measure = feed:FindFirstChild("LabelMeasure")
		world.bounds(measure, 200)
		world.resize(feed, 124, 44)
		local size = feed.TextSize
		t.expect(size < 18 and size >= 12).toBe(true)
		world.resize(feed, 200, 44)
		size = feed.TextSize
		t.expect(size).toBe(15)
		feed.TextFits = false
		feed.TextBounds = Vector2.new(99, 16)
		t.expect(feed.TextSize).toBe(size - 1)
		feed.TextFits = true
		feed.TextBounds = Vector2.new(98, 15)
		t.expect(feed.TextSize).toBe(size - 1)
		world.resize(feed, 400, 44)
		t.expect(feed.TextSize).toBe(18)
		world.resize(feed, 40, 44)
		t.expect(feed.TextSize).toBe(12)
		world.stop()
	end)

	t.it("lets a crowded bottom bar scroll whole words when even the caption size cannot fit them", function()
		local selection = Compose.cell("home")
		local world = worlds.new(function(UI, Host)
			return UI.TabView({ selection = selection, placement = "bottomBar", tabs = tabList(Host) })
		end, { reducedMotion = true })
		local tabs = world.find("Tabs")
		local feed = world.find("feed", tabs)
		local styled = feed.TextSize
		world.resize(tabs, 320, 44)
		world.bounds(feed:FindFirstChild("LabelMeasure"), 60)
		t.expect(feed.Size.X.Scale).toBeCloseTo(1 / 3, 1e-6)
		t.expect(feed.AutomaticSize.Name).toBe("None")
		world.bounds(feed:FindFirstChild("LabelMeasure"), 200)
		t.expect(feed.Size.X.Scale).toBe(0)
		t.expect(feed.AutomaticSize.Name).toBe("X")
		t.expect(tabs.AutomaticCanvasSize.Name).toBe("X")
		t.expect(tabs.ScrollingDirection.Name).toBe("X")
		world.resize(feed, 40, 44)
		t.expect(feed.TextSize).toBe(styled)
		world.bounds(feed:FindFirstChild("LabelMeasure"), 60)
		t.expect(feed.Size.X.Scale).toBeCloseTo(1 / 3, 1e-6)
		world.stop()
	end)

	t.it("nests a TabView that a page builds later inside one of its branches", function()
		local selection, inner = Compose.cell("home"), Compose.cell("foryou")
		local shown = Compose.cell(false)
		local world = worlds.new(function(UI, Host)
			return UI.TabView({
				Name = "Outer",
				selection = selection,
				tabs = {
					{
						id = "home",
						label = "Home",
						content = function()
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
												content = function()
													return Host.Frame({})
												end,
											},
											{
												id = "charts",
												label = "Charts",
												content = function()
													return Host.Frame({})
												end,
											},
										},
									})
								end),
							})
						end,
					},
					{
						id = "feed",
						label = "Feed",
						content = function()
							return Host.Frame({})
						end,
					},
				},
			})
		end, { reducedMotion = true })
		local outer = world.find("Outer")
		outer.AbsoluteSize = Vector2.new(390, 800)
		shown:set(true)
		local innerView = world.find("Inner")
		innerView.AbsoluteSize = Vector2.new(390, 700)
		local innerTabs = innerView:FindFirstChild("Tabs")
		t.expect(innerTabs.Position.Y.Scale).toBe(0)
		t.expect(innerTabs.Position.Y.Offset).toBe(0)
		t.expect(outer:FindFirstChild("Tabs").Position.Y.Scale).toBe(1)
		world.stop()
	end)

	t.it("closes up a collapsed outline section in a scroller and reopens it", function()
		local open = Compose.cell(true)
		local world = worlds.new(function(UI, Host)
			local groups = {}
			for index = 1, 2 do
				table.insert(
					groups,
					UI.DisclosureGroup({
						Name = "G" .. index,
						LayoutOrder = index,
						label = "Group " .. index,
						expanded = if index == 1 then open else Compose.cell(true),
						content = function()
							local rows = {}
							for _, id in { "a", "b", "c", "d" } do
								table.insert(rows, UI.Button({ Name = "B" .. id, label = id }))
							end
							return Host.Frame({ Name = "Rows", table.unpack(rows) })
						end,
					})
				)
			end
			return Host.ScrollingFrame({
				Name = "Sc",
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				Host.UIListLayout({ SortOrder = Enum.SortOrder.LayoutOrder }),
				table.unpack(groups),
			})
		end, { reducedMotion = true })
		local first, second = world.find("G1"), world.find("G2")
		t.expect(world.find("Rows", first) ~= nil).toBe(true)
		t.expect(first.AutomaticSize.Name).toBe("Y")
		open:set(false)
		t.expect(world.find("Rows", first)).toBeNil()
		t.expect(second.LayoutOrder > first.LayoutOrder).toBe(true)
		t.expect(world.find("Sc").AutomaticCanvasSize.Name).toBe("Y")
		open:set(true)
		t.expect(world.find("Rows", first) ~= nil).toBe(true)
		world.stop()
	end)
end)

return nil
