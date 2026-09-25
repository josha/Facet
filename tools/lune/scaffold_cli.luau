--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local scaffold = require("./scaffold")
assert(#process.args == 2, "usage: lune run tools/lune/scaffold_cli control lower_snake_name")
local plan = scaffold.plan(process.args[1], process.args[2])
local writes = {}
for _, file in plan.files do
	assert(not fs.isFile(file.path), `Refusing to overwrite {file.path}`)
	table.insert(writes, file)
end
for _, edit in plan.edits do
	table.insert(writes, { path = edit.path, content = scaffold.applyEdit(fs.readFile(edit.path), edit) })
end
for _, file in writes do
	fs.writeFile(file.path, file.content)
	print(`wrote {file.path}`)
end
print(
	"Implement the control, add a native behavior spec and gallery scenario, and document its API before running tools/verify.sh full."
)
