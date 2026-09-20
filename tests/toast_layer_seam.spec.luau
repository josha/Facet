--!strict
--[[ THE TOAST SEAM, MECHANISED — what keeps `src/present/toast_layer.luau`
	one-way.

	WHY A SPEC AND NOT A COMMENT. `tools/lune/verify/data/source-cap-ledger.md`
	records the rule every extraction in this repository is judged by: a block may
	leave a file only if it writes no mutable upvalue of its host, because
	otherwise the move creates a require BACK and the two files become one file
	with a slash in the middle. This row ALSO recorded, wrongly, that the toast
	region "costs MORE: six reassigned scalars ... a record with six fields rather
	than one". All six are the region's OWN, and the only thing that made them
	look shared was four inline lines in `tickBody`. Those lines are now
	`toasts.tick(step)`. THE WHOLE CLAIM OF THIS SPLIT IS THEREFORE A NEGATIVE:
	nothing about the toast survives on the presenter's side of the seam — and a
	negative claim is exactly the kind that rots silently, because re-introducing
	one of those six in `presenter.luau` would compile, pass every behavioural
	test, and quietly re-create the fork.

	SO THE SEAM IS FOUR SET COMPARISONS, run against the live sources:

	  READ      every `ctx.<key>` the module reads (its own destructuring block —
	            `toast_layer.new` destructures `ctx` into locals once rather than
	            reading it inline, so the destructuring IS the read surface)
	  DECLARED  every key the exported `Ctx` type names
	  PASSED    every key the ONE construction site in presenter.luau hands over
	  GONE      every one of the six scalars, absent from the host's CODE

	plus the empty shared WRITE surface, the three exports, the one-way require
	and the tick delegation. Each rule is a pure function of its inputs, so each
	carries a NEGATIVE CONTROL that feeds it a broken pair and proves it reports —
	a check that cannot fail is decoration.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local fs = require("@lune/fs")

local HOST_PATH = "src/present/presenter.luau"
local MODULE_PATH = "src/present/toast_layer.luau"

-- the six scalars the ledger row called shared. Every one of them is declared
-- inside the extracted region; a name of any of them in the host's CODE is the
-- finding this spec exists for.
local SCALARS = {
	"toastTime",
	"toastPosition",
	"toastTransition",
	"toastLayer",
	"toastSchedule",
	"syncToastLayer",
}

-- CODE ONLY. Every scan below asks "does this name appear here", and the host's
-- own seam comment names all six on purpose — it is the explanation of where
-- they went. `tests/recycle_prop_signature.spec` learned this on the same shape.
local function stripComments(source: string): string
	local out = string.gsub("\n" .. source, "%-%-%[%[.-%]%]", " ")
	out = string.gsub(out, "\n[ \t]*%-%-[^\n]*", "\n")
	return out
end

local function readsOf(source: string): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for key in string.gmatch(source, "ctx%.([%a_][%w_]*)") do
		out[key] = true
	end
	return out
end

-- every key the exported `Ctx` type declares. Comment lines are stripped first
-- (a plain-language `name: explanation` line would otherwise read as a field).
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

local function passedOf(host: string): { [string]: boolean }
	local block = string.match(host, "toastLayerLib%.new%({\n(.-)\n%s*}%)")
	assert(block ~= nil, `{HOST_PATH}: no 'toastLayerLib.new' construction site to read`)
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
-- field it sets on one, or a key it stores into one.
local function writesOf(moduleSource: string, keys: { [string]: boolean }): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for key in keys do
		local patterns = {
			`\n[ \t]*{key}%.[%a_][%w_]*%s*=[^=]`,
			`\n[ \t]*{key}%[[^%]]+%]%s*=[^=]`,
			`\n[ \t]*{key}%s*=[^=]`,
		}
		for _, pattern in patterns do
			local at = string.find(moduleSource, pattern)
			--[[ A TABLE-CONSTRUCTOR ENTRY IS A KEY, NOT AN ASSIGNMENT, and this
				seam is the first in this family to need the distinction: it hands
				`core` straight on to `transitionsLib.new({ core = core, ... })`,
				which the three patterns above read as "the module reassigns `core`".
				The source-cap ledger records this trap twice already ("a table
				constructor's `axis = axis` reads as a write ... that one alone
				inflated the count by half"); a Lua assignment STATEMENT never ends
				in a comma, so the line's last character settles it. ]]
			while at ~= nil do
				local lineEnd = string.find(moduleSource, "\n", at + 1, true) or #moduleSource
				local line = string.sub(moduleSource, at, lineEnd)
				if string.match(line, ",%s*$") == nil then
					out[key] = true
					break
				end
				at = string.find(moduleSource, pattern, lineEnd)
			end
			if out[key] then
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

describe("the toast_layer seam: READ == DECLARED == PASSED", function()
	local host = fs.readFile(HOST_PATH)
	local moduleSource = fs.readFile(MODULE_PATH)

	it("every `ctx.<key>` the module reads is declared in `Ctx`", function()
		local reads = readsOf(moduleSource)
		expect(#missingFrom(reads, declaredOf(moduleSource))).toBe(0)
		-- the set is not empty, which is the trap a set comparison invites: two
		-- empty sets are equal
		expect(#sorted(reads) > 5).toBe(true)
	end)

	it("every key `Ctx` declares is one the module actually reads", function()
		-- the direction that catches a dep left behind by a change: a
		-- declared-but-unread key is a fact nothing spends
		expect(#missingFrom(declaredOf(moduleSource), readsOf(moduleSource))).toBe(0)
	end)

	it("the one construction site passes exactly the declared set — no more, no less", function()
		local declared = declaredOf(moduleSource)
		local passed = passedOf(host)
		expect(#missingFrom(declared, passed)).toBe(0) -- a fact nobody hands over
		expect(#missingFrom(passed, declared)).toBe(0) -- a fact nothing reads
	end)

	it("there is exactly ONE construction site", function()
		local _, count = string.gsub(host, "toastLayerLib%.new", "")
		expect(count).toBe(1)
	end)

	it("NEGATIVE CONTROL: each set comparison reports the pair that is out of step", function()
		local declared = { alpha = true, beta = true }
		local reads = { alpha = true, gamma = true }
		expect(missingFrom(reads, declared)[1]).toBe("gamma")
		expect(missingFrom(declared, reads)[1]).toBe("beta")
		local fakeModule = "export type Ctx = {\n\t-- a comment, not a key\n\talpha: any,\n\tbeta: any,\n}"
		expect(#sorted(declaredOf(fakeModule))).toBe(2)
		local fakeHost = "toastLayerLib.new({\n\t\t-- a comment, not a key\n\t\talpha = alpha,\n\t\tbeta = beta,\n\t})"
		expect(sorted(passedOf(fakeHost))[2]).toBe("beta")
	end)
end)

describe("the toast_layer seam: the state really left, and the require is one-way", function()
	local host = fs.readFile(HOST_PATH)
	local moduleSource = fs.readFile(MODULE_PATH)

	it("all six scalars the ledger called SHARED are gone from the presenter's code", function()
		--[[ THE CLAIM THIS SPLIT IS MADE OF. `toastTime`, `toastPosition`,
			`toastTransition`, `toastLayer`, `toastSchedule` and `syncToastLayer`
			are declared inside the extracted region and referenced nowhere else,
			which is the score `catchers` and `text_reveal` came out on and a better
			one than `surface_lifecycle`'s (it paid a record for `displayLayer`).
			A NAME HERE IS THE FINDING: the presenter would have re-acquired a toast
			fact, and the two files would be answering the same question twice. The
			host's seam comment names all six deliberately — that is why this reads
			STRIPPED code rather than the raw file. ]]
		local code = stripComments(host)
		local survivors: { string } = {}
		for _, name in SCALARS do
			-- a WORD, not a substring: the require itself is `toastLayerLib`, and
			-- `toastLayer` is a prefix of it
			if string.find(code, `%f[%w_]{name}%f[^%w_]`) ~= nil then
				table.insert(survivors, name)
			end
		end
		expect(`toast state still in the presenter: {table.concat(survivors, ", ")}`).toBe(
			"toast state still in the presenter: "
		)
		-- ...and each of the six really is in the module, so this cannot pass by
		-- the feature having been deleted
		for _, name in SCALARS do
			expect(`{name} in {MODULE_PATH}: {string.find(moduleSource, name, 1, true) ~= nil}`).toBe(
				`{name} in {MODULE_PATH}: true`
			)
		end
	end)

	it("NEGATIVE CONTROL: the stripper removes comments and keeps code", function()
		local text = "\tlocal a = 1\n\t-- toastTime here\n\t--[[ and toastLayer\n\t\there ]]\n\tlocal toastTime = 2\n"
		local code = stripComments(text)
		expect(string.find(code, "local toastTime = 2", 1, true) ~= nil).toBe(true)
		expect(string.find(code, "toastTime here", 1, true)).toBe(nil)
		expect(string.find(code, "and toastLayer", 1, true)).toBe(nil)
	end)

	it("the presenter's tick body delegates one frame of toast time, and owns none of it", function()
		--[[ THE ONE CHANGE THE SPLIT MADE, and the reason the six scalars stopped
			being shared. `tickBody` used to carry four inline lines
			(`toastTime += ...`, `toastSchedule.update()`, `syncToastLayer()`); it
			now calls `toasts.tick(step)` beside the five siblings that already take
			their frame that way. A future round that re-inlines any part of it
			re-creates the fork, and the case above would catch it — this one says
			what SHOULD be there, so the pair reads as a rule rather than a ban. ]]
		local code = stripComments(host)
		expect(string.find(code, "toasts.tick(math.max(step :: number, 0))", 1, true) ~= nil).toBe(true)
		-- the clamp is the presenter's, exactly where it was inline, so the module
		-- is handed a step that is already >= 0
		expect(string.find(moduleSource, "local function tick(step: number)", 1, true) ~= nil).toBe(true)
		expect(string.find(moduleSource, "toastTime += step", 1, true) ~= nil).toBe(true)
	end)

	it("the module writes through NO ctx dep — the cost this extraction did not pay", function()
		--[[ `surface_lifecycle.luau` paid a record for one reassigned scalar and
			`virtual_list_hosted.luau` one for seven. This module reassigns not one
			of its ctx names: `core`/`env`/`adapter` are by-reference, `motionClock`
			is bound once, and `metricsNow`/`emitFeedback` are `local function`s.
			A NAME HERE means a fact the presenter owns has become state two files
			write. ]]
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

	it("the module offers exactly the entry points the presenter uses", function()
		local returnBlock = string.match(moduleSource, "\n\treturn {\n(.-)\n\t}\nend\n\nreturn toast_layer")
		assert(returnBlock ~= nil, `{MODULE_PATH}: no trailing 'return TABLE end' block to read`)
		local names: { string } = {}
		for name in string.gmatch("\n" .. (returnBlock :: string), "\n%s*([%a_][%w_]*) =") do
			table.insert(names, name)
		end
		table.sort(names)
		expect(names).toEqual({ "dispose", "presentToast", "tick", "toastCounts" })
		-- ...and both public verbs are rebound under their ORIGINAL names, so no
		-- consumer moved
		local code = stripComments(host)
		expect(string.find(code, "self.presentToast = toasts.presentToast", 1, true) ~= nil).toBe(true)
		expect(string.find(code, "self.toastCounts = toasts.toastCounts", 1, true) ~= nil).toBe(true)
		expect(string.find(code, "toasts.dispose", 1, true) ~= nil).toBe(true)
	end)

	it("the public `ToastOpts` has exactly ONE declaration, and its guard set travels with it", function()
		--[[ THE TYPE AND ITS KEY SET ARE ONE FACT. `specGuard.assertKnownKeys`
			refuses any key the type does not declare, so a second declaration one
			file over is a closed-opts guard that disagrees with the type it guards.
			The module declares both; `presenter.ToastOpts` is a re-export, which is
			the spelling every consumer already reads. ]]
		expect(string.find(moduleSource, "export type ToastOpts = {", 1, true) ~= nil).toBe(true)
		expect(string.find(host, "export type ToastOpts = toastLayerLib.ToastOpts", 1, true) ~= nil).toBe(true)
		expect(string.find(host, "export type ToastOpts = {", 1, true)).toBe(nil)
		expect(string.find(stripComments(host), "TOAST_OPTS_KEYS", 1, true)).toBe(nil)
		-- ...and every key the type declares is in the guard's set, in the file
		-- that now owns both
		local typeBlock = string.match(moduleSource, "export type ToastOpts = {\n(.-)\n}") :: string
		local keysBlock = string.match(moduleSource, "local TOAST_OPTS_KEYS = specGuard.keySet%({\n(.-)\n}%)") :: string
		local missing: { string } = {}
		--[[ PER LINE, AND ONLY THE CODE HALF OF IT. Every field here carries a
			TRAILING comment, and one of them is "-- default: slide in from its own
			edge" — a whole-block scan for `name:` reads `default` as an eighth
			field and reports a guard key nobody could ever add. Trailing comments
			are why `stripComments` (which takes line-START comments) is not the
			tool for this one. ]]
		for line in string.gmatch("\n" .. typeBlock, "\n([^\n]*)") do
			local code = string.match(line, "^(.-)%-%-") or line
			local field = string.match(code, "^%s*([%a_][%w_]*):")
			if field ~= nil and string.find(keysBlock, `"{field}"`, 1, true) == nil then
				table.insert(missing, field)
			end
		end
		-- ...and the scan really found all eight fields, so an empty `missing` is
		-- not an empty scan
		local counted = 0
		for line in string.gmatch("\n" .. typeBlock, "\n([^\n]*)") do
			local code = string.match(line, "^(.-)%-%-") or line
			if string.match(code, "^%s*([%a_][%w_]*):") ~= nil then
				counted += 1
			end
		end
		expect(counted).toBe(8)
		expect(`ToastOpts fields with no guard key: {table.concat(missing, ", ")}`).toBe(
			"ToastOpts fields with no guard key: "
		)
	end)

	it("the module requires the presenter NOWHERE — the require is one-way", function()
		for path in string.gmatch(moduleSource, 'require%("([^"]+)"%)') do
			expect(string.match(path, "presenter$") == nil).toBe(true)
		end
		-- ...and the direction that IS allowed is present, so this pair of
		-- assertions cannot both pass by the module having no requires at all
		expect(string.find(host, 'require("./toast_layer")', 1, true) ~= nil).toBe(true)
		-- exactly ONE consumer, matched on the path's TAIL: the
		-- `surface_lifecycle_seam` spec's own recorded finding is that pinning the
		-- literal sibling spelling leaves a planted `require("../present/...")` one
		-- directory over GREEN
		local consumers = 0
		for _, dir in { "src", "src/present", "src/controls", "src/render", "src/client" } do
			for _, entry in fs.readDir(dir) do
				local path = `{dir}/{entry}`
				if string.sub(entry, -5) == ".luau" and not fs.isDir(path) then
					local text = fs.readFile(path)
					for required in string.gmatch(text, 'require%("([^"]+)"%)') do
						if string.match(required, "/toast_layer$") ~= nil or required == "./toast_layer" then
							consumers += 1
						end
					end
				end
			end
		end
		expect(consumers).toBe(1)
	end)
end)
