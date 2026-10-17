--!strict
export type Fault = { element: string, ancestor: string, overflow: { number }, text: string, reason: string }

local function inspect(root: Instance): ({ Fault }, number)
	local faults: { Fault } = {}
	local sampled = 0
	local nodes = root:GetDescendants()
	table.insert(nodes, root)
	for _, node in nodes do
		if not (node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox")) then
			continue
		end
		local words = if node.Text ~= "" then node.Text elseif node:IsA("TextBox") then node.PlaceholderText else ""
		if words == "" or node.TextTransparency >= 1 then
			continue
		end
		local low, high = node.AbsolutePosition, node.AbsolutePosition + node.AbsoluteSize
		local visible = node.Visible and node.AbsoluteSize.X > 0 and node.AbsoluteSize.Y > 0
		local clips: { GuiObject } = {}
		local at = node.Parent
		while at do
			if at:IsA("GuiObject") then
				visible = visible and at.Visible and (not at:IsA("CanvasGroup") or at.GroupTransparency < 1)
				if at.ClipsDescendants or at:IsA("CanvasGroup") then
					table.insert(clips, at)
					local ending = at.AbsolutePosition + at.AbsoluteSize
					low = Vector2.new(math.max(low.X, at.AbsolutePosition.X), math.max(low.Y, at.AbsolutePosition.Y))
					high = Vector2.new(math.min(high.X, ending.X), math.min(high.Y, ending.Y))
				end
			elseif at:IsA("LayerCollector") then
				visible = visible and at.Enabled
			end
			at = at.Parent
		end
		if not visible or high.X <= low.X or high.Y <= low.Y then
			continue
		end
		sampled += 1
		if not node:IsA("TextBox") and not node.TextFits and node.TextTruncate == Enum.TextTruncate.None then
			table.insert(faults, {
				element = node:GetFullName(),
				ancestor = node:GetFullName(),
				text = words,
				reason = "TextFits is false",
				overflow = {
					math.max(0, node.TextBounds.X - node.AbsoluteSize.X),
					math.max(0, node.TextBounds.Y - node.AbsoluteSize.Y),
				},
			})
		end
		local position, ending = node.AbsolutePosition, node.AbsolutePosition + node.AbsoluteSize
		for _, clip in clips do
			if clip:IsA("ScrollingFrame") then
				local boundary = clip.AbsolutePosition + clip.AbsoluteSize
				position = Vector2.new(
					math.max(position.X, clip.AbsolutePosition.X),
					math.max(position.Y, clip.AbsolutePosition.Y)
				)
				ending = Vector2.new(math.min(ending.X, boundary.X), math.min(ending.Y, boundary.Y))
				continue
			end
			local boundary = clip.AbsolutePosition + clip.AbsoluteSize
			local overflow = {
				math.max(0, clip.AbsolutePosition.X - position.X),
				math.max(0, clip.AbsolutePosition.Y - position.Y),
				math.max(0, ending.X - boundary.X),
				math.max(0, ending.Y - boundary.Y),
			}
			if math.max(table.unpack(overflow)) > 0.5 then
				table.insert(faults, {
					element = node:GetFullName(),
					ancestor = clip:GetFullName(),
					overflow = overflow,
					text = words,
					reason = "clipping ancestor overflow: left, top, right, bottom",
				})
			end
		end
	end
	return faults, sampled
end

return { inspect = inspect }
