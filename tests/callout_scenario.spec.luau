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

local LuauUI = require("../src") :: any
local fake_target = require("./lib/fake_target")
local module = require("../examples/gallery/scenarios/callout") :: any

local PHONE = { w = 390, h = 844 }
local COMPACT_DESKTOP = { w = 700, h = 500 }
local DESKTOP = { w = 1200, h = 900 }

local function world(view: { w: number, h: number })
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = view.w, h = view.h })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = LuauUI.newPresenter(core, env, adapter, system)
	local built = module.build({
		LuauUI = LuauUI,
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
	platform inset facts, and `docs/lessons/device-emulator-truths.md` records that
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
