--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local catalogue = require("../examples/gallery/client/demo_picker")
local Compose = Facet.Compose

local function nativeContext()
	local engine = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local viewport = Compose.cell({ width = 1280, height = 720 })
	local target = engine.new("Folder")
	local guiService = engine.new("GuiService")
	local ctx = {
		Facet = Facet,
		Compose = Compose,
		runtime = runtime,
		Host = runtime.constructors,
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
			reducedMotion = true,
		}),
	}
	return ctx, engine, target
end

local function load(kind, name)
	return require("../examples/gallery/" .. (if kind == "example" then "examples/" else "scenarios/") .. name)
end

local function find(root, name)
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

local function mount(name, kind)
	local ctx, engine, target = nativeContext()
	local built
	local stop, node = ctx.runtime.mount(function()
		built = load(kind or "fixture", name).build(ctx)
		if built.dispose then
			Compose.cleanup(built.dispose)
		end
		return ctx.Host.ScreenGui({ Name = "DemoScreen", built.screen() })
	end, target)
	return built, node, function()
		stop()
		ctx.runtime.dispose()
	end, ctx, engine
end

t.describe("native gallery workflows", function()
	t.it("fits every word keyboard key and crossword rack slot in a narrow row", function()
		local word, node, stop, ctx = mount("05_word_game", "example")
		for row = 1, 2 do
			local keys = find(node, "kbrow" .. row)
			local layout = keys:FindFirstChildWhichIsA("UIListLayout")
			for _, width in { 240, 288, 369, 472 } do
				local total, count = 0, 0
				for _, key in keys:GetChildren() do
					if key:IsA("GuiButton") then
						t.expect(key.AutomaticSize).toBe(ctx.types.Enum.AutomaticSize.None)
						local extent = key.Size.X.Scale * width + key.Size.X.Offset
						t.expect(extent >= 20).toBe(true)
						total += extent
						count += 1
					end
				end
				t.expect(count).toBe(if row == 1 then 10 else 9)
				total += (count - 1) * layout.Padding.Offset
				t.expect(total <= width + 0.001 and total >= width - 10).toBe(true)
			end
		end
		local finalRow = find(node, "kbrow3")
		t.expect(finalRow:FindFirstChildWhichIsA("UIListLayout").HorizontalFlex)
			.toBe(ctx.types.Enum.UIFlexAlignment.Fill)
		local count = 0
		for _, key in finalRow:GetChildren() do
			if key:IsA("GuiButton") then
				local command = key.Name == "key_Enter" or key.Name == "key_Back"
				t.expect(key.AutomaticSize)
					.toBe(if command then ctx.types.Enum.AutomaticSize.X else ctx.types.Enum.AutomaticSize.None)
				t.expect(key:FindFirstChildWhichIsA("UIFlexItem").FlexMode)
					.toBe(if command then ctx.types.Enum.UIFlexMode.None else ctx.types.Enum.UIFlexMode.Fill)
				t.expect(key.TextWrapped).toBe(false)
				t.expect(key.Size.Y.Offset).toBe(44)
				count += 1
			end
		end
		t.expect(count).toBe(9)

		find(node, "key_O").Activated.fire()
		find(node, "key_P").Activated.fire()
		t.expect(word.row(1)).toBe("OP")
		find(node, "key_Back").Activated.fire()
		t.expect(word.row(1)).toBe("O")
		find(node, "key_Enter").Activated.fire()
		t.expect(word.activeRow()).toBe(1)
		t.expect(word.status():find("Not enough letters", 1, true) ~= nil).toBe(true)
		stop()
		local crossword, cross, close, crossCtx = mount("06_tile_game", "example")
		local rack = find(cross, "rack")
		local grid = rack:FindFirstChildWhichIsA("UIGridLayout")
		for _, width in { 240, 288, 360 } do
			local total = 7 * (grid.CellSize.X.Scale * width + grid.CellSize.X.Offset) + 6 * grid.CellPadding.X.Offset
			t.expect(total <= width + 0.001 and total >= width - 10).toBe(true)
		end
		for _, name in { "Stats", "Actions" } do
			local row = find(cross, name)
			t.expect(row:FindFirstChildWhichIsA("UIGridLayout")).toBe(nil)
			t.expect(row:FindFirstChildWhichIsA("UIListLayout") ~= nil).toBe(true)
			t.expect(row.AutomaticSize).toBe(crossCtx.types.Enum.AutomaticSize.Y)
		end
		local letter = crossword.rackLetter(7)
		find(rack, "rt7").Activated.fire()
		find(find(cross, "cell4_4"), "tap").Activated.fire()
		t.expect(crossword.pendingAt(4, 4)).toBe(letter)
		find(find(cross, "Actions"), "Undo").Activated.fire()
		t.expect(crossword.rackLetter(7)).toBe(letter)
		close()
	end)

	t.it("keeps Basics settings and numeric layout order across viewport changes", function()
		local built, node, stop, ctx = mount("adaptive_controls")
		local volume = find(node, "Volume")
		find(volume, "Increase").Activated.fire()
		local current = built.report().volume
		for _, width in { 390, 1280, 800, 1280 } do
			ctx.viewport:set({ width = width, height = 720 })
			t.expect(find(node, "Volume")).toBe(volume)
			t.expect(built.report().volume).toBe(current)
			t.expect(find(node, "Settings").Size.X.Scale).toBe(if width >= 900 then 0.5 else 1)
		end
		for i = 1, 12 do
			t.expect(find(node, "Stat" .. i).LayoutOrder).toBe(i)
		end
		local footer = find(node, "Actions")
		t.expect(find(footer, "Save").LayoutOrder < find(footer, "Reset").LayoutOrder).toBe(true)
		find(node, "Save").Activated.fire()
		t.expect(built.report().saved).toBe(true)
		find(node, "Reset").Activated.fire()
		t.expect(built.report().volume).toBe(6)
		stop()
	end)
	t.it("reflows one recipe action set and preserves controlled checks and keyed chips", function()
		local built, node, stop, ctx = mount("recipes_common")
		local actions = find(node, "Actions")
		local save = find(actions, "Save")
		actions.AbsoluteSize = ctx.types.Vector2.new(700, 44)
		for name, width in { Cancel = 48, Save = 200, Delete = 80 } do
			find(find(actions, name), "NaturalWidth").TextBounds = ctx.types.Vector2.new(width, 20)
		end
		for _, form in { "column", "row", "column" } do
			if form == "column" then
				built.steps.narrowActions()
			else
				built.steps.wideActions()
			end
			t.expect(built.report().actionsForm).toBe(form)
			t.expect(find(actions, "Save")).toBe(save)
			t.expect(find(actions, "UIListLayout").FillDirection)
				.toBe(
					if form == "row"
						then ctx.types.Enum.FillDirection.Horizontal
						else ctx.types.Enum.FillDirection.Vertical
				)
			save.Activated.fire()
		end
		t.expect(built.report().activations).toBe(3)
		built.steps.wideActions()
		actions.AbsoluteSize = ctx.types.Vector2.new(309, 44)
		find(save, "NaturalWidth").TextBounds = ctx.types.Vector2.new(324, 32)
		t.expect(built.report().actionsForm).toBe("column")
		t.expect(save.Size.X.Scale).toBe(1)
		t.expect(save.Size.X.Offset).toBe(0)
		t.expect(save.AutomaticSize).toBe(ctx.types.Enum.AutomaticSize.Y)
		t.expect(save.TextWrapped).toBe(true)
		t.expect(save.Text).toBe("Save changes to this profile")
		actions.AbsoluteSize = ctx.types.Vector2.new(700, 44)
		t.expect(built.report().actionsForm).toBe("row")
		find(save, "NaturalWidth").TextBounds = ctx.types.Vector2.new(700, 32)
		t.expect(built.report().actionsForm).toBe("column")
		find(save, "NaturalWidth").TextBounds = ctx.types.Vector2.new(200, 20)
		t.expect(built.report().actionsForm).toBe("row")
		t.expect(find(actions, "Save")).toBe(save)
		local fuel = find(find(node, "CheckboxGroup"), "fuel")
		fuel.Activated.fire()
		t.expect(built.report().checks.fuel).toBe(true)
		built.steps.rejectChecks()
		fuel.Activated.fire()
		t.expect(built.report().checks.fuel).toBe(true)
		t.expect(built.report().requests).toBe(2)
		built.steps.disableChecks()
		fuel.Activated.fire()
		t.expect(built.report().requests).toBe(2)
		local rain = find(find(node, "WrapChips"), "Rain")
		rain.Activated.fire()
		built.steps.reorderTags()
		t.expect(find(find(node, "WrapChips"), "Rain")).toBe(rain)
		t.expect(built.report().wrapSelected.Rain).toBe(true)
		t.expect(rain.LayoutOrder).toBe(2)
		for _, entry in
			{ { "EmptyCollection", "createCount" }, { "NoResults", "clearCount" }, { "LoadFailed", "retryCount" } }
		do
			find(find(node, entry[1]), "Action").Activated.fire()
			t.expect(built.report()[entry[2]]).toBe(1)
		end
		stop()
	end)
	t.it("opens one recipe accordion body at a time and restores its header focus", function()
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
			t.expect(headers[name].Selectable).toBe(true)
			t.expect(find(find(accordion, name), "Body")).toBe(nil)
		end
		local previousBody
		for _, name in { "Rules", "Setup", "Rewards", "Rewards" } do
			local expected = if built.report().openSection == name then nil else name
			ctx.guiService.SelectedObject = headers[name]
			headers[name].Activated.fire()
			t.expect(built.report().openSection).toBe(expected)
			t.expect(ctx.guiService.SelectedObject).toBe(headers[name])
			if previousBody then
				t.expect(previousBody.isDestroyed()).toBe(true)
			end
			for _, other in names do
				local section = find(accordion, other)
				t.expect(find(section, "Header")).toBe(headers[other])
				local body = find(section, "Body")
				t.expect(body ~= nil).toBe(other == expected)
				if body then
					t.expect(body.Text).toBe(text[other])
					t.expect(body.TextWrapped).toBe(true)
					t.expect(body.AutomaticSize).toBe(ctx.types.Enum.AutomaticSize.Y)
					previousBody = body
				end
			end
		end
		headers.Rules.Activated.fire()
		local body = find(find(accordion, "Rules"), "Body")
		ctx.guiService.SelectedObject = body
		headers.Rules.Activated.fire()
		t.expect(ctx.guiService.SelectedObject).toBe(headers.Rules)
		t.expect(body.isDestroyed()).toBe(true)
		headers.Setup.Activated.fire()
		built.reset()
		t.expect(built.report().openSection).toBe(nil)
		t.expect(find(accordion, "Body")).toBe(nil)
		stop()
		for _, header in headers do
			t.expect(header.isDestroyed()).toBe(true)
		end
		t.expect(#ctx.inputTarget:GetChildren()).toBe(0)
	end)

	t.it("applies shared and per-plate CanvasGroup opacity and owns the arrival tween", function()
		local built, node, stop, ctx, engine = mount("canvas_group")
		for _, opacity in { 1, 0.7, 0.15 } do
			built.opacity:set(opacity)
			t.expect(find(node, "OneGroup").GroupTransparency).toBe(1 - opacity)
			for i = 1, 3 do
				t.expect(find(find(node, "OneGroup"), "Plate" .. i).GroupTransparency).toBe(0)
				t.expect(find(find(node, "ManyGroups"), "Plate" .. i).GroupTransparency).toBe(1 - opacity)
			end
		end
		find(node, "Show").Activated.fire()
		for _ = 1, 30 do
			engine.heartbeat.fire(1 / 30)
		end
		t.expect(find(node, "Arrival").GroupTransparency).toBe(0)
		stop()
	end)
	t.it("expires passive toasts while retaining access to the underlying action", function()
		local built, node, stop, _, engine = mount("sponsor_toast")
		find(node, "Send").Activated.fire()
		t.expect(built.report().messages).toBe(1)
		local toast = find(node, "Toast")
		t.expect(toast.Active).toBe(false)
		t.expect(toast.Selectable).toBe(false)
		find(node, "Beneath").Activated.fire()
		t.expect(built.report().presses).toBe(1)
		engine.heartbeat.fire(4.1)
		t.expect(built.report().messages).toBe(0)
		engine.heartbeat.fire(0.3)
		t.expect(toast.isDestroyed()).toBe(true)
		find(node, "Send").Activated.fire()
		find(node, "Clear").Activated.fire()
		t.expect(built.report().messages).toBe(0)
		stop()
	end)
	t.it("moves and hides native map markers without remounting their controls", function()
		local built, node, stop, ctx = mount("world_markers")
		local map = find(node, "Map")
		map.AbsoluteSize = ctx.types.Vector2.new(309, 360)
		local objective, supplies = find(map, "A"), find(map, "C")
		objective.Activated.fire()
		t.expect(built.report().selected).toBe("Objective")
		find(node, "Move").Activated.fire()
		t.expect(find(map, "A")).toBe(objective)
		t.expect(find(objective, "Direction").Visible).toBe(true)
		t.expect(objective.Position.X.Offset + objective.Size.X.Offset <= map.AbsoluteSize.X).toBe(true)
		find(node, "Hide").Activated.fire()
		t.expect(supplies.Visible).toBe(false)
		t.expect(objective.Visible).toBe(true)
		stop()
		t.expect(objective.isDestroyed()).toBe(true)
		t.expect(supplies.isDestroyed()).toBe(true)
		t.expect(#ctx.worldTarget:GetChildren()).toBe(0)
	end)

	t.it("swipes the native mail list and deletes exactly the chosen message", function()
		local _, node, stop, ctx = mount("row_actions")
		local row = find(node, "Row_m1")
		row.AbsoluteSize = ctx.types.Vector2.new(300, 64)
		local detector = row:FindFirstChildWhichIsA("UIDragDetector")
		detector.DragStart.fire(ctx.types.Vector2.new(250, 20))
		detector.DragContinue.fire(ctx.types.Vector2.new(10, 20))
		detector.DragEnd.fire()
		t.expect(find(node, "Row_m1")).toBe(nil)
		t.expect(find(node, "Row_m2") ~= nil).toBe(true)
		stop()
	end)
	t.it("honors locked selection pinned movement and protected deletion in RunSheet", function()
		local built, node, stop, ctx = mount("row_capabilities")
		local body = find(find(node, "RunSheet"), "Body")
		body.AbsoluteWindowSize = ctx.types.Vector2.new(500, 400)
		find(find(body, "warmup"), "RowHit").Activated.fire()
		t.expect(built.report().selection.warmup).toBe(true)
		find(find(body, "notes"), "RowHit").Activated.fire()
		t.expect(built.report().selection.warmup).toBe(true)
		t.expect(built.report().selection.notes).toBe(nil)
		t.expect(find(find(body, "grid"), "Move").Interactable).toBe(false)
		local protected = find(find(body, "main"), "delete")
		t.expect(protected.Interactable).toBe(false)
		protected.Activated.fire()
		t.expect(#built.report().rows).toBe(5)
		stop()
	end)
	t.it("sorts filters reorders and restores playlist model and width bindings", function()
		local built, node, stop = mount("02_playlist_table", "example")
		built.sort:set({ column = "name", direction = "descending" })
		local before = built.sortedRows:peek()[1].id
		built.filterText:set("Drift")
		t.expect(#built.from:peek()).toBe(1)
		built.reorder({ "apex" }, 0)
		t.expect(built.sort:peek().direction).toBe("descending")
		built.filterText:set("")
		built.reorder({ before }, 0)
		t.expect(built.sort:peek()).toBe(nil)
		t.expect(built.baseRows:peek()[1].id).toBe(before)
		built.columnWidths:set({ name = 290, artist = 150 })
		t.expect(find(node, "Widths").Text:find("290", 1, true) ~= nil).toBe(true)
		built.restore()
		t.expect(built.ratingFor("neon"):peek()).toBe(4)
		stop()
	end)
end)
