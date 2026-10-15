--!strict
local fade = {}

function fade.of(node: any): number
	if node:IsA("CanvasGroup") then
		return node.GroupTransparency
	end
	local paint = node:FindFirstChild("FadePaint")
	if paint then
		return paint.Transparency.Keypoints[1].Value
	end
	local group = node:FindFirstChild("Fade")
	return if group then group.GroupTransparency else if node.Visible then 0 else 1
end

function fade.layer(node: any): any
	local parent = node.Parent
	if parent and parent.Name == "Fade" and parent:IsA("CanvasGroup") then
		return parent.Parent
	end
	return parent
end

function fade.groups(root: any): number
	local count = 0
	for _, node in root:GetDescendants() do
		if node:IsA("CanvasGroup") then
			count += 1
		end
	end
	return count
end

return fade
