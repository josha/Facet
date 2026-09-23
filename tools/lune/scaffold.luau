--!strict
local scaffold = {}
export type Edit = { path: string, before: string, insert: string, replace: boolean? }
export type Plan = { files: { { path: string, content: string } }, edits: { Edit } }
function scaffold.plan(kind: string, name: string): Plan
	assert(kind == "control", "Only control scaffolding belongs to Facet; construct native hosts with Compose")
	assert(string.match(name, "^[a-z][a-z0-9_]*$"), "Use a lower_snake_case control name")
	local display = string.gsub("_" .. name, "_(%l)", string.upper)
	return {
		files = {
			{
				path = `src/ui/{name}.luau`,
				content = `--!strict\nlocal Shared = require("@self/types")\nexport type Props = Shared.FrameProps\nexport type Constructor = Shared.Constructor<Props, Frame>\ntype Registry = \{ {display}: Constructor \}\nreturn function(ctx: Shared.Context, UI: Registry)\n\tUI.{display} = ctx.construct(function(spec: Props): Frame\n\t\treturn ctx.Host.Frame(ctx.props(spec, \{\}))\n\tend)\nend\n`,
			},
		},
		edits = {
			{
				path = "src/ui/init.luau",
				before = "\ttable.freeze(UI)",
				insert = `\trequire("@self/{name}")(ctx, UI)\n`,
			},
			{
				path = "src/ui/control_types.luau",
				before = "export type Controls = {",
				insert = `local {display} = require("./{name}")\n\nexport type Controls = \{\n\t{display}: {display}.Constructor,`,
				replace = true,
			},
			{
				path = "src/init.luau",
				before = "export type ButtonProps =",
				insert = `local {display} = require("@self/ui/{name}")\nexport type {display}Props = {display}.Props\n`,
			},
		},
	}
end
function scaffold.applyEdit(source: string, edit: Edit): string
	if string.find(source, edit.insert, 1, true) then
		return source
	end
	local at = string.find(source, edit.before, 1, true)
	assert(at, `Registration target missing in {edit.path}`)
	return string.sub(source, 1, at - 1)
		.. edit.insert
		.. string.sub(source, at + (if edit.replace then #edit.before else 0))
end
return scaffold
