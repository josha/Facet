--!strict
--[[ A DECLARED SURFACE DECIDES THE DECORATION SLOT. THE CLASS MAP ANSWERS FOR A
	NODE THAT DECLARED NONE.

	THE DEFECT. `chrome_slots.classify` ended in one clause —

	    if CONTROL_SURFACES[surface] or CONTROL_CLASSES[class] then return "control" end

	— so a `UI.Button` that declared `surface = "base"` was handed the package's
	CONTROL recipe anyway, by its class, over the top of the flat app-background
	fill its author asked for. Under Glossy Mobile that recipe carries
	`shadow = "raised"`, whose reach is the package's `chromeBleed`; the
	swipe-actions fixture's hand-wrapped list rows sit 1px apart, so every row's
	glow painted 17px into its neighbours. It is the same report the virtualized
	surface's row hit produced ("a crowded list that's overlapping"), one seam
	over, and the same class `classify`'s own `plain` clause already records for
	the playlist demo's star buttons.

	WHY THE FRAMEWORK IS THE RIGHT PLACE, and not the two fixtures. Every OTHER
	declared surface already outranks the class map in this same function:
	`plain` returns nil above the class rules, `raised` returns `panel`, `badge`
	returns `badge`. Only `base` and `scrim` fell through — an omission, not a
	design. And the two subsystems disagreed about one word, which is exactly the
	argument the `plain` clause's own comment makes: `screen_paint.applySurface`
	paints `base` as the flat surface fill with no corner and no hairline, while
	`chrome_slots` handed the same node a button plate with depth.

	`scrim` joins `base` for the same reason and one more: `sheet_model.classifyTags`
	ALREADY treats scrim as suppressed alongside plain, and `applySurfaceNative`
	already clears its interactivity. A scrim that paints a control plate was the
	third subsystem disagreeing.

	WHAT DOES NOT MOVE, stated so the boundary is deliberate rather than
	accidental: the `selection` branch above still answers for a node carrying a
	`selected` prop, whatever surface it declared. Selection is a STATE the
	framework paints and the node opted into by carrying the prop, `selection` is
	the slot whose whole job is "this node shows chosen-ness", and a base-surfaced
	row that can be chosen still needs that treatment. `base` means "paint me the
	app surface", never "paint me nothing" — that word is `plain`.

	THE CORPUS THIS WAS MEASURED OVER. Every gallery scenario, tutorial example
	and reference proof was mounted and censused for Button/Toggle nodes carrying
	a declared surface: 323 of them, and only two were not already `plain` — the
	two pinned below. Neither wants a control plate, which is why this lands in
	the framework and neither fixture is edited.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local worldLib = require("./lib/world")

local Facet = require("../src") :: any
local chrome_slots = require("../src/tokens/chrome_slots")
local glossy_mobile = require("../examples/themes/glossy_mobile")

local rowActions = require("../examples/gallery/scenarios/row_actions") :: any
local celebration = require("../examples/gallery/scenarios/sponsor_celebration") :: any

local function slotFor(class: string, surface: string?, hasSelection: boolean?): string?
	return chrome_slots.classify({ class = class, surface = surface, hasSelection = hasSelection == true })
end

local function scenarioWorld(module: any)
	local w = worldLib.new({ viewport = { x = 0, y = 0, w = 1232, h = 1067 } })
	local built = module.build({
		Facet = Facet,
		core = w.core,
		env = w.env,
		adapter = w.adapter,
		presenter = w.pres,
		actionSystem = w.system,
		record = function() end,
		flags = {},
		geometry = function()
			return {}
		end,
		bindResourceTransport = function()
			return function() end
		end,
	})
	built.handle = w.pres.present(built.screen, built.present)
	for _ = 1, 4 do
		w.pres.refresh()
	end
	return w, built
end

-- the slot the renderer would classify a MOUNTED node into: the same three
-- inputs `render/layout_node.luau` and the live adapter read off the node.
local function slotOfMounted(adapter: any, path: string): string?
	local node = adapter.node(path)
	assert(node ~= nil, `no mounted node at {path}`)
	local props = node.props or {}
	return chrome_slots.classify({
		class = node.class,
		surface = props.surface,
		hasSelection = props.selected ~= nil,
	})
end

describe("surface slot precedence: the class map is the answer for a node that declared nothing", function()
	it("an undeclared Button and Toggle are still controls", function()
		expect(slotFor("Button", nil)).toBe("control")
		expect(slotFor("Toggle", nil)).toBe("control")
	end)

	it("...and so is one whose surface is not a NAME — a reactive value the caller has not resolved", function()
		-- "declared nothing" is `type(surface) ~= "string"`. A caller handing this a
		-- Readable took the class answer before the precedence rule landed, and has
		-- to keep taking it: only a declared NAME is judged by the name.
		local readable: any = { get = function() end }
		expect(chrome_slots.classify({ class = "Button", surface = readable })).toBe("control")
	end)

	it("a declared CONTROL surface is still a control, on any class", function()
		expect(slotFor("Button", "control")).toBe("control")
		expect(slotFor("Button", "chip")).toBe("control")
		expect(slotFor("Button", "accent")).toBe("control")
		expect(slotFor("Box", "control")).toBe("control")
	end)

	it("the declared surfaces that already outranked the class map are unmoved", function()
		expect(slotFor("Button", "plain")).toBe(nil)
		expect(slotFor("Button", "raised")).toBe("panel")
		expect(slotFor("Button", "badge")).toBe("badge")
	end)
end)

describe("surface slot precedence: a declared non-control surface is not a control", function()
	it("a Button declaring `base` takes no slot, so no package plate or shadow reaches it", function()
		expect(slotFor("Button", "base")).toBe(nil)
	end)

	it("a Toggle declaring `base` likewise", function()
		expect(slotFor("Toggle", "base")).toBe(nil)
	end)

	it("`scrim` joins it — the surface two other subsystems already suppress", function()
		expect(slotFor("Button", "scrim")).toBe(nil)
		expect(slotFor("Toggle", "scrim")).toBe(nil)
	end)

	it("a non-control CLASS declaring `base` was never a control and still is not", function()
		expect(slotFor("Box", "base")).toBe(nil)
		expect(slotFor("Text", "base")).toBe(nil)
	end)

	it("SELECTION STILL WINS: a chosen row is painted with the selection slot whatever surface it declared", function()
		expect(slotFor("Button", "base", true)).toBe("selection")
		expect(slotFor("Button", nil, true)).toBe("selection")
	end)
end)

describe("surface slot precedence: the premise, and the two surfaces that carried it", function()
	it("Glossy Mobile's control slot really does declare a shadow that reaches outside its box", function()
		local package, report = glossy_mobile.build(Facet.themes)
		assert(package ~= nil, `glossy_mobile failed its own package gate: {report and report.errors[1]}`)
		expect(chrome_slots.shadowFor(package, "control") ~= nil).toBe(true)
		expect(Facet.themes.resolve(package, nil, {}).chromeBleed > 0).toBe(true)
	end)

	it("the swipe-actions list rows sit a hairline apart, so a control shadow would land on the next row", function()
		local w, built = scenarioWorld(rowActions)
		local first = w.adapter.node("/MailActions/ListWhen/then/List/Rows/RowsForEach/[m1]/m1")
		local second = w.adapter.node("/MailActions/ListWhen/then/List/Rows/RowsForEach/[m2]/m2")
		assert(first ~= nil and second ~= nil, "the list surface did not mount its rows")
		local gap = second.rect.y - (first.rect.y + first.rect.h)
		expect(gap < 4).toBe(true)
		local _ = built
	end)

	it("...and each of those rows declares `base`, so it takes no slot", function()
		local w = scenarioWorld(rowActions)
		for _, key in { "m1", "m2", "m3", "m4", "m5", "m6" } do
			local path = `/MailActions/ListWhen/then/List/Rows/RowsForEach/[{key}]/{key}/Content/Row`
			expect(w.adapter.node(path).props.surface).toBe("base")
			expect(slotOfMounted(w.adapter, path)).toBe(nil)
		end
	end)

	it("the celebration lab's full-pane skip surface is the other one, and it is not a button plate", function()
		local w = scenarioWorld(celebration)
		local path = "/CelebrationLab/Stage"
		expect(w.adapter.node(path).props.surface).toBe("base")
		expect(slotOfMounted(w.adapter, path)).toBe(nil)
	end)
end)
