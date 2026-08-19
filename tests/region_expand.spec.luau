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
			composition.normalize(decl({
				{ id = "Clock", group = "body", rank = 1, forms = 2, recover = "overflow", formInteractive = 3 },
			}))
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

-- ===== 4. THE PRESENTATION =================================================
-- What opens the plate, what closes it, and that nothing is left behind. The
-- engine is a root leaf that requires nothing, so the first block drives it with
-- two table doubles and no mount at all; the second closes the loop through the
-- real presenter, a real tap and a real surface stack.

local regionExpand = require("../src/region_expand")

local PLATE = { w = 200, h = 60, sheet = false }

--[[ A CONTROLLER DOUBLE. `compositionAt(path)` is the renderer's own published
	resolution dump, keyed by the composition's path, and `rectOf` is the solved
	rect — the two facts the engine reads and the only two. ]]
local function fakeController(row: any, rect: any)
	return {
		compositionAt = function(path: string)
			if path ~= "/S/C" then
				return nil
			end
			return { regions = { row } }
		end,
		rectOf = function(_path: string)
			return rect
		end,
	}
end

local function engineWith(row: any, rect: any, handler: (() -> ())?)
	local presented: { any } = {}
	local dismissed: { any } = {}
	local engine = regionExpand.new({
		id = "Clock",
		panelOf = function(w: number)
			return { class = "VStack", id = "ExpandPanel", plateWidth = w }
		end,
		sheetOf = function()
			return { class = "Screen", id = "ExpandSheet" }
		end,
		handler = handler,
	})
	engine.contribution.bindController(fakeController(row, rect))
	--[[ THE HANDLE CARRIES `onFeedback`, exactly as the presenter's does: it is how
		a surface tells its owner about a teardown the owner did not drive (an
		outside tap), and a double without it would let this engine pass a test the
		Menu and row_actions each failed live. ]]
	local function handleOf(kind: string, panel: any, opts: any)
		local handle: any = { kind = kind, panel = panel, opts = opts, listeners = {} }
		function handle.onFeedback(fn: (any) -> ())
			table.insert(handle.listeners, fn)
		end
		function handle.fireDismiss()
			for _, fn in handle.listeners do
				fn({ type = "dismiss" })
			end
		end
		return handle
	end
	engine.contribution.bindPresent(function(panel: any, opts: any)
		local handle = handleOf("sheet", panel, opts)
		table.insert(presented, handle)
		return handle
	end, function(handle: any)
		table.insert(dismissed, handle)
	end, function(panel: any, opts: any)
		local handle = handleOf("anchored", panel, opts)
		table.insert(presented, handle)
		return handle
	end)
	engine.contribution.syncGeometry(function(_p: string)
		return rect
	end, { path = "/S/C/Clock" })
	return engine, presented, dismissed
end

local STEPPED = { id = "/S/C/Clock", expandable = true, activeForm = 2, plate = PLATE }
local RICHEST = { id = "/S/C/Clock", expandable = false, activeForm = 1 }
local BOX = { x = 10, y = 20, w = 120, h = 30 }

describe("EXPAND 8 — the plate, and every way out of it", function()
	it("opens ANCHORED against the region's own rect, at the width the composition sized", function()
		local engine, presented = engineWith(STEPPED, BOX)
		expect(engine.open()).toBe("anchored")
		expect(#presented).toBe(1)
		expect(presented[1].kind).toBe("anchored")
		expect(presented[1].panel.plateWidth).toBe(200)
		expect(presented[1].opts.anchor.source.path).toBe("/S/C/Clock")
	end)

	it("falls back to the full-width SHEET where the richest form cannot meet its floor", function()
		local engine, presented = engineWith({
			id = "/S/C/Clock",
			expandable = true,
			activeForm = 2,
			plate = { w = 84, h = 60, sheet = true },
		}, BOX)
		expect(engine.open()).toBe("sheet")
		expect(presented[1].kind).toBe("sheet")
		expect(presented[1].panel.id).toBe("ExpandSheet")
	end)

	it("opens NOTHING at the richest form — there is nothing more to show", function()
		local engine, presented = engineWith(RICHEST, BOX)
		expect(engine.open()).toBeNil()
		expect(#presented).toBe(0)
	end)

	it("a second activation closes it, so the affordance is never inert under a thumb", function()
		local engine, presented, dismissed = engineWith(STEPPED, BOX)
		engine.open()
		expect(engine.open()).toBeNil()
		expect(#presented).toBe(1)
		expect(#dismissed).toBe(1)
		expect(engine.state()).toBe("closed")
		expect(engine.teardowns()).toBe(1)
	end)

	it("an EPOCH change closes it: the rect it was opened against moved", function()
		local engine, _, dismissed = engineWith(STEPPED, BOX)
		engine.open()
		engine.sync(function(_p: string)
			-- the rotation: the same region, a different box
			return { x = 200, y = 20, w = 120, h = 30 }
		end, { path = "/S/C/Clock" })
		expect(#dismissed).toBe(1)
		expect(engine.state()).toBe("closed")
	end)

	it("...and so does the region GOING: a zero rect is a source that is not there", function()
		local engine, _, dismissed = engineWith(STEPPED, BOX)
		engine.open()
		engine.sync(function(_p: string)
			return { x = 0, y = 0, w = 0, h = 0 }
		end, { path = "/S/C/Clock" })
		expect(#dismissed).toBe(1)
	end)

	it("...and so does the region climbing back to its richest form under the plate", function()
		local engine = regionExpand.new({
			id = "Clock",
			panelOf = function(_w: number)
				return { class = "VStack" }
			end,
			sheetOf = function()
				return { class = "Screen" }
			end,
		})
		local row: any = { id = "/S/C/Clock", expandable = true, activeForm = 2, plate = PLATE }
		local dismissed = 0
		engine.contribution.bindController(fakeController(row, BOX))
		engine.contribution.bindPresent(nil, function()
			dismissed += 1
		end, function()
			return { kind = "anchored" }
		end)
		engine.contribution.syncGeometry(function()
			return BOX
		end, { path = "/S/C/Clock" })
		engine.open()
		row.expandable = false
		row.activeForm = 1
		engine.sync(function()
			return BOX
		end, { path = "/S/C/Clock" })
		expect(dismissed).toBe(1)
		expect(engine.teardowns()).toBe(1)
	end)

	it("a dismiss the PRESENTER drove is counted too, and the plate can open again", function()
		local engine, presented, dismissed = engineWith(STEPPED, BOX)
		engine.open()
		expect(engine.teardowns()).toBe(0)
		--[[ THE OUTSIDE TAP. The presenter's own teardown runs entirely inside its
			outside-tap path and never through this engine's `close`, so without the
			feedback listener the engine would hold a dead handle and refuse to open
			ever again — the defect the Menu and row_actions each found live. ]]
		presented[1].fireDismiss()
		expect(engine.state()).toBe("closed")
		expect(engine.teardowns()).toBe(1)
		-- and it is NOT double-dismissed: the surface is already gone
		expect(#dismissed).toBe(0)
		expect(engine.open()).toBe("anchored")
		expect(#presented).toBe(2)
	end)

	it("an authored handler REPLACES the presentation, and the framework presents nothing", function()
		local ran = 0
		local engine, presented = engineWith(STEPPED, BOX, function()
			ran += 1
		end)
		expect(engine.open()).toBe("custom")
		expect(ran).toBe(1)
		expect(#presented).toBe(0)
	end)

	it("declares NO transition, so there is no travel to reduce", function()
		local _, presented = engineWith(STEPPED, BOX)
		local engine = regionExpand.new({
			id = "Clock",
			panelOf = function()
				return {}
			end,
			sheetOf = function()
				return {}
			end,
		})
		engine.contribution.bindController(fakeController(STEPPED, BOX))
		local opts: any = nil
		engine.contribution.bindPresent(nil, function() end, function(_panel: any, o: any)
			opts = o
			return { kind = "anchored" }
		end)
		engine.contribution.syncGeometry(function()
			return BOX
		end, { path = "/S/C/Clock" })
		engine.open()
		expect(opts.transition).toBeNil()
		expect(opts.modal).toBe(true)
		expect(opts.scrim).toBe("none")
		expect(opts.outsideTapCancel).toBe(true)
		-- cancelPolicy is left at the presenter's default, which is what makes
		-- Escape and gamepad ButtonB close the plate
		expect(opts.cancelPolicy).toBeNil()
		expect(#presented).toBe(0)
	end)
end)

-- ===== 4b. THE WHOLE LOOP ==================================================
-- Everything above tests one seam. This tests the claim: a screen that declares
-- a collapsing region and NOTHING ELSE gets a working disclosure — the tap, the
-- surface, the content, and the way back.

local worldLib = require("./lib/world")

local function hudScreen(): any
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
						children = {
							UI.VStack({
								id = "Full",
								children = {
									UI.Text({ id = "Timer", text = "2:14", textSize = 16 }),
									UI.Text({ id = "Scores", text = "12 - 9", textSize = 16 }),
								},
							}),
							UI.Text({ id = "TimerOnly", text = "2:14", textSize = 16 }),
						},
					}),
				},
			}),
		},
	})
end

describe("EXPAND 9 — the whole loop, with no per-region code anywhere in the declaration", function()
	it("a tap on the stepped-down region opens a plate carrying the richest form", function()
		-- 30px of height: the two-line form cannot stand, the one-line one can
		local w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 30 } })
		w.present(hudScreen(), { initialFocus = "none" })
		expect(w.controller.compositionAt("/S/C").regions[1].activeForm).toBe(2)
		expect(w.pres.depth()).toBe(1)
		w.adapter.tap("/S/C/Clock/Expand")
		w.pres.refresh()
		expect(w.pres.depth()).toBe(2)
		-- the plate carries the RICHEST form, by identity: the same nodes, on a
		-- surface of their own
		expect(w.adapter.node("/Expand:Clock/Layer/Surface/ExpandPanel/Full/Scores")).never().toBeNil()
	end)

	it("...and gamepad B closes it, because the plate is an ordinary presented surface", function()
		local w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 30 } })
		w.present(hudScreen(), { initialFocus = "none" })
		w.adapter.tap("/S/C/Clock/Expand")
		w.pres.refresh()
		expect(w.pres.depth()).toBe(2)
		-- Cancel through the real device path: the plate declares no cancel policy
		-- of its own, so the presenter's default (`dismiss`) is what answers
		w.system.deviceKey("ButtonB", true)
		w.system.deviceKey("ButtonB", false)
		w.pres.refresh()
		expect(w.pres.depth()).toBe(1)
	end)

	it("a screen with room opens nothing at all: the affordance is not even standing", function()
		local w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 844 } })
		w.present(hudScreen(), { initialFocus = "none" })
		expect(w.controller.compositionAt("/S/C").regions[1].activeForm).toBe(1)
		w.adapter.tap("/S/C/Clock/Expand")
		w.pres.refresh()
		expect(w.pres.depth()).toBe(1)
	end)
end)

-- ===== 5. THE FOCUS RING ===================================================
-- The director's constraint is about GESTURES, and a gesture on a pad is a stop
-- on a ring. Three things have to be true and none of them is about pixels: the
-- stop exists only while a reduced form is standing, it never disturbs the order
-- of the stops around it, and on a form that carries controls of its own it
-- comes AFTER them.

local function traversalPaths(w: any): { string }
	local map = w.pres.focus.focusMap()
	local out: { string } = {}
	for _, entry in (if map ~= nil then map.traversal else nil) or {} do
		table.insert(out, entry.path)
	end
	return out
end

local function indexOf(list: { string }, path: string): number?
	for i, entry in list do
		if entry == path then
			return i
		end
	end
	return nil
end

-- a screen with a stop BEFORE the region and a stop AFTER it, so "the ring was
-- not disturbed" is a claim about neighbours rather than about a count
local function ringScreen(interactive: boolean): any
	local compact: any = if interactive
		then UI.VStack({
			id = "Compact",
			width = { type = "fill", weight = 1 },
			children = { UI.Button({ id = "Live", label = "live", onActivate = function() end }) },
		})
		else UI.Text({ id = "Compact", text = "2:14", textSize = 16 })
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
						id = "Before",
						group = "body",
						rank = 1,
						children = { UI.Button({ id = "First", label = "first", onActivate = function() end }) },
					}),
					UI.Region({
						id = "Clock",
						group = "body",
						rank = 3,
						recover = "overflow",
						children = {
							--[[ FOUR LINES, and the number is load-bearing: the interactive
								compact form is a Button, a Button is at the 44px target floor, and
								a ladder whose reduced rung is TALLER than its rich one never steps
								down at all. The rich form has to be genuinely bigger than the
								thing that replaces it or this fixture proves nothing. ]]
							UI.VStack({
								id = "Full",
								children = {
									UI.Text({ id = "Timer", text = "2:14", textSize = 16 }),
									UI.Text({ id = "Scores", text = "12 - 9", textSize = 16 }),
									UI.Text({ id = "Home", text = "Home 12", textSize = 16 }),
									UI.Text({ id = "Away", text = "Away 9", textSize = 16 }),
								},
							}),
							compact,
						},
					}),
					UI.Region({
						id = "After",
						group = "body",
						rank = 2,
						children = { UI.Button({ id = "Last", label = "last", onActivate = function() end }) },
					}),
				},
			}),
		},
	})
end

describe("EXPAND 10 — the stop exists only while a reduced form does, and never moves its neighbours", function()
	it("a screen with room has no expand stop at all", function()
		local w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 844 } })
		w.present(ringScreen(false), { initialFocus = "none" })
		local order = traversalPaths(w)
		expect(indexOf(order, "/S/C/Clock/Expand")).toBeNil()
		expect(indexOf(order, "/S/C/Before/First")).never().toBeNil()
		expect(indexOf(order, "/S/C/After/Last")).never().toBeNil()
	end)

	it("stepped down, the stop appears ONCE and the neighbours keep their order", function()
		local roomy = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 844 } })
		roomy.present(ringScreen(false), { initialFocus = "none" })
		local before = traversalPaths(roomy)
		local tight = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 150 } })
		tight.present(ringScreen(false), { initialFocus = "none" })
		local after = traversalPaths(tight)
		expect(tight.controller.compositionAt("/S/C").regions[2].activeForm).toBe(2)
		expect(indexOf(after, "/S/C/Clock/Expand")).never().toBeNil()
		-- exactly one
		local count = 0
		for _, path in after do
			if path == "/S/C/Clock/Expand" then
				count += 1
			end
		end
		expect(count).toBe(1)
		-- ...and the ring around it is the ring it was: same stops, same order
		local function withoutExpand(list: { string }): string
			local kept: { string } = {}
			for _, path in list do
				if path ~= "/S/C/Clock/Expand" then
					table.insert(kept, path)
				end
			end
			return table.concat(kept, " ")
		end
		expect(withoutExpand(after)).toBe(withoutExpand(before))
	end)

	it("on a form that carries a control, the expand stop comes AFTER the form's own", function()
		local w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 150 } })
		w.present(ringScreen(true), { initialFocus = "none" })
		local order = traversalPaths(w)
		local live = indexOf(order, "/S/C/Clock/Compact/Live")
		local expand = indexOf(order, "/S/C/Clock/Expand")
		expect(live).never().toBeNil()
		expect(expand).never().toBeNil()
		expect((expand :: number) > (live :: number)).toBe(true)
	end)

	it("gamepad A opens the plate and B returns focus to the stop that opened it", function()
		local w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 150 } })
		w.present(ringScreen(false), { initialFocus = "none" })
		w.pres.focus.focusOn("/S/C/Clock/Expand")
		expect(w.pres.focus.focused:get()).toBe("/S/C/Clock/Expand")
		w.system.deviceKey("ButtonA", true)
		w.system.deviceKey("ButtonA", false)
		w.pres.refresh()
		expect(w.pres.depth()).toBe(2)
		w.system.deviceKey("ButtonB", true)
		w.system.deviceKey("ButtonB", false)
		w.pres.refresh()
		expect(w.pres.depth()).toBe(1)
		-- the modal scope popped, and the presenter's own restore put the ring back
		-- where the player left it
		expect(w.pres.focus.focused:get()).toBe("/S/C/Clock/Expand")
	end)
end)

describe("EXPAND 11 — a rotation under an open plate closes it, cleanly", function()
	it("the box the plate was opened against moved, so the plate is not there either", function()
		local w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 150 } })
		w.present(ringScreen(false), { initialFocus = "none" })
		w.adapter.tap("/S/C/Clock/Expand")
		w.pres.refresh()
		expect(w.pres.depth()).toBe(2)
		--[[ THE ROTATION, as the live adapter publishes one: a viewport write, and
			every solve that follows from it. Nothing here tells the plate to close —
			the epoch check reads the region's rect on the presenter's own cadence and
			finds a box that is not the one it was anchored to. ]]
		--[[ THE WIDTH ALONE, and the choice is what makes this a proof of the epoch
			check rather than of something else. A rotation that also gives the region
			room to climb back to its richest form would close the plate through the
			"nothing left to disclose" branch, and the rect-comparison could be deleted
			without this case noticing. Same height, wider box: the region is still
			stepped down, and the ONLY thing that changed is the box the plate was
			anchored to. ]]
		w.env:set("viewportRect", { x = 0, y = 0, w = 520, h = 150 })
		w.pres.refresh()
		expect(w.controller.compositionAt("/S/C").regions[2].activeForm).toBe(2)
		expect(w.pres.depth()).toBe(1)
		-- ...and the screen underneath is untouched: a dismissal, not a teardown
		expect(w.adapter.node("/S/C/Before/First")).never().toBeNil()
	end)
end)

-- ===== 6. THE WAY OUT, ON A KEYBOARD =======================================
--[[ ADR-0013's modal obligation, and the wave that inherited it.

	The plate is a MODAL — that is what stops it stranding its own contents (EXPAND
	8's note). A modal traps the ring, and on this platform the ring is the ONLY
	keyboard route out: Escape is permanently bound to the Roblox CoreGui menu and
	the engine's VirtualInput refuses it outright (ADR-0013 §Justified exceptions,
	verified live 2026-07-19), so `cancel.bind` binds ButtonB and nothing else.

	ADR-0013 already names the answer — "a focusable close affordance inside the
	modal … screens that present a modal should always include a visible close
	affordance for exactly this reason" — and until this wave that obligation fell
	on the screen author. It does not any more: the framework is the thing
	presenting, and the plate's content is the author's form 1, which in the
	director's own headline case (the clock) contains no focus stop at all. So the
	obligation moved with the presentation, and the panel wrapper carries it.

	IT IS THE LAST CHILD, so the presenter's existing rule decides where focus
	lands with no new option: a modal defaults to its FIRST focusable, which is the
	content's own control when form 1 has one and the Close when it does not. ]]

describe("EXPAND 12 — a keyboard-only player can open the plate and close it again", function()
	it("Return opens it, and the ring inside it is not empty", function()
		local w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 150 } })
		w.present(ringScreen(false), { initialFocus = "none" })
		w.pres.focus.focusOn("/S/C/Clock/Expand")
		w.press("Return")
		w.pres.refresh()
		expect(w.pres.depth()).toBe(2)
		--[[ THE REVIEWER'S REPRODUCTION, INVERTED. Before the close control this read
			`stops reachable while the plate is open: []` — a modal with an empty ring,
			no bindable Escape and therefore no keyboard exit at all. ]]
		local stops = traversalPaths(w)
		expect(#stops > 0).toBe(true)
		expect(string.sub(stops[1], 1, 13)).toBe("/Expand:Clock")
	end)

	it("...and Return on the focused close control closes it — no pad, no pointer", function()
		local w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 150 } })
		w.present(ringScreen(false), { initialFocus = "none" })
		w.pres.focus.focusOn("/S/C/Clock/Expand")
		w.press("Return")
		w.pres.refresh()
		expect(w.pres.depth()).toBe(2)
		-- form 1 here is two lines of text and holds no control of its own, so the
		-- modal's default (its FIRST focusable) IS the close affordance
		expect(w.pres.focus.focused:get()).toBe("/Expand:Clock/Layer/Surface/ExpandPanel/ExpandClose")
		w.press("Return")
		w.pres.refresh()
		expect(w.pres.depth()).toBe(1)
		-- ...and the ring is back on the stop that opened it
		expect(w.pres.focus.focused:get()).toBe("/S/C/Clock/Expand")
	end)

	it("Space activates it too, where the surface owns Space", function()
		--[[ SPACE IS OPT-IN AND THAT IS NOT THIS WAVE'S DOING (Step 8): a surface
			binds Tab and Space only with `keyboardNavigation`, because on a default
			screen those keys belong to the avatar — with it implicitly on, Space jumped
			the character while the UI had focus (director playtest 2026-08-03). So the
			second keyboard verb is asserted where it genuinely exists, rather than
			asserted into being on a surface that never claimed the key. ]]
		local w = worldLib.new({
			viewport = { x = 0, y = 0, w = 390, h = 150 },
			presenterOpts = { keyboardNavigation = true },
		})
		w.present(ringScreen(false), { initialFocus = "none" })
		w.pres.focus.focusOn("/S/C/Clock/Expand")
		w.press("Space")
		w.pres.refresh()
		expect(w.pres.depth()).toBe(2)
		w.press("Space")
		w.pres.refresh()
		expect(w.pres.depth()).toBe(1)
	end)

	--[[ A screen whose RICHEST form carries a control of its own — which is the
		case that decides where focus lands when the plate opens, and the one the
		ring-order rule below is about. ]]
	local function richControlScreen(): any
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
							children = {
								UI.VStack({
									id = "Full",
									children = {
										UI.Text({ id = "Timer", text = "2:14", textSize = 16 }),
										UI.Text({ id = "Scores", text = "12 - 9", textSize = 16 }),
										UI.Button({ id = "Details", label = "details", onActivate = function() end }),
									},
								}),
								UI.Text({ id = "Compact", text = "2:14", textSize = 16 }),
							},
						}),
					},
				}),
			},
		})
	end

	it("the CONTENT keeps the first stop when it has one, and the close is reachable after it", function()
		--[[ ADR-0013's rule followed rather than overridden: the close affordance is
			the panel's LAST child, so a form 1 carrying its own control keeps the first
			stop and the way out sits behind it. ]]
		local w = worldLib.new({
			viewport = { x = 0, y = 0, w = 390, h = 40 },
			presenterOpts = { keyboardNavigation = true },
		})
		w.present(richControlScreen(), { initialFocus = "none" })
		w.pres.focus.focusOn("/S/C/Clock/Expand")
		w.press("Return")
		w.pres.refresh()
		expect(w.pres.depth()).toBe(2)
		local stops = traversalPaths(w)
		expect(#stops).toBe(2)
		expect(stops[1]).toBe("/Expand:Clock/Layer/Surface/ExpandPanel/Full/Details")
		expect(stops[2]).toBe("/Expand:Clock/Layer/Surface/ExpandPanel/ExpandClose")
		-- the modal's existing rule put focus on the CONTENT, not on the way out
		expect(w.pres.focus.focused:get()).toBe("/Expand:Clock/Layer/Surface/ExpandPanel/Full/Details")
		-- Tab to it and press Return: the whole keyboard route, driven
		w.press("Tab")
		w.pres.refresh()
		expect(w.pres.focus.focused:get()).toBe("/Expand:Clock/Layer/Surface/ExpandPanel/ExpandClose")
		w.press("Return")
		w.pres.refresh()
		expect(w.pres.depth()).toBe(1)
	end)

	--[[ ...AND THE SHEET FALLBACK, MOUNTED — which also closes the wave's own open
		concern 2 ("no mounted end-to-end sheet proof exists"). Form 1 here is 2000px
		wide against a 390px viewport, so it cannot meet its floor in a plate at any
		gutter and the composition says `sheet = true` at the same solve that chose
		the rung. ]]
	local function sheetScreen(): any
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
							children = { fixedBox("Wide", 2000, 60), fixedBox("Compact", 60, 20) },
						}),
					},
				}),
			},
		})
	end

	it("the SHEET fallback is a real surface, and it carries the same way out", function()
		local w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 30 } })
		w.present(sheetScreen(), { initialFocus = "none" })
		local row = w.controller.compositionAt("/S/C").regions[1]
		expect(row.activeForm).toBe(2)
		expect(row.plate.sheet).toBe(true)
		w.pres.focus.focusOn("/S/C/Clock/Expand")
		w.press("Return")
		w.pres.refresh()
		expect(w.pres.depth()).toBe(2)
		-- the same content, presented full width, with the same way out
		expect(w.adapter.node("/ExpandSheet:Clock/Layer/ExpandSheet/Wide")).never().toBeNil()
		expect(w.pres.focus.focused:get()).toBe("/ExpandSheet:Clock/Layer/ExpandSheet/ExpandClose")
		w.press("Return")
		w.pres.refresh()
		expect(w.pres.depth()).toBe(1)
	end)
end)
