--!strict
--[[ THE STACK SEAM, MECHANISED — what keeps `layout/stack.luau` one-way.

	WHY A SPEC AND NOT A COMMENT. `tools/lune/verify/data/source-cap-ledger.md`
	records the rule every extraction in this repository is judged by: a block may
	leave a file only if it reads no mutable upvalue of its host, because otherwise
	the move creates a require BACK and the two files become one file with a slash
	in the middle. This is the FIFTH solver seam and the largest — 15,821 characters,
	the whole vstack/hstack arrange branch — and it is the block that row's trigger
	has named by name since the T4 split.

	  A CLOSED DEPS      READ == DECLARED == PASSED, as three SETS compared against
	                     each other. A sixth field reached for is a seam growing back
	  READ vs WRITE      the `ctx`/`node`/`child` fields it reads, as sets, and the
	                     ONE thing it writes (`ctx.diagnostics`, and only by insert)
	  TWO CALL ARGUMENTS `place` and `noteContainment`, passed rather than captured,
	                     for the reason `grid.luau` states about its own pair
	  ONE CONSUMER       `src/layout/solver.luau`, from the tail of `arrange`
	  ONE-WAY            it names no solver symbol and imports no solver type, and
	                     its three requires are leaves the solver also requires
	  NOTHING LEFT       the solver kept no copy of the branch
	  NO STATE           no module-level local is ever reassigned

	Each source rule is a pure function of a string, so each carries a NEGATIVE
	CONTROL that feeds it a broken input and proves it reports. A check that cannot
	fail is decoration. The BEHAVIOUR half of this seam is not here and does not need
	to be: `tests/stack_distribution.spec.luau`, `tests/layout.spec.luau` and very
	nearly every fixture in this repository drive a vstack or an hstack through the
	public surface, and they were green across the split. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local fs = require("@lune/fs")
local srcTree = require("./lib/src_tree")

local SOLVER_PATH = "src/layout/solver.luau"
local STACK_PATH = "src/layout/stack.luau"

--[[ COMMENTS ARE NOT CODE, and in this repository that is not a nicety: this
	module's own header names `arrange`, `measure` and `solver.Node` while explaining
	what it must never reach for, and a scan that counted them would report the exact
	dependency the header promises it does not have. ]]
local function stripComments(source: string): string
	local out = string.gsub("\n" .. source, "%-%-%[%[.-%]%]", " ")
	out = string.gsub(out, "\n[ \t]*%-%-[^\n]*", "\n")
	return out
end

local function sorted(set: { [string]: boolean }): { string }
	local out: { string } = {}
	for key in set do
		table.insert(out, key)
	end
	table.sort(out)
	return out
end

-- every `<name>.<field>` read of one receiver, comments stripped
local function fieldsRead(source: string, receiver: string): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for key in string.gmatch(stripComments(source), receiver .. "%.([%a_][%w_]*)") do
		out[key] = true
	end
	return out
end

describe("the stack seam: a CLOSED Deps record, read == declared == passed", function()
	local stackSrc = fs.readFile(STACK_PATH)
	local solverSrc = fs.readFile(SOLVER_PATH)

	it("the fields the body READS are exactly the fields the type DECLARES", function()
		--[[ THE ONE-WAY TEST ITSELF, as a set comparison rather than a promise. A
			`Deps` record is a statement about what a module reads from its host
			(`solver.luau`'s own note beside `COMPOSITION_DEPS`: "a spare field in it is
			a false statement"), so the two directions are both defects — a field read
			and not declared would not typecheck, and a field declared and not read is
			the host handing over something this module has stopped needing. ]]
		local declared: { [string]: boolean } = {}
		local block = string.match(stripComments(stackSrc), "export type Deps = {(.-)\n}")
		assert(block ~= nil, "the Deps type block was not found")
		for name in string.gmatch(block :: string, "\n\t([%a_][%w_]*):") do
			declared[name] = true
		end
		expect(sorted(declared)).toEqual({ "baseline", "dim", "mainDimOf", "measure", "shrink", "sides" })
		expect(sorted(fieldsRead(stackSrc, "deps"))).toEqual(sorted(declared))
	end)

	it("...and exactly the fields the solver PASSES, in the one record it builds", function()
		local literal = string.match(stripComments(solverSrc), "local STACK_DEPS: stackLib%.Deps = {(.-)\n}")
		assert(literal ~= nil, "the solver's STACK_DEPS literal was not found")
		local passed: { [string]: boolean } = {}
		for name in string.gmatch(literal :: string, "\n\t([%a_][%w_]*) =") do
			passed[name] = true
		end
		expect(sorted(passed)).toEqual({ "baseline", "dim", "mainDimOf", "measure", "shrink", "sides" })
		--[[ AND `measure` IS BORROWED, NOT REBUILT. `GRID_DEPS.measure` is the
			forwarder that reads the forward local at call time; building a second one
			here is how the two records end up reading a different `measure` after an
			edit, which is the failure `FLOW_DEPS = GRID_DEPS` was written to prevent
			one record up. ]]
		expect(string.find(literal :: string, "measure = GRID_DEPS.measure", 1, true) ~= nil).toBe(true)
		-- ...and the shrink record TRAVELS rather than being rebuilt in the module,
		-- for the same reason
		expect(string.find(literal :: string, "shrink = SHRINK_DEPS", 1, true) ~= nil).toBe(true)
		expect(string.find(stripComments(stackSrc), "textTypography", 1, true)).toBe(nil)
	end)

	it("`place` and `noteContainment` are CALL-SITE arguments, not Deps fields", function()
		--[[ THE DISTINCTION THAT IS NOT COSMETIC, and `grid.luau`'s header already
			carries the reason: both are declared BELOW the line `STACK_DEPS` is built
			on, so a by-value record there would capture the nil global and die inside a
			protected solve boundary — and forward-declaring them to avoid that would add
			a mutable module local, which is the opposite of what a split is for. ]]
		local declaredDeps = string.match(stripComments(stackSrc), "export type Deps = {(.-)\n}") :: string
		expect(string.find(declaredDeps, "place", 1, true)).toBe(nil)
		expect(string.find(declaredDeps, "noteContainment", 1, true)).toBe(nil)
		expect(string.find(stripComments(stackSrc), "place: Place,", 1, true) ~= nil).toBe(true)
		expect(string.find(stripComments(stackSrc), "noteContainment: NoteContainment,", 1, true) ~= nil).toBe(true)
		-- and the solver really does hand both over on the one call
		expect(
			string.find(
				solverSrc,
				"stackLib.arrange(STACK_DEPS, ctx, node, innerX, innerY, innerW, innerH, gap, arrange, noteContainment, out)",
				1,
				true
			) ~= nil
		).toBe(true)
	end)

	it("NEGATIVE CONTROL: the Deps and literal scans both report a changed set", function()
		local fakeType = "export type Deps = {\n\tmeasure: (any) -> (),\n\tghost: (any) -> (),\n}\n"
		local declared: { [string]: boolean } = {}
		local block = string.match(stripComments(fakeType), "export type Deps = {(.-)\n}") :: string
		for name in string.gmatch(block, "\n\t([%a_][%w_]*):") do
			declared[name] = true
		end
		expect(sorted(declared)).toEqual({ "ghost", "measure" })
		local fakeLiteral = "local STACK_DEPS: stackLib.Deps = {\n\tmeasure = m,\n\tghost = g,\n}\n"
		local passed: { [string]: boolean } = {}
		local literal =
			string.match(stripComments(fakeLiteral), "local STACK_DEPS: stackLib%.Deps = {(.-)\n}") :: string
		for name in string.gmatch(literal, "\n\t([%a_][%w_]*) =") do
			passed[name] = true
		end
		expect(sorted(passed)).toEqual({ "ghost", "measure" })
		expect(sorted(fieldsRead("local x = deps.ghost\n", "deps"))).toEqual({ "ghost" })
	end)
end)

describe("the stack seam: what it READS of the solve, and the one thing it WRITES", function()
	local stackSrc = fs.readFile(STACK_PATH)

	--[[ THE SCHEMA IT DEPENDS ON, AS THREE SETS rather than as a promise. Every
		parameter is typed `any` precisely so the module cannot import the solver's own
		types back, which means nothing but this check reports a further field being
		reached for. A field appearing here that is not on this list is a stack branch
		that has started to depend on the SOLVE rather than on the node and the box it
		was handed — which is sometimes exactly the right change, and is never one a
		green run should be able to make quietly.

		SO THE LISTS CARRY THEIR REASONS (Plan C, T14 step 0, ruling T7-3). `stack_measure`'s
		own seam went from ONE `ctx` field to TEN when T13's container memo landed, and
		that widening was worth a sentence per field rather than a diff on a literal.
		The stack ARRANGE branch is about to make the same move for the same reason —
		the replay that re-places only the children that moved has to ask the SOLVE what
		it is allowed to trust — so the three sets become named tables with a line each,
		and the widening lands as a set of new lines rather than as an edited literal.

		WHAT T14 WILL ADD, NAMED HERE BEFORE IT LANDS, so the commit that adds them is a
		commit about the mechanism and not about this pin:
		  `ctx.reuse`         the previous solve's map and dirty closure — the replay is
		                      structurally unreachable without it
		  `ctx.noSkipDepth`   the suspension a coordinate-space host raises; the arm must
		                      refuse under it exactly as `arrangeBody`'s own skip does
		  `ctx.measureQuiet`  the anchor arm's fourth gate and T13's: a measure-time
		                      finding is filed about a node in the subtree the arm does
		                      not re-measure, and no rect can carry it back
		  `ctx.measureStamp`  and `ctx.scopeKey` — the solve-wide inputs no per-child
		  `ctx.scopeKey`      fact can see (the viewport, the theme, the text scales,
		                      the text-metrics CALIBRATION generation)
		  `ctx.replayAudit`   the forced-on oracle's switch (ruling A-12)
		  `node.cmemo`        the container memo T13 created (ruling A-8), which is where
		                      the replay's own payload lives
		  `child.id`          the identity the payload's per-index arrays are keyed by —
		                      the `ForEach` splice moves indices under an unchanged mount
		                      children table
		  `child.layoutPriority`  the shrink pass's order, one of the two inputs that
		                      move a rect with no measurement change (ruling A-15)
		It does NOT add `node.gap`: `gap` is a PARAMETER of `stack.arrange`, and the
		replay compares the parameter it was handed. ]]
	local CTX_FIELDS = {
		-- the list its caller owns, appended to by the two diagnostics below
		"diagnostics",
		--[[ (Plan D, D3b) the widest lower bound on `reuse.dirtyContains`' SIZE this
			solve has established. It is the ONE field here that is written and read back
			in the same solve, and that is deliberate rather than an exception smuggled
			in: the set is a single fixed table per solve, so one container's bounded walk
			answers the size question for every container after it, and the alternative is
			a walk per container over a set that has nothing to do with that container's
			children. It decides only WHICH ENUMERATION runs, never what either produces —
			both arms place the same children at the same rects, which is what the oracle
			at the bottom of `tests/stack_replay_candidates.spec.luau` compares. ]]
		"dirtySeen",
		-- Plan E republishes the cut verdict and measurement offer of a served row.
		"fitCuts",
		-- ...and the gate those two share, which is also a replay gate term: the
		-- decision to file cannot have flipped under a re-filed finding
		"hiddenDepth",
		-- the anchor arm's fourth gate and T13's. A measure-time finding is filed about
		-- a node in the subtree the replay does not re-measure, and no rect carries it
		-- back, so the arm refuses on a solve whose predecessor filed one
		"measureQuiet",
		-- the solve-wide inputs no per-child fact can see: the viewport, the safe
		-- insets, the theme snapshot, the two text scales and the text-metrics
		-- CALIBRATION generation (the per-WORD half left this stamp in T18-A and
		-- arrives as dirt on the label, which the replay re-measures like any dirt)
		"measureStamp",
		-- the suspension a coordinate-space host holding a composition raises. The
		-- replay refuses under it for the reason `arrangeBody`'s own skip does
		"noSkipDepth",
		"offers",
		-- ...and the two censuses the arm owes: how many per-child placements it did NOT
		-- spend, and (Plan D, D2c) how many per-child ITERATIONS it DID. They are
		-- independent — the replay used to walk every sibling twice to serve a one-child
		-- payload — and both are WRITE-ONLY, never read back here (see the write half
		-- below)
		"placeScanned",
		"placeSkipped",
		-- the forced-on oracle's switch (ruling A-12) and its comparison count, the
		-- second of the two write-only counters
		"replayAudit",
		"replayChecks",
		-- ...and (Plan D, D3b) the third census: the DIRTY IDS the indexed arm
		-- enumerated to build its short list, which `placeScanned` cannot see because it
		-- prices the list and not the walk that produced it. Write-only like the others
		"replayProbes",
		-- the previous solve's rect map and dirty closure. The replay is structurally
		-- unreachable without it, which is what makes a full solve the pre-T14 branch
		"reuse",
		-- the container/hidden scope the measurements were taken under, beside the
		-- stamp for the same reason
		"scopeKey",
	}
	local NODE_FIELDS = {
		"align",
		"children",
		-- the container memo T13 created (ruling A-8), whose home is the mount-keyed
		-- node store — which is why it survives the rebuild a container with one dirty
		-- child gets. T14's payload lives beside T13's on it, under the same carrier
		-- gate and with its own per-index id key
		"cmemo",
		"distribute",
		"id",
		--[[ (Plan D, D2c) the TABLE IDENTITY `render/layout_node` stamps where the
			children array is built: the same table on every build that kept or patched
			it, a fresh one on every build that rebuilt it. Read only to compare against
			the token the recording pass wrote, which is what licenses this branch to
			trust `pIds`' indices instead of re-reading every sibling's id. It is not a
			layout input and no rect is a function of it. ]]
		"kidToken",
		"kind",
	}
	local CHILD_FIELDS = {
		"align",
		-- Plan E refuses kinds with measurement side channels or relative sizing.
		"containerRelativeInside",
		"hKey",
		-- the identity the payload's per-index arrays are keyed by. A `ForEach` splice
		-- moves every later index while the mount children table the carrier compares
		-- is untouched, so an index alone is not a binding
		"id",
		-- the shrink pass's order, one of the two inputs that move a rect with NO
		-- measurement change (ruling A-15); the other is `shrinkWeight` below
		"kind",
		"layoutPriority",
		"lineAlign",
		"margin",
		"shrinkWeight",
		"subtreeHasComposition",
		"subtreeHasScroll",
		"wKey",
	}

	it("it reads a CLOSED set of ctx, node and child fields", function()
		expect(sorted(fieldsRead(stackSrc, "ctx"))).toEqual(CTX_FIELDS)
		expect(sorted(fieldsRead(stackSrc, "node"))).toEqual(NODE_FIELDS)
		expect(sorted(fieldsRead(stackSrc, "child"))).toEqual(CHILD_FIELDS)
	end)

	--[[ THE READ-vs-WRITE HALF OF THE ONE-WAY TEST, and the half a field-read scan
		cannot see. A block that only reads its host's state can be moved; a block that
		WRITES it has to be trusted to write the same thing at the same moment, which is
		a different and much weaker claim. This branch assigns no field of `ctx`,
		`node`, `child` or `deps` at all — its two diagnostics append to the list its
		caller owns, and every rect it produces reaches `out` through `place`, which is
		the solver's own `arrange`.

		A COUNTER IS THE ONE ASSIGNMENT THIS SET WILL EVER ACCEPT (T14 step 0). It is
		WRITE-ONLY — the module never reads the field back, so no behaviour of this
		branch is a function of it and the "same thing at the same moment" objection
		does not arise. `stack_measure.luau`'s own seam went from an EMPTY write set to
		three on exactly that argument when T13/T13b's counters landed. Anything that is
		not a counter belongs in the empty list below, and a counter that is ever READ
		here stops being one. ]]
	--[[ ...AS A SET, NOT AS A TRANSCRIPT (Plan D, D2c). The scan used to compare the
		assignments in source order, which happened to work while each counter had one
		write site; the indexed arm gives `placeScanned` and `placeSkipped` one site per
		exit, and a list that pins HOW MANY TIMES a counter is incremented is pinning the
		branch's shape rather than its write SET — which is the claim this case makes.
		Deduped and sorted; the negative control below still reports the field it sees. ]]
	local WRITES: { string } = {
		--[[ ...AND THE ONE ENTRY THAT IS NOT A COUNTER (Plan D, D3b). `ctx.dirtySeen` is
			written here AND read back here, so the paragraph above does not cover it and
			saying "counter" of it would be false. It is per-solve SCRATCH: a lower bound
			on the dirty set's size, established by whichever container walked it first
			and spent by every container after. What it selects is the ENUMERATION — the
			short list or the sibling scan — and both enumerations place the same children
			at the same rects, so the "same thing at the same moment" objection is answered
			by the differential oracle rather than by write-only-ness. It is listed first
			so a second read-back field cannot arrive under this comment unremarked. ]]
		"ctx.dirtySeen",
		-- Cut verdict replay is semantic state, not a work counter.
		"ctx.fitCuts",
		-- the per-child placements the replay did not spend, the per-child ITERATIONS it
		-- did (D2c), the dirty IDS it read to decide (D3b), and the rects its forced-on
		-- oracle compared. All four are pure counters: this module never reads any of
		-- them back, so no behaviour of this branch is a function of them
		"ctx.placeScanned",
		"ctx.placeSkipped",
		"ctx.replayChecks",
		"ctx.replayProbes",
	}

	it("it WRITES nothing of the solver's but `ctx.diagnostics`, and only by insert", function()
		local body = stripComments(stackSrc)
		local assigned: { [string]: boolean } = {}
		for recv, field in string.gmatch(body, "([%a_][%w_]*)%.([%a_][%w_]*)%s*[%+%-]?=[^=]") do
			if recv == "ctx" or recv == "node" or recv == "child" or recv == "deps" then
				assigned[`{recv}.{field}`] = true
			end
		end
		expect(sorted(assigned)).toEqual(WRITES)
		local inserts: { [string]: boolean } = {}
		for target in string.gmatch(body, "table%.insert%(%s*([%a_][%w_%.]*)") do
			if string.find(target, ".", 1, true) ~= nil then
				inserts[target] = true
			end
		end
		expect(sorted(inserts)).toEqual({ "ctx.diagnostics" })
	end)

	it("NEGATIVE CONTROL: the write scans report an assignment and a second insert target", function()
		local fake = "\nctx.measured += 1\nlocal x = ctx.diagnostics\n"
		local assigned: { string } = {}
		for recv, field in string.gmatch(stripComments(fake), "([%a_][%w_]*)%.([%a_][%w_]*)%s*[%+%-]?=[^=]") do
			if recv == "ctx" then
				table.insert(assigned, `{recv}.{field}`)
			end
		end
		expect(assigned).toEqual({ "ctx.measured" })
		local inserts: { [string]: boolean } = {}
		for target in
			string.gmatch(
				stripComments("table.insert(ctx.walked, 1)\ntable.insert(ctx.diagnostics, d)\n"),
				"table%.insert%(%s*([%a_][%w_%.]*)"
			)
		do
			if string.find(target, ".", 1, true) ~= nil then
				inserts[target] = true
			end
		end
		expect(sorted(inserts)).toEqual({ "ctx.diagnostics", "ctx.walked" })
		-- ...and a `==` comparison is not an assignment, which is the one way this
		-- scan could have been silently vacuous
		local none: { string } = {}
		for recv, field in
			string.gmatch(
				stripComments("\nif ctx.hiddenDepth == 0 then\n"),
				"([%a_][%w_]*)%.([%a_][%w_]*)%s*[%+%-]?=[^=]"
			)
		do
			table.insert(none, `{recv}.{field}`)
		end
		expect(none).toEqual({})
	end)
end)

describe("the stack seam: one-way, one consumer, and nothing stayed behind", function()
	local stackSrc = fs.readFile(STACK_PATH)
	local solverSrc = fs.readFile(SOLVER_PATH)

	it("it requires only leaves, and never the solver", function()
		--[[ THE THREE ARE LEAVES THE SOLVER ALSO REQUIRES, so the graph stays acyclic:
			`../num` is arithmetic, `./placement` is five functions on numbers, and
			`./shrink` takes the record this module is handed rather than reaching back
			for one. The `shrink` DEPS itself is NOT rebuilt here — see the Deps case. ]]
		local requires: { string } = {}
		for path in string.gmatch(stripComments(stackSrc), 'require%("([^"]+)"%)') do
			table.insert(requires, path)
		end
		table.sort(requires)
		expect(requires).toEqual({
			"../num",
			"./baseline",
			"./measure_facts",
			"./placement",
			"./row_permutation",
			"./shrink",
		})
	end)

	it("it names no solver symbol and imports no solver type", function()
		-- a type import is a require by another name in Luau (`require` first, then
		-- `Module.Type`), so the structural `any` on every parameter is what keeps the
		-- graph acyclic
		local body = stripComments(stackSrc)
		expect(string.find(body, ": Node")).toBe(nil)
		expect(string.find(body, ": Ctx")).toBe(nil)
		expect(string.find(body, "solver%.")).toBe(nil)
		-- ...and the direction that IS allowed is present, so this cannot pass by the
		-- solver having quietly dropped the require
		expect(string.find(solverSrc, 'require("./stack")', 1, true) ~= nil).toBe(true)
	end)

	it("there is exactly ONE consumer of the module in src/", function()
		expect(srcTree.pathsMatching('require%("[^"]*/stack"%)')).toEqual({ SOLVER_PATH })
	end)

	it("the module exports exactly `arrange`, and the solver calls that one function", function()
		local exported: { [string]: boolean } = {}
		for name in string.gmatch(stripComments(stackSrc), "function stack%.([%a_][%w_]*)") do
			exported[name] = true
		end
		expect(sorted(exported)).toEqual({ "arrange" })
		local calls = 0
		for _ in string.gmatch(stripComments(solverSrc), "stackLib%.arrange%(") do
			calls += 1
		end
		expect(calls).toBe(1)
	end)

	it("the solver kept no copy of the branch", function()
		--[[ THE FAILURE THIS REPOSITORY HAS ALREADY PAID FOR ONCE: a block "moved" by
			copying, leaving the host's version live and the two drifting. Each string
			below is a distinctive line of the branch that left, and none of them may
			appear in the solver any more.

			▲ AMENDED 2026-09-05, and the amendment is the point of writing near-misses
			down. This case used to pin `local isH = node.kind == "hstack"` as PRESENT,
			on the grounds that the MEASURE-side stack pass still used that exact line —
			true when it was written, and false the moment that pass ALSO left, for
			`src/layout/stack_measure.luau` (Plan C, T13's seam). The three strings that
			moved with it (`local isH = node.kind == "hstack"`, `fillWeightSum`,
			`local shrunk`) are now pinned by `tests/stack_measure_seam.spec.luau`'s own
			"nothing stayed behind" case instead of here. A near-miss list is a statement
			about what ELSE lives in the host, so it goes stale when the host changes —
			and this spec noticing that is the mechanism working. ]]
		local body = stripComments(solverSrc)
		expect(string.find(body, "local hugLater", 1, true)).toBe(nil)
		expect(string.find(body, "hasShrink", 1, true)).toBe(nil)
		expect(string.find(body, "local clipMain", 1, true)).toBe(nil)
		-- The wrap branch now shares the baseline-aware inheritance expression.
		expect(string.find(body, "child.lineAlign or child.align or node.align", 1, true) ~= nil).toBe(true)
		--[[ TWO NEAR-MISSES ARE DELIBERATELY *NOT* ON THAT LIST: `gapExtraApplied` and
			`distributionOf(` are the WRAP arrange branch, which stayed behind and is one
			`Enum`-name apart from the branch that left. The positives below prove the
			file was not simply emptied. ]]
		expect(string.find(body, "gapExtraApplied", 1, true) ~= nil).toBe(true)
		expect(string.find(body, "distributionOf(", 1, true) ~= nil).toBe(true)
	end)

	it("NEGATIVE CONTROL: the require, export and leftover scans all report", function()
		local fakeRequires: { string } = {}
		for path in string.gmatch(stripComments('local s = require("./solver")\n'), 'require%("([^"]+)"%)') do
			table.insert(fakeRequires, path)
		end
		expect(fakeRequires).toEqual({ "./solver" })
		local fake = "function stack.arrange(a)\nend\nfunction stack.extra()\nend\n"
		local exported: { [string]: boolean } = {}
		for name in string.gmatch(stripComments(fake), "function stack%.([%a_][%w_]*)") do
			exported[name] = true
		end
		expect(sorted(exported)).toEqual({ "arrange", "extra" })
		expect(string.find(stripComments("\tlocal hugLater = {}\n"), "local hugLater", 1, true) ~= nil).toBe(true)
		expect(string.find(stripComments("local x: Node = node\n"), ": Node") ~= nil).toBe(true)
	end)
end)

describe("the stack seam: no module-level mutable state", function()
	it("nothing declared at module level is ever reassigned", function()
		--[[ A MODULE-LEVEL MUTABLE IS A SECOND SOLVE'S STATE LEAKING INTO THE FIRST,
			and it is the one way a pure-looking arrange branch stops being pure. The
			scan is deliberately crude — every `local <name>` at column zero, then every
			bare `<name> =` at column zero — because a `local` that is never written is
			a constant and a `local` that is written is the thing this forbids. ]]
		local body = stripComments(fs.readFile(STACK_PATH))
		local declared: { [string]: boolean } = {}
		for name in string.gmatch(body, "\nlocal ([%a_][%w_]*)") do
			declared[name] = true
		end
		expect(sorted(declared)).toEqual({
			--[[ (Plan D, D3b) the floor under the probe budget — a CONSTANT, which is
				exactly what this scan permits: declared once, never written. ]]
			"DIRT_PROBE_FLOOR",
			"alignOffset",
			"baseline",
			"distributionOf",
			--[[ (Plan D, D2c) `local function candidateIndices` — the crude scan reads the
				keyword, not the name, and that is the honest report: what it forbids is a
				module-level `local` that is later WRITTEN, and a `local function` is a
				constant binding. It is listed so a second one does not arrive unremarked. ]]
			"function",
			"num",
			"permutation",
			"placementLib",
			"roundPx",
			"shrinkLib",
			"spacerMinimum",
			"stack",
		})
		local reassigned: { string } = {}
		for name in string.gmatch(body, "\n([%a_][%w_]*) =") do
			if declared[name] then
				table.insert(reassigned, name)
			end
		end
		expect(reassigned).toEqual({})
	end)

	it("NEGATIVE CONTROL: the reassignment scan reports one", function()
		local fake = "\nlocal cache = nil\nlocal m = {}\ncache = 1\n"
		local declared: { [string]: boolean } = {}
		for name in string.gmatch(fake, "\nlocal ([%a_][%w_]*)") do
			declared[name] = true
		end
		local reassigned: { string } = {}
		for name in string.gmatch(fake, "\n([%a_][%w_]*) =") do
			if declared[name] then
				table.insert(reassigned, name)
			end
		end
		expect(reassigned).toEqual({ "cache" })
	end)
end)
