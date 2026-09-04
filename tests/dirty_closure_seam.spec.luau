--!strict
--[[ THE DIRTY-CLOSURE SEAM, MECHANISED — what keeps `render/dirty_closure.luau`
	one-way, and what the closure itself promises.

	It left `render/renderer.luau` on 2026-09-04 (Plan C, T3 step 0b) for the
	Source-write headroom the coordinate-space work needed. Unlike every other
	extraction out of that file, this one takes NO by-reference tables at all: it is
	a pure function of the list it is handed, which is why it needs no Deps record,
	no seam contract and no lifetime argument. The cases below say that in the two
	ways a source scan can — no requires, no module-level mutable state — and then
	drive the function itself, because a pure function's real seam test is that its
	answer depends on nothing but its argument.

	Each source rule is a pure function of a string, so each carries a NEGATIVE
	CONTROL that feeds it a broken input and proves it reports. A check that cannot
	fail is decoration. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local fs = require("@lune/fs")

local dirty_closure = require("../src/render/dirty_closure")

local MODULE_PATH = "src/render/dirty_closure.luau"
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

describe("the dirty-closure seam: a pure function, and the source says so", function()
	it("the module requires NOTHING — the strongest one-way claim this file can make", function()
		local source = fs.readFile(MODULE_PATH)
		expect(sorted(requiresIn(source))).toEqual({})
		-- NEGATIVE CONTROL: the scan really does see a require
		expect(sorted(requiresIn('local x = require("./somewhere")'))).toEqual({ "./somewhere" })
	end)

	it("no module-level mutable state: everything the function needs is its argument", function()
		local source = stripComments(fs.readFile(MODULE_PATH))
		--[[ the whole file above `function dirty_closure.of` — one table declaration
			and nothing else. A `local seen = {}` up here would be state shared across
			every surface on the client, which is exactly the class of defect a module
			that looks pure invites. ]]
		local head = string.match(source, "^(.-)\nfunction dirty_closure%.of")
		assert(head ~= nil, "no `function dirty_closure.of` to split on")
		local decls: { string } = {}
		for line in string.gmatch(head :: string, "\n([^\n]*)") do
			local trimmed = string.match(line, "^%s*(.-)%s*$") :: string
			if string.match(trimmed, "^local ") ~= nil then
				table.insert(decls, trimmed)
			end
		end
		expect(decls).toEqual({ "local dirty_closure = {}" })
	end)

	it("the renderer calls it and holds no copy of what left", function()
		local renderer = stripComments(fs.readFile(RENDERER_PATH))
		expect(string.find(renderer, 'local dirty_closure = require("./dirty_closure")', 1, true) ~= nil).toBe(true)
		expect(string.find(renderer, "dirtyContains, measureContains = dirty_closure.of(dirty)", 1, true) ~= nil).toBe(
			true
		)
		--[[ ...AND THE BLOCK IT REPLACED IS GONE rather than duplicated. The renderer
			still has ONE prefix walk of its own — the hidden-roots climb, which asks a
			different question of a different map — so this counts rather than forbids:
			two would mean the closure was copied out and left behind. ]]
		local walks = 0
		for _ in string.gmatch(renderer, "%^%(%.%*%)/%[%^/%]%*%$") do
			walks += 1
		end
		expect(`prefix walks left in the renderer={walks}`).toBe("prefix walks left in the renderer=1")
		expect(string.find(renderer, "local contains: { [string]: boolean } = {}", 1, true)).toBe(nil)
	end)
end)

describe("the dirty closure itself: every dirty node plus every ancestor of one", function()
	local function keys(set: { [string]: boolean }): { string }
		return sorted(set)
	end

	it("an arrange entry fills the arrange set and its prefixes, and the measure set stays empty", function()
		local contains, measures = dirty_closure.of({ { path = "/S/A/B/C", class = "arrange" } })
		expect(keys(contains)).toEqual({ "/S", "/S/A", "/S/A/B", "/S/A/B/C" })
		expect(keys(measures)).toEqual({})
	end)

	it("a measure entry fills BOTH — the measure half is a subset, never a separate tree", function()
		local contains, measures = dirty_closure.of({ { path = "/S/A/B", class = "measure" } })
		expect(keys(contains)).toEqual({ "/S", "/S/A", "/S/A/B" })
		expect(keys(measures)).toEqual({ "/S", "/S/A", "/S/A/B" })
	end)

	it("an arrange entry that filled a chain does not CUT a measure entry's", function()
		--[[ THE TERMINATION RULE, and the reason the walk stops per SET rather than on
			`contains`. Run the arrange entry first so `/S/A` is already in `contains`;
			a walk that stopped on `contains` would leave `/S/A` and `/S` out of
			`measures` and a measure slate two levels up would survive a change that
			invalidated it. ]]
		local contains, measures =
			dirty_closure.of({ { path = "/S/A/X", class = "arrange" }, { path = "/S/A/Y", class = "measure" } })
		expect(keys(contains)).toEqual({ "/S", "/S/A", "/S/A/X", "/S/A/Y" })
		expect(keys(measures)).toEqual({ "/S", "/S/A", "/S/A/Y" })
	end)

	it("every other dirt class is ignored, and a pathless entry cannot crash it", function()
		local contains, measures = dirty_closure.of({
			{ path = "/S/A", class = "paint" },
			{ path = "/S/B", class = "structure" },
			{ class = "arrange" },
			{ path = "/S/C", class = "arrange" },
		})
		expect(keys(contains)).toEqual({ "/S", "/S/C" })
		expect(keys(measures)).toEqual({})
	end)

	it("it depends on NOTHING but its argument: the same list twice gives equal sets", function()
		local list = { { path = "/S/A/B", class = "measure" }, { path = "/S/A/C", class = "arrange" } }
		local c1, m1 = dirty_closure.of(list)
		local c2, m2 = dirty_closure.of(list)
		expect(keys(c1)).toEqual(keys(c2))
		expect(keys(m1)).toEqual(keys(m2))
		-- ...and they are FRESH tables each time, so a caller that clears one cannot
		-- reach into the next call's answer
		expect(c1 ~= c2).toBe(true)
		expect(m1 ~= m2).toBe(true)
	end)

	it("an empty list gives two empty sets rather than nil", function()
		local contains, measures = dirty_closure.of({})
		expect(keys(contains)).toEqual({})
		expect(keys(measures)).toEqual({})
	end)
end)
