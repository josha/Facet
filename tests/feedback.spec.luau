--!strict
-- THE SEMANTIC FEEDBACK SEAM (acceptance row SF-F1). What is
-- actually being guarded here:
--
--   * EXACTNESS — one event per cause, under rapid repeat. A feedback beat that
--     double-fires is a double haptic, which reads as a bug in the game.
--   * THE CAUSAL FRAME — the event fires synchronously in the call that caused it,
--     so a subscriber that reads state sees the state the cause produced (a Toggle
--     that flipped is already flipped when its `activate` arrives).
--   * A CLOSED TAXONOMY — an unknown verb is an authoring error naming the
--     vocabulary, because taxonomy sprawl is the named risk.
--   * Facet PLAYS NOTHING — the framework's only job is to say what happened.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local worldLib = require("./lib/world")

local customFactory = require("../src/core/custom")
local UI = require("../src/blueprint")
local environment = require("../src/env/environment")
local actionsLib = require("../src/input/actions")
local presenterLib = require("../src/present/presenter")
local feedbackLib = require("../src/present/feedback")
local fake_target = require("./lib/fake_target")

--[[ ONE SUBSTRATE (reuse audit REUSE-88, controller ruling R12).
	`tests/lib/world.luau` owns the construction and its two invariants — the
	viewport is set before anything can solve, and one presenter per adapter. The
	tuple order here, `core, env, adapter, system, pres`, is the one
	`Facet.newPresenter` itself takes and is now the only one in the suite: twelve
	files used to swap positions three and four with the same five names, so a line
	copied between two neighbouring specs bound an action system to a variable
	called `adapter` and said nothing. ]]
local function world()
	local w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 844 } })
	return w.core, w.env, w.adapter, w.system, w.pres
end

local function typesOf(events: { any }): string
	local out: { string } = {}
	for _, event in events do
		table.insert(out, event.type)
	end
	return table.concat(out, ",")
end

describe("feedback bus: the taxonomy is closed", function()
	it("every v1 verb is accepted", function()
		local bus = feedbackLib.new()
		local seen: { string } = {}
		bus.subscribe(function(event)
			table.insert(seen, event.type)
		end)
		for _, name in feedbackLib.TYPES do
			bus.emit({ type = name })
		end
		expect(#seen).toBe(#feedbackLib.TYPES)
		expect(table.find(feedbackLib.TYPES, "arrive") ~= nil).toBe(true)
		expect(table.find(feedbackLib.TYPES, "land") ~= nil).toBe(true)
		expect(table.find(feedbackLib.TYPES, "dismiss") ~= nil).toBe(true)
	end)

	it("an invented verb is an authoring error that lists the vocabulary", function()
		local bus = feedbackLib.new()
		local ok, err = pcall(function()
			bus.emit({ type = "sparkle" })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "sparkle", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "activate", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "CLOSED", 1, true) ~= nil).toBe(true)
	end)

	it("a malformed event is refused rather than delivered half-formed", function()
		local bus = feedbackLib.new()
		expect(pcall(function()
			bus.emit("activate" :: any)
		end)).toBe(false)
		expect(pcall(function()
			bus.subscribe(42 :: any)
		end)).toBe(false)
	end)
end)

describe("feedback bus: subscriptions", function()
	it("unsubscribing stops delivery and leaves no slot behind", function()
		local bus = feedbackLib.new()
		local count = 0
		local unsub = bus.subscribe(function()
			count += 1
		end)
		bus.emit({ type = "activate" })
		unsub()
		bus.emit({ type = "activate" })
		expect(count).toBe(1)
		expect(bus.count()).toBe(0)
		unsub() -- idempotent
		expect(bus.count()).toBe(0)
	end)

	it("a handler may unsubscribe itself from inside its own delivery", function()
		local bus = feedbackLib.new()
		local count = 0
		local unsub: (() -> ())? = nil
		unsub = bus.subscribe(function()
			count += 1
			(unsub :: () -> ())()
		end)
		bus.emit({ type = "activate" })
		bus.emit({ type = "activate" })
		expect(count).toBe(1)
	end)

	it("a handler subscribing during a delivery does not receive that same event", function()
		local bus = feedbackLib.new()
		local late = 0
		bus.subscribe(function()
			bus.subscribe(function()
				late += 1
			end)
		end)
		bus.emit({ type = "activate" })
		expect(late).toBe(0)
		bus.emit({ type = "activate" })
		expect(late > 0).toBe(true)
	end)
end)

describe("presenter feedback: activate", function()
	it("fires exactly once per press, on the causal frame, after the effect", function()
		local core, _, adapter, system, pres = world()
		local events: { any } = {}
		pres.onFeedback(function(event)
			table.insert(events, event)
		end)
		local flag = core:signal(false)
		local handle = pres.present(UI.Screen({
			id = "S",
			children = { UI.Toggle({ id = "T", label = "Music", value = flag }) },
		}))
		adapter.tap("/S/T")
		expect(typesOf(events)).toBe("activate")
		expect(events[1].path).toBe("/S/T")
		expect(events[1].surface).toBe(handle)
		expect(flag:get()).toBe(true) -- the effect already landed when the event fired

		-- rapid repeat: one event per press, never two
		system.deviceKey("ButtonA", true)
		system.deviceKey("ButtonA", false)
		system.deviceKey("ButtonA", true)
		system.deviceKey("ButtonA", false)
		expect(typesOf(events)).toBe("activate,activate,activate")
	end)

	it("a disabled control emits nothing — nothing happened", function()
		local _, _, adapter, _, pres = world()
		local events: { any } = {}
		pres.onFeedback(function(event)
			table.insert(events, event)
		end)
		pres.present(UI.Screen({
			id = "S",
			children = { UI.Button({ id = "B", label = "Go", enabled = false }) },
		}))
		adapter.tap("/S/B")
		expect(#events).toBe(0)
	end)

	it("handle.onFeedback sees only its own surface's events", function()
		local _, _, adapter, _, pres = world()
		local base = pres.present(UI.Screen({ id = "Base", children = { UI.Button({ id = "B", label = "b" }) } }))
		local modal = pres.presentModal(UI.Screen({ id = "M", children = { UI.Button({ id = "Y", label = "y" }) } }))
		local baseEvents: { any } = {}
		local modalEvents: { any } = {}
		base.onFeedback(function(event)
			table.insert(baseEvents, event)
		end)
		modal.onFeedback(function(event)
			table.insert(modalEvents, event)
		end)
		adapter.tap("/M/Y")
		expect(#modalEvents).toBe(1)
		expect(#baseEvents).toBe(0)
	end)
end)

describe("presenter feedback: dismiss and the session registration point", function()
	it("a dismissed modal reports it on the frame the decision was taken", function()
		local _, _, _, system, pres = world()
		local events: { any } = {}
		pres.onFeedback(function(event)
			table.insert(events, event)
		end)
		pres.present(UI.Screen({ id = "Base", children = { UI.Button({ id = "B", label = "b" }) } }))
		pres.presentModal(UI.Screen({ id = "M", children = { UI.Button({ id = "Y", label = "y" }) } }))
		system.deviceKey("ButtonB", true)
		system.deviceKey("ButtonB", false)
		expect(typesOf(events)).toBe("dismiss")
		expect(events[1].path).toBe("/M")
		expect(pres.depth()).toBe(1) -- the surface was already gone when it fired
	end)

	it("presenter.emitFeedback is the seam a drag session commits through", function()
		local _, _, _, _, pres = world()
		local events: { any } = {}
		pres.onFeedback(function(event)
			table.insert(events, event)
		end)
		-- exactly the shape P4's session uses: its own verbs, its own reason codes
		pres.emitFeedback({ type = "commit", path = "/Hand/Card", context = { targetId = "row-3" } })
		pres.emitFeedback({ type = "reject", path = "/Hand/Card", reason = "not-your-turn" })
		pres.emitFeedback({ type = "land", path = "/Hand/Card" })
		expect(typesOf(events)).toBe("commit,reject,land")
		expect(events[2].reason).toBe("not-your-turn")
	end)

	it("onModalPresented is the modal-cancels-drag hook, and it unsubscribes", function()
		local _, _, _, _, pres = world()
		local cancelled = 0
		local unsub = pres.onModalPresented(function()
			cancelled += 1
		end)
		pres.present(UI.Screen({ id = "Base", children = { UI.Button({ id = "B", label = "b" }) } }))
		expect(cancelled).toBe(0) -- a base screen is not a trap
		local modal = pres.presentModal(UI.Screen({ id = "M", children = { UI.Button({ id = "Y", label = "y" }) } }))
		expect(cancelled).toBe(1)
		pres.dismiss(modal)
		unsub()
		pres.presentModal(UI.Screen({ id = "M2", children = { UI.Button({ id = "Y", label = "y" }) } }))
		expect(cancelled).toBe(1)
	end)
end)
