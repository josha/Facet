--!strict
local Compose = require("../vendor/compose/core")
local Types = require("./types")

return function(ctx: Types.Context, roots: { GuiObject }): () -> boolean
	local provider = ctx.config.services.ContentProvider
	local textService = ctx.config.services.TextService
	if (provider == nil and textService == nil) or task == nil then
		return function(): boolean
			return true
		end
	end
	local params = if textService
		then ((ctx.Host :: unknown) :: { GetTextBoundsParams: ({ Width: number }) -> GetTextBoundsParams }).GetTextBoundsParams({
			Width = 0,
		})
		else nil
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
		local fonts: { [string]: TextLabel | TextButton | TextBox } = {}
		for _, root in roots do
			local texts = root:GetDescendants()
			table.insert(texts, root)
			for _, node in texts do
				if node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then
					local face = node:GetStyled("FontFace") :: Font
					fonts[`{face.Family}:{face.Weight.Name}:{face.Style.Name}:{node:GetStyled("TextSize")}`] = node
				end
			end
		end
		local faces = {}
		for source in fonts do
			table.insert(faces, source)
		end
		table.sort(faces)
		local sources: { TextLabel | TextButton | TextBox } = {}
		for _, face in faces do
			table.insert(sources, fonts[face])
		end
		local key = table.concat(faces, ";")
		if key ~= wanted then
			cancel()
			wanted = key
			pending = task.defer(function()
				if textService and params then
					for _, node in sources do
						params.Font = node:GetStyled("FontFace") :: Font
						params.Size = node:GetStyled("TextSize") :: number
						params.Text = node.Text
						params.RichText = node.RichText
						pcall(function()
							textService:GetTextBoundsAsync(params)
						end)
					end
				elseif provider then
					pcall(function()
						provider:PreloadAsync(sources)
					end)
				end
				if not Compose.owner.isDisposed(owner) and wanted == key then
					loaded = key
				end
			end)
		end
		return loaded == key
	end
end
