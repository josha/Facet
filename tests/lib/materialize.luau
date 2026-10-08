--!strict
local materialize = {}
function materialize.of(panel: any): any
	return setmetatable({}, {
		__index = function(_, key)
			assert(key == "Scale")
			local uniform = panel:FindFirstChild("PresentationScale", true)
			if uniform then
				return uniform.Scale
			end
			local content = panel:FindFirstChild("PresentationContent", true)
			if content == nil then
				return 1
			end
			local plate = panel:FindFirstChild("PresentationPaint", true) or panel
			local width = content.Size.X.Offset
			local padding = plate:FindFirstChildWhichIsA("UIPadding")
			if padding then
				width += padding.PaddingLeft.Offset + padding.PaddingRight.Offset
			end
			return if width > 0 then plate.Size.X.Offset / width else 1
		end,
	})
end
function materialize.position(panel: any): any
	local size = panel.AbsoluteSize
	if panel:FindFirstChild("PresentationContent", true) then
		size = require("@lune/roblox").Vector2.new(panel.Size.X.Offset, panel.Size.Y.Offset)
	end
	local paint = panel:FindFirstChild("PresentationPaint", true)
	if paint then
		local position, anchor = panel.Position, panel.AnchorPoint
		local rest = panel.Size
		local pivot = paint.AnchorPoint
		local uniform = paint:FindFirstChild("PresentationScale")
		local factor = if uniform then uniform.Scale else 1
		return require("@lune/roblox").UDim2.new(
			position.X.Scale,
			position.X.Offset - anchor.X * rest.X.Offset + pivot.X * (rest.X.Offset - paint.Size.X.Offset * factor),
			position.Y.Scale,
			position.Y.Offset - anchor.Y * rest.Y.Offset + pivot.Y * (rest.Y.Offset - paint.Size.Y.Offset * factor)
		)
	end
	local position, anchor = panel.Position, panel.AnchorPoint
	return require("@lune/roblox").UDim2.new(
		position.X.Scale,
		position.X.Offset - anchor.X * size.X,
		position.Y.Scale,
		position.Y.Offset - anchor.Y * size.Y
	)
end
return materialize
