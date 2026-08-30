--!strict
--[[ THE SHOWCASE SURFACE FOR `newCallout` AND `help` —
	`examples/gallery/scenarios/callout.luau`.

	IT SHIPPED WITH NO SPEC AT ALL. `tests/callout.spec.luau` proves the CONSTRUCT
	against hand-built worlds and `tests/help.spec.luau` proves the plate, but the
	screen a person with a phone actually opens was reachable only through
	`gallery_demo_picker.spec`, which mounts its root node and asserts nothing
	else. Two of the four findings of the 2026-08-16 device review landed on this
	one file, and both are facts a headless solve can state outright:

	  * F2 — the coach marks showed once and then never again. The framework half
	    is fixed at the catcher (`tests/callout.spec.luau`), but the fixture half
	    is a contract, not a bug: `retired` is permanent BY CONTRACT, so a demo
	    with no way to start a fresh session is a device pass that can be run
	    exactly once. The reset is asserted here as a LOOP — show, retire, reset,
	    show again — because that is the thing a tester needs and the thing that
	    was missing.
	  * F3 — content clipped at the viewport edges. Asserted as painted rect vs
	    the screen's own content box, swept across the viewports a reviewer
	    switches between rather than the one a fixture was authored at.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local fake_target = require("./lib/fake_target")
local module = require("../examples/gallery/scenarios/callout") :: any

local PHONE = { w = 390, h = 844 }
local COMPACT_DESKTOP = { w = 700, h = 500 }
local DESKTOP = { w = 1200, h = 900 }

local function world(view: { w: number, h: number })
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = view.w, h = view.h })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = Facet.newPresenter(core, env, adapter, system)
	local built = module.build({
		Facet = Facet,
		core = core,
		env = env,
		adapter = adapter,
		presenter = pres,
		actionSystem = system,
	})
	built.handle = pres.present(built.screen, built.present)
	local w: any = { core = core, env = env, adapter = adapter, pres = pres, built = built, view = view }
	function w.settle(frames: number?)
		for _ = 1, frames or 8 do
			pres.tick(1 / 60)
			pres.refresh()
		end
	end
	w.settle()
	return w
end

describe("scenario 'callout': a device pass a tester can run more than once", function()
	--[[ THE LOOP THE DEVICE REVIEW ASKED FOR (F2). Director: *"the tooltips also
		showed up the first time I pressed the buttons but then they stopped
		appearing."* Half of that was the catcher (fixed in `callout.spec`); the
		other half is that this is what a retired coach mark is SUPPOSED to do, and
		the fixture offered no way back. A demo of a once-per-player mechanism has to
		be able to start a new player.

		Driven through `steps`, which is the same surface the buttons call, so the
		case cannot pass over a button that was never wired. ]]
	it("show -> retire -> RESET -> show again, without remounting the place", function()
		local w = world(PHONE)

		-- 1. the first showing
		expect(w.built.steps.show(w.built).state).toBe("showing")
		w.settle()

		-- 2. the player uses the feature: retired, permanently and by contract
		w.built.steps.use(w.built)
		w.settle()
		expect(w.built.report().tip.state).toBe("retired")
		-- ...and a second ask really is refused, which is the contract this fixture
		-- exists to demonstrate rather than a defect to route around
		expect(w.built.steps.show(w.built).state).toBe("retired")

		-- 3. THE RESET: a fresh session, in place
		w.built.steps.reset(w.built)
		w.settle()
		local afterReset = w.built.report()
		expect(afterReset.tip.state).toBe("waiting")
		expect(afterReset.seen).toBe(false)
		expect(afterReset.saved).toBe(module.copy.saveNothing)

		-- 4. ...and the coach mark shows AGAIN, which is the whole point
		expect(w.built.steps.show(w.built).state).toBe("showing")
		w.settle()
		expect(w.built.report().tip.state).toBe("showing")

		-- and the second plate is re-armed too — it carries no fixture-side state
		-- at all, so if the reset only cleared signals this would still be dead
		w.built.steps.reset(w.built)
		w.settle()
		expect(w.built.report().second.state).toBe("waiting")
		expect(w.core:lastError()).toBeNil()
	end)

	--[[ THE RESET MUST NOT TAKE THE SCREEN WITH IT (device review 2026-08-16, F2b).
		Director: *"note that clicking start a fresh session removes the two buttons
		the tips attach to."*

		The first version of this reset put the whole pair — the coach marks AND the
		two buttons they point at — inside a keyed `ForEach` and bumped the key. The
		buttons were not deleted, but their IDENTITY was: every path under the row
		went from `[gen-1]` to `[gen-2]`, and a coach mark's anchor is a PATH.
		Measured before the fix, on a fresh build with focus on the left button:

		    BEFORE  help plate placed at 12, 77.3 — under its anchor
		    AFTER   help plate placed at 0, 0     — 284x55, over the anchor

		A raised plate at the viewport origin covering an 80x46 button at 12,12 is
		what "the reset removes the buttons" looks like from the couch. The anchors
		are permanent furniture; only the coach marks are session state, so the
		session key is gone and the reset re-arms the CONSTRUCTS in place.

		The case is written against the paths, because a path IS the identity here —
		a check that only counted painted buttons would pass on the defect. ]]
	local PLUS = "/CalloutDemo/Bar/Plus"
	local SHARE = "/CalloutDemo/Bar/Share"

	it("the anchors survive a reset with their IDENTITY, not just their number", function()
		local w = world(PHONE)
		local plusBefore = w.adapter.node(PLUS)
		local shareBefore = w.adapter.node(SHARE)
		expect(`plus:{plusBefore ~= nil} share:{shareBefore ~= nil}`).toBe("plus:true share:true")

		w.built.steps.show(w.built)
		w.settle()
		w.built.steps.use(w.built)
		w.settle()
		w.built.steps.reset(w.built)
		w.settle()

		local plusAfter = w.adapter.node(PLUS)
		local shareAfter = w.adapter.node(SHARE)
		expect(`plus:{plusAfter ~= nil} share:{shareAfter ~= nil}`).toBe("plus:true share:true")
		-- the SAME boxes, in the same places: nothing was rebuilt underneath them
		expect(`{plusAfter.rect.x},{plusAfter.rect.y} {plusAfter.rect.w}x{plusAfter.rect.h}`).toBe(
			`{plusBefore.rect.x},{plusBefore.rect.y} {plusBefore.rect.w}x{plusBefore.rect.h}`
		)
		expect(`{shareAfter.rect.x},{shareAfter.rect.y}`).toBe(`{shareBefore.rect.x},{shareBefore.rect.y}`)
		-- ...and no path under a session key exists at all, on either side of it
		for _, path in w.adapter.paths() do
			expect(`{path} carries a session key: {string.find(path, "gen-", 1, true) ~= nil}`).toBe(
				`{path} carries a session key: false`
			)
		end
	end)

	it("nothing is left sitting on the anchors afterwards, and the tip shows again", function()
		local w = world(PHONE)
		-- put the ring on an anchor, which is what raises the focus-driven help plate
		-- (the surface that was stranded at the origin by the old reset)
		w.pres.focus.focusOn(SHARE)
		w.settle()
		w.built.steps.show(w.built)
		w.settle()
		w.built.steps.use(w.built)
		w.settle()
		expect(w.built.report().tip.state).toBe("retired")

		w.built.steps.reset(w.built)
		w.settle()

		local share = w.adapter.node(SHARE)
		-- EVERY painted rect that overlaps the anchor and is not the anchor's own
		-- subtree. Written as an overlap sweep rather than as "the help plate is not
		-- at 0,0", because the defect is "something is on top of the button" and the
		-- plate is only the surface that happened to be doing it.
		local covering: { string } = {}
		for _, path in w.adapter.paths() do
			if string.sub(path, 1, #SHARE) ~= SHARE and w.adapter.visibleOf(path) ~= false then
				local n = w.adapter.node(path)
				local isSurface = string.find(path, "/Layer/Surface", 1, true) ~= nil
				if
					isSurface
					and n ~= nil
					and n.rect.w > 0
					and n.rect.h > 0
					and n.rect.x < share.rect.x + share.rect.w
					and n.rect.x + n.rect.w > share.rect.x
					and n.rect.y < share.rect.y + share.rect.h
					and n.rect.y + n.rect.h > share.rect.y
				then
					table.insert(covering, path)
				end
			end
		end
		expect(`surfaces sitting on the anchor: {table.concat(covering, ", ")}`).toBe(
			"surfaces sitting on the anchor: "
		)
		-- and the whole point of a reset: it can be run again
		expect(w.built.steps.show(w.built).state).toBe("showing")
	end)

	--[[ THE RESET IS A BUTTON A THUMB CAN FIND, not a step only a spec can call.
		Every other affordance on this screen is an ordinary control with its own
		callback (the file's own rule), and a reset that only the scenario runner
		can reach would leave the device pass exactly as un-runnable as before. ]]
	it("the reset is on screen, at the 44px floor, beside the other picks", function()
		local w = world(PHONE)
		local node = w.adapter.node("/CalloutDemo/Page/Picks/Reset")
		expect(`the reset chip is painted? {node ~= nil}`).toBe("the reset chip is painted? true")
		expect(`{node.rect.h}px tall, under 44? {node.rect.h < 44}`).toBe(`{node.rect.h}px tall, under 44? false`)
		-- driven through the adapter, so the wiring is proved rather than described
		w.built.steps.show(w.built)
		w.settle()
		w.built.steps.use(w.built)
		w.settle()
		expect(w.built.report().tip.state).toBe("retired")
		w.adapter.tap("/CalloutDemo/Page/Picks/Reset")
		w.settle()
		expect(w.built.report().tip.state).toBe("waiting")
	end)
end)

--[[ F3 — THE SCREEN'S OWN EDGES. Director, on compact desktop: *"the left pixel
	seems cutoff"*, with the pick row's trailing chip cut off on the right.

	MEASURED, AND IT IS NOT THE FIXTURE AND NOT `wrap`. The page's own rects are
	inside their 12px gutter at every width from 320 up. What was flush is the
	COACH MARK: `presenter.safeBox()` was nothing but the per-edge max of the two
	platform inset facts, and the emulator records that
	the engine reports only the 58px topbar and nothing lateral — so both facts are
	structurally ZERO on the sides and the plate was placed hard against the glass.
	The trailing chip was not overflowing either: a flush-right plate was sitting
	on top of it, which is what "cut off on the right" looks like in a still frame.

	WHY EVERY EXISTING CHECK PASSED ON IT. Both f1 cases assert containment as
	`panel.x + panel.w <= 390` — and a rect whose right edge is EXACTLY the
	viewport width satisfies `<=`. Flush is the defect, so an overflow-only check
	is the one instrument that cannot see it. These ask for the gutter instead. ]]
describe("scenario 'callout': the plate clears the glass, and the page stays in its gutter", function()
	local function gutterOf(w: any): number
		local metrics = w.env:get("themeMetrics"):get()
		local space = (if type(metrics) == "table" then (metrics :: any).space else nil) or {}
		return space.s
	end

	it("the raised coach mark clears BOTH lateral edges by the theme's own step", function()
		for _, view in { PHONE, COMPACT_DESKTOP, DESKTOP } do
			local w = world(view)
			local gutter = gutterOf(w)
			expect(`{view.w}: a themed step? {type(gutter) == "number" and gutter > 0}`).toBe(
				`{view.w}: a themed step? true`
			)
			w.built.steps.show(w.built)
			w.settle()
			local plate = w.adapter.node("/AvatarTip/Layer/Surface/Plate")
			expect(`{view.w}: the plate is up? {plate ~= nil}`).toBe(`{view.w}: the plate is up? true`)
			local r = plate.rect
			expect(`{view.w}x{view.h} left edge {r.x}, clears {gutter}? {r.x >= gutter - 0.01}`).toBe(
				`{view.w}x{view.h} left edge {r.x}, clears {gutter}? true`
			)
			expect(`{view.w}x{view.h} right edge {r.x + r.w}, clears {gutter}? {r.x + r.w <= view.w - gutter + 0.01}`).toBe(
				`{view.w}x{view.h} right edge {r.x + r.w}, clears {gutter}? true`
			)
		end
	end)

	--[[ THE NEGATIVE CONTROL, without which `max` silently degrades into
		`replace`: a REAL platform inset larger than the theme's step still wins.
		A gutter that overrode a notch would be a worse bug than the one it fixed. ]]
	it("a real safe-area inset bigger than the step still wins", function()
		local w = world(PHONE)
		local gutter = gutterOf(w)
		w.env:set("coreSafeInsets", { top = 0, bottom = 0, left = gutter + 40, right = 0 })
		w.built.steps.show(w.built)
		w.settle()
		local r = w.adapter.node("/AvatarTip/Layer/Surface/Plate").rect
		expect(`left edge {r.x} respects the {gutter + 40}px inset? {r.x >= gutter + 40 - 0.01}`).toBe(
			`left edge {r.x} respects the {gutter + 40}px inset? true`
		)
	end)

	--[[ AND THE PAGE ITSELF, which the same review suspected and which measured
		clean: nothing the fixture paints crosses either LATERAL edge. Horizontal
		only, deliberately — this page scrolls on y, so content below the fold is
		the feature and asserting vertical containment would assert the scroll away. ]]
	it("nothing the page paints crosses a lateral edge, at any swept size", function()
		for _, view in { PHONE, COMPACT_DESKTOP, DESKTOP } do
			local w = world(view)
			local offenders: { string } = {}
			for _, path in w.adapter.paths() do
				if string.find(path, "^/CalloutDemo/") == nil then
					continue
				end
				local node = w.adapter.node(path)
				local r = node ~= nil and node.rect
				if r == nil or r.w <= 0 or r.h <= 0 then
					continue
				end
				if r.x < -0.01 or r.x + r.w > view.w + 0.01 then
					table.insert(offenders, `{path} [{r.x} .. {r.x + r.w}]`)
				end
			end
			expect(`{view.w}x{view.h}: {table.concat(offenders, "; ")}`).toBe(`{view.w}x{view.h}: `)
		end
	end)
end)
