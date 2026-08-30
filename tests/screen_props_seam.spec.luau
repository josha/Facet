--!strict
--[[ THE setProp SEAM, MECHANISED — what keeps `src/client/screen_props.luau`
	one-way.

	WHY A SPEC AND NOT A COMMENT. `docs/handoff/SOURCE_CAP_LEDGER.md` records the
	rule every extraction in this repository is judged by: a block may leave a
	file only if it reads no mutable upvalue of its host, because otherwise the
	move creates a require BACK and the two files become one file with a slash in
	the middle. This row also recorded that `setProp` becomes one-way "the moment
	the paint/style context it reads is a parameter object rather than four
	upvalues" — `ctx` is that parameter object, and a parameter object rots
	silently: one `ctx.somethingNew` read that nobody declared, one key passed
	that nothing reads, one write back through a dep that was supposed to be a
	value, and the property that made the split safe is gone while everything
	still passes.

	SO THE SEAM IS A SET COMPARISON, run against the live sources:

	  READ      every `ctx.<key>` the module reads (its own destructuring block —
	            `screen_props.new`, like every other screen_target sibling,
	            destructures `ctx` into locals once rather than reading it inline
	            throughout, so the destructuring IS the read surface)
	  DECLARED  every key the exported `Ctx` type names
	  PASSED    every key the ONE construction site in screen_target.luau hands
	            over

	all three equal, plus the shared WRITE surface (empty — see below), the one
	construction site, and the one-way require asserted directly. Each rule is a
	pure function of two strings, so each carries a NEGATIVE CONTROL that feeds it
	a broken pair and proves it reports — a check that cannot fail is decoration.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local fs = require("@lune/fs")

local HOST_PATH = "src/client/screen_target.luau"
local MODULE_PATH = "src/client/screen_props.luau"

-- every `ctx.<key>` the module actually reads
local function readsOf(source: string): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for key in string.gmatch(source, "ctx%.([%a_][%w_]*)") do
		out[key] = true
	end
	return out
end

-- every key the exported `Ctx` type declares. Comment lines are stripped first
-- (a plain-language `name: explanation` line would otherwise read as a field —
-- `tools/lune/check_prop_parity.luau`'s `recordFields` hit exactly this defect).
local function declaredOf(source: string): { [string]: boolean }
	local block = string.match(source, "export type Ctx = {\n(.-)\n}")
	assert(block ~= nil, `{MODULE_PATH}: no 'export type Ctx' block to read`)
	local out: { [string]: boolean } = {}
	for line in string.gmatch("\n" .. (block :: string), "\n([^\n]*)") do
		if string.match(line, "^%s*%-%-") == nil then
			local key = string.match(line, "^%s*([%a_][%w_]*):")
			if key ~= nil then
				out[key] = true
			end
		end
	end
	return out
end

-- every key the construction site passes
local function passedOf(host: string): { [string]: boolean }
	local block = string.match(host, "screen_props%.new%({\n(.-)\n%s*}%)")
	assert(block ~= nil, `{HOST_PATH}: no 'screen_props.new' construction site to read`)
	local out: { [string]: boolean } = {}
	for key in string.gmatch("\n" .. (block :: string), "\n%s*([%a_][%w_]*) =") do
		out[key] = true
	end
	return out
end

-- the names `setProp` WRITES THROUGH: a ctx-sourced local it reassigns, a field
-- it sets on one, or a key it stores into one. Each destructured local is bound
-- to a same-named local at the top of `new`, so a write shows up under that name.
local function writesOf(moduleSource: string, keys: { [string]: boolean }): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for key in keys do
		local patterns = {
			`\n[ \t]*{key}%.[%a_][%w_]*%s*=[^=]`, -- a field on it
			`\n[ \t]*{key}%[[^%]]+%]%s*=[^=]`, -- a key inside it
			`\n[ \t]*{key}%s*=[^=]`, -- the binding itself, reassigned
		}
		for _, pattern in patterns do
			if string.find(moduleSource, pattern) ~= nil then
				out[key] = true
				break
			end
		end
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

describe("the screen_props seam: READ == DECLARED == PASSED", function()
	local host = fs.readFile(HOST_PATH)
	local moduleSource = fs.readFile(MODULE_PATH)

	it("every `ctx.<key>` the module reads is declared in `Ctx`", function()
		local reads = readsOf(moduleSource)
		expect(#missingFrom(reads, declaredOf(moduleSource))).toBe(0)
		-- the set is not empty, which is the trap a set comparison invites: two
		-- empty sets are equal
		expect(#sorted(reads) > 20).toBe(true)
	end)

	it("every key `Ctx` declares is one the module actually reads", function()
		-- the other direction, and it is the one that catches a dep left behind
		-- by a change: a declared-but-unread key is a fact nothing spends
		expect(#missingFrom(declaredOf(moduleSource), readsOf(moduleSource))).toBe(0)
	end)

	it("the one construction site passes exactly the declared set — no more, no less", function()
		local declared = declaredOf(moduleSource)
		local passed = passedOf(host)
		expect(#missingFrom(declared, passed)).toBe(0) -- a fact nobody hands over
		expect(#missingFrom(passed, declared)).toBe(0) -- a fact nothing reads
	end)

	it("there is exactly ONE construction site", function()
		local _, count = string.gsub(host, "screen_props%.new", "")
		expect(count).toBe(1)
	end)

	it("NEGATIVE CONTROL: each set comparison reports the pair that is out of step", function()
		local declared = { alpha = true, beta = true }
		local reads = { alpha = true, gamma = true }
		expect(missingFrom(reads, declared)[1]).toBe("gamma")
		expect(missingFrom(declared, reads)[1]).toBe("beta")
		-- ...and the scans themselves read what they claim to
		local fakeModule = "export type Ctx = {\n\t-- a comment, not a key\n\talpha: any,\n\tbeta: any,\n}"
		expect(#sorted(declaredOf(fakeModule))).toBe(2)
		local fakeHost = "screen_props.new({\n\t\talpha = alpha,\n\t\tbeta = beta,\n\t})"
		expect(sorted(passedOf(fakeHost))[2]).toBe("beta")
	end)
end)

describe("the screen_props seam: the (empty) shared WRITE surface, and the one-way require", function()
	local host = fs.readFile(HOST_PATH)
	local moduleSource = fs.readFile(MODULE_PATH)

	it("setProp writes through NO ctx dep at all — the cost this extraction did not pay", function()
		--[[ EVERY OTHER SEAM IN THIS DOCUMENT PAID SOMETHING: `table_rows.luau` a
			record for two reassigned scalars, `virtual_list_hosted.luau` a record
			for seven. `setProp` reassigns not one of its 28 ctx names — every large
			block it dispatches to is a value fact (style/mode/palette), a function
			bound once from a sibling subsystem, or a host helper — so unlike its
			siblings this seam needed neither a record nor an accessor. A NAME HERE
			IS THE FINDING: it means a fact `screen_target` owns has quietly become
			state two files write, which is exactly the shape a later reader could
			not safely reason about from either file alone. ]]
		local writes = sorted(writesOf(moduleSource, declaredOf(moduleSource)))
		expect(#writes).toBe(0)
	end)

	it("NEGATIVE CONTROL: the write scan sees each of the three write shapes", function()
		local keys = { alpha = true, beta = true, gamma = true, delta = true }
		local text =
			"\n\talpha.field = 1\n\tbeta[key] = 2\n\tgamma = 3\n\tlocal x = delta.field\n\tif delta == nil then\n"
		local seen = writesOf(text, keys)
		expect(seen.alpha).toBe(true)
		expect(seen.beta).toBe(true)
		expect(seen.gamma).toBe(true)
		-- a READ of a field, and an equality test, are not writes
		expect(seen.delta).toBe(nil)
	end)

	it("the module offers exactly the one entry point it declares", function()
		--[[ NOT DRIVEN LIVE. `screen_props.new` requires `screen_vocabulary`,
			which reaches `Enum` at module load exactly as `screen_paint`/
			`screen_chrome` do — none of the three is `require`-able under bare
			Lune, and this repository's convention for that (see
			`tests/lib/adapter_source.luau`'s own header) is a source anchor,
			not a driven call. ]]
		local returnBlock = string.match(moduleSource, "\n\treturn {\n(.-)\n\t}\nend\n\nreturn screen_props")
		assert(returnBlock ~= nil, `{MODULE_PATH}: no trailing 'return TABLE end' block to read`)
		local names: { string } = {}
		for name in string.gmatch("\n" .. (returnBlock :: string), "\n%s*([%a_][%w_]*) =") do
			table.insert(names, name)
		end
		table.sort(names)
		expect(names).toEqual({ "setProp" })
	end)

	it("the module requires the host NOWHERE — the require is one-way", function()
		for path in string.gmatch(moduleSource, 'require%("([^"]+)"%)') do
			-- any spelling that resolves to the host itself
			expect(string.match(path, "screen_target$") == nil).toBe(true)
		end
		-- ...and the direction that IS allowed is present, so this pair of
		-- assertions cannot both pass by the module having no requires at all
		expect(string.find(host, 'require("./screen_props")', 1, true) ~= nil).toBe(true)
		-- the module's own prose names the host it left (the header explains the
		-- seam), which is why this check is the REQUIRE line, not a bare
		-- substring search for "screen_target" — screen_target exports no type
		-- this module could reach for in the first place, so there is no second
		-- (structural-type) route back to guard against, unlike table_rows.luau's
		-- `Column`
		local requireCount = select(2, string.gsub(moduleSource, 'require%("%./screen_vocabulary"%)', ""))
		expect(requireCount).toBe(1)
	end)
end)
