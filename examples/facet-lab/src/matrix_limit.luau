--!strict

return function(Compose: any, Host: any, node: GuiObject, available: any, vector: any?)
	local Vector = vector or Vector2
	Host.UISizeConstraint({
		Parent = Compose.static(node),
		Name = "MatrixLimit",
		MaxSize = Compose.formula(function(use: any)
			return Vector.new(math.max(0, use(available)), math.huge)
		end),
	})
	return node
end
