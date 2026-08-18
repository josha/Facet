--!strict
-- theme_sync — the ONE export action of the Style Editor workflow (ADR-0019 §3).
--
-- The DataModel theme sheet is the authoring surface: a designer edits supported
-- paint, metric and font tokens there and the running preview re-solves live.
-- This command writes those edits back into the committed plain-Luau package, so
-- the headless suite, the solver and the Style Editor never disagree — and its
-- `--check` mode is the freshness gate that fails a build when they do.
--
--   lune run tools/lune/theme_sync_cli -- --dump <dump.json> --package <file.luau>
--   lune run tools/lune/theme_sync_cli -- --dump <dump.json> --package <file.luau> --check
--   lune run tools/lune/theme_sync_cli -- --dump <dump.json> --out <file.luau>
--
-- The dump is what `controller.dumpTokens()` produces on the client (the theme
-- authoring scenario exposes it as an action): typed records, deterministically
-- ordered, exactly the six kinds feasibility m6 proved round-trip value-exact.
--
-- A package file carrying the theme_sync markers keeps everything around them —
-- its style, chrome and asset sections stay hand-authored — and has only the
-- metrics region regenerated. A file without them is generator-owned end to end.
-- Either way the committed metrics are GENERATOR-WRITTEN, so there is never a
-- second hand-edited metric source.

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local luau = require("@lune/luau")
local process = require("@lune/process")

local token_sync = require("../../src/themes/token_sync")

local function fail(message: string): never
	print(`theme_sync: {message}`)
	process.exit(2)
	error(message)
end

local args: { [string]: string } = {}
do
	local index = 1
	while index <= #process.args do
		local arg = process.args[index]
		if arg == "--" then
			index += 1
			continue
		end
		local name = string.match(arg, "^%-%-(.+)$")
		if name == nil then
			fail(`unexpected argument '{arg}' (flags are --dump, --package, --out, --check)`)
			break
		end
		if name == "check" then
			args.check = "true"
			index += 1
		else
			local value = process.args[index + 1]
			if value == nil then
				fail(`--{name} needs a value`)
			end
			args[name] = value
			index += 2
		end
	end
end

if args.dump == nil then
	print("usage: lune run tools/lune/theme_sync_cli -- --dump <dump.json> --package <file.luau> [--check]")
	process.exit(2)
end
if not fs.isFile(args.dump) then
	fail(`dump '{args.dump}' does not exist — produce it with the theme authoring scenario's dump action`)
end

local dump: any = serde.decode("json", fs.readFile(args.dump))
if type(dump) ~= "table" or type(dump.tokens) ~= "table" then
	fail(`dump '{args.dump}' is not a theme token dump (expected schema, package, theme and tokens fields)`)
end
-- THE PRE-RENAME SPELLING OF THE SAME SCHEMA, AND IT LIVES HERE RATHER THAN IN
-- src/. Studio dumps recorded before the 2026-08-17 Facet rename are immutable
-- evidence and carry `luauui-theme-sync/1`; a READER must still accept them, but
-- nothing ever writes it and no consumer of the library needs it — so keeping it
-- in `src/themes/token_sync.luau` would have shipped an old-brand string inside
-- build/Facet.rbxm for a dev-tool concern. Anything that is neither spelling is
-- still refused, so this is the same check it always was. Removable once no
-- stored dump names it.
local LEGACY_SCHEMA = "luauui-theme-sync/1"
if dump.schema ~= nil and dump.schema ~= token_sync.SCHEMA and dump.schema ~= LEGACY_SCHEMA then
	fail(
		`dump schema is '{tostring(dump.schema)}'; this build speaks '{token_sync.SCHEMA}' `
			.. `(and still reads the pre-rename '{LEGACY_SCHEMA}')`
	)
end

local target = args.package or args.out
if target == nil then
	fail("name the committed package file with --package (patched in place) or --out (written fresh)")
end

-- the committed side, as records: either the marker-delimited metrics region
-- (so a package file that requires other modules still loads) or the whole file
local function committedRecords(path: string): { any }?
	if not fs.isFile(path) then
		return nil
	end
	local source = fs.readFile(path)
	local chunk = token_sync.extractMetricsChunk(source) or source
	local ok, loaded = pcall(function()
		return (luau.load(chunk, { debugName = path }))()
	end)
	if not ok or type(loaded) ~= "table" then
		fail(
			`could not evaluate '{path}' to read its committed metrics `
				.. `({tostring(loaded)}). A generator-owned metrics module must not require anything; `
				.. `a hand-authored package must delimit its metrics with '{token_sync.BEGIN_MARKER}'`
		)
		return nil
	end
	local metrics = (loaded :: any).metrics or loaded
	return token_sync.recordsFromMetrics(metrics)
end

if args.check == "true" then
	local committed = committedRecords(target)
	if committed == nil then
		print(`theme_sync: FAIL — '{target}' does not exist; run theme_sync to generate it`)
		process.exit(1)
	end
	local drift = token_sync.diff(dump.tokens, committed :: { any })
	if #drift == 0 then
		print(`theme_sync: PASS — '{target}' matches the sheet dump ({#dump.tokens} tokens)`)
		process.exit(0)
	end
	print(`theme_sync: FAIL — {#drift} token(s) drifted between the theme sheet and '{target}'.`)
	for _, entry in drift do
		print(`  - {entry.path}: sheet {tostring(entry.left)} vs committed {tostring(entry.right)}`)
	end
	print("run theme_sync to write the sheet's values back into the committed package:")
	print(`  lune run tools/lune/theme_sync_cli -- --dump {args.dump} --package {target}`)
	process.exit(1)
end

local existing: string? = if fs.isFile(target) and args.out == nil then fs.readFile(target) else nil
local source, mode = token_sync.applyToSource(existing, dump)
fs.writeFile(target, source)
print(
	`theme_sync: {mode} '{target}' from {#dump.tokens} tokens (package '{tostring(dump.package and dump.package.id)}', theme '{tostring(
		dump.theme
	)}')`
)
process.exit(0)
