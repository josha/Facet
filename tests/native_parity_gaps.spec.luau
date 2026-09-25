--!strict
local t = require("./lib/testkit")
local fs = require("@lune/fs")
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
	screen: any,
	stop: () -> (),
}

local helpers: { [string]: boolean } = {
	fill = true,
	badged = true,
	environment = true,
	worldAnchor = true,
	scrollTo = true,
	scrollToVisible = true,
}

local function world(build: (any, any, any) -> any, options: { [string]: any }?): World
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
	local config: { [string]: any } = {
		types = engine.types,
		guiService = gui,
		services = { GuiService = gui, UserInputService = input },
	}
	for key, value in (options or {}) :: { [string]: any } do
		config[key] = value
	end
	local UI = Facet.controls(runtime, config :: any)
	local Host = runtime.constructors
	local stop, screen = runtime.mount(function()
		return Host.ScreenGui({ build(UI, Host, engine) })
	end, engine.new("Folder"))
	return {
		engine = engine,
		runtime = runtime,
		UI = UI,
		Host = Host,
		gui = gui,
		input = input,
		screen = screen,
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

local function mountError(build: (any, any) -> any): string?
	local engine: any = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local gui = engine.new("GuiService")
	local UI =
		Facet.controls(runtime, { types = engine.types, guiService = gui, services = { GuiService = gui } } :: any)
	local Host = runtime.constructors
	local ok, message = pcall(function()
		local stop = runtime.mount(function()
			return Host.Frame({ build(UI, Host) })
		end, engine.new("ScreenGui"))
		stop()
	end)
	runtime:dispose()
	return if ok then nil else tostring(message)
end

local function records(count: number): { { id: number, label: string } }
	local values = {}
	for index = 1, count do
		values[index] = { id = index, label = `Row {index}` }
	end
	return values
end

local function minimalSpecs(Host: any): { [string]: () -> { [string]: any } }
	local function content()
		return Host.Frame({})
	end
	local items = {
		{
			id = "a",
			label = "A",
			onSelect = function() end,
		},
	}
	return {
		Screen = function()
			return {}
		end,
		VStack = function()
			return {}
		end,
		HStack = function()
			return {}
		end,
		ZStack = function()
			return {}
		end,
		ScrollView = function()
			return {}
		end,
		Grid = function()
			return { columns = 2 }
		end,
		Alert = function()
			return {
				isPresented = Compose.cell(false),
				title = "Title",
				message = "Message",
				actions = { { id = "ok", label = "OK", role = "default" } },
			}
		end,
		Dialog = function()
			return { isPresented = Compose.cell(false), closeButton = false, title = "Title" }
		end,
		Snackbar = function()
			return { isPresented = Compose.cell(false), message = "Saved", closeButton = false }
		end,
		Notice = function()
			return { message = "Saved" }
		end,
		NavBar = function()
			return { title = "Tracks" }
		end,
		Popover = function()
			return {
				isPresented = Compose.cell(false),
				source = { rect = { x = 0, y = 0, w = 10, h = 10 } },
				content = function()
					return Host.Frame({})
				end,
			}
		end,
		AsyncImage = function()
			return { image = "rbxassetid://1" }
		end,
		Avatar = function()
			return { name = "Ada" }
		end,
		AvatarGroup = function()
			return { items = { { id = "a", name = "Ada" } } }
		end,
		Badge = function()
			return { label = "New" }
		end,
		Button = function()
			return { label = "Go" }
		end,
		Callout = function()
			return {
				anchor = Host.Frame({}),
				content = content,
				onRetire = function() end,
			}
		end,
		Chip = function()
			return { label = "Chip", selected = Compose.cell(false) }
		end,
		CollapsibleView = function()
			return { expanded = Compose.cell(false), content = content }
		end,
		ColorPicker = function()
			return { value = Compose.cell(require("@lune/roblox").Color3.new(1, 0, 0)) }
		end,
		ComboBox = function()
			return {
				value = Compose.cell(""),
				text = Compose.cell(""),
				options = { { value = "a", label = "A" } },
				acceptCustom = function()
					return nil
				end,
			}
		end,
		DateTimePicker = function()
			return { value = Compose.cell(nil), onChange = function() end }
		end,
		DisclosureGroup = function()
			return { expanded = Compose.cell(false), content = content }
		end,
		Label = function()
			return { text = "Label" }
		end,
		LevelPicker = function()
			return { value = Compose.cell(1) }
		end,
		Menu = function()
			return { items = items }
		end,
		NavigationStack = function()
			return {
				path = Compose.cell({}),
				root = { title = "Root", content = content },
				destinations = {},
			}
		end,
		PageView = function()
			return { selection = Compose.cell("a"), pages = { { id = "a", content = content } } }
		end,
		Picker = function()
			return { selected = Compose.cell("a"), options = { { value = "a", label = "A" } } }
		end,
		ProgressView = function()
			return { value = 0.5 }
		end,
		RadialMenu = function()
			return { items = items }
		end,
		Rating = function()
			return { value = Compose.cell(1) }
		end,
		RowActions = function()
			return { content = content }
		end,
		Sheet = function()
			return {
				isPresented = Compose.cell(false),
				detent = Compose.cell("medium"),
				title = "Sheet",
				content = content,
			}
		end,
		ShortcutHint = function()
			return { keys = { { "Ctrl", "K" } } }
		end,
		Skeleton = function()
			return {}
		end,
		Slider = function()
			return { value = Compose.cell(0.5) }
		end,
		SplitButton = function()
			return { label = "Primary", onActivate = function() end, items = items }
		end,
		Stage = function()
			return {}
		end,
		ErrorBoundary = function()
			return { view = content, fallback = content }
		end,
		Pagination = function()
			return { page = Compose.cell(3), pageCount = 10, onChange = function() end }
		end,
		Card = function()
			return {
				image = "rbxassetid://1",
				title = "Card",
				onActivate = function() end,
				primaryAction = { label = "Play", onActivate = function() end },
			}
		end,
		Vote = function()
			return { value = Compose.cell("none"), onChange = function() end }
		end,
		StepIndicator = function()
			return {
				steps = { { id = "a", label = "A", navigable = true }, { id = "b", label = "B" } },
				current = "a",
				onSelect = function() end,
			}
		end,
		StatusIndicator = function()
			return { status = "info" }
		end,
		Stepper = function()
			return { value = Compose.cell(1), max = 5 }
		end,
		TabView = function()
			return {
				selection = Compose.cell("a"),
				tabs = { { id = "a", label = "A", content = content } },
			}
		end,
		Table = function()
			return {
				from = {},
				key = function(item)
					return item.id
				end,
				columns = {
					{
						id = "c",
						label = "C",
						value = function(item)
							return item.id
						end,
					},
				},
			}
		end,
		TextInput = function()
			return { value = Compose.cell("") }
		end,
		NumberInput = function()
			return { value = Compose.cell("1"), numericValue = Compose.cell(1) }
		end,
		Toggle = function()
			return { value = Compose.cell(false) }
		end,
		VirtualGrid = function()
			return { from = {}, render = content }
		end,
		VirtualList = function()
			return { from = {}, render = content }
		end,
	}
end

t.describe("native parity gaps", function()
	t.it("refuses an unknown lower-case option on every public constructor", function()
		local probe: any = engineLib.new()
		local names: { string } = {}
		for name in Facet.controls(Facet.Roblox.createRuntime(probe), { types = probe.types } :: any) do
			if not helpers[name] then
				table.insert(names, name :: string)
			end
		end
		table.sort(names)
		local published: { string } = {}
		for name in string.gmatch(fs.readFile("tools/public_surface.txt"), "controls%(runtime%)%.([%w_]+) : function") do
			if not helpers[name] then
				table.insert(published, name)
			end
		end
		table.sort(published)
		t.expect(table.concat(names, " ")).toBe(table.concat(published, " "))
		for _, name in names do
			local accepted = mountError(function(UI, Host)
				local spec = assert(minimalSpecs(Host)[name], `no minimal spec for {name}`)()
				local node = UI[name](spec)
				return if spec.anchor then Host.Frame({ Host.Frame({ spec.anchor }), node }) else node
			end)
			t.expect(accepted).toBeNil()
			local refused = mountError(function(UI, Host)
				local spec = minimalSpecs(Host)[name]()
				spec.definitelyNotAKey = true
				local node = UI[name](spec)
				return if spec.anchor then Host.Frame({ Host.Frame({ spec.anchor }), node }) else node
			end)
			t.expect(refused ~= nil and string.find(refused, "unknown option 'definitelyNotAKey'", 1, true) ~= nil)
				.toBe(true)
			local native = mountError(function(UI, Host)
				local spec = minimalSpecs(Host)[name]()
				spec.LayoutOrder = 3
				local node = UI[name](spec)
				return if spec.anchor then Host.Frame({ Host.Frame({ spec.anchor }), node }) else node
			end)
			t.expect(native).toBeNil()
		end
	end)

	t.it("names the control and the nearest option in authoring errors", function()
		local cases: { { any } } = {
			{
				"Facet UI.Button: unknown option 'lable'. Did you mean 'label'?",
				function(UI)
					return UI.Button({ lable = "Go" })
				end,
			},
			{
				"Facet UI.Label: unknown option 'zzzzzz'.",
				function(UI)
					return UI.Label({ text = "Go", zzzzzz = true })
				end,
			},
			{
				"Facet UI.Button: expected a property table, got number",
				function(UI)
					return UI.Button(42)
				end,
			},
			{
				"Facet UI.Menu: two items at one level share the id 'a'",
				function(UI)
					return UI.Menu({
						items = {
							{ id = "a", label = "A", onSelect = function() end },
							{ id = "a", label = "B", onSelect = function() end },
						},
					})
				end,
			},
			{
				"Facet UI.Picker: options must be an array of { value, label } entries",
				function(UI)
					return UI.Picker({ selected = Compose.cell("a") })
				end,
			},
		}
		table.insert(cases, {
			"Facet UI.Label: set the text one time. Use text, and remove label and Text.",
			function(UI)
				return UI.Label({ text = "a", label = "b" })
			end,
		})
		table.insert(cases, {
			"Facet UI.Label: set the text one time.",
			function(UI)
				return UI.Label({ text = "a", Text = "b" })
			end,
		})
		table.insert(cases, {
			"Sise is not a valid member of TextButton",
			function(UI)
				return UI.Button({ label = "Go", Sise = 1 })
			end,
		})
		for _, case in cases do
			local message = mountError(case[2])
			t.expect(message ~= nil and string.find(message, case[1], 1, true) ~= nil).toBe(true)
		end
		local unrelated = mountError(function(UI)
			return UI.Label({ text = "Go", zzzzzz = true })
		end)
		t.expect(unrelated ~= nil and string.find(unrelated, "Did you mean", 1, true) == nil).toBe(true)
	end)

	t.it("refuses malformed documented options with a named error", function()
		local function content(Host: any): () -> any
			return function()
				return Host.Frame({})
			end
		end
		local cases: { { any } } = {
			{
				"Picker options require unique values or ids",
				function(UI)
					return UI.Picker({
						selected = Compose.cell("a"),
						options = { { value = "a", label = "A" }, { value = "a", label = "B" } },
					})
				end,
			},
			{
				"Unknown Picker style",
				function(UI)
					return UI.Picker({
						selected = Compose.cell("a"),
						style = "wheel",
						options = { { value = "a", label = "A" } },
					})
				end,
			},
			{
				"Facet UI.Menu: two items at one level share the id 'a'",
				function(UI)
					return UI.Menu({
						items = {
							{ id = "a", label = "A", onSelect = function() end },
							{ id = "a", label = "B", onSelect = function() end },
						},
					})
				end,
			},
			{
				"cannot have both children and onSelect",
				function(UI)
					return UI.Menu({
						items = {
							{
								id = "a",
								label = "A",
								onSelect = function() end,
								children = { { id = "b", label = "B", onSelect = function() end } },
							},
						},
					})
				end,
			},
			{
				"Menu items require an action, submenu, or selection state",
				function(UI)
					return UI.Menu({ items = { { id = "a", label = "A" } } })
				end,
			},
			{
				"Picker.selected requires a writable Compose cell",
				function(UI)
					return UI.Picker({ selected = "a", options = { { value = "a", label = "A" } } })
				end,
			},
			{
				"TabView.selection requires a writable Compose cell",
				function(UI, Host)
					return UI.TabView({ selection = "a", tabs = { { id = "a", label = "A", content = content(Host) } } })
				end,
			},
			{
				"PageView requires entries",
				function(UI)
					return UI.PageView({ selection = Compose.cell("a"), pages = {} })
				end,
			},
			{
				"PageView entries require unique string ids",
				function(UI, Host)
					return UI.PageView({
						selection = Compose.cell("a"),
						pages = { { id = "a", content = content(Host) }, { id = "a", content = content(Host) } },
					})
				end,
			},
			{
				"Sheet.detent requires a writable Compose cell",
				function(UI, Host)
					return UI.Sheet({
						isPresented = Compose.cell(false),
						detent = "medium",
						title = "Sheet",
						content = content(Host),
					})
				end,
			},
			{
				"TabView entries require unique string ids",
				function(UI, Host)
					return UI.TabView({
						selection = Compose.cell("a"),
						tabs = {
							{ id = "a", label = "A", content = content(Host) },
							{ id = "a", label = "B", content = content(Host) },
						},
					})
				end,
			},
			{
				"TabView.selection must name an entry",
				function(UI, Host)
					return UI.TabView({
						selection = Compose.cell("missing"),
						tabs = { { id = "a", label = "A", content = content(Host) } },
					})
				end,
			},
			{
				"PageView.selection must name an entry",
				function(UI, Host)
					return UI.PageView({
						selection = Compose.cell("missing"),
						pages = { { id = "a", content = content(Host) } },
					})
				end,
			},
			{
				"snap must be none or item",
				function(UI, Host)
					return UI.VirtualList({ from = {}, render = content(Host), snap = "page" })
				end,
			},
			{
				"finite min must be below max",
				function(UI)
					return UI.Stepper({ value = Compose.cell(1), min = 5, max = 5 })
				end,
			},
			{
				"step must be positive",
				function(UI)
					return UI.Slider({ value = Compose.cell(0.5), step = 0 })
				end,
			},
			{
				"exactly one of fraction or height",
				function(UI, Host)
					return UI.Sheet({
						isPresented = Compose.cell(false),
						detent = Compose.cell("half"),
						detents = { { id = "half", fraction = 0.5, height = 100 } },
						title = "Sheet",
						content = content(Host),
					})
				end,
			},
			{
				"count must be a positive integer",
				function(UI)
					return UI.Rating({ value = Compose.cell(1), count = 2.5 })
				end,
			},
			{
				"invalid clearButtonMode",
				function(UI)
					return UI.TextInput({ value = Compose.cell(""), clearButtonMode = "sometimes" })
				end,
			},
			{
				"shape must be rect or circle",
				function(UI)
					return UI.Button({ label = "Go", shape = "star" })
				end,
			},
			{
				"corners must be pill or square",
				function(UI)
					return UI.Button({ label = "Go", corners = "round" })
				end,
			},
			{
				"segments require bar presentation",
				function(UI)
					return UI.ProgressView({ value = 0.5, presentation = "circular", segments = 4 })
				end,
			},
			{
				"supply either a constructor name or Name",
				function(UI)
					return UI.Button("First")({ label = "Go", Name = "Second" })
				end,
			},
		}
		for _, case in cases do
			local message = mountError(case[2])
			t.expect(message ~= nil and string.find(message, case[1], 1, true) ~= nil).toBe(true)
		end
	end)

	t.it("reports a failed alert body to the onError factory option and dismisses once", function()
		local presented, failures = Compose.cell(true), {}
		local w = world(function(UI)
			return UI.Alert("Broken")({
				isPresented = presented,
				title = "Broken",
				actions = { { id = "ok", label = "OK", role = "default" } },
				content = function()
					error("content exploded", 0)
				end,
			})
		end, {
			onError = function(failure)
				table.insert(failures, tostring(failure))
			end,
		})
		t.expect(#failures).toBe(1)
		t.expect(string.find(failures[1], "content exploded", 1, true) ~= nil).toBe(true)
		t.expect(presented:peek()).toBe(false)
		t.expect(find(w.screen, "Broken"):GetAttribute("FacetError") ~= nil).toBe(true)
		t.expect(find(w.screen, "AlertPanel")).toBeNil()
		w.stop()
		t.expect(#failures).toBe(1)
	end)

	t.it("keeps at most the documented number of pooled row hosts", function()
		for _, limit in { 32, 4 } do
			local source = Compose.cell(records(100))
			local w = world(function(UI, Host)
				return UI.VirtualList({
					from = source,
					key = function(item)
						return item.id
					end,
					itemSize = 10,
					overscan = 0,
					maxRetained = if limit == 32 then nil else limit,
					render = function()
						return Host.Frame({ Name = "Cell" })
					end,
				})
			end)
			local list = w.screen:FindFirstChildWhichIsA("ScrollingFrame")
			list.AbsoluteWindowSize = w.engine.types.Vector2.new(100, 600)
			t.expect(#list:FindFirstChild("Items"):GetChildren()).toBe(60)
			local function parked()
				local count = 0
				for _, node in w.engine.made do
					if
						node.ClassName == "Frame"
						and node.Name ~= "Cell"
						and node.Parent == nil
						and not node:isDestroyed()
					then
						count += 1
					end
				end
				return count
			end
			source:set({})
			t.expect(#list:FindFirstChild("Items"):GetChildren()).toBe(0)
			t.expect(parked()).toBe(limit)
			w.stop()
			t.expect(parked()).toBe(0)
		end
	end)

	t.it("fills the controls table with indexOfKey, placementOf and offsetOf", function()
		local source, controls = Compose.cell(records(100)), {} :: { [string]: any }
		local w = world(function(UI, Host)
			return UI.VirtualList({
				from = source,
				key = function(item)
					return item.id
				end,
				itemSize = 10,
				gap = 2,
				controls = controls,
				render = function()
					return Host.Frame({})
				end,
			})
		end)
		local list = w.screen:FindFirstChildWhichIsA("ScrollingFrame")
		list.AbsoluteWindowSize = w.engine.types.Vector2.new(100, 100)
		t.expect(controls.indexOfKey(5)).toBe(5)
		t.expect(controls.indexOfKey(1000)).toBeNil()
		t.expect(controls.placementOf(5).offset).toBe(48)
		t.expect(controls.offsetOf(5, "start")).toBe(48)
		t.expect(controls.offsetOf(5, "end", 30)).toBe(28)
		t.expect(controls.offsetOf(5, "center", 30)).toBe(38)
		t.expect(controls.offsetOf(100, "start", 100)).toBe(1098)
		local reversed = records(100)
		table.sort(reversed, function(a: any, b: any)
			return a.id > b.id
		end)
		source:set(reversed)
		t.expect(controls.indexOfKey(1)).toBe(100)
		t.expect(controls.indexOfKey(100)).toBe(1)
		w.stop()
	end)

	t.it("delivers onActivate with the item and key and skips disabled rows", function()
		local activated: { any } = {}
		local w = world(function(UI, Host)
			return UI.VirtualList({
				from = records(10),
				key = function(item)
					return `k{item.id}`
				end,
				itemSize = 20,
				disabled = function(item)
					return item.id == 2
				end,
				onActivate = function(item, key)
					table.insert(activated, { item = item, key = key })
				end,
				render = function()
					return Host.Frame({})
				end,
			})
		end)
		local list = w.screen:FindFirstChildWhichIsA("ScrollingFrame")
		list.AbsoluteWindowSize = w.engine.types.Vector2.new(100, 200)
		find(find(list, "k3"), "RowHit").Activated.fire()
		t.expect(#activated).toBe(1)
		t.expect(activated[1].key).toBe("k3")
		t.expect(activated[1].item.id).toBe(3)
		local blocked = find(find(list, "k2"), "RowHit")
		t.expect(blocked.Interactable).toBe(false)
		blocked.Activated.fire()
		t.expect(#activated).toBe(1)
		w.stop()
	end)

	t.it("shows button help when gamepad selection rests on the button and hides it on deselection", function()
		local w = world(function(UI, Host)
			return Host.Frame("Screen")({
				UI.Button("Plus")({ label = "+", help = "Posts this avatar" }),
			})
		end)
		local Enum = w.engine.types.Enum
		local plus = find(w.screen, "Plus")
		w.input.PreferredInput = Enum.PreferredInput.Gamepad
		w.gui.SelectedObject = plus
		w.engine.heartbeat.fire(0.3)
		t.expect(find(w.screen, "HelpText")).toBeNil()
		w.engine.heartbeat.fire(0.2)
		t.expect(find(w.screen, "HelpText").Text).toBe("Posts this avatar")
		w.gui.SelectedObject = nil
		t.expect(find(w.screen, "HelpText")).toBeNil()
		w.input.PreferredInput = Enum.PreferredInput.Touch
		w.gui.SelectedObject = plus
		w.engine.heartbeat.fire(0.6)
		t.expect(find(w.screen, "HelpText")).toBeNil()
		w.stop()
	end)

	t.it("disables a stepper direction at its bound and refuses the step", function()
		local value, changes = Compose.cell(0), 0
		local w = world(function(UI)
			return UI.Stepper({
				value = value,
				min = 0,
				max = 2,
				onChange = function(nextValue)
					changes += 1
					value:set(nextValue)
				end,
			})
		end)
		local decrease, increase = find(w.screen, "Decrease"), find(w.screen, "Increase")
		t.expect(decrease.Interactable).toBe(false)
		t.expect(increase.Interactable).toBe(true)
		decrease.Activated.fire()
		t.expect(value:peek()).toBe(0)
		increase.Activated.fire()
		increase.Activated.fire()
		t.expect(value:peek()).toBe(2)
		t.expect(increase.Interactable).toBe(false)
		t.expect(decrease.Interactable).toBe(true)
		increase.Activated.fire()
		t.expect(value:peek()).toBe(2)
		t.expect(changes).toBe(2)
		w.stop()
	end)

	t.it("wraps rating activation to zero only when allowZero and ignores a disabled rating", function()
		local open, closed, blocked = Compose.cell(5), Compose.cell(5), Compose.cell(2)
		local w = world(function(UI, Host)
			return Host.Frame({
				UI.Rating("Open")({ value = open }),
				UI.Rating("Closed")({ value = closed, allowZero = false }),
				UI.Rating("Blocked")({ value = blocked, enabled = false }),
			})
		end)
		find(w.screen, "Open").Activated.fire()
		t.expect(open:peek()).toBe(0)
		find(w.screen, "Open").Activated.fire()
		t.expect(open:peek()).toBe(1)
		find(w.screen, "Closed").Activated.fire()
		t.expect(closed:peek()).toBe(1)
		local disabled = find(w.screen, "Blocked")
		t.expect(disabled.Interactable).toBe(false)
		t.expect(disabled.Selectable).toBe(false)
		disabled.Activated.fire()
		t.expect(blocked:peek()).toBe(2)
		w.stop()
	end)

	t.it("tags a disabled button for the theme disabled rule and lets a package retune it", function()
		local enabled = Compose.cell(false)
		local w = world(function(UI)
			return UI.Button("Go")({ label = "Go", enabled = enabled })
		end)
		local button = find(w.screen, "Go")
		t.expect(button:HasTag("facet-disabled")).toBe(true)
		t.expect(button.Interactable).toBe(false)
		enabled:set(true)
		t.expect(button:HasTag("facet-disabled")).toBe(false)
		t.expect(button.Interactable).toBe(true)
		w.stop()
		local engine: any = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local function disabledRule(package: any): number?
			local stop, sheet: any = runtime.mount(function()
				return Facet.themes.createStyleSheet(runtime, package, { types = engine.types })
			end, engine.new("Folder"))
			local found
			for _, rule in sheet:GetChildren() do
				if rule.Selector == ".facet-disabled" then
					found = rule:GetProperties().TextTransparency
				end
			end
			stop()
			return found
		end
		local neutral = Facet.themes.neutralPackage()
		t.expect(disabledRule(neutral)).toBe((neutral.style.themes[1].extra :: any).disabledContentOpacity)
		local custom = Facet.themes.neutralPackage()
		for _, palette in custom.style.themes do
			(palette.extra :: any).disabledContentOpacity = 0.6
		end
		local package, report = Facet.themes.define(custom :: any)
		t.expect(report.ok).toBe(true)
		t.expect(disabledRule(package)).toBe(0.6)
		runtime:dispose()
	end)

	t.it(
		"estimates table rows from a regular control height that falls back when the theme metric is missing or not finite",
		function()
			local empty = Facet.themes.neutralPackage()
			empty.metrics.controlSizes = {} :: any
			local nan = Facet.themes.neutralPackage()
			nan.metrics.controlSizes.regular.height = 0 / 0
			local huge = Facet.themes.neutralPackage()
			huge.metrics.controlSizes.regular.height = math.huge
			local short = Facet.themes.neutralPackage()
			short.metrics.controlSizes.regular.height = 30
			for _, case in
				{
					{ theme = empty, row = 44 },
					{ theme = nan, row = 44 },
					{ theme = huge, row = 44 },
					{ theme = short, row = 40 },
				}
			do
				local controls = {} :: { [string]: any }
				local w = world(function(UI)
					return UI.Table({
						from = records(3),
						key = function(item)
							return item.id
						end,
						controls = controls,
						columns = { { id = "label", width = 100 } },
					})
				end, { theme = case.theme })
				local body = find(w.screen, "Body")
				body.AbsoluteWindowSize = w.engine.types.Vector2.new(300, 300)
				t.expect(controls.placementOf(2).offset).toBe(case.row)
				t.expect(controls.placementOf(3).offset).toBe(case.row * 2)
				w.stop()
			end
		end
	)

	t.it("refuses picker selection and disclosure toggling while disabled and resumes when enabled", function()
		local selected, changes = Compose.cell("a"), 0
		local pickerEnabled, groupEnabled = Compose.cell(false), Compose.cell(false)
		local expanded, toggles = Compose.cell(false), 0
		local w = world(function(UI, Host)
			return Host.Frame({
				UI.Picker({
					selected = selected,
					style = "segmented",
					enabled = pickerEnabled,
					options = { { value = "a", label = "A" }, { value = "b", label = "B" } },
					onChange = function()
						changes += 1
					end,
				}),
				UI.DisclosureGroup({
					label = "Advanced",
					expanded = expanded,
					enabled = groupEnabled,
					onToggle = function()
						toggles += 1
					end,
					content = function()
						return Host.Frame("Body")({})
					end,
				}),
			})
		end)
		local picker = find(w.screen, "Picker")
		local option = find(picker, "b")
		t.expect(option.Interactable).toBe(false)
		option.Activated.fire()
		t.expect(selected:peek()).toBe("a")
		t.expect(changes).toBe(0)
		local header = find(find(w.screen, "DisclosureGroup"), "Header")
		t.expect(header.Interactable).toBe(false)
		t.expect(header.Selectable).toBe(false)
		header.Activated.fire()
		t.expect(expanded:peek()).toBe(false)
		t.expect(toggles).toBe(0)
		t.expect(find(w.screen, "Body")).toBe(nil)
		pickerEnabled:set(true)
		groupEnabled:set(true)
		t.expect(find(picker, "b").Interactable).toBe(true)
		find(picker, "b").Activated.fire()
		t.expect(selected:peek()).toBe("b")
		t.expect(changes).toBe(1)
		t.expect(header.Interactable).toBe(true)
		header.Activated.fire()
		t.expect(expanded:peek()).toBe(true)
		t.expect(toggles).toBe(1)
		t.expect(find(w.screen, "Body") ~= nil).toBe(true)
		w.stop()
	end)

	t.it("keeps the value when custom combo box validation unmounts the control", function()
		local value, text, changes = Compose.cell("a"), Compose.cell("Alpha"), 0
		local stopRef: { stop: () -> () } = {
			stop = function() end,
		}
		local failure: string? = nil
		local w = world(function(UI)
			return UI.ComboBox({
				value = value,
				text = text,
				commitOnFocusLost = true,
				options = { { value = "a", label = "Alpha" } },
				acceptCustom = function()
					stopRef.stop()
					return true
				end,
				onChange = function()
					changes += 1
				end,
			})
		end)
		stopRef.stop = w.stop
		local editor = find(w.screen, "Editor")
		local ok, message = pcall(function()
			editor:CaptureFocus()
			editor.Text = "Custom"
			editor:ReleaseFocus(true)
		end)
		if not ok then
			failure = tostring(message)
		end
		t.expect(failure).toBe(nil)
		t.expect(value:peek()).toBe("a")
		t.expect(changes).toBe(0)
		t.expect(editor.Parent).toBe(nil)
	end)

	t.it("keeps the changelog release heading equal to Facet.VERSION", function()
		local changelog = fs.readFile("CHANGELOG.md")
		local heading = string.match(changelog, "\n## (%d+%.%d+%.%d+)")
		t.expect(heading).toBe(Facet.VERSION)
		t.expect(string.match(Facet.VERSION, "^%d+%.%d+%.%d+$") ~= nil).toBe(true)
	end)
end)
