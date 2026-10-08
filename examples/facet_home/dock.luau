--!strict
type Runtime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type UDim2Type = typeof(UDim2)

return function(runtime: Runtime, dimensions: UDim2Type, children: { any }): Frame
	local Host = (runtime.constructors :: unknown) :: RobloxHost
	local dock = Host.Frame "HomeDock" {
		Position = dimensions.new(0, 12, 1, -88),
		Size = dimensions.new(1, -24, 0, 80),
		Host.UICorner {},
		table.unpack(children),
	}
	dock:AddTag("facet-panel")
	return dock
end
