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

--[[ WHAT IS NOT SHIPPABLE, AND WHY (wave THEME-UNBUNDLE, 2026-08-21).

	`tools/build_themes.sh` builds ONE `.rbxm` per shippable package so a consumer
	can take a skin without taking the gallery. "Shippable" is therefore a
	distribution decision, not a test decision, and the two do not coincide with
	the ROLE above: `fantasy_parchment_stub` has the `reference` role because every
	corpus claim is a claim it survives, and it must still never be handed to a
	player, because three of its four variants are broken ON PURPOSE.

	So the shippable set is the directory MINUS this table, and `check()` fails a
	module that is in neither — a new package cannot be added without a decision
	about whether a player may install it. Each entry carries the reason a reader
	needs and the condition under which it would move.
]]
theme_packages.NOT_SHIPPABLE = {
	fantasy_parchment_stub = "a REFUSAL fixture wearing a reference package's clothes: `buildBadAsset`, "
		.. "`buildBadFont` and `buildIncompatible` are deliberately broken variants, and the module already "
		.. "declares `testOnly = true` so the gallery picker hides it. The shipping skin of this name is "
		.. "`fantasy_parchment`. It would become shippable only if the broken variants moved to their own file.",
	content_alias_test = "an A/B fixture, not a look: it compiles the SAME package twice, once spelling every "
		.. "asset `content` and once `contentId`, so the suite can prove the alias agrees. Two identities, one "
		.. "skin, nothing for a player to pick. `testOnly = true`.",
	layered_test = "the layer-vocabulary probe: every rung of the tile -> fill -> frame -> edges -> corners -> "
		.. "plaque ladder in isolation, with the deliberate failures the layered-slot scenarios drive. "
		.. "`testOnly = true`.",
	custom_control = "NOT A THEME PACKAGE AT ALL — the rung-3 conformance fixture for a namespaced CONTROL "
		.. "contributing its own roles. It has no `id`, no `displayName` and no `build`; there is nothing to "
		.. "install.",
	ornate_gauge = "the rung-3 WORKED EXAMPLE, a control with its own art rather than a package. A game copies "
		.. "this file into its own source (docs/extending/new-control.md); it is not a package a player selects, "
		.. "and `fantasy_ornate` is the package that covers its namespaced roles.",
} :: { [string]: string }

--[[ THE ARTIFACT NAME. `build/themes/<Name>.rbxm` holds ONE ModuleScript of the
	same name, because that name is what a consumer without Rojo sees in the
	Explorer and types in a `require` — so it is Roblox house style (PascalCase),
	not the snake_case source filename. One derivation, no second list. ]]
function theme_packages.artifactName(name: string): string
	local parts: { string } = {}
	for word in string.gmatch(name, "[^_]+") do
		table.insert(parts, string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2))
	end
	return table.concat(parts, "")
end

--[[ the packages a consumer may install: the directory minus `NOT_SHIPPABLE`,
	sorted. Derived, never restated — `check()` proves the partition is total. ]]
function theme_packages.shippable(): { string }
	local out: { string } = {}
	for _, name in theme_packages.files() do
		if theme_packages.NOT_SHIPPABLE[name] == nil then
			table.insert(out, name)
		end
	end
	table.sort(out)
	return out
end

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

	--[[ THE SHIPPABLE PARTITION IS TOTAL. A module is either a package a consumer
		may install or a named exclusion with a reason; there is no third state, and
		"nobody decided yet" must not read as "ship it". A reason is required and
		must be a real sentence, because an empty string would satisfy a `~= nil`
		test while telling the next reader nothing. ]]
	for name in theme_packages.NOT_SHIPPABLE do
		if not onDisk[name] then
			problems[#problems + 1] = `tools/lune/theme_packages.luau excludes '{name}' from the shippable set, but `
				.. `{THEMES_DIR}/{name}.luau does not exist — if it was renamed or deleted, fix the exclusion table`
		end
		local reason = theme_packages.NOT_SHIPPABLE[name]
		if type(reason) ~= "string" or #reason < 40 then
			problems[#problems + 1] = `NOT_SHIPPABLE['{name}'] needs a REASON a reader can act on — what the module `
				.. `is for, and what would make it shippable`
		end
	end
	for _, name in theme_packages.shippable() do
		if theme_packages.ROLES[name] ~= "reference" then
			problems[#problems + 1] = `'{name}' is shippable but its role is `
				.. `'{tostring(theme_packages.ROLES[name])}' — only a reference package can be handed to a `
				.. `player, so either give it the reference role or exclude it in NOT_SHIPPABLE with a reason`
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
