--!strict
local Shared = require("./types")
local ComposeTypes = require("../vendor/compose/core")

export type Parts = {
	key: Shared.Input<Enum.KeyCode?>,
	name: Shared.Input<string?>?,
	primary: Shared.Input<Enum.KeyCode?>?,
	secondary: Shared.Input<Enum.KeyCode?>?,
	image: Shared.Input<Content?>?,
}
export type Glyph = (name: string, controlSize: Shared.Input<Shared.ControlSize?>?, parts: Parts) -> Frame

local KEY_NAMES: { [string]: string } = {
	Return = "Enter",
	KeypadEnter = "Enter",
	Escape = "Esc",
	Space = "Space",
	Backspace = "Delete",
	Tab = "Tab",
	LeftShift = "Shift",
	RightShift = "Shift",
	LeftControl = "Ctrl",
	RightControl = "Ctrl",
	LeftAlt = "Alt",
	RightAlt = "Alt",
}

return function(ctx: Shared.Context, noKey: Enum.KeyCode): Glyph
	local Host, Compose = ctx.Host, ctx.Compose
	local readContent = ctx.read<<Content?>>
	local readKey = ctx.read<<Enum.KeyCode?>>
	local readText = ctx.read<<string?>>
	local D2, E = ctx.types.UDim2, ctx.types.Enum
	return function(frameName: string, controlSize: Shared.Input<Shared.ControlSize?>?, parts: Parts): Frame
		local input = ctx.config.services.UserInputService
		local nativeImage = Compose.formula(function(use: ComposeTypes.Use): Content | string | nil
			local content = readContent(parts.image, use)
			if content and content.SourceType and content.SourceType.Name ~= "None" then
				return content
			end
			local code = readKey(parts.key, use)
			if code and input and input.GetImageForKeyCode then
				local ok, asset = pcall(input.GetImageForKeyCode, input, code)
				if ok and type(asset) == "string" and asset ~= "" then
					return asset
				end
			end
			return nil
		end)
		return Host.Frame(frameName)({
			Size = D2.fromOffset(0, 0),
			AutomaticSize = E.AutomaticSize.XY,
			BackgroundTransparency = 1,
			Compose.keyed({
				from = function(use: ComposeTypes.Use)
					local asset = use(nativeImage)
					return {
						if asset == nil then "text" elseif type(asset) == "string" then "Image" else "ImageContent",
					}
				end,
				render = function(_, _, kind: string): GuiObject
					if kind ~= "text" then
						local native: Shared.ImageLabelProps = {
							Name = "Glyph",
							BackgroundTransparency = 1,
							Size = function(use: ComposeTypes.Use)
								local size = ctx.controlSize(controlSize, "iconSize", use)
								return D2.fromOffset(size, size)
							end,
						}
						if kind ~= "Image" then
							native.ImageContent = function(use: ComposeTypes.Use): Content
								local asset = use(nativeImage)
								assert(typeof(asset) == "Content")
								return asset
							end
							return Host.ImageLabel(native)
						end
						native.Image = function(use: ComposeTypes.Use): string
							local asset = use(nativeImage)
							assert(type(asset) == "string")
							return asset
						end
						return ctx.styled(Host.ImageLabel(native), "shortcut-glyph")
					end
					return ctx.text({
						Name = "Key",
						Text = function(use: ComposeTypes.Use): string
							local custom = readText(parts.name, use)
							if custom and custom ~= "" then
								return custom
							end
							local keys: { string } = {}
							local service = input
							for _, code in
								{ readKey(parts.primary, use), readKey(parts.secondary, use), readKey(parts.key, use) }
							do
								if code and code ~= noKey then
									local ok, found = true, KEY_NAMES[code.Name] or ""
									if found == "" and service and service.GetStringForKeyCode then
										ok, found = pcall(function(): string
											return service:GetStringForKeyCode(code)
										end)
									end
									local text = if ok and type(found) == "string" then found else ""
									if string.match(text, "^%s*$") then
										text = KEY_NAMES[code.Name] or code.Name
									end
									table.insert(keys, text)
								end
							end
							return table.concat(keys, "+")
						end,
					})
				end,
			}),
		})
	end
end
