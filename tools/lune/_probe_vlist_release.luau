-- TEMPORARY probe (redteam NEW-1, 2026-08-13): does a HOSTED VirtualList swipe
-- survive its own release Activate? Clean room: newVirtualList + rowActions +
-- onActivate, driven through the real adapter seam. 12 combinations:
-- pointer kind (mouse|touch) x edge (trailing|leading) x release order
-- (none|after|before).
local Facet = require("../../src") :: any
local virtual_list = require("../../src/controls/virtual_list")
local row_actions_state = require("../../src/input/row_actions_state")
local fake_target = require("../../tests/lib/fake_target")

local LOCK = row_actions_state.AXIS_LOCK_PX
local FRAME = 1 / 60

local function rowHit(key: string): string
	return `/S/VL/Canvas/W/[{key}]/Row/Hit`
end
local function tray(key: string, edge: string): string
	local id = if edge == "leading" then "TrayLeading" else "TrayTrailing"
	return `/S/VL/Canvas/RowActionsOverlay/[{key}]/RowActionsTray/{id}When/then/{id}`
end

local function makeWorld()
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local clockTime = 0
	local pres = Facet.newPresenter(core, env, adapter, system, {
		now = function()
			return clockTime
		end,
	})
	local rows = {}
	for i = 1, 20 do
		table.insert(rows, { id = `r{i}`, label = `Row {i}` })
	end
	local activations: { string } = {}
	local fired: { string } = {}
	local list = virtual_list.build(
		Facet,
		core,
		{
			id = "VL",
			rows = core:signal(rows),
			key = function(item: any)
				return item.id
			end,
			rowHeight = 40,
			viewportHeight = 400,
			overscan = 2,
			cell = function(item: any)
				return Facet.UI.Text({ id = "Label", text = item.label, textSize = 14 })
			end,
			onActivate = function(item: any)
				table.insert(activations, item.id)
			end,
			rowActions = function(item: any): any
				return {
					leading = {
						{
							id = "read",
							label = "Read",
							onAction = function()
								table.insert(fired, `read:{item.id}`)
							end,
						},
					},
					trailing = {
						{
							id = "delete",
							label = "Delete",
							onAction = function()
								table.insert(fired, `delete:{item.id}`)
							end,
						},
					},
				}
			end,
			env = env,
		} :: any
	)
	local handle = pres.present(Facet.UI.Screen({ id = "S", children = { list.blueprint } }))
	pres.refresh()
	local unbindScroll = list.bindNativeScroll(handle.controller)

	local w: any = {
		core = core,
		adapter = adapter,
		pres = pres,
		list = list,
		handle = handle,
		activations = activations,
		fired = fired,
	}
	function w.tick(dt: number)
		clockTime += dt
		pres.tick(dt)
		pres.refresh()
	end
	function w.settle(frames: number?)
		for _ = 1, frames or 120 do
			w.tick(FRAME)
		end
	end
	function w.teardown()
		unbindScroll()
		pres.dismiss(handle)
		list.dispose()
	end
	return w
end

--[[ ONE swipe, on a hosted row, released the way the engine really releases:
	`order == nil` is the legacy silent release, "after"/"before" the two sides
	of InputEnded the real GuiButton Activated can land on. ]]
local function swipe(w: any, key: string, edge: string, pointerType: string, order: string?)
	local hit = rowHit(key)
	local rect = w.adapter.node(hit).rect
	local sign = if edge == "leading" then 1 else -1
	local originX = if sign < 0 then rect.x + rect.w - 20 else rect.x + 20
	local y = rect.y + rect.h / 2
	local dx = rect.w * 0.3
	w.adapter.pointerDown(hit, originX, y, pointerType)
	w.tick(FRAME)
	w.adapter.pointerMove(originX + sign * (LOCK + 2), y, pointerType)
	w.tick(FRAME)
	for i = 1, 6 do
		w.adapter.pointerMove(originX + sign * (LOCK + 2 + (dx - LOCK - 2) * (i / 6)), y, pointerType)
		w.tick(FRAME)
	end
	local endX = originX + sign * dx
	if order == nil then
		w.adapter.pointerUp(endX, y)
	else
		w.adapter.pointerUpActivating(endX, y, order :: any)
	end
	w.settle(150)
end

print("=== hosted VirtualList: does a swipe survive its own release Activate? ===")
local red, total = 0, 0
for _, pointerType in { "touch", "mouse" } do
	for _, edge in { "trailing", "leading" } do
		for _, order in { "NONE", "after", "before" } do
			local w = makeWorld()
			swipe(w, "r1", edge, pointerType, if order == "NONE" then nil else order)
			local trayOpen = w.adapter.node(tray("r1", edge)) ~= nil
			local activated = #w.activations
			local engaged = w.list._hostedDebug().engagedKey
			total += 1
			local ok = trayOpen and activated == 0
			if not ok then
				red += 1
			end
			print(
				string.format(
					"vlist %-5s/%-8s/%-5s  tray=%-5s engaged=%-5s onActivateFired=%d  %s",
					pointerType,
					edge,
					order,
					tostring(trayOpen),
					tostring(engaged),
					activated,
					if ok then "ok" else "FAIL"
				)
			)
			w.teardown()
		end
	end
end
print(string.format("=== %d/%d RED ===", red, total))
