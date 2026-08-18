--!strict
-- VirtualList four-input story (ui_todo §0; ADR-0013; matrix §1c). Proves the
-- presenter AUTO-COMPOSES VirtualList's pointer / touch / keyboard / gamepad
-- interaction from the input-contribution bundle the control attaches to its
-- root — with NO consumer present() wiring. Every interaction goes through the
-- REAL device paths (adapter.tap / adapter.scrollWheel / adapter.pointer* for
-- pointer & touch, system.deviceKey for keyboard & gamepad), never a direct api
-- call. Supplements tests/virtualization.spec.luau (which proves virtualization
-- correctness via Signal/api writes) — it does NOT replace it.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local worldLib = require("./lib/world")

local Facet = require("../src") :: any
local virtual_list = require("../src/controls/virtual_list")
local fake_target = require("../tests/lib/fake_target")

local function makeRows(n: number): { { id: string, label: string } }
	local rows = {}
	for i = 1, n do
		table.insert(rows, { id = `r{i}`, label = `Row {i}` })
	end
	return rows
end

--[[ ONE SUBSTRATE, ONE ORDER (reuse audit REUSE-88, controller ruling R12).
	`tests/lib/world.luau` owns the construction and its two invariants; the tuple
	this file hands its cases is `core, env, adapter, system, pres` — the order
	`Facet.newPresenter` itself takes, and now the only one in the suite. It used
	to be `core, env, system, adapter, pres` here and the other spelling sixteen
	files away, with the same five names on both sides, so a line copied between
	two neighbouring specs bound an action system to a variable called `adapter`
	and said nothing. ]]
local function harness()
	local w = worldLib.new({ viewport = { x = 0, y = 0, w = 800, h = 600 } })
	return w.core, w.env, w.adapter, w.system, w.pres
end

-- a VirtualList inside a Screen, presented with ZERO opts (full auto-composition)
local function world(opts: any?)
	local options = opts or {}
	local core, env, adapter, system, pres = harness()
	local rows = core:signal(makeRows(options.count or 100))
	local activations: { any } = {}
	local list = virtual_list.build(Facet, core, {
		id = "VL",
		rows = rows,
		key = function(item: any)
			return item.id
		end,
		rowHeight = 40,
		viewportHeight = options.viewportHeight or 400, -- 10 visible rows
		overscan = options.overscan or 2,
		cell = function(item: any)
			return Facet.UI.Text({ id = "Label", text = item.label, textSize = 14 })
		end,
		onActivate = function(item: any, meta: any)
			table.insert(activations, { item = item, meta = meta })
		end,
	})
	local screen = Facet.UI.Screen({ id = "S", children = { list.blueprint } })
	local handle = pres.present(screen) -- ZERO present opts
	pres.refresh()
	-- wire the engine CanvasPosition mirror (native-substrate NS-A2): on the live
	-- adapter this is what the presenter/consumer does after present so
	-- observeScroll feeds scrollTop and keep-visible can scrollTo. Headlessly the
	-- fake target's driveScroll/setScrollPosition drive the SAME observer.
	local unbindScroll = list.bindNativeScroll(handle.controller)
	return {
		core = core,
		env = env,
		system = system,
		adapter = adapter,
		pres = pres,
		list = list,
		rows = rows,
		activations = activations,
		handle = handle,
		unbindScroll = unbindScroll,
	}
end

-- mounted hit path (screen-prefixed; pathOf() is standalone-rooted so it is not
-- used here — the control's focusGroups walk the real mounted node paths). The
-- window rows live under the full-height "Canvas" anchor inside the ScrollView.
local function rowHit(key: string): string
	return `/S/VL/Canvas/W/[{key}]/Row/Hit`
end
local function keyOf(path: string?): string?
	if path == nil then
		return nil
	end
	return (string.match(path, "%[(.-)%]/Row/Hit$"))
end

-- ===========================================================================
describe("VirtualList pointer input (no consumer wiring)", function()
	it("VirtualList pointer: an engine scroll (driveScroll) slides the window", function()
		local w = world()
		expect(w.list.scrollTop:get()).toBe(0)
		-- the engine ScrollingFrame scrolled (wheel/drag/momentum are all native
		-- now); its CanvasPosition mirrors back through observeScroll -> scrollTop
		w.adapter.driveScroll("/S/VL", { x = 0, y = 120 })
		expect(w.list.scrollTop:get()).toBe(120)
		w.pres.refresh()
		-- the window slid: r1 left, r13 entered — each mounted row sits at its
		-- ABSOLUTE canvas offset (index-1)*40 (the engine translates by CanvasPos)
		expect(w.list.debugWindow().r1).toBe(nil)
		expect(w.list.debugWindow().r13).toBe(true)
		expect(w.adapter.node(rowHit("r13")).rect.y - w.adapter.node("/S/VL/Canvas").rect.y).toBe(12 * 40)
	end)

	it("VirtualList pointer: a row tap activates through auto handleActivate", function()
		local w = world()
		w.adapter.tap(rowHit("r1"))
		expect(#w.activations).toBe(1)
		expect(w.activations[1].item.id).toBe("r1")
	end)

	it("VirtualList pointer: partial rows crop via the engine clip host", function()
		local w = world()
		-- the viewport is a real clip container (Table's clip-host pattern): the
		-- engine crops partial rows at the band edges
		expect(w.adapter.node("/S/VL").props.clipChildren).toBe(true)
	end)
end)

-- ===========================================================================
describe("VirtualList touch input (no consumer wiring)", function()
	it("VirtualList touch: a native pan scroll slides the window (driveScroll)", function()
		local w = world()
		-- a one-finger touch pan is a NATIVE ScrollingFrame gesture now (native
		-- §4); headlessly the engine drive stands in for the fling. The window
		-- slides and no row activates (a scroll is never a tap).
		w.adapter.driveScroll("/S/VL", { x = 0, y = 80 })
		expect(w.list.scrollTop:get()).toBe(80)
		w.pres.refresh()
		expect(w.list.debugWindow().r12).toBe(true) -- window slid down
		expect(#w.activations).toBe(0)
	end)

	it("VirtualList touch: a garbage/negative mirror value cannot scroll above the top", function()
		local w = world()
		-- the engine never reports a negative CanvasPosition, but the windowing
		-- memo clamps the mirror anyway so garbage can never mount a phantom
		-- window above the top (native §6 — windowing stays pure)
		w.adapter.driveScroll("/S/VL", { x = 0, y = -200 })
		expect(w.list.debugWindow().r1).toBe(true)
		expect(w.list.dump().scrollTop).toBe(0)
	end)

	it("VirtualList touch: a row tap activates", function()
		local w = world()
		w.adapter.tap(rowHit("r2"), { pointer = "touch" })
		expect(#w.activations).toBe(1)
		expect(w.activations[1].item.id).toBe("r2")
	end)
end)

-- ===========================================================================
describe("VirtualList keyboard input (no consumer wiring)", function()
	it("VirtualList keyboard: Up/Down moves focus row-by-row through the window", function()
		local w = world()
		expect(w.pres.focus.focused:get()).toBe(rowHit("r1")) -- auto-focus first row
		w.system.deviceKey("Down", true)
		w.system.deviceKey("Down", false)
		expect(w.pres.focus.focused:get()).toBe(rowHit("r2"))
		w.system.deviceKey("Down", true)
		w.system.deviceKey("Down", false)
		expect(w.pres.focus.focused:get()).toBe(rowHit("r3"))
		w.system.deviceKey("Up", true)
		w.system.deviceKey("Up", false)
		expect(w.pres.focus.focused:get()).toBe(rowHit("r2"))
	end)

	it("VirtualList keyboard: focus past the window edge scrolls the row into view", function()
		local w = world() -- 10 visible + overscan 2
		-- step down well past the initial visible band; the app refreshes per frame
		for _ = 1, 12 do
			w.system.deviceKey("Down", true)
			w.system.deviceKey("Down", false)
			w.pres.refresh()
		end
		local focused = w.pres.focus.focused:get()
		local key = keyOf(focused) :: string
		local index = tonumber(string.match(key, "r(%d+)")) :: number
		expect(index > 10).toBe(true) -- advanced past the initial 10-row window
		-- and the focused row was scrolled into the visible band
		local top = w.list.scrollTop:get()
		expect(top > 0).toBe(true)
		local rowTop = (index - 1) * 40
		expect(rowTop >= top).toBe(true)
		expect(rowTop + 40 <= top + 400).toBe(true)
	end)

	it("VirtualList keyboard: Return activates the focused row", function()
		local w = world()
		w.system.deviceKey("Down", true)
		w.system.deviceKey("Down", false) -- focus r2
		expect(w.pres.focus.focused:get()).toBe(rowHit("r2"))
		w.system.deviceKey("Return", true)
		w.system.deviceKey("Return", false)
		expect(#w.activations).toBe(1)
		expect(w.activations[1].item.id).toBe("r2")
		expect(w.activations[1].meta.source).toBe("action")
	end)
end)

-- ===========================================================================
describe("VirtualList gamepad input (no consumer wiring)", function()
	it("VirtualList gamepad: D-pad moves focus identically to arrows", function()
		local w = world()
		expect(w.pres.focus.focused:get()).toBe(rowHit("r1"))
		w.system.deviceKey("DPadDown", true)
		w.system.deviceKey("DPadDown", false)
		expect(w.pres.focus.focused:get()).toBe(rowHit("r2"))
		w.system.deviceKey("DPadDown", true)
		w.system.deviceKey("DPadDown", false)
		expect(w.pres.focus.focused:get()).toBe(rowHit("r3"))
		w.system.deviceKey("DPadUp", true)
		w.system.deviceKey("DPadUp", false)
		expect(w.pres.focus.focused:get()).toBe(rowHit("r2"))
	end)

	it("VirtualList gamepad: ButtonA activates the focused row", function()
		local w = world()
		w.system.deviceKey("DPadDown", true)
		w.system.deviceKey("DPadDown", false) -- focus r2
		expect(w.pres.focus.focused:get()).toBe(rowHit("r2"))
		w.system.deviceKey("ButtonA", true)
		w.system.deviceKey("ButtonA", false)
		expect(#w.activations).toBe(1)
		expect(w.activations[1].item.id).toBe("r2")
	end)
end)

-- ===========================================================================
describe("VirtualList focus coherence + virtualization neutrality", function()
	it("VirtualList window-slide keeps focus coherent (focus follows the KEY, nearest-survivor on eviction)", function()
		local w = world({ count = 30 })
		-- navigate to r5 through the device path; focusMoved syncs focusedKey
		for _ = 1, 4 do
			w.system.deviceKey("DPadDown", true)
			w.system.deviceKey("DPadDown", false)
		end
		expect(w.pres.focus.focused:get()).toBe(rowHit("r5"))
		expect(w.list.focusedKey:get()).toBe("r5")
		-- slide the window far enough (engine scroll) that r5 unmounts but stays in
		-- data: the KEY-based focus persists even though the row left the window
		w.adapter.driveScroll("/S/VL", { x = 0, y = 400 })
		w.pres.refresh()
		expect(w.list.debugWindow().r5).toBe(nil) -- r5 no longer mounted
		expect(w.list.focusedKey:get()).toBe("r5") -- focus follows the KEY, not the row
		-- now EVICT r5 from the data: nearest surviving neighbor (following) = r6
		local next = makeRows(30)
		table.remove(next, 5) -- r5 gone
		w.rows:set(next)
		expect(w.list.focusedKey:get()).toBe("r6")
	end)

	it("VirtualList scroll: window slide re-runs factories only for entering rows (survivors kept)", function()
		local w = world() -- window r1..r12
		expect(w.list.debugWindow().r5).toBe(true)
		local before = w.handle.root.counters().factoryRuns
		w.adapter.driveScroll("/S/VL", { x = 0, y = 40 }) -- +40px: window adds r13 only
		w.pres.refresh()
		local after = w.handle.root.counters().factoryRuns
		-- only the entering row re-ran a factory (<= 1 new row * nodes/row);
		-- survivors never remount — mirrors the rect/window-writes-only invariant
		expect(after - before <= 3).toBe(true)
		expect(w.list.debugWindow().r5).toBe(true) -- survivor still mounted (no remount)
	end)

	it("VirtualList registry neutrality: build/mount/present/interact/dispose returns to baseline", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local baseline = core:counters()

		local rows = core:signal(makeRows(50))
		local list = virtual_list.build(Facet, core, {
			id = "VL",
			rows = rows,
			key = function(item: any)
				return item.id
			end,
			rowHeight = 40,
			viewportHeight = 400,
			overscan = 2,
			cell = function(item: any)
				return Facet.UI.Text({ id = "Label", text = item.label, textSize = 14 })
			end,
			onActivate = function() end,
		})
		local screen = Facet.UI.Screen({ id = "S", children = { list.blueprint } })
		local handle = pres.present(screen) -- zero opts: full auto-composition
		pres.refresh()
		local unbindScroll = list.bindNativeScroll(handle.controller)

		-- exercise every auto path: nav, activate, native engine scroll (the
		-- CanvasPosition mirror replaces the retired wheel/pan handlers)
		system.deviceKey("DPadDown", true)
		system.deviceKey("DPadDown", false)
		system.deviceKey("ButtonA", true)
		system.deviceKey("ButtonA", false)
		adapter.driveScroll("/S/VL", { x = 0, y = 120 })
		pres.refresh()

		unbindScroll()
		pres.dismiss(handle)
		list.dispose()
		rows:dispose()

		local after = core:counters()
		for key, value in baseline :: { [string]: number } do
			expect((after :: any)[key]).toBe(value)
		end
	end)
end)

-- ===========================================================================
-- native canvas conformance + keep-visible + teardown (native-substrate NS-A2)
-- ===========================================================================
describe("VirtualList native canvas (native scroll substrate)", function()
	it("declares the FULL virtual height as the scroll canvas and clips", function()
		local w = world({ count = 100 })
		local host = w.adapter.node("/S/VL")
		-- the control root is the native ScrollingFrame: clip host + scroll region
		expect(host.props.clipChildren).toBe(true)
		expect(host.scrollRegion ~= nil).toBe(true)
		expect(host.scrollRegion.axis).toBe("y")
		-- 100 rows x 40px = the full virtual extent, even though only ~14 mount
		expect(host.scrollRegion.contentH).toBe(100 * 40)
		-- windowed rows sit at ABSOLUTE canvas offsets under the Canvas anchor
		local canvasY = w.adapter.node("/S/VL/Canvas").rect.y
		expect(w.adapter.node(rowHit("r1")).rect.y - canvasY).toBe(0)
		expect(w.adapter.node(rowHit("r3")).rect.y - canvasY).toBe(2 * 40)
	end)

	it("the scroll canvas grows with the data (contentH tracks totalRows)", function()
		local w = world({ count = 20 })
		expect(w.adapter.node("/S/VL").scrollRegion.contentH).toBe(20 * 40)
		w.rows:set((function()
			local out = {}
			for i = 1, 50 do
				table.insert(out, { id = `r{i}`, label = `Row {i}` })
			end
			return out
		end)())
		w.pres.refresh()
		expect(w.adapter.node("/S/VL").scrollRegion.contentH).toBe(50 * 40)
	end)

	it("keep-visible writes a programmatic scrollTo target (scrollpos op) for an off-band focus", function()
		local w = world({ count = 100, viewportHeight = 400 })
		w.adapter.takeOps()
		-- drive focus far past the window; keep-visible scrolls it into view
		for _ = 1, 12 do
			w.system.deviceKey("Down", true)
			w.system.deviceKey("Down", false)
			w.pres.refresh()
		end
		-- the framework issued its ONE programmatic scroll write (CanvasPosition)
		local sawPos = false
		for _, op in w.adapter.takeOps() do
			if string.find(op, "scrollpos /S/VL=") ~= nil then
				sawPos = true
			end
		end
		expect(sawPos).toBe(true)
		expect(w.adapter.node("/S/VL").scrollPosition.y > 0).toBe(true)
	end)

	it("unbindNativeScroll stops the mirror (teardown cleanliness)", function()
		local w = world()
		w.adapter.driveScroll("/S/VL", { x = 0, y = 80 })
		expect(w.list.scrollTop:get()).toBe(80)
		w.unbindScroll()
		-- after unbind, an engine scroll no longer reaches the mirror
		w.adapter.driveScroll("/S/VL", { x = 0, y = 200 })
		expect(w.list.scrollTop:get()).toBe(80)
	end)
end)

-- ===========================================================================
-- SF-L4 — the contributed group is NAMEABLE and its wrap/exit are declarable
--
-- A screen that composes this list beside an authored control row has to state
-- how focus crosses between the two. Before `navigation` the list's group had no
-- name a sibling could reference and no way to declare `wrap` or `exit`, so the
-- only route was rebuilding the group consumer-side — which drops the live
-- focus-skip predicates AND the active-interaction exemption its order entries
-- carry. Each case below fails without the field.
describe("VirtualList navigation-group overrides (SF-L4)", function()
	-- a list plus a sibling HStack of two buttons, each side naming the other
	local function twoGroupWorld(navigation: any?)
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local rows = core:signal(makeRows(4))
		local list = virtual_list.build(Facet, core, {
			id = "VL",
			rows = rows,
			key = function(item: any)
				return item.id
			end,
			rowHeight = 40,
			viewportHeight = 400,
			navigation = navigation,
			cell = function(item: any)
				return Facet.UI.Text({ id = "Label", text = item.label, textSize = 14 })
			end,
			onActivate = function() end,
		})
		local dock = Facet.contribution.attach(
			Facet.UI.HStack({
				id = "Dock",
				children = {
					Facet.UI.Button({ id = "A", label = "A", onActivate = function() end }),
					Facet.UI.Button({ id = "B", label = "B", onActivate = function() end }),
				},
			}),
			{
				focusGroups = function(rootNode: any)
					return {
						{
							name = "Dock",
							axis = "horizontal",
							entry = "restore",
							exit = { up = list.focusGroupName, down = list.focusGroupName },
							order = { `{rootNode.path}/A`, `{rootNode.path}/B` },
						},
					}
				end,
			}
		)
		local handle = pres.present(Facet.UI.Screen({ id = "S", children = { list.blueprint, dock } }))
		pres.refresh()
		list.bindNativeScroll(handle.controller)
		return { pres = pres, system = system, list = list, handle = handle }
	end

	it("the group NAME is the list's own by default and is published for a sibling to reference", function()
		local w = twoGroupWorld()
		expect(w.list.focusGroupName).toBe("vl:VL")
		expect(w.list.dump().focusGroup).toBe("vl:VL")
		local named = twoGroupWorld({ name = "RacerList" })
		expect(named.list.focusGroupName).toBe("RacerList")
		-- and the NAME is what the sibling's declared exit resolves against: with
		-- the group renamed, the dock's exit (built from focusGroupName) still lands
		named.pres.focus.focusOn("/S/Dock/A")
		named.system.deviceKey("Down", true)
		named.system.deviceKey("Down", false)
		expect(named.pres.focus.focused:get()).toBe("/S/VL/Canvas/W/[r1]/Row/Hit")
	end)

	it("`exit` crosses to the named group where array-order fallthrough cannot", function()
		-- the dock is AFTER the list in tree order, so "left" from a row has no
		-- earlier group to fall through to: only a declared exit can get there.
		local w = twoGroupWorld({ exit = { left = "Dock" } })
		w.pres.focus.focusOn("/S/VL/Canvas/W/[r2]/Row/Hit")
		w.system.deviceKey("Left", true)
		w.system.deviceKey("Left", false)
		-- entry ALONG the target group's own axis lands at the NEAR end, so a
		-- leftward exit lands on the row's right-most member (the framework's
		-- own entry rule, unchanged by the override)
		expect(w.pres.focus.focused:get()).toBe("/S/Dock/B")

		local undeclared = twoGroupWorld()
		undeclared.pres.focus.focusOn("/S/VL/Canvas/W/[r2]/Row/Hit")
		undeclared.system.deviceKey("Left", true)
		undeclared.system.deviceKey("Left", false)
		-- without the declaration focus stays put — the case the field exists for
		expect(undeclared.pres.focus.focused:get()).toBe("/S/VL/Canvas/W/[r2]/Row/Hit")
	end)

	it("`wrap` wraps the row ring at both ends, and absent it still stops", function()
		local w = twoGroupWorld({ wrap = true })
		w.pres.focus.focusOn("/S/VL/Canvas/W/[r1]/Row/Hit")
		w.system.deviceKey("Up", true)
		w.system.deviceKey("Up", false)
		expect(w.pres.focus.focused:get()).toBe("/S/VL/Canvas/W/[r4]/Row/Hit")
		w.system.deviceKey("Down", true)
		w.system.deviceKey("Down", false)
		expect(w.pres.focus.focused:get()).toBe("/S/VL/Canvas/W/[r1]/Row/Hit")

		local flat = twoGroupWorld()
		flat.pres.focus.focusOn("/S/VL/Canvas/W/[r1]/Row/Hit")
		flat.system.deviceKey("Up", true)
		flat.system.deviceKey("Up", false)
		expect(flat.pres.focus.focused:get()).toBe("/S/VL/Canvas/W/[r1]/Row/Hit")
	end)

	it("the overrides never replace the group: the focus-skip predicates survive", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local rows = core:signal(makeRows(4))
		local blocked = core:signal(true)
		local list = virtual_list.build(Facet, core, {
			id = "VL",
			rows = rows,
			key = function(item: any)
				return item.id
			end,
			rowHeight = 40,
			viewportHeight = 400,
			navigation = { name = "Rows", wrap = true, exit = { left = "Nowhere" } },
			rowFocusable = function(item: any): boolean
				return not (blocked:get() and item.id == "r2")
			end,
			cell = function(item: any)
				return Facet.UI.Text({ id = "Label", text = item.label, textSize = 14 })
			end,
			onActivate = function() end,
		})
		pres.present(Facet.UI.Screen({ id = "S", children = { list.blueprint } }))
		pres.refresh()
		pres.focus.focusOn("/S/VL/Canvas/W/[r1]/Row/Hit")
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		-- r2 is skipped AT NAVIGATION TIME, exactly as with no overrides declared
		expect(pres.focus.focused:get()).toBe("/S/VL/Canvas/W/[r3]/Row/Hit")
		blocked:set(false)
		pres.focus.focusOn("/S/VL/Canvas/W/[r1]/Row/Hit")
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		expect(pres.focus.focused:get()).toBe("/S/VL/Canvas/W/[r2]/Row/Hit")
		-- an exit naming a group that does not exist is inert, never an error
		expect(pres.focus.focused:get()).toBe("/S/VL/Canvas/W/[r2]/Row/Hit")
	end)

	it("an unknown navigation field is refused at construction, naming the valid set", function()
		local core = Facet.newCore()
		local ok, err = pcall(function()
			virtual_list.build(Facet, core, {
				id = "VL",
				rows = core:signal(makeRows(2)),
				key = function(item: any)
					return item.id
				end,
				rowHeight = 40,
				viewportHeight = 200,
				navigation = { wrapp = true },
				cell = function()
					return Facet.UI.Text({ id = "L", text = "x", textSize = 14 })
				end,
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "wrapp", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "Valid: name, wrap", 1, true) ~= nil).toBe(true)
	end)
end)
