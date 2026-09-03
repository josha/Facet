--!strict
--[[ THE RECYCLE-KEY SEAM, MECHANISED — what keeps `render/recycle_key.luau`
	one-way.

	THE STRONGEST FORM ANY SEAM IN THIS FILE HAS REACHED: `recycle_key.new()`
	takes NO Deps record at all — every collaborator is a leaf require
	(`prop_channels`, `chrome_slots`) and every per-path record it owns
	(`partsOf`, `wornOf`) is a fresh table built inside `.new()`. So the
	mutable-upvalue test that every other seam spec in this repository runs
	against a Deps record's field list is, here, simpler and total: this
	module reads NOTHING from its host at all.

	  ONE-WAY       requires only `./prop_channels` and `../tokens/chrome_slots`,
	                both leaves the renderer already requires
	  NO STATE      no module-level mutable table; everything lives inside `new()`
	  EXPORTED==USED the six accessors `.new()` returns are exactly the six the
	                renderer calls (`recycleKeyState.<name>`)
	  ONE CONSUMER  `src/render/renderer.luau`, walked over the whole `src/` tree
	  NOTHING LEFT  the six old names (`propSignature`, `wornSignature`,
	                `recycleKey`, `recycleKeyPartsOf`, `wornStyleProps`, and the
	                bare `drainRecyclePool`-adjacent comment) are gone from
	                `renderer.luau`

	NO BEHAVIOUR CHANGE: `tests/recycle_prop_signature.spec.luau` and the whole
	`instance_recycling*` family drive the behaviour this seam moved, unmoved by
	the split.

	Each source rule is a pure function of a string, so each carries a NEGATIVE
	CONTROL that feeds it a broken input and proves it reports. A check that
	cannot fail is decoration. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local fs = require("@lune/fs")
local src_tree = require("./lib/src_tree")

local RENDERER_PATH = "src/render/renderer.luau"
local SEAM_PATH = "src/render/recycle_key.luau"

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
	for key in string.gmatch(stripComments(rendererSource), "recycleKeyState%.([%a_][%w_]*)") do
		out[key] = true
	end
	return out
end

describe("the recycle-key seam: one-way, no state, EXPORTED == USED, one consumer", function()
	local rendererSource = fs.readFile(RENDERER_PATH)
	local seamSource = fs.readFile(SEAM_PATH)

	it("requires only two leaves the renderer already requires, and never the renderer", function()
		local requires: { string } = {}
		for path in string.gmatch(stripComments(seamSource), 'require%("([^"]+)"%)') do
			table.insert(requires, path)
		end
		table.sort(requires)
		expect(requires).toEqual({ "../tokens/chrome_slots", "./prop_channels" })
		expect(string.find(seamSource, 'require%("%.%./render')).toBe(nil)
		-- ...and the direction that IS allowed is present, so this cannot pass by
		-- the renderer having quietly dropped the require
		expect(string.find(rendererSource, 'require("./recycle_key")', 1, true) ~= nil).toBe(true)
	end)

	it("holds no module-level mutable state: everything per-attach lives inside `new`", function()
		local head = string.sub(seamSource, 1, string.find(seamSource, "function recycle_key.new", 1, true) :: number)
		local body = stripComments(head)
		expect(string.find(body, "= {}", 1, true) ~= nil).toBe(true) -- the module table itself
		local offenders: { string } = {}
		for line in string.gmatch(body, "\n([^\n]*)") do
			local trimmed = string.match(line, "^%s*(.-)%s*$") :: string
			if
				string.match(trimmed, "^local [%a_][%w_]*.*=%s*{") ~= nil
				and string.match(trimmed, "^local recycle_key") == nil
			then
				table.insert(offenders, trimmed)
			end
		end
		expect(table.concat(offenders, " ")).toBe("")
	end)

	it("every accessor `.new()` exports is used by the renderer, and every use is exported", function()
		local exported = exportsOf(seamSource)
		local used = usedOf(rendererSource)
		expect(#missingFrom(exported, used)).toBe(0) -- an accessor nobody calls
		expect(#missingFrom(used, exported)).toBe(0) -- a call that would be nil
		expect(sorted(exported)).toEqual({ "declareParts", "forget", "key", "noteWorn", "parkKey", "signature" })
	end)

	it("there is exactly ONE consumer in src/", function()
		expect(src_tree.pathsContaining('require("./recycle_key")')).toEqual({ RENDERER_PATH })
	end)

	it("NOTHING STAYED BEHIND: the renderer kept no second copy of the moved functions", function()
		local body = stripComments(rendererSource)
		for _, name in
			{
				"local function propSignature",
				"local function wornSignature",
				"local function recycleKey(",
				"local recycleKeyPartsOf",
				"local wornStyleProps",
			}
		do
			expect(`{name} absent: {tostring(string.find(body, name, 1, true) == nil)}`).toBe(`{name} absent: true`)
		end
		-- ...and the renderer really does reach the seam for each, so the file was
		-- not simply emptied
		for _, call in
			{
				"recycleKeyState.key(",
				"recycleKeyState.signature(",
				"recycleKeyState.declareParts(",
				"recycleKeyState.parkKey(",
				"recycleKeyState.forget(",
				"recycleKeyState.noteWorn(",
			}
		do
			expect(`{call} present: {tostring(string.find(body, call, 1, true) ~= nil)}`).toBe(`{call} present: true`)
		end
	end)

	it("NEGATIVE CONTROL: the require, export, used and leftover scans all report", function()
		local fakeRequires: { string } = {}
		for path in string.gmatch(stripComments('local r = require("../render/renderer")\n'), 'require%("([^"]+)"%)') do
			table.insert(fakeRequires, path)
		end
		expect(fakeRequires).toEqual({ "../render/renderer" })
		local fake = "\treturn {\n\t\tkey = key,\n\t\textra = extra,\n\t}\nend"
		expect(sorted(exportsOf("\n" .. fake))).toEqual({ "extra", "key" })
		expect(sorted(usedOf("local x = recycleKeyState.key(a)\n"))).toEqual({ "key" })
		expect(
			string.find(stripComments("\tlocal recycleKeyPartsOf = {}\n"), "local recycleKeyPartsOf", 1, true) ~= nil
		).toBe(true)
	end)
end)

describe("the recycle-key seam: mutable-scope test — two `.new()` instances never see each other", function()
	it("each `.new()` call is a fresh, independent worn/parts pair", function()
		local recycle_key = require("../src/render/recycle_key")
		local a, b = recycle_key.new(), recycle_key.new()
		a.declareParts("/S/A", "Text", nil, "plain")
		a.noteWorn("/S/A", "text", "hi")
		expect(a.parkKey("/S/A") ~= nil).toBe(true)
		expect(b.parkKey("/S/A")).toBe(nil) -- b never saw a's declare at all
	end)

	--[[ T8 R3 (re-review, new Minor 1): this case was written as STYLE-only and
		its input carried no BINDING prop at all, so it passed unchanged against the
		very narrowing Critical 1 was about — a check that could not fail for the
		thing it was cited as pinning. One input, all three channels: `enabled` is
		BINDING, `shadow`/`textAlign` are STYLE, `padding` is LAYOUT and stays out
		(the key excludes it because every layout write is value-diffed against a
		cache carried across an adoption — `recycle_key.luau`'s header). ]]
	it("`signature` reads BINDING ∪ STYLE membership off `node.props`, sorted and joined", function()
		local recycle_key = require("../src/render/recycle_key")
		local rk = recycle_key.new()
		expect(rk.signature({ props = { shadow = {}, gap = 6, textAlign = "center", enabled = false, padding = 8 } })).toBe(
			"enabled,shadow,textAlign"
		)
		-- BINDING alone is enough to be signed: the STYLE-only signature scored
		-- this exact node "" and let it adopt anything
		expect(rk.signature({ props = { enabled = false } })).toBe("enabled")
		-- ...and LAYOUT alone is still nothing
		expect(rk.signature({ props = { gap = 6, padding = 8 } })).toBe("")
		expect(rk.signature({ props = nil })).toBe("")
	end)

	it("`noteWorn` adds on non-nil and removes on nil, and `parkKey` reflects it live", function()
		local recycle_key = require("../src/render/recycle_key")
		local rk = recycle_key.new()
		rk.declareParts("/S/B", "HStack", nil, "plain")
		expect(rk.parkKey("/S/B")).toBe(`HStack\0nil\0plain\0`)
		rk.noteWorn("/S/B", "shadow", { blurRadius = 1 })
		expect(rk.parkKey("/S/B")).toBe(`HStack\0nil\0plain\0shadow`)
		rk.noteWorn("/S/B", "shadow", nil)
		expect(rk.parkKey("/S/B")).toBe(`HStack\0nil\0plain\0`)
	end)

	it("`forget` clears both records — a reused path starts from nothing", function()
		local recycle_key = require("../src/render/recycle_key")
		local rk = recycle_key.new()
		rk.declareParts("/S/C", "Box", nil, "plain")
		rk.noteWorn("/S/C", "shadow", {})
		rk.forget("/S/C")
		expect(rk.parkKey("/S/C")).toBe(nil)
	end)
end)
