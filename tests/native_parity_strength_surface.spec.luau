--!strict
local t = require("./lib/testkit")
local fs = require("@lune/fs")
local process = require("@lune/process")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local Graph = require("../src/vendor/compose/core/reactive/graph")
local gallery = require("../examples/gallery/client/screen")
local themePackages = require("../tools/lune/theme_packages")
local Compose = Facet.Compose
local themes = Facet.themes

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

local function world(options: { [string]: any }?): (any, any, any, any)
	local engine: any = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local gui = engine.new("GuiService")
	local input = engine.new("UserInputService")
	input.GetFocusedTextBox = function()
		return nil
	end
	local config: { [string]: any } =
		{ types = engine.types, reducedMotion = true, services = { GuiService = gui, UserInputService = input } }
	for key, value in (options or {}) :: { [string]: any } do
		config[key] = value
	end
	local UI = Facet.controls(runtime, config :: any)
	return engine, runtime, UI, gui
end

local function registrations(path: string, found: { [string]: string })
	for _, name in fs.readDir(path) do
		local full = path .. "/" .. name
		if fs.isDir(full) then
			registrations(full, found)
		elseif string.match(name, "%.luau$") then
			for constructor in string.gmatch(fs.readFile(full), "UI%.([%a_][%w_]*)%s*=") do
				assert(not found[constructor], "Duplicate control registration: " .. constructor)
				found[constructor] = full
			end
		end
	end
end

local CONTROL_SECTIONS = {
	"## Layout",
	"## Actions and input",
	"## Menus and navigation",
	"## Presented controls",
	"## Collections",
	"## Media and status",
	"## Adaptive environment",
}

local function documentedControls(reference: string): { [string]: boolean }
	local documented: { [string]: boolean } = {}
	local section: string? = nil
	for line in string.gmatch(reference .. "\n", "([^\n]*)\n") do
		if string.sub(line, 1, 3) == "## " then
			section = if table.find(CONTROL_SECTIONS, line) then line else nil
		elseif section and string.sub(line, 1, 4) == "### " then
			local heading = string.sub(line, 5)
			for _, part in string.split((string.gsub(heading, " and ", ",")), ",") do
				local name = string.match(part, "^%s*([%a][%w]*)%s*$")
				if name then
					documented[name] = true
				end
			end
		elseif section == "## Media and status" then
			local name = string.match(line, "^| `([%u][%w]*)` |")
			if name then
				documented[name] = true
			end
		end
	end
	return documented
end

type RegistrationInput = {
	registered: { [string]: string },
	exported: { [string]: unknown },
	documented: { [string]: boolean },
}

local function registrationProblems(input: RegistrationInput): { string }
	local problems: { string } = {}
	for name in input.registered do
		if type(input.exported[name]) ~= "function" then
			table.insert(problems, `registered control {name} is not exported`)
		end
		if not input.documented[name] then
			table.insert(problems, `registered control {name} has no api.md entry`)
		end
	end
	for name in input.exported do
		if not input.registered[name] then
			table.insert(problems, `exported control {name} has no registration`)
		end
	end
	for name in input.documented do
		if input.exported[name] == nil then
			table.insert(problems, `api.md documents {name}, which is not exported`)
		end
	end
	table.sort(problems)
	return problems
end

local function liveRegistration(): RegistrationInput
	local engine = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local UI = Facet.controls(runtime, { types = engine.types })
	local registered: { [string]: string } = {}
	registrations("src/ui", registered)
	local exported: { [string]: unknown } = {}
	for name, constructor in UI :: any do
		exported[name] = constructor
	end
	runtime:dispose()
	return {
		registered = registered,
		exported = exported,
		documented = documentedControls(fs.readFile("docs/reference/api.md")),
	}
end

local function mentions(problems: { string }, needle: string): number
	local count = 0
	for _, problem in problems do
		if string.find(problem, needle, 1, true) then
			count += 1
		end
	end
	return count
end

t.describe("public surface registration", function()
	t.it("the live registration, exports and api.md control entries agree in every direction", function()
		local live = liveRegistration()
		local problems = registrationProblems(live)
		if #problems > 0 then
			error("registration problems:\n  " .. table.concat(problems, "\n  "))
		end
		local count = 0
		for _ in live.documented do
			count += 1
		end
		t.expect(count >= 30).toBe(true)
		t.expect(live.documented.Button).toBe(true)
		t.expect(live.documented.VirtualGrid).toBe(true)
		t.expect(live.documented.Stage).toBe(true)
	end)

	t.it("reports a registered control file with no export or documentation", function()
		local live = liveRegistration()
		local registered = table.clone(live.registered)
		for constructor in string.gmatch("UI.GhostControl = ctx.construct(function() end)", "UI%.([%a_][%w_]*)%s*=") do
			registered[constructor] = "src/ui/ghost_control.luau"
		end
		local problems = registrationProblems({
			registered = registered,
			exported = live.exported,
			documented = live.documented,
		})
		t.expect(mentions(problems, "registered control GhostControl is not exported")).toBe(1)
		t.expect(mentions(problems, "registered control GhostControl has no api.md entry")).toBe(1)
		t.expect(#problems).toBe(2)
	end)

	t.it("reports an undocumented export and a documented control that is not exported", function()
		local live = liveRegistration()
		local exported = table.clone(live.exported)
		exported.GhostExport = function() end
		local undocumented = registrationProblems({
			registered = live.registered,
			exported = exported,
			documented = live.documented,
		})
		t.expect(mentions(undocumented, "GhostExport")).toBe(1)
		local reference = fs.readFile("docs/reference/api.md")
		local ghostDoc =
			string.gsub(reference, "### Toggle\n", "### Toggle\n\n### ImaginaryControl and PhantomSwitch\n", 1)
		local documented = documentedControls(ghostDoc)
		t.expect(documented.ImaginaryControl).toBe(true)
		t.expect(documented.PhantomSwitch).toBe(true)
		local ghosts = registrationProblems({
			registered = live.registered,
			exported = live.exported,
			documented = documented,
		})
		t.expect(mentions(ghosts, "api.md documents ImaginaryControl, which is not exported")).toBe(1)
		t.expect(mentions(ghosts, "api.md documents PhantomSwitch, which is not exported")).toBe(1)
		t.expect(#ghosts).toBe(2)
		local tableGhost = string.gsub(reference, "| `Stage` |", "| `Hologram` | A ghost row. |\n| `Stage` |", 1)
		t.expect(mentions(
			registrationProblems({
				registered = live.registered,
				exported = live.exported,
				documented = documentedControls(tableGhost),
			}),
			"Hologram"
		)).toBe(1)
	end)

	t.it("the public entry point table matches the frozen Facet exports exactly", function()
		local reference = fs.readFile("docs/reference/api.md")
		local section = assert(string.match(reference, "## Public entry points\n(.-)\n### "))
		local documented: { [string]: boolean } = {}
		for name in string.gmatch(section, "\n| `([%a_][%w_]*)[%(`]") do
			documented[name] = true
		end
		for name in Facet :: any do
			t.expect(documented[name]).toBe(true)
		end
		for name in documented do
			t.expect((Facet :: any)[name] ~= nil).toBe(true)
		end
		t.expect(table.isfrozen(Facet)).toBe(true)
	end)

	t.it("every registered control has a typed constructor field, an exported spec type and a witness", function()
		local registered: { [string]: string } = {}
		registrations("src/ui", registered)
		local controlTypes = fs.readFile("src/ui/control_types.luau")
		local entry = fs.readFile("src/init.luau")
		local layoutTypes = fs.readFile("src/ui/layout_types.luau")
		local witnesses = ""
		for _, name in fs.readDir("tests/types") do
			if string.match(name, "_witness%.luau$") then
				witnesses ..= fs.readFile("tests/types/" .. name)
			end
		end
		local shared = {
			VirtualList = "CollectionSpec",
			VirtualGrid = "CollectionSpec",
			VStack = "StackProps",
			HStack = "StackProps",
			environment = "Environment",
			worldAnchor = "WorldAnchor",
			scrollTo = "ScrollOptions",
			scrollToVisible = "ScrollOptions",
		}
		local signatures = { fill = "fill: (weight: number?) -> UIFlexItem" }
		local count = 0
		for name in registered do
			count += 1
			t.expect(string.find(controlTypes, `\n\t{name}: typeof(`, 1, true) ~= nil).toBe(true)
			local exported = (signatures[name] ~= nil and string.find(layoutTypes, signatures[name], 1, true) ~= nil)
				or string.find(entry, `export type {name}Props`, 1, true) ~= nil
				or string.find(entry, `export type {name}Spec`, 1, true) ~= nil
				or (shared[name] ~= nil and string.find(entry, `export type {shared[name]}`, 1, true) ~= nil)
				or (
					name == "badged"
					and string.find(fs.readFile("src/ui/content_types.luau"), "export type Badged =", 1, true) ~= nil
					and string.find(entry, "export type BadgeValue", 1, true) ~= nil
				)
			if not exported then
				error(`{name} has no exported Props or Spec type in src/init.luau`)
			end
			if not string.find(witnesses, `UI.{name}`, 1, true) then
				error(`{name} has no public type witness in tests/types`)
			end
		end
		t.expect(count >= 30).toBe(true)
		t.expect(string.find(controlTypes, ": any", 1, true)).toBeNil()
	end)

	t.it("requiring the entry point touches no Roblox service or global", function()
		local dir = "artifacts/verify/probe"
		fs.writeDir(dir)
		local script = dir .. "/require_entry.luau"
		fs.writeFile(
			script,
			table.concat({
				"local touched = {}",
				"local function trap(label)",
				"\treturn setmetatable({}, { __index = function(_, key)",
				"\t\ttable.insert(touched, label .. '.' .. tostring(key))",
				"\t\terror('touched ' .. label)",
				"\tend })",
				"end",
				"local env = getfenv(1)",
				"env.game = trap('game')",
				"env.workspace = trap('workspace')",
				"env.script = trap('script')",
				"env.plugin = trap('plugin')",
				"local ok, facet = pcall(require, '../../../src')",
				"print(if ok then 'loaded ' .. facet.VERSION else 'failed ' .. tostring(facet))",
				"print('touched ' .. #touched .. ' ' .. table.concat(touched, ','))",
			}, "\n")
		)
		local result = process.exec("lune", { "run", script })
		fs.removeFile(script)
		t.expect(result.ok).toBe(true)
		t.expect(string.find(result.stdout, "loaded " .. Facet.VERSION, 1, true) ~= nil).toBe(true)
		t.expect(string.find(result.stdout, "touched 0 ", 1, true) ~= nil).toBe(true)
	end)

	t.it("loads headless and drives a public slice that mounts, binds, activates and tears down", function()
		local changelog = fs.readFile("CHANGELOG.md")
		local newest = string.match(changelog, "\n## %[?(%d+%.%d+%.%d+)")
		t.expect(newest).toBe(Facet.VERSION)
		t.expect((Facet :: any).new).toBeNil()
		local engine, runtime, UI = world()
		local root = engine.new("ScreenGui")
		local baseline = engine.census()
		local label, taps, activated = Compose.cell("Ready"), Compose.cell(0), 0
		local button, text
		local stop, frame = runtime.mount(function()
			button = UI.Button "Go" {
				label = label,
				onActivate = function()
					activated += 1
					taps:update(function(value: number)
						return value + 1
					end)
				end,
			}
			text = UI.Label "Count" {
				text = function(use: Facet.Use)
					return `Taps {use(taps)}`
				end,
			}
			return runtime.constructors.Frame({ button, text })
		end, root)
		t.expect(frame.Parent).toBe(root)
		t.expect(button.Parent).toBe(frame)
		t.expect(button.Text).toBe("Ready")
		t.expect(text.Text).toBe("Taps 0")
		label:set("Go now")
		t.expect(button.Text).toBe("Go now")
		button.Activated.fire()
		t.expect(activated).toBe(1)
		t.expect(text.Text).toBe("Taps 1")
		stop()
		t.expect(button:isDestroyed()).toBe(true)
		t.expect(#root:GetChildren()).toBe(0)
		label:set("After")
		t.expect(button.Text).toBe("Go now")
		local after = engine.census()
		t.expect(after.live).toBe(baseline.live)
		t.expect(after.connections).toBe(baseline.connections)
		runtime:dispose()
	end)
end)

t.describe("component lifetime", function()
	t.it("mounts a component once, updates only its bindings and releases its cleanup and nodes", function()
		local engine, runtime, UI = world()
		local root = engine.new("ScreenGui")
		local baseline = engine.census()
		local setups, cleaned, count = 0, 0, Compose.cell(0)
		local node
		local function Counter()
			setups += 1
			Compose.cleanup(function()
				cleaned += 1
			end)
			node = UI.Label "Count" {
				text = function(use: Facet.Use)
					return `Count {use(count)}`
				end,
			}
			return node
		end
		local stop = runtime.mount(function()
			return runtime.constructors.Frame({ Counter() })
		end, root)
		local made = #engine.made
		t.expect(node.Text).toBe("Count 0")
		count:set(2)
		t.expect(find(root, "Count")).toBe(node)
		t.expect(node.Text).toBe("Count 2")
		t.expect(setups).toBe(1)
		t.expect(#engine.made).toBe(made)
		stop()
		t.expect(cleaned).toBe(1)
		t.expect(#root:GetChildren()).toBe(0)
		local after = engine.census()
		t.expect(after.live).toBe(baseline.live)
		t.expect(after.connections).toBe(baseline.connections)
		runtime:dispose()
	end)

	t.it("show builds its branch on demand and releases it when the condition clears", function()
		local engine, runtime, UI = world()
		local root = engine.new("ScreenGui")
		local expanded, live = Compose.cell(false), 0
		local stop, body = runtime.mount(function()
			return runtime.constructors.Frame "Body" {
				UI.Label "Title" { text = "Title" },
				Compose.show(expanded, function()
					live += 1
					Compose.cleanup(function()
						live -= 1
					end)
					return UI.Label "Details" { text = "Details" }
				end),
			}
		end, root)
		local closed = engine.census()
		t.expect(find(body, "Details")).toBeNil()
		expanded:set(true)
		local details = find(body, "Details")
		t.expect(details ~= nil).toBe(true)
		t.expect(live).toBe(1)
		expanded:set(false)
		t.expect(find(body, "Details")).toBeNil()
		t.expect(details:isDestroyed()).toBe(true)
		t.expect(live).toBe(0)
		local after = engine.census()
		t.expect(after.live).toBe(closed.live)
		t.expect(after.connections).toBe(closed.connections)
		stop()
		runtime:dispose()
	end)

	t.it("a remount builds fresh component state", function()
		local engine, runtime, UI = world()
		local root = engine.new("ScreenGui")
		local shown, setups = Compose.cell(true), 0
		local function Counter()
			setups += 1
			local count = Compose.cell(0)
			return UI.Button "Bump" {
				label = function(use: Facet.Use)
					return `n {use(count)}`
				end,
				onActivate = function()
					count:set(count:peek() + 1)
				end,
			}
		end
		local stop, body = runtime.mount(function()
			return runtime.constructors.Frame "Body" { Compose.show(shown, Counter) }
		end, root)
		local first = find(body, "Bump")
		t.expect(first.Text).toBe("n 0")
		first.Activated.fire()
		t.expect(first.Text).toBe("n 1")
		shown:set(false)
		t.expect(find(body, "Bump")).toBeNil()
		t.expect(first:isDestroyed()).toBe(true)
		shown:set(true)
		local second = find(body, "Bump")
		t.expect(setups).toBe(2)
		t.expect(second ~= first).toBe(true)
		t.expect(second.Text).toBe("n 0")
		stop()
		runtime:dispose()
	end)

	t.it("a watch in a nested component stops when that component unmounts and the surface stays", function()
		local engine, runtime, UI = world()
		local root = engine.new("ScreenGui")
		local shown, source = Compose.cell(true), Compose.cell("a")
		local seen: { string } = {}
		local stop, body = runtime.mount(function()
			return runtime.constructors.Frame "Body" {
				Compose.show(shown, function()
					Compose.watch(function(use)
						table.insert(seen, use(source))
					end)
					return UI.Label "Details" { text = "Details" }
				end),
			}
		end, root)
		source:set("b")
		t.expect(table.concat(seen, ",")).toBe("a,b")
		shown:set(false)
		source:set("c")
		t.expect(table.concat(seen, ",")).toBe("a,b")
		t.expect(body.Parent).toBe(root)
		t.expect(body:isDestroyed()).toBe(false)
		t.expect(Graph.subscriberCount(source :: any)).toBe(0)
		stop()
		runtime:dispose()
	end)

	t.it("a watch stopped by hand stays stopped, a second stop is safe and the surface still closes", function()
		local engine, runtime, UI = world()
		local root = engine.new("ScreenGui")
		local baseline = engine.census()
		local source, calls = Compose.cell(0), 0
		local unwatch: () -> () = function() end
		local stop = runtime.mount(function()
			unwatch = Compose.watch(function(use)
				use(source)
				calls += 1
			end)
			return UI.Label "Label" { text = "Label" }
		end, root)
		source:set(1)
		t.expect(calls).toBe(2)
		unwatch()
		unwatch()
		source:set(2)
		t.expect(calls).toBe(2)
		t.expect(Graph.subscriberCount(source :: any)).toBe(0)
		stop()
		t.expect(#root:GetChildren()).toBe(0)
		local after = engine.census()
		t.expect(after.live).toBe(baseline.live)
		t.expect(after.connections).toBe(baseline.connections)
		runtime:dispose()
	end)
end)

t.describe("reactive recovery", function()
	t.it("an effect that disposes itself during its run is not subscribed again", function()
		local engine, runtime = world()
		local a, runs = Compose.cell(1), 0
		local unsubscribe: (() -> ())? = nil
		local stop = runtime.mount(function()
			unsubscribe = Compose.watch(function(use)
				runs += 1
				use(a)
				if runs >= 2 and unsubscribe ~= nil then
					unsubscribe()
				end
			end)
			return runtime.constructors.Frame({})
		end, engine.new("ScreenGui"))
		t.expect(runs).toBe(1)
		t.expect(Graph.subscriberCount(a :: any)).toBe(1)
		a:set(2)
		t.expect(runs).toBe(2)
		t.expect(Graph.subscriberCount(a :: any)).toBe(0)
		a:set(3)
		t.expect(runs).toBe(2)
		t.expect(Graph.subscriberCount(a :: any)).toBe(0)
		stop()
		runtime:dispose()
	end)

	t.it("an effect whose owner disposes during the run is not subscribed again", function()
		local engine, runtime = world()
		local a, runs, armed = Compose.cell(1), 0, false
		local scope: any
		local stop = runtime.mount(function()
			scope = Compose.currentOwner().createChild()
			scope.watch(function(use)
				runs += 1
				use(a)
				if armed then
					scope.dispose()
				end
			end)
			return runtime.constructors.Frame({})
		end, engine.new("ScreenGui"))
		armed = true
		a:set(2)
		t.expect(runs).toBe(2)
		t.expect(scope.isDisposed()).toBe(true)
		t.expect(Graph.subscriberCount(a :: any)).toBe(0)
		a:set(3)
		t.expect(runs).toBe(2)
		stop()
		runtime:dispose()
	end)

	t.it("transaction reads stay fresh and unrelated writes replay no effect", function()
		local engine, runtime = world()
		local left, right = Compose.cell(1), Compose.cell(10)
		local chooseLeft, unrelated = Compose.cell(true), Compose.cell(0)
		local selected = Compose.formula(function(use)
			return if use(chooseLeft) then use(left) else use(right)
		end)
		local effects: { number } = {}
		local stop = runtime.mount(function()
			Compose.watch(function(use)
				table.insert(effects, use(selected))
			end)
			return runtime.constructors.Frame({})
		end, engine.new("ScreenGui"))
		runtime:batch(function()
			left:set(2)
			t.expect(selected:peek()).toBe(2)
			left:set(3)
			t.expect(selected:peek()).toBe(3)
			chooseLeft:set(false)
			t.expect(selected:peek()).toBe(10)
			right:set(11)
			t.expect(selected:peek()).toBe(11)
		end)
		unrelated:set(1)
		left:set(99)
		t.expect(table.concat(effects, ",")).toBe("1,11")
		right:set(12)
		unrelated:set(2)
		t.expect(table.concat(effects, ",")).toBe("1,11,12")
		stop()
		runtime:dispose()
	end)

	t.it("a Label follows a bare title cell and a function title", function()
		local engine, runtime, UI = world()
		local title = Compose.cell("First")
		local bare, derived
		local stop = runtime.mount(function()
			bare = UI.Label "Bare" { text = title }
			derived = UI.Label "Derived" {
				text = function(use: Facet.Use)
					return string.upper(use(title))
				end,
			}
			return runtime.constructors.Frame({ bare, derived })
		end, engine.new("ScreenGui"))
		t.expect(bare.Text).toBe("First")
		t.expect(derived.Text).toBe("FIRST")
		local made = #engine.made
		title:set("Second")
		t.expect(bare.Text).toBe("Second")
		t.expect(derived.Text).toBe("SECOND")
		title:set("")
		t.expect(bare.Text).toBe("")
		t.expect(#engine.made).toBe(made)
		stop()
		title:set("Gone")
		t.expect(bare.Text).toBe("")
		runtime:dispose()
	end)

	t.it("a picker selection change keeps its options and makes no native node", function()
		local engine, runtime, UI = world()
		local selected = Compose.cell("one")
		local stop, picker = runtime.mount(function()
			return UI.Picker "Segments" {
				selected = selected,
				style = "segmented",
				options = {
					{ value = "one", label = "One" },
					{ value = "two", label = "Two" },
					{ value = "three", label = "Three" },
				},
			}
		end, engine.new("ScreenGui"))
		local options = { find(picker, "one"), find(picker, "two"), find(picker, "three") }
		for _, option in options do
			t.expect(option ~= nil).toBe(true)
		end
		local made = #engine.made
		options[2].Activated.fire()
		t.expect(selected:peek()).toBe("two")
		selected:set("three")
		selected:set("one")
		t.expect(#engine.made).toBe(made)
		t.expect(find(picker, "one")).toBe(options[1])
		t.expect(find(picker, "two")).toBe(options[2])
		t.expect(find(picker, "three")).toBe(options[3])
		for _, option in options do
			t.expect(option:isDestroyed()).toBe(false)
		end
		stop()
		runtime:dispose()
	end)

	t.it("a menu picker keeps its trigger across selection and makes no trigger node", function()
		local engine, runtime, UI = world()
		local selected = Compose.cell("hud")
		local stop, picker = runtime.mount(function()
			return UI.Picker "Bounded" {
				style = "menu",
				selected = selected,
				options = { { value = "hud", label = "HUD" }, { value = "other", label = "Other" } },
			}
		end, engine.new("ScreenGui"))
		local trigger = find(picker, "Trigger")
		trigger.Activated.fire()
		local panel = assert(find(picker.Parent, "MenuPanel"))
		find(panel, "other").Activated.fire()
		t.expect(selected:peek()).toBe("other")
		t.expect(find(picker, "Trigger")).toBe(trigger)
		t.expect(trigger:isDestroyed()).toBe(false)
		t.expect(trigger.Text).toBe("Other")
		local made = #engine.made
		selected:set("hud")
		t.expect(trigger.Text).toBe("HUD")
		t.expect(find(picker, "Trigger")).toBe(trigger)
		t.expect(#engine.made).toBe(made)
		stop()
		runtime:dispose()
	end)
end)

t.describe("declaration refusals", function()
	local function refusal(build: (any, any, any) -> any): (string, number, number)
		local engine, runtime, UI = world()
		local root = engine.new("ScreenGui")
		local baseline = engine.census()
		local ok, err = pcall(runtime.mount, function()
			return build(UI, runtime.constructors, engine)
		end, root)
		assert(not ok, "declaration was accepted")
		local after = engine.census()
		local children = #root:GetChildren()
		runtime:dispose()
		return tostring(err), after.live - baseline.live + children, after.connections - baseline.connections
	end

	local CASES: { { name: string, message: string, build: (any, any, any) -> any } } = {
		{
			name = "unknown Button option",
			message = "Facet UI.Button: unknown option 'bogusOption'",
			build = function(UI)
				return UI.Button({ label = "x", bogusOption = 1 })
			end,
		},
		{
			name = "unknown Picker option",
			message = "Facet UI.Picker: unknown option 'bogus'",
			build = function(UI)
				return UI.Picker({ selected = Compose.cell("a"), options = { { value = "a", label = "A" } }, bogus = 1 })
			end,
		},
		{
			name = "unknown Alert option",
			message = "Facet UI.Alert: unknown option 'bogus'",
			build = function(UI)
				return UI.Alert({ isPresented = Compose.cell(false), title = "t", bogus = 1 })
			end,
		},
		{
			name = "Picker without options",
			message = "Facet UI.Picker: options must be an array of { value, label } entries",
			build = function(UI)
				return UI.Picker({ selected = Compose.cell("a") })
			end,
		},
		{
			name = "read-only Picker selection",
			message = "Picker.selected requires a writable Compose cell",
			build = function(UI)
				return UI.Picker({ selected = "a", options = { { value = "a", label = "A" } } })
			end,
		},
		{
			name = "duplicate Picker values",
			message = "",
			build = function(UI)
				return UI.Picker({
					selected = Compose.cell("a"),
					options = { { value = "a", label = "A" }, { value = "a", label = "Again" } },
				})
			end,
		},
		{
			name = "unknown Picker style",
			message = "Unknown Picker style",
			build = function(UI)
				return UI.Picker({
					selected = Compose.cell("a"),
					options = { { value = "a", label = "A" } },
					style = "nope",
				})
			end,
		},
		{
			name = "read-only DisclosureGroup expansion",
			message = "DisclosureGroup.expanded requires a writable Compose cell",
			build = function(UI, Host)
				return UI.DisclosureGroup({
					expanded = true,
					label = "More",
					content = function()
						return Host.Frame({})
					end,
				})
			end,
		},
		{
			name = "read-only TabView selection",
			message = "TabView.selection requires a writable Compose cell",
			build = function(UI)
				return UI.TabView({ tabs = {}, selection = "a" })
			end,
		},
		{
			name = "NavigationStack without root and destinations",
			message = "NavigationStack requires path, root and destinations",
			build = function(UI)
				return UI.NavigationStack({ path = Compose.cell({}) })
			end,
		},
		{
			name = "PageView without pages",
			message = "PageView requires entries",
			build = function(UI)
				return UI.PageView({ selection = Compose.cell("a") })
			end,
		},
		{
			name = "RadialMenu without items",
			message = "RadialMenu requires items",
			build = function(UI)
				return UI.RadialMenu({})
			end,
		},
		{
			name = "Menu without items",
			message = "Menu requires items",
			build = function(UI)
				return UI.Menu({})
			end,
		},
		{
			name = "Sheet without a writable detent",
			message = "Sheet.detent requires a writable Compose cell",
			build = function(UI)
				return UI.Sheet({ isPresented = Compose.cell(false) })
			end,
		},
		{
			name = "Sheet without a writable isPresented",
			message = "Sheet.isPresented requires a writable Compose cell",
			build = function(UI)
				return UI.Sheet({ detent = Compose.cell("medium") })
			end,
		},
		{
			name = "Callout without onRetire",
			message = "Callout requires onRetire",
			build = function(UI)
				return UI.Callout({})
			end,
		},
		{
			name = "Alert without presentation state",
			message = "A presented control requires isPresented or item",
			build = function(UI)
				return UI.Alert({ title = "t" })
			end,
		},
		{
			name = "closed Label textRole",
			message = "Facet Label invalid textRole",
			build = function(UI)
				return UI.Label({ text = "x", textRole = "nope" })
			end,
		},
		{
			name = "closed status",
			message = "Facet: invalid status",
			build = function(UI)
				return UI.StatusIndicator({ status = "nope" })
			end,
		},
		{
			name = "closed Badge status",
			message = "Facet: invalid status",
			build = function(UI)
				return UI.Badge({ label = "x", status = "nope" })
			end,
		},
		{
			name = "closed ProgressView presentation",
			message = "Facet ProgressView presentation must be bar, circular or spinner",
			build = function(UI)
				return UI.ProgressView({ value = 0, presentation = "nope" })
			end,
		},
		{
			name = "closed Toggle presentation",
			message = "Facet.Toggle: invalid presentation",
			build = function(UI)
				return UI.Toggle({ value = Compose.cell(false), presentation = "nope" })
			end,
		},
		{
			name = "closed TextInput presentation",
			message = "Facet.TextInput: invalid presentation",
			build = function(UI)
				return UI.TextInput({ value = Compose.cell(""), presentation = "nope" })
			end,
		},
		{
			name = "closed Skeleton form",
			message = "Facet Skeleton invalid form",
			build = function(UI)
				return UI.Skeleton({ form = "nope" })
			end,
		},
		{
			name = "closed Avatar presence",
			message = "Facet Avatar invalid presence",
			build = function(UI)
				return UI.Avatar({ name = "x", presence = "nope" })
			end,
		},
		{
			name = "closed controlSize",
			message = "Facet controlSize must be xsmall, compact, regular or large",
			build = function(UI)
				return UI.Button({ label = "x", controlSize = "huge" })
			end,
		},
		{
			name = "closed Button role",
			message = "Facet.Button: invalid semantic role",
			build = function(UI)
				return UI.Button({ label = "x", role = "nope" })
			end,
		},
		{
			name = "wrong Slider bound type",
			message = "finite min must be below max",
			build = function(UI)
				return UI.Slider({ value = Compose.cell(0), min = "a" })
			end,
		},
		{
			name = "segments on a circular ProgressView",
			message = "",
			build = function(UI)
				return UI.ProgressView({ value = 0.5, presentation = "circular", segments = 4 })
			end,
		},
	}
	for _, name in { "Stepper", "Slider", "Rating", "LevelPicker", "Chip", "Toggle", "TextInput" } do
		table.insert(CASES, {
			name = `{name} without a value`,
			message = `Facet.{name}:`,
			build = function(UI)
				return UI[name]({})
			end,
		})
	end
	for _, name in { "Table", "VirtualList", "VirtualGrid", "AvatarGroup", "Avatar", "Badge", "ShortcutHint" } do
		table.insert(CASES, {
			name = `{name} without required options`,
			message = "",
			build = function(UI)
				return UI[name]({})
			end,
		})
	end

	t.it("refuses unknown options, missing required options and closed sets with a named error", function()
		local mismatches: { string } = {}
		for _, case in CASES do
			local message = refusal(case.build)
			if case.message ~= "" and not string.find(message, case.message, 1, true) then
				table.insert(mismatches, `{case.name}: expected "{case.message}", got {message}`)
			end
		end
		if #mismatches > 0 then
			error(table.concat(mismatches, "\n"))
		end
	end)

	t.it("a refused declaration releases every partially built native node and connection", function()
		for _, case in CASES do
			local _, live, connections = refusal(case.build)
			if live ~= 0 or connections ~= 0 then
				error(`{case.name}: retained {live} nodes and {connections} connections`)
			end
		end
	end)

	t.it("a bound closed option refuses a later illegal value", function()
		local engine, runtime, UI = world()
		local controlSize, corners = Compose.cell("regular"), Compose.cell("pill")
		local role, status = Compose.cell("body"), Compose.cell("info")
		local badge, presence = Compose.cell("info"), Compose.cell("online")
		local stop = runtime.mount(function()
			return runtime.constructors.Frame({
				UI.Button({ label = "x", controlSize = controlSize }),
				UI.Button({ label = "y", corners = corners }),
				UI.Label({ text = "z", textRole = role }),
				UI.StatusIndicator({ status = status }),
				UI.Badge({ label = "b", status = badge }),
				UI.Avatar({ name = "a", presence = presence }),
			})
		end, engine.new("ScreenGui"))
		local function refuses(cell: any, value: string, message: string)
			local ok, err = pcall(function()
				cell:set(value)
			end)
			t.expect(ok).toBe(false)
			if not string.find(tostring(err), message, 1, true) then
				error(`expected "{message}", got {err}`)
			end
		end
		controlSize:set("compact")
		refuses(controlSize, "huge", "Facet controlSize must be xsmall, compact, regular or large")
		corners:set("square")
		refuses(corners, "round", "Facet.Button: corners must be pill or square")
		role:set("caption")
		refuses(role, "nope", "Facet Label invalid textRole")
		status:set("success")
		refuses(status, "nope", "Facet: invalid status")
		badge:set("warning")
		refuses(badge, "nope", "Facet: invalid status")
		presence:set("away")
		refuses(presence, "nope", "Facet Avatar invalid presence")
		stop()
		runtime:dispose()
	end)
end)

t.describe("contained failures", function()
	t.it("contains a failing alert title, reports it once and presents a later valid item", function()
		local failures: { string } = {}
		local item, disposed = Compose.cell(nil :: any), 0
		local engine, runtime, UI = world({
			onError = function(failure)
				table.insert(failures, tostring(failure))
			end,
		})
		local root = engine.new("ScreenGui")
		local stop = runtime.mount(function()
			return runtime.constructors.Frame({
				UI.Alert "Decision" {
					item = item,
					title = function(value)
						if value.id == "bad" then
							error("invalid title")
						end
						return "Ready " .. value.id
					end,
					content = function()
						Compose.cleanup(function()
							disposed += 1
						end)
						return runtime.constructors.Frame "Body" {}
					end,
				},
			})
		end, root)
		local alert = find(root, "Decision")
		item:set({ id = "bad" })
		t.expect(item:peek()).toBe(nil)
		t.expect(#failures).toBe(1)
		t.expect(string.find(failures[1], "invalid title", 1, true) ~= nil).toBe(true)
		t.expect(string.find(tostring(alert:GetAttribute("FacetError")), "invalid title", 1, true) ~= nil).toBe(true)
		t.expect(find(root, "Body")).toBeNil()
		item:set({ id = "good" })
		t.expect(find(root, "Title").Text).toBe("Ready good")
		t.expect(find(root, "Body") ~= nil).toBe(true)
		t.expect(#failures).toBe(1)
		stop()
		t.expect(disposed).toBe(1)
		runtime:dispose()
	end)

	t.it("contains an initially presented failing alert without stranding its binding", function()
		local failures: { string } = {}
		local shown = Compose.cell(true)
		local engine, runtime, UI = world({
			onError = function(failure)
				table.insert(failures, tostring(failure))
			end,
		})
		local root = engine.new("ScreenGui")
		local ok, stop = pcall(runtime.mount, function()
			return runtime.constructors.Frame({
				UI.Alert "Decision" {
					isPresented = shown,
					title = function()
						error("invalid initial data")
					end,
				},
			})
		end, root)
		t.expect(ok).toBe(true)
		t.expect(shown:peek()).toBe(false)
		t.expect(#failures).toBe(1)
		t.expect(string.find(failures[1], "invalid initial data", 1, true) ~= nil).toBe(true)
		t.expect(find(root, "Decision"):GetAttribute("FacetError") ~= nil).toBe(true)
		shown:set(true)
		t.expect(shown:peek()).toBe(false)
		t.expect(#failures).toBe(2)
		stop()
		runtime:dispose()
	end)

	t.it("shows default error copy with critical artwork and clears the error on Back", function()
		local shown, problem = Compose.cell(true), Compose.cell("Save failed" :: string?)
		local engine, runtime, UI = world()
		local root = engine.new("ScreenGui")
		local stop = runtime.mount(function()
			return runtime.constructors.Frame({ UI.Alert({ isPresented = shown, error = problem }) })
		end, root)
		t.expect(find(root, "Title").Text).toBe("Something went wrong")
		t.expect(find(root, "Message").Text).toBe("Save failed")
		local icon = find(root, "AlertIcon")
		t.expect(icon ~= nil).toBe(true)
		find(root, "ModalBack").Pressed.fire()
		t.expect(problem:peek()).toBe(nil)
		t.expect(shown:peek()).toBe(false)
		t.expect(find(root, "Title")).toBeNil()
		stop()
		runtime:dispose()
	end)

	local function stack(UI: any, Host: any, path: any, released: { number })
		return UI.NavigationStack({
			path = path,
			root = {
				content = function()
					return UI.Button "RootAction" { label = "Root" }
				end,
			},
			destinations = {
				good = {
					content = function()
						return UI.Button "Good" { label = "Good" }
					end,
				},
				bad = {
					content = function()
						Compose.cleanup(function()
							released[1] += 1
						end)
						Host.Frame "Partial" {}
						error("test destination failure")
					end,
				},
			},
		})
	end

	t.it("quarantines an invalid path, keeps the page and clears the error on the next valid path", function()
		local engine, runtime, UI = world()
		local path, released = Compose.cell({}), { 0 }
		local stop, root = runtime.mount(function()
			return runtime.constructors.Frame({ stack(UI, runtime.constructors, path, released) })
		end, engine.new("ScreenGui"))
		local nav = find(root, "NavigationStack")
		t.expect(nav:GetAttribute("FacetError")).toBeNil()
		path:set({ { id = "good" } })
		local good = find(root, "Good")
		path:set({ { id = "missing" } })
		t.expect(find(root, "Good")).toBe(good)
		t.expect(good:isDestroyed()).toBe(false)
		t.expect(string.find(tostring(nav:GetAttribute("FacetError")), "undeclared destination", 1, true) ~= nil)
			.toBe(true)
		path:set({ { id = "good" }, { id = "good" } })
		t.expect(nav:GetAttribute("FacetError")).toBeNil()
		t.expect(released[1]).toBe(0)
		stop()
		runtime:dispose()
	end)

	t.it("a destination fault releases partial content, records the failure and keeps Back", function()
		local engine, runtime, UI = world()
		local root = engine.new("ScreenGui")
		local path, released = Compose.cell({}), { 0 }
		local stop = runtime.mount(function()
			return runtime.constructors.Frame({ stack(UI, runtime.constructors, path, released) })
		end, root)
		local nav = find(root, "NavigationStack")
		local before = engine.census()
		path:set({ { id = "bad" } })
		t.expect(released[1]).toBe(1)
		t.expect(find(root, "Partial")).toBeNil()
		t.expect(find(root, "DestinationError") ~= nil).toBe(true)
		t.expect(string.find(tostring(nav:GetAttribute("FacetError")), "test destination failure", 1, true) ~= nil)
			.toBe(true)
		find(root, "Back").Activated.fire()
		t.expect(#path:peek()).toBe(0)
		t.expect(find(root, "RootAction") ~= nil).toBe(true)
		t.expect(find(root, "DestinationError")).toBeNil()
		local after = engine.census()
		t.expect(after.live).toBe(before.live)
		t.expect(after.connections).toBe(before.connections)
		stop()
		t.expect(released[1]).toBe(1)
		runtime:dispose()
	end)

	t.it("warns once with the demo id when a gallery demo cannot build", function()
		local engine: any = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local target, gui = engine.new("Folder"), engine.new("GuiService")
		local input = engine.new("UserInputService")
		input.PreferredInput = engine.types.Enum.PreferredInput.KeyboardAndMouse
		input.GetFocusedTextBox = function()
			return nil
		end
		local demos = {
			{ id = "first", title = "First", kind = "fixture", module = "first" },
			{ id = "second", title = "Second", kind = "fixture", module = "second" },
		}
		local ctx: { [string]: any } = {
			Facet = Facet,
			Compose = Compose,
			runtime = runtime,
			Host = runtime.constructors,
			types = engine.types,
			viewport = Compose.cell({ width = 1280, height = 720 }),
			inputTarget = target,
			guiService = gui,
			runService = { Heartbeat = engine.heartbeat },
			selection = Compose.cell("first"),
			theme = Compose.cell(themes.neutralPackage()),
			themeMode = Compose.cell("light"),
			demos = demos,
			load = function(_, name)
				return {
					build = function(page)
						if name == "second" then
							error("second is broken")
						end
						return {
							screen = function()
								return page.Host.Frame({ Name = name })
							end,
						}
					end,
				}
			end,
		}
		ctx.packages = { Neutral = ctx.theme:peek() }
		local warnings: { string } = {}
		local env = getfenv(gallery.build)
		env.warn = function(...)
			local parts = {}
			for index = 1, select("#", ...) do
				table.insert(parts, tostring((select(index, ...))))
			end
			table.insert(warnings, table.concat(parts, " "))
		end
		local ok, err = pcall(function()
			local stop = runtime.mount(function()
				gallery.configure(ctx)
				ctx.UI = Facet.controls(
					runtime,
					{
						types = engine.types,
						viewport = ctx.viewport,
						inputParent = target,
						services = { GuiService = gui, UserInputService = input },
						theme = ctx.theme,
						reducedMotion = ctx.reducedMotion,
					} :: any
				)
				return ctx.Host.ScreenGui "GalleryTest" { gallery.build(ctx) }
			end, target)
			t.expect(#warnings).toBe(0)
			local result = gallery.dispatch(ctx, "show", "second")
			t.expect(result.mounted).toBeNil()
			t.expect(#warnings).toBe(1)
			t.expect(string.find(warnings[1], "[Facet Gallery] second: ", 1, true)).toBe(1)
			t.expect(string.find(warnings[1], "second is broken", 1, true) ~= nil).toBe(true)
			t.expect(ctx.errorMessage:peek() ~= nil).toBe(true)
			gallery.dispatch(ctx, "show", "first")
			t.expect(#warnings).toBe(1)
			stop()
		end)
		env.warn = nil
		runtime:dispose()
		if not ok then
			error(err, 0)
		end
	end)
end)

t.describe("theme package boundaries", function()
	local function nested(depth: number): (any, any)
		local top: any = {}
		local node = top
		for _ = 1, depth - 1 do
			local child: any = {}
			node.nest = child
			node = child
		end
		return top, node
	end

	t.it("finds a callback nested fifteen levels deep and names its path", function()
		for _, depth in { 1, 4, 15, 40 } do
			local definition: any = themes.neutralPackage()
			local top, leaf = nested(depth)
			leaf.onPaint = function() end
			definition.metrics.controls.deep = top
			local package, report = themes.define(definition)
			t.expect(package).toBeNil()
			t.expect(report.ok).toBe(false)
			local found = false
			for _, issue in report.errors do
				if issue.message == "Theme packages contain data, not callbacks" then
					found = string.find(issue.field, ".onPaint", 1, true) ~= nil
				end
			end
			t.expect(found).toBe(true)
		end
		local chrome: any = themes.neutralPackage()
		chrome.chrome.control = { kind = "native", fallback = function() end }
		local package, report = themes.define(chrome)
		t.expect(package).toBeNil()
		t.expect(report.errors[1].field).toBe("package.chrome.control.fallback")
	end)

	t.it("refuses a non-table definition and a cycle with a report instead of an error", function()
		for _, value in { false, "not a package", 7 } :: { any } do
			local ok, package, report = pcall(themes.define, value)
			t.expect(ok).toBe(true)
			t.expect(package).toBeNil()
			t.expect(report.ok).toBe(false)
			t.expect(report.errors[1].field).toBe("package")
		end
		local cyclic: any = themes.neutralPackage()
		local loop: any = {}
		loop.self = loop
		cyclic.metrics.controls.cycle = loop
		local ok, package, report = pcall(themes.define, cyclic)
		t.expect(ok).toBe(true)
		t.expect(package).toBeNil()
		t.expect(report.errors[1].message).toBe("Theme packages cannot contain cycles")
	end)

	t.it("reference packages use only the public themes surface and are not test fixtures", function()
		local files: { [string]: boolean } = {}
		for _, name in fs.readDir("examples/themes") do
			local stem = string.match(name, "^(.-)%.luau$")
			if stem then
				files[stem] = true
				t.expect(themePackages.ROLES[stem] ~= nil).toBe(true)
			end
		end
		local references = 0
		for name, role in themePackages.ROLES do
			t.expect(files[name]).toBe(true)
			if role ~= "reference" then
				continue
			end
			references += 1
			local source = fs.readFile(`examples/themes/{name}.luau`)
			t.expect(string.find(source, "require(", 1, true)).toBeNil()
			t.expect(string.find(source, "src/", 1, true)).toBeNil()
			local module: any = (require :: any)("../examples/themes/" .. name)
			if themePackages.NOT_SHIPPABLE[name] then
				t.expect(module.testOnly).toBe(true)
			else
				t.expect(module.testOnly).toBeNil()
				local package, report = module.build(themes)
				t.expect(report.ok).toBe(true)
				t.expect(package.identity.id).toBe(module.id)
			end
		end
		t.expect(references).toBe(#themePackages.REFERENCE_ORDER)
		for name in themePackages.NOT_SHIPPABLE do
			local source = fs.readFile(`examples/themes/{name}.luau`)
			if themePackages.ROLES[name] ~= "control" then
				t.expect(string.find(source, ".testOnly = true", 1, true) ~= nil).toBe(true)
			end
		end
	end)
end)
