--!strict
--[[
	LATE INPUT CONTRIBUTIONS + THE FOCUS-VISIBLE RULE
	(RascalRally device round 1, DB-4 the crown bug and DB-3(b)).

	DB-4. The presenter's input auto-wiring used to be a ONE-SHOT walk at
	`present()` time, which silently assumed every contributing control is mounted
	then. `UI.When` exists precisely so that is not true. RascalRally's whole
	Sponsor HUD lives under one region gated on "am I a sponsor" and the presenter
	is constructed at client startup, so on a real device the racer list's
	`handleActivate` was never wired: a tap on a row with a card held moved focus
	(and therefore the drag aim, so the row painted a legal verdict) and then did
	nothing at all. Every headless row passed because the rigs mount the
	contributing control at present time.

	DB-3(b). A focus RING is the answer to "where does the next Navigate go". A
	finger asks no such question, so a pointer/touch-driven focus move must track
	focus (aim, keep-visible, selection bridge — all unchanged) and paint nothing.
	The next navigation verb brings the ring back where the finger left it.

	Everything below drives the REAL seams: `adapter.touchTap` (the honest
	three-part finger: InputBegan, InputEnded, Activated with touch meta) and
	`system.deviceKey`.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local worldLib = require("./lib/world")

local Facet = require("../src") :: any
local contribution = require("../src/input/contribution")
local fake_target = require("../tests/lib/fake_target")

local UI = Facet.UI

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

-- a screen whose ONLY contributing control lives inside a `UI.When`, exactly
-- like a HUD gated on a role/phase the player does not have yet
local function gatedWorld()
	local core, _, adapter, system, pres = harness()
	local open = core:signal(false)
	local hits: { string } = {}
	local bound = { controller = 0, actions = 0 }
	local inner = contribution.attach(
		UI.VStack({
			id = "Panel",
			children = {
				UI.Button({ id = "One", label = "One" }),
				UI.Button({ id = "Two", label = "Two" }),
			},
		}),
		{
			handleActivate = function(path: string): boolean
				table.insert(hits, path)
				return true
			end,
			focusGroups = function(rootNode: any): { any }
				return {
					{
						name = "panel",
						axis = "vertical",
						wrap = true,
						order = { rootNode.path .. "/One", rootNode.path .. "/Two" },
					},
				}
			end,
			bindController = function()
				bound.controller += 1
			end,
			bindActionSystem = function()
				bound.actions += 1
			end,
		}
	)
	local screen = UI.Screen({
		id = "S",
		children = {
			UI.Button({ id = "Always", label = "Always" }),
			UI.When({
				id = "Gate",
				condition = open,
				thenView = function()
					return inner
				end,
			}),
		},
	})
	pres.present(screen) -- ZERO opts: full auto-composition
	pres.refresh()
	return {
		core = core,
		system = system,
		adapter = adapter,
		pres = pres,
		open = open,
		hits = hits,
		bound = bound,
	}
end

local GATED_ONE = "/S/Gate/then/Panel/One"

describe("DB-4: a contribution mounted AFTER present is discovered and wired", function()
	it("the region is closed at present time, so nothing of it is wired yet", function()
		local w = gatedWorld()
		expect(w.adapter.node(GATED_ONE)).toBe(nil)
		expect(w.bound.controller).toBe(0)
		expect(w.bound.actions).toBe(0)
	end)

	it("opening the region wires handleActivate — a REAL finger tap dispatches", function()
		local w = gatedWorld()
		w.open:set(true)
		w.pres.refresh()
		expect(w.adapter.node(GATED_ONE) ~= nil).toBe(true)
		-- the honest touch tap: InputBegan + InputEnded + Activated(touch meta)
		w.adapter.touchTap(GATED_ONE)
		expect(#w.hits).toBe(1)
		expect(w.hits[1]).toBe(GATED_ONE)
	end)

	it("...and its one-time bindings run exactly once, on the frame it appears", function()
		local w = gatedWorld()
		w.open:set(true)
		w.pres.refresh()
		expect(w.bound.controller).toBe(1)
		expect(w.bound.actions).toBe(1)
		-- a refresh that changes nothing re-binds nothing
		w.pres.refresh()
		w.pres.refresh()
		expect(w.bound.controller).toBe(1)
		expect(w.bound.actions).toBe(1)
	end)

	it("a LATE focusGroups upgrades the scope's navigation model (flat -> grouped)", function()
		local w = gatedWorld()
		w.open:set(true)
		w.pres.refresh()
		-- the declared group WRAPS: from the last entry, Down returns to the first.
		-- A flat ring over the whole screen would land on `/S/Always` instead.
		w.pres.focus.focusOn("/S/Gate/then/Panel/Two")
		w.system.deviceKey("Down", true)
		w.system.deviceKey("Down", false)
		expect(w.pres.focus.focused:get()).toBe(GATED_ONE)
	end)

	it("closing the region drops it again: a dispatch can never reach a dead control", function()
		local w = gatedWorld()
		w.open:set(true)
		w.pres.refresh()
		w.adapter.touchTap(GATED_ONE)
		expect(#w.hits).toBe(1)
		w.open:set(false)
		w.pres.refresh()
		expect(w.adapter.node(GATED_ONE)).toBe(nil)
		expect(#w.hits).toBe(1)
	end)
end)

-- ===========================================================================
describe("DB-3(b): the focus RING answers navigation, never a finger", function()
	local BTN_A = "/S/A"
	local BTN_B = "/S/B"
	local function ringWorld()
		local core, _, adapter, system, pres = harness()
		local screen = UI.Screen({
			id = "S",
			children = {
				UI.Button({ id = "A", label = "A" }),
				UI.Button({ id = "B", label = "B" }),
			},
		})
		pres.present(screen)
		pres.refresh()
		return { core = core, system = system, adapter = adapter, pres = pres }
	end

	-- "is a ring painted on this node right now" — nil (never written) and false
	-- (written off) are the same answer to the player
	local function ringOn(w: any, path: string): boolean
		local node = w.adapter.node(path)
		return node ~= nil and node.focused == true
	end

	it("a touch tap MOVES focus and paints NO ring", function()
		local w = ringWorld()
		expect(ringOn(w, BTN_A)).toBe(true) -- the entry ring, before any finger
		w.adapter.touchTap(BTN_B)
		expect(w.pres.focus.focused:get()).toBe(BTN_B) -- identity still tracked
		expect(ringOn(w, BTN_B)).toBe(false)
		expect(ringOn(w, BTN_A)).toBe(false) -- and the one it left is cleared
	end)

	it("a NAVIGATION verb brings the ring back, on the node the finger left it on", function()
		local w = ringWorld()
		w.adapter.touchTap(BTN_B)
		expect(ringOn(w, BTN_B)).toBe(false)
		-- Down wraps back to A in the flat ring; the ring is visible from here on
		w.system.deviceKey("Down", true)
		w.system.deviceKey("Down", false)
		expect(ringOn(w, w.pres.focus.focused:get())).toBe(true)
	end)

	it("a tap AFTER navigating puts the ring away again (no stale ring behind a finger)", function()
		local w = ringWorld()
		w.system.deviceKey("Down", true)
		w.system.deviceKey("Down", false)
		expect(ringOn(w, w.pres.focus.focused:get())).toBe(true)
		w.adapter.touchTap(BTN_A)
		expect(w.pres.focus.focused:get()).toBe(BTN_A)
		expect(ringOn(w, BTN_A)).toBe(false)
		expect(ringOn(w, BTN_B)).toBe(false)
	end)

	it("keyboard/gamepad-only sessions are untouched: the ring paints from the first move", function()
		local w = ringWorld()
		expect(w.pres.focus.focusVisible:get()).toBe(true)
		w.system.deviceKey("Down", true)
		w.system.deviceKey("Down", false)
		expect(w.pres.focus.focusVisible:get()).toBe(true)
		expect(ringOn(w, w.pres.focus.focused:get())).toBe(true)
	end)
end)
