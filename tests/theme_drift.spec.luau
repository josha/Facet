--!strict
-- Theme DRIFT lint (ADR-0019 §2). A hardcoded metric inside a reusable control
-- is invisible in review and invisible to the suite — 44 is still 44 under
-- Studio Neutral — while quietly making that control immune to every theme. So
-- the check runs here, and it is proven to FAIL: a lint nobody has watched fail
-- is a lint nobody knows works.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")
local drift = require("../tools/lune/check_theme_drift")

describe("no reusable framework control hardcodes a theme-owned metric", function()
	it("the framework surface is clean", function()
		local result = drift.check()
		local detail = if result.ok then "" else "\n" .. table.concat(result.problems, "\n")
		expect(result.ok and true or error(`theme drift lint FAILED:{detail}`, 2)).toBe(true)
	end)

	it("it actually scanned the surface it claims to cover", function()
		local result = drift.check()
		-- src/controls/* plus the renderer and the presenter
		expect(result.counts.files >= 15).toBe(true)
		expect(result.counts.lines > 5000).toBe(true)
	end)

	--[[ NEGATIVE PROOF: inject each shape of violation and watch the lint catch it.

		SCOPED TO THE PLANTED FILE, ALWAYS (MAINT-4, 2026-08-17). These cases used
		to assert ABSOLUTE global counts — `#result.violations == 1`, `result.ok ==
		true` — which made every one of them a second, silent copy of "the
		framework surface is clean". One real violation ANYWHERE in `src/` reddened
		four unrelated mutation cases with messages naming the wrong file, so the
		instrument that exists to prove the lint works became the loudest source of
		misdirection the moment the lint had something to say.

		A mutation case has exactly one question: did the lint see THE LINE I
		PLANTED? So each case takes a baseline, plants its line, and asserts the
		DELTA in the planted file. Whether the rest of the tree is clean is the
		first case's job, and it says so by name. ]]
	local function inPlantedFile(result: any, file: string): { any }
		local mine: { any } = {}
		for _, violation in result.violations do
			if violation.file == file then
				table.insert(mine, violation)
			end
		end
		return mine
	end

	-- how many violations this file ALREADY has, so a planted one is a delta
	local function baselineFor(file: string): number
		return #inPlantedFile(drift.check(), file)
	end

	local function plantedIn(file: string, line: string): { any }
		local before = baselineFor(file)
		local result = drift.check({ injectFile = file, injectLine = line })
		local mine = inPlantedFile(result, file)
		expect(`{file}: planted violations {#mine - before}`).toBe(`{file}: planted violations 1`)
		return mine
	end

	it("catches a hardcoded dimension in a control", function()
		local file = "src/controls/chip.luau"
		local before = baselineFor(file)
		local result = drift.check({
			injectFile = file,
			injectLine = 'local synthetic = { type = "fixed", px = 44 }',
		})
		expect(result.ok).toBe(false)
		local mine = inPlantedFile(result, file)
		expect(#mine - before).toBe(1)
		expect(mine[#mine].what).toBe("dimension px")
		-- the message tells the author what to do instead
		local message: string? = nil
		for _, problem in result.problems do
			if string.find(problem, file, 1, true) ~= nil then
				message = problem
			end
		end
		expect(message ~= nil).toBe(true)
		expect(string.find(message :: string, "theme metric name", 1, true) ~= nil).toBe(true)
		expect(string.find(message :: string, "ALLOWLIST", 1, true) ~= nil).toBe(true)
	end)

	it("catches a hardcoded text size, gap, padding and named metric constant", function()
		for _, case in
			{
				{ line = 'local x = UI.Text({ id = "T", text = "x", textSize = 15 })', what = "textSize" },
				{ line = "local x = { gap = 12 }", what = "gap" },
				{ line = "local x = { padding = 9 }", what = "padding" },
				{ line = "local ROW_HEIGHT = 36", what = "named metric constant" },
			}
		do
			local mine = plantedIn("src/controls/label.luau", case.line)
			expect(mine[#mine].what).toBe(case.what)
		end
	end)

	it("catches drift in the renderer and the presenter too, not only in controls", function()
		for _, file in { "src/render/renderer.luau", "src/present/presenter.luau" } do
			local mine = plantedIn(file, "local HIT_FLOOR = 44")
			expect(mine[#mine].file).toBe(file)
		end
	end)

	it("zero is not a metric: 'this container adds no spacing' stays legal", function()
		local file = "src/controls/chip.luau"
		local before = baselineFor(file)
		local result = drift.check({ injectFile = file, injectLine = "local x = { gap = 0, padding = 0 }" })
		-- the DELTA is what this case is about: `result.ok` would also answer for
		-- every other file in the tree
		expect(#inPlantedFile(result, file) - before).toBe(0)
	end)

	it("a comment describing a literal is not a violation", function()
		local file = "src/controls/chip.luau"
		local before = baselineFor(file)
		local result = drift.check({ injectFile = file, injectLine = "-- the old height = 44 literal" })
		expect(#inPlantedFile(result, file) - before).toBe(0)
	end)

	it("every allowlist entry carries a real justification", function()
		expect(#drift.ALLOWLIST > 0).toBe(true)
		for _, entry in drift.ALLOWLIST do
			expect(type(entry.file)).toBe("string")
			expect(type(entry.match)).toBe("string")
			expect(#entry.why > 40).toBe(true) -- a reason, not a shrug
		end
	end)
end)

--[[ THE SECOND SCOPE: the TEACHING corpus (declarative-purity sweep, 2026-08-21).

	The lint used to exempt `examples/` on the stated ground that "an app author's
	literal is a legitimate opt-out". That is right for an app and wrong for the
	gallery, which is the reference a reader copies from — the purity audit measured
	539 raw literals on the three props the theme system owns, 40% of every such prop
	in the corpus against 22% in the shipping game it teaches. So the scope moved, and
	these cases are what makes the move a standing guard rather than a one-time sweep.

	SCOPED TO THE PLANTED FILE, ALWAYS — the same MAINT-4 discipline as above, for
	the same reason: an absolute count here would be a second silent copy of "the
	corpus is clean" and would misname the file when it had something to say. ]]
describe("the teaching corpus spells the values the theme system already names", function()
	local EXAMPLE = "examples/gallery/scenarios/callout.luau"

	local function inFile(result: any, file: string): { any }
		local mine: { any } = {}
		for _, violation in result.violations do
			if violation.file == file then
				table.insert(mine, violation)
			end
		end
		return mine
	end

	local function exampleViolations(result: any): { any }
		local mine: { any } = {}
		for _, violation in result.violations do
			if violation.scope == "example" then
				table.insert(mine, violation)
			end
		end
		return mine
	end

	local function plantedDelta(line: string, opts: any?): { any }
		local before = #inFile(drift.check(opts), EXAMPLE)
		local options: any = { injectFile = EXAMPLE, injectLine = line }
		if opts ~= nil then
			for key, value in opts :: any do
				options[key] = value
			end
		end
		local mine = inFile(drift.check(options), EXAMPLE)
		local planted: { any } = {}
		for index = before + 1, #mine do
			table.insert(planted, mine[index])
		end
		return planted
	end

	it("the corpus is clean", function()
		local result = drift.check()
		local mine = exampleViolations(result)
		local detail = ""
		for _, violation in mine do
			detail ..= `\n{violation.file}:{violation.line}: {violation.what}`
		end
		expect(#mine == 0 or error(`the teaching corpus has {#mine} theme-drift violation(s):{detail}`, 2)).toBe(true)
	end)

	it("it actually scanned the corpus it claims to cover", function()
		local counts = drift.check().counts
		-- 165 example files / ~70,000 lines is the corpus the audit measured
		expect(counts.exampleFiles >= 150).toBe(true)
		expect(counts.exampleLines > 50000).toBe(true)
	end)

	--[[ THE POSITIVE DIRECTION: a literal a theme name RESOLVES TO is caught. ]]
	it("catches a spacing literal a space step already names", function()
		for _, case in
			{
				{ line = "local x = UI.HStack({ gap = 8 })", names = '"s"' },
				{ line = "local x = UI.VStack({ gap = 4 })", names = '"xs"' },
				{ line = "local x = UI.Grid({ rowGap = 16 })", names = '"m"' },
				{ line = "local x = UI.Screen({ padding = 24 })", names = '"l"' },
			}
		do
			local planted = plantedDelta(case.line)
			expect(`{case.line}: planted {#planted}`).toBe(`{case.line}: planted 1`)
			expect(string.find(planted[1].what, case.names, 1, true) ~= nil).toBe(true)
			expect(planted[1].scope).toBe("example")
		end
	end)

	it("catches a text size a typography role already names, and names the role", function()
		local planted = plantedDelta('local x = UI.Text({ text = "x", textSize = 12 })')
		expect(#planted).toBe(1)
		expect(string.find(planted[1].what, '"caption"', 1, true) ~= nil).toBe(true)
	end)

	--[[ THE NEGATIVE DIRECTION, and it is the half that makes the gate mechanical
		rather than a judgement call. A number NO name resolves to is not reported,
		because there is nothing to rewrite it to — `gap = 6` is the corpus's single
		most common spacing value and the framework concedes in `snapshot.luau` that
		no space step is 6. The day the scale grows that rung this case flips, which
		is exactly the alarm it should be. ]]
	it("a value no name resolves to is NOT reported — there is nothing to rewrite it to", function()
		for _, line in
			{
				"local x = UI.HStack({ gap = 6 })",
				"local x = UI.HStack({ gap = 2 })",
				"local x = UI.VStack({ padding = 12 })",
				'local x = UI.Text({ text = "x", textSize = 13 })',
			}
		do
			expect(`{line}: planted {#plantedDelta(line)}`).toBe(`{line}: planted 0`)
		end
	end)

	it("zero stays legal in the corpus too: 'this container adds no spacing'", function()
		expect(#plantedDelta("local x = UI.HStack({ gap = 0, padding = 0 })")).toBe(0)
	end)

	it("a prop the theme system does not own is not this scope's business", function()
		-- the framework scope reports `px`/`min`/`height`; the example scope
		-- deliberately does not, because a demo canvas is structure
		expect(#plantedDelta('local x = { width = { type = "fixed", px = 8 } }')).toBe(0)
	end)

	--[[ THE MARKERS, both directions each. ]]
	it("a THEME-OPT-OUT marker with a reason keeps the literal; one without does not", function()
		expect(#plantedDelta("local x = UI.HStack({ gap = 8 }) -- THEME-OPT-OUT: the fixture's subject is the hatch")).toBe(
			0
		)
		-- ...and a marker with no reason is a suppression comment, which is refused
		expect(#plantedDelta("local x = UI.HStack({ gap = 8 }) -- THEME-OPT-OUT: nope")).toBe(1)
		expect(#plantedDelta("local x = UI.HStack({ gap = 8 }) -- THEME-OPT-OUT:")).toBe(1)
	end)

	it("a marker in the comment ABOVE excuses the next literal, and only that one", function()
		expect(
			#plantedDelta("-- THEME-OPT-OUT: this one is deliberate and here is why\nlocal x = UI.HStack({ gap = 8 })")
		).toBe(0)
		-- ONE MARKER, ONE LITERAL: the second is still reported
		expect(
			#plantedDelta(
				"-- THEME-OPT-OUT: this one is deliberate and here is why\n"
					.. "local x = UI.HStack({ gap = 8 })\n"
					.. "local y = UI.HStack({ gap = 4 })"
			)
		).toBe(1)
	end)

	it("a PROBE-EXEMPT region excuses what is inside it, and an unclosed one is itself a violation", function()
		expect(
			#plantedDelta(
				"-- PROBE-EXEMPT BEGIN: this block is instrument, not example\n"
					.. "local x = UI.HStack({ gap = 8 })\n"
					.. "local y = UI.HStack({ gap = 4 })\n"
					.. "-- PROBE-EXEMPT END"
			)
		).toBe(0)
		local unclosed = plantedDelta(
			"-- PROBE-EXEMPT BEGIN: this block is instrument, not example\nlocal x = UI.HStack({ gap = 8 })"
		)
		expect(#unclosed).toBe(1)
		expect(string.find(unclosed[1].what, "unclosed", 1, true) ~= nil).toBe(true)
	end)

	--[[ THE FILE LISTING AND ITS GUARD, driven from the case so both directions
		are proved against real corpus files rather than asserted. ]]
	it("a PROBE_EXEMPT_FILES listing silences the file — and is refused when its header does not say so", function()
		--[[ `callout.luau` is an ordinary example and carries no PROBE-EXEMPT header,
			so listing it proves BOTH halves at once: the listing DOES silence the
			planted literal, and the missing header is reported in its place. A
			listing that silenced a file without telling its reader would be the
			invisible exemption this guard exists to refuse. ]]
		local planted = "local x = UI.HStack({ gap = 8 })"
		local listed = { { file = EXAMPLE, why = "a synthetic listing, for this case only" } }
		local function census(opts: any): string
			local literals, guards = 0, 0
			for _, violation in inFile(drift.check(opts), EXAMPLE) do
				if string.find(violation.what, "PROBE_EXEMPT_FILES listing", 1, true) ~= nil then
					guards += 1
				else
					literals += 1
				end
			end
			return `literals {literals}, guard findings {guards}`
		end
		-- unlisted: the planted literal is reported and no guard fires
		expect(census({ injectFile = EXAMPLE, injectLine = planted })).toBe("literals 1, guard findings 0")
		-- listed: the literal goes quiet and the missing header takes its place
		expect(census({ injectFile = EXAMPLE, injectLine = planted, probeExemptFiles = listed })).toBe(
			"literals 0, guard findings 1"
		)
	end)

	it("the shipped listing is guarded by real headers: every listed file says so in its own", function()
		expect(#drift.PROBE_EXEMPT_FILES > 0).toBe(true)
		for _, entry in drift.PROBE_EXEMPT_FILES do
			expect(#entry.why > 40).toBe(true) -- a reason, not a shrug
		end
		-- and the guard is live: with the shipped list the corpus is clean, which is
		-- only true because each listed file carries the marker its reader needs
		expect(#exampleViolations(drift.check())).toBe(0)
	end)

	--[[ THE COUPLING CLASS (review 2026-08-22, HIGH-1).

		"The rewrite cannot move one pixel" is a STUDIO-NEUTRAL, SCALE-1.0 guarantee
		and nothing more: a name resolves per solve against the ACTIVE snapshot, and a
		distance-adapted one scales the whole `space` section, so `"xs"` is 4 at arm's
		length and 6 on a television. That is the feature. It becomes a DEFECT in one
		shape — when the same file also predicts a box from a raw constant, so naming
		the literal moves one side of an arithmetic identity and leaves the other. The
		proven instance: the perf lab's row spent `padding = 4`, its slot was predicted
		from `ROW_PADDING_V = 16`, and the swap grew the row 77 -> 81px on a 1920x1078
		television against an unmoved 60px slot.

		So a finding in a coupled file is REPORTED DIFFERENTLY rather than refused —
		refusing would silence the lint across nine files that today carry correctly
		named sites, and the failure was never that the swap happened, it was that
		nobody was told the file predicts its own geometry. ]]
	it("a finding in a file that predicts geometry from raw constants says so, and names them", function()
		-- the perf lab's row declares `ROW_GAP` / `ROW_PADDING_HEADROOM` /
		-- `TEXT_BLOCK` and spends them in arithmetic. It replaced `card_rail`, which
		-- left the coupled set on 2026-08-22 when `viewportExtent = "auto"` and
		-- `crossExtent = "hug"` took both of its predictions away.
		local coupledFile = "examples/performance/lab/rows.luau"
		expect(`{coupledFile} is coupled: {#drift.coupledConstants(fs.readFile(coupledFile)) > 0}`).toBe(
			`{coupledFile} is coupled: true`
		)
		local before = #inFile(drift.check(), coupledFile)
		local result = drift.check({ injectFile = coupledFile, injectLine = "local x = UI.HStack({ gap = 8 })" })
		local mine = inFile(result, coupledFile)
		expect(#mine - before).toBe(1)
		local planted = mine[#mine]
		expect(`coupling recorded: {planted.coupled ~= nil and #planted.coupled > 0}`).toBe("coupling recorded: true")
		local message: string? = nil
		for _, problem in result.problems do
			if string.find(problem, coupledFile, 1, true) ~= nil then
				message = problem
			end
		end
		expect(message ~= nil).toBe(true)
		-- the message names the class, the ladder, the constants and BOTH exits
		for _, phrase in { "COUPLED", "Studio Neutral ONLY", "ROW_GAP", "THEME-OPT-OUT", "rowPaddingV" } do
			expect(`the coupled message says '{phrase}': {string.find(message :: string, phrase, 1, true) ~= nil}`).toBe(
				`the coupled message says '{phrase}': true`
			)
		end
	end)

	it("...and an UNCOUPLED file gets the plain message, so the distinction is real", function()
		-- `flow_wrap` declares no raw geometry constant it spends in arithmetic
		expect(`{EXAMPLE} is coupled: {#drift.coupledConstants(fs.readFile(EXAMPLE)) > 0}`).toBe(
			`{EXAMPLE} is coupled: false`
		)
		local result = drift.check({ injectFile = EXAMPLE, injectLine = "local x = UI.HStack({ gap = 8 })" })
		local message: string? = nil
		for _, problem in result.problems do
			if string.find(problem, EXAMPLE, 1, true) ~= nil then
				message = problem
			end
		end
		expect(message ~= nil).toBe(true)
		expect(string.find(message :: string, "COUPLED", 1, true) == nil).toBe(true)
	end)

	--[[ THE COUPLED SET IS PINNED, so a file entering or leaving it is visible in
		review rather than silent. This is the same discipline the route census in
		`overflow_sweep.spec` uses: when the corpus legitimately changes, this list
		changes with it and the next author RE-READS the case rather than deleting it. ]]
	it("the coupled set is exactly these files — a new one is a decision, not a diff", function()
		local names: { string } = {}
		for _, file in drift.exampleFiles() do
			local coupled = drift.coupledConstants(fs.readFile(file))
			if #coupled > 0 then
				table.insert(names, `{file} [{table.concat(coupled, " ")}]`)
			end
		end
		table.sort(names)
		expect(table.concat(names, "\n")).toBe(table.concat({
			"examples/gallery/client/demo_picker.luau [BAR_HEIGHT]",
			"examples/gallery/client/theme_picker.luau [BAR_HEIGHT]",
			"examples/gallery/scenarios/hud.luau [HUD_FLOOR_PX]",
			"examples/gallery/scenarios/perf_capture.luau [ROSTER_ROW_PADDING viewportExtent=<literal>]",
			"examples/performance/lab/levers.luau [itemExtent=<literal>]",
			"examples/performance/lab/perf_lab.luau [EXTENT_GAP EXTENT_LINE_H EXTENT_PAD SCREEN_GAP SCREEN_PADDING]",
			"examples/performance/lab/rows.luau [COMPACT_CONTROLS_WIDTH COMPACT_LINE_GAP COMPACT_TEXT_BLOCK "
				.. "ROW_GAP ROW_PADDING_HEADROOM TEXT_BLOCK]",
			"examples/reference/p2_cartwheel/screens/plaza.luau [ORBIT_RADIUS]",
		}, "\n"))
	end)

	--[[ THE LINT NO LONGER READS ITS OWN PROSE. Only the OPENING line of a long
		comment starts with a dash pair, so every continuation line used to look like
		code — and this repository writes most of its prose in long comments. It bit
		the moment the HIGH-1 fix wrote `padding = 4` into one. ]]
	it("a metric assignment inside a LONG comment is not a violation", function()
		expect(#plantedDelta("--[[ the old\npadding = 8\nliteral lived here ]]")).toBe(0)
		-- ...and the block really closes: the line AFTER it is still checked
		expect(#plantedDelta("--[[ prose ]]\nlocal x = UI.HStack({ gap = 8 })")).toBe(1)
		-- ...and a LEVEL MARKER cannot be closed by the wrong level
		expect(#plantedDelta("--[=[ prose ]]\npadding = 16\nstill inside ]=]")).toBe(0)
	end)

	it("the naming vocabulary is READ FROM THE FRAMEWORK, not restated here", function()
		-- a package that re-ladders its type scale re-ladders this lint with it, so
		-- the map has to come from the snapshot. Spot-check the ladder's ends.
		expect(drift.NAMES_FOR.type[12][1]).toBe("caption")
		expect(drift.NAMES_FOR.type[24][1]).toBe("title")
		expect(drift.NAMES_FOR.space[4][1]).toBe("xs")
		expect(drift.NAMES_FOR.space[40][1]).toBe("xl")
		-- ...and the ladder order decides the collision: `control` 18 outranks the
		-- derived `numeral` 18, `s` 8 outranks the derived `gutter` 8
		expect(drift.NAMES_FOR.type[18][1]).toBe("control")
		expect(drift.NAMES_FOR.space[8][1]).toBe("s")
	end)
end)
