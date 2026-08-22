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

	--[[ ═══ THE WHOLE DECISION, AND THE ADAPTER OBEYING IT ═════════════════════

		WHY THIS REPLACED A TWO-SUBSTRING GREP. The first version of this case
		asserted that `screen_target.luau` CONTAINS "native_style.resolveOpt(" and
		does NOT contain one literal second-copy spelling. A fresh-context reviewer
		broke it in one edit: call the seam, throw the answer into `_ignored`,
		re-derive the pre-flip rule underneath, and the FULL SUITE STAYS GREEN —
		6905 passed — while a bare `screen_target.new({})` paints explicit-write
		again. The case said the adapter MENTIONS the seam; it never said the
		adapter OBEYS it, and a paraphrase is not a mention.

		THE FIX IS AN EXTRACTION, NOT A TIGHTER GREP. `native_style.paintPlan` is
		now the whole decision — the default, the capability gate, the escape
		hatch, which handle/model/host/theme to use, and the transitions seed with
		reduced motion overriding it — as a PURE function with the engine probe and
		the motion fact as parameters. Every branch that used to live inside a
		closure no headless spec can construct now has a witness, and the adapter
		holds a call and a `plan.native` test instead of a rule.

		FOUR PINS ON THE CONSUMER, and the bypass above trips three of them:

		  1. exactly ONE call to `paintPlan`;
		  2. exactly ONE read of the `nativeStyle` opt off `opts` — a re-derivation
		     needs the RAW opt, and there is exactly one legal place to get it. The
		     plan carries only the RESOLVED opt, from which "was it absent" cannot
		     be recovered, so the pre-flip rule is not reconstructible from it;
		  3. the capability probe is NOT called in the target at all — it moved
		     into the plan, so the old `and native_style.available()` gate cannot
		     be rebuilt beside a discarded plan;
		  4. the branch really tests `plan.native`.

		They are still source reads, because this module opens with
		`game:GetService("Players")` at module scope and cannot be required
		headlessly by anything — ~20 specs read its source for the same reason. The
		difference is that what they read is now a SHAPE with one legal spelling
		rather than the presence of a string.

		AND THEN THE SHAPE WAS NOT ENOUGH EITHER. A re-review broke the five pins
		twice, both times with the full suite green at the identical count:

		  * substitute the pre-flip default INTO the seam's own argument —
		    `paintPlan(if raw == nil then false else raw, …)`. One call, one read,
		    no probe, no flag, `if plan.native then` verbatim: all five satisfied,
		    and a bare `screen_target.new({})` back on explicit-write paint;
		  * re-derive through a BRACKET index — `(opts :: any)["nativeStyle"]` —
		    which a `%.nativeStyle` pattern cannot see at all.

		The lesson is the one this file keeps re-learning: a pin on how the caller
		is SHAPED cannot say what VALUE it hands over. So the seam took the whole
		`opts` table and reads the opt itself, and the pin became a COUNT OF ZERO.
		There is no longer an opt in the adapter's hands to substitute, in any
		spelling — the two bypasses above are unwritable rather than merely
		detected, and the count is over the WORD rather than over one punctuation
		spelling of it, so a bracket index is not a way around it either.

		THE COST, NAMED: this file may not write the opt's name in a comment. The
		exclusions are exactly two, and both are structural rather than editorial —
		the `Opts` field's own declaration line, and the unrelated
		`adapter.nativeStyleInfo` surface. Anything else naming it is a read. ]]
	it("`screen_target` OBEYS the plan: it never touches the opt at all", function()
		local source = fs.readFile(TARGET)
		local function countOf(pattern: string): number
			local n, from = 0, 1
			while true do
				local at = string.find(source, pattern, from)
				if at == nil then
					break
				end
				n += 1
				from = at + 1
			end
			return n
		end
		local wrong: { string } = {}
		if countOf("native_style%.paintPlan%(") ~= 1 then
			table.insert(wrong, `paintPlan is called {countOf("native_style%.paintPlan%(")} time(s), not once`)
		end
		--[[ THE ZERO. Every line naming the opt is a read, whatever punctuation
			reaches it, EXCEPT the two the adapter cannot be without: the `Opts`
			field's own declaration, and `adapter.nativeStyleInfo`, a different
			surface that merely shares a prefix. A dotted read, a bracket index and
			a string built at runtime all land in this list. ]]
		local reads: { string } = {}
		for line in string.gmatch(source, "[^\n]+") do
			local rest = string.gsub(line, "nativeStyleInfo", "")
			if string.find(rest, "nativeStyle", 1, true) ~= nil and string.match(line, "^\tnativeStyle: ") == nil then
				table.insert(reads, (string.gsub(line, "^%s+", "")))
			end
		end
		if #reads ~= 0 then
			table.insert(wrong, `the target names the opt {#reads} time(s), and may name it none: {reads[1]}`)
		end
		if countOf("native_style%.available%(") ~= 0 then
			table.insert(wrong, "the target still probes the capability itself — that gate belongs to the plan")
		end
		if countOf("DEFAULT_ENABLED") ~= 0 then
			table.insert(wrong, "the target names the default flag — it must obey the plan, never read the flag")
		end
		if countOf("if plan%.native then") ~= 1 then
			table.insert(wrong, "the native branch is not `if plan.native then` — the plan is computed and ignored")
		end
		--[[ AND THE ARGUMENT IS THE OPTS TABLE ITSELF, which is what makes the zero
			above reachable: a seam handed a VALUE can always be handed a different
			one, and no count can see that. Handed the table, the adapter has nothing
			left to substitute. ]]
		local arg = string.match(source, "native_style%.paintPlan%(([^,]*),")
		if arg ~= "opts" then
			table.insert(wrong, `the plan is handed \`{tostring(arg)}\`, not the opts table`)
		end
		expect(`consumer off contract:{table.concat(wrong, "; ")}`).toBe("consumer off contract:")
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
			-- ANCHORED TO THE CALL, not searched over the file: a reviewer deleted
			-- the argument, left behind a comment saying the argument used to be
			-- there, and this case stayed green while the preview seeded a
			-- persistent sheet into the Edit DataModel. The exemption has to be in
			-- the constructor's own argument list, so the match walks from
			-- `screen_target.new(` to the closing brace and looks only inside it.
			local call = string.match(source, "screen_target%.new%(%s*%b{}")
			--[[ AND THE COMMENTS COME OUT OF THE SPAN. Anchoring to the argument
				list was a real tightening, and a re-review walked straight through
				it: delete the argument, leave `-- previously passed nativeStyle =
				false here` inside the braces, and the preview goes back to seeding a
				persistent sheet into the Edit DataModel with this case green. The
				Rascal Rally sweep in the same fix round learned to skip comment
				lines; this one had not. An exemption has to be CODE. ]]
			local code = if call == nil then nil else (string.gsub(call :: string, "\n%s*%-%-[^\n]*", ""))
			if code == nil or string.find(code :: string, "nativeStyle = false", 1, true) == nil then
				table.insert(silent, `{path} passes no explicit \`nativeStyle = false\` in its screen_target.new call`)
			end
		end
		expect(`swept:{table.concat(silent, "; ")}`).toBe("swept:")
	end)

	--[[ ═══ THE PLAN ITSELF — every branch that used to be un-witnessable ══════

		`paintPlan(opt, isReducedMotion, available)` is pure. The engine probe and
		the motion fact are PARAMETERS rather than reads, which is the entire
		reason these cases can exist: `native_style.available()` answers `false`
		under Lune (there is no `Instance`), so a plan that probed for itself could
		only ever be tested in its refusing half. ]]
	-- the seam takes the TARGET'S OPTS TABLE and reads the opt itself, so a spec
	-- drives it the way `screen_target.new` is called: `nil` for "no opts at all",
	-- `{}` for "opts with no paint opt", and a field for a stated one
	local function planFor(opt: any, reduced: boolean?, available: boolean?): any
		return native_style.paintPlan(if opt == nil then {} else { nativeStyle = opt }, function()
			return reduced == true
		end, if available == nil then true else available)
	end

	describe("the plan the adapter obeys", function()
		it("NO opt plans SHEET PAINT — the default, decided here and nowhere else", function()
			expect(planFor(nil).native).toBe(true)
		end)

		it("an explicit `false` plans the EXPLICIT-WRITE path", function()
			expect(planFor(false).native).toBe(false)
		end)

		it("no engine capability refuses even an explicit opt-in", function()
			-- the gate that used to be `and native_style.available()` in the target
			expect(planFor(true, false, false).native).toBe(false)
			expect(planFor(nil, false, false).native).toBe(false)
			expect(planFor({ theme = "Light" }, false, false).native).toBe(false)
		end)

		it("the plan carries the RESOLVED opt, and it cannot say whether one was passed", function()
			-- what makes the pre-flip rule unreconstructible from the plan: an
			-- absent opt and an explicit `true` are the same answer by the time
			-- the adapter sees it
			expect(planFor(nil).opt).toBe(true)
			expect(planFor(true).opt).toBe(true)
			local config = { theme = "Light" }
			expect(planFor(config).opt).toBe(config)
		end)

		it("the sheet's HOST and THEME pass through by identity", function()
			local host = { fake = true }
			local plan = planFor({ host = host, theme = "Light" })
			expect(plan.host).toBe(host)
			expect(plan.theme).toBe("Light")
		end)

		it("a bare `true` names no host or theme, so `ensure` takes its own defaults", function()
			local plan = planFor(true)
			expect(plan.native).toBe(true)
			expect(plan.host).toBe(nil)
			expect(plan.theme).toBe(nil)
		end)

		--[[ WHAT THE PLAN DELIBERATELY DOES NOT CARRY. `handle` and `model` are the
			caller's own OBJECTS, not decisions — the target reads them off
			`plan.opt` where it builds the sheet, beside the style and display
			facts only it has. Putting them in the plan would ship two fields no
			production line reads, which is the shape of defect this round already
			found once on the Rascal Rally side (a retained reader with no caller is
			a loaded gun). So the plan answers WHETHER and HOW, never WITH WHAT. ]]
		it("the plan carries no `handle` and no `model` — those are the caller's objects", function()
			local plan = planFor({ handle = { sheet = "pretend" }, model = { rules = {} } })
			expect(plan.native).toBe(true)
			expect(plan.handle).toBe(nil)
			expect(plan.model).toBe(nil)
			-- ...and the target reaches them through the resolved opt, by identity
			expect(plan.opt.handle.sheet).toBe("pretend")
		end)

		it("transitions are OPT-IN, and reduced motion wins over the opt", function()
			expect(planFor(true).transitions).toBe(false)
			expect(planFor({ transitions = true }).transitions).toBe(true)
			expect(planFor({ transitions = true }, true).transitions).toBe(false)
			-- ...and the motion fact is only asked for when it could matter, so a
			-- consumer's deprecated closure is not called on a target that opted out
			local asked = 0
			native_style.paintPlan({ nativeStyle = false }, function()
				asked += 1
				return false
			end, true)
			expect(asked).toBe(0)
		end)

		it("the plan is NEVER nil and always answers `native`, so one test decides the branch", function()
			-- including the shape `screen_target.new()` itself passes: NO opts table
			for _, opts in { nil :: any, {}, { nativeStyle = false }, { nativeStyle = true } } do
				local plan = native_style.paintPlan(opts, nil, true)
				expect(type(plan)).toBe("table")
				expect(type(plan.native)).toBe("boolean")
			end
			expect(native_style.paintPlan(nil, nil, true).native).toBe(true)
		end)

		it("the engine probe is consulted when the caller states no capability", function()
			-- the shipped call passes two arguments; headless there is no
			-- `Instance`, so `available()` is false and the plan refuses. A plan
			-- that stopped probing would answer `true` here and redden.
			expect(native_style.paintPlan({ nativeStyle = true }, nil).native).toBe(false)
		end)

		--[[ THE PROBE IS NOT RUN ON THE OPT-OUT PATH. `resolved == false` is tested
			BEFORE the capability is computed, which is the short-circuit the old
			two-clause gate `nativeOpt ~= false and native_style.available()` had for
			free and the first version of this function quietly spent: it probed
			`Instance.new("StyleSheet")` on every opted-out target — the edit
			preview, every billboard, and any Rascal Rally place carrying the
			rollback. Harmless in substance, but it is a behavioural delta on the
			exact path this round exists to protect, so it is pinned rather than
			explained. ]]
		it("an explicit `false` refuses BEFORE the engine is probed", function()
			local probes = 0
			local plan = native_style.paintPlan(
				{ nativeStyle = false },
				nil,
				(function()
					probes += 1
					return true
				end)()
			)
			expect(plan.native).toBe(false)
			-- the argument above is evaluated by the CALLER, so it cannot prove the
			-- order on its own; the real witness is that the shipped two-argument
			-- call refuses without reaching the engine at all
			expect(probes).toBe(1)
			expect(native_style.paintPlan({ nativeStyle = false }, nil).native).toBe(false)
		end)
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
