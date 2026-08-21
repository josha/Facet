--!strict
-- Framework-layer input auto-adaptation, screen level (ADR-0013; ui_todo §0).
-- Closes the remaining FRAMEWORK-AUTOMATIC cells the audit left open on PLAIN
-- screens (no input-contribution composites):
--   * WP-1 auto navigation groups derived from LAYOUT STRUCTURE (HStack row ->
--     horizontal group; Grid -> per-row groups with 2D up/down exits; a plain
--     vertical screen keeps the byte-identical flat ring);
--   * WP-2 modal outside-tap = Cancel (a tap outside the top modal dismisses it
--     and never clicks through to a lower screen; opt-out per modal);
--   * WP-3 a modal's declared close affordance is keyboard-reachable and
--     Activate-dismissable (Escape is engine-reserved — the justified exception);
--   * WP-4 Facet.inputHint(core, env, action): a reactive hint memo that flips
--     with env preferredInput, with no remount.
-- Every interaction rides the REAL device paths (adapter.tap for pointer/touch,
-- system.deviceKey for keyboard/gamepad), never a direct callback.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local worldLib = require("./lib/world")

local Facet = require("../src") :: any
local fake_target = require("../tests/lib/fake_target")

--[[ ONE SUBSTRATE, ONE ORDER (reuse audit REUSE-88, controller ruling R12).
	`tests/lib/world.luau` owns the construction and its two invariants; the tuple
	this file hands its cases is `core, env, adapter, system, pres` — the order
	`Facet.newPresenter` itself takes, and now the only one in the suite. It used
	to be `core, env, system, adapter, pres` here and the other spelling sixteen
	files away, with the same five names on both sides, so a line copied between
	two neighbouring specs bound an action system to a variable called `adapter`
	and said nothing. ]]
local function harness()
	local w = worldLib.new({ viewport = { x = 0, y = 0, w = 800, h = 600 } })
	return w.core, w.env, w.adapter, w.system, w.pres
end

local function press(system: any, key: string)
	system.deviceKey(key, true)
	system.deviceKey(key, false)
end

-- ===========================================================================
-- WP-1: auto navigation groups derived from layout structure
-- ===========================================================================
describe("auto-screens WP-1: a Grid of Buttons gets 2D D-pad navigation, zero opts", function()
	local function gridWorld()
		local core, _, adapter, system, pres = harness()
		local cells = {}
		for i = 1, 9 do
			cells[i] = Facet.UI.Button({ id = "b" .. i, label = "b" .. i })
		end
		local screen = Facet.UI.Screen({
			id = "S",
			children = { Facet.UI.Grid({ id = "G", columns = 3, children = cells }) },
		})
		local handle = pres.present(screen) -- ZERO present opts
		pres.refresh()
		return { core = core, system = system, adapter = adapter, pres = pres, handle = handle }
	end

	local function cell(i: number): string
		return `/S/G/b{i}`
	end

	it("initial focus lands on the first grid cell", function()
		local w = gridWorld()
		expect(w.pres.focus.focused:get()).toBe(cell(1))
	end)

	it("Left/Right move within a row (DPad); Up/Down cross rows keeping the column", function()
		local w = gridWorld()
		-- across row 1: b1 -> b2 -> b3
		press(w.system, "DPadRight")
		expect(w.pres.focus.focused:get()).toBe(cell(2))
		press(w.system, "DPadRight")
		expect(w.pres.focus.focused:get()).toBe(cell(3))
		-- down keeps column 3: b3 -> b6 -> b9
		press(w.system, "DPadDown")
		expect(w.pres.focus.focused:get()).toBe(cell(6))
		press(w.system, "DPadDown")
		expect(w.pres.focus.focused:get()).toBe(cell(9))
		-- back up the column, then left, then up: b9 -> b6 -> b5 -> b2
		press(w.system, "DPadUp")
		expect(w.pres.focus.focused:get()).toBe(cell(6))
		press(w.system, "DPadLeft")
		expect(w.pres.focus.focused:get()).toBe(cell(5))
		press(w.system, "DPadUp")
		expect(w.pres.focus.focused:get()).toBe(cell(2))
	end)

	it("Left at the start of a row is contained (grid 2D nav, no cross-row wrap)", function()
		local w = gridWorld()
		expect(w.pres.focus.focused:get()).toBe(cell(1))
		press(w.system, "DPadLeft") -- b1 is the first column: contained, stays put
		expect(w.pres.focus.focused:get()).toBe(cell(1))
	end)
end)

-- ===========================================================================
-- A GRID IS NOT A CLOSED BOX (found live 2026-08-06, tutorial example 06).
--
-- The per-row groups link to EACH OTHER, and `containment = true` stops the
-- fall-through that lets stacked HStacks leak into their neighbours. The first
-- row therefore had no `up` and the last row no `down`, so anything laid out
-- after a Grid was unreachable by D-pad or arrow key: measured on the tile game,
-- fourteen Downs from the bottom board row and focus never moved. That is the
-- standing "every control on every input" principle failing in the one container
-- built for boards.
-- ===========================================================================
describe("auto-screens WP-1: a Grid is linked into the page around it", function()
	local function pageWorld()
		local core, _, adapter, system, pres = harness()
		local cells = {}
		for i = 1, 9 do
			cells[i] = Facet.UI.Button({ id = "b" .. i, label = "b" .. i })
		end
		local screen = Facet.UI.Screen({
			id = "S",
			children = {
				Facet.UI.Button({ id = "Before", label = "Before" }),
				Facet.UI.Grid({ id = "G", columns = 3, children = cells }),
				Facet.UI.Button({ id = "After", label = "After" }),
			},
		})
		local handle = pres.present(screen)
		pres.refresh()
		return { core = core, system = system, adapter = adapter, pres = pres, handle = handle }
	end

	it("Down from the LAST row leaves the grid and reaches what follows it", function()
		local w = pageWorld()
		expect(w.pres.focus.focused:get()).toBe("/S/Before")
		press(w.system, "DPadDown") -- into the grid
		expect(w.pres.focus.focused:get()).toBe("/S/G/b1")
		press(w.system, "DPadDown")
		expect(w.pres.focus.focused:get()).toBe("/S/G/b4")
		press(w.system, "DPadDown")
		expect(w.pres.focus.focused:get()).toBe("/S/G/b7")
		press(w.system, "DPadDown") -- OUT of the grid: this used to stay on b7 forever
		expect(w.pres.focus.focused:get()).toBe("/S/After")
	end)

	it("Up from the FIRST row leaves the grid the other way", function()
		local w = pageWorld()
		press(w.system, "DPadDown")
		expect(w.pres.focus.focused:get()).toBe("/S/G/b1")
		press(w.system, "DPadUp")
		expect(w.pres.focus.focused:get()).toBe("/S/Before")
	end)

	it("the inner rows still navigate as a grid, and left/right are still contained", function()
		-- the fix links only the BOUNDARY rows; nothing about 2D nav inside changed
		local w = pageWorld()
		press(w.system, "DPadDown")
		press(w.system, "DPadRight")
		expect(w.pres.focus.focused:get()).toBe("/S/G/b2")
		press(w.system, "DPadDown")
		expect(w.pres.focus.focused:get()).toBe("/S/G/b5") -- column preserved
		press(w.system, "DPadLeft")
		expect(w.pres.focus.focused:get()).toBe("/S/G/b4")
		press(w.system, "DPadLeft") -- first column: contained, no wrap to b6
		expect(w.pres.focus.focused:get()).toBe("/S/G/b4")
	end)

	it("two adjacent grids hand off to each other at the seam", function()
		local core, _, adapter, system, pres = harness()
		local function grid(id: string, prefix: string)
			local cells = {}
			for i = 1, 4 do
				cells[i] = Facet.UI.Button({ id = prefix .. i, label = prefix .. i })
			end
			return Facet.UI.Grid({ id = id, columns = 2, children = cells })
		end
		local screen = Facet.UI.Screen({ id = "S", children = { grid("G1", "a"), grid("G2", "c") } })
		pres.present(screen)
		pres.refresh()
		expect(pres.focus.focused:get()).toBe("/S/G1/a1")
		press(system, "DPadDown")
		expect(pres.focus.focused:get()).toBe("/S/G1/a3")
		press(system, "DPadDown") -- across the seam into the SECOND grid
		expect(pres.focus.focused:get()).toBe("/S/G2/c1")
		press(system, "DPadUp")
		expect(pres.focus.focused:get()).toBe("/S/G1/a3")
		local _ = { core, adapter }
	end)

	it("a grid alone on a screen is unchanged: its boundary rows stay contained", function()
		-- no neighbours means no exits to invent, so the original behaviour holds
		local core, _, adapter, system, pres = harness()
		local cells = {}
		for i = 1, 9 do
			cells[i] = Facet.UI.Button({ id = "b" .. i, label = "b" .. i })
		end
		pres.present(Facet.UI.Screen({
			id = "S",
			children = { Facet.UI.Grid({ id = "G", columns = 3, children = cells }) },
		}))
		pres.refresh()
		expect(pres.focus.focused:get()).toBe("/S/G/b1")
		press(system, "DPadUp")
		expect(pres.focus.focused:get()).toBe("/S/G/b1")
		for _ = 1, 5 do
			press(system, "DPadDown")
		end
		expect(pres.focus.focused:get()).toBe("/S/G/b7")
		local _ = { core, adapter }
	end)
end)

describe("auto-screens WP-1: an HStack row navigates horizontally, zero opts", function()
	local function rowWorld()
		local core, _, adapter, system, pres = harness()
		local screen = Facet.UI.Screen({
			id = "S",
			children = {
				Facet.UI.HStack({
					id = "Row",
					children = {
						Facet.UI.Button({ id = "a", label = "a" }),
						Facet.UI.Button({ id = "b", label = "b" }),
						Facet.UI.Button({ id = "c", label = "c" }),
					},
				}),
			},
		})
		local handle = pres.present(screen) -- ZERO present opts
		pres.refresh()
		return { system = system, pres = pres, handle = handle }
	end

	it("Right/Left (keyboard) walk the row; the row is the horizontal axis", function()
		local w = rowWorld()
		expect(w.pres.focus.focused:get()).toBe("/S/Row/a")
		press(w.system, "Right")
		expect(w.pres.focus.focused:get()).toBe("/S/Row/b")
		press(w.system, "Right")
		expect(w.pres.focus.focused:get()).toBe("/S/Row/c")
		press(w.system, "Left")
		expect(w.pres.focus.focused:get()).toBe("/S/Row/b")
	end)

	it("DPadLeft/DPadRight drive the same horizontal row (gamepad)", function()
		local w = rowWorld()
		press(w.system, "DPadRight")
		expect(w.pres.focus.focused:get()).toBe("/S/Row/b")
	end)
end)

describe("auto-screens WP-1: a plain vertical screen keeps the byte-identical flat ring", function()
	it("Down advances in document order and WRAPS at the end (unchanged flat behavior)", function()
		local core, _, _, system, pres = harness()
		local screen = Facet.UI.Screen({
			id = "S",
			children = {
				Facet.UI.Button({ id = "a", label = "a" }),
				Facet.UI.Button({ id = "b", label = "b" }),
				Facet.UI.Button({ id = "c", label = "c" }),
			},
		})
		pres.present(screen) -- ZERO present opts
		pres.refresh()
		expect(pres.focus.focused:get()).toBe("/S/a")
		press(system, "Down")
		expect(pres.focus.focused:get()).toBe("/S/b")
		press(system, "Down")
		expect(pres.focus.focused:get()).toBe("/S/c")
		press(system, "Down")
		expect(pres.focus.focused:get()).toBe("/S/a") -- WRAP: flat ring, not grouped
		local _ = core
	end)
end)

describe("auto-screens WP-1: refresh re-derives auto layout groups after a structural change", function()
	it("a grid row added after present becomes reachable through the derived groups", function()
		local core, _, _, system, pres = harness()
		local items = core:signal({ { k = "a" }, { k = "b" }, { k = "c" }, { k = "d" } })
		local screen = Facet.UI.Screen({
			id = "S",
			children = {
				Facet.UI.Grid({
					id = "G",
					columns = 2,
					children = {
						Facet.UI.ForEach({
							id = "Cells",
							items = items,
							key = function(x: any)
								return x.k
							end,
							row = function(x: any)
								return Facet.UI.Button({ id = "cell", label = x.k })
							end,
						}),
					},
				}),
			},
		})
		pres.present(screen) -- ZERO present opts
		pres.refresh()
		expect(pres.focus.focused:get()).toBe("/S/G/Cells/[a]/cell")
		-- add a third row (e, f)
		items:set({ { k = "a" }, { k = "b" }, { k = "c" }, { k = "d" }, { k = "e" }, { k = "f" } })
		pres.refresh() -- groups re-derived here
		-- column 1 downward: a -> c -> e (the new bottom row)
		press(system, "DPadDown")
		expect(pres.focus.focused:get()).toBe("/S/G/Cells/[c]/cell")
		press(system, "DPadDown")
		expect(pres.focus.focused:get()).toBe("/S/G/Cells/[e]/cell")
		items:dispose()
	end)
end)

-- ===========================================================================
-- WP-2: modal outside-tap = Cancel
-- ===========================================================================
describe("auto-screens WP-2: an outside tap dismisses the top modal, never clicks through", function()
	local function stackWorld()
		local core, _, adapter, system, pres = harness()
		local baseHits: { string } = {}
		local base = Facet.UI.Screen({
			id = "Base",
			children = {
				Facet.UI.Button({
					id = "B",
					label = "B",
					onActivate = function(path: string)
						table.insert(baseHits, path)
					end,
				}),
			},
		})
		pres.present(base)
		local m1 = Facet.UI.Screen({ id = "M1", children = { Facet.UI.Button({ id = "X", label = "X" }) } })
		local hm1 = pres.presentModal(m1)
		local topHits: { string } = {}
		local m2 = Facet.UI.Screen({
			id = "M2",
			children = {
				Facet.UI.Button({
					id = "Y",
					label = "Y",
					onActivate = function(path: string)
						table.insert(topHits, path)
					end,
				}),
			},
		})
		local hm2 = pres.presentModal(m2)
		return {
			core = core,
			system = system,
			adapter = adapter,
			pres = pres,
			baseHits = baseHits,
			topHits = topHits,
			hm1 = hm1,
			hm2 = hm2,
		}
	end

	it("a stack of two modals pops exactly one per outside tap, base is never activated", function()
		local w = stackWorld()
		expect(w.pres.depth()).toBe(3) -- base + M1 + M2
		-- tap the base button (outside the top modal M2): dismiss M2 only
		w.adapter.tap("/Base/B")
		expect(w.pres.depth()).toBe(2)
		expect(#w.baseHits).toBe(0) -- NO clickthrough to the base
		-- tap again (now outside M1): dismiss M1
		w.adapter.tap("/Base/B")
		expect(w.pres.depth()).toBe(1)
		expect(#w.baseHits).toBe(0)
	end)

	it("a tap INSIDE the top modal routes normally (dispatches, does not dismiss)", function()
		local w = stackWorld()
		w.adapter.tap("/M2/Y")
		expect(w.pres.depth()).toBe(3) -- still open
		expect(#w.topHits).toBe(1)
		expect(w.topHits[1]).toBe("/M2/Y")
	end)

	it("outsideTapCancel=false swallows the outside tap (barrier; no dismiss, no clickthrough)", function()
		-- BEHAVIOR CHANGE (docs/research/2026-07-21-modal-dismissal-spec.md §3.4):
		-- a decision modal that declines outside-dismiss is still a BARRIER — the
		-- synthesized scrim catches and EATS the tap. The pre-spec behavior let an
		-- outsideTapCancel=false outside tap fall through to the lower surface; the
		-- spec closes that (other views disabled, plus a scrim).
		local core, _, adapter, _, pres = harness()
		local baseHits: { string } = {}
		local base = Facet.UI.Screen({
			id = "Base",
			children = {
				Facet.UI.Button({
					id = "B",
					label = "B",
					onActivate = function(path: string)
						table.insert(baseHits, path)
					end,
				}),
			},
		})
		pres.present(base)
		local modal = Facet.UI.Screen({ id = "M", children = { Facet.UI.Button({ id = "X", label = "X" }) } })
		pres.presentModal(modal, { outsideTapCancel = false })
		expect(pres.depth()).toBe(2)
		adapter.tap("/Base/B") -- outside the modal: the barrier swallows it
		expect(pres.depth()).toBe(2) -- modal NOT dismissed
		expect(#baseHits).toBe(0) -- NO clickthrough (spec §3.4 change)
		local _ = core
	end)

	it("with NO modal, base taps route normally (unchanged)", function()
		local core, _, adapter, _, pres = harness()
		local baseHits: { string } = {}
		local base = Facet.UI.Screen({
			id = "Base",
			children = {
				Facet.UI.Button({
					id = "B",
					label = "B",
					onActivate = function(path: string)
						table.insert(baseHits, path)
					end,
				}),
			},
		})
		pres.present(base)
		adapter.tap("/Base/B")
		expect(#baseHits).toBe(1)
		local _ = core
	end)
end)

-- ===========================================================================
-- WP-3: modal keyboard Cancel = a keyboard-reachable, Activate-dismissable
-- close affordance (Escape is engine-reserved; ADR-0013 justified exception).
-- ===========================================================================
describe("auto-screens WP-3: a modal's close button is keyboard-reachable and Activate-dismisses", function()
	it("Navigate reaches the close Button; Return activates it and dismisses the modal end-to-end", function()
		local core, _, _, system, pres = harness()
		pres.present(Facet.UI.Screen({
			id = "Base",
			children = { Facet.UI.Button({ id = "Open", label = "Open" }) },
		}))
		local modal
		modal = pres.presentModal(Facet.UI.Screen({
			id = "Sheet",
			children = {
				Facet.UI.Text({ id = "Msg", text = "Delete this?" }),
				Facet.UI.Button({ id = "Confirm", label = "Delete" }),
				Facet.UI.Button({
					id = "Close",
					label = "Cancel",
					onActivate = function()
						pres.dismiss(modal)
					end,
				}),
			},
		}))
		expect(pres.depth()).toBe(2)
		-- the ring reaches every focusable in the modal: Confirm -> Close
		expect(pres.focus.focused:get()).toBe("/Sheet/Confirm")
		press(system, "Down")
		expect(pres.focus.focused:get()).toBe("/Sheet/Close")
		-- keyboard Return activates the focused close affordance -> dismiss
		press(system, "Return")
		expect(pres.depth()).toBe(1)
		expect(pres.focus.focused:get()).toBe("/Base/Open") -- focus restored
		local _ = core
	end)
end)

-- ===========================================================================
-- WP-4: Facet.inputHint(core, env, action) reactive hint memo
-- ===========================================================================
describe("auto-screens WP-4: inputHint flips with preferredInput, no remount", function()
	it("the hint text prop follows env preferredInput via preferredBinding; zero factory reruns", function()
		local core, env, adapter, system, pres = harness()
		local ctx = system.createContext({ name = "Nav" })
		local activate = ctx.createAction("Activate", "Bool")
		activate.bind({ keyCode = "Return", displayName = "Enter" })
		activate.bind({ uiButton = "ActivateButton", displayName = "Tap" })

		local hint = Facet.inputHint(core, env, activate)
		local screen = Facet.UI.Screen({
			id = "S",
			children = {
				Facet.UI.Text({ id = "Hint", text = hint, textSize = 14 }),
				Facet.UI.Button({ id = "Go", label = "Go" }),
			},
		})
		local handle = pres.present(screen)
		pres.refresh()
		local runsBefore = handle.root.counters().factoryRuns
		local mountedBefore = handle.root.counters().mounted

		expect(adapter.node("/S/Hint").props.text).toBe("Enter") -- KeyboardAndMouse default
		env:set("preferredInput", "Touch")
		pres.refresh()
		expect(adapter.node("/S/Hint").props.text).toBe("Tap")
		expect(handle.root.counters().factoryRuns).toBe(runsBefore) -- no rerun
		expect(handle.root.counters().mounted).toBe(mountedBefore) -- no remount

		hint:dispose()
	end)

	it('style="phrase" answers the whole affordance, so a consumer never branches on input class', function()
		-- director 2026-07-29: "if we built the framework right, I'm not sure there
		-- would be any uses of preferred input outside it". A key label alone could
		-- not remove the consumer's branch, because touch differs by VERB, not by
		-- key — you tap, you do not press Enter.
		local core, env, _, system, _ = harness()
		local ctx = system.createContext({ name = "Nav3" })
		local activate = ctx.createAction("Activate", "Bool")
		activate.bind({ keyCode = "Return", displayName = "Enter" })
		activate.bind({ uiButton = "ActivateButton", displayName = "Tap" })
		local phrase = Facet.inputHint(core, env, activate, { style = "phrase" })
		expect(phrase:get()).toBe("Press Enter")
		env:set("preferredInput", "Gamepad")
		env:set("capabilities", { keyboard = false, mouse = false, touch = false, gamepad = true })
		expect(phrase:get()).toBe("Press Enter") -- gamepad takes the keyCode binding
		env:set("preferredInput", "Touch")
		expect(phrase:get()).toBe("Tap")
		-- ...and a TOUCH device that has not been touched yet is still "Tap": the
		-- resolved class comes from capability, not from the last input used
		env:set("preferredInput", "KeyboardAndMouse")
		env:set("capabilities", { keyboard = false, mouse = false, touch = true, gamepad = false })
		expect(phrase:get()).toBe("Tap")
		phrase:dispose()
	end)

	it("displayName-less bindings fall back to the key/button name, and nil is tolerated", function()
		local core, env, _, system, _ = harness()
		local ctx = system.createContext({ name = "Nav2" })
		local adjust = ctx.createAction("Adjust", "Bool")
		adjust.bind({ keyCode = "Period" }) -- no displayName
		local hint = Facet.inputHint(core, env, adjust)
		expect(hint:get()).toBe("Period")
		env:set("preferredInput", "Touch")
		expect(hint:get()).toBe("") -- no uiButton binding for Touch: empty, not an error
		hint:dispose()
	end)
end)
