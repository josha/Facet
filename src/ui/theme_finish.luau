--!strict
local ThemeTypes = require("./theme_types")

local PLATES = ".facet-panel::UIStroke, .facet-sheet::UIStroke"
local CONTROLS = ".facet-button::UIStroke, .facet-stepper-button::UIStroke"
local PLAIN = ".facet-button.facet-appearance-bare::UIStroke, .facet-button.facet-appearance-link::UIStroke"
local UTILITY = ".facet-button.facet-appearance-utility::UIStroke"
local DISABLED_EDGE = 0.6
local SHADOW = "finish"
local GLOW_STRENGTH = 0.55
local LIFT_STRENGTH = 0.35
local FAINT_GLOW = 8
local FAINT_STRENGTH = 0.4

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

local function apply(
	package: ThemeTypes.ThemePackage,
	finish: unknown
): ({ ThemeTypes.ThemeIssue }, { ThemeTypes.ThemeIssue })
	local issues: { ThemeTypes.ThemeIssue } = {}
	local advice: { ThemeTypes.ThemeIssue } = {}
	local function issue(field: string, message: string)
		table.insert(issues, { field = "finish" .. field, message = message })
	end
	if type(finish) ~= "table" then
		issue("", "finish is a table with edge and depth")
		return issues, advice
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
		return issues, advice
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
	local onControls = edge.controls
	local own: Table? = if type(onControls) == "table" then onControls :: Table else nil
	if onControls ~= nil and type(onControls) ~= "boolean" and own == nil then
		issue(".edge.controls", "controls is true, false or a table with width, role and transparency")
	end
	local controlWidth, controlLine, controlFaint = width, line, faint
	if own then
		controlWidth = if own.width == nil then width else measure(".edge.controls.width", own.width, true)
		if own.role ~= nil then
			local _, named = paint(".edge.controls.role", own.role, line)
			controlLine = named
		end
		controlFaint = share(".edge.controls.transparency", own.transparency, faint)
	end
	if lift > 0 and glow > 0 then
		issue(".depth", "A plate has one shadow. Give lift or glow, and 0 for the other")
	end
	if #issues > 0 then
		return issues, advice
	end
	if glow > 0 and (glow < FAINT_GLOW or strength < FAINT_STRENGTH) then
		table.insert(advice, {
			field = "finish.depth.glow",
			message = ("A glow of %d px at strength %.2f is usually too faint to see. On a dark ground a glow read as light from about 12 px at 0.5 in our captures, and a bright ground needed more. Look at the specimen: when the capture does not show the glow, raise it or state glow = 0."):format(
				glow,
				strength
			),
		})
	end
	if onControls == true and width >= 2 and faint < 0.5 then
		table.insert(advice, {
			field = "finish.edge.controls",
			message = ("The controls take the same %d px %s line as the plates. A plate that holds several controls then shows as many equal lines, and the main action is one outline among them. When the direction shows a quieter line on the controls, state it: controls = { width = 1, transparency = 0.5 }. Keep true when the direction shows one line on both."):format(
				width,
				line
			),
		})
	end

	local rules = table.clone(package.rules or {})
	if width > 0 then
		table.insert(rules, {
			selector = PLATES,
			properties = {
				Color = { role = line },
				Thickness = width,
				Transparency = faint,
				BorderStrokePosition = "Inner",
				LineJoinMode = if package.metrics.radii.panel == 0 then "Miter" else nil,
			},
		})
	end
	if (onControls == true or own ~= nil) and controlWidth > 0 then
		table.insert(rules, {
			selector = CONTROLS,
			properties = {
				Color = { role = controlLine },
				Thickness = controlWidth,
				Transparency = controlFaint,
				BorderStrokePosition = "Inner",
				LineJoinMode = if package.metrics.radii.control == 0 then "Miter" else nil,
			},
		})
		table.insert(rules, {
			selector = ".facet-button.facet-disabled::UIStroke",
			properties = { Transparency = math.max(controlFaint, DISABLED_EDGE) },
		})
		local utility = package.metrics.strokes.utility
		local outlined = type(utility) == "number" and utility > 0
		table.insert(rules, {
			selector = if outlined then PLAIN else PLAIN .. ", " .. UTILITY,
			properties = { Transparency = 1 },
		})
		if outlined then
			table.insert(rules, {
				selector = UTILITY,
				properties = { Color = { role = "hairline" }, Thickness = utility },
			})
		end
	end
	if #rules > #(package.rules or {}) then
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
	return issues, advice
end

return { apply = apply }
