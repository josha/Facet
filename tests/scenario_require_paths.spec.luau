--!strict
--[[ Headless-vs-instance-tree require guard (SHOWCASE2 task A). The "All
	controls" demo mounted EMPTY at Play: `examples/gallery/scenarios/
	adaptive_controls.luau` carried a module-scope `require("../../../src/
	tokens/chrome_slots")` that resolved under Lune (file-system path, this
	suite green throughout) but not live in Studio, where `src` and `examples/
	gallery/scenarios` are SIBLING trees under `ReplicatedStorage`, not nested
	(measured: `could not get parent of component ".."`). This is the SECOND
	headless-vs-instance-tree require divergence this campaign (G7+G11's Rojo
	mount-depth was the first, ADR-0048) — `tools/lune/check_scenario_requires.
	luau` closes the CLASS rather than just the one site: it re-derives, for
	every gallery/scenario/reference file, what the live Studio instance tree
	actually looks like (`tools/lune/lib/studio_tree.luau`, the SAME module
	`studio_sync` serves from) and proves every module-scope relative
	`require("...")` string actually lands on a node that exists there.

	Two more live instances of the identical bug were found and fixed the same
	round: `nested_compositing.luau` (`transform_footprint`) and `examples/
	reference/p4_foyer/init.luau` (`chrome_slots`) — both RED before the fix,
	confirmed by re-running this exact checker against the pre-fix source
	(recorded in task-showcase2-report.md, not re-asserted here since the
	fixed tree is what ships).
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local checker = require("../tools/lune/check_scenario_requires")

local KNOWN_BAD_FILE = "examples/gallery/scenarios/adaptive_controls.luau"

describe("scenario_require_paths: every gallery/scenario/reference require resolves live", function()
	it("the shipped tree is clean", function()
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
		expect(result.ok and true or error(`scenario require guard FAILED:{detail}`, 2)).toBe(true)
	end)

	it("it actually scanned the real tree, not an empty one", function()
		local result = checker.check()
		expect(result.counts.files >= 100).toBe(true)
		expect(result.counts.requiresChecked >= 50).toBe(true)
	end)

	--[[ THE MUTATION PROOF. A guard nobody has watched fail is a guard nobody
		knows works (same standing bar `check_example_drift`'s own negative
		controls set). This re-injects the EXACT historical defect — a module-
		scope require reaching from FacetScenarios three levels up into `src` —
		and requires the guard to name it. ]]
	it("catches the exact historical defect: a module-scope 3-level escape into src", function()
		local result = checker.check({
			injectFile = KNOWN_BAD_FILE,
			injectLine = 'local mutationProbe = require("../../../src/tokens/chrome_slots")',
		})
		expect(result.ok).toBe(false)
		local found = false
		for _, v in result.violations do
			if v.file == KNOWN_BAD_FILE and v.require == "../../../src/tokens/chrome_slots" then
				found = true
			end
		end
		expect(found).toBe(true)
	end)

	it("does NOT fire on the same literal string used inside the SAFE dual-route idiom", function()
		-- the established idiom (`resolveAdapterModule`/`resolveChromeSlots`)
		-- keeps this exact string as its Lune-only fallback route, indented
		-- inside a pcall — the guard must tell that apart from an unguarded
		-- module-scope require, or it would break the very idiom it exists to
		-- push authors toward.
		local result = checker.check({
			injectFile = KNOWN_BAD_FILE,
			injectLine = 'local function mutationProbe()\n\tlocal ok, mod = pcall(function()\n\t\treturn require("../../../src/tokens/chrome_slots")\n\tend)\n\treturn ok and mod or nil\nend',
		})
		expect(result.ok).toBe(true)
	end)

	it("a require with no relative path component is never flagged", function()
		local result = checker.check({
			injectFile = KNOWN_BAD_FILE,
			injectLine = 'local mutationProbe = require(game:GetService("ReplicatedStorage").Facet.tokens.chrome_slots)',
		})
		expect(result.ok).toBe(true)
	end)
end)
