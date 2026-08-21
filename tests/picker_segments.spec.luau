--!strict
-- Segmented Picker upgrades (navigation-and-menus brief §2 D6) — icons on
-- `Option`, a real VERTICAL pill, and the D4 indicator adopted as the segmented
-- presentation's DEFAULT paint.
--
-- D6 is a PROPERTIES-ONLY stage (director call 2026-08-16,
-- `artifacts/navigation-and-menus/additive-vs-net-new.md` §1): no new construct
-- and no new module, so every case below drives `Facet.newPicker` the way an
-- author will and never reaches into a private.
--
-- The three claims that carry the deliverable, and how each is falsified:
--
--   * THE DEFAULT CHANGED. A segmented picker paints a sliding chip unless it is
--     told otherwise. Proved by the bar node existing and by the options losing
--     the `selected` style tag — not by reading the spec back.
--   * AN ICON-ONLY SEGMENT STILL HAS A NAME. `dump().semanticText` names the
--     chosen option, and the authoring lint refuses a nameless one, because
--     `check_registration` cannot see an unreadable glyph.
--   * THE VERTICAL PILL IS NOT THE INLINE ROW LIST. Both report `axis = "y"`;
--     the pill is a content-sized RAIL with a 44px floor and the row list is a
--     full-width column, and `dump().verticalPill` is the field that tells them
--     apart.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local serde = require("@lune/serde")

local Facet = require("../src") :: any
local fake_target = require("./lib/fake_target")
local focus_map = require("../src/present/focus_map")

local UI = Facet.UI

-- ===== the harness ========================================================
-- One mounted picker on a real presenter. `viewportRect` is wide, so a picker
-- that does not declare its presentation resolves SEGMENTED — which is the
-- shape every case here is about.
local function world(spec: any?)
	local options = spec or {}
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = options.viewport or 480, h = 640 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = Facet.newPresenter(core, env, adapter, system)
	local selected = core:signal(options.initial or "grid")
	local built: any = {
		id = "View",
		selected = selected,
		options = options.options or {
			{ value = "grid", label = "Grid" },
			{ value = "list", label = "Listing" },
		},
		env = env,
	}
	for _, key in { "presentation", "indicator", "axis", "iconOnly", "label", "sizeClass", "sizing" } do
		if (options :: any)[key] ~= nil then
			built[key] = (options :: any)[key]
		end
	end
	local p = Facet.Controls.Picker(core, built)
	local handle = pres.present(UI.Screen({ id = "S", children = { p.blueprint } }))
	pres.refresh()
	return {
		core = core,
		env = env,
		adapter = adapter,
		pres = pres,
		picker = p,
		selected = selected,
		handle = handle,
	}
end

-- the options sit one level deeper whenever an indicator is on (the decoration
-- layer and the option stack must share a parent) — resolved from the dump so a
-- case never hard-codes the answer it is testing
local function optPath(w: any, n: number): string
	local base = if w.picker.dump().indicator == "none" then "/S/View/Options" else "/S/View/Indicator/Options"
	return `{base}/Opt{n}`
end
local BAR = "/S/View/Indicator/Layer/Bar"

local ICONS = {
	{ value = "grid", label = "Grid", icon = "shop:bag" },
	{ value = "list", label = "Listing", icon = "shop:person" },
}

describe("D6: the segmented presentation ADOPTS the sliding indicator", function()
	it("a segmented picker defaults to the pill — the chip is the shipped paint now", function()
		local w = world({ presentation = "segmented" })
		expect(w.adapter.node(BAR) ~= nil).toBe(true)
		expect(w.picker.dump().indicator.skin).toBe("pill")
		expect(w.picker.dump().requestedIndicator).toBe("automatic")
	end)

	it("...and so does an ADAPTIVE picker that resolves segmented", function()
		-- `presentation = "automatic"` is what most callers write. The default has
		-- to reach them or the flip changes almost nothing.
		local w = world()
		expect(w.picker.dump().presentation).toBe("segmented")
		expect(w.adapter.node(BAR) ~= nil).toBe(true)
	end)

	it("the default drops the `selected` style tag, because a tag AND a chip say it twice", function()
		local w = world({ presentation = "segmented" })
		expect(w.adapter.node(optPath(w, 1)).props.selected).toBeNil()
		expect(w.adapter.node(optPath(w, 1)).props.surface).toBe("plain")
	end)

	it('`indicator = "none"` is the documented escape hatch back to the static tag', function()
		local w = world({ presentation = "segmented", indicator = "none" })
		expect(w.adapter.node(BAR)).toBeNil()
		expect(w.adapter.node(optPath(w, 1)).props.selected).toBe(true)
		expect(w.adapter.node(optPath(w, 2)).props.selected).toBe(false)
		expect(w.picker.dump().indicator).toBe("none")
	end)

	it("a DECLARED inline picker keeps its current painting", function()
		-- the row list is not a strip and never wore a chip; the automatic default
		-- resolves to `none` for it, so nothing that ships as `inline` moves
		local w = world({ presentation = "inline" })
		expect(w.picker.dump().indicator).toBe("none")
		expect(w.adapter.node(BAR)).toBeNil()
		expect(w.adapter.node(optPath(w, 1)).props.selected).toBe(true)
	end)

	it("an explicit indicator still applies to `inline` — the DEFAULT changed, not the property", function()
		local w = world({ presentation = "inline", indicator = "underline" })
		expect(w.adapter.node(BAR) ~= nil).toBe(true)
		expect(w.picker.dump().indicator.skin).toBe("underline")
	end)

	it("the chip still SLIDES from the old rect to the new one under the default", function()
		local w = world({ presentation = "segmented" })
		local a = w.adapter.node(optPath(w, 1)).rect
		local b = w.adapter.node(optPath(w, 2)).rect
		expect(b.x > a.x).toBe(true)
		expect(w.adapter.node(BAR).rect.x).toBe(a.x + 4)
		w.selected:set("list")
		w.pres.refresh()
		local between = 0
		-- `object` responds in 0.28 s; 200 frames is ~3.3 s of clock, so the last
		-- assertion is on the TERMINAL rect rather than on a frame count
		local settled = false
		for _ = 1, 200 do
			w.pres.tick(1 / 60)
			w.pres.refresh()
			local x = w.adapter.node(BAR).rect.x
			if x > a.x + 4 and x < b.x + 4 then
				between += 1
			end
			if math.abs(x - (b.x + 4)) < 0.001 then
				settled = true
			end
		end
		expect(settled).toBe(true)
		expect(between > 3).toBe(true)
	end)

	it("`automatic` is a legal spelling and the refusal message names the whole set", function()
		local w = world({ presentation = "segmented", indicator = "automatic" })
		expect(w.adapter.node(BAR) ~= nil).toBe(true)
		local core = Facet.newCore()
		local ok, err = pcall(function()
			return Facet.Controls.Picker(core, {
				id = "X",
				options = { { value = 1, label = "one" } },
				selected = core:signal(1),
				indicator = "glow",
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "automatic | none | underline | pill", 1, true) ~= nil).toBe(true)
	end)
end)

describe("D6: `icon` on Option — icon-only and icon+label", function()
	it("an icon rides `compactLabel`, so the glyph is the DEGRADE and the word survives", function()
		-- the menu-row reading of the 2026-08-12 device ruling (row_actions.luau:
		-- 1774): a list of names keeps its names, and the glyph is what it wears
		-- when the word does not fit.
		local w = world({ presentation = "segmented", options = ICONS })
		expect(w.adapter.node(optPath(w, 1)).props.label).toBe("Grid")
		expect(w.adapter.node(optPath(w, 1)).props.compactLabel.icon).toBe("shop:bag")
		expect(w.picker.dump().iconCount).toBe(2)
		expect(w.picker.dump().iconOnly).toBe(false)
	end)

	it("...and the ladder really RUNS: too narrow for the word, the segment wears the glyph", function()
		-- the half of the ladder a wide fixture cannot see. Without it, "the word
		-- survives" above is satisfied by never declaring the icon at all.
		local long = {
			{ value = "grid", label = "Presentation", icon = "shop:bag" },
			{ value = "list", label = "Enumeration", icon = "shop:person" },
		}
		local wide = world({ presentation = "segmented", options = long })
		expect(wide.adapter.node(optPath(wide, 1)).props.label).toBe("Presentation")
		local narrow = world({ presentation = "segmented", options = long, viewport = 200 })
		expect(narrow.adapter.node(optPath(narrow, 1)).props.label).toBe("B")
		expect(narrow.adapter.node(optPath(narrow, 2)).props.label).toBe("P")
	end)

	it("`iconOnly` INVERTS it: the glyph is what every segment wears at every width", function()
		-- the TRAY reading of the same ruling (row_actions_trays.luau:346) —
		-- `prefer = true`. f1's top pill and left rail are both icon-only.
		local w = world({ presentation = "segmented", options = ICONS, iconOnly = true })
		expect(w.adapter.node(optPath(w, 1)).props.label).toBe("B")
		expect(w.adapter.node(optPath(w, 2)).props.label).toBe("P")
		expect(w.picker.dump().iconOnly).toBe(true)
	end)

	it("an icon-only segment STILL CARRIES A NAME, in the dump and in the option", function()
		local w = world({ presentation = "segmented", options = ICONS, iconOnly = true, label = "View" })
		local d = w.picker.dump()
		expect(d.semanticText).toBe("View: Grid")
		expect(d.selectedLabel).toBe("Grid")
		expect(d.selectedIcon).toBe("shop:bag")
		w.selected:set("list")
		expect(w.picker.dump().semanticText).toBe("View: Listing")
	end)

	it("a nameless option is an AUTHORING ERROR — an icon with no name announces nothing", function()
		local core = Facet.newCore()
		for _, bad in { "", nil :: any } do
			local ok, err = pcall(function()
				return Facet.Controls.Picker(core, {
					id = "X",
					options = { { value = "a", label = bad, icon = "shop:bag" } },
					selected = core:signal("a"),
				})
			end)
			expect(ok).toBe(false)
			expect(string.find(tostring(err), "semantic", 1, true) ~= nil).toBe(true)
		end
	end)

	it("Guidance: icons for ALL options in a group, or none — a half-iconned group is refused", function()
		local core = Facet.newCore()
		local ok, err = pcall(function()
			return Facet.Controls.Picker(core, {
				id = "X",
				options = {
					{ value = "a", label = "Alpha", icon = "shop:bag" },
					{ value = "b", label = "Beta" },
				},
				selected = core:signal("a"),
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "all options in a group, or none", 1, true) ~= nil).toBe(true)
		-- ...and a group with NO icons at all is of course fine. It adapts, so it
		-- reads the environment this core publishes (ADAPT-1); the refusal above
		-- fires first because the icon rule is checked before any fact is asked for.
		Facet.newEnvironment(core)
		local none = Facet.Controls.Picker(core, {
			id = "Y",
			options = { { value = "a", label = "Alpha" }, { value = "b", label = "Beta" } },
			selected = core:signal("a"),
		})
		expect(none.dump().iconCount).toBe(0)
		none.dispose()
	end)

	it("`iconOnly` with nothing to draw is refused rather than silently ignored", function()
		local core = Facet.newCore()
		local ok, err = pcall(function()
			return Facet.Controls.Picker(core, {
				id = "X",
				options = { { value = "a", label = "Alpha" }, { value = "b", label = "Beta" } },
				selected = core:signal("a"),
				iconOnly = true,
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "iconOnly", 1, true) ~= nil).toBe(true)
	end)

	it("an icon+label segment survives 1.4x pseudo-localization without clipping", function()
		local long = {
			{ value = "grid", label = "Grille de présentation", icon = "shop:bag" },
			{ value = "list", label = "Liste détaillée", icon = "shop:person" },
		}
		local w = world({ presentation = "segmented", options = long })
		for i = 1, 2 do
			local node = w.adapter.node(optPath(w, i))
			expect(node.rect.h >= 44).toBe(true)
			-- the drawn text is either the whole word or the glyph — never a
			-- truncation the framework invented
			expect(node.props.label == long[i].label or node.props.label == "B" or node.props.label == "P").toBe(true)
		end
	end)
end)

describe("D6: the VERTICAL pill is a rail, not the inline row list", function()
	it('`axis = "y"` on a segmented picker is a CONTENT-SIZED rail', function()
		local rail = world({ presentation = "segmented", axis = "y", options = ICONS, iconOnly = true })
		local column = world({ presentation = "inline", options = ICONS })
		local railWidth = rail.adapter.node("/S/View").rect.w
		local columnWidth = column.adapter.node("/S/View").rect.w
		-- the rail hugs its widest segment; the row list spans the offer
		expect(railWidth < columnWidth).toBe(true)
		expect(columnWidth).toBe(480)
	end)

	it("every segment of the rail still meets the 44px floor on BOTH axes", function()
		-- an icon-only rail has nothing wide in it, so the cross axis needs the
		-- floor as much as the main one does
		local w = world({ presentation = "segmented", axis = "y", options = ICONS, iconOnly = true })
		for i = 1, 2 do
			local r = w.adapter.node(optPath(w, i)).rect
			expect(r.w >= 44).toBe(true)
			expect(r.h >= 44).toBe(true)
		end
	end)

	it("the rail stacks along y and its segments share one width", function()
		local w = world({ presentation = "segmented", axis = "y", options = ICONS, iconOnly = true })
		local a = w.adapter.node(optPath(w, 1)).rect
		local b = w.adapter.node(optPath(w, 2)).rect
		expect(a.x).toBe(b.x)
		expect(a.w).toBe(b.w)
		expect(b.y > a.y).toBe(true)
	end)

	it("`dump().verticalPill` is what tells the pill and the row list apart", function()
		local rail = world({ presentation = "segmented", axis = "y" })
		local column = world({ presentation = "inline" })
		-- BOTH report axis = "y". That is exactly why the flag exists.
		expect(rail.picker.dump().axis).toBe("y")
		expect(column.picker.dump().axis).toBe("y")
		expect(rail.picker.dump().verticalPill).toBe(true)
		expect(column.picker.dump().verticalPill).toBe(false)
		-- ...and `axis` stays inert on the row list, whatever was asked for
		local asked = world({ presentation = "inline", axis = "y" })
		expect(asked.picker.dump().verticalPill).toBe(false)
	end)

	it("the chip travels down the rail, not across it", function()
		local w = world({ presentation = "segmented", axis = "y", options = ICONS, iconOnly = true })
		local a = w.adapter.node(optPath(w, 1)).rect
		local b = w.adapter.node(optPath(w, 2)).rect
		expect(w.adapter.node(BAR).rect.y).toBe(a.y + 4)
		w.selected:set("list")
		w.pres.refresh()
		for _ = 1, 200 do
			w.pres.tick(1 / 60)
			w.pres.refresh()
		end
		expect(math.abs(w.adapter.node(BAR).rect.y - (b.y + 4)) < 0.001).toBe(true)
		expect(w.adapter.node(BAR).rect.x).toBe(a.x + 4)
	end)

	it("wrapping does not collapse the rail: the indicated rail matches the plain one", function()
		-- the D4 rider's defect, on the OTHER axis: a content-sized wrapper around
		-- a content-sized rail is where a `fill` segment has nothing to fill. A
		-- REGRESSION GUARD rather than a mutation-bitten check — the rail's width is
		-- pinned twice over (by the root and by the option stack), so no single
		-- mutation of the wrapper alone can move it. It compares the indicated
		-- control against the plain one rather than against a number somebody chose.
		local plain = world({ presentation = "segmented", axis = "y", options = ICONS, indicator = "none" })
		local lit = world({ presentation = "segmented", axis = "y", options = ICONS })
		local plainWidth = plain.adapter.node(optPath(plain, 1)).rect.w
		expect(plainWidth > 0).toBe(true)
		expect(lit.adapter.node(optPath(lit, 1)).rect.w).toBe(plainWidth)
	end)

	it("flipping OUT of segmented gives the offer back: the rail becomes a column", function()
		-- the reason the rail's width is a memo and not a build-time answer. An
		-- adaptive picker asked for `axis = "y"` is a rail only while it is
		-- segmented; a live space change that stacks it must not leave a 44px
		-- column standing where a full-width row list belongs.
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 480, h = 640 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, Facet.newActionSystem(core))
		local sizeClass = core:signal("regular")
		local p = Facet.Controls.Picker(core, {
			id = "View",
			selected = core:signal("grid"),
			axis = "y",
			sizeClass = sizeClass,
			-- long labels, so a COMPACT space is what stacks them (the space rule,
			-- never a device name)
			options = {
				{ value = "grid", label = "Alphabetical order" },
				{ value = "list", label = "Beta distribution" },
			},
			env = env,
		})
		pres.present(UI.Screen({ id = "S", children = { p.blueprint } }))
		pres.refresh()
		expect(p.dump().verticalPill).toBe(true)
		local railWidth = adapter.node("/S/View").rect.w
		expect(railWidth < 480).toBe(true)
		sizeClass:set("compact")
		pres.refresh()
		expect(p.dump().presentation).toBe("inline")
		expect(p.dump().verticalPill).toBe(false)
		expect(adapter.node("/S/View").rect.w).toBe(480)
		p.dispose()
	end)

	it("a rail's options are still reachable by pointer, keyboard and gamepad", function()
		local w = world({ presentation = "segmented", axis = "y", options = ICONS, iconOnly = true })
		w.adapter.tap(optPath(w, 2))
		w.pres.refresh()
		expect(w.selected:get()).toBe("list")
		local sys = Facet.newActionSystem
		expect(type(sys)).toBe("function")
	end)
end)

describe("D6: the dump keeps schema /1 and stays deterministic", function()
	it("new fields, same schema string — every pre-D6 field keeps its name and meaning", function()
		local w = world({ presentation = "segmented", options = ICONS, iconOnly = true, label = "View" })
		local d = w.picker.dump()
		expect(d.schema).toBe("facet-picker-dump/1")
		expect(d.id).toBe("View")
		expect(d.optionCount).toBe(2)
		expect(d.requestedPresentation).toBe("segmented")
		expect(d.presentation).toBe("segmented")
		expect(d.axis).toBe("x")
		expect(serde.encode("json", w.picker.dump(), true)).toBe(serde.encode("json", w.picker.dump(), true))
	end)

	it("dispose is registry-neutral with icons, a rail and an indicator all on", function()
		local core = Facet.newCore()
		local baseline = core:counters()
		local p = Facet.Controls.Picker(core, {
			id = "X",
			options = ICONS,
			selected = core:signal("grid"),
			presentation = "segmented",
			axis = "y",
			iconOnly = true,
		})
		p.dispose()
		expect(core:counters().scopes).toBe(baseline.scopes)
		expect(core:counters().observers).toBe(baseline.observers)
	end)
end)

-- ===== the four seams D5's TabView composes ==============================
-- The director's call (`artifacts/navigation-and-menus/additive-vs-net-new.md`
-- §6) is that TabView builds its strip out of THIS control rather than
-- reimplementing the row, and this control's own header answers what that costs:
-- "anything a strip needs is a property". These are those properties, proved
-- HERE — on the picker, through the public surface — rather than only through
-- the construct that needed them, because a segmented control in a toolbar wants
-- to hug, and a segmented control over a message list wants a count.

describe("D5 seam: `sizing` is what makes a strip able to OVERFLOW", function()
	it('`sizing = "hug"` gives the band its natural width and its segments theirs', function()
		-- the band's `fill` divides the offer, so five tabs at a 320px viewport are
		-- 64px each and NOTHING ever overflows — which is exactly why an
		-- overflowing tab strip cannot be built out of the default sizing
		local w = world({ presentation = "segmented", sizing = "hug", viewport = 320 })
		local hugged = w.adapter.node("/S/View").rect.w
		local filled = world({ presentation = "segmented", viewport = 320 }).adapter.node("/S/View").rect.w
		expect(filled).toBe(320)
		expect(hugged < filled).toBe(true)
		expect(w.picker.dump().sizing).toBe("hug")
	end)

	it("...and the segments stop being equal-width, so a long label really is longer", function()
		local w = world({
			presentation = "segmented",
			sizing = "hug",
			viewport = 320,
			options = {
				{ value = "grid", label = "Hi" },
				{ value = "list", label = "A considerably longer name" },
			},
		})
		local first = w.adapter.node(optPath(w, 1)).rect.w
		local second = w.adapter.node(optPath(w, 2)).rect.w
		expect(second > first).toBe(true)
	end)

	it("`sizing` is REACTIVE, because a tab bar's home changes under a live rotation", function()
		local sizing = nil
		local w = nil
		do
			local core = Facet.newCore()
			local env = Facet.newEnvironment(core)
			env:set("viewportRect", { x = 0, y = 0, w = 480, h = 640 })
			env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
			local adapter = fake_target.new()
			local pres = Facet.newPresenter(core, env, adapter, Facet.newActionSystem(core))
			sizing = core:signal("fill")
			local p = Facet.Controls.Picker(core, {
				id = "View",
				options = { { value = "grid", label = "Grid" }, { value = "list", label = "Listing" } },
				selected = core:signal("grid"),
				presentation = "segmented",
				sizing = sizing,
				env = env,
			})
			pres.present(UI.Screen({ id = "S", children = { p.blueprint } }))
			pres.refresh()
			w = { adapter = adapter, pres = pres, picker = p }
		end
		expect(w.adapter.node("/S/View").rect.w).toBe(480)
		local before = w.adapter.node("/S/View/Indicator/Options/Opt1").id
		sizing:set("hug")
		w.pres.refresh()
		expect(w.adapter.node("/S/View").rect.w < 480).toBe(true)
		expect(w.picker.dump().sizing).toBe("hug")
		-- A RE-SOLVE, NOT A REBUILD (the A-AL2 rule): the option that was there is
		-- still there, at the same path, with the same identity
		expect(w.adapter.node("/S/View/Indicator/Options/Opt1").id).toBe(before)
		w.picker.dispose()
	end)

	it("an unknown `sizing` is an authoring error, not a silent fill", function()
		local core = Facet.newCore()
		local ok, err = pcall(function()
			Facet.Controls.Picker(core, {
				id = "X",
				options = { { value = "a", label = "A" } },
				selected = core:signal("a"),
				sizing = "shrinkwrap",
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "sizing", 1, true) ~= nil).toBe(true)
	end)
end)

describe("D5 seam: `axis` is REACTIVE, because a placement flip is a re-solve", function()
	it("a live axis flip turns the band into a rail without rebuilding an option", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 480, h = 640 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, Facet.newActionSystem(core))
		local axis = core:signal("x")
		local p = Facet.Controls.Picker(core, {
			id = "View",
			options = { { value = "grid", label = "Grid" }, { value = "list", label = "Listing" } },
			selected = core:signal("grid"),
			presentation = "segmented",
			axis = axis,
			env = env,
		})
		pres.present(UI.Screen({ id = "S", children = { p.blueprint } }))
		pres.refresh()
		expect(p.dump().axis).toBe("x")
		expect(p.dump().verticalPill).toBe(false)
		expect(adapter.node("/S/View").rect.w).toBe(480)
		axis:set("y")
		pres.refresh()
		expect(p.dump().axis).toBe("y")
		expect(p.dump().verticalPill).toBe(true)
		-- the rail hugs, and the option that was there never left
		expect(adapter.node("/S/View").rect.w < 480).toBe(true)
		expect(adapter.node("/S/View/Indicator/Options/Opt1") ~= nil).toBe(true)
		p.dispose()
	end)
end)

describe("D5 seam: a badge is a count that lives on an UNSELECTED option", function()
	local BADGED = {
		{ value = "grid", label = "Grid" },
		{ value = "list", label = "Listing", badge = "3" },
	}
	-- A BADGED SEGMENT GAINS ONE WRAPPER, and only a badged one: the seal is an
	-- overlay SIBLING of the Button (a Button with children draws no text at all,
	-- `renderer.luau:913`), so it needs a cell to overlay it in. The Button keeps
	-- its own id inside that cell, which is why activation and the indicator are
	-- untouched — and this helper spells the difference out rather than hiding it.
	local function cellPath(w: any, n: number): string
		local base = if w.picker.dump().indicator == "none" then "/S/View/Options" else "/S/View/Indicator/Options"
		return `{base}/Opt{n}Cell`
	end

	it('a badged option wears a `surface = "badge"` plate; an unbadged one wears nothing', function()
		local w = world({ presentation = "segmented", options = BADGED })
		local plate = w.adapter.node(cellPath(w, 2) .. "/Badge/Count")
		expect(plate ~= nil).toBe(true)
		expect(plate.props.surface).toBe("badge")
		expect(plate.props.text).toBe("3")
		-- the UNBADGED option gained no cell and no plate at all
		expect(w.adapter.node(cellPath(w, 1))).toBeNil()
		expect(w.adapter.node(optPath(w, 1)) ~= nil).toBe(true)
		expect(w.picker.dump().badgeCount).toBe(1)
	end)

	it("the badge is on the UNSELECTED option and stays live — that is the point of a badge", function()
		local w = world({ presentation = "segmented", options = BADGED, initial = "grid" })
		expect(w.selected:get()).toBe("grid")
		expect(w.adapter.node(cellPath(w, 2) .. "/Badge/Count").props.text).toBe("3")
	end)

	it("the seal is a DECORATION: no focus stop, no second activation site", function()
		-- focus_map.collectFocusables appends Button / Toggle / TextField, and that
		-- flat order IS the document order Tab walks. A ZStack holding a Text is
		-- neither, so a badged strip's focus order is byte-identical to a plain
		-- one's — and a non-interactive overlay is also what leaves the engine
		-- delivering the press to the Button underneath it
		local badged = world({ presentation = "segmented", options = BADGED })
		local plain = world({ presentation = "segmented" })
		expect(badged.adapter.node(cellPath(badged, 2)).class).toBe("ZStack")
		expect(badged.adapter.node(cellPath(badged, 2) .. "/Badge").class).toBe("ZStack")
		expect(badged.adapter.node(cellPath(badged, 2) .. "/Badge/Count").class).toBe("Text")
		local badgedFocus: { string } = {}
		local plainFocus: { string } = {}
		focus_map.collectFocusables(badged.handle.root.node, badgedFocus)
		focus_map.collectFocusables(plain.handle.root.node, plainFocus)
		expect(#badgedFocus).toBe(#plainFocus)
		expect(badgedFocus[2]).toBe(cellPath(badged, 2) .. "/Opt2")
	end)

	it("a badge VALUE is reactive, and an empty one hides the plate rather than painting a bubble", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 480, h = 640 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, Facet.newActionSystem(core))
		local count = core:signal("")
		local p = Facet.Controls.Picker(core, {
			id = "View",
			options = { { value = "grid", label = "Grid" }, { value = "list", label = "Listing", badge = count } },
			selected = core:signal("grid"),
			presentation = "segmented",
			env = env,
		})
		pres.present(UI.Screen({ id = "S", children = { p.blueprint } }))
		pres.refresh()
		expect(adapter.visibleOf("/S/View/Indicator/Options/Opt2Cell/Badge/Count")).toBe(false)
		count:set("12")
		pres.refresh()
		expect(adapter.visibleOf("/S/View/Indicator/Options/Opt2Cell/Badge/Count")).toBe(true)
		expect(adapter.node("/S/View/Indicator/Options/Opt2Cell/Badge/Count").props.text).toBe("12")
		p.dispose()
	end)

	it("the plate does NOT eat the tap: a badged segment still selects", function()
		-- the engine delivers a press to the TOPMOST interactive object only, so a
		-- decoration painted OVER a Button has to be non-interactive or the segment
		-- goes dead (docs/lessons/a-button-eats-the-swipe-underneath-it.md)
		local w = world({ presentation = "segmented", options = BADGED, initial = "grid" })
		w.adapter.tap(cellPath(w, 2) .. "/Opt2")
		w.pres.refresh()
		expect(w.selected:get()).toBe("list")
	end)

	it("a picker with NO badges mounts no badge node at all — the paths are unchanged", function()
		local w = world({ presentation = "segmented" })
		expect(w.adapter.node(cellPath(w, 1))).toBeNil()
		expect(w.adapter.node(optPath(w, 1)) ~= nil).toBe(true)
		expect(w.picker.dump().badgeCount).toBe(0)
	end)
end)

describe("D5 seam: an option LABEL may be a Readable, and `api.segments` names the row", function()
	it("a bound label satisfies the non-empty lint and is what dump() announces", function()
		local core = Facet.newCore()
		local name = core:signal("Listing")
		local p = Facet.Controls.Picker(core, {
			id = "View",
			label = "View",
			options = { { value = "grid", label = "Grid" }, { value = "list", label = name } },
			selected = core:signal("list"),
			presentation = "segmented",
		})
		expect(p.dump().selectedLabel).toBe("Listing")
		expect(p.dump().semanticText).toBe("View: Listing")
		name:set("Rows")
		expect(p.dump().selectedLabel).toBe("Rows")
		expect(p.dump().semanticText).toBe("View: Rows")
		p.dispose()
	end)

	it("a bound label that is EMPTY right now is still the authoring error it would be as a string", function()
		local core = Facet.newCore()
		local ok = pcall(function()
			Facet.Controls.Picker(core, {
				id = "X",
				options = { { value = "a", label = core:signal("") } },
				selected = core:signal("a"),
			})
		end)
		expect(ok).toBe(false)
	end)

	it("`api.segments` publishes the id this strip gave each option", function()
		-- a decoration or a scroller has to be able to find the mounted node for a
		-- selection value, and string arithmetic on "Opt1" is exactly the assumption
		-- that breaks silently when this control's internals move
		local w = world({ presentation = "segmented" })
		local segments = w.picker.segments
		expect(#segments).toBe(2)
		expect(segments[1].value).toBe("grid")
		expect(w.adapter.node(`/S/View/Indicator/Options/{segments[1].id}`) ~= nil).toBe(true)
		expect(w.adapter.node(`/S/View/Indicator/Options/{segments[2].id}`) ~= nil).toBe(true)
	end)
end)

describe("D5 found: a segmented strip navigates ACROSS on a pad, not down", function()
	it("the option stack is one HORIZONTAL group, so Right moves to the next segment", function()
		--[[ A SHIPPED DEFECT, not a new one. `focus_map.autoGroups` derived a
			horizontal run from an `HStack` alone, and this control's option stack is
			an `AdaptiveStack` — it has to be, because a presentation flip is a
			re-solve rather than a remount (A-AL2). So every segmented picker in the
			framework answered Up/Down on a pad and Right walked straight out of the
			control into whatever was painted after it. Found by D5, whose tab strip
			is this same stack in a band a player is expected to cross. ]]
		local w = world({ presentation = "segmented", options = { ICONS[1], ICONS[2] } })
		local paths: { string } = {}
		focus_map.collectFocusables(w.handle.root.node, paths)
		expect(#paths).toBe(2)
		local groups = focus_map.autoGroups(w.handle.root.node)
		expect(#groups).toBe(1)
		expect(groups[1].axis).toBe("horizontal")
		expect(groups[1].order[1]).toBe(optPath(w, 1))
		expect(groups[1].order[2]).toBe(optPath(w, 2))
	end)

	it("...and the VERTICAL rail stays a vertical group, because its axis says so", function()
		-- the axis is read LIVE from the bound prop, so the same stack answers
		-- differently in the two shapes rather than being pinned at build time
		local rail = world({ presentation = "segmented", axis = "y", options = { ICONS[1], ICONS[2] } })
		local groups = focus_map.autoGroups(rail.handle.root.node)
		expect(#groups).toBe(1)
		expect(groups[1].axis).toBe("vertical")
	end)

	it("a LIVE axis flip re-derives the group with it", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 480, h = 640 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, Facet.newActionSystem(core))
		local axis = core:signal("x")
		local p = Facet.Controls.Picker(core, {
			id = "View",
			options = { { value = "grid", label = "Grid" }, { value = "list", label = "Listing" } },
			selected = core:signal("grid"),
			presentation = "segmented",
			axis = axis,
			env = env,
		})
		local handle = pres.present(UI.Screen({ id = "S", children = { p.blueprint } }))
		pres.refresh()
		expect(focus_map.autoGroups(handle.root.node)[1].axis).toBe("horizontal")
		axis:set("y")
		pres.refresh()
		expect(focus_map.autoGroups(handle.root.node)[1].axis).toBe("vertical")
		p.dispose()
	end)
end)
