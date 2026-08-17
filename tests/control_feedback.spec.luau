--!strict
-- THE PER-CONTROL SENSORY HOOK — `UI.sensoryFeedback(bp, { activation = verb })`
-- (director request 2026-08-13: "when you press a button you get haptic
-- feedback"; docs/reference/swiftui-parity.md §7.1).
--
-- Round 2 shipped the CHANGE form — `{ trigger, event }` — which needs a Readable
-- and fires on its transitions. There was no way for a CONTROL to say "this is
-- what MY activation feels like", so an author who wanted a Confirm button to
-- feel different from a Cancel button had to invent a signal to hang the
-- modifier on. This file guards the second form of the same modifier.
--
-- What is guarded here:
--
--   * ONE MODIFIER, TWO FORMS, discriminated by key set and never mixed. The
--     taxonomy stays CLOSED for both, and `none` is the only extra word — a
--     control that must feel like nothing.
--   * IT IS A CASCADE, NOT A PROP. The declaration is resolved down the mounted
--     tree, nearest ancestor wins. That is what makes it a GENERAL mechanism
--     rather than a Button special case: it reaches every composite control
--     (Chip, Stepper, Table row, PopupButton) without one line of per-control
--     plumbing, and one declaration on a panel covers everything in it.
--   * THE VERB REPLACES `activate` ON THE BUS, on the same causal frame, from
--     every input class. `none` emits nothing at all.
--   * THE RESOLVED VERB REACHES THE ADAPTER, so the ENGINE can play the right
--     sensation through `GuiButton.PressHapticEffect`. LuauUI still plays
--     nothing — it publishes a fact and hands over a reference.
--
-- Mutation evidence for every check in this file:
-- artifacts/swiftui-parity-round3/control-feedback-mutations.md

local fs = require("@lune/fs")

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src") :: any
local customFactory = require("../src/core/custom")
local mountLib = require("../src/mount")
local feedbackLib = require("../src/present/feedback")
local hapticsLib = require("../src/client/haptics")
local environment = require("../src/env/environment")
local actionsLib = require("../src/input/actions")
local presenterLib = require("../src/present/presenter")
local fake_target = require("./lib/fake_target")

local UI = LuauUI.UI

local function world()
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 390, h = 844 })
	local adapter = fake_target.new()
	local system = actionsLib.newSystem(core)
	local pres = presenterLib.new(core, env, adapter, system)
	return core, env, adapter, system, pres
end

local function typesOf(events: { any }): string
	local names: { string } = {}
	for _, e in events do
		table.insert(names, e.type)
	end
	return table.concat(names, ",")
end

-- find a mounted node by path in a bare mount (the cascade is a MOUNT fact, so
-- these read the mounted tree rather than going through a presenter)
local function nodeAt(root: any, path: string): any
	local function walk(node: any): any
		if node.path == path then
			return node
		end
		for _, child in node.children or {} do
			local found = walk(child)
			if found ~= nil then
				return found
			end
		end
		return nil
	end
	return walk(root.node)
end

describe("the per-control declaration is ruled on at the call site", function()
	it("accepts every one of the twelve verbs, plus `none`", function()
		for _, verb in feedbackLib.TYPES do
			local bp = UI.sensoryFeedback(UI.Button({ id = "B", label = "b" }), { activation = verb })
			expect(bp.meta[feedbackLib.SENSORY_PROP][1].activation).toBe(verb)
		end
		local silent = UI.sensoryFeedback(UI.Button({ id = "B", label = "b" }), { activation = "none" })
		expect(silent.meta[feedbackLib.SENSORY_PROP][1].activation).toBe("none")
	end)

	it("refuses a verb outside the closed twelve, listing the whole vocabulary", function()
		local ok, err = pcall(function()
			UI.sensoryFeedback(UI.Button({ id = "B", label = "b" }), { activation = "rumble" })
		end)
		expect(ok).toBe(false)
		local text = tostring(err)
		expect(string.find(text, "rumble", 1, true) ~= nil).toBeTruthy()
		for _, name in feedbackLib.TYPES do
			expect(`{name}:{string.find(text, name, 1, true) ~= nil}`).toBe(`{name}:true`)
		end
		-- `none` is offered too, or the only way to silence a control is undiscoverable
		expect(string.find(text, "none", 1, true) ~= nil).toBeTruthy()
	end)

	it("refuses a non-string activation, NAMING the type rather than the value", function()
		local ok, err = pcall(function()
			UI.sensoryFeedback(UI.Button({ id = "B", label = "b" }), { activation = true } :: any)
		end)
		expect(ok).toBe(false)
		-- the unknown-VERB refusal would also fire here and would also contain the
		-- word "activation", so asserting that proves nothing about the type check.
		-- The message an author can act on names what they passed.
		local text = tostring(err)
		expect(string.find(text, "must be a string", 1, true) ~= nil).toBeTruthy()
		expect(string.find(text, "boolean", 1, true) ~= nil).toBeTruthy()
	end)

	it("refuses MIXING the two forms in one spec — they have different causes", function()
		local core = customFactory.new()
		local ok, err = pcall(function()
			UI.sensoryFeedback(
				UI.Button({ id = "B", label = "b" }),
				{ trigger = core:signal(0), event = "select", activation = "commit" } :: any
			)
		end)
		expect(ok).toBe(false)
		local text = tostring(err)
		expect(string.find(text, "activation", 1, true) ~= nil).toBeTruthy()
		expect(string.find(text, "trigger", 1, true) ~= nil).toBeTruthy()
	end)

	it("refuses a spec that declares NEITHER form", function()
		local ok, err = pcall(function()
			UI.sensoryFeedback(UI.Button({ id = "B", label = "b" }), {} :: any)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "activation", 1, true) ~= nil).toBeTruthy()
	end)

	it("refuses a SECOND activation on the same node — one control, one sensation", function()
		local once = UI.sensoryFeedback(UI.Button({ id = "B", label = "b" }), { activation = "commit" })
		local ok, err = pcall(function()
			UI.sensoryFeedback(once, { activation = "reject" })
		end)
		expect(ok).toBe(false)
		local text = tostring(err)
		expect(string.find(text, "commit", 1, true) ~= nil).toBeTruthy()
		expect(string.find(text, "reject", 1, true) ~= nil).toBeTruthy()
	end)

	it("composes with the CHANGE form on the same node — different causes, both kept", function()
		local core = customFactory.new()
		local bp = UI.sensoryFeedback(
			UI.sensoryFeedback(UI.Button({ id = "B", label = "b" }), { activation = "commit" }),
			{ trigger = core:signal(0), event = "select" }
		)
		local list = bp.meta[feedbackLib.SENSORY_PROP]
		expect(#list).toBe(2)
		expect(list[1].activation).toBe("commit")
		expect(list[2].event).toBe("select")
	end)

	it("refuses a structural region, exactly as the change form does", function()
		local core = customFactory.new()
		local ok, err = pcall(function()
			UI.sensoryFeedback(
				UI.ForEach({
					id = "F",
					items = core:signal({}),
					key = function(v: any): string
						return tostring(v)
					end,
					row = function(): any
						return UI.Box({ id = "R" })
					end,
				}),
				{ activation = "commit" }
			)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "UI.ForEach", 1, true) ~= nil).toBeTruthy()
	end)
end)

describe("the cascade: nearest declaration wins, and costs nothing when absent", function()
	it("a declaration on the control itself resolves onto its mounted node", function()
		local core = customFactory.new()
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				children = { UI.sensoryFeedback(UI.Button({ id = "B", label = "b" }), { activation = "commit" }) },
			})
		)
		expect(nodeAt(root, "/S/B").activationFeedback).toBe("commit")
		root.dispose()
	end)

	it("INHERITS: a declaration on a container reaches every control inside it", function()
		local core = customFactory.new()
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				children = {
					UI.sensoryFeedback(
						UI.VStack({
							id = "Panel",
							children = {
								UI.Button({ id = "A", label = "a" }),
								UI.VStack({ id = "Inner", children = { UI.Button({ id = "Deep", label = "d" }) } }),
							},
						}),
						{ activation = "commit" }
					),
					UI.Button({ id = "Outside", label = "o" }),
				},
			})
		)
		expect(nodeAt(root, "/S/Panel/A").activationFeedback).toBe("commit")
		expect(nodeAt(root, "/S/Panel/Inner/Deep").activationFeedback).toBe("commit")
		-- ...and stops at the panel's edge
		expect(nodeAt(root, "/S/Outside").activationFeedback).toBe(nil)
		root.dispose()
	end)

	it("a NEARER declaration overrides a farther one", function()
		local core = customFactory.new()
		local root = mountLib.mount(
			core,
			UI.sensoryFeedback(
				UI.Screen({
					id = "S",
					children = {
						UI.sensoryFeedback(UI.Button({ id = "No", label = "n" }), { activation = "none" }),
						UI.Button({ id = "Yes", label = "y" }),
					},
				}),
				{ activation = "commit" }
			)
		)
		expect(nodeAt(root, "/S/No").activationFeedback).toBe("none")
		expect(nodeAt(root, "/S/Yes").activationFeedback).toBe("commit")
		root.dispose()
	end)

	it("crosses a structural region: a When branch inherits from outside it", function()
		local core = customFactory.new()
		local show = core:signal(true)
		local root = mountLib.mount(
			core,
			UI.sensoryFeedback(
				UI.Screen({
					id = "S",
					children = {
						UI.When({
							id = "W",
							condition = show,
							thenView = function(): any
								return UI.Button({ id = "B", label = "b" })
							end,
						}),
					},
				}),
				{ activation = "reject" }
			)
		)
		expect(nodeAt(root, "/S/W/then/B").activationFeedback).toBe("reject")
		-- ...and again after a remount, which is a DIFFERENT code path
		show:set(false)
		show:set(true)
		expect(nodeAt(root, "/S/W/then/B").activationFeedback).toBe("reject")
		root.dispose()
	end)

	it("crosses a ForEach: every row inherits, including rows added later", function()
		local core = customFactory.new()
		local items = core:signal({ "a" })
		local root = mountLib.mount(
			core,
			UI.sensoryFeedback(
				UI.Screen({
					id = "S",
					children = {
						UI.ForEach({
							id = "F",
							items = items,
							key = function(v: any): string
								return tostring(v)
							end,
							row = function(v: any): any
								return UI.Button({ id = "Row", label = tostring(v) })
							end,
						}),
					},
				}),
				{ activation = "select" }
			)
		)
		expect(nodeAt(root, "/S/F/[a]/Row").activationFeedback).toBe("select")
		items:set({ "a", "b" })
		expect(nodeAt(root, "/S/F/[b]/Row").activationFeedback).toBe("select")
		root.dispose()
	end)

	it("an undeclared tree carries the field NOWHERE — the off path is free", function()
		local core = customFactory.new()
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				children = {
					UI.VStack({ id = "V", children = { UI.Button({ id = "B", label = "b" }) } }),
				},
			})
		)
		expect(nodeAt(root, "/S").activationFeedback).toBe(nil)
		expect(nodeAt(root, "/S/V").activationFeedback).toBe(nil)
		expect(nodeAt(root, "/S/V/B").activationFeedback).toBe(nil)
		root.dispose()
	end)

	it("buys NO observer: the control form has no Readable to watch", function()
		local plainCore = customFactory.new()
		local plainRoot = mountLib.mount(plainCore, UI.Button({ id = "B", label = "b" }), { feedback = function() end })
		local baseline = plainCore:counters().observers

		local declaredCore = customFactory.new()
		local declaredRoot = mountLib.mount(
			declaredCore,
			UI.sensoryFeedback(UI.Button({ id = "B", label = "b" }), { activation = "commit" }),
			{ feedback = function() end }
		)
		expect(declaredCore:counters().observers).toBe(baseline)
		plainRoot.dispose()
		declaredRoot.dispose()
	end)
end)

describe("what a press emits", function()
	it("an undeclared control still emits `activate` — the default is unchanged", function()
		local _, _, adapter, _, pres = world()
		local events: { any } = {}
		pres.onFeedback(function(event: any)
			table.insert(events, event)
		end)
		pres.present(UI.Screen({ id = "S", children = { UI.Button({ id = "B", label = "b" }) } }))
		adapter.tap("/S/B")
		expect(typesOf(events)).toBe("activate")
		-- ...and it now says WHY it fired, so a subscriber can tell a control
		-- activation from a game-emitted verb of the same name
		expect(events[1].reason).toBe("activation")
	end)

	it("a declared control emits ITS verb instead of `activate`", function()
		local _, _, adapter, _, pres = world()
		local events: { any } = {}
		pres.onFeedback(function(event: any)
			table.insert(events, event)
		end)
		pres.present(UI.Screen({
			id = "S",
			children = {
				UI.sensoryFeedback(UI.Button({ id = "Buy", label = "Buy" }), { activation = "commit" }),
				UI.sensoryFeedback(UI.Button({ id = "Stop", label = "Stop" }), { activation = "reject" }),
				UI.Button({ id = "Plain", label = "Plain" }),
			},
		}))
		adapter.tap("/S/Buy")
		adapter.tap("/S/Stop")
		adapter.tap("/S/Plain")
		expect(typesOf(events)).toBe("commit,reject,activate")
		expect(events[1].path).toBe("/S/Buy")
		expect(events[1].reason).toBe("activation")
	end)

	it("`none` emits NOTHING — the control is deliberately unfelt", function()
		local _, _, adapter, _, pres = world()
		local events: { any } = {}
		pres.onFeedback(function(event: any)
			table.insert(events, event)
		end)
		pres.present(UI.Screen({
			id = "S",
			children = {
				UI.sensoryFeedback(UI.Button({ id = "Quiet", label = "q" }), { activation = "none" }),
				UI.Button({ id = "Loud", label = "l" }),
			},
		}))
		adapter.tap("/S/Quiet")
		expect(#events).toBe(0)
		adapter.tap("/S/Loud")
		expect(typesOf(events)).toBe("activate")
	end)

	it("the same verb arrives from EVERY input class, not only a pointer", function()
		local _, _, adapter, system, pres = world()
		local events: { any } = {}
		pres.onFeedback(function(event: any)
			table.insert(events, event)
		end)
		pres.present(UI.Screen({
			id = "S",
			children = { UI.sensoryFeedback(UI.Button({ id = "B", label = "b" }), { activation = "commit" }) },
		}))
		adapter.tap("/S/B") -- mouse
		adapter.tap("/S/B", { source = "pointer", pointer = "touch" }) -- touch
		system.deviceKey("ButtonA", true) -- gamepad
		system.deviceKey("ButtonA", false)
		expect(typesOf(events)).toBe("commit,commit,commit")
	end)

	it("reaches a COMPOSITE control with no per-control plumbing", function()
		local core, _, adapter, _, pres = world()
		local events: { any } = {}
		pres.onFeedback(function(event: any)
			table.insert(events, event)
		end)
		local on = core:signal(false)
		local chip = LuauUI.newChip(LuauUI, core, { id = "C", label = "Wet", selected = on })
		pres.present(UI.Screen({
			id = "S",
			children = { UI.sensoryFeedback(chip.blueprint, { activation = "select" }) },
		}))
		-- the Chip is a composite: the node that actually activates is the Button
		-- it built, which never heard of this declaration
		local seen = false
		for _, path in adapter.paths() do
			if string.find(path, "/S/C", 1, true) == 1 then
				local before = #events
				adapter.tap(path)
				if #events > before then
					seen = true
					expect(events[#events].type).toBe("select")
				end
			end
		end
		expect(seen).toBe(true)
	end)

	it("a disabled declared control still emits nothing", function()
		local _, _, adapter, _, pres = world()
		local events: { any } = {}
		pres.onFeedback(function(event: any)
			table.insert(events, event)
		end)
		pres.present(UI.Screen({
			id = "S",
			children = {
				UI.sensoryFeedback(UI.Button({ id = "B", label = "b", enabled = false }), { activation = "commit" }),
			},
		}))
		adapter.tap("/S/B")
		expect(#events).toBe(0)
	end)
end)

describe("the render seam publishes the resolved verb", function()
	it("hands the adapter the verb for the controls that can be activated", function()
		local _, _, adapter, _, pres = world()
		pres.present(UI.Screen({
			id = "S",
			children = {
				UI.sensoryFeedback(UI.Button({ id = "Buy", label = "b" }), { activation = "commit" }),
				UI.sensoryFeedback(UI.Button({ id = "Quiet", label = "q" }), { activation = "none" }),
				UI.Button({ id = "Plain", label = "p" }),
			},
		}))
		expect(adapter.activationFeedbackOf("/S/Buy")).toBe("commit")
		expect(adapter.activationFeedbackOf("/S/Quiet")).toBe("none")
		expect(adapter.activationFeedbackOf("/S/Plain")).toBe(nil)
	end)

	it("does NOT spend the seam on nodes that cannot be activated", function()
		local _, _, adapter, _, pres = world()
		pres.present(UI.Screen({
			id = "S",
			children = {
				UI.sensoryFeedback(
					UI.VStack({
						id = "Panel",
						children = { UI.Box({ id = "Plate" }), UI.Button({ id = "B", label = "b" }) },
					}),
					{ activation = "commit" }
				),
			},
		}))
		expect(adapter.activationFeedbackOf("/S/Panel/B")).toBe("commit")
		-- a Box has no activation, so publishing a verb for it would be noise
		expect(adapter.activationFeedbackOf("/S/Panel/Plate")).toBe(nil)
		expect(adapter.activationFeedbackOf("/S/Panel")).toBe(nil)
	end)

	it("a recycled instance never inherits the PREVIOUS control's verb", function()
		-- MEASURED, NOT ASSUMED: the pool only has something to hand out on the
		-- SECOND structural change (the renderer creates before it parks), and
		-- `stats().recycled` is asserted below so this cannot quietly become a test
		-- of two fresh instances — which is exactly what its first version was.
		local core, _, adapter, _, pres = world()
		local items = core:signal({ { key = "a", declared = true } })
		local handle = pres.present(UI.Screen({
			id = "S",
			children = {
				UI.ForEach({
					id = "F",
					items = items,
					key = function(item: any): string
						return item.key
					end,
					row = function(item: any): any
						local button = UI.Button({ id = "B", label = "b" })
						return if item.declared then UI.sensoryFeedback(button, { activation = "commit" }) else button
					end,
				}),
			},
		}))
		expect(adapter.activationFeedbackOf("/S/F/[a]/B")).toBe("commit")
		items:set({ { key = "b", declared = true } })
		handle.controller.refresh()
		items:set({ { key = "c", declared = false } })
		handle.controller.refresh()
		expect(handle.controller.stats().recycled > 0).toBe(true)
		expect(adapter.activationFeedbackOf("/S/F/[c]/B")).toBe(nil)
	end)
end)

describe("the haptics adapter plays the declared sensation through the engine", function()
	-- one fake GuiButton: the adapter's whole engine contract for the press route
	local function fakeButton(attribute: string?): any
		local attrs: { [string]: any } = {}
		if attribute ~= nil then
			attrs.LuauUI_ActivationFeedback = attribute
		end
		return {
			PressHapticEffect = nil :: any,
			IsA = function(_self: any, className: string): boolean
				return className == "GuiButton"
			end,
			GetAttribute = function(_self: any, name: string): any
				return attrs[name]
			end,
			GetDescendants = function(): { any }
				return {}
			end,
		}
	end

	local function fakeRoot(children: { any }): any
		local root: any
		root = {
			IsA = function(): boolean
				return false
			end,
			GetAttribute = function(): any
				return nil
			end,
			GetDescendants = function(): { any }
				return children
			end,
			DescendantAdded = {
				Connect = function(): any
					return { Disconnect = function() end }
				end,
			},
			Destroying = {
				Connect = function(): any
					return { Disconnect = function() end }
				end,
			},
		}
		return root
	end

	local function adapterWith(children: { any })
		local built: { any } = {}
		local hap = hapticsLib.new({
			enabled = true,
			inputService = false,
			hapticService = false,
			parent = false,
			enums = {
				HapticEffectType = { UIClick = "E:UIClick", UIHover = "E:UIHover", UINotification = "E:UINotification" },
			},
			instanceNew = function(): any
				local effect: any = {
					Type = nil,
					Play = function() end,
					Stop = function() end,
					Destroy = function() end,
				}
				table.insert(built, effect)
				return effect
			end,
		})
		hap.attachButtons(fakeRoot(children))
		return hap, built
	end

	it("an UNDECLARED button gets the press preset, exactly as before", function()
		local button = fakeButton(nil)
		local hap = adapterWith({ button })
		expect(button.PressHapticEffect ~= nil).toBe(true)
		expect(button.PressHapticEffect.Type).toBe("E:UIClick")
		hap.dispose()
	end)

	it("a DECLARED button gets the effect its verb maps to, not the generic press", function()
		local commit = fakeButton("commit")
		local reject = fakeButton("reject")
		local hap = adapterWith({ commit, reject })
		expect(commit.PressHapticEffect.Type).toBe("E:UIClick")
		expect(reject.PressHapticEffect.Type).toBe("E:UINotification")
		-- ...and they are two DIFFERENT effects, or the declaration bought nothing
		expect(commit.PressHapticEffect == reject.PressHapticEffect).toBe(false)
		hap.dispose()
	end)

	it("`none` leaves the button with NO effect reference at all", function()
		local quiet = fakeButton("none")
		-- START DECORATED. A `decorate` that merely SKIPS a silent control passes a
		-- from-nil assertion while leaving a button somebody else already decorated
		-- buzzing forever, so the pin has to be that the reference is actively
		-- CLEARED — "none unless somebody already said otherwise" is not none.
		quiet.PressHapticEffect = { stale = true }
		local hap = adapterWith({ quiet })
		expect(quiet.PressHapticEffect).toBe(nil)
		expect(hap.diagnostics().decorated).toBe(0)
		hap.dispose()
	end)

	it("a verb the MAP deliberately silences is also unfelt", function()
		local cancel = fakeButton("cancel")
		local hap = adapterWith({ cancel })
		expect(cancel.PressHapticEffect).toBe(nil)
		hap.dispose()
	end)

	it("effects are POOLED per verb: ten commit buttons share one effect", function()
		local buttons: { any } = {}
		for _ = 1, 10 do
			table.insert(buttons, fakeButton("commit"))
		end
		local hap, built = adapterWith(buttons)
		expect(#built).toBe(1)
		for _, b in buttons do
			expect(b.PressHapticEffect == buttons[1].PressHapticEffect).toBe(true)
		end
		hap.dispose()
	end)

	it("STILL PLAYS NOTHING for an activation: the engine owns the press route", function()
		local button = fakeButton("commit")
		local hap = adapterWith({ button })
		hap.bind({
			onFeedback = function(fn: any): any
				-- a control activation, the new `reason`
				fn({ type = "commit", path = "/S/B", reason = "activation" })
				return function() end
			end,
		})
		-- the button's PressHapticEffect is what plays; the adapter must not
		-- double it from the bus
		expect(hap.diagnostics().plays).toBe(0)
		hap.dispose()
	end)

	it("...but a GAME-emitted verb of the same name still plays from the bus", function()
		local hap = adapterWith({})
		hap.bind({
			onFeedback = function(fn: any): any
				fn({ type = "commit", path = "/S/B" }) -- no `reason`: not an activation
				return function() end
			end,
		})
		expect(hap.diagnostics().plays).toBe(1)
		hap.dispose()
	end)

	it("DEFAULT OFF: a disabled adapter decorates nothing and builds nothing", function()
		local button = fakeButton("commit")
		local built: { any } = {}
		local hap = hapticsLib.new({
			instanceNew = function(): any
				table.insert(built, {})
				return {}
			end,
			inputService = false,
			hapticService = false,
			parent = false,
		})
		expect(hap.isEnabled()).toBe(false)
		hap.attachButtons(fakeRoot({ button }))
		expect(button.PressHapticEffect).toBe(nil)
		expect(#built).toBe(0)
		expect(hap.diagnostics().constructions).toBe(0)
		hap.dispose()
	end)

	it("the verb map is TOTAL over the taxonomy, so a thirteenth verb is a visible gap", function()
		expect(#hapticsLib.unmappedVerbs()).toBe(0)
		expect(#hapticsLib.strayVerbs()).toBe(0)
	end)

	it("the two ends of the attribute channel spell it the SAME", function()
		-- a string-keyed channel whose writer and reader drift apart fails as
		-- SILENCE — every button falls back to the generic press and nothing errors
		-- — so the only place this can be caught is here
		local body = fs.readFile("src/client/screen_target.luau")
		expect(string.find(body, `"{hapticsLib.ACTIVATION_ATTRIBUTE}"`, 1, true) ~= nil).toBeTruthy()
	end)
end)

-- ===========================================================================
-- THE SHOWCASE FIXTURE
-- ===========================================================================
--
-- Every gap closure ships its demo, and a demo nobody drives is a screenshot.
-- These cases drive `examples/gallery/scenarios/sensory_feedback` the way a
-- player does — real presses through the adapter's activate path — and hold it
-- under every shipped theme, because STUDIO NEUTRAL IS NOT EVIDENCE ON ITS OWN:
-- it reserves no chrome, so a surface measured only there has slack no shipped
-- package gives it, and Pixel Quest and Parchment have each broken a layout
-- Neutral survived.
describe("the showcase fixture drives the real thing", function()
	local snapshot = require("../src/themes/snapshot") :: any
	local scenario = require("../examples/gallery/scenarios/sensory_feedback") :: any

	local PACKAGES = {
		"glossy_mobile",
		"glossy_touch",
		"pixel_quest",
		"fantasy_ornate",
		"scifi_hud",
		"compact_pointer",
		"classic_desktop",
		"fantasy_parchment",
	}
	-- the narrowest supported viewport in BOTH orientations plus a desktop: two
	-- wrapping chip rows fail on width, and landscape-only defects are how the
	-- 2026-08-12 round's B5 survived a portrait-only capture set
	local VIEWS = { { w = 320, h = 640 }, { w = 640, h = 320 }, { w = 1232, h = 1067 } }

	local function mountUnder(pkgName: string?, view: any): (any, any)
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = view.w, h = view.h })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = LuauUI.newPresenter(core, env, adapter, system)
		if pkgName ~= nil then
			env:set(
				"themeMetrics",
				snapshot.resolve((require)(`../examples/themes/{pkgName}`).build(LuauUI.themes), nil, {})
			)
		end
		local built = scenario.build({
			LuauUI = LuauUI,
			core = core,
			env = env,
			actionSystem = system,
			presenter = pres,
		})
		built.handle = pres.present(built.screen, built.present)
		for _ = 1, 3 do
			pres.refresh()
		end
		return { adapter = adapter, core = core, pres = pres }, built
	end

	it("the sensation column is the SHIPPED map, not a story about it", function()
		-- the fixture may not require a client module, so its table is written out
		-- — which is exactly the shape that drifts into fiction. This is the pin.
		for _, row in scenario.sensation do
			local expected = hapticsLib.pressEffectFor(row.verb)
			expect(`{row.verb}:{tostring(row.effect)}`).toBe(`{row.verb}:{tostring(expected)}`)
		end
		-- ...and it covers every verb the fixture can actually produce
		for _, entry in scenario.declared do
			if entry.activation ~= nil and entry.activation ~= feedbackLib.ACTIVATION_SILENT then
				local found = false
				for _, row in scenario.sensation do
					if row.verb == entry.activation then
						found = true
					end
				end
				expect(`{entry.activation} is explained:{found}`).toBe(`{entry.activation} is explained:true`)
			end
		end
	end)

	it("pressing the five leaves writes four lines and Mute writes none", function()
		local w, built = mountUnder(nil, { w = 390, h = 844 })
		for _, entry in scenario.declared do
			w.adapter.tap(`/SensoryFeedback/Page/Leaves/LeafRow/{entry.id}`)
		end
		local log = built.logText:get()
		expect(built.reported:get()).toBe(4)
		for _, verb in { "commit", "reject", "select", "activate" } do
			expect(`{verb} logged:{string.find(log, verb, 1, true) ~= nil}`).toBe(`{verb} logged:true`)
		end
		expect(string.find(log, "Mute", 1, true)).toBeNil()
		built.dispose()
	end)

	it("the CASCADE panel: three controls, one declaration, one verb", function()
		local w, built = mountUnder(nil, { w = 390, h = 844 })
		local base = "/SensoryFeedback/Page/Cascade/CascadeRow"
		for _, path in { `{base}/First`, `{base}/Nested/Second`, `{base}/Nested/Third` } do
			w.adapter.tap(path)
		end
		expect(built.reported:get()).toBe(3)
		local _, count = string.gsub(built.logText:get(), "pickup", "")
		expect(count).toBe(3)
		built.dispose()
	end)

	it("a NON-activation event on the same surface writes no line", function()
		-- the fixture's subscriber filters on `reason`, and a filter nothing
		-- exercises is decoration: the showcase presents toasts and modals on the
		-- same presenter, and every one of their verbs would otherwise land in this
		-- surface's press log. Emitted through the presenter's own registration
		-- point, which is the seam a game's session code uses.
		local w, built = mountUnder(nil, { w = 390, h = 844 })
		w.pres.emitFeedback({ type = "commit", path = "/SensoryFeedback/Page/Leaves/LeafRow/Buy" })
		expect(built.reported:get()).toBe(0)
		expect(built.logText:get()).toBe(scenario.copy.logEmpty)
		-- ...and a real press on the same path still does
		w.adapter.tap("/SensoryFeedback/Page/Leaves/LeafRow/Buy")
		expect(built.reported:get()).toBe(1)
		built.dispose()
	end)

	it("a press on ANOTHER surface of the same presenter writes no line", function()
		-- the showcase presents its chrome and its demo on ONE presenter, so every
		-- chip-strip press is an `activation` event this subscriber sees. Without
		-- the path filter the fixture would count the picker's own buttons, which
		-- is the log lying about what the player just pressed.
		local w, built = mountUnder(nil, { w = 390, h = 844 })
		w.pres.present(UI.Screen({ id = "Chrome", children = { UI.Button({ id = "Pick", label = "p" }) } }))
		w.adapter.tap("/Chrome/Pick")
		expect(built.reported:get()).toBe(0)
		w.adapter.tap("/SensoryFeedback/Page/Leaves/LeafRow/Buy")
		expect(built.reported:get()).toBe(1)
		built.dispose()
	end)

	it("no diagnostic, in any package, at any of the three viewports", function()
		local problems: { string } = {}
		for _, pkgName in { false, table.unpack(PACKAGES) } do
			for _, view in VIEWS do
				local name = if pkgName == false then "flat" else tostring(pkgName)
				local w, built = mountUnder(if pkgName == false then nil else tostring(pkgName), view)
				local parts: { string } = {}
				for _, f in built.handle.controller.diagnostics() do
					table.insert(parts, `{f.node}: {f.issue}`)
				end
				if #parts > 0 then
					table.insert(problems, `  {name} at {view.w}x{view.h}: {table.concat(parts, " | ")}`)
				end
				expect(w.core:lastError()).toBeNil()
				built.dispose()
			end
		end
		if #problems > 0 then
			error(
				`sensory_feedback reports diagnostics under {#problems} package/viewport pair(s):\n`
					.. table.concat(problems, "\n"),
				0
			)
		end
	end)

	it("...and no two chips in a row ever overlap, in any package, at any viewport", function()
		local ROW = "/SensoryFeedback/Page/Leaves/LeafRow"
		for _, pkgName in { false, table.unpack(PACKAGES) } do
			for _, view in VIEWS do
				local name = if pkgName == false then "flat" else tostring(pkgName)
				local w, built = mountUnder(if pkgName == false then nil else tostring(pkgName), view)
				local placed: { any } = {}
				for _, entry in scenario.declared do
					local node = w.adapter.node(`{ROW}/{entry.id}`)
					if node == nil or node.rect == nil then
						error(`{name} at {view.w}x{view.h}: chip {entry.id} was never placed`, 0)
					end
					local r = node.rect
					for _, other in placed do
						if
							r.x < other.r.x + other.r.w
							and other.r.x < r.x + r.w
							and r.y < other.r.y + other.r.h
							and other.r.y < r.y + r.h
						then
							error(
								`{name} at {view.w}x{view.h}: chip {entry.id} [{r.x},{r.y} {r.w}x{r.h}] overlaps `
									.. `{other.id} [{other.r.x},{other.r.y} {other.r.w}x{other.r.h}]`,
								0
							)
						end
					end
					table.insert(placed, { id = entry.id, r = r })
				end
				built.dispose()
			end
		end
	end)
end)

-- ===========================================================================
-- THE DEMO CAN ACTUALLY PLAY THEM, AND SAYS WHICH OF THREE THINGS HAPPENED
-- (NM-G3, director's physical pass 2026-08-16: "none of the haptics in sensory
-- feedback work")
-- ===========================================================================
--
-- WHY NOTHING PLAYED, and it was never the engine choice. `src/client/haptics`
-- already uses `HapticEffect` rather than the superseded `HapticService:SetMotor`
-- — the fixture simply never constructed it. It subscribed the bus for a LOG and
-- printed the adapter's published map beside it, captioned "what an opt-in
-- adapter WOULD play". And a `bind(presenter)` alone would still have played
-- nothing here: `onEvent` drops every event carrying `reason = "activation"`,
-- which is every event this surface produces, because a control's press belongs
-- to the ENGINE through `GuiButton.PressHapticEffect`. So the route that makes a
-- press felt is `attachButtons(root)`, which needs a real Instance — the one
-- thing an engine-free fixture had no way to reach.
--
-- WHAT IS TESTABLE HERE AND WHAT IS NOT. A headless target cannot fire a motor
-- and cannot read whether one fired, so nothing below asserts a sensation. What
-- it asserts is the DECISION and the REPORTED STATE — and above all that the
-- three answers stay three. docs/lessons/capability-probes-must-be-tri-state.md
-- is about exactly this instrument shape, and this repository has now shipped a
-- boolean that published a false platform fact twice; `refused` and
-- `undetermined` are therefore separate states with separate sentences, and a
-- mutation that merges them reddens `the three answers stay three`.
describe("the sensory-feedback demo installs the real adapter and reports a TRI-STATE", function()
	local scenario = require("../examples/gallery/scenarios/sensory_feedback") :: any

	-- ---- a scripted engine, small enough to read in one screen ------------
	local function fakeSignal(): any
		local subs: { (any) -> () } = {}
		local signal: any = {}
		function signal:Connect(fn: (any) -> ()): any
			table.insert(subs, fn)
			return {
				Disconnect = function()
					local i = table.find(subs, fn)
					if i ~= nil then
						table.remove(subs, i)
					end
				end,
			}
		end
		return signal
	end

	local function fakeEnums(): any
		local set: any = {}
		for _, name in hapticsLib.EFFECT_TYPES do
			set[name] = `Enum.HapticEffectType.{name}`
		end
		return { HapticEffectType = set }
	end

	local function fakeInputService(pads: { any }): any
		local uis: any = {
			GamepadConnected = fakeSignal(),
			GamepadDisconnected = fakeSignal(),
			LastInputTypeChanged = fakeSignal(),
			pads = pads,
		}
		function uis:GetConnectedGamepads(): { any }
			return uis.pads
		end
		return uis
	end

	-- `GetAttribute` IS NOT OPTIONAL ON THIS FAKE, and leaving it off cost a
	-- debugging round: the adapter reads the renderer's declared-verb attribute
	-- through `guard`, so a button that cannot answer records a caught error in
	-- `diagnostics().lastError` — which then overwrote the engine's own
	-- construction words that the refusal line is supposed to keep. A fake that
	-- fails where the real class succeeds manufactures its own findings.
	local function fakeButton(name: string): any
		local inst: any = { Name = name, PressHapticEffect = nil }
		function inst:IsA(className: string): boolean
			return className == "GuiButton"
		end
		function inst:GetAttribute(_name: string): any
			return nil
		end
		return inst
	end

	-- the instances are counted off the instances, never off the adapter's own
	-- counters (the `pooled = 0` while fifteen sat in Workspace lesson)
	local function fakeEngine(opts: any): any
		local made: { any } = {}
		local rootChildren: { any } = {}
		for i = 1, (opts.buttons or 3) do
			table.insert(rootChildren, fakeButton(`B{i}`))
		end
		local root: any = { Name = "PlayerGui", DescendantAdded = fakeSignal(), Destroying = fakeSignal() }
		function root:IsA(): boolean
			return false
		end
		function root:GetDescendants(): { any }
			return rootChildren
		end
		local instanceNew = function(className: string): any
			if opts.constructionError ~= nil then
				error(opts.constructionError, 0)
			end
			local effect: any = { ClassName = className, Parent = nil, destroyed = false }
			function effect:Play() end
			function effect:Stop() end
			function effect:Destroy()
				effect.destroyed = true
				effect.Parent = nil
			end
			table.insert(made, effect)
			return effect
		end
		return {
			root = root,
			buttons = rootChildren,
			effects = made,
			live = function(): number
				local n = 0
				for _, e in made do
					if not e.destroyed then
						n += 1
					end
				end
				return n
			end,
			overrides = {
				module = hapticsLib,
				root = root,
				options = {
					instanceNew = instanceNew,
					inputService = fakeInputService(opts.pads or {}),
					hapticService = {
						IsVibrationSupported = function(_self: any, _pad: any): any
							return opts.vibration
						end,
					},
					enums = fakeEnums(),
					parent = { Name = "Workspace" },
				},
			},
		}
	end

	local function mountDemo(): (any, any)
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 390, h = 844 })
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = LuauUI.newPresenter(core, env, adapter, system)
		local built =
			scenario.build({ LuauUI = LuauUI, core = core, env = env, actionSystem = system, presenter = pres })
		built.handle = pres.present(built.screen, built.present)
		for _ = 1, 3 do
			pres.refresh()
		end
		return { adapter = adapter, core = core, pres = pres }, built
	end

	-- ---- the switch is the demo's decision, and it starts OFF -------------
	it("DEFAULT OFF: the demo constructs no adapter and claims nothing about the device", function()
		local w, built = mountDemo()
		expect(built.playHaptics:get()).toBe(false)
		expect(built.hapticsAdapter()).toBeNil()
		expect(built.hapticsState:get()).toBe("off")
		-- the on-screen line says OFF, and says nothing whatever about the platform
		local line = built.hapticsHeadline:get() .. " " .. built.hapticsDetail:get()
		for _, forbidden in { "cannot", "supported", "refus" } do
			expect(`off line mentions '{forbidden}':{string.find(string.lower(line), forbidden, 1, true) ~= nil}`).toBe(
				`off line mentions '{forbidden}':false`
			)
		end
		expect(w.core:lastError()).toBeNil()
		built.dispose()
	end)

	it("the switch is reachable as a control, and the demo says the LIBRARY is still default-off", function()
		local w, built = mountDemo()
		local node = w.adapter.node("/SensoryFeedback/Page/Play/PlayHaptics")
		expect(node ~= nil).toBe(true)
		expect(node.class).toBe("Toggle")
		-- the note is on screen, not only in a comment: the demo opting in is a
		-- different decision from the library opting in
		local note = w.adapter.node("/SensoryFeedback/Page/Play/PlayNote")
		expect(note ~= nil).toBe(true)
		expect(string.find(string.lower(tostring(note.props.text)), "default", 1, true) ~= nil).toBe(true)
		built.dispose()
	end)

	-- ---- the three answers -------------------------------------------------
	it("a connected pad that answers NO is a platform refusal", function()
		local engine = fakeEngine({ pads = { "Gamepad1" }, vibration = false })
		local _, built = mountDemo()
		built.useScriptedEngine(engine.overrides)
		built.playHaptics:set(true)
		expect(built.hapticsState:get()).toBe("refused")
		expect(built.hapticsDetail:get()).toBe(built.hapticsDetail:get())
		expect(string.find(built.hapticsDetail:get(), "unsupported", 1, true) ~= nil).toBe(true)
		built.dispose()
	end)

	it("NO PAD is NOT a refusal — it is could-not-determine, and it says the effects are installed", function()
		local engine = fakeEngine({ pads = {}, vibration = true })
		local _, built = mountDemo()
		built.useScriptedEngine(engine.overrides)
		built.playHaptics:set(true)
		expect(built.hapticsState:get()).toBe("undetermined")
		-- the press effects DID go out, which is why "nothing happened" and "this
		-- device cannot" are not the same sentence
		expect(built.hapticsAdapter().diagnostics().decorated > 0).toBe(true)
		expect(string.find(built.hapticsDetail:get(), "unknown", 1, true) ~= nil).toBe(true)
		built.dispose()
	end)

	it("a supported pad with press effects out says REQUESTED, never PLAYED", function()
		local engine = fakeEngine({ pads = { "Gamepad1" }, vibration = true })
		local _, built = mountDemo()
		built.useScriptedEngine(engine.overrides)
		built.playHaptics:set(true)
		expect(built.hapticsState:get()).toBe("requested")
		local line = string.lower(built.hapticsHeadline:get() .. " " .. built.hapticsDetail:get())
		expect(`says requested:{string.find(line, "requested", 1, true) ~= nil}`).toBe("says requested:true")
		expect(`claims played:{string.find(line, "played", 1, true) ~= nil}`).toBe("claims played:false")
		-- ...and it says who has to close the gap
		expect(`asks for a human:{string.find(line, "human", 1, true) ~= nil}`).toBe("asks for a human:true")
		built.dispose()
	end)

	it("a client that cannot build the class is a refusal, and the engine's own words are KEPT", function()
		local engine = fakeEngine({
			pads = { "Gamepad1" },
			vibration = true,
			constructionError = 'Unable to create an Instance of type "HapticEffect"',
		})
		local _, built = mountDemo()
		built.useScriptedEngine(engine.overrides)
		built.playHaptics:set(true)
		expect(built.hapticsState:get()).toBe("refused")
		expect(string.find(built.hapticsDetail:get(), "absent", 1, true) ~= nil).toBe(true)
		expect(string.find(built.hapticsDetail:get(), "Unable to create", 1, true) ~= nil).toBe(true)
		built.dispose()
	end)

	it("a refusal for some OTHER reason is `blocked`, and blocked is could-not-tell", function()
		local engine = fakeEngine({
			pads = { "Gamepad1" },
			vibration = true,
			constructionError = "The current thread cannot create an Instance (lacking capability)",
		})
		local _, built = mountDemo()
		built.useScriptedEngine(engine.overrides)
		built.playHaptics:set(true)
		expect(built.hapticsState:get()).toBe("undetermined")
		expect(string.find(built.hapticsDetail:get(), "blocked", 1, true) ~= nil).toBe(true)
		built.dispose()
	end)

	it("an adapter that could not be LOADED is undetermined, not a platform claim", function()
		local _, built = mountDemo()
		built.useScriptedEngine({ moduleError = "LuauUI.client.haptics is not replicated here" })
		built.playHaptics:set(true)
		expect(built.hapticsState:get()).toBe("undetermined")
		expect(string.find(built.hapticsDetail:get(), "not replicated", 1, true) ~= nil).toBe(true)
		built.dispose()
	end)

	-- THE ANTI-COLLAPSE CASE. This is the one that reddens when somebody merges
	-- "no" with "could not tell" — a boolean would satisfy every case above it by
	-- reporting one of the two states for all five inputs.
	it("the three answers stay THREE: three states, three headlines, no overlap", function()
		local seen: { [string]: string } = {}
		local INPUTS = {
			{ name = "supported pad", facts = { adapterLoaded = true, support = "supported", decorated = 3 } },
			{ name = "pad says no", facts = { adapterLoaded = true, support = "unsupported", decorated = 0 } },
			{ name = "no pad at all", facts = { adapterLoaded = true, support = "unknown", decorated = 3 } },
			{ name = "class absent", facts = { adapterLoaded = true, support = "absent", decorated = 0 } },
			{ name = "blocked", facts = { adapterLoaded = true, support = "blocked", decorated = 0 } },
			{ name = "no module", facts = { adapterLoaded = false, moduleError = "no module", decorated = 0 } },
			{
				name = "no root",
				facts = { adapterLoaded = true, support = "unknown", decorated = 0, rootError = "no root" },
			},
		}
		local states: { [string]: boolean } = {}
		for _, input in INPUTS do
			local verdict = scenario.classify(input.facts)
			states[verdict.state] = true
			local prior = seen[verdict.headline]
			-- headlines may repeat WITHIN a state (two ways to be refused read the
			-- same); they may never be shared ACROSS states
			for otherHeadline, otherState in seen do
				if otherHeadline == verdict.headline then
					expect(`{input.name}: '{verdict.headline}' also means {otherState}`).toBe(
						`{input.name}: '{verdict.headline}' also means {verdict.state}`
					)
				end
			end
			seen[verdict.headline] = verdict.state
			expect(`{input.name} detail is empty:{verdict.detail == ""}`).toBe(`{input.name} detail is empty:false`)
			local _ = prior
		end
		expect(
			`three states reachable:{states.requested == true and states.refused == true and states.undetermined == true}`
		).toBe("three states reachable:true")
	end)

	-- ---- the switch is reversible, and it takes its instances with it ------
	it("switching it off destroys every effect and takes the claim back", function()
		local engine = fakeEngine({ pads = { "Gamepad1" }, vibration = true })
		local _, built = mountDemo()
		built.useScriptedEngine(engine.overrides)
		built.playHaptics:set(true)
		expect(engine.live() > 0).toBe(true)
		for _, button in engine.buttons do
			expect(`{button.Name} carries an effect:{button.PressHapticEffect ~= nil}`).toBe(
				`{button.Name} carries an effect:true`
			)
		end
		built.playHaptics:set(false)
		expect(engine.live()).toBe(0)
		expect(built.hapticsState:get()).toBe("off")
		expect(built.hapticsAdapter()).toBeNil()
		for _, button in engine.buttons do
			expect(`{button.Name} still carries one:{button.PressHapticEffect ~= nil}`).toBe(
				`{button.Name} still carries one:false`
			)
		end
		built.dispose()
	end)

	it("disposing the fixture with the switch ON leaves no effect behind", function()
		local engine = fakeEngine({ pads = { "Gamepad1" }, vibration = true })
		local _, built = mountDemo()
		built.useScriptedEngine(engine.overrides)
		built.playHaptics:set(true)
		expect(engine.live() > 0).toBe(true)
		built.dispose()
		expect(engine.live()).toBe(0)
	end)

	-- ---- and the SHIPPED default path, with nothing injected ---------------
	-- The seam's default is what both hosts run, so it is the path that has to be
	-- exercised rather than described. Under Lune the adapter module really does
	-- resolve; the UI root really does not (there is no engine), and the demo
	-- says exactly that instead of reporting a platform verdict it cannot have.
	it("with NOTHING injected it still installs, and names what it could not reach", function()
		local w, built = mountDemo()
		built.playHaptics:set(true)
		expect(built.hapticsAdapter() ~= nil).toBe(true)
		expect(built.hapticsState:get()).toBe("undetermined")
		expect(built.hapticsAdapter().diagnostics().decorated).toBe(0)
		expect(w.core:lastError()).toBeNil()
		built.playHaptics:set(false)
		built.dispose()
	end)
end)
