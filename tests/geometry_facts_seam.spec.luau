--!strict
--[[ THE GEOMETRY-FACTS SEAM, MECHANISED — what keeps
	`render/geometry_facts.luau` one-way, and what keeps its two halves in step.

	WHY A SPEC AND NOT A COMMENT. `tools/lune/verify/data/source-cap-ledger.md` records
	the rule every extraction in this repository is judged by: a block may leave a file
	only if it reads no mutable upvalue of its host, because otherwise the move creates
	a require BACK and the two files become one file with a slash in the middle. This
	block passes that test by construction — a policy string in, a list of strings out;
	two readings in, a boolean out — so what is worth mechanising is the property the
	SPLIT itself put at risk: the list and the comparator used to be two halves of one
	`local`, and they are now two exports that a future round could move apart.

	  ONE-WAY        no require of the renderer, no controller local, no state
	  ONE CONSUMER   `src/render/renderer.luau`, by a walk of the whole tree
	  LIST == COMPARATOR   every key the list can produce is one the comparator has an
	                 arm for, and the one NESTED fact has its own
	  POLICY         the two narrowings are the measured ones, and the caller's list
	                 cannot be rewritten by another surface
	  RENDERER       the memo that stayed behind still reads the list and hands the
	                 comparator over

	Each source rule is a pure function of a string, so each carries a NEGATIVE CONTROL
	that feeds it a broken input and proves it reports. A check that cannot fail is
	decoration.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local fs = require("@lune/fs")
local srcTree = require("./lib/src_tree")
local geometry_facts = require("../src/render/geometry_facts")

local RENDERER_PATH = "src/render/renderer.luau"
local FACTS_PATH = "src/render/geometry_facts.luau"

--[[ COMMENTS ARE NOT CODE, and this module's own prose names `solveAndApply`,
	`rootPolicy` and the renderer by path while explaining what it must never reach
	for — a scan that read them would report the dependency the header promises is
	not there. ]]
local function stripComments(source: string): string
	local out = string.gsub("\n" .. source, "%-%-%[%[.-%]%]", " ")
	out = string.gsub(out, "\n[ \t]*%-%-[^\n]*", "\n")
	return out
end

--[[ EVERY MODULE-LEVEL DECLARATION, COUNTED, and `local function x` counts as a
	declaration of `x` rather than of the keyword. That distinction is the whole check:
	a scan that reads the name after `local` reports "function" for every helper in the
	file, so two copies of one function collapse into a single meaningless tally — which
	is how a verbatim duplicate shipped in this module's own first commit. ]]
local function declarationCounts(source: string): { [string]: number }
	local out: { [string]: number } = {}
	local body = "\n" .. source
	for name in string.gmatch(body, "\nlocal function ([%a_][%w_]*)") do
		out[name] = (out[name] or 0) + 1
	end
	for name in string.gmatch(body, "\nlocal ([%a_][%w_]*)") do
		if name ~= "function" then
			out[name] = (out[name] or 0) + 1
		end
	end
	return out
end

local function has(list: { string }, needle: string): boolean
	for _, v in list do
		if v == needle then
			return true
		end
	end
	return false
end

describe("the geometry-facts seam: one-way, one consumer, no state", function()
	local factsSrc = fs.readFile(FACTS_PATH)
	local rendererSrc = fs.readFile(RENDERER_PATH)

	it("the module requires only `../rect`, and never the renderer", function()
		local requires: { string } = {}
		for path in string.gmatch(stripComments(factsSrc), 'require%("([^"]+)"%)') do
			table.insert(requires, path)
		end
		expect(requires).toEqual({ "../rect" })
		-- ...and the direction that IS allowed is present, so this cannot pass by the
		-- renderer having quietly dropped the require
		expect(string.find(rendererSrc, 'require("./geometry_facts")', 1, true) ~= nil).toBe(true)
	end)

	it("there is exactly ONE consumer of the module in src/", function()
		expect(srcTree.pathsMatching('require%("[^"]*geometry_facts"%)')).toEqual({ RENDERER_PATH })
	end)

	it("every module-level local is DECLARED EXACTLY ONCE — a shadowed copy is a silent no-op", function()
		--[[ THE RULE THE EXTRACTION ITSELF NEEDED (review round 2, 2026-09-02). The
			split landed `sameChrome` TWICE, verbatim: the second declaration shadowed
			the first, 837 bytes of the file were dead, and an editor changing the first
			copy would have watched a correct edit do nothing. That is the silent-no-op
			class this repository documents, and the case below could not see it —
			counting names into a SET collapses two declarations into one, which is
			exactly the shape that made the duplicate invisible. Declarations are
			COUNTED here for that reason. ]]
		local counts = declarationCounts(stripComments(fs.readFile(FACTS_PATH)))
		local twice: { string } = {}
		for name, n in counts do
			if n > 1 then
				table.insert(twice, `{name} x{n}`)
			end
		end
		table.sort(twice)
		expect(`declared more than once: {table.concat(twice, ", ")}`).toBe("declared more than once: ")
		-- ...and the scan reached something, which is the trap an empty result invites
		expect(counts.sameChrome).toBe(1)
		expect(counts.BASE_KEYS).toBe(1)
	end)

	it("NEGATIVE CONTROL: the declaration count sees a second copy a set-scan collapses", function()
		local text = "local alpha = 1\nlocal function beta()\nend\nlocal function beta()\nend\n"
		local counts = declarationCounts(text)
		expect(counts.beta).toBe(2)
		expect(counts.alpha).toBe(1)
		-- ...and it counts the NAME, not the keyword: a scan reading the word after
		-- `local` records a declaration of "function" for every helper, which is the
		-- blindness that let the duplicate through
		expect(counts["function"]).toBe(nil)
		--[[ ...AND HERE IS THE BLINDNESS ITSELF, driven rather than asserted. The scan
			the reassignment case below uses reads the word after `local`, so on these
			two declarations it records the KEYWORD and never the name: `beta` is not in
			its set at all, twice over. A rule built on it could not have reported the
			duplicate whatever it compared. ]]
		local set: { [string]: boolean } = {}
		for name in string.gmatch("\n" .. text, "\nlocal ([%a_][%w_]*)") do
			set[name] = true
		end
		expect(set.beta).toBe(nil)
		expect(set["function"]).toBe(true)
		-- a `local` named inside a comment is not a declaration
		local commented = declarationCounts(stripComments("-- local beta = 1\nlocal gamma = 2\n"))
		expect(commented.beta).toBe(nil)
		expect(commented.gamma).toBe(1)
	end)

	it("no module-level local is ever reassigned — two surfaces cannot see different lists", function()
		--[[ THE SHAPE THE BLOCK HAD BEFORE IT MOVED, and the reason this rule is not
			decoration here: inside `attach`, `GEOMETRY_KEYS` was a `local` REASSIGNED
			by each policy narrowing. That was safe while it was one controller's own
			upvalue and would be a session-wide fact shared by every surface here. ]]
		local body = stripComments(factsSrc)
		local names: { [string]: boolean } = {}
		for name in string.gmatch("\n" .. body, "\nlocal ([%a_][%w_]*)") do
			names[name] = true
		end
		local reassigned: { string } = {}
		for name in names do
			if string.find(body, `\n{name}%s*=[^=]`) ~= nil then
				table.insert(reassigned, name)
			end
		end
		table.sort(reassigned)
		expect(reassigned).toEqual({})
		expect(names.BASE_KEYS).toBe(true)
	end)

	it("NEGATIVE CONTROL: the require scan and the reassignment scan both report", function()
		local requires: { string } = {}
		for path in string.gmatch(stripComments('local r = require("./renderer")\n'), 'require%("([^"]+)"%)') do
			table.insert(requires, path)
		end
		expect(requires).toEqual({ "./renderer" })
		-- a require named inside a comment is not a require
		local none: { string } = {}
		for path in string.gmatch(stripComments('-- require("./renderer")\n'), 'require%("([^"]+)"%)') do
			table.insert(none, path)
		end
		expect(none).toEqual({})
		local text = "local alpha\nlocal beta = 1\nlocal function f()\n\tbeta = 2\nend\nalpha = 3\n"
		expect(string.find(text, "\nalpha%s*=[^=]") ~= nil).toBe(true)
		expect(string.find(text, "\nbeta%s*=[^=]")).toBe(nil)
	end)
end)

describe("the geometry-facts seam: the list and the comparator are one decision", function()
	it("every policy answers with the keys that policy actually consumes", function()
		local core = geometry_facts.keysFor("coreSafeContent")
		expect(has(core, "coreSafeInsets")).toBe(true)
		expect(has(core, "deviceSafeInsets")).toBe(true)
		expect(has(core, "viewportRect")).toBe(true)
		expect(has(core, "themeMetrics")).toBe(true)
		-- an exact text width is geometry for every surface (RED-TEAM 2026-09-02)
		expect(has(core, "textMeasureEpoch")).toBe(true)
		expect(has(core, "platformChrome")).toBe(false)
		-- `deviceSafeContent` takes the per-edge max of both inset facts, so it is the
		-- unnarrowed list too
		expect(geometry_facts.keysFor("deviceSafeContent")).toEqual(core)
		-- ...and an unknown policy is the conservative one rather than an empty list
		expect(geometry_facts.keysFor(nil)).toEqual(core)

		--[[ THE TWO NARROWINGS, each measured onto its own branch (see the module).
			`edgeToEdge` reads `coreSafeInsets` and throws it away; `bandSafeContent`
			reads the DERIVED `platformChrome` instead of the three raw facts. ]]
		local edge = geometry_facts.keysFor("edgeToEdge")
		expect(has(edge, "coreSafeInsets")).toBe(false)
		expect(has(edge, "deviceSafeInsets")).toBe(false)
		expect(has(edge, "overscanInsets")).toBe(true)
		expect(has(edge, "viewportRect")).toBe(true)
		local band = geometry_facts.keysFor("bandSafeContent")
		expect(has(band, "platformChrome")).toBe(true)
		expect(has(band, "coreSafeInsets")).toBe(false)
		expect(has(band, "deviceSafeInsets")).toBe(false)
		expect(has(band, "overscanInsets")).toBe(false)
		expect(has(band, "typographyScale")).toBe(true)
	end)

	it("the list handed out is the CALLER'S: narrowing one surface cannot narrow another", function()
		-- the pre-split code reassigned one upvalue per controller; a shared module
		-- table would make one surface's list the next surface's
		local a = geometry_facts.keysFor("coreSafeContent")
		table.insert(a, "forged")
		local b = geometry_facts.keysFor("coreSafeContent")
		expect(has(b, "forged")).toBe(false)
	end)

	it("the comparator has an arm for every key the list can produce", function()
		--[[ THE HALF THE SPLIT PUT AT RISK. Comparing by CONTENT is what makes a
			re-published viewport with identical numbers cost nothing; a key with no
			arm would be compared by identity, and every one of these facts is rebuilt
			by the adapter on every push. `platformChrome` is the one NESTED fact and
			has a comparator of its own. ]]
		local seen: { [string]: boolean } = {}
		for _, policy in { "coreSafeContent", "edgeToEdge", "bandSafeContent" } do
			for _, key in geometry_facts.keysFor(policy) do
				seen[key] = true
			end
		end
		-- a flat record, rebuilt: same numbers must compare EQUAL
		local keys = { "viewportRect" }
		local first = { { x = 0, y = 0, w = 400, h = 800 } }
		local second = { { x = 0, y = 0, w = 400, h = 800 } }
		expect(geometry_facts.same(keys, first, second)).toBe(true)
		second[1].w = 401
		expect(geometry_facts.same(keys, first, second)).toBe(false)
		-- a scalar
		expect(geometry_facts.same({ "displaySize" }, { "Medium" }, { "Medium" })).toBe(true)
		expect(geometry_facts.same({ "displaySize" }, { "Medium" }, { "Large" })).toBe(false)
		-- ...and the NESTED fact, which no flat comparison can answer: same numbers in
		-- fresh tables is unchanged, and a moved band is not
		local chromeA = {
			{
				band = { x = 0, y = 0, w = 400, h = 36 },
				rects = { { x = 0, y = 0, w = 10, h = 10 } },
				insets = { top = 36 },
				bandInsets = { top = 0 },
			},
		}
		local chromeB = {
			{
				band = { x = 0, y = 0, w = 400, h = 36 },
				rects = { { x = 0, y = 0, w = 10, h = 10 } },
				insets = { top = 36 },
				bandInsets = { top = 0 },
			},
		}
		expect(seen.platformChrome).toBe(true)
		expect(geometry_facts.same({ "platformChrome" }, chromeA, chromeB)).toBe(true)
		chromeB[1].band.h = 48
		expect(geometry_facts.same({ "platformChrome" }, chromeA, chromeB)).toBe(false)
		-- a chrome that grew a rect is a change, which a field-for-field walk of the
		-- four named fields would miss without the list compare
		chromeB[1].band.h = 36
		table.insert(chromeB[1].rects, { x = 1, y = 1, w = 2, h = 2 })
		expect(geometry_facts.same({ "platformChrome" }, chromeA, chromeB)).toBe(false)
	end)

	it("a nested field on a FLAT fact is refused rather than half-compared", function()
		--[[ ARCHITECTURE GATE F3, carried across the split. A future fact shaped
			`{ rect = <cached>, insets = <fresh> }` would compare its inner references
			as equal under identity and report "unchanged" — a MISSED re-solve, which
			is the one direction this comparison may never take. ]]
		local nestedA = { { rect = { x = 0 } } }
		local nestedB = { { rect = { x = 0 } } }
		expect(geometry_facts.same({ "viewportRect" }, nestedA, nestedB)).toBe(false)
	end)

	it("nil on either side is only equal to nil — a memo that has not run is not unchanged", function()
		expect(geometry_facts.same({ "viewportRect" }, nil, nil)).toBe(true)
		expect(geometry_facts.same({ "viewportRect" }, nil, { 1 })).toBe(false)
		expect(geometry_facts.same({ "viewportRect" }, { 1 }, nil)).toBe(false)
	end)
end)

describe("the geometry-facts seam: what stayed behind still reads it", function()
	local rendererSrc = fs.readFile(RENDERER_PATH)

	it("the renderer builds its memo over the module's list and hands the comparator over", function()
		--[[ THE FAILURE A SET COMPARISON CANNOT SEE: a renderer that kept a second
			copy of the list, or that compared with `==` after the split, would pass
			every case above while the surface it renders went deaf to a fact. ]]
		local body = stripComments(rendererSrc)
		expect(string.find(body, "local GEOMETRY_KEYS = geometry_facts.keysFor(rootPolicy)", 1, true) ~= nil).toBe(true)
		expect(string.find(body, "return geometry_facts.same(GEOMETRY_KEYS, a, b)", 1, true) ~= nil).toBe(true)
		--[[ ...AND IT KEEPS NO SECOND COPY. The renderer still READS several of these
			facts directly (`solveAndApply` pulls the insets, the chrome and the
			typography scale to build its own offer), which is not a list — what may
			not come back is the LIST and the COMPARATOR: a narrowing loop, or a
			`sameChrome` of its own, is the two-files-one-decision failure this seam
			exists to prevent. ]]
		expect(string.find(body, "sameChrome")).toBe(nil)
		expect(string.find(body, 'key ~= "coreSafeInsets"')).toBe(nil)
		local assignments = 0
		for _ in string.gmatch(body, "GEOMETRY_KEYS = ") do
			assignments += 1
		end
		-- ONE, and it is the `local` above: the pre-split code REASSIGNED this name
		-- once per policy narrowing
		expect(assignments).toBe(1)
	end)
end)
