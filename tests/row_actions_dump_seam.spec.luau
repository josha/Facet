--!strict
--[[ THE dump() SEAM, MECHANISED — what keeps `src/controls/row_actions_dump.luau`
	one-way, following `screen_props_seam.spec.luau`'s technique (the freshest
	template this campaign has for the shape).

	`tools/lune/verify/data/source-cap-ledger.md`'s row_actions.luau row named this extraction
	across two prior recordings, on the theory that `dump()` reads state and writes
	nothing so a `row_actions_dump.luau` taking the tray/edge/commit records as an
	argument list cannot require back. Measured at the extraction commit (task
	EXTRACT2), that row's own "~42 KB, ~a dozen upvalues" description of `dump()`
	did not hold — the real function was 928 characters closing over six names —
	but the UNDERLYING CLAIM (one-way, no behavioural change, an argument list) was
	correct, and this spec is what makes it a mechanised property rather than a
	corrected guess.

	THE SHAPE IS SIMPLER than `screen_props`'s: `row_actions_dump.build(p)` is a
	pure, one-shot snapshot function, not a `new(ctx)` object living for the
	control's whole lifetime — so there is no destructure-once-at-the-top block to
	read, `p.<key>` is read directly, and every field is a VALUE (never a signal,
	never a mutable reference), so the write-surface check is not "empty because
	nothing happened to be reassigned" but "empty because a plain value has nothing
	to write through in the first place." Both are asserted anyway, mechanically,
	because "obviously true" is exactly the class of claim this document exists to
	stop taking on faith.

	READ == DECLARED == PASSED, plus the (empty) write surface, the one
	construction site, and the one-way require — each with a negative control
	proving the scan itself can report a mismatch. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local fs = require("@lune/fs")

local HOST_PATH = "src/controls/row_actions.luau"
local MODULE_PATH = "src/controls/row_actions_dump.luau"

-- every `p.<key>` the module actually reads
local function readsOf(source: string): { [string]: boolean }
	local out: { [string]: boolean } = {}
	-- `%f[%a_]` is a frontier: the character immediately before "p" must NOT be
	-- a letter/underscore, or a bare substring match ("row_actions_dum`P`.luau",
	-- "row_actions_dump.`b`uild") would misread as a read of `p`. Caught live:
	-- without it this scan over-reported by exactly two, both from the file's
	-- own header prose and the `function row_actions_dump.build` declaration.
	for key in string.gmatch(source, "%f[%a_]p%.([%a_][%w_]*)") do
		out[key] = true
	end
	return out
end

-- every key the exported `Params` type declares (comment lines stripped first,
-- same trap `screen_props_seam.spec` guards: a plain-language line would
-- otherwise read as a field)
local function declaredOf(source: string): { [string]: boolean }
	local block = string.match(source, "export type Params = {\n(.-)\n}")
	assert(block ~= nil, `{MODULE_PATH}: no 'export type Params' block to read`)
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
	local block = string.match(host, "rowActionsDump%.build%({\n(.-)\n%s*}%)")
	assert(block ~= nil, `{HOST_PATH}: no 'rowActionsDump.build' construction site to read`)
	local out: { [string]: boolean } = {}
	for key in string.gmatch("\n" .. (block :: string), "\n%s*([%a_][%w_]*) =") do
		out[key] = true
	end
	return out
end

-- the names `build` WRITES THROUGH: a field of `p.<key>` it sets, or a key it
-- stores into one. UNLIKE `screen_props` (which destructures `ctx` into
-- same-named locals, so a bare `key = ...` is the reassignment shape to
-- catch), this module never destructures `p` — every read is `p.<key>`
-- inline — so a bare `key = value` is a TABLE-CONSTRUCTOR FIELD in the
-- returned dump record (`id = p.id,`), not a write through the param, and
-- would be a false positive here. Anchoring every pattern on the literal
-- `p.<key>` prefix is what makes "reassigned" mean the same thing this
-- module's actual shape does.
local function writesOf(moduleSource: string, keys: { [string]: boolean }): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for key in keys do
		local patterns = {
			`p%.{key}%.[%a_][%w_]*%s*=[^=]`, -- a field on p.<key>
			`p%.{key}%[[^%]]+%]%s*=[^=]`, -- a key inside p.<key>
			`p%.{key}%s*=[^=]`, -- p.<key> itself, reassigned
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

describe("the row_actions dump seam: READ == DECLARED == PASSED", function()
	local host = fs.readFile(HOST_PATH)
	local moduleSource = fs.readFile(MODULE_PATH)

	it("every `p.<key>` the module reads is declared in `Params`", function()
		local reads = readsOf(moduleSource)
		expect(#missingFrom(reads, declaredOf(moduleSource))).toBe(0)
		-- the set is not empty, which is the trap a set comparison invites: two
		-- empty sets are equal
		expect(#sorted(reads) >= 6).toBe(true)
	end)

	it("every key `Params` declares is one the module actually reads", function()
		-- the other direction: a declared-but-unread key is a fact nothing spends
		expect(#missingFrom(declaredOf(moduleSource), readsOf(moduleSource))).toBe(0)
	end)

	it("the one construction site passes exactly the declared set — no more, no less", function()
		local declared = declaredOf(moduleSource)
		local passed = passedOf(host)
		expect(#missingFrom(declared, passed)).toBe(0) -- a fact nobody hands over
		expect(#missingFrom(passed, declared)).toBe(0) -- a fact nothing reads
	end)

	it("there is exactly ONE construction site", function()
		local _, count = string.gsub(host, "rowActionsDump%.build", "")
		expect(count).toBe(1)
	end)

	it("NEGATIVE CONTROL: each set comparison reports the pair that is out of step", function()
		local declared = { alpha = true, beta = true }
		local reads = { alpha = true, gamma = true }
		expect(missingFrom(reads, declared)[1]).toBe("gamma")
		expect(missingFrom(declared, reads)[1]).toBe("beta")
		-- ...and the scans themselves read what they claim to
		local fakeModule = "export type Params = {\n\t-- a comment, not a key\n\talpha: any,\n\tbeta: any,\n}"
		expect(#sorted(declaredOf(fakeModule))).toBe(2)
		local fakeHost = "rowActionsDump.build({\n\t\t\talpha = alpha,\n\t\t\tbeta = beta,\n\t\t})"
		expect(sorted(passedOf(fakeHost))[2]).toBe("beta")
	end)
end)

describe("the row_actions dump seam: the (empty) shared WRITE surface, and the one-way require", function()
	local host = fs.readFile(HOST_PATH)
	local moduleSource = fs.readFile(MODULE_PATH)

	it("build() writes through NO param at all — a value has nothing to write through", function()
		local writes = sorted(writesOf(moduleSource, declaredOf(moduleSource)))
		expect(#writes).toBe(0)
	end)

	it("NEGATIVE CONTROL: the write scan sees each of the three write shapes", function()
		local keys = { alpha = true, beta = true, gamma = true, delta = true }
		local text =
			"\n\tp.alpha.field = 1\n\tp.beta[key] = 2\n\tp.gamma = 3\n\tlocal x = p.delta.field\n\tif p.delta == nil then\n"
		local seen = writesOf(text, keys)
		expect(seen.alpha).toBe(true)
		expect(seen.beta).toBe(true)
		expect(seen.gamma).toBe(true)
		-- a READ of a field, and an equality test, are not writes
		expect(seen.delta).toBe(nil)
		-- ...and a bare TABLE-CONSTRUCTOR field (this module's own return
		-- shape: `alpha = p.alpha,`) is not mistaken for a reassignment of
		-- `p.alpha` — the false positive this scan exists to avoid
		expect(writesOf("\n\treturn {\n\t\talpha = p.alpha,\n\t}\n", { alpha = true }).alpha).toBe(nil)
	end)

	it("the module offers exactly the one entry point it declares", function()
		local returnBlock = string.match(moduleSource, "\nreturn row_actions_dump")
		assert(returnBlock ~= nil, `{MODULE_PATH}: no trailing 'return row_actions_dump' to read`)
		-- the table it returns is built once, above, and named once — confirm the
		-- ONLY function assigned onto it is `build`
		local names: { string } = {}
		for name in string.gmatch(moduleSource, "\nfunction row_actions_dump%.([%a_][%w_]*)") do
			table.insert(names, name)
		end
		table.sort(names)
		expect(names).toEqual({ "build" })
	end)

	it("the module requires the host NOWHERE — the require is one-way", function()
		-- the module makes no `require(...)` call at all: every field it needs
		-- arrives by value, in `Params`
		expect(string.find(moduleSource, "require%(") == nil).toBe(true)
		-- ...and the direction that IS allowed is present, so this cannot pass by
		-- the module simply requiring nothing on either side
		expect(string.find(host, 'require("./row_actions_dump")', 1, true) ~= nil).toBe(true)
	end)
end)
