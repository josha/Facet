--!strict

local function delta(at: number, size: number, frameAt: number, window: number): number
	if size > window + 1 then
		if at > frameAt + 1 then
			return at - frameAt
		elseif at + size < frameAt + window - 1 then
			return at + size - (frameAt + window)
		end
		return 0
	end
	if at < frameAt then
		return at - frameAt - 8
	elseif at + size > frameAt + window then
		return at + size - (frameAt + window) + 8
	end
	return 0
end

return function(object: GuiObject, ancestors: boolean): (ScrollingFrame?, number, number)
	local cursor = object.Parent
	while cursor ~= nil do
		if cursor:IsA("ScrollingFrame") and (not ancestors or cursor.ScrollingEnabled) then
			local at, size = object.AbsolutePosition, object.AbsoluteSize
			local frameAt, window = cursor.AbsolutePosition, cursor.AbsoluteWindowSize
			local deltaX = delta(at.X, size.X, frameAt.X, window.X)
			local deltaY = delta(at.Y, size.Y, frameAt.Y, window.Y)
			if not ancestors then
				return cursor, deltaX, deltaY
			end
			local canvas, direction = cursor.AbsoluteCanvasSize, cursor.ScrollingDirection.Name
			if direction == "X" or canvas.Y <= window.Y then
				deltaY = 0
			end
			if direction == "Y" or canvas.X <= window.X then
				deltaX = 0
			end
			if deltaX ~= 0 or deltaY ~= 0 then
				return cursor, deltaX, deltaY
			end
		end
		if cursor:IsA("LayerCollector") then
			return nil, 0, 0
		end
		cursor = cursor.Parent
	end
	return nil, 0, 0
end
