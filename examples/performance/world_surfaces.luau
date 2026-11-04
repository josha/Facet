--!strict
local Facet = require("../../src")

export type Context = {
	runtime: Facet.Runtime,
	UI: Facet.Controls,
	Host: Facet.Host,
	parent: Instance,
	adornee: BasePart,
	size: UDim2,
	count: number,
}

return function(c: Context): (Folder, () -> ())
	local Compose, UI, Host = Facet.Compose, c.UI, c.Host
	assert(c.count >= 1 and c.count % 1 == 0, "world surface count must be positive")
	local value = Compose.cell(0)
	local layers: { Instance } = {}
	local anchors: { Facet.Child } = {}
	for index = 1, c.count do
		local layer = Host.BillboardGui("PerfNameplate" .. index) {
			Adornee = Compose.static(c.adornee),
			Size = c.size,
			MaxDistance = 80,
		}
		table.insert(layers, layer)
		table.insert(
			anchors,
			UI.worldSurface(layer, function()
				return UI.Text {
					text = function(use: Facet.Use): string
						return `Target {index}: {use(value)}`
					end,
				}
			end)
		)
	end
	local root = Host.Folder "WorldSurfacePerf" {
		Compose.portal(c.parent, function()
			return layers
		end),
		table.unpack(anchors),
	}
	return root, function()
		value:update(function(previous)
			return previous + 1
		end)
	end
end
