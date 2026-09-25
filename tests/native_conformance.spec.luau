--!strict
local t = require("./lib/testkit")
local HELPERS =
	{ fill = true, badged = true, environment = true, worldAnchor = true, scrollTo = true, scrollToVisible = true }
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local Compose = Facet.Compose
local fixtures = {
	Screen = function()
		return {}
	end,
	VStack = function()
		return { gap = "s" }
	end,
	HStack = function()
		return { gap = "s" }
	end,
	ZStack = function()
		return {}
	end,
	ScrollView = function()
		return { gap = "s" }
	end,
	Grid = function()
		return { columns = 2 }
	end,
	Button = function()
		return { label = "Press" }
	end,
	Toggle = function()
		return { value = Compose.cell(false) }
	end,
	TextInput = function()
		return { value = Compose.cell("Text") }
	end,
	Stepper = function()
		return { value = Compose.cell(0) }
	end,
	Slider = function()
		return { value = Compose.cell(0) }
	end,
	Rating = function()
		return { value = Compose.cell(0) }
	end,
	LevelPicker = function()
		return { value = Compose.cell(0) }
	end,
	Chip = function()
		return { label = "Chip", selected = Compose.cell(false) }
	end,
	NumberInput = function()
		return { value = Compose.cell("1"), numericValue = Compose.cell(1) }
	end,
	DateTimePicker = function()
		return { value = Compose.cell(nil), onChange = function() end }
	end,
	ColorPicker = function()
		return { value = Compose.cell(require("@lune/roblox").Color3.new(1, 0, 0)), onChange = function() end }
	end,
	ShortcutHint = function()
		return { keys = { { "Ctrl", "K" } } }
	end,
	Label = function()
		return { text = "Label" }
	end,
	Badge = function()
		return { label = "Badge" }
	end,
	StatusIndicator = function()
		return { status = "success" }
	end,
	ProgressView = function()
		return { value = Compose.cell(0.5) }
	end,
	Skeleton = function()
		return {}
	end,
	AsyncImage = function()
		return {
			source = "image",
			loader = function(source, resolve)
				resolve(source)
			end,
		}
	end,
	Avatar = function()
		return { name = "Ada" }
	end,
	AvatarGroup = function()
		return { items = { { id = "a", name = "Ada" } } }
	end,
	ErrorBoundary = function(Host)
		return {
			view = function()
				return Host.Frame({})
			end,
			fallback = function()
				return Host.Frame({})
			end,
		}
	end,
	Stage = function()
		return {}
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
	Menu = function()
		return { items = { { id = "a", label = "A", onSelect = function() end } } }
	end,
	Picker = function()
		return { selected = Compose.cell("a"), options = { { value = "a", label = "A" } } }
	end,
	ComboBox = function()
		return {
			acceptCustom = function()
				return true
			end,
			text = Compose.cell("A"),
			value = Compose.cell("a"),
			options = { { value = "a", label = "A" } },
		}
	end,
	SplitButton = function()
		return { label = "Action", items = { { id = "a", label = "A", onSelect = function() end } } }
	end,
	RadialMenu = function()
		return { items = { { id = "a", label = "A", onSelect = function() end } }, isPresented = Compose.cell(false) }
	end,
	DisclosureGroup = function(Host)
		return {
			label = "Details",
			expanded = Compose.cell(false),
			content = function()
				return Host.Frame({})
			end,
		}
	end,
	CollapsibleView = function(Host)
		return {
			label = "Details",
			expanded = Compose.cell(false),
			content = function()
				return Host.Frame({})
			end,
		}
	end,
	Alert = function()
		return { title = "Confirm", isPresented = Compose.cell(false), actions = { { id = "ok", label = "OK" } } }
	end,
	Dialog = function()
		return { title = "Confirm", isPresented = Compose.cell(false), closeButton = false }
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
	Popover = function(Host)
		return {
			isPresented = Compose.cell(false),
			source = { rect = { x = 0, y = 0, w = 10, h = 10 } },
			content = function()
				return Host.Frame({})
			end,
		}
	end,
	Sheet = function(Host)
		return {
			detent = Compose.cell("medium"),
			isPresented = Compose.cell(false),
			content = function()
				return Host.Frame({})
			end,
		}
	end,
	Callout = function(Host)
		return {
			anchor = Host.Frame({}),
			onRetire = function() end,
			content = function()
				return Host.TextLabel({ Text = "Tip" })
			end,
			isPresented = Compose.cell(false),
		}
	end,
	TabView = function(Host)
		return {
			selection = Compose.cell("a"),
			tabs = {
				{
					id = "a",
					label = "A",
					content = function()
						return Host.Frame({})
					end,
				},
			},
		}
	end,
	PageView = function(Host)
		return {
			selection = Compose.cell("a"),
			pages = {
				{
					id = "a",
					title = "A",
					content = function()
						return Host.Frame({})
					end,
				},
			},
		}
	end,
	NavigationStack = function(Host)
		return {
			path = Compose.cell({}),
			root = {
				title = "Root",
				content = function()
					return Host.Frame({})
				end,
			},
			destinations = {},
		}
	end,
	RowActions = function(Host)
		return {
			content = function()
				return Host.Frame({})
			end,
		}
	end,
	Table = function()
		return {
			from = {},
			key = function(item)
				return item.id
			end,
			columns = { { id = "label", title = "Label" } },
		}
	end,
}
for _, name in { "VirtualList", "VirtualGrid" } do
	fixtures[name] = function(Host)
		return {
			from = { { id = "a" } },
			key = function(item)
				return item.id
			end,
			itemSize = 24,
			render = function()
				return Host.Frame({})
			end,
		}
	end
end

t.describe("native constructor conformance", function()
	t.it("requires a conformance fixture for every public control with no stale fixtures", function()
		local engine = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local UI = Facet.controls(runtime, { types = engine.types })
		for name in UI do
			assert(fixtures[name] or HELPERS[name], `Missing conformance fixture: {name}`)
		end
		for name in fixtures do
			assert(UI[name], `Stale conformance fixture: {name}`)
		end
		runtime:dispose()
	end)
	local names = {}
	for name in fixtures do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		t.it(`{name} preserves caller properties refs events and cleanup in both constructor forms`, function()
			for _, named in { false, true } do
				local engine = engineLib.new({ cacheDefaults = true })
				local runtime = Facet.Roblox.createRuntime(engine)
				local UI = Facet.controls(runtime, { types = engine.types, reducedMotion = true })
				local root = engine.new("ScreenGui")
				local baseline = engine.census()
				local zIndex, calls, reference, refCalls = Compose.cell(7), 0, nil, 0
				local stop, node = runtime.mount(function()
					local props = fixtures[name](runtime.constructors)
					props.ZIndex = zIndex
					props.Attributes = { Conformance = name }
					props.ref = function(value)
						reference = value
						refCalls += 1
					end
					props[Compose.event("MouseEnter")] = function()
						calls += 1
					end
					if not named then
						props.Name = "Caller"
					end
					return if named then UI[name]("Caller")(props) else UI[name](props)
				end, root)
				assert(reference == node, "ref must identify returned root")
				assert(refCalls == 1, `ref ran {refCalls} times for one build`)
				assert(node.Name == "Caller", "caller Name was lost")
				assert(node:GetAttribute("Conformance") == name, "caller attributes were lost")
				assert(node.ZIndex == 7, "native property was lost")
				zIndex:set(9)
				assert(node.ZIndex == 9, "native property stopped subscribing")
				assert(refCalls == 1, "a property update ran ref again")
				node.MouseEnter.fire()
				assert(calls == 1, "native event was not forwarded")
				stop()
				runtime:dispose()
				node.MouseEnter.fire()
				assert(calls == 1, "event survived disposal")
				assert(node:isDestroyed(), "root survived disposal")
				local after = engine.census()
				assert(after.live == baseline.live, `native instances leaked: {baseline.live} -> {after.live}`)
				assert(after.connections == baseline.connections, "native connections leaked")
			end
		end)
	end
end)
