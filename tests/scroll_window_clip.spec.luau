--!strict
-- THE SCROLL HOST'S WINDOW IS NOT ITS FRAME — the instrument, and the
-- disagreement it makes visible (device round 2026-08-12).
--
-- WHY THIS FILE EXISTS. Three device photographs show content sliced by the right
-- screen edge on a touch device, and the headless suite could not see any of it
-- because `tests/lib/fake_target.luau` modelled no window at all: a scroll host's
-- canvas and its visible box were the same rect, so a child laid out to the box's
-- full width was, headlessly, always visible. `ENGINEERING.md`: know what your
-- instrument can and cannot see — so the instrument comes first.
--
-- THE TWO NUMBERS, and why they now agree.
--
--   * `SCROLL_BAR_THICKNESS` is the thickness of the `ScrollingFrame` INSTANCE the
--     live adapter creates (`src/client/screen_target.luau`, written at every
--     host's creation). It is 8 whatever the indicator policy is; the policy only
--     fades the bar's IMAGE.
--   * `adapter.scrollBarThickness` is the LAYOUT RESERVE the target publishes to
--     the solver. Since 2026-08-12 it is that same 8 under BOTH policies.
--
-- The engine's window is narrower than the frame by the instance thickness when
-- the scroll axis overflows — `screen_target.luau`'s own cross-axis canvas clamp
-- records the fact ("the engine shrinks its window by the BAR THICKNESS even at
-- ScrollBarInset.None"). The reserve used to be ZERO under the overlay ("auto")
-- policy — which is what a TOUCH or GAMEPAD session derives, and what any machine
-- that merely CAN accept touch derives — on the reading that "an overlay indicator
-- lays claim to no layout space" (director ruling 2026-08-09). Roblox has no
-- overlay scrollbar, so that reading was wrong: the solver filled a box 8px wider
-- than the box the player could see and the engine clipped the difference.
--
-- THE RULING WAS REVERSED 2026-08-12 (device round, bugs/IMG_3691.jpeg; measured
-- live in Studio as AbsoluteSize 703x203 against AbsoluteWindowSize 695x203, with
-- nine nodes past the invisible edge — one of them a value reading "0.35" clipped
-- to "0.3"). The reserve is published under every policy now, because 8px of real
-- content on every phone beats a cosmetic flash indicator and Roblox offers no
-- free overlay bar. DO NOT "restore" the zero reserve thinking you found a
-- regression — see docs/plans/device-bug-round-2026-08-12.md B7(a).
--
-- The cases below pin BOTH halves:
--
--   1. the window model itself (mutation-provable: window == frame when nothing
--      overflows, when the host declares `indicators = "none"`, and on the scroll
--      axis; window == frame - 8 on the cross axis when it does overflow);
--   2. THE AGREEMENT, measured: under BOTH policies a fill-width child's right
--      edge lands inside the window. This was a pin on a defect until 2026-08-12;
--      it is now the pin that keeps the defect closed.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src") :: any
local fake_target = require("./lib/fake_target")

local UI = LuauUI.UI
local BAR = fake_target.SCROLL_BAR_THICKNESS

local TOUCH = { touch = true, mouse = false, keyboard = false, gamepad = false }
local POINTER = { touch = false, mouse = true, keyboard = true, gamepad = false }

-- one scroll host, filled with `rows` fill-width children of `rowHeight`
local function world(caps: any, preferred: string, rows: number, opts: any?): any
	local options: any = opts or {}
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 360, h = 400 })
	env:set("capabilities", caps)
	env:set("preferredInput", preferred)
	local system = LuauUI.newActionSystem(core)
	-- OPT INTO THE LIVE DEFAULT. The fake publishes NO bar thickness unless a spec
	-- asks for one ("which is WHY no headless sweep ever saw this class" —
	-- scroll_bar_measure.spec), while the live adapter publishes
	-- `SCROLL_BAR_THICKNESS` under BOTH policies since the 2026-08-12 reversal. The
	-- whole question here is what the two policies do and do not change, so the
	-- configured thickness has to be the live one before the presenter applies the
	-- boot policy.
	local adapter = fake_target.new();
	(adapter :: any).scrollBarThickness = BAR
	local presenter = LuauUI.newPresenter(core, env, adapter, system)
	local children = {}
	for i = 1, rows do
		table.insert(
			children,
			UI.Box({
				id = `Row{i}`,
				surface = "control",
				width = { type = "fill", weight = 1 },
				height = { type = "fixed", px = options.rowHeight or 60 },
			})
		)
	end
	local handle = presenter.present(UI.Screen({
		id = "S",
		children = {
			UI.ScrollView({
				id = "Host",
				axis = options.axis or "y",
				indicators = options.indicators,
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				children = children,
			}),
		},
	}))
	presenter.refresh()
	return { core = core, adapter = adapter, presenter = presenter, handle = handle }
end

describe("scroll host: the fake target models the engine's window", function()
	it("✓ a host whose content fits keeps its whole frame as its window", function()
		local w = world(TOUCH, "Touch", 1)
		local frame = w.adapter.node("/S/Host").rect
		local window = w.adapter.windowRectOf("/S/Host")
		expect(window).never().toBeNil()
		expect(window.w).toBe(frame.w)
		expect(window.h).toBe(frame.h)
	end)

	it("✓ a Y host that overflows loses the bar's thickness off its WIDTH, never its height", function()
		local w = world(TOUCH, "Touch", 40)
		local frame = w.adapter.node("/S/Host").rect
		local window = w.adapter.windowRectOf("/S/Host")
		expect(window.w).toBe(frame.w - BAR)
		expect(window.h).toBe(frame.h)
	end)

	it("✓ a host that declared `indicators = 'none'` has no bar and loses nothing", function()
		local w = world(TOUCH, "Touch", 40, { indicators = "none" })
		local frame = w.adapter.node("/S/Host").rect
		local window = w.adapter.windowRectOf("/S/Host")
		expect(window.w).toBe(frame.w)
		expect(w.adapter.node("/S/Host").barInstanceThickness).toBe(0)
	end)

	it("✓ the published reserve MATCHES the instance thickness under the overlay policy", function()
		local w = world(TOUCH, "Touch", 40)
		-- a touch session still derives the overlay policy — since the 2026-08-12
		-- reversal that decides the bar's PAINT and nothing else...
		expect((w.adapter :: any).scrollIndicatorPolicy).toBe("auto")
		-- ...and the RESERVE is the instance thickness, because the engine charges
		-- the window for the bar whatever the policy paints.
		--
		-- READ THIS AS A STATEMENT ABOUT THE FAKE (red-team T1, 2026-08-13). The
		-- fixture opts the fake target into the thickness itself, so every number in
		-- this file — including the failure message below, which names
		-- `src/client/screen_target.luau` — is about `tests/lib/fake_target.luau`'s
		-- mirrored `setScrollIndicatorPolicy`. What this file proves is the LAYOUT
		-- CONSEQUENCE of the reserve; that the live adapter still publishes it is
		-- pinned from source in `tests/scroll_indicators.spec.luau`
		-- ("the LIVE ScreenTarget publishes ONE reserve"), and nowhere else.
		expect((w.adapter :: any).scrollBarThickness).toBe(BAR)
		expect(w.adapter.node("/S/Host").barInstanceThickness).toBe(BAR)
	end)
end)

-- ===== the recorded defect ================================================
describe("scroll host: every policy lays content inside the window it can see", function()
	it("✓ a touch scroller's fill-width row lands INSIDE its window (the 2026-08-12 fix)", function()
		local w = world(TOUCH, "Touch", 40)
		local window = w.adapter.windowRectOf("/S/Host")
		local host = w.adapter.node("/S/Host").rect
		local row = w.adapter.node("/S/Host/Row1").rect
		local overrun = (row.x + row.w) - (window.x + window.w)
		if overrun ~= 0 then
			error(
				`the overlay-policy overrun is {overrun}px, and it must be 0. If it is {BAR}px the reserve `
					.. `regressed to the pre-2026-08-12 ruling (src/client/screen_target.luau `
					.. `setScrollIndicatorPolicy publishing 0 for "auto" while creation writes `
					.. `ScrollBarThickness = SCROLL_BAR_THICKNESS) — that is the defect in bugs/IMG_3691.jpeg, `
					.. `not a cleanup. If it moved to some other number, the two numbers drifted apart in a `
					.. `new way and this is a fresh defect.`,
				0
			)
		end
		-- What the fix moved is the ROW's box, not the host's frame: the host still
		-- fills its whole slot, and the reserve is spent INSIDE it, so the row now
		-- ends exactly at the window's edge instead of one bar past it.
		expect(host.w).toBe(window.w + BAR)
		expect(row.x + row.w).toBe(window.w)
	end)

	it("✓ a POINTER session reserves the bar, so its rows land inside the window", function()
		local w = world(POINTER, "KeyboardAndMouse", 40)
		expect((w.adapter :: any).scrollIndicatorPolicy).toBe("always")
		local window = w.adapter.windowRectOf("/S/Host")
		local row = w.adapter.node("/S/Host/Row1").rect
		expect((row.x + row.w) <= (window.x + window.w)).toBe(true)
	end)
end)
