--!strict
--[[ THE COMMIT-WALK SEAM, MECHANISED — what keeps `render/commit_walks.luau` one-way.

	WHY A SPEC AND NOT A COMMENT. `docs/handoff/SOURCE_CAP_LEDGER.md` records the
	rule every extraction in this repository is judged by: a block may leave a file
	only if it reads no mutable upvalue of its host, because otherwise the move
	creates a require BACK and the two files become one file with a slash in the
	middle. `table_rows_seam.spec` mechanised that for a parameter object;
	`measure_facts_seam.spec` mechanised it for a seam that had none. THIS ONE HAS
	A PARAMETER OBJECT AND TWENTY-ONE FIELDS IN IT, and eight of those fields are
	MUTABLE RECORDS the renderer keeps writing to after the walks have read them.
	So the property is the three set comparisons plus one this repository has not
	had to state before: what the two files SHARE, by name, and who is answerable
	for the lifetime of each shared thing.

	  READ      every `ctx.<field>` the module reads, comments stripped
	  DECLARED  every field its own `CommitCtx` type names
	  PASSED    every key the renderer's `commit_walks.new({ … })` call hands over

	all three equal in both directions, plus:

	  · the shared WRITE surface pinned to exactly twelve names — a thirteenth is
	    state that has quietly acquired two owners;
	  · every name that crosses is declared ONCE by the renderer and NEVER
	    reassigned, which is the mutable-upvalue test itself rather than a proxy
	    for it — a reassigned local cannot be shared by reference at all;
	  · the module never rebinds one of them either, which is the same failure
	    seen from this side: `handles = {}` here would silently detach the two
	    halves and every write after it would land in a table nobody reads;
	  · the module holds NO module-level mutable state, so two attached surfaces
	    can never see each other's walk;
	  · EXPORTED == BOUND == USED, one consumer, and the require is one-way.

	Each rule is a pure function of a string, so each carries a NEGATIVE CONTROL
	that feeds it a broken input and proves it reports. A check that cannot fail is
	decoration.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local fs = require("@lune/fs")

local RENDERER_PATH = "src/render/renderer.luau"
local WALKS_PATH = "src/render/commit_walks.luau"

--[[ COMMENTS ARE NOT CODE, and in this repository that is not a nicety: the walks
	travelled with their own reasoning blocks, and those blocks name records and
	seams by the spelling the scans below look for. A scan that counted them would
	report fields nobody reads and writes nobody makes. ]]
local function stripComments(source: string): string
	local out = string.gsub("\n" .. source, "%-%-%[%[.-%]%]", " ")
	out = string.gsub(out, "\n[ \t]*%-%-[^\n]*", "\n")
	return out
end

local function ctxFieldsRead(source: string): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for key in string.gmatch(stripComments(source), "ctx%.([%a_][%w_]*)") do
		out[key] = true
	end
	return out
end

-- every field a `type <name> = { … }` block declares. A comment line inside the
-- block never matches the `<name>:` shape, which is what lets the type carry its
-- reasoning without confusing this scan.
local function typeFields(source: string, typeName: string): { [string]: boolean }
	local block = string.match(source, "type " .. typeName .. " = {\n(.-)\n}")
	assert(block ~= nil, `no 'type {typeName}' block to read`)
	local out: { [string]: boolean } = {}
	for key in string.gmatch("\n" .. (block :: string), "\n\t([%a_][%w_]*):") do
		out[key] = true
	end
	return out
end

-- the keys the renderer's own construction call hands over
local function passedFields(renderer: string): { [string]: boolean }
	local call = string.match(stripComments(renderer), "local commitWalks = commit_walks%.new%({\n(.-)\n\t}%)")
	assert(call ~= nil, "no `commit_walks.new({ … })` call to read")
	local out: { [string]: boolean } = {}
	for key in string.gmatch("\n" .. (call :: string), "\n\t\t([%a_][%w_]*) =") do
		out[key] = true
	end
	return out
end

-- the names the module binds off the ctx, and the local each lands in
local function bindings(source: string): { [string]: string }
	local out: { [string]: string } = {}
	for name, field in string.gmatch(stripComments(source), "\n\tlocal ([%a_][%w_]*) = ctx%.([%a_][%w_]*)") do
		out[field] = name
	end
	return out
end

--[[ THE SHARED WRITE SURFACE. A field the module WRITES INTO is state the two
	files share; a field it only reads is a fact the renderer decided. Both
	spellings appear below — `lastVisible[path] = …` on a record, `stats.propWrites
	+= 1` on the counters. ]]
local function writtenFields(source: string): { [string]: boolean }
	local body = stripComments(source)
	local out: { [string]: boolean } = {}
	for field, name in bindings(source) do
		if string.find(body, `\n[ \t]*{name}%[[^%]]+%]%s*=[^=]`) ~= nil then
			out[field] = true
		elseif string.find(body, `\n[ \t]*{name}%.[%a_][%w_]*%s*%+=`) ~= nil then
			out[field] = true
		elseif string.find(body, `\n[ \t]*{name}%.[%a_][%w_]*%s*=[^=]`) ~= nil then
			out[field] = true
		end
	end
	return out
end

--[[ IS THIS NAME DECLARED ONCE AND NEVER REASSIGNED IN ITS HOST? A table-
	constructor entry (`handles = handles,`) reads exactly like an assignment, and
	the renderer contains twenty-one of them for these very names, so a scan that did
	not exclude a trailing comma would report every shared record as mutable. A
	`local` line is the declaration, not a reassignment. ]]
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

local function exportsOf(walks: string): { [string]: boolean }
	local block = string.match(walks, "\n\treturn {\n(.-)\n\t}\nend")
	assert(block ~= nil, "no returned table to read")
	local out: { [string]: boolean } = {}
	for key in string.gmatch("\n" .. (block :: string), "\n\t\t([%a_][%w_]*) =") do
		out[key] = true
	end
	return out
end

local function calledOf(renderer: string): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for key in string.gmatch(stripComments(renderer), "commitWalks%.([%a_][%w_]*)") do
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

describe("the commit-walk seam: READ == DECLARED == PASSED", function()
	local renderer = fs.readFile(RENDERER_PATH)
	local walks = fs.readFile(WALKS_PATH)

	it("every `ctx` field the module reads is declared in its own `CommitCtx`", function()
		local reads = ctxFieldsRead(walks)
		expect(#missingFrom(reads, typeFields(walks, "CommitCtx"))).toBe(0)
		-- ...and the set is not empty, which is the trap a set comparison invites:
		-- two empty sets are equal
		expect(#sorted(reads)).toBe(21)
	end)

	it("every field `CommitCtx` declares is one the module actually reads", function()
		-- the other direction, and it is the one that catches a field left behind
		-- by a change: a declared-but-unread field is a record the renderer is
		-- still handing over for nobody
		expect(#missingFrom(typeFields(walks, "CommitCtx"), ctxFieldsRead(walks))).toBe(0)
	end)

	it("every field `CommitCtx` declares is one the renderer actually PASSES", function()
		--[[ THE HALF A PARAMETER OBJECT IS SUPPOSED TO GIVE FOR FREE, and does not:
			the call is a table CONSTRUCTOR, so a field the module declares and the
			renderer forgot arrives as `nil` rather than as a missing argument, and
			`nil` here is a walk that silently stops writing. ]]
		expect(#missingFrom(typeFields(walks, "CommitCtx"), passedFields(renderer))).toBe(0)
		expect(#missingFrom(passedFields(renderer), typeFields(walks, "CommitCtx"))).toBe(0)
	end)

	it("NEGATIVE CONTROL: each scan reads what it claims to, and reports the pair out of step", function()
		local declared = { alpha = true, beta = true }
		local reads = { alpha = true, gamma = true }
		expect(missingFrom(reads, declared)[1]).toBe("gamma")
		expect(missingFrom(declared, reads)[1]).toBe("beta")
		local fake = "type Deps = {\n\t-- a comment, not a field\n\talpha: any,\n\tbeta: any,\n}"
		expect(#sorted(typeFields(fake, "Deps"))).toBe(2)
		-- a `ctx.` named inside a comment is NOT a read
		expect(sorted(ctxFieldsRead("--[[ ctx.ghost ]]\nlocal x = ctx.real\n"))).toEqual({ "real" })
		expect(sorted(ctxFieldsRead("\t-- ctx.ghost\n\tlocal x = ctx.real\n"))).toEqual({ "real" })
		expect(sorted(passedFields("local commitWalks = commit_walks.new({\n\t\talpha = alpha,\n\t})"))).toEqual({
			"alpha",
		})
	end)
end)

describe("the commit-walk seam: the shared WRITE surface, and who owns each lifetime", function()
	local renderer = fs.readFile(RENDERER_PATH)
	local walks = fs.readFile(WALKS_PATH)

	it("the module writes through exactly twelve of the twenty-one records it is handed", function()
		--[[ THE WHOLE POINT OF THE SPLIT, STATED AS A SET. Eight of these are the
			minimal-write records — one per verdict a walk sends — and each exists so
			a steady frame costs zero adapter writes. Three are the renderer's
			per-node bookkeeping the walks maintain as they go (`solverHidden`,
			`scrollAutoscroll`, `pathClipObservers`), and one is the counters.

			THE OTHER NINE ARE READ-ONLY AND MUST STAY SO: `adapter`, `handles`,
			`rectsEqual`, `paintedRectIn`, `pathEscapesClip`, `reculPathClips`,
			`paintHeld`, `pathNodes`, `inputSinks`. `paintHeld` in particular is PRESENTER-owned —
			set and cleared through `controller.setPaintHeld` — and a write to it from
			here would be a second authority for a presentation hold.

			A THIRTEENTH NAME IS THE FINDING. It means state the renderer decided has
			quietly acquired two writers, which is the shape that makes a later reader
			unable to tell which file is answerable for it. ]]
		expect(sorted(writtenFields(walks))).toEqual({
			"lastCompact",
			"lastHitRects",
			"lastPadding",
			"lastScrollRegions",
			"lastTextFont",
			"lastTextSize",
			"lastVisible",
			"lastWrapped",
			"pathClipObservers",
			"scrollAutoscroll",
			"solverHidden",
			"stats",
		})
	end)

	it("every per-path record the module writes is CLEARED by the renderer's removal sweep", function()
		--[[ THE LIFETIME CLAIM, MECHANISED. The module's header says these records
			stay with the renderer because the renderer owns mounting: it is the file
			that knows when a path has gone. If a record the walks write is not
			cleared when its path leaves, the surface accumulates a verdict for a node
			that no longer exists — and the next node to be given that path inherits
			it, which is exactly the recycle defect `lastCompact`'s own comment
			records against RascalRally's watch-cycle buttons.

			`stats` is the one exception and it is not a per-path record at all: it is
			the per-attach counter set, cleared by the attach going away. ]]
		local uncleared: { string } = {}
		for _, field in sorted(writtenFields(walks)) do
			if field == "stats" then
				continue
			end
			if string.find(stripComments(renderer), `\n[ \t]*{field}%[path%] = nil`) == nil then
				table.insert(uncleared, field)
			end
		end
		expect(table.concat(uncleared, " ")).toBe("")
	end)

	it("NEGATIVE CONTROL: the write scan sees each spelling, and a read is not a write", function()
		local text = "\n\tlocal a = ctx.alpha\n\tlocal b = ctx.beta\n\tlocal g = ctx.gamma\n\tlocal d = ctx.delta\n"
			.. "\n\ta[key] = 1\n\tb.count += 1\n\tg.field = 2\n\tlocal x = d[key]\n\tif d.eps == nil then\n"
		local seen = writtenFields(text)
		expect(seen.alpha).toBe(true)
		expect(seen.beta).toBe(true)
		expect(seen.gamma).toBe(true)
		expect(seen.delta).toBe(nil)
	end)
end)

describe("the commit-walk seam: the mutable-upvalue test itself", function()
	local renderer = fs.readFile(RENDERER_PATH)
	local walks = fs.readFile(WALKS_PATH)

	it("every name that crosses is declared ONCE by the renderer and never reassigned", function()
		--[[ THE LEDGER'S RULE, APPLIED TO THE TWENTY-ONE NAMES RATHER THAN ASSERTED
			ABOUT THE BLOCK. A reassigned local cannot be shared by reference at all —
			the callee keeps the OLD value and the two halves silently disagree — which
			is why `table.luau` had to turn two reassigned scalars into one record and
			`virtual_list` still owes the same on six. This seam needed neither,
			because every one of these twenty-one was already a table, a function or a
			parameter declared once. That is the fact, and here it is checked rather
			than remembered.

			`adapter` declares ZERO times on purpose: it is `attach`'s own parameter.
			A parameter is a local that is never reassigned, which is why it may
			cross. ]]
		local offenders: { string } = {}
		for _, field in sorted(typeFields(walks, "CommitCtx")) do
			local decls = declarationsOf(renderer, field)
			local assigns = assignmentsOutsideDeclaration(renderer, field)
			if decls > 1 or #assigns > 0 then
				table.insert(offenders, `{field}(decls={decls},assigns={#assigns})`)
			end
		end
		expect(table.concat(offenders, " ")).toBe("")
		-- ...and the scan really looked: twenty of the twenty-one are declared once
		-- and `adapter` is the parameter
		expect(declarationsOf(renderer, "adapter")).toBe(0)
		expect(declarationsOf(renderer, "lastHitRects")).toBe(1)
	end)

	it("the module never REBINDS one of them either — the same failure from this side", function()
		--[[ `handles = {}` inside this module would compile, run, and silently
			detach the two halves: every write after it lands in a table the renderer
			never reads, and the suite would go on being green because the walks would
			still be writing SOMETHING. The renderer half is checked above; this is
			the half nothing else can see. ]]
		local offenders: { string } = {}
		for field, name in bindings(walks) do
			if #assignmentsOutsideDeclaration(walks, name) > 0 then
				table.insert(offenders, field)
			end
		end
		table.sort(offenders)
		expect(table.concat(offenders, " ")).toBe("")
	end)

	it("the module holds NO module-level mutable state", function()
		--[[ Two attached surfaces each call `commit_walks.new`, so anything at
			module level is shared between them. Everything this module needs is
			either a require, a constant it never writes, or a per-attach local
			inside `new`. ]]
		local body = stripComments(walks)
		local offenders: { string } = {}
		for name in string.gmatch(body, "\nlocal ([%a_][%w_]*)[%s:=]") do
			if #assignmentsOutsideDeclaration(walks, name) > 0 then
				table.insert(offenders, name)
			end
		end
		expect(table.concat(offenders, " ")).toBe("")
		-- ...and the scan saw the module-level locals it is about
		expect(string.find(body, "\nlocal commit_walks = {}", 1, true) ~= nil).toBe(true)
	end)

	it("NEGATIVE CONTROL: a reassignment is reported and a table-constructor entry is not", function()
		local reassigned = "\nlocal alpha = {}\n\talpha = {}\n"
		expect(#assignmentsOutsideDeclaration(reassigned, "alpha")).toBe(1)
		-- the live spellings of `handles = handles,` inside a constructor
		local constructorEntry = "\nlocal alpha = {}\n\tfoo({\n\t\talpha = alpha,\n\t})\n"
		expect(#assignmentsOutsideDeclaration(constructorEntry, "alpha")).toBe(0)
		expect(declarationsOf(reassigned, "alpha")).toBe(1)
		expect(declarationsOf("\nlocal function beta()\n", "beta")).toBe(1)
	end)
end)

describe("the commit-walk seam: EXPORTED == CALLED, one consumer, one-way require", function()
	local renderer = fs.readFile(RENDERER_PATH)
	local walks = fs.readFile(WALKS_PATH)

	it("every walk the module exports is called by the renderer, and every call is exported", function()
		local exported = exportsOf(walks)
		local called = calledOf(renderer)
		expect(#missingFrom(exported, called)).toBe(0) -- a walk nobody runs
		expect(#missingFrom(called, exported)).toBe(0) -- a call that would be nil
		expect(sorted(exported)).toEqual({
			"hitRects",
			"padding",
			"scrollRegions",
			"textScale",
			"textVerdicts",
			"visible",
		})
	end)

	it("there is exactly ONE consumer of the module in src/", function()
		local seen: { string } = {}
		for _, dir in
			{
				"src/render",
				"src/layout",
				"src/present",
				"src/controls",
				"src/client",
				"src/tokens",
				"src/themes",
				"src/input",
				"src/core",
			}
		do
			for _, entry in fs.readDir(dir) do
				local path = `{dir}/{entry}`
				if not fs.isFile(path) or string.sub(path, -5) ~= ".luau" then
					continue
				end
				if string.find(fs.readFile(path), 'require("./commit_walks")', 1, true) ~= nil then
					table.insert(seen, path)
				end
			end
		end
		expect(seen).toEqual({ RENDERER_PATH })
	end)

	it("the module requires the renderer NOWHERE — the require is one-way", function()
		for path in string.gmatch(walks, 'require%("([^"]+)"%)') do
			expect(string.match(path, "renderer$") == nil).toBe(true)
		end
		-- ...and the direction that IS allowed is present, so this pair of
		-- assertions cannot both pass by the module having no requires at all
		expect(string.find(renderer, 'require("./commit_walks")', 1, true) ~= nil).toBe(true)
		expect(string.find(walks, 'require("./layout_node")', 1, true) ~= nil).toBe(true)
	end)

	it("the module names nothing off the renderer's own module table either", function()
		--[[ `renderer.compactForm` and `renderer.drawnButtonText` were what the
			text-verdict walk called before it moved, and both are RE-EXPORTS of
			`layout_node`'s own functions. Calling them through the renderer here
			would be a require back wearing a different hat, so the walk calls
			`layout_node` directly — which is also the one place they are defined. ]]
		local body = stripComments(walks)
		expect(string.find(body, "renderer%.")).toBe(nil)
		expect(string.find(body, "layout_node.compactForm", 1, true) ~= nil).toBe(true)
		expect(string.find(body, "layout_node.drawnButtonText", 1, true) ~= nil).toBe(true)
	end)
end)

describe("the commit-walk seam: the renderer's source-scanning pins still see the walks", function()
	it("`tests/lib/renderer_source` carries the new part", function()
		--[[ THE COST THIS FILE'S SPLIT ALWAYS PAYS, and the reason the instrument
			says so in its own header. A family of pins anchors on the exact line that
			carries a ruling — "the renderer really carries the wrap verdict across" —
			and those lines move with the code. `button_shape.spec` went red on
			exactly that pin the first time these walks left, which is the instrument
			working: it named the file it could no longer see. ]]
		local parts = require("./lib/renderer_source").PARTS
		local seen = false
		for _, path in parts do
			if path == WALKS_PATH then
				seen = true
			end
		end
		expect(seen).toBe(true)
		local all = require("./lib/renderer_source").all()
		expect(string.find(all, 'adapter.setProp(handle, "textWrapped", wraps, "layout")', 1, true) ~= nil).toBe(true)
	end)

	it("...and every module its own header NAMES is a part", function()
		--[[ THE HAND LIST BESIDE THE PARAGRAPH THAT DESCRIBES IT (review MEDIUM-4).
			The commit-walk split rewrote that header to name five modules the renderer
			has shed and added one of them to `PARTS`; `rect_pass.luau` had never been
			in it, and nothing could say so. The prose is the claim, the list is the
			instrument, and a claim an instrument does not implement is how a pin
			quietly stops seeing the code it names — which is the one failure this file
			exists to prevent. ]]
		local fs2 = require("@lune/fs")
		local source = fs2.readFile("tests/lib/renderer_source.luau")
		local parts: { [string]: boolean } = {}
		for _, path in require("./lib/renderer_source").PARTS do
			parts[path] = true
		end
		local named: { string } = {}
		for path in string.gmatch(source, "`(render/[%a_][%w_]*%.luau)`") do
			local full = `src/{path}`
			if not parts[full] then
				table.insert(named, full)
			end
		end
		table.sort(named)
		expect(table.concat(named, " ")).toBe("")
		-- ...and the scan found names at all, rather than passing on a header that
		-- stopped naming anything
		local count = 0
		for _ in string.gmatch(source, "`(render/[%a_][%w_]*%.luau)`") do
			count += 1
		end
		expect(count >= 5).toBe(true)
	end)
end)
