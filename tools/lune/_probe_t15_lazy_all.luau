--!strict
--[[ Driver: N processes per mode, reporting n / min / median / max rather than a
	single number. The ARM is whichever `src/init.luau` the caller has in place.
	`--json <path>` writes the raw samples so two arms can be paired by INDEX
	afterwards (`_probe_t15_lazy_pair`) instead of compared as two medians. ]]
local process = require("@lune/process")
local serde = require("@lune/serde")
local fs = require("@lune/fs")

local REPEATS = tonumber(process.args[1] or "") or 15
local jsonPath = process.args[2]

local function stat(xs: { number }): (number, number, number)
	table.sort(xs)
	return xs[1], xs[math.ceil(#xs / 2)], xs[#xs]
end

local out: { [string]: any } = {}
for _, mode in { "require", "mount", "preload" } do
	local req: { number } = {}
	local work: { number } = {}
	local ms: { number } = {}
	for _ = 1, REPEATS do
		local r = process.exec("lune", { "run", "tools/lune/_probe_t15_lazy", mode })
		local p = string.split(string.gsub(r.stdout, "%s+$", ""), "\t")
		table.insert(req, (tonumber(p[3]) or 0) - (tonumber(p[2]) or 0))
		table.insert(work, (tonumber(p[4]) or 0) - (tonumber(p[3]) or 0))
		table.insert(ms, tonumber(p[5]) or 0)
	end
	out[mode] = { require = table.clone(req), then_ = table.clone(work), ms = table.clone(ms) }
	local rlo, rmid, rhi = stat(req)
	local wlo, wmid, whi = stat(work)
	local _, mmid, _ = stat(ms)
	print(
		`{mode}\tn={REPEATS}\trequireKb={rmid} [{rlo}..{rhi}]\tthenKb={wmid} [{wlo}..{whi}]`
			.. `\trequireMs={string.format("%.1f", mmid)}`
	)
end
if jsonPath ~= nil then
	fs.writeFile(jsonPath, serde.encode("json", out, true))
end
