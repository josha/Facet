--!strict
--[[ Which gates actually need the machine to be quiet before they run?

	`tools/prior_gates.sh` waits for the one-minute load average to fall below a
	threshold before EVERY gate, up to 45 s each. It does that for a real reason,
	recorded in its own header: run back to back, `phase-3-pilot` failed in-batch
	2/2 and passed standalone 2/2 with nothing in the tree changed, because
	`tools/bench.sh` was measuring the previous gate's tail. A gate that goes red
	from its own scheduling is a flaky gate, and a flaky gate is a slower version
	of one that proves nothing.

	But the wait is charged to all of them. There are thirty-two registered stages
	now, so the worst case is around twenty-three minutes of deliberate idling in
	one sweep — and the great majority of gates measure nothing timing-sensitive
	at all. They run a scanner, they grep a cached transcript, they check a file
	exists. Those cannot be perturbed by a warm machine.

	So this prints the stages that DO measure, and `prior_gates.sh` settles before
	those and no others.

	IT IS DERIVED FROM THE MANIFEST, NEVER TYPED. A hand-maintained list of
	"timing-sensitive gates" is wrong the first time somebody adds a bench row to
	a stage that did not have one, and wrong silently — the new row simply starts
	measuring a busy machine and the flake arrives weeks later attached to the
	wrong change. This reads every stage's own commands and asks whether any of
	them invokes something that measures time, memory, or randomness.

	Usage:
	  lune run tools/lune/settle_gates            one stage name per line
	  lune run tools/lune/settle_gates -- --all   every stage, prefixed SETTLE/FAST
]]

local process = require("@lune/process")
local manifest = require("./gate_manifest")

--[[ The producers whose ANSWER depends on how busy the machine was.

	`bench`, `perf` and `soak` measure wall clock against a frozen p95. `faults`
	and `fuzz` inject failures on a schedule. `render` and `prove_perf_gate` both
	shell into the same measured places.

	Everything absent from this list is deterministic: a source scanner, a
	document check, a grep of a cached transcript, a file-existence assertion.
	None of those can answer differently on a warm machine, which is exactly why
	waiting for one is pure cost. ]]
local MEASURES_TIME = {
	"tools/bench.sh",
	"tools/soak.sh",
	"tools/perf.sh",
	"tools/faults.sh",
	"tools/fuzz.sh",
	"tools/render.sh",
	"lune run tools/lune/bench",
	"lune run tools/lune/soak",
	"lune run tools/lune/perf",
	"lune run tools/lune/faults",
	"lune run tools/lune/fuzz",
	"lune run tools/lune/render",
	"lune run tools/lune/prove_perf_gate",
}

local function needsQuiet(stage: string): boolean
	local checks = manifest[stage]
	if checks == nil then
		return false
	end
	for _, check in checks do
		local run = check.run
		if run ~= nil then
			for _, producer in MEASURES_TIME do
				if string.find(run, producer, 1, true) ~= nil then
					return true
				end
			end
		end
	end
	return false
end

local names: { string } = {}
for stage in manifest do
	table.insert(names, stage)
end
table.sort(names)

-- Lune passes a literal `--` through as an argument of its own, so the
-- documented `lune run <script> -- --flag` idiom arrives as {"--", "--flag"}.
-- Scanning is the only spelling that works for BOTH that idiom and a bare
-- `lune run <script> --flag`; `args[1] == "--all"` silently ignored the
-- documented one.
local all = false
for _, arg in process.args do
	if arg == "--all" then
		all = true
	end
end
for _, stage in names do
	local quiet = needsQuiet(stage)
	if all then
		print(`{if quiet then "SETTLE" else "FAST  "}\t{stage}`)
	elseif quiet then
		print(stage)
	end
end
