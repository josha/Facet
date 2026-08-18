--!strict
-- Phase 4 versioning and public-surface contract (design §17 Phase 4;
-- UI-AGENT-001): the library carries a semantic version governed by
-- ADR-0011 (semver + deprecation policy), the version is a valid semver
-- string matching the documented one, deprecated surfaces are declared in a
-- machine-readable ledger with removal rules, and the public API table only
-- grows through the documented surface (drift between init.luau and the API
-- reference is checked mechanically by tools/lune/check_docs).

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")

local Facet = require("../src") :: any

describe("semantic versioning and deprecation (ADR-0011)", function()
	it("VERSION is a plain semver MAJOR.MINOR.PATCH (scaffold suffixes are gone)", function()
		local major, minor, patch = string.match(Facet.VERSION, "^(%d+)%.(%d+)%.(%d+)$")
		expect(major ~= nil).toBeTruthy()
		expect(tonumber(major)).toBe(0) -- pre-1.0: minor bumps may break with notice
		expect(tonumber(minor) :: number).toBeGreaterThanOrEqual(4) -- Phase 4 bump
		expect(patch ~= nil).toBeTruthy()
	end)

	it("the semver/deprecation ADR exists and states the policy", function()
		local adr = fs.readFile("docs/adr/ADR-0011-semver-and-deprecation.md")
		expect(string.find(adr, "MAJOR") ~= nil).toBeTruthy()
		expect(string.find(adr, "deprecat") ~= nil).toBeTruthy()
		expect(string.find(adr, Facet.VERSION, 1, true) ~= nil).toBeTruthy() -- ADR names the current version
	end)

	it("deprecations are a machine-readable ledger with the ADR's required fields", function()
		expect(type(Facet.DEPRECATIONS)).toBe("table")
		-- every entry must carry the policy fields, whichever half it came from
		for _, entry in Facet.DEPRECATIONS :: { any } do
			expect(type(entry.surface)).toBe("string")
			expect(type(entry.since)).toBe("string")
			expect(type(entry.removeNoEarlierThan)).toBe("string")
			expect(type(entry.replacement)).toBe("string")
			expect(#entry.surface > 0).toBe(true)
			expect(#entry.replacement > 0).toBe(true)
			expect(entry.note == nil or type(entry.note) == "string").toBe(true)
		end
	end)

	-- F-34 / the DEP mechanism. The ledger used to be schema-generated only, so a
	-- deprecated surface that is not a blueprint PROPERTY (an opts field, a
	-- derived condition) could not be declared at all — ADR-0011's machinery
	-- simply did not know about it, and the init.luau comment still claimed
	-- "Empty = nothing deprecated".
	it("the ledger is the UNION of schema-generated and declared entries", function()
		local schema = require("../src/blueprint_schema") :: any
		local generated = schema.deprecations()
		local ledger = Facet.DEPRECATIONS :: { any }
		-- FIVE declared entries: the two 0.8.0 rows, the two 0.9.0 VirtualList extent
		-- renames that came with `axis` (an alias is only a deprecation if the ledger
		-- says so — parity round 2 §2.3), and `screen_target.new(opts.isReducedMotion)`,
		-- which was deprecated in prose in two places and declared in neither until
		-- the Milestone-1 review (C3) — a deprecation with no `since` and no
		-- `removeNoEarlierThan` is invisible to every upgrade check ADR-0011 defines
		expect(#ledger).toBe(#generated + 5)
		-- schema entries come first, in their own deterministic order
		for i, entry in generated do
			expect(ledger[i].surface).toBe(entry.surface)
		end
		local declared: { [string]: any } = {}
		for i = #generated + 1, #ledger do
			declared[ledger[i].surface] = ledger[i]
		end
		local retryAttempts = declared["newResourceProvider(opts.retryAttempts)"]
		expect(retryAttempts ~= nil).toBe(true)
		expect(retryAttempts.replacement).toBe("opts.retry = { count, delaySeconds?, giveUp? }")
		local contentWidth = declared["adaptive.conditions().contentWidth"]
		expect(contentWidth ~= nil).toBe(true)
		expect(contentWidth.replacement).toBe("viewportWidth")
		local rowHeight = declared["newVirtualList(spec.rowHeight)"]
		expect(rowHeight ~= nil).toBe(true)
		expect(rowHeight.replacement).toBe("itemExtent")
		local viewportHeight = declared["newVirtualList(spec.viewportHeight)"]
		expect(viewportHeight ~= nil).toBe(true)
		expect(viewportHeight.replacement).toBe("viewportExtent")
		local reducedMotion = declared["screen_target.new(opts.isReducedMotion)"]
		expect(reducedMotion ~= nil).toBe(true)
		expect(reducedMotion.since).toBe("0.9.0")
		expect(reducedMotion.removeNoEarlierThan).toBe("0.10.0")
	end)

	it("every entry gives at least one MINOR of notice, and the ledger is frozen", function()
		local function parse(v: string): (number, number, number)
			local a, b, c = string.match(v, "^(%d+)%.(%d+)%.(%d+)$")
			expect(a ~= nil).toBeTruthy()
			return tonumber(a) :: number, tonumber(b) :: number, tonumber(c) :: number
		end
		for _, entry in Facet.DEPRECATIONS :: { any } do
			local sinceMajor, sinceMinor = parse(entry.since)
			local removeMajor, removeMinor = parse(entry.removeNoEarlierThan)
			local sinceKey = sinceMajor * 1000 + sinceMinor
			local removeKey = removeMajor * 1000 + removeMinor
			expect(removeKey).toBeGreaterThan(sinceKey) -- ADR-0011: one minor of notice
		end
		-- the ledger is authority, not a scratch table a consumer can edit
		expect(table.isfrozen(Facet.DEPRECATIONS)).toBe(true)
		expect(pcall(function()
			table.insert(Facet.DEPRECATIONS :: { any }, { surface = "forged" })
		end)).toBe(false)
	end)
end)

-- ENF-3. The ledger is machine-readable; the REFERENCE is what a human reads,
-- and a deprecated surface that api.md still presents as ordinary API is the
-- same lie in the other direction. The window is deliberately small (a
-- paragraph, not a page): the marking has to be where the reader already is.
describe("the reference marks what the ledger deprecates (ENF-3)", function()
	-- Named tolerance: EMPTY. The two 0.8.0 rows were held here while the
	-- documentation package caught up, and removing an entry is how that package
	-- proves the marking landed. Both are marked in api.md now, so nothing is
	-- exempt — a new deprecation must be marked in the same change that declares it.
	local PENDING_MARKING: { [string]: string } = {}
	local WINDOW = 3 -- lines either side of the mention

	it("api.md mentions every deprecated surface, and says 'deprecated' beside it", function()
		local lines = string.split(fs.readFile("docs/reference/api.md"), "\n")
		for _, entry in Facet.DEPRECATIONS :: { any } do
			-- the searchable form of a surface: its LAST identifier is the thing
			-- being deprecated ("adaptive.conditions().contentWidth" -> contentWidth,
			-- "newResourceProvider(opts.retryAttempts)" -> retryAttempts)
			local needle = ""
			for token in string.gmatch(entry.surface, "[%w_]+") do
				needle = token
			end
			local mentionedAt: number? = nil
			local marked = false
			for i, line in lines do
				if string.find(line, needle, 1, true) ~= nil then
					mentionedAt = mentionedAt or i
					for j = math.max(1, i - WINDOW), math.min(#lines, i + WINDOW) do
						if string.find(string.lower(lines[j]), "deprecat", 1, true) ~= nil then
							marked = true
						end
					end
				end
			end

			-- HARD: a surface api.md never mentions is one no reader can discover
			-- has a replacement, whatever the ledger says.
			expect(`{entry.surface} mentioned in api.md: {mentionedAt ~= nil}`).toBe(
				`{entry.surface} mentioned in api.md: true`
			)

			if not marked and PENDING_MARKING[entry.surface] == nil then
				error(
					`docs/reference/api.md mentions '{entry.surface}' (line {mentionedAt}) but never says `
						.. `"deprecated" within {WINDOW} lines of it, while Facet.DEPRECATIONS says it is. `
						.. "Mark it there, or name the row in this spec's PENDING_MARKING with a reason.",
					0
				)
			end
		end
	end)
end)

-- F-28. `src/init.luau` never required `core/contract`, so `Core`/`Scope`/
-- `Signal<T>` were unreachable from the public entry: an author writing a typed
-- helper had no name to write, and the checked-in contract was decorative.
-- Types are erased at runtime, so what a test can prove is that the entry
-- module's require graph really does reach the contract and stays engine-free.
describe("public type re-exports (F-28)", function()
	it("init.luau names the core contract types it re-exports", function()
		local source = fs.readFile("src/init.luau")
		expect(string.find(source, 'require("@self/core/contract")', 1, true) ~= nil).toBe(true)
		for _, name in { "Core", "Scope", "Signal<T>", "Memo<T>", "Readable<T>", "Unsubscribe" } do
			expect(string.find(source, `export type {name} =`, 1, true) ~= nil).toBe(true)
		end
	end)

	it("requiring the contract keeps the entry point safe for shared/server graphs", function()
		-- the boundary rule (UI-BOUND-001) is that nothing outside src/client may
		-- reach src/client; the contract is pure types with no requires at all
		local contractSource = fs.readFile("src/core/contract.luau")
		expect(string.find(contractSource, "require(", 1, true)).toBeNil()
	end)
end)
