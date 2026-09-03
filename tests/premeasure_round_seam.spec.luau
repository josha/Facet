--!strict
--[[ THE TEXT-PREMEASUREMENT SEAM, MECHANISED — what keeps `render/premeasure_round`
	one-way.

	`tools/lune/verify/data/source-cap-ledger.md` has named this block as
	`renderer.luau`'s next seam since the geometry-facts split, together with the
	price it predicted: *it reads `adapter`, `env` and `stats`, so it costs a record
	the way `table.luau`'s `rowGesture` did, and is worth taking only by a round that
	needs the room.* Wicked-fast T7 adds 2,500-4,000 characters to a file that had
	1,480 of headroom, so the split came FIRST and on its own — which is what that
	document's wording has demanded of every extraction this file has taken.

	  READ      every `deps.<field>` the module reads, comments stripped
	  DECLARED  every field its own `Deps` type names
	  PASSED    every key the renderer's `premeasure_round.new({ … })` call hands over

	all three equal in both directions, plus the mutable-upvalue test over the three
	names, the no-rebind test from the module's side, no module-level mutable state,
	EXPORTED == USED, one consumer walked over the whole `src/` tree, ONE leaf require
	that the renderer also requires, and the two rules this seam needs for itself:

	  * THE RENDERER HOLDS NO COPY OF THE THREE RECORDS. `textInFlight`,
	    `textMeasureCancels` and the reassigned scalar `disposed` are what the block
	    owned, and all three were read nowhere else in that file — so THE STATE LEFT
	    WITH THE CODE, and the scalar takes the accessor move `tap_arm.luau` proved.
	  * `disposed` IS WRITTEN ONLY HERE, on exactly one line, inside `dispose()`.
	    `controller.dispose` — which used to assign it directly — now calls that
	    accessor, and the name appears nowhere else in `src/`.

	THE CALL ARGUMENT IS THE OTHER HALF OF THE PRICE. `solveAndApply` is NOT a `Deps`
	field and must not become one: the round RE-ENTERS the renderer's solve, and that
	function is declared roughly a thousand lines below the line this record is built
	on. `layout/stack.luau` takes `place` the same way and for the same reason.

	AND THE BEHAVIOUR, WHICH THE SUITE ALREADY DROVE, so the honest claim is narrow:
	`tests/text_premeasure.spec.luau` drives the whole round through `renderer.attach`
	and the fake target — the batch, the in-flight guard, the non-final answer, the
	corrected width, the one-solve-per-learned-round counter, the after-dispose
	delivery and the `revealWhenTextExact` settle that rides on top of it — and it was
	green across the split, 32 passed either side. What it does not asssert is the
	SEAM's own contract, which is what the cases below are.

	Each source rule is a pure function of a string, so each carries a NEGATIVE
	CONTROL that feeds it a broken input and proves it reports. A check that cannot
	fail is decoration.

	MUTATIONS RUN, 2026-09-03: eight, and all eight bite —

	  | mutation                                          | result |
	  | a `Deps` field is not passed at construction      | 2 red  |
	  | the renderer keeps its own `textInFlight`         | 1 red  |
	  | a second writer of `disposed`, outside `dispose`  | 1 red  |
	  | `dispose` is a no-op                              | 1 red  |
	  | a module-level mutable table                      | 1 red  |
	  | `solveAndApply` becomes a `Deps` field            | 2 red  |
	  | an accessor nobody calls (a fourth export)        | 1 red  |
	  | the module requires the renderer back             | 1 red  |

	AND TWO INSTRUMENTS WERE CORRECTED BEFORE THEY MEANT ANYTHING, both because
	`disposed` and `measureTextWidths` are ORDINARY names where `tap_arm`'s
	`armedHere` was a coined one. The single-writer sweep first ran repo-wide and
	reported five unrelated teardown latches; scoping it by DIRECTORY does not fix
	that either, because `render/transitions.luau` owns one and is not part of the
	renderer. And "nothing stayed behind" first looked for `adapter.measureTextWidths`
	and matched the Roblox target's own DEFINITION of it. Both now say what they mean.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local fs = require("@lune/fs")
local src_tree = require("./lib/src_tree")
local renderer_source = require("./lib/renderer_source")

local customFactory = require("../src/core/custom")
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local text_metrics = require("../src/layout/text_metrics")
local fake_target = require("./lib/fake_target")

local RENDERER_PATH = "src/render/renderer.luau"
local ROUND_PATH = "src/render/premeasure_round.luau"

--[[ COMMENTS ARE NOT CODE, and in this repository that is not a nicety: the block
	travelled with its own reasoning, and that reasoning names `textInFlight`,
	`textMeasureCancels` and `disposed` in the renderer's pointer comment — a scan
	that counted them would report the exact copies the split removed. ]]
local function stripComments(source: string): string
	local out = string.gsub("\n" .. source, "%-%-%[%[.-%]%]", " ")
	out = string.gsub(out, "\n[ \t]*%-%-[^\n]*", "\n")
	return out
end

local function depsFieldsRead(source: string): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for key in string.gmatch(stripComments(source), "deps%.([%a_][%w_]*)") do
		out[key] = true
	end
	return out
end

local function typeFields(source: string, typeName: string): { [string]: boolean }
	local block = string.match(stripComments(source), "type " .. typeName .. " = {\n(.-)\n}")
	assert(block ~= nil, `no 'type {typeName}' block to read`)
	local out: { [string]: boolean } = {}
	for key in string.gmatch("\n" .. (block :: string), "\n\t([%a_][%w_]*):") do
		out[key] = true
	end
	return out
end

local function passedFields(rendererSource: string): { [string]: boolean }
	local call =
		string.match(stripComments(rendererSource), "local premeasureRound = premeasure_round%.new%({\n(.-)\n\t}%)")
	assert(call ~= nil, "no `premeasure_round.new({ … })` call to read")
	local out: { [string]: boolean } = {}
	for key in string.gmatch("\n" .. (call :: string), "\n\t\t([%a_][%w_]*) =") do
		out[key] = true
	end
	return out
end

local function bindings(source: string): { [string]: string }
	local out: { [string]: string } = {}
	for name, field in string.gmatch(stripComments(source), "\n\tlocal ([%a_][%w_]*) = deps%.([%a_][%w_]*)") do
		out[field] = name
	end
	return out
end

--[[ IS THIS NAME DECLARED ONCE AND NEVER REASSIGNED? A table-constructor entry
	(`adapter = adapter,`) reads exactly like an assignment, so a scan that did not
	exclude a trailing comma would report every shared record as mutable. ]]
local function assignmentsOutsideDeclaration(source: string, name: string): { string }
	local out: { string } = {}
	for line in string.gmatch(stripComments(source), "\n([^\n]*)") do
		local trimmed = string.match(line, "^%s*(.-)%s*$") :: string
		if string.sub(trimmed, 1, 6) == "local " or string.sub(trimmed, -1) == "," then
			continue
		end
		if
			string.match(trimmed, "^" .. name .. "%s*=[^=]") ~= nil
			or string.match(trimmed, "^" .. name .. "%s*%+=") ~= nil
		then
			table.insert(out, trimmed)
		end
	end
	return out
end

local function declarationsOf(source: string, name: string): number
	local n = 0
	for line in string.gmatch(stripComments(source), "\n([^\n]*)") do
		local trimmed = string.match(line, "^%s*(.-)%s*$") :: string
		if
			string.match(trimmed, "^local " .. name .. "[%s:=]") ~= nil
			or string.match(trimmed, "^local function " .. name .. "%(") ~= nil
		then
			n += 1
		end
	end
	return n
end

local function exportsOf(source: string): { [string]: boolean }
	local block = string.match(source, "\n\treturn {\n(.-)\n\t}\nend")
	assert(block ~= nil, "no exported table to read")
	local out: { [string]: boolean } = {}
	for key in string.gmatch("\n" .. (block :: string), "\n\t\t([%a_][%w_]*) =") do
		out[key] = true
	end
	return out
end

local function usedOf(rendererSource: string): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for key in string.gmatch(stripComments(rendererSource), "premeasureRound%.([%a_][%w_]*)") do
		out[key] = true
	end
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

local function missingFrom(a: { [string]: boolean }, b: { [string]: boolean }): { string }
	local out: { string } = {}
	for key in a do
		if not b[key] then
			table.insert(out, key)
		end
	end
	table.sort(out)
	return out
end

describe("the premeasure-round seam: READ == DECLARED == PASSED", function()
	local rendererSource = fs.readFile(RENDERER_PATH)
	local roundSource = fs.readFile(ROUND_PATH)

	it("every `deps` field the module reads is declared in its own `Deps`", function()
		local reads = depsFieldsRead(roundSource)
		expect(#missingFrom(reads, typeFields(roundSource, "Deps"))).toBe(0)
		-- ...and the set is not empty, which is the trap a set comparison invites:
		-- two empty sets are equal. THREE, exactly as the ledger row predicted.
		expect(sorted(reads)).toEqual({ "adapter", "env", "stats" })
	end)

	it("every field `Deps` declares is one the module reads AND one the renderer passes", function()
		expect(#missingFrom(typeFields(roundSource, "Deps"), depsFieldsRead(roundSource))).toBe(0)
		--[[ The call is a table CONSTRUCTOR, so a field the module declares and the
			renderer forgot arrives as `nil` rather than as a missing argument — and a nil
			`adapter` here is a round that never asks the engine for anything, silently. ]]
		expect(#missingFrom(typeFields(roundSource, "Deps"), passedFields(rendererSource))).toBe(0)
		expect(#missingFrom(passedFields(rendererSource), typeFields(roundSource, "Deps"))).toBe(0)
	end)

	it("`solveAndApply` crosses AT THE CALL and is not a Deps field", function()
		--[[ THE OTHER HALF OF THE PRICE, and the rule that makes this seam possible at
			all: the round RE-ENTERS the renderer's solve, and `solveAndApply` is declared
			about a thousand lines below the line the record is built on, so it cannot be
			captured there. `layout/stack.luau` passes `place` the same way. ]]
		expect(typeFields(roundSource, "Deps").solveAndApply).toBe(nil)
		expect(
			string.find(stripComments(rendererSource), "premeasureRound.request(textRequests, solveAndApply)", 1, true)
				~= nil
		).toBe(true)
		-- ...and the module takes it as a PARAMETER rather than reaching for a name
		expect(
			string.find(
				stripComments(roundSource),
				"local function request(textRequests: { any }, solveAndApply: () -> ())",
				1,
				true
			) ~= nil
		).toBe(true)
	end)

	it("NEGATIVE CONTROL: each of the three scans reports a broken input", function()
		expect(depsFieldsRead("local x = deps.invented\n").invented).toBe(true)
		local brokenType = "export type Deps = {\n\tonly: any,\n}\n"
		expect(sorted(typeFields(brokenType, "Deps"))).toEqual({ "only" })
		local brokenCall = "\tlocal premeasureRound = premeasure_round.new({\n\t\tstray = stray,\n\t})\n"
		expect(sorted(passedFields(brokenCall))).toEqual({ "stray" })
	end)
end)

describe("the premeasure-round seam: the mutable-upvalue test, and the scalar the ledger named", function()
	local rendererSource = fs.readFile(RENDERER_PATH)
	local roundSource = fs.readFile(ROUND_PATH)

	it("every name that crosses is declared ONCE by the renderer and never reassigned", function()
		--[[ `adapter` and `env` are `attach` PARAMETERS, so `declarationsOf` — which
			reads `local` lines — sees zero of them and one of `stats`; what the rule is
			actually about is the reassignment half, and a parameter that is never
			assigned is exactly as safe to share by reference as a `local` that is not. ]]
		local offenders: { string } = {}
		for _, field in sorted(typeFields(roundSource, "Deps")) do
			local assigns = assignmentsOutsideDeclaration(rendererSource, field)
			if #assigns > 0 then
				table.insert(offenders, `{field}(assigns={#assigns})`)
			end
		end
		expect(table.concat(offenders, " ")).toBe("")
		expect(declarationsOf(rendererSource, "stats")).toBe(1)
	end)

	it("...and the module never REBINDS one either — the same test from the other side", function()
		local offenders: { string } = {}
		for field, name in bindings(roundSource) do
			if #assignmentsOutsideDeclaration(roundSource, name) > 0 then
				table.insert(offenders, `{field}->{name}`)
			end
		end
		expect(table.concat(offenders, " ")).toBe("")
		-- the bindings exist at all, so an empty offender list means something
		expect(sorted(bindings(roundSource) :: any)).toEqual({ "adapter", "env", "stats" })
	end)

	it("THE RENDERER HOLDS NO COPY of the three records this block owned", function()
		--[[ THE STATE LEFT WITH THE CODE, mechanised. Two of the three were tables the
			renderer never read outside the block — they are gone from it entirely — and
			the third is the reassigned scalar. A split that left any of these names behind
			would have made the two files one file with a slash in the middle. ]]
		local body = stripComments(rendererSource)
		for _, name in { "textInFlight", "textMeasureCancels", "disposed" } do
			expect(`{name} absent: {tostring(string.find(body, name, 1, true) == nil)}`).toBe(`{name} absent: true`)
		end
	end)

	it("`disposed` is assigned on exactly one line, and it is inside this module", function()
		--[[ THE SINGLE-WRITER RULE, third seam to need it (the drag bridge's `instance`
			was the first, `tap_arm`'s `armedHere` the second). A reassigned scalar cannot
			cross by reference — a callee handed the value keeps the old one forever — so
			the only safe move is to give it an owner and hand out the writer. ]]
		expect(declarationsOf(roundSource, "disposed")).toBe(1)
		expect(#assignmentsOutsideDeclaration(roundSource, "disposed")).toBe(1)
		--[[ AND THE ASSIGNMENT IS INSIDE `dispose()`, not merely somewhere in the file:
			the accessor is the whole point, so a `disposed = true` set anywhere else — the
			end of `request`, say — would satisfy a bare count and destroy the contract. ]]
		local disposeBlock = string.match(roundSource, "\n\t\tdispose = function%(%)\n(.-)\n\t\tend,") :: string?
		assert(disposeBlock ~= nil, "no `dispose = function()` block to read")
		expect(#assignmentsOutsideDeclaration(disposeBlock :: string, "disposed")).toBe(1)
		--[[ THE CROSS-FILE HALF IS TAKEN OVER THE RENDERER AS ITS PARTS, and this is
			where the rule differs from `tap_arm`'s. `armedHere` is a coined name, so a
			repo-wide sweep for it means something; `disposed` is the ORDINARY name for a
			per-object teardown latch and five unrelated modules own one
			(`present/feedback`, `input/drag_registry`, `input/actions`,
			`async/resources`, `render/transitions`) — reporting those would be reporting
			other objects' state, and scoping by DIRECTORY does not help, because the
			transitions module is in `src/render/` and is not part of the renderer.
			`tests/lib/renderer_source.all()` is the reading of "the renderer" this rule
			needs, and the one `drag_bridge_seam` already counts over. Two writes total —
			the declaration and the assignment — and both of them are the ones above. ]]
		local parts = renderer_source.all()
		local writes = declarationsOf(parts, "disposed") + #assignmentsOutsideDeclaration(parts, "disposed")
		expect(writes).toBe(2)
		-- the join really did read this module, so a count of two means the right two
		expect(string.find(parts, "premeasure_round.new", 1, true) ~= nil).toBe(true)
	end)

	it("no module-level mutable state: everything per-surface lives inside `new`", function()
		--[[ A module-level `textInFlight` would be SHARED BY EVERY SURFACE in the
			process, which means one screen's answered round suppressing another's request
			for the same word — and worse, one screen's `dispose` killing every other
			screen's deliveries. Read from the text above the constructor. ]]
		local head =
			string.sub(roundSource, 1, string.find(roundSource, "function premeasure_round.new", 1, true) :: number)
		local body = stripComments(head)
		expect(string.find(body, "= {}", 1, true) ~= nil).toBe(true) -- the module table itself
		local offenders: { string } = {}
		for line in string.gmatch(body, "\n([^\n]*)") do
			local trimmed = string.match(line, "^%s*(.-)%s*$") :: string
			-- ...INCLUDING A TYPED ONE: `local shared: { [string]: boolean } = {}` walks
			-- straight past a scan anchored on `^local x%s*=%s*{` (tap_arm's own finding)
			if
				string.match(trimmed, "^local [%a_][%w_]*.*=%s*{") ~= nil
				and string.match(trimmed, "^local premeasure_round") == nil
			then
				table.insert(offenders, trimmed)
			end
		end
		expect(table.concat(offenders, " ")).toBe("")
	end)
end)

describe("the premeasure-round seam: EXPORTED == USED, one consumer, one leaf require", function()
	local rendererSource = fs.readFile(RENDERER_PATH)
	local roundSource = fs.readFile(ROUND_PATH)

	it("every accessor the module exports is used by the renderer, and every use is exported", function()
		local exported = exportsOf(roundSource)
		local used = usedOf(rendererSource)
		expect(#missingFrom(exported, used)).toBe(0) -- an accessor nobody calls
		expect(#missingFrom(used, exported)).toBe(0) -- a call that would be nil
		expect(sorted(exported)).toEqual({ "dispose", "pending", "request" })
		-- ...and the type says the same three things, so the two cannot drift
		expect(sorted(typeFields(roundSource, "PremeasureRound"))).toEqual(sorted(exported))
	end)

	it("there is exactly ONE consumer in src/, and the one require is a leaf the renderer shares", function()
		--[[ WALKED, NOT LISTED — `tests/lib/src_tree.luau` exists because a hand list of
			directories missed six of `src/`'s sixteen. `layout/text_metrics` is the pure
			per-word store: it requires nothing from `render/`, so it cannot be the route
			back, and the renderer requires it too — which is what "leaf" means here. ]]
		expect(src_tree.pathsContaining('require("./premeasure_round")')).toEqual({ RENDERER_PATH })
		local requires: { string } = {}
		for path in string.gmatch(stripComments(roundSource), 'require%("([^"]+)"%)') do
			table.insert(requires, path)
		end
		expect(requires).toEqual({ "../layout/text_metrics" })
		local metrics = src_tree.readAll()["src/layout/text_metrics.luau"]
		expect(metrics ~= nil).toBe(true)
		expect(string.find(stripComments(metrics :: string), "render/", 1, true)).toBe(nil)
		-- ...and the module names no renderer symbol at all
		for _, name in { "handles", "controller", "solveAndApply()", "lastRects" } do
			local body = stripComments(roundSource)
			expect(`{name}: {tostring(string.find(body, name, 1, true) ~= nil)}`).toBe(
				`{name}: {tostring(name == "solveAndApply()")}`
			)
		end
	end)

	it("NOTHING STAYED BEHIND: the renderer kept no second copy of the round", function()
		--[[ The failure this rule exists for is the one `stack_seam` records: a block
			"extracted" while a live copy stays in the host is two implementations that
			drift. `measureTextWidths` names three files in `src/` and each one plays a
			different part — the CALLER (here), the Roblox target that IMPLEMENTS it, and
			the target contract that DECLARES it. The renderer is not among them. ]]
		local namers: { string } = {}
		for path, text in src_tree.readAll() do
			if string.find(stripComments(text), "measureTextWidths", 1, true) ~= nil then
				table.insert(namers, path)
			end
		end
		table.sort(namers)
		expect(namers).toEqual({ "src/client/screen_target.luau", ROUND_PATH, "src/render/target_contract.luau" })
	end)
end)

--[[ ── THE BEHAVIOUR THE SPLIT MOVED ────────────────────────────────────────
	`tests/text_premeasure.spec.luau` drives the round itself (see the header). What
	it does not assert is the seam's own three-accessor contract: that `pending`
	answers the module's set rather than a renderer copy, and that `dispose` is what
	stops a late delivery now that the renderer no longer owns the flag. ]]

--[[ `text_metrics` IS A PROCESS-WIDE STORE, and it caught this file twice. A word
	measured by one case is measured for every LATER one, so a second surface built from
	the same sentence asks for NOTHING and the batch assertions read as a broken seam —
	hence a private vocabulary per case. And every batch carries `" "`, whose width is
	the same process-wide fact at that font and size for every spec that runs after this
	one: delivering an invented space width turned `region_expand`'s EXPAND-13 rung red
	from three hundred cases away. `resetMeasured()` at both ends of a measuring case is
	this repository's standing answer (`text_premeasure.spec`, `layout.spec`). ]]
local function surface(sentence: string): { controller: any, adapter: any }
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
	local adapter = fake_target.new()
	local bp = UI.Screen({
		id = "S",
		children = {
			UI.Text({ id = "T", text = sentence, width = { type = "fixed", px = 120 } }),
		},
	})
	local mounted = mountLib.mount(core, bp)
	local controller = renderer.attach(core, mounted, env, adapter)
	controller.initialRender()
	return { controller = controller, adapter = adapter }
end

local function anyWidth(word: string, size: number): number
	return (utf8.len(word) :: number) * size * 0.45
end

describe("the premeasure-round seam: the three accessors, driven", function()
	it("`pending` answers the module's in-flight set, and an answered round closes it", function()
		--[[ `controller.textPending` is one line now, so the thing worth asserting is
			that the line reaches the module's OWN set: a renderer that kept a second
			`textInFlight` would answer from a table nothing fills. ]]
		text_metrics.resetMeasured()
		local s = surface("zzqvex pendword alphaflit")
		expect(s.adapter.textBatchCount() > 0).toBe(true)
		expect(s.controller.textPending()).toBe(true)
		s.adapter.deliverTextWidths(anyWidth)
		expect(s.controller.textPending()).toBe(false)
		s.controller.dispose()
		text_metrics.resetMeasured()
	end)

	it("`dispose` cancels the outstanding delivery, so a late answer reaches nothing", function()
		--[[ THE ACCESSOR IS THE WRITER, and this is the case that says so: before the
			split `controller.dispose` assigned `disposed` and ran the cancel loop itself.
			If the renderer's teardown stopped calling `premeasureRound.dispose()`, the
			tokens would never run — and `fake_target`'s own header records what that
			costs: a held `done` closure keeps `solveAndApply`'s upvalues, so the whole
			mounted tree of a dismissed surface stays in memory. ]]
		text_metrics.resetMeasured()
		local s = surface("qxjvorp cancelword betaflit")
		expect(s.adapter.textBatchCount() > 0).toBe(true)
		s.controller.dispose()
		expect(s.adapter.textBatchCount()).toBe(0)
		-- the batch is gone from the adapter, so the engine's late answer calls nothing
		s.adapter.deliverTextWidths(anyWidth)
		-- ...and the words are still in flight, because nothing ever answered them
		expect(s.controller.textPending()).toBe(true)
		text_metrics.resetMeasured()
	end)
end)
