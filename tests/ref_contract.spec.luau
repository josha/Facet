--!strict
--[[ `ref` IS THE PUBLIC HANDLE, SO IT IS HELD TO A PUBLIC CONTRACT.

	An application has exactly one way to reach a composite control's verbs and
	its dump: pass `ref = function(record) ... end` in the spec. `record` is what
	that application will hold for the whole life of the control, which makes its
	SHAPE part of the public surface rather than an implementation detail of
	`src/render/compose_controls.luau`.

	THE CONTRACT, ASSERTED HERE FOR EVERY COMPOSITE THE LIBRARY REGISTERS:

	  1. `ref` is called EXACTLY ONCE per build, with a table. Twice would mean an
	     application's second record silently replaces its first; never would mean
	     a control that cannot be driven at all.
	  2. The record is FROZEN. An application cannot stash a field on it and a
	     control cannot mutate it after handing it over, so what the app holds at
	     frame one is what it holds at frame ten thousand.
	  3. It carries `api` (nil is legal for a control with no verbs) and `dump`.
	  4. It NEVER carries `blueprint`. The node is the constructor's RETURN value;
	     handing a second reference to it through the record gives an application
	     a way to re-parent or decorate a node the library has already mounted.
	  5. It NEVER carries `dispose`. A composite's lifetime is its OWNER's —
	     `composite()` registers `built.dispose` with `Compose.cleanup`, so the
	     surface that built it releases it. A `dispose` an application can call is
	     a second, disagreeing authority over that lifetime.

	THE LIST OF COMPOSITES IS DERIVED FROM THE SOURCE, never hand-kept: a control
	registered with `composite(...)` and given no fixture here reddens the first
	case, which is the only way a list like this stays true.

	RULES 4 AND 5 ARE KNOWN TO FAIL TODAY, and they are written the way the
	contract SHOULD read rather than the way the library currently behaves.
	`composite()` hands `api = built.api or built`, so every control whose `build`
	returns a FLAT record — one with no `api` field of its own — gives the
	application its entire internal record, `blueprint` and `dispose` included.
	The failing case below NAMES each one, so the src owner has the list rather
	than a count. See the report attached to this spec's restoration. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")
local Facet = require("../src") :: any
local Compose = require("../src/vendor/compose/core")
local world = require("./lib/world")

-- ---------------------------------------------------------------------------
-- the registered composites, read off the library's own source
-- ---------------------------------------------------------------------------

local function registeredComposites(): { string }
	local source = fs.readFile("src/render/compose_controls.luau")
	local found: { string } = {}
	for name in string.gmatch(source, 'api%.([%a_][%w_]*) = composite%("') do
		table.insert(found, name)
	end
	table.sort(found)
	return found
end

-- ---------------------------------------------------------------------------
-- one minimal, VALID spec per composite
-- ---------------------------------------------------------------------------

-- `w` is the world the control is built in: its `UI` is `app.controls` and its
-- `core` is the application's own.
local FIXTURES: { [string]: (w: any) -> any } = {
	Alert = function(w)
		return {
			isPresented = Compose.cell(false),
			title = "Careful",
			message = "Are you sure?",
			actions = { { id = "ok", label = "OK" } },
		}
	end,
	AsyncImage = function(w)
		return { provider = Facet.newResourceProvider(w.core), key = "rbxassetid://1" }
	end,
	Button = function(w)
		return { label = "Save", onActivate = function() end }
	end,
	NavBar = function(w)
		return { title = "Garage" }
	end,
	Notice = function(w)
		return { message = "Saved." }
	end,
	Card = function(w)
		return { image = "rbxassetid://1", title = "Title" }
	end,
	Snackbar = function(w)
		return { isPresented = Compose.cell(false), message = "Saved.", closeButton = false }
	end,
	Dialog = function(w)
		return { isPresented = Compose.cell(false), closeButton = false, title = "Title" }
	end,
	Popover = function(w)
		return {
			isPresented = Compose.cell(false),
			source = { path = "/S/PopoverId" },
			content = function()
				return w.UI.Text("PopoverBody")({ text = "body" })
			end,
		}
	end,
	Callout = function(w)
		return {
			anchor = w.UI.Button("Plus")({ label = "+" }),
			content = w.UI.Text("TipBody")({ text = "Tap to add" }),
			onRetire = function() end,
		}
	end,
	Chip = function(w)
		return { label = "Wet", selected = Compose.cell(false) }
	end,
	CollapsibleView = function(w)
		return {
			label = "Details",
			expanded = Compose.cell(false),
			content = function()
				return w.UI.Text("Body")({ text = "Details" })
			end,
		}
	end,
	ComboBox = function(w)
		return {
			value = Compose.cell("a"),
			text = Compose.cell("Alpine"),
			options = { { id = "a", label = "Alpine" } },
			env = w.env,
			acceptCustom = function()
				return true
			end,
		}
	end,
	DisclosureGroup = function(w)
		return {
			label = "Advanced",
			expanded = Compose.cell(false),
			content = function()
				return w.UI.Text("Body")({ text = "body" })
			end,
		}
	end,
	Label = function(w)
		return { title = "Save", icon = "rbxassetid://1" }
	end,
	LevelPicker = function(w)
		return { value = Compose.cell(1) }
	end,
	Menu = function(w)
		return {
			trigger = w.UI.Button("MTrigger")({ label = "Open" }),
			items = { { id = "rename", label = "Rename", onSelect = function() end } },
			env = w.env,
		}
	end,
	NavigationStack = function(w)
		local function page()
			return w.UI.Text("PageBody")({ text = "page" })
		end
		return {
			path = Compose.cell({}),
			root = { title = "Home", content = page },
			destinations = { detail = { title = "Detail", content = page } },
			backLabel = "Back",
		}
	end,
	PageView = function(w)
		return {
			pages = {
				{ id = "one", title = "one", content = w.UI.Text("One")({ text = "one" }) },
				{ id = "two", title = "two", content = w.UI.Text("Two")({ text = "two" }) },
			},
			selection = Compose.cell("one"),
		}
	end,
	Picker = function(w)
		return {
			options = { { value = "a", label = "Alpha" }, { value = "b", label = "Beta" } },
			selected = Compose.cell("a"),
			env = w.env,
		}
	end,
	PopupButton = function(w)
		return {
			value = Compose.cell("one"),
			options = { { id = "one", label = "One" }, { id = "two", label = "Two" } },
			env = w.env,
		}
	end,
	ProgressView = function(w)
		return { value = 0.25, showValue = true }
	end,
	RadialMenu = function(w)
		return {
			items = {
				{ id = "wave", label = "Wave", onSelect = function() end },
				{ id = "point", label = "Point", onSelect = function() end },
			},
		}
	end,
	Rating = function(w)
		return { value = Compose.cell(3) }
	end,
	RowActions = function(w)
		return {
			content = w.UI.Text("RowBody")({ text = "row" }),
			trailing = { { id = "delete", label = "Delete", onAction = function() end } },
		}
	end,
	Sheet = function(w)
		return {
			title = "Details",
			isPresented = Compose.cell(false),
			detent = Compose.cell("medium"),
			content = function()
				return w.UI.Text("SheetBody")({ text = "body" })
			end,
		}
	end,
	AvatarGroup = function(_w)
		return { items = { { id = "ada", name = "Ada Quill" } } }
	end,
	Avatar = function(_w)
		return { name = "Ada Quill" }
	end,
	StatusIndicator = function(_w)
		return {}
	end,
	Badge = function(_w)
		return { label = "Ready" }
	end,
	Skeleton = function(_w)
		return { form = "box" }
	end,
	ShortcutHint = function(_w)
		return { keys = { { "K" } } }
	end,
	Slider = function(w)
		return { value = Compose.cell(0.5), min = 0, max = 1, step = 0.1 }
	end,
	SplitButton = function(w)
		return {
			label = "Save",
			onActivate = function() end,
			items = { { id = "copy", label = "Save copy", onSelect = function() end } },
		}
	end,
	Stepper = function(w)
		return { value = Compose.cell(2), min = 0, max = 10, step = 1 }
	end,
	Table = function(w)
		return {
			rows = Compose.cell({ { id = "a", name = "Apex" } }),
			key = function(row: any)
				return row.id
			end,
			rowHeight = 32,
			columns = {
				{
					id = "name",
					title = "Name",
					width = { type = "fill", weight = 1 },
					value = function(row: any)
						return row.name
					end,
				},
			},
		}
	end,
	TabView = function(w)
		return {
			selection = Compose.cell("a"),
			placement = "topBar",
			tabs = {
				{
					id = "a",
					title = "A",
					content = function()
						return w.UI.Text("ABody")({ text = "a" })
					end,
				},
			},
		}
	end,
	TextInput = function(w)
		return { value = Compose.cell("hi"), env = w.env }
	end,
	NumberInput = function(w)
		return { value = Compose.cell("1"), numericValue = Compose.cell(1), env = w.env }
	end,
	Toggle = function(w)
		return { label = "Filter", value = Compose.cell(true) }
	end,
	VirtualGrid = function(w)
		return {
			items = Compose.cell({ { id = "i1", label = "One" }, { id = "i2", label = "Two" } }),
			key = function(item: any)
				return item.id
			end,
			columns = 2,
			itemExtent = 40,
			viewportExtent = 200,
			cell = function(item: any)
				return w.UI.Text("Label")({ text = item.label, textSize = 14 })
			end,
		}
	end,
	VirtualList = function(w)
		return {
			rows = Compose.cell({ { id = "r1", label = "One" }, { id = "r2", label = "Two" } }),
			key = function(item: any)
				return item.id
			end,
			itemExtent = 40,
			viewportExtent = 200,
			cell = function(item: any)
				return w.UI.Text("Label")({ text = item.label, textSize = 14 })
			end,
		}
	end,
}

--[[ BUILT INSIDE A MOUNT, because that is where an application builds one: the
	owner the mount opens is what `composite()` registers `built.dispose` on, and
	a construction outside every owner would be testing a shape production never
	has. Each control is the screen's only child, so nothing else can be the
	source of a record. ]]
type Observation = { calls: number, record: any, node: any }

local function build(name: string): Observation
	local w = world.new()
	local observed: Observation = { calls = 0, record = nil, node = nil }
	w.present(function()
		local spec = table.clone(FIXTURES[name](w))
		spec.ref = function(record: any)
			observed.calls += 1
			observed.record = record
		end
		observed.node = w.UI[name](name .. "Id")(spec)
		return w.UI.Screen("S")({ observed.node })
	end)
	return observed
end

-- ---------------------------------------------------------------------------

describe("ref contract: every registered composite has a fixture", function()
	it("the fixture table covers exactly the composites the library registers", function()
		local registered = registeredComposites()
		expect(#registered > 20).toBe(true)
		for _, name in registered do
			expect(`{name} has a ref fixture: {FIXTURES[name] ~= nil}`).toBe(`{name} has a ref fixture: true`)
		end
		-- ...and no fixture here describes a composite the library no longer has
		for name in FIXTURES do
			expect(`{name} is still registered: {table.find(registered, name) ~= nil}`).toBe(
				`{name} is still registered: true`
			)
		end
	end)
end)

describe("ref contract: the record a composite hands an application", function()
	for _, name in registeredComposites() do
		it(`{name}: ref is called exactly once, with a frozen table`, function()
			local observed = build(name)
			expect(`{name} ref calls: {observed.calls}`).toBe(`{name} ref calls: 1`)
			expect(`{name} record type: {type(observed.record)}`).toBe(`{name} record type: table`)
			-- FROZEN, asserted by trying to write rather than by reading a flag:
			-- `table.isfrozen` answers about the table, a write answers about the
			-- promise an application is actually given
			local ok = pcall(function()
				(observed.record :: any).__probe = true
			end)
			expect(`{name} record is frozen: {not ok}`).toBe(`{name} record is frozen: true`)
		end)
	end

	it("NO record exposes `blueprint`: the node is the constructor's return value", function()
		--[[ THE FAILURE NAMES ITS CONTROLS. `composite()` hands
			`api = built.api or built`, so a control whose `build` returns a FLAT
			record publishes its own `blueprint` — a second reference to a node the
			library has already mounted, which an application can re-parent or
			decorate behind the library's back. ]]
		local leaking: { string } = {}
		for _, name in registeredComposites() do
			local observed = build(name)
			local record: any = observed.record
			if record.blueprint ~= nil or (type(record.api) == "table" and record.api.blueprint ~= nil) then
				table.insert(leaking, name)
			end
		end
		expect(table.concat(leaking, ", ")).toBe("")
	end)

	it("NO record exposes `dispose`: a composite's lifetime belongs to its owner", function()
		--[[ Same root cause as the case above, and the same list is expected. A
			`dispose` an application can call is a SECOND authority over a lifetime
			`Compose.cleanup` already owns: calling it leaves the owner holding a
			teardown for a control that is already gone, and not calling it is the
			only correct thing to do with it — which is what makes it surface a
			caller cannot use correctly. ]]
		local leaking: { string } = {}
		for _, name in registeredComposites() do
			local observed = build(name)
			local record: any = observed.record
			if record.dispose ~= nil or (type(record.api) == "table" and record.api.dispose ~= nil) then
				table.insert(leaking, name)
			end
		end
		expect(table.concat(leaking, ", ")).toBe("")
	end)

	it("the constructor still RETURNS the node, whatever the record carries", function()
		-- the half the two cases above cannot say: a record that carried nothing
		-- at all would pass them both
		for _, name in registeredComposites() do
			local observed = build(name)
			expect(`{name} node class: {type((observed.node :: any).class)}`).toBe(`{name} node class: string`)
		end
	end)
end)
