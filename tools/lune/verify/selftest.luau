--!strict
--[[ The verification graph's own negative controls.

	`lune run tools/lune/verify/selftest` — every refusal this store can make,
	made on purpose, in a scratch directory. A cache that cannot be seen to
	refuse is a cache that will one day serve a stale green to 500 gate rows, so
	the refusals are asserted here rather than described in a comment.

	This is itself a producer in the graph (`verify-selftest`), so a change that
	quietly removes a refusal reddens a row. ]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local util = require("./util")
local identity = require("./identity")
local results = require("./results")

local failures: { string } = {}
local checked = 0

local function check(name: string, ok: boolean, detail: string?)
	checked += 1
	if ok then
		print(`  ✓ {name}`)
	else
		print(`  ✗ {name}{if detail then " — " .. detail else ""}`)
		table.insert(failures, name)
	end
end

-- ---- canonical JSON ---------------------------------------------------------

print("canonical json")
do
	local a = util.canonicalJson({ b = 1, a = 2, c = { 3, 4 } })
	local b = util.canonicalJson({ c = { 3, 4 }, a = 2, b = 1 })
	check("key order does not change the encoding", a == b, `{a} vs {b}`)
	check("arrays stay arrays", string.find(a, '"c":[3,4]', 1, true) ~= nil, a)
	check("integers do not gain a decimal point", util.canonicalJson({ n = 7 }) == '{"n":7}')
	check("a control character is escaped", util.canonicalJson({ s = "a\nb" }) == '{"s":"a\\nb"}')
	--[[ THE ROUND TRIP IS THE POINT. A fraction that does not parse back to
		itself makes every body hash over a record holding one a coin toss — and
		the record holding thousands of them is the suite's, which is the most
		expensive producer there is. ]]
	local awkward = { 90.47791664488615, 0.0330416951328516, 265987.76987503516, 1 / 3, 1e-7, 2.2250738585072014e-308 }
	local roundTripped = 0
	for _, v in awkward do
		local encoded = util.canonicalJson({ ms = v })
		if util.canonicalJson(serde.decode("json", encoded)) == encoded then
			roundTripped += 1
		end
	end
	check(`every awkward fraction survives a decode ({roundTripped}/{#awkward})`, roundTripped == #awkward)
end

-- ---- globs ------------------------------------------------------------------

print("globs")
do
	check("src/** matches a nested file", util.matchesAny("src/layout/solver.luau", { "src/**" }))
	check("src/** does not match a sibling tree", not util.matchesAny("tests/x.luau", { "src/**" }))
	check("a single star stops at a separator", not util.matchesAny("tools/lune/x.luau", { "tools/*.luau" }))
	check("a single star matches within one segment", util.matchesAny("tools/x.luau", { "tools/*.luau" }))
	check("an exact path matches itself", util.matchesAny("rokit.toml", { "rokit.toml" }))
end

-- ---- identity ---------------------------------------------------------------

print("identity")
local scratch = `/tmp/facet-verify-selftest-{process.args[1] or tostring(os.time())}`
if fs.isDir(scratch) then
	fs.removeDir(scratch)
end
fs.writeDir(scratch)
fs.writeFile(`{scratch}/one.txt`, "alpha\n")

local tc = identity.toolchain()
local producer: identity.Producer = {
	id = "selftest-producer",
	command = "true",
	inputs = { `{scratch}/**` },
	environmentClass = "deterministic",
	tiers = { full = true },
}
do
	--[[ THE CACHES ARE A PER-RUN SNAPSHOT. Inside one coordinator run every
		producer is keyed against the same view of the tree on purpose, so a
		sibling agent's edit landing mid-run cannot give two producers two
		different ideas of what the source was. Each edit below is therefore
		followed by `identity.resetCaches()` — it is asking a SECOND run's
		question, which is the one that matters for invalidation. ]]
	local first = identity.compute(producer, tc)
	local again = identity.compute(producer, tc)
	check("the same tree hashes the same twice", first.hash == again.hash)

	fs.writeFile(`{scratch}/one.txt`, "beta\n")
	identity.resetCaches()
	local changed = identity.compute(producer, tc)
	check("a changed input file changes the identity", changed.hash ~= first.hash)

	fs.writeFile(`{scratch}/one.txt`, "alpha\n")
	identity.resetCaches()
	local restored = identity.compute(producer, tc)
	check("restoring the file restores the identity", restored.hash == first.hash)

	fs.writeFile(`{scratch}/one.txt`, "alpha\r\n")
	identity.resetCaches()
	local crlf = identity.compute(producer, tc)
	check("a CRLF line ending is the same source", crlf.hash == first.hash)
	fs.writeFile(`{scratch}/one.txt`, "alpha\n")
	identity.resetCaches()

	local other = table.clone(producer)
	other.command = "true # different"
	check("a changed command changes the identity", identity.compute(other, tc).hash ~= first.hash)

	local otherClass = table.clone(producer)
	otherClass.environmentClass = "perf"
	check("a changed environment class changes the identity", identity.compute(otherClass, tc).hash ~= first.hash)

	local staleTc = table.clone(tc)
	staleTc.lune = "lune 0.0.0-not-this-one"
	check("a changed toolchain pin changes the identity", identity.compute(producer, staleTc).hash ~= first.hash)

	local withFixture = table.clone(producer)
	withFixture.fixtures = { `{scratch}/missing.json` }
	local absent = identity.compute(withFixture, tc)
	fs.writeFile(`{scratch}/missing.json`, "{}")
	identity.resetCaches()
	check("a fixture appearing changes the identity", identity.compute(withFixture, tc).hash ~= absent.hash)
end

-- ---- the results store ------------------------------------------------------

print("result store refusals")
do
	local previousRoot = results.ROOT
	results.ROOT = `{scratch}/results`
	local id = "abc123"
	local record: results.Record = {
		schema = "facet-producer-result/1",
		producer = "selftest-producer",
		identity = id,
		environmentClass = "deterministic",
		command = "true",
		startedAt = "2026-08-30T00:00:00Z",
		durationMs = 1,
		exitCode = 0,
		status = "PASS",
		complete = true,
		payload = { toolchain = identity.toolchainString(tc) },
	}
	local path = results.write(record)

	local got, reason = results.read("selftest-producer", id, { requiredClass = "deterministic" })
	check("a clean result reads back", got ~= nil, reason)

	local _, wrongId = results.read("selftest-producer", "not-the-identity", {})
	check("a different identity is a miss", wrongId ~= nil, "it was accepted")

	local _, wrongClass = results.read("selftest-producer", id, { requiredClass = "perf" })
	check("a deterministic result cannot satisfy a perf row", wrongClass ~= nil, "it was accepted")

	local _, wrongTool = results.read("selftest-producer", id, { toolchain = "lune 0.0.0" })
	check("a stale toolchain is refused", wrongTool ~= nil, "it was accepted")

	-- hand-edit the payload without touching bodyHash
	local edited = string.gsub(fs.readFile(path), '"durationMs":1', '"durationMs":2')
	fs.writeFile(path, edited)
	local _, edit = results.read("selftest-producer", id, {})
	check("an edited result fails its body hash", edit ~= nil, "it was accepted")

	local incomplete = table.clone(record)
	incomplete.complete = false
	results.write(incomplete)
	local _, inc = results.read("selftest-producer", id, {})
	check("an incomplete result is refused", inc ~= nil, "it was accepted")

	local failed = table.clone(record)
	failed.status = "FAIL"
	failed.exitCode = 1
	results.write(failed)
	local _, f = results.read("selftest-producer", id, {})
	check("a failed result is never reused", f ~= nil, "it was accepted")

	-- suite-shaped refusals
	local function suiteRecord(payload: any): results.Record
		local r = table.clone(record)
		r.payload = payload
		return r
	end
	local goodSuite = {
		toolchain = identity.toolchainString(tc),
		results = {
			schema = "facet-suite-results/1",
			tier = "full",
			cases = { { id = "a::b::c", status = "pass" } },
			passed = 10,
			failed = 0,
			registeredSpecs = 1,
			reportedSpecs = 1,
		},
	}
	check("a complete full-tier suite result is accepted", results.suiteRefusal(suiteRecord(goodSuite)) == nil)

	local fastSuite = { toolchain = goodSuite.toolchain, results = table.clone(goodSuite.results) }
	fastSuite.results.tier = "fast"
	check("a fast-tier result is not suite evidence", results.suiteRefusal(suiteRecord(fastSuite)) ~= nil)

	local oneSuite = { toolchain = goodSuite.toolchain, results = table.clone(goodSuite.results) }
	oneSuite.results.tier = "one"
	check("a single-spec result is not suite evidence", results.suiteRefusal(suiteRecord(oneSuite)) ~= nil)

	local redSuite = { toolchain = goodSuite.toolchain, results = table.clone(goodSuite.results) }
	redSuite.results.failed = 1
	check("a suite with a failing case is refused", results.suiteRefusal(suiteRecord(redSuite)) ~= nil)

	local shortSuite = { toolchain = goodSuite.toolchain, results = table.clone(goodSuite.results) }
	shortSuite.results.reportedSpecs = 0
	check(
		"a suite that reported fewer specs than registered is refused",
		results.suiteRefusal(suiteRecord(shortSuite)) ~= nil
	)

	local partialSuite = { toolchain = goodSuite.toolchain, results = table.clone(goodSuite.results) }
	partialSuite.results.passed = 0
	partialSuite.results.registeredSpecs = 5
	partialSuite.results.reportedSpecs = 5
	check(
		"a suite with fewer passes than registered specs is refused",
		results.suiteRefusal(suiteRecord(partialSuite)) ~= nil
	)

	local noSummary = { toolchain = goodSuite.toolchain, results = table.clone(goodSuite.results) }
	noSummary.results.passed = nil
	check("a suite with no summary line is refused", results.suiteRefusal(suiteRecord(noSummary)) ~= nil)

	results.ROOT = previousRoot
end

fs.removeDir(scratch)

print("")
if #failures == 0 then
	print(`verify-selftest: PASS ({checked} checks)`)
	process.exit(0)
end
print(`verify-selftest: FAIL — {#failures} of {checked} checks`)
for _, name in failures do
	print(`  - {name}`)
end
process.exit(1)
