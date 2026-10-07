--!strict
local Types = require("./types")

return function(ctx: Types.Context, roots: { GuiObject }): () -> boolean
	local provider = ctx.config.services.ContentProvider
	if provider == nil or task == nil then
		return function(): boolean
			return true
		end
	end
	local owner = assert(ctx.Compose.currentOwner())
	local wanted: string? = nil
	local loaded: string? = nil
	local pending: thread? = nil
	local function cancel()
		if pending and coroutine.status(pending) == "suspended" then
			pcall(task.cancel, pending)
		end
		pending = nil
	end
	ctx.Compose.cleanup(cancel)
	return function(): boolean
		local fonts: { [string]: boolean } = {}
		for _, root in roots do
			local texts = root:GetDescendants()
			table.insert(texts, root)
			for _, node in texts do
				if node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then
					local face = node:GetStyled("FontFace") :: Font
					fonts[face.Family] = true
				end
			end
		end
		local sources = {}
		for source in fonts do
			table.insert(sources, source)
		end
		table.sort(sources)
		local key = table.concat(sources, ";")
		if key ~= wanted then
			cancel()
			wanted = key
			pending = task.defer(function()
				pcall(function()
					provider:PreloadAsync(sources)
				end)
				if not owner.isDisposed() and wanted == key then
					loaded = key
				end
			end)
		end
		return loaded == key
	end
end
