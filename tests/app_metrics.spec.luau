--!strict
--[[
	THE APP METRIC NAMESPACE (ADR-0042, framework-gaps-phase2 gap 1).

	An app's own structural numbers — a tile minimum, a chart band, a dock height
	— are not spacing steps and not control metrics, and before this round there
	was nowhere for them: `snapshot.isMetricPath` validates a name against the
	NEUTRAL snapshot, so a name no shipped package declares is a construction
	error; `themes.resolve` refuses an unknown override and an unknown
	`metrics.tenFoot` path; and the ten-foot density ladder walks a closed set of
	sections, so even a smuggled-in table would receive no distance transform.

	Four separate consumers rediscovered that independently and each wrote the
	same shim (`examples/reference/p2_cartwheel`, `p3_sipworks`, and Rascal Rally
	twice), two of them re-implementing the distance transform BY HAND — and one
	of those applied it to a single number and left three neighbours behind, so
	the ladder was half-applied inside one proof.

	This file is the contract for the channel that replaces them:

	  1. it is DECLARED once per app, under that app's own GROUP
	     (`Facet.themes.declareApp("cartwheel", …)`), and declaring is validated —
	     a name that is not a legal identifier, or a value that is not a finite
	     number, is refused rather than guessed at. The group is what lets the
	     showcase mount five proofs in one process without the second one
	     un-spelling the first one's names;
	  2. a declared name is SPELLABLE — `isMetricPath("app.proof.tileMin")` — so
	     `px = "app.proof.tileMin"` passes the same construction check
	     `px = "iconSizes.large"` passes, and an UNDECLARED `app.*` name is
	     refused exactly as `iconSizes.enormous` is;
	  3. it RESOLVES on every snapshot, whatever package is installed, so a proof
	     that must mount under Studio Neutral AND Fantasy Parchment keeps its
	     numbers;
	  4. it rides the TEN-FOOT LADDER: an app length scales by `metricScale`
	     exactly like a built-in, and an app number whose NAME says it is not a
	     length (a fraction, a count, seconds, a type size) does not — the same
	     open-section vocabulary `controls.*` already spends;
	  5. a package may MOVE a declared name (`metrics.app`) and may name one in
	     `metrics.tenFoot`, and `themes.resolve`'s `overrides` reaches it — so an
	     app number is theme-owned like every other metric, instead of being the
	     one table a theme swap cannot touch.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src")
local snapshot = require("../src/themes/snapshot") :: any
local themes = (Facet :: any).themes

--[[ THE DECLARATION IS PROCESS-WIDE, so every case restores it. `isMetricPath`
	is a STATIC check with no snapshot in scope (it runs at construction, inside
	`blueprint_schema`), which is what forces the namespace to be a declaration
	rather than a per-snapshot fact — and a spec that declared and walked away
	would leak names into every later spec file in this one Lune process. ]]
-- the first refusal a `themes.define` report carries, so a red row here names
-- what the compiler objected to rather than "expected table, got nil"
local function refusal(report: any): string
	local first = if type(report) == "table" and type(report.errors) == "table" then report.errors[1] else nil
	return if type(first) == "table" then tostring(first.message) else "?"
end

local GROUP = "proof"

local function withApp(declaration: any, body: () -> ())
	themes.declareApp(GROUP, declaration)
	local ok, err = pcall(body)
	themes.declareApp(GROUP, nil)
	if not ok then
		error(err, 0)
	end
end

local PROOF = {
	tileMin = 96,
	chartH = 160,
	sponsor = {
		rowHeight = { landscape = 56, portrait = 60 },
		-- the name says it is not a length: the open-section vocabulary
		mapFraction = { landscape = 0.52 },
		toastDurationSeconds = 2.5,
		listRowCount = 8,
		rowNameTextSize = 18,
	},
}

describe("app metrics: declaring the namespace", function()
	it("declares names under its own group, reads them back frozen, and retires them", function()
		withApp(PROOF, function()
			local declared = themes.appMetrics()
			expect(declared.proof.tileMin).toBe(96)
			expect(declared.proof.sponsor.rowHeight.landscape).toBe(56)
			expect(table.isfrozen(declared)).toBe(true)
			expect(table.isfrozen(declared.proof.sponsor)).toBe(true)
		end)
		-- retired: the group is gone and nothing else was touched
		expect(themes.appMetrics().proof).toBe(nil)
	end)

	--[[ THE REASON A GROUP EXISTS. `examples/gallery` mounts five reference
		proofs in ONE place and the picker switches between them at runtime, so a
		declaration that replaced the whole section would let the second proof's
		boot un-spell the first proof's names — and every form the picker rebuilt
		after the switch would refuse to construct. Two groups compose; neither can
		reach the other's. ]]
	it("two apps in one process compose instead of clobbering", function()
		themes.declareApp("alpha", { tileMin = 96 })
		themes.declareApp("beta", { tileMin = 200 })
		expect(snapshot.isMetricPath("app.alpha.tileMin")).toBe(true)
		expect(snapshot.isMetricPath("app.beta.tileMin")).toBe(true)
		local snap = snapshot.neutral()
		expect(snapshot.resolveNumber(snap, "app.alpha.tileMin")).toBe(96)
		expect(snapshot.resolveNumber(snap, "app.beta.tileMin")).toBe(200)
		-- retiring one leaves the other exactly where it was
		themes.declareApp("alpha", nil)
		expect(snapshot.isMetricPath("app.alpha.tileMin")).toBe(false)
		expect(snapshot.isMetricPath("app.beta.tileMin")).toBe(true)
		themes.declareApp("beta", nil)
	end)

	--[[ REFUSE, DON'T GUESS. Every one of these is a shape that would otherwise
		become a silent nil on the first solve of a themed screen. ]]
	it("refuses a name that is not a legal metric identifier", function()
		expect(pcall(themes.declareApp, GROUP, { ["tile-min"] = 96 })).toBe(false)
		expect(pcall(themes.declareApp, GROUP, { ["tile.min"] = 96 })).toBe(false)
		expect(pcall(themes.declareApp, GROUP, { ["9lives"] = 96 })).toBe(false)
		expect(pcall(themes.declareApp, GROUP, { [1] = 96 })).toBe(false)
		expect(themes.appMetrics()[GROUP]).toBe(nil)
	end)

	it("refuses a value that is not a finite number", function()
		expect(pcall(themes.declareApp, GROUP, { tileMin = "96" })).toBe(false)
		expect(pcall(themes.declareApp, GROUP, { tileMin = 0 / 0 })).toBe(false)
		expect(pcall(themes.declareApp, GROUP, { tileMin = math.huge })).toBe(false)
		expect(pcall(themes.declareApp, GROUP, { tileMin = true })).toBe(false)
	end)

	it("refuses a non-table declaration and an illegal group name", function()
		expect(pcall(themes.declareApp, GROUP, 96)).toBe(false)
		expect(pcall(themes.declareApp, GROUP, "tileMin")).toBe(false)
		expect(pcall(themes.declareApp, "not a group", { tileMin = 96 })).toBe(false)
		expect(pcall(themes.declareApp, nil, { tileMin = 96 })).toBe(false)
		expect(pcall(themes.declareApp, "proof.sub", { tileMin = 96 })).toBe(false)
	end)
end)

describe("app metrics: a declared name is spellable", function()
	it("isMetricPath accepts a declared app name and refuses an undeclared one", function()
		expect(snapshot.isMetricPath("app.proof.tileMin")).toBe(false)
		withApp(PROOF, function()
			expect(snapshot.isMetricPath("app.proof.tileMin")).toBe(true)
			expect(snapshot.isMetricPath("app.proof.sponsor.rowHeight.landscape")).toBe(true)
			-- an undeclared name is refused exactly as `iconSizes.enormous` is
			expect(snapshot.isMetricPath("app.proof.tilemin")).toBe(false)
			expect(snapshot.isMetricPath("app.proof.nope")).toBe(false)
			-- a BRANCH is not a metric: only numeric leaves resolve
			expect(snapshot.isMetricPath("app.proof.sponsor")).toBe(false)
			expect(snapshot.isMetricPath("app")).toBe(false)
		end)
		expect(snapshot.isMetricPath("app.proof.tileMin")).toBe(false)
	end)

	it("a dim may carry an app metric name, and an undeclared one is refused at construction", function()
		withApp(PROOF, function()
			local UI = (Facet :: any).UI
			local form = UI.Box({ id = "Tile", width = { type = "fixed", px = "app.proof.tileMin" } })
			expect(form ~= nil).toBe(true)
			expect(pcall(UI.Box, { id = "Bad", width = { type = "fixed", px = "app.proof.tilemin" } })).toBe(false)
		end)
	end)

	it("resolveNumber answers an app name against a live snapshot", function()
		withApp(PROOF, function()
			local snap = snapshot.neutral()
			expect(snapshot.resolveNumber(snap, "app.proof.tileMin")).toBe(96)
			expect(snapshot.resolveNumber(snap, "-app.proof.tileMin")).toBe(-96)
			expect(snapshot.resolveNumber(snap, "app.proof.nope")).toBe(nil)
		end)
	end)
end)

describe("app metrics: every package carries them", function()
	it("resolves on Studio Neutral and on a package that never heard of them", function()
		withApp(PROOF, function()
			local parchment = (require)("../examples/themes/fantasy_parchment").build(themes)
			for _, package in { snapshot.neutralPackage(), parchment } do
				local snap = snapshot.resolve(package, nil, {})
				expect(snap.app.proof.tileMin).toBe(96)
				expect(snap.app.proof.sponsor.rowHeight.portrait).toBe(60)
			end
		end)
	end)

	it("publishes the section even for a group nobody declared", function()
		local snap = snapshot.resolve(snapshot.neutralPackage(), nil, {})
		expect(type(snap.app)).toBe("table")
		-- an UNDECLARED group is absent, not empty: the section is exactly what
		-- was declared and nothing else (other specs in this process declare their
		-- own groups, which is the point of grouping)
		expect(snap.app[GROUP]).toBe(nil)
	end)

	--[[ THE ORDERING TRAP, FOUND MIGRATING `p2_cartwheel` AND CLOSED IN THE
		FRAMEWORK. A host creates the environment and may commit a theme package's
		snapshot; the APP then builds and declares its namespace. The snapshot every
		screen is measured against was therefore resolved against the previous
		vocabulary — and a metric name that resolves to nothing is a missing
		DIMENSION, not an error, so the whole proof measured zero in silence.

		`forDisplay` is the one seam every environment read passes through, and it
		refreshes a base whose declaration generation is stale. The steady state is
		still the identity. ]]
	it("a snapshot resolved BEFORE the declaration still spells the names", function()
		local stale = snapshot.resolve(snapshot.neutralPackage(), nil, {})
		expect(stale.app[GROUP]).toBe(nil)
		withApp(PROOF, function()
			local presented = snapshot.forDisplay(stale, "Medium")
			expect(presented.app.proof.tileMin).toBe(96)
			expect(snapshot.forDisplay(stale, "Large").app.proof.tileMin).toBe(144)
			-- …and a snapshot resolved AFTER it is the identity at a near display,
			-- which is the guarantee the refresh must not cost
			local fresh = snapshot.resolve(snapshot.neutralPackage(), nil, {})
			expect(rawequal(snapshot.forDisplay(fresh, "Medium"), fresh)).toBe(true)
		end)
	end)

	--[[ …AND THE REFRESH IS KEYED BY VOCABULARY, NOT MERELY BY SNAPSHOT. Found
		live in the overflow sweep, which resolves its eight package snapshots once
		at module load and then mounts five proofs against them: the first proof
		declared, a stale base was refreshed and cached, the second proof declared —
		and every read of that base got the FIRST refresh back, which had never heard
		of the second group. A cache that cannot say which vocabulary it holds is a
		stale answer with a fast path in front of it. ]]
	it("a base refreshed for one group is refreshed again for the next", function()
		local stale = snapshot.resolve(snapshot.neutralPackage(), nil, {})
		themes.declareApp("alpha", { tileMin = 96 })
		expect(snapshot.forDisplay(stale, "Medium").app.alpha.tileMin).toBe(96)
		themes.declareApp("beta", { tileMin = 200 })
		local both = snapshot.forDisplay(stale, "Medium")
		expect(both.app.alpha.tileMin).toBe(96)
		expect(both.app.beta.tileMin).toBe(200)
		themes.declareApp("alpha", nil)
		themes.declareApp("beta", nil)
	end)
end)

describe("app metrics: the ten-foot ladder", function()
	--[[ THE HALF THE HAND-ROLLED SHIMS GOT WRONG. `p2_cartwheel` multiplied ONE
		of its four structural numbers by `metricScale` and left `chartH`, `heroH`
		and `previewMin` at their phone values, so a television measured a 96 -> 144
		tile minimum inside a 160px chart band that had not moved. A named metric
		cannot be half-applied. ]]
	it("classifies an app length as a length and scales it by the factor", function()
		withApp(PROOF, function()
			expect(snapshot.densityClassOf("app.proof.tileMin")).toBe("scale")
			expect(snapshot.densityClassOf("app.proof.sponsor.rowHeight.landscape")).toBe("scale")
			local base = snapshot.resolve(snapshot.neutralPackage(), nil, {})
			local tv = snapshot.forDisplay(base, "Large")
			expect(tv.app.proof.tileMin).toBe(96 * 1.5)
			expect(tv.app.proof.chartH).toBe(160 * 1.5)
			expect(tv.app.proof.sponsor.rowHeight.landscape).toBe(56 * 1.5)
			-- reversible, and the near display is still the identity
			expect(rawequal(snapshot.forDisplay(base, "Medium"), base)).toBe(true)
			expect(snapshot.forDisplay(tv, "Medium").app.proof.tileMin).toBe(96)
		end)
	end)

	--[[ …AND THE HALF A BLANKET RULE WOULD GET WRONG. A fraction multiplied by
		1.5 is 0.78 of a viewport, a count of 8 rows becomes 12, a 2.5 second toast
		becomes 3.75, and a type size scaled here is the 2.25x double-application
		the type floor already guards. The vocabulary is `controls.*`'s, unchanged:
		a name is a LENGTH unless one of its segments says otherwise. ]]
	it("classifies an app number whose name says it is not a length as exempt", function()
		withApp(PROOF, function()
			expect(snapshot.densityClassOf("app.proof.sponsor.mapFraction.landscape")).toBe("exempt")
			expect(snapshot.densityClassOf("app.proof.sponsor.toastDurationSeconds")).toBe("exempt")
			expect(snapshot.densityClassOf("app.proof.sponsor.listRowCount")).toBe("exempt")
			expect(snapshot.densityClassOf("app.proof.sponsor.rowNameTextSize")).toBe("exempt")
			local tv = snapshot.forDisplay(snapshot.resolve(snapshot.neutralPackage(), nil, {}), "Large")
			expect(tv.app.proof.sponsor.mapFraction.landscape).toBe(0.52)
			expect(tv.app.proof.sponsor.toastDurationSeconds).toBe(2.5)
			expect(tv.app.proof.sponsor.listRowCount).toBe(8)
			expect(tv.app.proof.sponsor.rowNameTextSize).toBe(18)
		end)
	end)
end)

describe("app metrics: a theme owns them like every other metric", function()
	it("a package may MOVE a declared app metric", function()
		withApp(PROOF, function()
			local moved, report = themes.define({
				base = themes.neutralPackage(),
				identity = { id = "app-moved", displayName = "Moved", schemaVersion = themes.SCHEMA, version = "1.0.0" },
				metrics = { app = { proof = { tileMin = 128, sponsor = { rowHeight = { landscape = 72 } } } } },
			})
			expect(moved ~= nil).toBe(true)
			if moved == nil then
				error(`themes.define refused: {refusal(report)}`)
			end
			local snap = snapshot.resolve(moved, nil, {})
			expect(snap.app.proof.tileMin).toBe(128)
			expect(snap.app.proof.sponsor.rowHeight.landscape).toBe(72)
			-- everything the package stayed silent about keeps the app's own number
			expect(snap.app.proof.chartH).toBe(160)
			expect(snap.app.proof.sponsor.rowHeight.portrait).toBe(60)
		end)
	end)

	--[[ REFUSE-DON'T-GUESS, on the package side too: a package that invents an
		app name (or misspells one) is authoring against a namespace it does not
		own, and a silent no-op there is a number that never moves and nobody can
		see not moving. ]]
	it("refuses a package that names an app metric the app never declared", function()
		withApp(PROOF, function()
			local invented = themes.define({
				base = themes.neutralPackage(),
				identity = {
					id = "app-invented",
					displayName = "Invented",
					schemaVersion = themes.SCHEMA,
					version = "1.0.0",
				},
				metrics = { app = { proof = { tilemin = 128 } } },
			})
			expect(invented ~= nil).toBe(true)
			expect(pcall(snapshot.resolve, invented, nil, {})).toBe(false)
		end)
	end)

	it("an override reaches an app metric, and an undeclared one still refuses", function()
		withApp(PROOF, function()
			local snap = snapshot.resolve(snapshot.neutralPackage(), nil, {}, { ["app.proof.tileMin"] = 111 })
			expect(snap.app.proof.tileMin).toBe(111)
			expect(pcall(snapshot.resolve, snapshot.neutralPackage(), nil, {}, { ["app.proof.nope"] = 1 })).toBe(false)
		end)
	end)

	it("metrics.tenFoot may name an app metric, and wins over the derived ladder", function()
		withApp(PROOF, function()
			local declared, report = themes.define({
				base = themes.neutralPackage(),
				identity = {
					id = "app-tenfoot",
					displayName = "TenFoot",
					schemaVersion = themes.SCHEMA,
					version = "1.0.0",
				},
				metrics = { tenFoot = { ["app.proof.tileMin"] = 200 } },
			})
			expect(declared ~= nil).toBe(true)
			if declared == nil then
				error(`themes.define refused: {refusal(report)}`)
			end
			local base = snapshot.resolve(declared, nil, {})
			expect(base.app.proof.tileMin).toBe(96)
			expect(snapshot.forDisplay(base, "Large").app.proof.tileMin).toBe(200)
		end)
	end)

	--[[ A PIXEL PACKAGE'S GRID REACHES THE APP SECTION TOO. `resolve` snaps every
		authored length onto the package's own unit so measure and paint agree on
		one coordinate system; an app length that skipped the snap would be the one
		number off the grid, and `forDisplay` snaps it at ten-foot either way — so
		the near answer would disagree with the distant one about which grid it is
		on. A non-length is left exactly where it is. ]]
	it("a pixel package snaps app lengths and leaves app non-lengths alone", function()
		withApp(PROOF, function()
			local quest = (require)("../examples/themes/pixel_quest").build(themes)
			local snap = snapshot.resolve(quest, nil, {})
			local unit = snap.pixelUnit
			expect(type(unit)).toBe("number")
			expect(snap.app.proof.tileMin % unit).toBe(0)
			expect(snap.app.proof.chartH % unit).toBe(0)
			expect(snap.app.proof.sponsor.mapFraction.landscape).toBe(0.52)
			expect(snap.app.proof.sponsor.listRowCount).toBe(8)
		end)
	end)
end)

describe("app metrics: the theme dump carries them", function()
	it("token_sync emits a record per declared app leaf a package authored", function()
		withApp(PROOF, function()
			local token_sync = require("../src/themes/token_sync") :: any
			local authored = themes.define({
				base = themes.neutralPackage(),
				identity = { id = "app-dump", displayName = "Dump", schemaVersion = themes.SCHEMA, version = "1.0.0" },
				metrics = { app = { proof = { tileMin = 128, sponsor = { rowHeight = { landscape = 72 } } } } },
			})
			local seen: { [string]: any } = {}
			for _, record in token_sync.records(authored) do
				seen[record.path] = record
			end
			expect(seen["app.proof.tileMin"] ~= nil).toBe(true)
			expect(seen["app.proof.tileMin"].value).toBe(128)
			expect(seen["app.proof.sponsor.rowHeight.landscape"].value).toBe(72)
			-- and the round trip: a dump reconstructs the authored section
			local rebuilt = token_sync.metricsFromRecords(token_sync.records(authored))
			expect(rebuilt.app.proof.tileMin).toBe(128)
			expect(rebuilt.app.proof.sponsor.rowHeight.landscape).toBe(72)
		end)
	end)
end)
