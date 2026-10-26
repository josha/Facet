--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type Host = typeof(require("@repo/tools/typecheck/aliases").Host)
type ReadOnlyValue<T> = { peek: (ReadOnlyValue<T>) -> T }

return function(
	Compose: ComposeModule,
	Host: Host,
	node: GuiObject,
	available: ReadOnlyValue<number>,
	vector: typeof(Vector2)?
): GuiObject
	local Vector = vector or Vector2
	Host.UISizeConstraint({
		Parent = Compose.static(node),
		Name = "MatrixLimit",
		MaxSize = Compose.formula(function(use)
			return Vector.new(math.max(0, use(available)), math.huge)
		end),
	})
	return node
end
