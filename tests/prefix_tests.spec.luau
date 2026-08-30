--!strict
--[[ A PREFIX TEST THAT COMPARES THE WRONG NUMBER OF CHARACTERS.

	`string.sub(s, 1, N) == "<literal>"` is a comparison between a string of
	length N and a literal of length #literal. When the two disagree the
	comparison is not merely wrong, it is CONSTANT: it can never be true (or,
	with `~=`, never false), so the branch behind it is dead and nothing about
	the program's shape says so. It is green in every linter, it type-checks, and
	the suite stays exactly as green as it was.

	THE DEFECT CLASS IS A RENAME'S FAVOURITE HIDING PLACE, and this framework has
	paid for it twice in one week. The classification tags were renamed
	`luau-*` -> `facet-*` across 395 occurrences (`36d1883`, 2026-08-18). `"luau-"`
	is five characters and `"facet-"` is six, so the sweep rewrote every literal
	and left every length: `git log -S 'string.sub(tag, 1, 5)'` returns only the
	initial commit. The same rename moved the roots `LuauUI_<id>` -> `Facet_<id>`
	— six characters to five — and left two more.

	WHAT THE THREE OF THEM DID, each found by this file's own scan:

	* `src/client/screen_target.luau`'s `syncTags` — the ONE function that owns
	  every `facet-*` tag on an instance — could no longer REMOVE one. Its removal
	  loop went dead and the function became purely additive, so every
	  classification tag a node ever wore stayed on it for the node's whole life:
	  surface, selection, role, toggle, error, shape and typography. A picker
	  segment set to `surface = "plain"` kept `facet-surface-control` and the
	  sheet painted an opaque plate over the tab indicator behind it.
	* `tools/studio/device_matrix.luau` skipped EVERY tree instead of skipping
	  the platform's, so the five-view matrix judged an empty set.
	* `examples/gallery/scenarios/runner.luau` counted Facet's own roots as
	  FOREIGN, so the M3 instance census reported zero GuiObjects for the
	  framework and filed its own `Facet_PerfWorkload` under other people's.

	SO THE RULE IS MECHANISED RATHER THAN REMEMBERED. Every prefix comparison in
	`src/`, `tools/` and `examples/` must compare as many characters as the
	literal it compares against — and the way to be sure of that forever is to
	stop writing the number at all: `string.sub(s, 1, #PREFIX) == PREFIX` cannot
	disagree with itself, which is the idiom `screen_chrome`'s icon-tag loop was
	already using one file over.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")
local adapter_source = require("./lib/adapter_source")
local sheet_model = require("../src/tokens/sheet_model")
local tag_sync = require("../src/render/tag_sync")

-- `tests/` is deliberately absent: a spec is where a synthetic violation is
-- SUPPOSED to appear (the negative control below writes one), and a scanner that
-- reads its own fixtures reports its own props as defects.
local SCANNED = { "src", "tools", "examples" }

type Violation = {
	file: string,
	line: number,
	compared: number,
	literal: string,
}

--[[ THE SCAN, over one file's text.

	FOUR SPELLINGS ARE READ, because a rule that only sees one of them teaches
	people to write another: `string.sub(s, 1, N)` and the method form
	`s:sub(1, N)` (two live sites use it — `roblox_env`'s `"Gamepad"` and
	`studio_sync`'s `"/file/"`, both correct), each compared in either operand
	order.

	COMMENTS ARE PROSE AND ARE SKIPPED — BLOCK COMMENTS TOO. That half was
	learned the same day it was written: `src/render/tag_sync.luau`'s header
	QUOTES the defective line inside a long-bracket block comment to explain it,
	and a line-comment-only skip reported the module's own explanation as the
	defect it was explaining. Long-bracket levels (`--[=[`) are handled; a `--` inside a
	string literal is not, which is a stated hole rather than a hidden one — no
	file in the tree has one today and the anti-vacuity count below would move if
	that changed.

	A literal containing a BACKSLASH is skipped and COUNTED: `"\n"` is two
	characters of source and one byte of string, so `#literal` measured on the
	source text would be a false accusation. The count is asserted below, so the
	day one appears it is a visible number rather than a silent hole.
]]
local PATTERNS = {
	'string%.sub%(.-,%s*1,%s*(%d+)%)%s*[=~]=%s*"(.-)"',
	'[%w_%.%]%)]:sub%(%s*1,%s*(%d+)%)%s*[=~]=%s*"(.-)"',
}
local MIRRORED = {
	'"(.-)"%s*[=~]=%s*string%.sub%(.-,%s*1,%s*(%d+)%)',
	-- the receiver is a whole identifier chain here, not one character: unlike the
	-- forward form there is nothing after it for the matcher to scan back from
	'"(.-)"%s*[=~]=%s*[%w_%.%[%]%(%)]*:sub%(%s*1,%s*(%d+)%)',
}

-- the line with every comment removed. `inBlock` is the long-comment level
-- carried in from the previous line, or nil.
local function codeOf(line: string, inBlock: string?): (string, string?)
	local code, pos, level = "", 1, inBlock
	while pos <= #line do
		if level ~= nil then
			local closeAt, closeEnd = string.find(line, "]" .. level .. "]", pos, true)
			if closeAt == nil then
				return code, level
			end
			pos = (closeEnd :: number) + 1
			level = nil
		else
			local openAt, openEnd, eqs = string.find(line, "%-%-%[(=*)%[", pos)
			local lineAt = string.find(line, "--", pos, true)
			if openAt ~= nil and (lineAt == nil or openAt <= lineAt) then
				code ..= string.sub(line, pos, (openAt :: number) - 1)
				pos = (openEnd :: number) + 1
				level = eqs
			elseif lineAt ~= nil then
				code ..= string.sub(line, pos, (lineAt :: number) - 1)
				return code, nil
			else
				code ..= string.sub(line, pos)
				return code, nil
			end
		end
	end
	return code, level
end

local function scan(text: string, file: string): ({ Violation }, number, number)
	local violations: { Violation } = {}
	local considered, skippedEscapes = 0, 0
	local lineNo = 0
	local inBlock: string? = nil
	for line in string.gmatch(text .. "\n", "(.-)\n") do
		lineNo += 1
		local code: string
		code, inBlock = codeOf(line, inBlock)
		local function record(compared: string, literal: string)
			if string.find(literal, "\\", 1, true) ~= nil then
				skippedEscapes += 1
				return
			end
			considered += 1
			if #literal ~= tonumber(compared) then
				table.insert(violations, {
					file = file,
					line = lineNo,
					compared = tonumber(compared) :: number,
					literal = literal,
				})
			end
		end
		for _, pattern in PATTERNS do
			for compared, literal in string.gmatch(code, pattern) do
				record(compared, literal)
			end
		end
		for _, pattern in MIRRORED do
			for literal, compared in string.gmatch(code, pattern) do
				record(compared, literal)
			end
		end
	end
	return violations, considered, skippedEscapes
end

local function walk(dir: string, out: { string })
	if not fs.isDir(dir) then
		return
	end
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			walk(path, out)
		elseif string.match(name, "%.luau$") ~= nil then
			table.insert(out, path)
		end
	end
end

describe("a prefix test cannot disagree with the prefix it tests (rename fallout)", function()
	it("no comparison in src/, tools/ or examples/ counts differently from its own literal", function()
		local files: { string } = {}
		for _, dir in SCANNED do
			walk(dir, files)
		end
		table.sort(files)
		local all: { Violation } = {}
		local considered, skippedEscapes = 0, 0
		for _, path in files do
			local v, c, s = scan(fs.readFile(path), path)
			for _, one in v do
				table.insert(all, one)
			end
			considered += c
			skippedEscapes += s
		end

		-- ANTI-VACUITY, both halves. A scan that read no files, or a refactor that
		-- retired the idiom everywhere, would report "no violations" over nothing.
		expect(#files >= 300).toBe(true)
		expect(`prefix comparisons found: {considered >= 15}`).toBe("prefix comparisons found: true")
		-- ...and the escape hole is a NUMBER, not an assumption
		expect(`literals skipped for escapes: {skippedEscapes}`).toBe("literals skipped for escapes: 0")

		local report: { string } = {}
		for _, v in all do
			table.insert(
				report,
				`{v.file}:{v.line} compares {v.compared} characters against "{v.literal}" (#{#v.literal})`
			)
		end
		expect(`violations:\n{table.concat(report, "\n")}`).toBe("violations:\n")
	end)

	it("the scan BITES — every spelling, and prose in neither kind of comment", function()
		-- The rule this file exists for, injected in all four spellings, with two
		-- CORRECT neighbours that must not be reported and two comment forms that
		-- must not be either. The block-comment lines are the ones that matter:
		-- the module this defect now lives in quotes the bad line to explain it.
		local synthetic = table.concat({
			'if string.sub(tag, 1, 5) == "facet-" then',
			'if "Facet" ~= string.sub(tree.root, 1, 6) then',
			'if name:sub(1, 4) == "Gamepad" then',
			'if "/file/" == path:sub(1, 3) then',
			'if string.sub(target, 1, 6) == "@self/" then',
			'-- string.sub(tag, 1, 9) == "facet-" is quoted PROSE and must not count',
			'--[[ ...nor must a BLOCK comment quoting string.sub(tag, 1, 9) == "facet-"',
			'\tacross two lines: x:sub(1, 9) == "facet-" ]]',
			'if path:sub(1, 6) == "/file/" then',
		}, "\n")
		local found, considered, skipped = scan(synthetic, "synthetic")
		-- four bad, two good, nothing from either comment
		expect(considered).toBe(6)
		expect(skipped).toBe(0)
		expect(#found).toBe(4)
		expect(`{found[1].line}:{found[1].compared}:{found[1].literal}`).toBe("1:5:facet-")
		expect(`{found[2].line}:{found[2].compared}:{found[2].literal}`).toBe("2:6:Facet")
		expect(`{found[3].line}:{found[3].compared}:{found[3].literal}`).toBe("3:4:Gamepad")
		expect(`{found[4].line}:{found[4].compared}:{found[4].literal}`).toBe("4:3:/file/")
	end)
end)

describe("the adapter's facet-* tag ownership is one named fact (SCREEN-X)", function()
	it("the removal loop DELEGATES — the adapter hand-rolls no prefix test at all", function()
		--[[ The decision moved OUT of the adapter entirely (`render/tag_sync`), so
			what this pin asks of the adapter is that it holds no second copy: the
			live source calls the shared plan and spells no `facet-` prefix
			comparison of its own. The predicate itself is behaviour, not text, and
			`tests/tag_sync.spec.luau` drives it. ]]
		local source = adapter_source.live()
		expect(string.find(source, "tag_sync.diff(CollectionService:GetTags(instance), desired)", 1, true) ~= nil).toBe(
			true
		)
		expect(string.find(source, 'string.sub(tag, 1, 5) == "facet-"', 1, true) ~= nil).toBe(false)
		-- no hand-rolled prefix test of ANY length survives in the adapter
		expect(string.match(source, 'string%.sub%(tag,%s*1,%s*%d+%)%s*[=~]=%s*"facet') == nil).toBe(true)
		-- ...and the shared ruling is the one it reaches for
		expect(tag_sync.PREFIX).toBe("facet-")
	end)

	it("every tag the classifier can mint is one that predicate claims", function()
		--[[ THE CROSS-MODULE HALF. `sheet_model.classifyTags` MINTS the tags and
			the adapter's loop is the only thing that removes them, so a rename that
			moved one and not the other would leave the same dead branch by another
			route. Driven over the real classifier rather than over `TAGS`, because
			the composed tags (`facet-surface-<name>`, `facet-type-<role>`) are
			built at classification time and are exactly the ones that went sticky. ]]
		local prefix = tag_sync.PREFIX

		local dressed = sheet_model.classifyTags({
			surface = "control",
			interactive = true,
			selected = true,
			buttonRole = "destructive",
			typeRole = "label",
			shape = "circle",
			errorState = true,
			toggleOn = true,
		})
		local plain = sheet_model.classifyTags({ surface = nil, interactive = false })

		local minted, unclaimed = 0, {}
		for tag in dressed do
			minted += 1
			if string.sub(tag, 1, #prefix) ~= prefix then
				table.insert(unclaimed, tag)
			end
		end
		expect(`minted {minted >= 8}`).toBe("minted true")
		expect(table.concat(unclaimed, ",")).toBe("")

		-- THE REMOVAL SET IS REAL: dressing a node and then plainly re-classifying
		-- it leaves tags that MUST come off, and the predicate claims every one.
		local mustRemove: { string } = {}
		for tag in dressed do
			if plain[tag] ~= true then
				table.insert(mustRemove, tag)
			end
		end
		table.sort(mustRemove)
		expect(`tags that must be removed: {#mustRemove >= 8}`).toBe("tags that must be removed: true")
		for _, tag in mustRemove do
			expect(`{tag} claimed:{string.sub(tag, 1, #prefix) == prefix}`).toBe(`{tag} claimed:true`)
		end

		--[[ ...AND THE OLD TEST CLAIMED NONE OF THEM. Kept as an executable record
			of why the defect was invisible: `string.sub(tag, 1, 5)` is `"facet"`,
			which is not `"facet-"`, so the removal loop matched nothing at all
			rather than matching the wrong thing. A dead branch and a wrong branch
			fail very differently, and this is the shape that leaves no symptom
			anywhere near the code. ]]
		for _, tag in mustRemove do
			expect(`{tag} under the old five: {string.sub(tag, 1, 5) == "facet-"}`).toBe(
				`{tag} under the old five: false`
			)
		end
	end)
end)
