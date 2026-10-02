--!strict

local fs, serde, process = require("@lune/fs"), require("@lune/serde"), require("@lune/process")
local source = require("./modules/source")
local agent = require("./modules/agent")
local args = process.args
assert(
	args[1] == "inspect" or args[1] == "edit",
	"Usage: lune run tools/designer/edit inspect component.luau | edit component.luau operations.json output.luau"
)
local code = fs.readFile((assert(args[2], "Choose a component file")))
if args[1] == "inspect" then
	print(serde.encode("json", source.parse(code, args[2])))
else
	local operations = serde.decode("json", fs.readFile((assert(args[3], "Choose an operations file"))))
	local generated = agent.patch(code, operations)
	fs.writeFile(assert(args[4], "Choose an output file"), generated)
	print("Facet Design edits applied")
end
