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
-- THE COMPARISON DOCUMENT'S CITATION GATE
--
-- One document compares Facet with another user-interface framework, and it is
-- the only file in this repository allowed to name that framework. Claims about
-- OUR side are reconciled against the build by three checkers. Claims about the
-- other framework rested on memory until this gate, and a citation pass found
-- ten of them wrong, including a symbol that does not exist. Every wrong claim
-- had stood uncited. So the rule is mechanical: a verdict row naming that
-- framework carries a citation id, and an id resolves to a §16 row with a page,
-- a verbatim quote and a date. The vendor words in the fixtures below are match
-- data for that one document.
--
-- The rule cannot check that a quote is TRUE. That is the point of the shape of
-- these tests: each one proves the checker refuses a *missing* citation, never
-- that it can judge a real one.
-- ---------------------------------------------------------------------------

local PARITY = "docs/reference/swiftui-parity.md"

local GOOD_ROW = "| `zIndex` — SwiftUI controls the display order of overlapping views ([SW-01]) "
	.. "| **Covered** | a shared box prop | — |"
local GOOD_CITATION = "| **SW-01** | [`zIndex(_:)`](https://developer.apple.com/documentation/swiftui/view/zindex(_:)) "
	.. "| \u{201C}Controls the display order of overlapping views.\u{201D} | iOS 13+ | 2026-08-13 |"

-- A minimal parity document with the shape the checker reads: one verdict table
-- of claims, the two rows a concurrently-running task owns (which CITATION_EXEMPT
-- excuses, and which must therefore be present or the exemptions are stale), and
-- a §16 citation table.
local function parityFixture(claimRows: string, citationRows: string): string
	return table.concat({
		"# fixture",
		"",
		"| SwiftUI capability | Verdict | What Facet has | Evidence |",
		"|---|---|---|---|",
		claimRows,
		"",
		"| SwiftUI item | Verdict | What Facet has | Evidence |",
		"|---|---|---|---|",
		"| `Table.onPrimaryAction` (SwiftUI: the item-based context menu) | **Covered** | owned elsewhere | — |",
		"| Per-row capability opt-outs — SwiftUI's `selectionDisabled(_:)` | **Missing** | owned elsewhere | — |",
		"",
		"## 16. Citations — fixture",
		"",
		"Where a page says nothing, the row says Apple documents no behaviour here.",
		"",
		"| Id | Apple's page | The sentence the claim rests on | Availability | Checked |",
		"|---|---|---|---|---|",
		citationRows,
		"",
	}, "\n")
end

describe("documentation gate: every claim about the compared framework is cited", function()
	it("the live comparison document passes, and cites a substantial body of pages", function()
		local result = checker.check()
		if not result.ok then
			error("check_docs problems:\n  " .. table.concat(result.problems, "\n  "))
		end
		-- a floor, so a gutted §16 cannot pass by citing nothing
		expect(result.counts.citations).toBeGreaterThanOrEqual(100)
	end)

	it("passes on a minimal well-formed document (the fixture is not accidentally red)", function()
		local result = checker.check({
			fileOverrides = { [PARITY] = parityFixture(GOOD_ROW, GOOD_CITATION) },
		})
		if not result.ok then
			error("fixture should be clean:\n  " .. table.concat(result.problems, "\n  "))
		end
		expect(result.counts.citations).toBe(1)
	end)

	it("fails when a verdict row asserts something uncited about the compared framework", function()
		local uncited = "| `Grid` — SwiftUI sizes a column to its widest cell | **Covered** | ours | — |"
		local result = checker.check({
			fileOverrides = { [PARITY] = parityFixture(GOOD_ROW .. "\n" .. uncited, GOOD_CITATION) },
		})
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "asserts something about the compared framework with no citation")).toBe(1)
	end)

	it("fails when a cited id has no §16 row to resolve against", function()
		local dangling =
			"| `Layout` — SwiftUI's layout protocol defines geometry ([SW-42]) | **Missing** | — | — |"
		local result = checker.check({
			fileOverrides = { [PARITY] = parityFixture(GOOD_ROW .. "\n" .. dangling, GOOD_CITATION) },
		})
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "SW-42 is cited but §16 does not define it")).toBe(1)
	end)

	it("fails when a §16 row is defined but nothing cites it", function()
		local orphan = GOOD_CITATION
			.. "\n| **SW-77** | [`tint(_:)`](https://developer.apple.com/documentation/swiftui/view/tint(_:)) "
			.. "| \u{201C}Sets the tint color within this view.\u{201D} | iOS 15+ | 2026-08-13 |"
		local result = checker.check({ fileOverrides = { [PARITY] = parityFixture(GOOD_ROW, orphan) } })
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "SW-77 is defined in §16 but nothing cites it")).toBe(1)
	end)

	it("fails when a citation carries no vendor URL, no quote, or no date", function()
		local cases = {
			{
				citation = "| **SW-01** | `zIndex(_:)` | \u{201C}Controls the display order of overlapping views.\u{201D} "
					.. "| iOS 13+ | 2026-08-13 |",
				problem = "SW-01 has no developer.apple.com URL",
			},
			{
				citation = "| **SW-01** | [`zIndex(_:)`](https://developer.apple.com/documentation/swiftui/view/zindex(_:)) "
					.. "| it says roughly that overlapping views are ordered | iOS 13+ | 2026-08-13 |",
				problem = "SW-01 quotes nothing",
			},
			{
				citation = "| **SW-01** | [`zIndex(_:)`](https://developer.apple.com/documentation/swiftui/view/zindex(_:)) "
					.. "| \u{201C}Controls the display order of overlapping views.\u{201D} | iOS 13+ | recently |",
				problem = "SW-01 carries no ISO date",
			},
		}
		for _, case in cases do
			-- the anchor list still needs the convention date somewhere in the file
			local doc = parityFixture(GOOD_ROW, case.citation) .. "\nConvention: dates are ISO, e.g. 2026-08-13.\n"
			local result = checker.check({ fileOverrides = { [PARITY] = doc } })
			expect(result.ok).toBe(false)
			expect(problemsMentioning(result, case.problem)).toBe(1)
		end
	end)

	it("fails when an exemption stops matching, or when the row it excused gets cited", function()
		-- the row went away: the exemption is stale and must be deleted
		local noExemptRows = table.concat({
			"# fixture",
			"",
			"| SwiftUI capability | Verdict | What Facet has | Evidence |",
			"|---|---|---|---|",
			GOOD_ROW,
			"",
			"## 16. Citations — fixture",
			"",
			"Apple documents no behaviour here, where a page is silent.",
			"",
			"| Id | Apple's page | The sentence | Availability | Checked |",
			"|---|---|---|---|---|",
			GOOD_CITATION,
			"",
		}, "\n")
		local gone = checker.check({ fileOverrides = { [PARITY] = noExemptRows } })
		expect(gone.ok).toBe(false)
		expect(problemsMentioning(gone, "matches no row")).toBe(2)

		-- the debt was paid: the exempt row now carries a citation, so the
		-- exemption is the thing that is now wrong
		local cited = string.gsub(
			parityFixture(GOOD_ROW, GOOD_CITATION),
			"| `Table.onPrimaryAction` %(SwiftUI: the item%-based context menu%)",
			"| `Table.onPrimaryAction` (SwiftUI: the item-based context menu, [SW-01])",
			1
		)
		local paid = checker.check({ fileOverrides = { [PARITY] = cited } })
		expect(paid.ok).toBe(false)
		expect(problemsMentioning(paid, "now carries a citation")).toBe(1)
	end)

	it("fails when the parity document loses the citation convention itself", function()
		local result = checker.check({
			fileOverrides = { [PARITY] = "# parity\n\nNo citations, no §16, no dates.\n" },
		})
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "## 16. Citations")).toBeGreaterThanOrEqual(1)
		expect(problemsMentioning(result, "Apple documents no behaviour here")).toBeGreaterThanOrEqual(1)
	end)

	it("names the citation obligations in the CLI's --list output", function()
		local joined = table.concat(checker.OBLIGATIONS, "\n")
		for _, needle in { "[SW-nn]", "comparison document", "fixed words for a silent page", "CITATION_EXEMPT" } do
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
