--!strict
--[[ THE HOSTED SEAM, MECHANISED — what keeps `controls/virtual_list_hosted.luau`
	one-way.

	WHY A SPEC AND NOT A COMMENT. `tools/lune/verify/data/source-cap-ledger.md` records the
	rule every extraction in this repository is judged by: a block may leave a file
	only if it reads no mutable upvalue of its host, because otherwise the move
	creates a require BACK and the two files become one file with a slash in the
	middle. `virtual_list.luau`'s row also recorded exactly WHY this particular
	block was not one-way — it read seven REASSIGNED host scalars, and a reassigned
	local cannot be shared by reference at all. Those seven (and two more found on
	the way out) are now ONE record, `deps.delivery`. A record is the fix and also
	the new hazard: the moment either file keeps its own copy of a cell, the copy
	goes stale silently and everything still passes.

	SO THE SEAM IS A SET COMPARISON, run against the live sources:

	  READ      every `deps.<key>` the hosted half reads
	  DECLARED  every key its `Deps` type names
	  PASSED    every key the ONE construction site in `virtual_list.luau` hands over

	all three equal, plus the shared WRITE surface pinned by name (one dep, one
	field inside it), the NO-STALE-TWIN rule (neither file may re-declare a cell of
	the record as a local of its own), and the one-way require asserted directly.
	Each rule is a pure function of its input strings, so each carries a NEGATIVE
	CONTROL that feeds it a broken pair and proves it reports — a check that cannot
	fail is decoration (and this repo's own gate-integrity sweep).
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local fs = require("@lune/fs")

local CONTROL_PATH = "src/controls/virtual_list.luau"
local HOSTED_PATH = "src/controls/virtual_list_hosted.luau"

-- every `deps.<key>` the hosted half actually reads
local function readsOf(hosted: string): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for key in string.gmatch(hosted, "deps%.([%a_][%w_]*)") do
		out[key] = true
	end
	return out
end

-- every key a named `export type` block declares. Comment lines inside the block
-- start with `--` and so never match the `<name>:` shape, which is what lets the
-- type carry its reasoning without confusing this scan.
local function declaredOf(source: string, typeName: string): { [string]: boolean }
	local block = string.match(source, "export type " .. typeName .. " = {\n(.-)\n}")
	assert(block ~= nil, `{HOSTED_PATH}: no 'export type {typeName}' block to read`)
	local out: { [string]: boolean } = {}
	for key in string.gmatch("\n" .. (block :: string), "\n\t([%a_][%w_]*):") do
		out[key] = true
	end
	return out
end

-- every key the construction site passes
local function passedOf(control: string): { [string]: boolean }
	local block = string.match(control, "virtual_list_hosted%.new%({\n(.-)\n\t}%)")
	assert(block ~= nil, `{CONTROL_PATH}: no 'virtual_list_hosted.new' construction site to read`)
	local out: { [string]: boolean } = {}
	for key in string.gmatch("\n" .. (block :: string), "\n\t\t([%a_][%w_]*) =") do
		out[key] = true
	end
	return out
end

--[[ the names a source WRITES THROUGH: a binding it reassigns, a field it sets on
	one, or a key it stores into one. `deps` are bound to same-named locals at the
	top of `new`, so the write shows up under the local's name.

	SCANNED LINE BY LINE, AND A LINE ENDING IN A COMMA IS NOT A WRITE. That clause
	is a finding, not a nicety: `id = \`{id}:{key}\`,` inside a table constructor
	is spelled exactly like the statement `id = ...`, and a whole-file pattern read
	it as the hosted half reassigning a dep it merely quotes. A statement
	assignment does not end in a comma; a constructor field does. ]]
local function writesOf(source: string, keys: { [string]: boolean }): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for line in string.gmatch(source, "[^\n]+") do
		local statement = string.match(line, "^[ \t]*(.-)[ \t]*$") :: string
		if string.sub(statement, -1) ~= "," then
			for key in keys do
				local patterns = {
					`^{key}%.[%a_][%w_]*%s*=[^=]`, -- a field on it
					`^{key}%[[^%]]+%]%s*=[^=]`, -- a key inside it
					`^{key}%s*=[^=]`, -- the binding itself
				}
				for _, pattern in patterns do
					if string.find(statement, pattern) ~= nil then
						out[key] = true
						break
					end
				end
			end
		end
	end
	return out
end

-- every FIELD of the shared record a source assigns, by name
local function recordFieldWrites(source: string, holder: string): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for key in string.gmatch(source, `\n[ \t]*{holder}%.([%a_][%w_]*)%s*=[^=]`) do
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

describe("the hosted seam: READ == DECLARED == PASSED", function()
	local control = fs.readFile(CONTROL_PATH)
	local hosted = fs.readFile(HOSTED_PATH)

	it("every fact the hosted half reads off `deps` is declared in `Deps`", function()
		local reads = readsOf(hosted)
		expect(#missingFrom(reads, declaredOf(hosted, "Deps"))).toBe(0)
		-- ...and the set is not empty, which is the trap a set comparison invites:
		-- two empty sets are equal
		expect(#sorted(reads) > 12).toBe(true)
	end)

	it("every key `Deps` declares is one the hosted half actually reads", function()
		-- the direction that catches a dep left behind by a change: a
		-- declared-but-unread key is a fact the list is still computing for nobody
		expect(#missingFrom(declaredOf(hosted, "Deps"), readsOf(hosted))).toBe(0)
	end)

	it("the one construction site passes exactly the declared set — no more, no less", function()
		local declared = declaredOf(hosted, "Deps")
		local passed = passedOf(control)
		expect(#missingFrom(declared, passed)).toBe(0) -- a fact nobody hands over
		expect(#missingFrom(passed, declared)).toBe(0) -- a fact nothing reads
	end)

	it("there is exactly ONE construction site", function()
		local _, count = string.gsub(control, "virtual_list_hosted%.new", "")
		expect(count).toBe(1)
	end)

	it("NEGATIVE CONTROL: each set comparison reports the pair that is out of step", function()
		local declared = { alpha = true, beta = true }
		local reads = { alpha = true, gamma = true }
		expect(missingFrom(reads, declared)[1]).toBe("gamma")
		expect(missingFrom(declared, reads)[1]).toBe("beta")
		local fake = "export type Deps = {\n\t-- a comment, not a key\n\talpha: any,\n\tbeta: any,\n}"
		expect(#sorted(declaredOf(fake, "Deps"))).toBe(2)
		expect(sorted(passedOf("virtual_list_hosted.new({\n\t\talpha = alpha,\n\t\tbeta = beta,\n\t})"))[2]).toBe(
			"beta"
		)
	end)
end)

describe("the hosted seam: the shared record, and no stale twin of any cell", function()
	local control = fs.readFile(CONTROL_PATH)
	local hosted = fs.readFile(HOSTED_PATH)

	it("the hosted half writes through exactly ONE dep, and it is the record", function()
		--[[ THE WHOLE POINT OF THE SPLIT, stated as a set. A dep the hosted half
			WRITES is state the two files share; a dep it only reads is a fact the
			list decided. One name is allowed, and it is `delivery` — the record that
			exists precisely because its cells are REASSIGNED scalars and a reassigned
			local cannot be shared by reference.

			A SECOND NAME HERE IS THE FINDING. It means a value the list decided has
			quietly become state with two owners, which is the shape that makes a
			later reader unable to tell which file is answerable for it. ]]
		local writes = sorted(writesOf(hosted, declaredOf(hosted, "Deps")))
		expect(#writes).toBe(1)
		expect(writes[1]).toBe("delivery")
	end)

	it("...and inside the record it writes exactly ONE field", function()
		--[[ The other eight cells travel HOST -> HOSTED only: the render controller,
			the mounted scroll path and the six contribution handoffs are all written
			by `virtual_list.luau`'s own seams. `suppressActivate` is the one cell
			both halves write — this file arms it at the axis lock, the host spends it
			in `handleActivate` and clears it on a cancel — and it is in the record for
			exactly that reason. ]]
		expect(sorted(recordFieldWrites(hosted, "delivery"))).toEqual({ "suppressActivate" })
	end)

	it("every cell of the record is read by the hosted half, and every one is written by the host", function()
		local cells = declaredOf(hosted, "Delivery")
		expect(#sorted(cells) > 0).toBe(true)
		local read: { [string]: boolean } = {}
		for key in string.gmatch(hosted, "delivery%.([%a_][%w_]*)") do
			read[key] = true
		end
		-- a cell nothing over here reads is a cell that did not need to leave the host
		expect(missingFrom(cells, read)).toEqual({})
		local written: { [string]: boolean } = {}
		for key in string.gmatch(control, "hostedDelivery%.([%a_][%w_]*)%s*=[^=]") do
			written[key] = true
		end
		-- ...and a cell the host never writes is not a REASSIGNED scalar at all, so
		-- it had no business being a record field instead of a plain value
		expect(missingFrom(cells, written)).toEqual({})
	end)

	it("NO STALE TWIN: neither file re-declares a cell of the record as a local", function()
		--[[ THE HAZARD A RECORD INTRODUCES. The nine cells were nine `local`s in one
			file; the split works only while there is exactly ONE of each. A
			`local boundController` reappearing on either side would read correctly for
			one frame and then silently stop tracking, with a green suite either way,
			which is the failure mode this whole file exists to make impossible. ]]
		local historic = {
			"boundController",
			"mountedScrollPath",
			"suppressActivatePath",
			"hostedMotionClock",
			"hostedNow",
			"hostedActionSystem",
			"hostedFocusGraph",
			"hostedPresentModal",
			"hostedDismiss",
		}
		for _, name in historic do
			expect(string.find(control, `local {name}`, 1, true)).toBe(nil)
			expect(string.find(hosted, `local {name}`, 1, true)).toBe(nil)
		end
	end)

	it("NEGATIVE CONTROL: the write scans see each shape they claim to", function()
		local keys = { alpha = true, beta = true, gamma = true, delta = true, epsilon = true }
		local text = "\n\talpha.field = 1\n\tbeta[key] = 2\n\tgamma = 3\n\tlocal x = delta.field\n"
			.. "\tif delta == nil then\n\tepsilon = someValue,\n"
		local seen = writesOf(text, keys)
		expect(seen.alpha).toBe(true)
		expect(seen.beta).toBe(true)
		expect(seen.gamma).toBe(true)
		-- a READ of a field, and an equality test, are not writes
		expect(seen.delta).toBe(nil)
		-- ...and neither is a table-constructor FIELD of the same spelling
		expect(seen.epsilon).toBe(nil)
		expect(sorted(recordFieldWrites("\n\tdelivery.one = 1\n\tif delivery.two == nil then\n", "delivery"))).toEqual({
			"one",
		})
	end)
end)

describe("the hosted seam: the surface, and the one-way require", function()
	local control = fs.readFile(CONTROL_PATH)
	local hosted = fs.readFile(HOSTED_PATH)

	it("the hosted half offers exactly twelve names, and they are the ones the host rebinds", function()
		--[[ The seam's SURFACE, pinned beside its dependency set. Read from the
			source rather than from a live call because three of the twelve
			(`engagedKey`, `engagedOffset`, `overlayItems`) are reactive nodes that
			only a hosted list builds — see the case below, which is what proves that
			on purpose. A thirteenth name here without a rebinding over there is a
			private that leaked into the seam. ]]
		local block = string.match(hosted, "\n\treturn {\n(.-)\n\t}\nend")
		assert(block ~= nil, HOSTED_PATH .. ": no `new` return block to read")
		local names: { string } = {}
		for name in string.gmatch("\n" .. (block :: string), "\n\t\t([%a_][%w_]*) =") do
			table.insert(names, name)
			-- ...and the host binds every one of them to a local, which is what makes
			-- the split invisible to every call site in that file
			expect(string.find(control, `= hostedBlock.{name}`, 1, true) ~= nil).toBe(true)
		end
		table.sort(names)
		expect(names).toEqual({
			"closeRow",
			"dispatch",
			"engagedEngine",
			"engagedKey",
			"engagedOffset",
			"engines",
			"itemExtentIn",
			"noticeMount",
			"overlayItems",
			"syncKeysEnabled",
			"trayPath",
			"writeSlide",
		})
	end)

	it("a list with no `rowActions` builds NOTHING reactive — the construction site may be unconditional", function()
		--[[ THE CLAIM `virtual_list.luau` MAKES when it calls `new` unconditionally,
			asserted rather than assumed: with `enabled = false` not one signal, memo,
			scope or observe is created, so a plain list pays for the feature existing
			exactly what it paid before the split. `core` and `listScope` are passed as
			tables with NO methods on purpose — any reactive call on this path would
			raise rather than quietly pass — and the three reactive names come back
			absent, which is the same fact read from the other end. ]]
		local hostedModule = require("../src/controls/virtual_list_hosted")
		local built = hostedModule.new({
			Facet = {},
			core = {},
			spec = {},
			id = "L",
			listScope = {},
			delivery = {},
			enabled = false,
			rowActions = nil,
			windowItems = {},
			indexByKey = {},
			scrollTop = {},
			rowExtentIn = function()
				return 0
			end,
			rowPathUnder = function()
				return ""
			end,
			hitPathOf = function()
				return nil
			end,
			mountedRowPath = function()
				return nil
			end,
			itemForKey = function()
				return nil
			end,
		} :: any)
		expect(built.engagedKey).toBe(nil)
		expect(built.engagedOffset).toBe(nil)
		expect(built.overlayItems).toBe(nil)
		-- ...and the nine that are plain closures and tables ARE there, so the three
		-- nils above are the feature staying asleep rather than the call failing
		local names: { string } = {}
		for name in built do
			table.insert(names, name)
		end
		table.sort(names)
		expect(names).toEqual({
			"closeRow",
			"dispatch",
			"engagedEngine",
			"engines",
			"itemExtentIn",
			"noticeMount",
			"syncKeysEnabled",
			"trayPath",
			"writeSlide",
		})
	end)

	it("the hosted half requires the control NOWHERE — the require is one-way", function()
		for path in string.gmatch(hosted, 'require%("([^"]+)"%)') do
			-- any spelling that resolves to the control itself
			expect(string.match(path, "virtual_list$") == nil).toBe(true)
		end
		-- ...and the direction that IS allowed is present, so this pair of
		-- assertions cannot both pass by the module having no requires at all
		expect(string.find(control, 'require("./virtual_list_hosted")', 1, true) ~= nil).toBe(true)
	end)

	it("the two mounted-path ids have ONE spelling, published here and read there", function()
		-- the host renders the nodes; everything that reads a path built from them
		-- lives in the hosted half. Two literals would be two contracts.
		expect(string.find(control, "local HOSTED_OVERLAY_ID = virtual_list_hosted.OVERLAY_ID", 1, true) ~= nil).toBe(
			true
		)
		expect(string.find(control, "local HOSTED_TRAY_GROUP_ID = virtual_list_hosted.TRAY_GROUP_ID", 1, true) ~= nil).toBe(
			true
		)
		local _, overlayLiterals = string.gsub(control, '"RowActionsOverlay"', "")
		local _, trayLiterals = string.gsub(control, '"RowActionsTray"', "")
		expect(overlayLiterals).toBe(0)
		expect(trayLiterals).toBe(0)
	end)

	it("the hosted half holds no module-level mutable state", function()
		-- every list gets its own `new`; a module-level table would be shared by all
		-- of them, which is the one way a per-instance extraction can leak across
		-- instances. The two module-level tables allowed are the shared empty
		-- overlay sentinel and the closed key set, both frozen by convention.
		local head = string.match(hosted, "^(.-)\nfunction virtual_list_hosted%.new")
		assert(head ~= nil, "no `new` to split the module head from")
		for line in string.gmatch(head :: string, "[^\n]+") do
			local name = string.match(line, "^local ([%a_][%w_]*) *[:=]")
			if name ~= nil then
				local ok = string.find(line, "= require(", 1, true) ~= nil -- a required module
					or string.find(line, "HOSTED_", 1, true) ~= nil -- a frozen-by-convention constant
					or name == "virtual_list_hosted" -- the module table itself
				expect(ok).toBe(true)
			end
		end
	end)
end)
