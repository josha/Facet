--!strict
--[[ Composite controls live at `Facet.Controls.<Name>(core, spec)`.

	THE SHAPE THIS PINS. `Facet.Controls.Table(core, spec)` made an author write
	the library's name twice in every call: the first argument is the library
	handing itself to its own builder, boilerplate that teaches nothing and that
	autocomplete cannot explain. `Facet.Controls` closes over the library once, so
	the redundant argument disappears and completion on `Facet.Controls.` lists
	exactly the nineteen composite controls instead of the forty-four mixed
	entries `Facet.` offers.

	WHAT A TEST CAN ACTUALLY PROVE HERE, and why it is written this way. A
	namespace that merely EXISTS proves nothing — the defect this file exists to
	catch is an entry wired to the wrong builder, or wired to the right builder
	with the wrong library, and both produce a table that looks perfectly
	plausible from the outside. So every one of the nineteen is built BOTH WAYS
	with the SAME spec table, and the two results are compared on their published
	surface (the dump, the blueprint class, the node id). A builder that received
	something other than the library cannot construct its blueprint at all, and a
	builder wired to the wrong control produces a different class.

	AND THE OLD FORM STILL WORKS. That is not a nicety: it is the compatible half
	of the migration. The old
	form is what the comparison's control arm calls, so it is proven live by
	every case below rather than by one token case.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local UI = require("../src/blueprint")

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

--[[ ...AND THE CONTROLS BORN AFTER THE ADR, which are a DIFFERENT list on
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
	-- scaffold: new control names are appended above this line
}

-- One minimal, VALID spec per control, built fresh for each arm so the two
-- builders cannot share mutable state. `core` is the arm's own core.
local FIXTURES: { [string]: (core: any) -> any } = {
	Table = function(core)
		return {
			id = "T",
			rows = core:signal({ { id = "a", name = "Apex" } }),
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
		return { id = "Vol", value = core:signal(0.5), min = 0, max = 1, step = 0.1 }
	end,
	Stepper = function(core)
		return { id = "Qty", value = core:signal(2), min = 0, max = 10, step = 1 }
	end,
	Picker = function(core)
		return {
			id = "Mode",
			options = { { value = "a", label = "Alpha" }, { value = "b", label = "Beta" } },
			selected = core:signal("a"),
			-- an automatic presentation adapts, so it needs the arm's environment
			-- (ADAPT-1) — and BOTH arms build one, which is what keeps the two
			-- dumps comparable
			env = Facet.newEnvironment(core),
		}
	end,
	PopupButton = function(core)
		return {
			id = "Choice",
			value = core:signal("one"),
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
			selection = core:signal("a"),
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
		return { id = "C", label = "Wet", selected = core:signal(false) }
	end,
	Rating = function(core)
		return { id = "Stars", value = core:signal(3) }
	end,
	TextInput = function(core)
		-- a field reads the surface's environment (ADAPT-1), and both arms build one
		return { id = "Field", value = core:signal("hi"), env = Facet.newEnvironment(core) }
	end,
	ProgressView = function(_core)
		return { id = "Load", value = 0.25, showValue = true }
	end,
	LevelPicker = function(core)
		return { id = "L", value = core:signal(1) }
	end,
	DisclosureGroup = function(core)
		return {
			id = "Advanced",
			label = "Advanced",
			expanded = core:signal(false),
			content = function()
				return UI.Text({ id = "Body", text = "body" })
			end,
		}
	end,
	VirtualList = function(core)
		return {
			id = "VL",
			rows = core:signal({ { id = "r1", label = "One" }, { id = "r2", label = "Two" } }),
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
			items = core:signal({ { id = "i1", label = "One" }, { id = "i2", label = "Two" } }),
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
			scope = core:scope("img"),
			key = "rbxassetid://1",
		}
	end,
}

describe("the Controls namespace", function()
	it("exports exactly the nineteen composite controls the namespace names, and nothing else", function()
		expect(type(Facet.Controls)).toBe("table")
		local declared: { [string]: boolean } = {}
		for _, name in NAMES do
			declared[name] = true
			expect(`{name}: {type(Facet.Controls[name])}`).toBe(`{name}: function`)
		end
		-- ...plus the post-ADR additions, named just as explicitly. The claim is
		-- "nothing is in this namespace that no list admits to", not "the namespace
		-- never grows": a control added to `src/init.luau` and to neither list still
		-- reddens this case, which is the mutation that matters.
		for _, name in POST_ADR_NAMES do
			declared[name] = true
			expect(`{name}: {type(Facet.Controls[name])}`).toBe(`{name}: function`)
		end
		for key in Facet.Controls do
			expect(`Controls.{key} is in the ADR's list: {declared[key] == true}`).toBe(
				`Controls.{key} is in the ADR's list: true`
			)
		end
		-- authority, not a scratch table a consumer can extend with a 20th control
		expect(table.isfrozen(Facet.Controls)).toBe(true)
	end)

	--[[ THE ONE THAT MATTERS. An entry wired to the wrong builder, or to the
		right builder with the wrong first argument, still returns a table. Build
		each control BOTH WAYS from the same spec and compare what each publishes. ]]
	it("every entry builds what the old two-argument form builds", function()
		for _, name in NAMES do
			local fixture = FIXTURES[name]
			expect(`{name} has a fixture: {fixture ~= nil}`).toBe(`{name} has a fixture: true`)

			local oldCore = Facet.newCore()
			local old = Facet[`new{name}`](Facet, oldCore, fixture(oldCore))
			local newCore = Facet.newCore()
			local new = Facet.Controls[name](newCore, fixture(newCore))

			expect(`{name} blueprint: {new.blueprint ~= nil}`).toBe(`{name} blueprint: true`)
			expect(`{name} class: {new.blueprint.class}`).toBe(`{name} class: {old.blueprint.class}`)
			expect(`{name} id: {tostring(new.blueprint.props.id)}`).toBe(
				`{name} id: {tostring(old.blueprint.props.id)}`
			)
			if type(old.dump) == "function" then
				expect(`{name} dumps: {type(new.dump)}`).toBe(`{name} dumps: function`)
				expect(new.dump()).toEqual(old.dump())
			end
		end
	end)

	--[[ THE LEDGER IS THE NOTICE. The old form keeps working for at
		least one minor after `since`; what makes that a promise rather than a habit
		is a machine-readable row naming the replacement. api_surface.spec owns the
		ledger's SHAPE — this owns its CONTENT for the nineteen. ]]
	it("every old-form builder carries its deprecation row", function()
		local bySurface: { [string]: any } = {}
		for _, entry in Facet.DEPRECATIONS :: { any } do
			bySurface[entry.surface] = entry
		end
		for _, name in NAMES do
			local surface = `new{name}`
			local entry = bySurface[surface]
			expect(`{surface} is in the ledger: {entry ~= nil}`).toBe(`{surface} is in the ledger: true`)
			expect(`{surface} since: {entry.since}`).toBe(`{surface} since: 0.10.0`)
			expect(`{surface} removeNoEarlierThan: {entry.removeNoEarlierThan}`).toBe(
				`{surface} removeNoEarlierThan: 0.12.0`
			)
			expect(`{surface} replacement: {entry.replacement}`).toBe(
				`{surface} replacement: Facet.Controls.{name}(core, spec)`
			)
		end
	end)

	--[[ INFRASTRUCTURE DID NOT MOVE. `newCore`/`newPresenter`/`newActionSystem`/…
		take no library argument and their creation IS the important fact, so the ADR
		leaves them where they are. A future editor tidying "all the `new*`s" into
		the namespace would break every host in the repository. ]]
	it("the eleven infrastructure constructors stay at the top level and stay out of Controls", function()
		for _, name in
			{
				"newCore",
				"newEnvironment",
				"newPresenter",
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
			expect(`Controls.{short}: {tostring(Facet.Controls[short])}`).toBe(`Controls.{short}: nil`)
		end
	end)
end)
