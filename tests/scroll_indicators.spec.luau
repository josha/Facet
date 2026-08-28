--!strict
-- Scroll indicator policy (director ruling 2026-08-09, "auto-showing scroll
-- bars"; RESERVE HALF REVERSED 2026-08-12): pointer sessions keep the desktop
-- convention — a persistent bar; touch/gamepad sessions get hidden-at-rest
-- indicators — flash on first overflow, show while scrolling, fade when idle,
-- and reduced motion never fades. The policy is derived in the ENVIRONMENT
-- (from interactionClasses, never a device name) and pushed by the PRESENTER
-- through the declared optional target method `setScrollIndicatorPolicy`.
--
-- THE POLICY DECIDES PAINT, AND (AGAIN, AS OF 2026-08-28) HALF OF LAYOUT. The
-- 2026-08-09 ruling published a ZERO reserve under the overlay policy ("an
-- overlay indicator lays claim to no layout space"). Roblox has no overlay
-- scrollbar: the engine shrinks a ScrollingFrame's WINDOW by the instance's
-- thickness whatever the bar paints, so a zero reserve laid every touch
-- scroller's content out 8px wider than the box the player could see. Measured
-- live in Studio 2026-08-12 (AbsoluteSize 703x203 vs AbsoluteWindowSize
-- 695x203, nine nodes clipped — bugs/IMG_3691.jpeg), and the director REVERSED
-- that half: `scrollBarThickness` became the same number under both policies.
--
-- DIRECTOR RULING 2026-08-28 (task SCROLL2, fa7233a) PARTIALLY RE-REVERSED IT:
-- "if the scrollbar is set to persistently visible, we hold space for it, but
-- if it's auto visible, we let it overlap." "always" keeps the 2026-08-12
-- reserve; "auto" publishes ZERO again — but paired with
-- `screen_scroll_indicators.applyBarOverlayWiden`, which widens the scroll
-- host's own frame by the same thickness whenever its axis overflows, so the
-- zero reserve does NOT reproduce the 2026-08-09 clip (the engine's own window
-- narrowing is cancelled by the wider frame, not left unaddressed). This file
-- pins the DERIVATION/dispatch chain (below); `tests/scroll_bar_measure.spec.luau`
-- pins the geometry both policies now produce, `tests/scroll_window_clip.spec.luau`
-- pins the fake target's window math, and `tests/lib/fake_target.luau` is the
-- headless mirror all three read through.
--
-- The engine half (the actual fade tweens, the CanvasPosition-driven show) is
-- engine-only; what this spec pins headlessly is the POLICY CHAIN: derivation,
-- boot application, live flip, the reserve INVARIANT, and the reduced-motion and
-- fallback facts — through the fake target's recorded ops.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local environment = require("../src/env/environment")
local customFactory = require("../src/core/custom")
local fake_target = require("./lib/fake_target")

local function world(caps: any?, preferred: string?)
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 360, h = 691 })
	if caps ~= nil then
		env:set("capabilities", caps)
	end
	if preferred ~= nil then
		env:set("preferredInput", preferred)
	end
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new();
	(adapter :: any).scrollBarThickness = 8
	local presenter = Facet.newPresenter(core, env, adapter, system)
	return core, env, adapter, presenter
end

describe("scroll indicator policy: derivation is input facts, never a device", function()
	it("pointer sessions derive 'always'; touch and gamepad derive 'auto'", function()
		local core = customFactory.new()
		local env = environment.new(core)
		expect(env:get("scrollIndicatorPolicy"):get()).toBe("always")
		env:set("capabilities", { touch = true, mouse = false, keyboard = false, gamepad = false })
		env:set("preferredInput", "Touch")
		expect(env:get("scrollIndicatorPolicy"):get()).toBe("auto")
		env:set("capabilities", { touch = false, mouse = false, keyboard = false, gamepad = true })
		env:set("preferredInput", "Gamepad")
		expect(env:get("scrollIndicatorPolicy"):get()).toBe("auto")
	end)
end)

describe("scroll indicator policy: the presenter drives the adapter seam", function()
	it("boot applies the session's policy before anything mounts", function()
		local _, _, adapter = world({ touch = true, mouse = false, keyboard = false, gamepad = false }, "Touch")
		expect((adapter :: any).scrollIndicatorPolicy).toBe("auto")
		-- ...and the reserve MOVES with it (director ruling 2026-08-28, task
		-- SCROLL2, fa7233a, re-reversing half of 2026-08-12): "auto" publishes
		-- ZERO, from the very first mount — proving the boot ordering the test's
		-- own name claims (setScrollIndicatorPolicy runs before anything solves)
		-- actually holds, rather than leaving the construction-time default live
		-- for a frame.
		expect((adapter :: any).scrollBarThickness).toBe(0)
	end)

	it("a pointer session keeps the configured thickness (the reserve survives)", function()
		local _, _, adapter = world()
		expect((adapter :: any).scrollIndicatorPolicy).toBe("always")
		expect((adapter :: any).scrollBarThickness).toBe(8)
	end)

	it("an input-class flip mid-session re-applies the policy and MOVES the reserve", function()
		local _, env, adapter = world()
		expect((adapter :: any).scrollBarThickness).toBe(8)
		env:set("capabilities", { touch = true, mouse = false, keyboard = false, gamepad = false })
		env:set("preferredInput", "Touch")
		expect((adapter :: any).scrollIndicatorPolicy).toBe("auto")
		-- the reserve is a POLICY choice again (director ruling 2026-08-28): a
		-- flip to "auto" zeroes it, paired live with `applyBarOverlayWiden` (not
		-- modelled by this fake's `scrollBarThickness` field — see
		-- tests/scroll_window_clip.spec.luau) so the content box the player sees
		-- does not shrink even though the reserve did
		expect((adapter :: any).scrollBarThickness).toBe(0)
		-- and back: the configured thickness returns, never invented
		env:set("capabilities", { touch = false, mouse = true, keyboard = true, gamepad = false })
		env:set("preferredInput", "KeyboardAndMouse")
		expect((adapter :: any).scrollIndicatorPolicy).toBe("always")
		expect((adapter :: any).scrollBarThickness).toBe(8)
	end)

	it("reduced motion rides the same seam", function()
		local _, env, adapter = world()
		env:set("reducedMotion", true)
		expect((adapter :: any).scrollIndicatorReduced).toBe(true)
		local seen = false
		for _, op in (adapter :: any).takeOps() do
			if string.find(op, "indicatorPolicy always reduced=true", 1, true) ~= nil then
				seen = true
			end
		end
		expect(seen).toBe(true)
	end)

	it("an adapter WITHOUT the seam degrades by name: nothing is called, nothing breaks", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 360, h = 691 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new();
		(adapter :: any).scrollBarThickness = 8
		(adapter :: any).setScrollIndicatorPolicy = nil
		local presenter = Facet.newPresenter(core, env, adapter, system)
		expect(presenter ~= nil).toBe(true)
		expect((adapter :: any).scrollBarThickness).toBe(8)
		expect(core:lastError()).toBeNil()
	end)
end)

describe("scroll indicator policy: a Y-axis hug height is stable across a session flip", function()
	-- BEFORE 2026-08-12 this case was "a hug shelf regains the 8px the bar reserved
	-- when the session flips to touch" — the original zero-reserve ruling's own
	-- consequence. The 2026-08-12 reversal made the opposite the requirement for a
	-- while: nothing about the content box could move on a flip, because the
	-- engine's charge did not. Director ruling 2026-08-28 (task SCROLL2, fa7233a)
	-- restores the flip-sensitive reserve for "auto" — but only on the CROSS axis
	-- (width, for this Y scroller), so THIS case's own axis (hug HEIGHT) is still
	-- untouched by any of it: it was never testing the axis the ruling moves.
	it("a hug shelf does NOT change HEIGHT when the session flips to touch", function()
		local core, env, adapter, presenter = world()
		local UI = Facet.UI
		local handle = presenter.present(
			UI.Screen({
				id = "S",
				children = {
					UI.ScrollView({
						id = "Page",
						axis = "y",
						width = { type = "fill", weight = 1 },
						height = { type = "hug" },
						children = {
							UI.Box({
								id = "Tall",
								width = { type = "fill", weight = 1 },
								height = { type = "fixed", px = 2000 },
							}),
						},
					}),
				},
			}),
			{}
		)
		presenter.refresh()
		local before = (adapter :: any).node("/S/Page").rect.h
		env:set("capabilities", { touch = true, mouse = false, keyboard = false, gamepad = false })
		env:set("preferredInput", "Touch")
		presenter.refresh()
		local after = (adapter :: any).node("/S/Page").rect.h
		-- the page is height-hug in a bounded screen: its box is the offer both
		-- times regardless of policy. The RESERVE (director ruling 2026-08-28,
		-- task SCROLL2) now DOES depend on the policy again — "auto" zeroes it —
		-- but the reserve only ever comes off the CROSS axis (width, for a Y
		-- scroller), so this Y-axis hug HEIGHT stays identical across the flip
		-- either way: this case was never sensitive to the axis the fix touches.
		expect((adapter :: any).scrollBarThickness).toBe(0)
		expect(after).toBe(before)
		expect(core:lastError()).toBeNil()
		if type((handle :: any).dispose) == "function" then
			(handle :: any).dispose()
		end
	end)
end)

describe("a single-axis scroller's canvas never exceeds its window on the other axis", function()
	it("a wide x-carousel inside a y-page does not inflate the page's canvas width", function()
		-- director live report 2026-08-09: the feed (Y scroller) published an
		-- 880px-wide canvas in a 670px window because the nested friends
		-- carousel MEASURES at content width — so the engine drew a HORIZONTAL
		-- bar on a vertical scroller, straight through the tab dock under it.
		local core, _, adapter, presenter = world()
		local UI = Facet.UI
		presenter.present(
			UI.Screen({
				id = "S",
				children = {
					UI.ScrollView({
						id = "Page",
						axis = "y",
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
						children = {
							UI.ScrollView({
								id = "Carousel",
								axis = "x",
								width = { type = "fill", weight = 1 },
								height = { type = "fixed", px = 90 },
								children = {
									UI.Box({
										id = "WideStrip",
										width = { type = "fixed", px = 900 },
										height = { type = "fixed", px = 80 },
									}),
								},
							}),
							UI.Box({
								id = "Tall",
								width = { type = "fill", weight = 1 },
								height = { type = "fixed", px = 1200 },
							}),
						},
					}),
				},
			}),
			{}
		)
		presenter.refresh()
		local page = (adapter :: any).node("/S/Page")
		expect(page ~= nil and page.scrollRegion ~= nil).toBe(true)
		-- the page can only scroll Y: its canvas width must be its window width
		expect(page.scrollRegion.contentW <= page.rect.w + 1).toBe(true)
		-- the carousel keeps its own real X extent (that axis IS scrollable)
		local carousel = (adapter :: any).node("/S/Page/Carousel")
		expect(carousel.scrollRegion.contentW >= 900).toBe(true)
		expect(carousel.scrollRegion.contentH <= carousel.rect.h + 1).toBe(true)
		expect(core:lastError()).toBeNil()
	end)
end)

describe('indicators = "none": the carousel opt-out', function()
	it("a peeking carousel declares its indicator off; its parent page keeps one", function()
		local core, _, adapter, presenter = world()
		local UI = Facet.UI
		presenter.present(
			UI.Screen({
				id = "S",
				children = {
					UI.ScrollView({
						id = "Page",
						axis = "y",
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
						children = {
							UI.ScrollView({
								id = "Carousel",
								axis = "x",
								indicators = "none",
								width = { type = "fill", weight = 1 },
								height = { type = "fixed", px = 90 },
								children = {
									UI.Box({
										id = "WideStrip",
										width = { type = "fixed", px = 900 },
										height = { type = "fixed", px = 80 },
									}),
								},
							}),
							UI.Box({
								id = "Tall",
								width = { type = "fill", weight = 1 },
								height = { type = "fixed", px = 1200 },
							}),
						},
					}),
				},
			}),
			{}
		)
		presenter.refresh()
		expect(((adapter :: any).node("/S/Page/Carousel") :: any).indicatorsOff).toBe(true)
		expect(((adapter :: any).node("/S/Page") :: any).indicatorsOff).toBeNil()
		expect(core:lastError()).toBeNil()
	end)
end)

--[[ THE LIVE ADAPTER'S OWN HALF, READ FROM SOURCE — and it is the only thing in
	this repo that pins it (red-team T1, 2026-08-13).

	EVERY behavioural assertion above reads `tests/lib/fake_target.luau`, and the
	fixture at the top of this file writes `adapter.scrollBarThickness = 8` ITSELF
	before the presenter ever runs. So "the reserve survived the policy" is a
	statement about the FAKE's hand-mirrored `setScrollIndicatorPolicy`, never about
	`src/client/screen_target.luau` — which cannot even load headlessly (engine
	globals at load time), which is why the mirror exists at all.

	PROVED VACUOUS: reverting screen_target's write to
	`if forceScrollFallbackMode then 0 elseif scrollIndicatorPolicy == "auto" then 0
	else SCROLL_BAR_THICKNESS` — i.e. re-shipping the device bug in
	bugs/IMG_3691.jpeg verbatim — left this suite AND RascalRally's green. The pins
	below are what bite on it.

	Same instrument as `tests/reduced_motion_seam.spec.luau`'s live-adapter block
	and `tests/render_target_contract.spec.luau`: read the file as text, and pin the
	exact lines that carry the ruling. ]]
describe("the LIVE ScreenTarget publishes the reserve through TWO sanctioned writes", function()
	local fs = require("@lune/fs")
	-- THE LIVE ADAPTER IS TWO FILES. `setScrollIndicatorPolicy` and the flash/fade
	-- driver were extracted to src/client/screen_scroll_indicators for Studio's
	-- 200_000-char `Source` write cap; the constant and the construction-time
	-- publish stayed in screen_target, which hands the number down. Read them as
	-- one text so every pin below keeps the same bite it had while this was one
	-- file — the reserve is a statement about the ADAPTER, not about a filename.
	local SOURCES = { "src/client/screen_target.luau", "src/client/screen_scroll_indicators.luau" }
	local parts = {}
	for _, path in SOURCES do
		table.insert(parts, fs.readFile(path))
	end
	local source = table.concat(parts, "\n")
	-- THE PRE-POLICY DEFAULT (construction time, screen_target.luau): the value a
	-- brand-new adapter answers with before the environment's first fact has ever
	-- been pushed. It is deliberately NOT policy-aware — at construction there is no
	-- policy yet — and stays the value `forceScrollFallback` alone can zero.
	local CONSTRUCTION_WRITE = "adapter.scrollBarThickness = if forceScrollFallbackMode then 0 else SCROLL_BAR_THICKNESS"
	-- THE REAL RESERVE (director ruling 2026-08-28, screen_scroll_indicators.luau):
	-- restated on every `setScrollIndicatorPolicy` call, which the boot sequence
	-- guarantees runs before anything mounts (see "boot applies the session's
	-- policy before anything mounts" above) — so this is the value that actually
	-- reaches the solver for every real screen. "always" keeps the construction
	-- default; "auto" zeroes it (paired with `applyBarOverlayWiden`, which this file
	-- does not pin — see tests/scroll_bar_measure.spec.luau).
	-- the policy write's OWN first line — the fragment `string.gmatch`'s per-line
	-- scan below actually sees, since the `then`/`else` continuation lines carry no
	-- `adapter.scrollBarThickness` substring and never reach that scan's filter
	local POLICY_WRITE_HEAD = 'adapter.scrollBarThickness = if forceScrollFallbackMode or state.policy == "auto"'
	local POLICY_WRITE = POLICY_WRITE_HEAD .. '\n\t\t\tthen 0\n\t\t\telse SCROLL_BAR_THICKNESS'

	it("its one constant is the same 8px the fake mirrors", function()
		expect(string.find(source, "local SCROLL_BAR_THICKNESS = 8", 1, true) ~= nil).toBe(true)
		expect(fake_target.SCROLL_BAR_THICKNESS).toBe(8)
	end)

	it("TWO writes, not one: the construction default and the policy-aware seam", function()
		-- exactly one of each. A second construction-time write would be a new
		-- place for the pre-policy default to drift from the constant above; a
		-- second policy write would be a second place a future policy change has
		-- to remember to touch.
		local function occurrences(needle: string): number
			local escaped = string.gsub(needle, "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
			local _, count = string.gsub(source, escaped, "")
			return count
		end
		expect(occurrences(CONSTRUCTION_WRITE)).toBe(1)
		expect(occurrences(POLICY_WRITE)).toBe(1)
		-- and the policy write lives INSIDE `setScrollIndicatorPolicy` specifically,
		-- so a refactor that keeps the line but moves it out of the seam still fails
		local i = string.find(source, "function setScrollIndicatorPolicy(policy: string, reduced: boolean?)", 1, true)
		expect(i ~= nil).toBe(true)
		local body = string.sub(source, i :: number, (i :: number) + 900)
		expect(string.find(body, POLICY_WRITE, 1, true) ~= nil).toBe(true)
	end)

	it("NOTHING BUT those two recognised lines assigns the reserve", function()
		-- the exact shape of a THIRD write reappearing: a stray branch on the
		-- reserve's own assignment somewhere neither sanctioned site names.
		-- `scrollIndicatorPolicy` may be read freely for PAINT — the flash/show/fade
		-- driver below does exactly that — so this looks only at lines that assign
		-- the reserve field itself.
		for line in string.gmatch(source, "[^\n]+") do
			if
				string.find(line, "adapter.scrollBarThickness", 1, true) ~= nil
				and string.find(line, "=", 1, true) ~= nil
			then
				local trimmed = string.match(line, "^%s*(.-)%s*$") or line
				if trimmed ~= CONSTRUCTION_WRITE and trimmed ~= POLICY_WRITE_HEAD then
					error(
						`the live ScreenTarget (screen_target.luau / screen_scroll_indicators.luau) assigns `
							.. `the scroll reserve on a line this pin does not recognise:\n    {trimmed}\n`
							.. `The two sanctioned writes are:\n    {CONSTRUCTION_WRITE}\n    (split across lines) `
							.. `{POLICY_WRITE}\nIf this is a THIRD write site, collapse it into one of the two `
							.. `above. If it is a legitimate new seam, pin it here deliberately (director ruling `
							.. `2026-08-28, task SCROLL2, fa7233a).`,
						0
					)
				end
			end
		end
	end)
end)

return true
