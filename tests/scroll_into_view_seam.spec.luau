--!strict
--[[ THE SCROLL-INTO-VIEW SEAM, MECHANISED — what keeps `render/scroll_into_view.luau`
	one-way.

	WHY A SPEC AND NOT A COMMENT. `tools/lune/verify/data/source-cap-ledger.md` records
	the rule every extraction in this repository is judged by: a block may leave a file
	only if it reads no mutable upvalue of its host, because otherwise the move creates
	a require BACK and the two files become one file with a slash in the middle. This
	seam's own ledger row PREDICTED a four-name read set — `adapter`, `handles`,
	`lastRects`, `scrollHostOf` — and the row said so as a HYPOTHESIS, not a claim: "a
	read-set scan is the cheap half and this row has been burned by the expensive half
	twice." Measured here: SIX names, not four, and `handles` is not one of them —
	`lastScrollRegions`, `screenRectOf` and `controller` (for `scrollPosition`/`scrollTo`,
	the pair `autoscroll_bridge.luau`'s own `Ctx` already carries for the identical
	reason) were missing from the prediction.

	  READ      every `deps.<field>` the module reads, comments stripped
	  WRITE     the half a read-set scan cannot see — and the finding here is that it
	            is EMPTY: both functions read the solved geometry and call ONE
	            encapsulated write (`controller.scrollTo`), and touch nothing else
	  DECLARED  every field its own `Deps` type names
	  PASSED    every key the renderer's `scroll_into_view.new({ … })` call hands over

	all three equal in both directions, plus the mutable-upvalue test over the six
	names, the no-rebind test from the module's side, no module-level mutable state,
	EXPORTED == BOUND, one consumer, ONE LEAF REQUIRE (`../layout/solver`, the
	`premeasure_round.luau` precedent) that cannot reach back, and nothing left behind.

	Each source rule is a pure function of a string, so each carries a NEGATIVE
	CONTROL that feeds it a broken input and proves it reports. A check that cannot
	fail is decoration. The BEHAVIOUR half of this seam is mostly not here and does not
	need to be: `tests/native_scroll.spec.luau` drives `scrollToVisible` seven times and
	`tests/structural_incremental.spec.luau` drives `scrollHostFor` twice, both green
	across the split; the two cases at the bottom exist only to prove the WIRING —
	that the accessors bound onto `controller` truly reach this module and not a stale
	copy. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local fs = require("@lune/fs")
local src_tree = require("./lib/src_tree")

local customFactory = require("../src/core/custom")
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local fake_target = require("./lib/fake_target")

local RENDERER_PATH = "src/render/renderer.luau"
local SEAM_PATH = "src/render/scroll_into_view.luau"

--[[ COMMENTS ARE NOT CODE, and in this repository that is not a nicety: the block
	travelled with its own reasoning, and that reasoning names `lastRects`,
	`scrollHostOf`, `controller` and the rest in prose. A scan that counted them would
	report reads nobody makes. ]]
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
		string.match(stripComments(rendererSource), "local scrollIntoView = scroll_into_view%.new%({\n(.-)\n\t}%)")
	assert(call ~= nil, "no `scroll_into_view.new({ … })` call to read")
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

--[[ THE WRITE SCAN. A `<name>[key] = …` or `<name>.field = …` anywhere in the
	module body is a write to a table this seam was handed — the half a read-set scan
	(`depsFieldsRead` above) structurally cannot see, because a write never spells the
	name as `deps.field`, it spells it as the LOCAL the binding line created. ]]
local function writesInto(source: string, name: string): number
	local body = stripComments(source)
	local n = 0
	for _ in string.gmatch(body, "\n[ \t]*" .. name .. "%[[^%]]+%]%s*=[^=]") do
		n += 1
	end
	for _ in string.gmatch(body, "\n[ \t]*" .. name .. "%.[%a_][%w_]*%s*[%+%-]?=[^=]") do
		n += 1
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

local function boundOf(rendererSource: string): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for key in string.gmatch(stripComments(rendererSource), "= scrollIntoView%.([%a_][%w_]*)") do
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

describe("the scroll-into-view seam: READ == DECLARED == PASSED", function()
	local rendererSource = fs.readFile(RENDERER_PATH)
	local seamSource = fs.readFile(SEAM_PATH)

	it("every `deps` field the module reads is declared in its own `Deps`", function()
		local reads = depsFieldsRead(seamSource)
		expect(#missingFrom(reads, typeFields(seamSource, "Deps"))).toBe(0)
		-- ...and the set is not empty, which is the trap a set comparison invites, and
		-- it is SIX, not the four the ledger's own row predicted
		expect(sorted(reads)).toEqual({
			"adapter",
			"controller",
			"lastRects",
			"lastScrollRegions",
			"screenRectOf",
			"scrollHostOf",
		})
	end)

	it("every field `Deps` declares is one the module reads AND one the renderer passes", function()
		expect(#missingFrom(typeFields(seamSource, "Deps"), depsFieldsRead(seamSource))).toBe(0)
		--[[ The call is a table CONSTRUCTOR, so a field the module declares and the
			renderer forgot arrives as `nil` rather than as a missing argument — and a nil
			`scrollHostOf` here is every keep-visible call silently refusing. ]]
		expect(#missingFrom(typeFields(seamSource, "Deps"), passedFields(rendererSource))).toBe(0)
		expect(#missingFrom(passedFields(rendererSource), typeFields(seamSource, "Deps"))).toBe(0)
	end)

	it("NEGATIVE CONTROL: the Deps and literal scans both report a changed set", function()
		local fakeType = "export type Deps = {\n\tadapter: any,\n\tghost: any,\n}\n"
		expect(sorted(typeFields(fakeType, "Deps"))).toEqual({ "adapter", "ghost" })
		local fakeCall = "\tlocal scrollIntoView = scroll_into_view.new({\n\t\tadapter = adapter,\n\t\tghost = g,\n\t})"
		expect(sorted(passedFields(fakeCall))).toEqual({ "adapter", "ghost" })
		expect(sorted(depsFieldsRead("local x = deps.ghost\n"))).toEqual({ "ghost" })
	end)
end)

describe("the scroll-into-view seam: THE WRITE SET IS EMPTY", function()
	local seamSource = fs.readFile(SEAM_PATH)

	it("neither function writes into any of the six names it was handed", function()
		--[[ THE HALF A READ-SET SCAN CANNOT SEE, and the finding this seam adds to the
			pattern `stack.luau`/`commit_walks.luau` recorded: those two seams WROTE
			something (one diagnostics list, sixteen renderer records); this one writes
			NOTHING. Both functions are pure reads over the solved geometry, plus one
			call each into `controller.scrollTo` — a write, but an ENCAPSULATED one this
			module never touches directly, same as `stack.luau` calling `place`. ]]
		local offenders: { string } = {}
		for _, name in { "adapter", "controller", "lastRects", "lastScrollRegions", "scrollHostOf" } do
			local n = writesInto(seamSource, name)
			if n > 0 then
				table.insert(offenders, `{name}({n})`)
			end
		end
		expect(table.concat(offenders, " ")).toBe("")
	end)

	it("NEGATIVE CONTROL: the write scan sees an index write and a field write", function()
		expect(writesInto("\n\tlastRects[path] = {}\n", "lastRects")).toBe(1)
		expect(writesInto("\n\tcontroller.scrollPosition = nil\n", "controller")).toBe(1)
		-- ...and a READ (a `==` compare, an index READ) is not a write
		expect(writesInto("\n\tif lastRects[path] == nil then\n", "lastRects")).toBe(0)
	end)
end)

describe("the scroll-into-view seam: the mutable-upvalue test itself", function()
	local rendererSource = fs.readFile(RENDERER_PATH)
	local seamSource = fs.readFile(SEAM_PATH)

	it("every name that crosses is declared ONCE by the renderer and never reassigned", function()
		--[[ THE LEDGER'S RULE, APPLIED TO THE SIX NAMES RATHER THAN ASSERTED ABOUT THE
			BLOCK. Three are by-reference tables the renderer keeps writing to elsewhere
			(`lastRects`, `lastScrollRegions`, `scrollHostOf`), one is a `local function`
			(`screenRectOf`), one is `attach`'s own PARAMETER (`adapter`, zero
			declarations), and `controller` is the renderer's own `local controller = {}`
			— declared exactly once and never rebound, which is why the whole table may
			cross by reference. ]]
		local offenders: { string } = {}
		for _, field in sorted(typeFields(seamSource, "Deps")) do
			local decls = declarationsOf(rendererSource, field)
			local assigns = assignmentsOutsideDeclaration(rendererSource, field)
			if (field ~= "adapter" and decls ~= 1) or (field == "adapter" and decls ~= 0) or #assigns > 0 then
				table.insert(offenders, `{field}(decls={decls},assigns={#assigns})`)
			end
		end
		expect(table.concat(offenders, " ")).toBe("")
		expect(declarationsOf(rendererSource, "adapter")).toBe(0)
		expect(declarationsOf(rendererSource, "controller")).toBe(1)
		expect(declarationsOf(rendererSource, "screenRectOf")).toBe(1)
	end)

	it("...and the module never REBINDS one either — the same test from the other side", function()
		local offenders: { string } = {}
		for field, name in bindings(seamSource) do
			if #assignmentsOutsideDeclaration(seamSource, name) > 0 then
				table.insert(offenders, `{field}->{name}`)
			end
		end
		expect(table.concat(offenders, " ")).toBe("")
		expect(sorted(bindings(seamSource) :: any)).toEqual({
			"adapter",
			"controller",
			"lastRects",
			"lastScrollRegions",
			"screenRectOf",
			"scrollHostOf",
		})
	end)

	it("no module-level mutable state: everything per-surface lives inside `new`", function()
		local head =
			string.sub(seamSource, 1, string.find(seamSource, "function scroll_into_view.new", 1, true) :: number)
		local body = stripComments(head)
		expect(string.find(body, "= {}", 1, true) ~= nil).toBe(true) -- the module table itself
		local offenders: { string } = {}
		for line in string.gmatch(body, "\n([^\n]*)") do
			local trimmed = string.match(line, "^%s*(.-)%s*$") :: string
			if
				string.match(trimmed, "^local [%a_][%w_]*.*=%s*{") ~= nil
				and string.match(trimmed, "^local scroll_into_view") == nil
			then
				table.insert(offenders, trimmed)
			end
		end
		expect(table.concat(offenders, " ")).toBe("")
	end)

	it("NEGATIVE CONTROL: a reassignment is reported and a table-constructor entry is not", function()
		local reassigned = "\nlocal alpha = {}\n\talpha = {}\n"
		expect(#assignmentsOutsideDeclaration(reassigned, "alpha")).toBe(1)
		local constructorEntry = "\nlocal alpha = {}\n\tfoo({\n\t\talpha = alpha,\n\t})\n"
		expect(#assignmentsOutsideDeclaration(constructorEntry, "alpha")).toBe(0)
		expect(declarationsOf(reassigned, "alpha")).toBe(1)
		expect(declarationsOf("\nlocal function beta()\n", "beta")).toBe(1)
	end)
end)

describe("the scroll-into-view seam: EXPORTED == BOUND, one consumer, one leaf require", function()
	local rendererSource = fs.readFile(RENDERER_PATH)
	local seamSource = fs.readFile(SEAM_PATH)

	it("every accessor the module exports is bound onto the controller, and every binding is exported", function()
		local exported = exportsOf(seamSource)
		local bound = boundOf(rendererSource)
		expect(#missingFrom(exported, bound)).toBe(0) -- an accessor nobody binds
		expect(#missingFrom(bound, exported)).toBe(0) -- a binding that would be nil
		expect(sorted(exported)).toEqual({ "scrollHostFor", "scrollToVisible" })
		-- ...and the type says the same two things, so the two cannot drift
		expect(sorted(typeFields(seamSource, "ScrollIntoView"))).toEqual(sorted(exported))
	end)

	it("the two PUBLIC names are unchanged, and their in-tree callers still find them", function()
		--[[ `controls/table.luau`, `controls/tab_view.luau` and `present/presenter.luau`
			all call these through `controller`, guarding on the method existing rather
			than on which file defines it — the shape a rename must not be allowed to
			reach. ]]
		expect(string.find(fs.readFile("src/controls/table.luau"), "controller.scrollHostFor", 1, true) ~= nil).toBe(
			true
		)
		expect(string.find(fs.readFile("src/controls/tab_view.luau"), "scrollToVisible(path)", 1, true) ~= nil).toBe(
			true
		)
		expect(
			string.find(fs.readFile("src/present/presenter.luau"), "controller.scrollToVisible(path)", 1, true) ~= nil
		).toBe(true)
	end)

	it("there is exactly ONE consumer in src/, and the one require is a leaf the renderer shares", function()
		--[[ WALKED, NOT LISTED — `tests/lib/src_tree.luau` exists because a hand list of
			directories missed six of `src/`'s sixteen. `layout/solver` is required by the
			renderer already (line 22 of this very file, for `solver.solve`), so this
			require adds no edge the graph did not already have. ]]
		expect(src_tree.pathsContaining('require("./scroll_into_view")')).toEqual({ RENDERER_PATH })
		local requires: { string } = {}
		for path in string.gmatch(stripComments(seamSource), 'require%("([^"]+)"%)') do
			table.insert(requires, path)
		end
		expect(requires).toEqual({ "../layout/solver" })
		local solverSrc = src_tree.readAll()["src/layout/solver.luau"]
		expect(solverSrc ~= nil).toBe(true)
		expect(string.find(stripComments(solverSrc :: string), "render/", 1, true)).toBe(nil)
		expect(string.find(stripComments(solverSrc :: string), 'require("./scroll_into_view")', 1, true)).toBe(nil)
	end)

	it("NEGATIVE CONTROL: the export, bound and require scans all report", function()
		local fake = "\n\treturn {\n\t\tscrollHostFor = scrollHostFor,\n\t\textra = extra,\n\t}\nend"
		expect(sorted(exportsOf(fake))).toEqual({ "extra", "scrollHostFor" })
		expect(sorted(boundOf("controller.scrollHostFor = scrollIntoView.scrollHostFor\n"))).toEqual({
			"scrollHostFor",
		})
		local fakeRequires: { string } = {}
		for path in string.gmatch(stripComments('local s = require("./renderer")\n'), 'require%("([^"]+)"%)') do
			table.insert(fakeRequires, path)
		end
		expect(fakeRequires).toEqual({ "./renderer" })
	end)
end)

describe("the scroll-into-view seam: nothing left behind", function()
	it("the renderer kept no second copy of either function's body", function()
		--[[ THE FAILURE THIS REPOSITORY HAS ALREADY PAID FOR ONCE (`stack_seam`'s own
			case): a block "moved" by copying, leaving the host's version live and the
			two drifting. Each line below is distinctive to the block that left. ]]
		local body = stripComments(fs.readFile(RENDERER_PATH))
		expect(string.find(body, "solver.keepVisibleOffset(top, size, offset, band, extent)", 1, true)).toBe(nil)
		expect(
			string.find(
				body,
				"local hostPath: string? = if includeSelf == true and lastScrollRegions[path] ~= nil",
				1,
				true
			)
		).toBe(nil)
		expect(string.find(body, "maxScroll = math.max(0, extent - band),", 1, true)).toBe(nil)
		--[[ THREE NEAR-MISSES, DELIBERATELY *NOT* ON THAT LIST, and each is why this
			case had to be written by measurement rather than by eye: `scrollHostOf` is
			still WRITTEN by the structural sync and the removal sweep (it is a
			by-reference table, not a moved block), `controller.scrollPosition` and
			`controller.scrollTo` are the two methods this family CALLS and do not own —
			both stay, and both are still called from the new module's own source. ]]
		expect(string.find(body, "scrollHostOf[node.path] = host", 1, true) ~= nil).toBe(true)
		expect(string.find(body, "function controller.scrollPosition(path: string)", 1, true) ~= nil).toBe(true)
		expect(string.find(body, "function controller.scrollTo(path: string, pos:", 1, true) ~= nil).toBe(true)
	end)

	it("NEGATIVE CONTROL: the leftover scan reports a planted copy", function()
		local planted = "\n\tlocal wanted = solver.keepVisibleOffset(top, size, offset, band, extent)\n"
		expect(string.find(planted, "solver.keepVisibleOffset(top, size, offset, band, extent)", 1, true) ~= nil).toBe(
			true
		)
	end)
end)

--[[ ── THE WIRING, DRIVEN ─────────────────────────────────────────────────────
	`tests/native_scroll.spec.luau` (seven cases) and `tests/structural_incremental.spec.luau`
	(two cases) already drive the BEHAVIOUR this block owns, unmoved by the split. What
	they cannot prove about THIS commit is that `controller.scrollToVisible` and
	`controller.scrollHostFor` are truly the bindings this file installs rather than a
	stale pair left over from a half-finished edit — so these two cases exist only to
	confirm the wiring reaches the new module at all. ]]

local function scroller(): { controller: any, adapter: any }
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 300, h = 200 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local rows = {}
	for i = 1, 20 do
		table.insert(rows, UI.Text({ id = `R{i}`, text = `row {i}`, height = { type = "fixed", px = 40 } }))
	end
	local bp = UI.Screen({
		id = "S",
		padding = 0,
		gap = 0,
		children = {
			UI.ScrollView({
				id = "List",
				width = { type = "fill" },
				height = { type = "fixed", px = 200 },
				gap = 0,
				padding = 0,
				children = rows,
			}),
		},
	})
	local mounted = mountLib.mount(core, bp)
	local adapter = fake_target.new()
	local controller = renderer.attach(core, mounted, env, adapter)
	controller.initialRender()
	return { controller = controller, adapter = adapter }
end

describe("the scroll-into-view seam: the wiring, driven through renderer.attach", function()
	it("`controller.scrollToVisible` reaches the new module and moves the host", function()
		local s = scroller()
		expect(s.controller.scrollToVisible("/S/List/R20")).toBe(true)
		expect(s.adapter.scrollPositionOf("/S/List").y > 0).toBe(true)
		-- a path with no scroll host at all is a clean `false`, not an error
		expect(s.controller.scrollToVisible("/S")).toBe(false)
	end)

	it("`controller.scrollHostFor` reaches the new module and answers the host record", function()
		local s = scroller()
		local host = s.controller.scrollHostFor("/S/List/R10")
		expect(host ~= nil).toBe(true)
		expect(host.path).toBe("/S/List")
		expect(host.axis).toBe("y")
		expect(host.maxScroll > 0).toBe(true)
		-- a node with no scroll host answers nil, not an error
		expect(s.controller.scrollHostFor("/S")).toBe(nil)
	end)
end)
