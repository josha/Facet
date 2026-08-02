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
			fileOverrides = { ["docs/guide/README.md"] = "# LuauUI Guide\n\nNo chapter list here.\n" },
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

	it("fails when a public LuauUI.themes export is undocumented", function()
		local result = checker.check({ fileOverrides = { ["docs/reference/api.md"] = apiWithout("checkCoverage") } })
		expect(result.ok).toBe(false)
		expect(problemsMentioning(result, "LuauUI.themes.checkCoverage' is not documented")).toBe(1)
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
				["docs/guide/README.md"] = "# LuauUI Guide\n\n| [`09-custom-themes.md`](09-custom-themes.md) | … |\n",
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
			expect(problemsMentioning(result, "OrnateGauge (the rung-3 control's own art)")).toBeGreaterThanOrEqual(1)
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
