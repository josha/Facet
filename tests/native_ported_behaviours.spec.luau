--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engines = require("./lib/native_engine")
local Roblox = require("@lune/roblox")
local Vector2, UDim2 = Roblox.Vector2, Roblox.UDim2
local Compose = Facet.Compose
local themes = Facet.themes
local expect = t.expect

local function find(root: any, name: string): any
	if root == nil then
		return nil
	end
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

local function world(build: (any, any, any) -> any, options: { [string]: any }?): any
	local o: { [string]: any } = options or {}
	local engine: any = engines.new({
		measureText = function(node: any): any
			local text = node.Text or ""
			return Vector2.new(#text * 11, if #text > 0 then 20 else 0)
		end,
	})
	local gui = engine.new("GuiService")
	local input = engine.new("UserInputService")
	input.GetFocusedTextBox = function()
		return nil
	end
	local runtime = Facet.Roblox.createRuntime(engine)
	local UI: any = Facet.controls(
		runtime,
		{
			types = engine.types,
			services = { GuiService = gui, UserInputService = input },
			theme = o.theme,
			environment = o.environment,
		} :: any
	)
	local stop, screen = runtime.mount(function()
		return runtime.constructors.ScreenGui({ build(UI, runtime.constructors, engine) })
	end, engine.new("Folder"))
	return {
		engine = engine,
		runtime = runtime,
		screen = screen,
		UI = UI,
		step = function(count: number?)
			for _ = 1, count or 1 do
				engine.heartbeat.fire(1 / 60)
			end
		end,
		stop = function()
			stop()
			runtime:dispose()
		end,
	}
end

local function sheetFor(w: any, package: any): any
	local _, sheet = w.runtime.mount(function()
		return themes.createStyleSheet(
			w.runtime,
			package,
			{
				types = w.engine.types,
				preferredTransparency = 1,
				reducedMotion = false,
			} :: any
		)
	end, w.engine.new("Folder"))
	return sheet
end

local function rule(sheet: any, selector: string): any
	for _, node in sheet:GetChildren() do
		if node.Selector == selector then
			return node
		end
	end
	return nil
end

t.describe("Toggle switch follows controlSize", function()
	t.it("each rung draws its own track and knob; no rung keeps the 38 by 24 switch", function()
		local rung = Compose.cell("compact")
		local w = world(function(UI)
			return UI.VStack {
				UI.Toggle "Plain" { value = Compose.cell(true), label = "Sound" },
				UI.Toggle "Sized" { value = Compose.cell(true), label = "Music", controlSize = rung },
			}
		end)
		local plain = find(find(w.screen, "Plain"), "Indicator")
		expect(plain.Size.X.Offset .. "x" .. plain.Size.Y.Offset).toBe("38x24")
		local indicator = find(find(w.screen, "Sized"), "Indicator")
		local mark = find(indicator, "Mark")
		expect(indicator.Size.X.Offset .. "x" .. indicator.Size.Y.Offset).toBe("32x20")
		expect(mark.Size.X.Offset).toBe(14)
		expect(indicator.Position.X.Offset).toBe(-40)
		rung:set("large")
		w.step()
		expect(indicator.Size.X.Offset .. "x" .. indicator.Size.Y.Offset).toBe("44x28")
		expect(mark.Size.X.Offset).toBe(22)
		expect(find(indicator, "UICorner").CornerRadius.Offset).toBe(14)
		rung:set("regular")
		w.step()
		expect(indicator.Size.X.Offset .. "x" .. indicator.Size.Y.Offset).toBe("38x24")
		w.stop()
	end)
end)

t.describe("voice and contrast statuses", function()
	t.it("StatusIndicator and Badge take voice and contrast; voice defaults between warning and danger", function()
		local status = Compose.cell("voice")
		local w = world(function(UI)
			return UI.VStack {
				UI.StatusIndicator "Dot" { status = status },
				UI.Badge "Tag" { label = "Live", status = "contrast" },
			}
		end)
		local dot = find(w.screen, "Dot")
		expect(dot:HasTag("facet-status-voice")).toBe(true)
		status:set("contrast")
		expect(dot:HasTag("facet-status-contrast")).toBe(true)
		expect(dot:HasTag("facet-status-voice")).toBe(false)
		expect(find(w.screen, "Tag"):HasTag("facet-status-contrast")).toBe(true)
		local package = themes.neutralPackage()
		local sheet = sheetFor(w, package)
		local colors = package.style.themes[1].colors
		local warning, danger = colors.warning :: any, colors.danger :: any
		local voice = rule(sheet, ".facet-status-voice"):GetProperties().BackgroundColor3
		expect(math.abs(voice.R - (warning.r + danger.r) / 2) < 1e-6).toBe(true)
		expect(math.abs(voice.G - (warning.g + danger.g) / 2) < 1e-6).toBe(true)
		local strong = colors.contentStrong :: any
		local contrast = rule(sheet, ".facet-status-contrast"):GetProperties().BackgroundColor3
		expect(math.abs(contrast.R - strong.r) < 1e-6).toBe(true)
		package.style.themes[1].extra.voice = { r = 0.1, g = 0.2, b = 0.3 }
		local authored = rule(sheetFor(w, package), ".facet-status-voice"):GetProperties().BackgroundColor3
		expect(math.abs(authored.B - 0.3) < 1e-6).toBe(true)
		w.stop()
	end)
end)

t.describe("Avatar faces, in-experience ring and background", function()
	t.it("an icon face replaces the initials, also for a group member", function()
		local w = world(function(UI)
			return UI.VStack {
				UI.Avatar "Guest" { name = "Guest Player", icon = "person" },
				UI.AvatarGroup "Group" { items = { { id = "g", name = "Guest", icon = "person" } } },
			}
		end)
		local guest = find(w.screen, "Guest")
		expect(find(guest, "Face") ~= nil).toBe(true)
		expect(find(guest, "Initials").Visible).toBe(false)
		local member = find(find(w.screen, "Group"), "g")
		expect(find(member, "Face") ~= nil).toBe(true)
		expect(find(member, "Initials").Visible).toBe(false)
		expect(function()
			w.UI.Avatar { name = "A", icon = "person", image = "rbxassetid://1" }
		end).toThrow()
		w.stop()
	end)

	t.it("inExperience rings the face in accent with a surface gap and no corner mark", function()
		local presence = Compose.cell("inExperience")
		local w = world(function(UI)
			return UI.Avatar "A" { name = "Ada", presence = presence, background = "success" }
		end)
		local avatar = find(w.screen, "A")
		local ring = find(avatar, "PresenceRing")
		expect(ring.Visible).toBe(true)
		expect(ring:FindFirstChildWhichIsA("UIStroke"):HasTag("facet-avatar-ring")).toBe(true)
		expect(find(ring, "Gap"):FindFirstChildWhichIsA("UIStroke"):HasTag("facet-avatar-ring-gap")).toBe(true)
		expect(find(avatar, "Presence").Visible).toBe(false)
		expect(avatar:HasTag("facet-avatar-background-success")).toBe(true)
		presence:set("online")
		expect(ring.Visible).toBe(false)
		expect(find(avatar, "Presence").Visible).toBe(true)
		local sheet = sheetFor(w, themes.neutralPackage())
		expect(rule(sheet, ".facet-avatar-ring"):GetProperties().Transparency).toBe(0)
		expect(rule(sheet, ".facet-avatar-background-success") ~= nil).toBe(true)
		expect(function()
			w.UI.Avatar { name = "A", background = "rainbow" }
		end).toThrow()
		w.stop()
	end)
end)

t.describe("Alert suppression", function()
	t.it("the do-not-ask-again checkbox sits below the actions", function()
		local w = world(function(UI)
			return UI.Alert {
				isPresented = Compose.cell(true),
				title = "Delete save?",
				suppression = { isSuppressed = Compose.cell(false) },
				actions = {
					{ id = "Delete", label = "Delete", role = "destructive" },
					{ id = "Keep", label = "Keep", role = "cancel" },
				},
			}
		end)
		w.step(30)
		local toggle = find(w.screen, "Suppression")
		local actions = find(w.screen, "Actions")
		expect(find(find(w.screen, "AlertContent"), "Suppression")).toBe(nil)
		expect(toggle.Parent).toBe(actions.Parent)
		expect(toggle.LayoutOrder > actions.LayoutOrder).toBe(true)
		w.stop()
	end)
end)

t.describe("Card ring", function()
	t.it(
		"a selected card keeps the live shared focus look and asks it to reach the whole card, or the artwork",
		function()
			for _, target in { "card", "media" } do
				local w = world(function(UI)
					return UI.Card "C" {
						image = "rbxassetid://1",
						title = "Track",
						onActivate = function() end,
						primaryAction = { label = "Play", onActivate = function() end },
						ringTarget = if target == "media" then "media" else nil,
						Size = UDim2.fromOffset(160, 0),
					}
				end)
				w.step(5)
				local body = find(w.screen, "Body")
				expect(find(w.screen, "CardRingPaint")).toBe(nil)
				find(w.screen, "C").AbsoluteSize = Vector2.new(160, 200)
				body.AbsoluteSize = Vector2.new(160, 150)
				find(w.screen, "Artwork").AbsoluteSize = Vector2.new(160, 90)
				w.step()
				body.SelectionGained.fire()
				expect(body.SelectionImageObject).toBe(nil)
				local height = body:GetAttribute("FacetFocusHeight")
				expect(math.abs(height - (if target == "card" then 200 else 90) / 150) < 1e-5).toBe(true)
				w.stop()
			end
			expect(function()
				local w = world(function(UI)
					return UI.Card { image = "rbxassetid://1", title = "T", ringTarget = "shadow" }
				end)
				w.stop()
			end).toThrow()
		end
	)
end)

t.describe("Slider contained", function()
	t.it("contained paints a knob-thick pill rail and fill", function()
		local w = world(function(UI)
			return UI.VStack {
				UI.Slider "Plain" { value = Compose.cell(0.5) },
				UI.Slider "Contained" { value = Compose.cell(0.5), contained = true },
			}
		end)
		local plain = find(find(w.screen, "Plain"), "Rail")
		local rail = find(find(w.screen, "Contained"), "Rail")
		local fill = find(find(w.screen, "Contained"), "Fill")
		expect(plain.Size.Y.Offset).toBe(6)
		expect(rail.Size.Y.Offset).toBe(24)
		expect(fill.Size.Y.Offset).toBe(24)
		expect(find(rail, "UICorner").CornerRadius.Scale).toBe(1)
		expect(function()
			w.UI.Slider { value = Compose.cell(0.5), contained = "yes" }
		end).toThrow()
		w.stop()
	end)
end)

t.describe("Skeleton corners", function()
	t.it("control and panel read the theme radii", function()
		local package = themes.neutralPackage()
		local w = world(function(UI)
			return UI.VStack {
				UI.Skeleton "Control" { corners = "control" },
				UI.Skeleton "Panel" { corners = "panel" },
			}
		end, { theme = package })
		expect(find(find(w.screen, "Control"), "UICorner").CornerRadius.Offset).toBe(package.metrics.radii.control)
		expect(find(find(w.screen, "Panel"), "UICorner").CornerRadius.Offset).toBe(package.metrics.radii.panel)
		w.stop()
	end)
end)

t.describe("ShortcutHint label", function()
	t.it("the label sits after the keys by default and before them with labelPosition start", function()
		local w = world(function(UI)
			return UI.VStack {
				UI.ShortcutHint "End" { keys = { { "E" } }, label = "Interact" },
				UI.ShortcutHint "Start" { keys = { { "Q" } }, label = "Back", labelPosition = "start" },
			}
		end)
		local function order(root: any): string
			local names = {}
			for _, child in root:GetChildren() do
				if child:IsA("GuiObject") then
					table.insert(names, { child.LayoutOrder, child.Name })
				end
			end
			table.sort(names, function(a, b)
				return a[1] < b[1]
			end)
			local out = {}
			for _, entry in names do
				table.insert(out, entry[2])
			end
			return table.concat(out, ",")
		end
		local ending, starting = find(w.screen, "End"), find(w.screen, "Start")
		expect(order(ending)).toBe("Keys,Label")
		expect(order(starting)).toBe("Label,Keys")
		expect(find(ending, "Label").Text).toBe("Interact")
		expect(find(ending, "Keys").Text).toBe("E")
		w.stop()
	end)
end)

t.describe("filled icon names", function()
	t.it("<name>.fill uses package art, else the regular icon", function()
		local package = themes.neutralPackage()
		local regular = themes.resolveIcon(package, "checkmark")
		expect(regular ~= nil).toBe(true)
		expect(themes.resolveIcon(package, "checkmark.fill")).toBe(regular)
		package.icons = { ["checkmark.fill"] = "rbxassetid://42" }
		expect(themes.resolveIcon(package, "checkmark.fill")).toBe("rbxassetid://42")
		expect(themes.resolveIcon(package, "nothing.fill")).toBe(nil)
	end)
end)

t.describe("NavBar surface", function()
	t.it("surface paints a plate through the theme role tag", function()
		local w = world(function(UI)
			return UI.VStack {
				UI.NavBar "Bar" { title = "Garage", surface = "panel" },
				UI.NavBar "Bare" { title = "Garage" },
			}
		end)
		expect(find(w.screen, "Bar"):HasTag("facet-panel")).toBe(true)
		expect(find(w.screen, "Bare"):HasTag("facet-panel")).toBe(false)
		expect(function()
			w.UI.NavBar { title = "X", surface = "glass" }
		end).toThrow()
		w.stop()
	end)
end)

t.describe("app.refusal", function()
	t.it("answers the refusal words without mounting, and nil for an accepted spec", function()
		local engine: any = engines.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local app = Facet.app({ runtime = runtime, types = engine.types, parent = engine.new("Folder") })
		expect(app.refusal("Button", { label = "Go", onActivate = function() end })).toBe(nil)
		local words = app.refusal("Slider", { value = Compose.cell(0.5), contained = "yes" })
		expect(words).toBe("Facet UI.Slider: contained must be a boolean")
		expect(string.find(app.refusal("Button", { lable = "Go" }) or "", "Did you mean 'label'", 1, true) ~= nil).toBe(
			true
		)
		expect(function()
			app.refusal("Nothing", {})
		end).toThrow()
		app.dispose()
		runtime:dispose()
	end)
end)

t.describe("Table editable cells", function()
	t.it("each editor proposes through onCellChange, a no-op commit proposes nothing, rows re-seed", function()
		local rows = Compose.cell({
			{ id = "a", name = "Ada", laps = 3, ready = false, tier = "gold" },
			{ id = "b", name = "Bo", laps = 5, ready = true, tier = "silver" },
		})
		local proposals = {}
		local w = world(function(UI)
			return UI.Table "T" {
				from = rows,
				key = "id",
				scrolls = false,
				columns = {
					{ id = "name", label = "Name", editor = "text" },
					{ id = "laps", label = "Laps", editor = "number", min = 0, max = 99 },
					{ id = "ready", label = "Ready", editor = "toggle" },
					{
						id = "tier",
						label = "Tier",
						editor = "menu",
						options = { { value = "gold", label = "Gold" }, { value = "silver", label = "Silver" } },
					},
				},
				onCellChange = function(key, column, value)
					table.insert(proposals, `{key}.{column}={tostring(value)}`)
					local nextRows = table.clone(rows:peek())
					for index, row in nextRows do
						if row.id == key then
							local copy = table.clone(row)
							copy[column] = value
							nextRows[index] = copy
						end
					end
					rows:set(nextRows)
				end,
			}
		end)
		w.step(3)
		local function editor(column: string): any
			local found
			local function walk(node: any)
				if found == nil and node.Name == "Editor" and node.Parent and node.Parent.Name == column then
					found = node
				end
				for _, child in node:GetChildren() do
					walk(child)
				end
			end
			walk(w.screen)
			return found
		end
		local name = editor("name")
		local box = if name:IsA("TextBox") then name else name:FindFirstChildWhichIsA("TextBox", true)
		expect(box.Text).toBe("Ada")
		box:CaptureFocus()
		box:ReleaseFocus(true)
		expect(#proposals).toBe(0)
		box:CaptureFocus()
		box.Text = "Ava"
		box:ReleaseFocus(true)
		expect(proposals[1]).toBe("a.name=Ava")
		expect(box.Text).toBe("Ava")
		local laps = editor("laps")
		local lapsBox = if laps:IsA("TextBox") then laps else laps:FindFirstChildWhichIsA("TextBox", true)
		lapsBox:CaptureFocus()
		lapsBox.Text = "120"
		lapsBox:ReleaseFocus(true)
		expect(proposals[#proposals]).toBe("a.laps=99")
		local ready = editor("ready")
		ready.Activated.fire()
		expect(proposals[#proposals]).toBe("a.ready=true")
		local tier = editor("tier")
		local trigger = find(tier, "Trigger") or tier
		expect(trigger:HasTag("facet-appearance-utility")).toBe(true)
		expect(tier.Parent.ClipsDescendants).toBe(true)
		trigger.Activated.fire()
		w.step(10)
		local option = find(w.screen, "silver")
		expect(option ~= nil).toBe(true)
		option.Activated.fire()
		w.step(10)
		expect(proposals[#proposals]).toBe("a.tier=silver")
		rows:set({ { id = "a", name = "Zed", laps = 1, ready = false, tier = "silver" } })
		w.step()
		expect(box.Text).toBe("Zed")
		expect(function()
			w.UI.Table { from = rows, key = "id", columns = { { id = "x", editor = "text" } } }
		end).toThrow()
		expect(function()
			w.UI.Table {
				from = rows,
				key = "id",
				onCellChange = print,
				columns = { { id = "x", editor = "menu" } },
			}
		end).toThrow()
		w.stop()
	end)
end)

t.describe("Table row paint", function()
	t.it("the header band and every row carry theme tags, and alternatingRows tags the even rows", function()
		local rows = Compose.cell({ { id = "a", n = 3 }, { id = "b", n = 1 }, { id = "c", n = 2 } })
		local sort = Compose.cell(nil)
		local w = world(function(UI)
			return UI.VStack {
				UI.Table "Striped" {
					from = rows,
					key = "id",
					scrolls = false,
					sort = sort,
					alternatingRows = true,
					columns = { { id = "id" }, { id = "n" } },
				},
				UI.Table "Plain" { from = rows, key = "id", scrolls = false, columns = { { id = "id" } } },
			}
		end)
		w.step(3)
		local function rowsOf(name: string): { [string]: any }
			local found = {}
			for _, node in find(w.screen, name):GetDescendants() do
				if node.Name == "DisclosingRow" then
					found[node.Parent.Parent.Name] = node
				end
			end
			return found
		end
		local header = find(find(w.screen, "Striped"), "HeaderBand")
		expect(header:HasTag("facet-tablehead")).toBe(true)
		expect(header.BackgroundTransparency).toBe(0)
		local striped = rowsOf("Striped")
		expect(striped.a:HasTag("facet-tablerow")).toBe(true)
		expect(striped.a.BackgroundTransparency).toBe(0)
		expect(striped.a:HasTag("facet-tablerow-alternate")).toBe(false)
		expect(striped.b:HasTag("facet-tablerow-alternate")).toBe(true)
		expect(striped.c:HasTag("facet-tablerow-alternate")).toBe(false)
		sort:set({ column = "n", direction = "ascending" })
		w.step(3)
		expect(striped.c:HasTag("facet-tablerow-alternate")).toBe(true)
		expect(striped.b:HasTag("facet-tablerow-alternate")).toBe(false)
		for _, row in rowsOf("Plain") do
			expect(row:HasTag("facet-tablerow")).toBe(true)
			expect(row:HasTag("facet-tablerow-alternate")).toBe(false)
		end
		local sheet = sheetFor(w, themes.neutralPackage())
		local function paint(selector: string): any
			return rule(sheet, selector):GetProperties().BackgroundColor3
		end
		expect(paint(".facet-tablehead")).toBe(paint(".facet-control"))
		expect(paint(".facet-tablerow")).toBe(paint(".facet-control"))
		expect(paint(".facet-tablerow-alternate") ~= paint(".facet-tablerow")).toBe(true)
		expect(paint(".facet-tablerow") ~= paint(".facet-surface")).toBe(true)
		expect(find(striped.a, "Divider")).toBe(nil)
		expect(striped.a.Size).toBe(w.engine.types.UDim2.fromScale(1, 1))
		local corner = themes.neutralPackage().metrics.radii.control
		expect(rule(sheet, ".facet-tablerow::UICorner"):GetProperties().CornerRadius.Offset).toBe(corner)
		expect(rule(sheet, ".facet-tablehead::UICorner"):GetProperties().CornerRadius.Offset).toBe(corner)
		expect(rule(sheet, ".facet-tablerow::UIStroke"):GetProperties().Color).toBe(paint(".facet-surface"))
		expect(rule(sheet, ".facet-row-action::UIStroke"):GetProperties().Color).toBe(paint(".facet-surface"))
		local sortButton = find(find(find(w.screen, "Striped"), "Header"), "Sort")
		expect(sortButton:HasTag("facet-appearance-utility")).toBe(false)
		expect(sortButton:HasTag("facet-button")).toBe(true)
		local neutral = themes.neutralPackage()
		local dark = neutral.style.themes[1]
		local extra = table.clone(dark.extra :: any)
		extra.tableHeader = { r = 0.9, g = 0.1, b = 0.1 }
		extra.tableRow = { r = 0.1, g = 0.9, b = 0.1 }
		extra.tableRowAlternate = { r = 0.1, g = 0.1, b = 0.9 }
		local package = assert(themes.define({
			base = neutral,
			identity = { id = "rows", displayName = "Rows", schemaVersion = themes.SCHEMA, version = "1.0.0" },
			style = { defaultTheme = "Ink", themes = { { name = "Ink", colors = dark.colors, extra = extra } } },
		} :: any))
		local authored = sheetFor(w, package)
		expect(rule(authored, ".facet-tablehead"):GetProperties().BackgroundColor3.R).toBeCloseTo(0.9, 3)
		expect(rule(authored, ".facet-tablerow"):GetProperties().BackgroundColor3.G).toBeCloseTo(0.9, 3)
		expect(rule(authored, ".facet-tablerow-alternate"):GetProperties().BackgroundColor3.B).toBeCloseTo(0.9, 3)
		w.stop()
	end)
end)

t.describe("Table edit mode", function()
	local function editableTable(input: string, editing: any?): (any, { string })
		local rows = Compose.cell({ { id = "a", ready = false } })
		local proposals = {}
		local w = world(function(UI)
			return UI.Table "T" {
				from = rows,
				key = "id",
				scrolls = false,
				reorderable = true,
				onReorder = function() end,
				editing = editing,
				columns = { { id = "id" }, { id = "ready", editor = "toggle" } },
				onCellChange = function(key, column, value)
					table.insert(proposals, `{key}.{column}={tostring(value)}`)
				end,
			}
		end, { environment = { preferredInput = input } })
		w.step(3)
		return w, proposals
	end
	local function editorOf(w: any): any
		for _, node in w.screen:GetDescendants() do
			if node.Name == "Editor" and node.Parent and node.Parent.Name == "ready" then
				return node
			end
		end
		return nil
	end
	t.it("touch and gamepad cells edit only after Edit; Done ends the edit mode", function()
		for _, input in { "Touch", "Gamepad" } do
			local w, proposals = editableTable(input)
			local button = find(w.screen, "Edit")
			expect(button ~= nil).toBe(true)
			expect(button.Text).toBe("Edit")
			editorOf(w).Activated.fire()
			expect(#proposals).toBe(0)
			button.Activated.fire()
			w.step()
			expect(button.Text).toBe("Done")
			editorOf(w).Activated.fire()
			expect(proposals[1]).toBe("a.ready=true")
			button.Activated.fire()
			w.step()
			expect(button.Text).toBe("Edit")
			editorOf(w).Activated.fire()
			expect(#proposals).toBe(1)
			w.stop()
		end
	end)
	t.it("a pointer edits cells in place and gets no Edit toggle; a caller's editing cell owns the mode", function()
		local w, proposals = editableTable("KeyboardAndMouse")
		editorOf(w).Activated.fire()
		expect(proposals[1]).toBe("a.ready=true")
		expect(find(w.screen, "Edit")).toBe(nil)
		w.stop()
		local owned = editableTable("Touch", Compose.cell(false))
		expect(find(owned.screen, "Edit")).toBe(nil)
		owned.stop()
	end)
	t.it("a table that neither reorders nor deletes has no Edit button and keeps its cells live", function()
		local w = world(function(UI)
			return UI.Table "T" { from = { { id = "a" } }, key = "id", scrolls = false, columns = { { id = "id" } } }
		end, { environment = { preferredInput = "Touch" } })
		w.step(3)
		expect(find(w.screen, "Edit")).toBe(nil)
		expect(function()
			w.UI.Table {
				from = { { id = "a" } },
				key = "id",
				editable = true,
				header = false,
				columns = { { id = "id" } },
			}
		end).toThrow()
		w.stop()
	end)
end)

t.describe("environment preview", function()
	t.it("the environment option overrides the observed engine facts for controls and UI.environment", function()
		local engine: any = engines.new()
		local input = engine.new("UserInputService")
		local gui = engine.new("GuiService")
		local runtime = Facet.Roblox.createRuntime(engine)
		local forced = Compose.cell("Touch")
		local size = Compose.cell(engine.types.Vector2.new(390, 844))
		local UI: any = Facet.controls(
			runtime,
			{
				types = engine.types,
				services = { GuiService = gui, UserInputService = input },
				environment = {
					preferredInput = forced,
					touchEnabled = true,
					viewportSize = size,
					preferredTextSize = "Largest",
					displaySize = "Large",
				},
			} :: any
		)
		local seen: any
		local stop = runtime.mount(function()
			seen = UI.environment()
			return runtime.constructors.Folder({})
		end, engine.new("Folder"))
		expect(seen.interactionClasses:peek().primary).toBe("touch")
		expect(seen.sizeClass:peek()).toBe("compact")
		expect(seen.preferredTextSize:peek()).toBe("Largest")
		expect(seen.displaySize:peek()).toBe("Large")
		forced:set("Gamepad")
		expect(seen.interactionClasses:peek().primary).toBe("gamepad")
		forced:set(nil)
		expect(seen.interactionClasses:peek().primary).toBe("touch")
		size:set(engine.types.Vector2.new(1920, 1080))
		expect(seen.sizeClass:peek()).toBe("wide")
		stop()
		expect(function()
			Facet.controls(runtime, { types = engine.types, environment = { inputKind = "Touch" } } :: any)
		end).toThrow()
		runtime:dispose()
	end)
end)

t.describe("lab-found defects", function()
	t.it("a Divider leaves its transparency to the facet-divider rule", function()
		local w = world(function(UI)
			return UI.VStack { UI.Divider "Line" {} }
		end)
		local line = find(w.screen, "Line")
		expect(line:HasTag("facet-divider")).toBe(true)
		expect(line.BackgroundTransparency).toBe(0)
		local sheet = sheetFor(w, themes.neutralPackage())
		expect(rule(sheet, ".facet-divider"):GetProperties().BackgroundTransparency < 1).toBe(true)
		w.stop()
	end)
end)

t.describe("collection status seed", function()
	t.it("a status cell that starts empty is filled with the empty status record", function()
		for _, kind in { "VirtualList", "Table" } do
			local status = Compose.cell(nil)
			local w = world(function(UI, Host)
				if kind == "Table" then
					return UI.Table { from = { { id = "a" } }, key = "id", columns = { { id = "id" } }, status = status }
				end
				return UI.VirtualList {
					from = { { id = "a" } },
					key = "id",
					status = status,
					render = function()
						return Host.Frame {}
					end,
				}
			end)
			w.step(2)
			expect(type(status:peek()) == "table" and type(status:peek().total) == "number").toBe(true)
			w.stop()
		end
	end)
end)

t.describe("bounded text buttons", function()
	t.it(
		"a text Button or Toggle with an authored width wraps inside it; any text button truncates at its box",
		function()
			local w = world(function(UI, Host, engine)
				local engineEnum = engine.types.Enum
				local w0Enum = engineEnum.AutomaticSize
				return Host.Frame {
					Size = UDim2.fromOffset(180, 400),
					UI.Toggle "Long" {
						value = Compose.cell(false),
						label = "Allow friends to join my race from the lobby",
						Size = UDim2.fromScale(1, 0),
					},
					UI.Button "Cell" {
						label = "A very long button label",
						Size = UDim2.fromOffset(80, 44),
						AutomaticSize = w0Enum.None,
					},
					UI.Button "Hug" { label = "Go" },
				}
			end)
			local long, cell, hug = find(w.screen, "Long"), find(w.screen, "Cell"), find(w.screen, "Hug")
			expect(long.TextWrapped).toBe(true)
			expect(long.AutomaticSize.Name).toBe("Y")
			expect(cell.TextTruncate.Name).toBe("AtEnd")
			expect(cell.AutomaticSize.Name).toBe("None")
			expect(hug.AutomaticSize.Name).toBe("XY")
			w.stop()
		end
	)

	t.it("a text button whose width follows its label never truncates it", function()
		local w = world(function(UI)
			return UI.VStack {
				UI.Button "Hug" { label = "Go" },
				UI.Toggle "Wide" { value = Compose.cell(false), label = "Label", Size = UDim2.fromScale(1, 0) },
				UI.Picker "Segments" {
					style = "segmented",
					label = "Mode",
					selected = Compose.cell("a"),
					options = { { value = "a", label = string.rep("long ", 16) }, { value = "b", label = "B" } },
				},
			}
		end)
		expect(find(w.screen, "Hug").TextTruncate.Name).toBe("None")
		expect(find(w.screen, "Wide").TextTruncate.Name).toBe("AtEnd")
		local segment = find(find(w.screen, "Segments"), "a")
		expect(segment.AutomaticSize.Name).toBe("X")
		expect(segment.TextTruncate.Name).toBe("None")
		w.stop()
	end)
end)

t.describe("outline disclosure header", function()
	t.it("an outline DisclosureGroup header leads with its chevron and label", function()
		local w = world(function(UI)
			return UI.DisclosureGroup "Tree" {
				label = "Components",
				appearance = "outline",
				expanded = Compose.cell(false),
				content = function()
					return UI.Text { text = "Body" }
				end,
			}
		end)
		local header = find(w.screen, "Header")
		local layout = find(header, "Content"):FindFirstChildWhichIsA("UIListLayout")
		expect(layout.HorizontalAlignment.Name).toBe("Left")
		w.stop()
	end)
end)

t.describe("StepIndicator room", function()
	t.it("the underline sits below the copy, and a long description counts toward the fit", function()
		local w = world(function(UI)
			return UI.StepIndicator "Steps" {
				steps = {
					{ id = "a", label = "Cart" },
					{ id = "b", label = "Ship", description = "Address and speed of delivery for the order" },
				},
				current = "a",
				sizing = "fill",
			}
		end)
		local root = find(w.screen, "Steps")
		local row = find(root, "Row")
		expect(row:FindFirstChildWhichIsA("UIPadding").PaddingBottom.Offset >= 2).toBe(true)
		root.AbsoluteSize = Vector2.new(300, 80)
		w.step()
		expect(root:GetAttribute("FacetForm")).toBe("summary")
		w.stop()
	end)
end)

t.describe("plate-less appearances in skinned themes", function()
	t.it("utility and link Buttons take no control skin; a standard Button does", function()
		local package = themes.neutralPackage()
		package.assets = package.assets or {}
		package.assets.controlArt = { content = "rbxassetid://123" }
		package.chrome.control = { kind = "nineSlice", asset = "controlArt" }
		local appearance = Compose.cell("utility")
		local w = world(function(UI)
			return UI.VStack {
				UI.Button "Plated" { label = "Go" },
				UI.Button "Utility" { label = "Row", appearance = "utility" },
				UI.Button "Link" { label = "More", appearance = "link" },
				UI.Button "Live" { label = "Live", appearance = appearance },
			}
		end, { theme = package })
		expect(find(w.screen, "Plated"):FindFirstChild("SkinBoundary") ~= nil).toBe(true)
		expect(find(w.screen, "Utility"):FindFirstChild("SkinBoundary")).toBeNil()
		expect(find(w.screen, "Link"):FindFirstChild("SkinBoundary")).toBeNil()
		expect(find(w.screen, "Live"):FindFirstChild("SkinBoundary")).toBeNil()
		appearance:set("standard")
		expect(find(w.screen, "Live"):FindFirstChild("SkinBoundary") ~= nil).toBe(true)
		appearance:set("link")
		expect(find(w.screen, "Live"):FindFirstChild("SkinBoundary")).toBeNil()
		w.stop()
	end)
end)

t.describe("the focus ring", function()
	t.it("an app gives its PlayerGui one theme ring for engine selection, shown only for keys and pads", function()
		local engine: any = engines.new()
		local E = engine.types.Enum
		local runtime = Facet.Roblox.createRuntime(engine)
		local input = engine.new("UserInputService")
		input.GetFocusedTextBox = function()
			return nil
		end
		local gui = engine.new("GuiService")
		local playerGui = engine.new("PlayerGui")
		local app = Facet.app({
			runtime = runtime,
			types = engine.types,
			parent = playerGui,
			services = { UserInputService = input, GuiService = gui },
		})
		local stop = app.mount(function()
			return app.UI.Button { label = "Go" }
		end)
		local ring = playerGui.SelectionImageObject
		expect(ring ~= nil).toBe(true)
		expect(ring.Parent).toBeNil()
		local stroke = ring:FindFirstChildWhichIsA("UIStroke")
		expect(stroke.BorderStrokePosition).toBe(E.BorderStrokePosition.Inner)
		expect(ring:FindFirstChildWhichIsA("UICorner") ~= nil).toBe(true)
		input.LastInputTypeChanged.fire(E.UserInputType.MouseButton1)
		expect(stroke.Transparency).toBe(1)
		input.LastInputTypeChanged.fire(E.UserInputType.Keyboard)
		expect(stroke.Transparency).toBe(0)
		input.LastInputTypeChanged.fire(E.UserInputType.Touch)
		expect(stroke.Transparency).toBe(1)
		input.LastInputTypeChanged.fire(E.UserInputType.Gamepad1)
		expect(stroke.Transparency).toBe(0)
		stop()
		expect(playerGui.SelectionImageObject).toBeNil()
		app.dispose()
		runtime:dispose()
	end)
end)

t.describe("skins on laid-out plates", function()
	t.it("a skinned plate that lays out its children keeps its art out of the list", function()
		local package = themes.neutralPackage()
		package.assets = package.assets or {}
		package.assets.fieldArt = { content = "rbxassetid://123" }
		package.chrome.field = { kind = "nineSlice", asset = "fieldArt" }
		local w = world(function(UI)
			return UI.TextInput "Search" { value = Compose.cell(""), placeholder = "Search", label = "Find" }
		end, { theme = package })
		local plate = find(w.screen, "Input")
		expect(plate:FindFirstChildWhichIsA("UIListLayout") ~= nil).toBe(true)
		local boundary = find(plate, "SkinBoundary")
		expect(boundary ~= nil).toBe(true)
		expect(boundary.Parent.ClassName).toBe("Folder")
		expect(boundary.Parent.Parent).toBe(plate)
		w.stop()
	end)
end)

t.describe("toggle art", function()
	t.it("the switch track and knob art paint a switch, never a checkbox box", function()
		local package = themes.neutralPackage()
		package.assets = package.assets or {}
		package.assets.trackArt = { content = "rbxassetid://123" }
		package.assets.knobArt = { content = "rbxassetid://124" }
		package.chrome.toggleTrack = { kind = "nineSlice", asset = "trackArt" }
		package.chrome.toggleKnob = { kind = "nineSlice", asset = "knobArt" }
		local w = world(function(UI)
			return UI.VStack {
				UI.Toggle "Switch" { value = Compose.cell(true), label = "On" },
				UI.Toggle "Box" {
					value = Compose.cell(true),
					label = "Box",
					presentation = "checkbox",
					controlSize = "compact",
				},
			}
		end, { theme = package })
		expect(find(find(w.screen, "Switch"), "Indicator"):HasTag("facet-skinned")).toBe(true)
		local box = find(find(w.screen, "Box"), "Indicator")
		expect(box:HasTag("facet-skinned")).toBe(false)
		expect(find(box, "SkinBoundary")).toBeNil()
		w.stop()
	end)
end)
