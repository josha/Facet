--!strict
--[[ THE ONE ENUMERATOR OF `examples/themes/` (MAINT-8c, 2026-08-17).

	Six independently hand-maintained lists of theme-package names shipped in this
	repository — two in `tests/theme_reference_packages.spec.luau`, one in
	`tools/lune/check_docs.luau`, one in `tools/lune/_probe_matrix.luau`, one in
	`tests/renderer.spec.luau`, one in `tests/gallery_theme_picker.spec.luau` —
	and NOTHING enumerated the directory or cross-validated them. A new package
	could land and be named by none of them; a renamed one could leave a list
	pointing at a file that no longer exists; and `docs/extending/new-theme.md`,
	the playbook an author actually follows, named exactly one of the six.

	WHY THIS IS NOT JUST `readDir`. The directory holds three different KINDS of
	file and the lists are legitimately different subsets of them, so an
	enumerator that answered "all thirteen" would be wrong for every caller:

	  * `reference` — a shipping reference package. Every claim the corpus makes
	    (public-API-only construction, a resolvable snapshot, a stable sheet
	    stamp, honest theme-class declarations) is a claim this file has to
	    survive, and it must be one click away in the gallery picker.
	  * `fixture`   — a deliberately degenerate package the acceptance scenarios
	    install BY NAME to prove a refusal. It must NOT appear in a picker.
	  * `control`   — a rung-3 worked example: a CONTROL with its own art, not a
	    package a player can select.

	So the role is DECLARED here, once, and the check below fails a file with no
	role and a role with no file. Adding a theme is then a two-line change with a
	loud failure if you skip the second line — which is the whole difference
	between six lists and one.
]]

local fs = require("@lune/fs")

local theme_packages = {}

local THEMES_DIR = "examples/themes"

export type Role = "reference" | "fixture" | "control"

theme_packages.ROLES = {
	classic_desktop = "reference",
	glossy_mobile = "reference",
	scifi_hud = "reference",
	fantasy_parchment_stub = "reference",
	fantasy_parchment = "reference",
	fantasy_ornate = "reference",
	pixel_quest = "reference",
	glossy_touch = "reference",
	compact_pointer = "reference",
	content_alias_test = "fixture",
	layered_test = "fixture",
	custom_control = "control",
	ornate_gauge = "control",
} :: { [string]: Role }

--[[ THE REFERENCE CORPUS IN ITS DECLARED ORDER. The ORDER is a real fact — the
	five older packages come first because every later claim was proved against
	them — so it stays hand-written; what is mechanical is that it must be exactly
	the `reference` role set, which `check()` asserts. ]]
theme_packages.REFERENCE_ORDER = {
	"classic_desktop",
	"glossy_mobile",
	"scifi_hud",
	"fantasy_parchment_stub",
	"fantasy_parchment",
	"fantasy_ornate",
	"pixel_quest",
	"glossy_touch",
	"compact_pointer",
}

-- every `examples/themes/*.luau` on disk, sorted
function theme_packages.files(): { string }
	local out: { string } = {}
	for _, entry in fs.readDir(THEMES_DIR) do
		local name = string.match(entry, "^([%w_]+)%.luau$")
		if name ~= nil then
			table.insert(out, name)
		end
	end
	table.sort(out)
	assert(#out > 0, `theme_packages: no theme modules found under {THEMES_DIR}`)
	return out
end

function theme_packages.byRole(role: Role): { string }
	local out: { string } = {}
	for name, declared in theme_packages.ROLES do
		if declared == role then
			table.insert(out, name)
		end
	end
	table.sort(out)
	return out
end

function theme_packages.path(name: string): string
	return `{THEMES_DIR}/{name}.luau`
end

-- the drift check: the directory, the roles and the declared order agree
function theme_packages.check(extraFiles: { string }?): { ok: boolean, problems: { string } }
	local problems: { string } = {}
	local onDisk: { [string]: boolean } = {}
	for _, name in theme_packages.files() do
		onDisk[name] = true
	end
	for _, name in extraFiles or {} do
		onDisk[name] = true
	end

	for name in onDisk do
		if theme_packages.ROLES[name] == nil then
			problems[#problems + 1] = `{THEMES_DIR}/{name}.luau has no declared role in tools/lune/theme_packages.luau `
				.. `— every theme module is a reference package, a refusal fixture or a rung-3 control, and the six `
				.. `lists that consume this directory all read the role`
		end
	end
	for name in theme_packages.ROLES do
		if not onDisk[name] then
			problems[#problems + 1] = `tools/lune/theme_packages.luau declares a role for '{name}', which does not `
				.. `exist under {THEMES_DIR}/ — if it was renamed or deleted, fix the role table`
		end
	end

	local declaredOrder: { [string]: boolean } = {}
	for _, name in theme_packages.REFERENCE_ORDER do
		declaredOrder[name] = true
		if theme_packages.ROLES[name] ~= "reference" then
			problems[#problems + 1] =
				`REFERENCE_ORDER lists '{name}', whose declared role is not 'reference' — the order is the corpus, not a subset of it`
		end
	end
	for _, name in theme_packages.byRole("reference") do
		if not declaredOrder[name] then
			problems[#problems + 1] = `'{name}' is a reference package but is missing from REFERENCE_ORDER — every `
				.. `shipping package has to be one click away in the gallery picker, and the order is what puts it there`
		end
	end

	return { ok = #problems == 0, problems = problems }
end

return theme_packages
