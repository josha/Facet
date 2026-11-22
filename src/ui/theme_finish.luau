--!strict
local ThemeTypes = require("./theme_types")
local support = require("./theme_support")

local PLATES = ".facet-panel::UIStroke, .facet-sheet::UIStroke"
local CONTROLS = ".facet-button::UIStroke, .facet-stepper-button::UIStroke"
local PLAIN = ".facet-button.facet-appearance-bare::UIStroke, .facet-button.facet-appearance-link::UIStroke, "
	.. ".facet-button.facet-toggle-row::UIStroke, .facet-button.facet-toggle-plain::UIStroke"
local UTILITY = ".facet-button.facet-appearance-utility::UIStroke"
local DISABLED_EDGE = 0.6
local SHADOW = "finish"
local CONTROL_SHADOW = "finishControl"
local PLATE_SHADOW = "finishPlate."
local PLATE_SLOT = "plate-"
local GLOW_STRENGTH = 0.55
local LIFT_STRENGTH = 0.35
local FAINT_GLOW = 8
local FAINT_STRENGTH = 0.4

type Table = { [string]: unknown }

local LOOKS: { [string]: { edge: Table, depth: Table } } = {
	flat = { edge = { width = 0 }, depth = { lift = 0, glow = 0, sheen = 0 } },
	raised = {
		edge = { width = 1, transparency = 0.5 },
		depth = { lift = 8, blur = 24, glow = 0, sheen = 0.2, strength = 0.55, controls = { lift = 3 } },
	},
	glow = {
		edge = { width = 2, role = "accent", transparency = 0.1, controls = { width = 1, transparency = 0.4 } },
		depth = { lift = 0, glow = 28, sheen = 0.14, strength = 0.85 },
	},
	hard = {
		edge = { width = 3, role = "content", controls = { width = 2 } },
		depth = { lift = 6, blur = 0, glow = 0, sheen = 0, strength = 1, controls = { lift = 4 } },
	},
}

local function over(base: Table, stated: unknown): Table
	local out = table.clone(base)
	if type(stated) == "table" then
		for key, value in stated :: Table do
			out[key] = value
		end
	end
	return out
end

local function amount(value: unknown): number?
	return if type(value) == "number" and value == value and value >= 0 and value < math.huge then value else nil
end

local function color(palette: ThemeTypes.Palette, role: string): ThemeTypes.RGB?
	local found: unknown = if palette.colors then palette.colors[role] else nil
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
	finish: unknown,
	neutral: ThemeTypes.ReadOnlyThemePackage
): ({ ThemeTypes.ThemeIssue }, { ThemeTypes.ThemeIssue })
	local issues: { ThemeTypes.ThemeIssue } = {}
	local advice: { ThemeTypes.ThemeIssue } = {}
	local function issue(field: string, message: string)
		table.insert(issues, { field = "finish" .. field, message = message })
	end
	if type(finish) ~= "table" then
		issue("", "finish is a table with a look, or with edge and depth")
		return issues, advice
	end
	local stated = finish :: Table
	local look = if stated.look == nil then nil else LOOKS[stated.look :: string]
	if stated.look ~= nil and look == nil then
		issue(".look", "look is flat, raised, glow or hard")
		return issues, advice
	end
	if look == nil and type(stated.edge) ~= "table" then
		issue(".edge", "State the edge. For no edge, use edge = { width = 0 }")
	end
	if look == nil and type(stated.depth) ~= "table" then
		issue(".depth", "State the depth. For a flat plate, use depth = { lift = 0, glow = 0, sheen = 0 }")
	end
	if #issues > 0 then
		return issues, advice
	end
	local edge: Table = if look then over(look.edge, stated.edge) else stated.edge :: Table
	local depth: Table = if look then over(look.depth, stated.depth) else stated.depth :: Table
	if look then
		for _, part in { { look.edge, stated.edge, edge }, { look.depth, stated.depth, depth } } do
			local named: unknown = (part[1] :: Table).controls
			local own: unknown = if type(part[2]) == "table" then (part[2] :: Table).controls else nil
			if type(named) == "table" and type(own) == "table" then
				(part[3] :: Table).controls = over(named :: Table, own)
			end
		end
		local low: unknown, rest = look.depth.controls, amount(look.depth.lift) or 0
		local given: Table = if type(stated.depth) == "table" then stated.depth :: Table else {}
		local raisedTo = amount(given.lift)
		if type(low) == "table" and given.controls == nil and raisedTo and rest > 0 then
			local scaled = table.clone(low :: Table)
			scaled.lift = (amount(scaled.lift) or 0) * raisedTo / rest
			depth.controls = scaled
		end
	end
	if look and type(stated.depth) == "table" then
		local own = stated.depth :: Table
		local lifts, glows = amount(own.lift) or 0, amount(own.glow) or 0
		local turned = (lifts > 0 and own.glow == nil and (amount(look.depth.glow) or 0) > 0)
			or (glows > 0 and own.lift == nil and (amount(look.depth.lift) or 0) > 0)
		if turned then
			depth.lift, depth.glow = lifts, glows
			depth.blur, depth.side, depth.strength = own.blur, own.side, own.strength
		end
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
		local found = color(palette, name) or color(support.neutralBase(neutral, palette.colors), name)
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
	local held: unknown = depth.controls
	local low: Table? = if type(held) == "table" then held :: Table else nil
	if held ~= nil and type(held) ~= "boolean" and low == nil then
		issue(".depth.controls", "controls is true, false or a table with lift, side and shade")
	end
	local controlLift = if low == nil or low.lift == nil then lift else measure(".depth.controls.lift", low.lift, true)
	local shade: number? = if low and low.shade ~= nil then share(".depth.controls.shade", low.shade, 0) else nil
	local controlSide: number? = if low and low.side ~= nil
		then measure(".depth.controls.side", low.side, true)
		else nil
	type Variant = {
		name: string,
		width: number,
		line: string,
		faint: number,
		shadow: ThemeTypes.Shadow?,
		deep: boolean,
	}
	local function cast(at: string, part: Table, drop: number, halo: number, color: ThemeTypes.RGB?): ThemeTypes.Shadow?
		local soft = measure(at .. ".blur", part.blur, false)
		local across = measure(at .. ".side", part.side, false)
		local seen = share(at .. ".strength", part.strength, if halo > 0 then GLOW_STRENGTH else LIFT_STRENGTH)
		if (drop <= 0 and halo <= 0) or color == nil then
			return nil
		end
		return if halo > 0
			then {
				color = color,
				transparency = 1 - seen,
				blurRadius = { offset = halo },
				offset = { x = { offset = 0 }, y = { offset = 0 } },
			}
			else {
				color = if part.role == nil then { r = 0, g = 0, b = 0 } else color,
				transparency = 1 - seen,
				blurRadius = { offset = if part.blur == nil then drop * 2 else soft },
				offset = { x = { offset = across }, y = { offset = drop } },
			}
	end
	local variants: { Variant } = {}
	if stated.plates ~= nil and type(stated.plates) ~= "table" then
		issue(".plates", "plates is a table of named plates")
	elseif stated.plates ~= nil then
		for name, part in stated.plates :: { [unknown]: unknown } do
			local at = ".plates." .. tostring(name)
			if type(name) ~= "string" or string.match(name, "^%a%w*$") == nil or type(part) ~= "table" then
				issue(
					at,
					"A plate has a name that starts with a letter and has letters and digits, and a table with edge or depth"
				)
				continue
			end
			local own = part :: Table
			local sound = true
			for key, value in own do
				if (key ~= "edge" and key ~= "depth") or type(value) ~= "table" then
					issue(
						`{at}.{tostring(key)}`,
						"A plate has edge = { width, role, transparency } and depth = { lift, blur, side, glow, strength, role }"
					)
					sound = false
				end
			end
			if not sound then
				continue
			end
			local rim, body = over(edge, own.edge), over(depth, own.depth)
			local said: Table = if type(own.depth) == "table" then own.depth :: Table else {}
			if said.sheen ~= nil or said.controls ~= nil then
				issue(
					at .. ".depth",
					"A plate states lift, glow, blur, side, strength and role. The sheen and the controls belong to the theme"
				)
			end
			if type(own.edge) == "table" and (own.edge :: Table).controls ~= nil then
				issue(at .. ".edge", "A plate states width, role and transparency. The controls belong to the theme")
			end
			local up, lit = amount(said.lift) or 0, amount(said.glow) or 0
			if (up > 0 and said.glow == nil and glow > 0) or (lit > 0 and said.lift == nil and lift > 0) then
				body.lift, body.glow = up, lit
				body.blur, body.side, body.strength, body.role = said.blur, said.side, said.strength, said.role
			elseif up > 0 and lift > 0 and glow <= 0 then
				local ratio = up / lift
				if said.blur == nil then
					body.blur = (if depth.blur == nil then lift * 2 else blur) * ratio
				end
				if said.side == nil then
					body.side = side * ratio
				end
			end
			local _, named = paint(at .. ".edge.role", rim.role, "hairline")
			local drop = measure(at .. ".depth.lift", body.lift, true)
			local halo = measure(at .. ".depth.glow", body.glow, true)
			if drop > 0 and halo > 0 then
				issue(at .. ".depth", "A plate has one shadow. Give lift or glow, and 0 for the other")
			end
			local shown = paint(at .. ".depth.role", body.role, if halo > 0 then "accent" else "content")
			table.insert(variants, {
				name = name,
				width = measure(at .. ".edge.width", rim.width, true),
				line = named,
				faint = share(at .. ".edge.transparency", rim.transparency, 0),
				shadow = cast(at .. ".depth", body, drop, halo, shown),
				deep = said.lift ~= nil or said.glow ~= nil,
			})
		end
		table.sort(variants, function(a: Variant, b: Variant): boolean
			return a.name < b.name
		end)
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

		table.insert(rules, {
			selector = ".facet-outline-floating",
			properties = { Color3 = { role = line }, Thickness = width, Transparency = faint },
		})
		table.insert(rules, { selector = ".facet-outlined::UIStroke", properties = { Transparency = 1 } })
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

	local shadows = table.clone(style.shadows or {})
	if package.chrome == nil then
		package.chrome = {}
	end
	local chrome = package.chrome :: { [string]: Table }
	local pending: { { variant: Variant, key: string } } = {}
	for _, variant in variants do
		table.insert(rules, {
			selector = `.facet-plate-{variant.name}::UIStroke`,
			properties = {
				Color = { role = variant.line },
				Thickness = variant.width,
				Transparency = if variant.width > 0 then variant.faint else 1,
				BorderStrokePosition = "Inner",
				LineJoinMode = if package.metrics.radii.panel == 0 then "Miter" else nil,
			},
		})
		if variant.width > 0 then
			table.insert(rules, {
				selector = `.facet-plate-{variant.name}.facet-disabled::UIStroke`,
				properties = { Transparency = math.max(variant.faint, DISABLED_EDGE) },
			})
		end
		local key = PLATE_SHADOW .. variant.name
		shadows[key] = variant.shadow
		table.insert(pending, { variant = variant, key = key })
	end
	if #variants > 0 then
		package.rules = rules
		style.shadows = shadows
	end
	local shadow = if tint then cast(".depth", depth, lift, glow, tint) else nil
	local near: ThemeTypes.Shadow? = nil
	if glow <= 0 and low ~= nil and controlLift > 0 and tint then
		if controlLift ~= lift or shade ~= nil or controlSide ~= nil or shadow == nil then
			local ratio = if lift > 0 then controlLift / lift else 1
			local base: Table = table.clone(depth)
			base.blur = (if depth.blur == nil then (if lift > 0 then lift else controlLift) * 2 else blur) * ratio
			base.side = controlSide or side * ratio
			near = cast(".depth", base, controlLift, 0, tint)
			if near then
				near.shade = shade
			end
		end
	end
	if shadow or near then
		if shadow then
			shadows[SHADOW] = shadow
		end
		if near then
			shadows[CONTROL_SHADOW] = near
		end
		style.shadows = shadows
		local slots: { [string]: string? } = { panel = if shadow then SHADOW else nil }
		if held == true or (low ~= nil and glow > 0) then
			slots.control = if shadow then SHADOW else nil
		elseif low ~= nil and controlLift > 0 then
			slots.control = if near then CONTROL_SHADOW elseif shadow then SHADOW else nil
		end
		for slot, name in slots do
			local layer = chrome[slot]
			if layer == nil then
				chrome[slot] = { kind = "native", shadow = name }
			elseif type(layer) == "table" and layer.kind == "native" then
				layer.shadow = name
			end
		end
	end

	for _, entry in pending do
		local variant, panel = entry.variant, chrome.panel
		local layer: Table = if type(panel) == "table" then table.clone(panel) else { kind = "native" }
		if layer.kind == nil or layer.kind == "native" then
			if variant.shadow then
				layer.shadow = entry.key
			elseif variant.deep then
				layer.shadow = nil
			end
		end
		chrome[PLATE_SLOT .. variant.name] = layer
	end

	if sheen > 0 then
		for _, each in style.themes do
			local lit = color(each, tintName) or color(support.neutralBase(neutral, each.colors), tintName) or tint
			if lit then
				local extra = (each.extra or {}) :: Table
				local gradients = table.clone((extra.chromeGradient or {}) :: Table)
				gradients.panel = {
					wash = "surfaceStrong",
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
