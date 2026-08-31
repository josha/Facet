--!strict
--[[ THE VERIFICATION GRAPH: requirement -> producer -> result ids -> gate view.

	The data lives beside this file in `graph.json`. It WAS generated, from a gate
	manifest and a phases file that are now in the private archive — so it is no
	longer derived from anything in this tree: it is the source of truth, and
	`tools/lune/verify/repair_graph.py` is how it is maintained (idempotent; it
	records what it moved in the coverage map). Do not hand-edit it. The census
	of what every manifest row became is at
	`artifacts/distribution-readiness/verification/graph-census.md`.

	A ROW is one gate check. It carries the requirement ids it touches, the phase
	view it appears under, and a `check` built from at most four things:

	  producers   every one of these must have a PASS result in this run
	  resultIds   every one of these case ids must be `pass` in the suite result
	  stdoutPins  a pattern that must appear in a named producer's recorded output
	  shell       the residual assertions — file existence, text pins on evidence
	              documents, negative controls over src/ — kept verbatim

	plus two whole-row forms: `priorPhases` (every earlier phase must pass in THIS
	run, which is what replaces prior_gates.sh's replay) and a literal `state` for
	work that is PENDING or externally blocked.

	A PHASE is a VIEW, not a run. Every phase the manifest had survives, so
	`tools/gate.sh <phase>` still answers and still writes
	`artifacts/<phase>/gate.json` in the `facet-gate/1` shape — but it is
	evaluated from the one run's results rather than by starting the suite again.

	A PRODUCER is a command that runs at most once per exact identity. Its
	`environmentClass` is load-bearing: a perf, Studio, device, external or
	package result may satisfy only a row that asks for that class, and no
	headless cache can upgrade one into another. ]]

local fs = require("@lune/fs")
local serde = require("@lune/serde")

local identity = require("./identity")

local graph = {}

export type Check = {
	producers: { string }?,
	resultIds: { string }?,
	stdoutPins: { { producer: string, flags: string, pattern: string } }?,
	shell: string?,
	receipt: string?,
	priorPhases: boolean?,
}

export type Row = {
	id: string,
	phase: string,
	name: string,
	requirements: { string },
	evidence: string?,
	releaseBlocking: boolean,
	note: string,
	class: string,
	state: string?,
	retiredReason: string?,
	pendingMigration: string?,
	check: Check,
}

export type Phase = {
	id: string,
	artifactDir: string,
	gateArtifact: string,
	next: string?,
}

export type Graph = {
	schema: string,
	generatedAt: string,
	phases: { Phase },
	producers: { identity.Producer },
	rows: { Row },
	unresolvedPatterns: { string }?,
}

local loaded: Graph? = nil

function graph.load(): Graph
	if loaded ~= nil then
		return loaded :: Graph
	end
	local path = "tools/lune/verify/graph.json"
	assert(fs.isFile(path), `verify: {path} is missing — regenerate it with tools/lune/verify/convert_manifest.py`)
	local data = serde.decode("json", fs.readFile(path)) :: Graph
	assert(data.schema == "facet-verify-graph/1", `verify: unexpected graph schema {tostring(data.schema)}`)
	loaded = data
	return data
end

function graph.producerById(g: Graph): { [string]: identity.Producer }
	local index: { [string]: identity.Producer } = {}
	for _, p in g.producers do
		index[p.id] = p
	end
	return index
end

function graph.rowsForPhase(g: Graph, phase: string): { Row }
	local out: { Row } = {}
	for _, row in g.rows do
		if row.phase == phase then
			table.insert(out, row)
		end
	end
	return out
end

-- Producer ids a set of rows needs, in graph order.
function graph.producersForRows(rows: { Row }): { string }
	local seen: { [string]: boolean } = {}
	local out: { string } = {}
	local function add(id: string)
		if not seen[id] then
			seen[id] = true
			table.insert(out, id)
		end
	end
	for _, row in rows do
		for _, id in row.check.producers or {} do
			add(id)
		end
		if row.check.resultIds ~= nil then
			add("suite")
		end
		for _, pin in row.check.stdoutPins or {} do
			add(pin.producer)
		end
		-- a residual grep of the recorded transcript still needs the run that
		-- recorded it
		if row.check.shell ~= nil then
			if string.find(row.check.shell, "FACET_VERIFY_SUITE_TRANSCRIPT", 1, true) then
				add("suite")
			end
			if string.find(row.check.shell, "FACET_VERIFY_RR_TRANSCRIPT", 1, true) then
				add("rascalrally-suite")
			end
		end
	end
	return out
end

function graph.phaseIds(g: Graph): { string }
	local out: { string } = {}
	for _, p in g.phases do
		table.insert(out, p.id)
	end
	return out
end

function graph.phaseById(g: Graph): { [string]: Phase }
	local index: { [string]: Phase } = {}
	for _, p in g.phases do
		index[p.id] = p
	end
	return index
end

function graph.producersForTier(g: Graph, tier: string): { string }
	local out: { string } = {}
	for _, p in g.producers do
		if (p.tiers :: any)[tier] then
			table.insert(out, p.id)
		end
	end
	table.sort(out)
	return out
end

-- The gate.json severity ladder, unchanged from tools/lune/gate.luau so the
-- artifact this writes is the artifact everything already reads.
local SEVERITY = {
	PASS = 0,
	FAIL_OPTIONAL = 1,
	RETIRED = 1,
	FAIL_ENVIRONMENT = 2,
	PENDING = 3,
	FAIL_RECOVERABLE = 4,
	BLOCKED_CRITICAL = 5,
}

function graph.severity(state: string): number
	return SEVERITY[state] or 4
end

--[[ WHICH ROW STATES LET A RUN BE GREEN.

	PENDING NEEDS THE SAME `releaseBlocking` TREATMENT FAIL_ENVIRONMENT ALREADY
	HAS, and the reason is a knot rather than a preference (director ruling,
	2026-08-31). Two distribution-readiness rows -- `owner-packet-complete` and
	`private-package-id-and-update-proof` -- are the stage-CLOSING pair: each can
	only pass AFTER a guarded release action, and that action refuses to run
	unless the release gate's own `gateEvidence.status` reads PASS. A row that
	can only pass after the action must not be the reason the action cannot
	happen.

	THE HONEST RECORD SURVIVES INTACT. The row still reports PENDING, still
	appears as PENDING in its phase's counts and in the compatibility gate.json,
	still ranks at PENDING severity, and still says in its own note what it is
	waiting for. The only thing that changes is whether a DECLARED, explicitly
	NON-BLOCKING pending is counted as a failure of the run.

	THE DEFAULT STAYS STRICT. `releaseBlocking` is true or unset for any row
	pending because the WORK IS MISSING, and such a row still fails the run.
	Non-blocking is a per-row declaration somebody had to write down, not a
	property pending rows acquire by being pending. The selftest plants both
	arms. ]]
function graph.statePasses(state: string, releaseBlocking: boolean): boolean
	return state == "PASS"
		or state == "FAIL_OPTIONAL"
		or state == "RETIRED"
		or (state == "FAIL_ENVIRONMENT" and not releaseBlocking)
		--   EXPLICIT `false`, not merely falsy: an unset `releaseBlocking` is a
		--   row nobody has ruled on, and the strict answer is the safe one.
		or (state == "PENDING" and releaseBlocking == false)
end

return graph
