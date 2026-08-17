--!strict
--[[ NM-H4a round 3 — WHY THE BAND IS NIL WITH A 120px CORE INSET.

	The plate, on the phone, 2026-08-17 (`a.jpeg`):

	    Paint probe · 734x393 · solve 15
	    13 of 14 rows wanted
	    skipped: Objective
	    NOT RIDING · no platform band · coreTop=120

	`coreTop = 120`, so `bandH = min(120, 393) = 120 > 0` and the band's own height
	gate passes. It is the INTERSECTION that is collapsing.

	`topbarSafeInsets` is stored as EDGE INSETS, and edge insets are relative to the
	viewport they were measured against. `platformChrome` converts back with
	`H - safeI.bottom`. Measure that inset against one viewport height and read it
	against another — which is what an orientation change does when the engine
	updates `Camera.ViewportSize` before `GetInsetArea(TopbarSafeInsets)` — and the
	conversion produces a NEGATIVE edge, the intersection empties, and `band` is nil
	with nothing said.

	Usage: lune run tools/lune/_probe_h4e
]]

local LuauUI = require("../../src") :: any

local function chromeAt(facts: any): any
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	for k, v in facts do
		env:set(k, v)
	end
	return (env:get("platformChrome"):get() :: any)
end

local function show(label: string, facts: any)
	local chrome = chromeAt(facts)
	local band = chrome.band
	print(
		string.format(
			"%-52s band=%s",
			label,
			if band == nil
				then "NIL"
				else string.format("%d,%d %dx%d", band.x, band.y, band.w, band.h)
		)
	)
	return band
end

-- the healthy landscape the repo's own constants describe
local LAND_H = 393
print("== the two encodings, consistent ==")
show("landscape, safe insets measured AT 393 tall", {
	viewportRect = { x = 0, y = 0, w = 734, h = LAND_H },
	coreSafeInsets = { top = 120, right = 0, bottom = 0, left = 0 },
	deviceSafeInsets = { top = 0, right = 59, bottom = 21, left = 59 },
	-- topbar-safe AREA x 164..734, y 0..58 on a 393-tall window, as edge insets
	topbarSafeInsets = { top = 0, bottom = LAND_H - 58, left = 164, right = 0 },
	topbarInset = { x = 164, y = 0, w = 570, h = 58 },
})

print("")
print("== the same frame, with the topbar-safe inset still describing PORTRAIT ==")
--[[ THE ONE THING AN ORIENTATION CHANGE DOES THAT A RESIZE DOES NOT: the engine
	updates `Camera.ViewportSize` and `GetInsetArea` on different frames, so ONE
	`pushViewportFacts` can capture a new viewport beside an inset measured against
	the old one. `env:batch` makes the write atomic; it cannot make the two engine
	reads agree. ]]
local PORT_H = 852
local stale = show("landscape 393 tall, safe insets measured AT 852", {
	viewportRect = { x = 0, y = 0, w = 734, h = LAND_H },
	coreSafeInsets = { top = 120, right = 0, bottom = 0, left = 0 },
	deviceSafeInsets = { top = 0, right = 59, bottom = 21, left = 59 },
	topbarSafeInsets = { top = 0, bottom = PORT_H - 58, left = 164, right = 0 },
	topbarInset = { x = 164, y = 0, w = 570, h = 58 },
})
print(`   H - safeI.bottom = {LAND_H} - {PORT_H - 58} = {LAND_H - (PORT_H - 58)}   <- the clamp goes NEGATIVE`)

print("")
print("== and the horizontal half of the same arithmetic ==")
show("landscape, safe insets measured on a WIDER window", {
	viewportRect = { x = 0, y = 0, w = 734, h = LAND_H },
	coreSafeInsets = { top = 120, right = 0, bottom = 0, left = 0 },
	deviceSafeInsets = { top = 0, right = 59, bottom = 21, left = 59 },
	topbarSafeInsets = { top = 0, bottom = LAND_H - 58, left = 164, right = 300 },
	topbarInset = { x = 164, y = 0, w = 570, h = 58 },
})

print("")
print(`the phone's state is reproduced: {tostring(stale == nil)}`)
