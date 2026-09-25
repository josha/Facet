--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local worlds = require("./lib/content_world")
local Compose = Facet.Compose
local Roblox = require("../src/vendor/compose/roblox")
local themes = require("../src/ui/themes")(Compose)
local engineLib = require("./lib/native_engine")
local lune = require("@lune/roblox")
local UDim2, UDim, Vector2 = lune.UDim2, lune.UDim, lune.Vector2

local FRAME = 1 / 60

local function items(count: number, log: { string }?): { any }
	local out = {}
	for index = 1, count do
		out[index] = {
			id = `row{index}`,
			label = `Row {index}`,
			onSelect = function()
				if log then
					table.insert(log, `row{index}`)
				end
			end,
		}
	end
	return out
end

local NESTED = {
	{ id = "plain", label = "Plain", onSelect = function() end },
	{
		id = "adjust",
		label = "Adjust",
		children = {
			{ id = "head", label = "Head", onSelect = function() end },
			{ id = "body", label = "Body", onSelect = function() end },
		},
	},
	{ id = "skin", label = "Skin", onSelect = function() end },
}

local function labelled(spec: { [string]: any }, options: { [string]: any }?): any
	local fields = table.clone(spec)
	if fields.trigger == nil and fields.label == nil then
		fields.label = "Options"
	end
	return worlds.new(function(UI, Host)
		return Host.Frame({ Name = "S", Size = UDim2.fromOffset(800, 600), UI.Menu("M")(fields) })
	end, options or { reducedMotion = true })
end

local function panelOf(world: any): any
	return world.find("MenuPanel", world.screen.Parent)
end

local function modalOf(world: any, panel: any): any
	local modal = panel.Parent
	while modal and modal.Parent and modal.Parent ~= world.screen and modal.Parent.ClassName ~= "ScreenGui" do
		modal = modal.Parent
	end
	return modal
end

local function lay(world: any, panel: any, at: Vector2, size: Vector2, panelSize: Vector2)
	local trigger = world.find("Trigger")
	trigger.AbsolutePosition = at
	trigger.AbsoluteSize = size
	modalOf(world, panel).AbsoluteSize = Vector2.new(800, 600)
	panel.AbsoluteSize = panelSize
end

local function open(world: any): any
	world.find("Trigger").Activated.fire()
	return panelOf(world)
end

local function sheetRules(): (any, any)
	local engine = engineLib.new()
	local runtime = Roblox.createRuntime(engine)
	local sheet
	local stop = runtime.mount(function()
		sheet = themes.createStyleSheet(runtime, themes.neutralPackage(), { types = engine.types })
		return runtime.constructors.Frame({ sheet })
	end, engine.new("Folder"))
	return sheet, function()
		stop()
		runtime:dispose()
	end
end

local function ruleIndex(sheet: any, selector: string): (number, any)
	for index, node in sheet:GetChildren() do
		if node.Selector == selector then
			return index, node:GetProperties()
		end
	end
	error("No rule: " .. selector)
end

local function luminance(color: any): number
	local function channel(value: number): number
		return if value <= 0.03928 then value / 12.92 else ((value + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * channel(color.R) + 0.7152 * channel(color.G) + 0.0722 * channel(color.B)
end

t.describe("native menu parity with main", function()
	t.it("attaches to the caller's trigger node and returns that same node without a wrapper", function()
		local authored, returned
		local ran: { string } = {}
		local world = worlds.new(function(UI, Host)
			authored = UI.Button "Opener" { label = "More" }
			returned = UI.Menu({
				trigger = authored,
				LayoutOrder = 3,
				items = items(2, ran),
			})
			return Host.Frame({ Name = "S", Size = UDim2.fromOffset(800, 600), returned })
		end, { reducedMotion = true })
		t.expect(returned).toBe(authored)
		t.expect(authored.Parent.Name).toBe("S")
		t.expect(authored.Name).toBe("Opener")
		t.expect(authored.LayoutOrder).toBe(3)
		authored.Activated.fire()
		local panel = panelOf(world)
		t.expect(panel ~= nil).toBe(true)
		world.find("row2", panel).Activated.fire()
		t.expect(ran).toEqual({ "row2" })
		world.stop()
		local named = worlds.new(function(UI, Host)
			return Host.Frame({
				UI.Menu "Actions" { trigger = UI.Button "Opener" { label = "More" }, items = items(1) },
			})
		end, { reducedMotion = true })
		t.expect(named.find("Actions").ClassName).toBe("TextButton")
		t.expect(named.find("Opener")).toBeNil()
		named.stop()
	end)

	t.it("fills each row title so a submenu chevron or check sits at the trailing edge", function()
		local world = worlds.new(function(UI, Host)
			return Host.Frame({
				Name = "S",
				Size = UDim2.fromOffset(800, 600),
				UI.Menu {
					trigger = UI.Button "Opener" { label = "More" },
					items = {
						{ id = "plain", label = "Plain", onSelect = function() end },
						{
							id = "deeper",
							label = "Deeper",
							children = { { id = "leaf", label = "Leaf", onSelect = function() end } },
						},
					},
				},
			})
		end, { reducedMotion = true })
		world.find("Opener").Activated.fire()
		local panel = panelOf(world)
		for _, id in { "plain", "deeper" } do
			local content = world.find(id, panel):FindFirstChild("Content")
			local words = content:FindFirstChild("Captions") or content:FindFirstChild("Title")
			t.expect(words ~= nil and words:FindFirstChildWhichIsA("UIFlexItem") ~= nil).toBe(true)
			t.expect(content.Size.X.Scale).toBe(1)
		end
		world.stop()
	end)

	t.it("dims the page behind a menu presented as a sheet and not behind a panel", function()
		for _, case in { { "sheet", true }, { "menu", false } } do
			local world = worlds.new(function(UI, Host)
				return Host.Frame({
					Name = "S",
					Size = UDim2.fromOffset(800, 600),
					UI.Menu {
						trigger = UI.Button "Opener" { label = "More" },
						presentation = case[1],
						items = { { id = "one", label = "One", onSelect = function() end } },
					},
				})
			end, { reducedMotion = true })
			world.find("Opener").Activated.fire()
			local catcher = world.find("DismissOutside")
			t.expect(`{case[1]}: {catcher.BackgroundTransparency < 1}`).toBe(`{case[1]}: {case[2]}`)
			world.stop()
		end
	end)

	t.it("refuses label and trigger together", function()
		local message = worlds.mountError(function(UI, Host)
			return Host.Frame({
				UI.Menu({ label = "More", trigger = UI.Button "Opener" { label = "More" }, items = items(1) }),
			})
		end)
		t.expect(message ~= nil and string.find(message, "label or trigger, not both", 1, true) ~= nil).toBe(true)
	end)

	t.it("calls onOpen and onClose once for each open and each close on every route", function()
		local log: { string } = {}
		local presented = Compose.cell(false)
		local world = labelled({
			items = NESTED,
			isPresented = presented,
			presentation = "menu",
			onOpen = function()
				table.insert(log, "open")
			end,
			onClose = function()
				table.insert(log, "close")
			end,
		})
		t.expect(log).toEqual({})
		open(world)
		world.find("skin", panelOf(world)).Activated.fire()
		t.expect(log).toEqual({ "open", "close" })
		open(world)
		world.find("DismissOutside", world.screen.Parent).Activated.fire()
		t.expect(log).toEqual({ "open", "close", "open", "close" })
		presented:set(true)
		t.expect(log).toEqual({ "open", "close", "open", "close", "open" })
		world.find("Trigger").Activated.fire()
		t.expect(#log).toBe(5)
		world.gui.SelectedObject = world.find("adjust", panelOf(world))
		world.action("ModalBack").Pressed.fire()
		t.expect(log).toEqual({ "open", "close", "open", "close", "open", "close" })
		t.expect(presented:peek()).toBe(false)
		presented:set(true)
		world.stop()
		t.expect(log[#log]).toBe("close")
		t.expect(#log).toBe(8)
	end)

	t.it("takes a dimension table, a UDim or pixels for width and refuses a malformed one by name", function()
		for _, case in
			{
				{ width = 300, expected = 300 },
				{ width = { type = "fixed", px = 300 }, expected = 300 },
				{ width = UDim.new(0.5, 10), expected = 402 },
				{ width = UDim2.new(0.25, 0, 0, 0), expected = 196 },
				{ width = { type = "percent", fraction = 0.5, offset = -8 }, expected = 384 },
				{ width = { type = "hug", min = 320 }, expected = 320 },
				{ width = { type = "hug", max = 200 }, expected = 200 },
				{ width = { type = "fill" }, expected = 784 },
				{ width = { type = "fixed", px = "targetSizes.minimum" }, expected = 44 },
			}
		do
			local world = labelled({ width = case.width, items = items(3) })
			local panel = open(world)
			lay(world, panel, Vector2.new(100, 100), Vector2.new(200, 40), Vector2.new(220, 200))
			t.expect(`{typeof(case.width)} {panel.Size.X.Offset}`).toBe(`{typeof(case.width)} {case.expected}`)
			world.stop()
		end
		for _, case in
			{
				{ width = { type = "aspect", ratio = 1 }, words = "width.type must be" },
				{ width = { type = "fixed" }, words = "a fixed width requires px" },
				{ width = { type = "fixed", px = 10, weight = 1 }, words = "does not take 'weight'" },
				{ width = -4, words = "width must be a finite number" },
			}
		do
			local message = worlds.mountError(function(UI, Host)
				return Host.Frame({ UI.Menu({ label = "More", width = case.width, items = items(1) }) })
			end)
			t.expect(message ~= nil and string.find(message, case.words, 1, true) ~= nil).toBe(true)
		end
	end)

	t.it("draws the anchored panel as one card with one hairline between each pair of rows", function()
		local checked = Compose.cell(true)
		local world = labelled({
			presentation = "menu",
			items = {
				{ id = "a", label = "Alpha", onSelect = function() end },
				{ id = "b", label = "Beta", checked = checked },
				{ id = "c", label = "Gamma", onSelect = function() end },
				{ divider = true },
				{ id = "d", label = "Delta", onSelect = function() end },
			},
		})
		local panel = open(world)
		t.expect(panel:HasTag("facet-menu")).toBe(true)
		t.expect(panel:FindFirstChildWhichIsA("UICorner")).toBeNil()
		t.expect(panel:FindFirstChildWhichIsA("UIStroke")).toBeNil()
		t.expect(panel:FindFirstChildWhichIsA("UIShadow")).toBeNil()
		t.expect(world.find("MenuGroup", panel):HasTag("facet-menu-group")).toBe(true)
		local rows = panel:FindFirstChild("MenuRows", true)
		t.expect(rows:FindFirstChildWhichIsA("UIListLayout").Padding.Offset).toBe(0)
		local padding = rows:FindFirstChildWhichIsA("UIPadding")
		t.expect(padding.PaddingTop.Offset + padding.PaddingLeft.Offset).toBe(0)
		local ruled = {}
		for _, id in { "a", "b", "c", "d" } do
			local row = world.find(id, panel)
			t.expect(row:HasTag("facet-menu-item")).toBe(true)
			t.expect(row:FindFirstChildWhichIsA("UICorner")).toBeNil()
			local hairline = row:FindFirstChild("Hairline")
			t.expect(hairline:HasTag("facet-menu-hairline")).toBe(true)
			t.expect(hairline.Size).toBe(UDim2.new(1, 0, 0, 1))
			ruled[id] = hairline.Visible
		end
		t.expect(ruled).toEqual({ a = false, b = true, c = true, d = false })
		t.expect(world.find("b", panel):HasTag("facet-selected")).toBe(true)
		t.expect(world.find("a", panel):HasTag("facet-selected")).toBe(false)
		checked:set(false)
		t.expect(world.find("b", panel):HasTag("facet-selected")).toBe(false)
		world.stop()
	end)

	t.it("keeps the sheet rows spaced and unruled, since the card is a presentation branch", function()
		local world = labelled({ presentation = "sheet", items = items(3) })
		local panel = open(world)
		local rows = panel:FindFirstChild("MenuRows", true)
		t.expect(rows:FindFirstChildWhichIsA("UIListLayout").Padding.Offset).toBe(8)
		for index = 1, 3 do
			t.expect(world.find(`row{index}`, panel):FindFirstChild("Hairline").Visible).toBe(false)
		end
		world.stop()
	end)

	t.it("grows a Back row only in the sheet and shows the open path on the parent level", function()
		for _, presentation in { "menu", "sheet" } do
			local world = labelled({ presentation = presentation, items = NESTED })
			local panel = open(world)
			world.find("adjust", panel).Activated.fire()
			t.expect(`{presentation} {world.find("Back", panel) ~= nil}`)
				.toBe(`{presentation} {presentation == "sheet"}`)
			if presentation == "menu" then
				local parent = world.find("AncestorMenu", world.screen.Parent)
				local row = world.find("adjust", parent)
				t.expect(row:HasTag("facet-selected")).toBe(true)
				t.expect(world.find("skin", parent):HasTag("facet-selected")).toBe(false)
				t.expect(world.find("skin", parent):FindFirstChild("Hairline").Visible).toBe(true)
				for _, id in { "plain", "adjust", "skin" } do
					local layout =
						world.find(id, parent):FindFirstChild("Content"):FindFirstChildWhichIsA("UIListLayout")
					t.expect(`{id} {layout.HorizontalAlignment.Name}`).toBe(`{id} Left`)
				end
			end
			world.stop()
		end
	end)

	t.it("paints a selected row with the accent under an onAccent label at 4.5:1 or better", function()
		local sheet, stop = sheetRules()
		local hover = ruleIndex(sheet, ".facet-menu-item:Hover")
		local generic = ruleIndex(sheet, ".facet-selected")
		local _, accent = ruleIndex(sheet, ".facet-accent")
		for _, selector in
			{
				".facet-menu-item.facet-selected",
				".facet-menu-item.facet-selected:Hover",
				".facet-menu-item.facet-selected:Press",
			}
		do
			local index, props = ruleIndex(sheet, selector)
			t.expect(index > hover and index > generic).toBe(true)
			t.expect(props.BackgroundTransparency).toBe(0)
			t.expect(props.BackgroundColor3).toBe(accent.BackgroundColor3)
		end
		local _, caption = ruleIndex(sheet, ".facet-menu-item.facet-selected >> .facet-button-caption")
		local _, text = ruleIndex(sheet, ".facet-menu-item.facet-selected >> .facet-text")
		local _, icon = ruleIndex(sheet, ".facet-menu-item.facet-selected >> .facet-icon")
		t.expect(caption.TextColor3).toBe(accent.TextColor3)
		t.expect(text.TextColor3).toBe(accent.TextColor3)
		t.expect(icon.ImageColor3).toBe(accent.TextColor3)
		local a, b = luminance(accent.BackgroundColor3), luminance(accent.TextColor3)
		t.expect((math.max(a, b) + 0.05) / (math.min(a, b) + 0.05) >= 4.5).toBe(true)
		local _, card = ruleIndex(sheet, ".facet-menu::UICorner")
		local _, panelCorner = ruleIndex(sheet, ".facet-panel::UICorner")
		t.expect(card.CornerRadius).toBe(panelCorner.CornerRadius)
		local _, clip = ruleIndex(sheet, ".facet-menu-group::UICorner")
		t.expect(clip.CornerRadius).toBe(panelCorner.CornerRadius)
		local _, stroke = ruleIndex(sheet, ".facet-menu::UIStroke")
		t.expect(stroke.Thickness).toBe(1)
		t.expect(stroke.ApplyStrokeMode.Name).toBe("Border")
		local _, shadow = ruleIndex(sheet, ".facet-menu::UIShadow")
		t.expect(shadow.BlurRadius.Offset > 0).toBe(true)
		local _, rule = ruleIndex(sheet, ".facet-menu-hairline")
		t.expect(rule.BackgroundTransparency < 1).toBe(true)
		stop()
	end)

	t.it("grows each level from 0.96 at the corner it hangs at, fades in and dips out faster", function()
		local world = labelled({ edge = "top", align = "end", items = NESTED, presentation = "menu" }, {})
		local panel = open(world)
		lay(world, panel, Vector2.new(300, 300), Vector2.new(200, 40), Vector2.new(220, 200))
		local scale = world.find("PresentationScale", panel)
		local group = world.find("MenuGroup", panel)
		t.expect(scale.Scale).toBe(0.96)
		t.expect(group.GroupTransparency).toBe(1)
		local shrink = 1 - scale.Scale
		t.expect(panel.Position.X.Offset).toBeCloseTo(280 + 220 * shrink, 1)
		t.expect(panel.Position.Y.Offset).toBeCloseTo(96 + 200 * shrink, 1)
		local enter = 0
		while group.GroupTransparency > 0.05 and enter < 60 do
			world.engine.heartbeat.fire(FRAME)
			enter += 1
		end
		for _ = 1, 30 do
			world.engine.heartbeat.fire(FRAME)
		end
		t.expect(scale.Scale).toBe(1)
		t.expect(panel.Position).toBe(UDim2.fromOffset(280, 96))
		world.find("adjust", panel).Activated.fire()
		t.expect(scale.Scale).toBe(0.96)
		t.expect(group.GroupTransparency).toBe(1)
		for _ = 1, 30 do
			world.engine.heartbeat.fire(FRAME)
		end
		t.expect(scale.Scale).toBe(1)
		world.find("DismissOutside", world.screen.Parent).Activated.fire()
		local exit = 0
		while not panel.isDestroyed() and group.GroupTransparency < 0.95 and exit < 60 do
			world.engine.heartbeat.fire(FRAME)
			exit += 1
		end
		t.expect(exit > 0 and exit < enter).toBe(true)
		for _ = 1, 30 do
			world.engine.heartbeat.fire(FRAME)
		end
		t.expect(panel.isDestroyed()).toBe(true)
		world.stop()
	end)

	t.it("pivots a default panel at its top leading corner and a trailing panel at its leading side", function()
		for _, case in
			{
				{ edge = nil, align = nil, pivot = Vector2.new(0, 0), at = Vector2.new(100, 144) },
				{ edge = "trailing", align = "start", pivot = Vector2.new(0, 0), at = Vector2.new(304, 100) },
				{ edge = "bottom", align = "center", pivot = Vector2.new(110, 0), at = Vector2.new(90, 144) },
			}
		do
			local world = labelled({ edge = case.edge, align = case.align, items = items(3) }, {})
			local panel = open(world)
			lay(world, panel, Vector2.new(100, 100), Vector2.new(200, 40), Vector2.new(220, 200))
			local shrink = 1 - world.find("PresentationScale", panel).Scale
			t.expect(shrink > 0).toBe(true)
			t.expect(panel.Position.X.Offset).toBeCloseTo(case.at.X + case.pivot.X * shrink, 1)
			t.expect(panel.Position.Y.Offset).toBeCloseTo(case.at.Y + case.pivot.Y * shrink, 1)
			world.stop()
		end
	end)

	t.it("removes the travel under reduced motion for the panel and each submenu level", function()
		local world = labelled({ items = NESTED, presentation = "menu" })
		local panel = open(world)
		t.expect(world.find("PresentationScale", panel).Scale).toBe(1)
		t.expect(world.find("MenuGroup", panel).GroupTransparency).toBe(0)
		world.find("adjust", panel).Activated.fire()
		t.expect(world.find("PresentationScale", panel).Scale).toBe(1)
		t.expect(world.find("MenuGroup", panel).GroupTransparency).toBe(0)
		world.stop()
	end)

	t.it("follows a trigger that moves while the menu is open", function()
		local world = labelled({ items = items(3) })
		local panel = open(world)
		lay(world, panel, Vector2.new(100, 100), Vector2.new(200, 40), Vector2.new(220, 200))
		t.expect(panel.Position).toBe(UDim2.fromOffset(100, 144))
		world.find("Trigger").AbsolutePosition = Vector2.new(260, 180)
		t.expect(panel.Position).toBe(UDim2.fromOffset(260, 224))
		world.find("Trigger").AbsolutePosition = Vector2.new(260, 500)
		t.expect(panel.Position).toBe(UDim2.fromOffset(260, 296))
		world.stop()
	end)

	t.it("clamps the panel inside the GuiService inset when its screen ignores the inset", function()
		local world = labelled({ edge = "top", items = items(3) })
		world.screen.IgnoreGuiInset = true
		world.gui.GetGuiInset = function()
			return Vector2.new(40, 58), Vector2.new(24, 34)
		end
		local panel = open(world)
		lay(world, panel, Vector2.new(10, 20), Vector2.new(60, 40), Vector2.new(220, 200))
		t.expect(panel.Position).toBe(UDim2.fromOffset(48, 66))
		lay(world, panel, Vector2.new(700, 400), Vector2.new(60, 40), Vector2.new(220, 200))
		t.expect(panel.Position).toBe(UDim2.fromOffset(800 - 24 - 8 - 220, 196))
		world.find("Trigger").AbsolutePosition = Vector2.new(300, 560)
		t.expect(panel.Position.Y.Offset + 200 <= 600 - 34 - 8).toBe(true)
		world.stop()
		local plain = labelled({ edge = "top", items = items(3) })
		plain.gui.GetGuiInset = function()
			return Vector2.new(40, 58), Vector2.new(24, 34)
		end
		local inside = open(plain)
		lay(plain, inside, Vector2.new(10, 20), Vector2.new(60, 40), Vector2.new(220, 200))
		t.expect(inside.Position).toBe(UDim2.fromOffset(10, 64))
		plain.stop()
	end)

	t.it("bounds a sheet by the inset at the bottom and the sides", function()
		local world = labelled({ presentation = "sheet", items = items(3) })
		world.screen.IgnoreGuiInset = true
		world.gui.GetGuiInset = function()
			return Vector2.new(40, 58), Vector2.new(24, 34)
		end
		local panel = open(world)
		lay(world, panel, Vector2.new(100, 100), Vector2.new(200, 40), Vector2.new(736, 200))
		t.expect(panel.Size.X.Offset).toBe(-24 - 40 - 24)
		t.expect(panel.Position).toBe(UDim2.fromOffset(52, 600 - 34 - 200 - 12))
		world.stop()
	end)

	for _, reduced in { false, true } do
		t.it(`slides sheet submenus forward on entry and backward on Back; reduced={reduced}`, function()
			local world = labelled({ presentation = "sheet", items = NESTED }, { reducedMotion = reduced })
			local panel = open(world)
			for _ = 1, 30 do
				world.engine.heartbeat.fire(FRAME)
			end
			local rows = panel:FindFirstChild("MenuRows", true)
			t.expect(rows.Position.X.Offset).toBe(0)
			world.find("adjust", panel).Activated.fire()
			local forward = rows.Position.X.Offset
			t.expect(if reduced then forward == 0 else forward > 0).toBe(true)
			world.engine.heartbeat.fire(FRAME)
			t.expect(if reduced then true else rows.Position.X.Offset < forward).toBe(true)
			for _ = 1, 30 do
				world.engine.heartbeat.fire(FRAME)
			end
			t.expect(rows.Position.X.Offset).toBe(0)
			world.find("Back", panel).Activated.fire()
			local backward = rows.Position.X.Offset
			t.expect(if reduced then backward == 0 else backward < 0).toBe(true)
			for _ = 1, 30 do
				world.engine.heartbeat.fire(FRAME)
			end
			t.expect(rows.Position.X.Offset).toBe(0)
			t.expect(world.find("adjust", panel) ~= nil).toBe(true)
			world.stop()
		end)
	end
end)
