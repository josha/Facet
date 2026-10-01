--!strict

local catalog = require("./catalog")

local loader = {}

function loader.prepare(module: ModuleScript, editor: any): any
	local scope = catalog.scope(module)
	local path = {}
	local cursor: Instance = module
	while cursor ~= scope do
		table.insert(path, 1, cursor.Name)
		cursor = assert(cursor.Parent)
	end
	local copy = assert(scope:Clone(), "Preview root must be Archivable")
	local originals = { scope }
	for _, node in scope:GetDescendants() do
		table.insert(originals, node)
	end
	local ok, result = xpcall(function()
		for _, original in originals do
			local relative = {}
			cursor = original
			while cursor ~= scope do
				table.insert(relative, 1, cursor.Name)
				cursor = assert(cursor.Parent)
			end
			local target = copy
			for _, name in relative do
				local matches = 0
				for _, child in target:GetChildren() do
					if child.Name == name then
						matches += 1
					end
				end
				assert(matches == 1, `Preview root needs unique sibling names: {name}`)
				target = assert(target:FindFirstChild(name), `Cannot copy {original:GetFullName()}`)
			end
			if original:IsA("LuaSourceContainer") then
				(target :: any).Source = editor:GetEditorSource(original)
			end
			if target:IsA("BaseScript") then
				target.Enabled = false
			end
		end
		local selected = copy
		for _, name in path do
			selected = assert(selected:FindFirstChild(name))
		end
		return selected
	end, function(err)
		return debug.traceback(tostring(err), 2)
	end)
	if not ok then
		copy:Destroy()
		error(result, 0)
	end
	local disposed = false
	return {
		evaluate = function(loadModule: ((ModuleScript) -> any)?)
			assert(not disposed, "Preview snapshot is closed")
			local read: any = loadModule or require
			return catalog.validate(read(result :: ModuleScript))
		end,
		scope = scope,
		dispose = function()
			if not disposed then
				disposed = true
				copy:Destroy()
			end
		end,
	}
end

function loader.load(module: ModuleScript, editor: any, loadModule: ((ModuleScript) -> any)?): any
	local snapshot = loader.prepare(module, editor)
	local ok, definition = pcall(snapshot.evaluate, loadModule)
	if not ok then
		snapshot.dispose()
		error(definition, 0)
	end
	snapshot.definition = definition
	return snapshot
end

return loader
