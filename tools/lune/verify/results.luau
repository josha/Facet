--!strict
--[[ THE RESULT STORE, AND EVERY REASON IT REFUSES ONE (D7).

	`artifacts/verify/results/<producerId>/<identity>.json` holds one
	`facet-producer-result/1` record. A reader either returns the record or
	returns a REASON — never a shrug — because the whole value of the graph is
	that a reused result is exactly as good as a fresh run and a reader that
	guessed would destroy that.

	It refuses when:

	  * the identity in the file disagrees with the identity asked for (the file
	    was renamed or hand-placed);
	  * `complete` is false (the producer was killed, timed out, or the process
	    died between running and writing);
	  * `status` is FAIL — a failed producer is REPORTED, never reused as
	    evidence, and never cached: rerunning it is how a producer that failed
	    for an environmental reason stops failing;
	  * the toolchain string differs from the current pins;
	  * the environment class is not the one the row requires — a perf, Studio,
	    device, external or package result may satisfy only a row that asks for
	    that class, and a deterministic result may never stand in for one of
	    those (nor they for it);
	  * `bodyHash` does not match a fresh canonical hash of the record (someone
	    edited the file);
	  * for the suite: the tier is not `full`, `failed` is not zero, there is no
	    summary, `reportedSpecs` is short of `registeredSpecs`, or `passed` is
	    below the registered-spec floor. That last set is the truncated-suite
	    family. A main-thread yield ends the Lune suite EARLY AND WITH EXIT 0,
	    which is why "it exited zero" has never been sufficient here and is not
	    sufficient now. ]]

local fs = require("@lune/fs")
local serde = require("@lune/serde")

local util = require("./util")

local results = {}

results.ROOT = "artifacts/verify/results"

export type Record = {
	schema: string,
	producer: string,
	identity: string,
	environmentClass: string,
	command: string,
	startedAt: string,
	durationMs: number,
	exitCode: number,
	status: string,
	complete: boolean,
	payload: any,
	bodyHash: string?,
}

function results.path(producerId: string, identityHash: string): string
	return `{results.ROOT}/{producerId}/{identityHash}.json`
end

-- The hash covers everything except the field that carries it.
function results.bodyHash(record: Record): string
	local body: { [string]: any } = {}
	for k, v in record :: any do
		if k ~= "bodyHash" then
			body[k] = v
		end
	end
	return util.sha256(util.canonicalJson(body))
end

function results.write(record: Record): string
	local complete = table.clone(record) :: Record
	complete.bodyHash = results.bodyHash(record)
	local dir = `{results.ROOT}/{record.producer}`
	if not fs.isDir(dir) then
		fs.writeDir(dir)
	end
	local path = results.path(record.producer, record.identity)
	-- Written whole, by rename, so a reader never sees a half-file. The store is
	-- shared between concurrent runs exactly as the suite cache is.
	local staging = `{dir}/.{record.identity}.{math.random(1, 1e9)}.tmp`
	fs.writeFile(staging, util.canonicalJson(complete))
	fs.move(staging, path, { overwrite = true })
	return path
end

export type ReadOptions = {
	requiredClass: string?,
	toolchain: string?,
	suite: boolean?,
}

-- Returns (record, nil) or (nil, reason).
function results.read(producerId: string, identityHash: string, options: ReadOptions): (Record?, string?)
	local path = results.path(producerId, identityHash)
	if not fs.isFile(path) then
		return nil, "no stored result for this identity"
	end
	local ok, decoded = pcall(function()
		return serde.decode("json", fs.readFile(path))
	end)
	if not ok or type(decoded) ~= "table" then
		return nil, "stored result is not readable JSON"
	end
	local record = decoded :: Record
	if record.schema ~= "facet-producer-result/1" then
		return nil, `stored result has schema '{tostring(record.schema)}'`
	end
	if record.identity ~= identityHash then
		return nil, "stored result names a different identity than the file it lives in"
	end
	local stored = record.bodyHash
	if stored == nil or stored ~= results.bodyHash(record) then
		return nil, "body hash mismatch - the stored result was edited after it was written"
	end
	if record.complete ~= true then
		return nil, "stored result is incomplete (the producer did not finish)"
	end
	if record.status ~= "PASS" then
		return nil, `stored result is {tostring(record.status)} - a failed producer is rerun, never reused`
	end
	if options.toolchain ~= nil and record.payload ~= nil and type(record.payload) == "table" then
		local recorded = (record.payload :: any).toolchain
		if recorded ~= nil and recorded ~= options.toolchain then
			return nil, `stored result was produced under a different toolchain ({tostring(recorded)})`
		end
	end
	if options.requiredClass ~= nil and record.environmentClass ~= options.requiredClass then
		return nil,
			`stored result is class '{record.environmentClass}' but the row requires '{options.requiredClass}' - evidence classes are never upgraded`
	end
	if options.suite then
		local reason = results.suiteRefusal(record)
		if reason ~= nil then
			return nil, reason
		end
	end
	return record, nil
end

--[[ The suite-specific refusals, factored out so the coordinator can apply the
	same rule to a results file it has only just produced. ]]
function results.suiteRefusal(record: Record): string?
	local payload = record.payload
	if type(payload) ~= "table" then
		return "suite result carries no payload"
	end
	local suite = (payload :: any).results
	if type(suite) ~= "table" then
		return "suite result carries no structured case list"
	end
	if suite.schema ~= "facet-suite-results/1" then
		return `suite result has schema '{tostring(suite.schema)}'`
	end
	if suite.tier ~= "full" then
		return `suite result is tier '{tostring(suite.tier)}' - only a full-tier run is suite evidence`
	end
	if type(suite.cases) ~= "table" then
		return "suite result has no cases array"
	end
	if suite.failed == nil or suite.passed == nil then
		return "suite result has no pass/fail summary (a truncated run)"
	end
	if (suite.failed :: number) > 0 then
		return `suite result records {suite.failed} failing case(s)`
	end
	local registered = suite.registeredSpecs or 0
	local reported = suite.reportedSpecs or 0
	if registered > 0 and reported < registered then
		return `suite reported {reported} spec(s) but the runner registered {registered} - a spec registered nothing (silent zero) or the run was truncated`
	end
	if registered > 0 and (suite.passed :: number) < registered then
		return `suite passed {suite.passed} case(s), fewer than the {registered} registered spec modules - a partial run`
	end
	return nil
end

--[[ Index the cases of a suite result by id, so a row's lookup is one table
	read. Duplicate ids (the same describe/it text in one spec) collapse to the
	WORST status, which is the safe direction. ]]
function results.caseIndex(suiteResults: any): { [string]: string }
	local index: { [string]: string } = {}
	for _, case in suiteResults.cases :: { any } do
		local existing = index[case.id]
		if existing == nil or case.status ~= "pass" then
			index[case.id] = case.status
		end
	end
	return index
end

return results
