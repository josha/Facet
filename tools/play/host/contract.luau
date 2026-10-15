--!strict

local fs = require("@std/fs")
local process = require("@std/process")

local OWNED = { "src/server", "src/shared" }

local function normalized(text: string): string
	return (string.gsub(text, "\r\n", "\n"))
end

local function compare(starter: string, workspace: string, relative: string, problems: { string })
	local source = starter .. "/" .. relative
	if not fs.exists(source) then
		return
	end
	if not fs.exists(workspace .. "/" .. relative) then
		table.insert(problems, relative .. " was removed")
		return
	end
	for _, entry in fs.listDirectory(source) do
		local child = relative .. "/" .. entry.name
		if entry.type == "dir" then
			compare(starter, workspace, child, problems)
		else
			local target = workspace .. "/" .. child
			if not fs.exists(target) then
				table.insert(problems, child .. " was removed")
			elseif
				normalized(fs.readFileToString(target)) ~= normalized(fs.readFileToString(source .. "/" .. entry.name))
			then
				table.insert(problems, child .. " was changed")
			end
		end
	end
	for _, entry in fs.listDirectory(workspace .. "/" .. relative) do
		local child = relative .. "/" .. entry.name
		if not fs.exists(source .. "/" .. entry.name) then
			table.insert(problems, child .. " was added")
		end
	end
end

local starter = process.args[2]
local workspace = process.args[3]
if starter == nil or workspace == nil then
	print("usage: lute run tools/play/host/contract.luau <starter> <workspace>")
	process.exit(2)
end
local problems: { string } = {}
for _, relative in OWNED do
	compare(starter :: string, workspace :: string, relative, problems)
end
if #problems > 0 then
	print("the game model and the network contract changed:")
	for _, problem in problems do
		print("  " .. problem)
	end
	process.exit(1)
end
print("the game model and the network contract are unchanged")
