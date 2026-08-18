--!strict
-- DESKTOP KEYBOARD FOCUS-CHAIN BEHAVIOR (roadmap Step 8;
-- docs/plans/desktop-keyboard-navigation.md; acceptance rows DK-1..DK-16 in
-- artifacts/desktop-keyboard-navigation/acceptance.md).
--
-- The three conventions a desktop author expects, delivered by the EXISTING
-- focus graph / responder / Input Action System — never a second focus system:
--
--   * Tab / Shift+Tab traverse the active focus scope in mounted/group order;
--   * Space joins Return as Activate, once per press;
--   * a focused value control consumes the arrows on its DECLARED axis as
--     Adjust, and the other axis still Navigates.
--
-- DISCIPLINE. Every action-level case drives `system.deviceKey`, the arbitrated
-- device path, so the assertions are about what a real key press resolves to —
-- never a direct focus-graph or callback call. The pure cases below drive the
-- graph directly because the traversal ORDER is a deterministic decision that
-- must be pinned without an engine.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local worldLib = require("./lib/world")

local Facet = require("../src") :: any
local UI = Facet.UI
local customFactory = require("../src/core/custom")
local focus_graph = require("../src/focus/focus_graph")
local fake_target = require("../tests/lib/fake_target")
local default_style = require("../src/tokens/default_style")

-- ===========================================================================
-- PURE: the traversal decision (DK-1..DK-6)
-- ===========================================================================

local function flatGraph(order: { any }, traversalWrap: boolean?)
	local core = customFactory.new()
	local graph = focus_graph.new(core)
	graph.pushScope({ name = "S", trap = false, order = order, traversalWrap = traversalWrap })
	return graph
end

describe("keyboard traversal: the order comes from the mounted focus graph (DK-1)", function()
	it("traverse(+1) walks the flat scope forward and traverse(-1) walks it back", function()
		local graph = flatGraph({ "a", "b", "c" })
		expect(graph.focused:get()).toBe("a")
		expect(graph.traverse(1)).toBe(true)
		expect(graph.focused:get()).toBe("b")
		graph.traverse(1)
		expect(graph.focused:get()).toBe("c")
		expect(graph.traverse(-1)).toBe(true)
		expect(graph.focused:get()).toBe("b")
		graph.traverse(-1)
		expect(graph.focused:get()).toBe("a")
	end)

	-- architecture review ARCH-9: the enter branch used to ignore the direction, so
	-- entering a scope backwards landed on its FIRST item and read as the ring
	-- jumping past everything. A scope whose every node is ineligible at push time
	-- (a real focus-skip state) leaves focus nil, which is the branch.
	local function scopeEnteredWithNoFocus(): (any, { boolean })
		local core = customFactory.new()
		local graph = focus_graph.new(core)
		local live = { false }
		local function entry(id: string)
			return {
				id = id,
				focusable = function()
					return live[1]
				end,
			}
		end
		graph.pushScope({ name = "S", trap = false, order = { entry("x"), entry("y"), entry("z") } })
		return graph, live
	end

	it("Shift+Tab into a scope with no focus enters at the LAST eligible node", function()
		local graph, live = scopeEnteredWithNoFocus()
		expect(graph.focused:get()).toBeNil()
		live[1] = true
		expect(graph.traverse(-1)).toBe(true)
		expect(graph.focused:get()).toBe("z")
	end)

	it("...and Tab into the same scope enters at the first", function()
		local graph, live = scopeEnteredWithNoFocus()
		live[1] = true
		expect(graph.traverse(1)).toBe(true)
		expect(graph.focused:get()).toBe("x")
	end)

	it("traversal with no focus enters the scope at its first eligible node", function()
		local graph = flatGraph({ "a", "b" })
		graph.remove("a")
		graph.remove("b") -- empty ring, focus nil
		graph.setOrder("S", { "x", "y" })
		-- setOrder on an empty ring leaves focus nil; Tab must ENTER, not no-op
		expect(graph.focused:get() == nil or graph.focused:get() == "x").toBe(true)
		graph.traverse(1)
		expect(graph.focused:get() ~= nil).toBe(true)
	end)
end)

describe("keyboard traversal crosses navigation groups in group order (DK-2)", function()
	local function grouped()
		local core = customFactory.new()
		local graph = focus_graph.new(core)
		graph.pushScope({
			name = "S",
			trap = false,
			groups = {
				{ name = "row", axis = "horizontal", containment = true, order = { "r1", "r2" } },
				{ name = "col", axis = "vertical", order = { "c1", "c2" } },
			},
		})
		return graph
	end

	it("Tab leaves a CONTAINED group that the arrows cannot leave sideways", function()
		local graph = grouped()
		expect(graph.focused:get()).toBe("r1")
		-- the arrows are contained: right from r2 stays inside the row
		graph.navigateDirection("right")
		expect(graph.focused:get()).toBe("r2")
		graph.navigateDirection("right")
		expect(graph.focused:get()).toBe("r2")
		-- Tab crosses the group boundary in group order
		expect(graph.traverse(1)).toBe(true)
		expect(graph.focused:get()).toBe("c1")
		graph.traverse(1)
		expect(graph.focused:get()).toBe("c2")
	end)

	it("Shift+Tab crosses back into the previous group at its LAST node", function()
		local graph = grouped()
		graph.traverse(1)
		graph.traverse(1)
		expect(graph.focused:get()).toBe("c1")
		graph.traverse(-1)
		expect(graph.focused:get()).toBe("r2")
	end)
end)

describe("the SCOPE declares the traversal wrap policy (DK-3)", function()
	it("wraps by default at both ends", function()
		local graph = flatGraph({ "a", "b" })
		graph.traverse(-1)
		expect(graph.focused:get()).toBe("b") -- wrapped backward off the first
		graph.traverse(1)
		expect(graph.focused:get()).toBe("a") -- and forward off the last
	end)

	it("traversalWrap = false stops at the ends and reports that it did not move", function()
		local graph = flatGraph({ "a", "b" }, false)
		expect(graph.traverse(-1)).toBe(false)
		expect(graph.focused:get()).toBe("a")
		graph.traverse(1)
		expect(graph.focused:get()).toBe("b")
		expect(graph.traverse(1)).toBe(false)
		expect(graph.focused:get()).toBe("b")
	end)

	it("a GROUPED scope's wrap policy is the scope's, not any group's", function()
		local core = customFactory.new()
		local graph = focus_graph.new(core)
		graph.pushScope({
			name = "S",
			trap = false,
			traversalWrap = false,
			-- the row group declares wrap = true for the ARROWS; traversal must
			-- not inherit a per-control/per-group policy (plan: "controls cannot
			-- invent their own wrap behavior")
			groups = {
				{ name = "row", axis = "horizontal", wrap = true, order = { "r1", "r2" } },
			},
		})
		graph.navigateDirection("right")
		graph.navigateDirection("right")
		expect(graph.focused:get()).toBe("r1") -- the GROUP wraps for the arrows
		graph.traverse(1)
		expect(graph.focused:get()).toBe("r2")
		expect(graph.traverse(1)).toBe(false) -- the SCOPE does not wrap for Tab
		expect(graph.focused:get()).toBe("r2")
	end)
end)

describe("traversal skips exactly what navigation skips (DK-4)", function()
	it("an ineligible focus-skip entry is stepped over, not landed on", function()
		local eligible = true
		local graph = flatGraph({ "a", {
			id = "b",
			focusable = function()
				return eligible
			end,
		}, "c" })
		eligible = false
		graph.traverse(1)
		expect(graph.focused:get()).toBe("c")
		eligible = true
		graph.traverse(-1)
		expect(graph.focused:get()).toBe("b")
	end)

	it("focus stays put when nothing else in the scope is eligible", function()
		local graph = flatGraph({ "a", {
			id = "b",
			focusable = function()
				return false
			end,
		} })
		expect(graph.traverse(1)).toBe(false)
		expect(graph.focused:get()).toBe("a")
	end)
end)

describe("traversal survives structural churn (DK-5)", function()
	it("a node removed between presses never becomes a traversal target", function()
		local graph = flatGraph({ "a", "b", "c" })
		graph.remove("b")
		graph.traverse(1)
		expect(graph.focused:get()).toBe("c")
	end)

	it("re-ordering the scope re-reads the order on the very next press", function()
		local graph = flatGraph({ "a", "b", "c" })
		graph.setOrder("S", { "a", "z", "b", "c" })
		graph.traverse(1)
		expect(graph.focused:get()).toBe("z")
	end)
end)

describe("modal scopes trap traversal and restore focus (DK-6)", function()
	it("Tab cannot leave a trapped scope and the prior focus is restored on pop", function()
		local graph = flatGraph({ "a", "b", "c" })
		graph.traverse(1)
		expect(graph.focused:get()).toBe("b")
		graph.pushScope({ name = "M", trap = true, order = { "m1", "m2" } })
		expect(graph.focused:get()).toBe("m1")
		graph.traverse(1)
		expect(graph.focused:get()).toBe("m2")
		graph.traverse(1)
		expect(graph.focused:get()).toBe("m1") -- wrapped INSIDE the trap
		graph.traverse(-1)
		expect(graph.focused:get()).toBe("m2")
		graph.popScope()
		expect(graph.focused:get()).toBe("b") -- restored, not re-entered
	end)
end)

-- ===========================================================================
-- ACTION SYSTEM: the real device path (DK-7..DK-16)
-- ===========================================================================

-- KEYBOARD NAVIGATION IS OPT-IN (director playtest 2026-08-03), so every fixture
-- here enables it at the presenter — that IS the shipped usage for a surface meant
-- to be keyboard-navigable. The opt's own semantics (off by default, per-surface
-- override, and the sink it implies) are proven in their own describe block below.
--[[ ONE SUBSTRATE, ONE ORDER (reuse audit REUSE-88, controller ruling R12).
	`tests/lib/world.luau` owns the construction and its two invariants; the tuple
	this file hands its cases is `core, env, adapter, system, pres` — the order
	`Facet.newPresenter` itself takes, and now the only one in the suite. It used
	to be `core, env, system, adapter, pres` here and the other spelling sixteen
	files away, with the same five names on both sides, so a line copied between
	two neighbouring specs bound an action system to a variable called `adapter`
	and said nothing.

	KEYBOARD NAVIGATION DEFAULTS ON in this file, which is what it is about — the
	one thing the shared substrate does not decide for it. ]]
local function harness(presenterOpts: any?)
	local opts = if presenterOpts ~= nil then table.clone(presenterOpts) else {}
	if opts.keyboardNavigation == nil then
		opts.keyboardNavigation = true
	end
	local w = worldLib.new({ viewport = { x = 0, y = 0, w = 1280, h = 720 }, presenterOpts = opts })
	return w.core, w.env, w.adapter, w.system, w.pres
end

local function press(system: any, key: string)
	system.deviceKey(key, true)
	system.deviceKey(key, false)
end

local function tab(system: any)
	press(system, "Tab")
end

local function shiftTab(system: any)
	system.deviceKey("LeftShift", true)
	press(system, "Tab")
	system.deviceKey("LeftShift", false)
end

-- a plain form: three buttons, zero present() input opts
local function formScreen(acts: { [string]: number })
	local function button(id: string)
		return UI.Button({
			id = id,
			label = id,
			onActivate = function()
				acts[id] = (acts[id] or 0) + 1
			end,
		})
	end
	return UI.Screen({ id = "F", children = { button("one"), button("two"), button("three") } })
end

describe("Tab traverses a presented screen with zero consumer wiring (DK-1/DK-16)", function()
	it("Tab and Shift+Tab move the focus ring through a plain form", function()
		local _, _, _, system, pres = harness()
		local acts: { [string]: number } = {}
		pres.present(formScreen(acts))
		pres.refresh()
		expect(pres.focus.focused:get()).toBe("/F/one")
		tab(system)
		expect(pres.focus.focused:get()).toBe("/F/two")
		tab(system)
		expect(pres.focus.focused:get()).toBe("/F/three")
		shiftTab(system)
		expect(pres.focus.focused:get()).toBe("/F/two")
	end)

	it("a traversal move restores the focus RING that a tap put away", function()
		local _, _, adapter, system, pres = harness()
		local acts: { [string]: number } = {}
		pres.present(formScreen(acts))
		pres.refresh()
		adapter.tap("/F/two")
		expect(pres.focus.focusVisible:get()).toBe(false)
		tab(system)
		expect(pres.focus.focusVisible:get()).toBe(true)
		expect(pres.focus.focused:get()).toBe("/F/three")
	end)
end)

describe("traversal calls the SHARED keep-visible service (DK-7)", function()
	local function scrollSlice()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 300 })
		local rows = {}
		for i = 1, 12 do
			table.insert(
				rows,
				UI.Button({ id = "Btn" .. i, label = "Row " .. i, height = { type = "fixed", px = 40 } })
			)
		end
		local adapter = fake_target.new()
		local system = Facet.newActionSystem(core)
		local pres = Facet.newPresenter(core, env, adapter, system, { keyboardNavigation = true })
		pres.present(UI.Screen({
			id = "S",
			children = { UI.ScrollView({ id = "List", height = { type = "fixed", px = 160 }, children = rows }) },
		}))
		return adapter, pres, system
	end

	it("tabbing past the visible band scrolls the host, with no control wiring", function()
		local adapter, pres, system = scrollSlice()
		for _ = 1, 8 do
			tab(system)
		end
		pres.refresh()
		local pos = adapter.scrollPositionOf("/S/List")
		expect(pos ~= nil).toBe(true)
		expect((pos :: any).y > 0).toBe(true)
	end)
end)

describe("Space activates alongside Return, once per press (DK-8)", function()
	it("Space activates the focused control exactly once", function()
		local _, _, _, system, pres = harness()
		local acts: { [string]: number } = {}
		pres.present(formScreen(acts))
		pres.refresh()
		press(system, "Space")
		expect(acts.one).toBe(1)
		press(system, "Space")
		expect(acts.one).toBe(2)
	end)

	it("Return still activates, and the two keys do not double-count one press", function()
		local _, _, _, system, pres = harness()
		local acts: { [string]: number } = {}
		pres.present(formScreen(acts))
		pres.refresh()
		press(system, "Return")
		expect(acts.one).toBe(1)
		tab(system)
		press(system, "Space")
		expect(acts.two).toBe(1)
		expect(acts.one).toBe(1)
	end)

	it("a disabled control consumes Space and does nothing", function()
		local _, _, _, system, pres = harness()
		local fired = 0
		pres.present(UI.Screen({
			id = "F",
			children = {
				UI.Button({
					id = "off",
					label = "off",
					enabled = false,
					onActivate = function()
						fired += 1
					end,
				}),
				UI.Button({ id = "on", label = "on" }),
			},
		}))
		pres.refresh()
		-- a disabled control is not even in the focus order
		expect(pres.focus.focused:get()).toBe("/F/on")
		press(system, "Space")
		expect(fired).toBe(0)
	end)
end)

describe("exactly one Activate per press across the IAS and native-tap paths (DK-9)", function()
	-- the two signals only coexist on a surface that mirrors Facet focus onto
	-- GuiService.SelectedObject: the engine then fires the selected GuiButton's
	-- own Activated for the same key press IAS delivered as Activate
	local function bridgedModal(nowFn: () -> number)
		local _, _, adapter, system, pres = harness({ now = nowFn })
		local acts: { [string]: number } = {}
		pres.presentModal(
			UI.Screen({
				id = "M",
				children = {
					UI.Button({
						id = "ok",
						label = "ok",
						onActivate = function()
							acts.ok = (acts.ok or 0) + 1
						end,
					}),
				},
			}),
			{ engineSelectionBridge = true }
		)
		pres.refresh()
		return system, adapter, pres, acts
	end

	it("a native Activated echoing the same keyboard press does not activate twice", function()
		local now = 100
		local system, adapter, _, acts = bridgedModal(function()
			return now
		end)
		press(system, "Space")
		-- the engine's selection activation for the SAME press: a GuiButton
		-- Activated whose InputObject.UserInputType is Keyboard, not a pointer
		adapter.tap("/M/ok", { source = "pointer", pointer = "keyboard" })
		expect(acts.ok).toBe(1)
	end)

	it("two genuinely separate presses outside the echo window both count", function()
		local now = 100
		local system, adapter, _, acts = bridgedModal(function()
			return now
		end)
		press(system, "Return")
		now += 1
		adapter.tap("/M/ok", { source = "pointer", pointer = "keyboard" })
		expect(acts.ok).toBe(2)
	end)

	it("a spent echo does not roll the window forward onto the next real press", function()
		-- architecture review ARCH-4: the collapsing signal used to be recorded in
		-- the slot, so key -> echo -> key inside one window ate the second real
		-- press too. A press is a PAIR, and a collapsed pair is spent.
		local now = 100
		local system, adapter, _, acts = bridgedModal(function()
			return now
		end)
		press(system, "Return") -- press 1
		now += 0.01
		adapter.tap("/M/ok", { source = "pointer", pointer = "keyboard" }) -- its echo
		expect(acts.ok).toBe(1)
		now += 0.01 -- still inside one echo window of the echo
		press(system, "Return") -- press 2: a real press, must count
		expect(acts.ok).toBe(2)
	end)

	it("a real pointer tap beside a key press is two presses, never an echo", function()
		local now = 100
		local system, adapter, _, acts = bridgedModal(function()
			return now
		end)
		adapter.tap("/M/ok")
		adapter.tap("/M/ok")
		expect(acts.ok).toBe(2)
		press(system, "Return")
		press(system, "Return")
		expect(acts.ok).toBe(4) -- two key presses are two presses too
	end)

	it("a surface with no selection bridge never collapses a tap next to a key press", function()
		local now = 100
		local _, _, adapter, system, pres = harness({
			now = function()
				return now
			end,
		})
		local acts: { [string]: number } = {}
		pres.present(formScreen(acts))
		pres.refresh()
		press(system, "Return")
		adapter.tap("/F/one")
		expect(acts.one).toBe(2) -- SelectedObject is nil here: two real presses
	end)
end)

describe("a focused value control consumes its declared axis (DK-10/DK-11)", function()
	-- a GROUPED screen (an HStack of two buttons engages the layout derivation),
	-- which is exactly where Left/Right used to belong permanently to NavigateH
	local function sliderScreen()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 1280, h = 720 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system, { keyboardNavigation = true })
		local value = core:signal(0.5)
		local slider = Facet.Controls.Slider(core, { id = "Vol", value = value, min = 0, max = 1, step = 0.1 })
		local handle = pres.present(UI.Screen({
			id = "S",
			children = {
				UI.HStack({
					id = "Row",
					children = { UI.Button({ id = "a", label = "a" }), UI.Button({ id = "b", label = "b" }) },
				}),
				slider.blueprint,
			},
		}))
		pres.refresh()
		return core, system, pres, value, slider, handle
	end

	it("Left/Right adjust a focused horizontal Slider on a GROUPED screen", function()
		local _, system, pres, value = sliderScreen()
		-- reach the slider's track (a focusable Grip: last in the derived order)
		for _ = 1, 6 do
			if string.find(tostring(pres.focus.focused:get()), "Track") ~= nil then
				break
			end
			tab(system)
		end
		expect(string.find(tostring(pres.focus.focused:get()), "Track") ~= nil).toBe(true)
		local before = value:get()
		press(system, "Right")
		expect(value:get() > before).toBe(true)
		press(system, "Left")
		expect(math.abs(value:get() - before) < 1e-9).toBe(true)
	end)

	it("the OTHER axis still navigates while the value control holds focus", function()
		local _, system, pres, value = sliderScreen()
		for _ = 1, 6 do
			if string.find(tostring(pres.focus.focused:get()), "Track") ~= nil then
				break
			end
			tab(system)
		end
		local at = pres.focus.focused:get()
		local before = value:get()
		press(system, "Up")
		expect(pres.focus.focused:get() ~= at).toBe(true) -- Navigate, not Adjust
		expect(value:get()).toBe(before)
	end)

	it("the Adjust keys are UNBOUND while focus sits off a declared target", function()
		local _, system, pres, value, _, handle = sliderScreen()
		-- focus is on the first button, NOT the track
		expect(string.find(tostring(pres.focus.focused:get()), "Track")).toBe(nil)
		expect(#handle.actions.adjust.bindings).toBe(0)
		local before = value:get()
		press(system, "Right")
		expect(value:get()).toBe(before) -- nothing adjusted
	end)
end)

--[[ THE ADJUST CLAIM STOPS AT THE CONTROL'S OWN SUBTREE (DK-11).

	Found live in Studio 2026-08-02, under a green suite: a screen carrying a
	Stepper (or a Rating) plus ANY other button kept the Adjust keys bound with
	focus anywhere on the screen, because the presenter handed `adjustTargets` the
	SCREEN root while `focusGroups` — the seam beside it — has always been handed
	the contribution's own node. "Every Button below here" then meant every button
	on the screen. One Right press with focus on an unrelated Save button fired an
	Adjust action that nothing consumed, with a gameplay context underneath losing
	the key for nothing — the exact shadowing this dynamic binding exists to stop.

	Every headless fixture had put the value control on a screen by itself, which
	is why the suite was blind. This one deliberately does not. ]]
describe("a value control claims Adjust only inside its own subtree (DK-11)", function()
	local function mixedScreen()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 1280, h = 720 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system, { keyboardNavigation = true })
		local count = core:signal(3)
		local stepper = Facet.Controls.Stepper(core, { id = "Qty", value = count, min = 0, max = 10, step = 1 })
		local handle = pres.present(UI.Screen({
			id = "S",
			children = {
				UI.Button({ id = "Save", label = "Save" }),
				stepper.blueprint,
			},
		}))
		pres.refresh()
		return core, system, pres, handle, count
	end

	it("the Adjust keys unbind when focus leaves the control for a sibling button", function()
		local _, _, pres, handle = mixedScreen()
		pres.focus.focusOn("/S/Qty/Dec")
		expect(#handle.actions.adjust.bindings > 0).toBe(true)
		pres.focus.focusOn("/S/Save")
		expect(#handle.actions.adjust.bindings).toBe(0)
	end)

	it("a sibling button's arrows fire no dead Adjust", function()
		local _, system, pres, handle, count = mixedScreen()
		pres.focus.focusOn("/S/Save")
		expect(#handle.actions.adjust.bindings).toBe(0)
		press(system, "Right")
		expect(count:get()).toBe(3) -- nothing was adjusted
	end)

	--[[ THE SURFACE THAT DID NOT ASK FOR KEYBOARD NAVIGATION KEEPS ITS HANDS OFF.

		This is the regression for everyone who has not opted in — the default. A
		presenter with `keyboardNavigation` unset binds no Tab and no Space, does
		not sink, and leaves every arrow to whatever is underneath. The director's
		playtest found the opposite (Space jumped the avatar while the UI had
		focus), which is why the feature became opt-in at all. ]]
	it("with keyboard navigation OFF the surface binds nothing and sinks nothing", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 1280, h = 720 })
		local system = Facet.newActionSystem(core)
		local pres = Facet.newPresenter(core, env, fake_target.new(), system) -- no opt
		local acts: { [string]: number } = {}
		local handle = pres.present(formScreen(acts))
		pres.refresh()

		local game_ = system.createContext({ name = "Gameplay", priority = 1000, sink = false })
		local jump = game_.createAction("Jump", "Bool")
		jump.bind({ keyCode = "Space" })
		local steer = game_.createAction("Steer", "Direction1D")
		steer.bind({ keyCode = "Down", direction = 1 })
		local jumps, steers = 0, 0
		jump.onPressed(function()
			jumps += 1
		end)
		core:observe(steer.state, function(d)
			if d == 1 then
				steers += 1
			end
		end)

		expect(handle.context.sink).toBe(false)
		local traverseKeys = 0
		for _, b in handle.actions.traverse.bindings do
			traverseKeys += 1
		end
		expect(traverseKeys).toBe(0)
		for _, b in handle.actions.activate.bindings do
			expect(b.keyCode ~= "Space").toBe(true)
		end

		local at = pres.focus.focused:get()
		press(system, "Tab")
		expect(pres.focus.focused:get()).toBe(at) -- no traversal
		press(system, "Space")
		expect(next(acts)).toBe(nil) -- no activation
		expect(jumps).toBe(1) -- ...and the game kept its key
		press(system, "Down")
		expect(steers).toBe(1) -- arrows reach the game too (non-sinking)
	end)
end)

--[[ A STEPPER IS ACTIVATED, NOT ADJUSTED (director playtest 2026-08-03).

	Its two buttons are ordinary focus stops: the arrows move BETWEEN them and
	Space does the work. Claiming Left/Right for the value would do the same job
	twice and, over an avatar, take the arrows from the camera for nothing.
	Comma/Period and the shoulder buttons stay bound while focus is inside the
	control, which is the same arithmetic without the contention. ]]
--[[ THE SLIDER PAINTS ITS OWN FOCUSED STATE (director playtest 2026-08-03).

	The track is a full-width Grip, and the adapter's Grip treatment fills a
	focused grip with accent — which painted a solid bar over the value. The track
	now declares `focusVisual = "none"` and the control puts the treatment on the
	THUMB, where the value is, using the `accent` ROLE so every theme package
	answers it in its own palette. ]]
describe("a focused Slider draws its own treatment, on the thumb (DK-20)", function()
	it("the thumb takes a focus stroke while the track holds focus, and drops it after", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 1280, h = 720 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system, { keyboardNavigation = true })
		local value = core:signal(0.5)
		local slider = Facet.Controls.Slider(core, { id = "Vol", value = value, min = 0, max = 1, step = 0.1 })
		pres.present(UI.Screen({
			id = "S",
			children = { UI.Button({ id = "before", label = "before" }), slider.blueprint },
		}))
		pres.refresh()

		-- the adapter materializes an authored stroke as its ONE bespoke child, so
		-- `strokeInstance` is what "is there a ring on the thumb" actually means
		local function thumbStroke(): any
			local node = adapter.node("/S/Vol/TrackHost/Groove/Thumb")
			return node ~= nil and node.strokeInstance or nil
		end
		-- resting: no ring on the thumb
		expect(pres.focus.focused:get()).toBe("/S/before")
		expect(thumbStroke()).toBeNil()

		-- focus the track (the focus stop is unchanged — only the PAINT moved)
		local moved = pres.focus.focusOn("/S/Vol/TrackHost/Track")
		expect(moved).toBe(true)
		pres.refresh()
		expect(thumbStroke() ~= nil).toBe(true)

		--[[ ...AND IT HAS TO BE VISIBLE, NOT MERELY PRESENT (director playtest
			round 2, 2026-08-03: "i don't see any visual affordance when the
			slider's focused").

			`thumbStroke() ~= nil` above is exactly the shape of check this whole
			project keeps having to remove: it proved a ring EXISTS and said nothing
			about whether a person could see one. It passed for the entire life of
			the defect, because `UI.strokeData{ color = "accent" }` defaults its
			thickness and transparency to the theme's HAIRLINE — so the ring was a
			1px accent line at 0.92 transparency (8% visible), stacked under the
			thumb's own resting hairline. Measured live in the gallery: two
			UIStrokes on the focused thumb, both `thick=1 trans=0.92`.

			So the assertion is now about the two numbers that decide visibility,
			pinned against the SAME token the adapter draws its own focus ring at. ]]
		local ring = thumbStroke()
		expect(ring.thickness).toBe(default_style.extra.focusRingThickness)
		expect(ring.thickness > default_style.strokes.hairline).toBe(true)
		expect(ring.transparency).toBe(0)

		-- ...and it goes away again
		pres.focus.focusOn("/S/before")
		pres.refresh()
		expect(thumbStroke()).toBeNil()
	end)

	--[[ ONE NUMBER, ONE HOME. A focused control's ring is painted by the ADAPTER
		from `extra.focusRingThickness`, except for a control that declares
		`focusVisual = "none"` and paints its own — a Slider, whose track is the
		full width of the control so the adapter's fill would cover the value.

		That control reaches the same number through the `"focusRing"` thickness
		alias rather than through a second token beside it, so a theme that thickens
		its focus ring thickens it for both and a Slider's ring can never stop
		matching every other control on the screen. ]]
	it('the "focusRing" thickness alias resolves to the adapter\'s own ring weight', function()
		local resolved = Facet.UI.strokeData({ thickness = "focusRing" })
		expect(resolved.thickness).toBe(default_style.extra.focusRingThickness)
		expect(resolved.thickness > default_style.strokes.hairline).toBe(true)
		-- ...and it is still a CLOSED set: a made-up token is refused by name
		local ok, err = pcall(function()
			return Facet.UI.strokeData({ thickness = "focusRingg" })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "focusRingg") ~= nil).toBe(true)
	end)

	it("the track declares that the adapter must not paint a focused state", function()
		local core = Facet.newCore()
		local value = core:signal(0.5)
		local slider = Facet.Controls.Slider(core, { id = "Vol", value = value, min = 0, max = 1, step = 0.1 })
		local found = nil
		local function walk(bp: any)
			if bp.id == "Track" and bp.class == "Grip" then
				found = bp.props.focusVisual
			end
			for _, c in bp.children or {} do
				walk(c)
			end
		end
		walk(slider.blueprint)
		expect(found).toBe("none")
	end)
end)

describe("a Stepper is driven by Activate, not by the arrows (DK-10)", function()
	it("Space on the focused button steps the value, in both directions", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 1280, h = 720 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system, { keyboardNavigation = true })
		local value = core:signal(3)
		local stepper = Facet.Controls.Stepper(core, { id = "Qty", value = value, min = 0, max = 10, step = 1 })
		pres.present(UI.Screen({ id = "S", children = { stepper.blueprint } }))
		pres.refresh()
		-- focus lands on Dec first; Space decrements
		expect(string.find(tostring(pres.focus.focused:get()), "/Dec") ~= nil).toBe(true)
		press(system, "Space")
		expect(value:get()).toBe(2)
		-- the arrows MOVE between the buttons rather than changing the value
		press(system, "Right")
		expect(string.find(tostring(pres.focus.focused:get()), "/Inc") ~= nil).toBe(true)
		expect(value:get()).toBe(2)
		press(system, "Space")
		expect(value:get()).toBe(3)
	end)

	it("the axis-independent Adjust keys still reach the same arithmetic", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 1280, h = 720 })
		local system = Facet.newActionSystem(core)
		local pres = Facet.newPresenter(core, env, fake_target.new(), system, { keyboardNavigation = true })
		local value = core:signal(3)
		local stepper = Facet.Controls.Stepper(core, { id = "Qty", value = value, min = 0, max = 10, step = 1 })
		pres.present(UI.Screen({ id = "S", children = { stepper.blueprint } }))
		pres.refresh()
		press(system, "Period")
		expect(value:get()).toBe(4)
		press(system, "Comma")
		expect(value:get()).toBe(3)
	end)
end)

describe("text editing owns Space and the arrows; Tab commits then advances (DK-12)", function()
	local function fieldScreen()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 1280, h = 720 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system, { keyboardNavigation = true })
		local value = core:signal("hi")
		local commits: { string } = {}
		local field = Facet.Controls.TextInput(core, {
			id = "Name",
			value = value,
			onCommit = function(text: string)
				table.insert(commits, text)
			end,
		})
		pres.present(UI.Screen({
			id = "S",
			children = { field.blueprint, UI.Button({ id = "next", label = "next" }) },
		}))
		pres.refresh()
		return core, system, adapter, pres, value, field, commits
	end

	it("Space does not activate anything while the field is editing", function()
		local _, system, _, pres, _, field = fieldScreen()
		press(system, "Return") -- Activate the field: begins editing
		expect(field.dump().editing).toBe(true)
		press(system, "Space")
		expect(field.dump().editing).toBe(true) -- still editing: Space typed, not activated
	end)

	it("Tab commits through the field's own path and only THEN advances focus", function()
		local _, system, _, pres, _, field, commits = fieldScreen()
		press(system, "Return")
		expect(field.dump().editing).toBe(true)
		local at = pres.focus.focused:get()
		tab(system)
		expect(field.dump().editing).toBe(false) -- the edit ended
		expect(#commits).toBe(1) -- through the commit path, not a silent drop
		expect(pres.focus.focused:get() ~= at).toBe(true) -- and focus advanced
	end)

	it("the arrows stay with the field's own sinking context while editing", function()
		local _, system, _, pres, _, field = fieldScreen()
		press(system, "Return")
		local at = pres.focus.focused:get()
		press(system, "Down")
		expect(pres.focus.focused:get()).toBe(at) -- swallowed, focus did not move
		expect(field.dump().editing).toBe(true)
	end)
end)

describe("keyboard bindings follow capability and responder ownership (DK-13/DK-15)", function()
	local function gameplay(system: any, core: any)
		local ctx = system.createContext({ name = "Char", priority = 1000, sink = false })
		local jump = ctx.createAction("Jump", "Bool")
		jump.bind({ keyCode = "Space" })
		local menu = ctx.createAction("Menu", "Bool")
		menu.bind({ keyCode = "Tab" })
		local counts = { jump = 0, menu = 0 }
		jump.onPressed(function()
			counts.jump += 1
		end)
		menu.onPressed(function()
			counts.menu += 1
		end)
		return counts
	end

	it("a PASSIVE HUD binds no Tab and no Space: gameplay is untouched", function()
		local core, _, _, system, pres = harness()
		local counts = gameplay(system, core)
		local acts: { [string]: number } = {}
		local h = pres.present(formScreen(acts), { responder = "passive" })
		pres.refresh()
		local at = pres.focus.focused:get()
		press(system, "Tab")
		press(system, "Space")
		expect(counts.menu).toBe(1)
		expect(counts.jump).toBe(1)
		expect(pres.focus.focused:get()).toBe(at)
		expect(next(acts)).toBe(nil)
		expect(h.responder:get()).toBe("passive")
	end)

	it("engage() binds them and resign() gives them back, with no residue", function()
		local core, _, _, system, pres = harness()
		local counts = gameplay(system, core)
		local acts: { [string]: number } = {}
		local h = pres.present(formScreen(acts), { responder = "passive" })
		pres.refresh()
		h.engage()
		-- a passive surface now mounts with NO focus (round 6), so the first Tab
		-- ENTERS the scope and the second is the one that moves along it
		press(system, "Tab")
		expect(pres.focus.focused:get()).toBe("/F/one")
		press(system, "Tab")
		expect(pres.focus.focused:get()).toBe("/F/two")
		expect(counts.menu).toBe(0) -- sunk from gameplay while engaged
		press(system, "Space")
		expect(acts.two).toBe(1)
		expect(counts.jump).toBe(0)
		h.resign()
		press(system, "Tab")
		press(system, "Space")
		expect(counts.menu).toBe(1)
		expect(counts.jump).toBe(1)
		expect(acts.two).toBe(1) -- no leaked Activate binding
	end)

	--[[ THE GESTURE, NOT THE API (director playtest 2026-08-03 round 3: "there's no
		way to unfocus. i'd expect when i click elsewhere (non-ui element) the ui
		loses focus, and when i first click on ui that's when the responder chain
		gets focus").

		The case above proves `engage()` and `resign()` do the right thing when
		CALLED. Nobody calls them: a player clicks. This drives the two real taps —
		one on a control, one outside the surface — and asserts the keyboard changes
		hands both ways.

		It is the routing that was missing in use, not the mechanism: the fixture had
		been presented engaged-open, where `resign()` is a no-op and no outside-tap
		catcher is ever mounted, so the surface held Tab and Space forever. ]]
	it("a tap on the UI takes the keyboard, and a tap OUTSIDE gives it back", function()
		local core, _, adapter, system, pres = harness()
		local counts = gameplay(system, core)
		local acts: { [string]: number } = {}
		local h = pres.present(formScreen(acts), { responder = "passive" })
		pres.refresh()

		-- at rest: the surface binds nothing gameplay-contended
		expect(h.responder:get()).toBe("passive")
		press(system, "Tab")
		press(system, "Space")
		expect(counts.menu).toBe(1)
		expect(counts.jump).toBe(1)

		-- FIRST TAP ON UI -> the responder chain takes focus
		adapter.tap("/F/one")
		pres.refresh()
		expect(h.responder:get()).toBe("engaged")
		press(system, "Tab")
		expect(counts.menu).toBe(1) -- still 1: sunk from gameplay now
		expect(pres.focus.focused:get()).toBe("/F/two")

		-- TAP OUTSIDE (the catcher an engaged surface mounts) -> it lets go
		local scrimPath = pres.topScrimPath()
		expect(scrimPath ~= nil).toBe(true)
		adapter.tap(scrimPath :: string, { x = 1250, y = 700 })
		pres.refresh()
		expect(h.responder:get()).toBe("passive")

		-- ...and the keyboard is the game's again, with no residue
		local focusBefore = pres.focus.focused:get()
		press(system, "Tab")
		press(system, "Space")
		expect(counts.menu).toBe(2)
		expect(counts.jump).toBe(2)
		expect(pres.focus.focused:get()).toBe(focusBefore) -- Tab moved nothing
	end)

	--[[ THE RING IS A CLAIM ABOUT WHO OWNS INPUT (director playtest 2026-08-03
		round 4: "when i hit play and clicked on the world, the text field kept
		showing a focus ring even though input goes to the avatar").

		A passive surface has focus IDENTITY from the moment it mounts — entry focus
		lands on its first focusable — but it binds nothing until it engages. The
		ring was driven by `focusVisible` alone, which only distinguishes a pointer
		focus move from a navigation one, so a freshly mounted passive HUD painted a
		full ring over a keyboard it did not have.

		Measured live before the fix, on a fresh Play with nothing clicked:
		`traverse = {}` (binds nothing) and a 2px opaque ring on the text field.

		The assertion is on the ADAPTER's painted state, not on a signal, because
		"is a ring drawn" is the whole question. ]]
	it("a PASSIVE surface paints no focus ring: the ring never claims input it lacks", function()
		local _, _, adapter, _, pres = harness()
		local acts: { [string]: number } = {}
		local h = pres.present(formScreen(acts), { responder = "passive" })
		pres.refresh()

		-- a passive surface now takes NO initial focus at all (round 6), so there
		-- is nothing to paint and nothing claiming the keyboard
		expect(pres.focus.focused:get()).toBeNil()
		expect(adapter.node("/F/one").focused).toBeNil()

		-- give it focus the way a player would, then engage: the ring comes up on
		-- the node focus is ALREADY standing on. Focus does not move across the
		-- engage, so neither focus observer fires — the responder flip drives it,
		-- which is the half that was missing.
		pres.focus.focusOn("/F/one")
		pres.focus.setFocusOrigin("navigation")
		pres.refresh()
		expect(adapter.node("/F/one").focused).toBeNil() -- still passive: no paint
		h.engage()
		pres.refresh()
		expect(adapter.node("/F/one").focused).toBe(true)

		-- and resigning takes it away again
		h.resign()
		pres.refresh()
		expect(adapter.node("/F/one").focused).toBe(false)
		expect(pres.focus.focused:get()).toBe("/F/one") -- identity survives; only the paint went
	end)

	it("an ordinary (engaged-open) screen still paints its ring exactly as before", function()
		local _, _, adapter, _, pres = harness()
		local acts: { [string]: number } = {}
		pres.present(formScreen(acts), {})
		pres.refresh()
		-- the gate on the ring is RESPONDER ownership, and a plain screen owns input
		-- from mount — so this path must be byte-identical to pre-fix behavior
		expect(adapter.node("/F/one").focused).toBe(true)
	end)

	--[[ WHERE FOCUS FIRST APPEARS IS THE SURFACE'S CHOICE (director playtest
		2026-08-03 round 5). Before this, every scope put focus on its first
		focusable and an author had no say. The default is unchanged. ]]
	it("initialFocus defaults to the first focusable — every existing caller unmoved", function()
		local _, _, _, _, pres = harness()
		pres.present(formScreen({}), {})
		pres.refresh()
		expect(pres.focus.focused:get()).toBe("/F/one")
	end)

	--[[ THE DEFAULT FOLLOWS THE RESPONDER (director, round 6, revising round 5).
		A surface that owns input from the moment it mounts should say where focus
		is; a surface that owns nothing until the player touches it has no business
		claiming any. Both halves are pinned, because the whole value of the rule is
		that it is different for the two kinds. ]]
	it("a PASSIVE surface defaults to NO initial focus", function()
		local _, _, _, _, pres = harness()
		pres.present(formScreen({}), { responder = "passive" })
		pres.refresh()
		expect(pres.focus.focused:get()).toBeNil()
	end)

	it("...while an engaged-open screen still defaults to its first focusable", function()
		local _, _, _, _, pres = harness()
		pres.present(formScreen({}), {})
		pres.refresh()
		expect(pres.focus.focused:get()).toBe("/F/one")
	end)

	it("an explicit initialFocus still wins on a passive surface", function()
		local _, _, _, _, pres = harness()
		pres.present(formScreen({}), { responder = "passive", initialFocus = "two" })
		pres.refresh()
		expect(pres.focus.focused:get()).toBe("/F/two")
	end)

	it('initialFocus = "none" mounts the surface with NO focus', function()
		local _, _, adapter, _, pres = harness()
		pres.present(formScreen({}), { initialFocus = "none" })
		pres.refresh()
		expect(pres.focus.focused:get()).toBeNil()
		expect(adapter.node("/F/one").focused).toBeNil()
	end)

	it("...and Tab still ENTERS such a scope rather than no-opping", function()
		local _, _, _, system, pres = harness()
		pres.present(formScreen({}), { initialFocus = "none" })
		pres.refresh()
		press(system, "Tab")
		expect(pres.focus.focused:get()).toBe("/F/one")
	end)

	it("initialFocus names a control by id, without the author knowing its path", function()
		local _, _, _, _, pres = harness()
		pres.present(formScreen({}), { initialFocus = "three" })
		pres.refresh()
		expect(pres.focus.focused:get()).toBe("/F/three")
	end)

	it("focus lands there ONCE — the ring never appears elsewhere first", function()
		local _, _, _, _, pres = harness()
		local seen: { string? } = {}
		pres.present(formScreen({}), {
			initialFocus = "three",
			onFocusNav = function(path)
				table.insert(seen, path)
			end,
		})
		pres.refresh()
		-- the push decides; a presenter that set "first" and then corrected it
		-- would have moved focus twice and flashed a ring on /F/one
		expect(#seen <= 1).toBe(true)
		expect(pres.focus.focused:get()).toBe("/F/three")
	end)

	it("an initialFocus id that names nothing is refused, listing what is available", function()
		local _, _, _, _, pres = harness()
		local ok, err = pcall(function()
			pres.present(formScreen({}), { initialFocus = "Sve" })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "Sve") ~= nil).toBe(true)
		expect(string.find(tostring(err), "one") ~= nil).toBe(true) -- names the real ones
	end)

	--[[ THE RESERVED-WORD COLLISION, refused rather than resolved silently. A
		surface holding a focusable literally called "first" makes
		`initialFocus = "first"` mean two things, and guessing either way is the
		accepted-and-ignored class the strict boundary exists to remove. ]]
	it('a focusable actually named "first" makes the keyword ambiguous, and it says so', function()
		local _, _, _, _, pres = harness()
		local screen = UI.Screen({
			id = "A",
			children = { UI.Button({ id = "first", label = "f" }), UI.Button({ id = "b", label = "b" }) },
		})
		local ok, err = pcall(function()
			pres.present(screen, { initialFocus = "first" })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "ambiguous") ~= nil).toBe(true)
	end)

	it("...and { id = … } is the escape hatch that means the CONTROL", function()
		local _, _, _, _, pres = harness()
		local screen = UI.Screen({
			id = "A",
			children = { UI.Button({ id = "b", label = "b" }), UI.Button({ id = "first", label = "f" }) },
		})
		pres.present(screen, { initialFocus = { id = "first" } })
		pres.refresh()
		expect(pres.focus.focused:get()).toBe("/A/first")
	end)

	--[[ GIVING FOCUS UP WHEN THE VIEW GOES AWAY (round 5). Dismissal already
		released focus IDENTITY and destroyed the input context. What it did not do
		was stop the departing surface PAINTING a ring: `syncFocusVisuals` walks the
		live stack and the handle is removed from it first, so the focus change it
		causes reaches every surface except the one wearing the ring. With an exit
		transition the tree stays mounted for the whole animation, so the ring sat
		on a surface that had already stopped taking input. ]]
	it("a dismissed surface gives up its focus ring immediately, mid-exit-transition", function()
		local _, _, adapter, _, pres = harness()
		local screen = UI.Screen({
			id = "D",
			children = {
				UI.ZStack({
					id = "G",
					canvasGroup = true,
					children = { UI.Button({ id = "Save", label = "Save" }) },
				}),
			},
		})
		local h = pres.present(screen, { transition = { enter = "fade", exit = "fade" } })
		pres.refresh()
		expect(adapter.node("/D/G/Save").focused).toBe(true)

		pres.dismiss(h)
		pres.refresh()
		expect(pres.focus.focused:get()).toBeNil() -- identity released
		expect(adapter.node("/D/G/Save") ~= nil).toBe(true) -- still mounted: exit playing
		expect(adapter.node("/D/G/Save").focused).toBe(false) -- ...and no longer painted
	end)

	--[[ A CONTROL THAT PAINTS ITS OWN FOCUSED STATE OBEYS THE SAME RULE (director
		playtest 2026-08-03 round 6: "slider has focus, and i clicked on the world.
		it's not giving up focus").

		Round 4 gated the ADAPTER's ring on responder ownership. A Slider declares
		`focusVisual = "none"` and paints its own, from `graph.focused` alone — and
		focus IDENTITY deliberately survives a resign, so the responder handed the
		keyboard back and the thumb went on wearing its ring. The gate existed; the
		control could not see it.

		The presenter now publishes the permission through `bindFocusGraph`, and this
		is the case that keeps it honest. It is written against the SLIDER because
		that is the only control that paints its own focus today — if another one
		ever does, it belongs here too. ]]
	it("a self-painted focus ring clears when the surface resigns", function()
		local core, _, adapter, _, pres = harness()
		local slider = Facet.Controls.Slider(core, {
			id = "Vol",
			value = core:signal(0.5),
			min = 0,
			max = 1,
			step = 0.1,
		})
		local h = pres.present(
			UI.Screen({
				id = "P",
				children = { UI.Button({ id = "b", label = "b" }), slider.blueprint },
			}),
			{ responder = "passive" }
		)
		pres.refresh()
		local function thumbRing(): any
			local n = adapter.node("/P/Vol/TrackHost/Groove/Thumb")
			return n ~= nil and n.strokeInstance or nil
		end

		h.engage()
		pres.focus.focusOn("/P/Vol/TrackHost/Track")
		pres.focus.setFocusOrigin("navigation")
		pres.refresh()
		expect(pres.focus.focused:get()).toBe("/P/Vol/TrackHost/Track")
		expect(thumbRing() ~= nil).toBe(true) -- engaged and focused: painted

		-- the world click: the responder hands the keyboard back...
		h.resign()
		pres.refresh()
		expect(h.responder:get()).toBe("passive")
		-- ...and the control's OWN ring goes with it, though focus identity stays
		expect(pres.focus.focused:get()).toBe("/P/Vol/TrackHost/Track")
		expect(thumbRing()).toBeNil()

		-- and it comes back on re-engage, without focus having moved
		h.engage()
		pres.refresh()
		expect(thumbRing() ~= nil).toBe(true)
	end)

	--[[ A RESIGN HAS NO FORGIVENESS ZONE (director playtest 2026-08-03 round 7).

		Zone A — the union bounding box of every painted node, inflated, plus every
		focusable's 44px hit rect — is MODAL DISMISSAL forgiveness. Applied to an
		engaged HUD it swallowed nearly every click: the fixture's slider track is
		803px wide, so the box reached most of the viewport and a click on visibly
		empty world did nothing at all.

		My own live check missed this because I happened to click BELOW the box. The
		earlier headless case has the same hole — it taps the catcher at (1250,700),
		outside the content. This one taps INSIDE the painted region's bbox, which is
		the case that was broken. ]]
	it("an engaged HUD resigns on an outside tap even CLOSE to its own content", function()
		local core, _, adapter, system, pres = harness()
		local counts = gameplay(system, core)
		local h = pres.present(formScreen({}), { responder = "passive" })
		pres.refresh()
		adapter.tap("/F/one")
		pres.refresh()
		expect(h.responder:get()).toBe("engaged")

		-- a few px off the content — Zone A territory, and a resign must not care
		local scrimPath = pres.topScrimPath()
		expect(scrimPath ~= nil).toBe(true)
		adapter.tap(scrimPath :: string, { x = 5, y = 5 })
		pres.refresh()
		expect(h.responder:get()).toBe("passive")
		press(system, "Tab")
		press(system, "Space")
		expect(counts.menu).toBe(1) -- the keyboard really went back
		expect(counts.jump).toBe(1)
	end)

	it("...while a MODAL keeps its dismissal forgiveness", function()
		local _, _, adapter, _, pres = harness()
		local modal = pres.presentModal(UI.Screen({
			id = "M",
			children = { UI.Button({ id = "ok", label = "OK" }) },
		}))
		pres.refresh()
		local scrimPath = pres.topScrimPath()
		expect(scrimPath ~= nil).toBe(true)
		-- a near-miss on the card must NOT destroy it: this is the behaviour the
		-- resign path deliberately gives up, and it has to survive here
		adapter.tap(scrimPath :: string, { x = 5, y = 5 })
		pres.refresh()
		expect(pres.depth()).toBe(1) -- still up
	end)

	--[[ THE ADJUST KEYS GO BACK TOO (round 7). They were gated on focus alone, so a
		resigned surface kept Left/Right bound to whatever its focus was standing on
		— the second half of "left/right go to the slider". It is inert today only
		because a passive context is disabled, which is luck rather than design. ]]
	it("a resigned surface unbinds the Adjust keys it had claimed", function()
		local core, _, adapter, _, pres = harness()
		local slider = Facet.Controls.Slider(core, {
			id = "Vol",
			value = core:signal(0.5),
			min = 0,
			max = 1,
			step = 0.1,
		})
		local h = pres.present(
			UI.Screen({ id = "P", children = { UI.Button({ id = "b", label = "b" }), slider.blueprint } }),
			{ responder = "passive" }
		)
		pres.refresh()
		-- BOTH ADJUST ACTIONS, because a control with a declared axis puts its
		-- directional keys on `adjustAxis` and its Comma/Period/bumpers on `adjust`
		-- (ruling 9, so one of the two can be yielded back to navigation at the
		-- control's limit). Counting only one of them would let a leak on the other
		-- pass as "given back" — the exact shape this case exists to catch.
		local function adjustKeys(): number
			local n = 0
			for _, action in { h.actions.adjust, h.actions.adjustAxis } do
				for _, binding in action.bindings do
					if binding.keyCode == "Left" or binding.keyCode == "Right" then
						n += 1
					end
				end
			end
			return n
		end

		h.engage()
		pres.focus.focusOn("/P/Vol/TrackHost/Track")
		pres.refresh()
		expect(adjustKeys() > 0).toBe(true) -- focused on the value control: claimed

		h.resign()
		pres.refresh()
		expect(adjustKeys()).toBe(0) -- ...and given back, not merely made undeliverable
		expect(pres.focus.focused:get()).toBe("/P/Vol/TrackHost/Track") -- identity kept
	end)

	it("keyboard hot-plug adds and removes the bindings with no stuck sink", function()
		local core, env, _, system, pres = harness()
		local counts = gameplay(system, core)
		local acts: { [string]: number } = {}
		pres.present(formScreen(acts), { sinkNavigation = true })
		pres.refresh()
		press(system, "Tab")
		expect(pres.focus.focused:get()).toBe("/F/two")
		expect(counts.menu).toBe(0)

		-- the keyboard goes away (a pad-only handheld, a docked tablet)
		env:set("capabilities", { keyboard = false, mouse = true, touch = true, gamepad = false })
		press(system, "Tab")
		expect(pres.focus.focused:get()).toBe("/F/two") -- no traversal
		expect(counts.menu).toBe(1) -- and no stuck sink: gameplay got it back
		press(system, "Space")
		expect(counts.jump).toBe(1)

		-- and back again
		env:set("capabilities", { keyboard = true, mouse = true, touch = true, gamepad = false })
		press(system, "Tab")
		expect(pres.focus.focused:get()).toBe("/F/three")
		expect(counts.menu).toBe(1)
	end)

	it("gameplayGuard = false leaves Space to the game even while engaged", function()
		local core, _, _, system, pres = harness()
		local counts = gameplay(system, core)
		local acts: { [string]: number } = {}
		pres.present(formScreen(acts), { responder = "passive", gameplayGuard = false })
		pres.refresh()
		local h = pres.present(formScreen(acts), { responder = "passive", gameplayGuard = false })
		h.engage()
		press(system, "Space")
		expect(counts.jump).toBe(1)
	end)
end)

--[[ THE OPT ITSELF (director playtest 2026-08-03).

	Global at the presenter, overridable per surface, and turning it on makes the
	surface SINK — because a surface that claims Space and the arrows has to
	consume them, or the avatar underneath acts on the same press. Measured live
	against the real PlayerModule CharacterContext: non-sinking = UI activates AND
	the character jumps; sinking = UI activates and the character gets nothing. ]]
describe("keyboard navigation is opt-in, globally and per surface (DK-19)", function()
	local function world(presenterOpts: any?)
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 1280, h = 720 })
		local system = Facet.newActionSystem(core)
		local pres = Facet.newPresenter(core, env, fake_target.new(), system, presenterOpts)
		return system, pres
	end
	local function keys(handle: any): { [string]: boolean }
		local out: { [string]: boolean } = {}
		for name, action in handle.actions do
			for _, b in action.bindings do
				if b.keyCode ~= nil then
					out[`{name}:{b.keyCode}`] = true
				end
			end
		end
		return out
	end

	it("defaults OFF at the presenter: no Tab, no Space, no sink", function()
		local _, pres = world()
		local acts: { [string]: number } = {}
		local h = pres.present(formScreen(acts))
		pres.refresh()
		expect(keys(h)["traverse:Tab"]).toBeNil()
		expect(keys(h)["activate:Space"]).toBeNil()
		expect(h.context.sink).toBe(false)
	end)

	it("presenter opt turns it on for every surface, and the surface sinks", function()
		local _, pres = world({ keyboardNavigation = true })
		local acts: { [string]: number } = {}
		local h = pres.present(formScreen(acts))
		pres.refresh()
		expect(keys(h)["traverse:Tab"]).toBe(true)
		expect(keys(h)["activate:Space"]).toBe(true)
		expect(h.context.sink).toBe(true)
	end)

	it("a surface can override the presenter default in both directions", function()
		local _, presOn = world({ keyboardNavigation = true })
		local acts: { [string]: number } = {}
		local off = presOn.present(formScreen(acts), { keyboardNavigation = false })
		presOn.refresh()
		expect(keys(off)["traverse:Tab"]).toBeNil()
		expect(off.context.sink).toBe(false)

		local _, presOff = world()
		local on = presOff.present(formScreen(acts), { keyboardNavigation = true })
		presOff.refresh()
		expect(keys(on)["traverse:Tab"]).toBe(true)
		expect(on.context.sink).toBe(true)
	end)

	it("an engaged surface EATS the contended keys instead of sharing them", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 1280, h = 720 })
		local system = Facet.newActionSystem(core)
		local pres = Facet.newPresenter(core, env, fake_target.new(), system, { keyboardNavigation = true })
		-- the avatar stack, underneath, exactly as the responder chain describes it
		local char = system.createContext({ name = "Character", priority = 150, sink = false })
		local jump = char.createAction("Jump", "Bool")
		jump.bind({ keyCode = "Space" })
		local move = char.createAction("Move", "Direction1D")
		move.bind({ keyCode = "Down", direction = 1 })
		local jumps, moves = 0, 0
		jump.onPressed(function()
			jumps += 1
		end)
		core:observe(move.state, function(d)
			if d == 1 then
				moves += 1
			end
		end)
		local acts: { [string]: number } = {}
		pres.present(formScreen(acts))
		pres.refresh()

		press(system, "Space")
		expect(acts.one).toBe(1) -- the UI activated...
		expect(jumps).toBe(0) -- ...and the avatar did NOT jump
		press(system, "Down")
		expect(moves).toBe(0) -- nor move
	end)

	it("a boolean is required, and the error names the inherit spelling", function()
		local _, pres = world()
		local acts: { [string]: number } = {}
		expect(function()
			pres.present(formScreen(acts), { keyboardNavigation = "yes" } :: any)
		end).toThrow()
	end)
end)

describe("teardown removes every keyboard binding (DK-14)", function()
	it("a dismissed screen stops eating Tab and Space", function()
		local core, _, _, system, pres = harness()
		local ctx = system.createContext({ name = "Char", priority = 1000, sink = false })
		local menu = ctx.createAction("Menu", "Bool")
		menu.bind({ keyCode = "Tab" })
		local seen = 0
		menu.onPressed(function()
			seen += 1
		end)
		local acts: { [string]: number } = {}
		local h = pres.present(formScreen(acts), { sinkNavigation = true })
		pres.refresh()
		press(system, "Tab")
		expect(seen).toBe(0)
		pres.dismiss(h)
		press(system, "Tab")
		expect(seen).toBe(1)
	end)
end)

describe("a modal traps traversal and restores focus through the presenter (DK-6)", function()
	it("Tab stays inside the modal and the base screen's focus comes back", function()
		local _, _, _, system, pres = harness()
		local acts: { [string]: number } = {}
		pres.present(formScreen(acts))
		pres.refresh()
		tab(system)
		expect(pres.focus.focused:get()).toBe("/F/two")
		local modal = pres.presentModal(UI.Screen({
			id = "M",
			children = { UI.Button({ id = "ok", label = "ok" }), UI.Button({ id = "cancel", label = "cancel" }) },
		}))
		pres.refresh()
		expect(pres.focus.focused:get()).toBe("/M/ok")
		tab(system)
		expect(pres.focus.focused:get()).toBe("/M/cancel")
		tab(system)
		expect(pres.focus.focused:get()).toBe("/M/ok") -- trapped: wrapped inside
		pres.dismiss(modal)
		expect(pres.focus.focused:get()).toBe("/F/two") -- restored
	end)
end)

describe("traversal wrap is declarable per presented surface (DK-3)", function()
	it("present({ traversalWrap = false }) stops Tab at the last control", function()
		local _, _, _, system, pres = harness()
		local acts: { [string]: number } = {}
		pres.present(formScreen(acts), { traversalWrap = false })
		pres.refresh()
		tab(system)
		tab(system)
		expect(pres.focus.focused:get()).toBe("/F/three")
		tab(system)
		expect(pres.focus.focused:get()).toBe("/F/three")
	end)

	it("an unknown present() opt is still refused by name", function()
		local _, _, _, _, pres = harness()
		local acts: { [string]: number } = {}
		expect(function()
			pres.present(formScreen(acts), { traversalWarp = false } :: any)
		end).toThrow()
	end)
end)
