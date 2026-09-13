--!strict
-- STRUCTURAL TRANSITIONS (acceptance row SF-M6). Three
-- layers, proven separately and then together:
--
--   1. the MOUNT LAYER's retire model, against a SCRIPTED collaborator — so the
--      lifetime rules (retire, dispose exactly once at done, re-entry reuses the
--      SAME mounted subtree, a retiring row holds its slot) are proven without any
--      motion at all;
--   2. the COORDINATOR, under a scripted clock — the forms it derives, the fade
--      group it insists on, the reversal that keeps its velocity, the flat 500 ms
--      cap, and reduced motion (which must complete on the frame it starts and
--      still emit the same event);
--   3. the PRESENTER, where a retiring subtree must stop being interactive and a
--      dismissed surface must leave the stack immediately but the screen late.
--
-- The churn assertions are the ones that matter most: an exit transition that
-- keeps a disposed scope alive, or disposes one twice, is exactly the leak the
-- retire model could have introduced.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local worldLib = require("./lib/world")

local customFactory = require("../src/core/custom")
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local rendererLib = require("../src/render/renderer")
local clockLib = require("../src/motion/clock")
local transitionsLib = require("../src/render/transitions")
local Facet = require("../src") :: any -- framework-gaps-phase2 item 41: EXIT_CAP_SECONDS
local presenterLib = require("../src/present/presenter")
local actionsLib = require("../src/input/actions")
local fake_target = require("./lib/fake_target")

local FRAME = 1 / 60

-- a collaborator that records everything and hands the test the `done` callbacks,
-- so "the exit completes" is something the test decides, frame by frame
local function scripted()
	local calls: { string } = {}
	local pending: { [string]: () -> () } = {}
	local specs: { [string]: any } = {}
	local coordinator: any = {}
	function coordinator.shouldRetire(path: string, node: any): any?
		table.insert(calls, `shouldRetire {path}`)
		return node.transition
	end
	function coordinator.beginExit(path: string, _node: any, spec: any, done: () -> ())
		table.insert(calls, `beginExit {path}`)
		pending[path] = done
		specs[path] = spec
	end
	function coordinator.cancelExit(path: string)
		table.insert(calls, `cancelExit {path}`)
		pending[path] = nil
	end
	function coordinator.beginEnter(path: string, _node: any, _spec: any)
		table.insert(calls, `beginEnter {path}`)
	end
	function coordinator.release(path: string)
		table.insert(calls, `release {path}`)
		pending[path] = nil
	end
	return {
		coordinator = coordinator,
		calls = calls,
		finish = function(path: string)
			local done = pending[path]
			expect(done ~= nil).toBe(true)
			pending[path] = nil
			(done :: () -> ())()
		end,
		isPending = function(path: string): boolean
			return pending[path] ~= nil
		end,
		specOf = function(path: string): any
			return specs[path]
		end,
	}
end

local FADE = { enter = "fade" }

local function whenScreen(condition: any, transition: any?)
	return UI.Screen({
		id = "S",
		children = {
			UI.When({
				id = "Gate",
				condition = condition,
				transition = transition,
				thenView = function()
					return UI.ZStack({
						id = "Panel",
						canvasGroup = true,
						children = { UI.Button({ id = "Go", label = "Go" }) },
					})
				end,
			}),
		},
	})
end

describe("mount retire model: When", function()
	it("a declared transition retires the branch instead of disposing it", function()
		local core = customFactory.new()
		local script = scripted()
		local on = core:signal(true)
		local root = mountLib.mount(core, whenScreen(on, FADE), { transitions = script.coordinator })
		local gate = root.node.children[1]
		local branch = gate.children[1]
		expect(branch.id).toBe("Panel")
		-- the mount-time enter ran, and the declaration rides the branch root so a
		-- collaborator can read it off the node it is asked about
		expect(script.calls[1]).toBe("beginEnter /S/Gate/then/Panel")
		expect(branch.transition).toBe(FADE)

		local before = root.counters().mounted
		on:set(false)
		-- STILL MOUNTED, and marked
		expect(gate.children[1]).toBe(branch)
		expect(branch.retiring).toBe(true)
		expect(root.counters().mounted).toBe(before)
		expect(script.isPending("/S/Gate/then/Panel")).toBe(true)
		-- retiring IS a structural change (focus and hit routing both read the mark)
		local dirty = root.takeDirty()
		expect(#dirty).toBe(1)
		expect(dirty[1].class).toBe("structure")

		script.finish("/S/Gate/then/Panel")
		expect(#gate.children).toBe(0)
		expect(root.counters().mounted < before).toBe(true)
		expect(root.takeDirty()[1].class).toBe("structure")
		root.dispose()
	end)

	it("re-entry mid-exit reuses the SAME mounted subtree — identity, scope, factory runs", function()
		local core = customFactory.new()
		local script = scripted()
		local on = core:signal(true)
		local root = mountLib.mount(core, whenScreen(on, FADE), { transitions = script.coordinator })
		local gate = root.node.children[1]
		local branch = gate.children[1]
		local runsBefore = root.counters().factoryRuns

		on:set(false)
		on:set(true)
		-- the exit was cancelled and the enter re-ran on the SAME node table
		expect(gate.children[1]).toBe(branch)
		expect(branch.retiring).toBeNil()
		expect(script.isPending("/S/Gate/then/Panel")).toBe(false)
		expect(root.counters().factoryRuns).toBe(runsBefore) -- nothing re-built
		expect(table.concat(script.calls, "|")).toBe(
			"beginEnter /S/Gate/then/Panel|shouldRetire /S/Gate/then/Panel|beginExit /S/Gate/then/Panel"
				.. "|cancelExit /S/Gate/then/Panel|beginEnter /S/Gate/then/Panel"
		)

		-- a LATE `done` from the cancelled exit must not dispose the live branch
		on:set(false)
		local retired = script.isPending("/S/Gate/then/Panel")
		expect(retired).toBe(true)
		script.finish("/S/Gate/then/Panel")
		expect(#gate.children).toBe(0)
		root.dispose()
	end)

	it("the branch scope disposes exactly once, at done — never at retire, never twice", function()
		local core = customFactory.new()
		local script = scripted()
		local on = core:signal(true)
		local disposals = 0
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				children = {
					UI.When({
						id = "Gate",
						condition = on,
						transition = FADE,
						thenView = function()
							return UI.Box({ id = "Leaf" })
						end,
					}),
				},
			}),
			{ transitions = script.coordinator }
		)
		local baseline = core:counters()
		on:set(false)
		expect(core:counters().scopes).toBe(baseline.scopes) -- nothing released yet
		script.finish("/S/Gate/then/Leaf")
		disposals += 1
		expect(core:counters().scopes < baseline.scopes).toBe(true)
		-- a second `done` is inert (the coordinator's cap and its settle can both
		-- fire in a wedged frame)
		local after = core:counters().scopes
		expect(disposals).toBe(1)
		expect(core:counters().scopes).toBe(after)
		root.dispose()
	end)

	it("the scope handed to thenView survives the RETIRE and dies at done, once", function()
		--[[ docs/reference/api.md §When. The branch scope is now the factory's
			second argument, so a panel's MotionValue lives on it — and a panel with a
			motion value is precisely the panel that has an exit transition. The
			retire path moves the scope onto `retiring` and disposes it at `done`, so
			the resource must still be ALIVE for the whole exit (an exit animation
			reading a released handle is the defect) and released exactly once after.
			The re-entry case above proves the factory does not re-run; this one
			proves the thing it was handed is still usable while it does not. ]]
		local core = customFactory.new()
		local script = scripted()
		local on = core:signal(true)
		local handed: { any } = {}
		local released = 0
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				children = {
					UI.When({
						id = "Gate",
						condition = on,
						transition = FADE,
						thenView = function(branchScope)
							table.insert(handed, branchScope)
							branchScope:own(function()
								released += 1
							end)
							return UI.Box({ id = "Leaf" })
						end,
					}),
				},
			}),
			{ transitions = script.coordinator }
		)
		expect(#handed).toBe(1)
		expect(handed[1].label).toBe("/S/Gate/then")

		on:set(false) -- retiring: the exit is playing and the scope must still be live
		expect(handed[1]:isDisposed()).toBe(false)
		expect(released).toBe(0)

		on:set(true) -- reversed mid-exit: SAME scope comes back, factory did not re-run
		expect(#handed).toBe(1)
		expect(handed[1]:isDisposed()).toBe(false)
		expect(released).toBe(0)

		on:set(false)
		script.finish("/S/Gate/then/Leaf")
		expect(handed[1]:isDisposed()).toBe(true)
		expect(released).toBe(1)
		root.dispose()
		expect(released).toBe(1) -- and the region's disposal does not release it twice
		expect(core:lastError()).toBeNil()
	end)

	it("without a transition the removal path is byte-identical to before", function()
		local core = customFactory.new()
		local script = scripted()
		local on = core:signal(true)
		local root = mountLib.mount(core, whenScreen(on), { transitions = script.coordinator })
		local gate = root.node.children[1]
		on:set(false)
		expect(#gate.children).toBe(0)
		expect(#script.calls).toBe(0) -- the collaborator was never consulted
		root.dispose()
	end)

	it("disposing the region mid-exit releases the coordinator's motion, once", function()
		local core = customFactory.new()
		local script = scripted()
		local on = core:signal(true)
		local root = mountLib.mount(core, whenScreen(on, FADE), { transitions = script.coordinator })
		local baseline = core:counters()
		on:set(false)
		root.dispose()
		expect(table.find(script.calls, "release /S/Gate/then/Panel") ~= nil).toBe(true)
		expect(core:counters().scopes).toBe(baseline.scopes - (baseline.scopes - core:counters().scopes))
		expect(core:lastError()).toBeNil()
	end)
end)

describe("mount retire model: ForEach", function()
	local function listRoot(core: any, items: any, script: any)
		return mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				children = {
					UI.ForEach({
						id = "Rows",
						items = items,
						transition = FADE,
						key = function(item: any): string
							return item.id
						end,
						row = function(item: any)
							return UI.ZStack({
								id = "Row",
								canvasGroup = true,
								children = { UI.Text({ id = "L", text = item.id }) },
							})
						end,
					}),
				},
			}),
			{ transitions = script.coordinator }
		)
	end

	it("a removed row holds its previous slot while it exits", function()
		local core = customFactory.new()
		local script = scripted()
		local items = core:signal({ { id = "a" }, { id = "b" }, { id = "c" } })
		local root = listRoot(core, items, script)
		local rows = root.node.children[1]
		local middle = rows.children[2]
		items:set({ { id = "a" }, { id = "c" } })
		expect(#rows.children).toBe(3)
		expect(rows.children[2]).toBe(middle) -- exits IN PLACE, slot 2
		expect(middle.retiring).toBe(true)
		script.finish("/S/Rows/[b]/Row")
		expect(#rows.children).toBe(2)
		expect(rows.children[1].path).toBe("/S/Rows/[a]/Row")
		expect(rows.children[2].path).toBe("/S/Rows/[c]/Row")
		root.dispose()
	end)

	it("the same key re-added mid-exit keeps its mounted identity", function()
		local core = customFactory.new()
		local script = scripted()
		local items = core:signal({ { id = "a" }, { id = "b" } })
		local root = listRoot(core, items, script)
		local rows = root.node.children[1]
		local b = rows.children[2]
		local runs = root.counters().factoryRuns
		items:set({ { id = "a" } })
		items:set({ { id = "a" }, { id = "b" } })
		expect(rows.children[2]).toBe(b)
		expect(b.retiring).toBeNil()
		expect(root.counters().factoryRuns).toBe(runs)
		expect(script.isPending("/S/Rows/[b]/Row")).toBe(false)
		root.dispose()
	end)

	it("a retiring row is not resurrected by an unrelated reorder", function()
		local core = customFactory.new()
		local script = scripted()
		local items = core:signal({ { id = "a" }, { id = "b" }, { id = "c" } })
		local root = listRoot(core, items, script)
		local rows = root.node.children[1]
		items:set({ { id = "a" }, { id = "c" } })
		items:set({ { id = "c" }, { id = "a" } }) -- reorder while b exits
		expect(#rows.children).toBe(3)
		script.finish("/S/Rows/[b]/Row")
		expect(#rows.children).toBe(2)
		expect(rows.children[1].path).toBe("/S/Rows/[c]/Row")
		root.dispose()
	end)

	it("churn with exits in flight returns the core to baseline", function()
		local core = customFactory.new()
		local script = scripted()
		local items = core:signal({ { id = "a" } })
		local baseline = core:counters()
		for _ = 1, 20 do
			local root = listRoot(core, items, script)
			items:set({})
			items:set({ { id = "a" } })
			items:set({})
			root.dispose()
			items:set({ { id = "a" } })
		end
		local after = core:counters()
		for key, value in baseline :: { [string]: number } do
			expect((after :: any)[key]).toBe(value)
		end
	end)
end)

-- ===== the coordinator =====================================================

local function world(reduced: boolean?)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	if reduced then
		env:set("reducedMotion", true)
	end
	local clock = clockLib.new(core, { motionPolicy = env:get("motionPolicy") })
	return core, env, clock
end

local function attach(core: any, env: any, clock: any, screen: any, feedback: any?)
	local coordinator = transitionsLib.new({ core = core, clock = clock, feedback = feedback })
	local root = mountLib.mount(core, screen, { transitions = coordinator })
	local adapter = fake_target.new()
	local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
	controller.initialRender()
	coordinator.bindController(controller)
	return root, adapter, controller, coordinator
end

--[[ THE VISIBLE CLOCK of one fade transition, in frames at 60 fps: when the
	enter is 95% opaque, when the exit is 95% faded, and when the branch is
	actually gone. Every number is read off the SAME painted `groupTransparency`
	the player sees, so none of them moves with a settle tolerance — which is
	exactly the property the frame-count pins below need (task 7 item 1). ]]
local function fadeFrames(exitClass: string?, class: string?): (number, number, number)
	local core, env, clock = world()
	local on = core:signal(true)
	local spec: any = { enter = "fade", class = class, exitClass = exitClass }
	local root, adapter, _, coordinator = attach(core, env, clock, whenScreen(on, spec))
	local path = "/S/Gate/then/Panel"
	local function alpha(): number
		return adapter.node(path).canvasGroupInstance.groupTransparency
	end
	local enterCross = -1
	for f = 1, 120 do
		clock:step(FRAME)
		if enterCross < 0 and alpha() <= 0.05 then
			enterCross = f
		end
	end
	local gate = root.node.children[1]
	on:set(false)
	local exitCross, disposeFrame = -1, -1
	for f = 1, 120 do
		clock:step(FRAME)
		if exitCross < 0 and #gate.children > 0 and alpha() >= 0.95 then
			exitCross = f
		end
		if disposeFrame < 0 and #gate.children == 0 then
			disposeFrame = f
		end
	end
	root.dispose()
	coordinator.dispose()
	clock:dispose()
	return enterCross, exitCross, disposeFrame
end

describe("transition coordinator: the forms", function()
	it("a slide exit clears the interrupted fade before moving and disposing", function()
		local core, env, clock = world()
		local on = core:signal(true)
		local root, adapter, controller, coordinator = attach(
			core,
			env,
			clock,
			whenScreen(on, {
				enter = "fade",
				exit = "slide-left",
			})
		)
		local path = "/S/Gate/then/Panel"
		local panel = adapter.node(path)
		for _ = 1, 5 do
			clock:step(FRAME)
		end
		local alpha = panel.canvasGroupInstance.groupTransparency
		expect(alpha > 0 and alpha < 1).toBe(true)
		on:set(false)
		expect(panel.canvasGroupInstance.groupTransparency).toBe(0)
		for _ = 1, 90 do
			clock:step(FRAME)
		end
		controller.refresh()
		expect(adapter.node(path)).toBeNil()
		expect(clock:activeCount()).toBe(0)
		root.dispose()
		coordinator.dispose()
		clock:dispose()
	end)

	it("a revived row samples pure slide and clears the cancelled fade through settle", function()
		local core, env, clock = world()
		local on = core:signal(true)
		local declared = core:signal({ enter = "fade" })
		local root, adapter, controller, coordinator = attach(core, env, clock, whenScreen(on, declared))
		local panel = adapter.node("/S/Gate/then/Panel")
		for _ = 1, 90 do
			clock:step(FRAME)
		end
		on:set(false)
		for _ = 1, 5 do
			clock:step(FRAME)
		end
		local alpha = panel.canvasGroupInstance.groupTransparency
		expect(alpha > 0 and alpha < 1).toBe(true)
		declared:set({ enter = "slide-right" })
		expect(panel.canvasGroupInstance.groupTransparency).toBe(alpha)
		on:set(true)
		expect(panel.canvasGroupInstance.groupTransparency).toBe(0)
		for _ = 1, 90 do
			clock:step(FRAME)
		end
		controller.refresh()
		expect(adapter.node("/S/Gate/then/Panel")).toBe(panel)
		expect(panel.canvasGroupInstance.groupTransparency).toBe(0)
		expect(panel.props.transform).toBeNil()
		expect(clock:activeCount()).toBe(0)
		root.dispose()
		coordinator.dispose()
		clock:dispose()
	end)

	it("redirecting materialize to slide clears descendant alpha and whole-page scale", function()
		local core, env, clock = world()
		local root, adapter, _, coordinator = attach(
			core,
			env,
			clock,
			UI.Screen({
				id = "S",
				children = {
					UI.ZStack({
						id = "Panel",
						children = {
							UI.Box({ id = "Backdrop", surface = "raised" }),
							UI.ZStack({
								id = "Content",
								canvasGroup = true,
								children = { UI.Text({ id = "Label", text = "Journey" }) },
							}),
						},
					}),
				},
			})
		)
		local path = "/S/Panel"
		local node = root.node.children[1]
		local panel = adapter.node(path)
		local content = adapter.node(path .. "/Content")
		coordinator.beginEnter(path, node, { enter = "materialize" })
		for _ = 1, 5 do
			clock:step(FRAME)
		end
		expect(content.canvasGroupInstance.groupTransparency > 0).toBe(true)
		expect(panel.props.transform.scale < 1).toBe(true)
		coordinator.beginEnter(path, node, { enter = "slide-left" })
		expect(content.canvasGroupInstance.groupTransparency).toBe(0)
		expect(panel.props.transform.scale).toBeNil()
		for _ = 1, 90 do
			clock:step(FRAME)
		end
		expect(content.canvasGroupInstance.groupTransparency).toBe(0)
		expect(panel.props.transform).toBeNil()
		expect(#coordinator.findings()).toBe(0)
		root.dispose()
		coordinator.dispose()
		expect(clock:activeCount()).toBe(0)
		clock:dispose()
	end)

	it("a fade drives group transparency 1 -> 0 and clears at rest", function()
		local core, env, clock = world()
		local on = core:signal(true)
		local _, adapter = attach(core, env, clock, whenScreen(on, FADE))
		local group = adapter.node("/S/Gate/then/Panel")
		expect(group.canvasGroupInstance.groupTransparency).toBe(1) -- seeded absent
		for _ = 1, 60 do
			clock:step(FRAME)
		end
		expect(group.canvasGroupInstance.groupTransparency).toBe(0)
		expect(clock:activeCount()).toBe(0) -- rest costs zero
	end)

	it("a slide seeds the offset from the edge it travels from, in theme space", function()
		local core, env, clock = world()
		local on = core:signal(true)
		local _, adapter = attach(core, env, clock, whenScreen(on, { enter = "slide-up" }))
		local panel = adapter.node("/S/Gate/then/Panel")
		-- travelling UP means starting BELOW: +y, one `space.l` step (24 px neutral)
		expect(panel.props.transform.y).toBe(24)
		expect(panel.props.transform.x).toBe(0)
		for _ = 1, 60 do
			clock:step(FRAME)
		end
		expect(panel.props.transform).toBeNil() -- cleared at rest
	end)

	it("materialize scales 0.96 -> 1 and fades together", function()
		local core, env, clock = world()
		local on = core:signal(true)
		local _, adapter = attach(core, env, clock, whenScreen(on, { enter = "materialize" }))
		local panel = adapter.node("/S/Gate/then/Panel")
		expect(panel.props.transform.scale).toBeCloseTo(0.96, 1e-6)
		expect(panel.canvasGroupInstance.groupTransparency).toBe(1)
		clock:step(FRAME)
		expect(panel.props.transform.scale > 0.96).toBe(true)
	end)

	it("the mirrored exit displaces the node to the SAME absent place as the enter", function()
		local core, env, clock = world()
		local on = core:signal(true)
		local _, adapter = attach(core, env, clock, whenScreen(on, { enter = "slide-up" }))
		local panel = adapter.node("/S/Gate/then/Panel")
		for _ = 1, 60 do
			clock:step(FRAME)
		end
		on:set(false)
		for _ = 1, 60 do
			clock:step(FRAME)
		end
		-- the exit's LAST written offset is +24 (back down where it came from), and
		-- the node is gone by the time the motion settles, so read the recorded op
		expect(panel.props.transform.y > 0).toBe(true)
	end)

	it("a fading form on a node that is not a fade group is an authoring error that names the fix", function()
		local core, env, clock = world()
		local on = core:signal(true)
		local screen = UI.Screen({
			id = "S",
			children = {
				UI.When({
					id = "Gate",
					condition = on,
					transition = FADE,
					thenView = function()
						return UI.Text({ id = "Plain", text = "no group" })
					end,
				}),
			},
		})
		local ok, err = pcall(function()
			attach(core, env, clock, screen)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "canvasGroup = true", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "slide", 1, true) ~= nil).toBe(true)
	end)
end)

describe("transition coordinator: lifetime", function()
	it("an exit defers disposal until the motion lands", function()
		local core, env, clock = world()
		local on = core:signal(true)
		local root = attach(core, env, clock, whenScreen(on, FADE))
		for _ = 1, 60 do
			clock:step(FRAME)
		end
		local gate = root.node.children[1]
		local branch = gate.children[1]
		on:set(false)
		clock:step(FRAME)
		expect(gate.children[1]).toBe(branch) -- still there, still fading
		for _ = 1, 120 do
			clock:step(FRAME)
		end
		expect(#gate.children).toBe(0)
	end)

	it("the exit cap disposes a motion that has not landed by 500 ms", function()
		local core, env, clock = world()
		local on = core:signal(true)
		-- `decay` is the slowest shipped class (response 0.5 s), so even at the
		-- coarse exit epsilon it settles at ~0.82 s — well past the flat cap.
		-- `exitClass` is pinned to it too: the exit otherwise defaults to the
		-- faster `dismiss`, which disposes at frame 21 of 30 (the case below),
		-- and would prove nothing about the cap.
		local root = attach(core, env, clock, whenScreen(on, { enter = "fade", class = "decay", exitClass = "decay" }))
		for _ = 1, 200 do
			clock:step(FRAME)
		end
		local gate = root.node.children[1]
		on:set(false)
		-- one frame short of the cap: still retiring
		for _ = 1, 29 do
			clock:step(1 / 60)
		end
		expect(#gate.children).toBe(1)
		expect(gate.children[1].retiring).toBe(true)
		-- past 500 ms of clock time: gone, whatever the spring was doing
		for _ = 1, 3 do
			clock:step(1 / 60)
		end
		expect(#gate.children).toBe(0)
		expect(transitionsLib.EXIT_CAP_SECONDS).toBe(0.5)
		-- framework-gaps-phase2 item 41: `Facet.EXIT_CAP_SECONDS` is the SAME
		-- number, published at the root so a consumer stops copying `0.5` by
		-- hand from this file's own doc comment
		expect(Facet.EXIT_CAP_SECONDS).toBe(transitionsLib.EXIT_CAP_SECONDS)
	end)

	--[[ THE EXIT ENDS ON ITS SPRING, NOT ON THE CAP (task 7 item 1). Measured
		before the fix: `dismiss` disposed at frame 30 = 0.500 s — the flat cap to
		the frame — and `container` at 31. So the two classes were
		indistinguishable at the ONE place a player can see the difference (when
		the instances go), and a `dismiss` exit sat fully faded yet mounted for
		~200 ms. The cause was the settle epsilon: a spring settles on `|x| <= eps
		AND |v| <= eps`, and the VELOCITY half binds long after a critically
		damped 0.2 s spring's value is visually zero. The exit phase now builds
		its spring at `transitions.EXIT_EPS`; the ENTER keeps the default,
		because its settle is what fires `arrive`.

		Both halves are pinned below: the exit is 95%-faded SOONER than the enter
		is 95%-opaque (the pace the owner ruled), and it disposes INSIDE the cap
		(the lifetime the cap was never meant to decide). Discriminating — with
		`exitClass = "container"` the exit cross is 17, not < the enter cross 17,
		and disposal is 31, not < 30; the second case pins exactly that. ]]
	it("a `dismiss` exit is ended by its own spring, well inside the flat cap", function()
		local capFrame = math.ceil(transitionsLib.EXIT_CAP_SECONDS * 60)
		expect(capFrame).toBe(30)
		local enterCross, exitCross, disposeFrame = fadeFrames(nil) -- the default: `dismiss`
		-- the pace: 95% faded out sooner than it was 95% faded in
		expect(exitCross > 0 and exitCross < enterCross).toBe(true)
		-- the lifetime: the SPRING ends it, not the cap
		expect(disposeFrame > 0 and disposeFrame < capFrame).toBe(true)
		-- the measured numbers, so a drift in either direction is visible here
		expect(enterCross).toBe(17)
		expect(exitCross).toBe(10)
		expect(disposeFrame).toBe(22)
	end)

	it("a long declared slide ends on its spring, at the same frame as a short one (review D3)", function()
		--[[ A ROUND OF THIS FIX CLAMPED THE EPSILON TO `0.5 / distance` for a
			travelling form, so the guarantee could be stated in pixels. Measured,
			that made a full-width slide UNABLE to settle: `dismiss` at
			`distance = 1920` went from disposing on frame 22 to frame 31 — the
			cap — which is the very defect the epsilon exists to remove, re-entered
			through the caller most likely to declare a long slide.
			`NavigationStack` passes `distance = stackWidth`, so every push and pop
			would have run to the cap.

			And the residue it was buying is not visible: `screen_presentation`
			rounds a presentation offset to whole pixels before the engine sees it
			(`UDim.Offset` is an integer), so anything under half a pixel is the
			same written number either way. The bound is the honest one — at most
			2 % of the travel, or the cap, whichever comes first — and the claim
			this case makes is that the DISPOSE FRAME does not move with the
			distance. ]]
		local function disposeFrameFor(distance: number?): (number, number)
			local core, env, clock = world()
			local on = core:signal(true)
			local spec: any = { enter = "slide-left", distance = distance }
			local root, adapter, _, coordinator = attach(core, env, clock, whenScreen(on, spec))
			for _ = 1, 200 do
				clock:step(FRAME)
			end
			local gate = root.node.children[1]
			on:set(false)
			local lastX, disposeAt = 0, -1
			for f = 1, 120 do
				clock:step(FRAME)
				if #gate.children == 0 then
					disposeAt = f
					break
				end
				local node = adapter.node("/S/Gate/then/Panel")
				if node ~= nil and node.props.transform ~= nil then
					lastX = math.abs(node.props.transform.x)
				end
			end
			root.dispose()
			coordinator.dispose()
			clock:dispose()
			return disposeAt, lastX
		end
		local capFrame = math.ceil(transitionsLib.EXIT_CAP_SECONDS * 60)
		local shortFrame, shortX = disposeFrameFor(nil) -- the themed 24 px nudge
		local longFrame, longX = disposeFrameFor(1920)
		expect(`short {shortFrame} long {longFrame}`).toBe("short 22 long 22")
		expect(longFrame < capFrame).toBe(true)
		-- ...and the residue really is the same FRACTION at both, which is what
		-- "at most EXIT_EPS of the travel" means
		expect((24 - shortX) / 24 <= transitionsLib.EXIT_EPS).toBe(true)
		expect((1920 - longX) / 1920 <= transitionsLib.EXIT_EPS).toBe(true)
		-- measured: 0.02 px and 1.87 px, both under one written pixel
		expect(`{string.format("%.2f", 1920 - longX)} px`).toBe("1.87 px")
	end)

	it("reduced motion is untouched by the distance (review D3)", function()
		local core, env, clock = world(true)
		local on = core:signal(true)
		local root, _, _, coordinator =
			attach(core, env, clock, whenScreen(on, { enter = "slide-left", distance = 1920 }))
		local gate = root.node.children[1]
		on:set(false)
		clock:step(FRAME)
		-- an exit under reduced motion completes, and disposes, on the frame it
		-- begins — whatever it was going to travel
		expect(#gate.children).toBe(0)
		root.dispose()
		coordinator.dispose()
		clock:dispose()
	end)

	it("`container` as an exit is the class the cap still has to end", function()
		local capFrame = math.ceil(transitionsLib.EXIT_CAP_SECONDS * 60)
		local enterCross, exitCross, disposeFrame = fadeFrames("container")
		-- the SYMMETRIC pair: identical pace in and out, which is the shape the
		-- round moved away from. Its exit spring needs 33 frames even at
		-- EXIT_EPS, so the cap — not the spring — is what ends it, and it is
		-- unchanged by this fix. This is the case that makes the assertions above
		-- discriminating rather than decorative, and the reason `dismiss` rather
		-- than `container` is `DEFAULT_EXIT_CLASS`.
		expect(enterCross).toBe(17)
		expect(exitCross).toBe(17)
		expect(exitCross < enterCross).toBe(false)
		expect(disposeFrame).toBe(capFrame + 1)
	end)

	it("a re-entry mid-exit reverses from the value it had, without a jump", function()
		local core, env, clock = world()
		local on = core:signal(true)
		local _, adapter = attach(core, env, clock, whenScreen(on, FADE))
		for _ = 1, 60 do
			clock:step(FRAME)
		end
		local group = adapter.node("/S/Gate/then/Panel")
		on:set(false)
		-- the exit now defaults to `dismiss` (transitions round 2026-09-12) and the
		-- re-entry retunes it back to `container` (the enter class) — a much
		-- softer spring inheriting a much stiffer one's velocity. 4 frames into
		-- the exit is where that handoff lands mid-flight with room on every
		-- assertion below (measured); at 6 (the old frame count, right for a
		-- symmetric `container`/`container` exit) the softer re-entry spring is
		-- already outrun by the inherited velocity within its first step, which
		-- is a property of the class swap, not a broken invariant.
		for _ = 1, 4 do
			clock:step(FRAME)
		end
		local mid = group.canvasGroupInstance.groupTransparency
		expect(mid > 0 and mid < 1).toBe(true)
		on:set(true)
		clock:step(FRAME)
		-- NO JUMP: the reversal continues from the value the exit had reached...
		local first = group.canvasGroupInstance.groupTransparency
		expect(math.abs(first - mid) < 0.05).toBe(true)
		-- ...and it carries the VELOCITY too, which is why the very next frame is
		-- still drifting outward by a hair before the spring turns it round. A
		-- tween-shaped implementation would hard-cut here and read as a stutter.
		expect(first > mid).toBe(true)
		clock:step(FRAME)
		expect(group.canvasGroupInstance.groupTransparency < first).toBe(true)
		for _ = 1, 90 do
			clock:step(FRAME)
		end
		expect(group.canvasGroupInstance.groupTransparency).toBe(0)
	end)

	it("an `instant` exit never retires at all", function()
		local core, env, clock = world()
		local on = core:signal(true)
		local root = attach(core, env, clock, whenScreen(on, { enter = "fade", exit = "instant" }))
		local gate = root.node.children[1]
		on:set(false)
		expect(#gate.children).toBe(0) -- disposed on the spot
	end)
end)

describe("transition coordinator: event-sampled slides", function()
	it("mounted When and ForEach sample structural declarations without subscribing or scheduling solves", function()
		for _, kind in { "When", "ForEach" } do
			local core = customFactory.new()
			local on = core:signal(true)
			local items = core:signal({ "a" })
			local declared = core:signal({ enter = "slide-left", distance = 400 })
			local sampled = nil
			local collaborator = scripted()
			collaborator.coordinator.shouldRetire = function(_, node)
				sampled = transitionsLib.resolve(node.transition)
				return sampled
			end
			local function row()
				return UI.Box({ id = "Page" })
			end
			local region = if kind == "When"
				then UI.When({ id = "Region", condition = on, thenView = row, transition = declared })
				else UI.ForEach({
					id = "Region",
					items = items,
					key = function(item)
						return item
					end,
					row = row,
					transition = declared,
				})
			local root = mountLib.mount(core, UI.Screen({ id = "S", children = { region } }), {
				transitions = collaborator.coordinator,
			})
			local dirty, counters = root.dirtySeq(), root.counters()
			-- Only condition/items owns an observer; transition is read at the event.
			expect(core:counters().observers).toBe(1)
			local calls = #collaborator.calls
			declared:set({ enter = "slide-right", distance = 800 })
			expect(root.dirtySeq()).toBe(dirty)
			expect(root.counters().factoryRuns).toBe(counters.factoryRuns)
			expect(#collaborator.calls).toBe(calls)
			expect(UI.PROP_DIRTY[kind].transition[1]).toBe("structure")
			if kind == "When" then
				on:set(false)
			else
				items:set({})
			end
			expect(sampled.enter).toBe("slide-right")
			expect(sampled.distance).toBe(800)
			expect(root.dirtySeq() > dirty).toBe(true)
			root.dispose()
			declared:dispose()
			on:dispose()
			items:dispose()
		end
	end)
	local function slideWorld()
		local core, _, clock = world()
		local painted = { x = 0, y = 0 }
		local progress = nil
		local spring = clock.spring
		clock.spring = function(self, ...)
			progress = spring(self, ...)
			return progress
		end
		local coordinator = transitionsLib.new({
			core = core,
			clock = clock,
			controller = {
				setPresentationTransform = function(_, value)
					painted = value or { x = 0, y = 0 }
				end,
			},
		})
		return core, clock, coordinator, function()
			return painted, progress
		end
	end

	it("samples and validates a readable only when an operation starts", function()
		local core, clock, coordinator, read = slideWorld()
		local declared = core:signal({ enter = "slide-left", exit = "slide-left", distance = 400 })
		local node = { props = {}, transition = declared }
		coordinator.beginEnter("/Page", node, declared)
		expect(read().x).toBe(400)
		declared:set({ enter = "slide-right", exit = "slide-right", distance = 800 })
		-- Publishing a new declaration does not steer an active flight.
		expect(read().x).toBe(400)
		local snapshot = coordinator.shouldRetire("/Page", node)
		expect(snapshot.distance).toBe(800)
		expect(snapshot.exit).toBe("slide-right")
		declared:set({ enter = "sideways" })
		expect(function()
			coordinator.shouldRetire("/Page", node)
		end).toThrow()
		declared:set({ enter = "slide-left", distance = math.huge })
		expect(function()
			coordinator.shouldRetire("/Page", node)
		end).toThrow()
		expect(read().x).toBe(400)
		coordinator.dispose()
		clock:dispose()
		declared:dispose()
	end)

	it("reversing a slide mid-enter preserves its painted position and pixel velocity", function()
		local _, clock, coordinator, read = slideWorld()
		local node = { props = {} }
		local spec = transitionsLib.resolve({ enter = "slide-left", exit = "slide-left", distance = 400 })
		coordinator.beginEnter("/Page", node, spec)
		for _ = 1, 5 do
			clock:step(FRAME)
		end
		local before, progress = read()
		local x, velocity = before.x, -400 * progress:getVelocity()
		local done = 0
		coordinator.beginExit("/Page", node, spec, function()
			done += 1
		end)
		local after, redirected = read()
		expect(math.abs(after.x - x) < 1e-8).toBe(true)
		expect(math.abs(400 * redirected:getVelocity() - velocity) < 1e-8).toBe(true)
		clock:step(FRAME)
		expect(read().x < x).toBe(true)
		for _ = 1, 90 do
			clock:step(FRAME)
		end
		expect(done).toBe(1)
		coordinator.dispose()
		clock:dispose()
	end)

	--[[ PARKED MEANS PARKED (final review item 8). `cancelExit` says it parks the
		motion where it stands, and it stopped the cap, cleared the completion and
		named the phase — but left the spring still AIMED at 0, the exit's own
		target. Every caller in `mount.luau` follows it with `beginEnter` on the
		next line, whose aim replaces that one, so no shipped path ever saw the
		difference; the seam is public on the coordinator all the same, and a
		comment that describes a behaviour the code does not have is the kind of
		claim the next reader builds on. Aim it where it is: the value is unchanged
		and the velocity survives a retarget, so the reversal below still reverses
		from exactly this value AND this velocity. ]]
	it("cancelExit alone parks the motion instead of letting the exit finish", function()
		local _, clock, coordinator, read = slideWorld()
		local node = { props = {} }
		local outward = transitionsLib.resolve({ enter = "slide-left", exit = "slide-left", distance = 400 })
		coordinator.beginExit("/Page", node, outward, function()
			error("cancelled exit completed")
		end)
		for _ = 1, 5 do
			clock:step(FRAME)
		end
		local parked = read().x
		expect(`moving when cancelled: {parked ~= 0 and parked ~= -400}`).toBe("moving when cancelled: true")
		coordinator.cancelExit("/Page")
		for _ = 1, 120 do
			clock:step(FRAME)
		end
		expect(`still where it stood: {math.abs(read().x - parked) < 1e-6}`).toBe("still where it stood: true")
		coordinator.dispose()
		clock:dispose()
	end)

	it("returning mid-exit samples a new width without jumping or restarting velocity", function()
		local _, clock, coordinator, read = slideWorld()
		local node = { props = {} }
		local outward = transitionsLib.resolve({ enter = "slide-left", exit = "slide-left", distance = 400 })
		coordinator.beginExit("/Page", node, outward, function()
			error("cancelled exit completed")
		end)
		for _ = 1, 5 do
			clock:step(FRAME)
		end
		local before, progress = read()
		local x, velocity = before.x, 400 * progress:getVelocity()
		coordinator.cancelExit("/Page")
		coordinator.beginEnter("/Page", node, { enter = "slide-right", distance = 700 })
		local after, redirected = read()
		expect(math.abs(after.x - x) < 1e-8).toBe(true)
		expect(math.abs(700 * redirected:getVelocity() - velocity) < 1e-8).toBe(true)
		for _ = 1, 120 do
			clock:step(FRAME)
		end
		expect(read().x).toBe(0)
		expect(clock:activeCount()).toBe(0)
		coordinator.dispose()
		clock:dispose()
	end)
end)

describe("transition coordinator: reduced motion is parity, not deletion", function()
	it("an enter lands on the frame it starts and still emits arrive", function()
		local core, env, clock = world(true)
		local events: { any } = {}
		local on = core:signal(true)
		local _, adapter = attach(core, env, clock, whenScreen(on, FADE), function(event: any)
			table.insert(events, event)
		end)
		expect(#events).toBe(1)
		expect(events[1].type).toBe("arrive")
		expect(events[1].path).toBe("/S/Gate/then/Panel")
		expect(adapter.node("/S/Gate/then/Panel").canvasGroupInstance.groupTransparency).toBe(0)
		expect(clock:activeCount()).toBe(0)
	end)

	it("an exit completes in the frame it begins — the beat is instant, never dropped", function()
		local core, env, clock = world(true)
		local on = core:signal(true)
		local root = attach(core, env, clock, whenScreen(on, FADE))
		local gate = root.node.children[1]
		on:set(false)
		expect(#gate.children).toBe(0)
		expect(clock:activeCount()).toBe(0) -- and nothing is left running
	end)

	it("the full-motion path emits the same arrive, one frame later than the pixels", function()
		local core, env, clock = world()
		local events: { any } = {}
		local on = core:signal(true)
		attach(core, env, clock, whenScreen(on, FADE), function(event: any)
			table.insert(events, event)
		end)
		expect(#events).toBe(0)
		for _ = 1, 90 do
			clock:step(FRAME)
		end
		expect(#events).toBe(1)
		expect(events[1].type).toBe("arrive")
	end)
end)

-- ===== the presenter =======================================================

--[[ ONE SUBSTRATE (reuse audit REUSE-88, controller ruling R12).
	`tests/lib/world.luau` owns the construction and its two invariants — the
	viewport is set before anything can solve, and one presenter per adapter. The
	tuple order here, `core, env, adapter, system, pres`, is the one
	`Facet.newPresenter` itself takes and is now the only one in the suite: twelve
	files used to swap positions three and four with the same five names, so a line
	copied between two neighbouring specs bound an action system to a variable
	called `adapter` and said nothing. ]]
local function presenterWorld()
	local w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 844 } })
	return w.core, w.env, w.adapter, w.system, w.pres
end

describe("presenter: a retiring subtree is not interactive", function()
	it("focus order drops the branch the moment it starts to exit, and taps stop landing", function()
		local core, _, adapter, _, pres = presenterWorld()
		local on = core:signal(true)
		local activated: { string } = {}
		local handle = pres.present(
			UI.Screen({
				id = "S",
				children = {
					UI.Button({ id = "Keep", label = "Keep" }),
					UI.When({
						id = "Gate",
						condition = on,
						transition = FADE,
						thenView = function()
							return UI.ZStack({
								id = "Panel",
								canvasGroup = true,
								children = { UI.Button({ id = "Go", label = "Go" }) },
							})
						end,
					}),
				},
			}),
			{
				onActivate = function(path: string?)
					table.insert(activated, tostring(path))
				end,
			}
		)
		pres.refresh()
		adapter.tap("/S/Gate/then/Panel/Go")
		expect(#activated).toBe(1)

		on:set(false)
		pres.refresh()
		-- still mounted (it is fading), and no longer reachable by either paradigm
		expect(handle.root.node.children[2].children[1].retiring).toBe(true)
		adapter.tap("/S/Gate/then/Panel/Go")
		expect(#activated).toBe(1) -- the tap was swallowed
		pres.focus.focusOn("/S/Keep")
		local order: { string } = {}
		for _ = 1, 4 do
			pres.focus.navigate(1)
			table.insert(order, tostring(pres.focus.focused:get()))
		end
		for _, path in order do
			expect(string.find(path, "/Gate/", 1, true)).toBeNil()
		end
		pres.dismiss(handle)
	end)
end)

describe("presenter: a surface transition", function()
	local function surface(id: string)
		return UI.Screen({
			id = id,
			children = {
				UI.ZStack({
					id = "Content",
					canvasGroup = true,
					children = { UI.Button({ id = "Ok", label = "Ok" }) },
				}),
			},
		})
	end

	it("targets the root's declared fade group and enters on the first frame", function()
		local _, _, adapter, _, pres = presenterWorld()
		local handle = pres.present(surface("Sheet"), { transition = { enter = "fade" } })
		expect(handle.transitionNode.path).toBe("/Sheet/Content")
		expect(adapter.node("/Sheet/Content").canvasGroupInstance.groupTransparency).toBe(1)
		for _ = 1, 90 do
			pres.tick(FRAME)
		end
		expect(adapter.node("/Sheet/Content").canvasGroupInstance.groupTransparency).toBe(0)
	end)

	it("dismiss leaves the stack immediately and the screen late", function()
		local _, _, adapter, _, pres = presenterWorld()
		local handle = pres.presentModal(surface("Modal"), { transition = { enter = "fade" } })
		for _ = 1, 90 do
			pres.tick(FRAME)
		end
		expect(pres.depth()).toBe(1)
		pres.dismiss(handle)
		-- gone from the stack, its context destroyed, its focus scope popped...
		expect(pres.depth()).toBe(0)
		expect(handle.context.destroyed).toBe(true)
		-- ...but still on screen, fading
		expect(adapter.node("/Modal/Content") ~= nil).toBe(true)
		for _ = 1, 90 do
			pres.tick(FRAME)
		end
		expect(adapter.node("/Modal/Content")).toBeNil()
	end)

	it("the deferred teardown is bounded by the same flat cap", function()
		local _, _, adapter, _, pres = presenterWorld()
		-- exitClass pinned to `decay` too: the exit otherwise defaults to the
		-- faster `dismiss` and would settle well before the cap, proving nothing
		local handle =
			pres.present(surface("Slow"), { transition = { enter = "fade", class = "decay", exitClass = "decay" } })
		for _ = 1, 200 do
			pres.tick(FRAME)
		end
		pres.dismiss(handle)
		for _ = 1, 29 do
			pres.tick(1 / 60)
		end
		expect(adapter.node("/Slow/Content") ~= nil).toBe(true)
		for _ = 1, 3 do
			pres.tick(1 / 60)
		end
		expect(adapter.node("/Slow/Content")).toBeNil()
	end)

	it("a same-id re-present during a deferred exit tears the first surface down first", function()
		--[[ THE ORPHAN (task 7 item 2). A dismissed surface leaves the stack
			SYNCHRONOUSLY and the screen up to 500 ms later, and a control that
			owns its own handle (Alert's `dismiss()` clears `handle` on the spot,
			Menu's `close()` likewise) is free to present again in the very next
			frame. The second surface mounts under the SAME blueprint id, so it
			takes over every node path the first one still occupies — and the
			first one's deferred teardown then walks a tree whose paths belong to
			somebody else and removes nothing. Measured before the fix: the
			round's own `alert-present-dismiss` scene steady-stated at ~12
			mounted alerts, and the fake adapter's root count climbed one per
			cycle and never came down.

			So a pending exit is now held by the id it is exiting under, and a
			present under that id runs it FIRST — the old instances go, the new
			ones mount clean. The 500 ms grace is for a surface nobody is
			replacing. ]]
		local _, _, adapter, _, pres = presenterWorld()
		local rootsBefore = adapter.rootCount()
		local first = pres.present(surface("Modal"), { transition = { enter = "fade" } })
		for _ = 1, 90 do
			pres.tick(FRAME)
		end
		local firstNode = adapter.node("/Modal/Content")
		expect(firstNode.alive).toBe(true)
		pres.dismiss(first)
		-- well inside the exit: the first surface is still on screen, fading
		for _ = 1, 5 do
			pres.tick(FRAME)
		end
		expect(firstNode.alive).toBe(true)
		expect(adapter.rootCount()).toBe(rootsBefore + 1)

		local second = pres.present(surface("Modal"), { transition = { enter = "fade" } })
		-- the corpse is gone on the spot, not 25 frames from now
		expect(firstNode.alive).toBe(false)
		local secondNode = adapter.node("/Modal/Content")
		expect(secondNode ~= nil and secondNode ~= firstNode).toBe(true)
		expect(adapter.rootCount()).toBe(rootsBefore + 1)
		for _ = 1, 60 do
			pres.tick(FRAME)
		end
		-- ...and the first surface's own deferred teardown, whenever it would
		-- have run, takes nothing of the second one's with it
		expect(adapter.node("/Modal/Content")).toBe(secondNode)
		expect(secondNode.alive).toBe(true)
		expect(adapter.rootCount()).toBe(rootsBefore + 1)
		expect(pres.depth()).toBe(1)

		pres.dismiss(second)
		for _ = 1, 60 do
			pres.tick(FRAME)
		end
		expect(adapter.rootCount()).toBe(rootsBefore)
	end)

	it("TWO surfaces exiting under one id are BOTH flushed by the next present (review N7)", function()
		--[[ the pending teardowns were held one-per-id, so a second registration
			under the same key overwrote the first: the overwritten one still ran
			on its own settle or cap, but it was no longer reachable by the flush
			— which is the whole point of the map. Nothing stops two surfaces
			sharing a blueprint id while both are LIVE (the flush only runs when
			one is already exiting), so dismissing both leaves two pending under
			one key. The key holds a list now, and the flush drains it. ]]
		local _, _, adapter, _, pres = presenterWorld()
		local rootsBefore = adapter.rootCount()
		local first = pres.present(surface("Modal"), { transition = { enter = "fade" } })
		local second = pres.present(surface("Modal"), { transition = { enter = "fade" } })
		for _ = 1, 90 do
			pres.tick(FRAME)
		end
		expect(adapter.rootCount()).toBe(rootsBefore + 2)
		pres.dismiss(first)
		pres.dismiss(second)
		for _ = 1, 5 do
			pres.tick(FRAME)
		end
		-- both are still on screen, both still exiting under the same id
		expect(adapter.rootCount()).toBe(rootsBefore + 2)

		local third = pres.present(surface("Modal"), { transition = { enter = "fade" } })
		-- ...and BOTH corpses go, not just the last one registered
		expect(adapter.rootCount()).toBe(rootsBefore + 1)
		for _ = 1, 60 do
			pres.tick(FRAME)
		end
		expect(adapter.rootCount()).toBe(rootsBefore + 1)
		expect(pres.depth()).toBe(1)
		pres.dismiss(third)
		for _ = 1, 60 do
			pres.tick(FRAME)
		end
		expect(adapter.rootCount()).toBe(rootsBefore)
	end)

	it("ten present/dismiss cycles under one id leave one surface, not ten", function()
		local _, _, adapter, _, pres = presenterWorld()
		local rootsBefore = adapter.rootCount()
		local handle = nil
		for _ = 1, 10 do
			if handle ~= nil then
				pres.dismiss(handle)
			end
			handle = pres.present(surface("Modal"), { transition = { enter = "fade" } })
			-- three frames apart: a player double-tapping, and far inside the
			-- 30-frame exit
			for _ = 1, 3 do
				pres.tick(FRAME)
			end
		end
		expect(adapter.rootCount()).toBe(rootsBefore + 1)
		pres.dismiss(handle)
		for _ = 1, 60 do
			pres.tick(FRAME)
		end
		expect(adapter.rootCount()).toBe(rootsBefore)
	end)

	it("surfaces without a transition tear down synchronously, exactly as before", function()
		local _, _, adapter, _, pres = presenterWorld()
		local handle = pres.present(surface("Plain"))
		pres.dismiss(handle)
		expect(adapter.node("/Plain/Content")).toBeNil()
	end)
end)

describe("transition coordinator: exits are faster than enters by default", function()
	local function framesUntilIdle(clock: any): number
		local n = 0
		while clock:activeCount() > 0 and n < 600 do
			clock:step(FRAME)
			n += 1
		end
		return n
	end

	it("a default fade exits in fewer frames than it entered", function()
		local core, env, clock = world()
		local on = core:signal(true)
		local root, _, controller, coordinator = attach(core, env, clock, whenScreen(on, { enter = "fade" }))
		local enterFrames = framesUntilIdle(clock)
		on:set(false)
		local exitFrames = framesUntilIdle(clock)
		controller.refresh()
		expect(enterFrames > 0).toBe(true)
		expect(exitFrames < enterFrames).toBe(true)
		root.dispose()
		coordinator.dispose()
		clock:dispose()
	end)

	it("exitClass restores symmetry when declared", function()
		--[[ SYMMETRY IS A PACE, READ OFF THE PAINT. This used to count frames
			until the clock went idle, which stopped being the right instrument
			once the exit phase got its own settle epsilon (task 7 item 1): the
			two directions then idle 6 frames apart on `reward` while painting
			the SAME trajectory — the difference is entirely in the invisible
			tail (reward's progress is 0.0003 at the earlier of the two). The
			claim `exitClass` actually makes is about the motion a player sees,
			so the pin is the frame the fade CROSSES 95% in each direction.

			`reward` (not `container`): the flat 500 ms exit cap already
			truncates a `container` exit, so pairing class/exitClass on it would
			prove the CAP fired identically on both sides rather than that
			exitClass restored the spring's own symmetric timing. ]]
		local enterCross, exitCross = fadeFrames("reward", "reward")
		expect(enterCross).toBe(5)
		expect(exitCross).toBe(enterCross)
	end)

	it("a re-entry mid-exit keeps its velocity across the retune", function()
		local core, env, clock = world()
		local on = core:signal(true)
		local root, adapter, _, coordinator = attach(core, env, clock, whenScreen(on, { enter = "fade" }))
		for _ = 1, 90 do
			clock:step(FRAME)
		end
		on:set(false)
		for _ = 1, 4 do
			clock:step(FRAME)
		end
		local panel = adapter.node("/S/Gate/then/Panel")
		local midway = panel.canvasGroupInstance.groupTransparency
		expect(midway > 0 and midway < 1).toBe(true)
		on:set(true)
		-- the value is continuous across the class swap: no jump on the reversal frame
		expect(panel.canvasGroupInstance.groupTransparency).toBe(midway)
		for _ = 1, 90 do
			clock:step(FRAME)
		end
		expect(panel.canvasGroupInstance.groupTransparency).toBe(0)
		expect(clock:activeCount()).toBe(0)
		root.dispose()
		coordinator.dispose()
		clock:dispose()
	end)

	it("resolve fills exitClass with dismiss and refuses a non-string", function()
		local spec = transitionsLib.resolve({ enter = "fade" })
		expect(spec.class).toBe("container")
		expect(spec.exitClass).toBe("dismiss")
		-- both defaults are PUBLISHED, for the same reason `DEFAULT_CLASS` is: a
		-- consumer that must mirror one (navigation_stack pins exitClass to the
		-- page class rather than let it drift) reads it instead of copying the
		-- string (review finding 13)
		expect(transitionsLib.DEFAULT_CLASS).toBe(spec.class)
		expect(transitionsLib.DEFAULT_EXIT_CLASS).toBe(spec.exitClass)
		local ok, err = pcall(transitionsLib.resolve, { enter = "fade", exitClass = 3 })
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "exitClass", 1, true) ~= nil).toBe(true)
	end)

	it("a fresh transition builds ONE spring, not one it throws away", function()
		--[[ review finding 9: `entryFor` used to construct `spec.class`
			unconditionally and the `retune` on the very next line replaced it —
			one MotionValue built, observed and disposed per transition for
			nothing, which on a 600-row retire is 600 of them. The entry is now
			built with the phase's own class AND epsilon, so the retune no-ops on
			the fresh path and only a REVERSAL (enter↔exit, which really does
			change both) pays for a replacement. ]]
		local core, env, clock = world()
		local built = 0
		local realSpring = clock.spring
		clock.spring = function(...)
			built += 1
			return realSpring(...)
		end
		local on = core:signal(true)
		local root, _, _, coordinator = attach(core, env, clock, whenScreen(on, FADE))
		expect(built).toBe(1) -- the mount-time enter
		for _ = 1, 60 do
			clock:step(FRAME)
		end
		on:set(false)
		expect(built).toBe(2) -- the exit: a fresh entry at `dismiss`, no retune
		for _ = 1, 60 do
			clock:step(FRAME)
		end
		root.dispose()
		coordinator.dispose()
		clock:dispose()
	end)
end)

--[[ STAGGER: A LIST'S ENTRANCE IS A RHYTHM (spec 2F). Rows arriving together
	step in one after another instead of landing as one slab. Four properties are
	pinned here, and they are the whole feature:

	  1. the delay is REAL and ORDERED — a later row has not moved on a frame an
	     earlier one has, and no row starts before its own delay;
	  2. it is ENTER-ONLY — an exit is a dismissal, and a list that leaves one row
	     at a time reads as a stall rather than a rhythm;
	  3. reduced motion deletes the rhythm, not the information — every row lands
	     on the first frame, with nothing left running;
	  4. the WAIT is capped — past `STAGGER_CAP` rows the delay stops growing, so
	     the last row of a 600-row list enters 400 ms in rather than half a minute
	     later.

	The delays themselves are read off `clock:timer` rather than off alpha
	wherever the number is the claim: a painted alpha can only say "has moved",
	which cannot tell 0.4 s from 0.55 s. ]]
describe("transition coordinator: stagger", function()
	local function rowsScreen(items: any, on: any, stagger: number?)
		return UI.Screen({
			id = "S",
			children = {
				UI.When({
					id = "Gate",
					condition = on,
					thenView = function()
						return UI.ForEach({
							id = "List",
							items = items,
							key = function(item: any): string
								return item.id
							end,
							transition = { enter = "fade", stagger = stagger },
							row = function(item: any)
								return UI.ZStack({
									id = "Row",
									canvasGroup = true,
									children = { UI.Text({ id = "T", text = item.id }) },
								})
							end,
						})
					end,
				}),
			},
		})
	end
	-- the same shape with a SECOND keyed list inside each row. Only the inner
	-- list staggers, so the outer rows all enter on frame one and the only
	-- rhythm under test is the one the inner batches keep.
	local function nestedScreen(rows: any, cells: any, on: any, stagger: number)
		return UI.Screen({
			id = "S",
			children = {
				UI.When({
					id = "Gate",
					condition = on,
					thenView = function()
						return UI.ForEach({
							id = "List",
							items = rows,
							key = function(item: any): string
								return item.id
							end,
							row = function()
								return UI.ZStack({
									id = "Row",
									children = {
										UI.ForEach({
											id = "Inner",
											items = cells,
											key = function(cell: any): string
												return cell.id
											end,
											transition = { enter = "fade", stagger = stagger },
											row = function(cell: any)
												return UI.ZStack({
													id = "Cell",
													canvasGroup = true,
													children = { UI.Text({ id = "T", text = cell.id }) },
												})
											end,
										}),
									},
								})
							end,
						})
					end,
				}),
			},
		})
	end
	local function alphaOf(adapter: any, key: string): number
		return adapter.node(`/S/Gate/then/List/[{key}]/Row`).canvasGroupInstance.groupTransparency
	end
	-- the booked delays, in the order the coordinator books them: the ONE
	-- instrument that can say how long a row waited rather than merely that it
	-- did. The exit cap is the only other timer this coordinator books, and it is
	-- the one duration a hold can never take (eight beats of 0.05 is 0.4).
	local function recordHolds(clock: any): { number }
		local booked: { number } = {}
		local realTimer = clock.timer
		clock.timer = function(this: any, spec: any)
			if spec.duration ~= transitionsLib.EXIT_CAP_SECONDS then
				table.insert(booked, spec.duration)
			end
			return realTimer(this, spec)
		end
		return booked
	end

	it("later rows start later, and none starts before its delay", function()
		local core, env, clock = world()
		local items = core:signal({ { id = "a" }, { id = "b" }, { id = "c" } })
		local on = core:signal(true)
		local root, adapter, _, coordinator = attach(core, env, clock, rowsScreen(items, on, 0.05))
		-- every row is painted ABSENT before the first frame — a held row waits at
		-- the absent place, never at rest with a pop to follow
		expect(alphaOf(adapter, "a")).toBe(1)
		expect(alphaOf(adapter, "b")).toBe(1)
		expect(alphaOf(adapter, "c")).toBe(1)
		clock:step(FRAME)
		expect(alphaOf(adapter, "a") < 1).toBe(true)
		expect(alphaOf(adapter, "b")).toBe(1)
		expect(alphaOf(adapter, "c")).toBe(1)
		for _ = 1, 3 do
			clock:step(FRAME)
		end -- 4 frames ~ 67 ms > 50 ms: b has started, c (100 ms) has not
		expect(alphaOf(adapter, "b") < 1).toBe(true)
		expect(alphaOf(adapter, "c")).toBe(1)
		for _ = 1, 120 do
			clock:step(FRAME)
		end
		expect(alphaOf(adapter, "c")).toBe(0)
		expect(clock:activeCount()).toBe(0)
		root.dispose()
		coordinator.dispose()
		clock:dispose()
	end)

	--[[ A KEY IS THE AUTHOR'S STRING, AND A `/` IN IT IS ORDINARY (final review
		item 6). The batch is "the path with the row's own segment and the keyed
		segment above it removed", and the keyed segment was matched as
		`/%[[^/]*%]$` — a bracket group that may not contain a slash. A ForEach
		keyed by anything path-shaped (`world/moss`, a route, an asset id) failed
		that match, so every row kept its own parent, every row was the first of
		its own batch, and the stagger silently did nothing. Silently is the whole
		problem: the rows still enter, all at once, and nothing says a word. ]]
	it("a key containing a slash still shares one batch, so the rhythm survives it", function()
		local core, env, clock = world()
		local items = core:signal({ { id = "world/moss" }, { id = "world/fen" } })
		local on = core:signal(true)
		local root, adapter, _, coordinator = attach(core, env, clock, rowsScreen(items, on, 0.05))
		expect(alphaOf(adapter, "world/moss")).toBe(1)
		expect(alphaOf(adapter, "world/fen")).toBe(1)
		clock:step(FRAME)
		expect(`first moving: {alphaOf(adapter, "world/moss") < 1}`).toBe("first moving: true")
		expect(`second held: {alphaOf(adapter, "world/fen") == 1}`).toBe("second held: true")
		for _ = 1, 120 do
			clock:step(FRAME)
		end
		expect(alphaOf(adapter, "world/fen")).toBe(0)
		expect(clock:activeCount()).toBe(0)
		root.dispose()
		coordinator.dispose()
		clock:dispose()
	end)

	--[[ ...AND SO IS A BRACKET (R1, final re-review). The slash fix matched the
		keyed segment as `%b[]` — a BALANCED bracket group — which is right for
		every key that contains no bracket of its own and wrong for every key that
		does. `"a]b"` builds `<list>/[a]b]`, where `%b[]` matches `[a]` and then
		fails the anchor; `"a[b"` builds `<list>/[a[b]`, which never balances at
		all. Both fall back to the row's own parent, which is the exact silent
		no-stagger the slash fix existed to remove. A key is the author's string:
		the segment is "a `[`, anything at all, a `]`", taken at the RIGHTMOST
		slash that can start one. ]]
	it("a key containing a bracket still shares one batch", function()
		local core, env, clock = world()
		local items = core:signal({ { id = "a]b" }, { id = "a[b" } })
		local on = core:signal(true)
		local root, adapter, _, coordinator = attach(core, env, clock, rowsScreen(items, on, 0.05))
		expect(alphaOf(adapter, "a]b")).toBe(1)
		expect(alphaOf(adapter, "a[b")).toBe(1)
		clock:step(FRAME)
		expect(`first moving: {alphaOf(adapter, "a]b") < 1}`).toBe("first moving: true")
		expect(`second held: {alphaOf(adapter, "a[b") == 1}`).toBe("second held: true")
		for _ = 1, 120 do
			clock:step(FRAME)
		end
		expect(alphaOf(adapter, "a[b")).toBe(0)
		expect(clock:activeCount()).toBe(0)
		root.dispose()
		coordinator.dispose()
		clock:dispose()
	end)

	--[[ A NESTED KEYED LIST BATCHES AT THE INNER LIST (R1's other half). The
		capture is greedy, so it takes the RIGHTMOST slash whose remainder is a
		bracket group: `<list>/[A]/Row/Inner/[two]` resolves to
		`<list>/[A]/Row/Inner`, and each outer row's inner list keeps its own
		rhythm. Resolved at the OUTER list instead, the second row's FIRST cell
		would inherit the first row's count and wait a beat it never asked for. ]]
	it("a nested keyed list batches at the inner list, one rhythm per outer row", function()
		local core, env, clock = world()
		local rows = core:signal({ { id = "A" }, { id = "B" } })
		local cells = core:signal({ { id = "one" }, { id = "two" } })
		local on = core:signal(true)
		local root, adapter, _, coordinator = attach(core, env, clock, nestedScreen(rows, cells, on, 0.05))
		local function cellAlpha(row: string, cell: string): number
			local path = `/S/Gate/then/List/[{row}]/Row/Inner/[{cell}]/Cell`
			return adapter.node(path).canvasGroupInstance.groupTransparency
		end
		expect(cellAlpha("A", "one")).toBe(1)
		clock:step(FRAME)
		-- the FIRST cell of EACH row moves; the second of each waits its own beat
		expect(`A/one moving: {cellAlpha("A", "one") < 1}`).toBe("A/one moving: true")
		expect(`B/one moving: {cellAlpha("B", "one") < 1}`).toBe("B/one moving: true")
		expect(`A/two held: {cellAlpha("A", "two") == 1}`).toBe("A/two held: true")
		expect(`B/two held: {cellAlpha("B", "two") == 1}`).toBe("B/two held: true")
		for _ = 1, 120 do
			clock:step(FRAME)
		end
		expect(cellAlpha("B", "two")).toBe(0)
		expect(clock:activeCount()).toBe(0)
		root.dispose()
		coordinator.dispose()
		clock:dispose()
	end)

	it("exits never stagger", function()
		local core, env, clock = world()
		local items = core:signal({ { id = "a" }, { id = "b" }, { id = "c" } })
		local on = core:signal(true)
		local booked = recordHolds(clock)
		local root, adapter, _, coordinator = attach(core, env, clock, rowsScreen(items, on, 0.05))
		for _ = 1, 120 do
			clock:step(FRAME)
		end
		expect(alphaOf(adapter, "c")).toBe(0)
		expect(#booked).toBe(2) -- the enter's two held rows, and nothing since
		items:set({})
		clock:step(FRAME)
		expect(alphaOf(adapter, "a") > 0).toBe(true)
		expect(alphaOf(adapter, "b") > 0).toBe(true)
		expect(alphaOf(adapter, "c") > 0).toBe(true)
		expect(#booked).toBe(2) -- the exit booked no hold at all
		root.dispose()
		coordinator.dispose()
		clock:dispose()
	end)

	it("reduced motion lands every row on the first frame", function()
		local core, env, clock = world(true)
		local items = core:signal({ { id = "a" }, { id = "b" }, { id = "c" } })
		local on = core:signal(true)
		local booked = recordHolds(clock)
		local root, adapter, _, coordinator = attach(core, env, clock, rowsScreen(items, on, 0.05))
		expect(alphaOf(adapter, "a")).toBe(0)
		expect(alphaOf(adapter, "c")).toBe(0)
		expect(#booked).toBe(0)
		expect(clock:activeCount()).toBe(0)
		root.dispose()
		coordinator.dispose()
		clock:dispose()
	end)

	it("the wait is capped, so a long list's last row is not half a minute late", function()
		local core, env, clock = world()
		local booked = recordHolds(clock)
		local list: { any } = {}
		for i = 1, 20 do
			table.insert(list, { id = `r{i}` })
		end
		local items = core:signal(list)
		local on = core:signal(true)
		local root, _, _, coordinator = attach(core, env, clock, rowsScreen(items, on, 0.05))
		expect(transitionsLib.STAGGER_CAP).toBe(8)
		-- row 1 waits for nothing, so 20 rows book 19 holds
		expect(#booked).toBe(19)
		expect(booked[1]).toBeCloseTo(0.05)
		expect(booked[8]).toBeCloseTo(8 * 0.05) -- row 9, the last distinct start
		expect(booked[19]).toBeCloseTo(8 * 0.05) -- row 20 rides in with row 9
		for _ = 1, 150 do
			clock:step(FRAME)
		end
		expect(clock:activeCount()).toBe(0)
		root.dispose()
		coordinator.dispose()
		clock:dispose()
	end)

	it("a held row's wait costs no writes at all", function()
		--[[ A MotionValue IS a core signal, so a hold that RAMPED 0 -> 1 would do a
			real `value:set` and a `countWrite()` on every frame of a wait nobody
			observes — only the settle event is ever read. The hold is flat
			(`from = to = 0`) and the value's own write gate then suppresses every
			write, so a staggered list and an unstaggered one spend the SAME
			writes: the twenty springs' own, and nothing else. At twenty rows the
			ramp would show up here as a few hundred; at the 600-row list the cap
			exists for, ~14k. `clock:stats().writes` is a measured gate. ]]
		local function writesFor(stagger: number?): number
			local core, env, clock = world()
			local list: { any } = {}
			for i = 1, 20 do
				table.insert(list, { id = `r{i}` })
			end
			local items = core:signal(list)
			local on = core:signal(true)
			local root, _, _, coordinator = attach(core, env, clock, rowsScreen(items, on, stagger))
			local before = clock:stats().writes
			for _ = 1, 200 do
				clock:step(FRAME)
			end
			expect(clock:activeCount()).toBe(0)
			local spent = clock:stats().writes - before
			root.dispose()
			coordinator.dispose()
			clock:dispose()
			return spent
		end
		-- the same twenty springs on the same twenty trajectories; the ONLY
		-- difference between the two runs is when each one starts
		local flat = writesFor(nil)
		expect(flat > 0).toBe(true)
		expect(writesFor(0.05)).toBe(flat)
	end)

	it("a batch is one clock step: rows added later start the rhythm over", function()
		local core, env, clock = world()
		local booked = recordHolds(clock)
		local items = core:signal({ { id = "a" }, { id = "b" } })
		local on = core:signal(true)
		local root, _, _, coordinator = attach(core, env, clock, rowsScreen(items, on, 0.05))
		expect(#booked).toBe(1)
		expect(booked[1]).toBeCloseTo(0.05)
		for _ = 1, 120 do
			clock:step(FRAME)
		end
		items:set({ { id = "a" }, { id = "b" }, { id = "c" }, { id = "d" } })
		-- c leads the NEW batch (no wait) and d follows it one beat later; if the
		-- counter carried over they would be the third and fourth of one long queue
		expect(#booked).toBe(2)
		expect(booked[2]).toBeCloseTo(0.05)
		for _ = 1, 120 do
			clock:step(FRAME)
		end
		expect(clock:activeCount()).toBe(0)
		root.dispose()
		coordinator.dispose()
		clock:dispose()
	end)

	it("a re-entry mid-exit reverses at once instead of waiting its turn", function()
		local core, env, clock = world()
		local booked = recordHolds(clock)
		local items = core:signal({ { id = "a" }, { id = "b" }, { id = "c" } })
		local on = core:signal(true)
		local root, adapter, _, coordinator = attach(core, env, clock, rowsScreen(items, on, 0.05))
		for _ = 1, 120 do
			clock:step(FRAME)
		end
		expect(#booked).toBe(2)
		items:set({})
		for _ = 1, 5 do
			clock:step(FRAME)
		end
		local midway = alphaOf(adapter, "c")
		expect(midway > 0 and midway < 1).toBe(true)
		items:set({ { id = "a" }, { id = "b" }, { id = "c" } })
		-- all three are ON SCREEN already, so none of them books a hold: the row
		-- that would have waited two beats is heading home on the very next frame
		-- rather than freezing part-faded until its turn came round
		expect(#booked).toBe(2)
		clock:step(FRAME)
		-- a HELD row paints the very same alpha on this frame and every frame
		-- until its turn; a reversing one is already moving (still outward here,
		-- on the momentum the exit carried in — which is the point of reversing
		-- through one continuous spring rather than restarting)
		expect(alphaOf(adapter, "c") ~= midway).toBe(true)
		for _ = 1, 10 do
			clock:step(FRAME)
		end
		expect(alphaOf(adapter, "c") < midway).toBe(true)
		for _ = 1, 120 do
			clock:step(FRAME)
		end
		expect(alphaOf(adapter, "c")).toBe(0)
		expect(clock:activeCount()).toBe(0)
		root.dispose()
		coordinator.dispose()
		clock:dispose()
	end)

	--[[ `scale` IS `distance`'S TWIN FOR THE SCALING FORM (A1, 2026-09-13). The
		engine rasterizes text at `floor(TextSize x effectiveScale)`, so a surface
		that is mostly type has to settle DOWN from just above 1 rather than grow
		from below it; the default stays the ratified 0.96 for everything else. ]]
	it("the schema takes a materialize's own scale, and refuses the ones that mean nothing", function()
		expect(transitionsLib.resolve({ enter = "materialize" }).scale).toBeNil()
		expect(transitionsLib.resolve({ enter = "materialize", scale = 1.015 }).scale).toBe(1.015)
		for _, bad in { 1, 0, -0.5, math.huge, "big" } do
			local ok, err = pcall(transitionsLib.resolve, { enter = "materialize", scale = bad })
			expect(ok).toBe(false)
			expect(string.find(tostring(err), "scale", 1, true) ~= nil).toBe(true)
		end
	end)

	it("an authored scale is the band the ENTER travels, and it starts there", function()
		local core, env, clock = world()
		local on = core:signal(true)
		local _, adapter = attach(core, env, clock, whenScreen(on, { enter = "materialize", scale = 1.015 }))
		local panel = adapter.node("/S/Gate/then/Panel")
		expect(panel.props.transform.scale).toBeCloseTo(1.015, 1e-6)
		clock:step(FRAME)
		-- it settles DOWN toward rest, and never crosses into the band where the
		-- engine would rasterize the type a pixel small
		expect(panel.props.transform.scale < 1.015).toBe(true)
		expect(panel.props.transform.scale >= 1).toBe(true)
		for _ = 1, 120 do
			clock:step(FRAME)
		end
		expect(panel.props.transform).toBeNil() -- cleared at rest
	end)

	--[[ …AND THE EXIT STILL DIPS (RED-TEAM F1). `scale` is an answer about the
		instant the text ARRIVES and is read; an exit is the opposite instant, the
		plate is already fading, and the shape the owner asked for is a dip out.
		Spent in both phases the alert SWELLED 1.5% on the way out. ]]
	it("...and the exit dips to the ratified band, whatever the enter declared", function()
		local core, env, clock = world()
		local on = core:signal(true)
		local _, adapter = attach(core, env, clock, whenScreen(on, { enter = "materialize", scale = 1.015 }))
		for _ = 1, 120 do
			clock:step(FRAME)
		end
		local panel = adapter.node("/S/Gate/then/Panel")
		expect(panel.props.transform).toBeNil()
		on:set(false)
		local lowest, highest = math.huge, -math.huge
		for _ = 1, 90 do
			clock:step(FRAME)
			local t = adapter.node("/S/Gate/then/Panel")
			local scale = if t ~= nil and t.props.transform ~= nil then t.props.transform.scale else nil
			if type(scale) == "number" then
				lowest = math.min(lowest, scale)
				highest = math.max(highest, scale)
			end
		end
		-- it went DOWN, toward the ratified dip, and never swelled past rest
		expect(lowest < 1).toBe(true)
		expect(lowest >= 0.96 - 1e-6).toBe(true)
		expect(highest <= 1 + 1e-6).toBe(true)
	end)

	it("the schema refuses a negative stagger, and resolve defaults it to zero", function()
		local ok, err = pcall(transitionsLib.resolve, { enter = "fade", stagger = -1 })
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "stagger", 1, true) ~= nil).toBe(true)
		expect(transitionsLib.resolve({ enter = "fade" }).stagger).toBe(0)
		expect(transitionsLib.resolve({ enter = "fade", stagger = 0.05 }).stagger).toBe(0.05)
	end)
end)

--[[ THE SYNTHESIZED SURFACE'S FADE GROUP IS NOT A DIRECT CHILD (task A2,
	live Studio 2026-09-12). `presenter.presentAnchored` synthesizes
	`Screen -> Anchor(Layer) -> VStack(Surface) -> <the caller's panel>`, so a
	pop-up menu's `canvasGroup` panel sits THREE levels under the root. The
	coordinator's alpha half already descends to it (`resolveAlphaTarget`), and
	the transition's TRANSFORM half did not: it wrote `scale`/`pivot` to the
	Screen root, whose live instance is a ScreenGui — not a `GuiObject`, so
	`screen_presentation.applyPresentationPaint` returns before it can
	materialize a UIScale, and the write vanished with no error. Measured on a
	live picker: the Popup faded 1 -> 0.02 and NOTHING ever scaled. ]]
describe("presenter: a transition on a surface whose fade group is nested", function()
	local function popupSurface(id: string)
		return UI.Screen({
			id = id,
			children = {
				UI.Anchor({
					id = "Layer",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						UI.VStack({
							id = "Surface",
							anchor = "topLeft",
							width = { type = "hug" },
							height = { type = "hug" },
							children = {
								UI.ZStack({
									id = "Popup",
									canvasGroup = true,
									surface = "raised",
									children = { UI.Button({ id = "Ok", label = "Ok" }) },
								}),
							},
						}),
					},
				}),
			},
		})
	end

	local POPUP = "/Pop/Layer/Surface/Popup"

	-- released (no transform at all) IS scale 1: the channel clears the UIScale
	-- at rest rather than leaving a settled 1 behind
	local function scaleOf(adapter: any, path: string): number
		local node = adapter.node(path)
		return if node ~= nil and node.motionScaleInstance ~= nil then node.motionScaleInstance.scale else 1
	end

	it("materialize scales AND fades the sole nested fade group, and never the root", function()
		local _, _, adapter, _, pres = presenterWorld()
		local handle = pres.present(popupSurface("Pop"), { transition = { enter = "materialize", pivot = "topRight" } })
		expect(handle.transitionNode.path).toBe(POPUP)
		pres.tick(FRAME)
		expect(scaleOf(adapter, POPUP) < 1).toBe(true)
		expect(adapter.node(POPUP).canvasGroupInstance.groupTransparency > 0).toBe(true)
		-- THE PIVOT REACHES THE NODE THAT SCALES. `topRight` is the corner an
		-- anchored popover hangs from, so the body grows out of it: the visual
		-- rect's top-right corner sits on the solved rect's while it is small.
		local mid = adapter.node(POPUP)
		expect(mid.presentedVisualRect ~= nil).toBe(true)
		expect(mid.presentedVisualRect.w < mid.rect.w).toBe(true)
		expect(mid.presentedVisualRect.x + mid.presentedVisualRect.w).toBeCloseTo(mid.rect.x + mid.rect.w, 1e-6)
		expect(mid.presentedVisualRect.y).toBeCloseTo(mid.rect.y, 1e-6)
		-- ...and the ScreenGui root, which cannot carry a UIScale at all, is untouched
		expect(scaleOf(adapter, "/Pop")).toBe(1)
		for _ = 1, 90 do
			pres.tick(FRAME)
		end
		expect(scaleOf(adapter, POPUP)).toBe(1)
		expect(adapter.node(POPUP).canvasGroupInstance.groupTransparency).toBe(0)
	end)

	it("a plain fade on the same shape still fades the nested group (alpha half unchanged)", function()
		local _, _, adapter, _, pres = presenterWorld()
		local handle = pres.present(popupSurface("Pop"), { transition = { enter = "fade" } })
		expect(handle.transitionNode.path).toBe(POPUP)
		expect(adapter.node(POPUP).canvasGroupInstance.groupTransparency).toBe(1)
		for _ = 1, 90 do
			pres.tick(FRAME)
		end
		expect(adapter.node(POPUP).canvasGroupInstance.groupTransparency).toBe(0)
		expect(scaleOf(adapter, POPUP)).toBe(1)
	end)

	it("two nested fade groups are ambiguous: the root stays the target", function()
		local _, _, _, _, pres = presenterWorld()
		local handle = pres.present(
			UI.Screen({
				id = "Two",
				children = {
					UI.Anchor({
						id = "Layer",
						children = {
							UI.ZStack({
								id = "A",
								canvasGroup = true,
								children = { UI.Text({ id = "T", text = "a" }) },
							}),
							UI.ZStack({
								id = "B",
								canvasGroup = true,
								children = { UI.Text({ id = "U", text = "b" }) },
							}),
						},
					}),
				},
			}),
			{ transition = { enter = "slide-up" } }
		)
		expect(handle.transitionNode.path).toBe("/Two")
		pres.dismiss(handle)
	end)
end)

--[[ THE 1.015 HEADROOM, PINNED AGAINST EVERY SIZE THIS FRAMEWORK CAN PAINT
	(RED-TEAM F10).

	`Controls.Alert`'s band is derived, not chosen: the engine rasterizes text at
	`floor(TextSize x effectiveScale)`, so a scale in `[1, 1 + 1/n)` floors to the
	same pixel for text of size `n` — and `1/0.015` is 66.7 px. api.md says that is
	above every size the framework can paint. This is the sweep that makes the
	sentence checkable instead of asserted: every shipped package's whole type
	ladder, at both display classes, at the largest preferred-text offset, through
	`text_metrics.reservedSize` — the same call the renderer's own measure seam
	makes. A package that ever authors a 67 px rung fails HERE, at the commit that
	introduces it, instead of on a television. ]]
describe("the alert's materialize band has headroom over the whole type ladder", function()
	local snapshot = require("../src/themes/snapshot")
	local textMetrics = require("../src/layout/text_metrics")
	local ALERT_BAND = 1.015
	local PACKAGES = {
		"classic_desktop",
		"compact_pointer",
		"fantasy_ornate",
		"fantasy_parchment",
		"glossy_mobile",
		"glossy_touch",
		"pixel_quest",
		"scifi_hud",
	}

	--[[ TWO SWEEPS, BECAUSE THE DOMAIN IS WIDER THAN THE STEPS (NEW-4). The engine
		applies its preferred-text reservation as ONE OF FOUR measured steps
		(0/4/10/14 px) and the live `preferredTextSize` fact is 1 on every shipped
		path — that is the domain the Alert's band is claimed over, and api.md now
		says so in those words. The FACTS, though, are clamped to [0, 32] and
		[0.5, 3]: a fixture or a device profile may legally push either to its
		ceiling, and there the band's headroom is gone (glossy_mobile's `title` at a
		ten-foot display reaches 149 px at the extremes, against a 66.7 px ceiling).
		Both are swept so the claim and its edge are each written down, and the
		second case is the one that says what a caller at the extremes gets. ]]
	it("no package paints a rung at or past 1/(band - 1) px, at either distance", function()
		local ceiling = 1 / (ALERT_BAND - 1)
		local worst, worstName = 0, "none"
		local resolved: { any } = { { "facet-neutral", snapshot.resolve(Facet.themes.neutralPackage(), nil, {}) } }
		for _, name in PACKAGES do
			table.insert(
				resolved,
				{ name, snapshot.resolve((require)(`../examples/themes/{name}`).build(Facet.themes), nil, {}) }
			)
		end
		for _, entry in resolved do
			local name, base = entry[1], entry[2]
			for _, displaySize in { "Medium", "Large" } do
				local metrics = snapshot.forDisplay(base, displaySize)
				local scale = snapshot.measureScale(displaySize, 1)
				for role, spec in metrics.type do
					-- the LARGEST preferred-text step the engine applies (api.md's
					-- measured 0/4/10/14 table), added the way the renderer adds it
					local painted = textMetrics.reservedSize(spec.size, scale, 14)
					if painted > worst then
						worst, worstName = painted, `{name}.{role}@{displaySize}`
					end
				end
			end
		end
		expect(`worst {worstName} {worst} < ceiling {ceiling}`).toBe(
			`worst {worstName} {math.min(worst, ceiling - 1e-9)} < ceiling {ceiling}`
		)
		-- ...and the sweep really looked at something, rather than passing on zero
		expect(worst > 40).toBe(true)
	end)

	--[[ …AND WHAT HAPPENS AT THE FACTS' OWN CEILINGS, written down rather than left
		to be discovered. `snapshot.textOffset` clamps the additive offset to
		[0, 32] and `typographyScale` clamps the multiplier to [0.5, 3]; nothing
		shipped drives either past the four measured steps and 1, but the domain is
		the domain. At the ceilings a text-safe band would have to be derived from
		the largest rung the SURFACE paints rather than from the library's largest —
		this case records the number that derivation would have to beat, so the day
		a profile drives it there, the failure names the package and the rung
		instead of arriving as a re-flow on a device. ]]
	it("at the facts' clamped ceilings the fixed band has no headroom, and the sweep says so", function()
		local ceiling = 1 / (ALERT_BAND - 1)
		local worst, worstName = 0, "none"
		local resolved: { any } = { { "facet-neutral", snapshot.resolve(Facet.themes.neutralPackage(), nil, {}) } }
		for _, name in PACKAGES do
			table.insert(
				resolved,
				{ name, snapshot.resolve((require)(`../examples/themes/{name}`).build(Facet.themes), nil, {}) }
			)
		end
		for _, entry in resolved do
			local name, base = entry[1], entry[2]
			for _, displaySize in { "Medium", "Large" } do
				local metrics = snapshot.forDisplay(base, displaySize)
				-- the CLAMPED ceilings, taken through the same two seams the renderer
				-- takes them through, not hand-multiplied
				local scale = snapshot.measureScale(displaySize, 3)
				local offset = snapshot.textOffset(32)
				for role, spec in metrics.type do
					local painted = textMetrics.reservedSize(spec.size, scale, offset)
					if painted > worst then
						worst, worstName = painted, `{name}.{role}@{displaySize}`
					end
				end
			end
		end
		-- the clamps really are what this case says they are
		expect(snapshot.textOffset(99)).toBe(32)
		expect(snapshot.measureScale("Medium", 99)).toBe(3)
		-- ...and at them the fixed band is exceeded, by the rung this names
		expect(`worst {worstName} past ceiling: {worst > ceiling}`).toBe(`worst {worstName} past ceiling: true`)
		expect(worst > 100).toBe(true)
	end)
end)
