--!strict
local process = require("@lune/process")
local checker = require("./check_experiment_markers")

local USAGE = "usage: lune run tools/lune/check_experiment_markers_cli [--selftest]"

local selftest = false
for _, arg in process.args do
	if arg == "--selftest" then
		selftest = true
	elseif arg ~= "--" then
		print(USAGE)
		process.exit(2)
	end
end

if selftest then
	local files = checker.files()
	if #files == 0 then
		print("check_experiment_markers: SELFTEST FAIL — no module under src/ to scan")
		process.exit(1)
	end
	local target = files[#files]
	local red = {
		"local ZZ_NO_PATH2D = true",
		"if class == 'Path' and not ZZExperiment then end",
		"local flag = ZZ",
	}
	for _, line in red do
		local result = checker.check({ injectFile = target, injectLine = line })
		local caught = false
		for _, v in result.violations do
			if v.file == target and v.text == line then
				caught = true
			end
		end
		if not caught then
			print(`check_experiment_markers: SELFTEST FAIL — the planted line was not reported: {line}`)
			process.exit(1)
		end
		print(`  planted '{line}': reported`)
	end
	local green = { "local BUZZER = 1", "local fizz, buzz = 1, 2", "local aZZ = 1" }
	for _, line in green do
		local result = checker.check({ injectFile = target, injectLine = line })
		for _, v in result.violations do
			if v.file == target and v.text == line then
				print(`check_experiment_markers: SELFTEST FAIL — an ordinary name was reported: {line}`)
				process.exit(1)
			end
		end
		print(`  ordinary '{line}': passed`)
	end
	local live = checker.check()
	if not live.ok then
		print("check_experiment_markers: SELFTEST FAIL — the working tree has markers:")
		for _, v in live.violations do
			print("  " .. checker.describe(v))
		end
		process.exit(1)
	end
	print(
		`check_experiment_markers: SELFTEST PASS — {#red} planted markers were reported, {#green} ordinary names `
			.. `passed, and {live.counts.files} modules are clean`
	)
	process.exit(0)
end

local result = checker.check()
if result.ok then
	print(`check_experiment_markers: PASS — {result.counts.files} modules, {result.counts.lines} lines, no ZZ marker`)
	process.exit(0)
end
for _, v in result.violations do
	print("  " .. checker.describe(v))
end
print(`check_experiment_markers: FAIL — {#result.violations} scratch marker(s) in src/`)
process.exit(1)
