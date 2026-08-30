--!strict
--[[ VirtualGrid four-input story (ui_todo §0; matrix §1c).

	Proves the presenter AUTO-COMPOSES the lazy grid's pointer / touch / keyboard /
	gamepad interaction from the input-contribution bundle the control attaches to
	its root, with NO consumer `present()` wiring. Every interaction goes through
	the REAL device paths (`adapter.driveScroll` / `adapter.tap` for pointer and
	touch, `system.deviceKey` for keyboard and gamepad), never a direct api call.

	THE STRUCTURAL CLAIM THIS FILE EXISTS FOR, and it is a grid's own: **DOWN MOVES
	A WHOLE LINE, NOT ONE CELL.** The focus graph has no two-dimensional group axis,
	so the mounted cells are one `horizontal` group (±1 in row-major document order
	IS the cell to the left or right) and the second axis arrives through the
	`navigateIntercept` seam. Emitting the group as `vertical` instead would have
	made Down walk visually RIGHTWARD — reachable, and wrong in shape, which is
	exactly the difference between the reachability axis and the paradigm axis.

	`tests/virtual_grid.spec.luau` proves the LAYOUT and the LAZINESS; this file
	does not repeat either.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local virtual_grid = require("../src/controls/virtual_grid")
local fake_target = require("../tests/lib/fake_target")

local function makeItems(n: number): { { id: string, label: string } }
	local items = table.create(n)
	for i = 1, n do
		items[i] = { id = `i{i}`, label = `Item {i}` }
	end
	return items
end

-- a VirtualGrid inside a Screen, presented with ZERO opts (full auto-composition).
-- 4 lanes x 40px lines in a 400px viewport = 10 visible lines, overscan 2.
local function world(opts: any?)
	local options = opts or {}
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = Facet.newPresenter(core, env, adapter, system)
	local items = core:signal(makeItems(options.count or 400))
	local activations: { any } = {}
	local grid = virtual_grid.build(Facet, core, {
		id = "VG",
		items = items,
		key = function(item: any)
			return item.id
		end,
		columns = options.columns or 4,
		itemExtent = 40,
		viewportExtent = options.viewportExtent or 400,
		overscan = options.overscan or 2,
		width = { type = "fixed", px = 320 },
		cell = function(item: any)
			return Facet.UI.Text({ id = "Label", text = item.label, textSize = 14 })
		end,
		onActivate = function(item: any, meta: any)
			table.insert(activations, { item = item, meta = meta })
		end,
	})
	local screen = Facet.UI.Screen({ id = "S", padding = 0, gap = 0, children = { grid.blueprint } })
	local handle = pres.present(screen) -- ZERO present opts
	pres.refresh()
	local unbindScroll = grid.bindNativeScroll(handle.controller)
	return {
		core = core,
		system = system,
		adapter = adapter,
		pres = pres,
		grid = grid,
		items = items,
		activations = activations,
		handle = handle,
		unbindScroll = unbindScroll,
	}
end

local function cellHit(key: string): string
	return `/S/VG/Canvas/Band/W/[{key}]/Cell/Hit`
end

-- ===========================================================================
describe("VirtualGrid pointer input (no consumer wiring)", function()
	it("VirtualGrid pointer: an engine scroll (driveScroll) slides the window", function()
		local w = world()
		expect(w.grid.scrollTop:get()).toBe(0)
		-- the engine ScrollingFrame scrolled — wheel, drag and momentum are all
		-- native; its CanvasPosition mirrors back through observeScroll -> scrollTop
		w.adapter.driveScroll("/S/VG", { x = 0, y = 400 })
		expect(w.grid.scrollTop:get()).toBe(400)
		w.pres.refresh()
		-- ten lines down: line 1's cells left, line 11's arrived
		expect(w.grid.debugWindow().i1).toBe(nil)
		expect(w.grid.debugWindow().i41).toBe(true)
		-- and the mounted cell sits at its ABSOLUTE canvas offset — the engine
		-- translates the whole canvas by CanvasPosition, the framework never does
		expect(w.adapter.node(cellHit("i41")).rect.y - w.adapter.node("/S/VG/Canvas").rect.y).toBe(10 * 40)
	end)

	it("VirtualGrid pointer: a cell tap activates through auto handleActivate", function()
		local w = world()
		w.adapter.tap(cellHit("i7"))
		expect(#w.activations).toBe(1)
		expect(w.activations[1].item.id).toBe("i7")
	end)

	it("VirtualGrid pointer: partial lines crop via the engine clip host", function()
		local w = world()
		expect(w.adapter.node("/S/VG").props.clipChildren).toBe(true)
	end)
end)

-- ===========================================================================
describe("VirtualGrid touch input (no consumer wiring)", function()
	it("VirtualGrid touch: a native pan scroll slides the window and never activates a cell", function()
		local w = world()
		-- a one-finger pan is a NATIVE ScrollingFrame gesture; headlessly the engine
		-- drive stands in for the fling. A scroll is never a tap.
		w.adapter.driveScroll("/S/VG", { x = 0, y = 200 })
		expect(w.grid.scrollTop:get()).toBe(200)
		w.pres.refresh()
		expect(w.grid.debugWindow().i25).toBe(true)
		expect(#w.activations).toBe(0)
	end)

	it("VirtualGrid touch: a cell tap activates", function()
		local w = world()
		w.adapter.tap(cellHit("i3"), { pointer = "touch" })
		expect(#w.activations).toBe(1)
		expect(w.activations[1].item.id).toBe("i3")
	end)

	it("VirtualGrid touch: a garbage mirror value cannot mount a window above the top", function()
		local w = world()
		w.adapter.driveScroll("/S/VG", { x = 0, y = -300 })
		expect(w.grid.debugWindow().i1).toBe(true)
		expect(w.grid.dump().scrollTop).toBe(0)
	end)
end)

-- ===========================================================================
describe("VirtualGrid keyboard input (no consumer wiring)", function()
	it("VirtualGrid keyboard: Left/Right steps cell-by-cell ACROSS a line", function()
		local w = world()
		expect(w.pres.focus.focused:get()).toBe(cellHit("i1")) -- auto-focus first cell
		w.system.deviceKey("Right", true)
		w.system.deviceKey("Right", false)
		expect(w.pres.focus.focused:get()).toBe(cellHit("i2"))
		w.system.deviceKey("Right", true)
		w.system.deviceKey("Right", false)
		expect(w.pres.focus.focused:get()).toBe(cellHit("i3"))
		w.system.deviceKey("Left", true)
		w.system.deviceKey("Left", false)
		expect(w.pres.focus.focused:get()).toBe(cellHit("i2"))
	end)

	it("VirtualGrid keyboard: Down moves a whole LINE, not one cell", function()
		--[[ THE STRUCTURAL IDIOM OF A GRID RING, and the case that separates this
			control from a list wearing four columns. The group's order is row-major,
			so ±1 is a sideways step; Down has to be ±lanes or the ring walks
			visually rightward while the player presses down. ]]
		local w = world()
		expect(w.pres.focus.focused:get()).toBe(cellHit("i1"))
		w.system.deviceKey("Down", true)
		w.system.deviceKey("Down", false)
		expect(w.pres.focus.focused:get()).toBe(cellHit("i5")) -- NOT i2
		w.system.deviceKey("Down", true)
		w.system.deviceKey("Down", false)
		expect(w.pres.focus.focused:get()).toBe(cellHit("i9"))
		w.system.deviceKey("Up", true)
		w.system.deviceKey("Up", false)
		expect(w.pres.focus.focused:get()).toBe(cellHit("i5"))
	end)

	it("VirtualGrid keyboard: focus past the window edge scrolls the line into view", function()
		local w = world() -- 10 visible lines + overscan 2
		for _ = 1, 14 do
			w.system.deviceKey("Down", true)
			w.system.deviceKey("Down", false)
			w.pres.refresh()
		end
		local focused = w.pres.focus.focused:get() :: string
		local key = string.match(focused, "%[(.-)%]/Cell/Hit$") :: string
		local index = tonumber(string.match(key, "i(%d+)")) :: number
		expect(index).toBe(1 + 14 * 4) -- fourteen whole lines down
		-- ...and the focused cell's LINE was scrolled into the visible band
		local top = w.grid.scrollTop:get()
		expect(top > 0).toBe(true)
		local lineTop = 14 * 40
		expect(lineTop >= top).toBe(true)
		expect(lineTop + 40 <= top + 400).toBe(true)
	end)

	it("VirtualGrid keyboard: Right off the END of a line scrolls the next line into view", function()
		--[[ FOUND BY MUTATION. Up/Down run through `navigateIntercept`, which does its
			own keep-visible before it lands the ring — so neutering the keep-visible on
			the FOCUS-MOVED seam reddened nothing, and that seam looked proven when it
			was merely shadowed. Left/Right are the group's own axis and never reach the
			intercept at all: they walk row-major, so stepping Right off the end of a
			line is how the ring crosses into the next one, and `focusMoved` is the only
			thing that scrolls it. This is that path. ]]
		local w = world() -- 10 visible lines of 4
		for _ = 1, 43 do
			w.system.deviceKey("Right", true)
			w.system.deviceKey("Right", false)
			w.pres.refresh()
		end
		expect(w.pres.focus.focused:get()).toBe(cellHit("i44")) -- line 11, past the first ten
		local top = w.grid.scrollTop:get()
		expect(top > 0).toBe(true)
		local lineTop = 10 * 40
		expect(lineTop >= top).toBe(true)
		expect(lineTop + 40 <= top + 400).toBe(true)
	end)

	it("VirtualGrid keyboard: the focus dump REPORTS the second axis", function()
		--[[ The whole chain in one assertion: the control declares `columns` beside
			the order it describes, `focus_map.autoGroups` splices the group in whole,
			the graph reads it as a rectangle, and `handle.focusOrder()` reports it.
			It is in the dump because the order cannot show it — these sixteen paths
			are the same sixteen paths whether they are a 4-lane grid or one very long
			row, and "which one is this" is exactly the question the dump exists to
			answer without pressing a key sixteen times. ]]
		local w = world()
		local group
		for _, g in w.handle.focusOrder().navigation do
			if string.find(g.name, "VirtualGridCells", 1, true) ~= nil then
				group = g
			end
		end
		expect(group ~= nil).toBe(true)
		expect(group.axis).toBe("horizontal") -- the LANE axis
		expect(group.columns).toBe(4) -- ...and where its lines break
		-- the null half: an ordinary group in the same dump claims no second axis
		for _, g in w.handle.focusOrder().navigation do
			if string.find(g.name, "VirtualGridCells", 1, true) == nil then
				expect(g.columns).toBe(nil)
			end
		end
	end)

	it("VirtualGrid keyboard: Return activates the focused cell", function()
		local w = world()
		w.system.deviceKey("Down", true)
		w.system.deviceKey("Down", false) -- focus i5
		expect(w.pres.focus.focused:get()).toBe(cellHit("i5"))
		w.system.deviceKey("Return", true)
		w.system.deviceKey("Return", false)
		expect(#w.activations).toBe(1)
		expect(w.activations[1].item.id).toBe("i5")
		expect(w.activations[1].meta.source).toBe("action")
	end)
end)

-- ===========================================================================
describe("VirtualGrid gamepad input (no consumer wiring)", function()
	it("VirtualGrid gamepad: DPadRight steps a cell and DPadDown steps a whole line", function()
		local w = world()
		expect(w.pres.focus.focused:get()).toBe(cellHit("i1"))
		w.system.deviceKey("DPadRight", true)
		w.system.deviceKey("DPadRight", false)
		expect(w.pres.focus.focused:get()).toBe(cellHit("i2"))
		w.system.deviceKey("DPadDown", true)
		w.system.deviceKey("DPadDown", false)
		expect(w.pres.focus.focused:get()).toBe(cellHit("i6"))
		w.system.deviceKey("DPadUp", true)
		w.system.deviceKey("DPadUp", false)
		expect(w.pres.focus.focused:get()).toBe(cellHit("i2"))
	end)

	it("VirtualGrid gamepad: ButtonA activates the focused cell", function()
		local w = world()
		w.system.deviceKey("DPadDown", true)
		w.system.deviceKey("DPadDown", false) -- focus i5
		expect(w.pres.focus.focused:get()).toBe(cellHit("i5"))
		w.system.deviceKey("ButtonA", true)
		w.system.deviceKey("ButtonA", false)
		expect(#w.activations).toBe(1)
		expect(w.activations[1].item.id).toBe("i5")
	end)
end)
