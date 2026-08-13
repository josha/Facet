--!strict
--[[ THE ROW-ACTIONS FLIGHT (device bug round 2026-08-12, Group C —
	docs/plans/device-bug-round-2026-08-12.md §"Group C — the flight").

	Six findings from a phone, all of them motion-quality, none of them visible to
	the 4377-case suite that shipped them. What they had in common is that every
	existing row-actions check asks about the SETTLED state — "is it open", "did it
	fire", "what is the offset once 90 frames have gone by" — and every one of these
	six lives strictly BETWEEN two settled states. So this file only ever asserts
	over a RECORDED SEQUENCE of frames: `flight()` below steps the presenter one
	frame at a time and keeps the whole per-frame trace, and every check is a
	statement about that trace.

	The instrument each finding needed, named, because the next agent will want to
	know what to reach for:

	  C9a/C8b  the painted band width and the row's own travel, SAMPLED PER FRAME.
	           A settled assertion cannot see a plate that is full-size before the
	           row has moved, because by the time it settles the two agree.
	  C9b      the frame the tray UNMOUNTS versus the frame the row VISUALLY
	           ARRIVES. Two different events that a settle-only test collapses into
	           one.
	  C9c/C9d  `controller.rectOf` on the row's own content plus
	           `controller.diagnostics()` — the solver already reports the overlap
	           this causes, and nobody was reading it
	           (docs/lessons/the-solver-already-told-you.md).
	  C8a      the commit's own trace: what is still painted after the row has left,
	           and what is painted on the frames after `onAction` fires.

	Four-input: the pointer cases here drive the REAL adapter capture against the
	composite's own Hit grip (never `_pointerHandlers` directly), which is the same
	path touch, mouse and pen all take — `onPointerDown` has no branch on the source
	past the capture (row_actions.luau's own "Mouse and touch share this
	identically"). The keyboard/gamepad entries reach the same `doCommitAction`
	seam and are covered by tests/row_actions_input.spec.luau; the checks here are
	about the FLIGHT that seam starts, which is source-independent by construction.
	The reduced-motion case at the end is the deliberate branch: no flight at all.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src") :: any
local row_actions = require("../src/controls/row_actions")
local fake_target = require("./lib/fake_target")

local ROW = "/S/Cage/Row"
local HIT = ROW .. "/Content/Hit"
local CONTENT = ROW .. "/Content"
local TRAY_TRAILING = ROW .. "/TrayTrailingWhen/then/TrayTrailing"
local TRAY_LEADING = ROW .. "/TrayLeadingWhen/then/TrayLeading"
local FRAME = 1 / 60

-- the SAME resolver the control itself uses, so the one place a check has to name
-- the band's row-facing negative space asks the theme rather than a literal that
-- silently drifts from it (the house pattern in tests/row_actions.spec.luau)
local themeSnapshot = require("../src/themes/snapshot")
local ROW_GUTTER_PX = themeSnapshot.resolveNumber(themeSnapshot.neutral(), "controls.rowActions.rowGutter") or 0

-- A REALISTIC ROW: wide enough that the commit threshold (60% of the row) and
-- the open threshold (half the tray) are nowhere near each other, and with a
-- WRAPPING preview line — the leading-reveal defect (C9c/C9d) is a re-wrap, so a
-- row whose content cannot wrap could not have shown it.
local function content()
	return LuauUI.UI.VStack({
		id = "Body",
		gap = 2,
		width = { type = "fill", weight = 1 },
		padding = { top = 10, bottom = 10, left = 14, right = 14 },
		children = {
			LuauUI.UI.Text({ id = "From", text = "Sender Name", textSize = 15 }),
			LuauUI.UI.Text({
				id = "Preview",
				text = "a preview line long enough that it wraps once the row is squeezed",
				textSize = 12,
				role = "secondary",
			}),
		},
	})
end

-- presenter harness with a scripted clock, mirroring
-- tests/row_actions_input.spec.luau's `pointerWorld` (the same `w.tick` pairing of
-- `pres.tick` with `pres.refresh`, for the same reason: `syncGeometry` only runs
-- on the refresh, and the naturals this whole file is about are derived there).
local function flight(build: (core: any) -> any, envSetup: ((any) -> ())?, cageWidth: number?)
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	if envSetup ~= nil then
		envSetup(env)
	end
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local clockTime = 0
	local pres = LuauUI.newPresenter(core, env, adapter, system, {
		now = function()
			return clockTime
		end,
	})
	local ra = build(core)
	local screen = LuauUI.UI.Screen({
		id = "S",
		-- a fixed-width cage, so the row's own width is decided FOR it exactly as a
		-- list row's is, and `deriveNaturals`' clamp branch behaves like the shipped
		-- surfaces rather than like a hug row
		children = {
			--[[ 360 UNLESS A CASE ASKS OTHERWISE (2026-08-13). The width is the
				row's TRAVEL, and a spring's settle tail scales with it — so a
				case about WHEN a commit hands off cannot be asked at 360px and
				believed at 703px, which is what a phone-width playlist row
				actually is. `cageWidth` exists for exactly that one case;
				every other case passes nothing and is byte-identical. ]]
			LuauUI.UI.VStack({
				id = "Cage",
				width = { type = "fixed", px = cageWidth or 360 },
				children = { ra.blueprint },
			}),
		},
	})
	local handle = pres.present(screen)
	pres.refresh()
	local w: any = { core = core, env = env, system = system, adapter = adapter, pres = pres, ra = ra, handle = handle }
	function w.rect(path: string)
		return handle.controller.rectOf(path)
	end
	function w.widthOf(path: string): number
		local r = handle.controller.rectOf(path)
		return if r == nil then 0 else r.w
	end
	--[[ THE BAND THE PLAYER SEES, which is NOT the tray container's rect. The tray
		HStack paints nothing at all (it is a bare stack; only the action Buttons
		carry a fill), and it keeps its own fixed extras — the row-facing gutter and
		the inter-plate gaps — at every reveal fraction, so its rect never drops
		below ~12px even with every plate at zero width. Measuring it would have
		made every check in this file untrue by a constant.

		So: the visible band is the distance from the row's own edge to the far side
		of the furthest plate that is actually PAINTING (width >= 1px). Zero when no
		plate is. That is the number "the red appeared before the row moved" is
		about. ]]
	local function bandOf(trayPath: string, edge: string, ids: { string }): number
		local row = handle.controller.rectOf(ROW)
		if row == nil then
			return 0
		end
		local extent = 0
		for _, id in ids do
			local plate = handle.controller.rectOf(`{trayPath}/Action:{id}`)
			if plate ~= nil and plate.w >= 1 then
				local reach = if edge == "trailing" then (row.x + row.w) - plate.x else (plate.x + plate.w) - row.x
				extent = math.max(extent, reach)
			end
		end
		return extent
	end
	-- THE SOLVER ALREADY TOLD YOU (docs/lessons/the-solver-already-told-you.md):
	-- every fixture in this file asserts the diagnostic list, and C9c/C9d were
	-- REPORTED there by the solver the whole time.
	function w.diagnostics()
		return handle.controller.diagnostics()
	end
	function w.overlapFindings(): { string }
		local out: { string } = {}
		for _, finding in handle.controller.diagnostics() do
			table.insert(out, `{finding.node}: {finding.issue}`)
		end
		return out
	end
	-- one frame, and one recorded sample of everything this file asks about
	function w.step(): any
		clockTime += FRAME
		pres.tick(FRAME)
		pres.refresh()
		local dump = ra.dump()
		local sample = {
			offset = dump.offset,
			openEdge = dump.openEdge,
			trailingBand = bandOf(TRAY_TRAILING, "trailing", { "delete", "flag" }),
			leadingBand = bandOf(TRAY_LEADING, "leading", { "read" }),
			-- ...and the BAND'S OWN BOX, which is a different number from the painted
			-- reach above: it also carries the inter-plate gaps and the row-facing
			-- gutter, the two fixed extras `bandWidth` counts into the row's travel.
			-- `drawn band == frac x bandWidth == |offset|` is the invariant that keeps
			-- "the tray uncovered is the tray drawn" true, and it is the only place
			-- those extras are observable at all (the container paints nothing, and
			-- both are laid out on the side of the band the row never reaches).
			trailingBox = w.widthOf(TRAY_TRAILING),
			leadingBox = w.widthOf(TRAY_LEADING),
			trailingMounted = w.rect(TRAY_TRAILING) ~= nil,
			leadingMounted = w.rect(TRAY_LEADING) ~= nil,
			contentW = w.widthOf(CONTENT),
			rowH = (w.rect(ROW) or { h = 0 }).h,
			bodyH = (w.rect(ROW .. "/Content/Body") or { h = 0 }).h,
		}
		table.insert(w.trace, sample)
		return sample
	end
	function w.run(frames: number)
		for _ = 1, frames do
			w.step()
		end
	end
	w.trace = {}
	return w
end

local function twoActionRow(core: any, fired: { string }, fullSwipe: boolean?)
	return row_actions.build(LuauUI, core, {
		id = "Row",
		width = { type = "fill", weight = 1 },
		content = content(),
		leading = {
			{
				id = "read",
				label = "Mark Read",
				onAction = function()
					table.insert(fired, "read")
				end,
			},
		},
		trailing = {
			{
				id = "delete",
				label = "Delete",
				role = "destructive",
				onAction = function()
					table.insert(fired, "delete")
				end,
			},
			{
				id = "flag",
				label = "Flag",
				onAction = function()
					table.insert(fired, "flag")
				end,
			},
		},
		fullSwipe = if fullSwipe == nil then true else fullSwipe,
	})
end

describe("RowActions flight — C9a: the tray is UNCOVERED by the row, never revealed ahead of it", function()
	--[[ C9a, verbatim: "when the buttons slide in, they appear first and then the
		row slides — it's visually distracting seeing the red appear for example and
		then the row animate above it".

		MEASURED BEFORE THE FIX (`_open("trailing")`, 800x600, flat theme):
		  frame 1: offset 0.00, band 159px   <- the whole band, painted, row not moved
		  frame 2: offset -14.41, band 26px
		  frame 3: offset -36.32, band 46px
		The band a tray paints can never exceed the travel that uncovers it: that is
		the whole geometric contract of a swipe tray, and it is what this asserts. ]]
	it("a programmatic open never paints more band than the row has travelled", function()
		local fired: { string } = {}
		local w = flight(function(core)
			return twoActionRow(core, fired)
		end)
		w.ra._open("trailing")
		w.run(30)
		local worst = 0
		local worstFrame = 0
		local worstBox = 0
		--[[ THE ANTI-VACUITY GUARD, and it is not decoration (red-team T2,
			2026-08-13). `worst` and `worstBox` both start at 0 and only ever move
			UP, so every assertion below is satisfied by a trace in which the tray
			never opened at all: mutation-proved by commenting out `_open("trailing")`
			above, which left this case green (10 passed). "Never paints more band
			than the row has travelled" is trivially true of a band that is never
			painted, and this file exists precisely because the settled state hides
			the flight — so the flight has to be proved to have HAPPENED.
			Instrumented on the real run: the band peaks at 151px and the row ends
			open on the trailing edge. The floor below is a third of that. ]]
		local maxBand = 0
		for _, s in w.trace do
			maxBand = math.max(maxBand, s.trailingBand)
		end
		if maxBand < 50 then
			error(
				`the trailing tray never painted a band worth measuring: the peak over {#w.trace} frames was `
					.. `{string.format("%.2f", maxBand)}px, and a real programmatic open peaks at 151px. Every `
					.. `other assertion in this case is an upper bound and is vacuously true of a tray that `
					.. `never opened, so this is the one that says the flight happened at all.`,
				0
			)
		end
		expect(w.trace[#w.trace].openEdge).toBe("trailing")
		for i, s in w.trace do
			local excess = s.trailingBand - math.abs(s.offset)
			if excess > worst then
				worst, worstFrame = excess, i
			end
			-- ...and the band's own BOX is the travel, extras included: every term in
			-- `bandWidth` is spent at the reveal fraction, or the band drawn stops
			-- being the band uncovered (see `trailingBox` in the trace's own comment).
			if s.trailingMounted then
				worstBox = math.max(worstBox, math.abs(s.trailingBox - math.abs(s.offset)))
			end
		end
		--[[ `worstFrame` USED TO CARRY A TAUTOLOGY (red-team T3, 2026-08-13):
			`expect(worstFrame >= 0).toBe(true)`, on a local initialised to 0 and only
			ever assigned a loop index — true for every possible trace, including the
			empty one. It is a DIAGNOSTIC, not a fact about the control, so it is
			reported here in the failure instead of pretending to be an assertion:
			"the band ran ahead on frame 1" and "on frame 27" are different bugs (the
			original defect was frame 1 — the whole band painted before the row had
			moved at all), and naming the frame is what turns a red line into a
			measurement. ]]
		if worst > 1 then
			error(
				`the trailing tray painted {string.format("%.2f", worst)}px MORE band than the row had `
					.. `travelled, worst on frame {worstFrame} of {#w.trace} (offset there: `
					.. `{string.format("%.2f", math.abs(w.trace[worstFrame].offset))}px, band: `
					.. `{string.format("%.2f", w.trace[worstFrame].trailingBand)}px). Frame 1 means the plates `
					.. `are at full size before the row has moved — finding C9a verbatim.`,
				0
			)
		end
		expect(worstBox <= 2.5).toBe(true) -- four independently rounded terms
		expect(#w.diagnostics()).toBe(0)
	end)

	--[[ ...and the same statement for a LIVE DRAG, which is the path the director
		actually filmed and the one the shipped fallback could never satisfy: a drag
		writes `offset` straight through `applySlide` and never calls `retarget`, so
		the lazily-built spring did not exist and every plate took the
		`minMax`/`buttonMinWidth` fallback — full size — for the WHOLE gesture.

		MEASURED BEFORE THE FIX: 14 drag frames, offset -27 -> -183, band a constant
		159px on every one of them. ]]
	it("a live drag never paints more band than the finger has dragged", function()
		local fired: { string } = {}
		local w = flight(function(core)
			return twoActionRow(core, fired)
		end)
		w.run(2)
		w.adapter.pointerDown(HIT, 500, 20, "touch")
		w.step()
		w.adapter.pointerMove(485, 20) -- past the 8px axis lock
		w.step()
		local samples = 0
		--[[ THE SAME HOLE AS THE CASE ABOVE (red-team T2, 2026-08-13). The per-frame
			assertion is an UPPER BOUND, and `expect(samples).toBe(12)` guards the loop
			count, not the paint: with the tray unmounted `trailingBand` is 0 on every
			frame and `0 <= |offset| + 1` holds all twelve times. So the drag has to be
			proved to have DRAGGED — the tray mounted, and a band actually painted.
			Instrumented on the real run: 13 of the 16 recorded frames have the tray
			mounted and the band peaks at 151px. ]]
		local maxBand = 0
		local mountedFrames = 0
		for i = 1, 12 do
			w.adapter.pointerMove(485 - i * 12, 20)
			local s = w.step()
			samples += 1
			maxBand = math.max(maxBand, s.trailingBand)
			if s.trailingMounted then
				mountedFrames += 1
			end
			expect(s.trailingBand <= math.abs(s.offset) + 1).toBe(true)
		end
		w.adapter.pointerUp(485 - 12 * 12, 20)
		expect(samples).toBe(12)
		if mountedFrames < 12 or maxBand < 50 then
			error(
				`the drag never painted a tray to bound: the trailing tray was mounted on {mountedFrames} of `
					.. `the 12 dragged frames and the band peaked at {string.format("%.2f", maxBand)}px (a real `
					.. `drag mounts it on all 12 and peaks at 151px). The per-frame check above is an upper `
					.. `bound and is vacuously true of a band of zero.`,
				0
			)
		end
		expect(#w.diagnostics()).toBe(0)
	end)

	--[[ C8b, first half, verbatim: "if I swipe slowly to make the buttons appear,
		the row seems to animate too far horizontally."

		SAME CAUSE, and this is the check that names it. While the fallback stood,
		the LEADING plate painted at the theme's `buttonMinWidth` FLOOR (64px) for
		the whole drag, while the distance the release settles to is derived from the
		plate's real NATURAL width ("Mark Read", 117px + the row gutter) — so the row
		flew a further 53px past the band the player had been looking at. The band a
		drag paints at distance d and the band the SAME row shows once settled at d
		have to be the same band. ]]
	it("a drag paints the same band the settled row does at the same distance", function()
		local fired: { string } = {}
		local w = flight(function(core)
			return twoActionRow(core, fired)
		end)
		w.run(2)
		-- learn the settled leading geometry from this same world (never a literal)
		w.ra._open("leading")
		w.run(120)
		local settledTarget = w.trace[#w.trace].offset
		local settledBand = w.trace[#w.trace].leadingBand
		expect(settledTarget > 0).toBe(true)
		expect(settledBand > 0).toBe(true)
		w.ra._close()
		w.run(150)
		-- ...now drag to exactly that distance and read the band the player sees
		w.adapter.pointerDown(HIT, 100, 20, "touch")
		w.step()
		w.adapter.pointerMove(115, 20)
		w.step()
		w.adapter.pointerMove(100 + settledTarget, 20)
		local dragged = w.step()
		expect(dragged.offset).toBeCloseTo(settledTarget, 1.5)
		expect(dragged.leadingBand).toBeCloseTo(settledBand, 2)
		w.adapter.pointerUp(100 + settledTarget, 20)
		expect(#w.diagnostics()).toBe(0)
	end)
end)

describe(
	"RowActions flight — C9b: the reveal ends when the row arrives, not when the spring's epsilon does",
	function()
		--[[ C9b, verbatim: "near the end of the video, after the row slides back, you
		see it stop and then pop position one or two frames later. This is not a
		sampling issue but an actual pop."

		MEASURED BEFORE THE FIX (real showcase list, 359x718): the row was within
		half a pixel of home at frame 23, and the tray unmounted at frame 58 — 35
		frames, 0.58 s later. `spring.luau`'s own header says why: `DEFAULT_EPS` is
		1e-3, and "position-domain springs (hundreds of px) settle a few frames after
		they visually arrive", so a reveal gated on `offset == 0` EXACTLY holds a
		visible sliver of band on screen long after the motion is over and then
		drops it in one frame. ]]
		it("the tray unmounts within a frame of the row arriving, not 35 frames later", function()
			local fired: { string } = {}
			local w = flight(function(core)
				return twoActionRow(core, fired)
			end)
			w.ra._open("trailing")
			w.run(120)
			local openedAt = #w.trace
			w.ra._close()
			w.run(150)
			local arrived: number? = nil
			local unmounted: number? = nil
			for i = openedAt + 1, #w.trace do
				local s = w.trace[i]
				if arrived == nil and math.abs(s.offset) < 0.5 then
					arrived = i
				end
				if unmounted == nil and not s.trailingMounted then
					unmounted = i
				end
			end
			expect(arrived ~= nil).toBe(true)
			expect(unmounted ~= nil).toBe(true)
			expect((unmounted :: number) - (arrived :: number) <= 1).toBe(true)
			expect(#w.diagnostics()).toBe(0)
		end)
	end
)

describe("RowActions flight — C9c/C9d: a leading reveal TRANSLATES the row, it does not squeeze it", function()
	--[[ C9c, verbatim: "the Mark Read button is very tall vertically and causes odd
		row resizing". C9d: "when the row animates back, it overlaps the mark read
		button and causes that to collapse into something on a different row vs
		animating smoothly away, and then the other rows pop".

		NEITHER IS ABOUT THE BUTTON. `Content` is `width = fill`, `anchor =
		"topLeft"`, and its `offsetX` is the slide — and `solver.luau`'s `offsetFill`
		SHRINKS a fill anchor child by a POSITIVE offset (it only leaves the width
		alone when the child is anchored to the edge it is being pushed past). A
		trailing swipe is negative and was always fine; a LEADING swipe took the tray
		width straight out of the row's content box, so the row's text re-wrapped,
		its content grew taller than the row, and it painted over the row below.

		MEASURED BEFORE THE FIX (real showcase list row, 359x718): `Content` 319 ->
		194px, `Content/Row` 88 -> 117px, and the solver reported
		"overflows its zstack by 0x29px" for the whole time the tray was open. On the
		way back the content re-wrapped in two discrete 14px steps mid-flight. ]]
	it("a leading reveal leaves the row's content box exactly as wide as it was", function()
		local fired: { string } = {}
		local w = flight(function(core)
			return twoActionRow(core, fired)
		end)
		w.run(3)
		local restWidth = w.trace[#w.trace].contentW
		local restBody = w.trace[#w.trace].bodyH
		expect(restWidth > 0).toBe(true)
		w.ra._open("leading")
		w.run(120)
		local narrowest = math.huge
		local tallest = 0
		for i = 4, #w.trace do
			narrowest = math.min(narrowest, w.trace[i].contentW)
			tallest = math.max(tallest, w.trace[i].bodyH)
		end
		expect(narrowest).toBeCloseTo(restWidth, 1)
		expect(tallest).toBeCloseTo(restBody, 1)
		-- ...and the solver agrees: no overlap finding anywhere in the row
		expect(#w.diagnostics()).toBe(0)
	end)

	it("a trailing reveal is unchanged (the edge that never had the defect)", function()
		local fired: { string } = {}
		local w = flight(function(core)
			return twoActionRow(core, fired)
		end)
		w.run(3)
		local restWidth = w.trace[#w.trace].contentW
		w.ra._open("trailing")
		w.run(120)
		for i = 4, #w.trace do
			expect(w.trace[i].contentW).toBeCloseTo(restWidth, 1)
		end
		expect(#w.diagnostics()).toBe(0)
	end)
end)

describe("RowActions flight — C8a: a destructive commit leaves nothing standing behind it", function()
	--[[ C8a, verbatim: "when I swipe to delete, the row goes fully away but the
		delete/flag buttons show up and then animate away vertically? That's odd —
		the row should just go away. Then the row reappears quickly before the delete
		happens".

		TWO DEFECTS IN ONE SENTENCE, and they are separate mechanisms.

		(i) `doCommitAction` sets `openEdge` to the committing edge and leaves it
		    there for the whole slide-off AND the whole height collapse, so the band
		    stays fully painted on a row that has left. MEASURED BEFORE THE FIX: the
		    band was 159px wide and fully opaque from frame 1 to frame 115 of the
		    commit — 95 of those frames (1.58 s) with the row completely off-screen —
		    and then it was squashed vertically as the height collapsed to 0. That is
		    the "animate away vertically" the director saw.

		(ii) the chain's last step fires `onAction` and then calls `resetToClosed()`,
		     which puts the height override back to `nil` and springs the row home
		     from -400px. MEASURED: at the fire frame the row went from 0px tall back
		     to its full 48px and started travelling home (-400 -> -252 in four
		     frames) — a whole row, repainted, before the owner's data change had
		     landed. ]]
	it("nothing is painted where the row was once the commit has carried it off", function()
		local fired: { string } = {}
		local w = flight(function(core)
			return twoActionRow(core, fired)
		end)
		w.run(3)
		local rowWidth = w.rect(ROW).w
		w.ra._commitFirst("trailing")
		w.run(200)
		local goneFrom: number? = nil
		for i, s in w.trace do
			if goneFrom == nil and math.abs(s.offset) >= rowWidth * 0.95 then
				goneFrom = i
			end
			if goneFrom ~= nil and i >= goneFrom then
				expect(s.trailingBand).toBeLessThanOrEqual(1)
			end
		end
		expect(goneFrom ~= nil).toBe(true)
		expect(#fired).toBe(1)
		expect(fired[1]).toBe("delete")
		expect(#w.diagnostics()).toBe(0)
	end)

	it("the row is never repainted at full height on its way home after the action fires", function()
		local fired: { string } = {}
		local w = flight(function(core)
			return twoActionRow(core, fired)
		end)
		w.run(3)
		local restHeight = w.rect(ROW).h
		expect(restHeight > 0).toBe(true)
		w.ra._commitFirst("trailing")
		local fireFrame: number? = nil
		for i = 1, 200 do
			local before = #fired
			local s = w.step()
			if fireFrame == nil and #fired > before then
				fireFrame = i
			end
			if fireFrame ~= nil then
				-- once the action has fired the row is GONE: either it is still
				-- collapsed to nothing, or it is already home. A full-height row
				-- standing at a nonzero offset is the frame the director filmed.
				local visible = s.rowH > 1
				local displaced = math.abs(s.offset) > 1
				expect(visible and displaced).toBe(false)
			end
		end
		expect(fireFrame ~= nil).toBe(true)
		expect(#fired).toBe(1)
		-- ...and the row is genuinely reusable afterwards (the "phantom row" the
		-- redteam's item-5 fix exists to prevent — a row whose owner did NOT remove
		-- it must come back to a normal, openable, full-height row)
		expect(w.ra._isOpen()).toBe(false)
		expect(w.ra.dump().offset).toBe(0)
		expect(w.rect(ROW).h).toBeCloseTo(restHeight, 1)
		expect(#w.diagnostics()).toBe(0)
	end)
end)

describe("RowActions flight — the commit's own handoff (director device round 2026-08-13)", function()
	--[[ VERBATIM: "there's an odd pause once the row goes away before the others
		animate up after i swipe and click delete."

		MEASURED on the playlist example before the fix: the slide carried the row
		off-screen over frames 1-38 (gone from view by about frame 20), then NOTHING
		in the whole tree moved for 27 frames (~0.45s), and only at frame 65 did the
		height collapse begin and the rows below start closing the gap.

		The cause was this control chaining slide-off -> collapse on
		`spring:onSettle`, the NUMERIC settle (`|x - target| <= 1e-3 AND |v| <=
		1e-3`), on the largest position-domain spring in the library. `spring.luau`'s
		own header warns about precisely that, and `chase.luau` already carries the
		answer — perceptual arrival is a RADIUS, settle is only the fallback.

		WHAT THIS CASE ASSERTS is the symptom, not the implementation: the collapse
		must begin while the slide is still visibly moving, or within a frame or two
		of it stopping. It deliberately does NOT pin the radius, the spring class or
		the frame numbers — any of those may be retuned; a dead window may not
		reappear. It also deliberately measures only up to the fire, because the
		collapse's OWN settle tail plays out on a row already at zero height, where
		being late costs nothing and is not what the director saw.
	]]
	it("the collapse begins as the slide ARRIVES, not when it numerically settles", function()
		local fired: { string } = {}
		-- 703px: the width a playlist row actually solves to on the phone the
		-- director filmed. The dead window was 27 frames THERE and only a
		-- handful at this file's default 360, because a spring's settle tail
		-- scales with its travel — measured, a mutation that restores the old
		-- serial handoff does not even redden at 360.
		local w = flight(function(core)
			return twoActionRow(core, fired)
		end, nil, 703)
		w.run(3)
		local restHeight = w.rect(ROW).h
		expect(restHeight > 1).toBe(true)
		-- ...and the row really is wide enough for the defect to be visible here.
		-- Proven necessary: a mutation restoring the old serial handoff does NOT
		-- redden this case at the file's 360px default, so a future edit that
		-- narrows the cage would quietly turn this into a check that proves
		-- nothing.
		expect(`row width for this case: {w.rect(ROW).w >= 600}`).toBe("row width for this case: true")
		w.ra._commitFirst("trailing")

		local samples: { { offset: number, rowH: number } } = {}
		for _ = 1, 400 do
			local s = w.step()
			table.insert(samples, { offset = s.offset, rowH = s.rowH })
			-- the solver, EVERY FRAME of the flight — not just once at the end.
			-- The collapse's own overflow diagnostic was invisible for a whole
			-- mission because the settled-state cases sampled it 200 frames late
			-- (docs/lessons/the-solver-already-told-you.md).
			local detail = {}
			for _, d in w.diagnostics() do
				table.insert(detail, `{d.node or "?"}: {d.issue or "?"}`)
			end
			expect(`mid-flight diagnostics: {table.concat(detail, " / ")}`).toBe("mid-flight diagnostics: ")
			if #fired > 0 then
				break
			end
		end
		expect(#fired).toBe(1)

		--[[ THE TWO QUANTITIES, AND WHY NOT THE OBVIOUS ONE ─────────────────
			The first metric tried here was "frames between the slide finishing
			and the collapse starting", and it did not bite: after the action
			fires, `finishCommit` springs the row HOME from a full row width
			away, and that homeward flight is the LAST visible slide in the
			trace. The measure was reading the wrong flight.

			So: the OUTBOUND slide only — frames on which |offset| is still
			growing — against the first frame the height moves. The claim is
			that the collapse begins while the row is still flying out, which
			is what "concurrent, not chained" means and what the eye reads as
			a single motion. Measured: frame 2 concurrent, frame 66 when
			chained on the slide's numeric settle.
		]]
		local lastOutboundSlide, firstHeightChange = 0, nil :: number?
		for i = 2, #samples do
			local prev, cur = samples[i - 1], samples[i]
			if math.abs(cur.offset) - math.abs(prev.offset) >= 1 then
				lastOutboundSlide = i
			end
			if firstHeightChange == nil and math.abs(cur.rowH - prev.rowH) >= 1 then
				firstHeightChange = i
			end
		end
		-- both halves of the animation must actually have happened, or the
		-- comparison below is between two numbers that mean nothing
		expect(`the row never flew out at all over {#samples} frames: {lastOutboundSlide > 1}`).toBe(
			`the row never flew out at all over {#samples} frames: true`
		)
		expect(`the height never collapsed at all over {#samples} frames: {firstHeightChange ~= nil}`).toBe(
			`the height never collapsed at all over {#samples} frames: true`
		)
		local began = firstHeightChange :: number
		expect(`collapse began on frame {began}, outbound slide ran to frame {lastOutboundSlide}`).toBe(
			`collapse began on frame {math.min(began, lastOutboundSlide)}, outbound slide ran to frame {lastOutboundSlide}`
		)
		local detail = {}
		for _, d in w.diagnostics() do
			table.insert(detail, `{d.node or "?"}: {d.issue or "?"}`)
		end
		expect(`diagnostics: {table.concat(detail, " / ")}`).toBe("diagnostics: ")
	end)

	-- ...and the handoff still happens EXACTLY ONCE. The radius and the settle are
	-- two subscriptions racing each other, so "fires once" stops being free the
	-- moment there are two of them.
	it("the action still fires exactly once, and the row still ends up gone", function()
		local fired: { string } = {}
		local w = flight(function(core)
			return twoActionRow(core, fired)
		end)
		w.run(3)
		w.ra._commitFirst("trailing")
		w.run(400)
		expect(#fired).toBe(1)
		expect(fired[1]).toBe("delete")
		expect(w.ra._isOpen()).toBe(false)
		expect(w.ra.dump().offset).toBe(0)
		expect(#w.diagnostics()).toBe(0)
	end)
end)

describe("RowActions flight — reduced motion", function()
	--[[ REDUCED MOTION IS A DELIBERATE BRANCH, not an accident of the fixes above.
		Under it the motion authority PLACES every value instantly (motion.luau), so
		there is no flight for any of the six findings to happen during: an open
		lands on the target on the frame it is asked for, with the band already
		exactly as wide as the travel that uncovered it, and a commit fires without a
		slide. This case exists so a future change that reintroduces a flight under
		reduced motion is caught here rather than on a device. ]]
	it("an open lands instantly, with the band fully out on the frame after the mount", function()
		local fired: { string } = {}
		local w = flight(function(core)
			return twoActionRow(core, fired)
		end, function(env)
			env:set("reducedMotion", true)
		end)
		w.run(2)
		w.ra._open("trailing")
		-- the offset is placed on the SAME frame — there is no flight at all
		local first = w.step()
		expect(math.abs(first.offset) > 1).toBe(true)
		-- ...and the band is full one frame later. The one frame is structural, not
		-- motion: a plate's natural width is measured off the MOUNTED button
		-- (`deriveNaturals` reads `controller.textAt`), so it cannot exist before the
		-- tray has mounted once. What changed is what that frame paints — nothing,
		-- now, instead of the whole band at full size ahead of the row.
		local second = w.step()
		-- band + the row-facing gutter == travel: the negative space between the row
		-- and its first plate is part of what the row has to uncover (finding A1a's
		-- `rowGutter`, counted into `bandWidth`), so it is the difference between the
		-- two — read from the theme rather than written as a literal.
		expect(second.trailingBand + ROW_GUTTER_PX).toBeCloseTo(math.abs(second.offset), 2)
		expect(second.trailingBand > 100).toBe(true)
		expect(#w.diagnostics()).toBe(0)
	end)

	it("a destructive commit under reduced motion leaves nothing standing either", function()
		local fired: { string } = {}
		local w = flight(function(core)
			return twoActionRow(core, fired)
		end, function(env)
			env:set("reducedMotion", true)
		end)
		w.run(2)
		w.ra._commitFirst("trailing")
		w.run(10)
		expect(#fired).toBe(1)
		for i = 3, #w.trace do
			expect(w.trace[i].trailingBand).toBeLessThanOrEqual(1)
		end
		expect(w.ra.dump().offset).toBe(0)
		expect(#w.diagnostics()).toBe(0)
	end)
end)
