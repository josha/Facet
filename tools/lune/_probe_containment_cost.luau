--!strict
-- I-6: what a per-solve lane-containment finding would COST, measured rather than
-- asserted. ABBA, medians of 5 rounds, one process, one declaration set.
local composition = require("../../src/layout/composition")

local SIZES: { [string]: { w: number, h: number } } = {}
local REGIONS: { any } = {}
local ZONES = { "topLeft", "left", "bottomLeft", "top", "center", "bottom", "topRight", "right", "bottomRight" }
for i, zone in ZONES do
	local id = "R" .. tostring(i)
	SIZES[id] = { w = 80 + i * 7, h = 22 + i * 3 }
	table.insert(REGIONS, { id = id, group = zone, rank = i, forms = 1 })
end
-- a second region in three of the zones, so a group really stacks (the shape the
-- HUD has: health then feed in `bottomLeft`)
for i, zone in { "bottomLeft", "bottomRight", "left" } do
	local id = "S" .. tostring(i)
	SIZES[id] = { w = 120, h = 40 }
	table.insert(REGIONS, { id = id, group = zone, rank = 10 + i, forms = 1 })
end

local CTX = { measure = function(id: string, _f: number, _w: number, _h: number): (number, number)
	local s = SIZES[id]
	return s.w, s.h
end }

local DECL = { groups = composition.HUD_GROUPS, arrangements = { composition.HUD }, regions = REGIONS }

local function ctx(withExclusions: boolean): any
	local c = table.clone(CTX) :: any
	if withExclusions then
		c.exclusions = { { x = 0, y = 0, w = 1716, h = 54 } }
	end
	return c
end

--[[ THE CANDIDATE FINDING, exactly as it would ship: only on a LEGAL, non-fallback
	resolution (the scope the 312-case measurement forces), one compare per mounted
	laned region against a lane rect already in hand. O(#regions), no allocation on
	the common path. ]]
local function scan(r: any): number
	if not r.legal or r.fallback then
		return 0
	end
	local hits = 0
	for _, reg in r.regions do
		if not reg.mounted or reg.dropped or reg.lane == nil or reg.rect == nil then
			continue
		end
		local lane = r.lanes[reg.lane]
		if lane == nil then
			continue
		end
		if
			(reg.rect.y + reg.rect.h) - (lane.rect.y + lane.rect.h) > 0.5
			or lane.rect.y - reg.rect.y > 0.5
		then
			hits += 1
		end
	end
	return hits
end

local N = 4000

local function armPlain(withEx: boolean): number
	local t0 = os.clock()
	local sink = 0
	for _ = 1, N do
		local r = composition.resolve(DECL :: any, { w = 1716, h = 871 }, ctx(withEx))
		sink += #r.regions
	end
	local dt = os.clock() - t0
	if sink < 0 then
		print(sink)
	end
	return dt
end

local function armScanned(withEx: boolean): number
	local t0 = os.clock()
	local sink = 0
	for _ = 1, N do
		local r = composition.resolve(DECL :: any, { w = 1716, h = 871 }, ctx(withEx))
		sink += #r.regions + scan(r)
	end
	local dt = os.clock() - t0
	if sink < 0 then
		print(sink)
	end
	return dt
end

local function median(xs: { number }): number
	table.sort(xs)
	return xs[math.ceil(#xs / 2)]
end

local function report(label: string, withEx: boolean)
	-- warm
	armPlain(withEx)
	armScanned(withEx)
	local a: { number } = {}
	local b: { number } = {}
	-- ABBA x 5: the order is symmetric, so a monotone drift in the machine cancels
	for _ = 1, 5 do
		table.insert(a, armPlain(withEx))
		table.insert(b, armScanned(withEx))
		table.insert(b, armScanned(withEx))
		table.insert(a, armPlain(withEx))
	end
	local ma, mb = median(a), median(b)
	-- an A/A spread: the same arm against itself, which is the noise floor any
	-- claimed delta has to clear
	local a2: { number } = {}
	for _ = 1, 5 do
		table.insert(a2, armPlain(withEx))
	end
	local ma2 = median(a2)
	print(
		string.format(
			"%-28s plain=%.4fs scanned=%.4fs delta=%+.2f%%   |  A/A spread=%+.2f%%   (%d resolves/arm)",
			label,
			ma,
			mb,
			(mb - ma) / ma * 100,
			(ma2 - ma) / ma * 100,
			N
		)
	)
end

report("no exclusions declared", false)
report("exclusions declared", true)
