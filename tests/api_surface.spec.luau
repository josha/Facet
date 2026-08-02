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

local LuauUI = require("../src") :: any

describe("semantic versioning and deprecation (ADR-0011)", function()
	it("VERSION is a plain semver MAJOR.MINOR.PATCH (scaffold suffixes are gone)", function()
		local major, minor, patch = string.match(LuauUI.VERSION, "^(%d+)%.(%d+)%.(%d+)$")
		expect(major ~= nil).toBeTruthy()
		expect(tonumber(major)).toBe(0) -- pre-1.0: minor bumps may break with notice
		expect(tonumber(minor) :: number).toBeGreaterThanOrEqual(4) -- Phase 4 bump
		expect(patch ~= nil).toBeTruthy()
	end)

	it("the semver/deprecation ADR exists and states the policy", function()
		local adr = fs.readFile("docs/adr/ADR-0011-semver-and-deprecation.md")
		expect(string.find(adr, "MAJOR") ~= nil).toBeTruthy()
		expect(string.find(adr, "deprecat") ~= nil).toBeTruthy()
		expect(string.find(adr, LuauUI.VERSION, 1, true) ~= nil).toBeTruthy() -- ADR names the current version
	end)

	it("deprecations are a machine-readable ledger with the ADR's required fields", function()
		expect(type(LuauUI.DEPRECATIONS)).toBe("table")
		-- empty today; every future entry must carry the policy fields
		for _, entry in LuauUI.DEPRECATIONS :: { any } do
			expect(type(entry.surface)).toBe("string")
			expect(type(entry.since)).toBe("string")
			expect(type(entry.removeNoEarlierThan)).toBe("string")
			expect(type(entry.replacement)).toBe("string")
		end
	end)
end)
