--!strict
local harness = require("../lib/harness")
-- Registers the micro-screens and the a11y/l10n corpus in the main test loop.
-- Both are about what Facet's CONTROLS do; the core-conformance kit that used to
-- head this file certified a pluggable Core contract that no longer exists.

local t = require("../lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local microScreens = require("./micro_screens")
local a11yL10nCorpus = require("./a11y_l10n_corpus")
local customFactory = harness.coreFactory

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
