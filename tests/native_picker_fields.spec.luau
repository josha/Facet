--!strict
local t = require("./lib/testkit")
local Compose = require("../src/vendor/compose/core")
local Roblox = require("../src/vendor/compose/roblox")
local controls = require("../src/ui")
local engines = require("./lib/native_engine")
local expect = t.expect

local THREE = {
	{ value = "easy", label = "Easy" },
	{ value = "normal", label = "Normal" },
	{ value = "hard", label = "Hard" },
}

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
	local out = {}
	for _, node in root:GetDescendants() do
		if node.Name == name then
			table.insert(out, node)
		end
	end
	return out
end

local function world(spec: any, preferred: string?): any
	local engine: any = engines.new()
	local gui = engine.new("GuiService")
	local input = engine.new("UserInputService")
	input.GetFocusedTextBox = function()
		return nil
	end
	input.PreferredInput = engine.types.Enum.PreferredInput[preferred or "KeyboardAndMouse"]
	local runtime = Roblox.createRuntime(engine)
	local UI: any = controls(Compose, runtime, {
		types = engine.types,
		services = { GuiService = gui, UserInputService = input },
	})
	local built = table.clone(spec)
	built.selected = built.selected or Compose.cell("normal")
	built.options = built.options or THREE
	local target = engine.new("Folder")
	local stop, screen = runtime.mount(function()
		return runtime.constructors.ScreenGui({ UI.Picker("P")(built) })
	end, target)
	return {
		engine = engine,
		gui = gui,
		input = input,
		runtime = runtime,
		screen = screen,
		selected = built.selected,
		E = engine.types.Enum,
		stop = function()
			stop()
			runtime:dispose()
		end,
	}
end

local function open(w: any)
	find(w.screen, "Trigger").Activated.fire()
end

t.describe("native Picker menu field", function()
	t.it("the required mark rides the label and the error replaces the hint beside a danger trigger", function()
		local failure = Compose.cell("")
		local w = world({
			style = "menu",
			label = "Difficulty",
			requiredMark = "required",
			hint = "Change it any time",
			errorText = failure,
		})
		expect(find(w.screen, "Label").Text).toBe("Difficulty *")
		local line, mark = find(w.screen, "Validation"), find(w.screen, "MessageMark")
		expect(line.Text).toBe("Change it any time")
		expect(mark.Visible).toBe(false)
		local trigger = find(w.screen, "Trigger")
		expect(trigger:HasTag("facet-invalid")).toBe(false)
		local before = trigger.Size
		failure:set("Pick a difficulty to continue.")
		expect(line.Text).toBe("Pick a difficulty to continue.")
		expect(line:HasTag("facet-validation")).toBe(true)
		expect(mark.Visible).toBe(true)
		expect(trigger:HasTag("facet-invalid")).toBe(true)
		expect(trigger.Size == before).toBe(true)
		failure:set("")
		expect(trigger:HasTag("facet-invalid")).toBe(false)
		w.stop()
	end)

	t.it("a labelled menu picker stands its title above a trigger at the leading edge", function()
		local w = world({ style = "menu", label = "Driver" })
		local label = find(w.screen, "Label")
		local menu = find(w.screen, "Value")
		expect(label.Parent == menu.Parent).toBe(true)
		expect(label.LayoutOrder < menu.LayoutOrder).toBe(true)
		expect(label.Parent:FindFirstChildWhichIsA("UIListLayout").FillDirection).toBe(w.E.FillDirection.Vertical)
		expect(menu.AnchorPoint.X).toBe(0)
		expect(find(w.screen, "Trigger").Text).toBe("Normal")
		w.stop()
	end)

	t.it("appearance maps onto the trigger's paint live, and a word outside the family is refused", function()
		local word = Compose.cell("standard")
		local w = world({ style = "menu", appearance = word })
		local trigger = find(w.screen, "Trigger")
		expect(trigger:HasTag("facet-accent")).toBe(false)
		word:set("contrast")
		expect(trigger:HasTag("facet-accent")).toBe(true)
		word:set("utility")
		expect(trigger:HasTag("facet-appearance-utility")).toBe(true)
		expect(find(w.screen, "Trigger") == trigger).toBe(true)
		pcall(function()
			word:set("filled")
		end)
		expect(trigger:HasTag("facet-appearance-utility")).toBe(true)
		w.stop()
		for _, bad in { { style = "menu", appearance = "stroke" }, { style = "inline", appearance = "utility" } } do
			expect(pcall(world, bad)).toBe(false)
		end
	end)

	t.it("a named rung shrinks the trigger, corners reach it, and it still opens", function()
		local w = world({ style = "menu", controlSize = "compact", corners = "pill" })
		local trigger = find(w.screen, "Trigger")
		expect(trigger.Size.Y.Offset).toBe(36)
		expect(trigger:FindFirstChildWhichIsA("UICorner").CornerRadius.Scale).toBe(1)
		open(w)
		expect(find(w.screen, "normal") ~= nil).toBe(true)
		w.stop()
	end)

	t.it("the hint line belongs to the picker: disposal releases it for every style", function()
		for _, style in { "menu", "segmented", "cards", "inline" } do
			local engine: any = engines.new()
			local runtime = Roblox.createRuntime(engine)
			local UI: any = controls(Compose, runtime, { types = engine.types })
			local before = engine.census()
			local stop = runtime.mount(function()
				return UI.Picker("P")({
					style = style,
					selected = Compose.cell("normal"),
					options = THREE,
					hint = "Change it any time",
				})
			end, engine.new("ScreenGui"))
			stop()
			expect(`{style} {engine.census().connections - before.connections}`).toBe(`{style} 0`)
			runtime:dispose()
		end
	end)
end)

t.describe("native Picker menu panel", function()
	local LONG = {}
	for i = 1, 30 do
		table.insert(LONG, { value = `v{i}`, label = `Option {i}` })
	end

	t.it("maxHeight bounds the whole panel, ordinary and searchable, and a bad cap is refused", function()
		local w = world({ style = "menu", options = LONG, maxHeight = 96, selected = Compose.cell("v1") })
		open(w)
		local panel = find(w.screen, "MenuPanel")
		find(panel, "MenuRows").AbsoluteSize = w.engine.types.Vector2.new(280, 30 * 44)
		expect(panel.Size.Y.Offset <= 96).toBe(true)
		w.stop()
		local searchable = world({
			style = "navigationLink",
			options = LONG,
			query = Compose.cell(""),
			maxHeight = 96,
			selected = Compose.cell("v1"),
		})
		find(searchable.screen, "P").Activated.fire()
		local results = find(searchable.screen, "Results")
		expect(results ~= nil).toBe(true)
		find(results, "Choices").AbsoluteSize = searchable.engine.types.Vector2.new(400, 1320)
		expect(results.Size.Y.Offset).toBe(96)
		searchable.stop()
		local tiny = world({ style = "menu", options = LONG, maxHeight = 10 })
		open(tiny)
		local tinyPanel = find(tiny.screen, "MenuPanel")
		find(tinyPanel, "MenuRows").AbsoluteSize = tiny.engine.types.Vector2.new(280, 30 * 44)
		expect(tinyPanel.Size.Y.Offset >= 44).toBe(true)
		tiny.stop()
		for _, bad in { 0, math.huge, 0 / 0, "96" } :: { any } do
			expect(pcall(world, { style = "menu", maxHeight = bad })).toBe(false)
		end
		expect(pcall(world, { style = "segmented", maxHeight = 96 })).toBe(false)
	end)

	t.it("opening lands on the selected row with gamepad or keyboard selection", function()
		for _, preferred in { "Gamepad", "KeyboardAndMouse" } do
			local w =
				world({ style = "menu", options = LONG, maxHeight = 200, selected = Compose.cell("v25") }, preferred)
			w.gui.SelectedObject = find(w.screen, "Trigger")
			open(w)
			local target = w.gui.SelectedObject
			expect(`{preferred} {target and target.Name}`).toBe(`{preferred} v25`)
			w.stop()
		end
	end)
end)

t.describe("native Picker menu rows", function()
	t.it("an option avatar's keys are closed: a misspelt one is refused by name", function()
		local ok, err = pcall(function()
			local w = world({
				style = "menu",
				options = { { value = "a", label = "Ada", avatar = { name = "Ada", userID = 1 } } },
			})
			open(w)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "userID", 1, true) ~= nil).toBe(true)
	end)

	t.it("an avatar leads its row without a second stop or press, and a disabled row is unreachable", function()
		local selected = Compose.cell("a")
		local w = world({
			style = "menu",
			selected = selected,
			options = {
				{ value = "a", label = "Ada", avatar = { name = "Ada" } },
				{ value = "b", label = "Bo", avatar = { name = "Bo" }, badge = 2 },
				{ value = "c", label = "Cy", avatar = { name = "Cy" }, enabled = false },
			},
		})
		open(w)
		local row = find(w.screen, "b")
		local avatar = find(row, "Avatar")
		expect(avatar ~= nil).toBe(true)
		expect(avatar.Selectable).toBe(false)
		expect(avatar.Active).toBe(false)
		expect(avatar.Interactable).toBe(false)
		expect(avatar.LayoutOrder < find(row, "Content"):FindFirstChildWhichIsA("TextLabel", true).LayoutOrder + 100).toBe(
			true
		)
		expect(find(find(row, "Accessories"), "Count").Text).toBe("2")
		local disabled = find(w.screen, "c")
		expect(disabled.Interactable).toBe(false)
		disabled.Activated.fire()
		expect(selected:peek()).toBe("a")
		row.Activated.fire()
		expect(selected:peek()).toBe("b")
		w.stop()
	end)

	t.it("badge, meta and sectionTitle reach the menu engine from an automatic picker", function()
		local w = world({
			options = {
				{ value = "easy", label = "Easy", sectionTitle = "Casual" },
				{ value = "normal", label = "Normal", badge = 3, meta = "Crew" },
				{ value = "hard", label = "Hard", sectionTitle = "Ranked", badge = "New" },
			},
		})
		find(w.screen, "P").AbsoluteSize = w.engine.types.Vector2.new(200, 44)
		open(w)
		expect(find(find(find(w.screen, "normal"), "Accessories"), "Count").Text).toBe("3")
		expect(find(find(w.screen, "normal"), "Meta").Text).toBe("Crew")
		local headings = {}
		for _, node in all(w.screen, "SectionTitle") do
			table.insert(headings, node.Text)
			expect(node.ClassName).toBe("TextLabel")
		end
		table.sort(headings)
		expect(table.concat(headings, " ")).toBe("Casual Ranked")
		w.stop()
	end)
end)

t.describe("native Picker segmented vocabulary and the radio mark", function()
	t.it("appearance paints the track filled, stroked or not at all, live, and refuses a menu word", function()
		local word = Compose.cell("filled")
		local w = world({ style = "segmented", appearance = word })
		local track = find(w.screen, "P")
		expect(track:HasTag("facet-segmented")).toBe(true)
		expect(track:HasTag("facet-segmented-stroke")).toBe(false)
		word:set("stroke")
		expect(track:HasTag("facet-segmented-stroke")).toBe(true)
		word:set("utility")
		expect(track:HasTag("facet-segmented-utility")).toBe(true)
		expect(track:HasTag("facet-segmented-stroke")).toBe(false)
		pcall(function()
			word:set("contrast")
		end)
		expect(track:HasTag("facet-segmented-utility")).toBe(true)
		w.stop()
		expect(pcall(world, { style = "segmented", appearance = "contrast" })).toBe(false)
	end)

	t.it("an automatic picker keeps its appearance intent across a live family switch", function()
		local w = world({ appearance = "contrast" }, "KeyboardAndMouse")
		find(w.screen, "P").AbsoluteSize = w.engine.types.Vector2.new(200, 44)
		local presentation = find(w.screen, "Presentation")
		local trigger = find(presentation, "Trigger")
		expect(trigger ~= nil and trigger:HasTag("facet-accent")).toBe(true)
		find(w.screen, "P").AbsoluteSize = w.engine.types.Vector2.new(800, 44)
		local strip = find(w.screen, "Presentation")
		expect(strip:HasTag("facet-segmented-stroke")).toBe(true)
		w.stop()
	end)

	t.it("corners reach the strip, and a rung shrinks the segments", function()
		local pill = world({ style = "segmented", corners = "pill" })
		expect(find(pill.screen, "Corners").CornerRadius.Scale).toBe(1)
		pill.stop()
		local square = world({ style = "segmented", corners = "square" })
		expect(find(square.screen, "Corners").CornerRadius.Scale).toBe(0)
		square.stop()
		local compact = world({ style = "segmented", controlSize = "compact" })
		expect(find(compact.screen, "P").Size.Y.Offset).toBe(36)
		for _, key in { "easy", "normal", "hard" } do
			expect(find(compact.screen, key).Size.Y.Scale).toBe(1)
		end
		compact.stop()
	end)

	t.it("indicatorPosition moves the radio mark to either edge, and belongs to the radio group only", function()
		for _, edge in { "leading", "trailing" } do
			local w = world({ style = "radioGroup", indicatorPosition = edge })
			local mark = find(find(w.screen, "normal"), "Indicator")
			local title = find(find(w.screen, "normal"), "Captions")
			expect(mark.Parent).toBe(title.Parent)
			expect(`{edge}: {mark.LayoutOrder > title.LayoutOrder}`).toBe(`{edge}: {edge == "trailing"}`)
			expect(find(mark, "Dot").Visible).toBe(true)
			expect(find(find(find(w.screen, "easy"), "Indicator"), "Dot").Visible).toBe(false)
			w.stop()
		end
		expect(pcall(world, { style = "segmented", indicatorPosition = "trailing" })).toBe(false)
	end)
end)

t.describe("native Picker cards", function()
	local CARDS = {
		{ value = "sprint", label = "Sprint", description = "Three short laps", meta = "3 laps", icon = "flag" },
		{ value = "endurance", label = "Endurance", description = "A long race", meta = "20 laps", icon = "flag" },
		{
			value = "locked",
			label = "Night",
			description = "Unlocks at level 10",
			meta = "Soon",
			icon = "flag",
			enabled = false,
		},
	}

	t.it("each option is a bordered card with its meta, the chosen one plated, on every input", function()
		local selected = Compose.cell("sprint")
		local w = world({ style = "cards", options = CARDS, selected = selected })
		local card = find(w.screen, "Card-endurance")
		expect(card:HasTag("facet-card-option")).toBe(true)
		expect(find(w.screen, "Card-sprint"):HasTag("facet-accent")).toBe(true)
		expect(card:HasTag("facet-accent")).toBe(false)
		expect(find(card, "Meta").Text).toBe("20 laps")
		card.Activated.fire()
		expect(selected:peek()).toBe("endurance")
		expect(card:HasTag("facet-accent")).toBe(true)
		local locked = find(w.screen, "Card-locked")
		expect(locked.Selectable).toBe(false)
		locked.Activated.fire()
		expect(selected:peek()).toBe("endurance")
		w.stop()
	end)

	t.it("choosing the chosen card again clears it only when the selection is not required", function()
		local optional = Compose.cell("sprint")
		local w = world({ style = "cards", options = CARDS, selected = optional, required = false })
		find(w.screen, "Card-sprint").Activated.fire()
		expect(optional:peek()).toBeNil()
		w.stop()
		local kept = Compose.cell("sprint")
		local w2 = world({ style = "cards", options = CARDS, selected = kept })
		find(w2.screen, "Card-sprint").Activated.fire()
		expect(kept:peek()).toBe("sprint")
		w2.stop()
	end)

	t.it("a row of cards wraps and long copy wraps inside its card; cards take no appearance", function()
		local w = world({ style = "cards", options = CARDS, axis = "x" })
		local layout = find(w.screen, "Cards"):FindFirstChildWhichIsA("UIListLayout")
		expect(layout.FillDirection).toBe(w.E.FillDirection.Horizontal)
		expect(layout.Wraps).toBe(true)
		local card = find(w.screen, "Card-sprint")
		expect(card.AutomaticSize).toBe(w.E.AutomaticSize.Y)
		w.stop()
		expect(pcall(world, { style = "cards", options = CARDS, appearance = "utility" })).toBe(false)
	end)
end)

t.describe("native Picker option indicator and search rows", function()
	t.it("follows the caller's live option record: status changes and a removed mark goes", function()
		local function options(indicator: any?)
			return {
				{ value = "easy", label = "Easy" },
				{ value = "normal", label = "Normal", indicator = indicator },
				{ value = "hard", label = "Hard" },
			}
		end
		local list = Compose.cell(options({ status = "warning" }))
		local w = world({ style = "radioGroup", options = list })
		local function status(): string
			local mark = find(find(w.screen, "normal"), "Status")
			if mark == nil then
				return "none"
			end
			for _, tag in mark:GetTags() do
				if string.sub(tag, 1, 13) == "facet-status-" and tag ~= "facet-status-hollow" then
					return tag
				end
			end
			return "untagged"
		end
		expect(status()).toBe("facet-status-warning")
		list:set(options({ status = "error" }))
		expect(status()).toBe("facet-status-error")
		list:set(options(nil))
		expect(status()).toBe("none")
		w.stop()
	end)

	t.it("a searchable list's chosen row paints no wash and wears a check instead", function()
		local w = world({ label = "Track", query = Compose.cell("") }, "Touch")
		find(w.screen, "Presentation").Activated.fire()
		local row = find(find(w.screen, "Choices"), "normal")
		expect(row:HasTag("facet-selected")).toBe(false)
		expect(row:HasTag("facet-choice-current")).toBe(false)
		expect(find(row, "TrailingIcon").Visible).toBe(true)
		expect(find(find(find(w.screen, "Choices"), "easy"), "TrailingIcon").Visible).toBe(false)
		w.stop()
	end)

	t.it("a navigation link keeps its title and value in one row", function()
		local w = world({ label = "Track", style = "navigationLink" })
		local trigger = find(w.screen, "P")
		local value = find(trigger, "Trailing")
		expect(value.Text).toBe("Normal")
		expect(value.Parent == find(trigger, "Content")).toBe(true)
		local button = if trigger:IsA("GuiButton") then trigger else trigger:FindFirstChildWhichIsA("GuiButton", true)
		expect(button.Size.Y.Offset >= 44).toBe(true)
		expect(button.Size.X.Scale).toBe(1)
		expect(find(trigger, "TrailingIcon").LayoutOrder > value.LayoutOrder).toBe(true)
		w.selected:set("hard")
		expect(value.Text).toBe("Hard")
		w.stop()
	end)
end)
