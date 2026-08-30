--!strict
-- Gamepad d-pad auto-repeat (director item 4). Holding a gamepad
-- direction must repeatedly advance focus after an initial delay, matching
-- platform convention, exactly the way CoreGui's own selection navigator does
-- for native selection — a HELD `Navigate`/`NavigateH` Direction1D only ever
-- delivered ONE step before this (a value change, then back to 0 on release),
-- so nothing moved a second time until the key was released and pressed
-- again.
--
-- CENSUS + Fire(true/false) EDGES, never injected input (campaign lesson:
-- injected input is per-session flaky). Time is driven exclusively through
-- `w.tick(dt)` (an explicit dt bypasses the presenter's `now()` entirely —
-- tests/lib/world.luau's own seam), never a wall-clock sleep.
--
-- Part 1 — the low-level gamepad-source classification actions.luau stamps
-- onto an action (`lastGamepad`), which is what makes the repeat gate
-- possible without the presenter re-deriving "was this gamepad" from a live
-- platform fact.
--
-- Part 2 — the presenter-level repeat behavior: cadence, gamepad-only gating,
-- the analog-stick no-double-fire proof (item 4's own "check the stick"
-- instruction), boundary/release/dismiss cleanliness.
--
-- Part 3 — a real interaction the repeat feature exposed: a repeat that lands
-- focus on an `adjustAxis`-owning control mid-hold suspends that axis's
-- keys out from under the still-held Direction1D. Fixed at the same seam
-- (`suspendAxisKeys` zeroes the axis owner's state) rather than patched at
-- the repeat glue, because the identical stale-value hazard existed before
-- auto-repeat ever shipped (a swallowed NEXT press), just harder to notice.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local worldLib = require("./lib/world")
local customFactory = require("../src/core/custom")
local actionsLib = require("../src/input/actions")
local Facet = require("../src") :: any
local contribution = require("../src/input/contribution")

-- ===========================================================================
-- Part 1 — actions.luau: gamepad-source classification (the repeat gate's
-- own plumbing, engine-free, no presenter needed)
-- ===========================================================================
describe("actions: gamepad-source classification (director item 4 plumbing)", function()
	local function ctx()
		local core = customFactory.new()
		local system = actionsLib.newSystem(core)
		local action = system.createContext({ name = "Nav", priority = 1000 }).createAction("Navigate", "Direction1D")
		return system, action
	end

	it("DPad/Button keyCodes classify as gamepad", function()
		local system, navigate = ctx()
		navigate.bind({ keyCode = "DPadDown", direction = 1 })
		system.deviceKey("DPadDown", true)
		expect(navigate.lastGamepad).toBe(true)
	end)

	it("keyboard keyCodes (Up/Down/Left/Right) classify as NOT gamepad", function()
		local system, navigate = ctx()
		navigate.bind({ keyCode = "Down", direction = 1 })
		system.deviceKey("Down", true)
		expect(navigate.lastGamepad).toBe(false)
	end)

	it("an axis binding (Thumbstick*) is always gamepad-classed", function()
		local system, navigate = ctx()
		navigate.bindAxis({ axis = "Thumbstick1", component = "y" })
		system.deviceAxis("Thumbstick1", 0, 0.8)
		expect(navigate.lastGamepad).toBe(true)
	end)

	it("a scriptable binding (no keyCode) is never gamepad", function()
		local _, action = ctx()
		local b = action.bind({ scriptable = true, direction = 1 })
		b.fire(1)
		expect(action.lastGamepad).toBe(false)
	end)

	it("dedup: a same-value re-fire from a DIFFERENT source class never overwrites lastGamepad", function()
		local system, navigate = ctx()
		navigate.bind({ keyCode = "DPadDown", direction = 1 })
		navigate.bind({ keyCode = "Down", direction = 1 })
		system.deviceKey("DPadDown", true) -- establishes value 1 as gamepad
		expect(navigate.lastGamepad).toBe(true)
		system.deviceKey("Down", true) -- same value 1: deduped, never reaches _deliver
		expect(navigate.lastGamepad).toBe(true)
	end)
end)

-- ===========================================================================
-- Part 2 — presenter-level repeat behavior
-- ===========================================================================
local function fiveRowScreen()
	return Facet.UI.Screen({
		id = "S",
		children = {
			Facet.UI.Button({ id = "Row1", label = "Row1" }),
			Facet.UI.Button({ id = "Row2", label = "Row2" }),
			Facet.UI.Button({ id = "Row3", label = "Row3" }),
			Facet.UI.Button({ id = "Row4", label = "Row4" }),
			Facet.UI.Button({ id = "Row5", label = "Row5" }),
		},
	})
end

describe("d-pad auto-repeat: presenter cadence and gating", function()
	it("holding DPadDown steps once immediately, then repeats after 0.4s, then every 0.1s", function()
		local w = worldLib.new()
		w.present(fiveRowScreen())
		expect(w.pres.focus.focused:get()).toBe("/S/Row1")

		w.system.deviceKey("DPadDown", true) -- immediate single step (pre-existing)
		expect(w.pres.focus.focused:get()).toBe("/S/Row2")

		w.tick(0.39) -- just under the initial delay: no repeat yet
		expect(w.pres.focus.focused:get()).toBe("/S/Row2")
		w.tick(0.01) -- crosses 0.4s: first repeat
		expect(w.pres.focus.focused:get()).toBe("/S/Row3")

		w.tick(0.09) -- under the 0.1s steady interval: no repeat yet
		expect(w.pres.focus.focused:get()).toBe("/S/Row3")
		w.tick(0.01) -- crosses: second repeat
		expect(w.pres.focus.focused:get()).toBe("/S/Row4")

		w.system.deviceKey("DPadDown", false) -- release
		w.tick(1) -- long past another interval: nothing moves after release
		expect(w.pres.focus.focused:get()).toBe("/S/Row4")
	end)

	it("a slow first frame catches up: a dt spanning several intervals fires every owed step in one tick", function()
		local w = worldLib.new()
		w.present(fiveRowScreen())
		w.system.deviceKey("DPadDown", true) -- Row1 -> Row2
		w.tick(0.4 + 0.1 + 0.1) -- delay + two full intervals owed in one tick
		expect(w.pres.focus.focused:get()).toBe("/S/Row5")
	end)

	it("holding a keyboard arrow (Down) does NOT auto-repeat", function()
		local w = worldLib.new()
		w.present(fiveRowScreen())
		w.system.deviceKey("Down", true) -- immediate single step only
		expect(w.pres.focus.focused:get()).toBe("/S/Row2")
		w.tick(0.4)
		w.tick(0.1)
		w.tick(2)
		expect(w.pres.focus.focused:get()).toBe("/S/Row2")
		w.system.deviceKey("Down", false)
	end)

	it("releasing before the initial delay elapses cancels the repeat entirely", function()
		local w = worldLib.new()
		w.present(fiveRowScreen())
		w.system.deviceKey("DPadDown", true)
		w.system.deviceKey("DPadDown", false)
		expect(w.pres.focus.focused:get()).toBe("/S/Row2")
		w.tick(1)
		expect(w.pres.focus.focused:get()).toBe("/S/Row2")
	end)

	it("repeat honors the ring's OWN wrap policy exactly like a single press would", function()
		-- the flat (ungrouped) ring wraps at its ends by default — the same rule
		-- a single fresh press already gets from `graph.navigate`. Repeat must
		-- reuse that rule rather than reimplement or override it: this is the
		-- "focus boundaries/wrap rules unchanged per step" requirement, proven by
		-- driving PAST the last row and landing back at the first.
		local w = worldLib.new()
		w.present(fiveRowScreen())
		w.system.deviceKey("DPadDown", true)
		w.tick(0.4) -- Row3
		w.tick(0.1) -- Row4
		w.tick(0.1) -- Row5
		w.tick(0.1) -- past the last item: wraps to Row1, same as a single press would
		expect(w.pres.focus.focused:get()).toBe("/S/Row1")
	end)

	it("a held Thumbstick1 push repeats through the SAME glue, at the SAME cadence — no double-fire", function()
		local w = worldLib.new()
		w.present(fiveRowScreen())
		w.system.deviceAxis("Thumbstick1", 0, 0.8) -- cross+latch: one step
		expect(w.pres.focus.focused:get()).toBe("/S/Row2")
		w.tick(0.4) -- exactly one repeat, not two
		expect(w.pres.focus.focused:get()).toBe("/S/Row3")
		w.tick(0.1) -- exactly one more repeat
		expect(w.pres.focus.focused:get()).toBe("/S/Row4")
	end)

	it("dismissing the surface mid-repeat stops it (scope-owned, no leaked timer)", function()
		local w = worldLib.new()
		w.present(fiveRowScreen())
		w.system.deviceKey("DPadDown", true)
		expect(w.pres.focus.focused:get()).toBe("/S/Row2")
		expect(w.pres.depth()).toBe(1)
		w.pres.dismiss(w.handle)
		expect(w.pres.depth()).toBe(0)
		-- a leaked hook is inert on a torn-down scope by the SAME contract the
		-- drag-to-edge autoscroll stepper already relies on; this just proves
		-- ticking afterward is harmless (no error, no dangling focus move)
		w.tick(1)
		w.tick(1)
	end)
end)

-- ===========================================================================
-- Part 3 — repeat interacting with the axis-suspend Adjust seam
-- ===========================================================================
describe("d-pad auto-repeat + the axis-suspend Adjust seam (found while building item 4)", function()
	local function fakeVerticalAdjustControl(id: string)
		local root = Facet.UI.VStack({
			id = id,
			children = {
				Facet.UI.Button({ id = "Row1", label = "Row1" }),
				Facet.UI.Button({ id = "Row2", label = "Row2" }),
				Facet.UI.Button({ id = "Adj", label = "Adj" }),
			},
		})
		local adjustHits: { any } = {}
		local adjPath = "/S/" .. id .. "/Adj"
		local bundle = {
			adjustAxis = "vertical",
			adjustTargets = function(_rootNode: any): { [string]: boolean }
				return { [adjPath] = true }
			end,
			handleAdjust = function(path: string, dir: number): boolean
				table.insert(adjustHits, { path = path, dir = dir })
				return true
			end,
		}
		return { blueprint = contribution.attach(root, bundle), adjustHits = adjustHits, adjPath = adjPath }
	end

	it("a repeat that lands focus on a vertical-adjust target stops cleanly, with no stuck Direction1D", function()
		local w = worldLib.new()
		local ctl = fakeVerticalAdjustControl("Ctl")
		w.present(Facet.UI.Screen({ id = "S", children = { ctl.blueprint } }))
		expect(w.pres.focus.focused:get()).toBe("/S/Ctl/Row1")

		w.system.deviceKey("DPadDown", true) -- held; immediate step Row1 -> Row2
		expect(w.pres.focus.focused:get()).toBe("/S/Ctl/Row2")

		w.tick(0.4) -- first repeat: Row2 -> Adj, which SUSPENDS navigate's vertical keys
		expect(w.pres.focus.focused:get()).toBe(ctl.adjPath)

		-- the axis is now owned by Adjust: navigate no longer claims a held
		-- direction (the fix — without it this reads 1, stuck forever)
		expect(w.handle.actions.navigate.state:get()).toBe(0)
		-- and the DPadDown/DPadUp bindings genuinely left `navigate`
		local stillBound = false
		for _, b in w.handle.actions.navigate.bindings do
			if b.keyCode == "DPadDown" or b.keyCode == "DPadUp" then
				stillBound = true
			end
		end
		expect(stillBound).toBe(false)

		-- further ticks do NOT keep moving focus past the target (no leaked repeat)
		w.tick(1)
		w.tick(1)
		expect(w.pres.focus.focused:get()).toBe(ctl.adjPath)

		-- the physical release now routes to Adjust (which owns the keyCode), not
		-- Navigate — and does not error
		w.system.deviceKey("DPadDown", false)
	end)
end)

-- ===========================================================================
-- Part 4 — RED-TEAM review finding C1: a HELD direction's context can stop
-- owning arbitration for reasons beyond "the surface was dismissed", and the
-- repeat's own poll turns that staleness into an unbounded, invisible,
-- periodic side effect on the SHARED (presenter-wide) focus graph. Both
-- reproductions are the reviewer's own, verbatim.
-- ===========================================================================
describe("d-pad auto-repeat + RED-TEAM C1: ownership can be lost mid-hold without a dismiss", function()
	it("Variant A — resign() mid-hold stops the repeat and zeroes navigate.state, not just heldDir", function()
		local w = worldLib.new()
		w.present(fiveRowScreen(), { responder = "passive" })
		w.handle.engage()

		-- a passive, not-yet-engaged surface starts with NO focus; the first
		-- navigate event on it seeds ENTRY focus (Row1) rather than moving
		-- relative to a prior one — `engage()` alone does not
		w.system.deviceKey("DPadDown", true)
		expect(w.pres.focus.focused:get()).toBe("/S/Row1")
		w.tick(0.4) -- repeat active: Row2
		expect(w.pres.focus.focused:get()).toBe("/S/Row2")

		-- Cancel (ButtonB) WHILE DPadDown is still physically held: resign()
		w.system.deviceKey("ButtonB", true)
		w.system.deviceKey("ButtonB", false)

		-- the fix: context.setEnabled(false) now zeros Direction1D too, so this
		-- is 0 immediately — not left stuck at 1 forever (the review's own
		-- measurement of the pre-fix state)
		expect(w.handle.actions.navigate.state:get()).toBe(0)

		-- 13 is deliberately NOT a multiple of the 5-row ring (the review's own
		-- note: 20 gave a false negative by coincidence, landing back on the
		-- start row); focus must not move AT ALL after resign
		local afterResign = w.pres.focus.focused:get()
		for _ = 1, 13 do
			w.tick(0.1)
		end
		expect(w.pres.focus.focused:get()).toBe(afterResign)
	end)

	it(
		"Variant B — a modal opening mid-hold stops the BACKGROUNDED repeat instead of hijacking the modal's own ring",
		function()
			local w = worldLib.new()
			w.present(Facet.UI.Screen({
				id = "Base",
				children = {
					Facet.UI.Button({ id = "Row1", label = "Row1" }),
					Facet.UI.Button({ id = "Row2", label = "Row2" }),
					Facet.UI.Button({ id = "Row3", label = "Row3" }),
					Facet.UI.Button({ id = "Row4", label = "Row4" }),
					Facet.UI.Button({ id = "Row5", label = "Row5" }),
				},
			}))
			local baseHandle = w.handle

			w.system.deviceKey("DPadDown", true) -- Row1 -> Row2
			w.tick(0.4) -- repeat active: Base/Row3
			expect(w.pres.focus.focused:get()).toBe("/Base/Row3")

			local modalHandle = w.pres.presentModal(Facet.UI.Screen({
				id = "Modal",
				children = {
					Facet.UI.Button({ id = "Row1", label = "Row1" }),
					Facet.UI.Button({ id = "Row2", label = "Row2" }),
					Facet.UI.Button({ id = "Row3", label = "Row3" }),
					Facet.UI.Button({ id = "Row4", label = "Row4" }),
					Facet.UI.Button({ id = "Row5", label = "Row5" }),
				},
			}))
			w.pres.refresh()
			expect(w.pres.focus.focused:get()).toBe("/Modal/Row1")

			-- release the physical key: arbitration routes this to the MODAL's own
			-- (higher-priority, sinking) Navigate context — Base's context never
			-- sees it, exactly the mechanism the review measured
			w.system.deviceKey("DPadDown", false)

			-- with NO further player input, the fix must stop Base's leaked
			-- repeat instead of letting it keep driving the shared focus graph —
			-- which right now belongs to the modal
			for _ = 1, 4 do
				w.tick(0.1)
			end
			expect(w.pres.focus.focused:get()).toBe("/Modal/Row1")
			expect(baseHandle.actions.navigate.state:get()).toBe(0)

			-- and the modal's OWN navigation is untouched by any of this
			w.system.deviceKey("DPadDown", true)
			w.system.deviceKey("DPadDown", false)
			expect(w.pres.focus.focused:get()).toBe("/Modal/Row2")
			w.pres.dismiss(modalHandle)
		end
	)
end)
