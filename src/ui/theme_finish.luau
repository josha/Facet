--!strict
local ThemeTypes = require("./theme_types")

local PLATES = ".facet-panel::UIStroke, .facet-sheet::UIStroke"
local SHADOW = "finish"
local GLOW_STRENGTH = 0.55
local LIFT_STRENGTH = 0.35

type Table = { [string]: unknown }

local function amount(value: unknown): number?
	return if type(value) == "number" and value == value and value >= 0 and value < math.huge then value else nil
end

local function color(palette: ThemeTypes.Palette, role: string): ThemeTypes.RGB?
	local found: unknown = palette.colors[role]
	if found == nil and palette.extra then
		found = (palette.extra :: Table)[role]
	end
	local rgb = found :: Table
	if type(found) == "table" and amount(rgb.r) and amount(rgb.g) and amount(rgb.b) then
		return (found :: unknown) :: ThemeTypes.RGB
	end
	return nil
end

local function apply(package: ThemeTypes.ThemePackage, finish: unknown): { ThemeTypes.ThemeIssue }
	local issues: { ThemeTypes.ThemeIssue } = {}
	local function issue(field: string, message: string)
		table.insert(issues, { field = "finish" .. field, message = message })
	end
	if type(finish) ~= "table" then
		issue("", "finish is a table with edge and depth")
		return issues
	end
	local stated = finish :: Table
	local edge, depth = stated.edge :: Table, stated.depth :: Table
	if type(edge) ~= "table" then
		issue(".edge", "State the edge. For no edge, use edge = { width = 0 }")
	end
	if type(depth) ~= "table" then
		issue(".depth", "State the depth. For a flat plate, use depth = { lift = 0, glow = 0, sheen = 0 }")
	end
	if #issues > 0 then
		return issues
	end
	local style = package.style
	local palette = style.themes[1]
	for _, candidate in style.themes do
		if candidate.name == style.defaultTheme then
			palette = candidate
		end
	end
	local function paint(field: string, role: unknown, fallback: string): (ThemeTypes.RGB?, string)
		local name = if role == nil then fallback else role
		if type(name) ~= "string" then
			issue(field, "A role is the name of a palette color")
			return nil, fallback
		end
		local found = color(palette, name)
		if found == nil then
			issue(field, `The palette {palette.name} has no color {name}`)
		end
		return found, name
	end
	local function measure(field: string, value: unknown, required: boolean): number
		local read = amount(value)
		if read == nil and (required or value ~= nil) then
			issue(field, "Give a number of 0 or more")
		end
		return read or 0
	end
	local function share(field: string, value: unknown, fallback: number): number
		local read = if value == nil then fallback else amount(value)
		if read == nil or read > 1 then
			issue(field, "Give a number from 0 to 1")
			return fallback
		end
		return read
	end

	local width = measure(".edge.width", edge.width, true)
	local _, line = paint(".edge.role", edge.role, "hairline")
	local faint = share(".edge.transparency", edge.transparency, 0)
	local lift = measure(".depth.lift", depth.lift, true)
	local glow = measure(".depth.glow", depth.glow, true)
	local sheen = amount(depth.sheen) or -1
	if sheen < 0 or sheen > 1 then
		issue(".depth.sheen", "Give a number from 0 to 1")
		sheen = 0
	end
	local blur = measure(".depth.blur", depth.blur, false)
	local side = measure(".depth.side", depth.side, false)
	local tint, tintName = paint(".depth.role", depth.role, if glow > 0 then "accent" else "content")
	local strength = share(".depth.strength", depth.strength, if glow > 0 then GLOW_STRENGTH else LIFT_STRENGTH)
	if depth.controls ~= nil and type(depth.controls) ~= "boolean" then
		issue(".depth.controls", "controls is true or false")
	end
	if lift > 0 and glow > 0 then
		issue(".depth", "A plate has one shadow. Give lift or glow, and 0 for the other")
	end
	if #issues > 0 then
		return issues
	end

	if width > 0 then
		local properties: ThemeTypes.AuthoredRuleProperties = {
			Color = { role = line },
			Thickness = width,
			Transparency = faint,
		}
		if package.metrics.radii.panel == 0 then
			properties.LineJoinMode = "Miter"
		end
		local rules = table.clone(package.rules or {})
		table.insert(rules, { selector = PLATES, properties = properties })
		package.rules = rules
	end

	if (lift > 0 or glow > 0) and tint then
		local shadow: ThemeTypes.Shadow = if glow > 0
			then {
				color = tint,
				transparency = 1 - strength,
				blurRadius = { offset = glow },
				offset = { x = { offset = 0 }, y = { offset = 0 } },
			}
			else {
				color = if depth.role == nil then { r = 0, g = 0, b = 0 } else tint,
				transparency = 1 - strength,
				blurRadius = { offset = if depth.blur == nil then lift * 2 else blur },
				offset = { x = { offset = side }, y = { offset = lift } },
			}
		local shadows = table.clone(style.shadows or {})
		shadows[SHADOW] = shadow
		style.shadows = shadows
		local chrome = package.chrome :: { [string]: Table }
		for _, slot in if depth.controls == true then { "panel", "control" } else { "panel" } do
			local layer = chrome[slot]
			if layer == nil then
				chrome[slot] = { kind = "native", shadow = SHADOW }
			elseif type(layer) == "table" and layer.kind == "native" then
				layer.shadow = SHADOW
			end
		end
	end

	if sheen > 0 then
		for _, each in style.themes do
			local lit = color(each, tintName) or tint
			if lit then
				local extra = (each.extra or {}) :: Table
				local gradients = table.clone((extra.chromeGradient or {}) :: Table)
				gradients.panel = {
					rotation = 90,
					stops = { { t = 0, r = lit.r, g = lit.g, b = lit.b }, { t = 1, r = lit.r, g = lit.g, b = lit.b } },
					alpha = { { t = 0, v = sheen }, { t = 1, v = 0 } },
				}
				extra.chromeGradient = gradients
				each.extra = (extra :: unknown) :: ThemeTypes.PaletteExtra
			end
		end
	end
	return issues
end

return { apply = apply }
