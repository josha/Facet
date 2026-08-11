--!strict
-- Pointer interaction seam (ADR-0008, Table Phase B foundation): Grip zones
-- (non-button Active nodes — engine overrides MouseIcon over GuiButtons, so
-- resize grips must be Frames), semantic cursor hints through the adapter,
-- pointer capture (down routes moves to the captured node until up), the
-- renderer's rect lookup for drag math, and Anchor overlays whose dynamic
-- offsets re-arrange without remount (drop indicator / resize preview).

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src")
local fake_target = require("../tests/lib/fake_target")

local function world(screenBp: any)
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	local adapter = fake_target.new()
	local root = LuauUI.mount(core, screenBp)
	local controller = LuauUI.renderer.attach(core, root, env, adapter, {})
	controller.initialRender()
	return core, adapter, controller, root
end

describe("Pointer seam: grips and cursor hints", function()
	it("a Grip renders as a non-button node and hover requests its cursor hint", function()
		local _, adapter = world(LuauUI.UI.Screen({
			id = "S",
			children = {
				LuauUI.UI.Grip({
					id = "G",
					cursorHint = "colResize",
					width = { type = "fixed", px = 8 },
					height = { type = "fixed", px = 20 },
				}),
			},
		}))
		local grip = adapter.node("/S/G")
		expect(grip ~= nil).toBe(true)
		expect(grip.class).toBe("Grip")
		expect(grip.props.cursorHint).toBe("colResize")
		expect(adapter.cursorHint()).toBe(nil)
		adapter.hover("/S/G")
		expect(adapter.cursorHint()).toBe("colResize")
		adapter.unhover("/S/G")
		expect(adapter.cursorHint()).toBe(nil)
	end)

	it("pointer capture: down on a grip routes moves and up to it, with rects", function()
		local calls: { any } = {}
		local _, adapter = world(LuauUI.UI.Screen({
			id = "S",
			children = {
				LuauUI.UI.Grip({
					id = "G",
					cursorHint = "colResize",
					width = { type = "fixed", px = 8 },
					height = { type = "fixed", px = 20 },
					onPointerDown = function(path: string, pos: any, rectOf: (string) -> any)
						table.insert(calls, { "down", path, pos.x, pos.y, rectOf(path) })
					end,
					onPointerMove = function(path: string, pos: any)
						table.insert(calls, { "move", path, pos.x, pos.y })
					end,
					onPointerUp = function(path: string, pos: any)
						table.insert(calls, { "up", path, pos.x, pos.y })
					end,
				}),
			},
		}))
		adapter.pointerDown("/S/G", 4, 10)
		-- capture: the move is far outside the grip yet still routes to it
		adapter.pointerMove(160, 12)
		adapter.pointerUp(161, 13)
		expect(#calls).toBe(3)
		expect(calls[1][1]).toBe("down")
		expect(calls[1][2]).toBe("/S/G")
		expect(calls[1][3]).toBe(4)
		-- the rect lookup hands drag math the solved rect of any live path
		expect(calls[1][5].w).toBe(8)
		expect(calls[1][5].h).toBe(20)
		expect(calls[2][1]).toBe("move")
		expect(calls[2][3]).toBe(160)
		expect(calls[3][1]).toBe("up")
		-- capture released: a move after up routes nowhere
		adapter.pointerMove(200, 20)
		expect(#calls).toBe(3)
	end)

	it("cursor hint persists across a captured drag even off the grip", function()
		local _, adapter = world(LuauUI.UI.Screen({
			id = "S",
			children = {
				LuauUI.UI.Grip({
					id = "G",
					cursorHint = "colResize",
					width = { type = "fixed", px = 8 },
					height = { type = "fixed", px = 20 },
					onPointerDown = function() end,
				}),
			},
		}))
		adapter.hover("/S/G")
		adapter.pointerDown("/S/G", 4, 10)
		adapter.unhover("/S/G") -- pointer slid off mid-drag
		expect(adapter.cursorHint()).toBe("colResize") -- capture keeps the hint
		adapter.pointerUp(90, 10)
		expect(adapter.cursorHint()).toBe(nil)
	end)
end)

describe("Pointer seam: capture lifecycle", function()
	it("destroying the root cancels an active pointer capture", function()
		local cancelled = false
		local moves = 0
		local _, adapter, controller = world(LuauUI.UI.Screen({
			id = "S",
			children = {
				LuauUI.UI.Grip({
					id = "G",
					cursorHint = "colResize",
					width = { type = "fixed", px = 8 },
					height = { type = "fixed", px = 20 },
					onPointerDown = function() end,
					onPointerMove = function()
						moves += 1
					end,
					onPointerCancel = function()
						cancelled = true
					end,
				}),
			},
		}))
		adapter.pointerDown("/S/G", 4, 10)
		controller.dispose() -- whole-root teardown mid-drag (screen dismissed)
		expect(cancelled).toBe(true)
		adapter.pointerMove(100, 10) -- must route nowhere after teardown
		expect(moves).toBe(0)
		expect(adapter.cursorHint()).toBe(nil)
	end)

	-- Task 10 (row-actions Table integration) follow-up: destroyRoot's capture
	-- cancellation, proven SCOPED to its own root — no Table, no row_actions,
	-- no presenter. Live-found bug: `destroyRoot` used to end the adapter's
	-- ONE live pointer capture unconditionally whenever ANY root tore down
	-- (fake_target.luau's own prior comment on this exact line: "root
	-- teardown always ends the capture" — true only when the torn-down root
	-- is the SAME one that holds the capture), even a root the capture has
	-- nothing to do with — an adapter legitimately hosts several roots at
	-- once. row-actions Task 10 hit this through the presenter's own
	-- transient popup-catcher root (mounted/retired reactively off any
	-- `outsideDismiss.active` change) tearing down mid-gesture and cancelling
	-- an UNRELATED row's still-live drag; this test isolates the same
	-- invariant at the one seam it actually lives in (`destroyRoot` itself),
	-- independent of that whole call chain.
	local function mountRoot(adapter: any, id: string, counts: { moves: number, ups: number, cancels: number })
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local root = LuauUI.mount(
			core,
			LuauUI.UI.Screen({
				id = id,
				children = {
					LuauUI.UI.Grip({
						id = "G",
						width = { type = "fixed", px = 8 },
						height = { type = "fixed", px = 20 },
						onPointerDown = function(): boolean?
							return true
						end,
						onPointerMove = function()
							counts.moves += 1
						end,
						onPointerUp = function()
							counts.ups += 1
						end,
						onPointerCancel = function(): boolean?
							counts.cancels += 1
							return nil
						end,
					}),
				},
			})
		)
		local controller = LuauUI.renderer.attach(core, root, env, adapter, {})
		controller.initialRender()
		return root, controller
	end

	it("a live capture on root B survives root A's destroyRoot, and cancels on root B's own destroyRoot", function()
		local adapter = fake_target.new()
		local countsA = { moves = 0, ups = 0, cancels = 0 }
		local countsB = { moves = 0, ups = 0, cancels = 0 }
		local rootA, controllerA = mountRoot(adapter, "A", countsA)
		local rootB, controllerB = mountRoot(adapter, "B", countsB)

		-- capture a live gesture on root B's own grip
		adapter.pointerDown("/B/G", 4, 10, "mouse")
		expect(countsB.cancels).toBe(0)

		-- destroying the UNRELATED root (A) must never touch B's live capture
		controllerA.dispose()
		rootA.dispose()
		expect(countsB.cancels).toBe(0) -- not cancelled by an unrelated root's teardown
		adapter.pointerMove(5, 10)
		expect(countsB.moves).toBe(1) -- the capture survived: move still routes to it
		adapter.pointerUp(5, 10)
		expect(countsB.ups).toBe(1) -- ...and completes normally
		expect(countsA.moves + countsA.ups + countsA.cancels).toBe(0) -- root A's own grip never involved

		-- a FRESH capture on B, this time destroying B itself: THIS must cancel
		adapter.pointerDown("/B/G", 4, 10, "mouse")
		controllerB.dispose()
		rootB.dispose()
		expect(countsB.cancels).toBe(1) -- the capture belonged to the destroyed root
	end)

	-- REDTEAM ITEM 14 (LOW; screen_target.luau:4709 in the charter's own
	-- numbering, mirrored here). `destroyRoot`'s own capture-cancel (proven
	-- above) is scoped to nodes it can still find belonging to the root
	-- being torn down — correct for that case, but a captured node whose
	-- underlying instance dies through some OTHER path FIRST (the real
	-- adapter's `discardParked`, for one — a pool-evicted node's Instance is
	-- destroyed directly with no capture check at all; the live engine's
	-- `IsDescendantOf` on an already-destroyed instance is false against
	-- EVERY root, so no `destroyRoot` call, on ANY root, can ever reach it
	-- again) leaves the adapter's ONE capture slot stuck forever — blocking
	-- every future press adapter-wide. Fixed at the capture-acquisition gate
	-- itself (`onPointerDown`/`pointerDown`, both adapters): a capture whose
	-- own node is no longer alive is treated as already-ended rather than
	-- as still owning the pointer. `node.alive` is flipped directly here
	-- (not through `remove`/`park`, both of which already correctly cancel
	-- the capture as part of their own bookkeeping, proven elsewhere in this
	-- file) — the one honest way this fake can model an out-of-band
	-- destruction its own tracked mutators never leave uncancelled.
	it("a capture whose node dies through an untracked path no longer blocks a fresh press", function()
		local movesG, movesH, upsH = 0, 0, 0
		local _, adapter, controller = world(LuauUI.UI.Screen({
			id = "S",
			children = {
				LuauUI.UI.Grip({
					id = "G",
					width = { type = "fixed", px = 8 },
					height = { type = "fixed", px = 20 },
					onPointerDown = function()
						return true
					end,
					onPointerMove = function()
						movesG += 1
					end,
				}),
				LuauUI.UI.Grip({
					id = "H",
					width = { type = "fixed", px = 8 },
					height = { type = "fixed", px = 20 },
					onPointerDown = function()
						return true
					end,
					onPointerMove = function()
						movesH += 1
					end,
					onPointerUp = function()
						upsH += 1
					end,
				}),
			},
		}))
		adapter.pointerDown("/S/G", 4, 10)
		local capturedNode = adapter.node("/S/G")
		expect(capturedNode ~= nil).toBe(true)
		-- simulate the node dying through a path the capture bookkeeping
		-- never saw (the real adapter's `discardParked`)
		capturedNode.alive = false

		-- WITHOUT the fix: this decline is permanent — the stale capture
		-- blocks every future press, on any node, forever — a fresh press
		-- on H would silently do nothing at all.
		adapter.pointerDown("/S/H", 4, 10)
		adapter.pointerMove(100, 10)
		adapter.pointerUp(100, 10)
		expect(movesG).toBe(0) -- G's stale capture never fires again
		expect(movesH).toBe(1) -- H genuinely captured the fresh gesture
		expect(upsH).toBe(1)
		controller.dispose()
	end)
end)

describe("Pointer seam: dynamic hints and opt-in bindings", function()
	it("a dynamic cursorHint re-applies through the adapter on change", function()
		local core = LuauUI.newCore()
		local hint = core:signal("colResize")
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local adapter = fake_target.new()
		local root = LuauUI.mount(
			core,
			LuauUI.UI.Screen({
				id = "S",
				children = {
					LuauUI.UI.Grip({
						id = "G",
						cursorHint = hint,
						width = { type = "fixed", px = 8 },
						height = { type = "fixed", px = 20 },
					}),
				},
			})
		)
		local controller = LuauUI.renderer.attach(core, root, env, adapter, {})
		controller.initialRender()
		expect(adapter.node("/S/G").props.cursorHint).toBe("colResize")
		hint:set("rowDrag")
		controller.refresh()
		expect(adapter.node("/S/G").props.cursorHint).toBe("rowDrag")
	end)

	it("sinkNavigation stops nav keys from reaching lower contexts (the avatar)", function()
		-- hand-test finding 2026-07-20: arrow keys walked list focus AND moved
		-- the avatar — a focus-driven screen must be able to sink its keys
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = LuauUI.newPresenter(core, env, adapter, system)
		-- the "character controls": a lower-priority context bound to Down
		local game = system.createContext({ name = "CharacterControls", priority = 1000 })
		local move = game.createAction("Move", "Bool")
		move.bind({ keyCode = "Down" })
		local moved = 0
		move.onPressed(function()
			moved += 1
		end)
		local screen = LuauUI.UI.Screen({
			id = "S",
			children = { LuauUI.UI.Button({ id = "A", label = "A" }), LuauUI.UI.Button({ id = "B", label = "B" }) },
		})
		-- without the opt-in, nav keys leak through (base screens never sink
		-- by default: HUD overlays must not eat gameplay input)
		local h1 = pres.present(screen, {})
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		expect(moved).toBe(1)
		pres.dismiss(h1)
		local h2 = pres.present(screen, { sinkNavigation = true })
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		expect(moved).toBe(1) -- sunk: the avatar never saw it
		expect(pres.focus.focused:get()).toBe("/S/B") -- but focus moved
		pres.dismiss(h2)
	end)

	it("Adjust and reorder-nav bindings exist only when the screen opts in", function()
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = LuauUI.newPresenter(core, env, adapter, system)
		local screen = LuauUI.UI.Screen({
			id = "Plain",
			children = { LuauUI.UI.Button({ id = "B", label = "Go" }) },
		})
		local h1 = pres.present(screen, {})
		expect(#h1.actions.adjust.bindings).toBe(0)
		pres.dismiss(h1)
		local h2 = pres.present(screen, { onAdjust = function() end })
		expect(#h2.actions.adjust.bindings > 0).toBe(true)
		pres.dismiss(h2)
	end)
end)

describe("Pointer seam: rectOf and anchored overlays", function()
	it("controller.rectOf returns solved rects for live paths", function()
		local _, _, controller = world(LuauUI.UI.Screen({
			id = "S",
			children = {
				LuauUI.UI.VStack({
					id = "Main",
					width = { type = "fill", weight = 1 },
					height = { type = "fixed", px = 100 },
					children = {},
				}),
			},
		}))
		local rect = controller.rectOf("/S/Main")
		expect(rect.w).toBe(800)
		expect(rect.h).toBe(100)
		expect(controller.rectOf("/S/Nope")).toBe(nil)
	end)

	it("Anchor overlay: a dynamic offset re-arranges with rect writes only (no remount)", function()
		local core = LuauUI.newCore()
		local offsetX = core:signal(40)
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local adapter = fake_target.new()
		local root = LuauUI.mount(
			core,
			LuauUI.UI.Screen({
				id = "S",
				children = {
					LuauUI.UI.Anchor({
						id = "Z",
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
						children = {
							LuauUI.UI.VStack({
								id = "Main",
								width = { type = "fill", weight = 1 },
								height = { type = "fill", weight = 1 },
								children = {},
							}),
							LuauUI.UI.Box({
								id = "Line",
								anchor = "topLeft",
								offsetX = offsetX,
								width = { type = "fixed", px = 2 },
								height = { type = "fixed", px = 50 },
							}),
						},
					}),
				},
			})
		)
		local controller = LuauUI.renderer.attach(core, root, env, adapter, {})
		controller.initialRender()
		expect(adapter.node("/S/Z/Line").rect.x).toBe(40)
		-- the Main content still fills underneath the overlay
		expect(adapter.node("/S/Z/Main").rect.w).toBe(800)
		local factoryRuns = root.counters().factoryRuns
		adapter.takeOps()
		offsetX:set(90)
		controller.refresh()
		expect(adapter.node("/S/Z/Line").rect.x).toBe(90)
		expect(root.counters().factoryRuns).toBe(factoryRuns) -- no remount
		for _, op in adapter.takeOps() do
			expect(string.sub(op, 1, 4)).toBe("rect") -- minimal writes: rects only
		end
	end)
end)
