--!strict
type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type Child = typeof(require("@repo/tools/typecheck/aliases").Child)
type UDim2Type = typeof(UDim2)

return function(Host: RobloxHost, dimensions: UDim2Type, children: { Child }): Frame
	local dock = Host.Frame "HomeDock" {
		Position = dimensions.new(0, 12, 1, -88),
		Size = dimensions.new(1, -24, 0, 80),
		Host.UICorner {},
		table.unpack(children),
	}
	dock:AddTag("facet-panel")
	return dock
end
