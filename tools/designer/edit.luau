--!strict

local fs, process = require("@std/fs"), require("@std/process")
local Json = require("../facet/lib/json")
local source = require("./modules/source")
local agent = require("./modules/agent")
local args = table.move(process.args, 2, #process.args, 1, {})
assert(
	args[1] == "inspect" or args[1] == "edit",
	"Usage: lute run tools/designer/edit.luau inspect component.luau | edit component.luau operations.json output.luau"
)
local code = fs.readFileToString((assert(args[2], "Choose a component file")))
if args[1] == "inspect" then
	print(Json.encode(source.parse(code, args[2]), { sortKeys = true, compact = true, ascii = false }))
else
	local operations = Json.decode(fs.readFileToString((assert(args[3], "Choose an operations file"))))
	local generated = agent.patch(code, operations :: any)
	fs.writeStringToFile(assert(args[4], "Choose an output file"), generated)
	print("Facet Design edits applied")
end
