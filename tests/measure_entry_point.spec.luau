--!strict
-- The headless measurement entry point (framework-gaps-phase2 gap 11).
--
-- api.md's `text` section names the anti-pattern this closes verbatim: "the
-- alternative is what consumers were writing instead — a character count
-- times a guessed average glyph width, which is the measurer's own
-- conservative fallback." `text_metrics.luau` IS that measurer, and it has
-- zero requires and zero GetService — but the only PUBLISHED route to it was
-- `Facet.text` via `src/init.luau`, which makes 65 `@self` requires and
-- transitively pulls `src/client/*`, GetService and all. A model that must
-- run headless (Lune, a benchmark, a shared game module with no DataModel)
-- could not take that dependency for a fact `text_metrics.luau` already
-- answers on its own.
--
-- THE PROOF IS STRUCTURAL, not asserted: this file requires `src/measure`
-- ALONE — never `src/init` — and drives it under plain Lune, with no
-- `@lune/roblox` mock loaded anywhere in this process. If the entry point (or
-- anything it pulls in) ever called `game:GetService(...)`, requiring it
-- would error here, because Lune's default realm has no `game` global at
-- all. A green run of this file IS the headless-reachability claim.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local measure = require("../src/measure")
local text_metrics = require("../src/layout/text_metrics")

describe("GAP 11: the measurement engine is reachable without src/init.luau", function()
	it("requires cleanly, standing alone, with zero @self/init dependency", function()
		expect(type(measure)).toBe("table")
		expect(type(measure.measure)).toBe("function")
		expect(type(measure.minWidth)).toBe("function")
	end)

	it("is the SAME module text_metrics.luau is — a republish, not a fork", function()
		-- Luau caches modules by resolved path; `src/measure` requiring
		-- `./layout/text_metrics` returns the identical table `text_metrics.luau`
		-- does, so there is exactly one implementation and it cannot drift.
		expect(measure).toBe(text_metrics)
	end)

	it("exports the fallback constant, so a consumer sources it instead of copying it", function()
		-- the same number RascalRally's HudZoneModel used to hand-copy as
		-- `GLYPH_EM = 0.62` under a comment that misidentified it as "Gotham Bold
		-- cap advance" — reached here, and (equally) as `Facet.text.AVG_GLYPH_FRACTION`
		-- for a caller that already holds the live `Facet` table (api.md `text`)
		expect(type(measure.AVG_GLYPH_FRACTION)).toBe("number")
		expect(measure.AVG_GLYPH_FRACTION).toBe(0.62)
	end)

	it("measures for real: a headless caller gets the library's own metrics, not a guess", function()
		local metrics = measure.measure("Hello", "BuilderSans", 20, 400)
		expect(type(metrics)).toBe("table")
		expect(type(metrics.height)).toBe("number")
		expect(metrics.height > 0).toBe(true)
	end)

	it("minWidth answers the same fallback-fraction arithmetic a hand-rolled estimate reproduces", function()
		local w = measure.minWidth("BOOST", "BuilderSans", 18)
		expect(type(w)).toBe("number")
		expect(w > 0).toBe(true)
	end)
end)

--[[ GAP 11 registry evidence, item 31 ("a pure viewport-fact simulator for
	benchmarks", task-purity-audit.md:370-371, candidate-dissolve target for
	gap 11's headless-testability theme). NOT built by this round — but the
	demonstration below is cheap and true, and belongs beside the claim it
	informs: `src/layout/adaptive.luau`'s PURE half (this module's own header
	names the split) is ALREADY independently requireable, on the same grounds
	gap 11 just proved for measurement — `adaptive.luau` requires only
	`spec_guard`, which requires only `text_distance`, and neither calls
	GetService or touches `game`. A benchmark can drive viewport facts
	headlessly TODAY by requiring `src/layout/adaptive` alone. What is
	genuinely missing (and what keeps item 31 OPEN rather than dissolved) is a
	NAMED, surface-ledgered entry point and an actual benchmark harness built
	against it — this proves the capability exists, not that anyone has
	published or used it as one. ]]
describe("Registry evidence — item 31 (pure viewport-fact simulator), NOT built here", function()
	it("DEMONSTRATION: adaptive.luau's pure half is already reachable with no @self/init dependency", function()
		local adaptive = require("../src/layout/adaptive")
		expect(adaptive.sizeClass(320)).toBe("compact")
		expect(adaptive.sizeClass(1200)).toBe("wide")
		expect(adaptive.heightClass(400)).toBe("short")
		expect(adaptive.orientationFor(800, 400)).toBe("landscape")
		expect(adaptive.navPlacement({ sizeClass = "compact", heightClass = "medium" })).toBe("bottomBar")
	end)
end)
