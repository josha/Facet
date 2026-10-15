--!strict

return function(object: GuiObject, ancestors: boolean): (ScrollingFrame?, number, number)
	local cursor = object.Parent
	while cursor ~= nil do
		if cursor:IsA("ScrollingFrame") and (not ancestors or cursor.ScrollingEnabled) then
			local at, size = object.AbsolutePosition, object.AbsoluteSize
			local frameAt, window = cursor.AbsolutePosition, cursor.AbsoluteWindowSize
			local deltaX, deltaY = 0, 0
			if at.Y < frameAt.Y then
				deltaY = at.Y - frameAt.Y - 8
			elseif at.Y + size.Y > frameAt.Y + window.Y then
				deltaY = at.Y + size.Y - (frameAt.Y + window.Y) + 8
			end
			if at.X < frameAt.X then
				deltaX = at.X - frameAt.X - 8
			elseif at.X + size.X > frameAt.X + window.X then
				deltaX = at.X + size.X - (frameAt.X + window.X) + 8
			end
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
