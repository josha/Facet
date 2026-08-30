--!strict
-- STEP-5 PRESENTER INTEGRATION (the lead's glue between packages): what a
-- surface gets WITHOUT wiring anything — the feedback
-- bus on drag events, the shared motion clock driving terminal flights, the
-- ghost layer, the F7 modal broadcast — plus the presenter's public frame hook.
-- These are the seams a fixture consumes blind, so each is pinned here against
-- the exact regression integration fixed: collaborators that exist headlessly
-- but never reach a live surface.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local fake_target = require("../tests/lib/fake_target")

local UI = Facet.UI

local function rig()
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = Facet.newPresenter(core, env, adapter, system)

	local drops: { any } = {}
	local screen = UI.Screen({
		id = "S",
		children = {
			UI.Anchor({
				id = "Board",
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				children = {
					UI.draggable(
						UI.Box({
							id = "Card",
							anchor = "topLeft",
							offsetX = 0,
							offsetY = 0,
							width = { type = "fixed", px = 100 },
							height = { type = "fixed", px = 60 },
						}),
						{ payload = "card", onCommitProxy = "flyToTarget" }
					),
					UI.dropTarget(
						UI.Box({
							id = "SlotA",
							anchor = "topLeft",
							offsetX = 0,
							offsetY = 300,
							width = { type = "fixed", px = 200 },
							height = { type = "fixed", px = 100 },
						}),
						{
							onDrop = function(payload: any, info: any)
								table.insert(drops, { payload = payload, info = info })
							end,
						}
					),
				},
			}),
		},
	})
	local events: { any } = {}
	pres.onFeedback(function(event: any)
		table.insert(events, event)
	end)
	local handle = pres.present(screen)
	pres.refresh()
	return {
		core = core,
		adapter = adapter,
		pres = pres,
		handle = handle,
		controller = handle.controller,
		registry = handle.controller.dragRegistry(),
		drops = drops,
		events = events,
		names = function(): { string }
			local out = {}
			for _, e in events do
				table.insert(out, e.type)
			end
			return out
		end,
	}
end

describe("presenter drag integration: the auto-wired collaborators", function()
	it("a presented surface's drag events reach the PRESENTER bus, surface attached", function()
		local b = rig()
		b.registry.arm("/S/Board/Card")
		b.registry.armTo("/S/Board/SlotA")
		b.registry.commit()
		local names = b.names()
		expect(names[1]).toBe("select")
		expect(table.find(names, "commit") ~= nil).toBe(true)
		expect(b.events[1].surface).toBe(b.handle)
		expect(#b.drops).toBe(1)
	end)

	it("the auto-wired motion clock defers `land` to the ARRIVAL frame; ticking lands it", function()
		local b = rig()
		b.registry.arm("/S/Board/Card")
		b.registry.armTo("/S/Board/SlotA")
		b.registry.commit()
		-- terminal is immediate (detached-flight rule)…
		expect(b.registry.isActive()).toBe(false)
		-- …but the commit flight is CLOCK-DRIVEN because the presenter wired its
		-- clock: land has not fired yet, and arrives only through presenter.tick
		expect(table.find(b.names(), "land")).toBe(nil)
		for _ = 1, 240 do
			if table.find(b.names(), "land") ~= nil then
				break
			end
			b.pres.tick(1 / 60)
		end
		expect(table.find(b.names(), "land") ~= nil).toBe(true)
	end)

	it("the HELD SOURCE is a framework guarantee: dragHeld rides pickup, clears on the RETURN'S ARRIVAL", function()
		-- director round five: "the slot sits empty until it lands or returns" is
		-- universal — the registry publishes the held path, the renderer stamps
		-- `dragHeld` on the node (native: the `.facet-drag-held` sheet rule empties
		-- the label; bespoke: a direct text write), and NO consumer writes a line.
		local b = rig()
		expect(b.adapter.node("/S/Board/Card").props.dragHeld).toBeNil()
		b.registry.arm("/S/Board/Card")
		expect(b.adapter.node("/S/Board/Card").props.dragHeld).toBe(true)
		b.registry.cancel("done")
		-- held SURVIVES the release frame: the card is still visually in flight
		expect(b.adapter.node("/S/Board/Card").props.dragHeld).toBe(true)
		local returned = false
		for _ = 1, 240 do
			b.pres.tick(1 / 60)
			for _, e in b.events do
				if e.type == "arrive" and type(e.context) == "table" and e.context.returned == true then
					returned = true
				end
			end
			if returned then
				break
			end
		end
		-- the return flight ARRIVED (the new `arrive` emission) and the slot refills
		expect(returned).toBe(true)
		expect(b.adapter.node("/S/Board/Card").props.dragHeld).toBe(false)
	end)

	it("the dragHeld write goes through the authority assert like every other (ARCH-3)", function()
		--[[ The two `setProp(..., "dragHeld", ...)` calls were the only writes in
			`renderer.luau` that skipped `authority.assertWrite` — the one sentence
			constitution §11 makes about the renderer. The instrument is the manifest
			itself: move `dragHeld` to another authority and the write must be
			REFUSED (quarantined by the observer that made it, so the diagnostic is
			`core:lastError`) rather than landing anyway. This is the existing
			authority-parity idiom — `authority.manifest()` hands back the live table
			on purpose, so a checker can read it. ]]
		local authority = require("../src/render/authority")
		local manifest = authority.manifest()
		local restore = manifest.common.dragHeld
		manifest.common.dragHeld = "style"
		local ok = pcall(function()
			local b = rig()
			b.registry.arm("/S/Board/Card")
			expect(b.adapter.node("/S/Board/Card").props.dragHeld).toBeNil()
			expect(string.find(tostring(b.core:lastError()), "presentation tried to write", 1, true) ~= nil).toBe(true)
			expect(string.find(tostring(b.core:lastError()), "dragHeld", 1, true) ~= nil).toBe(true)
		end)
		manifest.common.dragHeld = restore
		expect(ok).toBe(true)

		-- ...and with the manifest as it ships, the same pickup writes
		local b = rig()
		b.registry.arm("/S/Board/Card")
		expect(b.adapter.node("/S/Board/Card").props.dragHeld).toBe(true)
		expect(b.core:lastError()).toBeNil()
	end)

	it("...and the RELEASE site pays the same assert (ARCH-3)", function()
		--[[ There are two `dragHeld` writes, and the first version of this case only
			exercised the pickup: bypassing the assert on the `false` path alone left
			the suite green (review's mutation-confirmed coverage gap). The clear is
			the write that matters most — it is what puts the label back — and it goes
			out from a different branch of the same observer. ]]
		local authority = require("../src/render/authority")
		local manifest = authority.manifest()
		local b = rig()
		b.registry.arm("/S/Board/Card")
		expect(b.adapter.node("/S/Board/Card").props.dragHeld).toBe(true)
		expect(b.core:lastError()).toBeNil()

		-- move the property mid-session, so ONLY the clear meets the changed
		-- manifest — the pickup already happened under the shipping one
		local restore = manifest.common.dragHeld
		manifest.common.dragHeld = "style"
		local ok = pcall(function()
			b.registry.cancel("done")
			for _ = 1, 240 do
				b.pres.tick(1 / 60)
				if b.core:lastError() ~= nil then
					break
				end
			end
			-- the clear was REFUSED, so the node is still wearing the held state
			expect(b.adapter.node("/S/Board/Card").props.dragHeld).toBe(true)
			expect(string.find(tostring(b.core:lastError()), "presentation tried to write", 1, true) ~= nil).toBe(true)
			expect(string.find(tostring(b.core:lastError()), "dragHeld", 1, true) ~= nil).toBe(true)
		end)
		manifest.common.dragHeld = restore
		expect(ok).toBe(true)

		-- ...and the negative control: the same release under the shipping manifest
		-- puts the label back and says nothing
		local c = rig()
		c.registry.arm("/S/Board/Card")
		c.registry.cancel("done")
		for _ = 1, 240 do
			c.pres.tick(1 / 60)
			if c.adapter.node("/S/Board/Card").props.dragHeld == false then
				break
			end
		end
		expect(c.adapter.node("/S/Board/Card").props.dragHeld).toBe(false)
		expect(c.core:lastError()).toBeNil()
	end)

	it("the ghost layer mounts on pickup and is GONE after the flight (registry-neutral)", function()
		local b = rig()
		b.registry.arm("/S/Board/Card")
		-- the presenter's proxy host mounted a real (fake-adapter) surface
		expect(b.adapter.node("/__dragproxy__/Layer/Slot") ~= nil).toBe(true)
		b.registry.cancel("done")
		for _ = 1, 240 do
			b.pres.tick(1 / 60)
		end
		-- …and it does not survive the flight
		expect(b.adapter.node("/__dragproxy__/Layer/Slot")).toBe(nil)
	end)

	it("presentModal mid-drag cancels the base surface's session (F7, end to end)", function()
		local b = rig()
		b.registry.arm("/S/Board/Card")
		expect(b.registry.isActive()).toBe(true)
		local modal = b.pres.presentModal(UI.Screen({
			id = "M",
			children = { UI.Button({ id = "Ok", label = "Ok", onActivate = function() end }) },
		}))
		expect(b.registry.isActive()).toBe(false)
		local cancelAt: any = nil
		for _, e in b.events do
			if e.type == "cancel" and e.reason == "modalPresented" then
				cancelAt = e
			end
		end
		expect(cancelAt ~= nil).toBe(true)
		b.pres.dismiss(modal)
	end)
end)

describe("detector taps are never eaten (SF-D3 live half)", function()
	-- Found 2026-07-27 by a REAL injected click in Studio: the engine's
	-- UIDragDetector consumes the click on a draggable Button, so `.Activated`
	-- never fires and a plain tap did nothing — while headless stayed green
	-- because the fake mirror preserved the native tap. The registry now answers
	-- "tap" for an under-threshold detector release and the renderer dispatches
	-- it through the SAME node-tap path a native tap takes.
	it("an under-threshold detector release dispatches Activate exactly once", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, Facet.newActionSystem(core))
		local activations = 0
		local screen = UI.Screen({
			id = "S",
			children = {
				UI.Anchor({
					id = "Board",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						UI.draggable(
							UI.Button({
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
							{ payload = "card" }
						),
					},
				}),
			},
		})
		local handle = pres.present(screen)
		pres.refresh()
		local registry = handle.controller.dragRegistry()
		-- under the 6px pointer token: down, 4px of travel, release = a tap
		adapter.driveDragStart("/S/Board/Card", { x = 20, y = 20, pointerType = "mouse" })
		adapter.driveDragContinue("/S/Board/Card", { x = 24, y = 20, pointerType = "mouse" }, { x = 4, y = 0 })
		adapter.driveDragEnd("/S/Board/Card", { x = 24, y = 20, pointerType = "mouse" })
		expect(activations).toBe(1)
		expect(registry.isActive()).toBe(false)
		-- over the token: a real drag — no activation, a session instead
		adapter.driveDragStart("/S/Board/Card", { x = 20, y = 20, pointerType = "mouse" })
		adapter.driveDragContinue("/S/Board/Card", { x = 40, y = 20, pointerType = "mouse" }, { x = 20, y = 0 })
		expect(registry.isActive()).toBe(true)
		adapter.driveDragEnd("/S/Board/Card", { x = 700, y = 500, pointerType = "mouse" })
		expect(activations).toBe(1)
	end)

	it("armOnTap: a TAP IS the pickup — arms instead of activating; a tap while held flows through", function()
		-- director round six: the touch paradigm's pickup. Tap a declaring card =
		-- an armed session (one-thumb mobile flow: scroll freely, tap a row to
		-- drop); the consumer's onActivate is NOT called — the pickup is the
		-- activation. A tap while a session is live flows to the consumer
		-- unchanged (put-back and row commits stay consumer/list semantics).
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, Facet.newActionSystem(core))
		local activations = 0
		local screen = UI.Screen({
			id = "S",
			children = {
				UI.Anchor({
					id = "Board",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						UI.draggable(
							UI.Button({
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
							{ payload = "card", armOnTap = true }
						),
					},
				}),
			},
		})
		local handle = pres.present(screen)
		pres.refresh()
		local registry = handle.controller.dragRegistry()
		-- an injectable clock steps past the PLAT-1 echo window between presses
		-- (two real presses in one test frame would otherwise read as one echo)
		local t = 0
		handle.controller.setDragCollaborators({
			now = function()
				return t
			end,
		})
		-- an under-threshold TOUCH release: not an activation — a pickup
		adapter.driveDragStart("/S/Board/Card", { x = 20, y = 20, pointerType = "touch" })
		adapter.driveDragEnd("/S/Board/Card", { x = 22, y = 20, pointerType = "touch" })
		expect(activations).toBe(0)
		expect(registry.isActive()).toBe(true)
		expect(registry.mode()).toBe("armed")
		-- the held guarantee rides the tap pickup too
		expect(adapter.node("/S/Board/Card").props.dragHeld).toBe(true)
		-- a tap WHILE HELD is the consumer's (put-back etc.): activate flows
		t += 1
		adapter.driveDragStart("/S/Board/Card", { x = 20, y = 20, pointerType = "touch" })
		adapter.driveDragEnd("/S/Board/Card", { x = 22, y = 20, pointerType = "touch" })
		expect(activations).toBe(1)
		registry.cancel("done")
		for _ = 1, 240 do
			pres.tick(1 / 60)
		end
		expect(adapter.node("/S/Board/Card").props.dragHeld).toBe(false)
		-- a REAL travel on the same card still promotes to a pointer drag
		adapter.driveDragStart("/S/Board/Card", { x = 20, y = 20, pointerType = "touch" })
		adapter.driveDragContinue("/S/Board/Card", { x = 60, y = 20, pointerType = "touch" }, { x = 40, y = 0 })
		expect(registry.isActive()).toBe(true)
		expect(registry.mode()).toBe("pointer")
		adapter.driveDragEnd("/S/Board/Card", { x = 700, y = 500, pointerType = "touch" })
		expect(activations).toBe(1)
	end)

	it("one press cannot activate twice when BOTH signals arrive (PLAT-1 echo guard)", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, Facet.newActionSystem(core))
		local activations = 0
		local screen = UI.Screen({
			id = "S",
			children = {
				UI.Anchor({
					id = "Board",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						UI.draggable(
							UI.Button({
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
							{ payload = "card" }
						),
					},
				}),
			},
		})
		local handle = pres.present(screen)
		pres.refresh()
		-- a scripted clock so the echo window is deterministic
		local t = 0
		handle.controller.setDragCollaborators({
			now = function()
				return t
			end,
		})
		-- one press, two signals: the detector's synthesized tap AND the native
		-- Activated (gamepad-A-shaped engine behavior) inside the echo window
		adapter.driveDragStart("/S/Board/Card", { x = 20, y = 20, pointerType = "mouse" })
		adapter.driveDragEnd("/S/Board/Card", { x = 22, y = 20, pointerType = "mouse" })
		adapter.tap("/S/Board/Card")
		expect(activations).toBe(1)
		-- past the window, a REAL second tap counts — the guard can never eat one
		t = 0.2
		adapter.tap("/S/Board/Card")
		expect(activations).toBe(2)
	end)
end)

describe("mid-flight teardown and retiring surfaces (ARCH-F1 / ARCH-F2)", function()
	it("dismissing a surface mid-commit-flight leaves the shared clock EMPTY", function()
		local b = rig()
		b.registry.arm("/S/Board/Card")
		b.registry.armTo("/S/Board/SlotA")
		b.registry.commit()
		b.pres.tick(1 / 60) -- the flight is airborne on the presenter clock
		b.pres.dismiss(b.handle)
		for _ = 1, 120 do
			b.pres.tick(1 / 60)
		end
		-- ARCH-F1: the chase died with the surface — no orphan stepping forever
		expect(b.pres.motionClock:activeCount()).toBe(0)
	end)

	-- RR-3-R1 (Step 5.5 disposition): registry.dispose() walks `detachedFlights`
	-- while hideProxyFor clears the entry it is standing on. Clearing an EXISTING
	-- key during generalized iteration is legal in Luau, but nothing executed the
	-- teardown path with flights actually in the air, so the residual was carried
	-- unverified. This drives it: TWO flights airborne, disposed mid-flight.
	it("disposing the registry with several flights in the air is clean (RR-3-R1)", function()
		-- the CONTROL: the same surface presented and dismissed, no drag at all.
		-- Counters are per-core and both cores are fresh, so the control's
		-- post-teardown numbers are what "left nothing behind" means here.
		local control = rig()
		control.pres.dismiss(control.handle)
		local expected = control.core:counters()

		local b = rig()
		local registry = b.registry
		for _ = 1, 2 do
			registry.arm("/S/Board/Card")
			registry.armTo("/S/Board/SlotA")
			registry.commit()
			b.pres.tick(1 / 60) -- airborne on the presenter clock
		end
		local ok, err = pcall(function()
			registry.dispose()
		end)
		expect(ok).toBe(true)
		expect(err).toBe(nil)
		-- no flight survives its registry: the shared clock is empty and stays empty
		for _ = 1, 120 do
			b.pres.tick(1 / 60)
		end
		expect(b.pres.motionClock:activeCount()).toBe(0)
		-- and the flights' own core resources went back (SF-C1 neutrality)
		b.pres.dismiss(b.handle)
		local after = b.core:counters()
		for key, value in expected :: any do
			expect(`{key}={(after :: any)[key]}`).toBe(`{key}={value}`)
		end
	end)

	it("a RETIRING drop target leaves resolution and returns on re-entry (ARCH-F2)", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, Facet.newActionSystem(core))
		local slotOn = core:signal(true)
		local dropped = 0
		local screen = UI.Screen({
			id = "S",
			children = {
				UI.Anchor({
					id = "Board",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						UI.draggable(
							UI.Button({
								id = "Card",
								label = "Card",
								anchor = "topLeft",
								offsetX = 0,
								offsetY = 0,
								width = { type = "fixed", px = 100 },
								height = { type = "fixed", px = 60 },
								onActivate = function() end,
							}),
							{ payload = "card" }
						),
						UI.When({
							id = "SlotRegion",
							condition = slotOn,
							transition = { enter = "fade", exit = "fade" },
							thenView = function()
								return UI.dropTarget(
									UI.ZStack({
										id = "Slot",
										canvasGroup = true,
										anchor = "topLeft",
										offsetX = 0,
										offsetY = 300,
										width = { type = "fixed", px = 200 },
										height = { type = "fixed", px = 100 },
										children = {
											UI.Box({
												id = "Plate",
												surface = "control",
												width = { type = "fill", weight = 1 },
												height = { type = "fill", weight = 1 },
											}),
										},
									}),
									{
										onDrop = function()
											dropped += 1
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
		local slotPath = "/S/Board/SlotRegion/then/Slot"
		expect(registry.arm("/S/Board/Card")).toBe(true)
		expect(registry.armTo(slotPath)).toBe(true)
		registry.cancel("setup")
		-- retire the slot: it keeps painting its exit but is NOT a drop surface
		slotOn:set(false)
		pres.refresh()
		expect(registry.arm("/S/Board/Card")).toBe(true)
		expect(registry.armTo(slotPath)).toBe(false)
		registry.commit()
		expect(dropped).toBe(0)
		registry.cancel("cleanup")
		-- re-entry mid-exit: eligible again the same frame, no rewiring
		slotOn:set(true)
		pres.refresh()
		expect(registry.arm("/S/Board/Card")).toBe(true)
		expect(registry.armTo(slotPath)).toBe(true)
		registry.commit()
		expect(dropped).toBe(1)
	end)

	it("a retiring '/S/Slot' never excludes its live SIBLING '/S/SlotA' (P2-2)", function()
		-- the segment-boundary rule: exclusion is by subtree, not by string prefix
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, Facet.newActionSystem(core))
		local slotOn = core:signal(true)
		local droppedA = 0
		local function target(id: string, y: number, onDrop: () -> ())
			return UI.dropTarget(
				UI.Box({
					id = id,
					anchor = "topLeft",
					offsetX = 0,
					offsetY = y,
					width = { type = "fixed", px = 200 },
					height = { type = "fixed", px = 80 },
				}),
				{ onDrop = onDrop }
			)
		end
		local screen = UI.Screen({
			id = "S",
			children = {
				UI.Anchor({
					id = "Board",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						UI.draggable(
							UI.Button({
								id = "Card",
								label = "C",
								anchor = "topLeft",
								offsetX = 0,
								offsetY = 0,
								width = { type = "fixed", px = 100 },
								height = { type = "fixed", px = 60 },
								onActivate = function() end,
							}),
							{ payload = "card" }
						),
						-- "Slot" retires; "SlotA" shares the string prefix and must stay live
						UI.When({
							id = "SlotRegion",
							condition = slotOn,
							transition = { enter = "fade", exit = "fade" },
							thenView = function()
								return UI.ZStack({
									id = "Slot",
									canvasGroup = true,
									anchor = "topLeft",
									offsetX = 0,
									offsetY = 300,
									width = { type = "fixed", px = 200 },
									height = { type = "fixed", px = 80 },
									children = {
										UI.Box({
											id = "Plate",
											surface = "control",
											width = { type = "fill", weight = 1 },
											height = { type = "fill", weight = 1 },
										}),
									},
								})
							end,
						}),
						target("SlotA", 420, function()
							droppedA += 1
						end),
					},
				}),
			},
		})
		local handle = pres.present(screen)
		pres.refresh()
		local registry = handle.controller.dragRegistry()
		slotOn:set(false) -- "/S/Board/SlotRegion/then/Slot" retires
		pres.refresh()
		expect(registry.arm("/S/Board/Card")).toBe(true)
		expect(registry.armTo("/S/Board/SlotA")).toBe(true)
		registry.commit()
		expect(droppedA).toBe(1)
	end)

	it("a DISABLED draggable acquires no session (P2-3), and re-enabling restores it", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, Facet.newActionSystem(core))
		local enabled = core:signal(false)
		local screen = UI.Screen({
			id = "S",
			children = {
				UI.Anchor({
					id = "Board",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						UI.draggable(
							UI.Button({
								id = "Card",
								label = "C",
								enabled = enabled,
								anchor = "topLeft",
								offsetX = 0,
								offsetY = 0,
								width = { type = "fixed", px = 100 },
								height = { type = "fixed", px = 60 },
								onActivate = function() end,
							}),
							{ payload = "card" }
						),
					},
				}),
			},
		})
		local handle = pres.present(screen)
		pres.refresh()
		local registry = handle.controller.dragRegistry()
		expect(registry.arm("/S/Board/Card")).toBe(false)
		adapter.driveDragStart("/S/Board/Card", { x = 20, y = 20, pointerType = "mouse" })
		adapter.driveDragContinue("/S/Board/Card", { x = 40, y = 20, pointerType = "mouse" }, { x = 20, y = 0 })
		expect(registry.isActive()).toBe(false)
		adapter.driveDragEnd("/S/Board/Card", { x = 40, y = 20, pointerType = "mouse" })
		enabled:set(true)
		pres.refresh()
		expect(registry.arm("/S/Board/Card")).toBe(true)
	end)
end)

describe("presenter frame hook (onTick)", function()
	it("hooks run inside tick with the frame dt, and unsubscribe cleanly", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local pres = Facet.newPresenter(core, env, fake_target.new(), Facet.newActionSystem(core))
		local seen: { number } = {}
		local unsub = pres.onTick(function(dt: number)
			table.insert(seen, dt)
		end)
		pres.tick(0.016)
		pres.tick(0.02)
		expect(#seen).toBe(2)
		expect(seen[2]).toBe(0.02)
		unsub()
		pres.tick(0.016)
		expect(#seen).toBe(2)
	end)
end)
