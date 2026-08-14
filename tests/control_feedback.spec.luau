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
