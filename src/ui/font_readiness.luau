--!strict
local Compose = require("../vendor/compose/core")
local Types = require("./types")

export type TextNode = TextLabel | TextButton | TextBox

local function fontOf(node: TextNode): Font
	local font: unknown = node:GetStyled("FontFace")
	assert(typeof(font) == "Font", "text font must be a Font")
	return font
end

local function sizeOf(node: TextNode): number
	local size: unknown = node:GetStyled("TextSize")
	assert(type(size) == "number", "text size must be a number")
	return size
end

return function(ctx: Types.Context, roots: { GuiObject }): (texts: { TextNode }?) -> boolean
	local provider = ctx.config.services.ContentProvider
	local textService = ctx.config.services.TextService
	if (provider == nil and textService == nil) or task == nil then
		return function(_texts: { TextNode }?): boolean
			return true
		end
	end
	local params = if textService
		then ctx.Host.GetTextBoundsParams {
			Width = 0,
		}
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
	local function collect(): { TextNode }
		local found: { TextNode } = {}
		for _, root in roots do
			local texts = root:GetDescendants()
			table.insert(texts, root)
			for _, node in texts do
				if node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then
					table.insert(found, node)
				end
			end
		end
		return found
	end
	return function(texts: { TextNode }?): boolean
		local fonts: { [string]: TextNode } = {}
		local nodes: { TextNode } = texts or collect()
		for _, node in nodes do
			local face = fontOf(node)
			fonts[`{face.Family}:{face.Weight.Name}:{face.Style.Name}:{sizeOf(node)}`] = node
		end
		local faces = {}
		for source in fonts do
			table.insert(faces, source)
		end
		table.sort(faces)
		local sources: { TextNode } = {}
		for _, face in faces do
			table.insert(sources, fonts[face])
		end
		local key = table.concat(faces, ";")
		if key ~= wanted then
			cancel()
			wanted = key
			pending = task.defer(function()
				if textService and params then
					local service, request = textService, params
					for _, node in sources do
						request.Font = fontOf(node)
						request.Size = sizeOf(node)
						request.Text = node.Text
						request.RichText = node.RichText
						pcall(function()
							service:GetTextBoundsAsync(request)
						end)
					end
				elseif provider then
					local content = provider
					pcall(function()
						content:PreloadAsync(sources)
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
