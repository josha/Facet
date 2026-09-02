--!strict
--[[ THE DRAG BRIDGE'S REGISTRY SEAM, MECHANISED — and the behaviour it moved.

	`tools/lune/verify/data/source-cap-ledger.md` records the rule every extraction in
	this repository is judged by: a block may leave a file only if it reads no mutable
	upvalue of its host, because otherwise the move creates a require BACK and the two
	files become one file with a slash in the middle. `commit_walks_seam.spec`
	mechanised that for a twenty-one-field parameter object and
	`autoscroll_bridge_seam.spec` for a nine-field one whose two reassigned scalars
	left WITH the code.

	THIS SEAM IS THE ONE THE LEDGER SAID NEEDED A RECORD, and that is what makes it a
	different commit from a verbatim move. Its row's own words: "the REGISTRY half
	(`dragRegistry`/`attachDetector`, ~5 KB) is NOT taken and is the next named seam:
	`dragRegistryInstance` is read from eleven places in this file … so it needs the
	shared-record move `controls/table.luau` proved". A reassigned scalar cannot cross
	by reference at all — the callee keeps the OLD value — so the move is to give it an
	OWNER and hand out accessors. The rules below therefore include one no previous
	seam spec has had to state: THE RENDERER HOLDS NO COPY OF THE SCALAR, and there is
	exactly one place in the codebase that assigns it.

	  READ      every `ctx.<field>` the module reads, comments stripped
	  DECLARED  every field its own `DragBridgeCtx` type names
	  PASSED    every key the renderer's `drag_bridge.new({ … })` call hands over

	all three equal in both directions, plus the mutable-upvalue test over the ten
	names, the no-rebind test from the module's side, no module-level mutable state,
	EXPORTED == USED, one consumer walked over the whole `src/` tree, a one-way
	require, and the single-writer rule above.

	AND THE BEHAVIOUR — WHICH, UNLIKE THE AUTOSCROLL HALF, THE SUITE ALREADY DROVE.
	That is worth saying rather than assuming: `tests/drag_public.spec` reaches
	`controller.dragRegistry()` at eleven sites and `tests/presenter_drag_integration.spec`
	is the only file that exercises `setDragDetector` and the `dragHeld` write, so the
	full suite going 7,945 -> 7,945 with no spec edited is real evidence about THIS
	block and not only about its neighbours. What those files do not assert is the
	seam's own contract — build-once, `peek` never builds, the three by-reference
	collaborators resolve live, and dispose clears the scalar — so the cases at the
	bottom drive exactly that through `renderer.attach` and the fake target.

	Each mechanised rule is a pure function of a string, so each carries a NEGATIVE
	CONTROL that feeds it a broken input and proves it reports. A check that cannot
	fail is decoration.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local fs = require("@lune/fs")
-- every `.luau` under `src/`, walked recursively (see the one-consumer case)
local src_tree = require("./lib/src_tree")
-- the renderer AS ITS PARTS: the accessor count below is taken over all of them,
-- because P5's Phase 0 moved three counted call sites into `render/tap_arm.luau`
local renderer_source = require("./lib/renderer_source")

local customFactory = require("../src/core/custom")
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local fake_target = require("./lib/fake_target")

local RENDERER_PATH = "src/render/renderer.luau"
local BRIDGE_PATH = "src/render/drag_bridge.luau"

-- COMMENTS ARE NOT CODE: the block travelled with its own reasoning, and that
-- reasoning names every one of these fields in prose. A scan that counted them
-- would report reads nobody makes.
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

local function passedFields(rendererSource: string): { [string]: boolean }
	local call = string.match(stripComments(rendererSource), "local dragBridge = drag_bridge%.new%({\n(.-)\n\t}%)")
	assert(call ~= nil, "no `drag_bridge.new({ … })` call to read")
	local out: { [string]: boolean } = {}
	for key in string.gmatch("\n" .. (call :: string), "\n\t\t([%a_][%w_]*) =") do
		out[key] = true
	end
	return out
end

local function bindings(source: string): { [string]: string }
	local out: { [string]: string } = {}
	for name, field in string.gmatch(stripComments(source), "\n\tlocal ([%a_][%w_]*) = ctx%.([%a_][%w_]*)") do
		out[field] = name
	end
	return out
end

--[[ IS THIS NAME DECLARED ONCE AND NEVER REASSIGNED IN ITS HOST? A table-constructor
	entry (`handles = handles,`) reads exactly like an assignment, so a scan that did
	not exclude a trailing comma would report every shared record as mutable. ]]
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

local function exportsOf(bridge: string): { [string]: boolean }
	local block = string.match(bridge, "\n\treturn {([^\n]*)}\n")
	assert(block ~= nil, "no returned table to read")
	local out: { [string]: boolean } = {}
	for key in string.gmatch(block :: string, "([%a_][%w_]*) =") do
		out[key] = true
	end
	return out
end

local function usedOf(rendererSource: string): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for key in string.gmatch(stripComments(rendererSource), "dragBridge%.([%a_][%w_]*)") do
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

describe("the drag-bridge seam: READ == DECLARED == PASSED", function()
	local rendererSource = fs.readFile(RENDERER_PATH)
	local bridge = fs.readFile(BRIDGE_PATH)

	it("every `ctx` field the module reads is declared in its own `DragBridgeCtx`", function()
		local reads = ctxFieldsRead(bridge)
		expect(#missingFrom(reads, typeFields(bridge, "DragBridgeCtx"))).toBe(0)
		-- ...and the set is not empty, which is the trap a set comparison invites:
		-- two empty sets are equal
		expect(#sorted(reads)).toBe(10)
	end)

	it("every field `DragBridgeCtx` declares is one the module actually reads", function()
		expect(#missingFrom(typeFields(bridge, "DragBridgeCtx"), ctxFieldsRead(bridge))).toBe(0)
	end)

	it("every field `DragBridgeCtx` declares is one the renderer actually PASSES", function()
		--[[ The call is a table CONSTRUCTOR, so a field the module declares and the
			renderer forgot arrives as `nil` rather than as a missing argument — and a
			nil `handles` here is a detector acquisition that silently never fires. ]]
		expect(#missingFrom(typeFields(bridge, "DragBridgeCtx"), passedFields(rendererSource))).toBe(0)
		expect(#missingFrom(passedFields(rendererSource), typeFields(bridge, "DragBridgeCtx"))).toBe(0)
	end)

	it("NEGATIVE CONTROL: each scan reads what it claims to, and reports the pair out of step", function()
		local declared = { alpha = true, beta = true }
		local reads = { alpha = true, gamma = true }
		expect(missingFrom(reads, declared)[1]).toBe("gamma")
		expect(missingFrom(declared, reads)[1]).toBe("beta")
		local fake = "type Deps = {\n\t-- a comment, not a field\n\talpha: any,\n\tbeta: any,\n}"
		expect(#sorted(typeFields(fake, "Deps"))).toBe(2)
		expect(sorted(ctxFieldsRead("--[[ ctx.ghost ]]\nlocal x = ctx.real\n"))).toEqual({ "real" })
		expect(sorted(ctxFieldsRead("\t-- ctx.ghost\n\tlocal x = ctx.real\n"))).toEqual({ "real" })
		expect(sorted(passedFields("local dragBridge = drag_bridge.new({\n\t\talpha = alpha,\n\t})"))).toEqual({
			"alpha",
		})
	end)
end)

describe("the drag-bridge seam: the mutable-upvalue test, and the record the ledger asked for", function()
	local rendererSource = fs.readFile(RENDERER_PATH)
	local bridge = fs.readFile(BRIDGE_PATH)

	it("every name that crosses is declared ONCE by the renderer and never reassigned", function()
		--[[ THE LEDGER'S RULE APPLIED TO THE TEN NAMES rather than asserted about the
			block. `core` and `adapter` declare ZERO times on purpose: they are
			`attach`'s own parameters, and a parameter is a local that is never
			reassigned, which is why it may cross. ]]
		local offenders: { string } = {}
		for _, field in sorted(typeFields(bridge, "DragBridgeCtx")) do
			local decls = declarationsOf(rendererSource, field)
			local assigns = assignmentsOutsideDeclaration(rendererSource, field)
			if decls > 1 or #assigns > 0 then
				table.insert(offenders, `{field}(decls={decls},assigns={#assigns})`)
			end
		end
		expect(table.concat(offenders, " ")).toBe("")
		expect(declarationsOf(rendererSource, "adapter")).toBe(0)
		expect(declarationsOf(rendererSource, "core")).toBe(0)
		expect(declarationsOf(rendererSource, "lastZ")).toBe(1)
	end)

	it("the module never REBINDS one of them either — the same failure from this side", function()
		local offenders: { string } = {}
		for field, name in bindings(bridge) do
			if #assignmentsOutsideDeclaration(bridge, name) > 0 then
				table.insert(offenders, field)
			end
		end
		table.sort(offenders)
		expect(table.concat(offenders, " ")).toBe("")
	end)

	it("THE RECORD: the reassigned scalar has exactly one owner and the renderer holds no copy", function()
		--[[ THE RULE THAT MADE THIS A DIFFERENT COMMIT FROM A VERBATIM MOVE. Before the
			split `dragRegistryInstance` was a renderer local, assigned in three places
			(built, torn down, nilled) and read in eleven — the shape that cannot cross a
			seam, because a callee handed the VALUE keeps the old one forever. It is now
			`instance` inside `drag_bridge.new`, and the two halves of the claim are:
			the old name exists nowhere in the renderer at all, and inside the module the
			scalar is written on exactly two lines (the build and the dispose). A third
			writer, or a renderer-side cache of `peek()`, rebuilds the coupling. ]]
		expect(string.find(rendererSource, "dragRegistryInstance", 1, true)).toBe(nil)
		local body = stripComments(bridge)
		local assigns = 0
		for line in string.gmatch(body, "\n([^\n]*)") do
			local trimmed = string.match(line, "^%s*(.-)%s*$") :: string
			if string.match(trimmed, "^instance%s*=[^=]") ~= nil then
				assigns += 1
			end
		end
		expect(assigns).toBe(2)
		expect(declarationsOf(bridge, "instance")).toBe(1)
	end)

	it("`peek` never builds and `registry` does — the difference four call sites depend on", function()
		--[[ Structural, because the behaviour case below can only show that today's
			`peek` did not build; this shows that it CANNOT. `peek`'s body is one
			`return instance`, and the constructor call lives inside `registry`'s
			nil-guard. Four sites read without building — the tap-arm guard, the
			seam-armed test, the activate-arms path and `controller.peekDragRegistry` —
			and each of them treats "there is no registry" as "no declaring source is
			mounted", which a building read would erase. ]]
		local peekBody = string.match(stripComments(bridge), "\n\tlocal function peek%(%): any\n(.-)\n\tend")
		expect(peekBody ~= nil).toBe(true)
		expect(string.match(peekBody :: string, "^%s*return instance%s*$") ~= nil).toBe(true)
		local registryBody = string.match(stripComments(bridge), "\n\tlocal function registry%(%): any\n(.-)\n\tend\n")
		expect(registryBody ~= nil).toBe(true)
		expect(string.find(registryBody :: string, "dragRegistryLib.new(", 1, true) ~= nil).toBe(true)
	end)

	it("the module holds NO module-level mutable state", function()
		--[[ Two attached surfaces each call `drag_bridge.new`, so anything at module
			level is shared between them — and for THIS module that would be a second
			surface's drag session. ]]
		local body = stripComments(bridge)
		local offenders: { string } = {}
		for name in string.gmatch(body, "\nlocal ([%a_][%w_]*)[%s:=]") do
			if #assignmentsOutsideDeclaration(bridge, name) > 0 then
				table.insert(offenders, name)
			end
		end
		expect(table.concat(offenders, " ")).toBe("")
		expect(string.find(body, "\nlocal drag_bridge = {}", 1, true) ~= nil).toBe(true)
	end)

	it("NEGATIVE CONTROL: a reassignment is reported and a table-constructor entry is not", function()
		local reassigned = "\nlocal alpha = {}\n\talpha = {}\n"
		expect(#assignmentsOutsideDeclaration(reassigned, "alpha")).toBe(1)
		local constructorEntry = "\nlocal alpha = {}\n\tfoo({\n\t\talpha = alpha,\n\t})\n"
		expect(#assignmentsOutsideDeclaration(constructorEntry, "alpha")).toBe(0)
		expect(declarationsOf(reassigned, "alpha")).toBe(1)
		expect(declarationsOf("\nlocal function beta()\n", "beta")).toBe(1)
	end)
end)

describe("the drag-bridge seam: EXPORTED == USED, one consumer, one-way require", function()
	local rendererSource = fs.readFile(RENDERER_PATH)
	local bridge = fs.readFile(BRIDGE_PATH)

	it("every accessor the module exports is used by the renderer, and every use is exported", function()
		local exported = exportsOf(bridge)
		local used = usedOf(rendererSource)
		expect(#missingFrom(exported, used)).toBe(0) -- an accessor nobody calls
		expect(#missingFrom(used, exported)).toBe(0) -- a call that would be nil
		expect(sorted(exported)).toEqual({ "attachDetector", "dispose", "peek", "registry" })
	end)

	it("the accessor split is COUNTED from the live source, not remembered", function()
		--[[ THE MODULE HEADER AND THE SOURCE-CAP LEDGER BOTH NAME THE SPLIT — 7 reads,
			4 builds, 2 detector acquisitions, 1 dispose — and the first version of both
			said "four `peek()`" because the number was carried over from the ledger's
			count of pre-split READ SITES rather than counted after the move (P4 review,
			folded minor 2). Three inline reads became named locals on the way out, so
			eleven read sites became fourteen call sites.

			A prose count nobody recounts is a prose count that drifts, so it is pinned
			here instead: the numbers below are what the renderer actually contains, and
			the header has to move with them.

			COUNTED OVER THE WHOLE RENDERER, NOT OVER `renderer.luau` (2026-09-01, perf
			campaign P5's Phase 0). The tap-echo guard and the arm dispatch left for
			`render/tap_arm.luau` and took THREE of the seven `peek()` calls with them —
			the first split to move a line this file COUNTS rather than one it names.
			The split did not change the accessor split by one call, so the number must
			not move either, and the only reading of "the renderer" under which it does
			not is `tests/lib/renderer_source`'s: every part, joined. That library exists
			for exactly this failure and its header's own rule is ADD A PART WHENEVER
			MORE OF THE RENDERER MOVES OUT. ]]
		local body = stripComments(renderer_source.all())
		local counts: { [string]: number } = { peek = 0, registry = 0, attachDetector = 0, dispose = 0 }
		for name in string.gmatch(body, "dragBridge%.([%a_][%w_]*)%(") do
			if counts[name] ~= nil then
				counts[name] += 1
			end
		end
		expect(counts.peek).toBe(7)
		expect(counts.registry).toBe(4)
		expect(counts.attachDetector).toBe(2)
		expect(counts.dispose).toBe(1)
		-- ...and the header states the same four numbers, so the two cannot drift apart
		for _, claim in { "`peek()` x7", "`registry()` x4", "`attachDetector()` x2", "`dispose()` x1" } do
			expect(string.find(bridge, claim, 1, true) ~= nil).toBe(true)
		end
	end)

	it("there is exactly ONE consumer of the module in src/, and the requires are one-way", function()
		--[[ WALKED, NOT LISTED — `tests/lib/src_tree.luau` exists because a hand list of
			directories missed six of `src/`'s sixteen and two seam specs proved "exactly
			ONE consumer" over nine of fifteen (P3 review round 2). ]]
		local seen = src_tree.pathsContaining('require("./drag_bridge")')
		expect(seen).toEqual({ RENDERER_PATH })
		local all = src_tree.readAll()
		expect(all["src/env/environment.luau"] ~= nil).toBe(true)
		expect(all["src/tokens/chrome_slots.luau"] ~= nil).toBe(true)
		--[[ ...and this module DOES require two things, which is where it differs from
			the autoscroll half. The one-way claim is therefore stated rather than
			asserted-by-absence: it requires the write manifest and the pure drag MODEL,
			and neither of those requires the renderer or this bridge back. ]]
		local requires: { string } = {}
		for path in string.gmatch(stripComments(bridge), 'require%("([^"]+)"%)') do
			table.insert(requires, path)
		end
		table.sort(requires)
		expect(requires).toEqual({ "../input/drag_registry", "./authority" })
		for _, path in { "src/input/drag_registry.luau", "src/render/authority.luau" } do
			local text = fs.readFile(path)
			expect(string.find(text, "drag_bridge", 1, true)).toBe(nil)
			expect(string.find(text, "render/renderer", 1, true)).toBe(nil)
		end
	end)
end)

--[[ ── THE BEHAVIOUR THE SPLIT MOVED ────────────────────────────────────────
	Driven through `renderer.attach` and the fake target. The suite already reaches
	this block (see the header); what it does not assert is the SEAM's own contract,
	which is what these cases are. ]]

local function surface(opts: { noDetector: boolean?, noDeclarations: boolean? }?)
	local options = opts or {}
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
	local enabled = core:signal(true)
	local drops: { string } = {}
	--[[ TWO DROP TARGETS ON THE SAME BOX, AND THEIR PAINT ORDER DELIBERATELY DISAGREES
		WITH THEIR REGISTRATION ORDER. That disagreement is the whole point of the
		`zOf` case and it took a correction to get right: with two plain siblings the
		registry's own fallback (`rank = index` when `zOf` answers nil) ranks them the
		same way the z walk does, so passing a COPY of `lastZ` instead of the live
		table changed nothing and the case proved nothing. `Top` is declared FIRST — so
		it registers first and its index is lower — and carries `zIndex = 5`, so the
		renderer paints it above `Bottom`. Only a bridge reading the LIVE `lastZ` can
		see that. ]]
	local function slot(id: string, z: number)
		return UI.dropTarget(
			UI.Box({
				id = id,
				anchor = "topLeft",
				offsetX = 200,
				offsetY = 0,
				zIndex = z,
				width = { type = "fixed", px = 100 },
				height = { type = "fixed", px = 60 },
			}),
			{
				onDrop = function()
					table.insert(drops, id)
				end,
			}
		)
	end
	local children: { any } = {}
	if not options.noDeclarations then
		table.insert(
			children,
			UI.draggable(
				UI.Box({
					id = "Card",
					anchor = "topLeft",
					offsetX = 0,
					offsetY = 0,
					width = { type = "fixed", px = 100 },
					height = { type = "fixed", px = 60 },
				}),
				{ payload = "card", enabled = enabled }
			)
		)
		table.insert(children, slot("Top", 5))
		table.insert(children, slot("Bottom", 0))
	end
	local bp = UI.Screen({
		id = "S",
		children = {
			UI.Anchor({
				id = "Board",
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				children = children,
			}),
		},
	})
	local root = mountLib.mount(core, bp)
	local adapter = fake_target.new()
	if options.noDetector then
		adapter.setDragDetector = nil
	end
	local controller = renderer.attach(core, root, env, adapter, {})
	controller.initialRender()
	return {
		core = core,
		env = env,
		adapter = adapter,
		controller = controller,
		enabled = enabled,
		drops = drops,
	}
end

describe("the drag bridge, driven", function()
	it("`registry()` builds ONCE and hands the same object back", function()
		local s = surface()
		local a = s.controller.dragRegistry()
		local b = s.controller.dragRegistry()
		expect(a).toBe(b)
		expect(a.isActive()).toBe(false)
	end)

	it("`peek()` answers the live instance and never manufactures one", function()
		--[[ THE SIGNAL THE FOUR READING SITES DEPEND ON: "no registry" means "no
			declaring source or target is mounted", so a building read would erase it.
			A surface with neither peeks nil FOREVER, however many times it is asked —
			and asking is what the tap-arm guard does on every tap of every control on
			every surface in the framework. The declaring surface builds one at MOUNT,
			through the wiring's own `registry()`, which is the other half of the
			claim. ]]
		local bare = surface({ noDeclarations = true })
		expect(bare.controller.peekDragRegistry()).toBe(nil)
		expect(bare.controller.peekDragRegistry()).toBe(nil)
		local built = bare.controller.dragRegistry()
		expect(built ~= nil).toBe(true)
		expect(bare.controller.peekDragRegistry()).toBe(built)

		local declaring = surface()
		local atMount = declaring.controller.peekDragRegistry()
		expect(atMount ~= nil).toBe(true)
		expect(declaring.controller.dragRegistry()).toBe(atMount)
	end)

	it("the held source reaches the adapter as a `dragHeld` write, through the manifest", function()
		--[[ The observer the bridge installs on `registry.heldSource`, which is the one
			write in this module and the reason it needs `handles`, `findNode` and
			`authority` at all. `setDragHeld` clears the PREVIOUS path before setting the
			new one, so a hand-off leaves nothing latched. ]]
		local s = surface()
		local registry = s.controller.dragRegistry()
		local held = (registry :: any).heldSource
		held:set("/S/Board/Card")
		local ops = table.concat(s.adapter.ops(), "\n")
		expect(string.find(ops, "prop /S/Board/Card.dragHeld=true", 1, true) ~= nil).toBe(true)
		held:set(nil)
		expect(string.find(table.concat(s.adapter.ops(), "\n"), "prop /S/Board/Card.dragHeld=false", 1, true) ~= nil).toBe(
			true
		)
	end)

	it("`zOf` breaks a tie between two stacked targets, through the renderer's live `lastZ`", function()
		--[[ THE BY-REFERENCE HALF OF THE SEAM, driven rather than asserted. `lastZ` is
			written by the renderer's z walk AFTER this module was constructed, so a
			bridge handed a COPY resolves every tie against an empty table and the
			registry falls back to REGISTRATION order — which in this fixture names
			`Bottom`, because `Top` is declared first and wins only on the `zIndex` the
			renderer painted it with. Proved by mutation: `lastZ = table.clone(lastZ)`
			at the construction call turns this green answer red. ]]
		local s = surface()
		local registry = s.controller.dragRegistry()
		expect(#registry.dump().targets).toBe(2)
		registry.pointerDown("/S/Board/Card", { x = 50, y = 30 })
		registry.pointerMove("/S/Board/Card", { x = 250, y = 30 })
		registry.pointerUp("/S/Board/Card", { x = 250, y = 30 })
		expect(s.drops).toEqual({ "Top" })
	end)

	it("`isSourceEnabled` is read LIVE per acquisition, not captured at registration", function()
		local s = surface()
		local registry = s.controller.dragRegistry()
		expect(registry.arm("/S/Board/Card")).toBe(true)
		registry.cancel("test")
		s.enabled:set(false)
		s.controller.refresh()
		expect(registry.arm("/S/Board/Card")).toBe(false)
	end)

	it("`attachDetector` answers nil on an adapter without the seam, and a detach with it", function()
		local without = surface({ noDetector = true })
		expect(without.controller.attachDragDetector("/S/Board/Card", {})).toBe(nil)
		local with = surface()
		local detach = with.controller.attachDragDetector("/S/Board/Card", {})
		expect(typeof(detach)).toBe("function")
		-- ...and a path with no handle answers nil rather than raising
		expect(with.controller.attachDragDetector("/S/Board/Nope", {})).toBe(nil)
	end)

	it("dispose tears the registry down and clears the scalar", function()
		local s = surface()
		local registry = s.controller.dragRegistry()
		expect(registry.isActive()).toBe(false)
		s.controller.dispose()
		expect(s.controller.peekDragRegistry()).toBe(nil)
	end)

	it("`setDragCollaborators` reaches an already-built registry", function()
		local s = surface()
		local registry = s.controller.dragRegistry()
		local seen: { string } = {}
		s.controller.setDragCollaborators({
			feedback = {
				emit = function(event: string)
					table.insert(seen, event)
				end,
			},
		})
		expect(registry.arm("/S/Board/Card")).toBe(true)
		expect(#seen > 0).toBe(true)
	end)
end)
