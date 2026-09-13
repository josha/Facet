--!strict
--[[ THE setFocusVisual SEAM, MECHANISED — what keeps
	`src/client/screen_focus_visual.luau` one-way.

	WHY A SPEC AND NOT A COMMENT. `tools/lune/verify/data/source-cap-ledger.md`
	records the rule every extraction in this repository is judged by: a block may
	leave a file only if it writes no mutable upvalue of its host, because
	otherwise the move creates a require BACK and the two files become one file
	with a slash in the middle. `ctx` is the parameter object that makes this
	block one-way, and a parameter object rots silently: one `ctx.somethingNew`
	read that nobody declared, one key passed that nothing reads, one accessor
	quietly demoted to a value, and the property that made the split safe is gone
	while everything still passes.

	SO THE SEAM IS A SET COMPARISON, run against the live sources:

	  READ      every `ctx.<key>` the module reads (its own destructuring block —
	            `screen_focus_visual.new`, like every other screen_target sibling,
	            destructures `ctx` into locals once rather than reading it inline
	            throughout, so the destructuring IS the read surface)
	  DECLARED  every key the exported `Ctx` type names
	  PASSED    every key the ONE construction site in screen_target.luau hands
	            over

	all three equal, plus the shared WRITE surface pinned to a LIST rather than to
	emptiness (this seam, unlike `screen_props`, has one — see below), the two
	accessors asserted to be CALLED rather than captured, the one construction
	site, and the one-way require asserted directly. Each rule is a pure function
	of two strings, so each carries a NEGATIVE CONTROL that feeds it a broken pair
	and proves it reports — a check that cannot fail is decoration.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local fs = require("@lune/fs")

local HOST_PATH = "src/client/screen_target.luau"
local MODULE_PATH = "src/client/screen_focus_visual.luau"

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

-- every key the construction site passes. Comment lines inside the table are
-- skipped for the same reason they are in the type: the two accessors carry a
-- three-line explanation of why they are accessors.
local function passedOf(host: string): { [string]: boolean }
	local block = string.match(host, "screen_focus_visual%.new%({\n(.-)\n%s*}%)")
	assert(block ~= nil, `{HOST_PATH}: no 'screen_focus_visual.new' construction site to read`)
	local out: { [string]: boolean } = {}
	for line in string.gmatch("\n" .. (block :: string), "\n([^\n]*)") do
		if string.match(line, "^%s*%-%-") == nil then
			local key = string.match(line, "^%s*([%a_][%w_]*) =")
			if key ~= nil then
				out[key] = true
			end
		end
	end
	return out
end

-- the names this module WRITES THROUGH: a ctx-sourced local it reassigns, a
-- field it sets on one, or a key it stores into one. Each destructured local is
-- bound to a same-named local at the top of `new`, so a write shows up under
-- that name.
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

-- CODE ONLY. Both scans below ask "does this name appear here", and both would
-- otherwise be answered by this module's own header, which names every helper it
-- left behind and every accessor it takes. `tests/recycle_prop_signature.spec`
-- learned the same lesson on the same shape.
local function stripComments(source: string): string
	local out = string.gsub("\n" .. source, "%-%-%[%[.-%]%]", " ")
	out = string.gsub(out, "\n[ \t]*%-%-[^\n]*", "\n")
	return out
end

-- every line of a body that mentions `name` WITHOUT calling it — the one
-- failure a set comparison cannot see, because an accessor demoted to a value
-- keeps its key, its type and its construction site and only stops being live.
-- The `local name = ctx.name` destructuring is the one legitimate bare mention.
local function bareReadsOf(body: string, name: string): { string }
	local out: { string } = {}
	for line in string.gmatch("\n" .. body, "\n([^\n]*)") do
		local isDecl = string.find(line, `local {name} = ctx.{name}`, 1, true) ~= nil
		local isComment = string.match(line, "^%s*%-%-") ~= nil
		if not isDecl and not isComment then
			for nextChar in string.gmatch(line, `{name}(.?)`) do
				if nextChar ~= "(" then
					table.insert(out, line)
				end
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

describe("the screen_focus_visual seam: READ == DECLARED == PASSED", function()
	local host = fs.readFile(HOST_PATH)
	local moduleSource = fs.readFile(MODULE_PATH)

	it("every `ctx.<key>` the module reads is declared in `Ctx`", function()
		local reads = readsOf(moduleSource)
		expect(#missingFrom(reads, declaredOf(moduleSource))).toBe(0)
		-- the set is not empty, which is the trap a set comparison invites: two
		-- empty sets are equal
		expect(#sorted(reads) > 8).toBe(true)
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
		local _, count = string.gsub(host, "screen_focus_visual%.new", "")
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
		local fakeHost =
			"screen_focus_visual.new({\n\t\t-- a comment, not a key\n\t\talpha = alpha,\n\t\tbeta = beta,\n\t})"
		expect(sorted(passedOf(fakeHost))[2]).toBe("beta")
	end)
end)

describe("the screen_focus_visual seam: the shared WRITE surface, the accessors, the one-way require", function()
	local host = fs.readFile(HOST_PATH)
	local moduleSource = fs.readFile(MODULE_PATH)

	it("the shared write surface is exactly `focusedHandles`, and nothing else", function()
		--[[ UNLIKE `screen_props`, THIS SEAM HAS ONE — and pinning it to a LIST
			rather than to emptiness is what makes the case honest. `focusedHandles`
			is the live focus set: a table declared once in `screen_target.new`,
			never rebound, and this module is its one ADDER (`setFocusVisual` writes
			the profile on focus and clears it on blur). The host reads it in
			`refreshFocusVisuals`/`setProp` and clears it in `remove`/`destroyRoot`,
			so the table has to go back AS ITSELF — which is exactly why a write
			through it is allowed where a reassignment would not be.

			ANY OTHER NAME HERE IS THE FINDING: it means a fact `screen_target`
			owns has quietly become state two files write, which is the shape a
			later reader could not safely reason about from either file alone.
			`chromeState` is deliberately NOT on this list and must not join it —
			the glow census is noted through its `noteFocusGlow` METHOD, so the
			record stays the chrome subsystem's to keep. ]]
		local writes = sorted(writesOf(moduleSource, declaredOf(moduleSource)))
		expect(writes).toEqual({ "focusedHandles" })
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

	it("the two reassigned host locals arrive as ACCESSORS and are always CALLED", function()
		--[[ THE ONE FAILURE MODE A SET COMPARISON CANNOT SEE. `focusTreatment` is
			reassigned by `setActiveTheme` and the theme snapshot by
			`setThemePackage`; both were captured by value inside the host closure
			and read live. Handed over as values they would freeze at construction
			and a live theme swap would repaint everything except the focus ring —
			a defect this file's own history already paid for once (the ring stayed
			Facet-Neutral blue under every package). So: the construction site
			passes FUNCTIONS, and every use inside the module is a call. ]]
		local block = string.match(host, "screen_focus_visual%.new%({\n(.-)\n%s*}%)") :: string
		expect(string.find(block, "focusTreatment = function(): any", 1, true) ~= nil).toBe(true)
		expect(string.find(block, "snapshot = function(): any", 1, true) ~= nil).toBe(true)
		-- and inside the module BODY: no bare read survives. The destructuring
		-- line is the one legitimate uncalled mention of each, so it is excluded
		-- by name; the `Ctx` type block is outside the body and never scanned.
		local body =
			string.match(stripComments(moduleSource), "function screen_focus_visual%.new%(ctx: Ctx%)\n(.*)") :: string
		expect(#body > 5_000).toBe(true)
		for _, name in { "focusTreatment", "snapshot" } do
			expect(`{name} read without a call: {table.concat(bareReadsOf(body, name), " ~ ")}`).toBe(
				`{name} read without a call: `
			)
		end
	end)

	it("NEGATIVE CONTROL: the bare-read scan reports an accessor that was demoted to a value", function()
		local fake = "\tlocal snapshot = ctx.snapshot\n\tlocal a = snapshot()\n\tlocal b = snapshot.radii\n"
		expect(bareReadsOf(fake, "snapshot")[1]).toBe("\tlocal b = snapshot.radii")
		-- the declaration and the call are both clean, so the scan reports one
		expect(#bareReadsOf(fake, "snapshot")).toBe(1)
	end)

	it("the module offers exactly the one entry point it declares", function()
		--[[ NOT DRIVEN LIVE for its behaviour — `setFocusVisual` builds real
			`UIStroke`/`UIShadow`/`UIScale` instances and reads `AbsolutePosition`,
			so the behavioural proof is the Studio scenario, exactly as it was while
			this code was inline. The module itself IS require-able (it reaches no
			engine global at load), which is what lets the entry point be read off
			the source rather than guessed. ]]
		local returnBlock = string.match(moduleSource, "\n\treturn {\n(.-)\n\t}\nend\n\nreturn screen_focus_visual")
		assert(returnBlock ~= nil, `{MODULE_PATH}: no trailing 'return TABLE end' block to read`)
		local names: { string } = {}
		for name in string.gmatch("\n" .. (returnBlock :: string), "\n%s*([%a_][%w_]*) =") do
			table.insert(names, name)
		end
		table.sort(names)
		expect(names).toEqual({ "setFocusVisual" })
		-- ...and the host binds it straight onto the adapter, so the method the
		-- render layer calls is the same function it always was
		expect(string.find(host, "adapter.setFocusVisual = focusVisual.setFocusVisual", 1, true) ~= nil).toBe(true)
	end)

	it("the module requires the host NOWHERE — the require is one-way", function()
		for path in string.gmatch(moduleSource, 'require%("([^"]+)"%)') do
			-- any spelling that resolves to the host itself
			expect(string.match(path, "screen_target$") == nil).toBe(true)
		end
		-- ...and the direction that IS allowed is present, so this pair of
		-- assertions cannot both pass by the module having no requires at all
		expect(string.find(host, 'require("./screen_focus_visual")', 1, true) ~= nil).toBe(true)
		-- the two module-scope requires it DOES take are the two token modules the
		-- host already reads, never threaded through ctx: a copy of an address
		local _, tokenRequires = string.gsub(moduleSource, 'require%("%.%./tokens/[%w_]+"%)', "")
		expect(tokenRequires).toBe(2)
	end)

	it("`aimFocusScale` and `stopFocusScaleTweens` stayed behind AS A PAIR", function()
		--[[ THE ONE JUDGEMENT CALL THIS SEAM MADE, pinned so it cannot decay into
			an accident. `aimFocusScale` calls `stopFocusScaleTweens`, and
			`stopFocusScaleTweens` has three other callers in the host
			(`park`, `remove`, `destroyRoot`). Moving both would drag a teardown
			helper three unrelated paths depend on across the seam; moving only the
			first would split a two-line pair across two files. So the pair stays in
			the host and `aimFocusScale` arrives here as one ctx function — one name
			cheaper than either alternative. ]]
		expect(string.find(host, "local function aimFocusScale(", 1, true) ~= nil).toBe(true)
		expect(string.find(host, "local function stopFocusScaleTweens(", 1, true) ~= nil).toBe(true)
		local code = stripComments(moduleSource)
		expect(string.find(code, "function aimFocusScale(", 1, true)).toBe(nil)
		expect(string.find(code, "stopFocusScaleTweens", 1, true)).toBe(nil)
		-- ...and the stripper really removed the header that names both, so this
		-- pair cannot pass by reading an empty string
		expect(string.find(moduleSource, "stopFocusScaleTweens", 1, true) ~= nil).toBe(true)
		expect(#code > 5_000).toBe(true)
		-- ...and the module reaches the lift only through the ctx name
		expect(string.find(moduleSource, "local aimFocusScale = ctx.aimFocusScale", 1, true) ~= nil).toBe(true)
	end)
end)
