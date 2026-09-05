--!strict
--[[ THE Z-ORDER SEAM, MECHANISED — what keeps `render/z_order.luau` one-way.

	The explicit paint-order walk left `render/renderer.luau` on 2026-09-04 (Plan C,
	ruling T5-2) because that file stood 40 characters from the campaign's 197,500
	STOP line. `tools/lune/verify/data/source-cap-ledger.md` records the rule every
	extraction here is judged by: a block may leave a file only if it reads no
	MUTABLE upvalue of its host, because otherwise the move creates a require back
	and the two files become one file with a slash in the middle. The cases below are
	that rule, in the shape `tests/stack_seam.spec.luau` established:

	  A CLOSED DEPS   READ == DECLARED == PASSED, as three SETS compared against each
	                  other. An eighth field reached for is a seam growing back — the
	                  seventh, `stats`, arrived with C5 and argues for itself below
	  ONE CONSUMER    `src/render/renderer.luau`, and nothing else in `src/`
	  ONE-WAY         it names no renderer symbol and imports no renderer type, and
	                  its two requires are leaves the renderer requires as well
	  NOTHING LEFT    the renderer kept no copy of the walk
	  NO STATE        no module-level local is ever reassigned, so two surfaces share
	                  no counter — which for a Z WALK is not a nicety: `z` is a
	                  per-walk local, and a module-level one would make one surface's
	                  paint order a function of another's node count

	Each source rule is a pure function of a string, so each carries a NEGATIVE
	CONTROL that feeds it a broken input and proves it reports. A check that cannot
	fail is decoration. The BEHAVIOUR half of this seam is not here and does not need
	to be: `tests/hit_expander_z_band.spec.luau`, `tests/hit_expander_overhang.spec.luau`
	and `tests/nested_tree_pins.spec.luau` drive the walk through the public surface,
	and they were green across the split. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local fs = require("@lune/fs")
local srcTree = require("./lib/src_tree")

local MODULE_PATH = "src/render/z_order.luau"
local RENDERER_PATH = "src/render/renderer.luau"

local function stripComments(source: string): string
	local out = string.gsub("\n" .. source, "%-%-%[%[.-%]%]", " ")
	out = string.gsub(out, "\n[ \t]*%-%-[^\n]*", "\n")
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

describe("the z-order seam: a closed deps record, one consumer, one-way", function()
	it("READ == DECLARED == PASSED: the deps record is closed on all three sides", function()
		--[[ THE THREE SETS, compared against each other rather than against a list in
			this file. A field the module reads and the type does not declare is a seam
			that has grown a new dependency in silence; one the renderer passes and the
			module never reads is a dependency nobody removed when it stopped mattering. ]]
		local source = stripComments(fs.readFile(MODULE_PATH))
		local declared: { [string]: boolean } = {}
		local typeBody = string.match(source, "export type Deps = {(.-)\n}") :: string
		assert(typeBody ~= nil, "no `export type Deps` to read")
		for name in string.gmatch(typeBody, "\n\t([%a_][%w_]*):") do
			declared[name] = true
		end
		local read: { [string]: boolean } = {}
		for name in string.gmatch(source, "deps%.([%a_][%w_]*)") do
			read[name] = true
		end
		--[[ ...AND THE ONES UNPACKED INTO LOCALS, which is how five of the six are
			actually reached. A scan that saw only `deps.x` would report this record as
			one field wide and pass.

			THE `(` TEST IS LOAD-BEARING: `local zMetrics = deps.metrics()` is a CALL,
			not an unpack, and counting its left-hand name put a local that is not a deps
			field into the READ set. The rule is that an unpack's right-hand side is
			`deps.x[, deps.y…]` and nothing else. ]]
		for names, rhs in string.gmatch(source, "local ([%w_, ]+) = ([^\n]*)") do
			-- an unpack's WHOLE right-hand side is `deps.x[, deps.y…]`; anything else —
			-- a call, an index, a concatenation — is not one
			if string.match(rhs, "^deps%.[%w_]+[deps%.%w_, ]*$") ~= nil then
				for name in string.gmatch(names, "[%a_][%w_]*") do
					read[name] = true
				end
			end
		end
		local rendererBody = stripComments(fs.readFile(RENDERER_PATH))
		local call = string.match(rendererBody, "z_order%.new%({(.-)\n\t}%)") :: string
		assert(call ~= nil, "no `z_order.new({ … })` call in the renderer")
		local passed: { [string]: boolean } = {}
		for name in string.gmatch(call, "\n\t\t([%a_][%w_]*) =") do
			passed[name] = true
		end
		--[[ SEVEN, since Plan C's C5 — and the growth is the thing this case exists to
			make ARGUE for itself rather than to forbid. `stats` is there because two z
			walks can run in one frame (the structural sync's bounded one and the commit's
			hit-lift re-run), so the walk COUNT is part of what a caller has to read, and
			only the module knows it. It is a write-only field: the module never reads a
			counter back, so no renderer state re-enters through it. ]]
		expect(sorted(declared)).toEqual({
			"adapter",
			"handles",
			"hitLift",
			"lastZ",
			"metrics",
			"root",
			"stats",
		})
		expect(sorted(read)).toEqual(sorted(declared))
		expect(sorted(passed)).toEqual(sorted(declared))
		--[[ NEGATIVE CONTROL, BOTH WAYS: the scan sees a multi-name unpack, and it does
			NOT see the left-hand name of a deps CALL. ]]
		local fake: { [string]: boolean } = {}
		for names, rhs in
			string.gmatch("local a, b = deps.a, deps.b\nlocal c = deps.f()", "local ([%w_, ]+) = ([^\n]*)")
		do
			if string.match(rhs, "^deps%.[%w_]+[deps%.%w_, ]*$") ~= nil then
				for name in string.gmatch(names, "[%a_][%w_]*") do
					fake[name] = true
				end
			end
		end
		expect(sorted(fake)).toEqual({ "a", "b" })
	end)

	it("ONE CONSUMER in src/, and the requires are one-way", function()
		expect(srcTree.pathsMatching('require%("[^"]*z_order"%)')).toEqual({ RENDERER_PATH })
		local source = stripComments(fs.readFile(MODULE_PATH))
		local requires: { [string]: boolean } = {}
		for path in string.gmatch(source, 'require%("([^"]*)"%)') do
			requires[path] = true
		end
		-- two LEAVES, both of which the renderer requires as well, so the module can
		-- ask them the same questions without either file learning about the other
		expect(sorted(requires)).toEqual({ "./authority", "./layout_node" })
		-- ...and NOTHING back: no renderer require, no renderer symbol, no renderer type
		expect(`renderer require:{string.find(source, "renderer", 1, true) ~= nil}`).toBe("renderer require:false")
		-- NEGATIVE CONTROL: the scan really does see a require
		local fake: { [string]: boolean } = {}
		for path in string.gmatch('local x = require("./renderer")', 'require%("([^"]*)"%)') do
			fake[path] = true
		end
		expect(sorted(fake)).toEqual({ "./renderer" })
	end)

	it("NO module-level state: a z counter shared between surfaces is the defect", function()
		--[[ `z` is a per-walk local and must stay one. A module-level counter would make
			one surface's paint order a function of another surface's node count — the
			exact non-determinism the explicit walk exists to remove, reintroduced one
			level up. So the head of the file may declare the module table and the two
			immutable module locals it imports, and nothing else. ]]
		local source = stripComments(fs.readFile(MODULE_PATH))
		local head = string.match(source, "^(.-)\nfunction z_order%.new") :: string
		assert(head ~= nil, "no `function z_order.new` to split on")
		local decls: { string } = {}
		for line in string.gmatch(head, "\n([^\n]*)") do
			local trimmed = string.match(line, "^%s*(.-)%s*$") :: string
			if string.match(trimmed, "^local ") ~= nil then
				table.insert(decls, trimmed)
			end
		end
		expect(decls).toEqual({
			'local authority = require("./authority")',
			'local layoutNode = require("./layout_node")',
			"local effectiveHitFloor = layoutNode.effectiveHitFloor",
			"local z_order = {}",
		})
		-- ...and none of the four is ever reassigned
		local reassigned = 0
		for _, name in { "authority", "layoutNode", "effectiveHitFloor", "z_order" } do
			for _ in string.gmatch(source, `\n{name} = `) do
				reassigned += 1
			end
		end
		expect(`reassigned:{reassigned}`).toBe("reassigned:0")
		-- NEGATIVE CONTROL: the reassignment scan sees one
		local seen = 0
		for _ in string.gmatch("\nz_order = {}\n", "\nz_order = ") do
			seen += 1
		end
		expect(`control:{seen}`).toBe("control:1")
	end)

	it("NOTHING LEFT BEHIND: the renderer kept no copy of the walk", function()
		local rendererBody = stripComments(fs.readFile(RENDERER_PATH))
		for _, needle in { "local function orderedChildren", "local function walkZ", "adapter.setZOrder(" } do
			expect(`{needle} in the renderer:{string.find(rendererBody, needle, 1, true) ~= nil}`).toBe(
				`{needle} in the renderer:false`
			)
		end
		--[[ ...AND THE FORWARD LOCAL IS STILL THERE AND STILL ASSIGNED ONCE. `syncZOrder`
			is declared near the top of `renderer.attach` because three call sites — the
			structural sync, the commit's overhang lift and the translate lane — are
			above the line that fills it. The seam changed WHAT fills it, not the shape.

			ITS SIGNATURE IS PART OF THE PIN (Plan C, C5): the walk takes the bounded
			structural sync's ROOT LIST, `nil` meaning the whole tree. It is here so that a
			future change back to a no-argument call has to come through this line rather
			than past it. ]]
		local decls, fills = 0, 0
		for _ in
			string.gmatch(rendererBody, "\n\tlocal syncZOrder: %(roots: { { path: string, node: any } }%?%) %-> %(%)\n")
		do
			decls += 1
		end
		for _ in string.gmatch(rendererBody, "\n\tsyncZOrder = zOrder%.sync\n") do
			fills += 1
		end
		expect(`declared:{decls} filled:{fills}`).toBe("declared:1 filled:1")
	end)

	it("the module is in `tests/lib/renderer_source`'s PARTS, so the prop scans still see it", function()
		--[[ THE INSTRUMENT THAT GOES BLIND SILENTLY. Several pins count
			`adapter.setProp(`/`setZOrder(` over "the renderer", and that phrase means
			`renderer_source.all()` — a hand list of parts. This module holds the only
			`adapter.setZOrder(` call in `src/render/`, so a part missing here would take
			the z pins' denominator to zero and every one of them would still pass. ]]
		local parts = stripComments(fs.readFile("tests/lib/renderer_source.luau"))
		expect(`z_order in PARTS:{string.find(parts, '"src/render/z_order.luau"', 1, true) ~= nil}`).toBe(
			"z_order in PARTS:true"
		)
		local renderer_source = require("./lib/renderer_source")
		local joined = (renderer_source :: any).all()
		local writes = 0
		for _ in string.gmatch(joined, "adapter%.setZOrder%(") do
			writes += 1
		end
		expect(`setZOrder writes across the parts:{writes}`).toBe("setZOrder writes across the parts:1")
	end)
end)
