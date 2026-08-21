--!strict
--[[ THE DEFAULT PAINT PATH IS THE ROBLOX STYLESHEET (director ruling, 2026-08-21).

	WHAT CHANGED. `native_style.DEFAULT_ENABLED` was `false` for the whole
	native-stylesheets stage: sheet paint was opt-in per target, and a
	`screen_target.new({})` with no `nativeStyle` opt took the explicit-write
	path. The game director ruled on 2026-08-21 that native StyleSheets become
	Facet's DEFAULT, and the record is ADR-0040 row B-15 (a real product-behaviour
	change riding an unreleased `0.10.0`, which is the only thing that makes it
	legal).

	WHY THIS FILE EXISTS AT ALL, and it is the finding that motivated it: NOTHING
	IN THE REPOSITORY PINNED THE DEFAULT. `DEFAULT_ENABLED` appeared in exactly two
	source lines and no spec, because the one consumer that reads it —
	`screen_target.new` — needs `Players.LocalPlayer` and a DataModel and so cannot
	run headlessly at all. So the library's most consequential single boolean could
	have been flipped, or flipped BACK, by an edit no gate could see. The decision
	it encodes is now a pure function (`native_style.resolveOpt`) that the target
	calls instead of re-deriving, which is what gives the default a witness.

	THE FOUR CLAIMS, and each of them was RED before the flip:

	  1. the LIBRARY DEFAULT is sheet paint — an absent opt resolves to `true`;
	  2. the ESCAPE HATCH SURVIVES — an explicit `false` still refuses it, which is
	     what keeps the explicit-write path a first-class tested path rather than a
	     corpse. `Facet_ForceStyleFallback` (the gallery A/B's forced arm) and any
	     game passing `nativeStyle = false` both ride this one branch;
	  3. the SCREEN TARGET really routes through the seam, so the pins above are
	     about the shipped decision and not about a function nobody calls;
	  4. the RECORD exists — ADR-0040 carries the row, because the record is what
	     makes an unreleased breaking change legal (ADR-0040 Decision 1).

	AND THE GALLERY'S A/B DRIVER, whose precedence had to survive the flip: the
	forced-fallback attribute still wins over everything, `Facet_NativeStyle = true`
	is now redundant-but-harmless, and "neither set" now means the LIBRARY DEFAULT
	rather than a hardcoded `false`.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")
local native_style = require("../src/client/native_style")
local paint_mode = require("../examples/gallery/client/paint_mode")

local RECORD = "docs/adr/ADR-0040-unreleased-breaking-changes.md"
local TARGET = "src/client/screen_target.luau"

describe("the library default paint path (ADR-0040 B-15)", function()
	it("the default IS sheet paint — the flag itself, read off the module", function()
		expect(native_style.DEFAULT_ENABLED).toBe(true)
	end)

	it("NO opt resolves to the library default, rather than to `false`", function()
		-- `nil` is the absence of a choice, and the absence of a choice is what
		-- the library's default answers. This is the whole flip.
		expect(native_style.resolveOpt(nil)).toBe(true)
	end)

	it("an explicit `false` STILL refuses sheet paint — the per-target escape hatch", function()
		-- the branch the explicit-write path lives on. `Facet_ForceStyleFallback`,
		-- the NSS-A10 parity arm, and any game that wants the bespoke painter all
		-- arrive here, and the flip must not have taken it with it.
		expect(native_style.resolveOpt(false)).toBe(false)
	end)

	it("an explicit `true` or a config table passes through UNTOUCHED", function()
		expect(native_style.resolveOpt(true)).toBe(true)
		-- identity, not a copy: `screen_target` reads `.handle`, `.model`,
		-- `.host`, `.theme` and `.transitions` off the object it was handed, and
		-- a resolver that rebuilt the table would drop every key it did not know
		local config = { theme = "Light", transitions = true }
		expect(native_style.resolveOpt(config)).toBe(config)
	end)

	it("the resolver NEVER answers `nil`, so one comparison decides the path", function()
		-- `screen_target`'s condition is `nativeOpt ~= false`. A resolver that
		-- could return `nil` would make that condition true for "no answer",
		-- which is the shape of the original defect in reverse.
		for _, input in { { "absent" }, { false }, { true } } do
			local answer = native_style.resolveOpt(if input[1] == "absent" then nil else input[1])
			expect(answer ~= nil).toBe(true)
		end
	end)

	--[[ THE SEAM IS REALLY THE ONE THE TARGET USES. A pure function agrees with
		itself; what it cannot say is that the shipped adapter asks it. The target
		cannot be constructed headlessly, so its source is the witness — and the
		second half is what matters: no SECOND copy of the default rule may exist
		beside the call, which is exactly how the rule got to be untested. ]]
	it("`screen_target` resolves its opt through the seam, and holds no second copy", function()
		local source = fs.readFile(TARGET)
		expect(string.find(source, "native_style.resolveOpt(", 1, true) ~= nil).toBe(true)
		-- the flag is named ONCE in that file — inside the comment that explains
		-- the call — and never re-branched on
		expect(string.find(source, "nativeOpt = native_style.DEFAULT_ENABLED", 1, true)).toBeNil()
	end)

	--[[ WHO THE DEFAULT DOES NOT SWEEP, and this case is here because the flag's
		own comment claimed two exemptions and the code only had one.

		`billboard_target` has always passed an explicit `false` — the billboard
		contract stays conservative until an integrated billboard drive proves the
		path. `edit_preview` did NOT, and the difference matters in a way a
		screenshot cannot show: the preview runs in the STUDIO EDIT DataModel, where
		`native_style.ensure` would seed a persistent `FacetStyle` StyleSheet that
		the next place save commits. That module's own header is emphatic about
		never committing preview furniture into a place file (verifier F5), and the
		flag's comment recorded the intent that the preview be unaffected — so the
		flip made the intent true rather than discovering it in a diff. It costs
		nothing visually: the adoption evidence measured the two paths byte-equal
		on every mapped property, so the preview shows what the game shows either
		way, and the one that writes nothing into the place is the one to take. ]]
	it("the two exemptions really pass an explicit choice, so the default cannot sweep them", function()
		local silent: { string } = {}
		for _, path in { "src/client/billboard_target.luau", "src/client/edit_preview.luau" } do
			local source = fs.readFile(path)
			if string.find(source, "nativeStyle = false", 1, true) == nil then
				table.insert(silent, `{path} names no explicit \`nativeStyle = false\``)
			end
		end
		expect(`swept:{table.concat(silent, "; ")}`).toBe("swept:")
	end)

	it("the flip is RECORDED in ADR-0040, which is what makes it legal", function()
		local adr = fs.readFile(RECORD)
		local missing: { string } = {}
		if string.find(adr, "native_style.DEFAULT_ENABLED", 1, true) == nil then
			table.insert(missing, "ADR-0040 does not record the `native_style.DEFAULT_ENABLED` flip")
		end
		-- ...and it records what the escape hatch is, because a breaking row that
		-- does not name the way out is half a record
		if string.find(adr, "`nativeStyle = false`", 1, true) == nil then
			table.insert(missing, "ADR-0040's row does not name `nativeStyle = false` as the opt-out")
		end
		expect(`unrecorded:{table.concat(missing, "; ")}`).toBe("unrecorded:")
	end)
end)

--[[ ═══ THE GALLERY'S A/B DRIVER, AFTER THE FLIP ═══════════════════════════════

	The place that exercises both paint paths live is the gallery, through three
	workspace attributes. The flip changes exactly one of its three answers, and
	the other two are the ones a careless flip would have broken.
]]
describe("the gallery A/B driver's precedence survives the flip", function()
	local function selectors(over: { [string]: boolean }?): paint_mode.Selectors
		local s = { native = false, fallback = false, transitions = false }
		for key, value in over or {} do
			(s :: any)[key] = value
		end
		return s
	end

	it("NEITHER SET -> no opt, so the place takes the LIBRARY default", function()
		-- the one answer the flip moves. It was `false`, which would have left the
		-- gallery pinned to the explicit-write path forever after the default
		-- changed underneath it — the framework's own demo place being the last
		-- consumer unable to see the framework's own default.
		expect(paint_mode.decide(selectors())).toBe(nil)
	end)

	it("FORCED FALLBACK WINS OVER EVERYTHING — including an explicit opt-in", function()
		expect(paint_mode.decide(selectors({ fallback = true }))).toBe(false)
		expect(paint_mode.decide(selectors({ fallback = true, native = true }))).toBe(false)
		expect(paint_mode.decide(selectors({ fallback = true, native = true, transitions = true }))).toBe(false)
	end)

	it("an explicit opt-in is REDUNDANT-BUT-HARMLESS: it still carries transitions", function()
		local opt = paint_mode.decide(selectors({ native = true }))
		expect(type(opt)).toBe("table")
		expect((opt :: any).transitions).toBe(false)
		local withTransitions = paint_mode.decide(selectors({ native = true, transitions = true }))
		expect((withTransitions :: any).transitions).toBe(true)
	end)

	it("the transitions attribute alone opts in, because it cannot mean anything else", function()
		-- before the flip `Facet_NativeTransitions` did nothing unless
		-- `Facet_NativeStyle` was set beside it; with sheet paint the default,
		-- an attribute whose only purpose is enhancing sheet paint asking for
		-- nothing would be a dead switch in the place that demonstrates it
		local opt = paint_mode.decide(selectors({ transitions = true }))
		expect(type(opt)).toBe("table")
		expect((opt :: any).transitions).toBe(true)
	end)

	--[[ THE BOOTSTRAP REALLY ASKS. Same technique and same reason as
		`gallery_boot_mode.spec.luau`: the LocalScript cannot run here, so its call
		is read back out of the source, and each attribute is read EXACTLY ONCE —
		a count, because "the literal never appears" would be satisfied by a split
		string and "it appears" would be satisfied by the second reader that is the
		defect. ]]
	it("the bootstrap reads each attribute once, into the decision", function()
		local source = fs.readFile("examples/gallery/client/init.client.luau")
		local call = string.match(source, "paint_mode%.decide%((%b{})")
		assert(call ~= nil, "init.client.luau no longer calls paint_mode.decide({ ... })")
		for _, attribute in { "Facet_NativeStyle", "Facet_ForceStyleFallback", "Facet_NativeTransitions" } do
			local read = `GetAttribute("{attribute}")`
			local count, from = 0, 1
			while true do
				local at = string.find(source, read, from, true)
				if at == nil then
					break
				end
				count += 1
				from = at + 1
			end
			expect(`{attribute} read {count} time(s)`).toBe(`{attribute} read 1 time(s)`)
			expect(string.find(call :: string, read, 1, true) ~= nil).toBe(true)
		end
	end)
end)
