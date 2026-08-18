-- TEMPORARY probe (redteam NEW-2, 2026-08-13): does a swipe that ends WITHOUT
-- an Activated leave `suppressActivatePath` armed, so the NEXT device Activate
-- (gamepad A / keyboard Return — no pointer-down at all) is swallowed?
--
-- Runs unchanged on 13fd3c6 (pre-fix) and a6229e0+ (post-fix): it uses only
-- pointerDown/pointerMove/pointerUp/interruptCapture, never the
-- `pointerUpActivating` that post-dates 13fd3c6.
local Facet = require("../../src") :: any
local table_control = require("../../src/controls/table")
local fake_target = require("../../tests/lib/fake_target")

local RACERS = {
	{ id = "razz", name = "Razz Raccoon" },
	{ id = "bolt", name = "Bolt Badger" },
	{ id = "josh", name = "Josh Jackal" },
}

local function hitPath(key: string): string
	return `/S/T/Main/Body/Rows/[{key}@0]/RowActions-{key}/Content/Row/Hit`
end
local function trayPath(key: string, action: string): string
	return `/S/T/Main/Body/Rows/[{key}@0]/RowActions-{key}/TrayTrailingWhen/then/TrayTrailing/Action:{action}`
end

local function makeWorld()
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	env:set("preferredInput", "Gamepad")
	env:set("capabilities", { keyboard = true, mouse = false, touch = false, gamepad = true })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local clock = { t = 100 }
	local pres = Facet.newPresenter(core, env, adapter, system, {
		now = function()
			return clock.t
		end,
	})
	local opened: { string } = {}
	local fired: { string } = {}
	local tbl = table_control.build(
		Facet,
		core,
		{
			id = "T",
			rows = core:signal(RACERS),
			key = function(r: any)
				return r.id
			end,
			columns = {
				{
					id = "name",
					title = "Racer",
					width = { type = "fill", weight = 1 },
					value = function(r: any)
						return r.name
					end,
				},
			},
			selection = "single",
			rowHeight = 40,
			env = env,
			onPrimaryAction = function(_item: any, key: string)
				table.insert(opened, key)
			end,
			rowActions = function(_item: any): any
				return {
					trailing = {
						{
							id = "delete",
							role = "destructive",
							label = "Delete",
							onAction = function()
								table.insert(fired, "delete")
							end,
						},
					},
				}
			end,
		} :: any
	)
	local handle = pres.present(Facet.UI.Screen({ id = "S", children = { tbl.blueprint } }))
	pres.refresh()
	local w: any = {
		core = core,
		adapter = adapter,
		pres = pres,
		system = system,
		tbl = tbl,
		handle = handle,
		opened = opened,
		fired = fired,
	}
	function w.tick(dt: number)
		clock.t += dt
		pres.tick(dt)
		pres.refresh()
	end
	function w.settle(frames: number?)
		for _ = 1, frames or 120 do
			w.tick(1 / 60)
		end
	end
	-- a horizontal swipe on `key`'s hit, LEFT past the axis lock; `finish` is
	-- how the gesture ends: "silent" = a plain pointerUp that produces no
	-- Activated (the up landed off the translated Hit), "cancel" = the capture
	-- lost mid-gesture (the Roblox menu opened, the row unmounted, a scroll stole it)
	function w.swipe(key: string, finish: string)
		local rect = w.adapter.node(hitPath(key)).rect
		local originX = rect.x + rect.w - 8
		local y = rect.y + rect.h / 2
		w.adapter.pointerDown(hitPath(key), originX, y, "touch")
		w.tick(1 / 60)
		for i = 1, 8 do
			w.adapter.pointerMove(originX - (rect.w * 0.3) * (i / 8), y, "touch")
			w.tick(1 / 60)
		end
		if finish == "cancel" then
			w.adapter.interruptCapture()
		else
			w.adapter.pointerUp(originX - rect.w * 0.3, y)
		end
		w.settle(150)
	end
	-- an IAS DEVICE Activate on the focused row: gamepad A, through the real
	-- action system, meta.source == "action" and NO pointer event whatsoever
	function w.deviceActivate(key: string)
		w.pres.focus.focusOn(hitPath(key))
		w.pres.refresh()
		w.system.deviceKey("ButtonA", true)
		w.system.deviceKey("ButtonA", false)
		w.pres.refresh()
		w.settle(60)
	end
	return w
end

print("=== NEW-2: a swipe that ends with no Activated leaves the suppression armed ===")

-- A. a swipe CANCELLED mid-gesture, then a gamepad A on that row
do
	local w = makeWorld()
	w.swipe("razz", "cancel")
	local before = #w.opened
	w.deviceActivate("razz")
	print(
		string.format(
			"A  swipe CANCELLED mid-gesture, then gamepad A   onPrimaryAction fired %d -> %d   %s",
			before,
			#w.opened,
			if #w.opened > before then "ok" else "FAIL (the device press was eaten)"
		)
	)
end

-- B. a swipe with a SILENT release (tray open), then a gamepad A on the open row
do
	local w = makeWorld()
	w.swipe("razz", "silent")
	local trayOpen = w.adapter.node(trayPath("razz", "delete")) ~= nil
	w.deviceActivate("razz")
	local stillOpen = w.adapter.node(trayPath("razz", "delete")) ~= nil
	print(
		string.format(
			"B  swipe SILENT release (tray=%s), then gamepad A  tray after = %s   %s",
			tostring(trayOpen),
			if stillOpen then "STILL OPEN" else "closed",
			if trayOpen and not stillOpen then "ok" else "FAIL (the close verb was eaten)"
		)
	)
end

-- CONTROL. the same device press after a swipe whose release DID carry an
-- Activate — the arm is cleared by the Activate it swallows, so this one lands
do
	local w = makeWorld()
	local rect = w.adapter.node(hitPath("razz")).rect
	local originX = rect.x + rect.w - 8
	local y = rect.y + rect.h / 2
	w.adapter.pointerDown(hitPath("razz"), originX, y, "touch")
	w.tick(1 / 60)
	for i = 1, 8 do
		w.adapter.pointerMove(originX - (rect.w * 0.3) * (i / 8), y, "touch")
		w.tick(1 / 60)
	end
	if (w.adapter :: any).pointerUpActivating ~= nil then
		(w.adapter :: any).pointerUpActivating(originX - rect.w * 0.3, y, "after")
	else
		-- 13fd3c6 has no pointerUpActivating: synthesize the same two events
		w.adapter.pointerUp(originX - rect.w * 0.3, y)
		w.adapter.driveActivate(hitPath("razz"), { source = "pointer", pointer = "touch" })
	end
	w.settle(150)
	local trayOpen = w.adapter.node(trayPath("razz", "delete")) ~= nil
	w.deviceActivate("razz")
	local stillOpen = w.adapter.node(trayPath("razz", "delete")) ~= nil
	print(
		string.format(
			"C  CONTROL: release DID Activate (tray=%s), then gamepad A  tray after = %s   %s",
			tostring(trayOpen),
			if stillOpen then "STILL OPEN" else "closed",
			if trayOpen and not stillOpen then "ok" else "FAIL"
		)
	)
end
