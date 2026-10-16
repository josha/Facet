--!strict
type Context = {
	cell: typeof(require("@repo/tools/typecheck/aliases").CellFactory),
}
type Use = typeof(require("@repo/tools/typecheck/aliases").Use)
type ButtonProps = typeof(require("@repo/tools/typecheck/aliases").ButtonProps)

return function(c: Context, described: boolean): ButtonProps
	local width = c.cell(if described then "describedWidth" else "plainWidth", 140)
	return {
		label = "Change width",
		subtitle = if described then "Tap: 140, 220, then hug" else nil,
		Size = function(use: Use): UDim2
			return UDim2.fromOffset(use(width), 0)
		end,
		onActivate = function()
			local current = width:peek()
			width:set(if current == 140 then 220 elseif current == 220 then 0 else 140)
		end,
	}
end
