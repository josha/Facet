--!strict
local harness = require("./lib/harness")
-- Control factories and their explicit-handle contract.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local Compose = require("../src/vendor/compose/core")
local UI = harness.UI

-- the nineteen names, in the namespace's own order
local NAMES = {
	"Table",
	"Slider",
	"Stepper",
	"Picker",
	"PopupButton",
	"Menu",
	"TabView",
	"Label",
	"Chip",
	"Rating",
	"TextInput",
	"ProgressView",
	"LevelPicker",
	"DisclosureGroup",
	"VirtualList",
	"VirtualGrid",
	"RowActions",
	"Callout",
	"AsyncImage",
}

--[[ ...AND THE CONTROLS BORN AFTER THE NAMESPACE, which are a DIFFERENT list on
	purpose, and empty until the first one lands.

	A control created after 0.10.0 has exactly ONE public spelling.
	There is no `Facet.new<Name>` for it, so it has no old form to compare against
	and no deprecation row to carry — a new control is not born deprecated. That
	is why it cannot simply join `NAMES` above: the two cases below `NAMES` feeds
	are both ABOUT the old form, and a twentieth name in that list would fail them
	for existing rather than for being wrong.

	It still belongs to the namespace, and the exhaustive case below still refuses
	anything that is in NEITHER list, which is the property that case exists for.
	`tools/lune/scaffold` appends here from the one declared control record, so a
	control author never meets this file as a red test with no instruction
	(measured 2026-08-21: a fresh-context agent found this list by its failure
	message and had to guess whether editing it was allowed). ]]
local POST_ADR_NAMES: { string } = {
	"Button",
	"Toggle",
	"ComboBox",
	"SplitButton",
	"NavigationStack",
	"RadialMenu",
	"Alert",
	"Sheet",
	"PageView",
	"CollapsibleView",
	"Composition",
	"Region",
	"ShortcutHint",
	"Skeleton",
	"Avatar",
	-- scaffold: new control names are appended above this line
}

-- One minimal, VALID spec per control, built fresh for each arm so the two
-- builders cannot share mutable state. `core` is the arm's own core.
local FIXTURES: { [string]: (core: any) -> any } = {
	Table = function(core)
		return {
			id = "T",
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
	Slider = function(core)
		return { id = "Vol", value = Compose.cell(0.5), min = 0, max = 1, step = 0.1 }
	end,
	Stepper = function(core)
		return { id = "Qty", value = Compose.cell(2), min = 0, max = 10, step = 1 }
	end,
	Picker = function(core)
		return {
			id = "Mode",
			options = { { value = "a", label = "Alpha" }, { value = "b", label = "Beta" } },
			selected = Compose.cell("a"),
			-- an automatic presentation adapts, so it needs the arm's environment
			-- (ADAPT-1) — and BOTH arms build one, which is what keeps the two
			-- dumps comparable
			env = Facet.newEnvironment(core),
		}
	end,
	PopupButton = function(core)
		return {
			id = "Choice",
			value = Compose.cell("one"),
			options = { { id = "one", label = "One" }, { id = "two", label = "Two" } },
			-- an automatic presentation adapts, so it needs the arm's environment (ADAPT-1)
			env = Facet.newEnvironment(core),
		}
	end,
	Menu = function(core)
		return {
			id = "M",
			trigger = UI.Button({ id = "MTrigger", label = "Open" }),
			items = { { id = "rename", label = "Rename", onSelect = function() end } },
			-- an automatic presentation adapts, so it needs the arm's environment (ADAPT-1)
			env = Facet.newEnvironment(core),
		}
	end,
	TabView = function(core)
		return {
			id = "TV",
			selection = Compose.cell("a"),
			placement = "topBar",
			tabs = {
				{
					id = "a",
					title = "A",
					content = function()
						return UI.Text({ id = "ABody", text = "a" })
					end,
				},
			},
		}
	end,
	Label = function(_core)
		return { id = "Save", title = "Save", icon = "rbxassetid://1" }
	end,
	Chip = function(core)
		return { id = "C", label = "Wet", selected = Compose.cell(false) }
	end,
	Rating = function(core)
		return { id = "Stars", value = Compose.cell(3) }
	end,
	TextInput = function(core)
		-- a field reads the surface's environment (ADAPT-1), and both arms build one
		return { id = "Field", value = Compose.cell("hi"), env = Facet.newEnvironment(core) }
	end,
	ProgressView = function(_core)
		return { id = "Load", value = 0.25, showValue = true }
	end,
	LevelPicker = function(core)
		return { id = "L", value = Compose.cell(1) }
	end,
	DisclosureGroup = function(core)
		return {
			id = "Advanced",
			label = "Advanced",
			expanded = Compose.cell(false),
			content = function()
				return UI.Text({ id = "Body", text = "body" })
			end,
		}
	end,
	VirtualList = function(core)
		return {
			id = "VL",
			rows = Compose.cell({ { id = "r1", label = "One" }, { id = "r2", label = "Two" } }),
			key = function(item: any)
				return item.id
			end,
			itemExtent = 40,
			viewportExtent = 200,
			cell = function(item: any)
				return UI.Text({ id = "Label", text = item.label, textSize = 14 })
			end,
		}
	end,
	VirtualGrid = function(core)
		return {
			id = "VG",
			items = Compose.cell({ { id = "i1", label = "One" }, { id = "i2", label = "Two" } }),
			key = function(item: any)
				return item.id
			end,
			columns = 2,
			itemExtent = 40,
			viewportExtent = 200,
			cell = function(item: any)
				return UI.Text({ id = "Label", text = item.label, textSize = 14 })
			end,
		}
	end,
	RowActions = function(_core)
		return {
			id = "Row",
			content = UI.Text({ id = "RowBody", text = "row" }),
			trailing = { { id = "delete", label = "Delete", onAction = function() end } },
		}
	end,
	Callout = function(_core)
		return {
			id = "Tip",
			anchor = UI.Button({ id = "Plus", label = "+" }),
			content = UI.Text({ id = "TipBody", text = "Tap to add" }),
			onRetire = function() end,
		}
	end,
	AsyncImage = function(core)
		return {
			id = "I",
			provider = Facet.newResourceProvider(core),
			key = "rbxassetid://1",
		}
	end,
}

describe("the Controls namespace", function()
	it("exports exactly the declared composite controls from an application, and nothing else", function()
		local controls = require("./lib/world").new().UI
		-- The structural constructors are public: a schema-shaped spec plays region transitions.
		local declared: { [string]: boolean } = { ScrollView = true, Stage = true, ForEach = true, When = true }
		for _, name in NAMES do
			declared[name] = true
			expect(`{name}: {type(rawget(controls, name))}`).toBe(`{name}: function`)
		end
		-- ...plus the later additions, named just as explicitly. A control added to
		-- the library and to neither list reddens this case.
		for _, name in POST_ADR_NAMES do
			declared[name] = true
			expect(`{name}: {type(rawget(controls, name))}`).toBe(`{name}: function`)
		end
		for key in controls do
			-- lower-case members are modifiers and dimension helpers
			if string.match(key, "^%u") then
				expect(`controls.{key} is in the declared list: {declared[key] == true}`).toBe(
					`controls.{key} is in the declared list: true`
				)
			end
		end
		expect(Facet.Controls).toBe(nil)
	end)

	it("builds declared roots without flat constructor aliases", function()
		for _, name in NAMES do
			local core = harness.newCore()
			local spec = FIXTURES[name](core)
			local control = harness.Controls[name](core, spec)
			expect(type(control.blueprint.class)).toBe("string")
			local expectedId = if name == "Menu"
				then spec.id .. "Trigger"
				elseif name == "Callout" then spec.anchor.id
				else spec.id
			expect(control.blueprint.id).toBe(expectedId)
			expect(Facet[`new{name}`]).toBe(nil)
			if control.dispose then
				control.dispose()
			end
		end
	end)

	-- An application owns its core and presenter; the service constructors that
	-- take no library stay at the top level and out of the control library.
	it("the infrastructure constructors stay at the top level and stay out of the controls", function()
		local controls = require("./lib/world").new().UI
		for _, name in
			{
				"newEnvironment",
				"newActionSystem",
				"newFocusGraph",
				"newDragRegistry",
				"newDragSession",
				"newDragVelocity",
				"newResourceProvider",
				"newAutoscroll",
				"newRowActionsCoordinator",
			}
		do
			expect(`{name}: {type(Facet[name])}`).toBe(`{name}: function`)
			local short = string.sub(name, 4)
			expect(`controls.{short}: {tostring(rawget(controls, short))}`).toBe(`controls.{short}: nil`)
		end
		for _, name in { "newCore", "newPresenter" } do
			expect(`{name}: {type(Facet[name])}`).toBe(`{name}: nil`)
		end
	end)
end)

--[[ THE TWO STRUCTURAL REGIONS ON `app.controls`. `UI.ForEach`/`UI.When` are
	told apart from a hand-rolled region by the SPEC KEY, never by the name: an
	anonymous schema-shaped spec dispatches exactly like a named one, and a table
	that is neither a spec nor a list of children is a typo rather than a bare
	structural node that quietly does nothing. ]]
describe("app.controls regions dispatch on the spec shape, named or not", function()
	local world = require("./lib/world")

	-- the mounted paths under the region, with the region's own segment stripped
	local function branchPaths(w: any, region: string): { string }
		local out: { string } = {}
		for _, path in w.adapter.paths() do
			local inside = string.match(path, `^/S/Host/{region}/(.+)$`)
			if inside ~= nil then
				table.insert(out, inside)
			end
		end
		table.sort(out)
		return out
	end

	it("an ANONYMOUS schema-shaped When mounts the branch, exactly as a named one does", function()
		local open = Compose.cell(true)
		local function screen(build: (any) -> any)
			local w = world.new()
			w.present(function()
				return w.UI.Screen("S")({ w.UI.VStack("Host")({ build(w.UI) }) })
			end)
			return w
		end
		local anonymous = screen(function(U: any)
			return U.When({
				condition = open,
				thenView = function()
					return U.Text("Branch")({ text = "branch" })
				end,
			})
		end)
		local named = screen(function(U: any)
			return U.When("Gate")({
				condition = open,
				thenView = function()
					return U.Text("Branch")({ text = "branch" })
				end,
			})
		end)
		-- the anonymous region gets a generated segment; what it MOUNTS is identical
		local anonSegment = nil
		for _, path in anonymous.adapter.paths() do
			anonSegment = string.match(path, "^/S/Host/(When[^/]*)/") or anonSegment
		end
		expect(`anonymous region: {tostring(anonSegment ~= nil)}`).toBe("anonymous region: true")
		expect(table.concat(branchPaths(anonymous, anonSegment :: string), ",")).toBe(
			table.concat(branchPaths(named, "Gate"), ",")
		)
		expect(table.concat(branchPaths(named, "Gate"), ",")).toBe("then,then/Branch")
	end)

	it("an ANONYMOUS schema-shaped ForEach mounts rows, exactly as a named one does", function()
		local items = Compose.cell({ { id = "a" }, { id = "b" } })
		local w = world.new()
		w.present(function()
			return w.UI.Screen("S")({
				w.UI.VStack("Host")({
					w.UI.ForEach({
						items = items,
						key = function(item: any)
							return item.id
						end,
						row = function(item: any)
							return w.UI.Text("Row")({ text = item.id })
						end,
					}),
				}),
			})
		end)
		local segment = nil
		for _, path in w.adapter.paths() do
			segment = string.match(path, "^/S/Host/(ForEach[^/]*)/") or segment
		end
		expect(`anonymous region: {tostring(segment ~= nil)}`).toBe("anonymous region: true")
		expect(table.concat(branchPaths(w, segment :: string), ",")).toBe("[a]/Row,[b]/Row")
	end)

	it("numeric children still build a bare region, named or anonymous", function()
		local w = world.new()
		local bare = w.scoped(function()
			return w.UI.When({ w.UI.Text({ text = "hand-rolled" }) })
		end)
		expect(`class: {bare.class}, children: {#bare.children}`).toBe("class: When, children: 1")
	end)

	it("a spec that is neither shape names what was expected", function()
		local w = world.new()
		local ok, err = pcall(function()
			return w.scoped(function()
				return w.UI.ForEach({ rows = {}, row = function() end })
			end)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "Facet UI.ForEach", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "neither a numeric child nor a declared prop", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "items = <cell or formula>", 1, true) ~= nil).toBe(true)
	end)

	-- `key` is a function OR the name of the field that holds the identity, with
	-- the same `tostring` rule the list engine uses — one rule everywhere.
	it("ForEach takes a field name for `key`, like VirtualList does", function()
		local items = Compose.cell({ { id = 1 }, { id = 2 } })
		local w = world.new()
		w.present(function()
			return w.UI.Screen("S")({
				w.UI.VStack("Host")({
					w.UI.ForEach("Rows")({
						items = items,
						key = "id",
						row = function(item: any)
							return w.UI.Text("Row")({ text = tostring(item.id) })
						end,
					}),
				}),
			})
		end)
		-- a numeric id is spelled out, because a key is a path segment
		expect(table.concat(branchPaths(w, "Rows"), ",")).toBe("[1]/Row,[2]/Row")
	end)

	it("a `key` that is neither a function nor a field name says so", function()
		local w = world.new()
		local ok, err = pcall(function()
			return w.scoped(function()
				return w.UI.ForEach("Rows")({ items = Compose.cell({}), key = 7, row = function() end })
			end)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "Facet UI.ForEach: `key` identifies an item", 1, true) ~= nil).toBe(true)
	end)
end)
