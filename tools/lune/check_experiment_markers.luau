--!strict
--[[ NO SCRATCH EXPERIMENT SURVIVES IN `src/` (RED-TEAM C1, 2026-09-07).

	WHAT HAPPENED. `src/client/screen_target.luau` shipped, inside a feature commit
	that had nothing to do with it, two lines of a throwaway experiment:

	    local ZZ_NO_PATH2D = true -- ZZ-EXPERIMENT
	    if class == "Path" and not ZZ_NO_PATH2D then

	The second line is the whole `Path2D` creation branch. With the flag on, the
	real adapter creates no `Path2D` at all, so EVERY `UI.Path` — a circular
	`newProgressView`'s track and arc, and twelve sites in the consumer game —
	renders empty on a device. The headless suite is blind to it by construction:
	`tests/lib/fake_target.luau` builds its own Path2D model rather than the
	engine's, so 8,824 checks stayed green over a framework that draws no strokes.

	WHY A CHECKER AND NOT A LESSON. Nothing in the ladder could see it. It is not a
	type error, not a boundary violation, not a property-authority violation, not a
	documentation drift, and not a size regression — it is a correct-looking
	constant whose value happens to disable a subsystem, and the one instrument that
	would have caught it (a live adapter) is exactly the instrument a headless tier
	does not run. What IS mechanically visible is the marker the author left on it.
	`ZZ` is this repository's own convention for "scratch, sorts last" — the
	yardstick bench scene, the throwaway spec files — and it is a convention worth
	making load-bearing: a `ZZ` name is allowed to exist anywhere a human is
	expected to read it as temporary (`tests/`, `bench/`, `tools/`), and nowhere in
	the runtime.

	THE RULE, STATED NARROWLY. No identifier under `src/` may begin with `ZZ`. The
	scan is textual and covers comments too, because `-- ZZ-EXPERIMENT` beside an
	innocuous-looking constant is the tell that outlives the constant's name.

	check(opts?) -> { ok, violations, counts }. `injectFile`/`injectLine` are the
	selftest seam: they append one line to one scanned file in memory, so the check
	can be watched CATCHING a planted fault without writing to the tree.
]]

local fs = require("@lune/fs")

local checker = {}

local ROOT = "src"

export type Violation = {
	file: string,
	line: number,
	token: string,
	text: string,
}

export type Options = {
	root: string?,
	injectFile: string?,
	injectLine: string?,
}

local function luauFilesUnder(dir: string, out: { string })
	for _, entry in fs.readDir(dir) do
		local path = `{dir}/{entry}`
		if fs.isDir(path) then
			luauFilesUnder(path, out)
		elseif string.sub(entry, -5) == ".luau" then
			table.insert(out, path)
		end
	end
end

--[[ A WHOLE WORD that starts with `ZZ`. The frontier pattern is what makes it a
	word rather than a substring: `BUZZER` contains "ZZ" and is not a marker, while
	`ZZ_NO_PATH2D`, `ZZ` and `ZZExperiment` all are. Case is NOT folded — `zz` in
	prose ("fizz", "buzz") is ordinary English and flagging it would make the check
	something an author routes around instead of obeys. ]]
local function markersIn(line: string, out: { string })
	for token in string.gmatch(line, "%f[%w_]ZZ[%w_]*") do
		table.insert(out, token)
	end
end

function checker.check(
	opts: Options?
): { ok: boolean, violations: { Violation }, counts: { files: number, lines: number } }
	local options = opts or {}
	local root = options.root or ROOT
	local files: { string } = {}
	luauFilesUnder(root, files)
	table.sort(files)

	local violations: { Violation } = {}
	local lineCount = 0
	for _, file in files do
		local source = fs.readFile(file)
		if options.injectFile == file and options.injectLine ~= nil then
			source ..= "\n" .. options.injectLine .. "\n"
		end
		local n = 0
		for line in string.gmatch(source .. "\n", "([^\n]*)\n") do
			n += 1
			lineCount += 1
			local tokens: { string } = {}
			markersIn(line, tokens)
			for _, token in tokens do
				table.insert(violations, {
					file = file,
					line = n,
					token = token,
					text = (string.gsub(line, "^%s+", "")),
				})
			end
		end
	end
	return {
		ok = #violations == 0,
		violations = violations,
		counts = { files = #files, lines = lineCount },
	}
end

function checker.describe(v: Violation): string
	return `{v.file}:{v.line}: '{v.token}' — a ZZ-prefixed name is a scratch experiment marker and may not `
		.. `live in src/. Scratch belongs in tests/, bench/ or tools/; a runtime flag that ships is a feature `
		.. `flag and needs a name, a default and a documented reason.`
end

return checker
