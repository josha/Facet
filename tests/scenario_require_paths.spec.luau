--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness, tier: string)
	local expect = Verify.expect

	local checker = require("../tools/lune/check_scenario_requires")

	local KNOWN_BAD_FILE = "examples/gallery/scenarios/adaptive_controls.luau"

	verifyHarness:suite("scenario_require_paths: every gallery/scenario/reference require resolves live", function()
		verifyHarness:case("the shipped tree is clean", {
			id = "scenario_require_paths::scenario_require_paths: every gallery/scenario/reference require resolves live::the shipped tree is clean",
			run = function()
				local result = checker.check()
				local detail = if result.ok
					then ""
					else "\n" .. table.concat(
						(function()
							local lines = {}
							for _, v in result.violations do
								table.insert(lines, `{v.file} ({v.scriptPath}): require("{v.require}") — {v.reason}`)
							end
							return lines
						end)(),
						"\n"
					)
				expect(result.ok and true or error(`scenario require guard FAILED:{detail}`, 2)):toBe(true)
			end,
		})

		verifyHarness:case("it actually scanned the real tree, not an empty one", {
			id = "scenario_require_paths::scenario_require_paths: every gallery/scenario/reference require resolves live::it actually scanned the real tree, not an empty one",
			run = function()
				local result = checker.check()
				expect(result.counts.files >= 100):toBe(true)
				local injected = checker.check({
					injectFile = KNOWN_BAD_FILE,
					injectLine = 'local first = require("./common")\nlocal second = require("./common")',
				})
				expect(injected.counts.requiresChecked):toBe(result.counts.requiresChecked + 2)
			end,
		})

		verifyHarness:case("catches the exact historical defect: a module-scope 3-level escape into src", {
			id = "scenario_require_paths::scenario_require_paths: every gallery/scenario/reference require resolves live::catches the exact historical defect: a module-scope 3-level escape into src",
			run = function()
				local result = checker.check({
					injectFile = KNOWN_BAD_FILE,
					injectLine = 'local mutationProbe = require("../../../src/tokens/chrome_slots")',
				})
				expect(result.ok):toBe(false)
				local found = false
				for _, v in result.violations do
					if v.file == KNOWN_BAD_FILE and v.require == "../../../src/tokens/chrome_slots" then
						found = true
					end
				end
				expect(found):toBe(true)
			end,
		})

		verifyHarness:case("does NOT fire on the same literal string used inside the SAFE dual-route idiom", {
			id = "scenario_require_paths::scenario_require_paths: every gallery/scenario/reference require resolves live::does NOT fire on the same literal string used inside the SAFE dual-route idiom",
			run = function()
				local result = checker.check({
					injectFile = KNOWN_BAD_FILE,
					injectLine = 'local function mutationProbe()\n\tlocal ok, mod = pcall(function()\n\t\treturn require("../../../src/tokens/chrome_slots")\n\tend)\n\treturn ok and mod or nil\nend',
				})
				expect(result.ok):toBe(true)
			end,
		})

		verifyHarness:case("a require with no relative path component is never flagged", {
			id = "scenario_require_paths::scenario_require_paths: every gallery/scenario/reference require resolves live::a require with no relative path component is never flagged",
			run = function()
				local result = checker.check({
					injectFile = KNOWN_BAD_FILE,
					injectLine = 'local mutationProbe = require(game:GetService("ReplicatedStorage").Facet.tokens.chrome_slots)',
				})
				expect(result.ok):toBe(true)
			end,
		})
	end)
end
