--!strict
-- EXAMPLE PROPERTY-AUTHORITY DRIFT LINT (roadmap Step 10,
-- docs/plans/example-quality-pass.md §"Theme coverage and drift prevention").
--
-- Its sibling `check_theme_drift.luau` guards the REUSABLE framework surface and
-- deliberately exempts examples, on the stated ground that "an app author's
-- literal is a legitimate opt-out". That is right for an app. It is wrong for the
-- tutorial gallery, whose whole job is to demonstrate the framework — and the
-- 2026-08-06 play audit measured what the exemption bought: all seven examples
-- painted `textSize` 14/16/18/20/24/26/28 straight to the engine, so the theme
-- picker mounted beside them could not move a single letter of type.
--
-- THE PLAN ASKS FOR A CHECK THAT UNDERSTANDS PROPERTY AUTHORITY, not a grep that
-- bans every number: "It should fail on direct writes/literals for style-owned
-- properties, unknown semantic roles, or example adapter writes, while allowing
-- documented content and structural constants." So the vocabularies below are
-- READ FROM THE FRAMEWORK ITSELF — the typography roles from the theme package,
-- the tint roles from the styling module, the surface/role enums from the class
-- schema. A role this lint accepts is a role the renderer accepts, today, with no
-- restated list to go stale.
--
-- Four rules:
--   R1  a style-owned property assigned a NUMBER          (use a role/step/metric)
--   R2  a style-owned property assigned an UNKNOWN STRING (not in its closed set)
--   R3  a raw colour                                       (Color3 / #rrggbb / {r,g,b})
--   R4  an engine or adapter reach-around                  (Instance.new, GetService,
--                                                           adapter.setProp, …)
--
-- check(opts?) -> { ok, problems, violations, counts }. CLI: run this file directly.

local fs = require("@lune/fs")

local schema = require("../../src/blueprint_schema")
local themePackage = require("../../src/themes/package")
local styling = require("../../src/tokens/styling")

local checker = {}

-- WHAT IS SCANNED. The tutorial example modules only. `examples/gallery/client`
-- is the HOST that mounts them — it sets workspace attributes, reads Studio
-- attributes and owns the theme picker, all of which are legitimately engine
-- work — and `examples/gallery/scenarios` is verification tooling. The claim this
-- lint enforces is the plan's claim about EXAMPLES: "content/domain logic plus
-- declarative Facet composition".
local SCANNED_DIR = "examples/gallery/examples"
-- swiftui-reference-app-validation: the five clean-room proofs are held to the
-- same authority rules as the tutorials. Scanned recursively (proof folders
-- carry content/ and services/ subtrees).
local REFERENCE_DIR = "examples/reference"

-- ---- the vocabularies, read from the framework -----------------------------

local function setOf(list: { string }): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for _, name in list do
		out[name] = true
	end
	return out
end

local TYPE_ROLES = setOf(themePackage.TYPE_ROLES)
local TINT_ROLES = setOf(styling.TINT_ROLES)

-- the surface and text-role enums, taken from the class schema rather than
-- restated (a restated list is a list that goes stale)
local function enumOf(className: string, prop: string): { [string]: boolean }
	local classSpec = schema.forClass(className)
	assert(classSpec ~= nil, `check_example_drift: no class '{className}'`)
	local spec = (classSpec.props :: any)[prop]
	assert(spec ~= nil and spec.enum ~= nil, `check_example_drift: {className}.{prop} has no enum`)
	return setOf(spec.enum)
end

local SURFACES = enumOf("Box", "surface")
local TEXT_ROLES = enumOf("Text", "role")
local BUTTON_ROLES = enumOf("Button", "role")

-- the spacing steps a `metric` may name, plus the dotted-path form. Both rulings
-- live in the theme snapshot; this asks it rather than hardcoding "xs".."xl".
local themeSnapshot = require("../../src/themes/snapshot")
local function isMetricName(value: string): boolean
	local name = if string.sub(value, 1, 1) == "-" then string.sub(value, 2) else value
	return themeSnapshot.isSpaceStep(name) or themeSnapshot.isMetricPath(name)
end

-- ---- the rules --------------------------------------------------------------

-- R1: a style-owned property may not be a bare number. ZERO is exempt for the
-- spacing family, exactly as the framework lint has it: `padding = 0` is a
-- structural statement ("this container adds no spacing"), not a style value.
local NUMBER_RULES: { { pattern: string, what: string, zeroOk: boolean } } = {
	{ pattern = "textSize%s*=%s*%-?%d+", what = "textSize", zeroOk = false },
	{ pattern = "[^%w_]gap%s*=%s*%-?%d+", what = "gap", zeroOk = true },
	{ pattern = "rowGap%s*=%s*%-?%d+", what = "rowGap", zeroOk = true },
	{ pattern = "padding%s*=%s*%-?%d+", what = "padding", zeroOk = true },
	{ pattern = "[^%w_]px%s*=%s*%-?%d+", what = "dimension px", zeroOk = false },
	{ pattern = "[^%w_]min%s*=%s*%-?%d+", what = "dimension min", zeroOk = false },
	{ pattern = "[^%w_]max%s*=%s*%-?%d+", what = "dimension max", zeroOk = false },
	{ pattern = "preferred%s*=%s*%-?%d+", what = "dimension preferred", zeroOk = false },
	{ pattern = "iconSize%s*=%s*%-?%d+", what = "iconSize", zeroOk = false },
	{ pattern = "thickness%s*=%s*%-?%d+", what = "thickness", zeroOk = false },
}

-- R2: a style-owned property assigned a string must name something the framework
-- actually resolves. `vocabulary` answers "is this a legal value".
local STRING_RULES: { { pattern: string, what: string, legal: (string) -> boolean, list: string } } = {
	{
		pattern = 'textSize%s*=%s*"([%w_.]+)"',
		what = "textSize role",
		legal = function(v)
			return TYPE_ROLES[v] == true or isMetricName(v)
		end,
		list = table.concat(themePackage.TYPE_ROLES, " | "),
	},
	{
		pattern = 'surface%s*=%s*"([%w_.]+)"',
		what = "surface role",
		legal = function(v)
			return SURFACES[v] == true
		end,
		list = "the Box.surface enum",
	},
	{
		pattern = '[^%w_]role%s*=%s*"([%w_.]+)"',
		what = "semantic role",
		legal = function(v)
			-- one pattern, two owners: `role` is a Text style role AND the key of a
			-- tint. A value legal for either is legal here; a value legal for
			-- neither is the typo this rule exists to catch.
			-- ...and `role` is ALSO Button's semantic role (default|cancel|destructive),
			-- which the reference proofs use as the spec mandates
			return TEXT_ROLES[v] == true or TINT_ROLES[v] == true or BUTTON_ROLES[v] == true
		end,
		list = "a Text role, a tint role, or a Button role",
	},
}

-- R3: colour is style authority, full stop. An example names a semantic role.
local COLOUR_RULES: { { pattern: string, what: string } } = {
	{ pattern = "Color3%s*%.", what = "a Color3 literal" },
	{ pattern = '"#%x%x%x%x%x%x"', what = "a hex colour literal" },
	{ pattern = "{%s*r%s*=%s*[%d%.]+%s*,%s*g%s*=", what = "an { r, g, b } colour literal" },
}

-- R4: an example composes Facet. It does not reach around it.
local REACHAROUND_RULES: { { pattern: string, what: string } } = {
	{ pattern = "Instance%s*%.%s*new", what = "raw Instance construction" },
	{ pattern = "game%s*:%s*GetService", what = "a direct engine service" },
	{ pattern = "adapter%s*%.%s*setProp", what = "a direct adapter write" },
	{ pattern = "UserInputService", what = "direct input routing" },
	{ pattern = "TweenService", what = "animation outside the framework model" },
	{ pattern = "workspace%s*[:%.]", what = "a direct workspace reach" },
	-- a platform-name branch is the shape the plan bans by name
	{ pattern = "UserInputType%s*%.%s*Touch", what = "a platform branch" },
	{ pattern = 'IsA%s*%(%s*"', what = "an engine class test" },
}

-- INTENTIONALLY exempt, each with the standing reason. `match` is a plain
-- substring of the offending source line, so the reason lives in one reviewable
-- place instead of being scattered through the examples as suppression comments.
local ALLOWLIST: { { file: string, match: string, why: string } } = {
	-- ── swiftui-reference-app-validation proofs ────────────────────────────
	-- The specs proposed proof theme metrics (metrics.foyer.*, metrics.wardrobe.*);
	-- the stage ruling (package-briefs.md) is NO new theme tokens, so these are
	-- structural constants at their one definition site, each with its reason.
	{
		file = "examples/reference/p4_foyer/init.luau",
		match = 'width = { type = "minMax", min = 280, max = DETAIL_W },',
		why = "modal panel structure: a floor a readable dialog needs and the spec's detail cap — layout, not themable chrome",
	},
	{
		file = "examples/reference/p4_foyer/init.luau",
		match = 'width = { type = "minMax", min = 200, preferred = SEARCH_W, max = SEARCH_W },',
		why = "the search field's usable floor and its spec cap — structure of the top bar, not theme chrome",
	},
	{
		file = "examples/reference/p4_foyer/init.luau",
		match = 'height = { type = "fixed", px = 3 },',
		why = "the tab-selection underline: an indicator FORM (the visual-language invariant's channel), deliberately constant across themes",
	},
	{
		file = "examples/reference/p4_foyer/init.luau",
		match = 'width = { type = "fixed", px = 3 },',
		why = "the rail active bar: the same selection-indicator FORM as the underline, on the vertical axis",
	},
	{
		file = "examples/reference/p4_foyer/init.luau",
		match = 'width = { type = "fixed", px = 10 },',
		why = "the presence dot: a display-only marker below the target floor by contract",
	},
	{
		file = "examples/reference/p4_foyer/init.luau",
		match = 'height = { type = "fixed", px = 10 },',
		why = "the presence dot's other axis — the same display-only marker ruling as its width",
	},
	{
		file = "examples/reference/p5_wardrobe/init.luau",
		match = 'width = { type = "minMax", min = 260, max = CONFIRM_W },',
		why = "purchase-confirm panel structure (spec's confirmW), layout not chrome",
	},
	{
		file = "examples/reference/p5_wardrobe/init.luau",
		match = 'width = { type = "minMax", min = 240, max = 360 },',
		why = "refine panel structure: a small filter sheet's readable bounds",
	},
	{
		file = "examples/reference/p5_wardrobe/init.luau",
		match = 'height = { type = "fixed", px = 3 },',
		why = "the category-selection underline: indicator form, constant across themes",
	},
	{
		file = "examples/reference/p5_wardrobe/init.luau",
		match = "ambient = { r = 0.55, g = 0.55, b = 0.58 },",
		why = "3D stage lighting is CONTENT behind the stage seam (the scene's own light), not UI paint",
	},
	{
		file = "examples/reference/p5_wardrobe/init.luau",
		match = "lightColor = { r = 1, g = 0.98, b = 0.94 },",
		why = "stage-scene light colour is 3D content behind the stage seam by contract, never UI paint",
	},
	{
		file = "examples/reference/p2_cartwheel/init.luau",
		match = "ambient = { r = 0.38, g = 0.36, b = 0.42 },",
		why = "3D stage ambient light is scene CONTENT behind the stage seam by contract, never UI paint",
	},
	{
		file = "examples/reference/p2_cartwheel/init.luau",
		match = "lightColor = { r = 0.95, g = 0.9, b = 0.78 },",
		why = "3D stage lighting is CONTENT behind the stage seam, not UI paint (same ruling as the Wardrobe pane)",
	},
	{
		file = "examples/reference/p2_cartwheel/screens/brew_detail.luau",
		match = "min = 0,",
		why = "a countdown progress range is semantics (0..1 ratio), not a themable size",
	},
	{
		file = "examples/reference/p2_cartwheel/screens/brew_detail.luau",
		match = "max = 1,",
		why = "the ceiling of the same semantic 0..1 ratio range — content semantics, not a themable size",
	},
	{
		file = "examples/reference/p2_cartwheel/screens/workbench.luau",
		match = "min = 0,",
		why = "a relative-max gauge's RANGE is semantics (0..1 ratio), not a themable size",
	},
	{
		file = "examples/reference/p2_cartwheel/screens/workbench.luau",
		match = "max = 1,",
		why = "the ceiling of the same semantic 0..1 ratio range — content semantics, not a themable size",
	},
	{
		file = "examples/gallery/examples/02_playlist_table.luau",
		match = 'width = { type = "fixed", px = 70 }',
		why = "the Length column holds a fixed-shape duration (`0:00`), which is CONTENT: it does not "
			.. "grow with a theme because the string it holds never does",
	},
	{
		file = "examples/gallery/examples/02_playlist_table.luau",
		match = 'width = { type = "fixed", px = 144 }',
		why = "the Rating column, with the standing framework follow-up recorded beside it in the "
			.. "example: a table resolves column widths per SECTION, so `hug` measured the header "
			.. "and the body separately and they disagreed by 21px. Content-sizing a column across "
			.. "header AND body is the fix; 144 clears the widest measured touch star run (136px) "
			.. "until it lands",
	},
}

local function isComment(line: string): boolean
	local trimmed = string.match(line, "^%s*(.-)%s*$") :: string
	return string.sub(trimmed, 1, 2) == "--"
end

export type Options = {
	-- inject a synthetic violation for the lint's own negative proof
	injectFile: string?,
	injectLine: string?,
}

export type Violation = { file: string, line: number, rule: string, what: string, text: string }

function checker.check(opts: Options?)
	local options = opts or {}
	local violations: { Violation } = {}
	local files: { string } = {}
	local entries = fs.readDir(SCANNED_DIR)
	table.sort(entries)
	for _, entry in entries do
		if string.match(entry, "%.luau$") ~= nil then
			table.insert(files, `{SCANNED_DIR}/{entry}`)
		end
	end
	local function addDir(dir: string)
		local names = fs.readDir(dir)
		table.sort(names)
		for _, entry in names do
			local full = `{dir}/{entry}`
			if fs.isDir(full) then
				addDir(full)
			elseif string.match(entry, "%.luau$") ~= nil then
				table.insert(files, full)
			end
		end
	end
	if fs.isDir(REFERENCE_DIR) then
		addDir(REFERENCE_DIR)
	end

	local allowed = 0
	local scannedLines = 0
	local roleUses = 0
	for _, file in files do
		local source = fs.readFile(file)
		if options.injectFile == file and options.injectLine ~= nil then
			source ..= "\n" .. options.injectLine .. "\n"
		end
		local lineNumber = 0
		for line in string.gmatch(source .. "\n", "([^\n]*)\n") do
			lineNumber += 1
			scannedLines += 1
			if isComment(line) then
				continue
			end
			local found: { { rule: string, what: string } } = {}

			for _, rule in NUMBER_RULES do
				local hit = string.match(line, "(" .. rule.pattern .. ")")
				if hit ~= nil then
					local n = tonumber(string.match(hit, "(%-?%d+)$"))
					if not (rule.zeroOk and n == 0) then
						table.insert(found, {
							rule = "R1",
							what = `{rule.what} = {tostring(n)} (a number where the theme owns the value)`,
						})
					end
				end
			end

			for _, rule in STRING_RULES do
				local value = string.match(line, rule.pattern)
				if value ~= nil then
					roleUses += 1
					if not rule.legal(value) then
						table.insert(found, {
							rule = "R2",
							what = `{rule.what} '{value}' names nothing the framework resolves (expected {rule.list})`,
						})
					end
				end
			end

			for _, rule in COLOUR_RULES do
				if string.find(line, rule.pattern) ~= nil then
					table.insert(found, { rule = "R3", what = rule.what })
				end
			end

			for _, rule in REACHAROUND_RULES do
				if string.find(line, rule.pattern) ~= nil then
					table.insert(found, { rule = "R4", what = rule.what })
				end
			end

			if #found == 0 then
				continue
			end
			local suppressed = false
			for _, entry in ALLOWLIST do
				if entry.file == file and string.find(line, entry.match, 1, true) ~= nil then
					suppressed = true
					allowed += 1
					break
				end
			end
			if not suppressed then
				for _, hit in found do
					table.insert(violations, {
						file = file,
						line = lineNumber,
						rule = hit.rule,
						what = hit.what,
						text = string.match(line, "^%s*(.-)%s*$") :: string,
					})
				end
			end
		end
	end

	local problems: { string } = {}
	for _, v in violations do
		table.insert(
			problems,
			`{v.file}:{v.line}: [{v.rule}] {v.what} — "{v.text}". An example declares style INTENT: a `
				.. `typography role for text, a spacing step or theme metric path for space and size, a `
				.. "semantic surface/role or a tint naming a theme role for colour, and public Facet for "
				.. "everything the engine would otherwise be asked for. If the value really is content or "
				.. "structure, add it to the ALLOWLIST in tools/lune/check_example_drift.luau with the reason."
		)
	end

	return {
		ok = #violations == 0,
		problems = problems,
		violations = violations,
		counts = { files = #files, lines = scannedLines, allowlisted = allowed, roleUses = roleUses },
	}
end

checker.ALLOWLIST = ALLOWLIST
checker.SCANNED_DIR = SCANNED_DIR

return checker
