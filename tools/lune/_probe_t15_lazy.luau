--!strict
--[[ T15: what `require(Facet)` costs, measured so the number survives resampling.

	WHY THE MARK IS TAKEN AFTER A SETTLE, NOT IMMEDIATELY. Lune has no forced
	collection, so a `gcinfo()` taken the instant a require returns reports
	wherever the collector happened to be — and the T15 review resampled the root
	row and found it BIMODAL (2,574-2,816 KB), i.e. two collector phases, not two
	memory costs. Reading a difference off one pair of such samples is reading
	noise. So each mark is taken after an identical settle: allocate and drop a
	fixed churn, which pushes the collector to a comparable place in its cycle for
	every arm, then read.

	The driver pairs arm samples by INDEX and reports the spread, so a claim is a
	range with an n beside it rather than the best pair anybody found.

	Usage: lune run tools/lune/_probe_t15_lazy <require|mount|preload>
]]
local process = require("@lune/process")
local mode = process.args[1] or "require"

local function settle()
	local churn: { any } = {}
	for i = 1, 20000 do
		churn[i] = { i }
	end
	churn = {}
	local _ = churn
end

settle()
local floorKb = gcinfo()
local t0 = os.clock()
local Facet = require("../../src") :: any
local requireMs = (os.clock() - t0) * 1000
settle()
local afterRequireKb = gcinfo()

local afterWorkKb = afterRequireKb
if mode == "mount" then
	local core = Facet.newCore()
	local rows = core:signal({ { id = "a" }, { id = "b" } })
	local list = Facet.Controls.VirtualList(core, {
		id = "VL",
		rows = rows,
		key = function(i: any)
			return i.id
		end,
		rowHeight = 40,
		viewportHeight = 200,
		cell = function(item: any)
			return Facet.UI.Text({ id = "L", text = item.id, textSize = 12 })
		end,
	})
	settle()
	afterWorkKb = gcinfo()
	local _ = list
elseif mode == "preload" then
	if Facet.preload ~= nil then
		Facet.preload()
	end
	settle()
	afterWorkKb = gcinfo()
end

print(`{mode}\t{floorKb}\t{afterRequireKb}\t{afterWorkKb}\t{requireMs}`)
