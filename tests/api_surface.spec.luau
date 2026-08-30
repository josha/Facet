--!strict
-- Phase 4 versioning and public-surface contract (design §17 Phase 4;
-- UI-AGENT-001): the library carries a semantic version governed by the
-- versioning and deprecation policy in CONTRIBUTING.md, the version is a valid
-- semver string matching the documented one, deprecated surfaces are declared in
-- a machine-readable ledger with removal rules, and the public API table only
-- grows through the documented surface (drift between init.luau and the API
-- reference is checked mechanically by tools/lune/check_docs).

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")

local Facet = require("../src") :: any
local public_shape = require("./lib/public_shape")

describe("semantic versioning and deprecation", function()
	it("VERSION is a plain semver MAJOR.MINOR.PATCH (scaffold suffixes are gone)", function()
		local major, minor, patch = string.match(Facet.VERSION, "^(%d+)%.(%d+)%.(%d+)$")
		expect(major ~= nil).toBeTruthy()
		expect(tonumber(major)).toBe(0) -- pre-1.0: minor bumps may break with notice
		expect(tonumber(minor) :: number).toBeGreaterThanOrEqual(4) -- Phase 4 bump
		expect(patch ~= nil).toBeTruthy()
	end)

	it("the published policy exists and states the rules the ledger is built on", function()
		local policy = fs.readFile("CONTRIBUTING.md")
		expect(string.find(policy, "MAJOR") ~= nil).toBeTruthy()
		expect(string.find(policy, "deprecat") ~= nil).toBeTruthy()
		-- ...and the changelog's newest numbered entry is the version this tree
		-- reports, so the two cannot drift apart
		local changelog = fs.readFile("CHANGELOG.md")
		expect(string.match(changelog, "## %[([%d%.]+)%]")).toBe(Facet.VERSION)
	end)

	it("deprecations are a machine-readable ledger with the policy's required fields", function()
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
	-- derived condition) could not be declared at all — the policy's machinery
	-- simply did not know about it, and the init.luau comment still claimed
	-- "Empty = nothing deprecated".
	it("the ledger is the UNION of schema-generated and declared entries", function()
		local schema = require("../src/blueprint_schema") :: any
		local generated = schema.deprecations()
		local ledger = Facet.DEPRECATIONS :: { any }
		--[[ TWENTY-FOUR declared entries. FIVE predate this stage: the two 0.8.0 rows,
			the two 0.9.0 VirtualList extent renames that came with `axis` (an alias is
			only a deprecation if the ledger says so — parity round 2 §2.3), and
			`screen_target.new(opts.isReducedMotion)`, which was deprecated in prose in
			two places and declared in neither until the Milestone-1 review (C3) — a
			deprecation with no `since` and no `removeNoEarlierThan` is invisible to
			every upgrade check the versioning policy defines. The other NINETEEN are
			the old-form composite builders (`newTable` … `newAsyncImage`), each naming
			`Facet.Controls.<Name>(core, spec)`; their content is owned by
			tests/controls_namespace.spec.luau. ]]
		expect(#ledger).toBe(#generated + 24)
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
			expect(removeKey).toBeGreaterThan(sinceKey) -- the policy owes one minor of notice
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

--[[ ═══ THE TWO SHAPE CHANGES A DEPRECATION LEDGER CANNOT SEE ═════════════════

	Wave LAYOUT-FIX made `UI.AdaptiveStack.axis` REQUIRED and changed `UI.Grid`'s
	undeclared lane default, and every gate in this repository stayed green over
	both. Three mechanisms each had a reason not to fire:

	  * `blueprint_schema.deprecations()` emits a row only for a prop carrying an
	    explicit `deprecated` field — making one REQUIRED generates nothing;
	  * the cases above enforce the LEDGER's schema, not the SCHEMA's shape;
	  * `VERSION` had been frozen for seventy commits, so "nothing bumped" read as
	    campaign practice rather than as an omission.

	These three cases close it. They pin the two facts that turn working consumer
	code into broken consumer code with no deprecation machinery involved — the set
	of REQUIRED props, and the VALUE every documented default names — and the third
	asserts that everything the changelog's register records as breaking is really in
	those sets, so the record and the schema cannot drift apart in either direction.

	THE PIN IS A VALUE, NOT A DOC STRING, deliberately: `public_shape.defaultTokenOf`
	lifts the value a doc names, so rewording a doc without changing its default
	moves nothing. Nine of the ninety-seven state their default in prose and pin a
	normalized window instead; that is stated in the extractor rather than hidden.

	SHARED PROPS ARE PINNED ONCE. `gridSpan`, `layoutPriority`, `shrinkWeight` and
	`distribute` are the same declaration on every class, and eighty rows repeating
	four facts is a pin nobody would read or maintain.
]]
describe("the public SHAPE a breaking change moves", function()
	-- every `Class.prop` carrying `required = true`, sorted. A prop joining or
	-- leaving this list is a change to what a consumer must write.
	local REQUIRED: { string } = {
		"AdaptiveStack.axis",
		"Button.label",
		"Composition.arrangements",
		"Composition.groups",
		"ErrorBoundary.fallback",
		"ErrorBoundary.view",
		"ForEach.items",
		"ForEach.key",
		"ForEach.row",
		"Path.points",
		"Region.group",
		"Region.rank",
		"Text.text",
		"Toggle.label",
		"When.condition",
		"When.thenView",
	}

	-- the value each documented default names, by `public_shape.defaultTokenOf`
	local SHARED_DEFAULTS: { [string]: string } = {
		["focusable"] = "focusable",
		["gridSpan"] = "1",
		["layoutPriority"] = "0",
		["shrinkWeight"] = "0 = never, matching Roblox's `UIFlexMode.None`",
		["traversalPriority"] = "0",
	}
	local CLASS_DEFAULTS: { [string]: string } = {
		["AdaptiveStack.distribute"] = "`start`",
		["Box.opacity"] = "prose: subtree: 1 = opaque (the default), 0 = invisible but",
		["Button.compactLabel"] = "prose:he compact form ALWAYS (a default, not a degrade) —",
		["Composition.groups"] = "prose:s ceiling on a fill lane; defaults at ten-foot to `ad",
		["ForEach.transition"] = "the mirror of enter",
		["Grid.flow"] = "cells wrap across the width, lines advance down",
		["Grid.itemSizing"] = "natural",
		["Grid.minColumnWidth"] = "prose: the widest child — the DEFAULT when neither this n",
		["Grid.rowGap"] = "gap",
		["Grip.focusVisual"] = "prose:'default' (adapter paints th",
		["Grip.focusable"] = "prose:(Grips are unfocusable by default)",
		["HStack.distribute"] = "`start`",
		["Image.scaleMode"] = "prose: aspect ratio, the engine default)",
		["Region.expand"] = "— the framework presents it in a transient plate at the region's anchor",
		["Region.mayDrop"] = "false",
		["Region.sizing"] = "hug",
		["Region.weight"] = "1",
		["Screen.distribute"] = "`start`",
		["ScrollView.autoscroll"] = "on, inert unless a drag is in flight",
		["ScrollView.axis"] = "y",
		["ScrollView.indicators"] = "prose:croll indicators: 'auto' (default, session policy) or",
		["Text.role"] = "prose:or 'content' (the resting default, worth naming so a ",
		["VStack.distribute"] = "`start`",
		["When.transition"] = "the mirror of enter",
		["ZStack.opacity"] = "prose: subtree: 1 = opaque (the default), 0 = invisible but",
	}

	local RECORD = "CHANGELOG.md"

	local function liveShape(): ({ string }, { [string]: string }, { [string]: string })
		local all = (Facet.UI.schema.all :: any)()
		local classes: { string } = {}
		for name in all do
			table.insert(classes, name)
		end
		table.sort(classes)
		local required: { string } = {}
		local shared: { [string]: string } = {}
		local perClass: { [string]: string } = {}
		for _, class in classes do
			local props: { string } = {}
			for prop in (all[class] :: any).props do
				table.insert(props, prop)
			end
			table.sort(props)
			for _, prop in props do
				local spec = (all[class] :: any).props[prop] :: any
				if spec.required == true then
					table.insert(required, `{class}.{prop}`)
				end
				local token = public_shape.defaultTokenOf(spec.doc)
				if token ~= nil then
					if spec.shared == true then
						shared[prop] = token
					else
						perClass[`{class}.{prop}`] = token
					end
				end
			end
		end
		return required, shared, perClass
	end

	-- what a failure has to say to be worth having: the surfaces that moved, and
	-- the one place a deliberate move is recorded
	local function diff(label: string, pinned: { [string]: string }, live: { [string]: string }): { string }
		local out: { string } = {}
		for key, token in live do
			if pinned[key] == nil then
				table.insert(out, `{label} GAINED a documented default: {key} = "{token}"`)
			elseif pinned[key] ~= token then
				table.insert(out, `{label} CHANGED its documented default: {key} "{pinned[key]}" -> "{token}"`)
			end
		end
		for key, token in pinned do
			if live[key] == nil then
				table.insert(out, `{label} LOST its documented default: {key} was "{token}"`)
			end
		end
		table.sort(out)
		return out
	end

	it("no prop has flipped to REQUIRED without a record", function()
		local required = liveShape()
		local pinned: { [string]: boolean } = {}
		for _, name in REQUIRED do
			pinned[name] = true
		end
		local moved: { string } = {}
		for _, name in required do
			if not pinned[name] then
				table.insert(moved, `{name} is now REQUIRED and was not`)
			end
		end
		for _, name in REQUIRED do
			local stillThere = false
			for _, live in required do
				if live == name then
					stillThere = true
				end
			end
			if not stillThere then
				table.insert(moved, `{name} is no longer REQUIRED`)
			end
		end
		table.sort(moved)
		expect(
			if #moved == 0
				then "the required set is the pinned one"
				else `{table.concat(moved, "; ")} — a required prop is a BREAKING change to what a consumer must write: record it in {RECORD} and update this pin in the same commit`
		).toBe("the required set is the pinned one")
	end)

	it("no documented default has changed VALUE without a record", function()
		local _, shared, perClass = liveShape()
		local moved: { string } = {}
		for _, entry in diff("a shared box/container prop", SHARED_DEFAULTS, shared) do
			table.insert(moved, entry)
		end
		for _, entry in diff("a class prop", CLASS_DEFAULTS, perClass) do
			table.insert(moved, entry)
		end
		table.sort(moved)
		expect(
			if #moved == 0
				then "every documented default is the pinned value"
				else `{table.concat(moved, "; ")} — a documented default is the contract a consumer reads: record it in {RECORD} and update this pin in the same commit`
		).toBe("every documented default is the pinned value")
	end)

	it("every surface the register records as breaking is really in the pinned shape", function()
		--[[ THE HALF THAT MAKES THE OTHER TWO MORE THAN A SNAPSHOT. A pin agrees
			with itself by construction; what it cannot say is whether the RECORD is
			about the same surfaces. So the register's own two schema-shaped rows are
			read back out of it and checked against the live schema — delete either
			from the changelog and this reddens, which is the red-first this
			instrument was asked for. ]]
		local record = fs.readFile(RECORD)
		local missing: { string } = {}
		-- the prop that flipped to required
		if string.find(record, "`UI.AdaptiveStack.axis` was optional", 1, true) == nil then
			table.insert(missing, "the changelog does not record `UI.AdaptiveStack.axis` becoming required")
		end
		-- the default that changed value
		if string.find(record, "`UI.Grid` given neither `columns` nor `minColumnWidth`", 1, true) == nil then
			table.insert(missing, "the changelog does not record `UI.Grid`'s changed lane default")
		end
		-- ...and both must still be true of the SCHEMA, or the record is stale
		local required, _, perClass = liveShape()
		local axisRequired = false
		for _, name in required do
			if name == "AdaptiveStack.axis" then
				axisRequired = true
			end
		end
		if not axisRequired then
			table.insert(
				missing,
				"the changelog records `AdaptiveStack.axis` as required and the schema no longer says so"
			)
		end
		if perClass["Grid.minColumnWidth"] == nil then
			table.insert(missing, "the changelog records `UI.Grid`'s lane default and the schema documents none")
		end
		-- ...and the policy that authorises an unreleased breaking change is stated
		if
			string.find(record, "what makes a breaking change legal before a version's first publish", 1, true) == nil
		then
			table.insert(missing, "the changelog no longer states the pre-release policy the register stands on")
		end
		expect(`unrecorded:{table.concat(missing, "; ")}`).toBe("unrecorded:")
	end)
end)
