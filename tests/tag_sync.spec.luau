--!strict
--[[ THE CLASSIFICATION-TAG SYNC, DRIVEN RATHER THAN READ.

	This is the regression the sticky-tag defect (ADR-0038, SCREEN-X) did not
	have and should have. `syncTags` owns every `facet-*` tag on an instance, and
	for four days its REMOVAL half was dead code — `string.sub(tag, 1, 5)`
	compared five characters against the six-character `"facet-"`, so the
	comparison was constant and the function became purely additive. Every
	classification tag a node ever wore stayed on it for life.

	IT SURVIVED 7,116 GREEN CASES, and the reason is worth stating because it is
	the thing this file changes: `tests/lib/fake_target.luau` modelled NO TAGS AT
	ALL. The one channel by which Facet's states, roles and surfaces reach native
	paint had no headless witness, so the entire defect was invisible to the
	suite and could only be found by looking at a screen.

	WHAT IS SHARED AND WHAT IS MIRRORED. The DECISION — who owns a tag, and what
	one sync adds and removes — is `src/render/tag_sync.luau`, a pure module both
	adapters call; there is no second copy of it to drift. What the fake mirrors
	is the narrow bookkeeping around it (which classification state a create and
	three prop writes leave behind), declared in one place in that file and
	deliberately not the adapter's whole classification surface.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local tag_sync = require("../src/render/tag_sync")
local sheet_model = require("../src/tokens/sheet_model")

local UI = require("../src/blueprint")
local customFactory = require("../src/core/custom")
local environment = require("../src/env/environment")
local actionsLib = require("../src/input/actions")
local presenterLib = require("../src/present/presenter")
local fake_target = require("./lib/fake_target")

-- one Button on a Screen, its interesting prop on a signal, mounted through the
-- real presenter and renderer onto the headless target
local function mountButton(id: string, props: any): (any, any, any)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local adapter = fake_target.new()
	local system = actionsLib.newSystem(core)
	local pres = presenterLib.new(core, env, adapter, system)
	local spec: any = { id = "Btn", label = "Go" }
	for k, v in props :: any do
		spec[k] = v
	end
	pres.present(UI.Screen({ id = id, children = { UI.Button(spec) } }))
	pres.refresh()
	return core, pres, adapter
end

describe("tag_sync: the pure ruling", function()
	it("owns a tag by the LENGTH OF ITS OWN PREFIX, not by a counted number", function()
		expect(tag_sync.PREFIX).toBe("facet-")
		expect(tag_sync.owns("facet-surface-control")).toBe(true)
		expect(tag_sync.owns("facet-selected")).toBe(true)
		-- THE DEFECT, EXECUTED: the retired five-character test answers false for
		-- every one of these, which is why the removal loop matched NOTHING rather
		-- than matching the wrong thing — a dead branch and a wrong branch leave
		-- very different symptoms, and this one left none.
		expect(string.sub("facet-surface-control", 1, 5) == "facet-").toBe(false)
		-- ...and it never claims a tag that is not its own
		expect(tag_sync.owns("RascalKart")).toBe(false)
		expect(tag_sync.owns("facet")).toBe(false)
		expect(tag_sync.owns("")).toBe(false)
	end)

	it("a state change produces a REMOVAL, and the plan is deterministic", function()
		local dressed = sheet_model.classifyTags({ surface = "control", interactive = true, selected = true })
		local plain = sheet_model.classifyTags({ surface = nil, interactive = false })
		local current: { string } = {}
		for tag in dressed do
			table.insert(current, tag)
		end
		table.sort(current)

		local plan = tag_sync.diff(current, plain)
		expect(#plan.remove > 0).toBe(true)
		expect(table.concat(plan.remove, ",")).toBe(table.concat(current, ","))
		expect(table.concat(plan.add, ",")).toBe("")

		-- ...and re-running the same sync is a no-op: A/A writes nothing
		local settled = tag_sync.diff({}, plain)
		expect(table.concat(settled.add, ",")).toBe("")
		expect(table.concat(tag_sync.diff({}, {}).remove, ",")).toBe("")
	end)

	it("never removes a tag the game owns", function()
		local plan = tag_sync.diff({ "RascalKart", "facet-selected", "Interactable" }, {})
		expect(table.concat(plan.remove, ",")).toBe("facet-selected")
	end)
end)

describe("tag_sync: mounted, state changed, tag removed", function()
	it("a Button that stops being selected LOSES facet-selected", function()
		local core = customFactory.new()
		local selected = core:signal(true)
		local _, pres, target = mountButton("TagSel", { selected = selected })
		local dressed = target.tagsOf("/TagSel/Btn")
		expect(table.find(dressed, "facet-selected") ~= nil).toBe(true)

		selected:set(false)
		pres.refresh()
		local after = target.tagsOf("/TagSel/Btn")
		-- THE ASSERTION THE DEFECT WOULD HAVE FAILED
		expect(table.find(after, "facet-selected") ~= nil).toBe(false)
		-- ...and the tags that should have stayed did
		expect(table.find(after, "facet-surface-control") ~= nil).toBe(true)
		expect(table.find(after, "facet-interactive") ~= nil).toBe(true)
	end)

	it("a segment declared surface=plain ends up with NO tags — Bugs A and B", function()
		--[[ THE EXACT SHAPE OF THE SHIPPED REGRESSION. `picker.luau:552` declares
			every segment `surface = "plain"` whenever an indicator slides, "so
			nothing paints over the chip behind them". The adapter's handle went
			right and the INSTANCE kept `facet-surface-control`, whose sheet rule
			paints an opaque `$Control` fill — over the underline and the pill that
			`selection_indicator.luau` deliberately draws BEHIND the strip. ]]
		local core = customFactory.new()
		local surface = core:signal("control")
		local _, pres, target = mountButton("TagSurf", { surface = surface })
		expect(table.find(target.tagsOf("/TagSurf/Btn"), "facet-surface-control") ~= nil).toBe(true)

		surface:set("plain")
		pres.refresh()
		expect(table.concat(target.tagsOf("/TagSurf/Btn"), ",")).toBe("")
	end)

	it("a surface change swaps the surface tag rather than accumulating one", function()
		local core = customFactory.new()
		local surface = core:signal("control")
		local _, pres, target = mountButton("TagSwap", { surface = surface })
		surface:set("accent")
		pres.refresh()
		local tags = target.tagsOf("/TagSwap/Btn")
		-- RED carried BOTH at once, which made the sheet cascade decide the fill by
		-- rule ORDER rather than by what the node declared
		expect(table.find(tags, "facet-surface-accent") ~= nil).toBe(true)
		expect(table.find(tags, "facet-surface-control") ~= nil).toBe(false)
	end)

	it("a destructive Button returning to the default role LOSES the role tag", function()
		local core = customFactory.new()
		local role = core:signal("destructive")
		local _, pres, target = mountButton("TagRole", { role = role })
		expect(table.find(target.tagsOf("/TagRole/Btn"), "facet-role-destructive") ~= nil).toBe(true)

		role:set("default")
		pres.refresh()
		expect(table.find(target.tagsOf("/TagRole/Btn"), "facet-role-destructive") ~= nil).toBe(false)
	end)
end)
