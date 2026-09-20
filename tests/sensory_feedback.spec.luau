--!strict
local harness = require("./lib/harness")
-- `UI.sensoryFeedback(bp, { trigger, event })` — the authored half of the
-- semantic feedback seam (docs/plans/parity-round2.md §3.3, the
-- `.sensoryFeedback(_:trigger:)`).
--
-- What is guarded here:
--
--   * THE MODIFIER SAYS WHAT HAPPENED, IT PLAYS NOTHING. The emission is an
--     event on the presenter's bus (`src/present/feedback.luau:4-5`) and never
--     a sound, a haptic or a particle. There is no branch in this file that
--     could ever produce one.
--   * THE TAXONOMY STAYS CLOSED. An unregistered `event` is an authoring error
--     that lists the twelve valid verbs, refused at the CALL SITE rather than
--     one frame later inside `bus.emit`.
--   * A CHANGE, NOT A VALUE. The trigger must be a Signal/Memo — a plain value
--     can never change, so the declaration would be silently inert.
--   * THE CAUSAL FRAME. The event fires synchronously in the write that moved
--     the trigger, carrying the mounted path it was declared on.
--   * NO INERT DECLARATIONS. A structural region mounts no node of its own, so
--     the modifier is refused there instead of being accepted and dropped.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local customFactory = harness.coreFactory
local mountLib = harness
local feedbackLib = require("../src/present/feedback")
local environment = require("../src/env/environment")
local actionsLib = require("../src/input/actions")
local presenterLib = harness.presenterLib
local fake_target = require("./lib/fake_target")
local Compose = require("../src/vendor/compose/core")

local UI = harness.UI

-- a mount with a scripted feedback sink: the presenter supplies the real one,
-- and this is the same seam scripted, exactly as the transitions collaborator is
local function mounted(bp: any)
	local core = customFactory.new()
	local events: { any } = {}
	local root = mountLib.mount(core, bp, {
		feedback = function(event: any)
			table.insert(events, event)
		end,
	})
	return core, root, events
end

describe("UI.sensoryFeedback: the declaration is ruled on at the call site", function()
	it("refuses an event outside the closed twelve, listing the vocabulary", function()
		local core = customFactory.new()
		local trigger = Compose.cell(0)
		local ok, err = pcall(function()
			UI.sensoryFeedback(UI.Box({ id = "B" }), { trigger = trigger, event = "sparkle" })
		end)
		expect(ok).toBe(false)
		local text = tostring(err)
		expect(string.find(text, "sparkle", 1, true) ~= nil).toBeTruthy()
		-- the whole vocabulary, not a bare refusal
		for _, name in feedbackLib.TYPES do
			expect(string.find(text, name, 1, true) ~= nil).toBeTruthy()
		end
	end)

	it("accepts every one of the twelve verbs", function()
		local core = customFactory.new()
		local trigger = Compose.cell(0)
		for _, name in feedbackLib.TYPES do
			local bp = UI.sensoryFeedback(UI.Box({ id = "B" }), { trigger = trigger, event = name })
			expect(bp.meta[feedbackLib.SENSORY_PROP][1].event).toBe(name)
		end
	end)

	it("refuses a trigger that is not a Signal/Memo — a constant never changes", function()
		local ok, err = pcall(function()
			UI.sensoryFeedback(UI.Box({ id = "B" }), { trigger = 3, event = "select" })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "trigger", 1, true) ~= nil).toBeTruthy()
	end)

	it("refuses an unknown spec key rather than dropping it", function()
		local core = customFactory.new()
		local ok, err = pcall(function()
			UI.sensoryFeedback(
				UI.Box({ id = "B" }),
				{ trigger = Compose.cell(0), event = "select", intensity = "heavy" } :: any
			)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "intensity", 1, true) ~= nil).toBeTruthy()
	end)

	it("refuses a structural region — it would mount no node to emit for", function()
		local core = customFactory.new()
		local trigger = Compose.cell(0)
		local ok, err = pcall(function()
			UI.sensoryFeedback(
				UI.When({
					id = "W",
					condition = Compose.cell(true),
					thenView = function()
						return UI.Box({ id = "B" })
					end,
				}),
				{ trigger = trigger, event = "select" }
			)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "UI.When", 1, true) ~= nil).toBeTruthy()
	end)

	it("declares on the node it is given, in frozen metadata", function()
		local core = customFactory.new()
		local base = UI.Box({ id = "B" })
		local out = UI.sensoryFeedback(base, { trigger = Compose.cell(0), event = "select" })
		expect(out == base).toBe(true)
		expect(#out.meta[feedbackLib.SENSORY_PROP]).toBe(1)
		expect(table.isfrozen(out.meta)).toBe(true)
		expect(table.isfrozen(out.meta[feedbackLib.SENSORY_PROP])).toBe(true)
	end)
end)

describe("UI.sensoryFeedback: what reaches the bus", function()
	it("emits the declared verb with the mounted path when the trigger changes", function()
		local core = customFactory.new()
		local trigger = Compose.cell(0)
		local events: { any } = {}
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				children = {
					UI.sensoryFeedback(UI.Box({ id = "B" }), { trigger = trigger, event = "select" }),
				},
			}),
			{
				feedback = function(event: any)
					table.insert(events, event)
				end,
			}
		)
		expect(#events).toBe(0) -- mounting is not a change
		trigger:set(1)
		expect(#events).toBe(1)
		expect(events[1].type).toBe("select")
		expect(events[1].path).toBe("/S/B")
		root.dispose()
	end)

	it("fires once per change, and not at all for a write of the same value", function()
		local core = customFactory.new()
		local trigger = Compose.cell("a")
		local events: { any } = {}
		local root =
			mountLib.mount(core, UI.sensoryFeedback(UI.Box({ id = "B" }), { trigger = trigger, event = "adjust" }), {
				feedback = function(event: any)
					table.insert(events, event)
				end,
			})
		trigger:set("b")
		trigger:set("b")
		trigger:set("c")
		expect(#events).toBe(2)
		root.dispose()
	end)

	it("emits synchronously inside the write that moved the trigger", function()
		local core = customFactory.new()
		local trigger = Compose.cell(0)
		local seen: { number } = {}
		local root = mountLib.mount(
			core,
			UI.sensoryFeedback(UI.Box({ id = "B" }), {
				trigger = trigger,
				event = "commit",
			}),
			{
				feedback = function()
					table.insert(seen, trigger:peek())
				end,
			}
		)
		trigger:set(7)
		-- the handler already saw the POST-change value, in the same call
		expect(#seen).toBe(1)
		expect(seen[1]).toBe(7)
		root.dispose()
	end)

	it("stops emitting the moment the node unmounts", function()
		local core = customFactory.new()
		local trigger = Compose.cell(0)
		local show = Compose.cell(true)
		local events: { any } = {}
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				children = {
					UI.When({
						id = "W",
						condition = show,
						thenView = function()
							return UI.sensoryFeedback(UI.Box({ id = "B" }), { trigger = trigger, event = "select" })
						end,
					}),
				},
			}),
			{
				feedback = function(event: any)
					table.insert(events, event)
				end,
			}
		)
		trigger:set(1)
		expect(#events).toBe(1)
		show:set(false)
		trigger:set(2)
		expect(#events).toBe(1) -- the observer died with the branch scope
		root.dispose()
	end)

	it("composes: two declarations on one node both fire", function()
		local core = customFactory.new()
		local a, b = Compose.cell(0), Compose.cell(0)
		local bp = UI.sensoryFeedback(
			UI.sensoryFeedback(UI.Box({ id = "B" }), { trigger = a, event = "select" }),
			{ trigger = b, event = "reject" }
		)
		local _, root, events = mounted(bp)
		a:set(1)
		b:set(1)
		expect(#events).toBe(2)
		expect(events[1].type).toBe("select")
		expect(events[2].type).toBe("reject")
		root.dispose()
	end)

	it("observes NOTHING when no sink is wired, and exactly one thing when one is", function()
		-- the baseline: the same node with no declaration at all
		local plainCore = customFactory.new()
		local plainRoot = mountLib.mount(plainCore, UI.Box({ id = "B" }))
		local baseline = plainCore.owner.size()

		-- no presentation layer, so there is no bus to emit on: the declaration
		-- must not buy an observer nobody can hear (and must not throw)
		local bareCore = customFactory.new()
		local bareTrigger = Compose.cell(0)
		local bareRoot = mountLib.mount(
			bareCore,
			UI.sensoryFeedback(UI.Box({ id = "B" }), { trigger = bareTrigger, event = "select" })
		)
		expect(bareCore.owner.size()).toBe(baseline)
		bareTrigger:set(1)

		-- with a sink, exactly one observer more than the bare tree
		local wiredCore = customFactory.new()
		local wiredTrigger = Compose.cell(0)
		local wiredRoot = mountLib.mount(
			wiredCore,
			UI.sensoryFeedback(UI.Box({ id = "B" }), { trigger = wiredTrigger, event = "select" }),
			{ feedback = function() end }
		)
		expect(wiredCore.owner.size()).toBe(baseline + 1)

		plainRoot.dispose()
		bareRoot.dispose()
		wiredRoot.dispose()
	end)
end)

describe("UI.sensoryFeedback: through the real presenter", function()
	local function world()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 390, h = 844 })
		local adapter = fake_target.new()
		local system = actionsLib.newSystem(core)
		local pres = presenterLib.new(core, env, adapter, system)
		return core, pres
	end

	it("reaches presenter.onFeedback, carrying the surface it happened on", function()
		local core, pres = world()
		local trigger = Compose.cell(0)
		local events: { any } = {}
		pres.onFeedback(function(event: any)
			table.insert(events, event)
		end)
		local handle = pres.present(UI.Screen({
			id = "S",
			children = {
				UI.sensoryFeedback(UI.Box({ id = "B" }), { trigger = trigger, event = "celebrate" }),
			},
		}))
		trigger:set(1)
		expect(#events).toBe(1)
		expect(events[1].type).toBe("celebrate")
		expect(events[1].path).toBe("/S/B")
		expect(events[1].surface == handle).toBe(true)
	end)

	it("is visible on handle.onFeedback, the per-surface filter", function()
		local core, pres = world()
		local trigger = Compose.cell(0)
		local mine: { any } = {}
		local handle = pres.present(UI.Screen({
			id = "S",
			children = {
				UI.sensoryFeedback(UI.Box({ id = "B" }), { trigger = trigger, event = "land" }),
			},
		}))
		handle.onFeedback(function(event: any)
			table.insert(mine, event)
		end)
		trigger:set(1)
		expect(#mine).toBe(1)
		expect(mine[1].type).toBe("land")
	end)
end)
