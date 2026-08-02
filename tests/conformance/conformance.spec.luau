--!strict
-- Registers the conformance suite + micro-screens against the CUSTOM core in
-- the main test loop: the reference implementation must pass every check on
-- every ./run-tests.sh. Candidate scorecards (fusion/imperative) come from
-- tests/conformance/cli.luau, which runs the same checks without asserting.

local t = require("../lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local suite = require("./suite")
local microScreens = require("./micro_screens")
local a11yL10nCorpus = require("./a11y_l10n_corpus")
local customFactory = require("../../src/core/custom")

describe("core conformance (custom)", function()
	for _, check in suite do
		it(`{check.name} [{check.requirement}]`, function()
			local ok, note = check.run(customFactory.new())
			if not ok then
				print(`    note: {note}`)
			end
			expect(ok).toBe(true)
		end)
	end
end)

describe("micro-screens (custom)", function()
	for _, check in microScreens do
		it(`{check.name} [{check.requirement}]`, function()
			local ok, note = check.run(customFactory.new())
			if not ok then
				print(`    note: {note}`)
			end
			expect(ok).toBe(true)
		end)
	end
end)

describe("a11y/l10n corpus (custom)", function()
	for _, check in a11yL10nCorpus.checks do
		it(`{check.name} [{check.requirement}]`, function()
			local ok, note = check.run(customFactory.new())
			if not ok then
				print(`    note: {note}`)
			end
			expect(ok).toBe(true)
		end)
	end
end)
