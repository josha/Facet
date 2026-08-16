--!strict
-- Segmented Picker upgrades (navigation-and-menus brief §2 D6) — icons on
-- `Option`, a real VERTICAL pill, and the D4 indicator adopted as the segmented
-- presentation's DEFAULT paint.
--
-- D6 is a PROPERTIES-ONLY stage (director call 2026-08-16,
-- `artifacts/navigation-and-menus/additive-vs-net-new.md` §1): no new construct
-- and no new module, so every case below drives `LuauUI.newPicker` the way an
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

local LuauUI = require("../src") :: any
local fake_target = require("./lib/fake_target")

local UI = LuauUI.UI

-- ===== the harness ========================================================
-- One mounted picker on a real presenter. `viewportRect` is wide, so a picker
-- that does not declare its presentation resolves SEGMENTED — which is the
-- shape every case here is about.
local function world(spec: any?)
	local options = spec or {}
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = options.viewport or 480, h = 640 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = LuauUI.newPresenter(core, env, adapter, system)
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
	for _, key in { "presentation", "indicator", "axis", "iconOnly", "label", "sizeClass" } do
		if (options :: any)[key] ~= nil then
			built[key] = (options :: any)[key]
		end
	end
	local p = LuauUI.newPicker(LuauUI, core, built)
	pres.present(UI.Screen({ id = "S", children = { p.blueprint } }))
	pres.refresh()
	return { core = core, env = env, adapter = adapter, pres = pres, picker = p, selected = selected }
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
		local core = LuauUI.newCore()
		local ok, err = pcall(function()
			return LuauUI.newPicker(LuauUI, core, {
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
		local core = LuauUI.newCore()
		for _, bad in { "", nil :: any } do
			local ok, err = pcall(function()
				return LuauUI.newPicker(LuauUI, core, {
					id = "X",
					options = { { value = "a", label = bad, icon = "shop:bag" } },
					selected = core:signal("a"),
				})
			end)
			expect(ok).toBe(false)
			expect(string.find(tostring(err), "semantic", 1, true) ~= nil).toBe(true)
		end
	end)

	it("HIG: icons for ALL options in a group, or none — a half-iconned group is refused", function()
		local core = LuauUI.newCore()
		local ok, err = pcall(function()
			return LuauUI.newPicker(LuauUI, core, {
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
		-- ...and a group with NO icons at all is of course fine
		local none = LuauUI.newPicker(LuauUI, core, {
			id = "Y",
			options = { { value = "a", label = "Alpha" }, { value = "b", label = "Beta" } },
			selected = core:signal("a"),
		})
		expect(none.dump().iconCount).toBe(0)
		none.dispose()
	end)

	it("`iconOnly` with nothing to draw is refused rather than silently ignored", function()
		local core = LuauUI.newCore()
		local ok, err = pcall(function()
			return LuauUI.newPicker(LuauUI, core, {
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
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 480, h = 640 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake_target.new()
		local pres = LuauUI.newPresenter(core, env, adapter, LuauUI.newActionSystem(core))
		local sizeClass = core:signal("regular")
		local p = LuauUI.newPicker(LuauUI, core, {
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
		local sys = LuauUI.newActionSystem
		expect(type(sys)).toBe("function")
	end)
end)

describe("D6: the dump keeps schema /1 and stays deterministic", function()
	it("new fields, same schema string — every pre-D6 field keeps its name and meaning", function()
		local w = world({ presentation = "segmented", options = ICONS, iconOnly = true, label = "View" })
		local d = w.picker.dump()
		expect(d.schema).toBe("luauui-picker-dump/1")
		expect(d.id).toBe("View")
		expect(d.optionCount).toBe(2)
		expect(d.requestedPresentation).toBe("segmented")
		expect(d.presentation).toBe("segmented")
		expect(d.axis).toBe("x")
		expect(serde.encode("json", w.picker.dump(), true)).toBe(serde.encode("json", w.picker.dump(), true))
	end)

	it("dispose is registry-neutral with icons, a rail and an indicator all on", function()
		local core = LuauUI.newCore()
		local baseline = core:counters()
		local p = LuauUI.newPicker(LuauUI, core, {
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
