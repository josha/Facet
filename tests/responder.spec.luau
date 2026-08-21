--!strict
-- First-responder (focus-engagement) model (ADR-0014; ui_todo §0/§3; director
-- 2026-07-21). A Facet surface becomes first responder over avatar/gameplay
-- input via FOCUS ENGAGEMENT (the responder-chain analogue), NOT by
-- disabling player input. The proof here builds a fake gameplay stack in the
-- headless action system and drives the REAL device path (system.deviceKey /
-- adapter.tap), asserting exactly the director's scenario:
--   (a) a PASSIVE HUD present yields avatar input untouched (Space/ButtonA/Up
--       reach gameplay; HUD focus never moves);
--   (b) a pointer tap on the HUD's focusable ENGAGES it — nav now owns Up/Down
--       and does NOT reach gameplay, Space/ButtonA are guarded, Activate works;
--   (c) resign (Cancel or outside-tap) restores gameplay delivery exactly;
--   (d) presentModal over gameplay suppresses + dismissal restores;
--   (e) gameplayGuard=false lets Space reach gameplay while engaged;
--   (f) present() default (no responder opt) is byte-identical to today —
--       nav works AND gameplay also receives (documented UI-only-place semantics);
--   (g) engage/resign churn is registry-neutral and leak-free.
-- The engaged band sits at 3000+ (research conclusion 3; mirrors CAS High),
-- strictly above the doc-sanctioned gameplay sink at 2000.

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

-- fake gameplay stack (director's exact scenario): the avatar's CharacterContext
-- at 1000 (non-sinking) with Jump<-Space+ButtonA and Move<-Up/Down, plus a game
-- PlayContext at 2000 SINK with its own action on a distinct key. Facet's
-- engaged band must sit strictly above the 2000 sink.
local function gameplay(system: any, core: any)
	local char = system.createContext({ name = "CharacterContext", priority = 1000, sink = false })
	local jump = char.createAction("Jump", "Bool")
	jump.bind({ keyCode = "Space" })
	jump.bind({ keyCode = "ButtonA" })
	local move = char.createAction("Move", "Direction1D")
	move.bind({ keyCode = "Up", direction = -1 })
	move.bind({ keyCode = "Down", direction = 1 })

	local play = system.createContext({ name = "PlayContext", priority = 2000, sink = true })
	local special = play.createAction("Special", "Bool")
	special.bind({ keyCode = "ButtonX" })

	local counters = { jump = 0, move = 0, special = 0 }
	jump.onPressed(function()
		counters.jump += 1
	end)
	core:observe(move.state, function(dir)
		if dir == 1 or dir == -1 then
			counters.move += 1
		end
	end)
	special.onPressed(function()
		counters.special += 1
	end)
	return { char = char, play = play, counters = counters }
end

-- a simple passive HUD: two buttons that record activation
local function hudScreen(acts: { [string]: number })
	return Facet.UI.Screen({
		id = "HUD",
		children = {
			Facet.UI.Button({
				id = "b1",
				label = "b1",
				onActivate = function()
					acts.b1 = (acts.b1 or 0) + 1
				end,
			}),
			Facet.UI.Button({
				id = "b2",
				label = "b2",
				onActivate = function()
					acts.b2 = (acts.b2 or 0) + 1
				end,
			}),
		},
	})
end

-- ===========================================================================
-- (a) passive HUD present: avatar input untouched
-- ===========================================================================
describe("responder (a): a passive HUD leaves avatar input untouched", function()
	it("Space/ButtonA/Up all reach gameplay and the HUD focus never moves", function()
		local core, _, _, system, pres = harness()
		local g = gameplay(system, core)
		local acts: { [string]: number } = {}
		local h = pres.present(hudScreen(acts), { responder = "passive" })
		pres.refresh()

		expect(h.responder:get()).toBe("passive")
		expect(pres.exclusiveSurfaceActive:get()).toBe(false)
		local focus0 = pres.focus.focused:get()

		press(system, "Space")
		expect(g.counters.jump).toBe(1)
		press(system, "ButtonA")
		expect(g.counters.jump).toBe(2)
		press(system, "Up")
		expect(g.counters.move).toBe(1)

		-- the HUD is passive: its navigation context is DISABLED, focus is inert
		expect(pres.focus.focused:get()).toBe(focus0)
	end)
end)

-- ===========================================================================
-- (b) tap engages: HUD becomes first responder
-- ===========================================================================
describe("responder (b): a tap on the HUD's focusable engages it (first responder)", function()
	it("engaged: Up/Down navigate the HUD and NOT gameplay; Space/ButtonA guarded; Activate works", function()
		local core, _, adapter, system, pres = harness()
		local g = gameplay(system, core)
		local acts: { [string]: number } = {}
		local h = pres.present(hudScreen(acts), { responder = "passive" })
		pres.refresh()

		-- tap inside the passive HUD -> engages (and activates the tapped control)
		adapter.tap("/HUD/b1")
		expect(h.responder:get()).toBe("engaged")
		expect(pres.exclusiveSurfaceActive:get()).toBe(true)
		expect(acts.b1).toBe(1) -- the engaging tap still activated b1
		expect(pres.focus.focused:get()).toBe("/HUD/b1")

		-- Down now navigates the HUD; gameplay Move is NOT reached (sunk)
		press(system, "Down")
		expect(pres.focus.focused:get()).toBe("/HUD/b2")
		expect(g.counters.move).toBe(0)

		-- ButtonA activates the focused HUD control; jump is guarded (never fires)
		press(system, "ButtonA")
		expect(acts.b2).toBe(1)
		expect(g.counters.jump).toBe(0)

		-- Space is guarded by the GameplayGuard no-op action; jump never fires
		press(system, "Space")
		expect(g.counters.jump).toBe(0)
	end)

	it("handle.engage() is the explicit public path to first responder", function()
		local core, _, _, system, pres = harness()
		local g = gameplay(system, core)
		local acts: { [string]: number } = {}
		local h = pres.present(hudScreen(acts), { responder = "passive" })
		pres.refresh()
		h.engage()
		expect(h.responder:get()).toBe("engaged")
		press(system, "Up")
		expect(g.counters.move).toBe(0) -- nav sunk from gameplay
		-- A PASSIVE HUD MOUNTS WITH NO FOCUS (2026-08-03 round 6), so the first
		-- Navigate ENTERS the ring at b1 rather than stepping from it. The claim
		-- this case exists for is that the HUD — not the avatar — received the
		-- press, which the `move == 0` above already pins; the second press keeps
		-- the "it really steps" half honest.
		expect(pres.focus.focused:get()).toBe("/HUD/b1")
		press(system, "Up")
		expect(pres.focus.focused:get()).toBe("/HUD/b2") -- wraps up in a two-element ring
	end)
end)

-- ===========================================================================
-- (c) resign restores gameplay delivery exactly
-- ===========================================================================
describe("responder (c): resign restores gameplay delivery exactly", function()
	it("Cancel (ButtonB) resigns an engaged-from-passive HUD; gameplay restored", function()
		local core, _, _, system, pres = harness()
		local g = gameplay(system, core)
		local acts: { [string]: number } = {}
		local h = pres.present(hudScreen(acts), { responder = "passive" })
		pres.refresh()
		h.engage()
		expect(h.responder:get()).toBe("engaged")

		press(system, "ButtonB") -- Cancel resigns (back to passive), not nothing
		expect(h.responder:get()).toBe("passive")
		expect(pres.exclusiveSurfaceActive:get()).toBe(false)

		-- gameplay delivery is restored exactly
		press(system, "Space")
		expect(g.counters.jump).toBe(1)
		press(system, "Up")
		expect(g.counters.move).toBe(1)
	end)

	it("an outside tap resigns an engaged-from-passive HUD; gameplay restored, no clickthrough", function()
		local core, _, adapter, system, pres = harness()
		local g = gameplay(system, core)
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
		local acts: { [string]: number } = {}
		local h = pres.present(hudScreen(acts), { responder = "passive" })
		pres.refresh()
		h.engage()
		expect(h.responder:get()).toBe("engaged")

		-- tap OUTSIDE the engaged HUD (on the base) resigns it and never clicks through
		adapter.tap("/Base/B")
		expect(h.responder:get()).toBe("passive")
		expect(#baseHits).toBe(0)

		press(system, "Space")
		expect(g.counters.jump).toBe(1)
	end)
end)

-- ===========================================================================
-- (d) presentModal over gameplay: same suppression + dismissal restores
-- ===========================================================================
describe("responder (d): a modal over gameplay suppresses avatar input; dismiss restores", function()
	it("Space/ButtonA/Up are suppressed while the modal is up and restored on dismiss", function()
		local core, _, _, system, pres = harness()
		local g = gameplay(system, core)
		local modal = pres.presentModal(Facet.UI.Screen({
			id = "Sheet",
			children = { Facet.UI.Button({ id = "ok", label = "ok" }) },
		}))
		pres.refresh()
		expect(pres.exclusiveSurfaceActive:get()).toBe(true)

		press(system, "Space")
		expect(g.counters.jump).toBe(0)
		press(system, "Up")
		expect(g.counters.move).toBe(0)
		press(system, "ButtonA")
		expect(g.counters.jump).toBe(0)

		pres.dismiss(modal)
		expect(pres.exclusiveSurfaceActive:get()).toBe(false)

		press(system, "Space")
		expect(g.counters.jump).toBe(1)
		press(system, "Up")
		expect(g.counters.move).toBe(1)
	end)
end)

-- ===========================================================================
-- (e) gameplayGuard=false opts out of the Space guard
-- ===========================================================================
describe("responder (e): gameplayGuard=false lets Space reach gameplay while engaged", function()
	it("Space reaches gameplay; Up is still sunk (nav owns it)", function()
		local core, _, _, system, pres = harness()
		local g = gameplay(system, core)
		local acts: { [string]: number } = {}
		local h = pres.present(hudScreen(acts), { responder = "passive", gameplayGuard = false })
		pres.refresh()
		h.engage()

		press(system, "Space")
		expect(g.counters.jump).toBe(1) -- Space is NOT guarded (opted out)
		press(system, "Up")
		expect(g.counters.move).toBe(0) -- Up still sunk by the engaged nav context
	end)
end)

-- ===========================================================================
-- (f) present() default is byte-identical: nav works AND gameplay also receives
-- ===========================================================================
describe("responder (f): present() default (no responder opt) is byte-identical", function()
	it("nav works immediately AND gameplay ALSO receives (documented UI-only-place semantics)", function()
		local core, _, _, system, pres = harness()
		local g = gameplay(system, core)
		local acts: { [string]: number } = {}
		local h = pres.present(hudScreen(acts)) -- NO responder opt: today's semantics
		pres.refresh()

		-- a plain present() screen is engaged-open (non-sinking) from the start
		expect(h.responder:get()).toBe("engaged")
		expect(pres.exclusiveSurfaceActive:get()).toBe(false) -- non-sinking: not exclusive

		press(system, "Down")
		expect(pres.focus.focused:get()).toBe("/HUD/b2") -- nav works immediately
		expect(g.counters.move).toBe(1) -- gameplay ALSO receives (non-sinking)
	end)
end)

-- ===========================================================================
-- (g) engage/resign churn is registry-neutral and leak-free
-- ===========================================================================
describe("responder (g): engage/resign churn is leak-free and registry-neutral", function()
	it("50 engage/resign cycles leave a single working context and gameplay intact", function()
		local core, _, _, system, pres = harness()
		local g = gameplay(system, core)
		local acts: { [string]: number } = {}
		local h = pres.present(hudScreen(acts), { responder = "passive" })
		pres.refresh()

		for _ = 1, 50 do
			h.engage()
			h.resign()
		end
		expect(h.responder:get()).toBe("passive")
		expect(pres.exclusiveSurfaceActive:get()).toBe(false)

		-- idempotent: a redundant engage/resign is a no-op, no double-registration
		h.engage()
		h.engage()
		-- a single Up moves focus exactly ONCE (no duplicate nav delivery). Focus is
		-- standing on b1 from the cycles above, so one press is one step to b2 — if
		-- the doubled engage had registered twice this would land back on b1.
		pres.focus.focusOn("/HUD/b1")
		press(system, "Up")
		expect(pres.focus.focused:get()).toBe("/HUD/b2") -- one step (wrap up)
		h.resign()
		h.resign()
		expect(h.responder:get()).toBe("passive")

		-- gameplay is fully restored after all the churn
		press(system, "Space")
		expect(g.counters.jump).toBe(1)
	end)
end)

-- ===========================================================================
-- Band placement (research conclusion 3): engaged bands sit strictly above 2000
-- ===========================================================================
describe("responder: the engaged band sits strictly above the gameplay sink (2000)", function()
	it("a modal's context priority is >= 3000 (mirrors CAS High) and > 2000", function()
		local _, _, _, _, pres = harness()
		local modal = pres.presentModal(Facet.UI.Screen({
			id = "M",
			children = { Facet.UI.Button({ id = "x", label = "x" }) },
		}))
		expect(modal.context.priority > 2000).toBe(true)
		expect(modal.context.priority >= 3000).toBe(true)
	end)

	it("an engaged-from-passive context sits above 2000", function()
		local _, _, _, _, pres = harness()
		local h = pres.present(
			Facet.UI.Screen({ id = "H", children = { Facet.UI.Button({ id = "x", label = "x" }) } }),
			{ responder = "passive" }
		)
		h.engage()
		expect(h.context.priority > 2000).toBe(true)
	end)
end)

-- ===========================================================================
-- Adapter-seam contract (platform verifier P1, 2026-07-21): engage()/resign()
-- must raise/lower Sink through the context's setSink seam — never a bare
-- field write. The headless model tolerates a field write (arbitration re-reads
-- context.sink), but the Roblox adapter arbitrates through the REAL
-- InputContext.Sink property, which only a setSink implementation can reach.
-- This spy proves the presenter uses the seam; roblox_input implements the
-- same seam over contextInstance.Sink (gate-grepped; Studio-drive-verified).
-- ===========================================================================
describe("responder: Sink changes go through the setSink adapter seam", function()
	it("engage() calls setSink(true) and resign() calls setSink(false) on the context", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = Facet.newActionSystem(core)
		local sinkCalls: { boolean } = {}
		-- wrap the action system: every created context records setSink calls
		local spySystem = setmetatable({
			createContext = function(spec)
				local context = system.createContext(spec)
				local realSetSink = context.setSink
				context.setSink = function(on: boolean)
					table.insert(sinkCalls, on)
					if realSetSink ~= nil then
						realSetSink(on)
					else
						context.sink = on -- seam missing: record, emulate, and fail below
					end
				end
				return context
			end,
			modifiers = system.modifiers,
			deviceKey = system.deviceKey,
		}, { __index = system })
		local adapter = require("../tests/lib/fake_target").new()
		local pres = Facet.newPresenter(core, env, adapter, spySystem)
		local h = pres.present(
			Facet.UI.Screen({ id = "SpyH", children = { Facet.UI.Button({ id = "b", label = "b" }) } }),
			{ responder = "passive" }
		)
		h.engage()
		expect(#sinkCalls).toBe(1)
		expect(sinkCalls[1]).toBe(true)
		expect(h.context.sink).toBe(true)
		h.resign()
		expect(#sinkCalls).toBe(2)
		expect(sinkCalls[2]).toBe(false)
		expect(h.context.sink).toBe(false)
	end)
end)
