--!strict
--[[ THE DRAG-TO-EDGE AUTOSCROLL SEAM, MECHANISED — and the behaviour it moved.

	`tools/lune/verify/data/source-cap-ledger.md` records the rule every extraction in
	this repository is judged by: a block may leave a file only if it reads no mutable
	upvalue of its host, because otherwise the move creates a require BACK and the two
	files become one file with a slash in the middle. `commit_walks_seam.spec`
	mechanised that for a twenty-one-field parameter object; this seam has NINE fields
	and — unlike every previous one — it also had TWO REASSIGNED SCALARS
	(`pointerDrag`, `autoscrollClock`). They could cross because they were declared
	inside the block and read nowhere else, so the state left WITH the code, which is
	the `present/catchers.luau` precedent. That claim is the one this file exists to
	pin: a later round that starts reading `pointerDrag` from the renderer again would
	silently rebuild the coupling the split removed.

	  READ      every `ctx.<field>` the module reads, comments stripped
	  DECLARED  every field its own `Ctx` type names
	  PASSED    every key the renderer's `autoscroll_bridge.new({ … })` call hands over

	all three equal in both directions, plus the mutable-upvalue test itself over the
	nine names, the no-rebind test from the module's side, no module-level mutable
	state, EXPORTED == BOUND, one consumer and a one-way require.

	AND THE BEHAVIOUR, BECAUSE A GREEN SUITE WAS NOT EVIDENCE HERE. When this block
	was extracted the suite had **no case at all** that drove `controller.stepAutoscroll`
	— `tests/autoscroll.spec` covers the pure model (`input/autoscroll`) and
	`tests/collection_list.spec` covers `virtual_list`'s own stepper, and neither one
	reaches the renderer's chain. So "the full suite is unchanged" proved that nothing
	ELSE moved and said nothing about the block that did. The seven cases at the bottom
	drive the real seam through `renderer.attach` + the fake target: the dwell, the
	canvas write, the retraction reset, the opt-out, the clip-only fallback, and the
	NESTED CHAIN RULE — a pinned inner list is transparent and the page behind it wins,
	which is the claim the block's own comment calls the reason it exists.

	Each mechanised rule is a pure function of a string, so each carries a NEGATIVE
	CONTROL that feeds it a broken input and proves it reports. A check that cannot
	fail is decoration.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local fs = require("@lune/fs")
-- every `.luau` under `src/`, walked recursively (see the one-consumer case)
local src_tree = require("./lib/src_tree")

local customFactory = require("../src/core/custom")
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local fake_target = require("../tests/lib/fake_target")

local RENDERER_PATH = "src/render/renderer.luau"
local BRIDGE_PATH = "src/render/autoscroll_bridge.luau"

-- COMMENTS ARE NOT CODE: the chain rule, the band policy and the transparency
-- argument travelled with the block and name every one of these fields in prose.
-- A scan that counted them would report reads nobody makes.
local function stripComments(source: string): string
	local out = string.gsub("\n" .. source, "%-%-%[%[.-%]%]", " ")
	out = string.gsub(out, "\n[ \t]*%-%-[^\n]*", "\n")
	return out
end

local function ctxFieldsRead(source: string): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for key in string.gmatch(stripComments(source), "ctx%.([%a_][%w_]*)") do
		out[key] = true
	end
	return out
end

local function typeFields(source: string, typeName: string): { [string]: boolean }
	local block = string.match(source, "type " .. typeName .. " = {\n(.-)\n}")
	assert(block ~= nil, `no 'type {typeName}' block to read`)
	local out: { [string]: boolean } = {}
	for key in string.gmatch("\n" .. (block :: string), "\n\t([%a_][%w_]*):") do
		out[key] = true
	end
	return out
end

local function passedFields(source: string): { [string]: boolean }
	local call = string.match(stripComments(source), "local autoscroll = autoscroll_bridge%.new%({\n(.-)\n\t}%)")
	assert(call ~= nil, "no `autoscroll_bridge.new({ … })` call to read")
	local out: { [string]: boolean } = {}
	for key in string.gmatch("\n" .. (call :: string), "\n\t\t([%a_][%w_]*) =") do
		out[key] = true
	end
	return out
end

-- the names the module binds off the ctx, and the local each lands in
local function bindings(source: string): { [string]: string }
	local out: { [string]: string } = {}
	for name, field in string.gmatch(stripComments(source), "\n\tlocal ([%a_][%w_]*) = ctx%.([%a_][%w_]*)") do
		out[field] = name
	end
	return out
end

--[[ IS THIS NAME DECLARED ONCE AND NEVER REASSIGNED IN ITS HOST? A table-
	constructor entry (`handles = handles,`) reads exactly like an assignment, and the
	renderer contains dozens of them for these very names, so a scan that did not
	exclude a trailing comma would report every shared record as mutable. A `local`
	line is the declaration, not a reassignment. ]]
local function assignmentsOutsideDeclaration(source: string, name: string): { string }
	local out: { string } = {}
	for line in string.gmatch(stripComments(source), "\n([^\n]*)") do
		local trimmed = string.match(line, "^%s*(.-)%s*$") :: string
		if string.sub(trimmed, 1, 6) == "local " or string.sub(trimmed, -1) == "," then
			continue
		end
		if
			string.match(trimmed, "^" .. name .. "%s*=[^=]") ~= nil
			or string.match(trimmed, "^" .. name .. "%s*%+=") ~= nil
		then
			table.insert(out, trimmed)
		end
	end
	return out
end

local function declarationsOf(source: string, name: string): number
	local n = 0
	for line in string.gmatch(stripComments(source), "\n([^\n]*)") do
		local trimmed = string.match(line, "^%s*(.-)%s*$") :: string
		if
			string.match(trimmed, "^local " .. name .. "[%s:=]") ~= nil
			or string.match(trimmed, "^local function " .. name .. "%(") ~= nil
		then
			n += 1
		end
	end
	return n
end

local function exportsOf(source: string): { [string]: boolean }
	local block = string.match(source, "\n\treturn {\n(.-)\n\t}\nend")
	assert(block ~= nil, "no returned table to read")
	local out: { [string]: boolean } = {}
	for key in string.gmatch("\n" .. (block :: string), "\n\t\t([%a_][%w_]*) =") do
		out[key] = true
	end
	return out
end

local function boundOf(renderer_: string): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for key in string.gmatch(stripComments(renderer_), "= autoscroll%.([%a_][%w_]*)") do
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

describe("the autoscroll seam: READ == DECLARED == PASSED", function()
	local rendererSource = fs.readFile(RENDERER_PATH)
	local bridge = fs.readFile(BRIDGE_PATH)

	it("every `ctx` field the module reads is declared in its own `Ctx`", function()
		local reads = ctxFieldsRead(bridge)
		expect(#missingFrom(reads, typeFields(bridge, "Ctx"))).toBe(0)
		-- ...and the set is not empty, which is the trap a set comparison invites:
		-- two empty sets are equal
		expect(#sorted(reads)).toBe(9)
	end)

	it("every field `Ctx` declares is one the module actually reads", function()
		expect(#missingFrom(typeFields(bridge, "Ctx"), ctxFieldsRead(bridge))).toBe(0)
	end)

	it("every field `Ctx` declares is one the renderer actually PASSES, and back", function()
		-- the call is a table CONSTRUCTOR, so a field the module declares and the
		-- renderer forgot arrives as `nil` rather than as a missing argument — and a
		-- nil `lastScrollRegions` here is a chain that is silently always empty
		expect(#missingFrom(typeFields(bridge, "Ctx"), passedFields(rendererSource))).toBe(0)
		expect(#missingFrom(passedFields(rendererSource), typeFields(bridge, "Ctx"))).toBe(0)
		expect(sorted(passedFields(rendererSource))).toEqual({
			"adapter",
			"autoscrollLib",
			"autoscrollModels",
			"controller",
			"handles",
			"lastScrollRegions",
			"rectLib",
			"screenRectOf",
			"scrollAutoscroll",
		})
	end)

	it("NEGATIVE CONTROL: each scan reads what it claims to, and reports the pair out of step", function()
		local declared = { alpha = true, beta = true }
		local reads = { alpha = true, gamma = true }
		expect(missingFrom(reads, declared)[1]).toBe("gamma")
		expect(missingFrom(declared, reads)[1]).toBe("beta")
		local fake = "type Ctx = {\n\t-- a comment, not a field\n\talpha: any,\n\tbeta: any,\n}"
		expect(#sorted(typeFields(fake, "Ctx"))).toBe(2)
		expect(sorted(ctxFieldsRead("--[[ ctx.ghost ]]\nlocal x = ctx.real\n"))).toEqual({ "real" })
		expect(sorted(ctxFieldsRead("\t-- ctx.ghost\n\tlocal x = ctx.real\n"))).toEqual({ "real" })
		expect(sorted(passedFields("local autoscroll = autoscroll_bridge.new({\n\t\talpha = alpha,\n\t})"))).toEqual({
			"alpha",
		})
	end)
end)

describe("the autoscroll seam: the mutable-upvalue test itself", function()
	local rendererSource = fs.readFile(RENDERER_PATH)
	local bridge = fs.readFile(BRIDGE_PATH)

	it("every name that crosses is declared ONCE by the renderer and never reassigned", function()
		--[[ THE LEDGER'S RULE, APPLIED TO THE NINE NAMES RATHER THAN ASSERTED ABOUT
			THE BLOCK. A reassigned local cannot be shared by reference at all — the
			callee keeps the OLD value and the two halves silently disagree. Four of
			these are by-reference tables the renderer keeps writing to (`handles`,
			`lastScrollRegions`, `scrollAutoscroll`, `autoscrollModels`), two are module
			requires, one is a `local function`, one is the controller table, and
			`adapter` is `attach`'s own PARAMETER — a local that is never reassigned,
			which is why it may cross and why it declares zero times. ]]
		local offenders: { string } = {}
		for _, field in sorted(typeFields(bridge, "Ctx")) do
			local decls = declarationsOf(rendererSource, field)
			local assigns = assignmentsOutsideDeclaration(rendererSource, field)
			if decls > 1 or #assigns > 0 then
				table.insert(offenders, `{field}(decls={decls},assigns={#assigns})`)
			end
		end
		expect(table.concat(offenders, " ")).toBe("")
		expect(declarationsOf(rendererSource, "adapter")).toBe(0)
		expect(declarationsOf(rendererSource, "autoscrollModels")).toBe(1)
	end)

	it("THE TWO REASSIGNED SCALARS LEFT WITH THE CODE, and the renderer never grew them back", function()
		--[[ THE CLAIM THIS FILE EXISTS FOR. `pointerDrag` (the live drag record) and
			`autoscrollClock` (the accumulated frame time) are the only reassigned
			locals in the block, and the split was legal because they were declared
			inside it and read nowhere else in the renderer — so the state moved WITH
			the code instead of becoming a shared record. A round that starts reading
			either name from the renderer again has rebuilt the coupling the split
			removed, and would do it silently: the renderer would simply be holding a
			second, always-nil drag. ]]
		expect(declarationsOf(bridge, "pointerDrag")).toBe(1)
		expect(declarationsOf(bridge, "autoscrollClock")).toBe(1)
		expect(#assignmentsOutsideDeclaration(bridge, "pointerDrag")).toBe(2)
		expect(#assignmentsOutsideDeclaration(bridge, "autoscrollClock")).toBe(1)
		expect(string.find(stripComments(rendererSource), "pointerDrag") == nil).toBe(true)
		expect(string.find(stripComments(rendererSource), "autoscrollClock") == nil).toBe(true)
		-- ...and neither are the two private helpers that read them
		expect(string.find(stripComments(rendererSource), "scrollChainAt") == nil).toBe(true)
		expect(string.find(stripComments(rendererSource), "autoscrollOptsFor") == nil).toBe(true)
	end)

	it("the module never REBINDS one of the nine either — the same failure from this side", function()
		-- `handles = {}` inside the module would compile, run, and silently detach the
		-- two halves; the renderer half is checked above, this is the half nothing
		-- else can see
		local offenders: { string } = {}
		for field, name in bindings(bridge) do
			if #assignmentsOutsideDeclaration(bridge, name) > 0 then
				table.insert(offenders, field)
			end
		end
		table.sort(offenders)
		expect(table.concat(offenders, " ")).toBe("")
	end)

	it("the module holds NO module-level mutable state", function()
		-- two attached surfaces each call `autoscroll_bridge.new`, so anything at
		-- module level is shared between them — and `pointerDrag` at module level
		-- would mean one surface's drag steering another's scrollers
		local body = stripComments(bridge)
		local offenders: { string } = {}
		for name in string.gmatch(body, "\nlocal ([%a_][%w_]*)[%s:=]") do
			if #assignmentsOutsideDeclaration(bridge, name) > 0 then
				table.insert(offenders, name)
			end
		end
		expect(table.concat(offenders, " ")).toBe("")
		expect(string.find(body, "\nlocal autoscroll_bridge = {}", 1, true) ~= nil).toBe(true)
	end)

	it("NEGATIVE CONTROL: a reassignment is reported and a table-constructor entry is not", function()
		local reassigned = "\nlocal alpha = {}\n\talpha = {}\n"
		expect(#assignmentsOutsideDeclaration(reassigned, "alpha")).toBe(1)
		local constructorEntry = "\nlocal alpha = {}\n\tfoo({\n\t\talpha = alpha,\n\t})\n"
		expect(#assignmentsOutsideDeclaration(constructorEntry, "alpha")).toBe(0)
		expect(#assignmentsOutsideDeclaration("\nlocal beta = 0\n\tbeta += 1\n", "beta")).toBe(1)
		expect(declarationsOf(reassigned, "alpha")).toBe(1)
		expect(declarationsOf("\nlocal function beta()\n", "beta")).toBe(1)
	end)
end)

describe("the autoscroll seam: EXPORTED == BOUND, one consumer, one-way require", function()
	local rendererSource = fs.readFile(RENDERER_PATH)
	local bridge = fs.readFile(BRIDGE_PATH)

	it("every method the module exports is bound onto the controller, and every binding is exported", function()
		local exported = exportsOf(bridge)
		local bound = boundOf(rendererSource)
		expect(#missingFrom(exported, bound)).toBe(0) -- a method nobody can call
		expect(#missingFrom(bound, exported)).toBe(0) -- a binding that would be nil
		expect(sorted(exported)).toEqual({ "setPointerDrag", "stepAutoscroll" })
	end)

	it("the two PUBLIC names are unchanged, and their in-tree callers still find them", function()
		--[[ `controls/table.luau` publishes a row drag through `setPointerDrag` and
			`present/presenter.luau` drives `stepAutoscroll` once a frame; both go
			through `controller`, and both guard on `type(...) == "function"`, so a
			binding that failed to land would degrade to silence rather than to an
			error. That is exactly the shape a rename must not be allowed to reach. ]]
		expect(
			string.find(stripComments(rendererSource), "controller.setPointerDrag = autoscroll.setPointerDrag", 1, true)
				~= nil
		).toBe(true)
		expect(
			string.find(stripComments(rendererSource), "controller.stepAutoscroll = autoscroll.stepAutoscroll", 1, true)
				~= nil
		).toBe(true)
		expect(string.find(fs.readFile("src/controls/table.luau"), "renderController.setPointerDrag", 1, true) ~= nil).toBe(
			true
		)
		expect(string.find(fs.readFile("src/present/presenter.luau"), "controller.stepAutoscroll", 1, true) ~= nil).toBe(
			true
		)
	end)

	it("there is exactly ONE consumer of the module in src/, and the require is one-way", function()
		--[[ WALKED, NOT LISTED. This case shipped with a hand list of nine directories
			copied from `commit_walks_seam.spec` — and `src/` has sixteen, which is the
			precise defect `tests/lib/src_tree.luau` was written to remove and whose own
			header records two seam specs proving "exactly ONE consumer" over nine of
			fifteen. A second consumer in `src/async`, `src/env`, `src/focus`,
			`src/motion`, `src/preview` or `src/replication` would have read as "exactly
			one" (P3 review round 2). ]]
		local seen = src_tree.pathsContaining('require("./autoscroll_bridge")')
		expect(seen).toEqual({ RENDERER_PATH })
		-- ...and the walk reached past the nine the old list named
		local all = src_tree.readAll()
		expect(all["src/env/environment.luau"] ~= nil).toBe(true)
		expect(all["src/motion/spring.luau"] ~= nil or all["src/replication/props.luau"] ~= nil).toBe(true)
		-- ...and the module requires NOTHING — not the renderer (which is what "one
		-- file with a slash in the middle" would look like), not anything else: every
		-- collaborator it has arrives through `Ctx`, which is the strongest form of
		-- the one-way test any seam in this repository has been able to claim
		expect(string.match(stripComments(bridge), 'require%("')).toBe(nil)
	end)
end)

--[[ ── THE BEHAVIOUR THE SPLIT MOVED ────────────────────────────────────────
	Driven through `renderer.attach` and the fake target, because that is the only
	path `controller.stepAutoscroll` has. The pure model already has 25 cases of its
	own (`tests/autoscroll.spec`); none of them reach the CHAIN, the opt-out, the
	handle gate or the canvas write, and those are the four things this block is. ]]

local function textRows(prefix: string, n: number, h: number)
	local out = {}
	for i = 1, n do
		table.insert(
			out,
			UI.Text({ id = prefix .. i, text = prefix .. i, textSize = 16, height = { type = "fixed", px = h } })
		)
	end
	return out
end

--[[ One 400x600 surface holding an OUTER 300px scroller whose first child is an
	INNER 300px scroller: the two share a bottom edge, so ONE drag point is inside
	both of their bottom bands, and that coincidence is what makes the chain rule
	observable at all.

	THE INNER LIST IS DELIBERATELY LONG (1,600 px of canvas in a 300 px band). With a
	short one the first armed step scrolls it to its own end, `canTravel` resets the
	model on the very next frame, and the retraction case below then passes whether or
	not `setPointerDrag(nil)` resets anything — measured, which is why the number is
	40 rows and not 10. ]]
local function nestedSurface(opts: { autoscroll: any?, stripScrollSeam: boolean? }?)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local innerProps: any = {
		id = "Inner",
		width = { type = "fill" },
		height = { type = "fixed", px = 300 },
		gap = 0,
		padding = 0,
		children = textRows("i", 40, 40),
	}
	if opts ~= nil and opts.autoscroll ~= nil then
		innerProps.autoscroll = opts.autoscroll
	end
	local outerChildren: { any } = { UI.ScrollView(innerProps) }
	for _, row in textRows("o", 20, 40) do
		table.insert(outerChildren, row)
	end
	local bp = UI.Screen({
		id = "S",
		padding = 0,
		gap = 0,
		children = {
			UI.ScrollView({
				id = "Outer",
				width = { type = "fill" },
				height = { type = "fixed", px = 300 },
				gap = 0,
				padding = 0,
				children = outerChildren,
			}),
		},
	})
	local root = mountLib.mount(core, bp)
	local adapter = fake_target.new()
	if opts ~= nil and opts.stripScrollSeam then
		(adapter :: any).setScrollPosition = nil
	end
	local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
	controller.initialRender()
	return adapter, controller
end

-- 5 px above the shared bottom edge: inside BOTH bands
local DEEP_IN_BAND = { x = 200, y = 295 }

describe("drag-to-edge autoscroll: the renderer's chain, driven", function()
	it("dwells, then arms, then writes the canvas — and the host it names is the innermost", function()
		local adapter, controller = nestedSurface()
		controller.setPointerDrag({ pos = DEEP_IN_BAND })
		-- the model's dwell is 300 ms: nothing moves before it elapses
		expect(controller.stepAutoscroll(0).delta).toBe(0)
		expect(adapter.scrollPositionOf("/S/Outer/Inner").y).toBe(0)
		local armed = controller.stepAutoscroll(0.5)
		expect(armed.state).toBe("active")
		expect(armed.path).toBe("/S/Outer/Inner")
		local moved = controller.stepAutoscroll(0.5)
		expect(moved.delta > 0).toBe(true)
		-- ...and the delta reached the ADAPTER, which is the half a pure model test
		-- structurally cannot see
		expect(adapter.scrollPositionOf("/S/Outer/Inner").y).toBe(moved.delta)
		expect(adapter.scrollPositionOf("/S/Outer").y).toBe(0)
	end)

	it("THE CHAIN RULE: an inner list pinned at its tail is transparent and the page behind it wins", function()
		--[[ The block's own reason for existing. The inner scroller is driven to its
			maximum (400 content − 300 band = 100), so the band it owns can no longer
			travel; it disarms and the drag falls through to the outer page, which
			still has 800 px of canvas left. Without the `canTravel` test the inner
			list would swallow the gesture forever. ]]
		local adapter, controller = nestedSurface()
		adapter.driveScroll("/S/Outer/Inner", { x = 0, y = 99999 })
		expect(adapter.scrollPositionOf("/S/Outer/Inner").y).toBe(1300)
		controller.setPointerDrag({ pos = DEEP_IN_BAND })
		controller.stepAutoscroll(0)
		controller.stepAutoscroll(0.5)
		local moved = controller.stepAutoscroll(0.5)
		expect(moved.path).toBe("/S/Outer")
		expect(moved.delta > 0).toBe(true)
		expect(adapter.scrollPositionOf("/S/Outer").y).toBe(moved.delta)
		-- the pinned inner host did not move, and did not stay armed behind the winner
		expect(adapter.scrollPositionOf("/S/Outer/Inner").y).toBe(1300)
	end)

	it("`autoscroll = false` opts a host out, and the chain skips straight past it", function()
		local adapter, controller = nestedSurface({ autoscroll = false })
		controller.setPointerDrag({ pos = DEEP_IN_BAND })
		controller.stepAutoscroll(0)
		controller.stepAutoscroll(0.5)
		local moved = controller.stepAutoscroll(0.5)
		expect(moved.path).toBe("/S/Outer")
		expect(adapter.scrollPositionOf("/S/Outer/Inner").y).toBe(0)
	end)

	it("RETRACTION disarms on the spot, so a re-arm re-pays the dwell with no step in between", function()
		--[[ `setPointerDrag(nil)` resets every model ITSELF rather than leaving it to
			the next `stepAutoscroll`, and the difference is only visible when no step
			runs in between — which is the real sequence: `controls/table.luau` retracts
			on release and the next drag may begin inside the same frame. A retraction
			that only marked `pointerDrag = nil` would leave the winner ARMED, and the
			second drag would scroll from its first step with no dwell at all. ]]
		local adapter, controller = nestedSurface()
		controller.setPointerDrag({ pos = DEEP_IN_BAND })
		controller.stepAutoscroll(0)
		controller.stepAutoscroll(0.5)
		expect(controller.stepAutoscroll(0.5).delta > 0).toBe(true)
		local at = adapter.scrollPositionOf("/S/Outer/Inner").y
		controller.setPointerDrag(nil)
		controller.setPointerDrag({ pos = DEEP_IN_BAND })
		local reArmed = controller.stepAutoscroll(0.1)
		expect(reArmed.state).toBe("dwelling")
		expect(reArmed.delta).toBe(0)
		expect(adapter.scrollPositionOf("/S/Outer/Inner").y).toBe(at)
	end)

	it("a pointer that leaves the chain disarms the host it was steering", function()
		--[[ The block's last rule: EVERY host that is not this frame's winner is
			reset, so a chain can never have two models armed at once. The observable
			form is a pointer that walks off both scrollers — the chain is then empty,
			nobody wins, and the model the inner list was holding must not still be
			counting. Without that sweep the drag comes back to a host that is already
			`active` and scrolls on its first frame. ]]
		local adapter, controller = nestedSurface()
		controller.setPointerDrag({ pos = DEEP_IN_BAND })
		controller.stepAutoscroll(0)
		expect(controller.stepAutoscroll(0.5).state).toBe("active")
		local at = adapter.scrollPositionOf("/S/Outer/Inner").y
		-- y = 500 is below both hosts (the outer is 0..300), so the chain is empty
		controller.setPointerDrag({ pos = { x = 200, y = 500 } })
		expect(controller.stepAutoscroll(0.1)).toBe(nil)
		expect(adapter.scrollPositionOf("/S/Outer/Inner").y).toBe(at)
		controller.setPointerDrag({ pos = DEEP_IN_BAND })
		expect(controller.stepAutoscroll(0.1).state).toBe("dwelling")
		expect(adapter.scrollPositionOf("/S/Outer/Inner").y).toBe(at)
	end)

	it("with no drag at all the stepper answers nil and leaves every canvas alone", function()
		local adapter, controller = nestedSurface()
		controller.setPointerDrag({ pos = DEEP_IN_BAND })
		controller.stepAutoscroll(0)
		controller.stepAutoscroll(0.5)
		expect(controller.stepAutoscroll(0.5).delta > 0).toBe(true)
		local at = adapter.scrollPositionOf("/S/Outer/Inner").y
		controller.setPointerDrag(nil)
		expect(controller.stepAutoscroll(0.5)).toBe(nil)
		expect(adapter.scrollPositionOf("/S/Outer/Inner").y).toBe(at)
	end)

	it("a point in the middle of the host never arms, and a clip-only adapter is inert", function()
		local adapter, controller = nestedSurface()
		controller.setPointerDrag({ pos = { x = 200, y = 150 } })
		controller.stepAutoscroll(0)
		expect(controller.stepAutoscroll(1)).toBe(nil)
		expect(adapter.scrollPositionOf("/S/Outer/Inner").y).toBe(0)
		-- an adapter with no `setScrollPosition` is the clip-only fallback: the
		-- stepper answers nil instead of reaching for a seam that is not there
		local _, clipOnly = nestedSurface({ stripScrollSeam = true })
		clipOnly.setPointerDrag({ pos = DEEP_IN_BAND })
		clipOnly.stepAutoscroll(0)
		expect(clipOnly.stepAutoscroll(1)).toBe(nil)
	end)
end)
