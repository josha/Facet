--!strict
--[[ THE RECT_READS SEAM, MECHANISED — what keeps `render/rect_reads.luau` one-way.

	THE LIVE SEAM (Plan C, T1). Unlike every prior renderer split, this one is not
	only an extraction: it is the seam Plan C's own host-space work (T3, T5) will
	change next, taken FIRST and in its own commit. The four geometry reads —
	`rectOf`, `scrollShift`, `screenRectOf`, `paintedRectIn` — read `lastRects`,
	`handles` and `scrollHostOf`, three tables the renderer mutates IN PLACE and
	never rebinds (`dispose` clears them with `table.clear` for exactly this
	reason — `tests/lib/renderer_source.luau`'s own header names the pattern), plus
	`adapter` and one function, `presentationShift`. The host-space maps and
	helpers T3/T5 will fill (`hostSpaceOf`, `spaceHosts`, `spaceHostHasPath`,
	`pathHostOf`, `hostOriginOf`, `originIn`, `noteUnder`, `noteFromHost`,
	`invalidateOrigins`, `clearHosts`, `dropPath`) are declared here EMPTY, so this
	round's behaviour must be byte-identical to today's: with every map empty,
	`hostOriginOf`/`originIn` answer `0, 0` on every path and `rectOf` returns the
	STORED table, unchanged — `slider.luau:183-185` compares it by identity.

	Each source rule is a pure function of a string, so each carries a NEGATIVE
	CONTROL that feeds it a broken input and proves it reports. A check that cannot
	fail is decoration. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local fs = require("@lune/fs")

local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local customFactory = require("../src/core/custom")
local fake_target = require("./lib/fake_target")

local RECT_READS_PATH = "src/render/rect_reads.luau"
local RENDERER_PATH = "src/render/renderer.luau"

local BIND_LINE = "local geometry = rect_reads.new({ adapter = adapter, handles = handles, "
	.. "lastRects = lastRects, scrollHostOf = scrollHostOf, presentationShift = presentationShift })"

local function px(n: number): any
	return { type = "fixed", px = n }
end

--[[ COMMENTS ARE NOT CODE, exactly as `stack_seam`'s own copy of this helper says:
	this module's own header names every crossing name while explaining what it
	must never reach for, and a scan that counted them would report the exact
	dependency the header promises it does not have. ]]
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

-- every `<name>.<field>` read of one receiver, comments stripped
local function fieldsRead(source: string, receiver: string): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for key in string.gmatch(stripComments(source), receiver .. "%.([%a_][%w_]*)") do
		out[key] = true
	end
	return out
end

describe("the rect_reads seam: a CLOSED Deps record, read == declared", function()
	it("`rect_reads.new` loads and is a function", function()
		local rect_reads = require("../src/render/rect_reads")
		expect(type(rect_reads.new)).toBe("function")
	end)

	it("the fields the body READS off `deps` are exactly the fields the type DECLARES", function()
		--[[ THE ONE-WAY TEST ITSELF, as a set comparison rather than a promise — the
			same shape `stack_seam`'s own copy of this case takes, and `solver.luau`'s
			note beside `COMPOSITION_DEPS` states the reason plainly: "a spare field in
			it is a false statement". ]]
		local src = fs.readFile(RECT_READS_PATH)
		local declared: { [string]: boolean } = {}
		local block = string.match(stripComments(src), "export type Deps = {(.-)\n}")
		assert(block ~= nil, "the Deps type block was not found")
		for name in string.gmatch(block :: string, "\n\t([%a_][%w_]*):") do
			declared[name] = true
		end
		local CLOSED = { "adapter", "handles", "lastRects", "presentationShift", "scrollHostOf" }
		expect(sorted(declared)).toEqual(CLOSED)
		expect(sorted(fieldsRead(src, "deps"))).toEqual(CLOSED)
	end)

	it("NEGATIVE CONTROL: the Deps scan reports a changed set", function()
		local fakeType = "export type Deps = {\n\tadapter: any,\n\tghost: any,\n}\n"
		local declared: { [string]: boolean } = {}
		local block = string.match(stripComments(fakeType), "export type Deps = {(.-)\n}") :: string
		for name in string.gmatch(block, "\n\t([%a_][%w_]*):") do
			declared[name] = true
		end
		expect(sorted(declared)).toEqual({ "adapter", "ghost" })
		expect(sorted(fieldsRead("local x = deps.ghost\n", "deps"))).toEqual({ "ghost" })
	end)
end)

describe("the rect_reads seam: it WRITES no field of `deps`", function()
	local src = fs.readFile(RECT_READS_PATH)
	local body = stripComments(src)

	it("assigns no field of `deps`", function()
		--[[ THE READ-vs-WRITE HALF OF THE ONE-WAY TEST. A module that only reads its
			host's state can be moved; one that WRITES it has to be trusted to write the
			same thing at the same moment, which is a different and much weaker claim.
			This module owns every map it touches (`hostSpaceOf`, `originCache`, …) —
			none of them is a `deps` field — so it assigns nothing of its host's at all. ]]
		local assigned: { string } = {}
		for recv, field in string.gmatch(body, "([%a_][%w_]*)%.([%a_][%w_]*)%s*[%+%-]?=[^=]") do
			if recv == "deps" then
				table.insert(assigned, `{recv}.{field}`)
			end
		end
		expect(assigned).toEqual({})
	end)

	it("inserts into no field of `deps`", function()
		local inserts: { [string]: boolean } = {}
		for target in string.gmatch(body, "table%.insert%(%s*([%a_][%w_%.]*)") do
			if string.sub(target, 1, 5) == "deps." then
				inserts[target] = true
			end
		end
		expect(sorted(inserts)).toEqual({})
	end)

	it("NEGATIVE CONTROL: the write scans both report", function()
		local fake = "\ndeps.measured += 1\ntable.insert(deps.list, 1)\n"
		local assigned: { string } = {}
		for recv, field in string.gmatch(stripComments(fake), "([%a_][%w_]*)%.([%a_][%w_]*)%s*[%+%-]?=[^=]") do
			if recv == "deps" then
				table.insert(assigned, `{recv}.{field}`)
			end
		end
		expect(assigned).toEqual({ "deps.measured" })
		local inserts: { [string]: boolean } = {}
		for target in string.gmatch(stripComments(fake), "table%.insert%(%s*([%a_][%w_%.]*)") do
			if string.sub(target, 1, 5) == "deps." then
				inserts[target] = true
			end
		end
		expect(sorted(inserts)).toEqual({ "deps.list" })
	end)
end)

describe("the rect_reads seam: the renderer binds it, and keeps no copy", function()
	it("the renderer carries the char-for-char bind line", function()
		local rendererSrc = fs.readFile(RENDERER_PATH)
		expect(string.find(rendererSrc, BIND_LINE, 1, true) ~= nil).toBe(true)
	end)

	it("the renderer keeps no local definition of the four moved functions", function()
		--[[ THE FAILURE THIS REPOSITORY HAS ALREADY PAID FOR ONCE: a block "moved" by
			copying, leaving the host's version live and the two drifting. ]]
		local rendererSrc = fs.readFile(RENDERER_PATH)
		expect(string.find(rendererSrc, "local function screenRectOf", 1, true)).toBe(nil)
		expect(string.find(rendererSrc, "local function scrollShift", 1, true)).toBe(nil)
		expect(string.find(rendererSrc, "local function paintedRectIn", 1, true)).toBe(nil)
		expect(string.find(rendererSrc, "local function rectOf", 1, true)).toBe(nil)
	end)

	it("NEGATIVE CONTROL: the bind-line and leftover-definition scans both report", function()
		local fakeMissingBind = "local geometry = rect_reads.new({ adapter = adapter })\n"
		expect(string.find(fakeMissingBind, BIND_LINE, 1, true)).toBe(nil)
		local fakeLeftover = "\tlocal function rectOf(path: string): any\n\t\treturn lastRects[path]\n\tend\n"
		expect(string.find(fakeLeftover, "local function rectOf", 1, true) ~= nil).toBe(true)
	end)
end)

describe("the rect_reads seam: behaviour is unchanged with the host maps empty", function()
	it("`screenRectOf` minus `rectOf` is minus the scroll position, exactly as at HEAD", function()
		--[[ THE ONE BEHAVIOURAL CASE. Built by hand — `customFactory.new()` /
			`environment.new` / `mountLib.mount` / `fake_target.new()` /
			`renderer.attach`, the world every spec in this repository builds this way
			(`tests/layout_prop_dirt.spec.luau:395-422`) — with a ScrollView ancestor so
			`scrollShift` has a host to walk. With `hostSpaceOf` empty (T1's whole
			point), `hostOriginOf` contributes `0, 0` on every path, so the only
			difference between the two reads is the scroll shift `scrollTo` applies —
			the SAME NUMBER the pre-seam renderer returned, pinned as a literal. ]]
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 300, h = 200 })
		local bp = UI.ScrollView({
			id = "Scroll",
			axis = "y",
			width = px(300),
			height = px(200),
			children = {
				UI.VStack({
					id = "Content",
					width = px(300),
					height = px(600),
					children = {
						UI.Box({ id = "Item", width = px(40), height = px(40) }),
					},
				}),
			},
		})
		local root = mountLib.mount(core, UI.Screen({ id = "S", children = { bp } }))
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		local path = "/S/Scroll/Content/Item"
		local before = controller.rectOf(path)
		expect(before ~= nil).toBe(true)
		controller.scrollTo("/S/Scroll", { x = 0, y = 40 })
		local screen = controller.screenRectOf(path)
		local plain = controller.rectOf(path)
		expect(plain).toBe(before) -- IDENTITY: an empty host chain returns the stored table
		expect(screen.y - plain.y).toBe(-40)
		expect(screen.x - plain.x).toBe(0)
	end)
end)
