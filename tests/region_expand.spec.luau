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

describe("EXPAND 2b — `unshown` alone is not the census, and here is the state that proves it", function()
	--[[ THE TRAP A CENSUS FALLS INTO (fix round 1, from the review's edge probe).
		`unshown` lists what a screen has stopped SHOWING, and by construction it
		excludes a `recover = "none"` region — the author has stated that every form
		below the richest still shows everything that matters, so nothing is missing.
		That is correct and it is not the whole census: such a region can still be
		STANDING ON A REDUCED FORM, and a surface that prints "nothing is hidden" off
		`#unshown == 0` alone will print it over one.

		The two facts live on the same dump and a census must read both. The guide
		says so; this pins the state that makes it true, so a consumer reading only
		one half has a failing case to look at. ]]
	it("a stepped-down region with a lossless ladder is invisible in `unshown` and visible in `activeForm`", function()
		local res = composition.resolve(
			decl({ { id = "Rounds", group = "body", rank = 1, forms = 2, recover = "none" } }),
			{ w = 400, h = 30 },
			{ measure = measureFrom({ Rounds = { { w = 200, h = 60 }, { w = 60, h = 20 } } }) }
		)
		local r = res.regionById.Rounds
		expect(r.activeForm).toBe(2)
		expect(r.elided).toBe(true)
		expect(#res.unshown).toBe(0)
		-- ...and it has no expand either, so the census row it needs is "simplified",
		-- not "open to expand"
		expect(r.expandable).toBe(false)
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
-- the plate's chrome, read from the ONE place that declares it: a spec that
-- restated `space.m` here would be the second copy the module exists to remove
local Facet = require("../src")
local themeSnapshot = require("../src/themes/snapshot")
local expandPlate = require("../src/layout/expand_plate")
-- the ONE enumerator for the theme corpus (MAINT-8c): a spec that restated the
-- package list would be a second copy of it, and a tenth package would escape
local themePackages = require("../tools/lune/theme_packages")
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

	--[[ THE CONTRADICTION IS REFUSED, NOT DEFAULTED AROUND (fix round 1). It used to
		be a silent default: `recover = "none"` resolved `expand` to "none" and an
		author who wrote `expand = "auto"` beside it was accepted in silence — which
		also produced a census that could print "nothing is hidden" over a zone
		standing on a reduced form with a live affordance on it. Two statements that
		cannot both be true are an authoring error, and this boundary refuses those. ]]
	it('an expand under recover = "none" is refused — the declaration contradicts itself', function()
		local function withExpand(value: any): boolean
			local ok = pcall(UI.Region, {
				id = "Rounds",
				group = "body",
				rank = 1,
				recover = "none",
				expand = value,
				children = { textForm("Wide"), textForm("Wrapped") },
			})
			return ok
		end
		expect(withExpand("auto")).toBe(false)
		-- ...and "none" is refused too, exactly as the one-form region refuses every
		-- value of a key that cannot mean anything there
		expect(withExpand("none")).toBe(false)
		expect(withExpand(function() end)).toBe(false)
		-- SILENCE is still the right way to say it, and still resolves to "none"
		local region = UI.Region({
			id = "Rounds",
			group = "body",
			rank = 1,
			recover = "none",
			children = { textForm("Wide"), textForm("Wrapped") },
		})
		expect(region.props.expand.mode).toBe("none")
		expect(#expandNodes(region)).toBe(0)
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
		-- the FACT is still reported — form 2 contributes nothing to focus or action
		expect(region.props.expand.interactive[2]).toBe(false)
		--[[ THE DIRECTOR'S RULE (DIR5, 2026-08-21): *"the controls should just be
			tappable by default to open more without the arrow. we'll only need the
			arrow if the thing is already a control the user can tap."* So a passive
			form gets a COVER — the whole pill is the target — and it draws NOTHING:
			no caret, no glyph, one empty box that exists only to stop a Button
			painting its own accessible label. ]]
		expect(aff.props.expandTarget.role).toBe("cover")
		expect(childrenOf(aff)[1].id).toBe("Zone")
		--[[ ...AND IT IS DECLARED BELOW THE FORM, which is the whole difference from
			the cover that was retired for rendering three pills empty. `zIndex` is
			paint order within the parent's stacking scope; the affordance is still the
			LAST child, because that is the TREE fact the solver's identity lookup
			reads. Two orders, and only one of them moved. ]]
		expect(aff.props.zIndex).toBe(-1)
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

	it("a UI.Foreign box owns its own gestures, so the cover never goes over one", function()
		--[[ THE ONE CLASS DEFINED AS CONTENT THE FRAMEWORK HAS NEVER SEEN (review
			MEDIUM-2). `UI.Foreign` reserves and clips a rect for a GuiObject Facet does
			not wrap: the framework writes exactly one property on that instance (its
			Parent) and the content's OWN engine input still works. Its class contract
			says so in as many words.

			So it takes no focus stop and declares no semantic action, and a registry
			read alone therefore calls it PASSIVE — which used to mean a full-cover
			activation surface laid over live content. This repository has measured what
			that does: "a GuiButton SINKS input", so the adopted instance's own gestures
			stop arriving. That is exactly the one-gesture-two-meanings collision the
			chevron exists to prevent, arriving through the one class that cannot be
			inspected for it.

			`UI.Stage` is deliberately NOT in the same set: a stage is a picture whose
			contract states it owns no input, and interaction is composed AROUND it. ]]
		local region = UI.Region({
			id = "Feed",
			group = "body",
			rank = 1,
			recover = "overflow",
			children = {
				textForm("Full"),
				UI.VStack({ id = "Compact", children = { UI.Foreign({ id = "Adopted" }) } }),
			},
		})
		expect(region.props.expand.interactive[2]).toBe(true)
		expect(expandNodes(region)[1].props.expandTarget.role).toBe("chevron")
	end)

	it("a Box that declares `active` SINKS input, so it takes the chevron too", function()
		--[[ REVIEW M3, and it is `UI.Foreign`'s mechanism arriving through the
			framework's own vocabulary rather than through a class. `active` is a
			public Box prop documented as "engine `Active` flag — an input-sinking
			panel (modal backdrops)", and the adapter writes exactly that
			(`screen_target.luau`, `instance.Active = value == true`). `Box` is in the
			passive class set, so a reduced form holding one was classified passive,
			got a cover UNDERNEATH it, and the Active Frame above sank the press: the
			cover is unreachable over that rect.

			An author asking the adapter to sink input has declared an actionable host
			by this framework's own definition, so the affordance is a chevron BESIDE
			it — which is the disambiguation the arrow exists for. It is read off the
			PROP rather than the class, because the class is right about a plain Box
			and this is a Box that has said otherwise. ]]
		local region = UI.Region({
			id = "Backdrop",
			group = "body",
			rank = 1,
			recover = "overflow",
			children = {
				textForm("Full"),
				UI.VStack({ id = "Compact", children = { UI.Box({ id = "Sink", active = true }) } }),
			},
		})
		expect(region.props.expand.interactive[2]).toBe(true)
		expect(expandNodes(region)[1].props.expandTarget.role).toBe("chevron")
		-- ...and `active = false` (or absent) is still an ordinary passive Box
		local plain = UI.Region({
			id = "Plain",
			group = "body",
			rank = 1,
			recover = "overflow",
			children = {
				textForm("Full"),
				UI.VStack({ id = "Compact", children = { UI.Box({ id = "Sink", active = false }) } }),
			},
		})
		expect(plain.props.expand.interactive[2]).toBe(false)
		expect(expandNodes(plain)[1].props.expandTarget.role).toBe("cover")
		--[[ ...AND THE REACTIVE SPELLING, which is the one the first fix missed (fix
			round 1, review MEDIUM-1). `active` is `Bound<boolean>` — a literal or a
			Signal/Memo — and `== true` is false for every bound value, so
			`UI.Box{ active = core:signal(true) }`, the framework's own primary idiom
			for a prop that varies, still got a cover UNDERNEATH an Active Frame. Both
			pinned arms above are literals, so no mutation could have caught it. ]]
		local core = Facet.newCore()
		local bound = UI.Region({
			id = "Bound",
			group = "body",
			rank = 1,
			recover = "overflow",
			children = {
				textForm("Full"),
				UI.VStack({ id = "Compact", children = { UI.Box({ id = "Sink", active = core:signal(true) }) } }),
			},
		})
		expect(bound.props.expand.interactive[2]).toBe(true)
		expect(expandNodes(bound)[1].props.expandTarget.role).toBe("chevron")
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

	it("stepped down, a PASSIVE form IS the target: the cover is the region's whole box", function()
		local adapter, controller = mountedAt(400, 30, { expand = nil })
		expect(controller.compositionAt("/S/C").regions[1].activeForm).toBe(2)
		local region = adapter.node("/S/C/Clock").rect
		local affordance = adapter.node("/S/C/Clock/Expand").rect
		local form = adapter.node("/S/C/Clock/Compact").rect
		expect(controller.hiddenRoots()["/S/C/Clock/Expand"]).toBe(nil)
		--[[ THE WHOLE BOX, and the form KEEPS the whole box too: a cover reserves
			nothing, so the compact form is not paying a column for a mark it no longer
			has. That is the second half of the director's rule — the arrow was costing
			the value beside it width on exactly the phones where the value was
			already tightest. ]]
		expect(`{affordance.x},{affordance.y} {affordance.w}x{affordance.h}`).toBe(
			`{region.x},{region.y} {region.w}x{region.h}`
		)
		--[[ ...and the form is exactly the size it is with NO affordance at all. A
			chevron is reserved out of the region's offer, so a form beside one measures
			against a narrower box; a cover reserves nothing, and this is that stated as
			a differential rather than as a number. ]]
		local bare = mountedAt(400, 30, { expand = "none" })
		expect(`the form pays nothing for the affordance: {form.w}`).toBe(
			`the form pays nothing for the affordance: {bare.node("/S/C/Clock/Compact").rect.w}`
		)
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

local PLATE = { w = 200, h = 60, sheet = false, max = 320 }

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
		panelOf = function(plate: any)
			return { class = "VStack", id = "ExpandPanel", plateWidth = plate.w, plateCap = plate.max }
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
			plate = { w = 84, h = 60, sheet = true, max = 84 },
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
			panelOf = function(_plate: any)
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
			panelOf = function(_plate: any)
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
		--[[ ...AND THE BARRIER IS THE SCRIM ROLE (DIR5, the third report of "the
			popup background is opaque"). `none` mounts the catcher as the SUPPRESSED
			surface, whose transparency no rule in the sheet's vocabulary can address —
			`tests/popup_catcher_paint.spec` resolves both roles to the rule that
			supplies the number. ]]
		expect(opts.scrim).toBe("scrim")
		expect(opts.outsideTapCancel).toBe(true)
		-- cancelPolicy is left at the presenter's default, which is what makes
		-- gamepad ButtonB closes the plate (Escape cannot be bound on this platform;
		-- the keyboard route is the panel's own close affordance — EXPAND 12)
		expect(opts.cancelPolicy).toBeNil()
		expect(#presented).toBe(0)
	end)
end)

-- ===== 4b. THE WHOLE LOOP ==================================================
-- Everything above tests one seam. This tests the claim: a screen that declares
-- a collapsing region and NOTHING ELSE gets a working disclosure — the tap, the
-- surface, the content, and the way back.

local worldLib = require("./lib/world")
local adapter_source = require("./lib/adapter_source")
local sheet_model = require("../src/tokens/sheet_model")
local default_style = require("../src/tokens/default_style")

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
		expect(w.adapter.node("/Expand:Clock/Layer/Surface/ExpandPanel/ExpandPlate/Full/Scores")).never().toBeNil()
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

-- the mounted CHILD IDS of a node, in the order the renderer walks them: the
-- instrument that says which of two siblings paints over the other
local function childIdsOf(w: any, parent: string): { string }
	local out: { string } = {}
	for _, path in w.adapter.paths() do
		local rest = string.match(path, `^{parent}/([^/]+)$`)
		if rest ~= nil then
			table.insert(out, { id = rest, z = w.adapter.node(path).z or 0 })
		end
	end
	table.sort(out :: any, function(a: any, b: any)
		return a.z < b.z
	end)
	local ids: { string } = {}
	for _, entry in out :: any do
		table.insert(ids, entry.id)
	end
	return ids
end

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
--[[ The modal obligation, and the wave that inherited it.

	The plate is a MODAL — that is what stops it stranding its own contents (EXPAND
	8's note). A modal traps the ring, and on this platform the ring is the ONLY
	keyboard route out: Escape is permanently bound to the Roblox CoreGui menu and
	the engine's VirtualInput refuses it outright (verified live 2026-07-19), so `cancel.bind` binds ButtonB and nothing else.

	The framework already names the answer — "a focusable close affordance inside the
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
		--[[ the rule followed rather than overridden: the close affordance is
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
		expect(stops[1]).toBe("/Expand:Clock/Layer/Surface/ExpandPanel/ExpandPlate/Full/Details")
		expect(stops[2]).toBe("/Expand:Clock/Layer/Surface/ExpandPanel/ExpandClose")
		-- the modal's existing rule put focus on the CONTENT, not on the way out
		expect(w.pres.focus.focused:get()).toBe("/Expand:Clock/Layer/Surface/ExpandPanel/ExpandPlate/Full/Details")
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
		expect(w.adapter.node("/ExpandSheet:Clock/Layer/ExpandSheet/ExpandSheetPlate/Wide")).never().toBeNil()
		expect(w.pres.focus.focused:get()).toBe("/ExpandSheet:Clock/Layer/ExpandSheet/ExpandClose")
		w.press("Return")
		w.pres.refresh()
		expect(w.pres.depth()).toBe(1)
	end)
end)

describe("EXPAND 19 — the panel a plate becomes never exceeds the gutter allowance", function()
	--[[ THE BAND DIR5 LEFT OPEN, CLOSED (2026-08-21). The plate hugging its content
		removed the overflow at every width BELOW a band and named the residue with
		the line: the composition measures form 1 against `viewport - 2*gutter` and
		calls the answer a plate, but the panel it is actually wrapped in is wider
		than that answer by its OWN CHROME — the plate's two paddings (the right one
		is the close disc's reserve) and the straddle the disc sits on. A form whose
		natural width lands within the chrome of the cap therefore produced a panel
		wider than the allowance, and at the top of the band wider than the viewport.

		At 390 the numbers are exact: gutter 16 so the ALLOWANCE is 358; straddle 16
		so the widest the plate BOX may be is 342; padding 8 + 36 so the CONTENT cap
		is 298. A 320px form is inside the band. Before the fix `plate.sheet` was
		false and the anchored panel mounted at 380 — 22px past the allowance.

		THE FIX IS THE ONE SEAM THE RESIDUE NAMED: the chrome is declared once, in
		`layout/expand_plate.luau`, spent by `blueprint`'s `panelOf` when it builds
		the plate and resolved by the solver into `resolveCtx.expandPlateInset` /
		`expandPlateStraddle`, so the cap form 1 is measured against already has the
		plate's own insets taken out of it. Nothing re-derives an inset and no caller
		can forget one. ]]
	local ALLOWANCE = 358
	local function bandScreen(formWidth: number): any
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
							children = { fixedBox("Wide", formWidth, 60), fixedBox("Compact", 60, 20) },
						}),
					},
				}),
			},
		})
	end

	-- ...and the same region with a form that WRAPS instead of declaring a width:
	-- the arm whose measured answer and whose hugged content are two different
	-- numbers, which is the whole of review H2
	local function wrapScreen(text: string): any
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
										UI.Text({ id = "R1", text = text, textSize = 16 }),
										UI.Text({ id = "R2", text = text, textSize = 16 }),
										UI.Text({ id = "R3", text = text, textSize = 16 }),
									},
								}),
								UI.Text({ id = "Tiny", text = "2:14", textSize = 16 }),
							},
						}),
					},
				}),
			},
		})
	end

	it("a form INSIDE the chrome band cannot mount a panel wider than the allowance", function()
		local w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 30 } })
		w.present(bandScreen(320), { initialFocus = "none" })
		local row = w.controller.compositionAt("/S/C").regions[1]
		expect(row.activeForm).toBe(2)
		-- `plate.max` is the widest the plate BOX may be declared: the allowance
		-- minus the straddle its own margin will add back on the way out
		--[[ RE-VERDICTED (plate design B, 2026-08-21): the straddle was `space.m`
			(16, a number unrelated to the disc it carried) and is now the disc's own
			derivation, `space.xs + disc/2` (22). Read from the module that DECLARES
			it rather than restated, so the cap and this line can never be two
			readings of one intention. ]]
		local straddle = expandPlate.straddleX(w.env:get("themeMetrics"):get())
		expect(row.plate.max).toBe(ALLOWANCE - straddle)
		w.pres.focus.focusOn("/S/C/Clock/Expand")
		w.press("Return")
		w.pres.refresh()
		expect(w.pres.depth()).toBe(2)
		local panel = w.adapter.node("/Expand:Clock/Layer/Surface/ExpandPanel")
		local sheet = w.adapter.node("/ExpandSheet:Clock/Layer/ExpandSheet/ExpandSheetPlate")
		--[[ EITHER ANSWER IS LEGAL; PAINTING PAST THE ALLOWANCE IS NOT. A form that
			cannot fit the content cap belongs on the full-width sheet, which is
			edge-to-edge by construction and cannot overflow; a form that fits gets a
			panel. What may never happen is the third thing, which is what shipped:
			an anchored panel wider than the allowance it was chosen against.

			AND THERE IS A FOURTH OUTCOME THIS FRAMING DID NOT NAME (fix round 1,
			review LOW-5). `sheet` is `measured > maxW`, and a WRAPPING form's measure
			is by construction `<= maxW`, so such a form can never reach the sheet — it
			is capped instead. At any viewport wide enough to ship that is the right
			answer (the content wraps and stays inside), but at a degenerate width the
			cap squeezes rather than promotes: measured at a 90px viewport the content
			gets 4px. No device is that narrow; it is named because the rule above
			reads as an exhaustive pair and is not one. ]]
		if panel ~= nil then
			expect(`panel {panel.rect.w} within allowance {ALLOWANCE}`).toBe(
				`panel {math.min(panel.rect.w, ALLOWANCE)} within allowance {ALLOWANCE}`
			)
		else
			expect(sheet).never().toBeNil()
		end
	end)

	it("a WRAPPING form cannot hug past the cap either — the panel the review found off-screen", function()
		--[[ REVIEW H2. The band above is the FIXED-width arm: a form that declares
			its own width is measured, capped, and either fits or goes to the sheet.
			A WRAPPING form takes neither route. `measure` answers the WRAPPED width,
			which is always <= the cap, so `sheet` is false — and then the plate HUGS,
			and a hug is the CONTENT's width, which is not the number that was
			measured. Measured at 390 before this fix: three text rows hugged to 374
			against a 342 cap, panel 8..398, with 8 of the close disc's 36px off the
			screen; at a 20px safe inset the whole disc was outside the safe area.

			The clamp cannot save it and that is the load-bearing half: the anchored
			placement REPOSITIONS a surface, it does not shrink one, so a panel wider
			than the space is pinned at the near edge and the far edge runs. The plate
			carries the cap itself now (`minMax`), so the hug is bounded before the
			clamp is ever asked. ]]
		for _, insets in { { left = 0, right = 0 }, { left = 20, right = 20 } } do
			local w = worldLib.new({
				viewport = { x = 0, y = 0, w = 390, h = 30 },
				safeInsets = { top = 0, bottom = 0, left = insets.left, right = insets.right },
			})
			w.present(wrapScreen(string.rep("a", 40)), { initialFocus = "none" })
			local row = w.controller.compositionAt("/S/C").regions[1]
			expect(row.activeForm).toBe(2)
			w.pres.focus.focusOn("/S/C/Clock/Expand")
			w.press("Return")
			w.pres.refresh()
			local panel = w.adapter.node("/Expand:Clock/Layer/Surface/ExpandPanel")
			local disc = w.adapter.node("/Expand:Clock/Layer/Surface/ExpandPanel/ExpandClose")
			expect(panel).never().toBeNil()
			expect(disc).never().toBeNil()
			--[[ THE SAFE AREA, NOT THE VIEWPORT, and at zero insets they are the same
				box — so one arm states the rule and the other exercises the inset the
				review measured the disc entirely outside of. ]]
			local safeL, safeR = insets.left, 390 - insets.right
			expect(
				`insets {insets.left}: panel {panel.rect.x}..{panel.rect.x + panel.rect.w} inside {safeL}..{safeR}: {panel.rect.x >= safeL and panel.rect.x + panel.rect.w <= safeR}`
			).toBe(
				`insets {insets.left}: panel {panel.rect.x}..{panel.rect.x + panel.rect.w} inside {safeL}..{safeR}: true`
			)
			expect(
				`insets {insets.left}: disc {disc.rect.x}..{disc.rect.x + disc.rect.w} inside {safeL}..{safeR}: {disc.rect.x >= safeL and disc.rect.x + disc.rect.w <= safeR}`
			).toBe(
				`insets {insets.left}: disc {disc.rect.x}..{disc.rect.x + disc.rect.w} inside {safeL}..{safeR}: true`
			)
		end
	end)

	it("...and a form that fits the CONTENT cap still gets its panel, chrome included", function()
		-- 240 + 44 of padding + 16 of straddle = 300, comfortably inside the 358
		-- allowance: the control, and what keeps the fix from being "always sheet"
		local w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 30 } })
		w.present(bandScreen(240), { initialFocus = "none" })
		local row = w.controller.compositionAt("/S/C").regions[1]
		expect(row.plate.sheet).toBe(false)
		expect(row.plate.w).toBe(240)
		w.pres.focus.focusOn("/S/C/Clock/Expand")
		w.press("Return")
		w.pres.refresh()
		local panel = w.adapter.node("/Expand:Clock/Layer/Surface/ExpandPanel")
		expect(panel).never().toBeNil()
		expect(`panel {panel.rect.w} within allowance {ALLOWANCE}`).toBe(
			`panel {math.min(panel.rect.w, ALLOWANCE)} within allowance {ALLOWANCE}`
		)
		-- ...and the form itself is untouched by the reserve: it gets what it asked for
		local form = w.adapter.node("/Expand:Clock/Layer/Surface/ExpandPanel/ExpandPlate/Wide")
		expect(form).never().toBeNil()
		expect(form.rect.w).toBe(240)
	end)
end)

-- ===== 7. THE TWO LINES NOTHING WATCHED ====================================
--[[ Both of these were found by the wave's own reviewer, by MUTATION: delete the
	line, run the whole suite, and see 6516/6516 still green. A line with a long
	comment and no witness is a line the next reader has to take on faith, and this
	repository's standing answer to that is a case that reddens.

	They are pinned here rather than beside the code because the code is
	`src/layout/solver.luau`, which is over its extraction trigger and closed to
	growth. Neither fix needed a source change: both lines were correct and
	unwatched, which the two cases below now say out loud. ]]

describe("EXPAND 13 — the ladder chooses a rung against the width it will actually get", function()
	--[[ THE MEASURE-SIDE RESERVE (mutation M2). `compositionResolution`'s measure
		closure hands an interactive reduced form `availW - chevron`, so the rung the
		ladder picks is picked against the width `arrange` will hand it. Delete that
		subtraction and every fixed-size fixture in this suite stays green — because a
		fixed box measures the same at any offer. It takes content whose HEIGHT
		depends on its width to see the difference, which is what wrapping text is.

		At this viewport the compact form's line fits on ONE line in the region's full
		box and needs TWO in what is left beside the chevron. With the reserve the
		composition reserves two lines and everything fits. Without it, the
		composition reserves one, `arrange` hands the form the narrower box anyway,
		the text wraps to two lines inside a box measured for one — and the solver
		files it. ]]
	local WRAPPING = "the quick brown fox jumps"

	local function wrapScreen(): any
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
								fixedBox("Full", 200, 200),
								UI.VStack({
									id = "Compact",
									children = {
										UI.Button({ id = "Live", label = "go", onActivate = function() end }),
										UI.Text({ id = "Line", text = WRAPPING, textSize = 16 }),
									},
								}),
							},
						}),
					},
				}),
			},
		})
	end

	it("a wrapping compact form is measured against the box the chevron leaves it", function()
		local w = worldLib.new({ viewport = { x = 0, y = 0, w = 260, h = 100 } })
		w.present(wrapScreen(), { initialFocus = "none" })
		expect(w.controller.compositionAt("/S/C").regions[1].activeForm).toBe(2)
		local line = w.adapter.node("/S/C/Clock/Compact/Line").rect
		local region = w.adapter.node("/S/C/Clock").rect
		local chevron = w.adapter.node("/S/C/Clock/Expand").rect
		-- the premise: at this width the line genuinely wraps beside the chevron
		expect(chevron.w > 0).toBe(true)
		expect(line.h > 30).toBe(true)
		-- ...and the region's box was measured for the wrapped form, not the flat one
		expect(region.h >= line.h + chevron.h).toBe(true)
		--[[ THE ASSERTION THAT BITES: the solver files nothing. Measured against the
			un-reserved width, this same screen resolves the region 19px shorter and
			the text paints outside the box it was granted — two findings. ]]
		expect(#w.controller.diagnostics()).toBe(0)
	end)
end)

describe("EXPAND 14 — a form that spliced itself away cannot be indexed, and is not", function()
	--[[ THE COUNT-MISMATCH FALLBACK (mutation M9). `interactive` is indexed by the
		DECLARED form; the ladder counts the MOUNTED ones. A form declared behind a
		`UI.When` splices itself out of the mounted child list when its condition
		reads false, and from that moment the two indexes name different things —
		so the solver falls back to the affordance's ROLE, the conservative answer
		computed at construction across the whole ladder.

		Deleting that fallback and reading `record.interactive` straight through kept
		the entire suite green, because no case had ever built the shape. This is that
		shape: three declared forms with the RICHEST behind a gate. With the gate
		closed the ladder walks two mounted rungs, lands on the second — which is the
		declared THIRD form, the one carrying a live Button — and a straight-through
		read would answer with the declared SECOND form's answer: passive, for a form
		that holds a control. ]]
	local function gatedScreen(gate: any): any
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
								UI.When({
									id = "Rich",
									condition = gate,
									thenView = function()
										return fixedBox("RichBody", 200, 200)
									end,
								}),
								fixedBox("Medium", 120, 60),
								UI.VStack({
									id = "Compact",
									children = { UI.Button({ id = "Live", label = "go", onActivate = function() end }) },
								}),
							},
						}),
					},
				}),
			},
		})
	end

	it("with the richest form spliced away, the standing rung's own answer is reported", function()
		local core = customFactory.new()
		local gate = core:signal(false)
		local w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 50 } })
		w.present(gatedScreen(gate), { initialFocus = "none" })
		local row = w.controller.compositionAt("/S/C").regions[1]
		-- two mounted rungs, and the ladder is standing on the second: the form that
		-- carries the Button
		expect(row.activeForm).toBe(2)
		expect(w.adapter.node("/S/C/Clock/Compact/Live").rect.h > 0).toBe(true)
		--[[ A straight-through `record.interactive[2]` answers for the declared
			SECOND form (the passive 120x60 box) and reports FALSE — a live control
			described as a passive box, which is the one mistake this fact exists to
			prevent. ]]
		expect(row.formInteractive).toBe(true)
	end)

	it("...and with the gate open the indexes line up again, unchanged", function()
		local core = customFactory.new()
		local gate = core:signal(true)
		local roomy = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 400 } })
		roomy.present(gatedScreen(gate), { initialFocus = "none" })
		local rich = roomy.controller.compositionAt("/S/C").regions[1]
		expect(rich.activeForm).toBe(1)
		expect(rich.expandable).toBe(false)
	end)
end)

-- ===== 8. THE DEVICE ROUND'S THREE DEFECTS =================================
--[[ A director device round (2026-08-21, emulated portrait 360x691, the HUD
	demo) found three things no headless instrument in this repository could see,
	and the first is the one that matters: EVERY STEPPED-DOWN ZONE RENDERED AS AN
	EMPTY PILL. The timer, the tasks chip and the health pod were rounded boxes
	with nothing in them — which is the exact opposite of the constraint the
	feature was approved under ("key information stays visible in the collapse").

	WHY NOTHING CAUGHT IT. The model was healthy at that viewport: every one of
	those Text nodes had a real rect and `visible = true`, so the value-text
	oracle, the overflow sweep and the composition dump all agreed the screen was
	fine. The framework had put its own instance ON TOP of them — a full-size
	activation surface plus a 44px hit band over a 23px pill — and "it is
	transparent, so it is harmless" is a claim about the ENGINE that no model-side
	check makes or can make.

	So the rule below is not a paint assertion, because a paint assertion is
	exactly what this repository cannot make headlessly. It is a STRUCTURAL one,
	and it is stronger: THE FRAMEWORK PUTS NOTHING OF ITS OWN ABOVE THE AUTHOR'S
	CONTENT.

	=== AND THE COVER IS BACK, UNDER THAT SAME RULE (DIR5, 2026-08-21) ===

	The director's ruling: *"the controls should just be tappable by default to open
	more without the arrow. we'll only need the arrow if the thing is already a
	control the user can tap."* So a passive form is covered again — and the
	retirement note's own escape clause is what makes it legal, met exactly as
	written: *"restoring it means placing the affordance BELOW the form"*.

	`zIndex = -1` is that placement. Siblings paint in `(zIndex or 0, tree order)`
	and a node's whole subtree travels with its root, so the cover AND the hit
	expander the renderer bands one below it are UNDER every form — which is what
	the rule asks for, and what the retired version got backwards. The claim that
	needed an extraction was about the TREE (the solver finds the affordance as the
	last child by identity); paint order is a different axis, and only that one
	moved.

	SO THE RULE SPLITS BY DIRECTION, and the sweep below reads z rather than
	assuming it:
	  * ABOVE author content — FORBIDDEN, whatever the overlap and whatever the
	    transparency. This is the retired cover's defect and it stays banned.
	  * BELOW author content — allowed, and only for a COVER, which is synthesized
	    only where nothing above it is interactive. A Facet node that is not
	    interactive is not an `Active` GuiObject, so the gesture still reaches the
	    cover underneath. ]]

--[[ EXPAND 15's helpers: what the fake target calls an INTERACTIVE node, and the
	overlap of two rects. Both are used by the hit-floor sweep below. ]]
local INTERACTIVE_SEAMS = {
	"onActivate",
	"secondaryActivate",
	"pointer",
	"dragDetector",
	"touchGestures",
	"scrollHandler",
	"discloseZone",
}

local function interactiveNode(n: any): boolean
	for _, seam in INTERACTIVE_SEAMS do
		if n[seam] ~= nil then
			return true
		end
	end
	return false
end

local function overlapOf(a: any, b: any): (number, number)
	if a == nil or b == nil then
		return 0, 0
	end
	return math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x), math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
end

describe("EXPAND 15 — the framework paints nothing over the author's content", function()
	it("a passive form gets a cover UNDER it — same box, and every z below the form's", function()
		local w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 150 } })
		w.present(ringScreen(false), { initialFocus = "none" })
		expect(w.controller.compositionAt("/S/C").regions[2].activeForm).toBe(2)
		local mark = w.adapter.node("/S/C/Clock/Expand")
		local form = w.adapter.node("/S/C/Clock/Compact")
		expect(mark).never().toBeNil()
		--[[ THE WHOLE REGION IS THE TARGET: the affordance takes the region's own
			box, and the form stands inside it rather than beside a reserved column. ]]
		local region = w.adapter.node("/S/C/Clock")
		expect(`{mark.rect.x},{mark.rect.y} {mark.rect.w}x{mark.rect.h}`).toBe(
			`{region.rect.x},{region.rect.y} {region.rect.w}x{region.rect.h}`
		)
		expect(mark.rect.x <= form.rect.x and form.rect.x + form.rect.w <= mark.rect.x + mark.rect.w).toBe(true)
		--[[ ...AND UNDER IT. The z the adapter was told is the whole claim: every
			node of the framework's affordance is strictly below every node of the
			standing form, so no engine behaviour — transparency, stacking context,
			recycling — can put it on top. The band one z BELOW the cover is the hit
			expander's, reserved by `syncZOrder`, so it is under the form too. ]]
		local coverZ, formZ = {}, {}
		for _, path in w.adapter.paths() do
			local n = w.adapter.node(path)
			if n == nil or type(n.z) ~= "number" then
				continue
			end
			if string.find(path, "/S/C/Clock/Expand", 1, true) == 1 then
				table.insert(coverZ, n.z)
			elseif string.find(path, "/S/C/Clock/Compact", 1, true) == 1 then
				table.insert(formZ, n.z)
			end
		end
		expect(#coverZ >= 2).toBe(true) -- the Button and its empty Zone
		expect(#formZ >= 1).toBe(true)
		local highestCover, lowestForm = -math.huge, math.huge
		for _, z in coverZ do
			highestCover = math.max(highestCover, z)
		end
		for _, z in formZ do
			lowestForm = math.min(lowestForm, z)
		end
		expect(`cover tops out at {highestCover}, form starts at {lowestForm}: {highestCover < lowestForm}`).toBe(
			`cover tops out at {highestCover}, form starts at {lowestForm}: true`
		)
	end)

	it("no framework instance covers any node of the screen, painted OR reachable (R18)", function()
		--[[ THE STRUCTURAL RULE, checked as geometry rather than as paint: no
			instance the framework synthesized intersects a node the author declared.
			A paint assertion is what this repository cannot make headlessly — which
			is how an overlay that "was transparent" shipped over three pills.

			IT NOW READS BOTH OF THE MARK'S RECTS, and the second one is why this case
			was rewritten (M2 review, B-H1). The first version compared author rects
			against `mark.rect` — 20x22 — and never against `mark.hitRect`, the 44x44
			touch floor the renderer asks for and the adapter realizes as a real
			`FacetHitExpander` TextButton. With a fill-width compact form that floor
			reaches 12px back over the author's own node, and the file stayed green:
			the same shape as the original defect, a framework-owned instance over
			author content that every model-side check called fine.

			THE CONTROLLER'S RULING (R18, 2026-08-21) SPLITS THE RULE BY WHAT IS
			UNDERNEATH. The 44px floor is EXEMPT over PASSIVE content: 44px is the F1
			accessibility floor and the platform convention every OS ships — an
			enlarged tap target is allowed to extend over adjacent non-interactive
			content, and clamping it to the mark's reserved 20px column would put a
			below-floor target on the one thing on the row that exists to be tapped.
			It is BANNED over INTERACTIVE content: two overlapping actionable targets
			is the tap-ambiguity defect class, because the engine delivers input to the
			topmost object only and the player cannot see which one won.

			...AND DIR5 SPLITS IT AGAIN, BY DIRECTION. "Covers" is a claim about
			z, not about geometry, and the cover role's whole design is a rect the size
			of the form with every one of its z values BELOW it. So the painted rule
			reads the z the adapter was told:

			  * overlap AT OR ABOVE an author node — FORBIDDEN. This is the retired
			    cover's defect, and it stays banned for both roles.
			  * overlap strictly BELOW a PASSIVE author node — allowed, and counted.
			    The count is asserted non-zero so the allowance is a measured fact.
			  * overlap strictly below an INTERACTIVE author node — still forbidden:
			    a cover is only ever synthesized where nothing above it is
			    interactive, so one appearing here means the role derivation is wrong,
			    which is the one-gesture-two-meanings collision itself. ]]
		local MARK = "/S/C/Clock/Expand"
		local passiveOverlaps = 0
		local thefts: { string } = {}
		local rolesSeen: { string } = {}
		for _, interactive in { false, true } do
			local w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 150 } })
			w.present(ringScreen(interactive), { initialFocus = "none" })
			local mark = w.adapter.node(MARK)
			local markHit = w.adapter.hitRectOf(MARK)
			table.insert(rolesSeen, if interactive then "chevron" else "cover")
			--[[ THE INSTRUMENT IS NOT VACUOUS, AND THE TWO ROLES NOW ANSWER
				DIFFERENTLY (this file's own H1). A CHEVRON is a mark in its
				own reserved column and its 44px floor reaches only its region's passive
				gutter, so it keeps the whole thing. A COVER is the region's WHOLE BOX,
				and in THIS fixture the regions are edge to edge — so its floor reached
				960 px2 of `Before/First` and 828 of `After/Last`, and the clamp in
				`render/commit_walks.hitRects` gives it back the region instead, which
				for a cover IS its own painted rect. `nil` is therefore the correct
				answer here and the sweep below reads `mark.rect` for it: there is no
				expander left to be vacuous about.

				A COVER WITH ROOM STILL KEEPS ITS 44px — the HUD demo's three do — and
				that arm is pinned in `tests/hit_floor_region_clamp.spec.luau` beside
				this one's numbers. ]]
			local expectFloor = interactive
			if expectFloor then
				expect(markHit).never().toBeNil()
				expect(markHit.w >= 44 and markHit.h >= 44).toBe(true)
				expect(markHit.w >= mark.rect.w and markHit.h > mark.rect.h).toBe(true)
			else
				expect(markHit).toBeNil()
				markHit = mark.rect
			end
			--[[ ...AND SO IS THE Z READING: every node in the sweep has to have been
				told a z, or the direction test below is comparing nils. ]]
			expect(type(mark.z)).toBe("number")

			for _, path in w.adapter.paths() do
				-- the mark's own subtree is the framework's, and its ANCESTORS contain
				-- it by construction: neither is author content the mark sits over
				if string.find(path, MARK, 1, true) == 1 or string.find(MARK, path, 1, true) == 1 then
					continue
				end
				local n = w.adapter.node(path)
				if n == nil or n.rect == nil or n.rect.w <= 0 or n.rect.h <= 0 then
					continue
				end
				-- the affordance's own hit expander is banded one z BELOW it, so the
				-- whole affordance — painted rect and floor — is at or under `mark.z`
				local below = type(n.z) == "number" and mark.z < n.z

				-- (a) the PAINTED rect covers nothing it is not strictly UNDER
				local px, py = overlapOf(mark.rect, n.rect)
				if px > 0.5 and py > 0.5 then
					expect(`{path} under the affordance's paint, framework below it: {below}`).toBe(
						`{path} under the affordance's paint, framework below it: true`
					)
				end

				-- (b) the HIT floor covers no INTERACTIVE node, by either of its rects
				-- the hitRectOf arm is FORWARD protection: in today's fixtures every
				-- author node's hit rect is nil (re-review NEW-M2), so the arm is
				-- unexercised until the first author-side hit floor exists — kept
				-- because the rule is about both rects, not about these fixtures
				for _, authorRect in { n.rect, w.adapter.hitRectOf(path) } do
					local ox, oy = overlapOf(markHit, authorRect)
					if ox > 0.5 and oy > 0.5 then
						if not interactiveNode(n) then
							passiveOverlaps += 1
							continue
						end
						--[[ AN INTERACTIVE NODE UNDER THE FLOOR SPLITS BY SCOPE, and the
							cover's own floor is what made the distinction necessary: a cover
							is the region's whole box, so inflating a 20px zone to the 44px
							floor overhangs the ROW BELOW — measured 12px into the next
							region's Button.

							  INSIDE THE AFFORDANCE'S OWN REGION it stays absolutely
							  FORBIDDEN. That is the one-gesture-two-meanings collision the
							  chevron exists to prevent, and it is the collision R18 was ruled
							  on: two targets for the same content, and the player cannot see
							  which one won.

							  ACROSS REGIONS IT IS AN EXPOSURE, AND THIS CASE NO LONGER
							  RATIFIES IT (review H1, 2026-08-21). The previous version
							  asserted that the framework OUTRANKED the neighbour — "the band
							  is deliverable" — which made the case green *because* a press in
							  the bottom 12px of the region above, across its full width,
							  opened this plate instead of pressing the button the player
							  aimed at. Nothing in the suite could redden on it.

							  THE MEASUREMENT THAT CORRECTS THE REVIEW'S MECHANISM. The
							  review attributed the outranking to `render/hit_lift.luau`.
							  Measured here at 390x150, with the lift's constraint set for
							  this host EMPTIED: the z values do not move (First 5, After's
							  Last 8, Clock 9, its cover 11). The composition arranges its
							  regions by RANK — Before 1, After 2, Clock 3 — and paint order
							  follows the ARRANGED order, so the Clock branch is already
							  above both neighbours before any lift is considered. The lift
							  never fires for a cover.

							  SO THE HONEST RULE IS A BOUND, NOT A DELIVERY CLAIM. A cover is
							  the region's whole box, so a floor larger than that box leaves
							  the region on the axis it is short on, by exactly half the
							  shortfall each way — and NOTHING BEYOND THAT. That is what is
							  asserted: the overhang is the floor's own arithmetic and cannot
							  grow. Removing it altogether is a clamp in the renderer's floor
							  pass (`pushHitRects` inflates around the solved rect with no
							  knowledge of the node), which is behind the source-cap lock —
							  named in this round's report, owed with that file's extraction. ]]
						--[[ FORBIDDEN IN BOTH DIRECTIONS NOW. This case used
							to split here: inside the affordance's own region an interactive
							node under the floor was banned, and ACROSS a region boundary it
							was an EXPOSURE the case merely bounded — first by ratifying the
							lift that delivered it (review H1: green *because* the theft
							happened), then by asserting the overhang was no bigger than the
							floor's own arithmetic.

							The clamp closes it, so there is no band left to bound. An
							interactive node under a framework floor is a defect wherever it
							is, and the tail below asserts this branch is never entered
							rather than asserting it is. ]]
						table.insert(thefts, `{path} under the {if interactive then "chevron" else "cover"}'s floor`)
					end
				end
			end
		end
		-- the allowance is exercised: the cover DOES sit under the passive form,
		-- which is the whole of the director's gesture
		expect(passiveOverlaps >= 1).toBe(true)
		--[[ ...AND NOT ONE INTERACTIVE NODE IS UNDER EITHER ROLE'S FLOOR, in its own
			region or in a neighbour's. Before the bounded floor this read `overhangs >= 1` and
			was green BECAUSE the cover took 26% of each of the two buttons beside
			it. ]]
		expect(table.concat(thefts, " | ")).toBe("")
		expect(table.concat(rolesSeen, " ")).toBe("cover chevron")
	end)

	it("the hit expander is paint-INERT by construction, not by transparency (R18)", function()
		--[[ THE OTHER HALF OF B-H1, AND THE ONE THIS REPOSITORY'S OWN DOCTRINE
			DEMANDS. The `cover` role was retired on the ruling that "it is
			transparent, so it is harmless" is a claim about the ENGINE that nothing
			here makes or can make — and the object that argument still applied to, the
			`FacetHitExpander` sitting in the same z band the device round measured,
			was left in place unexamined.

			SO THE CLAIM IS MADE STRUCTURALLY INSTEAD, in three halves that do not rely
			on a transparency value being obeyed:

			  1. it is born writing nothing that paints — `Text = ""`,
			     `BackgroundTransparency = 1`, `AutoButtonColor = false`,
			     `BorderSizePixel = 0`;
			  2. NO PAINT CHANNEL EVER REACHES IT. Every fill, corner, stroke and state
			     in a Facet sheet hangs off a `facet-*` CLASS selector applied through
			     `CollectionService:AddTag` in `syncTags`, and an explicit paint
			     hand-off is recorded in the `Facet_PaintClaims` attribute. The expander
			     is `Instance.new`'d in `setHitRect` and enters neither path, so the
			     whole tag-driven vocabulary cannot address it. The property set the
			     adapter writes to it, anywhere, is enumerated and pinned;
			  3. ...and the rules that CAN still reach it — the bare CLASS selectors,
			     which need no tag — are enumerated out of the built sheet and shown to
			     deposit no paint on an empty-text, fully-transparent button.

			`src/client/screen_target.luau` is inside the source-cap band, so this is
			read as text rather than driven: the adapter cannot load headlessly anyway
			(`tests/lib/adapter_source.luau`). ]]
		local live = adapter_source.live()
		local body = adapter_source.bodyOf(live, "function adapter.setHitRect(handle: any, rect: any)")
		expect(#body > 0).toBe(true)
		for _, written in
			{
				'expander.Name = "FacetHitExpander"',
				'expander.Text = ""',
				"expander.BackgroundTransparency = 1",
				"expander.AutoButtonColor = false",
				"expander.BorderSizePixel = 0",
			}
		do
			expect(`setHitRect writes '{written}': {string.find(body, written, 1, true) ~= nil}`).toBe(
				`setHitRect writes '{written}': true`
			)
		end

		--[[ NO TAG AND NO CLAIM, ANYWHERE IN THE ADAPTER. A line that mentions an
			expander and a paint channel in the same breath is the mutation this
			refuses — `CollectionService:AddTag(expander, ...)` is the one the review
			named. Read across every part of the live adapter, not just this
			function. ]]
		local PAINT_CHANNELS = { "AddTag", "CollectionService", "CLAIM_ATTRIBUTE", "claimPaint", "syncTags" }
		local offenders: { string } = {}
		for line in string.gmatch(live, "[^\n]+") do
			if string.find(line, "xpander", 1, true) == nil then
				continue
			end
			-- a comment is prose, not a write
			if string.match(line, "^%s*%-%-") ~= nil then
				continue
			end
			for _, channel in PAINT_CHANNELS do
				if string.find(line, channel, 1, true) ~= nil then
					table.insert(offenders, `{channel}: {string.match(line, "^%s*(.-)%s*$")}`)
				end
			end
		end
		expect(`paint channels reaching the hit expander: {table.concat(offenders, " | ")}`).toBe(
			"paint channels reaching the hit expander: "
		)

		--[[ EVERY PROPERTY THE ADAPTER WRITES TO AN EXPANDER, enumerated from the
			source and compared against the declared paint-inert set. A new write of
			any kind lands here before it lands on a screen. ]]
		local written: { [string]: boolean } = {}
		for prop in string.gmatch(live, "xpander%.([%w]+)%s*=[^=]") do
			-- %w, not %a (re-review NEW-H1): a letters-only class made every
			-- digit-suffixed property invisible — BackgroundColor3 painted the
			-- expander solid red inside a fully green suite
			written[prop] = true
		end
		local INERT = {
			-- identity, geometry and z: nothing that deposits a pixel
			Name = true,
			Parent = true,
			Position = true,
			Size = true,
			ZIndex = true,
			Visible = true,
			-- the two that COULD paint, and the values they are given are why this
			-- object is inert: no text and no background
			Text = true,
			BackgroundTransparency = true,
			-- input/appearance suppressors
			AutoButtonColor = true,
			BorderSizePixel = true,
			Selectable = true,
			Active = true,
			Interactable = true,
		}
		local unexpected: { string } = {}
		for prop in written do
			if not INERT[prop] then
				table.insert(unexpected, prop)
			end
		end
		table.sort(unexpected)
		expect(`expander properties outside the paint-inert set: {table.concat(unexpected, ",")}`).toBe(
			"expander properties outside the paint-inert set: "
		)
		-- ...and the enumeration found the two that matter, so it is not empty
		expect(written.BackgroundTransparency).toBe(true)
		expect(written.Text).toBe(true)

		--[[ THE SHEET'S OWN REACH. A rule whose selector carries a CLASS token
			(`.facet-…`) cannot match an instance with no tags, and a pseudo-element
			rule addresses a child modifier this instance does not have. What is left
			is the bare class selectors, and they are enumerated by name: any new
			`TextButton` rule that paints reddens this line rather than a screen. ]]
		local model = sheet_model.build({ themes = { { name = "Dark", style = default_style } } })
		local reachable: { string } = {}
		for _, rule in model.rules do
			local selector = rule.selector
			if string.find(selector, ".", 1, true) ~= nil or string.find(selector, "::", 1, true) ~= nil then
				continue
			end
			if string.find(selector, "TextButton", 1, true) == nil then
				continue
			end
			for prop, value in rule.props do
				table.insert(reachable, `{rule.name}/{prop}`)
				if prop == "BackgroundTransparency" then
					-- the one property that could fill the 44x44 band, declared away
					expect(`{rule.name} BackgroundTransparency: {value.value}`).toBe(
						`{rule.name} BackgroundTransparency: 1`
					)
				end
			end
		end
		table.sort(reachable)
		expect(table.concat(reachable, " ")).toBe(
			"Button default/BackgroundTransparency Button text default/FontFace "
				.. "Button text default/TextColor3 Disabled button/TextTransparency"
		)
	end)

	it("the role is the forms' own answer, and only the cover is allowed to be under one", function()
		local passive = UI.Region({
			id = "Clock",
			group = "body",
			rank = 1,
			recover = "overflow",
			children = { textForm("Full"), textForm("Tiny") },
		})
		local chevron = UI.Region({
			id = "Tasks",
			group = "body",
			rank = 1,
			recover = "overflow",
			children = {
				textForm("Full"),
				UI.VStack({
					id = "Chip",
					children = { UI.Button({ id = "Open", label = "go", onActivate = function() end }) },
				}),
			},
		})
		expect(expandNodes(passive)[1].props.expandTarget.role).toBe("cover")
		expect(expandNodes(chevron)[1].props.expandTarget.role).toBe("chevron")
		--[[ THE LIFT IS THE COVER'S ALONE. A chevron stands BESIDE the form and
			overlaps nothing, so pushing it under would only lift it below the thing it
			is meant to sit next to — and the `zIndex` here is what the paint sweep
			above resolves into a z, so a role that took the wrong one would silently
			change what "below" means for the whole rule. ]]
		expect(expandNodes(passive)[1].props.zIndex).toBe(-1)
		expect(expandNodes(chevron)[1].props.zIndex).toBe(nil)
	end)
end)

describe("EXPAND 16 — the plate opens OVER a live screen, and hands it back", function()
	--[[ The second of the device round's three findings: opening the plate left the
		plate alone on a blank background. The base must stay PAINTED — the director
		allows it to be non-interactive under the focus trap, and nothing more.

		WHAT THIS CASE IS, said honestly: a regression FENCE, not the proof that the
		device symptom is gone. It passes at HEAD and passed before the fix, because
		the model kept every base node visible at the failing viewport — the symptom
		lives somewhere only a Play session can see. What it does is make the
		CONTRACT executable: the day a change to this feature hides, resizes or
		unmounts a base node while a plate is up, this reddens instead of waiting for
		another device round. The fix that ships beside it is the removal of the only
		node this overlay contributed that paints opaquely by design (the tail's
		seam band). ]]
	it("every base node keeps its rect and its visibility while the plate is up", function()
		local w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 150 } })
		w.present(ringScreen(false), { initialFocus = "none" })
		local before: { [string]: any } = {}
		for _, path in w.adapter.paths() do
			if string.find(path, "/S/", 1, true) == 1 then
				local n = w.adapter.node(path)
				if n ~= nil and n.rect ~= nil then
					before[path] = { v = w.adapter.visibleOf(path), w = n.rect.w, h = n.rect.h, x = n.rect.x }
				end
			end
		end
		w.adapter.tap("/S/C/Clock/Expand")
		w.pres.refresh()
		expect(w.pres.depth()).toBe(2)
		local checked = 0
		for path, was in before do
			local n = w.adapter.node(path)
			expect(`{path} still mounted: {n ~= nil}`).toBe(`{path} still mounted: true`)
			expect(`{path} still visible: {w.adapter.visibleOf(path)}`).toBe(`{path} still visible: {was.v}`)
			expect(`{path} same box: {n.rect.w}x{n.rect.h}@{n.rect.x}`).toBe(`{path} same box: {was.w}x{was.h}@{was.x}`)
			checked += 1
		end
		-- the fence is only a fence if it walked a screen
		expect(checked > 8).toBe(true)
	end)

	it("...and the plate contributes no opaque node of its own: no tail, no seam", function()
		local w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 150 } })
		w.present(ringScreen(false), { initialFocus = "none" })
		w.adapter.tap("/S/C/Clock/Expand")
		w.pres.refresh()
		--[[ THE WEDGE AND ITS SEAM are the only nodes an anchored surface paints
			opaquely by construction (a `raised` wedge and a `base` band carrying a
			reconstructed tint). This feature anchors plates to zone pills pressed
			against the screen edges — geometry the shipped tailed surfaces never gave
			the placement machinery — so it takes neither. ]]
		expect(w.adapter.node("/Expand:Clock/Layer/Tail")).toBeNil()
		expect(w.adapter.node("/Expand:Clock/Layer/TailSeam")).toBeNil()
		expect(w.adapter.node("/Expand:Clock/Layer/Surface/ExpandPanel")).never().toBeNil()
	end)

	it("the base is interactive again the moment the plate goes", function()
		local w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 150 } })
		w.present(ringScreen(false), { initialFocus = "none" })
		w.adapter.tap("/S/C/Clock/Expand")
		w.pres.refresh()
		expect(w.pres.depth()).toBe(2)
		w.system.deviceKey("ButtonB", true)
		w.system.deviceKey("ButtonB", false)
		w.pres.refresh()
		expect(w.pres.depth()).toBe(1)
		-- the affordance takes a tap again, which it could not while the modal held
		w.adapter.tap("/S/C/Clock/Expand")
		w.pres.refresh()
		expect(w.pres.depth()).toBe(2)
	end)
end)

describe("EXPAND 17 — the way out is a disc CENTRED on the plate's corner", function()
	--[[ PLATE DESIGN B (director choice 2026-08-21,
		`.superpowers/sdd/release-candidate-review/task-plate-design-spec.md`).

		What it replaces, measured on a phone at 360x691: the plate reserved the
		close disc's own metric (36) as its RIGHT padding while its left was
		`space.s` (8), so a 36px dead band trailed the content — and then pushed the
		disc `space.m` (16) outside the box on both axes, a number unrelated to the
		disc's size, so the disc was neither on the corner nor in the panel. The eye
		read three chips hugging one corner of a panel bigger than its content, plus
		a satellite.

		Option B keeps the corner disc the director's reference showed and fixes
		both causes at once:

		  · the padding is UNIFORM (`space.m` on all four sides), so the close
		    reserves nothing in content flow and the content sits dead centre of its
		    own frame;
		  · the straddle is DERIVED FROM THE DISC — `space.xs + disc/2` — so the
		    disc's centre and the plate's corner are the same point by construction
		    at every theme ladder, rather than two numbers that happen to be close.

		All three cases below read the geometry the adapter was told, at both rungs
		of the ten-foot ladder, and none of them names a pixel this framework did
		not derive from a token. ]]
	local PANEL = "/Expand:Clock/Layer/Surface/ExpandPanel"

	-- the plate, its disc and the panel that holds both, at one display class
	--[[ ...AND IT TAKES A PACKAGE, because the default is the LOOSEST one (fix
		round 1, review MEDIUM-4b). `studio_neutral` clears the R18 inequality by
		9.2px; `classic_desktop` clears it by 0.63px and clears the DISTANCE by
		0.31px — below the whole-pixel granularity a solve rounds its rects to. A
		geometric sweep that only ever runs the roomiest package is a sweep whose
		margin is not the guarantee's margin. ]]
	local function plateAt(displaySize: string?, packageName: string?): any
		local opts: any = { viewport = { x = 0, y = 0, w = 390, h = 150 } }
		if displaySize ~= nil then
			opts.displaySize = displaySize
			opts.viewport = { x = 0, y = 0, w = 1200, h = 150 }
		end
		if packageName ~= nil then
			local pkg = (require)(`../examples/themes/{packageName}`).build(Facet.themes)
			opts.themeMetrics = themeSnapshot.resolve(pkg, nil, {})
		end
		local w = worldLib.new(opts)
		w.present(ringScreen(false), { initialFocus = "none" })
		w.adapter.tap("/S/C/Clock/Expand")
		w.pres.refresh()
		return {
			w = w,
			panel = w.adapter.node(PANEL),
			plate = w.adapter.node(`{PANEL}/ExpandPlate`),
			close = w.adapter.node(`{PANEL}/ExpandClose`),
			content = w.adapter.node(`{PANEL}/ExpandPlate/Full`),
			metrics = w.env:get("themeMetrics"):get(),
		}
	end

	--[[ ...AND THE SHEET, which is the presentation the fence used to have a BLIND
		SPOT on (fix round 1, review HIGH-1). `closeAffordance()` is SHARED by
		`panelOf` and `sheetOf`: the margin that makes the plate's two corners
		coincide moved the disc INWARD on the sheet, where there is no straddle to
		absorb it, straight into the reservation `SHEET_PADDING.right` holds — and
		the fence swept the plate only, so the round's own instrument never looked at
		the presentation the round's own change regressed. The fixture is a form that
		FILLS the sheet's content box, because a hugging one leaves slack that hides
		the incursion. ]]
	local SHEET = "/ExpandSheet:Clock/Layer/ExpandSheet"
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
							children = {
								-- measured WIDER than the content cap, so the composition
								-- chooses the sheet; `fill` so what mounts is exactly the
								-- sheet's own content box
								UI.VStack({
									id = "Full",
									width = { type = "fill", weight = 1 },
									children = { fixedBox("Wide", 2000, 60) },
								}),
								fixedBox("Compact", 60, 20),
							},
						}),
					},
				}),
			},
		})
	end

	local function sheetAt(displaySize: string?): any
		local opts: any = { viewport = { x = 0, y = 0, w = 390, h = 30 } }
		if displaySize ~= nil then
			opts.displaySize = displaySize
			opts.viewport = { x = 0, y = 0, w = 1200, h = 30 }
		end
		local w = worldLib.new(opts)
		w.present(sheetScreen(), { initialFocus = "none" })
		w.adapter.tap("/S/C/Clock/Expand")
		w.pres.refresh()
		return {
			w = w,
			close = w.adapter.node(`{SHEET}/ExpandClose`),
			content = w.adapter.node(`{SHEET}/ExpandSheetPlate/Full`),
			metrics = w.env:get("themeMetrics"):get(),
		}
	end

	it("the plate's padding is UNIFORM — one token on all four sides, no reserved band", function()
		for _, displaySize in { "Medium", "Large" } do
			local g = plateAt(displaySize)
			local pad = themeSnapshot.resolveNumber(g.metrics, expandPlate.PADDING.top)
			expect(g.plate).never().toBeNil()
			expect(g.content).never().toBeNil()
			--[[ FOUR INSETS, ONE NUMBER, and the number is the token's own
				resolution at this rung — not a literal, and not three sides checked
				against a fourth. The trailing side is the one the shipped design got
				wrong (it was the disc's 36), so it is stated first. ]]
			local insets = {
				`leading {g.content.rect.x - g.plate.rect.x}`,
				`trailing {g.plate.rect.x + g.plate.rect.w - (g.content.rect.x + g.content.rect.w)}`,
				`top {g.content.rect.y - g.plate.rect.y}`,
				`bottom {g.plate.rect.y + g.plate.rect.h - (g.content.rect.y + g.content.rect.h)}`,
			}
			expect(`{displaySize}: {table.concat(insets, " ")}`).toBe(
				`{displaySize}: leading {pad} trailing {pad} top {pad} bottom {pad}`
			)
		end
	end)

	it("the disc's CENTRE is the plate's corner, and the panel still contains the disc", function()
		for _, displaySize in { "Medium", "Large" } do
			local g = plateAt(displaySize)
			local close, plate, panel = g.close, g.plate, g.panel
			expect(close).never().toBeNil()
			-- a DISC carrying a SEMANTIC ICON NAME, which is the framework's one icon
			-- affordance that never names an asset
			expect(close.props.shape).toBe("circle")
			expect(close.props.icon).toBe("close")
			expect(close.props.surface).toBe("chip")
			expect(close.rect.w).toBe(close.rect.h)
			expect(close.rect.h).toBe(themeSnapshot.resolveNumber(g.metrics, expandPlate.CLOSE_DISC))
			--[[ THE CONSTRUCTION, STATED AS THE EQUALITY IT IS. The disc's centre
				offset from the panel's top-trailing corner is `CLOSE_INSET + disc/2`;
				the plate's corner offset from that same corner IS its margin, which is
				written as those two terms. Equal by construction — so this reads them
				as points and compares them, which is the only form in which a tuned
				number could not pass. ]]
			expect(`{displaySize}: disc centre {close.rect.x + close.rect.w / 2},{close.rect.y + close.rect.h / 2}`).toBe(
				`{displaySize}: disc centre {plate.rect.x + plate.rect.w},{plate.rect.y}`
			)
			--[[ ...AND THE SURFACE BOX STILL CONTAINS IT, which is what the
				safe-area clamp clamps: `present/anchored` knows only the surface's
				box, so a disc outside it could be pushed off-screen at the edge. The
				inset is the token, so a package with a bigger `space.xs` moves the
				disc in rather than out. ]]
			local inset = themeSnapshot.resolveNumber(g.metrics, expandPlate.CLOSE_INSET)
			expect(
				`{displaySize}: disc inset from the panel {panel.rect.x + panel.rect.w - (close.rect.x + close.rect.w)},{close.rect.y - panel.rect.y}`
			).toBe(`{displaySize}: disc inset from the panel {inset},{inset}`)
		end
	end)

	--[[ THE FENCE IS A CIRCLE, and that is the honest instrument rather than a
		convenience: `shape = "circle"` paints a disc, and the one part of its
		bounding BOX that paints nothing is exactly the corner that reaches furthest
		in. A box-overlap sweep therefore reports an incursion the player cannot see
		— 2x2 px on the default package at Medium, 3x3 at Large, and 1 to 6 px across
		the shipped corpus.

		AND THE FALSE-NEGATIVE HALF OF THIS ARGUMENT WAS WRONG (fix round 1, review
		MEDIUM-3). The version of this comment that shipped said a box sweep "would
		go green on a package whose disc genuinely covered a word diagonally". It
		cannot: a circle's bounding box strictly CONTAINS the circle, so the box
		test's red set is a strict superset of this one's. With disc `D` and padding
		`P` the box fires iff `D > 2P` and the circle iff `D > 2*sqrt(2)*P`, so the
		box always fires first — measured on all ten configurations the guarantee
		runs over: box red, circle green, 20 rows out of 20. The false POSITIVE is
		the box sweep's only error mode, and that alone is the reason to use a
		circle. ]]
	local function distanceToRect(cx: number, cy: number, r: any): number
		local dx = math.max(r.x - cx, 0, cx - (r.x + r.w))
		local dy = math.max(r.y - cy, 0, cy - (r.y + r.h))
		return math.sqrt(dx * dx + dy * dy)
	end

	--[[ ONE FENCE, RUN ON WHICHEVER PRESENTATION IT IS HANDED. `subtree` is the
		prefix every AUTHOR node of that presentation shares. Returns the worst
		distance and the offenders, so a caller can state both the rule and the
		measurement that carries it. ]]
	local function r18Sweep(w: any, close: any, subtree: string): (number, { string }, number)
		local cx = close.rect.x + close.rect.w / 2
		local cy = close.rect.y + close.rect.h / 2
		local radius = close.rect.w / 2
		local covered: { string } = {}
		local swept, worst = 0, math.huge
		for _, path in w.adapter.paths() do
			if string.find(path, subtree, 1, true) ~= 1 then
				continue
			end
			local n = w.adapter.node(path)
			if n == nil or n.rect == nil or n.rect.w <= 0 or n.rect.h <= 0 then
				continue
			end
			swept += 1
			local d = distanceToRect(cx, cy, n.rect)
			worst = math.min(worst, d)
			if d < radius - 0.5 then
				table.insert(covered, `{path} at {d} < {radius}`)
			end
		end
		table.sort(covered)
		return worst, covered, swept
	end

	it("R18 — the disc's incursion lands on the PADDING and never on content, on BOTH presentations", function()
		--[[ THE SHEET ARM IS THE ONE THIS CASE WAS EXTENDED FOR. Measured before the
			fix, on a form that fills the sheet's content box: the disc's centre sat
			14.00 from the author's node against an 18 radius at Medium, and 21.00
			against 27 at Large — 4px and 6px of painted circle over the author's
			words. The parent's construction was exactly TANGENT (18.00 / 27.00), which
			is what `SHEET_PADDING`'s comment means by "the content box ends where the
			disc begins"; the shared `closeAffordance` margin broke it, and the fence
			that would have caught it swept the plate only. ]]
		for _, displaySize in { "Medium", "Large" } do
			for _, arm in
				{
					{ label = "plate", geom = plateAt(displaySize), subtree = `{PANEL}/ExpandPlate/` },
					{ label = "sheet", geom = sheetAt(displaySize), subtree = `{SHEET}/ExpandSheetPlate/` },
					--[[ THE TIGHTEST SHIPPED PACKAGE, swept as real solved rects rather
						than as the inequality alone: `classic_desktop` is `space.m` 8
						against a 22px disc, so the guarantee clears by 0.63px and the
						distance by 0.31px — inside the rounding a solve applies. If
						whole-pixel rects ever tip it, this arm is where it shows. ]]
					{
						label = "plate/classic_desktop",
						geom = plateAt(displaySize, "classic_desktop"),
						subtree = `{PANEL}/ExpandPlate/`,
					},
				}
			do
				local g = arm.geom
				expect(`{displaySize}/{arm.label}: close mounted {g.close ~= nil}`).toBe(
					`{displaySize}/{arm.label}: close mounted true`
				)
				local worst, covered, swept = r18Sweep(g.w, g.close, arm.subtree)
				-- a sweep that swept nothing proves nothing
				expect(`{displaySize}/{arm.label}: swept {swept > 0}`).toBe(`{displaySize}/{arm.label}: swept true`)
				expect(`{displaySize}/{arm.label}: {table.concat(covered, " ; ")}`).toBe(`{displaySize}/{arm.label}: `)
				-- ...and the sheet's is TANGENCY, not merely clearance: its reservation
				-- is exactly the disc plus its inset, so the nearest author point is
				-- the radius away and not one pixel more
				if arm.label == "sheet" then
					expect(`sheet {displaySize}: nearest {worst} vs radius {g.close.rect.w / 2}`).toBe(
						`sheet {displaySize}: nearest {g.close.rect.w / 2} vs radius {g.close.rect.w / 2}`
					)
				end
			end
		end
	end)

	it("...and the disc's HIT floor takes nothing from an interactive control on the plate", function()
		--[[ REVIEW MEDIUM-2, and it is the OTHER rect. The case above measures PAINT
			(a circle against author rects); the 44px effective target is a second
			rect the framework asks for, and on the default package it reaches 6px
			(Medium) / 9px (Large) PAST the padding and into the content box. Over
			text that is legal — R18 exempts the floor over PASSIVE content, which is
			the F1 accessibility floor every platform ships. Over an INTERACTIVE
			control it is banned: two actionable targets for one gesture, the
			framework's on top, and the player cannot see which won.

			The mechanism that answers it already shipped for the region cover
			(`render/commit_walks.growWithin`): a floor that grows one side
			at a time and stops at the first pressable thing. This round widened its
			scope from `role == "cover"` to the framework's whole synthesized chrome,
			so the close disc is bounded by the same rule. Measured before: 6x6 = 36
			px2 at Medium and 9x9 = 81 px2 at Large, over an author Button in the
			plate's top-trailing corner, with the close on top. ]]
		local function cornerScreen(): any
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
											--[[ THE AUTHOR'S OWN CONTROL, IN THE CORNER THE
												CLOSE'S FLOOR REACHES INTO — and it has to be the
												LAST child of a row for that, because the plate
												hugs: a control that is merely first in a column
												sits at the LEADING edge and the floor never comes
												near it (measured: right edge 71 against a band
												starting at 78, which is why the first draft of
												this case passed vacuously). ]]
											UI.HStack({
												id = "Row",
												children = {
													UI.Text({ id = "Body", text = "12 - 9", textSize = 16 }),
													UI.Button({
														id = "Corner",
														label = "go",
														onActivate = function() end,
													}),
												},
											}),
											UI.Text({ id = "Below", text = "2:14", textSize = 16 }),
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
		for _, displaySize in { "Medium", "Large" } do
			local opts: any = { viewport = { x = 0, y = 0, w = 390, h = 40 } }
			if displaySize == "Large" then
				opts.displaySize = "Large"
				opts.viewport = { x = 0, y = 0, w = 1200, h = 40 }
			end
			local w = worldLib.new(opts)
			w.present(cornerScreen(), { initialFocus = "none" })
			w.adapter.tap("/S/C/Clock/Expand")
			w.pres.refresh()
			local closePath = `{PANEL}/ExpandClose`
			local band = w.adapter.hitRectOf(closePath) or w.adapter.node(closePath).rect
			local corner = w.adapter.node(`{PANEL}/ExpandPlate/Full/Row/Corner`)
			expect(`{displaySize}: corner control mounted {corner ~= nil}`).toBe(
				`{displaySize}: corner control mounted true`
			)
			--[[ NON-VACUOUS: without the clamp the floor is bigger than the disc on
				both axes, which is the only state in which it could reach anything. ]]
			local painted = w.adapter.node(closePath).rect
			expect(`{displaySize}: floor asked for more than the disc {band.w >= painted.w and band.h >= painted.h}`).toBe(
				`{displaySize}: floor asked for more than the disc true`
			)
			local function areaOver(a: any, b: any): number
				local ox = math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x)
				local oy = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
				return if ox > 0 and oy > 0 then ox * oy else 0
			end
			--[[ THE RULE IS THAT THE FLOOR GRANTS NOTHING OVER THE CONTROL, not that
				nothing overlaps it at all — and the difference is a fact about the
				engine rather than about this design. A hit rect is a RECTANGLE and the
				disc is a CIRCLE, so the disc's own box already reaches
				`discHalf - padding` into the content box at its corner (2px near, 3px
				at Large) while the painted circle clears it by the case above. That
				residue belongs to the disc's own box and no floor can give it back;
				what the floor may not do is ADD to it. Measured before the widening:
				36 px2 at Medium and 81 px2 at Large against a disc-box residue of 4 and
				9 — the floor was contributing 32 and 72 px2 of its own. ]]
			local disc = w.adapter.node(closePath).rect
			expect(
				`{displaySize}: floor over the control {areaOver(band, corner.rect)} px2, disc's own box {areaOver(
					disc,
					corner.rect
				)} px2`
			).toBe(
				`{displaySize}: floor over the control {areaOver(disc, corner.rect)} px2, disc's own box {areaOver(
					disc,
					corner.rect
				)} px2`
			)
		end
	end)

	it("...and the guarantee is a TOKEN inequality, so a package that breaks it goes red here", function()
		--[[ WHY THE THREE CASES ABOVE ARE NOT ENOUGH. They measure the DEFAULT
			package on two rungs. The construction's promise is bigger: the disc
			reaches `disc/2` in from the plate's corner and the content box's nearest
			point is the padded corner, `padding * sqrt(2)` away, so R18 holds for
			every package satisfying

			    controlSizes.compact.height <= 2 * sqrt(2) * space.m

			(36 <= 45.2 on the neutral snapshot). It is the theme-authoring rule that
			the geometry above is only one instance of, and it is checked on every
			package this repository ships, at both rungs of the ladder — a package
			with a fatter disc or a thinner plate padding reddens HERE, with the two
			distances named, instead of painting a disc over a word on a device. ]]
		--[[ THE LIST IS DERIVED, NOT RESTATED (fix round 1, review LOW-3). A
			hand-written corpus plus a pinned `checked 18` is a COUNT, not a
			derivation: a tenth reference package would enter `REFERENCE_ORDER`,
			redden `theme_package_enumeration.spec` over there, and escape this
			guarantee here with the count still green. `shippable()` reads the
			directory, so the guarantee grows with the corpus and the assertion below
			is a function of it. ]]
		local packages = { "studio_neutral" }
		for _, name in themePackages.shippable() do
			table.insert(packages, name)
		end
		local checked = 0
		for _, name in packages do
			local package = if name == "studio_neutral"
				then themeSnapshot.neutralPackage()
				else (require)(`../examples/themes/{name}`).build(Facet.themes)
			local base = themeSnapshot.resolve(package, nil, {})
			for _, class in { "Medium", "Large" } do
				local snap = themeSnapshot.forDisplay(base, class)
				local nearest, reach = expandPlate.r18Clearance(snap)
				expect(`{name}/{class}: padding corner {nearest} > disc reach {reach}: {nearest > reach}`).toBe(
					`{name}/{class}: padding corner {nearest} > disc reach {reach}: true`
				)
				checked += 1
			end
		end
		expect(`checked {checked}`).toBe(`checked {#packages * 2}`)
		-- ...and the corpus is not empty or one-element, which is the only way the
		-- derivation above could pass while measuring nothing
		expect(`corpus {#packages >= 9}`).toBe("corpus true")
	end)

	it("...and the disc's inset is measured against the RING's own authority, package by package", function()
		--[[ THE RATCHET THIS REPLACES (gap 42, W3-B; closes task-plate-b-report.md's
			"Concerns carried forward" #1 and t16-triage.md:39). The round before this
			one could not make the inset ring-aware — `space.xs` is a METRIC, the ring's
			thickness lived only on the STYLE side (`extra.focusRingThickness` /
			`extra.tenFootFocusRingThickness`), and the metric snapshot answered nil for
			it — so it named `classic_desktop`/`compact_pointer`'s ten-foot shortfall (3
			against a 4px ring) as a RATCHET: a list of known-short packages, asserted in
			both directions so a third joining or one repairing would both redden here.

			`themes/snapshot.luau`'s `resolve` now mirrors both style values onto
			`controls.focusRing.thickness` (the ring) and `controls.focusRing.inset`
			(`math.max(space.xs, ring)`, at both rungs) — the metric snapshot's own
			vocabulary, which `expand_plate.CLOSE_INSET` now names directly instead of
			`space.xs`. Two things are proved below instead of one ratchet: the metric
			MIRRORS the style authority exactly (a parity check — if `resolve` ever drifts
			from what `screen_target` actually paints, this reddens), and the disc's inset
			clears the ring on EVERY shipped package at BOTH rungs, universally, with no
			named exceptions — because it is now the `max` of the ring and the package's
			own `space.xs`, not an unrelated spacing step that happened to be big enough. ]]
		local packages = { "studio_neutral" }
		for _, name in themePackages.shippable() do
			table.insert(packages, name)
		end
		local short: { string } = {}
		local mismatched: { string } = {}
		local checked = 0
		for _, name in packages do
			local package = if name == "studio_neutral"
				then themeSnapshot.neutralPackage()
				else (require)(`../examples/themes/{name}`).build(Facet.themes)
			-- the package's OWN theme entry first, then the library default — which is
			-- the `fill` semantics `tokens/sheet_model` applies when it builds a style
			local extra = (package.style.themes[1] or {}).extra or {}
			local base = themeSnapshot.resolve(package, nil, {})
			for _, class in { "Medium", "Large" } do
				local ring = if class == "Large"
					then extra.tenFootFocusRingThickness or default_style.extra.tenFootFocusRingThickness
					else extra.focusRingThickness or default_style.extra.focusRingThickness
				local snap = themeSnapshot.forDisplay(base, class)
				local mirroredRing = themeSnapshot.resolveNumber(snap, expandPlate.RING_THICKNESS)
				local inset = themeSnapshot.resolveNumber(snap, expandPlate.CLOSE_INSET)
				expect(`{name}/{class}: inset {type(inset)} ring {type(mirroredRing)}`).toBe(
					`{name}/{class}: inset number ring number`
				)
				if mirroredRing ~= ring then
					table.insert(mismatched, `{name}/{class}: metric {mirroredRing} style {ring}`)
				end
				if (inset :: number) < (ring :: number) then
					table.insert(short, `{name}/{class}`)
				end
				checked += 1
			end
		end
		table.sort(short)
		table.sort(mismatched)
		expect(`checked {checked}`).toBe(`checked {#packages * 2}`)
		-- non-vacuity, the LOW-3 pattern this round inherits
		expect(`corpus {#packages >= 9}`).toBe("corpus true")
		expect(`mirror mismatches: {table.concat(mismatched, " | ")}`).toBe("mirror mismatches: ")
		expect(`short: {table.concat(short, " ")}`).toBe("short: ")
	end)

	it("...and it is still the same control: one focus stop, the standard band, Return closes", function()
		local w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 150 } })
		w.present(ringScreen(false), { initialFocus = "none" })
		w.pres.focus.focusOn("/S/C/Clock/Expand")
		w.press("Return")
		w.pres.refresh()
		local stops = traversalPaths(w)
		expect(#stops).toBe(1)
		expect(stops[1]).toBe(`{PANEL}/ExpandClose`)
		--[[ THE WORD IS NOT DRAWN, and this is the framework's own rule doing it: a
			CONTENT button's label is semantics, so the renderer writes "" as its text
			(B-BTN1) and the content is what shows. The label itself — `"Close"`, what
			a screen reader says — is a construction fact this seam cannot report,
			because no adapter channel carries it; `blueprint.Button` refuses a Button
			without one, and the value is one grep from here. ]]
		local close = w.adapter.node(`{PANEL}/ExpandClose`)
		expect(close.props.label).never().toBe("Close")
		expect(#close.props.label <= 2).toBe(true)
		--[[ THE EFFECTIVE BAND, which is the hit rect where the control is under the
			floor and the painted rect where it is already over it — an expander is
			only built for the first case, so reading `hitRectOf` alone would report a
			generously-sized chip as having no band at all. ]]
		local closePath = `{PANEL}/ExpandClose`
		local band = w.adapter.hitRectOf(closePath) or w.adapter.node(closePath).rect
		expect(`{band.w}x{band.h} clears the floor: {band.w >= 44 and band.h >= 44}`).toBe(
			`{band.w}x{band.h} clears the floor: true`
		)
		w.press("Return")
		w.pres.refresh()
		expect(w.pres.depth()).toBe(1)
	end)
end)

describe("EXPAND 18 — a plate does not truncate what it was opened to show", function()
	--[[ The device round's fold-in: the task plate rendered "Win a…" at three rows.
		`plate.w` is `min(natural, viewport - gutters)` and `natural` is whatever the
		measure seam answers — which for a form that declared `width = fill` is its
		CONTENT, not what it asked for. The panel then squeezed rows that had room to
		spare. A fill form gets the cap. ]]
	local function fillFormScreen(): any
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
							id = "Tasks",
							group = "body",
							rank = 1,
							recover = "overflow",
							children = {
								UI.VStack({
									id = "Full",
									width = { type = "fill", weight = 1 },
									children = {
										UI.Text({ id = "Row1", text = "Win a round", textSize = 16 }),
										UI.Text({ id = "Row2", text = "Land 25 hits", textSize = 16 }),
										UI.Text({ id = "Row3", text = "Open a crate", textSize = 16 }),
									},
								}),
								UI.Text({ id = "Compact", text = "Tasks 1/3", textSize = 16 }),
							},
						}),
					},
				}),
			},
		})
	end

	it("a fill-width richest form gets the whole plate, not its own content width", function()
		local w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 40 } })
		w.present(fillFormScreen(), { initialFocus = "none" })
		local row = w.controller.compositionAt("/S/C").regions[1]
		expect(row.activeForm).toBe(2)
		-- the composition reports BOTH numbers: what the form measured, and the cap
		-- it was measured against
		expect(row.plate.max > row.plate.w).toBe(true)
		w.adapter.tap("/S/C/Tasks/Expand")
		w.pres.refresh()
		local plate = w.adapter.node("/Expand:Tasks/Layer/Surface/ExpandPanel/ExpandPlate")
		expect(plate).never().toBeNil()
		expect(plate.rect.w).toBe(row.plate.max)
	end)

	it("...and a HUGGING richest form still gets exactly what it measured, INSIDE the plate", function()
		--[[ THE DEFECT THIS CASE NOW OWNS (director round 5, MEASURED live: panel 135
			wide at x=151, its content spanning 159..294 against a right edge of 286).
			`plate.w` measures FORM 1; it was written straight onto a box that also
			declares padding, and a padded box's declared width is its OUTER width — so
			the content box was `plate.w` minus two insets and the form overflowed it by
			exactly that, at every viewport.

			So the assertion is no longer "the panel is `plate.w`" (which is what was
			green while the content bled): it is that the FORM gets `plate.w` and every
			node of it lands inside the plate that carries it. ]]
		local w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 150 } })
		w.present(ringScreen(false), { initialFocus = "none" })
		local row = w.controller.compositionAt("/S/C").regions[2]
		w.adapter.tap("/S/C/Clock/Expand")
		w.pres.refresh()
		local PANEL = "/Expand:Clock/Layer/Surface/ExpandPanel"
		local plate = w.adapter.node(`{PANEL}/ExpandPlate`)
		local form = w.adapter.node(`{PANEL}/ExpandPlate/Full`)
		expect(row.plate.w < row.plate.max).toBe(true)
		expect(form).never().toBeNil()
		expect(`the form measures the plate width: {form.rect.w}`).toBe(
			`the form measures the plate width: {row.plate.w}`
		)
		-- ...and the plate is WIDER than its content, by its own chrome
		expect(plate.rect.w > row.plate.w).toBe(true)
		local outside: { string } = {}
		for _, path in w.adapter.paths() do
			if string.find(path, `{PANEL}/ExpandPlate/`, 1, true) ~= 1 then
				continue
			end
			local n = w.adapter.node(path)
			if n == nil or n.rect == nil or n.rect.w <= 0 then
				continue
			end
			if n.rect.x < plate.rect.x - 0.5 or n.rect.x + n.rect.w > plate.rect.x + plate.rect.w + 0.5 then
				table.insert(
					outside,
					`{path} spans {n.rect.x}..{n.rect.x + n.rect.w} outside {plate.rect.x}..{plate.rect.x + plate.rect.w}`
				)
			end
		end
		table.sort(outside)
		expect(table.concat(outside, " ; ")).toBe("")
		-- the sweep walked something
		expect(#w.adapter.paths() > 10).toBe(true)
	end)
end)
