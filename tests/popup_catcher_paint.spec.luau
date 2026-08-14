--!strict
--[[ THE SYNTHESIZED POPUP CATCHER MUST BE INVISIBLE (device bug, director,
	2026-08-13: "in the showcase when i swipe from left to right in swipe row
	actions/table, some random thing appears over the top of the screen blocking
	the demo picker and settings button" — evidence: topscreen.mov).

	THE MECHANISM. An open row-actions tray publishes `outsideDismiss.active`
	(row_actions.luau's contribution bundle), so the presenter synthesizes its
	transient popup catcher: a full-viewport `Button` on its own `__popupcatcher__`
	root, mounted at `owner.displayOrder - 50`, whose entire job is to swallow one
	outside tap. `mountPopupCatcher` declared that Button with NO `surface` and NO
	decoration hint — and `chrome_slots.classify` maps every bare `Button` to the
	`control` slot, so an image-driven package materialized its control plate
	across the whole viewport. Beneath the base screen it is invisible; in the band
	the base screen does not cover (the showcase's chrome inset, where the demo
	picker and Settings live) it is a brown plate over the chrome.

	THIS IS THE SCRIM CATCHER'S ALREADY-LEARNED LESSON, UNAPPLIED TO ITS SIBLING.
	`mountScrim` carries both halves of the fix and both of its comments explain
	exactly this failure ("a Button with no surface still classifies as `control`,
	so the invisible catcher wore the installed package's SOLID control colour
	across the whole viewport"; "every image-driven package painted its button
	plate over the whole screen"). `mountPopupCatcher` — written later, for the
	same "invisible full-viewport tap swallower" job — inherited neither.

	SO THE CHECK IS ON THE MECHANISM, NOT ON THE ROW. Two facts about the ONE
	catcher the presenter mounts, asserted from both of its live owners: the
	row-actions tray the director actually swiped, and PopupButton, the seam's
	original consumer, which has the identical defect for the identical reason.

	`chrome_slots.classify` is the real oracle — the same call
	`screen_chrome.luau`'s `chromeSlotOf` makes on the live adapter, fed the same
	two inputs (`handle.declaredSurface`, `handle.decorationHint.slot`). A nil
	answer is "no package will ever draw here"; `"control"` is the defect.

	MEASURED ON THE REAL ADAPTER, same session, same theme, both shapes — the
	shipped popup catcher against the scrim catcher, which already carries the
	declarations this one was missing:

	  TextButton '/__popupcatcher__/catcher'  413x735  bgT=0.00
	    ImageLabel 'LuauUIChrome'             413x735  bgT=0.00   <- the plate
	  TextButton '/__scrim__/catcher'         413x735  bgT=1.00   <- and nothing else

	Full write-up: docs/lessons/an-invisible-surface-declares-its-invisibility.md ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src") :: any
local row_actions = require("../src/controls/row_actions")
local popup_button = require("../src/controls/popup_button")
local fake_target = require("./lib/fake_target")
local chrome_slots = require("../src/tokens/chrome_slots")

local FRAME = 1 / 60

-- One string carrying BOTH halves of "invisible", so a failure names the defect
-- rather than reporting `control ~= nil` with no context.
local function catcherPaint(adapter: any, path: string): string
	local node = adapter.node(path)
	if node == nil then
		return "no catcher mounted"
	end
	local hint = chrome_slots.readHint(node)
	local slot = chrome_slots.classify({
		class = node.class,
		surface = node.props.surface,
		hint = if hint ~= nil then hint.slot else nil,
	})
	return `decorationSlot={tostring(slot)} surface={tostring(node.props.surface)}`
end

local INVISIBLE = "decorationSlot=nil surface=plain"

-- ===========================================================================
-- 1. the reported repro: a real left-to-right swipe on a row-actions row
-- ===========================================================================
describe("popup catcher paint: an open row-actions tray", function()
	--[[ Driven as the director drove it — `adapter.pointerDown/Move/Up` left to
		right across the row's own hit surface (the leading edge), released past
		half the tray so it settles OPEN, exactly like
		row_actions_input.spec.luau's own gesture cases. Nothing here is
		programmatic: the catcher appears because a real gesture left a real tray
		open, which is when the director saw the plate. ]]
	local function leadingWorld()
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local clockTime = 0
		local pres = LuauUI.newPresenter(core, env, adapter, system, {
			now = function()
				return clockTime
			end,
		})
		local ra = row_actions.build(LuauUI, core, {
			id = "Row",
			content = LuauUI.UI.Text({
				id = "Body",
				text = "Row content",
				width = { type = "fixed", px = 400 },
				height = { type = "fixed", px = 48 },
			}),
			leading = {
				{ id = "read", label = "Mark Read", onAction = function() end },
			},
		})
		local screen = LuauUI.UI.Screen({ id = "S", children = { ra.blueprint } })
		local handle = pres.present(screen)
		pres.refresh()
		local w: any =
			{ core = core, env = env, system = system, adapter = adapter, pres = pres, ra = ra, handle = handle }
		function w.tick(dt: number)
			clockTime += dt
			pres.tick(dt)
			pres.refresh()
		end
		function w.settle(frames: number?)
			for _ = 1, frames or 90 do
				w.tick(FRAME)
			end
		end
		return w
	end

	-- the settled leading tray width, learned live from an identical throwaway
	-- world (the house pattern) rather than hardcoded
	local function learnLeadingWidth(): number
		local ref = leadingWorld()
		ref.ra._open("leading")
		ref.settle()
		return ref.ra.dump().offset
	end

	it("swiping LEFT TO RIGHT to reveal the leading tray must not paint a plate over the viewport", function()
		local trayWidth = learnLeadingWidth()
		local w = leadingWorld()
		local releaseX = 100 + trayWidth * 0.75 -- well past half the tray: settles OPEN
		w.adapter.pointerDown("/S/Row/Content/Hit", 100, 20, "touch")
		w.tick(0.01)
		w.adapter.pointerMove(115, 20) -- dx = +15: past the 8px axis lock, resolves horizontal
		w.tick(1.0) -- a long, calm gap, so the release is a snap decision and not a flick
		w.adapter.pointerMove(releaseX, 20)
		w.tick(FRAME)
		w.adapter.pointerUp(releaseX, 20)
		w.settle()

		expect(w.ra._isOpen()).toBe(true) -- the gesture really did leave a tray open
		local path = w.pres.topPopupCatcherPath()
		expect(path).never().toBeNil() -- ...so the presenter really did synthesize a catcher
		expect(catcherPaint(w.adapter, path :: string)).toBe(INVISIBLE)
	end)
end)

-- ===========================================================================
-- 2. the sibling owner: PopupButton, the seam's original consumer
-- ===========================================================================
describe("popup catcher paint: an open PopupButton", function()
	it("the same catcher, reached through the other outsideDismiss owner, is equally unpainted", function()
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = LuauUI.newPresenter(core, env, adapter, system)
		local control = popup_button.build(LuauUI, core, {
			id = "Difficulty",
			options = { { id = "easy", label = "Easy" }, { id = "normal", label = "Normal" } },
			value = core:signal("normal"),
			onChange = function() end,
		})
		pres.present(LuauUI.UI.Screen({ id = "S", children = { control.blueprint } }), { sinkNavigation = true })
		pres.refresh()
		adapter.tap("/S/Difficulty/Trigger")
		pres.refresh()

		local path = pres.topPopupCatcherPath()
		expect(path).never().toBeNil()
		expect(catcherPaint(adapter, path :: string)).toBe(INVISIBLE)
	end)

	--[[ The catcher sits BENEATH its owner (`owner.displayOrder - 50`), which is
		why the plate showed up in the chrome band rather than over the whole
		screen: the base screen covers the catcher everywhere it paints, and the
		showcase's inset chrome band is exactly where it does not. Pinned here so
		the geometry half of the director's report ("over the top of the screen
		blocking the demo picker") stays explained by a measured fact rather than
		by this comment alone. ]]
	it("sits beneath its owner's DisplayOrder — which is why only the uncovered chrome band showed it", function()
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = LuauUI.newPresenter(core, env, adapter, system)
		local control = popup_button.build(LuauUI, core, {
			id = "Difficulty",
			options = { { id = "easy", label = "Easy" } },
			value = core:signal("easy"),
			onChange = function() end,
		})
		pres.present(LuauUI.UI.Screen({ id = "S", children = { control.blueprint } }), { sinkNavigation = true })
		pres.refresh()
		adapter.tap("/S/Difficulty/Trigger")
		pres.refresh()
		expect(adapter.rootDisplayOrder("__popupcatcher__")).never().toBeNil()
		expect(adapter.rootDisplayOrder("__popupcatcher__") < adapter.rootDisplayOrder("S")).toBe(true)
	end)
end)
