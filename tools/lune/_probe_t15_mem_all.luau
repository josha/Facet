--!strict
-- Driver for _probe_t15_mem: one PROCESS per subset per repeat, median reported.
local process = require("@lune/process")
local serde = require("@lune/serde")
local fs = require("@lune/fs")

local SUBSETS = {
	"nothing",
	"core",
	"core+env",
	"blueprint",
	"schemas",
	"tokens",
	"solver",
	"focus",
	"motion",
	"async",
	"input-actions",
	"renderer",
	"presenter",
	"mount-path",
	"mount-path+1control",
	"mount-path+table",
	"controls-all",
	"replication",
	"spatial",
	"pathShapes",
	"sensory-profile",
	"themes-machinery",
	"theme-package-neutral",
	"theme-package-ornate",
	"themes-snapshot",
	"themes-package",
	"themes-icons",
	"text-metrics",
	"blueprint-schema-only",
	"root-lazy-floor",
	"lazy-floor-no-themepackage",
	"lazy-floor-no-replication",
	"lazy-floor-no-spatial",
	"lazy-floor-no-pathshapes",
	"lazy-floor-no-drag",
	"root-lazy+progress",
	"root-lazy+table",
	"root-lazy+rascalrally",
	"root",
}
local REPEATS = 9

local function median(xs: { number }): number
	table.sort(xs)
	return xs[math.ceil(#xs / 2)]
end

local rows: { any } = {}
for _, subset in SUBSETS do
	local floors: { number } = {}
	local afters: { number } = {}
	local deltas: { number } = {}
	for _ = 1, REPEATS do
		local r = process.exec("lune", { "run", "tools/lune/_probe_t15_mem", subset })
		if not r.ok then
			print(`{subset}: FAILED {r.stderr}`)
			break
		end
		local parts = string.split(string.gsub(r.stdout, "%s+$", ""), "\t")
		table.insert(floors, tonumber(parts[2]) or 0)
		table.insert(afters, tonumber(parts[3]) or 0)
		table.insert(deltas, tonumber(parts[4]) or 0)
	end
	if #deltas > 0 then
		table.insert(rows, {
			subset = subset,
			floorKb = median(floors),
			afterKb = median(afters),
			deltaKb = median(deltas),
			deltas = deltas,
		})
	end
end

print(`{"subset"}\tfloorKb\tafterKb\tdeltaKb\tsamples`)
for _, r in rows do
	print(`{r.subset}\t{r.floorKb}\t{r.afterKb}\t{r.deltaKb}\t{table.concat(r.deltas, ",")}`)
end
fs.writeFile("artifacts/release-candidate-review/perf/_memory.json", serde.encode("json", rows, true))
