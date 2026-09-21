--!strict
local t = require("./lib/testkit")
local expect = t.expect
local Facet = require("../src")
local world = require("./lib/world")
local fake = require("./lib/fake_target")
local inspecting = false
t.afterEach(function()
	if inspecting then
		Facet.Compose.inspect.stop()
		inspecting = false
	end
end)
local function adapter()
	local target = fake.new({ ops = true })
	target.scrollBarThickness = fake.SCROLL_BAR_RESERVE
	return target
end
local function mounted(metrics)
	local w =
		world.new({ viewport = { x = 0, y = 0, w = 1280, h = 1100 }, themeMetrics = metrics, newAdapter = adapter })
	local built = require("../examples/gallery/scenarios/container_grid").build({
		Facet = Facet,
		UI = w.UI,
		Compose = Facet.Compose,
		env = w.env,
		presenter = w.pres,
	})
	expect(built.report().Sidebar.width).toBeNil()
	w.present(built.screen)
	return w, built
end
t.describe("measured container grid recipe", function()
	t.it("three simultaneous widths choose their own columns and measured tracks", function()
		local w, built = mounted()
		local facts = built.report()
		expect(facts.Sidebar.columns).toBe(3)
		expect(facts.Column.columns).toBe(6)
		expect(facts.Board.columns).toBe(12)
		for _, id in { "Sidebar", "Column", "Board" } do
			local class = Facet.adaptive.sizeClass(facts[id].width)
			expect(facts[id].caption).toBe(`{class} · {math.floor(facts[id].width)}px · {facts[id].columns} columns`)
			expect(facts[id].width > facts[id].rowWidth).toBe(true)
			expect(facts[id].cells).toEqual({ "Standings", "Lap", "Media", "Notes" })
		end
		local captions = 0
		for _, op in w.adapter.takeOps() do
			expect(op:find("· 0px", 1, true)).toBeNil()
			if op:find("/Caption.text=", 1, true) then
				captions += 1
			end
		end
		expect(captions >= 3).toBe(true)
		expect(built.steps.grow().columns).toBe(6)
		expect(built.steps.shrink().columns).toBe(3)
		w.close()
		expect(built.report().Sidebar.width).toBeNil()
	end)
	t.it("debug-on resize updates actual bands and zero span removes/re-enters a branch", function()
		local w, built = mounted()
		expect(built.steps.debugOn().Sidebar.bands).toBe(3)
		expect(built.steps.grow().bands).toBe(6)
		expect(built.steps.wide().bands).toBe(12)
		expect(built.steps.shrink().bands).toBe(3)
		expect(built.steps.hideMedia().cells).toEqual({ "Standings", "Lap", "Notes" })
		expect(built.steps.showMedia().cells).toEqual({ "Standings", "Lap", "Media", "Notes" })
		local debugNodes = 0
		for _, path in w.adapter.paths() do
			if path:find("DebugOverlay", 1, true) then
				debugNodes += 1
				expect(w.adapter.node(path).props.focusable == true).toBe(false)
			end
		end
		expect(debugNodes > 0).toBe(true)
		expect(built.steps.debugOff().Board.bands).toBe(0)
	end)
	for _, name in { "neutral", "fantasy_ornate", "pixel_quest" } do
		t.it(`measures themed row containment in {name}`, function()
			local metrics = if name == "neutral"
				then nil
				else Facet.themes.resolve(require("../examples/themes/" .. name).build(Facet.themes), nil, {})
			local w, built = mounted(metrics)
			for _, panel in built.report() do
				local row = panel.row
				for _, rect in panel.rects do
					expect(rect.x >= row.x - 0.5 and rect.x + rect.w <= row.x + row.w + 0.5).toBe(true)
				end
			end
			w.env:set("viewportRect", { x = 0, y = 0, w = 390, h = 844 })
			w.settle()
			for _, panel in built.report() do
				expect(panel.columns).toBe(3)
			end
		end)
	end
	t.it("same-instance panel hide/show releases recipe formulas and geometry callbacks", function()
		Facet.Compose.inspect.start()
		inspecting = true
		local w = world.new({ viewport = { x = 0, y = 0, w = 1280, h = 1100 } })
		local show = Facet.Compose.cell(true)
		local built = require("../examples/gallery/scenarios/container_grid").build({
			Facet = Facet,
			UI = w.UI,
			Compose = Facet.Compose,
			env = w.env,
			presenter = w.pres,
		})
		w.present(function()
			return w.UI.Screen("S")({ w.UI.When("Gate")({ condition = show, thenView = built.section }) })
		end)
		local function holding()
			local n = 0
			for _, owner in Facet.Compose.inspect.snapshot().mounts do
				n += owner.totalHolding
			end
			return n
		end
		local before = holding()
		expect(before > 0).toBe(true)
		for _ = 1, 10 do
			show:set(false)
			w.settle()
			show:set(true)
			w.settle()
		end
		expect(holding()).toBe(before)
		w.close()
		Facet.Compose.inspect.stop()
	end)
end)
