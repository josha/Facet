--!strict
-- THE DOCUMENTATION GATE (stage theme-packages-and-skinning, acceptance row
-- TP-A12). `lune run tools/lune/check_docs_cli` is the canonical command; this
-- spec runs the same checker the CLI runs, so a documentation drift fails the
-- SUITE and not only a command someone remembered to type.
--
-- Same shape as tests/extension_checker.spec.luau: assert the live repository is
-- green, then prove every rule actually bites by injecting synthetic drift. A
-- gate that has never been seen to fail is not evidence of anything.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local checker = require("../tools/lune/check_docs")

local function problemsMentioning(result: any, needle: string): number
	local n = 0
	for _, problem in result.problems :: { string } do
		if string.find(problem, needle, 1, true) ~= nil then
			n += 1
		end
	end
	return n
end

-- a stand-in API reference that satisfies every anchor EXCEPT the one under test
local function apiWithout(omitted: string): string
	local exports = { "define", "resolve", "neutralPackage", "neutral", "lintProperty", "checkCoverage", "SCHEMA" }
	local lines = { "# API", "### `themes`" }
	for _, name in exports do
		if name ~= omitted then
			table.insert(lines, `\`themes.{name}\` — documented.`)
		end
	end
	table.insert(lines, "theme_controller: install/swap/dumpTokens/inspect() — documented.")
	return table.concat(lines, "\n")
end

describe("documentation gate: the shipped theme surface and its docs agree", function()
	it("the live repository passes every documentation obligation", function()
		local result = checker.check()
		if not result.ok then
			error("check_docs problems:\n  " .. table.concat(result.problems, "\n  "))
		end
		expect(result.ok).toBe(true)
		expect(#result.problems).toBe(0)
		-- the counts double as a floor: a gutted checker cannot pass by checking nothing
		expect(result.counts.themeExports).toBeGreaterThanOrEqual(7)
		expect(result.counts.anchors).toBeGreaterThanOrEqual(68)
		expect(result.counts.links).toBeGreaterThanOrEqual(40)
		expect(result.counts.scenarioSteps).toBeGreaterThanOrEqual(24)
		expect(result.counts.documents).toBeGreaterThanOrEqual(8)
		expect(result.counts.examplePackages).toBeGreaterThanOrEqual(10)
		expect(result.counts.assets).toBeGreaterThanOrEqual(11)
	end)

	it("names every obligation it enforces (the CLI's --list output)", function()
		expect(#checker.OBLIGATIONS).toBeGreaterThanOrEqual(10)
		local joined = table.concat(checker.OBLIGATIONS, "\n")
		for _, needle in { "09-custom-themes.md", "new-theme.md", "api.md", "check_docs" } do
			expect(string.find(joined, needle, 1, true) ~= nil).toBe(true)
		end
	end)

	it("fails when the guide index stops linking the custom-theme chapter", function()
		local result = checker.check({
			fileOverrides = { ["docs/guide/README.md"] = "# Facet Guide\n\nNo chapter list here.\n" },
		})
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "does not link 09-custom-themes.md")).toBeGreaterThanOrEqual(1)
	end)

	it("fails when a required document is missing", function()
		for _, path in { "docs/guide/09-custom-themes.md", "docs/extending/new-theme.md" } do
			local result = checker.check({ missingFiles = { [path] = true } })
			expect(result.ok).toBe(false)
			expect(problemsMentioning(result, path)).toBeGreaterThanOrEqual(1)
		end
	end)

	it("fails when a public Facet.themes export is undocumented", function()
		local result = checker.check({ fileOverrides = { ["docs/reference/api.md"] = apiWithout("checkCoverage") } })
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "Facet.themes.checkCoverage' is not documented")).toBe(1)
	end)

	it("fails when a guide stops naming the surface it teaches", function()
		local result = checker.check({
			fileOverrides = { ["docs/guide/09-custom-themes.md"] = "# 9. Custom themes\n\nNothing to see.\n" },
		})
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "no longer mentions 'chromeCensus'")).toBe(1)
		expect(problemsMentioning(result, "no longer mentions 'theme_sync_cli'")).toBe(1)
		expect(problemsMentioning(result, "no longer mentions 'checkCoverage'")).toBe(1)
	end)

	it("fails when the walkthrough's worked example stops using the public API", function()
		local result = checker.check({
			fileOverrides = {
				["examples/themes/fantasy_parchment.luau"] = "local internal = require('../../src/tokens/sheet_model')\n",
			},
		})
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "no longer calls 'themes.define'")).toBe(1)
		expect(problemsMentioning(result, "no longer calls 'neutralPackage'")).toBe(1)
	end)

	it("fails when an example package or its art/provenance disappears", function()
		for _, path in
			{
				"examples/themes/scifi_hud.luau",
				"assets/themes/fantasy-parchment/parchment_panel.png",
				"assets/themes/fantasy-parchment/provenance.md",
				"assets/themes/fantasy-parchment/upload-manifest.json",
			}
		do
			local result = checker.check({ missingFiles = { [path] = true } })
			expect(result.ok).toBe(false)
			expect(problemsMentioning(result, path)).toBeGreaterThanOrEqual(1)
		end
	end)

	it("fails when the upload manifest and the package disagree about a content ID", function()
		local result = checker.check({
			fileOverrides = {
				["assets/themes/fantasy-parchment/upload-manifest.json"] = '{ "assets": { "ghost": { "contentId": "rbxassetid://1234567890" } } }',
			},
		})
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "rbxassetid://1234567890 is not used")).toBe(1)
	end)

	it("fails when a local link in a new document points at nothing", function()
		local result = checker.check({
			fileOverrides = {
				["docs/extending/new-theme.md"] = "# Playbook\n\nSee [gone](../guide/99-nonexistent.md).\n",
			},
		})
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "docs/guide/99-nonexistent.md")).toBe(1)
	end)

	it("fails when the styling guide goes back to calling the contract unshipped", function()
		local result = checker.check({
			fileOverrides = {
				["docs/guide/05-styling.md"] = "# 5. Styling\n\nThe planned Step 3.5 adds a public versioned theme package.\n"
					.. "See 09-custom-themes.md and themeMetrics.\n",
			},
		})
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "The planned Step 3.5 adds")).toBe(1)
	end)

	it("fails when a scenario step the guide teaches no longer exists", function()
		local result = checker.check({
			fileOverrides = {
				["examples/gallery/scenarios/theme_authoring.luau"] = "return { steps = { inspect = function() end } }\n",
			},
		})
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "step 'editMetricLive' no longer exists")).toBe(1)
		expect(problemsMentioning(result, "step 'failMissingAsset' no longer exists")).toBe(1)
		-- ...and the rich-skinning chapter's own steps, from the same gutted file
		expect(problemsMentioning(result, "step 'layerCensus' no longer exists")).toBe(1)
		expect(problemsMentioning(result, "step 'gaugeCoverage' no longer exists")).toBe(1)
	end)
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- RICH SKINNING v2 (ADR-0020 R8, ledger row RS-A15). The v2 surface added a
-- chapter, a contributor playbook, a worked control and that control's own art,
-- and every one of them can rot independently of the Step 3.5 set above. Same
-- discipline: prove each new rule BITES rather than trusting that it exists.
-- ─────────────────────────────────────────────────────────────────────────────
describe("documentation gate: the rich-skinning surface and its docs agree", function()
	it("names the v2 obligations in the CLI's --list output", function()
		local joined = table.concat(checker.OBLIGATIONS, "\n")
		for _, needle in { "10-rich-skinning.md", "skinned-control.md", "ornate_gauge.luau", "OrnateGauge", "selectBy" } do
			expect(string.find(joined, needle, 1, true) ~= nil).toBe(true)
		end
	end)

	it("fails when the guide index stops linking the rich-skinning chapter", function()
		local result = checker.check({
			fileOverrides = {
				["docs/guide/README.md"] = "# Facet Guide\n\n| [`09-custom-themes.md`](09-custom-themes.md) | … |\n",
			},
		})
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "does not link 10-rich-skinning.md")).toBe(1)
	end)

	it("fails when either v2 document is missing", function()
		for _, path in { "docs/guide/10-rich-skinning.md", "docs/extending/skinned-control.md" } do
			local result = checker.check({ missingFiles = { [path] = true } })
			expect(result.ok).toBe(false)
			expect(problemsMentioning(result, path)).toBeGreaterThanOrEqual(1)
		end
	end)

	it("fails when the rich-skinning chapter stops naming a v2 capability", function()
		local result = checker.check({
			fileOverrides = { ["docs/guide/10-rich-skinning.md"] = "# 10. Rich skinning\n\nNothing to see.\n" },
		})
		expect(result.ok).toBe(false)
		-- one per capability the chapter exists to teach
		for _, term in { "selectBy", "barFill", "stepperPlate", "pixelUnit", "iconSizes", "MAX_LAYERS", "UI.gradient" } do
			expect(problemsMentioning(result, `no longer mentions '{term}'`)).toBe(1)
		end
	end)

	it("fails when the rung-3 playbook stops naming the contribution contract", function()
		local result = checker.check({
			fileOverrides = { ["docs/extending/skinned-control.md"] = "# Playbook\n\nWrite a control.\n" },
		})
		expect(result.ok).toBe(false)
		for _, term in { "checkCoverage", "ns:role", "provenance.md", "presentGaugeFixture" } do
			expect(problemsMentioning(result, `no longer mentions '{term}'`)).toBe(1)
		end
	end)

	it("fails when the rung-3 example stops going through the public contract", function()
		local result = checker.check({
			fileOverrides = { ["examples/themes/ornate_gauge.luau"] = "local gauge = {}\nreturn gauge\n" },
		})
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "no longer uses 'checkCoverage'")).toBe(1)
	end)

	it("fails when the rung-3 example REQUIRES anything — a clean consumer takes arguments", function()
		local result = checker.check({
			fileOverrides = {
				["examples/themes/ornate_gauge.luau"] = "local chrome = require('../../src/tokens/chrome_slots')\n"
					.. "-- needs, resolve, checkCoverage all still named\n",
			},
		})
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "contains a `require(`")).toBe(1)
	end)

	it("fails when the CONTROL's own art, generator, provenance or manifest disappears", function()
		for _, path in
			{
				"assets/themes/ornate-gauge/gauge_face.png",
				"assets/themes/ornate-gauge/gauge_needle.png",
				"assets/themes/ornate-gauge/source/generate_art.py",
				"assets/themes/ornate-gauge/provenance.md",
				"assets/themes/ornate-gauge/upload-manifest.json",
			}
		do
			local result = checker.check({ missingFiles = { [path] = true } })
			expect(result.ok).toBe(false)
			expect(problemsMentioning(result, path)).toBeGreaterThanOrEqual(1)
			-- the owner is DERIVED from the manifest now (MAINT-8d), so the message
			-- names the control and the manifest that registered it rather than a
			-- hardcoded phrase about the one worked example
			expect(problemsMentioning(result, "OrnateGauge (a skinned control's own art")).toBeGreaterThanOrEqual(1)
		end
	end)

	it("fails when the control's manifest and the control disagree about a content ID", function()
		local result = checker.check({
			fileOverrides = {
				["assets/themes/ornate-gauge/upload-manifest.json"] = '{ "assets": { "ghost": { "contentId": "rbxassetid://9876543210" } } }',
			},
		})
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "rbxassetid://9876543210 is not used")).toBe(1)
	end)

	it("fails when a document goes back to describing the v2 surface as unshipped", function()
		local result = checker.check({
			fileOverrides = {
				["docs/guide/09-custom-themes.md"] = "# 9\n\nThere are nine **decoration slots**, and the list is closed:\n"
					.. "### States are tints, not more art\n",
			},
		})
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "There are nine **decoration slots**")).toBe(1)
		expect(problemsMentioning(result, "States are tints, not more art")).toBe(1)
	end)

	it("fails when the chapter goes back to calling the per-view gradient unshipped", function()
		-- the charter's cap 11 says views may apply shadow AND gradient modifiers.
		-- Both ship; a document that reverts to the interim "there is no per-view
		-- gradient" wording is describing a build that no longer exists.
		local result = checker.check({
			fileOverrides = {
				["docs/guide/10-rich-skinning.md"] = "# 10\n\nThere is no per-view gradient.\n",
			},
		})
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "There is no per-view gradient")).toBe(1)
	end)

	it("fails when a local link in either v2 document points at nothing", function()
		local result = checker.check({
			fileOverrides = {
				["docs/guide/10-rich-skinning.md"] = "# 10\n\nSee [gone](../guide/99-nope.md).\n",
			},
		})
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "docs/guide/99-nope.md")).toBe(1)
	end)
end)

-- ---------------------------------------------------------------------------
-- A COMPARISON DOCUMENT'S SOURCING GATE
--
-- Facet explains itself in Facet and Roblox terms. One kind of document is
-- exempt: a comparison written for a reader who already knows another library.
-- Claims about OUR side are reconciled against the build by three checkers.
-- Claims about the other libraries rested on memory until this gate, and a
-- citation pass over the comparison this repository used to carry found TEN of
-- them wrong, including a symbol that does not exist. Every wrong claim had
-- stood with nothing for a reader to open.
--
-- THE PATH IS NOT THE CONTRACT (2026-08-30). That document was product research
-- and has been archived out of this repository (docs/plans/distribution-
-- readiness.md, "Private research and public framework choice"). The rule
-- outlived it: `COMPARISON_DOCS` in tools/lune/check_docs.luau is the list, and
-- the four rules below are what a listed document that EXISTS is held to.
--
-- These cases drive the checker through `fileOverrides` rather than against
-- whatever is on disk, so the machinery is proven to bite on its own terms —
-- on this tree and on a tree where no comparison document has landed yet.
--
-- The rule cannot check that a source SAYS what the document claims. That is
-- the point of the shape of these tests: each proves the checker refuses a
-- *missing* source, a *missing* date, a *missing* pin or a *missing* label,
-- never that it can judge a real one.
-- ---------------------------------------------------------------------------

local COMPARISON = "docs/guide/14-choosing-a-ui-library.md"

-- The shape all four rules read: a table of claims, a sources table pinning
-- each project with a URL, a research date, and the inference label.
local function comparisonFixture(overrides: { [string]: string }?): string
	local o = overrides or {}
	local date = o.date or "Fetched 2026-08-30."
	local pin = o.pin or "Each project is pinned to the version, tag or commit current on that date."
	local label = o.label or "`[INFERENCE]` — a conclusion drawn from those facts."
	local vide = o.vide or "| Vide | release `0.4.1` | <https://centau.github.io/vide/> |"
	return table.concat({
		"# fixture",
		"",
		label,
		"",
		"| | Facet | React | Fusion | Vide |",
		"|---|---|---|---|---|",
		"| **Cleanup** | scopes | `useEffect` returns a cleanup | `doCleanup()` | `root()` returns a destructor |",
		"",
		"## Sources",
		"",
		date,
		pin,
		"",
		"| Project | Pinned to | Source |",
		"|---|---|---|",
		"| React | tag `v17.1.3` | <https://github.com/Roblox/react-luau> |",
		"| Fusion | release `v0.3-beta` | <https://elttob.uk/Fusion/0.3/> |",
		vide,
		"",
	}, "\n")
end

describe("documentation gate: a comparison document sources what it compares against", function()
	it("the live tree's comparison document passes, and an absent one is not an error", function()
		local result = checker.check()
		-- Scoped to THIS gate on purpose: this spec proves the sourcing rules,
		-- and an unrelated red elsewhere in check_docs must not be reported here
		-- as if the comparison document caused it.
		if problemsMentioning(result, COMPARISON) ~= 0 then
			error("comparison document problems:\n  " .. table.concat(result.problems, "\n  "))
		end
		-- the count is reported, so a section that read nothing is visible
		-- rather than indistinguishable from a section that passed
		expect(typeof(result.counts.comparisonDocs)).toBe("number")
	end)

	it("passes on a minimal well-formed document, and reports that it read it", function()
		local result = checker.check({ fileOverrides = { [COMPARISON] = comparisonFixture() } })
		if problemsMentioning(result, COMPARISON) ~= 0 then
			error("fixture should be clean:\n  " .. table.concat(result.problems, "\n  "))
		end
		expect(result.counts.comparisonDocs).toBe(1)
		-- one per framework the fixture names and sources
		expect(result.counts.citations).toBe(3)
	end)

	it("fails when a framework it compares against carries no source URL", function()
		local unsourced = comparisonFixture({ vide = "| Vide | release `0.4.1` | the website |" })
		local result = checker.check({ fileOverrides = { [COMPARISON] = unsourced } })
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "compares against 'Vide' but no line naming it carries a source URL")).toBe(1)
	end)

	it("fails when the comparison carries no ISO research date", function()
		local undated = comparisonFixture({ date = "Fetched recently." })
		local result = checker.check({ fileOverrides = { [COMPARISON] = undated } })
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "carries no ISO research date")).toBe(1)
	end)

	it("fails when the comparison pins no version, tag or commit", function()
		local unpinned = comparisonFixture({
			pin = "Each project is pinned to whatever was current on that date.",
			vide = "| Vide | the current one | <https://centau.github.io/vide/> |",
		})
		-- the other two rows still carry pin words, so strip them too
		unpinned = string.gsub(unpinned, "tag `v17%.1%.3`", "the newest one")
		unpinned = string.gsub(unpinned, "release `v0%.3%-beta`", "the newest one")
		local result = checker.check({ fileOverrides = { [COMPARISON] = unpinned } })
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "pins no version, tag or commit")).toBe(1)
	end)

	it("fails when the comparison never marks a claim as an inference", function()
		local unlabelled = comparisonFixture({ label = "Every claim below is stated by a pinned source." })
		local result = checker.check({ fileOverrides = { [COMPARISON] = unlabelled } })
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "never marks a claim as 'inference'")).toBe(1)
	end)

	it("names the sourcing obligations in the CLI's --list output", function()
		local joined = table.concat(checker.OBLIGATIONS, "\n")
		for _, needle in { "comparison document", "source URL", "ISO research date", "version, tag or commit" } do
			expect(string.find(joined, needle, 1, true) ~= nil).toBe(true)
		end
	end)
end)

--[[ THE CAPABILITY CATALOG (wave T12).

	docs/guide/README.md is where a Roblox developer who has never seen this
	repository finds out what the library can do. The plan's "public guide
	completeness" rule says that index must name every capability that ships and
	nothing that does not, so the checker compares it against the LIVE exported
	table rather than against prose. These cases prove all four directions bite:
	a missing capability, an invented one, a broken API-reference link, and an
	unlinked extension playbook. ]]
local fs = require("@lune/fs")

local INDEX = "docs/guide/README.md"

describe("the guide index catalogs the live public surface", function()
	local index = fs.readFile(INDEX)

	it("counts a catalog entry for every namespace member, export and playbook", function()
		local result = checker.check()
		expect(result.ok).toBe(true)
		-- floor, not a pin: 19 controls + 51 UI members + the top-level exports
		-- + the seven extension playbooks. A gutted check cannot pass by
		-- checking nothing.
		expect(result.counts.catalogEntries).toBeGreaterThanOrEqual(100)
	end)

	it("fails when the catalog stops naming a shipped control", function()
		local dropped = string.gsub(index, "| `Controls%.Chip` |[^\n]*\n", "", 1)
		expect(dropped ~= index).toBe(true)
		local result = checker.check({ fileOverrides = { [INDEX] = dropped } })
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "does not name 'Controls.Chip'")).toBe(1)
	end)

	it("fails when the catalog advertises something the library does not export", function()
		local invented = string.gsub(index, "| `UI%.Screen` |", "| `UI.Sparkle` | `UI.Screen` |", 1)
		expect(invented ~= index).toBe(true)
		local result = checker.check({ fileOverrides = { [INDEX] = invented } })
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "names 'UI.Sparkle', which the library no longer exports")).toBe(1)
	end)

	--[[ THE THREE HOLES THE RE-REVIEW FOUND. Direction (b) used to scan for a
		dotted `UI.x`/`Controls.x` token anywhere in the file, so an invented
		TOP-LEVEL export, an invented member of any OTHER namespace, and an
		invented `client.*` row all lingered with no error. It now reads the
		capability COLUMN of every catalog row, which is the bound that lets it
		judge a bare name as a claim rather than as prose. ]]
	it("fails when the catalog invents a top-level export", function()
		local invented = string.gsub(index, "| `mount` |", "| `newSparkle` | `mount` |", 1)
		expect(invented ~= index).toBe(true)
		local result = checker.check({ fileOverrides = { [INDEX] = invented } })
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "names 'newSparkle', which the library no longer exports")).toBe(1)
	end)

	it("fails when the catalog invents a member of a namespace that is not UI or Controls", function()
		local invented = string.gsub(index, "| `adaptive` |", "| `adaptive.nope` | `adaptive` |", 1)
		expect(invented ~= index).toBe(true)
		local result = checker.check({ fileOverrides = { [INDEX] = invented } })
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "names 'adaptive.nope', which the library no longer exports")).toBe(1)
	end)

	it("fails when the catalog invents a client module row", function()
		local invented = string.gsub(index, "| `client%.host` |", "| `client.nope_target` | `client.host` |", 1)
		expect(invented ~= index).toBe(true)
		local result = checker.check({ fileOverrides = { [INDEX] = invented } })
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "names 'client.nope_target', which the library no longer exports")).toBe(1)
	end)

	it("fails when a catalog row links an API-reference heading that does not exist", function()
		local broken = string.gsub(index, "api%.md#screen%)", "api.md#no-such-heading)", 1)
		expect(broken ~= index).toBe(true)
		local result = checker.check({ fileOverrides = { [INDEX] = broken } })
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "api.md#no-such-heading, which is not a heading")).toBe(1)
	end)

	it("fails when an extension playbook is not linked from the index", function()
		local unlinked = string.gsub(index, "%.%./extending/new%-primitive%.md", "../extending/nope.md", 1)
		expect(unlinked ~= index).toBe(true)
		local result = checker.check({ fileOverrides = { [INDEX] = unlinked } })
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "does not link new-primitive.md")).toBe(1)
	end)
end)
