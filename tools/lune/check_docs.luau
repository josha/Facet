--!strict
-- Documentation checker for the theme surface (ADR-0019 §"Documentation and one
-- canonical command"; stage theme-packages-and-skinning, row TP-A12). Fails when
-- the shipped theme surface and the documents that describe it have drifted:
--
--   1. the guide index links the custom-theme chapter, and both new documents
--      exist (an unlinked chapter is a chapter nobody finds);
--   2. every public `Facet.themes` export is documented in the API reference —
--      read out of src/init.luau, never a hardcoded list, so a new export is
--      undocumented the moment it lands;
--   3. each document still NAMES the tools it teaches (theme_sync_cli,
--      theme_controller, chromeCensus, checkCoverage, …): a grep anchor is a
--      cheap proxy for "this section was not silently gutted";
--   4. the Fantasy Parchment walkthrough points at a file that exists and still
--      builds through the public API (themes.define + neutralPackage);
--   5. the example packages, the art, its provenance and its upload manifest
--      exist — and the manifest's content IDs still match the package's;
--   6. every LOCAL link in the two new documents resolves to a real path;
--   7. stale language: the styling guide may not still call the package
--      contract unshipped;
--   8. every scenario step the guide teaches still exists in the scenario;
--   9. the comparison document (the one file allowed to name another
--      framework) backs every claim about that framework: each verdict row
--      carries a citation id, and every id resolves to a §16 row with the
--      vendor's page URL, a verbatim quote (or the document's own words for a
--      page that says nothing) and the date it was read;
--  10. the guide index catalogs the live public surface: it names every member
--      of the UI and Controls namespaces and every non-retired export, names
--      nothing that has stopped existing, links only api.md headings that
--      exist, and links every extension playbook.
--
-- check(opts?) -> { ok, problems, counts }. `opts` injects synthetic drift for
-- the checker's own tests (tests/theme_docs.spec.luau) — the same shape
-- check_registration uses. CLI: tools/lune/check_docs_cli.luau (read-only).
--
-- There are no generated blocks in this document set: every line is a human
-- explanation, so the CLI's --write has nothing to regenerate and says so.

local fs = require("@lune/fs")

--[[ THE LIVE LIBRARY TABLE, not a parsed literal.

	The capability catalog below asks "does the guide index name everything the
	library exports". The only honest source for "everything the library
	exports" is the exported table itself, so this module requires it the same
	way tools/lune/check_registration does. A hand list here would be one more
	place a new export could fail to appear. ]]
local liveFacet = require("../../src") :: any

local check_docs = {}

local GUIDE_INDEX = "docs/guide/README.md"
local GUIDE = "docs/guide/09-custom-themes.md"
local PLAYBOOK = "docs/extending/new-theme.md"
local API = "docs/reference/api.md"
local STYLING = "docs/guide/05-styling.md"
-- chapter 1 introduces `UI.Button`, so it is where the circle Button is taught
local CONCEPTS = "docs/guide/01-concepts.md"
local WORKED_EXAMPLE = "examples/themes/fantasy_parchment.luau"
local SCENARIO = "examples/gallery/scenarios/theme_authoring.luau"
local INIT = "src/init.luau"
local ASSET_DIR = "assets/themes/fantasy-parchment"
local MANIFEST = ASSET_DIR .. "/upload-manifest.json"

-- ---- rich skinning v2 (ADR-0020, stage rich-skinning-v2 row RS-A15) --------
-- The v2 surface has its own chapter and its own contributor playbook, and the
-- rung-3 example ships ART, so it owes the same provenance obligations a theme
-- package's art does. Same drift-alarm discipline: few anchors, each one
-- load-bearing, each naming a shipped thing that would be silently lost.
--[[ ---- the theme CATALOG (wave THEME-UNBUNDLE, 2026-08-21) ----------------
	The eight reference packages became separate distribution artifacts
	(`tools/build_themes.sh` -> `build/themes/<Name>.rbxm`), so a consumer's first
	theme question stopped being "how do I write one" and became "which one do I
	take". The catalog answers it, and the obligations below are the ones a
	catalog rots by failing: a package that ships and is not listed, a listed
	package that no longer ships, and an install route nobody can follow.
	The per-package list is DERIVED from the enumerator rather than typed here. ]]
local CATALOG = "docs/guide/13-theme-catalog.md"

local RICH_GUIDE = "docs/guide/10-rich-skinning.md"
local RUNG3_PLAYBOOK = "docs/extending/skinned-control.md"
local RUNG3_EXAMPLE = "examples/themes/ornate_gauge.luau"
local RUNG3_ASSET_DIR = "assets/themes/ornate-gauge"
local RUNG3_MANIFEST = RUNG3_ASSET_DIR .. "/upload-manifest.json"

-- ---- the framework's OWN icon set (stage compact-label) --------------------
-- The first art in this repository that belongs to the LIBRARY rather than to a
-- theme package, so it sits outside `assets/themes/` and outside every check
-- that was written for one. It owes exactly the obligations a package's art
-- owes -- a generator, a provenance note and a manifest that agrees with the
-- source that references the ids -- because a framework set that nothing checks
-- is a set that rots, and its failure mode is silent: an id that drifts is a
-- picture that simply never appears under every package that did not opt out.
local ICON_ASSET_DIR = "assets/icons"
local ICON_MANIFEST = ICON_ASSET_DIR .. "/upload-manifest.json"
local ICON_REGISTRY = "src/themes/standard_icons.luau"

-- Anchors: a term the document must still contain, and the action to take when
-- it does not. Deliberately few and load-bearing — this is a drift alarm, not a
-- style guide.
type Anchor = { term: string, why: string }

local GUIDE_ANCHORS: { Anchor } = {
	{ term = "themes.define", why = "the compiler the walkthrough starts from" },
	{ term = "neutralPackage", why = "deriving from Studio Neutral is step 1 of the walkthrough" },
	{ term = "theme_controller", why = "installing at an application root" },
	{ term = "theme_sync_cli", why = "the validate/export step and its --check freshness gate" },
	{ term = "--check", why = "the freshness gate the export step must teach" },
	{ term = "dumpTokens", why = "the dump theme_sync_cli consumes" },
	{ term = "chromeCensus", why = "the ornate-cost profiling step" },
	{ term = "checkCoverage", why = "shipping a custom control alongside a theme" },
	{ term = "sliceCenter", why = "nine-slice geometry is the centrepiece of the chrome step" },
	{ term = "contentInsets", why = "the solver-visible inset the chrome step declares" },
	{ term = "facet-chrome-fallback", why = "the asset-failure fallback the chrome step promises" },
	{ term = "FacetChromeText", why = "the chrome text lift a Button author must design around" },
	{ term = "facet-chrome-editing", why = "the TextBox editing yield" },
	{ term = WORKED_EXAMPLE, why = "Fantasy Parchment is THE worked example" },
	{ term = "provenance.md", why = "the art/import/content-ID story" },
}

local PLAYBOOK_ANCHORS: { Anchor } = {
	{ term = "lintProperty", why = "the property-authority section" },
	{ term = "checkCoverage", why = "the namespaced-contribution gate" },
	{ term = "::UICorner", why = "the pseudo-selector allowlist" },
	{ term = "::UIStroke", why = "the pseudo-selector allowlist" },
	{ term = "::UIGradient", why = "the pseudo-selector allowlist" },
	{ term = "::UIShadow", why = "the inert selector the allowlist exists to reject (TP-M7)" },
	{ term = "facet-theme/1", why = "the schema/version migration duties" },
	{ term = "provenance.md", why = "the asset provenance obligation" },
	{ term = "theme_authoring", why = "the Studio evidence obligation" },
	{ term = "check_docs_cli", why = "the gate obligations must name the canonical command" },
	{ term = "acceptance-ledger.md", why = "the ledger must be named (and never edited)" },
}

-- Chapter 10 must still NAME every v2 capability it exists to teach. Each of
-- these is a surface a package author cannot discover any other way, so a
-- section quietly deleted from the chapter is a capability that becomes
-- undocumented while the build still ships it.
local RICH_GUIDE_ANCHORS: { Anchor } = {
	{ term = 'kind = "layered"', why = "layer stacks are §10.1's whole subject" },
	{ term = "MAX_LAYERS", why = "the bounded-stack cap the census exists to police" },
	{ term = "corners", why = "the layer kind whose declaration is FOUR instances" },
	{ term = "plaque", why = "the overhanging header layer kind" },
	{ term = "tile", why = "the tiled layer kind (rs-m1's verdict shipped)" },
	{
		term = "inset = { x",
		why = "the full-bleed inset (director round 5b) — the one field fill/frame/tile share, "
			.. "and the reason a repeating texture can stop short of a rounded plate's corners",
	},
	{
		term = 'mask = "pill"',
		why = "the full-bleed mask (director round 5c, probe rs-m9) — the silhouette half of the pair",
	},
	{
		term = "canvasMasks",
		why = "a mask is one real CanvasGroup per layer and the guide must say so: the census counts them",
	},
	{ term = "pressed", why = "the per-state variant vocabulary (§10.2)" },
	{ term = "barTrack", why = "the bar family's stackable half" },
	{ term = "barFill", why = "the clipped fill, and the slot that refuses layers" },
	{ term = "barCap", why = "the ornaments that must survive every percent" },
	{ term = "toggleKnob", why = "the sliding switch's knob slot" },
	{ term = "stepperPlate", why = "the whole-image-by-default plate and its `sliced = true`" },
	{ term = "spinner", why = "the indeterminate ProgressView's dot slot (parity round 2 §3.1)" },
	{ term = "iconSizes", why = "icon size rides the metric snapshot" },
	{ term = "tintRole", why = "an icon is tinted by its asset's role" },
	{ term = 'rendering = "pixel"', why = "pixel mode's flag" },
	{ term = "pixelUnit", why = "the pixel grid the snapshot snaps onto" },
	{ term = "Pixelated", why = "the censused resample mode pixel mode turns on" },
	{ term = "selectBy", why = "profile-conditional package selection" },
	{ term = "contentId", why = "the permanent alias for the canonical `content` field" },
	{ term = "UI.gradient", why = "the rung-2 per-view gradient modifier (charter cap 11)" },
	{
		term = "FacetGradient",
		why = "the bespoke child the gradient modifier materializes — instance, never a rule",
	},
	{ term = "checkCoverage", why = "rung 3's pre-play gate" },
	{ term = "chromeCensus", why = "declared layers versus actual instances is a measurement" },
	{ term = RUNG3_EXAMPLE, why = "OrnateGauge is THE rung-3 worked example" },
	{ term = "extending/skinned-control.md", why = "the chapter must point at the rung-3 playbook" },
}

local RUNG3_ANCHORS: { Anchor } = {
	{ term = "checkCoverage", why = "the pre-play conformance gate is the playbook's centre" },
	{ term = "ns:role", why = "the namespaced contribution convention" },
	{ term = "controlSize", why = "one of the three contribution kinds" },
	{ term = "fallback", why = "what makes an uncovered package degrade instead of erroring" },
	{ term = "metrics.controlSizes", why = "the only legal home for a controlSize need" },
	{ term = "metrics.radii", why = "the legal home for a plain namespaced number" },
	{ term = "UI.shadow", why = "the one public per-view channel that takes an explicit colour" },
	{ term = "UI.Image", why = "a control paints its own art through the public primitive" },
	{ term = "provenance.md", why = "a control's art owes the same provenance a package's does" },
	{ term = "upload-manifest.json", why = "the record of which IDs the control references" },
	{ term = "theme_authoring", why = "the Studio evidence obligation" },
	{ term = "presentGaugeFixture", why = "the rung-3 scenario fixture" },
	{ term = "check_docs_cli", why = "the gate obligations must name the canonical command" },
}

local API_ANCHORS: { Anchor } = {
	{ term = "theme_controller", why = "the client controller's require path and instance API" },
	{ term = "dumpTokens", why = "the controller instance API" },
	{ term = "inspect()", why = "the controller instance API" },
	-- the circle Button (feature round 2026-07-26). Three facts an author cannot
	-- discover any other way, each of which the reference is the only home for.
	{ term = 'shape = "circle"', why = "the disc's flag — the API reference is where its rules live" },
	{
		term = "controls.button.height",
		why = "the diameter is a theme METRIC; without this the reference reads as if the author picks a size",
	},
	{
		term = "facet-shape-circle",
		why = "the pill and the rim are phantom rules on this tag, which is what makes a flat disc cost no instances",
	},
}

-- Chapter 1 is where `UI.Button` is introduced, so it is where the circle
-- Button is taught. Same drift-alarm discipline as every other anchor list.
local CONCEPTS_ANCHORS: { Anchor } = {
	{ term = 'shape = "circle"', why = "the round action button the chapter teaches beside UI.Button" },
	{
		term = "controls.button.height",
		why = "a description names the SHAPE and the metric names the size — the point of the paragraph",
	},
	{ term = '"chevron.trailing"', why = "an icon is a MEANING, never an asset id" },
}

local STYLING_ANCHORS: { Anchor } = {
	{ term = "09-custom-themes.md", why = "the styling chapter must point at the walkthrough" },
	{ term = "themeMetrics", why = "the metric snapshot is the substance of §5.8" },
}

-- Stale language: an exact phrase that described the feature as unshipped. Each
-- one was removed by the docs package; its reappearance means a document was
-- reverted or copied from an old revision.
local FORBIDDEN: { { file: string, phrase: string, why: string } } = {
	{
		file = STYLING,
		phrase = "The planned Step 3.5 adds",
		why = "Step 3.5 shipped (ADR-0019); describe the package contract in the present tense",
	},
	{
		file = STYLING,
		phrase = "The current native Dark/Light themes are palette themes.",
		why = "themes own metrics, fonts, insets and chrome now — §5.8 says so",
	},
	{
		file = STYLING,
		phrase = "remain reference-only in this version",
		why = "metric attributes are the live authoring source once a package is installed",
	},
	{
		file = STYLING,
		phrase = "Current theme limit and the planned package contract",
		why = "the old §5.8 heading; the section now documents the shipped contract",
	},
	{
		file = "docs/reference/swiftui-parity.md",
		phrase = "there is no public\nreusable theme-package API",
		why = "Facet.themes is public surface",
	},
	-- rich skinning v2: statements that were TRUE before ADR-0020 and are now
	-- wrong. Each one would send a package author looking for a capability the
	-- build has, and find nothing.
	-- the WRONG root cause for the tofu caret (phase-gate verifier F6). It was a
	-- measured fact — the live probe drew U+25B8/U+25BE in Michroma and got the
	-- placeholder's advance — and stating a different cause sends the next author
	-- looking for a codepoint RANGE to avoid instead of testing their own font.
	{
		file = RICH_GUIDE,
		phrase = "private-use codepoints that measured at the tofu placeholder",
		why = "the measured cause is absent-from-Michroma geometric shapes, not a private-use range "
			.. "(artifacts/rich-skinning-v2/rs-a7-semantic-icons.json)",
	},
	{
		file = "docs/extending/new-theme.md",
		phrase = "refuses a private-use codepoint",
		why = "isSafeGlyph refuses everything outside plain ASCII; the measured failure was a missing "
			.. "geometric-shapes character, not a private-use one",
	},
	{
		file = GUIDE,
		phrase = "There are nine **decoration slots**, and the list is closed",
		why = "v2 ships seventeen slots (the bar family, stepperPlate, toggleTrack/Knob, spinner) — chapter 10 documents them",
	},
	{
		file = GUIDE,
		phrase = "### States are tints, not more art",
		why = "per-state ASSET variants ship (ADR-0020 R2); the section now says states can be tints OR more art",
	},
	{
		file = STYLING,
		phrase = "Six decoration slots, each either native paint",
		why = "the slot list grew and a slot may carry a layer stack — §5.8a describes the shipped surface",
	},
	{
		file = RICH_GUIDE,
		phrase = "There is no per-view gradient",
		why = "the charter's cap-11 gradient modifier SHIPS (UI.gradient); §10.10 documents it",
	},
}

-- ---- THE COMPARISON DOCUMENT'S CITATION GATE ------------------------------
--
-- One document in this repository compares Facet with another user-interface
-- framework, and it is the only one allowed to name it. Its whole value is that
-- comparison, and half of it used to be unguarded: claims about Facet are
-- reconciled against the build by this checker, check_prop_parity and
-- check_registration, while claims about the OTHER framework rested on memory.
-- A citation pass found ten of them wrong, including a symbol that does not
-- exist and a sizing rule attributed to a page that never states it. Every one
-- had stood uncited, which is why nobody had opened the page.
--
-- So: a row in a VERDICT table that asserts something about that framework must
-- carry a citation id, and every id must resolve to a §16 row carrying the
-- vendor's own documentation URL, a quoted sentence (or the document's fixed
-- words for a page that states nothing) and an ISO date. This cannot check that
-- a quote is TRUE -- only a human opening the URL does that -- but it stops a
-- new uncited assertion landing, which is the failure mode that produced all
-- ten.
--
-- The vendor words below are match data for that one document, the same way the
-- patterns in tools/check_brand_drift.py are match data for the rule that keeps
-- them out of every other file.
--
-- Deliberately narrow, because a noisy checker gets disabled: it fires only on a
-- table row, only in a table whose header says "Verdict", and only when the row
-- names the compared framework. Prose is not covered.
local PARITY = "docs/reference/swiftui-parity.md"
local CITE_DATE = "2026%-08%-13"
local NO_BEHAVIOUR = "Apple documents no behaviour here"

-- Rows that assert something about the compared framework and carry no
-- citation, with the
-- reason. An exemption is a debt, not a permission: the checker fails when one
-- stops matching (the row went away) AND when the exempt row starts carrying a
-- citation (the debt was paid), so neither entry can rot here unnoticed.
local CITATION_EXEMPT: { { match: string, why: string } } = {
	{
		match = "`Table.onPrimaryAction`",
		why = "owned by a concurrent Table task on 2026-08-13; the row quotes the vendor's context-menu "
			.. "discussion inline but does not link it",
	},
	{
		match = "Per-row capability opt-outs",
		why = "same task, same day: the §13 pointer row for the selectionDisabled/deleteDisabled/moveDisabled family",
	},
}

-- The scenario steps the guide teaches. Each must exist in BOTH the guide (so
-- the chapter still teaches it) and the scenario (so it still exists to teach).
local SCENARIO_STEPS = {
	"installPackage",
	"installFlat",
	"swapTheme",
	"swapPackage",
	"editMetricLive",
	"restoreMetric",
	"exportDump",
	"failMissingAsset",
	"recoverMissingAsset",
	"failMissingFont",
	"failIncompatible",
	"customControl",
	"inspect",
}

-- The scenario steps chapter 10 teaches. Same rule as SCENARIO_STEPS: each must
-- exist in the scenario AND be named by the chapter, so neither can rot alone.
local RICH_SCENARIO_STEPS = {
	"installLayered",
	"layerCensus",
	"barSweep",
	"setToggle",
	"iconProbe",
	"pixelProbe",
	"tileProbe",
	"selectByPair",
	"presentGaugeFixture",
	"gaugeProbe",
	"gaugeCoverage",
}

--[[ DERIVED FROM THE ONE ENUMERATOR (MAINT-8c). This was a hand list of ten
	paths, one of six such lists, and none of them could see a package the others
	had and it did not. `tools/lune/theme_packages.luau` declares each module's
	role; the docs check covers everything a reader can be sent to — the shipping
	reference corpus and the rung-3 controls — and deliberately not the refusal
	FIXTURES, which exist to be broken and are installed by name. ]]
local theme_packages = require("./theme_packages")
-- the skinned-control asset roots, derived from their manifests (MAINT-8d)
local skinned_controls = require("./skinned_controls")
local EXAMPLE_PACKAGES: { string } = {}
for _, role in { "reference", "control" } do
	for _, name in theme_packages.byRole(role :: any) do
		table.insert(EXAMPLE_PACKAGES, theme_packages.path(name))
	end
end

local ASSET_FILES = {
	ASSET_DIR .. "/parchment_panel.png",
	ASSET_DIR .. "/parchment_button.png",
	ASSET_DIR .. "/parchment_field.png",
	ASSET_DIR .. "/upload-manifest.json",
	ASSET_DIR .. "/provenance.md",
	-- (a skinned CONTROL's own art is appended below, DERIVED from the manifests
	-- rather than named here — see the loop after this table)
	-- the FRAMEWORK's own set. `edit` is named explicitly because it is the one
	-- semantic name this library invented, and the pencil is what a
	-- `compactLabel = { icon = "edit" }` button draws; the chevron stands in for
	-- the ten names that predate the art.
	ICON_ASSET_DIR .. "/facet_icon_edit.png",
	ICON_ASSET_DIR .. "/facet_icon_chevron_right.png",
	ICON_ASSET_DIR .. "/source/generate_icons.py",
	ICON_ASSET_DIR .. "/upload-manifest.json",
	ICON_ASSET_DIR .. "/provenance.md",
	ICON_REGISTRY,
}

--[[ ...AND EVERY SKINNED CONTROL'S OWN ART, DERIVED (MAINT-8d, 2026-08-17).

	The rung-3 control's six files used to be named here by hand, under a
	hardcoded `assets/themes/ornate-gauge`, while `docs/extending/skinned-control.md`
	promised a contributor that this checker enforced THEIR control's art,
	provenance and manifest. It enforced exactly one control's, and the playbook
	never said to come and edit this list.

	`tools/lune/skinned_controls.luau` enumerates the roots instead: an asset
	directory whose `upload-manifest.json` declares a `control` and a null
	`package` IS a skinned control, which is what the shipped manifest already
	says about itself. A second control is protected the moment it ships the
	manifest it owes anyway. ]]
for _, file in skinned_controls.files() do
	table.insert(ASSET_FILES, file)
end

export type Opts = {
	-- replace a file's contents (synthetic drift for the checker's own tests)
	fileOverrides: { [string]: string }?,
	-- pretend a path does not exist
	missingFiles: { [string]: boolean }?,
}

-- Documents that restate `Facet.VERSION` in prose. Each pattern captures the
-- version the document claims, so the check compares NUMBERS rather than
-- searching for a phrase that would go stale with the number in it.
local VERSION_DOCS: { { file: string, pattern: string, why: string } } = {
	{
		file = "docs/reference/api.md",
		pattern = "currently `([%d%.]+)`",
		why = "the API reference states the current version in its stability section",
	},
	{
		file = "docs/guide/08-without-rojo.md",
		pattern = "%(currently `([%d%.]+)`%)",
		why = "the no-Rojo chapter tells a consumer which version to pin",
	},
	{
		file = "docs/guide/README.md",
		pattern = 'Facet%.VERSION%s+%-%- "([%d%.]+)"',
		why = "the guide index shows the constant's value in its API sketch",
	},
	{
		file = "docs/adr/ADR-0011-semver-and-deprecation.md",
		pattern = "Current version: %*%*([%d%.]+)%*%*",
		why = "ADR-0011 is the version's home and api_surface.spec already pins it",
	},
}

local function contains(haystack: string, needle: string): boolean
	return string.find(haystack, needle, 1, true) ~= nil
end

-- resolve "a/b/../c" without touching the filesystem
local function normalize(path: string): string
	local parts: { string } = {}
	for part in string.gmatch(path, "[^/]+") do
		if part == ".." then
			if #parts > 0 then
				table.remove(parts)
			end
		elseif part ~= "." then
			table.insert(parts, part)
		end
	end
	return table.concat(parts, "/")
end

function check_docs.check(opts: Opts?)
	local options: Opts = opts or {}
	local overrides = options.fileOverrides or {}
	local missing = options.missingFiles or {}
	local problems: { string } = {}
	local anchorsChecked = 0
	local linksChecked = 0
	local citationsChecked = 0

	local function problem(file: string, what: string, fix: string)
		table.insert(problems, `{file}: {what}\n      fix: {fix}`)
	end

	local function exists(path: string): boolean
		if missing[path] then
			return false
		end
		if overrides[path] ~= nil then
			return true
		end
		return fs.isFile(path) or fs.isDir(path)
	end

	-- read a file, or nil when it is absent; every caller reports the absence
	-- itself so the message names the obligation and not just the path
	local function read(path: string): string?
		if missing[path] then
			return nil
		end
		if overrides[path] ~= nil then
			return overrides[path]
		end
		if not fs.isFile(path) then
			return nil
		end
		return fs.readFile(path)
	end

	local function requireFile(path: string, obligation: string, fix: string): string?
		local source = read(path)
		if source == nil then
			problem(path, obligation, fix)
		end
		return source
	end

	local function checkAnchors(path: string, source: string?, anchors: { Anchor })
		if source == nil then
			return
		end
		for _, anchor in anchors do
			anchorsChecked += 1
			if not contains(source, anchor.term) then
				problem(
					path,
					`no longer mentions '{anchor.term}' ({anchor.why})`,
					`restore the section that documents '{anchor.term}', or update this checker's anchor list `
						.. "in tools/lune/check_docs.luau if the surface itself was removed"
				)
			end
		end
	end

	-- ---- 1. the two new documents exist, and the index links the guide ------
	local guide = requireFile(
		GUIDE,
		"the custom-theme guide is missing",
		"restore docs/guide/09-custom-themes.md (the beginner walkthrough required by ADR-0019)"
	)
	local playbook = requireFile(
		PLAYBOOK,
		"the theme playbook is missing",
		"restore docs/extending/new-theme.md (the contributor playbook required by ADR-0019)"
	)
	local richGuide = requireFile(
		RICH_GUIDE,
		"the rich-skinning guide is missing",
		"restore docs/guide/10-rich-skinning.md (the v2 walkthrough required by ADR-0020 R8)"
	)
	local rung3 = requireFile(
		RUNG3_PLAYBOOK,
		"the rung-3 (custom skinned control) playbook is missing",
		"restore docs/extending/skinned-control.md (the contributor playbook required by ADR-0020 R8)"
	)
	local catalog = requireFile(
		CATALOG,
		"the theme catalog is missing",
		"restore docs/guide/13-theme-catalog.md (the shelf of installable packages, wave THEME-UNBUNDLE)"
	)
	local index = read(GUIDE_INDEX)
	if index == nil then
		problem(GUIDE_INDEX, "the guide index is missing", "restore docs/guide/README.md")
	else
		for _, chapter in { "09-custom-themes.md", "10-rich-skinning.md", "13-theme-catalog.md" } do
			if not contains(index, chapter) then
				problem(
					GUIDE_INDEX,
					`the reading-order table does not link {chapter}`,
					`add a \`| [\`{chapter}\`]({chapter}) | … |\` row to the reading-order table`
				)
			end
		end
	end

	-- ---- 2. every public Facet.themes export is documented -----------------
	local initSource = read(INIT)
	local api = requireFile(API, "the API reference is missing", "restore docs/reference/api.md")
	local exportsDocumented = 0
	if initSource ~= nil and api ~= nil then
		local block = string.match(initSource, "\n\tthemes = {(.-)\n\t},")
		if block == nil then
			problem(
				INIT,
				"could not find the `themes = { … }` export block (this checker reads the export list from it)",
				"keep the themes export block on the Facet table, or update the pattern in tools/lune/check_docs.luau"
			)
		else
			for name in string.gmatch(block, "\n\t\t([%w_]+) = ") do
				exportsDocumented += 1
				if not contains(api, `themes.{name}`) then
					problem(
						API,
						`public export 'Facet.themes.{name}' is not documented`,
						`document it in the \`themes\` section of docs/reference/api.md as \`themes.{name}\``
					)
				end
			end
		end
	end

	-- ---- 3. each document still names the surface it teaches ----------------
	checkAnchors(GUIDE, guide, GUIDE_ANCHORS)
	checkAnchors(PLAYBOOK, playbook, PLAYBOOK_ANCHORS)
	checkAnchors(RICH_GUIDE, richGuide, RICH_GUIDE_ANCHORS)
	checkAnchors(RUNG3_PLAYBOOK, rung3, RUNG3_ANCHORS)
	checkAnchors(API, api, API_ANCHORS)
	checkAnchors(STYLING, read(STYLING), STYLING_ANCHORS)
	checkAnchors(CONCEPTS, read(CONCEPTS), CONCEPTS_ANCHORS)

	-- ---- 4. the walkthrough's worked example still builds publicly ----------
	local example = read(WORKED_EXAMPLE)
	if example == nil then
		problem(
			WORKED_EXAMPLE,
			"the guide's worked example is missing",
			"restore examples/themes/fantasy_parchment.luau, or repoint the walkthrough at the package that replaced it"
		)
	else
		for _, needle in { "themes.define", "neutralPackage" } do
			if not contains(example, needle) then
				problem(
					WORKED_EXAMPLE,
					`no longer calls '{needle}' — the guide teaches it as a clean-consumer package built on the public API`,
					"keep the example building through Facet.themes only, and update docs/guide/09-custom-themes.md if the public path changed"
				)
			end
		end
	end

	-- the RUNG-3 worked example: a control, not a package, so what it must still
	-- do is contribute through the public gate rather than compile as a theme
	local rung3Example = read(RUNG3_EXAMPLE)
	if rung3Example == nil then
		problem(
			RUNG3_EXAMPLE,
			"the rung-3 worked example is missing",
			"restore examples/themes/ornate_gauge.luau, or repoint docs/extending/skinned-control.md at the control that replaced it"
		)
	else
		for _, needle in { "checkCoverage", "needs", "resolve" } do
			if not contains(rung3Example, needle) then
				problem(
					RUNG3_EXAMPLE,
					`no longer uses '{needle}' — the rung-3 walkthrough teaches it as a control that contributes `
						.. "namespaced roles through the PUBLIC contribution contract",
					"keep the example on themes.checkCoverage + the resolved snapshot, and update "
						.. "docs/extending/skinned-control.md if the public path changed"
				)
			end
		end
		-- A CLEAN CONSUMER REQUIRES NOTHING. The walkthrough's whole claim is
		-- that a control written OUTSIDE this repository has enough public
		-- surface, and this example takes `UI`, `core`, `themes` and the resolved
		-- snapshot as ARGUMENTS. Any require at all — internal or not — would
		-- mean it is reaching for something a third-party control cannot reach.
		if string.find(rung3Example :: string, "require(", 1, true) ~= nil then
			problem(
				RUNG3_EXAMPLE,
				"contains a `require(` — the rung-3 walkthrough teaches a control that receives UI, core, themes "
					.. "and the resolved snapshot as ARGUMENTS, so a require here means it reaches for something a "
					.. "control written outside this repository could not",
				"pass what the control needs in, or report the missing public seam instead of requiring around it"
			)
		end
	end

	-- ---- 5. example packages, art, provenance and manifest ------------------
	for _, path in EXAMPLE_PACKAGES do
		if not exists(path) then
			problem(
				path,
				"reference theme package missing (the guide lists it as part of the corpus)",
				"restore the package, or remove it from the guide's reference-package table"
			)
		end
	end
	for _, path in ASSET_FILES do
		if not exists(path) then
			local skinned = skinned_controls.ownerOf(path)
			local owner = if skinned ~= nil
				then `{skinned.control} (a skinned control's own art, declared by {skinned.manifestPath})`
				else "Fantasy Parchment"
			problem(
				path,
				`{owner} asset/provenance file missing`,
				"restore it (provenance.md records how to regenerate the art; upload-manifest.json records the content IDs)"
			)
		end
	end
	local manifest = read(MANIFEST)
	if manifest ~= nil and example ~= nil then
		for contentId in string.gmatch(manifest, "rbxassetid://%d+") do
			if not contains(example, contentId) then
				problem(
					MANIFEST,
					`content ID {contentId} is not used by {WORKED_EXAMPLE}`,
					"re-run the upload and update both files together — the manifest is the record of what the package actually references"
				)
			end
		end
	end
	-- the framework's own icon set: the manifest is the record of what was
	-- uploaded, the registry is the table the framework READS, and they are
	-- written by the same tool run so a disagreement means one of them was edited
	-- by hand
	local iconManifest = read(ICON_MANIFEST)
	local iconRegistry = read(ICON_REGISTRY)
	if iconManifest ~= nil and iconRegistry ~= nil then
		for contentId in string.gmatch(iconManifest, "rbxassetid://%d+") do
			if not contains(iconRegistry, contentId) then
				problem(
					ICON_MANIFEST,
					`content ID {contentId} is not used by {ICON_REGISTRY}`,
					"re-run tools/upload_icons.py --recheck, which writes both from one source — the registry is what resolveIcon reads"
				)
			end
		end
	end
	local rung3Manifest = read(RUNG3_MANIFEST)
	if rung3Manifest ~= nil and rung3Example ~= nil then
		for contentId in string.gmatch(rung3Manifest, "rbxassetid://%d+") do
			if not contains(rung3Example, contentId) then
				problem(
					RUNG3_MANIFEST,
					`content ID {contentId} is not used by {RUNG3_EXAMPLE}`,
					"re-run the upload and update both files together — a control's manifest is the record of the art it draws"
				)
			end
		end
	end

	-- ---- 6. local links in the two new documents resolve --------------------
	for _, entry in
		{
			{ path = GUIDE, source = guide },
			{ path = PLAYBOOK, source = playbook },
			{ path = RICH_GUIDE, source = richGuide },
			{ path = RUNG3_PLAYBOOK, source = rung3 },
			{ path = CATALOG, source = catalog },
		}
	do
		if entry.source == nil then
			continue
		end
		local dir = string.match(entry.path, "^(.*)/[^/]+$") or "."
		for target in string.gmatch(entry.source :: string, "%]%(([^)]+)%)") do
			if string.sub(target, 1, 4) == "http" or string.sub(target, 1, 1) == "#" then
				continue
			end
			local withoutAnchor = string.match(target, "^([^#]+)") or target
			local resolved = normalize(dir .. "/" .. withoutAnchor)
			linksChecked += 1
			if not exists(resolved) then
				problem(
					entry.path,
					`local link '{target}' resolves to '{resolved}', which does not exist`,
					"fix the link target, or restore the file it points at"
				)
			end
		end
	end

	--[[ ---- 6b. THE CATALOG LISTS EXACTLY WHAT SHIPS ------------------------

		Derived from `tools/lune/theme_packages.luau`, never from a list typed
		here — a catalog checked against a second hand list is two lists drifting
		in step. Both directions matter and they fail differently: a shippable
		package the catalog omits is a product a consumer cannot find, and a
		catalog entry for a module that is no longer shippable is an install
		instruction that ends in a file nobody built.

		The artifact FILENAME is what is matched, because that is the thing a
		consumer types after dragging the model in. A display name alone would
		pass on a catalog that lost every install route. ]]
	if catalog ~= nil then
		local catalogSource: string = catalog
		for _, name in theme_packages.shippable() do
			local artifact = `{theme_packages.artifactName(name)}.rbxm`
			if not contains(catalogSource, artifact) then
				problem(
					CATALOG,
					`'{name}' ships as build/themes/{artifact} and the catalog never names it`,
					`add its entry (one-screenshot description, character, install, cost) — tools/build_themes.sh `
						.. `builds it whether or not this page mentions it`
				)
			end
		end
		for name in theme_packages.NOT_SHIPPABLE do
			local artifact = `{theme_packages.artifactName(name)}.rbxm`
			if contains(catalogSource, artifact) then
				problem(
					CATALOG,
					`the catalog offers build/themes/{artifact}, which tools/build_themes.sh does not build `
						.. `('{name}' is excluded — see NOT_SHIPPABLE)`,
					"remove the entry, or make the module shippable in tools/lune/theme_packages.luau"
				)
			end
		end
		-- the install route itself: an artifact list with no way in is a menu
		for _, anchor in { "tools/build_themes.sh", "theme_controller.install", "ReplicatedStorage" } do
			if not contains(catalogSource, anchor) then
				problem(
					CATALOG,
					`the catalog no longer names '{anchor}', so it cannot be followed`,
					"restore the build command, the install call and the no-Rojo route"
				)
			end
		end
		-- ...and the pending cost row stays PENDING rather than quietly acquiring
		-- an invented number (the distribution plan's unsupported-claim rule)
		if not contains(catalogSource, "release performance wave") then
			problem(
				CATALOG,
				"the per-package memory table is not yet measured and the catalog no longer says so",
				"keep the pending-measurement note until the release performance wave lands, or replace it "
					.. "with the measured table"
			)
		end
	end
	if api ~= nil and not contains(api :: string, "13-theme-catalog.md") then
		problem(
			API,
			"the API reference does not cross-reference the theme catalog",
			`link {CATALOG} from the theme-controller section — a consumer reading install() is one sentence `
				.. "away from discovering they need write no theme at all"
		)
	end

	-- ---- 7. stale language --------------------------------------------------
	for _, entry in FORBIDDEN do
		local source = read(entry.file)
		if source ~= nil and contains(source, entry.phrase) then
			problem(
				entry.file,
				`still contains the stale phrase "{entry.phrase}"`,
				`{entry.why} — remove the sentence; the shipped surface is described in {GUIDE}`
			)
		end
	end

	-- ---- 7b. VERSION CONSISTENCY (phase-gate verifier F11) ------------------
	--
	-- `Facet.VERSION` is a number three documents restate in prose, and until
	-- this check they drifted silently: api.md and guide 08 still said 0.5.0 two
	-- stages after 0.6.0 shipped. The version is the ONE fact a consumer pins a
	-- build by, so a document that names a version nobody runs is worse than one
	-- that names none. `tests/api_surface.spec.luau` already ties ADR-0011 to the
	-- constant; this ties the guides to it too.
	do
		local initForVersion = read(INIT)
		local version = if initForVersion ~= nil then string.match(initForVersion, 'VERSION%s*=%s*"([%d%.]+)"') else nil
		if version == nil then
			problem(INIT, "no VERSION constant found", 'restore `VERSION = "x.y.z"` in the public export table')
		else
			for _, entry in VERSION_DOCS do
				local source = read(entry.file)
				if source == nil then
					continue
				end
				local named = string.match(source :: string, entry.pattern)
				if named ~= version then
					problem(
						entry.file,
						`says the current version is '{tostring(named)}' but Facet.VERSION is '{version}'`,
						`{entry.why} — update the sentence when you bump the constant (ADR-0011 says both move together)`
					)
				end
			end
		end
	end

	-- ---- 8. the scenario steps the guide teaches still exist ----------------
	local scenario = read(SCENARIO)
	if scenario == nil then
		problem(
			SCENARIO,
			"the theme-authoring scenario is missing (the guide's preview step drives it)",
			"restore examples/gallery/scenarios/theme_authoring.luau"
		)
	else
		for _, step in SCENARIO_STEPS do
			if not contains(scenario, step .. " = function") then
				problem(
					SCENARIO,
					`step '{step}' no longer exists, but {GUIDE} teaches it`,
					`restore the step, or update the step table in {GUIDE} and SCENARIO_STEPS in tools/lune/check_docs.luau`
				)
			elseif guide ~= nil and not contains(guide :: string, step) then
				problem(
					GUIDE,
					`does not mention the scenario step '{step}'`,
					"add it to the step table in §9.6, or drop it from SCENARIO_STEPS in tools/lune/check_docs.luau"
				)
			end
		end
		for _, step in RICH_SCENARIO_STEPS do
			if not contains(scenario, step .. " = function") then
				problem(
					SCENARIO,
					`step '{step}' no longer exists, but {RICH_GUIDE} teaches it`,
					`restore the step, or update {RICH_GUIDE} and RICH_SCENARIO_STEPS in tools/lune/check_docs.luau`
				)
			elseif richGuide ~= nil and not contains(richGuide :: string, step) then
				problem(
					RICH_GUIDE,
					`does not mention the scenario step '{step}'`,
					"add it to §10.12's step list, or drop it from RICH_SCENARIO_STEPS in tools/lune/check_docs.luau"
				)
			end
		end
	end

	-- ---- 9. every claim about the compared framework carries a citation -----
	local parity = read(PARITY)
	if parity == nil then
		problem(PARITY, "the comparison document is missing", "restore it, or drop section 9 of this checker with it")
	else
		local lines: { string } = {}
		for line in string.gmatch(parity :: string .. "\n", "([^\n]*)\n") do
			table.insert(lines, line)
		end

		-- 9a. §16 rows: `| **SW-nn** | page | quote | availability | date |`
		local defined: { [string]: boolean } = {}
		for _, line in lines do
			local id = string.match(line, "^| %*%*(SW%-%d+)%*%* |")
			if id == nil then
				continue
			end
			citationsChecked += 1
			if defined[id] then
				problem(PARITY, `citation {id} is defined twice in §16`, "give the second one its own id")
			end
			defined[id] = true
			if not contains(line, "https://developer.apple.com/") then
				problem(
					PARITY,
					`citation {id} has no developer.apple.com URL`,
					"cite the page a reader should open, or delete the citation and the claim that leans on it"
				)
			end
			if string.match(line, "%d%d%d%d%-%d%d%-%d%d") == nil then
				problem(
					PARITY,
					`citation {id} carries no ISO date`,
					"append the YYYY-MM-DD you read the page on — an undated citation rots invisibly"
				)
			end
			if not (contains(line, "\u{201C}") or contains(line, NO_BEHAVIOUR)) then
				problem(
					PARITY,
					`citation {id} quotes nothing`,
					`quote the sentence the claim rests on, or say "{NO_BEHAVIOUR}" — an unsupported `
						.. "citation is worse than none, because it looks checked"
				)
			end
		end

		-- 9b. references resolve, and nothing is defined that nobody cites
		local referenced: { [string]: boolean } = {}
		for _, line in lines do
			for id in string.gmatch(line, "%[(SW%-%d+)%]") do
				referenced[id] = true
				if not defined[id] then
					problem(
						PARITY,
						`{id} is cited but §16 does not define it`,
						`add the {id} row to §16 (page, verbatim quote, availability, date read)`
					)
				end
			end
		end
		for id in defined do
			if not referenced[id] then
				problem(
					PARITY,
					`citation {id} is defined in §16 but nothing cites it`,
					"cite it, or delete it — an unused citation is a claim that was removed without its evidence"
				)
			end
		end

		-- 9c. a verdict row naming the compared framework carries a citation
		local exemptSeen: { [number]: boolean } = {}
		local inVerdictTable = false
		for index, line in lines do
			if string.sub(line, 1, 1) ~= "|" then
				inVerdictTable = false
				continue
			end
			if string.match(line, "^|[%s%-:|]+|$") ~= nil then
				local header = lines[index - 1]
				inVerdictTable = header ~= nil and contains(header, "Verdict")
				continue
			end
			if not inVerdictTable or not contains(line, "SwiftUI") then
				continue
			end
			local cited = contains(line, "[SW-")
			local exempt = nil
			for slot, entry in CITATION_EXEMPT do
				if contains(line, entry.match) then
					exempt = slot
					exemptSeen[slot] = true
					break
				end
			end
			if exempt ~= nil then
				if cited then
					problem(
						PARITY,
						`the exempt row '{CITATION_EXEMPT[exempt].match}' now carries a citation`,
						"delete its entry from CITATION_EXEMPT in tools/lune/check_docs.luau — the debt is paid"
					)
				end
			elseif not cited then
				problem(
					PARITY,
					`line {index} asserts something about the compared framework with no citation`,
					"add a [SW-nn] id and its §16 row (the vendor's page, the sentence quoted verbatim, the "
						.. "date read), or reword the row so it stops making that claim"
				)
			end
		end
		for slot, entry in CITATION_EXEMPT do
			if not exemptSeen[slot] then
				problem(
					PARITY,
					`the citation exemption for '{entry.match}' matches no row`,
					"remove it from CITATION_EXEMPT in tools/lune/check_docs.luau — the row it excused is gone"
				)
			end
		end

		-- 9d. the convention itself is stated where a reader will meet it
		for _, anchor in
			{
				{ term = "## 16. Citations", why = "the citation table §§3-11 resolve their ids against" },
				{ term = CITE_DATE:gsub("%%", ""), why = "the date every citation in this pass was read on" },
				{ term = NO_BEHAVIOUR, why = "the words this document uses for a page that states nothing" },
			}
		do
			anchorsChecked += 1
			if not contains(parity :: string, anchor.term) then
				problem(
					PARITY,
					`no longer contains '{anchor.term}' ({anchor.why})`,
					"restore it, or update the anchor list in tools/lune/check_docs.luau if the convention changed"
				)
			end
		end
	end

	--[[ ---- 10. THE CAPABILITY CATALOG -------------------------------------
		The guide index is where a new author discovers what the library can do.
		So it must name every capability that currently ships, and it must not
		advertise anything that does not. Four directions are checked:

		  a. every live public capability is named in the index;
		  b. every capability name the index prints still resolves on the
		     `Facet` table (a removed or renamed item cannot linger);
		  c. every API-reference link the index makes lands on a heading that
		     api.md really has;
		  d. every extension playbook under docs/extending/ is linked.

		Surfaces on their way out are skipped, read from `Facet.DEPRECATIONS`:
		an alias with a replacement is not something the index has to teach.
		`UI` and `Controls` are namespaces whose MEMBERS are the capabilities,
		so the members carry the obligation and the bare namespace name does
		not. ]]
	local catalogEntries = 0
	if index ~= nil then
		local text = index :: string

		local retired: { [string]: boolean } = {}
		for _, entry in liveFacet.DEPRECATIONS :: { any } do
			retired[tostring(entry.surface)] = true
		end

		local function named(token: string): boolean
			return contains(text, "`" .. token .. "`") or contains(text, "`Facet." .. token .. "`")
		end

		local function mustName(token: string, why: string)
			catalogEntries += 1
			if not named(token) then
				problem(
					GUIDE_INDEX,
					`the capability catalog does not name '{token}' ({why})`,
					`add a catalog row naming \`{token}\` and linking its docs/reference/api.md section, or `
						.. "retire the export through Facet.DEPRECATIONS if it is going away"
				)
			end
		end

		local namespaces = { "UI", "Controls" }
		for _, key in namespaces do
			local namespace = liveFacet[key]
			if type(namespace) == "table" then
				local members: { string } = {}
				for member in namespace do
					table.insert(members, tostring(member))
				end
				table.sort(members)
				for _, member in members do
					mustName(`{key}.{member}`, `a member of the {key} namespace`)
				end
			end
		end

		local topLevel: { string } = {}
		for key in liveFacet do
			table.insert(topLevel, tostring(key))
		end
		table.sort(topLevel)
		for _, key in topLevel do
			if retired[key] or table.find(namespaces, key) ~= nil then
				continue
			end
			mustName(key, "a public export of the Facet table")
		end

		-- b. nothing the index advertises may have disappeared
		for token in string.gmatch(text, "`([%w_]+%.[%w_]+)`") do
			local namespace, member = string.match(token, "^([%w_]+)%.([%w_]+)$")
			if namespace ~= nil and table.find(namespaces, namespace :: string) ~= nil then
				local live = liveFacet[namespace]
				if type(live) ~= "table" or live[member] == nil then
					problem(
						GUIDE_INDEX,
						`the capability catalog names '{token}', which the library no longer exports`,
						"delete the catalog row, or restore the export"
					)
				end
			end
		end

		-- c. every API-reference link resolves to a real heading
		if api ~= nil then
			local seen: { [string]: number } = {}
			local anchors: { [string]: boolean } = {}
			for line in string.gmatch(api :: string, "[^\n]+") do
				local heading = string.match(line, "^#+%s+(.-)%s*$")
				if heading ~= nil then
					local slug = string.lower(heading)
					slug = string.gsub(slug, "[`*]", "")
					slug = string.gsub(slug, "[^%w%s_-]", "")
					slug = string.gsub(slug, "%s", "-")
					local count = seen[slug] or 0
					anchors[if count == 0 then slug else `{slug}-{count}`] = true
					seen[slug] = count + 1
				end
			end
			for anchor in string.gmatch(text, "%(%.%./reference/api%.md#([%w_-]+)%)") do
				linksChecked += 1
				if not anchors[anchor] then
					problem(
						GUIDE_INDEX,
						`links docs/reference/api.md#{anchor}, which is not a heading in that document`,
						"point the catalog row at the heading api.md really has, or add the missing section"
					)
				end
			end
		end

		-- d. every extension playbook is reachable from the index
		if fs.isDir("docs/extending") then
			local playbooks = fs.readDir("docs/extending")
			table.sort(playbooks)
			for _, entry in playbooks do
				if string.match(entry, "%.md$") ~= nil then
					catalogEntries += 1
					if not contains(text, `../extending/{entry}`) then
						problem(
							GUIDE_INDEX,
							`the extension-playbook list does not link {entry}`,
							`add a bullet linking [\`{string.gsub(entry, "%.md$", "")}\`](../extending/{entry})`
						)
					end
				end
			end
		end
	end

	return {
		ok = #problems == 0,
		problems = problems,
		counts = {
			documents = 9,
			catalogEntries = catalogEntries,
			anchors = anchorsChecked,
			citations = citationsChecked,
			links = linksChecked,
			themeExports = exportsDocumented,
			scenarioSteps = #SCENARIO_STEPS + #RICH_SCENARIO_STEPS,
			examplePackages = #EXAMPLE_PACKAGES,
			assets = #ASSET_FILES,
			forbiddenPhrases = #FORBIDDEN,
		},
	}
end

-- the obligation list, in the CLI's words. Exported so the gate artifact and
-- the spec name the same set this module enforces.
check_docs.OBLIGATIONS = table.freeze({
	"docs/guide/README.md links 09-custom-themes.md and that guide exists",
	"docs/extending/new-theme.md exists",
	"every public Facet.themes export (read from src/init.luau) is documented in docs/reference/api.md",
	"docs/guide/09-custom-themes.md still names the shipped surface it teaches (themes.define, neutralPackage, "
		.. "theme_controller, theme_sync_cli + --check, dumpTokens, chromeCensus, checkCoverage, sliceCenter, "
		.. "contentInsets, facet-chrome-fallback, FacetChromeText, facet-chrome-editing, the worked example, provenance.md)",
	"docs/extending/new-theme.md still names lintProperty, checkCoverage, the ::UICorner/::UIStroke/::UIGradient "
		.. "allowlist and inert ::UIShadow, facet-theme/1, provenance.md, the theme_authoring scenario, "
		.. "check_docs_cli and the acceptance ledger",
	"docs/reference/api.md documents the client controller (require path, dumpTokens, inspect())",
	"docs/guide/05-styling.md points at 09-custom-themes.md and explains themeMetrics",
	'docs/reference/api.md and docs/guide/01-concepts.md still teach the circle Button (shape = "circle", the '
		.. "controls.button.height diameter metric, the facet-shape-circle paint tag, and that an icon is a MEANING "
		.. 'like "chevron.trailing" rather than an asset id)',
	"examples/themes/fantasy_parchment.luau exists and still builds through themes.define + neutralPackage",
	"the five reference/example theme packages exist",
	"the three Fantasy Parchment PNGs, upload-manifest.json and provenance.md exist, and every content ID in the "
		.. "manifest is used by the package",
	"the FRAMEWORK's own icon set exists (assets/icons: the edit and chevron PNGs, source/generate_icons.py, "
		.. "upload-manifest.json, provenance.md, and the src/themes/standard_icons.luau registry), and every "
		.. "content ID in its manifest is used by that registry",
	"every local markdown link in the two new documents resolves to a real path",
	'docs/guide/05-styling.md no longer claims the package contract is unshipped ("The planned Step 3.5 adds", '
		.. '"The current native Dark/Light themes are palette themes.", "remain reference-only in this version", '
		.. '"Current theme limit and the planned package contract"), and the comparison document no longer says '
		.. "there is no public reusable theme-package API",
	"every theme_authoring scenario step the guide teaches exists in the scenario, and every step in the checker's "
		.. "list is taught by the guide",
	-- ---- the comparison document's citation gate ---------------------------
	"every VERDICT-table row of the comparison document that asserts something about the compared framework "
		.. "carries a [SW-nn] citation id (or is one of the named, self-expiring exemptions in CITATION_EXEMPT)",
	"every [SW-nn] id cited in the comparison document resolves to a §16 row, every §16 row is cited by "
		.. "something, and each one carries the vendor's documentation URL, a quoted sentence (or the document's "
		.. "fixed words for a silent page) and an ISO date — the citation cannot be checked for truth, only for "
		.. "existence",
	-- ---- the theme catalog (wave THEME-UNBUNDLE) ---------------------------
	"docs/guide/README.md links 13-theme-catalog.md and that catalog exists",
	"docs/guide/13-theme-catalog.md names every SHIPPABLE package's build/themes/<Name>.rbxm and no artifact "
		.. "tools/build_themes.sh does not build (both derived from tools/lune/theme_packages.luau), still carries "
		.. "the install route (tools/build_themes.sh, theme_controller.install, the no-Rojo ReplicatedStorage "
		.. "path), and still marks the per-package memory table as owed to the release performance wave rather "
		.. "than inventing a "
		.. "number",
	"docs/reference/api.md cross-references the theme catalog from the theme-controller section",
	-- ---- rich skinning v2 (ADR-0020 R8, ledger row RS-A15) -----------------
	"docs/guide/README.md links 10-rich-skinning.md and that guide exists",
	"docs/extending/skinned-control.md (the rung-3 playbook) exists",
	"docs/guide/10-rich-skinning.md still names the whole v2 surface it teaches (layered recipes and MAX_LAYERS, the "
		.. "corners/plaque/tile layer kinds, the per-state vocabulary, barTrack/barFill/barCap, toggleKnob, "
		.. 'stepperPlate, iconSizes, tintRole, rendering = "pixel" + pixelUnit + Pixelated, selectBy, contentId, '
		.. "the rung-2 UI.gradient modifier and its FacetGradient child, checkCoverage, chromeCensus, and both the "
		.. "rung-3 example and its playbook)",
	"docs/extending/skinned-control.md still names checkCoverage, ns:role, the three contribution kinds and their "
		.. "legal sections, fallbacks, UI.shadow, UI.Image, provenance.md, upload-manifest.json, the theme_authoring "
		.. "scenario and its gauge fixture, and check_docs_cli",
	"examples/themes/ornate_gauge.luau exists, contributes through themes.checkCoverage + the resolved snapshot, and "
		.. "reaches NO internal module",
	"the three OrnateGauge PNGs, their generator, upload-manifest.json and provenance.md exist, and every content ID "
		.. "in that manifest is used by the control",
	"every local markdown link in the rich-skinning chapter and the rung-3 playbook resolves to a real path",
	'no document still describes the v2 surface as unshipped (the nine-slot list, "states are tints, not more art", '
		.. '"six decoration slots"), and no document restates the WRONG tofu root cause (the measured failure was '
		.. "U+25B8/U+25BE absent from Michroma, not a private-use codepoint)",
	"every rich-skinning scenario step the chapter teaches exists in the scenario, and every step in the checker's "
		.. "list is taught by the chapter",
	"every document that restates Facet.VERSION in prose (api.md, guide 08, guide README, ADR-0011) names the "
		.. "version src/init.luau actually exports",
	-- ---- the capability catalog (wave T12) ---------------------------------
	"docs/guide/README.md names every member of the UI and Controls namespaces and every non-retired export of "
		.. "the live Facet table, read from the exported table itself rather than from a hand list",
	"docs/guide/README.md advertises no UI.* or Controls.* capability the library has stopped exporting",
	"every docs/reference/api.md link the guide index makes lands on a heading that document really has",
	"docs/guide/README.md links every extension playbook under docs/extending/",
})

return check_docs
