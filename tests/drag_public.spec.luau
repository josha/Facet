--!strict
-- The PUBLIC drag/drop contract (ADR-0022 Decision 5, rows SF-D1/D2/D4/D5).
-- `UI.draggable` / `UI.dropTarget` declared on real blueprints, mounted through
-- the real renderer, driven through the REAL acquisition paths — the engine
-- detector mirror and the ADR-0008 pointer capture — never by poking the
-- session directly. What is asserted is what a player would see: which target
-- lit up, what the predicted verdict said and why, what the game's onDrop was
-- handed, and which semantic events fired on which frame.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local fake_target = require("../tests/lib/fake_target")

local UI = Facet.UI

-- a board with one draggable card and two stacked slots, at known offsets so
-- every pointer coordinate below is a fact about geometry, not a guess
local function board(opts: any?)
	local options = opts or {}
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	if options.noDragDetector then
		adapter.noDragDetector = true
	end
	local pres = Facet.newPresenter(core, env, adapter, system)

	local drops: { any } = {}
	local enters: { string } = {}
	local leaves: { string } = {}
	local events: { any } = {}

	local function slot(id: string, y: number, accepts: any)
		return UI.dropTarget(
			UI.Box({
				id = id,
				anchor = "topLeft",
				offsetX = 0,
				offsetY = y,
				width = { type = "fixed", px = 200 },
				height = { type = "fixed", px = 100 },
			}),
			{
				accepts = accepts,
				onDrop = function(payload: any, info: any)
					table.insert(drops, { id = id, payload = payload, info = info })
				end,
				onEnter = function()
					table.insert(enters, id)
				end,
				onLeave = function()
					table.insert(leaves, id)
				end,
			}
		)
	end

	local slots: { any } = {
		slot("SlotA", 200, nil),
		slot("SlotB", 320, function(payload: any)
			if payload == "card" then
				return false, "WRONG_KIND"
			end
			return true
		end),
	}
	if options.extraSlot then
		table.insert(slots, options.extraSlot(slot))
	end

	local card = UI.draggable(
		UI.Box({
			id = "Card",
			anchor = "topLeft",
			offsetX = 0,
			offsetY = 0,
			width = { type = "fixed", px = 100 },
			height = { type = "fixed", px = 60 },
		}),
		{
			payload = options.payload or "card",
			declineTouch = options.declineTouch == true,
			grabAnchor = options.grabAnchor,
			armStaging = options.armStaging,
		}
	)

	local children: { any } = { card }
	for _, s in slots do
		table.insert(children, s)
	end
	local screen = UI.Screen({
		id = "S",
		children = {
			UI.Anchor({
				id = "Board",
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				children = children,
			}),
		},
	})
	local handle = pres.present(screen)
	pres.refresh()
	local controller = handle.controller
	controller.setDragCollaborators({
		feedback = {
			emit = function(event: string, info: any)
				table.insert(events, { event = event, info = info })
			end,
		},
	})
	local registry = controller.dragRegistry()

	local api: any = {
		core = core,
		adapter = adapter,
		pres = pres,
		handle = handle,
		controller = controller,
		registry = registry,
		drops = drops,
		enters = enters,
		leaves = leaves,
		events = events,
	}
	function api.rect(path: string)
		return controller.rectOf(path)
	end
	function api.centerOf(path: string): (number, number)
		local r = controller.rectOf(path)
		assert(r ~= nil, `no rect for {path}`)
		return r.x + r.w / 2, r.y + r.h / 2
	end
	-- the ENGINE detector mirror (NS-A5): the acquisition path the live adapter
	-- takes whenever UIDragDetector exists
	function api.dragStart(x: number, y: number, pointerType: string?)
		adapter.driveDragStart("/S/Board/Card", { x = x, y = y, pointerType = pointerType or "mouse" })
	end
	function api.dragTo(x: number, y: number, pointerType: string?)
		adapter.driveDragContinue(
			"/S/Board/Card",
			{ x = x, y = y, pointerType = pointerType or "mouse" },
			{ x = 0, y = 0 }
		)
	end
	function api.dragEnd(x: number, y: number, pointerType: string?)
		adapter.driveDragEnd("/S/Board/Card", { x = x, y = y, pointerType = pointerType or "mouse" })
	end
	function api.eventNames(): { string }
		local out: { string } = {}
		for _, entry in events do
			table.insert(out, entry.event)
		end
		return out
	end
	function api.eventNamed(name: string): any
		for _, entry in events do
			if entry.event == name then
				return entry.info
			end
		end
		return nil
	end
	return api
end

describe("public drag: acquisition and promotion (SF-D1, SF-D3)", function()
	it("mounts the declarations: the card acquires a detector, the slots register", function()
		local b = board()
		expect(b.registry.dump().sources[1]).toBe("/S/Board/Card")
		expect(#b.registry.dump().targets).toBe(2)
		expect(b.adapter.node("/S/Board/Card").dragDetector ~= nil).toBe(true)
	end)

	it("a press under the promotion token never becomes a session (the tap survives)", function()
		local b = board()
		b.dragStart(20, 20)
		b.dragTo(24, 22) -- 4.47 px of travel on a mouse
		expect(b.registry.isActive()).toBe(false)
		b.dragEnd(24, 22)
		expect(b.registry.isActive()).toBe(false)
		expect(#b.events).toBe(0) -- nothing semantic happened: it was a tap
	end)

	it("past the token the session begins and emits `select`", function()
		local b = board()
		b.dragStart(20, 20)
		b.dragTo(30, 20) -- 10 px on a mouse: promoted
		expect(b.registry.isActive()).toBe(true)
		expect(b.registry.mode()).toBe("pointer")
		expect(b.registry.payload()).toBe("card")
		expect(b.eventNames()[1]).toBe("select")
	end)

	it("touch takes the touch token, not the pointer one", function()
		local b = board()
		b.dragStart(20, 20, "touch")
		b.dragTo(30, 20, "touch") -- 10 px: a drag on a mouse, still a tap on a finger
		expect(b.registry.isActive()).toBe(false)
		b.dragTo(36, 20, "touch") -- 16 px: past the touch token
		expect(b.registry.isActive()).toBe(true)
	end)

	it("declineTouch declines the capture so a native scroll host keeps the pan", function()
		local b = board({ declineTouch = true })
		expect(b.registry.pointerDown("/S/Board/Card", { x = 20, y = 20, pointerType = "touch" })).toBe(false)
		-- ...and the same node still acquires normally on a mouse
		expect(b.registry.pointerDown("/S/Board/Card", { x = 20, y = 20, pointerType = "mouse" })).never().toBe(false)
	end)

	it("falls back to the ADR-0008 pointer capture when the engine has no detector", function()
		local b = board({ noDragDetector = true })
		expect(b.adapter.node("/S/Board/Card").dragDetector).toBe(nil)
		b.adapter.pointerDown("/S/Board/Card", 20, 20, "mouse")
		b.adapter.pointerMove(30, 20)
		expect(b.registry.isActive()).toBe(true)
		-- the SAME promotion rule, the SAME session: only the acquisition differed
		expect(b.registry.mode()).toBe("pointer")
	end)
end)

describe("public drag: hover, legality and the predicted verdict (SF-D1)", function()
	it("enter/leave fire exactly once per boundary", function()
		local b = board()
		local ax, ay = b.centerOf("/S/Board/SlotA")
		b.dragStart(20, 20)
		b.dragTo(30, 20)
		b.dragTo(ax, ay)
		b.dragTo(ax + 2, ay + 2) -- still inside A: no new transition
		b.dragTo(20, 20) -- back out to empty space
		expect(b.enters).toEqual({ "SlotA" })
		expect(b.leaves).toEqual({ "SlotA" })
	end)

	it("the predicted verdict is readable while hovering, with the game's reason", function()
		local b = board()
		local bx, by = b.centerOf("/S/Board/SlotB")
		b.dragStart(20, 20)
		b.dragTo(30, 20)
		b.dragTo(bx, by)
		local verdict = b.registry.verdict:get()
		expect(verdict.legal).toBe(false)
		expect(verdict.targetId).toBe(nil) -- an illegal target is never "hovered"
		expect(verdict.overId).toBe("/S/Board/SlotB") -- ...but the player IS over it
		expect(verdict.reason).toBe("WRONG_KIND")
		-- ...and no enter fired for it: the session skips illegal targets
		expect(#b.enters).toBe(0)
	end)

	it("a legal hover publishes the target and no reason", function()
		local b = board()
		local ax, ay = b.centerOf("/S/Board/SlotA")
		b.dragStart(20, 20)
		b.dragTo(30, 20)
		b.dragTo(ax, ay)
		local verdict = b.registry.verdict:get()
		expect(verdict.legal).toBe(true)
		expect(verdict.targetId).toBe("/S/Board/SlotA")
		expect(verdict.reason).toBe(nil)
	end)

	it("the same payload is legal for one target and refused by the other", function()
		local b = board({ payload = "chip" })
		local bx, by = b.centerOf("/S/Board/SlotB")
		b.dragStart(20, 20)
		b.dragTo(30, 20)
		b.dragTo(bx, by)
		expect(b.registry.verdict:get().legal).toBe(true) -- SlotB accepts non-cards
	end)
end)

describe("public drag: terminals (SF-D1, SF-D5)", function()
	it("a legal drop calls the game's onDrop and emits commit then land", function()
		local b = board()
		local ax, ay = b.centerOf("/S/Board/SlotA")
		b.dragStart(20, 20)
		b.dragTo(30, 20)
		b.dragTo(ax, ay)
		b.dragEnd(ax, ay)
		expect(#b.drops).toBe(1)
		expect(b.drops[1].id).toBe("SlotA")
		expect(b.drops[1].payload).toBe("card")
		expect(b.drops[1].info.targetId).toBe("/S/Board/SlotA")
		expect(b.eventNames()).toEqual({ "select", "commit", "land" })
		expect(b.registry.isActive()).toBe(false) -- terminal: the session is inert
	end)

	it("an ILLEGAL drop rejects ONCE, carrying the game's reason code", function()
		local b = board()
		local bx, by = b.centerOf("/S/Board/SlotB")
		b.dragStart(20, 20)
		b.dragTo(30, 20)
		b.dragTo(bx, by)
		b.dragEnd(bx, by)
		expect(#b.drops).toBe(0) -- the game's onDrop was never called
		expect(b.eventNames()).toEqual({ "select", "reject" })
		local reject = b.eventNamed("reject")
		expect(reject.reason).toBe("WRONG_KIND")
		expect(reject.targetId).toBe("/S/Board/SlotB")
		expect(reject.payload).toBe("card")
	end)

	it("a release over NOTHING is the free-area cancel, not a reason-less reject (I-7)", function()
		local b = board()
		b.dragStart(20, 20)
		b.dragTo(30, 20)
		b.dragEnd(700, 500)
		expect(b.eventNames()).toEqual({ "select", "cancel" })
		expect(b.eventNamed("cancel").how).toBe("freeRelease")
	end)

	it("cancel fires a leave for the hovered target and emits `cancel`", function()
		local b = board()
		local ax, ay = b.centerOf("/S/Board/SlotA")
		b.dragStart(20, 20)
		b.dragTo(30, 20)
		b.dragTo(ax, ay)
		b.registry.cancel("playerCancelled")
		expect(b.leaves).toEqual({ "SlotA" })
		expect(b.eventNamed("cancel").reason).toBe("playerCancelled")
		expect(b.eventNamed("cancel").how).toBe("action")
		expect(b.registry.isActive()).toBe(false)
	end)

	it("rapid retry never double-fires: a terminal session is inert", function()
		local b = board()
		local bx, by = b.centerOf("/S/Board/SlotB")
		b.dragStart(20, 20)
		b.dragTo(30, 20)
		b.dragEnd(bx, by)
		b.dragEnd(bx, by)
		b.registry.cancel("late")
		local rejects = 0
		for _, name in b.eventNames() do
			if name == "reject" then
				rejects += 1
			end
		end
		expect(rejects).toBe(1)
	end)
end)

describe("public drag: geometry stays live (SF-D1, SF-L2)", function()
	it("overlapping targets resolve to the TOPMOST drawn one", function()
		local b = board({
			extraSlot = function(slot: any)
				-- declared last, so it paints above SlotA and covers it exactly
				return slot("SlotOver", 200, nil)
			end,
		})
		local ax, ay = b.centerOf("/S/Board/SlotA")
		b.dragStart(20, 20)
		b.dragTo(30, 20)
		b.dragTo(ax, ay)
		expect(b.registry.verdict:get().targetId).toBe("/S/Board/SlotOver")
	end)

	it("removing the hovered target mid-session leaves ONCE and clears the verdict (F5)", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local present = core:signal(true)
		local leaves: { string } = {}
		local card = UI.draggable(
			UI.Box({
				id = "Card",
				anchor = "topLeft",
				offsetX = 0,
				offsetY = 0,
				width = { type = "fixed", px = 100 },
				height = { type = "fixed", px = 60 },
			}),
			{ payload = "card" }
		)
		local screen = UI.Screen({
			id = "S",
			children = {
				UI.Anchor({
					id = "Board",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						card,
						UI.When({
							id = "SlotWhen",
							condition = present,
							thenView = function()
								return UI.dropTarget(
									UI.Box({
										id = "Slot",
										anchor = "topLeft",
										offsetX = 0,
										offsetY = 200,
										width = { type = "fixed", px = 200 },
										height = { type = "fixed", px = 100 },
									}),
									{
										onDrop = function() end,
										onLeave = function()
											table.insert(leaves, "Slot")
										end,
									}
								)
							end,
						}),
					},
				}),
			},
		})
		local handle = pres.present(screen)
		pres.refresh()
		local registry = handle.controller.dragRegistry()
		local slotPath = "/S/Board/SlotWhen/then/Slot"
		local r = handle.controller.rectOf(slotPath)
		adapter.driveDragStart("/S/Board/Card", { x = 20, y = 20, pointerType = "mouse" })
		adapter.driveDragContinue("/S/Board/Card", { x = 30, y = 20, pointerType = "mouse" }, { x = 0, y = 0 })
		adapter.driveDragContinue(
			"/S/Board/Card",
			{ x = r.x + r.w / 2, y = r.y + r.h / 2, pointerType = "mouse" },
			{ x = 0, y = 0 }
		)
		expect(registry.verdict:get().targetId).toBe(slotPath)

		present:set(false)
		pres.refresh()
		-- the targeting ENDED with exactly one leave; the session did NOT
		expect(leaves).toEqual({ "Slot" })
		expect(registry.isActive()).toBe(true)
		expect(registry.verdict:get().targetId).toBe(nil)
		expect(registry.verdict:get().legal).toBe(false)
	end)

	it("removing the SOURCE mid-session CANCELS it — no orphan ghost, no wedge (F5's mirror)", function()
		--[[ F5 above handles the TARGET vanishing under a live drag. The SOURCE
			vanishing had no handling at all, and the consequence is worse, because
			the ghost is not parented to the source: the drag proxy is its own screen
			on the presenter's scope, so it outlives whatever unmounted. A surface
			that drops its sources while a card is held left the card painted over
			the world with nothing under it, and the stale session then refused every
			new pickup while staying committable onto anything that remounted
			underneath. Director report, 2026-08-04: "the card stayed picked up
			outside director view and was inaccessible when I opened director view
			up." ]]
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local present = core:signal(true)
		local events: { string } = {}
		local screen = UI.Screen({
			id = "S",
			children = {
				UI.Anchor({
					id = "Board",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						UI.When({
							id = "CardWhen",
							condition = present,
							thenView = function()
								return UI.draggable(
									UI.Box({
										id = "Card",
										anchor = "topLeft",
										offsetX = 0,
										offsetY = 0,
										width = { type = "fixed", px = 100 },
										height = { type = "fixed", px = 60 },
									}),
									{ payload = "card" }
								)
							end,
						}),
					},
				}),
			},
		})
		local handle = pres.present(screen)
		pres.refresh()
		handle.controller.setDragCollaborators({
			feedback = {
				emit = function(event: string)
					table.insert(events, event)
				end,
			},
		})
		local registry = handle.controller.dragRegistry()
		local cardPath = "/S/Board/CardWhen/then/Card"
		adapter.driveDragStart(cardPath, { x = 20, y = 20, pointerType = "mouse" })
		adapter.driveDragContinue(cardPath, { x = 30, y = 20, pointerType = "mouse" }, { x = 0, y = 0 })
		expect(registry.isActive()).toBe(true)

		present:set(false)
		pres.refresh()
		-- the session is OVER — not merely un-targeted, as the F5 target case is
		expect(`active={registry.isActive()}`).toBe("active=false")
		expect(`cancelled={table.find(events, "cancel") ~= nil}`).toBe("cancelled=true")
		--[[ ...and once the return flight ARRIVES nothing is held, so the next
			pickup is not refused. `heldSource` deliberately outlives the cancel
			frame — it clears on arrival, not on release — so this settles the
			flight rather than reading it too early. ]]
		for _ = 1, 120 do
			pres.tick(1 / 60)
		end
		pres.refresh()
		expect(`held={registry.heldSource:get()}`).toBe("held=nil")
	end)

	it("...but a RECYCLED source keeps its session: virtualization is not removal", function()
		--[[ The other half, and the reason the rule cannot simply be "the source
			went away". A VirtualList unmounts rows it is still holding — that is
			what windowing IS — and a reorder drag deliberately scrolls the list, so
			the dragged row is routinely the one that leaves. `recycled` is how the
			only thing that knows says so. Asserted through the SAME teardown as the
			case above, so the declaration is provably the whole difference. ]]
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local present = core:signal(true)
		local screen = UI.Screen({
			id = "S",
			children = {
				UI.Anchor({
					id = "Board",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						UI.When({
							id = "CardWhen",
							condition = present,
							thenView = function()
								return UI.draggable(
									UI.Box({
										id = "Card",
										anchor = "topLeft",
										offsetX = 0,
										offsetY = 0,
										width = { type = "fixed", px = 100 },
										height = { type = "fixed", px = 60 },
									}),
									{ payload = "card", recycled = true }
								)
							end,
						}),
					},
				}),
			},
		})
		local handle = pres.present(screen)
		pres.refresh()
		local registry = handle.controller.dragRegistry()
		local cardPath = "/S/Board/CardWhen/then/Card"
		adapter.driveDragStart(cardPath, { x = 20, y = 20, pointerType = "mouse" })
		adapter.driveDragContinue(cardPath, { x = 30, y = 20, pointerType = "mouse" }, { x = 0, y = 0 })
		expect(registry.isActive()).toBe(true)
		present:set(false)
		pres.refresh()
		expect(`stillLive={registry.isActive()}`).toBe("stillLive=true")
		expect(`stillHeld={registry.heldSource:get()}`).toBe(`stillHeld={cardPath}`)
	end)

	it("the source contract CARRIES `recycled` — a dropped key would be silent", function()
		--[[ `drag_contract.source` copies the spec into a frozen table of known
			keys rather than passing it through, so a member the copy forgets is
			dropped with no error anywhere — which is exactly what happened to
			`recycled` on its first cut, and it presented as "the fix does nothing".
			The copy is worth keeping (it is what freezes and defaults the spec), so
			this pins the membership instead. ]]
		local dragContract = require("../src/input/drag_contract")
		expect(`carried={dragContract.source({ payload = "p", recycled = true }).recycled}`).toBe("carried=true")
		-- ...and it DEFAULTS false rather than nil, so the registry's check is a
		-- boolean compare and never an accidental truthy read
		expect(`default={dragContract.source({ payload = "p" }).recycled}`).toBe("default=false")
	end)

	it("a target inside a SCROLLED host hit-tests where it is DRAWN, not where it solved", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local hits: { string } = {}
		local rowsChildren: { any } = {}
		for i = 1, 10 do
			table.insert(
				rowsChildren,
				UI.dropTarget(
					UI.Box({
						id = `Row{i}`,
						anchor = "topLeft",
						offsetX = 0,
						offsetY = (i - 1) * 100,
						width = { type = "fill", weight = 1 },
						height = { type = "fixed", px = 100 },
					}),
					{
						onDrop = function()
							table.insert(hits, `Row{i}`)
						end,
					}
				)
			)
		end
		local card = UI.draggable(
			UI.Box({
				id = "Card",
				anchor = "topLeft",
				offsetX = 500,
				offsetY = 0,
				width = { type = "fixed", px = 60 },
				height = { type = "fixed", px = 60 },
			}),
			{ payload = "card" }
		)
		local screen = UI.Screen({
			id = "S",
			children = {
				UI.Anchor({
					id = "Board",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						card,
						UI.ScrollView({
							id = "List",
							anchor = "topLeft",
							offsetX = 0,
							offsetY = 0,
							axis = "y",
							padding = 0,
							gap = 0,
							clipChildren = true,
							width = { type = "fixed", px = 300 },
							height = { type = "fixed", px = 300 },
							children = {
								UI.Anchor({
									id = "Canvas",
									width = { type = "fill", weight = 1 },
									height = { type = "fixed", px = 1000 },
									children = rowsChildren,
								}),
							},
						}),
					},
				}),
			},
		})
		local handle = pres.present(screen)
		pres.refresh()
		local registry = handle.controller.dragRegistry()
		local host = handle.controller.rectOf("/S/Board/List")
		-- unscrolled: a point 50 px into the viewport is over Row1
		adapter.driveDragStart("/S/Board/Card", { x = 520, y = 20, pointerType = "mouse" })
		adapter.driveDragContinue("/S/Board/Card", { x = 530, y = 20, pointerType = "mouse" }, { x = 0, y = 0 })
		adapter.driveDragContinue(
			"/S/Board/Card",
			{ x = 150, y = host.y + 50, pointerType = "mouse" },
			{ x = 0, y = 0 }
		)
		expect(registry.verdict:get().targetId).toBe("/S/Board/List/Canvas/Row1")
		-- scroll the host 150 px: the SAME screen point is now over Row3
		adapter.driveScroll("/S/Board/List", { x = 0, y = 150 })
		registry.refreshTargets()
		expect(registry.verdict:get().targetId).toBe("/S/Board/List/Canvas/Row3")
		adapter.driveDragEnd("/S/Board/Card", { x = 150, y = host.y + 50, pointerType = "mouse" })
		expect(hits).toEqual({ "Row3" })
	end)
end)

describe("public drag: hit geometry follows the PAINT (PLAT-4)", function()
	-- The platform verifier's finding: the paint half of the presentation channel
	-- composed ancestor offsets and the GEOMETRY half did not, so while any
	-- transform was live — the keyboard keep-visible shift sits on the root for the
	-- whole time the OS keyboard is up, an enter/exit slide sits on a region that
	-- can contain drop targets — Facet's own drop verdicts were about a rect the
	-- player is not looking at. The engine's hit-testing follows the moved
	-- instance, so a plain button press still landed; the disagreement was ours.
	it("a target under a live surface shift hit-tests where it PAINTS", function()
		local b = board()
		local solved = b.controller.rectOf("/S/Board/SlotA")
		local ax, ay = b.centerOf("/S/Board/SlotA")
		b.controller.setPresentationOffset(120) -- the keep-visible shift
		-- `rectOf` is LAYOUT space and must not move: the solver wrote it, a motion
		-- never edits it, and every existing consumer reads it as the solved rect
		expect(b.controller.rectOf("/S/Board/SlotA").y).toBe(solved.y)
		-- `screenRectOf` is where the player is looking
		expect(b.controller.screenRectOf("/S/Board/SlotA").y).toBe(solved.y - 120)
		b.dragStart(20, 20)
		b.dragTo(30, 20)
		b.dragTo(ax, ay - 120) -- the PAINTED centre
		expect(b.registry.verdict:get().targetId).toBe("/S/Board/SlotA")
		b.dragEnd(ax, ay - 120)
		expect(b.drops[1].id).toBe("SlotA")
	end)

	it("...and a SOLVED coordinate the paint has left behind resolves to nothing", function()
		-- the counter-example that makes the first case a fact rather than a
		-- coincidence: SlotB's solved centre is empty screen once the surface has
		-- shifted 120 px up, and before the fix that point still answered SlotB
		local b = board()
		local bx, by = b.centerOf("/S/Board/SlotB")
		b.controller.setPresentationOffset(120)
		b.dragStart(20, 20)
		b.dragTo(30, 20)
		b.dragTo(bx, by)
		expect(b.registry.verdict:get().targetId).toBe(nil)
		expect(b.registry.verdict:get().overId).toBe(nil)
	end)

	it("an ANCESTOR's slide accumulates onto its whole subtree", function()
		-- the transition case: the coordinator writes the transform on the region
		-- path, and the targets inside it move with it
		local b = board()
		local ax, ay = b.centerOf("/S/Board/SlotA")
		b.controller.setPresentationTransform("/S/Board", { x = 40, y = -25 })
		b.dragStart(20, 20)
		b.dragTo(30, 20)
		b.dragTo(ax + 40, ay - 25)
		expect(b.registry.verdict:get().targetId).toBe("/S/Board/SlotA")
	end)

	it("a cleared transform returns the hit rect to the solved one", function()
		local b = board()
		local solved = b.controller.rectOf("/S/Board/SlotA")
		b.controller.setPresentationTransform("/S/Board", { x = 40, y = -25 })
		expect(b.controller.screenRectOf("/S/Board/SlotA").x).toBe(solved.x + 40)
		b.controller.setPresentationTransform("/S/Board", nil)
		-- identity, not a fresh table: a surface at rest pays nothing for the
		-- channel existing (the same table `rectOf` hands back)
		expect(b.controller.screenRectOf("/S/Board/SlotA")).toBe(solved)
	end)
end)

describe("public drag: the non-pointer paradigm (SF-D4)", function()
	it("arm -> navigate -> commit drives the SAME session and the SAME legality", function()
		local b = board()
		expect(b.registry.arm("/S/Board/Card")).toBe(true)
		expect(b.registry.mode()).toBe("armed")
		expect(b.eventNames()[1]).toBe("select")
		expect(b.registry.armTo("/S/Board/SlotA")).toBe(true)
		expect(b.registry.verdict:get().targetId).toBe("/S/Board/SlotA")
		expect(b.registry.verdict:get().mode).toBe("armed")
		b.registry.commit()
		expect(#b.drops).toBe(1)
		expect(b.drops[1].id).toBe("SlotA")
		expect(b.drops[1].info.mode).toBe("armed")
		expect(b.eventNames()).toEqual({ "select", "commit", "land" })
	end)

	it("an armed commit on an ILLEGAL target rejects — it does not silently do nothing", function()
		local b = board()
		b.registry.arm("/S/Board/Card")
		b.registry.armTo("/S/Board/SlotB")
		expect(b.registry.verdict:get().legal).toBe(false)
		b.registry.commit()
		expect(#b.drops).toBe(0)
		expect(b.eventNamed("reject").reason).toBe("WRONG_KIND")
	end)

	it("cancel disarms and emits `cancel`", function()
		local b = board()
		b.registry.arm("/S/Board/Card")
		b.registry.armTo("/S/Board/SlotA")
		b.registry.cancel("cancel")
		expect(b.registry.isActive()).toBe(false)
		expect(b.leaves).toEqual({ "SlotA" })
		expect(b.eventNamed("cancel").mode).toBe("armed")
	end)

	-- ===== armStaging: the parked armed ghost (row SF-D14) ================
	local function stagingBoard(spot: { x: number, y: number })
		local b = board({
			armStaging = function()
				return spot
			end,
		})
		local moves: { any } = {}
		b.controller.setDragCollaborators({
			motionClock = false, -- placement is instant with no clock: assert the POINT
			proxy = {
				show = function()
					return { id = "ghost" }
				end,
				transform = function(_h: any, tr: any)
					table.insert(moves, tr)
				end,
				hide = function() end,
			},
		})
		return b, moves
	end

	it("armStaging parks the ghost at the PICKUP and the aim never moves it", function()
		local b, moves = stagingBoard({ x = 400, y = 520 })
		b.registry.arm("/S/Board/Card")
		local afterArm = moves[#moves]
		expect(afterArm.x).toBe(400)
		expect(afterArm.y).toBe(520)
		local writes = #moves
		-- the aim still resolves, the verdict still publishes, and the ghost stays
		expect(b.registry.armTo("/S/Board/SlotA")).toBe(true)
		expect(b.registry.verdict:get().targetId).toBe("/S/Board/SlotA")
		expect(#moves).toBe(writes) -- not one proxy write from aiming
		b.registry.armTo("/S/Board/SlotB")
		expect(#moves).toBe(writes)
		expect(moves[#moves].x).toBe(400)
	end)

	it("without armStaging the ghost RIDES the aim (the unchanged default)", function()
		local b = board()
		local moves: { any } = {}
		b.controller.setDragCollaborators({
			motionClock = false,
			proxy = {
				show = function()
					return { id = "ghost" }
				end,
				transform = function(_h: any, tr: any)
					table.insert(moves, tr)
				end,
				hide = function() end,
			},
		})
		b.registry.arm("/S/Board/Card")
		b.registry.armTo("/S/Board/SlotA")
		local slot = b.rect("/S/Board/SlotA")
		local card = b.rect("/S/Board/Card")
		expect(moves[#moves].x).toBe(slot.x + slot.w / 2 - card.w / 2)
		expect(moves[#moves].y).toBe(slot.y + slot.h / 2 - card.h / 2)
	end)

	it("a second arm while one is live is refused (one gesture at a time)", function()
		local b = board()
		expect(b.registry.arm("/S/Board/Card")).toBe(true)
		expect(b.registry.arm("/S/Board/Card")).toBe(false)
	end)
end)

--[[ ADAPT-16 — THE PUBLIC VERB'S PICKUP ON A PAD AND A KEYBOARD.

	Every piece of arm->navigate->commit is proved above, called directly. The
	audit's finding is that nothing CALLED it: with the card focused, ButtonA armed
	nothing and Return armed nothing, and `grep` found no caller of `registry.arm`
	anywhere in `src/present/`. The machinery was built, tested and bound to
	nothing, so a keyboard-only or pad-only player could not pick a card up at all.

	These cases drive the REAL keys through the REAL action system, and the board
	is a focusable card (a `UI.Button` with no `onActivate`, which is the shape the
	rule is about) on a screen that sinks navigation, so the presenter's own
	Activate context is what hears the press. ]]
local function padBoard()
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = Facet.newPresenter(core, env, adapter, system)
	local drops: { any } = {}
	local activates = 0
	local card = UI.draggable(
		UI.Button({
			id = "Card",
			label = "Card",
			anchor = "topLeft",
			offsetX = 0,
			offsetY = 0,
			width = { type = "fixed", px = 100 },
			height = { type = "fixed", px = 60 },
		}),
		{ payload = "card" }
	)
	local target = UI.dropTarget(
		UI.Button({
			id = "Slot",
			label = "Slot",
			anchor = "topLeft",
			offsetX = 0,
			offsetY = 200,
			width = { type = "fixed", px = 200 },
			height = { type = "fixed", px = 100 },
		}),
		{
			onDrop = function(payload: any, info: any)
				table.insert(drops, { payload = payload, info = info })
			end,
		}
	)
	local screen = UI.Screen({
		id = "S",
		children = {
			UI.Anchor({
				id = "Board",
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				children = { card, target },
			}),
		},
	})
	local handle = pres.present(screen, { sinkNavigation = true })
	pres.refresh()
	local api: any = {
		core = core,
		pres = pres,
		system = system,
		handle = handle,
		controller = handle.controller,
		drops = drops,
		registry = handle.controller.dragRegistry(),
	}
	function api.press(key: string)
		system.deviceKey(key, true)
		system.deviceKey(key, false)
		pres.refresh()
	end
	function api.focus(path: string)
		handle.controller.setFocusPath(path)
		pres.refresh()
	end
	function api.activates(): number
		return activates
	end
	function api.countActivate()
		activates += 1
	end
	return api
end

describe("ADAPT-16: the public drag verb has a pad and keyboard pickup by default", function()
	it("ButtonA on a focused card ARMS it, DPad aims it, ButtonA commits", function()
		local b = padBoard()
		b.focus("/S/Board/Card")
		expect(b.registry.isActive()).toBe(false)
		b.press("ButtonA")
		expect(b.registry.mode()).toBe("armed")
		-- the aim follows the ring, which is what the presenter has always done
		-- for an already-armed session
		b.press("DPadDown")
		expect(b.registry.verdict:get().targetId).toBe("/S/Board/Slot")
		b.press("ButtonA")
		expect(#b.drops).toBe(1)
		expect(b.drops[1].payload).toBe("card")
		expect(b.drops[1].info.mode).toBe("armed")
		expect(b.registry.isActive()).toBe(false)
	end)

	it("Return does the identical thing, because it is the same verb", function()
		local b = padBoard()
		b.focus("/S/Board/Card")
		b.press("Return")
		expect(b.registry.mode()).toBe("armed")
		b.press("Down")
		b.press("Return")
		expect(#b.drops).toBe(1)
	end)

	it("ButtonB puts it back down, and the card is not dropped anywhere", function()
		local b = padBoard()
		b.focus("/S/Board/Card")
		b.press("ButtonA")
		expect(b.registry.mode()).toBe("armed")
		b.press("ButtonB")
		expect(b.registry.isActive()).toBe(false)
		expect(#b.drops).toBe(0)
	end)

	--[[ THE RULE IS `newVirtualList`'S, AND THIS IS THE HALF THAT MAKES IT SAFE:
		a source that declares its own Activate keeps it. Otherwise adding a drag
		declaration to a button would silently steal the button's press. ]]
	it("a card with its own onActivate keeps it — the consumer's verb wins", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local presses = 0
		local card = UI.draggable(
			UI.Button({
				id = "Card",
				label = "Card",
				anchor = "topLeft",
				offsetX = 0,
				offsetY = 0,
				width = { type = "fixed", px = 100 },
				height = { type = "fixed", px = 60 },
				onActivate = function()
					presses += 1
				end,
			}),
			{ payload = "card" }
		)
		local handle = pres.present(
			UI.Screen({
				id = "S",
				children = {
					UI.Anchor({
						id = "Board",
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
						children = { card },
					}),
				},
			}),
			{ sinkNavigation = true }
		)
		pres.refresh()
		handle.controller.setFocusPath("/S/Board/Card")
		pres.refresh()
		system.deviceKey("ButtonA", true)
		system.deviceKey("ButtonA", false)
		pres.refresh()
		expect(presses).toBe(1)
		expect(handle.controller.dragRegistry().isActive()).toBe(false)
	end)
end)

describe("public drag: the presentation collaborators", function()
	it("a modal presented mid-drag CANCELS the session (F7)", function()
		local b = board()
		b.dragStart(20, 20)
		b.dragTo(30, 20)
		expect(b.registry.isActive()).toBe(true)
		b.registry.surfacePresented("modal")
		expect(b.registry.isActive()).toBe(false)
		expect(b.eventNamed("cancel").reason).toBe("modalPresented")
		-- a plain surface does NOT cancel: only a focus trap and a proxy conflict
		local c = board()
		c.dragStart(20, 20)
		c.dragTo(30, 20)
		c.registry.surfacePresented("screen")
		expect(c.registry.isActive()).toBe(true)
	end)

	it("the proxy layer tracks the pointer 1:1 and is released on the terminal", function()
		local b = board()
		local shown: { any } = {}
		local moves: { any } = {}
		local hidden = 0
		b.controller.setDragCollaborators({
			-- isolate the proxy LIFECYCLE from flights: the presenter pre-wires a
			-- motion clock on every surface now (Step-5 integration), so a test
			-- about show/track/release opts it back out with the `false` sentinel
			motionClock = false,
			proxy = {
				show = function(info: any)
					table.insert(shown, info)
					return { id = "ghost" }
				end,
				transform = function(_handle: any, tr: any)
					table.insert(moves, tr)
				end,
				hide = function()
					hidden += 1
				end,
			},
		})
		b.dragStart(20, 20)
		b.dragTo(30, 20)
		expect(#shown).toBe(1)
		expect(shown[1].payload).toBe("card")
		local cardRect = b.rect("/S/Board/Card")
		b.dragTo(130, 220)
		local last = moves[#moves]
		-- the DEFAULT grab anchor is "center" (director fix round, RR parity): the
		-- ghost rides CENTERED under the pointer with no spring on the finger, so
		-- its top-left is the pointer minus half the source
		expect(last.x).toBe(130 - cardRect.w / 2)
		expect(last.y).toBe(220 - cardRect.h / 2)
		b.dragEnd(700, 500)
		expect(hidden).toBe(1)
	end)

	it("grabAnchor = 'preserve' keeps the grab-point offset exactly", function()
		local b = board({ grabAnchor = "preserve" })
		local moves: { any } = {}
		b.controller.setDragCollaborators({
			motionClock = false,
			proxy = {
				show = function()
					return { id = "ghost" }
				end,
				transform = function(_h: any, tr: any)
					table.insert(moves, tr)
				end,
				hide = function() end,
			},
		})
		b.dragStart(20, 20)
		b.dragTo(30, 20)
		local cardRect = b.rect("/S/Board/Card")
		b.dragTo(130, 220)
		local last = moves[#moves]
		-- grabbed at (30,20) inside the card: the ghost keeps that offset exactly
		expect(last.x).toBe(130 - (30 - cardRect.x))
		expect(last.y).toBe(220 - (20 - cardRect.y))
		b.dragEnd(700, 500)
	end)

	it("without a motion clock the terminal resolves instantly instead of flying", function()
		local b = board()
		local hidden = 0
		b.controller.setDragCollaborators({
			-- the degraded-host case: the presenter pre-wires a clock, so "without
			-- a motion clock" is now CONSTRUCTED with the `false` sentinel
			motionClock = false,
			proxy = {
				show = function()
					return { id = "ghost" }
				end,
				transform = function() end,
				hide = function()
					hidden += 1
				end,
			},
		})
		b.dragStart(20, 20)
		b.dragTo(30, 20)
		b.dragEnd(700, 500) -- illegal: would normally fly home
		expect(hidden).toBe(1)
		expect(b.registry.isActive()).toBe(false) -- no clock: no flight to wait for
	end)

	it("with a motion clock the reject flies home, seeded with the release velocity", function()
		local b = board()
		local now = 0
		local clock = Facet.motion.newClock(b.core, {
			now = function()
				return now
			end,
		})
		local moves: { any } = {}
		local hidden = 0
		b.controller.setDragCollaborators({
			now = function()
				return now
			end,
			motionClock = clock,
			proxy = {
				show = function()
					return { id = "ghost" }
				end,
				transform = function(_h: any, tr: any)
					table.insert(moves, tr)
				end,
				hide = function()
					hidden += 1
				end,
			},
		})
		b.dragStart(20, 20)
		now = 0.02
		b.dragTo(40, 20)
		now = 0.04
		b.dragTo(120, 20) -- a fast rightward toss
		now = 0.06
		b.dragEnd(200, 20) -- released over nothing: free-area cancel + fly home
		expect(b.eventNamed("cancel") ~= nil).toBe(true)
		-- the flight is LIVE: the session is still holding the proxy
		expect(hidden).toBe(0)
		local before = moves[#moves].x
		now = 0.08
		clock:step(0.02)
		-- seeded with the toss velocity, the first frame keeps travelling RIGHT,
		-- away from home — that is the seam a zero seed would show
		expect(moves[#moves].x > before).toBe(true)
		for i = 1, 200 do
			now += 0.016
			clock:step(0.016)
			if hidden > 0 then
				break
			end
			local _ = i
		end
		expect(hidden).toBe(1)
		expect(b.registry.isActive()).toBe(false)
		clock:dispose()
	end)

	it("a NON-gestural cancel seeds ZERO through the same path", function()
		local b = board()
		local now = 0
		local clock = Facet.motion.newClock(b.core, {
			now = function()
				return now
			end,
		})
		local moves: { any } = {}
		local hidden = 0
		b.controller.setDragCollaborators({
			now = function()
				return now
			end,
			motionClock = clock,
			proxy = {
				show = function()
					return { id = "ghost" }
				end,
				transform = function(_h: any, tr: any)
					table.insert(moves, tr)
				end,
				hide = function()
					hidden += 1
				end,
			},
		})
		b.dragStart(20, 20)
		now = 0.02
		b.dragTo(40, 20)
		now = 0.04
		b.dragTo(200, 20) -- moving fast when the cancel lands
		b.registry.cancel("modalPresented")
		local before = moves[#moves].x
		now = 0.06
		clock:step(0.02)
		-- a cancel is not a throw: it never inherits the gesture's momentum, so
		-- the very first frame already heads back toward home
		expect(moves[#moves].x < before).toBe(true)
		for _ = 1, 200 do
			now += 0.016
			clock:step(0.016)
			if hidden > 0 then
				break
			end
		end
		expect(hidden).toBe(1)
		clock:dispose()
	end)
end)

describe("public drag: authoring errors name the fix", function()
	it("refuses a draggable with no payload", function()
		local ok, err = pcall(function()
			UI.draggable(UI.Box({ id = "X" }), {})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "payload", 1, true) ~= nil).toBe(true)
	end)

	it("refuses a drop target with no onDrop", function()
		local ok, err = pcall(function()
			UI.dropTarget(UI.Box({ id = "X" }), {
				accepts = function()
					return true
				end,
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "onDrop", 1, true) ~= nil).toBe(true)
	end)

	it("resolves the motion class at DECLARATION time, not mid-gesture", function()
		local ok, err = pcall(function()
			UI.draggable(UI.Box({ id = "X" }), { payload = 1, dragMotion = "zoomy" })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "zoomy", 1, true) ~= nil).toBe(true)
	end)

	it("refuses an unknown onCommitProxy form", function()
		local ok = pcall(function()
			UI.draggable(UI.Box({ id = "X" }), { payload = 1, onCommitProxy = "vanish" })
		end)
		expect(ok).toBe(false)
	end)

	it("declarations ride `meta`, so strict prop validation is untouched", function()
		local bp = UI.draggable(UI.Box({ id = "X" }), { payload = 1 })
		expect(bp.props.dragSource).toBe(nil)
		expect(bp.meta.dragSource.payload).toBe(1)
		expect(bp.meta.dragSource.dragMotion).toBe("object")
	end)
end)

-- ===========================================================================
describe("UI.draggable `enabled` — acquisition refused, the control still speaks (SF-D6)", function()
	-- A blocked affordance has to stay pressable: "skipped for navigation" (and
	-- "cannot be dragged") must never mean "dead to inspection", or the player
	-- loses the one thing that could tell them WHY. `enabled = false` on the node
	-- refuses acquisition too, but it also eats the tap — so it cannot serve this.
	local function world(gate: any)
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, Facet.newActionSystem(core))
		local activations = 0
		local screen = Facet.UI.Screen({
			id = "S",
			children = {
				Facet.UI.Anchor({
					id = "Board",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						Facet.UI.draggable(
							Facet.UI.Button({
								id = "Card",
								label = "Card",
								anchor = "topLeft",
								offsetX = 0,
								offsetY = 0,
								width = { type = "fixed", px = 100 },
								height = { type = "fixed", px = 60 },
								onActivate = function()
									activations += 1
								end,
							}),
							{ payload = "card", armOnTap = true, enabled = gate }
						),
					},
				}),
			},
		})
		local handle = pres.present(screen)
		pres.refresh()
		local t = 0
		handle.controller.setDragCollaborators({
			now = function()
				return t
			end,
		})
		return {
			adapter = adapter,
			pres = pres,
			registry = handle.controller.dragRegistry(),
			tap = function()
				t += 1
				adapter.driveDragStart("/S/Board/Card", { x = 20, y = 20, pointerType = "touch" })
				adapter.driveDragEnd("/S/Board/Card", { x = 22, y = 20, pointerType = "touch" })
			end,
			travel = function()
				t += 1
				adapter.driveDragStart("/S/Board/Card", { x = 20, y = 20, pointerType = "mouse" })
				adapter.driveDragContinue("/S/Board/Card", { x = 80, y = 20, pointerType = "mouse" }, { x = 60, y = 0 })
			end,
			activations = function()
				return activations
			end,
		}
	end

	it("a refused source ARMS NOTHING on tap — and the tap reaches the consumer instead", function()
		local w = world(false)
		w.tap()
		expect(w.registry.isActive()).toBe(false)
		-- the whole point: the control still activated, so it can say why
		expect(w.activations()).toBe(1)
	end)

	it("a refused source does not PROMOTE either, however far the pointer travels", function()
		local w = world(false)
		w.travel()
		expect(w.registry.isActive()).toBe(false)
	end)

	it("the gate is LIVE: a Readable flipping true makes the same tap a pickup", function()
		local core = Facet.newCore()
		local gate = core:signal(false)
		local w = world(gate)
		w.tap()
		expect(w.registry.isActive()).toBe(false)
		expect(w.activations()).toBe(1)
		gate:set(true)
		w.tap()
		expect(w.registry.isActive()).toBe(true)
		expect(w.registry.mode()).toBe("armed")
		-- the pickup IS the activation: the consumer's onActivate did NOT fire again
		expect(w.activations()).toBe(1)
	end)

	it("absent, nothing changes: the source arms exactly as it always did", function()
		local w = world(nil)
		w.tap()
		expect(w.registry.isActive()).toBe(true)
		expect(w.activations()).toBe(0)
	end)

	it("a non-boolean, non-Readable gate is refused at construction, naming the reason", function()
		local ok, err = pcall(function()
			Facet.UI.draggable(Facet.UI.Box({ id = "B" }), { payload = "x", enabled = "yes" })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "ACQUISITION only", 1, true) ~= nil).toBe(true)
	end)
end)

-- ===========================================================================
-- F-18 (ledger/blueprints.md BP-F15): `UI.draggable` / `UI.dropTarget` applied
-- NO class gate, so a declaration on `When` / `ForEach` / `ErrorBoundary` was
-- accepted and inert — the renderer registers a drag source inside the
-- per-instance branch of `ensureTree`, which a structural node never reaches.
-- Every other modifier is gated by the schema; these two now gate themselves.
-- ===========================================================================

describe("F-18: a drag declaration is refused on a structural node", function()
	local function structural(class: string): any
		local core = Facet.newCore()
		if class == "When" then
			return UI.When({
				id = "W",
				condition = core:signal(true),
				thenView = function()
					return UI.Box({ id = "c" })
				end,
			})
		elseif class == "ForEach" then
			return UI.ForEach({
				id = "F",
				items = core:signal({ 1 }),
				key = function(item)
					return tostring(item)
				end,
				row = function()
					return UI.Box({ id = "c" })
				end,
			})
		end
		return UI.ErrorBoundary({
			id = "E",
			view = function()
				return UI.Box({ id = "c" })
			end,
			fallback = function()
				return UI.Box({ id = "f" })
			end,
		})
	end

	for _, class in { "When", "ForEach", "ErrorBoundary" } do
		it(`UI.draggable on a UI.{class} names the class and the fix`, function()
			local ok, err = pcall(function()
				return UI.draggable(structural(class), { payload = 1 })
			end)
			expect(ok).toBe(false)
			local message = tostring(err)
			expect(string.find(message, `UI.{class}`, 1, true) ~= nil).toBe(true)
			expect(string.find(message, "UI.draggable", 1, true) ~= nil).toBe(true)
			expect(string.find(message, "wrap", 1, true) ~= nil).toBe(true)
		end)

		it(`UI.dropTarget on a UI.{class} is refused the same way`, function()
			local ok, err = pcall(function()
				return UI.dropTarget(structural(class), { onDrop = function() end })
			end)
			expect(ok).toBe(false)
			expect(string.find(tostring(err), `UI.{class}`, 1, true) ~= nil).toBe(true)
			expect(string.find(tostring(err), "UI.dropTarget", 1, true) ~= nil).toBe(true)
		end)
	end

	it("a RENDERED node still takes both declarations", function()
		expect(pcall(function()
			return UI.draggable(UI.Box({ id = "B" }), { payload = 1 })
		end)).toBe(true)
		expect(pcall(function()
			return UI.dropTarget(UI.VStack({ id = "V", children = {} }), { onDrop = function() end })
		end)).toBe(true)
	end)
end)
