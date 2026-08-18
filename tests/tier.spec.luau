--!strict
-- THE TIER GUARDS (parity round 2, Phase 6 step 2).
--
-- A fast tier is a promise about what it still runs, and a promise nobody
-- checks decays into "the specs somebody remembered to list". These cases hold
-- the promise to the file system and to the gate suite:
--
--   * the fast tier is DERIVED from tests/run.luau, never hand-listed, so a new
--     spec joins it by existing;
--   * every exclusion names a spec that is really in the suite — rename a spec
--     out from under `tiers.SLOW` and this reddens instead of the tier quietly
--     losing a file;
--   * the smoke check, the core spine and every parity-round-2 area are IN the
--     fast tier by name;
--   * every path the suite requires is a real file (this one guards
--     tests/run.luau itself, not only the tier);
--   * and the fast runner cannot be mistaken for the suite: it prints the
--     FACET-FAST-TIER marker that tools/test.sh refuses.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")
local tiers = require("./lib/tiers")

local function fileExists(rel: string): boolean
	-- run.luau's requires drop the extension; specs live under tests/.
	return fs.isFile("tests/" .. rel .. ".luau")
end

describe("test tiers: the fast tier is the suite list minus named exclusions", function()
	it("the full order is parsed from tests/run.luau and every entry is a real file", function()
		local full = tiers.fullOrder()
		expect(#full > 150).toBe(true)
		local missing: { string } = {}
		for _, rel in full do
			if not fileExists(rel) then
				table.insert(missing, rel)
			end
		end
		expect(
			#missing == 0 or error(`tests/run.luau requires files that do not exist: {table.concat(missing, ", ")}`, 2)
		).toBe(true)
	end)

	it("EVERY exclusion names a spec the suite actually runs (a rename reddens here)", function()
		local full = tiers.fullOrder()
		local inSuite: { [string]: boolean } = {}
		for _, rel in full do
			inSuite[rel] = true
		end
		local orphans: { string } = {}
		for _, entry in tiers.SLOW do
			if not inSuite[entry.spec] then
				table.insert(orphans, entry.spec)
			end
		end
		expect(
			#orphans == 0 or error(`tiers.SLOW excludes specs the suite does not run: {table.concat(orphans, ", ")}`, 2)
		).toBe(true)
	end)

	it("every exclusion carries a measured cost and a reason, not just a name", function()
		expect(#tiers.SLOW >= 1).toBe(true)
		for _, entry in tiers.SLOW do
			expect(entry.ms > 250).toBe(true)
			expect(#entry.why > 30).toBe(true)
		end
	end)

	it("the fast tier is a strict subset of the suite, in the same relative order", function()
		local full = tiers.fullOrder()
		local fast = tiers.fastOrder()
		expect(#fast).toBe(#full - #tiers.SLOW)
		local i = 1
		for _, rel in full do
			if i <= #fast and fast[i] == rel then
				i += 1
			end
		end
		-- every fast entry was consumed in full order => same relative order,
		-- and no fast entry is absent from the suite
		expect(i).toBe(#fast + 1)
	end)

	it("smoke, the core spine and every parity-round-2 area are IN the fast tier", function()
		local fast: { [string]: boolean } = {}
		for _, rel in tiers.fastOrder() do
			fast[rel] = true
		end
		local dropped: { string } = {}
		for _, anchor in tiers.FAST_ANCHORS do
			if not fast[anchor] then
				table.insert(dropped, anchor)
			end
		end
		expect(#dropped == 0 or error(`the fast tier no longer runs: {table.concat(dropped, ", ")}`, 2)).toBe(true)
	end)

	it("the fast runner announces itself with the marker tools/test.sh refuses", function()
		local runner = fs.readFile("tests/run_fast.luau")
		expect(string.find(runner, "FACET-FAST-TIER", 1, true) ~= nil).toBe(true)
		local gate = fs.readFile("tools/test.sh")
		expect(string.find(gate, "FACET-FAST-TIER", 1, true) ~= nil).toBe(true)
		-- ...and the gate's own path is still the argument-free full suite
		expect(string.find(gate, 'out="$(./run-tests.sh 2>&1)"', 1, true) ~= nil).toBe(true)
	end)

	it("the fast runner does not hand-list specs: it derives them from run.luau", function()
		local runner = fs.readFile("tests/run_fast.luau")
		expect(string.find(runner, "tiers.fastOrder", 1, true) ~= nil).toBe(true)
		-- a literal spec require in the fast runner would be a second list, and
		-- a second list is the thing this whole module exists to prevent
		expect(string.match(runner, 'require%("%./[%w_/]+%.spec"%)')).toBeNil()
	end)
end)
