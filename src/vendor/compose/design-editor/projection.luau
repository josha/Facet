--!strict

local Compose = require "../core"
local Design = require "../design"
local Devices = require "./devices"
local UI = require "./ui"

local function project(
	ui: UI.UI,
	library: Design.Library,
	device: Devices.Profile,
	seen: { [Design.Library]: Design.Library }
): Design.Library
	if seen[library] then
		return seen[library]
	end
	local projected = table.clone(library)
	seen[library] = projected
	projected.kinds = {}
	for name, kind in library.kinds do
		local copy = table.clone(kind)
		if kind.design then
			local imported = table.clone(kind.design)
			imported.library = project(ui, imported.library, device, seen)
			copy.design = imported
		end
		copy.build = function(props: { [string]: Design.Resolved }, children: { unknown }, name: string): unknown
			local source = kind.build(props, children, name)
			if not ui.isA(source, "LayerCollector") then
				return source
			end
			local runtime = ui.runtime
			local enabled = runtime.observe(ui.node(source), "Enabled")
			local out: Compose.Props = {
				Name = name,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Visible = function(use: Compose.Use): boolean
					return use(enabled) == true
				end,
			}
			if ui.isA(source, "ScreenGui") then
				local mode = runtime.observe(ui.node(source), "ScreenInsets")
				local function area(use: Compose.Use): Devices.Rect
					local name = string.match(tostring(use(mode)), "([^%.]+)$") or "CoreUISafeInsets"
					return Devices.area(device, name)
				end
				out.Position = function(use: Compose.Use): unknown
					local rect = area(use)
					return ui.values.udim2(0, rect.x, 0, rect.y)
				end
				out.Size = function(use: Compose.Use): unknown
					local rect = area(use)
					return ui.values.udim2(0, rect.width, 0, rect.height)
				end
			elseif ui.isA(source, "BillboardGui") then
				local size = runtime.observe(ui.node(source), "Size")
				local offset = runtime.observe(ui.node(source), "StudsOffsetWorldSpace")
				local function pixels(use: Compose.Use): number
					return device.size.Y
						/ (
							2
							* math.tan(math.rad(device.fieldOfView) / 2)
							* math.max(0.01, 12 - ui.vector(use(offset)).Z)
						)
				end
				out.AnchorPoint = ui.values.vector2(0.5, 0.5)
				out.Position = function(use: Compose.Use): unknown
					local world = ui.vector(use(offset))
					local factor = pixels(use)
					return ui.values.udim2(0.5, world.X * factor, 0.5, -world.Y * factor)
				end
				out.Size = function(use: Compose.Use): unknown
					local value, factor = use(size), pixels(use)
					local x, y = ui.get(value, "X"), ui.get(value, "Y")
					return ui.values.udim2(
						0,
						ui.number(x, "Offset") + ui.number(x, "Scale") * factor,
						0,
						ui.number(y, "Offset") + ui.number(y, "Scale") * factor
					)
				end
			else
				error("Unsupported Design layer collector: " .. ui.text(source, "ClassName"))
			end
			for index, child in children do
				out[index] = ui.node(child)
			end
			return runtime.create "Frame"(out)
		end
		projected.kinds[name] = copy
	end
	return projected
end

return function(ui: UI.UI, library: Design.Library, device: Devices.Profile): Design.Library
	return project(ui, library, device, {})
end
