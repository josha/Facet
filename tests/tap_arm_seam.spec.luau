--!strict
--[[ THE TAP-ECHO / ARM-DISPATCH SEAM, MECHANISED — and the behaviour it moved.

	`tools/lune/verify/data/source-cap-ledger.md` names this block as `renderer.luau`'s
	next seam and says exactly when it comes out: *before the next round that changes
	tap dispatch, the arm paradigm or the recycle pool / removal sweep / parked-props
	record*. Perf campaign P5 changes the removal sweep, so it came out FIRST, as its
	own commit, which is what that wording has demanded of every split this file has
	taken.

	  READ      every `deps.<field>` the module reads, comments stripped
	  DECLARED  every field its own `Deps` type names
	  PASSED    every key the renderer's `tap_arm.new({ … })` call hands over

	all three equal in both directions, plus the mutable-upvalue test over the three
	names, the no-rebind test from the module's side, no module-level mutable state,
	EXPORTED == USED, one consumer walked over the whole `src/` tree, a module that
	requires NOTHING, and the two rules this seam is the first to need:

	  * THE RENDERER HOLDS NO COPY OF THE FOUR PER-PATH RECORDS. `detectorTapGuard`,
	    `lastNodeTapAt`, `armOnTapDecl` and the scalar `armedHere` are what the block
	    owned; three of them are tables the renderer never read, so THE STATE LEFT WITH
	    THE CODE, and the fourth is the reassigned scalar the ledger warned about.
	  * `armedHere` IS WRITTEN ONLY HERE. It is assigned on four lines inside the
	    module and appears nowhere else in `src/`; `controller.cancelArmed` — which used
	    to assign it directly — now goes through `disarm()`, which is one of the four.

	AND THE BEHAVIOUR, WHICH THE SUITE ALREADY DROVE, so the honest claim is narrow:
	`tests/presenter_drag_integration.spec` drives `armOnTap` and the PLAT-1 echo guard
	through the presenter, and `tests/drag_public.spec` drives the refused-source arm.
	The full suite going 7,978 -> 7,978 with one instrument edited (see below) is real
	evidence about THIS block. What none of those files assert is the seam's own
	contract — that the echo window is a property of the DETECTOR-GUARDED path only,
	that the four record writers the renderer kept are the only way in, and that
	`disarm` is the only way out of the scalar — so the cases at the bottom drive
	exactly that through `renderer.attach` and the fake target.

	ONE INSTRUMENT WAS EDITED AND IT IS THE INTERESTING PART. `tests/drag_bridge_seam`
	COUNTS `dragBridge.peek()` call sites and pins the total at seven; this split moved
	three of them, so it is the first extraction in this repository to move a line
	another spec counts rather than one it names. The count is now taken over
	`tests/lib/renderer_source.all()` — every part of the renderer, joined — which is
	the reading of "the renderer" under which the number is unchanged, and which that
	library's own header has demanded since the commit-walk split.

	Each mechanised rule is a pure function of a string, so each carries a NEGATIVE
	CONTROL that feeds it a broken input and proves it reports. A check that cannot
	fail is decoration.

	MUTATIONS RUN, 2026-09-01: eight, of which SEVEN bite —

	  | mutation                                          | result   |
	  | the renderer keeps its own `armedHere`            | 2 red    |
	  | the echo guard applies to every node              | 1 red    |
	  | `activateArms` accepts a pointer meta             | 1 red    |
	  | `disarm` is a no-op                               | 1 red    |
	  | a module-level mutable table                      | 1 red    |
	  | `forgetDetector` drops only the guard             | 1 red    |
	  | a `Deps` field is not passed at construction      | 4 red    |
	  | `forgetSource` is a no-op                         | DOES NOT |

	AND TWO OF THEM ONLY BITE BECAUSE THE INSTRUMENT WAS CORRECTED. The module-level
	scan first matched `^local x[%s:]*=%s*{` and a TYPED `local shared: { … } = {}`
	walked past it; the `forgetDetector` half needed the remount case below, because
	nothing else in the suite re-creates a guarded node at a path it already held.

	`forgetSource` IS THE RECORDED NULL RESULT and it is kept as-is. The only route
	that reaches it is a drag declaration's unbind, and every route that unbinds one at
	a path that is coming BACK re-declares it in the same structural sync — so a
	no-op leaves `armOnTapDecl` holding a value the next `declareSource` overwrites
	anyway. It would bite the day a node remounts at the same path WITHOUT its
	declaration, which is the day the clear is load-bearing; there is no fixture in the
	repository that does that, and inventing one to make a mutation red would be a case
	written for the mutation rather than for the behaviour.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local fs = require("@lune/fs")
local src_tree = require("./lib/src_tree")

local customFactory = require("../src/core/custom")
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local fake_target = require("./lib/fake_target")

local RENDERER_PATH = "src/render/renderer.luau"
-- the card mounts as the `When`'s branch, so ITS path is the branch path
local CARD = "/S/Board/Gate/then/Card"
local TAP_ARM_PATH = "src/render/tap_arm.luau"

-- COMMENTS ARE NOT CODE: the block travelled with its own reasoning, and that
-- reasoning names these fields in prose.
local function stripComments(source: string): string
	local out = string.gsub("\n" .. source, "%-%-%[%[.-%]%]", " ")
	out = string.gsub(out, "\n[ \t]*%-%-[^\n]*", "\n")
	return out
end

local function depsFieldsRead(source: string): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for key in string.gmatch(stripComments(source), "deps%.([%a_][%w_]*)") do
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
	local call = string.match(stripComments(rendererSource), "local tapArm = tap_arm%.new%({\n(.-)\n\t}%)")
	assert(call ~= nil, "no `tap_arm.new({ … })` call to read")
	local out: { [string]: boolean } = {}
	for key in string.gmatch("\n" .. (call :: string), "\n\t\t([%a_][%w_]*) =") do
		out[key] = true
	end
	return out
end

local function bindings(source: string): { [string]: string }
	local out: { [string]: string } = {}
	for name, field in string.gmatch(stripComments(source), "\n\tlocal ([%a_][%w_]*) = deps%.([%a_][%w_]*)") do
		out[field] = name
	end
	return out
end

--[[ IS THIS NAME DECLARED ONCE AND NEVER REASSIGNED? A table-constructor entry
	(`dragBridge = dragBridge,`) reads exactly like an assignment, so a scan that did
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

local function exportsOf(source: string): { [string]: boolean }
	local block = string.match(source, "\n\treturn {\n(.-)\n\t}\n")
	assert(block ~= nil, "no exported table to read")
	local out: { [string]: boolean } = {}
	for key in string.gmatch("\n" .. (block :: string), "\n\t\t([%a_][%w_]*) =") do
		out[key] = true
	end
	return out
end

local function usedOf(rendererSource: string): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for key in string.gmatch(stripComments(rendererSource), "tapArm%.([%a_][%w_]*)") do
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

describe("the tap-arm seam: READ == DECLARED == PASSED", function()
	local rendererSource = fs.readFile(RENDERER_PATH)
	local tapArmSource = fs.readFile(TAP_ARM_PATH)

	it("every `deps` field the module reads is declared in its own `Deps`", function()
		local reads = depsFieldsRead(tapArmSource)
		expect(#missingFrom(reads, typeFields(tapArmSource, "Deps"))).toBe(0)
		-- ...and the set is not empty, which is the trap a set comparison invites:
		-- two empty sets are equal
		expect(sorted(reads)).toEqual({ "dragBridge", "dragCollaborators", "dragSourceEnabled" })
	end)

	it("every field `Deps` declares is one the module reads AND one the renderer passes", function()
		expect(#missingFrom(typeFields(tapArmSource, "Deps"), depsFieldsRead(tapArmSource))).toBe(0)
		--[[ The call is a table CONSTRUCTOR, so a field the module declares and the
			renderer forgot arrives as `nil` rather than as a missing argument — and a
			nil `dragSourceEnabled` here is a refused source that arms anyway. ]]
		expect(#missingFrom(typeFields(tapArmSource, "Deps"), passedFields(rendererSource))).toBe(0)
		expect(#missingFrom(passedFields(rendererSource), typeFields(tapArmSource, "Deps"))).toBe(0)
	end)

	it("NEGATIVE CONTROL: each of the three scans reports a broken input", function()
		expect(depsFieldsRead("local x = deps.invented\n").invented).toBe(true)
		local brokenType = "export type Deps = {\n\tonly: any,\n}\n"
		expect(sorted(typeFields(brokenType, "Deps"))).toEqual({ "only" })
		local brokenCall = "\tlocal tapArm = tap_arm.new({\n\t\tstray = stray,\n\t})\n"
		expect(sorted(passedFields(brokenCall))).toEqual({ "stray" })
	end)
end)

describe("the tap-arm seam: the mutable-upvalue test, and the scalar the ledger named", function()
	local rendererSource = fs.readFile(RENDERER_PATH)
	local tapArmSource = fs.readFile(TAP_ARM_PATH)

	it("every name that crosses is declared ONCE by the renderer and never reassigned", function()
		local offenders: { string } = {}
		for _, field in sorted(typeFields(tapArmSource, "Deps")) do
			local decls = declarationsOf(rendererSource, field)
			local assigns = assignmentsOutsideDeclaration(rendererSource, field)
			if decls ~= 1 or #assigns > 0 then
				table.insert(offenders, `{field}(decls={decls},assigns={#assigns})`)
			end
		end
		expect(table.concat(offenders, " ")).toBe("")
	end)

	it("...and the module never REBINDS one either — the same test from the other side", function()
		local offenders: { string } = {}
		for field, name in bindings(tapArmSource) do
			if #assignmentsOutsideDeclaration(tapArmSource, name) > 0 then
				table.insert(offenders, `{field}->{name}`)
			end
		end
		expect(table.concat(offenders, " ")).toBe("")
		-- the bindings exist at all, so an empty offender list means something
		expect(sorted(bindings(tapArmSource) :: any)).toEqual({
			"dragBridge",
			"dragCollaborators",
			"dragSourceEnabled",
		})
	end)

	it("THE RENDERER HOLDS NO COPY of the four records this block owned", function()
		--[[ THE STATE LEFT WITH THE CODE, mechanised. Three of the four were tables the
			renderer never read outside the block — they are gone from it entirely — and
			the fourth is the reassigned scalar. A split that left any of these names
			behind would have made the two files one file with a slash in the middle. ]]
		local body = stripComments(rendererSource)
		for _, name in { "detectorTapGuard", "lastNodeTapAt", "armOnTapDecl", "armedHere", "TAP_ECHO_WINDOW" } do
			expect(`{name} absent: {tostring(string.find(body, name, 1, true) == nil)}`).toBe(`{name} absent: true`)
		end
	end)

	it("`armedHere` is assigned on exactly four lines, all of them inside this module", function()
		--[[ THE SINGLE-WRITER RULE, and this seam is the second to need it (the drag
			bridge's `instance` was the first). A reassigned scalar cannot cross by
			reference — a callee handed the value keeps the old one forever — so the
			only safe move is to give it an owner and hand out `disarm()`.

			FOUR, COUNTED RATHER THAN REMEMBERED, and the first draft of this case said
			three: the session-died clear in `armedBySeam`, the commit clear and the arm
			in `activateArms` — and then `disarm` itself, which is the whole reason the
			renderer no longer needs the name. A prose count nobody recounts drifts. ]]
		expect(declarationsOf(tapArmSource, "armedHere")).toBe(1)
		expect(#assignmentsOutsideDeclaration(tapArmSource, "armedHere")).toBe(4)
		local elsewhere: { string } = {}
		for path, text in src_tree.readAll() do
			if path ~= TAP_ARM_PATH and string.find(stripComments(text), "armedHere", 1, true) ~= nil then
				table.insert(elsewhere, path)
			end
		end
		expect(elsewhere).toEqual({})
	end)

	it("no module-level mutable state: everything per-surface lives inside `new`", function()
		--[[ A module-level table would be SHARED BY EVERY SURFACE in the process, which
			for an echo guard means one screen's tap suppressing another's. Read from the
			text above the constructor. ]]
		local head = string.sub(tapArmSource, 1, string.find(tapArmSource, "function tap_arm.new", 1, true) :: number)
		local body = stripComments(head)
		expect(string.find(body, "= {}", 1, true) ~= nil).toBe(true) -- the module table itself
		local offenders: { string } = {}
		for line in string.gmatch(body, "\n([^\n]*)") do
			local trimmed = string.match(line, "^%s*(.-)%s*$") :: string
			-- ...INCLUDING A TYPED ONE. The first draft matched `^local x[%s:]*=%s*{`
			-- and a `local shared: { [string]: boolean } = {}` walked straight past it,
			-- which the mutation found and the reviewer would not have.
			if
				string.match(trimmed, "^local [%a_][%w_]*.*=%s*{") ~= nil
				and string.match(trimmed, "^local tap_arm") == nil
			then
				table.insert(offenders, trimmed)
			end
		end
		expect(table.concat(offenders, " ")).toBe("")
	end)
end)

describe("the tap-arm seam: EXPORTED == USED, one consumer, requires nothing", function()
	local rendererSource = fs.readFile(RENDERER_PATH)
	local tapArmSource = fs.readFile(TAP_ARM_PATH)

	it("every accessor the module exports is used by the renderer, and every use is exported", function()
		local exported = exportsOf(tapArmSource)
		local used = usedOf(rendererSource)
		expect(#missingFrom(exported, used)).toBe(0) -- an accessor nobody calls
		expect(#missingFrom(used, exported)).toBe(0) -- a call that would be nil
		expect(sorted(exported)).toEqual({
			"activateArms",
			"armedBySeam",
			"declareSource",
			"disarm",
			"dispatchNodeTapOnce",
			"forgetDetector",
			"forgetSource",
			"guardDetector",
			"tapArmsInstead",
		})
		-- ...and the type says the same nine things, so the two cannot drift
		expect(sorted(typeFields(tapArmSource, "TapArm"))).toEqual(sorted(exported))
	end)

	it("there is exactly ONE consumer in src/, and this module requires NOTHING", function()
		--[[ WALKED, NOT LISTED — `tests/lib/src_tree.luau` exists because a hand list of
			directories missed six of `src/`'s sixteen. The require-nothing half is the
			strongest form of the one-way test: a module with no requires cannot reach
			back into its host by any path at all. ]]
		expect(src_tree.pathsContaining('require("./tap_arm")')).toEqual({ RENDERER_PATH })
		local requires: { string } = {}
		for path in string.gmatch(stripComments(tapArmSource), 'require%("([^"]+)"%)') do
			table.insert(requires, path)
		end
		expect(requires).toEqual({})
		-- the walk really did read the tree it claims to
		local all = src_tree.readAll()
		expect(all[TAP_ARM_PATH] ~= nil).toBe(true)
		expect(all["src/input/drag_registry.luau"] ~= nil).toBe(true)
	end)
end)

--[[ ── THE BEHAVIOUR THE SPLIT MOVED ────────────────────────────────────────
	Driven through `renderer.attach` and the fake target. The suite already reaches
	this block through the presenter (see the header); what it does not assert is the
	SEAM's own contract, which is what these cases are. ]]

type Surface = {
	adapter: any,
	controller: any,
	taps: { string },
	now: (number) -> (),
	mounted: any,
	registry: any,
}

local function surface(opts: { armOnTap: boolean?, plain: boolean? }?): Surface
	local options = opts or {}
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
	local taps: { string } = {}
	local clock = 0
	-- the card lives under a `When` so a case can unmount and remount it at the SAME
	-- path, which is the shape the per-path records are swept for
	local mounted = core:signal(true)
	-- a Button, because `controller.tapAt` dispatches only through `TAPPABLE`
	local card = UI.Button({
		id = "Card",
		label = "Card",
		anchor = "topLeft",
		offsetX = 0,
		offsetY = 0,
		width = { type = "fixed", px = 100 },
		height = { type = "fixed", px = 60 },
	})
	local inner = if options.plain
		then card
		else UI.draggable(card, { payload = "card", armOnTap = options.armOnTap == true })
	local children: { any } = {
		UI.When({
			id = "Gate",
			condition = mounted,
			thenView = function()
				return inner
			end,
		}),
	}
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
	local controller = renderer.attach(core, root, env, adapter, {
		onNodeTap = function(path: string)
			table.insert(taps, path)
		end,
	})
	controller.initialRender()
	controller.setDragCollaborators({
		now = function(): number
			return clock
		end,
	})
	return {
		adapter = adapter,
		controller = controller,
		taps = taps,
		now = function(v: number)
			clock = v
		end,
		mounted = mounted,
		registry = controller.peekDragRegistry(),
	}
end

describe("the tap-arm block, driven", function()
	it("THE ECHO WINDOW IS THE DETECTOR-GUARDED PATH'S ALONE", function()
		--[[ The rule the block's own comment states and nothing asserted: only a node
			carrying a detector can hear the same press twice, so only such a node is
			guarded. A plain control mashed twice inside the window is two real presses
			and must count twice — a guard applied to every node would eat the second. ]]
		local guarded = surface()
		guarded.adapter.driveDragStart(CARD, { x = 20, y = 20, pointerType = "touch" })
		guarded.adapter.driveDragEnd(CARD, { x = 22, y = 20, pointerType = "touch" })
		local afterFirst = #guarded.taps
		expect(afterFirst).toBe(1)
		-- the same press echoing through the OTHER signal, inside the window
		guarded.controller.tapAt(20, 20)
		expect(#guarded.taps).toBe(afterFirst)
		-- ...and a real second press, once the window has closed
		guarded.now(1)
		guarded.controller.tapAt(20, 20)
		expect(#guarded.taps).toBe(afterFirst + 1)

		local plain = surface({ plain = true })
		plain.controller.tapAt(20, 20)
		plain.controller.tapAt(20, 20)
		expect(#plain.taps).toBe(2)
	end)

	it("A REMOUNT AT THE SAME PATH FORGETS THE ECHO TIMESTAMP, not only the guard", function()
		--[[ PATHS ARE REUSED ACROSS A REMOUNT — the rule the renderer's removal sweep
			states about every per-path record it owns, and this block owns two. The
			timestamp is the dangerous one: it is meaningless without the guard that
			reads it, so a `forgetDetector` that dropped only the guard would leave a
			stale `at` behind, and a node re-created inside the window would have its
			FIRST real press eaten. The clock never moves in this case, so nothing but
			the clear can make the second tap dispatch. ]]
		local s = surface()
		s.controller.tapAt(20, 20)
		expect(#s.taps).toBe(1)
		s.mounted:set(false)
		s.controller.refresh()
		s.mounted:set(true)
		s.controller.refresh()
		expect(s.adapter.node(CARD) ~= nil).toBe(true)
		s.controller.tapAt(20, 20)
		expect(#s.taps).toBe(2)
	end)

	it("`armOnTap` ARMS instead of dispatching, and only while nothing is live", function()
		local s = surface({ armOnTap = true })
		s.adapter.driveDragStart(CARD, { x = 20, y = 20, pointerType = "touch" })
		s.adapter.driveDragEnd(CARD, { x = 22, y = 20, pointerType = "touch" })
		expect(#s.taps).toBe(0)
		local registry = s.controller.peekDragRegistry()
		expect(registry.isActive()).toBe(true)
		expect(registry.mode()).toBe("armed")
		--[[ a tap WHILE HELD is the consumer's (a put-back, a row commit): it flows.
			DEFENDED TWICE, and the mutation says so: deleting the `isActive()` refusal
			from `tapArmsInstead` leaves this green, because `registry.arm` refuses a
			path while a session is live and the guard's last line reads that answer.
			The refusal stays because it is the one that states the MEANING — "this tap
			means something else" — and because it is the only half that would still
			hold if `arm` ever learned to re-arm. ]]
		s.now(1)
		s.controller.tapAt(20, 20)
		expect(#s.taps).toBe(1)
	end)

	it("`activateArms` picks up on an ACTION source only, and commits the second time", function()
		--[[ The non-pointer half. A pointer meta never arms — a mouse lifts by
			travelling and a tap has to stay a tap — and the second action activate is
			the COMMIT half of arm→navigate→commit. ]]
		local s = surface()
		expect(s.controller.activateArms(CARD, { source = "pointer" })).toBe(false)
		expect(s.controller.activateArms(CARD, { source = "action" })).toBe(true)
		local registry = s.controller.peekDragRegistry()
		expect(registry.mode()).toBe("armed")
		expect(s.controller.activateArms(CARD, { source = "action" })).toBe(true)
		expect(registry.isActive()).toBe(false)
	end)

	it("`cancelArmed` only ever cancels a session THIS seam armed, and `disarm` is the way out", function()
		--[[ `armedHere` is the whole point of the scalar: a control-owned grab (a
			VirtualList row's) must be invisible to the generic Cancel verb. Driven both
			ways on one surface. ]]
		local s = surface()
		expect(s.controller.cancelArmed("nothing")).toBe(false)
		local registry = s.controller.dragRegistry()
		registry.arm(CARD)
		expect(registry.mode()).toBe("armed")
		-- armed by someone else: not ours, so the verb declines and leaves it alone
		expect(s.controller.cancelArmed("verb")).toBe(false)
		expect(registry.isActive()).toBe(true)
		registry.cancel("reset")
		-- ...and armed by US: cancelled, and the scalar is cleared on the way out, so a
		-- second call cannot cancel a session that is no longer ours
		expect(s.controller.activateArms(CARD, { source = "action" })).toBe(true)
		expect(s.controller.cancelArmed("verb")).toBe(true)
		expect(registry.isActive()).toBe(false)
		expect(s.controller.cancelArmed("verb")).toBe(false)
	end)
end)
