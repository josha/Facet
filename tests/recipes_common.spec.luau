--!strict
local t = require("./lib/testkit")
local world = require("./lib/example_world")
local scenario = require("../examples/gallery/scenarios/recipes_common")
local function make(width, metrics, offset)
	local w = world.new({
		viewport = { x = 0, y = 0, w = width or 1000, h = 844 },
		themeMetrics = metrics,
		env = { preferredTextOffset = offset or 0 },
		reducedMotion = true,
		preferredInput = "Keyboard",
		hostOpts = { keyboardNavigation = true },
	})
	local built = scenario.build(w.ctx)
	t.expect(built.report()).toBeNil()
	local handle = w.presenter.present(built.screen)
	w.handle = handle
	return w, built, handle
end
local function find(w, suffix)
	for _, path in w.adapter.paths() do
		if path:sub(-#suffix) == suffix then
			return assert(w.adapter.node(path)), path
		end
	end
	error("missing " .. suffix)
end
local function tap(w, suffix)
	local _, path = find(w, suffix)
	w.adapter.tap(path)
	w.settle(4)
	return path
end
local function rect(w, suffix)
	return find(w, suffix).rect
end

t.describe("public composition recipes", function()
	t.it("selects measured action candidates, preserves order and excludes hidden focus targets", function()
		local w, b = make()
		for _, form in { "row", "column", "row" } do
			local r = if form == "row" then b.steps.wideActions() else b.steps.narrowActions()
			t.expect(r.actionsForm).toBe(form)
			local active = if form == "row" then "Row" else "Column"
			local off = if form == "row" then r.column else r.row
			t.expect(off.w).toBe(0)
			local count = 0
			for _, entry in w.handle.focusOrder().traversal do
				if string.find(entry.path, "/Actions/", 1, true) then
					count += 1
				end
			end
			t.expect(count).toBe(3)
			local a, c, d =
				rect(w, "/Actions/" .. active .. "/Cancel"),
				rect(w, "/Actions/" .. active .. "/Save"),
				rect(w, "/Actions/" .. active .. "/Delete")
			t.expect(if form == "row" then a.x < c.x and c.x < d.x else a.y < c.y and c.y < d.y).toBe(true)
			if form == "column" then
				t.expect(a.w).toBe(c.w)
				t.expect(c.w).toBe(d.w)
			end
			t.expect(find(w, "/Actions/" .. active .. "/Save").props.appearance).toBe("emphasis")
			t.expect(find(w, "/Actions/" .. active .. "/Delete").props.role).toBe("destructive")
			tap(w, "/Actions/" .. active .. "/Save")
		end
		t.expect(b.report().activations).toBe(3)
	end)
	t.it("accepts or rejects checkbox requests without changing neighboring caller values", function()
		local w, b = make(320)
		tap(w, "/CheckboxGroup/fuel+target/fuel")
		t.expect(b.report().checks).toEqual({ tires = true, fuel = true })
		t.expect(b.report().requests).toBe(1)
		local wrap = find(w, "/WrapChecks/fuel+target/fuel")
		t.expect(wrap.props.selected).toBe(true)
		tap(w, "/WrapChecks/fuel+target/fuel")
		t.expect(find(w, "/CheckboxGroup/fuel+target/fuel").props.selected).toBe(false)
		tap(w, "/WrapChecks/fuel+target/fuel")
		b.steps.rejectChecks()
		tap(w, "/CheckboxGroup/fuel+target/fuel")
		t.expect(b.report().checks.fuel).toBe(true)
		t.expect(b.report().requests).toBe(4)
		b.steps.disableChecks()
		tap(w, "/CheckboxGroup/fuel+target/fuel")
		t.expect(b.report().requests).toBe(4)
	end)
	t.it("retains keyed chip selection and identity through reorder and removal", function()
		local w, b = make(320)
		local before, path = find(w, "/Rain")
		w.adapter.tap(path)
		w.settle()
		t.expect(b.report().wrapSelected.Rain).toBe(true)
		t.expect(b.report().wrapSelected.Night).toBe(false)
		b.steps.reorderTags()
		w.settle()
		t.expect(find(w, "/Rain")).toBe(before)
		t.expect(b.report().wrapSelected.Rain).toBe(true)
		tap(w, "/Rain")
		t.expect(b.report().wrapSelected.Rain).toBe(false)
	end)
	t.it("delivers all three empty-state commands once per activation", function()
		local w, b = make(320)
		for _, entry in
			{ { "EmptyCollection", "createCount" }, { "NoResults", "clearCount" }, { "LoadFailed", "retryCount" } }
		do
			for n = 1, 2 do
				tap(w, "/" .. entry[1] .. "/Action")
				t.expect(b.report()[entry[2]]).toBe(n)
			end
		end
	end)
	t.it("resolves divider edges and heavy extent under each theme", function()
		local Facet = require("../src")
		local variants = { Facet.themes.neutral() }
		for _, name in { "pixel_quest", "fantasy_ornate" } do
			table.insert(variants, Facet.themes.resolve((require("../examples/themes/" .. name).build(Facet.themes))))
		end
		for _, metrics in variants do
			local w = make(390, metrics)
			local f, l, r, b, h =
				rect(w, "/DividerFull/Pad/Line"),
				rect(w, "/DividerLeading/Pad/Line"),
				rect(w, "/DividerTrailing/Pad/Line"),
				rect(w, "/DividerBoth/Pad/Line"),
				rect(w, "/DividerHeavy/Pad/Line")
			-- Owner report 2026-09-22 (bugs/divider.png): each line sits under a
			-- representative icon row, so a leading inset visibly starts at the text
			local text = rect(w, "/DividerLeading/Row/Title")
			local inset = metrics.controlSizes.regular.iconSize + metrics.controls.label.gap
			t.expect(l.x).toBe(text.x)
			t.expect(l.x - f.x).toBe(inset)
			t.expect(l.x + l.w).toBe(f.x + f.w)
			t.expect(r.x).toBe(f.x)
			t.expect(r.x + r.w).toBe(f.x + f.w - inset)
			-- owner follow-up: one bounded card (<= 360 px, on a 390 px phone) holds
			-- every line, so both ends are on screen to compare
			local card = rect(w, "/Dividers")
			t.expect(card.w <= 360 and card.x >= 0 and card.x + card.w <= 390).toBe(true)
			t.expect(f.x >= card.x and f.x + f.w <= card.x + card.w).toBe(true)
			t.expect(b.x).toBe(l.x)
			t.expect(b.x + b.w).toBe(r.x + r.w)
			t.expect(f.h).toBe(metrics.strokes.hairline)
			-- heavy is three of the theme's hairlines, so it stays heavier under Pixel's 4 px line
			t.expect(h.h).toBe(3 * metrics.strokes.hairline)
		end
	end)
	t.it("keeps only the activated accordion body open and focus on its header", function()
		local w, b, h = make(320)
		for _, id in { "Rules", "Setup", "Rewards", "Rewards" } do
			local old = b.report().openSection
			local path = tap(w, "/Accordion/" .. id .. "/Header")
			local expected = if old == id then nil else id
			t.expect(b.report().openSection).toBe(expected)
			for _, other in { "Rules", "Setup", "Rewards" } do
				local node = w.adapter.node(b.report().rootPath .. "/Accordion/" .. other .. "/Reveal")
				t.expect(node ~= nil).toBe(other == expected)
				if node then
					t.expect(node.rect.h > 0).toBe(true)
				end
			end
			t.expect(w.pres.focus.focused:peek()).toBe(path)
		end
		w.presenter.dismiss(h)
		t.expect(b.report()).toBeNil()
		local nested = w.presenter.present(function()
			return w.UI.Screen("Embedded")({ b.section() })
		end)
		t.expect(b.report().rootPath).toBe("/Embedded/Page")
		t.expect(b.steps.narrowActions().actionsForm).toBe("column")
		w.presenter.dismiss(nested)
		t.expect(b.report()).toBeNil()
	end)
	t.it("real Tab navigation reaches checkbox, wrap chip, accordion and scrolls the rail tail", function()
		local w, b = make(320)
		local _, start = find(w, "/Wet Weather")
		local _, tail = find(w, "/Ghost Lap")
		local rail = b.report().rootPath .. "/RailChips"
		t.expect(w.pres.focus.focusOn(start)).toBe(true)
		w.settle()
		local controller = w.handle.controller
		local before = controller.scrollPosition(rail).x
		w.press("Tab")
		w.settle()
		t.expect(w.pres.focus.focused:peek()).toBe(tail)
		t.expect(controller.scrollPosition(rail).x > before).toBe(true)
		local target, window = controller.screenRectOf(tail), controller.screenRectOf(rail)
		t.expect(target.x >= window.x and target.x + target.w <= window.x + window.w).toBe(true)
		local visited = {}
		for _ = 1, 100 do
			visited[w.pres.focus.focused:peek()] = true
			w.press("Tab")
			w.settle(1)
		end
		for _, suffix in
			{
				"/CheckboxGroup/fuel+target/fuel",
				"/WrapChecks/fuel+target/fuel",
				"/Rain",
				"/Accordion/Rules/Header",
				"/Accordion/Setup/Header",
				"/Accordion/Rewards/Header",
			}
		do
			local _, path = find(w, suffix)
			t.expect(visited[path]).toBe(true)
		end
	end)
end)
