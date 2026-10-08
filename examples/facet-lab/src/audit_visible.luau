--!strict

return function(node: GuiObject): boolean
	local p, s = node.AbsolutePosition, node.AbsoluteSize
	local left, top = p.X, p.Y
	local right, bottom = p.X + math.max(1, s.X), p.Y + math.max(1, s.Y)
	local at: Instance? = node
	while at do
		if at:IsA("LayerCollector") and not (at :: LayerCollector).Enabled then
			return false
		elseif at:IsA("GuiObject") then
			local gui = at :: GuiObject
			if not gui.Visible or (gui:IsA("CanvasGroup") and (gui :: CanvasGroup).GroupTransparency >= 1) then
				return false
			end
			if gui ~= node and gui.ClipsDescendants then
				local position, size = gui.AbsolutePosition, gui.AbsoluteSize
				left, top = math.max(left, position.X), math.max(top, position.Y)
				right, bottom = math.min(right, position.X + size.X), math.min(bottom, position.Y + size.Y)
				if right <= left or bottom <= top then
					return false
				end
			end
		end
		at = at.Parent
	end
	return true
end
