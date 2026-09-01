--!strict
--[[
	THE DIRTY TABLE IS LOAD-BEARING, SO IT IS AUDITED — not read and trusted.

	WHAT WENT WRONG (P1 review, CRITICAL 1). Every reactive prop declares the dirty
	CLASSES a change to it invalidates (`blueprint_schema`'s `dirty = { … }`, surfaced
	as `schema.propDirty()` and subscribed by `mount.luau`). `renderer.luau:2878-2884`
	turns `structure`/`measure`/`arrange` into a solve and `paint`/`semantics` into a
	property write; `renderer.luau`'s ancestor closure then puts only the layout
	classes into `dirtyContains`, which is what `arrange`'s skip — and, since P1,
	`measure`'s cross-solve store — read to decide a subtree is unchanged.

	`surface` was declared `{ "paint" }` on all sixteen container classes and on `Text`,
	and `layout_node` reads it TWICE as a size input: an intrinsic minimum for
	`surface = "badge"` (`:822`), and `chrome_slots.classify` (`:929`), whose slot picks
	the `chromeInsets`/`chromeOutsets` that are ADDED TO PADDING. `Button.selected` was
	`{ "paint", "semantics" }` and feeds the same classify call as `hasSelection`
	(`:930`).

	Declared paint-only, a flip set `needsSolve = false`, so the new geometry landed
	LATE — on whatever unrelated solve came next. P1's store turned late into NEVER:
	the node is absent from `dirtyContains`, its slate is adopted, and the pre-flip
	measurement is served forever. The repro lives in `tests/measure_reuse.spec.luau`
	("a paint-classed prop that layout_node reads as a SIZE input").

	WHY THIS FILE EXISTS RATHER THAN THREE MORE `dirty` ENTRIES. The bug was not that
	someone wrote the wrong list; it was that NOTHING RELATED THE TWO FILES. A prop's
	classes live in `blueprint_schema.luau` and its consumption lives in
	`layout_node.luau`, and the only thing joining them was that someone had once read
	both. This walks `layout_node.luau`'s actual `props.<name>` reads against each
	prop's declared classes and fails on any class-and-prop pair the solver consumes
	without a layout class.

	IT ATTRIBUTES READS TO CLASS BRANCHES, which is what keeps it from being noise.
	`layout_node` dispatches through flat `if class == "X" then … elseif class == "Y"`
	chains at one tab of indent, so a read inside a branch speaks only for the classes
	that branch names, and a read outside every branch speaks for all of them. Without
	that, `Path.thickness` (`dirty = { "paint" }`) reports as a violation because
	`Divider.thickness` — a different class, correctly `{ "measure" }` — is read at
	`:788` under `elseif class == "Divider"`. Its absence from the output is the
	attribution working, and `PARSER_PINS` below asserts it directly rather than
	leaving it to be inferred from a green run.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")
local schema = require("../src/blueprint_schema")

local SOURCE = "src/render/layout_node.luau"
-- the classes a change must reach the SOLVER through. `paint`/`semantics` reach the
-- adapter without one (renderer.luau's refresh), which is the whole distinction.
local LAYOUT_CLASSES = { measure = true, arrange = true, structure = true }

local lines = fs.readFile(SOURCE):split("\n")

-- a `if`/`elseif class == "A"` (or `... or class == "B"`) dispatch line
local function guardAt(i: number): { indent: string, classes: { string } }?
	local indent, keyword = lines[i]:match("^(\t*)(%a+) class ==")
	if indent == nil or (keyword ~= "if" and keyword ~= "elseif") then
		return nil
	end
	local classes = {}
	for name in lines[i]:gmatch('class == "([%w_]+)"') do
		table.insert(classes, name)
	end
	return { indent = indent, classes = classes }
end

-- the class branch line `target` sits in, or nil when it sits outside every one
local function branchOf(target: number): { string }?
	for i = target - 1, 1, -1 do
		local guard = guardAt(i)
		if guard ~= nil then
			for j = i + 1, #lines do
				local sibling = lines[j]:match(`^{guard.indent}(%a+)`)
				if sibling == "elseif" or sibling == "else" or sibling == "end" then
					if target < j then
						return guard.classes
					end
					break
				end
			end
		end
	end
	return nil
end

type Read = { prop: string, line: number, classes: { string }? }

local function readsOf(): { Read }
	local out: { Read } = {}
	local inBlockComment = false
	for i, raw in lines do
		if inBlockComment then
			if raw:match("%]%]") then
				inBlockComment = false
			end
			continue
		end
		if raw:match("%-%-%[%[") then
			inBlockComment = true
			continue
		end
		-- a prop named in a trailing line comment is prose, not a read
		local code = raw:gsub("%-%-.*", "")
		for name in code:gmatch("props%.([%a_][%w_]*)") do
			table.insert(out, { prop = name, line = i, classes = branchOf(i) })
		end
	end
	return out
end

--[[ THE PAINT-ONLY ALLOWLIST, and it is empty ON PURPOSE.

	Every `(class, prop)` pair `layout_node` reads today carries a layout class. An
	entry here is a claim that a read is provably not solver-visible — that the value
	reaches only `channel`/paint output — and it must say WHY on the line beside it.
	Adding one silently is how CRITICAL 1 would come back, so the count is pinned by
	its own case below: growing this list is a deliberate, reviewed act. ]]
local PAINT_ONLY_ALLOWLIST: { [string]: string } = {}

describe("layout_node's prop reads agree with the dirty table that gates them", function()
	it("PARSER PINS: the branch attribution actually attributes", function()
		--[[ An audit whose parser silently matched nothing would pass forever. These
			four facts are what the scan is FOR, asserted directly. ]]
		local reads = readsOf()
		expect(#reads > 50).toBe(true)

		local byProp: { [string]: { Read } } = {}
		for _, r in reads do
			byProp[r.prop] = byProp[r.prop] or {}
			table.insert(byProp[r.prop], r)
		end

		-- 1. `thickness` is read ONCE, and only inside the Divider branch. This is the
		--    pair that makes attribution load-bearing: `Path.thickness` is paint-only
		--    and correct, `Divider.thickness` is `{ "measure" }` and correct, and a
		--    scan without branches cannot tell them apart.
		expect(byProp.thickness ~= nil).toBe(true)
		expect(#byProp.thickness).toBe(1)
		expect(table.concat(byProp.thickness[1].classes :: { string }, ",")).toBe("Divider")

		-- 2. `surface` is read OUTSIDE every class branch — it speaks for all sixteen
		--    container classes and for Text, which is why the fix touched two
		--    declarations rather than one.
		expect(byProp.surface ~= nil).toBe(true)
		local unscopedSurface = 0
		for _, r in byProp.surface do
			if r.classes == nil then
				unscopedSurface += 1
			end
		end
		expect(unscopedSurface >= 2).toBe(true)

		-- 3. `selected` is read, unscoped, and is the `hasSelection` input.
		expect(byProp.selected ~= nil).toBe(true)
		expect(byProp.selected[1].classes).toBe(nil)

		-- 4. a read INSIDE a branch is attributed to it (Text, the densest branch)
		expect(byProp.lineLimit ~= nil).toBe(true)
		expect(table.concat(byProp.lineLimit[1].classes :: { string }, ",")).toBe("Text")
	end)

	it("every solver-consumed prop declares a layout dirty class", function()
		local dirty = schema.propDirty()
		local violations: { string } = {}
		local seen: { [string]: boolean } = {}
		for _, read in readsOf() do
			for className, props in dirty do
				local classes = props[read.prop]
				if classes == nil then
					continue
				end
				if read.classes ~= nil then
					local named = false
					for _, c in read.classes do
						if c == className then
							named = true
						end
					end
					if not named then
						continue
					end
				end
				local key = `{className}.{read.prop}`
				if PAINT_ONLY_ALLOWLIST[key] ~= nil or seen[key] then
					continue
				end
				local layout = false
				for _, c in classes do
					if LAYOUT_CLASSES[c] then
						layout = true
					end
				end
				if not layout then
					seen[key] = true
					table.insert(
						violations,
						`{key} = {table.concat(classes, "+")} — read at {SOURCE}:{read.line}, `
							.. `so a change to it moves geometry the renderer will never re-solve for`
					)
				end
			end
		end
		table.sort(violations)
		if #violations > 0 then
			error(
				`{#violations} solver-consumed prop(s) declare no measure/arrange/structure `
					.. `dirty class:\n  `
					.. table.concat(violations, "\n  "),
				0
			)
		end
		expect(#violations).toBe(0)
	end)

	it("the allowlist is empty, and stays a deliberate act", function()
		local n = 0
		for _ in PAINT_ONLY_ALLOWLIST do
			n += 1
		end
		expect(n).toBe(0)
	end)

	it("...and the three props the review found now carry it", function()
		-- the pins, by name: a later edit that reverts any of them reddens HERE with
		-- the reason, not only in the scan above with a path
		local dirty = schema.propDirty()
		local function has(className: string, prop: string, want: string): boolean
			for _, c in dirty[className][prop] do
				if c == want then
					return true
				end
			end
			return false
		end
		expect(has("Box", "surface", "measure")).toBe(true)
		expect(has("Text", "surface", "measure")).toBe(true)
		expect(has("Button", "selected", "measure")).toBe(true)
		-- ...and they did not LOSE the paint class they also legitimately have
		expect(has("Box", "surface", "paint")).toBe(true)
		expect(has("Button", "selected", "semantics")).toBe(true)
	end)
end)
