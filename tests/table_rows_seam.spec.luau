--!strict
--[[ THE BUILDER SEAM, MECHANISED — what keeps `controls/table_rows.luau` one-way.

	WHY A SPEC AND NOT A COMMENT. `docs/handoff/SOURCE_CAP_LEDGER.md` records the
	rule every extraction in this repository is judged by: a block may leave a
	file only if it reads no mutable upvalue of its host, because otherwise the
	move creates a require BACK and the two files become one file with a slash in
	the middle. `table.luau`'s row also recorded that no such block existed —
	until the row/cell builder's inputs became a parameter object. That parameter
	object is now the whole of the seam, and a parameter object rots silently:
	one `deps.somethingNew` read that nobody declared, one key passed that
	nothing reads, one write back through a dep that was supposed to be a value,
	and the property that made the split safe is gone while everything still
	passes.

	SO THE SEAM IS A SET COMPARISON, run against the live sources:

	  READ      every `deps.<key>` the builder reads
	  DECLARED  every key its `Deps` type names
	  PASSED    every key the ONE construction site in `table.luau` hands over

	all three equal, plus the shared WRITE surface pinned by name (the two
	mutable containers, and nothing else) and the one-way require asserted
	directly. Each rule is a pure function of two strings, so each carries a
	NEGATIVE CONTROL that feeds it a broken pair and proves it reports — a check
	that cannot fail is decoration (a red check cannot report the next defect,
	and this repository's own gate-integrity sweep says so).
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local fs = require("@lune/fs")

local CONTROL_PATH = "src/controls/table.luau"
local BUILDER_PATH = "src/controls/table_rows.luau"

-- every `deps.<key>` the builder actually reads
local function readsOf(builder: string): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for key in string.gmatch(builder, "deps%.([%a_][%w_]*)") do
		out[key] = true
	end
	return out
end

-- every key the `Deps` type declares. Comment lines inside the block start with
-- `--` and so never match the `<name>:` shape, which is what lets the type carry
-- its reasoning without confusing this scan.
local function declaredOf(builder: string): { [string]: boolean }
	local block = string.match(builder, "export type Deps = {\n(.-)\n}")
	assert(block ~= nil, `{BUILDER_PATH}: no 'export type Deps' block to read`)
	local out: { [string]: boolean } = {}
	for key in string.gmatch("\n" .. (block :: string), "\n\t([%a_][%w_]*):") do
		out[key] = true
	end
	return out
end

-- every key the construction site passes
local function passedOf(control: string): { [string]: boolean }
	local block = string.match(control, "table_rows%.new%({\n(.-)\n\t}%)")
	assert(block ~= nil, `{CONTROL_PATH}: no 'table_rows.new' construction site to read`)
	local out: { [string]: boolean } = {}
	for key in string.gmatch("\n" .. (block :: string), "\n\t\t([%a_][%w_]*) =") do
		out[key] = true
	end
	return out
end

-- the names the builder WRITES THROUGH: a dep it reassigns, a field it sets on
-- one, or a key it stores into one. `deps` are bound to same-named locals at the
-- top of `new`, so the write shows up under the local's name.
local function writesOf(builder: string, keys: { [string]: boolean }): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for key in keys do
		local patterns = {
			`\n[ \t]*{key}%.[%a_][%w_]*%s*=[^=]`, -- a field on it
			`\n[ \t]*{key}%[[^%]]+%]%s*=[^=]`, -- a key inside it
			`\n[ \t]*{key}%s*=[^=]`, -- the binding itself
		}
		for _, pattern in patterns do
			if string.find(builder, pattern) ~= nil then
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

describe("the row-builder seam: READ == DECLARED == PASSED", function()
	local control = fs.readFile(CONTROL_PATH)
	local builder = fs.readFile(BUILDER_PATH)

	it("every fact the builder reads off `deps` is declared in `Deps`", function()
		local reads = readsOf(builder)
		-- the binding block is the only place `deps.` may appear at all, so a read
		-- with no declaration is a field somebody added by hand
		expect(#missingFrom(reads, declaredOf(builder))).toBe(0)
		-- ...and the set is not empty, which is the trap a set comparison invites:
		-- two empty sets are equal
		expect(#sorted(reads) > 20).toBe(true)
	end)

	it("every key `Deps` declares is one the builder actually reads", function()
		-- the other direction, and it is the one that catches a dep left behind by
		-- a change: a declared-but-unread key is a fact the table is still
		-- computing for nobody
		expect(#missingFrom(declaredOf(builder), readsOf(builder))).toBe(0)
	end)

	it("the one construction site passes exactly the declared set — no more, no less", function()
		local declared = declaredOf(builder)
		local passed = passedOf(control)
		expect(#missingFrom(declared, passed)).toBe(0) -- a fact nobody hands over
		expect(#missingFrom(passed, declared)).toBe(0) -- a fact nothing reads
	end)

	it("there is exactly ONE construction site", function()
		local _, count = string.gsub(control, "table_rows%.new", "")
		expect(count).toBe(1)
	end)

	it("NEGATIVE CONTROL: each set comparison reports the pair that is out of step", function()
		local declared = { alpha = true, beta = true }
		local reads = { alpha = true, gamma = true }
		expect(missingFrom(reads, declared)[1]).toBe("gamma")
		expect(missingFrom(declared, reads)[1]).toBe("beta")
		-- ...and the scans themselves read what they claim to
		local fake = "export type Deps = {\n\t-- a comment, not a key\n\talpha: any,\n\tbeta: any,\n}"
		expect(#sorted(declaredOf(fake))).toBe(2)
		expect(sorted(passedOf("table_rows.new({\n\t\talpha = alpha,\n\t\tbeta = beta,\n\t})"))[2]).toBe("beta")
	end)
end)

describe("the row-builder seam: the shared WRITE surface, and the one-way require", function()
	local control = fs.readFile(CONTROL_PATH)
	local builder = fs.readFile(BUILDER_PATH)

	it("the builder writes through exactly two deps, and both are containers by design", function()
		--[[ THE WHOLE POINT OF THE SPLIT, stated as a set. A dep the builder
			WRITES is state the two files share; a dep it only reads is a fact the
			table decided. Two names are allowed and each has its reason in the
			builder's own header:

			  · `rowGesture` — the live row drag and the activate suppression. These
			    were reassigned SCALARS, which cannot be shared by reference at all,
			    and turning them into one record is what closed this seam.
			  · `rowActionsByKey` — the per-row `row_actions` handles. A table is
			    already a reference, so this one cost nothing: the builder inserts,
			    `table.luau` prunes on data churn and disposes on teardown.

			A THIRD NAME HERE IS THE FINDING. It means a value the table decided has
			quietly become state with two owners, which is the shape that makes a
			later reader unable to tell which file is answerable for it. ]]
		local writes = sorted(writesOf(builder, declaredOf(builder)))
		expect(#writes).toBe(2)
		expect(writes[1]).toBe("rowActionsByKey")
		expect(writes[2]).toBe("rowGesture")
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

	it("the builder offers exactly the two entry points it declares", function()
		--[[ The seam's SURFACE, pinned beside its dependency set. `blueprint` is the
			`UI.ForEach` row function and is what the module exists for; `cellContent`
			is the same cell-content priority ladder offered to the hidden-column
			disclosure (ADAPT-18), which has to show the value the ROW would have
			shown. A third name appearing here without a caller is a private that
			leaked into the seam. ]]
		local rows = require("../src/controls/table_rows")
		local names: { string } = {}
		for name in
			rows.new({
				Facet = {},
				core = {},
				UI = {},
				spec = {},
				tableId = "T",
				columns = {},
				api = {},
				rowGesture = { drag = nil, suppressActivate = nil },
				selectionMode = "none",
				virtualized = false,
				HANDLE_GUTTER = 32,
				ROW_ART = {},
				ALIGN_H = {},
				ALIGN_V = {},
				cellPadding = "s",
				cellsEditPadding = {},
				editingSignal = {},
				selectedKeys = {},
				dragging = {},
				ghostText = {},
				ghostCount = {},
				rowBox = {},
				layoutIndex = {},
				rowActionsByKey = {},
				rowActionsCoordinator = nil,
				rowHeightOf = function()
					return 0
				end,
				capFor = function()
					return 1
				end,
				columnDim = function() end,
				columnHidden = function() end,
				selectedMemo = function() end,
				itemForKey = function()
					return nil
				end,
				applyDragPosition = function() end,
				clearPointerDrag = function() end,
				liveDragRects = function()
					return nil, nil
				end,
				cancelDrag = function() end,
			} :: any)
		do
			table.insert(names, name)
		end
		table.sort(names)
		expect(names).toEqual({ "blueprint", "cellContent" })
	end)

	it("the builder requires the control NOWHERE — the require is one-way", function()
		for path in string.gmatch(builder, 'require%("([^"]+)"%)') do
			-- any spelling that resolves to the control itself
			expect(string.match(path, "table$") == nil).toBe(true)
		end
		-- ...and the direction that IS allowed is present, so this pair of
		-- assertions cannot both pass by the module having no requires at all
		expect(string.find(control, 'require("./table_rows")', 1, true) ~= nil).toBe(true)
	end)

	it("the builder names no type from the control either", function()
		-- a type import is a require by another name in Luau ( `require` first,
		-- then `Module.Type` ), so the structural `Column` in the builder is what
		-- keeps the graph acyclic. Nothing may reach for the control's own module
		-- table at all.
		expect(string.find(builder, "table_control", 1, true)).toBe(nil)
	end)
end)
