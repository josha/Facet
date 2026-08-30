--!strict
--[[ The human half of the coordinator.

	Four things have to be impossible to miss, because each of them has already
	been got wrong somewhere in this repository's history:

	  1. WHICH TIER RAN. An affected or fast run must never be mistaken for full
	     or release evidence, so it prints a banner saying so in as many words —
	     the same defence `./run-tests.sh --fast` uses.
	  2. WHY EACH PRODUCER WAS SELECTED, and whether it ran or was reused, WITH
	     THE INVALIDATION REASON. "cached" with no reason is how a stale cache
	     hides.
	  3. WHERE THE TIME WENT — the ten slowest, so the next optimisation pass
	     starts from a measurement.
	  4. THE SMALLEST COMMAND THAT REPRODUCES A FAILURE. A failing case names
	     `lune run tests/run_one <spec>`; a failing producer names
	     `tools/verify.sh --rerun <id>`. ]]

local report = {}

local BOLD = "\27[1m"
local DIM = "\27[2m"
local RED = "\27[31m"
local GREEN = "\27[32m"
local YELLOW = "\27[33m"
local OFF = "\27[0m"

local function seconds(ms: number): string
	return string.format("%6.2fs", ms / 1000)
end

function report.banner(tier: string)
	print("")
	if tier == "full" then
		print(`{BOLD}=== FACET VERIFY — FULL TIER: every deterministic producer, every phase view ==={OFF}`)
	elseif tier == "release" then
		print(
			`{BOLD}=== FACET VERIFY — RELEASE TIER: the full graph, including perf, package and Rascal Rally ==={OFF}`
		)
	elseif tier == "fast" then
		print(`{BOLD}{YELLOW}=== FACET VERIFY — FAST TIER — NOT FULL, NOT RELEASE, NOT GATE EVIDENCE ==={OFF}`)
		print(`{YELLOW}    The fast tier runs the inner-loop producers only. Its suite result is tier{OFF}`)
		print(`{YELLOW}    'fast' and the full/release reader REFUSES it. Run tools/verify.sh full{OFF}`)
		print(`{YELLOW}    before you call anything green.{OFF}`)
	elseif tier == "affected" then
		print(`{BOLD}{YELLOW}=== FACET VERIFY — AFFECTED TIER — NOT FULL, NOT RELEASE, NOT GATE EVIDENCE ==={OFF}`)
		print(`{YELLOW}    Only the producers whose declared inputs match your changed paths ran.{OFF}`)
		print(`{YELLOW}    Changed specs run through tests/run_one, whose result is tier 'one' and{OFF}`)
		print(`{YELLOW}    is REFUSED as suite evidence. Run tools/verify.sh full before merging.{OFF}`)
	end
	print("")
end

export type ProducerLine = {
	id: string,
	environmentClass: string,
	status: string,
	reused: boolean,
	reason: string,
	durationMs: number,
	selectedBecause: string,
}

function report.producers(lines: { ProducerLine }, explain: boolean)
	print(`{BOLD}Producers{OFF}`)
	local sorted = table.clone(lines)
	table.sort(sorted, function(a, b)
		return a.id < b.id
	end)
	for _, line in sorted do
		local mark = if line.status == "PASS"
			then `{GREEN}✓{OFF}`
			elseif line.status == "SKIP_MISSING" then `{YELLOW}-{OFF}`
			else `{RED}✗{OFF}`
		local how = if line.reused then `{DIM}reused{OFF}` else "ran   "
		print(
			`  {mark} {string.format("%-42s", line.id)} {how} {seconds(line.durationMs)}  {DIM}{line.environmentClass}{OFF}`
		)
		if explain then
			print(`      {DIM}selected: {line.selectedBecause}{OFF}`)
			print(`      {DIM}{if line.reused then "reuse" else "invalidation"}: {line.reason}{OFF}`)
		elseif not line.reused and line.reason ~= "" and line.status ~= "PASS" then
			print(`      {DIM}{line.reason}{OFF}`)
		end
	end
	print("")
end

function report.slowest(lines: { ProducerLine })
	local sorted = table.clone(lines)
	table.sort(sorted, function(a, b)
		return a.durationMs > b.durationMs
	end)
	print(`{BOLD}Slowest producers{OFF}`)
	for i = 1, math.min(10, #sorted) do
		local line = sorted[i]
		print(
			`  {string.format("%2d", i)}. {seconds(line.durationMs)}  {string.format("%-42s", line.id)} {DIM}{if line.reused
				then "(reused)"
				else ""}{OFF}`
		)
	end
	print("")
end

export type Failure = {
	kind: string,
	subject: string,
	detail: string,
	rerun: string,
}

function report.failures(failures: { Failure })
	if #failures == 0 then
		return
	end
	print(`{BOLD}{RED}Failures{OFF}`)
	for _, f in failures do
		print(`  {RED}✗{OFF} {f.kind}: {BOLD}{f.subject}{OFF}`)
		if f.detail ~= "" then
			for line in string.gmatch(f.detail, "[^\n]+") do
				print(`      {DIM}{line}{OFF}`)
			end
		end
		print(`      {YELLOW}smallest rerun:{OFF} {f.rerun}`)
	end
	print("")
end

function report.phases(phaseStates: { { phase: string, status: string, counts: { [string]: number } } })
	print(`{BOLD}Phase views{OFF}`)
	for _, p in phaseStates do
		local mark = if p.status == "PASS"
			then `{GREEN}PASS {OFF}`
			elseif p.status == "NOT_EVALUATED" then `{DIM}—    {OFF}`
			else `{RED}{string.format("%-5s", p.status)}{OFF}`
		local parts: { string } = {}
		for _, key in
			{ "PASS", "FAIL_RECOVERABLE", "FAIL_ENVIRONMENT", "FAIL_OPTIONAL", "PENDING", "RETIRED", "NOT_EVALUATED" }
		do
			local n = p.counts[key]
			if n ~= nil and n > 0 then
				table.insert(parts, `{n} {string.lower(key)}`)
			end
		end
		print(`  {mark} {string.format("%-34s", p.phase)} {DIM}{table.concat(parts, ", ")}{OFF}`)
	end
	print("")
end

return report
