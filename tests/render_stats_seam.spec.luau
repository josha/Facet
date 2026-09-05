--!strict
--[[ THE RENDERER-COUNTERS SEAM, MECHANISED — what keeps
	`render/render_stats.luau` one-way, and what its two exports promise.

	The counter record and the "publish a solve's work into it" block left
	`render/renderer.luau` on 2026-09-04 (Plan C, T5) for the Source-write headroom
	the translate lane needed. Like `render/dirty_closure`, and unlike every other
	extraction out of that file, this one takes NO by-reference tables of its own:
	`new()` returns a fresh table and keeps nothing, and `publish` writes only into
	the table it is handed. So the seam claim is the strongest kind — the source
	requires nothing and holds no module-level mutable state — and the cases below
	say that in the two ways a source scan can, then drive both exports, because a
	stateless module's real seam test is that its answer depends on nothing but its
	arguments.

	Each source rule is a pure function of a string, so each carries a NEGATIVE
	CONTROL that feeds it a broken input and proves it reports. A check that cannot
	fail is decoration. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local fs = require("@lune/fs")

local render_stats = require("../src/render/render_stats")

local MODULE_PATH = "src/render/render_stats.luau"
local RENDERER_PATH = "src/render/renderer.luau"

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

local function requiresIn(source: string): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for path in string.gmatch(stripComments(source), 'require%("([^"]*)"%)') do
		out[path] = true
	end
	return out
end

describe("the render-stats seam: no requires, no state, two exports", function()
	it("the module requires NOTHING — the strongest one-way claim this file can make", function()
		local source = fs.readFile(MODULE_PATH)
		expect(sorted(requiresIn(source))).toEqual({})
		-- NEGATIVE CONTROL: the scan really does see a require
		expect(sorted(requiresIn('local x = require("./somewhere")'))).toEqual({ "./somewhere" })
	end)

	it("no module-level mutable state: every counter belongs to ONE surface", function()
		--[[ a `local counts = {}` up here would be a record shared by every surface on
			the client — every number in `controller.stats()` silently summed across
			surfaces. That is precisely the defect a module of counters invites, and the
			reason `new()` returns a fresh table instead of exporting one. ]]
		local source = stripComments(fs.readFile(MODULE_PATH))
		local head = string.match(source, "^(.-)\nfunction render_stats%.new")
		assert(head ~= nil, "no `function render_stats.new` to split on")
		local decls: { string } = {}
		for line in string.gmatch(head :: string, "\n([^\n]*)") do
			local trimmed = string.match(line, "^%s*(.-)%s*$") :: string
			if string.match(trimmed, "^local ") ~= nil then
				table.insert(decls, trimmed)
			end
		end
		expect(decls).toEqual({ "local render_stats = {}" })
		-- NEGATIVE CONTROL: the scan really does see a second declaration (two here
		-- against the module's own one)
		local fake = "local render_stats = {}\nlocal shared = {}\nfunction render_stats.new()"
		local fakeHead = string.match(stripComments(fake), "^(.-)\nfunction render_stats%.new") :: string
		local found = 0
		for line in string.gmatch(fakeHead, "\n([^\n]*)") do
			if string.match(line, "^%s*local ") ~= nil then
				found += 1
			end
		end
		expect(`decls seen:{found}`).toBe("decls seen:2")
	end)

	it("the export set is exactly `new` and `publish`", function()
		local names: { string } = {}
		for name in render_stats :: any do
			table.insert(names, name)
		end
		table.sort(names)
		expect(names).toEqual({ "new", "publish" })
	end)

	it("`new` returns a FRESH record every call — two surfaces never share a counter", function()
		local a, b = render_stats.new(), render_stats.new()
		a.solves += 7
		expect(`a={a.solves} b={b.solves} same={a == b}`).toBe("a=7 b=0 same=false")
	end)

	it("...and it carries every field `controller.stats()` documents", function()
		local s = render_stats.new()
		-- a SAMPLE of the record's own contract, one field per family, so a field
		-- deleted in a later edit is caught here rather than by a nil arithmetic
		-- error inside a commit
		expect(
			`{s.creates},{s.rectWrites},{s.solves},{s.lastArranged},{s.lastCommitVisits},`
				.. `{s.lastLayoutNodes},{s.lastNodeBuilds},{s.partialSolves},{s.structuralPartialSolves}`
		).toBe("0,0,0,0,0,0,0,0,0")
		expect(`byWalk={typeof(s.lastCommitVisitsByWalk)} boundary={tostring(s.lastStructuralBoundary)}`).toBe(
			"byWalk=table boundary=nil"
		)
		-- ...and the QUESTION counter beside the visit one (C4). It is named here
		-- because it is the only counter in the record that a walk publishes without
		-- ever incrementing a visit, so nothing else would catch its deletion.
		expect(`scans={s.lastCommitScans} cells={s.lastCommitListCells}`).toBe("scans=0 cells=0")
	end)

	it("`publish` writes ONLY into the record it is handed, and repairs `work.skipped`", function()
		local s = render_stats.new()
		local other = render_stats.new()
		local work = { arranged = 4, measured = 9, rectInserts = 3, translated = 2 }
		render_stats.publish(s, { work = work }, 10, false)
		-- 10 layout nodes, 4 arranged, 2 translated -> 4 skipped, written BACK into
		-- `work` because `rect_pass.apply` is handed the same record
		expect(
			`skipped={work.skipped} arranged={s.lastArranged} measured={s.lastMeasured}`
				.. ` inserts={s.lastRectInserts} translated={s.lastTranslated}`
				.. ` solveSkipped={s.lastSolveSkipped} nodes={s.lastLayoutNodes}`
				.. ` partial={s.partialSolves} lastSkipped={s.lastSkipped}`
		).toBe(
			"skipped=4 arranged=4 measured=9 inserts=3 translated=2 solveSkipped=4 nodes=10 partial=1 lastSkipped=4"
		)
		expect(`other touched={other.lastArranged},{other.partialSolves}`).toBe("other touched=0,0")
	end)

	it("...and `lastSkipped`/`partialSolves` are the ones that stay STALE BY DESIGN", function()
		local s = render_stats.new()
		render_stats.publish(s, { work = { arranged = 4, translated = 2 } }, 10, false)
		-- a second solve that skipped NOTHING: `lastSolveSkipped` follows it to 0,
		-- `lastSkipped` does not move, and `partialSolves` does not count
		render_stats.publish(s, { work = { arranged = 10, translated = 0 } }, 10, false)
		expect(`lastSkipped={s.lastSkipped} solveSkipped={s.lastSolveSkipped} partial={s.partialSolves}`).toBe(
			"lastSkipped=4 solveSkipped=0 partial=1"
		)
	end)

	it("a solve with no `work` record publishes nothing and counts nothing", function()
		local s = render_stats.new()
		render_stats.publish(s, {}, 10, false)
		expect(`arranged={tostring(s.lastArranged)} nodes={s.lastLayoutNodes} partial={s.partialSolves}`).toBe(
			"arranged=0 nodes=0 partial=0"
		)
		-- ...but the structural half is counted from the SOLVE'S SET-UP, so it lands
		-- whether or not the solve produced a work record
		render_stats.publish(s, {}, 10, true)
		expect(`structural={s.structuralPartialSolves}`).toBe("structural=1")
	end)

	it("the renderer holds the record and nothing else: one `new`, one `publish`", function()
		local source = stripComments(fs.readFile(RENDERER_PATH))
		local news, publishes = 0, 0
		for _ in string.gmatch(source, "render_stats%.new%(%)") do
			news += 1
		end
		for _ in string.gmatch(source, "render_stats%.publish%(") do
			publishes += 1
		end
		expect(`new={news} publish={publishes}`).toBe("new=1 publish=1")
		--[[ ...AND `lastResult = result` STAYED BEHIND. It is the renderer's own solve
			state rather than a counter, and moving it would have made this module hold
			something the renderer reads back — the difference between a one-way seam and
			a shared record. ]]
		local held = 0
		for _ in string.gmatch(source, "\n%s*lastResult = result\n") do
			held += 1
		end
		expect(`lastResult held by the renderer:{held}`).toBe("lastResult held by the renderer:1")
	end)
end)
