--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local Compose = Facet.Compose

type World = {
	engine: any,
	runtime: any,
	UI: any,
	Host: any,
	gui: any,
	input: any,
	root: any,
	node: any,
	stop: () -> (),
}

local function setup(build: (any, any, any, any) -> any, options: { [string]: any }?): World
	local engine: any = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local gui = engine.new("GuiService")
	local input = engine.new("UserInputService")
	input.GetFocusedTextBox = function()
		return nil
	end
	input.IsKeyDown = function()
		return false
	end
	local root = engine.new("ScreenGui")
	local config: { [string]: any } = {
		types = engine.types,
		guiService = gui,
		services = { GuiService = gui, UserInputService = input },
		inputParent = root,
		reducedMotion = true,
	}
	for key, value in (options or {}) :: { [string]: any } do
		config[key] = if type(value) == "function" and key ~= "onError" then value(engine) else value
	end
	local UI = Facet.controls(runtime, config :: any)
	local Host = runtime.constructors
	local stop, node = runtime.mount(function()
		return build(UI, Host, engine, runtime)
	end, root)
	return {
		engine = engine,
		runtime = runtime,
		UI = UI,
		Host = Host,
		gui = gui,
		input = input,
		root = root,
		node = node,
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

local function action(root: any, name: string): any
	for _, child in root:GetDescendants() do
		if child:IsA("InputContext") and child.Name == "Facet" .. name and child.Enabled then
			return child:FindFirstChild(name)
		end
	end
	return nil
end

local function deliver(root: any, key: any): { string }
	local contexts = {}
	for _, child in root:GetDescendants() do
		if child:IsA("InputContext") and child.Enabled then
			table.insert(contexts, child)
		end
	end
	table.sort(contexts, function(a, b)
		return a.Priority > b.Priority
	end)
	local received = {}
	for _, context in contexts do
		local matched = false
		for _, inputAction in context:GetChildren() do
			if inputAction:IsA("InputAction") then
				for _, binding in inputAction:GetChildren() do
					if binding:IsA("InputBinding") and binding.KeyCode == key then
						matched = true
						table.insert(received, context.Name)
						inputAction.Pressed.fire()
						break
					end
				end
			end
		end
		if matched and context.Sink then
			break
		end
	end
	return received
end

local function probe(Host: any, engine: any, onPressed: () -> ()): any
	return Host.InputContext "Probe" {
		Priority = 3000,
		Sink = false,
		Enabled = true,
		Host.InputAction "ProbeNavigate" {
			Pressed = onPressed,
			Host.InputBinding({ KeyCode = engine.types.Enum.KeyCode.DPadDown }),
			Host.InputBinding({ KeyCode = engine.types.Enum.KeyCode.Down }),
		},
	}
end

local function pointer(engine: any, kind: string): any
	local E = engine.types.Enum
	return {
		UserInputType = if kind == "gamepad"
			then E.UserInputType.Gamepad1
			elseif kind == "touch" then E.UserInputType.Touch
			else E.UserInputType.MouseButton1,
		KeyCode = if kind == "gamepad" then E.KeyCode.ButtonA else E.KeyCode.Unknown,
	}
end

local function galleryContext(): (any, any, any)
	local engine = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local viewport = Compose.cell({ width = 1280, height = 720 })
	local target = engine.new("Folder")
	local guiService = engine.new("GuiService")
	local input = engine.new("UserInputService")
	input.GetFocusedTextBox = function()
		return nil
	end
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
		UI = Facet.controls(
			runtime,
			{
				types = engine.types,
				viewport = viewport,
				guiService = guiService,
				services = { GuiService = guiService, UserInputService = input },
				inputParent = target,
				reducedMotion = true,
			} :: any
		),
	}
	return ctx, engine, target
end

local function mountGallery(name: string, kind: string?): (any, any, () -> (), any)
	local ctx, _, target = galleryContext()
	local built
	local folder = if kind == "example" then "examples/" else "scenarios/"
	local stop, node = ctx.runtime.mount(function()
		built = (require :: any)("../examples/gallery/" .. folder .. name).build(ctx)
		if built.dispose then
			Compose.cleanup(built.dispose)
		end
		return ctx.Host.ScreenGui "DemoScreen" { built.screen() }
	end, target)
	return built, node, function()
		stop()
		ctx.runtime:dispose()
	end, ctx
end

t.describe("native parity weaker actions", function()
	t.it("shows the owner value and placeholder in a native TextBox and edits without optional services", function()
		local value, placeholder = Compose.cell("Ada"), "Your name"
		local world = setup(function(UI)
			return UI.TextInput "Name" { value = value, placeholder = placeholder }
		end)
		local field = find(world.node, "Name")
		t.expect(field.ClassName).toBe("TextBox")
		t.expect(field.Text).toBe("Ada")
		t.expect(field.PlaceholderText).toBe("Your name")
		value:set("")
		t.expect(field.Text).toBe("")
		t.expect(field.PlaceholderText).toBe("Your name")
		world.stop()
		local engine: any = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local UI = Facet.controls(runtime, { types = engine.types } :: any)
		local text, commits = Compose.cell(""), {}
		local stop, bare = runtime.mount(function()
			return UI.TextInput "Bare" {
				value = text,
				placeholder = "Type here",
				onCommit = function(committed, reason)
					table.insert(commits, { committed, reason })
				end,
			}
		end, engine.new("ScreenGui"))
		t.expect(bare.PlaceholderText).toBe("Type here")
		bare:CaptureFocus()
		bare.Text = "abc"
		t.expect(text:peek()).toBe("abc")
		bare:ReleaseFocus(true)
		t.expect(#commits).toBe(1)
		t.expect(commits[1][1]).toBe("abc")
		t.expect(commits[1][2]).toBe("submit")
		stop()
		runtime:dispose()
	end)

	t.it("enters editing on native focus, flows typed text to onChange and names both commit reasons", function()
		local value, changes, commits = Compose.cell(""), {}, {}
		local world = setup(function(UI)
			return UI.TextInput "Name" {
				value = value,
				onChange = function(text)
					value:set(text)
					table.insert(changes, text)
				end,
				onCommit = function(text, reason)
					table.insert(commits, { text, reason })
				end,
			}
		end)
		local field = find(world.node, "Name")
		t.expect(action(world.root, "TextEditing")).toBe(nil)
		field:CaptureFocus()
		t.expect(action(world.root, "TextEditing") ~= nil).toBe(true)
		for _, text in { "a", "ab", "abc" } do
			field.Text = text
		end
		t.expect(value:peek()).toBe("abc")
		t.expect(#changes).toBe(3)
		t.expect(changes[1]).toBe("a")
		t.expect(changes[3]).toBe("abc")
		t.expect(#commits).toBe(0)
		field:ReleaseFocus(true)
		t.expect(commits[1][1]).toBe("abc")
		t.expect(commits[1][2]).toBe("submit")
		t.expect(action(world.root, "TextEditing")).toBe(nil)
		field:CaptureFocus()
		field.Text = "abcd"
		field:ReleaseFocus(false)
		t.expect(#commits).toBe(2)
		t.expect(commits[2][1]).toBe("abcd")
		t.expect(commits[2][2]).toBe("focusLost")
		t.expect(action(world.root, "TextEditing")).toBe(nil)
		world.stop()
	end)

	t.it("keeps onChange and onCommit distinct, clamps a pasted append and reconciles an over-long commit", function()
		local value, changes, commits = Compose.cell("ab"), 0, {}
		local world = setup(function(UI)
			return UI.TextInput "Name" {
				value = value,
				maxLength = 5,
				onChange = function(text)
					value:set(text)
					changes += 1
				end,
				onCommit = function(text)
					table.insert(commits, text)
				end,
			}
		end)
		local field = find(world.node, "Name")
		field:CaptureFocus()
		field.Text = "abcdefgh"
		t.expect(value:peek()).toBe("abcde")
		t.expect(field.Text).toBe("abcde")
		t.expect(changes).toBe(1)
		t.expect(#commits).toBe(0)
		field.Text = "abcdeXYZ"
		t.expect(value:peek()).toBe("abcde")
		t.expect(field.Text).toBe("abcde")
		t.expect(changes).toBe(1)
		field:ReleaseFocus(true)
		t.expect(#commits).toBe(1)
		t.expect(commits[1]).toBe("abcde")
		world.stop()
		local upper, edits = Compose.cell(""), 0
		world = setup(function(UI)
			return UI.TextInput "Upper" {
				value = upper,
				validate = function(proposed)
					return if string.find(proposed, "%d") then nil else string.upper(proposed)
				end,
				onChange = function(text)
					upper:set(text)
					edits += 1
				end,
			}
		end)
		field = find(world.node, "Upper")
		field:CaptureFocus()
		field.Text = "ab"
		t.expect(upper:peek()).toBe("AB")
		t.expect(field.Text).toBe("AB")
		field.Text = "AB1"
		t.expect(upper:peek()).toBe("AB")
		t.expect(field.Text).toBe("AB")
		t.expect(edits).toBe(1)
		field.Text = "AB\xC3("
		t.expect(upper:peek()).toBe("AB")
		t.expect(edits).toBe(1)
		world.stop()
	end)

	t.it("sinks navigation keys from lower contexts only while a field edits", function()
		local probed, value, commits = 0, Compose.cell("seed"), {}
		local world = setup(function(UI, Host, engine)
			return Host.Frame({
				probe(Host, engine, function()
					probed += 1
				end),
				UI.TextInput "Field" {
					value = value,
					onCommit = function(text, reason)
						table.insert(commits, { text, reason })
					end,
				},
			})
		end)
		local E = world.engine.types.Enum
		local field = find(world.node, "Field")
		deliver(world.root, E.KeyCode.DPadDown)
		t.expect(probed).toBe(1)
		field:CaptureFocus()
		local sink = find(world.root, "FacetTextEditing")
		t.expect(sink.Enabled).toBe(true)
		t.expect(sink.Sink).toBe(true)
		t.expect(sink.Priority > 3000).toBe(true)
		for _, key in { E.KeyCode.DPadDown, E.KeyCode.Down, E.KeyCode.Up, E.KeyCode.Left, E.KeyCode.Right } do
			local received = deliver(world.root, key)
			t.expect(received[1]).toBe("FacetTextEditing")
			t.expect(table.find(received, "Probe")).toBe(nil)
		end
		t.expect(probed).toBe(1)
		t.expect(field:IsFocused()).toBe(true)
		field.Text = "seedX"
		t.expect(value:peek()).toBe("seedX")
		field:ReleaseFocus(true)
		t.expect(commits[1][2]).toBe("submit")
		t.expect(sink.Enabled).toBe(false)
		deliver(world.root, E.KeyCode.DPadDown)
		t.expect(probed).toBe(2)
		world.stop()
	end)

	t.it("brings the editing sink down when the engine drops the editing surface without Enter", function()
		local probed, value, commits = 0, Compose.cell(""), {}
		local world = setup(function(UI, Host, engine)
			return Host.Frame({
				probe(Host, engine, function()
					probed += 1
				end),
				UI.TextInput "Field" {
					value = value,
					onCommit = function(text, reason)
						table.insert(commits, { text, reason })
					end,
				},
			})
		end)
		local E = world.engine.types.Enum
		local field = find(world.node, "Field")
		field:CaptureFocus()
		field.Text = "hi"
		deliver(world.root, E.KeyCode.DPadDown)
		t.expect(probed).toBe(0)
		field:ReleaseFocus(false)
		t.expect(#commits).toBe(1)
		t.expect(commits[1][1]).toBe("hi")
		t.expect(commits[1][2]).toBe("focusLost")
		t.expect(value:peek()).toBe("hi")
		t.expect(find(world.root, "FacetTextEditing").Enabled).toBe(false)
		deliver(world.root, E.KeyCode.DPadDown)
		t.expect(probed).toBe(1)
		field:CaptureFocus()
		deliver(world.root, E.KeyCode.DPadDown)
		t.expect(probed).toBe(1)
		world.node.Visible = false
		t.expect(field:IsFocused()).toBe(false)
		t.expect(find(world.root, "FacetTextEditing").Enabled).toBe(false)
		world.node.Visible = true
		deliver(world.root, E.KeyCode.DPadDown)
		t.expect(probed).toBe(2)
		world.stop()
	end)
	t.it("converts typed Fahrenheit live, commits on Enter and focus loss, and Clear resets every readout", function()
		local built, node, stop = mountGallery("01_temperature_converter", "example")
		local field, preview, result = find(node, "Fahrenheit"), find(node, "Preview"), find(node, "Result")
		t.expect(field.PlaceholderText).toBe("e.g. 212")
		t.expect(find(node, "Convert")).toBe(nil)
		t.expect(find(node, "Stepper")).toBe(nil)
		field:CaptureFocus()
		field.Text = "212"
		t.expect(built.fahrenheitText()).toBe("212")
		t.expect(preview.Text).toBe("Preview: 100 °C  (live, as you type)")
		t.expect(result.Text).toBe("Result: —")
		field.Text = "212a"
		t.expect(field.Text).toBe("212")
		t.expect(built.fahrenheitText()).toBe("212")
		field:ReleaseFocus(true)
		t.expect(result.Text).toBe("Result: 100 °C")
		field:CaptureFocus()
		field.Text = "32"
		t.expect(result.Text).toBe("Result: 100 °C")
		field:ReleaseFocus(false)
		t.expect(built.celsius()).toBe(0)
		t.expect(result.Text).toBe("Result: 0 °C")
		find(node, "Clear").Activated.fire()
		t.expect(built.fahrenheitText()).toBe("")
		t.expect(field.Text).toBe("")
		t.expect(built.liveCelsius()).toBe(nil)
		t.expect(built.celsius()).toBe(nil)
		t.expect(preview.Text).toBe("Preview: —")
		t.expect(result.Text).toBe("Result: —")
		stop()
	end)

	t.it("filters the playlist from typed text, keeps row identity and never navigates the table", function()
		local built, node, stop, ctx = mountGallery("02_playlist_table", "example")
		local E = ctx.types.Enum
		find(node, "Body").AbsoluteWindowSize = ctx.types.Vector2.new(600, 400)
		local function rowFor(name: string): any
			for _, label in node:GetDescendants() do
				if label:IsA("TextLabel") and label.Text == name then
					local at = label
					while at and at.Name ~= "Row" do
						at = at.Parent
					end
					return at
				end
			end
			return nil
		end
		local filter = find(node, "Filter")
		local clear = find(filter, "Clear")
		t.expect(clear.Visible).toBe(false)
		local drift = rowFor("Drift City Nights")
		t.expect(drift ~= nil).toBe(true)
		local order = {}
		for _, track in built.baseRows:peek() do
			table.insert(order, track.id)
		end
		filter:CaptureFocus()
		local received = deliver(ctx.inputTarget, E.KeyCode.Down)
		t.expect(received[1]).toBe("FacetTextEditing")
		t.expect(#received).toBe(1)
		filter.Text = "d"
		t.expect(built.filterText:peek()).toBe("d")
		t.expect(clear.Visible).toBe(true)
		filter.Text = "DRIFT"
		t.expect(#built.from:peek()).toBe(1)
		t.expect(built.from:peek()[1].id).toBe("drift")
		t.expect(rowFor("Drift City Nights")).toBe(drift)
		t.expect(drift.isDestroyed()).toBe(false)
		t.expect(rowFor("Neon Straightaway")).toBe(nil)
		for _, row in node:GetDescendants() do
			if row.Name == "Row" then
				t.expect(row:GetAttribute("FacetSelected")).toBe(false)
			end
		end
		built.reorder({ "drift" }, 0)
		for index, track in built.baseRows:peek() do
			t.expect(track.id).toBe(order[index])
		end
		clear.Activated.fire()
		t.expect(built.filterText:peek()).toBe("")
		t.expect(filter.Text).toBe("")
		t.expect(clear.Visible).toBe(false)
		t.expect(#built.from:peek()).toBe(6)
		t.expect(rowFor("Drift City Nights")).toBe(drift)
		filter:ReleaseFocus(false)
		t.expect(find(ctx.inputTarget, "FacetTextEditing").Enabled).toBe(false)
		stop()
	end)
	t.it("filters the monitor feed by genre and typed search, opens the chosen game and clears back", function()
		local screens = require("../examples/virtual_monitors/screens")
		local modelModule = require("../examples/virtual_monitors/model")
		local engine: any = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
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
				reducedMotion = true,
			})
			local _, discover = runtime.mount(views.Discover, target)
			find(discover, "DiscoverBody").AbsoluteSize = engine.types.Vector2.new(1000, 800)
			local total = #model.catalog.items:peek()
			local genres = {}
			for _, item in model.catalog.items:peek() do
				genres[item.id] = item.genre
			end
			local function shownGenres(): { string }
				local shown = {}
				local grid = find(discover, "Games")
				grid.AbsoluteWindowSize = engine.types.Vector2.new(850, 260)
				for _, card in grid:GetDescendants() do
					local id = string.match(card.Name, "^Game_(%w+)$")
					if id then
						table.insert(shown, genres[id])
					end
				end
				return shown
			end
			local picker = find(discover, "Genres")
			find(picker, "Genre_Racing").Activated.fire()
			t.expect(model.genre:peek()).toBe("Racing")
			t.expect(#model.visibleGames:peek() > 0).toBe(true)
			for _, item in model.visibleGames:peek() do
				t.expect(item.genre).toBe("Racing")
			end
			t.expect(#shownGenres() > 0).toBe(true)
			for _, genre in shownGenres() do
				t.expect(genre).toBe("Racing")
			end
			find(picker, "Genre_Building").Activated.fire()
			t.expect(model.genre:peek()).toBe("Building")
			t.expect(find(picker, "Genre_Building"):GetAttribute("selected")).toBe(true)
			t.expect(find(picker, "Genre_Racing"):GetAttribute("selected")).toBe(false)
			find(picker, "Genre_all").Activated.fire()
			t.expect(model.genre:peek()).toBe("all")
			t.expect(#model.visibleGames:peek()).toBe(total)
			find(picker, "Genre_Adventure").Activated.fire()
			local editor = find(find(discover, "Search"), "Editor")
			editor:CaptureFocus()
			editor.Text = "Neon Harbor"
			t.expect(model.query:peek()).toBe("Neon Harbor")
			t.expect(#model.visibleGames:peek()).toBe(0)
			find(picker, "Genre_all").Activated.fire()
			local matches = model.visibleGames:peek()
			t.expect(#matches > 0).toBe(true)
			for _, item in matches do
				t.expect(string.find(string.lower(item.title), "neon harbor", 1, true) ~= nil).toBe(true)
			end
			local panel = find(target, "MenuPanel")
			t.expect(panel ~= nil).toBe(true)
			find(panel, matches[1].id).Activated.fire()
			t.expect(model.selectedGame:peek().title).toBe("Neon Harbor")
			find(target, "close").Activated.fire()
			editor:CaptureFocus()
			editor.Text = ""
			editor:ReleaseFocus(false)
			t.expect(model.query:peek()).toBe("")
			t.expect(#model.visibleGames:peek()).toBe(total)
		end, runtime.reactor)
		lifetime.dispose()
		t.expect(#target:GetChildren()).toBe(0)
		runtime:dispose()
	end)
	t.it("drives the gallery setting rows and removable race tags and stops reporting after unmount", function()
		local settings, node, stop = mountGallery("adaptive_controls")
		t.expect(find(node, "Vsync")).toBe(nil)
		find(find(node, "Advanced"), "Header").Activated.fire()
		local vsync = find(node, "Vsync")
		t.expect(vsync ~= nil).toBe(true)
		t.expect(vsync.ClassName).toBe("TextButton")
		t.expect(vsync:HasTag("facet-toggle")).toBe(true)
		t.expect(vsync:GetAttribute("selected")).toBe(true)
		vsync.Activated.fire()
		t.expect(settings.report().vsync).toBe(false)
		t.expect(vsync:GetAttribute("selected")).toBe(false)
		local telemetry = find(node, "Telemetry")
		t.expect(telemetry:HasTag("facet-toggle")).toBe(true)
		telemetry.Activated.fire()
		t.expect(settings.report().telemetry).toBe(true)
		stop()
		local actions, actionNode, actionStop = mountGallery("action_controls")
		t.expect(actions.report().tokenCount).toBe(3)
		local tokens = find(actionNode, "Tokens")
		local function chips(): { any }
			local found = {}
			for _, child in tokens:GetDescendants() do
				if child.Name == "Token" then
					table.insert(found, child)
				end
			end
			return found
		end
		t.expect(#chips()).toBe(3)
		local removed = chips()[2]
		local remove = find(removed, "Remove")
		t.expect(remove.ClassName).toBe("TextLabel")
		t.expect(remove.Visible).toBe(false)
		t.expect(removed:GetAttribute("editing")).toBe(false)
		find(actionNode, "EditTags").Activated.fire()
		t.expect(remove.Visible).toBe(true)
		t.expect(removed:GetAttribute("editing")).toBe(true)
		removed.Activated.fire()
		t.expect(actions.report().tokenCount).toBe(2)
		t.expect(#chips()).toBe(2)
		t.expect(removed.isDestroyed()).toBe(true)
		t.expect(remove.Parent).toBe(nil)
		actions.steps.reset()
		t.expect(actions.report().tokenCount).toBe(3)
		t.expect(#chips()).toBe(3)
		actionStop()
		t.expect(actions.report()).toBe(nil)
	end)

	t.it(
		"keeps recipe action order, equal column widths, appearances, focus targets, checks, chips and commands",
		function()
			local built, node, stop, ctx = mountGallery("recipes_common")
			local E = ctx.types.Enum
			local actions = find(node, "Actions")
			actions.AbsoluteSize = ctx.types.Vector2.new(700, 44)
			for name, width in { Cancel = 48, Save = 200, Delete = 80 } do
				find(find(actions, name), "NaturalWidth").TextBounds = ctx.types.Vector2.new(width, 20)
			end
			local cancel, save, delete = find(actions, "Cancel"), find(actions, "Save"), find(actions, "Delete")
			for _, form in { "row", "column", "row" } do
				local report = if form == "row" then built.steps.wideActions() else built.steps.narrowActions()
				t.expect(report.actionsForm).toBe(form)
				local selectable = 0
				for _, child in actions:GetDescendants() do
					if child:IsA("GuiButton") and child.Selectable then
						selectable += 1
					end
				end
				t.expect(selectable).toBe(3)
				t.expect(cancel.LayoutOrder < save.LayoutOrder and save.LayoutOrder < delete.LayoutOrder).toBe(true)
				t.expect(find(actions, "UIListLayout").SortOrder).toBe(E.SortOrder.LayoutOrder)
				if form == "column" then
					for _, button in { cancel, save, delete } do
						t.expect(button.Size.X.Scale).toBe(1)
						t.expect(button.Size.X.Offset).toBe(0)
						t.expect(button.AutomaticSize).toBe(E.AutomaticSize.Y)
					end
				else
					for _, button in { cancel, save, delete } do
						t.expect(button.AutomaticSize).toBe(E.AutomaticSize.XY)
					end
				end
				t.expect(save:GetAttribute("appearance")).toBe("emphasis")
				t.expect(save:HasTag("facet-accent")).toBe(true)
				t.expect(delete:GetAttribute("role")).toBe("destructive")
				t.expect(delete:HasTag("facet-role-destructive")).toBe(true)
				t.expect(cancel:GetAttribute("role")).toBe("cancel")
				save.Activated.fire()
			end
			t.expect(built.report().activations).toBe(3)
			local group, wrap = find(node, "CheckboxGroup"), find(node, "WrapChecks")
			find(group, "fuel").Activated.fire()
			t.expect(built.report().checks.tires).toBe(true)
			t.expect(built.report().checks.fuel).toBe(true)
			t.expect(built.report().requests).toBe(1)
			t.expect(find(wrap, "fuel"):GetAttribute("selected")).toBe(true)
			find(wrap, "fuel").Activated.fire()
			t.expect(find(group, "fuel"):GetAttribute("selected")).toBe(false)
			t.expect(built.report().checks.tires).toBe(true)
			t.expect(find(group, "tires"):GetAttribute("selected")).toBe(true)
			local chips = find(node, "WrapChips")
			local rain, dust = find(chips, "Rain"), find(chips, "Dust")
			rain.Activated.fire()
			t.expect(built.report().wrapSelected.Rain).toBe(true)
			t.expect(built.report().wrapSelected.Night).toBe(false)
			built.steps.reorderTags()
			t.expect(find(chips, "Rain")).toBe(rain)
			t.expect(dust.isDestroyed()).toBe(true)
			t.expect(find(chips, "Dust")).toBe(nil)
			t.expect(built.report().wrapSelected.Rain).toBe(true)
			t.expect(rain:HasTag("facet-selected")).toBe(true)
			t.expect(find(chips, "Night"):HasTag("facet-selected")).toBe(false)
			rain.Activated.fire()
			t.expect(built.report().wrapSelected.Rain).toBe(false)
			t.expect(rain:HasTag("facet-selected")).toBe(false)
			for _, entry in
				{ { "EmptyCollection", "createCount" }, { "NoResults", "clearCount" }, { "LoadFailed", "retryCount" } }
			do
				for count = 1, 2 do
					find(find(node, entry[1]), "Action").Activated.fire()
					t.expect(built.report()[entry[2]]).toBe(count)
				end
			end
			stop()
		end
	)

	t.it("activates a plain Button once from pointer, touch, gamepad and keyboard with no wiring", function()
		local hits, count = {}, 0
		local world = setup(function(UI)
			return UI.Button "Go" {
				label = "Go",
				onActivate = function(input)
					count += 1
					table.insert(hits, input)
				end,
			}
		end)
		local node = find(world.node, "Go")
		t.expect(action(world.root, "Activate")).toBe(nil)
		for _, kind in { "pointer", "touch", "gamepad" } do
			local input = pointer(world.engine, kind)
			node.Activated.fire(input, 1)
			t.expect(hits[#hits]).toBe(input)
		end
		t.expect(count).toBe(3)
		world.gui.SelectedObject = node
		local activate = action(world.root, "Activate")
		t.expect(activate ~= nil).toBe(true)
		local keys = {}
		for _, binding in activate:GetChildren() do
			keys[binding.KeyCode.Name] = true
		end
		t.expect(keys.Return).toBe(true)
		t.expect(keys.Space).toBe(true)
		t.expect(keys.ButtonA).toBe(nil)
		deliver(world.root, world.engine.types.Enum.KeyCode.Return)
		t.expect(count).toBe(4)
		deliver(world.root, world.engine.types.Enum.KeyCode.ButtonA)
		t.expect(count).toBe(4)
		world.stop()
	end)

	t.it("mounts an initially busy Button with its spinner and releases it when busy ends", function()
		local busy, actions = Compose.cell(true), 0
		local world = setup(function(UI)
			return UI.Button "Loading" {
				label = "Loading",
				busy = busy,
				onActivate = function()
					actions += 1
				end,
			}
		end, { reducedMotion = false })
		local node = find(world.node, "Loading")
		t.expect(find(node, "Busy") ~= nil).toBe(true)
		t.expect(find(node, "Dot3") ~= nil).toBe(true)
		t.expect(world.engine.heartbeat.count()).toBe(1)
		t.expect(node:HasTag("facet-busy")).toBe(true)
		t.expect(node.Interactable).toBe(false)
		node.Activated.fire()
		t.expect(actions).toBe(0)
		busy:set(false)
		t.expect(find(node, "Busy")).toBe(nil)
		t.expect(world.engine.heartbeat.count()).toBe(0)
		node.Activated.fire()
		t.expect(actions).toBe(1)
		busy:set(true)
		t.expect(world.engine.heartbeat.count()).toBe(1)
		world.stop()
		t.expect(world.engine.heartbeat.count()).toBe(0)
	end)

	t.it("keeps a disabled destructive Button disabled on every input and re-enables it in place", function()
		local enabled, fired = Compose.cell(false), 0
		local world = setup(function(UI)
			return UI.Button "Delete" {
				label = "Delete",
				role = "destructive",
				enabled = enabled,
				onActivate = function()
					fired += 1
				end,
			}
		end)
		local node = find(world.node, "Delete")
		t.expect(node:HasTag("facet-role-destructive")).toBe(true)
		t.expect(node:HasTag("facet-disabled")).toBe(true)
		t.expect(node.Selectable).toBe(false)
		t.expect(node.Interactable).toBe(false)
		for _, kind in { "pointer", "touch", "gamepad" } do
			node.Activated.fire(pointer(world.engine, kind))
		end
		world.gui.SelectedObject = node
		t.expect(world.gui.SelectedObject).toBe(nil)
		t.expect(table.find(world.engine.rejectedSelections, node) ~= nil).toBe(true)
		t.expect(action(world.root, "Activate")).toBe(nil)
		deliver(world.root, world.engine.types.Enum.KeyCode.Return)
		t.expect(fired).toBe(0)
		enabled:set(true)
		t.expect(find(world.node, "Delete")).toBe(node)
		t.expect(node:HasTag("facet-disabled")).toBe(false)
		t.expect(node:HasTag("facet-role-destructive")).toBe(true)
		t.expect(node.Selectable).toBe(true)
		world.gui.SelectedObject = node
		t.expect(world.gui.SelectedObject).toBe(node)
		deliver(world.root, world.engine.types.Enum.KeyCode.Return)
		node.Activated.fire(pointer(world.engine, "touch"))
		t.expect(fired).toBe(2)
		world.stop()
	end)

	t.it("mounts an explicit rect shape as an ordinary Button and a circle with a bound label", function()
		local label = Compose.cell("1")
		local world = setup(function(UI, Host)
			return Host.Frame({
				UI.Button "Rect" { label = "Save changes", shape = "rect" },
				UI.Button "Plain" { label = "Save changes" },
				UI.Button "Count" { label = label, shape = "circle" },
			})
		end)
		local rect, plain, count = find(world.node, "Rect"), find(world.node, "Plain"), find(world.node, "Count")
		for _, node in { rect, plain } do
			t.expect(node:FindFirstChildWhichIsA("UIAspectRatioConstraint")).toBe(nil)
			t.expect(node:FindFirstChildWhichIsA("UICorner")).toBe(nil)
			t.expect(node:HasTag("facet-shape-circle")).toBe(false)
			t.expect(node.Text).toBe("Save changes")
			t.expect(node.AutomaticSize).toBe(world.engine.types.Enum.AutomaticSize.XY)
		end
		t.expect(count:HasTag("facet-shape-circle")).toBe(true)
		t.expect(count:FindFirstChildWhichIsA("UIAspectRatioConstraint").AspectRatio).toBe(1)
		t.expect(count.Text).toBe("1")
		t.expect(count:GetAttribute("label")).toBe("1")
		label:set("99+")
		t.expect(find(world.node, "Count")).toBe(count)
		t.expect(count.Text).toBe("99+")
		t.expect(count:GetAttribute("label")).toBe("99+")
		t.expect(count.Size.X.Offset).toBe(count.Size.Y.Offset)
		world.stop()
	end)
	t.it(
		"shares activation and disable guards across Toggle, Button, ComboBox and SplitButton on every input",
		function()
			for _, kind in { "Toggle", "Button", "ComboBox", "SplitButton" } do
				for _, input in { "pointer", "touch", "keyboard", "gamepad" } do
					local enabled, calls = Compose.cell(true), 0
					local value, text = Compose.cell("a"), Compose.cell("A")
					local world = setup(function(UI)
						if kind == "Toggle" then
							return UI.Toggle "Control" {
								label = "Test checkbox",
								value = Compose.cell(false),
								mixed = Compose.cell(true),
								presentation = "checkbox",
								enabled = enabled,
								onChange = function()
									calls += 1
								end,
							}
						elseif kind == "Button" then
							return UI.Button "Control" {
								label = "Test action",
								enabled = enabled,
								onActivate = function()
									calls += 1
								end,
							}
						elseif kind == "SplitButton" then
							return UI.SplitButton "Control" {
								label = "Test action",
								enabled = enabled,
								onActivate = function()
									calls += 1
								end,
								items = { { id = "option", label = "Choose this", onSelect = function() end } },
							}
						end
						return UI.ComboBox "Control" {
							value = value,
							text = text,
							enabled = enabled,
							options = { { id = "a", label = "A" }, { id = "b", label = "B" } },
							acceptCustom = function()
								return true
							end,
						}
					end)
					local root = world.node
					local function activate(target: any)
						if input == "keyboard" then
							world.gui.SelectedObject = target
							deliver(world.root, world.engine.types.Enum.KeyCode.Return)
							world.gui.SelectedObject = nil
						else
							target.Activated.fire(pointer(world.engine, input), 1)
						end
					end
					if kind == "ComboBox" then
						local editor = find(root, "Editor")
						t.expect(editor.TextEditable).toBe(true)
						t.expect(editor.Selectable).toBe(true)
						editor:CaptureFocus()
						t.expect(find(world.root, "FacetTextEditing").Enabled).toBe(true)
						editor.Text = "B"
						editor:ReleaseFocus(true)
						t.expect(value:peek()).toBe("b")
						text:set("")
						activate(find(root, "Trigger"))
						t.expect(find(world.root, "MenuPanel") ~= nil).toBe(true)
						activate(find(find(world.root, "MenuPanel"), "a"))
						t.expect(value:peek()).toBe("a")
						enabled:set(false)
						t.expect(editor.TextEditable).toBe(false)
						t.expect(editor.Selectable).toBe(false)
						t.expect(find(root, "Trigger").Interactable).toBe(false)
						editor:CaptureFocus()
						t.expect(find(world.root, "FacetTextEditing").Enabled).toBe(false)
						editor.Text = "B"
						editor:ReleaseFocus(true)
						activate(find(root, "Trigger"))
						t.expect(value:peek()).toBe("a")
						t.expect(find(world.root, "MenuPanel")).toBe(nil)
					else
						local target = if kind == "SplitButton" then find(root, "Primary") else root
						activate(target)
						t.expect(calls).toBe(1)
						if kind == "SplitButton" then
							activate(find(find(root, "Alternatives"), "Trigger"))
							t.expect(find(world.root, "MenuPanel") ~= nil).toBe(true)
							t.expect(calls).toBe(1)
							find(find(world.root, "MenuPanel"), "option").Activated.fire()
						end
						enabled:set(false)
						t.expect(target.Interactable).toBe(false)
						t.expect(target.Selectable).toBe(false)
						activate(target)
						t.expect(calls).toBe(1)
						if kind == "SplitButton" then
							activate(find(find(root, "Alternatives"), "Trigger"))
							t.expect(find(world.root, "MenuPanel")).toBe(nil)
						end
					end
					world.stop()
				end
			end
		end
	)

	t.it(
		"hands one application press haptic to opted-in buttons, segments and toggles and leaves plain buttons, hover and fields alone",
		function()
			local effect
			local selected = Compose.cell("one")
			local world = setup(function(UI, Host)
				return Host.Frame({
					UI.Button "Plain" { label = "Play" },
					UI.Button "Other" { label = "Stop", haptic = true },
					UI.Toggle "Switch" { label = "Sound", value = Compose.cell(true) },
					UI.Picker "Segments" {
						selected = selected,
						style = "segmented",
						options = { { value = "one", label = "One" }, { value = "two", label = "Two" } },
					},
					UI.TextInput "Field" { value = Compose.cell("") },
				})
			end, {
				pressHaptic = function(engine)
					effect = engine.new("HapticEffect")
					return effect
				end,
			})
			local plain, other, switch =
				find(world.node, "Plain"), find(world.node, "Other"), find(world.node, "Switch")
			local segment = find(find(world.node, "Segments"), "two")
			for _, node in { other, switch, segment } do
				t.expect(node.PressHapticEffect).toBe(effect)
				t.expect(node.HoverHapticEffect).toBe(nil)
			end
			t.expect(plain.PressHapticEffect).toBe(nil)
			t.expect(plain.HoverHapticEffect).toBe(nil)
			t.expect(find(world.node, "Field").PressHapticEffect).toBe(nil)
			t.expect(world.node.PressHapticEffect).toBe(nil)
			local effects = 0
			for _, made in world.engine.made do
				if made.ClassName == "HapticEffect" then
					effects += 1
				end
			end
			t.expect(effects).toBe(1)
			t.expect(effect.PlayCount).toBe(nil)
			plain.Activated.fire()
			other.Activated.fire()
			t.expect(effect.PlayCount).toBe(nil)
			world.stop()
			t.expect(effect.isDestroyed()).toBe(false)
			world = setup(function(UI)
				return UI.Button "Plain" { label = "Play" }
			end)
			t.expect(find(world.node, "Plain").PressHapticEffect).toBe(nil)
			world.stop()
		end
	)

	t.it("returns a pressed pop to its rest under an authored scale and keeps the native shadow", function()
		local package = Facet.themes.neutralPackage()
		package.chrome.control = { kind = "native", shadow = "raised" }
		local world = setup(function(UI, Host)
			return Host.Frame "Card" {
				Host.UIScale "Authored" { Scale = 0.8 },
				UI.Button "Pop" { label = "Pop", pop = true, onActivate = function() end },
			}
		end, { reducedMotion = false, theme = package })
		local E = world.engine.types.Enum
		local node = find(world.node, "Pop")
		local authored = find(world.node, "Authored")
		local pop = node:FindFirstChildWhichIsA("UIScale")
		local shadow = find(node, "ChromeShadow")
		t.expect(shadow.ClassName).toBe("UIShadow")
		t.expect(shadow.Enabled).toBe(true)
		t.expect(pop.Scale).toBe(1)
		node.GuiState = E.GuiState.Press
		node.Activated.fire()
		world.engine.heartbeat.fire(0.1)
		t.expect(pop.Scale > 1).toBe(true)
		t.expect(find(node, "ChromeShadow")).toBe(shadow)
		t.expect(shadow.Enabled).toBe(true)
		node.GuiState = E.GuiState.Idle
		world.engine.heartbeat.fire(1)
		t.expect(pop.Scale).toBe(1)
		t.expect(authored.Scale).toBe(0.8)
		t.expect(find(node, "ChromeShadow")).toBe(shadow)
		t.expect(shadow.Enabled).toBe(true)
		t.expect(shadow.isDestroyed()).toBe(false)
		world.stop()
		t.expect(shadow.isDestroyed()).toBe(true)
	end)

	t.it(
		"tags every disabled control for the theme and tears down cleanly under a non-interactable ancestor",
		function()
			local enabled = Compose.cell(false)
			local world = setup(function(UI, Host)
				return Host.Frame "Panel" {
					UI.Button "Go" { label = "Go", enabled = enabled, onActivate = function() end },
					UI.Toggle "Switch" { label = "Sound", value = Compose.cell(true), enabled = enabled },
					UI.TextInput "Field" { value = Compose.cell(""), enabled = enabled },
				}
			end)
			local go, switch, field = find(world.node, "Go"), find(world.node, "Switch"), find(world.node, "Field")
			for _, node in { go, switch, field } do
				t.expect(node:HasTag("facet-disabled")).toBe(true)
			end
			enabled:set(true)
			for _, node in { go, switch, field } do
				t.expect(node:HasTag("facet-disabled")).toBe(false)
			end
			world.gui.SelectedObject = go
			local activate = action(world.root, "Activate")
			t.expect(activate ~= nil).toBe(true)
			field:CaptureFocus()
			local editing = find(world.root, "FacetTextEditing")
			t.expect(editing.Enabled).toBe(true)
			world.node.Interactable = false
			t.expect(activate.Parent.Enabled).toBe(false)
			t.expect(editing.Enabled).toBe(false)
			t.expect(field:IsFocused()).toBe(false)
			enabled:set(false)
			world.stop()
			t.expect(activate.isDestroyed()).toBe(true)
			t.expect(editing.isDestroyed()).toBe(true)
			t.expect(world.engine.heartbeat.count()).toBe(0)
			t.expect(world.gui:GetPropertyChangedSignal("SelectedObject").count()).toBe(0)
			t.expect(world.node:GetPropertyChangedSignal("Interactable").count()).toBe(0)
			t.expect(go.Activated.count()).toBe(0)
		end
	)

	t.it(
		"waits for a resting pointer, restarts the dwell, shows current help text and never engages on touch",
		function()
			local text = Compose.cell("Posts this avatar")
			local world = setup(function(UI, Host)
				return Host.Frame "Screen" {
					UI.Button "Plus" { label = "+", help = text },
				}
			end)
			local plus = find(world.node, "Plus")
			local E = world.engine.types.Enum
			world.input.PreferredInput = E.PreferredInput.KeyboardAndMouse
			plus.GuiState = E.GuiState.Hover
			world.engine.heartbeat.fire(0.3)
			plus.GuiState = E.GuiState.Idle
			plus.GuiState = E.GuiState.Hover
			world.engine.heartbeat.fire(0.3)
			t.expect(find(world.root, "HelpText")).toBe(nil)
			text:set("Shares this avatar")
			world.engine.heartbeat.fire(0.2)
			local help = find(world.root, "HelpText")
			t.expect(help.Text).toBe("Shares this avatar")
			for _, node in find(world.root, "Help"):GetDescendants() do
				if node:IsA("GuiObject") then
					t.expect(node.Selectable).toBe(false)
				end
			end
			t.expect(find(world.root, "Help").Selectable).toBe(false)
			plus.GuiState = E.GuiState.Idle
			t.expect(find(world.root, "HelpText")).toBe(nil)
			world.input.PreferredInput = E.PreferredInput.Touch
			plus.TouchLongPress.fire({}, E.UserInputState.Begin)
			plus.GuiState = E.GuiState.Press
			world.engine.heartbeat.fire(1)
			t.expect(find(world.root, "HelpText")).toBe(nil)
			world.stop()
		end
	)

	t.it("shows the disclosure state on a leading or trailing caret through header activation", function()
		for _, side in { "leading", "trailing" } do
			local expanded = Compose.cell(false)
			local world = setup(function(UI, Host)
				return UI.DisclosureGroup "Group" {
					label = "Advanced",
					chevronPosition = side,
					expanded = expanded,
					content = function()
						return Host.Frame "Body" {}
					end,
				}
			end)
			local header = find(world.node, "Header")
			local caret = find(header, if side == "leading" then "LeadingIcon" else "TrailingIcon")
			t.expect(find(header, if side == "leading" then "TrailingIcon" else "LeadingIcon")).toBe(nil)
			local closed = caret.Image
			t.expect(header:GetAttribute("selected")).toBe(false)
			header.Activated.fire()
			t.expect(expanded:peek()).toBe(true)
			t.expect(caret.Image ~= closed).toBe(true)
			t.expect(header:GetAttribute("selected")).toBe(true)
			t.expect(find(world.node, "Body") ~= nil).toBe(true)
			header.Activated.fire()
			t.expect(expanded:peek()).toBe(false)
			t.expect(caret.Image).toBe(closed)
			t.expect(header:GetAttribute("selected")).toBe(false)
			t.expect(find(world.node, "Body")).toBe(nil)
			world.stop()
		end
	end)

	t.it(
		"paints contained disclosures, places a trailing caret after the label and follows a bound description",
		function()
			for _, appearance in { "plain", "contained", "divided" } do
				local expanded, description = Compose.cell(false), Compose.cell("Configure the current race")
				local world = setup(function(UI, Host)
					return UI.DisclosureGroup "Group" {
						label = "Details",
						description = description,
						icon = "menu",
						appearance = appearance,
						chevronPosition = "trailing",
						expanded = expanded,
						content = function()
							return Host.Frame "Body" {}
						end,
					}
				end)
				local group, header = world.node, find(world.node, "Header")
				t.expect(group:HasTag("facet-panel")).toBe(appearance == "contained")
				t.expect(group:HasTag("facet-disclosure-" .. appearance)).toBe(true)
				if appearance == "contained" then
					t.expect(group.BackgroundTransparency).toBe(0)
				end
				local content = find(header, "Content")
				local captions, caret = find(content, "Captions"), find(content, "TrailingIcon")
				t.expect(captions.Parent).toBe(caret.Parent)
				t.expect(captions.LayoutOrder < caret.LayoutOrder).toBe(true)
				t.expect(find(content, "LeadingIcon") ~= nil).toBe(true)
				t.expect(find(content, "LeadingIcon").LayoutOrder < captions.LayoutOrder).toBe(true)
				t.expect(find(captions, "Description").Text).toBe("Configure the current race")
				t.expect(header:HasTag("facet-button-described")).toBe(true)
				t.expect(header.AutomaticSize).toBe(world.engine.types.Enum.AutomaticSize.XY)
				description:set("Updated details")
				t.expect(find(captions, "Description").Text).toBe("Updated details")
				t.expect(find(world.node, "Header")).toBe(header)
				t.expect(find(group, "Divider")).toBe(nil)
				expanded:set(true)
				t.expect(find(group, "Divider") ~= nil).toBe(appearance == "divided")
				expanded:set(false)
				t.expect(find(group, "Divider")).toBe(nil)
				world.stop()
			end
		end
	)

	t.it("keeps split primary and alternatives separate in pointer form and runs a plain touch tap", function()
		local primary, alternative = 0, 0
		local world = setup(function(UI)
			return UI.SplitButton "Split" {
				label = "Run",
				onActivate = function()
					primary += 1
				end,
				items = {
					{
						id = "Alternate",
						label = "Alternate",
						onSelect = function()
							alternative += 1
						end,
					},
				},
			}
		end)
		local E = world.engine.types.Enum
		world.input.PreferredInput = E.PreferredInput.KeyboardAndMouse
		local first = find(world.node, "Primary")
		local menu = find(world.node, "Alternatives")
		t.expect(first.Parent).toBe(menu.Parent)
		t.expect(first.LayoutOrder < menu.LayoutOrder).toBe(true)
		t.expect(first.Parent:FindFirstChildWhichIsA("UIListLayout").FillDirection).toBe(E.FillDirection.Horizontal)
		first.Activated.fire(pointer(world.engine, "pointer"))
		t.expect(primary).toBe(1)
		t.expect(find(world.root, "MenuPanel")).toBe(nil)
		find(menu, "Trigger").Activated.fire(pointer(world.engine, "pointer"))
		t.expect(primary).toBe(1)
		t.expect(find(world.root, "MenuPanel") ~= nil).toBe(true)
		find(find(world.root, "MenuPanel"), "Alternate").Activated.fire()
		t.expect(alternative).toBe(1)
		t.expect(primary).toBe(1)
		t.expect(find(world.root, "MenuPanel")).toBe(nil)
		world.input.PreferredInput = E.PreferredInput.Touch
		t.expect(find(world.node, "Alternatives")).toBe(nil)
		local trigger = find(world.node, "Primary")
		t.expect(trigger ~= first).toBe(true)
		trigger.Activated.fire(pointer(world.engine, "touch"))
		t.expect(primary).toBe(2)
		t.expect(find(world.root, "MenuPanel")).toBe(nil)
		trigger.TouchLongPress.fire({}, E.UserInputState.Begin)
		trigger.Activated.fire(pointer(world.engine, "touch"))
		t.expect(primary).toBe(2)
		find(find(world.root, "MenuPanel"), "Alternate").Activated.fire()
		t.expect(alternative).toBe(2)
		trigger.Activated.fire(pointer(world.engine, "touch"))
		t.expect(primary).toBe(3)
		world.input.PreferredInput = E.PreferredInput.KeyboardAndMouse
		find(world.node, "Primary").Activated.fire(pointer(world.engine, "pointer"))
		t.expect(primary).toBe(4)
		world.stop()
	end)

	t.it("selects a page from pointer and touch taps on its indicators", function()
		local selection = Compose.cell("one")
		local world = setup(function(UI, Host)
			return UI.PageView "Pager" {
				selection = selection,
				pages = {
					{ id = "one", title = "One", content = Host.Frame({}) },
					{ id = "two", title = "Two", content = Host.Frame({}) },
					{ id = "three", title = "Three", content = Host.Frame({}) },
				},
			}
		end)
		local indicators = find(world.node, "Indicators")
		local layout = find(world.node, "PagesLayout")
		find(indicators, "three").Activated.fire(pointer(world.engine, "pointer"))
		t.expect(selection:peek()).toBe("three")
		t.expect(layout.CurrentPage.Name).toBe("three")
		t.expect(find(indicators, "three"):HasTag("facet-selected")).toBe(true)
		t.expect(find(world.node, "Summary").Text).toBe("Page 3 of 3")
		find(indicators, "two").Activated.fire(pointer(world.engine, "touch"))
		t.expect(selection:peek()).toBe("two")
		t.expect(layout.CurrentPage.Name).toBe("two")
		t.expect(find(indicators, "two"):HasTag("facet-selected")).toBe(true)
		t.expect(find(indicators, "three"):HasTag("facet-selected")).toBe(false)
		world.stop()
	end)

	t.it("resolves live control-size rungs in place, retracts nil to regular and keeps selection", function()
		local rung, look = Compose.cell("large" :: string?), Compose.cell("standard" :: string?)
		local builds = 0
		local world = setup(function(UI, Host)
			builds += 1
			return Host.Frame({
				UI.Button "Other" { label = "Other" },
				UI.Button "Live" { label = "Go", controlSize = rung, appearance = look },
				UI.Toggle "Switch" { label = "Sound", value = Compose.cell(true), controlSize = rung },
			})
		end)
		local live, switch = find(world.node, "Live"), find(world.node, "Switch")
		world.gui.SelectedObject = live
		for _, entry in { { "large", 56 }, { "compact", 36 }, { "regular", 44 } } do
			rung:set(entry[1])
			t.expect(live.Size.Y.Offset).toBe(entry[2])
			t.expect(live:GetAttribute("controlSize")).toBe(entry[1])
			t.expect(switch:GetAttribute("controlSize")).toBe(entry[1])
			t.expect(world.gui.SelectedObject).toBe(live)
		end
		rung:set("compact")
		look:set("emphasis")
		t.expect(live:HasTag("facet-accent")).toBe(true)
		rung:set(nil)
		look:set(nil)
		t.expect(live.Size.Y.Offset).toBe(44)
		t.expect(live:GetAttribute("controlSize")).toBe("regular")
		t.expect(live:GetAttribute("appearance")).toBe("standard")
		t.expect(live:HasTag("facet-accent")).toBe(false)
		t.expect(find(world.node, "Live")).toBe(live)
		t.expect(world.gui.SelectedObject).toBe(live)
		t.expect(action(world.root, "Activate") ~= nil).toBe(true)
		t.expect(builds).toBe(1)
		world.stop()
	end)

	t.it("refuses a readable corners source that turns into an illegal word", function()
		local corners = Compose.cell("pill")
		local world = setup(function(UI)
			return UI.Button "Corners" { label = "Corners", corners = corners }
		end)
		local corner = world.node:FindFirstChildWhichIsA("UICorner")
		t.expect(corner.CornerRadius.Scale).toBe(1)
		local ok, message = pcall(function()
			corners:set("round")
		end)
		t.expect(ok).toBe(false)
		t.expect(string.find(tostring(message), "corners must be pill or square", 1, true) ~= nil).toBe(true)
		world.stop()
		local failed, reason = pcall(function()
			setup(function(UI)
				return UI.Button "Bad" { label = "Bad", corners = Compose.cell("round") }
			end)
		end)
		t.expect(failed).toBe(false)
		t.expect(string.find(tostring(reason), "corners must be pill or square", 1, true) ~= nil).toBe(true)
	end)
end)
