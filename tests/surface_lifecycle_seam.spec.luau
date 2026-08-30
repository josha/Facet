--!strict
--[[ THE SURFACE-LIFECYCLE SEAM, MECHANISED — what keeps
	`present/surface_lifecycle.luau` one-way.

	WHY A SPEC AND NOT A COMMENT. `docs/handoff/SOURCE_CAP_LEDGER.md` records the
	rule every extraction in this repository is judged by: a block may leave a
	file only if it reads no mutable upvalue of its host, because otherwise the
	move creates a require BACK and the two files become one file with a slash in
	the middle. `measure_facts_seam.spec` mechanised that for a seam with NO
	parameter object (everything arrived on a `ctx` the module did not own).
	THIS SEAM HAS ONE: `presenter.new` builds a fifteen-field record and hands it
	over once. So the three sets are taken at the object rather than through it:

	  HOSTED    every key the presenter's `surfaceLifecycleLib.new({ … })` call
	            actually writes into the record
	  DECLARED  every `local <name> = ctx.<name>` the module unpacks
	  READ      every unpacked name the module's BODY actually uses

	all three equal, plus the shared WRITE surface (one field of one record, and
	the presented stack), EXPORTED == BOUND in both directions, the ONE consumer,
	the one-way require, and that the module holds no module-level mutable state.

	AND ONE RULE NO PREVIOUS SEAM IN THIS DOCUMENT NEEDED: `displayLayer`. It is
	the only mutable scalar that genuinely crossed — `makeHandle` INCREMENTS the
	cross-surface z counter and `dismiss` RESETS it — so it became a RECORD
	(`{ value = 0 }`) shared by reference, the `table.luau` technique the ledger
	names. A record is only a fix while BOTH writers go through the same object,
	and a later edit that re-declares a plain number on either side would restore
	the defect the reset exists to prevent (a long-lived session pushing every
	future base screen past the toast band) with nothing to say so. That is the
	last describe block below.

	Each rule is a pure function of a string, so each carries a NEGATIVE CONTROL
	that feeds it a broken input and proves it reports. A check that cannot fail
	is decoration.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local fs = require("@lune/fs")
-- every `.luau` under `src/`, ONE enumeration (see its header for the nine-of-
-- fifteen hole this replaces)
local srcTree = require("./lib/src_tree")

local PRESENTER_PATH = "src/present/presenter.luau"
local LIFECYCLE_PATH = "src/present/surface_lifecycle.luau"

--[[ COMMENTS ARE NOT CODE, and in this file that is not a nicety: the moved
	blocks carry the reasoning of seven director rounds, and those paragraphs
	name `presenter.dismiss`, `makeHandle` and `displayLayer` while discussing
	code that is now one file over. A scan that counted them would report reads
	and writes that do not exist. ]]
local function stripComments(source: string): string
	local out = string.gsub("\n" .. source, "%-%-%[%[.-%]%]", " ")
	out = string.gsub(out, "\n[ \t]*%-%-[^\n]*", "\n")
	return out
end

-- the module's own unpack block: `local <name> = ctx.<name>`, which is the only
-- place `ctx` may be touched at all (asserted below).
local function declaredOf(lifecycle: string): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for name in string.gmatch(stripComments(lifecycle), "\n\tlocal [%a_][%w_]* = ctx%.([%a_][%w_]*)") do
		out[name] = true
	end
	return out
end

-- every key the presenter WRITES into the record it hands over. The literal is
-- read by its own delimiters rather than by line count, so a field added in the
-- middle of it is seen.
local function hostedOf(presenter: string): { [string]: boolean }
	local block = string.match(presenter, "surfaceLifecycleLib%.new%({\n(.-)\n\t}%)")
	assert(block ~= nil, "no `surfaceLifecycleLib.new({ … })` record literal to read")
	local out: { [string]: boolean } = {}
	for key in string.gmatch("\n" .. (block :: string), "\n\t\t([%a_][%w_]*) =") do
		out[key] = true
	end
	return out
end

--[[ THE UNPACK LINE NAMES THE NAME TWICE (`local X = ctx.X`), so a count that
	included it could never reach zero and the rule would be decoration — the
	lesson `measure_facts_seam` paid for as mutation M7. The unpack block is
	removed before counting uses. ]]
local function bodyWithoutUnpack(lifecycle: string): string
	return (string.gsub(stripComments(lifecycle), "\n\tlocal [%a_][%w_]* = ctx%.[%a_][%w_]*", ""))
end

local function unusedIn(body: string, names: { [string]: boolean }): { string }
	local out: { string } = {}
	for name in names do
		local _, uses = string.gsub(body, `[^%w_]{name}[^%w_]`, "")
		if uses < 1 then
			table.insert(out, name)
		end
	end
	table.sort(out)
	return out
end

-- every name the module hangs off the table it returns
local function exportsOf(lifecycle: string): { [string]: boolean }
	local block = string.match(lifecycle, "\n\treturn {\n(.-)\n\t}\nend\n")
	assert(block ~= nil, "no `return { … }` block to read")
	local out: { [string]: boolean } = {}
	for key in string.gmatch("\n" .. (block :: string), "\n\t\t([%a_][%w_]*) =") do
		out[key] = true
	end
	return out
end

-- every name the presenter takes off the constructed module, whether it binds it
-- to a local (`local syncFocusVisuals = surfaceLifecycle.syncFocusVisuals`) or
-- straight onto the instance (`self.dismiss = surfaceLifecycle.dismiss`)
local function boundOf(presenter: string): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for key in string.gmatch(stripComments(presenter), "= surfaceLifecycle%.([%a_][%w_]*)") do
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

describe("the surface-lifecycle seam: HOSTED == DECLARED == READ", function()
	local presenter = fs.readFile(PRESENTER_PATH)
	local lifecycle = fs.readFile(LIFECYCLE_PATH)

	it("every field the presenter hands over is one the module unpacks", function()
		local hosted = hostedOf(presenter)
		expect(#missingFrom(hosted, declaredOf(lifecycle))).toBe(0)
		-- ...and the set is not empty, which is the trap a set comparison invites:
		-- two empty sets are equal
		-- 16, not 15: `SURFACE_LAYER` joined 2026-08-23 for `raise` (registry
		-- item 23; W3-D)
		expect(#sorted(hosted)).toBe(16)
	end)

	it("every field the module unpacks is one the presenter hands over", function()
		--[[ THE DIRECTION THAT CATCHES A SILENT `nil`. Nothing type-checks this
			record — `ctx: any` is what keeps the require graph acyclic — so a field
			renamed on the presenter's side arrives here as `nil` and fails on the
			frame that first needs it, which for `retireRevealFor` is a dismissal
			during an exit transition. This is the assertion that turns that back
			into a shape a suite can see. ]]
		expect(#missingFrom(declaredOf(lifecycle), hostedOf(presenter))).toBe(0)
	end)

	it("every unpacked name is USED by the module, not just unpacked", function()
		--[[ The third set, and the one the two comparisons above cannot see: the
			key exists, the unpack exists, and the last call site left. That is a
			fact the presenter is still computing for nobody, one indirection
			further out. ]]
		expect(table.concat(unusedIn(bodyWithoutUnpack(lifecycle), declaredOf(lifecycle)), " ")).toBe("")
	end)

	it("`ctx` is touched NOWHERE but the unpack block", function()
		--[[ WHAT MAKES THE THREE SETS MEAN ANYTHING. If the module could reach
			`ctx.something` deep in a body, the unpack block would stop being the
			declaration of what crosses and the comparison above would be measuring
			a subset. Every read is hoisted, once, at the top of `new`. ]]
		local body = bodyWithoutUnpack(lifecycle)
		expect(string.find(body, "ctx.", 1, true)).toBe(nil)
	end)

	it("NEGATIVE CONTROL: each scan reads what it claims to, and reports the pair out of step", function()
		local hosted = { alpha = true, beta = true }
		local declared = { alpha = true, gamma = true }
		expect(missingFrom(hosted, declared)[1]).toBe("beta")
		expect(missingFrom(declared, hosted)[1]).toBe("gamma")
		-- a `ctx.` named inside a comment is NOT an unpack (this file is mostly
		-- comment by volume, so the trap is live)
		local fake = "\n\t-- local ghost = ctx.ghost\n\tlocal real = ctx.real\n"
		expect(sorted(declaredOf(fake))).toEqual({ "real" })
		-- an unpacked-but-unused name is reported
		expect(unusedIn("\n\treal()\n", { real = true, ghost = true })).toEqual({ "ghost" })
		-- and the record literal is read by its delimiters, not by position
		local literal = "\tlocal m = surfaceLifecycleLib.new({\n\t\talpha = alpha,\n\t\tbeta = x.beta,\n\t})\n"
		expect(sorted(hostedOf(literal))).toEqual({ "alpha", "beta" })
	end)
end)

describe("the surface-lifecycle seam: the shared WRITE surface", function()
	local lifecycle = fs.readFile(LIFECYCLE_PATH)

	-- every ctx-derived name the module REBINDS, and every one it writes a field
	-- or an index of. The first would make the record a lie; the second is the
	-- state the two files genuinely share.
	local function rebound(source: string, names: { [string]: boolean }): { string }
		local body = bodyWithoutUnpack(source)
		local out: { string } = {}
		for name in names do
			if string.find(body, `[^%w_.]{name}%s*=[^=]`) ~= nil then
				table.insert(out, name)
			end
		end
		table.sort(out)
		return out
	end

	local function writtenThrough(source: string, names: { [string]: boolean }): { string }
		local body = bodyWithoutUnpack(source)
		local out: { string } = {}
		for name in names do
			if
				string.find(body, `[^%w_.]{name}%.[%a_][%w_]*%s*=[^=]`) ~= nil
				or string.find(body, `[^%w_.]{name}%.[%a_][%w_]*%s*%+=`) ~= nil
				or string.find(body, `[^%w_.]{name}%[[^%]]+%]%s*=[^=]`) ~= nil
			then
				table.insert(out, name)
			end
		end
		table.sort(out)
		return out
	end

	it("no name the presenter handed over is ever rebound here", function()
		-- a rebind would give the two files two different values under one name,
		-- which is the whole failure a by-reference record is supposed to prevent
		expect(rebound(lifecycle, declaredOf(lifecycle))).toEqual({})
	end)

	it("the module writes through exactly ONE of them, and it is the z record", function()
		--[[ THE COST OF THIS SPLIT, STATED AS A SET. Fourteen of the fifteen names
			are read-only here: registries the module calls verbs on, functions it
			invokes, the presenter instance it reaches two names back through.
			`displayLayer` is the fifteenth, and it is shared state by construction
			— `makeHandle` counts up, `dismiss` resets on an empty stack. A SECOND
			NAME HERE IS THE FINDING: it means another value the presenter owns has
			quietly acquired a second writer in a second file. ]]
		expect(writtenThrough(lifecycle, declaredOf(lifecycle))).toEqual({ "displayLayer" })
	end)

	it("the presented stack is mutated by exactly one call, and never rebuilt", function()
		--[[ `stack` is the other shared object, and it is shared by design — every
			surface verb in both files reads the live array. What must stay true is
			that this file only ever REMOVES from it: presenting is the presenter's
			(`makeHandle` appends), and a `table.insert` or an index write here
			would mean two files could disagree about surface order, which is what
			the cross-surface z band is derived from. ]]
		local body = bodyWithoutUnpack(lifecycle)
		local _, removes = string.gsub(body, "table%.remove%(stack", "")
		expect(removes).toBe(1)
		expect(string.find(body, "table.insert(stack", 1, true)).toBe(nil)
		expect(string.find(body, "stack = ", 1, true)).toBe(nil)
	end)

	it("NEGATIVE CONTROL: the write scans see each spelling, and a read is not a write", function()
		local names = { alpha = true, beta = true, gamma = true, delta = true, eps = true, zeta = true }
		local text = "\n\talpha.value = 1\n\tbeta[key] = 2\n\tgamma.n += 1\n\tlocal x = delta.value\n"
			.. "\tif eps.n == nil then\n\tzeta = 3\n"
		expect(writtenThrough(text, names)).toEqual({ "alpha", "beta", "gamma" })
		expect(rebound(text, names)).toEqual({ "zeta" })
		-- `handle.alpha = 1` is a write to a HANDLE, not to the name `alpha`
		expect(writtenThrough("\n\thandle.alpha = 1\n", { alpha = true })).toEqual({})
	end)
end)

describe("the surface-lifecycle seam: EXPORTED == BOUND, one consumer, one-way require", function()
	local presenter = fs.readFile(PRESENTER_PATH)
	local lifecycle = fs.readFile(LIFECYCLE_PATH)

	it("every name the module exports is bound by the presenter, and every bound name is exported", function()
		local exported = exportsOf(lifecycle)
		local bound = boundOf(presenter)
		expect(#missingFrom(exported, bound)).toBe(0) -- an export nobody takes
		expect(#missingFrom(bound, exported)).toBe(0) -- a binding that would be nil
		-- "raise" joined 2026-08-23 (registry item 23; W3-D)
		expect(sorted(exported)).toEqual({ "back", "dismiss", "raise", "refresh", "syncFocusVisuals" })
	end)

	it("four of the five are bound straight onto the presenter under their original names", function()
		--[[ THE CLAIM THE MOVE RESTS ON: not one call site changed. `self.dismiss`,
			`self.back`, `self.raise` and `self.refresh` are public verbs with
			consumers in RR and in every example, so the binding form is asserted
			literally rather than inferred from a set. `syncFocusVisuals` is the
			fifth and is bound to a LOCAL, because the presenter wraps it
			(`self.syncFocusVisuals()` reads the graph's current focus first). ]]
		for _, name in { "dismiss", "back", "refresh", "raise" } do
			expect(string.find(presenter, `\n\tself.{name} = surfaceLifecycle.{name}\n`) ~= nil).toBe(true)
			-- ...and the presenter no longer DECLARES it, which is the half a set
			-- comparison cannot see: a leftover `function self.dismiss(` further
			-- down the file would silently win
			expect(string.find(presenter, `function self.{name}(`, 1, true)).toBe(nil)
		end
		expect(string.find(presenter, "local syncFocusVisuals = surfaceLifecycle.syncFocusVisuals", 1, true) ~= nil).toBe(
			true
		)
	end)

	it("there is exactly ONE consumer of the module in src/", function()
		--[[ MATCHED BY THE PATH'S TAIL, NOT BY `"./surface_lifecycle"` — measured,
			not chosen. A scan pinned to the sibling spelling cannot see a consumer
			in another directory (`require("../present/surface_lifecycle")` from
			`src/controls`), which is exactly the second consumer this rule exists
			to notice, and the mutation that planted one left the check green
			(mutation M15, 2026-08-22). ]]
		--[[ ...AND OVER THE WHOLE TREE, not over nine of its fifteen directories
			(rulings P5 + PRES-X minor, fixed 2026-08-22). The directory list here was
			hand-written and six subdirectories plus every top-level `src/*.luau` were
			outside it, so the second-consumer this case exists to notice could have
			appeared in a dozen places and still read "exactly one".
			`tests/lib/src_tree.luau` is the one enumeration. ]]
		expect(srcTree.pathsMatching('require%("[^"]*surface_lifecycle"%)')).toEqual({ PRESENTER_PATH })
	end)

	it("the module requires the presenter NOWHERE — the require is one-way", function()
		for path in string.gmatch(lifecycle, 'require%("([^"]+)"%)') do
			expect(string.match(path, "presenter$") == nil).toBe(true)
		end
		-- ...and the direction that IS allowed is present, so this pair of
		-- assertions cannot both pass by the module having no requires at all
		expect(string.find(presenter, 'require("./surface_lifecycle")', 1, true) ~= nil).toBe(true)
		expect(string.find(lifecycle, 'require("./focus_map")', 1, true) ~= nil).toBe(true)
	end)

	it("the only way back to the presenter is the instance, and it carries exactly two names", function()
		--[[ `back` dismisses through `presenter.dismiss` and the refresh body ends
			by calling `presenter.syncFocusVisuals()`. Both are late-bound through
			the table every other caller already uses, which is what stops them
			being a require — and round 7's rule (ONE copy of the "does this surface
			own input" decision) is why the second one exists at all. A third name
			appearing here is a module growing an opinion about the presenter's
			shape, and is worth a reader's attention. ]]
		local reached: { [string]: boolean } = {}
		for name in string.gmatch(bodyWithoutUnpack(lifecycle), "presenter%.([%a_][%w_]*)") do
			reached[name] = true
		end
		expect(sorted(reached)).toEqual({ "dismiss", "syncFocusVisuals" })
	end)
end)

describe("the surface-lifecycle seam: no module-level mutable state", function()
	local lifecycle = fs.readFile(LIFECYCLE_PATH)

	-- every module-level `local <name>` (column 0), and every module-level
	-- reassignment of one. A local assigned twice is an upvalue two presenters
	-- would share.
	local function moduleLocals(source: string): { [string]: boolean }
		local out: { [string]: boolean } = {}
		for name in string.gmatch("\n" .. stripComments(source), "\nlocal ([%a_][%w_]*)") do
			out[name] = true
		end
		for name in string.gmatch("\n" .. stripComments(source), "\nlocal function ([%a_][%w_]*)") do
			out[name] = true
		end
		return out
	end

	local function moduleReassignments(source: string, names: { [string]: boolean }): { string }
		local body = stripComments(source)
		local out: { string } = {}
		for name in names do
			if string.find(body, `\n{name}%s*=[^=]`) ~= nil then
				table.insert(out, name)
			end
		end
		table.sort(out)
		return out
	end

	it("no module-level local is ever reassigned — two presenters cannot share a helper", function()
		--[[ THE PROPERTY THE LEDGER'S TEST IS ACTUALLY ABOUT, asserted from the
			other side, and it has teeth here specifically: THREE of the names this
			module owns ARE mutable scalars (`lastArmedAim`, `armedSeen`,
			`prevFocusPath` — the armed-follows-focus state the director round
			added). They are correct because they live inside `new`, one set per
			presenter. Hoisting any of them to column 0 to "share" it would make two
			presented worlds in one Studio session aim each other's drag sessions,
			and nothing else in the suite would notice. ]]
		expect(moduleReassignments(lifecycle, moduleLocals(lifecycle))).toEqual({})
		-- ...and the three that must stay INSIDE `new` are still inside it
		for _, name in { "lastArmedAim", "armedSeen", "prevFocusPath" } do
			expect(string.find(lifecycle, `\n\tlocal {name}`) ~= nil).toBe(true)
			expect(string.find(lifecycle, `\nlocal {name}`)).toBe(nil)
		end
	end)

	it("NEGATIVE CONTROL: the reassignment scan sees a late assignment and ignores a local one", function()
		local text = "local alpha\nlocal beta = 1\nlocal function f()\n\tbeta = 2\nend\nalpha = 3\n"
		local names = moduleLocals(text)
		expect(names.alpha).toBe(true)
		expect(names.beta).toBe(true)
		-- `alpha = 3` is at column 0 and is the finding; `beta = 2` is indented
		-- inside a function and is not
		expect(moduleReassignments(text, names)).toEqual({ "alpha" })
	end)
end)

describe("the surface-lifecycle seam: `displayLayer` is ONE record with TWO writers", function()
	local presenter = fs.readFile(PRESENTER_PATH)
	local lifecycle = fs.readFile(LIFECYCLE_PATH)

	it("the presenter declares it as a record, never as a number", function()
		expect(string.find(presenter, "\n\tlocal displayLayer = { value = 0 }\n") ~= nil).toBe(true)
		expect(string.find(presenter, "\n\tlocal displayLayer = 0\n")).toBe(nil)
	end)

	it("both writers go through `.value` on that one object", function()
		--[[ THE DEFECT THE RESET EXISTS TO PREVENT (red-team item 3, MAJOR): the
			counter only ever went up, so a session that opened and closed a hundred
			surfaces pushed every FUTURE base screen's `displayOrder` past the toast
			band, and three hundred pushed it past the modal band — surfaces
			reordering that nobody touched. The fix is one line in each file, and it
			only works while both lines address the same table. ]]
		expect(string.find(presenter, "displayLayer.value += 100", 1, true) ~= nil).toBe(true)
		expect(string.find(presenter, "SURFACE_LAYER.base) + displayLayer.value", 1, true) ~= nil).toBe(true)
		expect(string.find(lifecycle, "displayLayer.value = 0", 1, true) ~= nil).toBe(true)
	end)

	--[[ A BARE WRITE IS A STATEMENT, and the two shapes that look like one are
		not: `local displayLayer = { value = 0 }` is the declaration (the line
		begins `local`), and `displayLayer = displayLayer,` is the record being
		HANDED OVER inside the ctx literal (the line ends in a comma). Everything
		else that starts with the name and assigns to it is the regression. ]]
	local function bareWrites(source: string): { string }
		local out: { string } = {}
		for line in string.gmatch("\n" .. stripComments(source), "\n([^\n]*)") do
			local trimmed = string.match(line, "^%s*(.-)%s*$") :: string
			if string.sub(trimmed, 1, 12) ~= "displayLayer" or string.sub(trimmed, -1) == "," then
				continue
			end
			local rest = string.sub(trimmed, 13)
			if string.match(rest, "^%s*=[^=]") ~= nil or string.match(rest, "^%s*%+=") ~= nil then
				table.insert(out, trimmed)
			end
		end
		return out
	end

	it("neither file writes the bare name, on either side of the seam", function()
		--[[ THE REGRESSION SHAPE, and it is a plausible one: a later edit that
			writes `displayLayer = 0` or `displayLayer += 100` type-checks fine
			against `any`, replaces the shared object with a number in ONE closure,
			and leaves the other file writing into a table nobody reads. Both
			halves keep working in every existing fixture — the counter is only
			observable across a hundred present/dismiss cycles. ]]
		expect(bareWrites(presenter)).toEqual({})
		expect(bareWrites(lifecycle)).toEqual({})
	end)

	it("NEGATIVE CONTROL: the bare-write scan reports each spelling and passes the three legal ones", function()
		expect(bareWrites("\n\tdisplayLayer = 0\n")).toEqual({ "displayLayer = 0" })
		expect(bareWrites("\n\tdisplayLayer += 100\n")).toEqual({ "displayLayer += 100" })
		expect(bareWrites("\n\tdisplayLayer.value = 0\n")).toEqual({})
		expect(bareWrites("\n\tlocal displayLayer = { value = 0 }\n")).toEqual({})
		expect(bareWrites("\n\t\tdisplayLayer = displayLayer,\n")).toEqual({})
		expect(bareWrites("\n\tif displayLayer.value == 0 then\n")).toEqual({})
	end)
end)
