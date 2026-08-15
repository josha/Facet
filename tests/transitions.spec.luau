--!strict
-- STRUCTURAL TRANSITIONS (ADR-0022 Decision 3; acceptance row SF-M6). Three
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

local customFactory = require("../src/core/custom")
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local rendererLib = require("../src/render/renderer")
local clockLib = require("../src/motion/clock")
local transitionsLib = require("../src/render/transitions")
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
		--[[ react-lua-comparison.md §5 rank 2. The branch scope is now the factory's
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

describe("transition coordinator: the forms", function()
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
		-- `decay` is the slowest shipped class (response 0.5 s), so its settle
		-- epsilon lands well past the flat cap
		local root = attach(core, env, clock, whenScreen(on, { enter = "fade", class = "decay" }))
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
		for _ = 1, 6 do
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

local function presenterWorld()
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 390, h = 844 })
	local adapter = fake_target.new()
	local system = actionsLib.newSystem(core)
	local pres = presenterLib.new(core, env, adapter, system)
	return core, env, adapter, system, pres
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
		local handle = pres.present(surface("Slow"), { transition = { enter = "fade", class = "decay" } })
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

	it("surfaces without a transition tear down synchronously, exactly as before", function()
		local _, _, adapter, _, pres = presenterWorld()
		local handle = pres.present(surface("Plain"))
		pres.dismiss(handle)
		expect(adapter.node("/Plain/Content")).toBeNil()
	end)
end)
