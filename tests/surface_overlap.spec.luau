--!strict
--[[ CROSS-SURFACE OVERLAP — the alarm for two surfaces covering each other (ADR-0028).

	The director, 2026-08-14, watching a leftover debug probe interleave with a
	real fixture in his live Studio session, both starting at x=16: *"the
	framework should stop this from happening."*

	ADR-0025's collision alarm answers "which REGIONS of one composition paint
	into each other". Nothing answered "which SURFACES paint into each other",
	which is the shape a real game has constantly — a HUD, a modal, a toast
	layer, a debug overlay, each mounted through its own `renderer.attach`.

	THE PREDICATE, and every case below defends one clause of it:

	    fire when two live surfaces on one target both COVER something, their
	    cover rects intersect, and NEITHER declared that it means to cover the
	    other.

	  A. THE PURE PAIR SCAN — geometry, bands and `edgeToEdge`, with no engine
	     and no controller in sight.
	  B. THE DECLARATIONS — `edgeToEdge`, a different display band, and the fact
	     that an *unset* display order declares nothing at all.
	  C. THE COVERING SET — every way a surface is present and covers nothing:
	     `hidden`, an authored `opacity = 0`, a framework fade to nothing, a
	     hidden root, an unsolved surface. ADR-0026's hand-off, pinned.
	  D. THE DELIVERY — it arrives through `controller.diagnostics()`, on BOTH
	     surfaces of the pair, is not `designed`, and leaves with the surface.
	  E. THE COST — zero scans per frame, by measurement rather than assertion.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src") :: any
local UI = require("../src/blueprint")
local overlap = require("../src/render/surface_overlap")
local fake_target = require("./lib/fake_target")

local function rect(x: number, y: number, w: number, h: number): any
	return { x = x, y = y, w = w, h = h }
end

-- a bare descriptor for the pure scan: no controller, no adapter, no engine
local function surface(id: string, r: any, opts: any?): any
	local o = opts or {}
	return {
		id = id,
		rect = r,
		displayOrder = o.displayOrder,
		rootPolicy = o.rootPolicy or "coreSafeContent",
	}
end

--[[ ── A. THE PURE PAIR SCAN ──────────────────────────────────────────────── ]]

describe("cross-surface overlap: the pure pair scan", function()
	it("two undeclared surfaces whose cover rects intersect are ONE reported pair", function()
		local found = overlap.scan({
			surface("Hud", rect(0, 0, 400, 600)),
			surface("Probe", rect(16, 16, 200, 120)),
		})
		expect(#found).toBe(1)
		expect(found[1].a).toBe("Hud")
		expect(found[1].b).toBe("Probe")
		expect(found[1].dx).toBe(200)
		expect(found[1].dy).toBe(120)
	end)

	it("rects that only touch at an edge do not intersect — a 0px overlap is not an overlap", function()
		expect(#overlap.scan({
			surface("Left", rect(0, 0, 100, 100)),
			surface("Right", rect(100, 0, 100, 100)),
		})).toBe(0)
		expect(#overlap.scan({
			surface("Top", rect(0, 0, 100, 100)),
			surface("Bottom", rect(0, 100, 100, 100)),
		})).toBe(0)
	end)

	it("a FULL COVER is reported as a different shape from a partial overlap", function()
		local whole = overlap.scan({
			surface("Backdrop", rect(0, 0, 400, 600)),
			surface("Panel", rect(16, 16, 200, 120)),
		})
		expect(whole[1].covered).toBe("Panel")
		expect(string.find(overlap.issue(whole[1]), "'Backdrop' completely covers surface 'Panel'", 1, true) ~= nil).toBe(
			true
		)

		local partial = overlap.scan({
			surface("A", rect(0, 0, 200, 200)),
			surface("B", rect(100, 100, 200, 200)),
		})
		expect(partial[1].covered).toBe(nil)
		expect(string.find(overlap.issue(partial[1]), "'A' overlaps surface 'B' by 100x100px", 1, true) ~= nil).toBe(
			true
		)
	end)

	it("the report is deterministic: pairs sorted by id, and each pair filed once", function()
		local found = overlap.scan({
			surface("Zulu", rect(0, 0, 400, 600)),
			surface("Alpha", rect(0, 0, 400, 600)),
			surface("Mike", rect(0, 0, 400, 600)),
		})
		expect(#found).toBe(3)
		local seen = {}
		for _, o in found do
			table.insert(seen, `{o.a}|{o.b}`)
		end
		expect(table.concat(seen, " ")).toBe("Alpha|Mike Alpha|Zulu Mike|Zulu")
	end)

	it("a surface that covers nothing (nil rect) is in no pair at all", function()
		expect(#overlap.scan({
			surface("Hud", rect(0, 0, 400, 600)),
			surface("Faded", nil),
		})).toBe(0)
	end)

	it("a zero-area cover rect is not a cover", function()
		expect(#overlap.scan({
			surface("Hud", rect(0, 0, 400, 600)),
			surface("Empty", rect(0, 0, 0, 0)),
		})).toBe(0)
	end)

	it("one surface alone can collide with nothing", function()
		expect(#overlap.scan({ surface("Hud", rect(0, 0, 400, 600)) })).toBe(0)
		expect(#overlap.scan({})).toBe(0)
	end)
end)

--[[ ── B. THE DECLARATIONS ─────────────────────────────────────────────────── ]]

describe("cross-surface overlap: what counts as declaring an intent to cover", function()
	it("edgeToEdge on EITHER side is a declaration — a scrim means to cover, and means to be covered", function()
		expect(#overlap.scan({
			surface("Hud", rect(0, 0, 400, 600)),
			surface("Scrim", rect(0, 0, 400, 600), { rootPolicy = "edgeToEdge" }),
		})).toBe(0)
		expect(#overlap.scan({
			surface("Scrim", rect(0, 0, 400, 600), { rootPolicy = "edgeToEdge" }),
			surface("Hud", rect(0, 0, 400, 600)),
		})).toBe(0)
	end)

	it("deviceSafeContent is NOT a declaration — it is an inset choice, not a layering one", function()
		expect(#overlap.scan({
			surface("Hud", rect(0, 0, 400, 600), { rootPolicy = "deviceSafeContent" }),
			surface("Probe", rect(16, 16, 200, 120)),
		})).toBe(1)
	end)

	it("two DIFFERENT display bands is a declaration — a modal over a base screen is what a modal is for", function()
		expect(#overlap.scan({
			surface("Hud", rect(0, 0, 400, 600), { displayOrder = 10100 }),
			surface("Modal", rect(0, 0, 400, 600), { displayOrder = 40100 }),
		})).toBe(0)
	end)

	it("...but the SAME band is not, however far apart the two orders are", function()
		local found = overlap.scan({
			surface("Hud", rect(0, 0, 400, 600), { displayOrder = 10100 }),
			surface("Probe", rect(16, 16, 200, 120), { displayOrder = 10900 }),
		})
		expect(#found).toBe(1)
	end)

	it("an UNSET display order declares nothing — a raw attach that never ordered itself is not layered", function()
		-- the director's case exactly: a probe attached and never given a layer
		local found = overlap.scan({
			surface("Hud", rect(0, 0, 400, 600), { displayOrder = 10100 }),
			surface("Probe", rect(16, 16, 200, 120)),
		})
		expect(#found).toBe(1)
		expect(#overlap.scan({
			surface("Hud", rect(0, 0, 400, 600)),
			surface("Probe", rect(16, 16, 200, 120)),
		})).toBe(1)
	end)

	it(
		"the four SURFACE_LAYER bands land in four DISTINCT bands — the presenter's table and this scan agree",
		function()
			local layers = (require("../src/present/presenter") :: any).SURFACE_LAYER
			local bands: { [number]: string } = {}
			local names = {}
			for name in layers do
				table.insert(names, name)
			end
			table.sort(names)
			expect(#names).toBe(4)
			for _, name in names do
				local band = overlap.bandOf(layers[name])
				expect(`{name} shares a band with {tostring(bands[band])}`).toBe(`{name} shares a band with nil`)
				bands[band] = name
			end
			-- ...and the +100 per-surface step inside a band never leaves it: the
			-- presenter allows ~100 live surfaces per band before two would tie
			expect(overlap.bandOf(layers.base + 100)).toBe(overlap.bandOf(layers.base + 9900))
			-- ...and the synthesized scrim at owner-50 stays under its owner's band
			expect(overlap.bandOf(layers.base + 100 - 50)).toBe(overlap.bandOf(layers.base + 100))
		end
	)
end)

--[[ ── C / D / E. THE LIVE MECHANISM ───────────────────────────────────────── ]]

local function world()
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = LuauUI.newPresenter(core, env, adapter, system)
	return { core = core, env = env, adapter = adapter, presenter = pres, system = system }
end

local function panel(id: string, props: any?): any
	local p: any = props or {}
	return UI.Screen({
		id = id,
		children = {
			UI.ZStack({
				id = "Plate",
				width = { type = "fixed", px = 200 },
				height = { type = "fixed", px = 120 },
				opacity = p.opacity,
				hidden = p.hidden,
				canvasGroup = p.canvasGroup,
				children = { UI.Text({ id = "T", text = id }) },
			}),
		},
	})
end

local function crossFindings(handle: any): { any }
	local out = {}
	for _, finding in handle.controller.diagnostics() do
		if string.find(finding.issue, "surface", 1, true) ~= nil then
			table.insert(out, finding)
		end
	end
	return out
end

describe("cross-surface overlap: it arrives through controller.diagnostics()", function()
	it("two base screens covering each other file the finding on BOTH surfaces", function()
		local w = world()
		local a = w.presenter.present(panel("Hud"))
		local b = w.presenter.present(panel("Probe"))
		w.presenter.refresh()

		local fa, fb = crossFindings(a), crossFindings(b)
		expect(#fa).toBe(1)
		expect(#fb).toBe(1)
		expect(fa[1].node).toBe("/Hud")
		expect(fb[1].node).toBe("/Probe")
		-- one sentence, naming both surfaces and the remedy
		expect(string.find(fa[1].issue, "'Hud'", 1, true) ~= nil).toBe(true)
		expect(string.find(fa[1].issue, "'Probe'", 1, true) ~= nil).toBe(true)
		expect(string.find(fa[1].issue, "setDisplayOrder", 1, true) ~= nil).toBe(true)
		-- it is a DEFECT, not the framework doing what it was told (ruling 8)
		expect(fa[1].designed).toBe(nil)
	end)

	it("...and it is the only new finding: a single surface on the target reports nothing", function()
		local w = world()
		local a = w.presenter.present(panel("Hud"))
		w.presenter.refresh()
		expect(#crossFindings(a)).toBe(0)
	end)

	it("surfaces whose painted content does not intersect are not a pair", function()
		-- `deviceSafeContent` pushes the second surface's content rect 300px down
		-- (and is deliberately NOT a declaration — see the pure cases above), so
		-- the two 200x120 plates are 180px apart and share nothing
		local w = world()
		w.env:set("deviceSafeInsets", { top = 300, bottom = 0, left = 0, right = 0 })
		local a = w.presenter.present(panel("Hud"))
		local b = w.presenter.present(panel("Probe"), { rootPolicy = "deviceSafeContent" })
		w.presenter.refresh()
		expect(`{a.controller.coverRect().y} {b.controller.coverRect().y}`).toBe("0 300")
		expect(#crossFindings(a)).toBe(0)
		expect(#crossFindings(b)).toBe(0)
	end)

	it("a container that FILLS claims the whole box it fills, and the alarm says so", function()
		-- the cover rect is what the surface paints, and a fill container paints
		-- the whole screen even when its one visible child is a corner badge: it
		-- may put that badge anywhere in the box, at any viewport and text size
		local w = world()
		w.env:set("deviceSafeInsets", { top = 300, bottom = 0, left = 0, right = 0 })
		local a = w.presenter.present(UI.Screen({
			id = "Hud",
			children = {
				UI.Anchor({
					id = "A",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						UI.Box({
							id = "Badge",
							anchor = "topLeft",
							width = { type = "fixed", px = 40 },
							height = { type = "fixed", px = 40 },
						}),
					},
				}),
			},
		}))
		local b = w.presenter.present(panel("Probe"), { rootPolicy = "deviceSafeContent" })
		w.presenter.refresh()
		expect(a.controller.coverRect().h).toBe(600)
		expect(#crossFindings(a)).toBe(1)
		expect(#crossFindings(b)).toBe(1)
	end)

	it("a MODAL over a base screen reports nothing — the band is the declaration", function()
		local w = world()
		local a = w.presenter.present(panel("Hud"))
		local m = w.presenter.presentModal(panel("Sheet"))
		w.presenter.refresh()
		expect(#crossFindings(a)).toBe(0)
		expect(#crossFindings(m)).toBe(0)
	end)

	it("the modal's own SCRIM reports nothing either — it is edgeToEdge", function()
		local w = world()
		local a = w.presenter.present(panel("Hud"))
		w.presenter.presentModal(panel("Sheet"))
		w.presenter.refresh()
		-- the scrim sits at owner.displayOrder-50, in the BASE band, right over
		-- the base screen: only `edgeToEdge` keeps it quiet
		expect(#crossFindings(a)).toBe(0)
	end)

	it("a dismissed surface stops being a surface — the pair leaves with it", function()
		local w = world()
		local a = w.presenter.present(panel("Hud"))
		local b = w.presenter.present(panel("Probe"))
		w.presenter.refresh()
		expect(#crossFindings(a)).toBe(1)
		w.presenter.dismiss(b)
		w.presenter.refresh()
		expect(#crossFindings(a)).toBe(0)
	end)

	--[[ ...AND IT STOPS THE MOMENT IT IS DISMISSED, NOT WHEN THE PIXELS STOP.

		Found by the corpus, not by design: `tests/reference/sipworks_spec` went
		red on eight compact cases the hour this alarm landed, because
		`p3_sipworks` pushes one full-screen detail over another — `dismiss` the
		outgoing, `presentModal` the incoming — and with a `slide-left`
		transition the outgoing tree stays mounted and fully painted for the
		whole animation. A departing screen covering its replacement is the
		transition doing its job.
	]]
	it("a dismissed surface with a live EXIT TRANSITION is out immediately, tree and all", function()
		local w = world()
		local a = w.presenter.present(panel("Hud"))
		local b = w.presenter.present(panel("Probe"), { transition = { enter = "slide-left" } })
		w.presenter.refresh()
		expect(#crossFindings(a)).toBe(1)
		w.presenter.dismiss(b)
		-- the tree is STILL MOUNTED and still painting: the exit has not run
		expect(b.controller.coverRect() ~= nil).toBe(true)
		expect(#crossFindings(a)).toBe(0)
	end)

	it("a raw renderer.attach surface leaves at dispose — nothing needs a presenter", function()
		local w = world()
		local a = w.presenter.present(panel("Hud"))
		local mounted = require("../src/mount").mount(w.core, panel("Probe"))
		local ctrl = require("../src/render/renderer").attach(w.core, mounted, w.env, w.adapter, {})
		ctrl.initialRender()
		w.presenter.refresh()
		expect(#crossFindings(a)).toBe(1)
		ctrl.dispose()
		expect(#crossFindings(a)).toBe(0)
	end)

	--[[ ...AND IT LEAVES THE REGISTRY, NOT JUST THE REPORT.

		This case exists because a mutation found the line that does it to be
		decoration: a disposed controller answers a nil `coverRect` (its
		`lastRects` are cleared), so deleting the unregister changed no finding
		anywhere. What it changes is that the bucket for a long-lived paint target
		— a PlayerGui outlives every surface in a session — grows by one dead
		entry per mount, forever, each holding a closure over a destroyed
		controller. That is a leak, so it gets the check the finding could not
		give it.
	]]
	it("a disposed surface leaves the REGISTRY: the target's bucket does not grow with every mount", function()
		local w = world()
		w.presenter.present(panel("Hud"))
		expect(overlap.count(w.adapter)).toBe(1)
		for i = 1, 5 do
			local mounted = require("../src/mount").mount(w.core, panel(`Probe{i}`))
			local ctrl = require("../src/render/renderer").attach(w.core, mounted, w.env, w.adapter, {})
			ctrl.initialRender()
			ctrl.dispose()
		end
		expect(overlap.count(w.adapter)).toBe(1)
	end)
end)

describe("cross-surface overlap: the covering set (ADR-0026's hand-off)", function()
	it("a surface whose content is `hidden` covers nothing", function()
		local w = world()
		local a = w.presenter.present(panel("Hud"))
		w.presenter.present(panel("Probe", { hidden = true }))
		w.presenter.refresh()
		expect(#crossFindings(a)).toBe(0)
	end)

	it("a surface at `opacity = 0` covers nothing — a geometry-only test would report it", function()
		local w = world()
		local a = w.presenter.present(panel("Hud"))
		w.presenter.present(panel("Probe", { opacity = 0 }))
		w.presenter.refresh()
		expect(#crossFindings(a)).toBe(0)
	end)

	it("...and at any opacity above zero it covers again — 0 is the edge, not `opacity` itself", function()
		local w = world()
		local a = w.presenter.present(panel("Hud"))
		w.presenter.present(panel("Probe", { opacity = 0.01 }))
		w.presenter.refresh()
		expect(#crossFindings(a)).toBe(1)
	end)

	it("a framework fade to nothing covers nothing — the same rule, from the other contributor", function()
		local w = world()
		local a = w.presenter.present(panel("Hud"))
		local b = w.presenter.present(panel("Probe", { canvasGroup = true }))
		w.presenter.refresh()
		expect(#crossFindings(a)).toBe(1)
		b.controller.setPresentationTransparency("/Probe/Plate", 1)
		expect(#crossFindings(a)).toBe(0)
		b.controller.setPresentationTransparency("/Probe/Plate", 0.5)
		expect(#crossFindings(a)).toBe(1)
	end)

	it("a surface whose ROOT is not visible covers nothing", function()
		local w = world()
		local a = w.presenter.present(panel("Hud"))
		local b = w.presenter.present(panel("Probe"))
		w.presenter.refresh()
		expect(#crossFindings(a)).toBe(1)
		expect(b.controller.setRootVisible(false)).toBe(true)
		expect(#crossFindings(a)).toBe(0)
		b.controller.setRootVisible(true)
		expect(#crossFindings(a)).toBe(1)
	end)

	it("coverRect is the union of what a surface paints BELOW its root, not the root's own claim", function()
		local w = world()
		local a = w.presenter.present(panel("Hud"))
		w.presenter.refresh()
		local r = a.controller.coverRect()
		expect(`{r.x},{r.y} {r.w}x{r.h}`).toBe("0,0 200x120")
		-- ...and it is a copy, like every other diagnostic read (F-30)
		r.w = 1
		expect(a.controller.coverRect().w).toBe(200)
	end)
end)

describe("cross-surface overlap: the cost is zero off the inspection path", function()
	it("a frame NEVER scans — the whole mechanism runs only when diagnostics() is read", function()
		local w = world()
		w.presenter.present(panel("Hud"))
		w.presenter.present(panel("Probe"))
		local before = overlap.scans()
		for _ = 1, 60 do
			w.presenter.refresh()
		end
		expect(overlap.scans() - before).toBe(0)
	end)

	it("...and a single-surface target does not scan even when it IS read", function()
		local w = world()
		local a = w.presenter.present(panel("Hud"))
		w.presenter.refresh()
		local before = overlap.scans()
		a.controller.diagnostics()
		a.controller.diagnostics()
		expect(overlap.scans() - before).toBe(0)
	end)

	it("...and two surfaces scan exactly once per read", function()
		local w = world()
		local a = w.presenter.present(panel("Hud"))
		w.presenter.present(panel("Probe"))
		w.presenter.refresh()
		local before = overlap.scans()
		a.controller.diagnostics()
		expect(overlap.scans() - before).toBe(1)
	end)

	it("two surfaces on DIFFERENT targets never see each other", function()
		local w1, w2 = world(), world()
		local a = w1.presenter.present(panel("Hud"))
		w2.presenter.present(panel("Probe"))
		w1.presenter.refresh()
		w2.presenter.refresh()
		expect(#crossFindings(a)).toBe(0)
	end)
end)
