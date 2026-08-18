--!strict
--[[ WAVE REVEAL — a stepped-down region EXPANDS to its richest form.

	The knob is `expand`: `reveal` is already UI.Text's marquee prop and `disclose`
	is already its truncation policy, so a third meaning on the same surface would
	be the collision this name avoids.

	The ladder in `src/layout/composition.luau` steps a region down and then drops
	it, and D7.1 gave every one of those events a stated ROUTE. What no route
	covered is the commonest one of all: a region that stepped DOWN and whose
	author declared `recover = "self"` — "the reduced form IS the route" — had to
	hand-author the tap target, the focus stop, the plate and the dismissal in
	every zone of every screen. Measured on the HUD showcase: the one zone that
	did it (`Tasks`) is 40 lines of fixture code, and the seven that did not sent
	their content to the overflow sink instead, which is two navigations away from
	a thing that is standing right there on the screen.

	This file is the proof of the framework doing it. Four layers, in order:

	  1. THE PURE FACTS — `activeForm` / `richestForm` / `formInteractive` /
	     `expand` / `expandable` on the resolution, and the plate SIZE (with its
	     sheet fallback) decided by the same pure pass that decided the ladder, so
	     the device matrix stays a headless sweep.
	  2. THE AUTHORING BOUNDARY — `UI.Region{ expand = … }`, refused where it
	     cannot mean anything, and the per-form INTERACTIVITY read off the class
	     contract rather than guessed.
	  3. THE GEOMETRY — the affordance the framework synthesizes: a full-cover
	     activation surface over a PASSIVE compact form, a chevron beside an
	     INTERACTIVE one, hidden (and therefore out of focus order) at the richest
	     form and under `expand = "none"`.
	  4. THE PRESENTATION — the anchored plate itself: what opens it, what closes
	     it, and that nothing is left behind when it goes.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local composition = require("../src/layout/composition")

-- ===== 1. THE PURE FACTS ===================================================
-- One region per case, measured from a table, exactly as `composition.spec`
-- drives the ladder: no mount, no theme, no engine.

local function measureFrom(sizes: { [string]: { { w: number, h: number } } })
	return function(id: string, form: number, availW: number, _availH: number): (number, number)
		local forms = sizes[id]
		if forms == nil then
			return 0, 0
		end
		local entry = forms[math.min(form, #forms)]
		-- the honest measure a composition gets: the content's own width, NOT
		-- clamped to the offer, so a form that cannot fit says so
		return entry.w, entry.h
	end
end

local function decl(regions: { any }): any
	return {
		id = "Screen",
		groups = { { id = "body", lane = "main", sizing = "fill" } },
		regions = regions,
		arrangements = { { name = "column", lanes = { { "main" } } } },
	}
end

describe("EXPAND 1 — the resolution states which form is standing and whether it is a dead end", function()
	local SIZES = {
		Clock = { { w = 200, h = 60 }, { w = 60, h = 20 } },
	}

	it("a region at its richest form reports activeForm 1 and nothing to expand to", function()
		local res = composition.resolve(
			decl({ { id = "Clock", group = "body", rank = 1, forms = 2, recover = "overflow" } }),
			{ w = 400, h = 400 },
			{ measure = measureFrom(SIZES) }
		)
		local r = res.regionById.Clock
		expect(r.activeForm).toBe(1)
		expect(r.richestForm).toBe(1)
		expect(r.expandable).toBe(false)
	end)

	it("a stepped-down region reports the form it landed on, and that an expansion exists", function()
		local res = composition.resolve(
			decl({ { id = "Clock", group = "body", rank = 1, forms = 2, recover = "overflow" } }),
			{ w = 400, h = 30 },
			{ measure = measureFrom(SIZES) }
		)
		local r = res.regionById.Clock
		expect(r.activeForm).toBe(2)
		expect(r.richestForm).toBe(1)
		expect(r.expandable).toBe(true)
		expect(r.expand).toBe("auto")
	end)

	it("a DROPPED region has no active form, so it is never expandable — drops stay sheet-only", function()
		local res = composition.resolve(
			decl({
				{ id = "Clock", group = "body", rank = 2, forms = 2, recover = "overflow", mayDrop = true },
				{ id = "Big", group = "body", rank = 1, forms = 1, floor = nil },
			}),
			{ w = 400, h = 30 },
			{ measure = measureFrom({ Clock = SIZES.Clock, Big = { { w = 30, h = 30 } } }) }
		)
		local r = res.regionById.Clock
		expect(r.dropped).toBe(true)
		expect(r.activeForm).toBe(0)
		expect(r.expandable).toBe(false)
	end)

	it('expand = "none" is the authored escape: stepped down, and nothing to expand', function()
		local res = composition.resolve(
			decl({ { id = "Clock", group = "body", rank = 1, forms = 2, recover = "overflow", expand = "none" } }),
			{ w = 400, h = 30 },
			{ measure = measureFrom(SIZES) }
		)
		local r = res.regionById.Clock
		expect(r.activeForm).toBe(2)
		expect(r.expand).toBe("none")
		expect(r.expandable).toBe(false)
	end)

	it("formInteractive is the ACTIVE form's own answer, read from the declaration", function()
		local d = decl({
			{
				id = "Clock",
				group = "body",
				rank = 1,
				forms = 2,
				recover = "overflow",
				-- form 1 holds buttons, form 2 is a bare figure
				formInteractive = { true, false },
			},
		})
		local rich = composition.resolve(d, { w = 400, h = 400 }, { measure = measureFrom(SIZES) })
		expect(rich.regionById.Clock.formInteractive).toBe(true)
		local poor = composition.resolve(d, { w = 400, h = 30 }, { measure = measureFrom(SIZES) })
		expect(poor.regionById.Clock.formInteractive).toBe(false)
	end)

	it("a dropped region's formInteractive is false — there is no form to be interactive", function()
		local res = composition.resolve(
			decl({
				{
					id = "Clock",
					group = "body",
					rank = 2,
					forms = 2,
					recover = "overflow",
					mayDrop = true,
					formInteractive = { true, true },
				},
				{ id = "Big", group = "body", rank = 1, forms = 1 },
			}),
			{ w = 400, h = 30 },
			{ measure = measureFrom({ Clock = SIZES.Clock, Big = { { w = 30, h = 30 } } }) }
		)
		expect(res.regionById.Clock.dropped).toBe(true)
		expect(res.regionById.Clock.formInteractive).toBe(false)
	end)

	it("the declaration refuses an expand mode it cannot honour", function()
		expect(function()
			composition.normalize(
				decl({ { id = "Clock", group = "body", rank = 1, forms = 2, recover = "overflow", expand = "maybe" } })
			)
		end).toThrow()
		expect(function()
			composition.normalize(
				decl({ { id = "Clock", group = "body", rank = 1, forms = 2, recover = "overflow", formInteractive = 3 } })
			)
		end).toThrow()
	end)
end)

describe("EXPAND 2 — the plate is sized by the same pure pass, and says when it cannot be one", function()
	local SIZES = {
		Clock = { { w = 200, h = 60 }, { w = 60, h = 20 } },
	}

	it("the plate is the richest form's own width, capped at the viewport minus gutters", function()
		local res = composition.resolve(
			decl({ { id = "Clock", group = "body", rank = 1, forms = 2, recover = "overflow" } }),
			{ w = 100, h = 30 },
			{ measure = measureFrom(SIZES), expandGutter = 8 }
		)
		local plate = res.regionById.Clock.plate
		expect(plate).never().toBeNil()
		-- 200 wanted, 100 - 2*8 offered: the cap wins and the form does not fit in it
		expect(plate.w).toBe(84)
		expect(plate.sheet).toBe(true)
	end)

	it("...and reports sheet = false when the richest form fits the plate", function()
		local res = composition.resolve(
			decl({ { id = "Clock", group = "body", rank = 1, forms = 2, recover = "overflow" } }),
			{ w = 400, h = 30 },
			{ measure = measureFrom(SIZES), expandGutter = 8 }
		)
		local r = res.regionById.Clock
		expect(r.activeForm).toBe(2)
		expect(r.plate.w).toBe(200)
		expect(r.plate.h).toBe(60)
		expect(r.plate.sheet).toBe(false)
	end)

	it("a region with nothing to expand is not measured for a plate", function()
		local res = composition.resolve(
			decl({ { id = "Clock", group = "body", rank = 1, forms = 2, recover = "overflow", expand = "none" } }),
			{ w = 100, h = 30 },
			{ measure = measureFrom(SIZES), expandGutter = 8 }
		)
		expect(res.regionById.Clock.plate).toBeNil()
	end)
end)

describe("EXPAND 3 — the dump carries the facts, and two calls are equal", function()
	local SIZES = {
		Clock = { { w = 200, h = 60 }, { w = 60, h = 20 } },
	}

	it("every region row states the form standing, the richest one, and the route", function()
		local res = composition.resolve(
			decl({ { id = "Clock", group = "body", rank = 1, forms = 2, recover = "overflow" } }),
			{ w = 100, h = 30 },
			{ measure = measureFrom(SIZES), expandGutter = 8 }
		)
		local dump = composition.dump(res)
		local row = dump.regions[1]
		expect(row.activeForm).toBe(2)
		expect(row.richestForm).toBe(1)
		expect(row.formInteractive).toBe(false)
		expect(row.expand).toBe("auto")
		expect(row.expandable).toBe(true)
		expect(row.plate.sheet).toBe(true)
		expect(dump).toEqual(composition.dump(res))
	end)
end)

-- ===== 2. THE AUTHORING BOUNDARY ===========================================
-- What an author writes, what the framework refuses, and the ONE thing it adds
-- to the tree: the affordance. Blueprints are plain frozen tables, so every
-- assertion here reads the declaration the mount would have received.

local UI = require("../src/blueprint")
local customFactory = require("../src/core/custom")

local function childrenOf(node: any): { any }
	return node.children or {}
end

local function expandNodes(region: any): { any }
	local out = {}
	for _, child in childrenOf(region) do
		if string.sub(child.id or "", 1, 6) == "Expand" then
			table.insert(out, child)
		end
	end
	return out
end

local function textForm(id: string): any
	return UI.VStack({ id = id, children = { UI.Text({ id = id .. "Line", text = "2:14" }) } })
end

describe("EXPAND 4 — the authoring surface is one word, and it is refused where it cannot mean anything", function()
	it("a multi-form region gets ONE affordance, whatever the depth of its ladder", function()
		local region = UI.Region({
			id = "Clock",
			group = "body",
			rank = 1,
			recover = "overflow",
			children = { textForm("Full"), textForm("Mid"), textForm("Tiny") },
		})
		local affordances = expandNodes(region)
		expect(#affordances).toBe(1)
		expect(affordances[1].class).toBe("Button")
		expect(affordances[1].id).toBe("Expand")
		-- it is the LAST child, which is what makes it findable under a `UI.When`
		-- form that spliced itself away, and what puts its focus stop after the
		-- form's own stops in document order
		expect(childrenOf(region)[4].id).toBe("Expand")
		-- the record states the DECLARED form count, which `#children` no longer is
		expect(region.props.expand.forms).toBe(3)
	end)

	it("the affordance says what it does, in the words a screen reader will read", function()
		local region = UI.Region({
			id = "Clock",
			group = "body",
			rank = 1,
			recover = "overflow",
			children = { textForm("Full"), textForm("Tiny") },
		})
		expect(expandNodes(region)[1].props.label).toBe("expands to full Clock")
	end)

	it('expand = "none" is the authored escape and synthesizes nothing at all', function()
		local region = UI.Region({
			id = "Clock",
			group = "body",
			rank = 1,
			recover = "overflow",
			expand = "none",
			children = { textForm("Full"), textForm("Tiny") },
		})
		expect(#expandNodes(region)).toBe(0)
		expect(#childrenOf(region)).toBe(2)
	end)

	it('recover = "none" states nothing is missing, so nothing is synthesized either', function()
		local region = UI.Region({
			id = "Rounds",
			group = "body",
			rank = 1,
			recover = "none",
			children = { textForm("Wide"), textForm("Wrapped") },
		})
		expect(#expandNodes(region)).toBe(0)
	end)

	it("a ONE-FORM region never simplifies, so declaring an expand on one is refused", function()
		expect(function()
			UI.Region({
				id = "Sink",
				group = "body",
				rank = 1,
				expand = "auto",
				children = { textForm("Only") },
			})
		end).toThrow()
	end)

	it("an unknown expand mode is refused at the call site", function()
		expect(function()
			UI.Region({
				id = "Clock",
				group = "body",
				rank = 1,
				recover = "overflow",
				expand = "sometimes",
				children = { textForm("Full"), textForm("Tiny") },
			})
		end).toThrow()
	end)
end)

describe("EXPAND 5 — one gesture, one meaning: the form's own controls decide the shape", function()
	it("a PASSIVE form is the target itself — the affordance covers it and draws nothing", function()
		local region = UI.Region({
			id = "Clock",
			group = "body",
			rank = 1,
			recover = "overflow",
			children = { textForm("Full"), textForm("Tiny") },
		})
		local aff = expandNodes(region)[1]
		expect(aff.props.surface).toBe("plain")
		-- the record the solver reads: form 2 contributes nothing to focus or action,
		-- so the affordance is the form's own box rather than a mark beside it
		expect(region.props.expand.interactive[2]).toBe(false)
		expect(aff.props.expandTarget.role).toBe("cover")
		expect(childrenOf(aff)[1].id).toBe("Zone")
	end)

	it("an INTERACTIVE form keeps its own meanings and gets a chevron beside it", function()
		local region = UI.Region({
			id = "Tasks",
			group = "body",
			rank = 1,
			recover = "overflow",
			children = {
				textForm("Full"),
				UI.VStack({
					id = "Chip",
					children = { UI.Button({ id = "Open", label = "Tasks 1/3", onActivate = function() end }) },
				}),
			},
		})
		local aff = expandNodes(region)[1]
		expect(region.props.expand.interactive[2]).toBe(true)
		expect(aff.props.expandTarget.role).toBe("chevron")
		-- ...and it carries a MARK, so it reads as an affordance rather than a gap
		expect(childrenOf(aff)[1].id).toBe("Caret")
	end)

	it("interactivity is the class CONTRACT's answer, not a list of button names", function()
		-- a ScrollView contributes the `Scroll` action and no focus stop; overloading
		-- a scrollable compact form with a tap-to-expand is exactly the collision the
		-- chevron exists to avoid, so it counts as interactive
		local region = UI.Region({
			id = "Feed",
			group = "body",
			rank = 1,
			recover = "overflow",
			children = {
				textForm("Full"),
				UI.ScrollView({ id = "Scroller", children = { UI.Text({ id = "Line", text = "…" }) } }),
			},
		})
		expect(region.props.expand.interactive[2]).toBe(true)
	end)

	it("content the framework CANNOT see is taken as interactive — a lazy region is never covered", function()
		local region = UI.Region({
			id = "Lazy",
			group = "body",
			rank = 1,
			recover = "overflow",
			children = {
				textForm("Full"),
				UI.VStack({
					id = "Maybe",
					children = {
						UI.When({
							id = "Gate",
							condition = customFactory.new():signal(true),
							thenView = function()
								return UI.Button({ id = "Hidden", label = "go", onActivate = function() end })
							end,
						}),
					},
				}),
			},
		})
		expect(region.props.expand.interactive[2]).toBe(true)
	end)
end)

describe("EXPAND 6 — the framework's affordance IS the self route", function()
	it("a ladder that is passive at one rung and interactive at another takes the chevron", function()
		local region = UI.Region({
			id = "Mixed",
			group = "body",
			rank = 1,
			recover = "overflow",
			children = {
				textForm("Full"),
				textForm("Passive"),
				UI.VStack({
					id = "Live",
					children = { UI.Button({ id = "Go", label = "go", onActivate = function() end }) },
				}),
			},
		})
		-- ONE affordance serves the whole ladder, so its shape is decided by the
		-- rung that would COLLIDE: never overload a control, even at the rungs that
		-- have none
		expect(expandNodes(region)[1].props.expandTarget.role).toBe("chevron")
		expect(region.props.expand.interactive).toEqual({ false, false, true })
	end)

	it('recover = "self" no longer needs a hand-authored control in every reduced form', function()
		local region = UI.Region({
			id = "Tasks",
			group = "body",
			rank = 1,
			recover = "self",
			children = { textForm("Full"), textForm("Chip") },
		})
		expect(#expandNodes(region)).toBe(1)
	end)

	it('...but with expand = "none" the route has to be there, and the boundary still says so', function()
		expect(function()
			UI.Region({
				id = "Tasks",
				group = "body",
				rank = 1,
				recover = "self",
				expand = "none",
				children = { textForm("Full"), textForm("Chip") },
			})
		end).toThrow()
	end)
end)

-- ===== 3. THE GEOMETRY =====================================================
-- The affordance is a real node in the region, so everything it needs — being
-- out of focus order when it is not standing, the 44px hit floor, its place in
-- document order — is the machinery the framework already had. What is new is
-- WHERE the solver puts it, and that it puts it nowhere at all at the richest
-- form. Mounted over the fake target, so these are solved rects.

local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local fake_target = require("./lib/fake_target")

local function fixedBox(id: string, w: number, h: number): any
	return UI.Box({ id = id, width = { type = "fixed", px = w }, height = { type = "fixed", px = h } })
end

-- ONE region, one lane, two forms: the smallest declaration that can collapse.
local function screenOf(opts: { interactive: boolean?, expand: any })
	local compact: any
	if opts.interactive then
		-- FILL width on purpose: a form that takes whatever it is granted is the
		-- only shape that can prove the chevron was RESERVED rather than laid over
		compact = UI.VStack({
			id = "Compact",
			width = { type = "fill", weight = 1 },
			children = { UI.Button({ id = "Live", label = "live", onActivate = function() end }) },
		})
	else
		compact = fixedBox("Compact", 60, 20)
	end
	return UI.Screen({
		id = "S",
		width = { type = "fill", weight = 1 },
		height = { type = "fill", weight = 1 },
		children = {
			UI.Composition({
				id = "C",
				arrangements = { "column" },
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				groups = { { id = "body", lane = "main", sizing = "fill" } },
				children = {
					UI.Region({
						id = "Clock",
						group = "body",
						rank = 1,
						recover = "overflow",
						expand = opts.expand,
						children = { fixedBox("Full", 200, 60), compact },
					}),
				},
			}),
		},
	})
end

local function mountedAt(w: number, h: number, opts: any)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = w, h = h })
	local root = mountLib.mount(core, screenOf(opts))
	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
	controller.initialRender()
	return adapter, controller
end

describe("EXPAND 7 — the affordance stands exactly while a reduced form does", function()
	it("at the richest form it has a zero rect and is hidden, so nothing can focus it", function()
		local adapter, controller = mountedAt(400, 400, { expand = nil })
		expect(controller.compositionAt("/S/C").regions[1].activeForm).toBe(1)
		expect(adapter.node("/S/C/Clock/Expand").rect.w).toBe(0)
		expect(controller.hiddenRoots()["/S/C/Clock/Expand"]).toBe(true)
	end)

	it("stepped down, a PASSIVE form is covered by it exactly", function()
		local adapter, controller = mountedAt(400, 30, { expand = nil })
		expect(controller.compositionAt("/S/C").regions[1].activeForm).toBe(2)
		local region = adapter.node("/S/C/Clock").rect
		local affordance = adapter.node("/S/C/Clock/Expand").rect
		expect(affordance.x).toBe(region.x)
		expect(affordance.y).toBe(region.y)
		expect(affordance.w).toBe(region.w)
		expect(affordance.h).toBe(region.h)
		expect(controller.hiddenRoots()["/S/C/Clock/Expand"]).toBe(nil)
	end)

	it("stepped down, an INTERACTIVE form keeps its box and the chevron takes the trailing edge", function()
		local adapter, controller = mountedAt(400, 30, { interactive = true, expand = nil })
		expect(controller.compositionAt("/S/C").regions[1].formInteractive).toBe(true)
		local region = adapter.node("/S/C/Clock").rect
		local chevron = adapter.node("/S/C/Clock/Expand").rect
		local form = adapter.node("/S/C/Clock/Compact").rect
		expect(chevron.w > 0).toBe(true)
		-- the mark is at the trailing edge, and the form stops short of it: the
		-- affordance is BESIDE the compact form, never over it
		expect(chevron.x + chevron.w).toBe(region.x + region.w)
		expect(form.x + form.w <= chevron.x).toBe(true)
	end)

	it('expand = "none" synthesizes nothing, so the region is exactly its forms', function()
		local adapter, controller = mountedAt(400, 30, { expand = "none" })
		expect(controller.compositionAt("/S/C").regions[1].expandable).toBe(false)
		expect(adapter.node("/S/C/Clock/Expand")).toBeNil()
	end)

	it("the affordance is not a FORM: the ladder still has exactly two rungs", function()
		local _, controller = mountedAt(400, 400, { expand = nil })
		-- form 1 at a 400x400 offer, form 2 at 400x30 — a third rung would mean the
		-- affordance had been counted as one, and the ladder would step onto it
		expect(controller.compositionAt("/S/C").regions[1].activeForm).toBe(1)
		local _, tight = mountedAt(400, 30, { expand = nil })
		expect(tight.compositionAt("/S/C").regions[1].activeForm).toBe(2)
	end)
end)
