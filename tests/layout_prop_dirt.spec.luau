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

-- ...and the machinery THE SPLIT'S OWN AUDIT at the foot of this file needs: it
-- MOUNTS each arrange-only prop rather than grepping for it.
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local customFactory = require("../src/core/custom")
local fake_target = require("./lib/fake_target")
local device_views = require("./lib/device_views")

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

--[[ THE SPLIT'S OWN AUDIT (wicked-fast O2). `renderer.luau`'s closure now trusts
	the declared class to decide whether a node keeps its measure slate — it builds
	a `measureContains` from `measure` dirt alone and the solver's adopt gate reads
	THAT, not the union — so "declared arrange-only" has to be a FACT about the
	solver, not a claim in the schema. For every prop whose declared classes are
	exactly { "arrange" }, this mounts it, changes it, and asserts the solve
	measured NOTHING. The values come from the schema itself (`enum[1]` and
	`enum[#enum]`, or 0 and 7 for a number, or false and true for a boolean), so
	the audit cannot drift out of date when an enum grows. A prop that fails here
	is a REAL finding — either its declared class is wrong or measure reads it. Do
	not weaken the assertion to make it pass.

	THE PARENT MATTERS, AND A WRONG ONE MAKES THE AUDIT VACUOUS. `alignH`/`alignV`
	under a stack are INERT — `placement_audit.luau:92-99` gives them to `zstack`,
	`grid` and `gridrow` only, and `:183-189` files an inert-placement diagnostic
	for exactly the stack pairing — so an audit that drove `alignH` on a vstack
	child would drive a prop nothing consumes and pass while measuring nothing.
	Each parent below is a kind `placement_audit.luau` says READS that prop.

	THE SET IS EIGHT, NOT NINE. `grep -n 'dirty = { "arrange" }' src/blueprint_schema.luau`
	returns nine hits and one of them (`:1174`) is inside a comment. The eight real
	arrange-only specs are `anchor` (`:754`), `offsetX` (`:763`), `offsetY` (`:772`),
	`lineAlign` (`:801`), `alignH` (`:876`), `alignV` (`:885`), `hidden` (`:967`)
	and `distribute` (`DISTRIBUTE`, `:1176`) — and the set is DERIVED from
	`schema.propDirty()` below rather than transcribed, so a ninth cannot escape.
	`layoutPriority` (`:828`), `shrinkWeight` (`:837`) and `gridSpan` (`:866`) are
	`dirty = { "measure" }` and are NOT audited here — they are already covered by
	the class-scan cases above, and putting them in this table would assert the
	opposite of what the schema declares.

	AND THE FIXTURE INHERITS THE PLAN_SKIP HAZARD, ON THE PARENT AS WELL AS THE
	CHILDREN — a correction to the T3 brief, measured 2026-09-02. A fixed x fixed
	node is `PLAN_SKIP` (`measure_facts.luau:409-412`) and
	`solver.luau:1588-1590` sends it straight to `measureUncached`, which counts it
	on every touch with no slate consulted, so `lastMeasured == 0` is unreachable
	for ANY fixed x fixed node the arrange pass still descends through. The brief
	warned about the children; the parent has the same hazard, and the same
	fixture with `height = px(200)` on the parent reads `lastMeasured == 1` on a
	pure `offsetX` change rather than 0. The children below are `width = px(20)`
	with a `content` height around a text leaf, and the parent is `width = px(200)`
	with a `fill` height — content or fill on one axis is enough to leave
	PLAN_SKIP.

	AND THE FIRST DRIVE IS DISCARDED: `controller.initialRender()` is not a reuse
	solve, so `measure_reuse.clear` has just emptied the store and the drive right
	after it is the FILL pass (it reads 6 on this fixture, not 0). The audit warms
	one drive and pins the second, the same discipline
	`tests/nameplates_baseline.spec.luau` states for its steady tick. ]]

-- the solver KIND a prop is READ by -> the blueprint class that mounts that kind
local CLASS_FOR_KIND: { [string]: (props: any) -> any } = {
	anchor = UI.Anchor,
	zstack = UI.ZStack,
	hstack = UI.HStack,
	vstack = UI.VStack,
}

-- prop -> the parent KIND that reads it (`src/layout/placement_audit.luau:89-117`).
-- `hidden` has no parent requirement (it is read on the node itself, wherever it
-- sits), so it takes the plainest container here.
local PARENT_FOR: { [string]: string } = {
	anchor = "anchor",
	offsetX = "anchor",
	offsetY = "anchor",
	alignH = "zstack",
	alignV = "zstack",
	lineAlign = "hstack",
	hidden = "vstack",
	distribute = "vstack",
}

--[[ ...and the one prop of the eight that is a CONTAINER prop: `distribute` is
	authored on the parent that distributes, never on a child, so the driver binds
	its signal to the mounted parent instead. Spelled as its own set rather than as
	a `"SELF"` sentinel inside `PARENT_FOR` so that table stays a pure prop -> kind
	map and the two round-trip assertions below need no special case. ]]
local DRIVEN_ON_PARENT: { [string]: boolean } = { distribute = true }

local function px(n: number): any
	return { type = "fixed", px = n }
end

-- the two values to drive between, read off the prop's own spec so an enum that
-- grows cannot leave this audit driving a value that no longer exists
local function valuesFor(className: string, prop: string): (any, any)
	local spec = (schema.forClass(className) :: any).props[prop]
	if spec.enum ~= nil then
		return spec.enum[1], spec.enum[#spec.enum]
	end
	for _, ty in spec.types do
		if ty == "boolean" then
			return false, true
		end
		if ty == "number" then
			return 0, 7
		end
	end
	error(`layout_prop_dirt: no drivable value for {className}.{prop}`, 0)
end

--[[ Mount `prop` under the parent kind that reads it, drive it A -> B -> A, and
	report `lastMeasured` on the SECOND drive. `control` swaps the driven prop for
	a measure-classed one on the same fixture, which is what keeps a zero here from
	being a zero the fixture would report for anything. ]]
local function measuredOnDrive(prop: string, view: any, control: boolean): number
	local kind = PARENT_FOR[prop]
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = view.w, h = view.h })
	local onParent = DRIVEN_ON_PARENT[prop] == true
	-- every audited prop is `shared = true`, so VStack carries all eight and is the
	-- one spec the values are read off — including `distribute`, which VStack has
	local driven = if control then "width" else prop
	local a: any, b: any = px(20), px(31)
	if not control then
		a, b = valuesFor("VStack", prop)
	end
	local sig = core:signal(a)
	local function kid(id: string, bind: boolean): any
		local props: any = {
			id = id,
			width = px(20),
			height = { type = "content" },
			children = { UI.Text({ id = "T", text = "xy", textSize = 12 }) },
		}
		if bind then
			props[driven] = sig
		end
		return UI.VStack(props)
	end
	local parentProps: any = {
		id = "P",
		width = px(200),
		height = { type = "fill", weight = 1 },
		children = { kid("A", control or not onParent), kid("B", false) },
	}
	if onParent and not control then
		parentProps[prop] = sig
	end
	local root = mountLib.mount(core, UI.Screen({ id = "S", children = { CLASS_FOR_KIND[kind](parentProps) } }))
	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter, {
		rootPolicy = "edgeToEdge",
		incrementalLayout = true,
		measureReuse = true,
		layoutNodeReuse = true,
		commitScope = true,
	})
	controller.initialRender()
	sig:set(b) -- warm: the fill pass after `initialRender` cleared the store
	controller.refresh()
	sig:set(a)
	controller.refresh()
	local measured = (controller.stats() :: any).lastMeasured
	controller.dispose()
	root.dispose()
	return measured
end

describe("an arrange-only prop is PROVABLY unread by measure (the split's own audit)", function()
	-- every prop whose declared classes are exactly { "arrange" }, derived
	local arrangeOnly: { [string]: boolean } = {}
	for _, props in schema.propDirty() do
		for prop, classes in props do
			if #classes == 1 and classes[1] == "arrange" then
				arrangeOnly[prop] = true
			end
		end
	end

	it("the audit table covers exactly the schema's arrange-only props, both directions", function()
		local missing: { string } = {}
		for prop in arrangeOnly do
			if PARENT_FOR[prop] == nil then
				table.insert(missing, prop)
			end
		end
		table.sort(missing)
		if #missing > 0 then
			error(
				`{#missing} arrange-only prop(s) escape the mount-and-measure audit: {table.concat(missing, ", ")} — `
					.. `add each to PARENT_FOR with the parent kind placement_audit says reads it`,
				0
			)
		end
		local reclassified: { string } = {}
		for prop in PARENT_FOR do
			if not arrangeOnly[prop] then
				table.insert(reclassified, prop)
			end
		end
		table.sort(reclassified)
		if #reclassified > 0 then
			error(
				`{#reclassified} audited prop(s) are no longer declared arrange-only: `
					.. `{table.concat(reclassified, ", ")} — the adopt gate's assumption moved, so this audit `
					.. `must move with it`,
				0
			)
		end
		local n = 0
		for _ in arrangeOnly do
			n += 1
		end
		expect(n).toBe(8)
	end)

	it("...and driving each of them measures NOTHING, at every device view", function()
		for prop in PARENT_FOR do
			for _, view in device_views.VIEWS do
				expect(`{prop}@{view.id}:{measuredOnDrive(prop, view, false)}`).toBe(`{prop}@{view.id}:0`)
			end
		end
	end)

	it("CONTROL: the same fixture measures when a MEASURE-classed prop moves", function()
		--[[ The zero above is only evidence if this fixture can produce a non-zero.
			Same mount, same drive, same counter — `width` instead of the arrange-only
			prop, and `width` is `dirty = { "measure" }`. Without this row the audit
			would pass on a fixture that never solves at all. ]]
		local view = device_views.VIEWS[1]
		for prop in PARENT_FOR do
			expect(`{prop}:{measuredOnDrive(prop, view, true) > 0}`).toBe(`{prop}:true`)
		end
	end)
end)
