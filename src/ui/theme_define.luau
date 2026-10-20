--!strict
local ComposeTypes = require("../vendor/compose/core")
local ThemeTypes = require("./theme_types")
local support = require("./theme_support")

local copy, merge, frozen, shadowPresets = support.copy, support.merge, support.frozen, support.shadowPresets

export type Definitions = {
	define: (
		ThemeTypes.ThemeDefinition | ThemeTypes.ThemePackage
	) -> (ThemeTypes.ThemePackage?, ThemeTypes.ThemeReport),
	checkCoverage: (ThemeTypes.ThemePackage, { ThemeTypes.CoverageNeed }) -> ThemeTypes.CoverageReport,
}

local EASING_STYLES: { [string]: boolean } = {
	Linear = true,
	Sine = true,
	Back = true,
	Quad = true,
	Quart = true,
	Quint = true,
	Bounce = true,
	Elastic = true,
	Exponential = true,
	Circular = true,
	Cubic = true,
}

local derivedTypeRoles: { [string]: { base: string, weight: string } } = {
	strong = { base = "body", weight = "SemiBold" },
	numeral = { base = "control", weight = "Bold" },
}

local function checkCoverage(
	package: ThemeTypes.ThemePackage,
	needs: { ThemeTypes.CoverageNeed }
): ThemeTypes.CoverageReport
	local missing: { { name: string, message: string, fix: string } }, covered: { string } = {}, {}
	for _, need in needs do
		local section: unknown = package
		for key in string.gmatch(need.section or "metrics", "[^.]+") do
			section = if type(section) == "table" then (section :: { [string]: unknown })[key] else nil
		end
		local present = true
		if need.kind == "color" then
			for _, palette in package.style.themes do
				if (palette.colors or {})[need.name] == nil and (palette.extra or {})[need.name] == nil then
					present = false
				end
			end
		else
			local value = if type(section) == "table" then (section :: { [string]: unknown })[need.name] else nil
			present = value ~= nil and (need.kind ~= "number" or type(value) == "number")
			for _, field in (need.fields or {}) :: { string } do
				if type(value) ~= "table" or type((value :: { [string]: unknown })[field]) ~= "number" then
					present = false
				end
			end
		end
		if present then
			table.insert(covered, need.name)
		else
			table.insert(missing, {
				name = need.name,
				message = "Theme has no " .. need.name,
				fix = "Declare " .. (need.section or "metrics") .. "." .. need.name,
			})
		end
	end
	return { ok = #missing == 0, missing = missing, covered = covered }
end

return function(neutral: ThemeTypes.ThemePackage, schema: string, typeRoles: { string }): Definitions
	local function define(
		inputDefinition: ThemeTypes.ThemeDefinition | ThemeTypes.ThemePackage
	): (ThemeTypes.ThemePackage?, ThemeTypes.ThemeReport)
		local definition = (inputDefinition :: unknown) :: ThemeTypes.ThemeDefinition
		local errors: { ThemeTypes.ThemeIssue } = {}
		local seen: { [unknown]: boolean } = {}
		local function validate(value: unknown, path: string)
			if type(value) == "number" and (value ~= value or math.abs(value) == math.huge) then
				table.insert(errors, { field = path, message = "Theme numbers must be finite" })
			elseif type(value) == "function" then
				table.insert(errors, { field = path, message = "Theme packages contain data, not callbacks" })
			elseif type(value) == "table" then
				if seen[value] then
					table.insert(errors, { field = path, message = "Theme packages cannot contain cycles" })
					return
				end
				seen[value] = true
				for key, child in value :: { [unknown]: unknown } do
					validate(child, path .. "." .. tostring(key))
				end
				seen[value] = nil
			end
		end
		if type(definition) ~= "table" then
			return nil,
				{
					ok = false,
					errors = { { field = "package", message = "Expected a package definition" } },
					missing = {},
					contrast = {},
				}
		end
		if definition.base ~= nil and type(definition.base) ~= "table" then
			table.insert(errors, { field = "base", message = "Theme base must be a package" })
		end
		validate(definition, "package")
		if #errors > 0 then
			return nil, { ok = false, errors = errors, missing = {}, contrast = {} }
		end
		local base = copy(definition.base or neutral)
		if type(base.style) == "table" and type(base.style.themes) == "table" and #base.style.themes > 1 then
			base.style.themes = { base.style.themes[1] }
		end
		local package = merge(base, definition)
		if type(package.identity) ~= "table" or type(package.identity.id) ~= "string" then
			table.insert(errors, { field = "identity.id", message = "A theme package needs an identity" })
		end
		if type(package.style) ~= "table" or type(package.style.themes) ~= "table" or #package.style.themes == 0 then
			table.insert(errors, { field = "style.themes", message = "A theme package needs at least one palette" })
		end
		if #errors > 0 then
			return nil, { ok = false, errors = errors, missing = {}, contrast = {} }
		end
		local typography = (package.metrics.typography :: unknown) :: { [string]: unknown }
		local definedMetrics = (definition :: { metrics: unknown? }).metrics
		local authored: { [string]: unknown } = if type(definedMetrics) == "table"
				and type((definedMetrics :: { typography: unknown? }).typography) == "table"
			then (definedMetrics :: { typography: { [string]: unknown } }).typography
			else {}
		for role, derivation in derivedTypeRoles do
			local source = typography[derivation.base]
			if authored[role] == nil and authored[derivation.base] ~= nil and type(source) == "table" then
				local entry = source :: { size: unknown, lineHeight: unknown, font: unknown }
				if type(entry.font) == "table" then
					local face = entry.font :: ThemeTypes.FontSpec
					typography[role] = {
						size = entry.size,
						lineHeight = entry.lineHeight,
						font = { family = face.family, weight = derivation.weight, style = face.style },
					}
				end
			end
		end
		for _, role in typeRoles do
			local entry = typography[role]
			local size = if type(entry) == "table" then (entry :: { size: unknown }).size else nil
			if entry ~= nil and (type(size) ~= "number" or size <= 0) then
				table.insert(
					errors,
					{ field = "metrics.typography." .. role, message = "Type roles require a positive size" }
				)
			end
		end
		local minimum = math.max(
			neutral.metrics.controls.typography.minimumSize,
			support.numericMetric(package.metrics, "controls.typography.minimumSize") or 0
		)
		local sizes: { number } = {}
		for _, entry in package.metrics.typography do
			if type(entry) == "table" and type(entry.size) == "number" and entry.size > 0 then
				if not table.find(sizes, entry.size) then
					table.insert(sizes, entry.size)
				end
			end
		end
		table.sort(sizes)
		local resolved: { [number]: number } = {}
		local previous = minimum - 1
		for _, size in sizes do
			local value = math.max(size, previous + 1)
			resolved[size] = value
			previous = value
		end
		for _, entry in package.metrics.typography do
			if type(entry) == "table" and type(entry.size) == "number" and resolved[entry.size] then
				entry.size = resolved[entry.size]
			end
		end
		local space = (package.metrics :: { space: unknown }).space
		if type(space) ~= "table" then
			table.insert(errors, { field = "metrics.space", message = "Spacing steps must be a table of pixel sizes" })
		else
			for step, pixels in space :: { [unknown]: unknown } do
				if type(step) ~= "string" or type(pixels) ~= "number" or pixels < 0 then
					table.insert(errors, {
						field = "metrics.space." .. tostring(step),
						message = "Spacing steps require a pixel size of 0 or more",
					})
				end
			end
		end
		local controlSizes = (package.metrics :: { controlSizes: unknown }).controlSizes
		local xsmall = if type(controlSizes) == "table" then (controlSizes :: { [string]: unknown }).xsmall else nil
		if xsmall ~= nil then
			for _, field in { "height", "paddingX", "iconSize" } do
				local value = if type(xsmall) == "table" then (xsmall :: { [string]: unknown })[field] else nil
				if type(value) ~= "number" or (value :: number) < 0 then
					table.insert(errors, {
						field = "metrics.controlSizes.xsmall." .. field,
						message = "The xsmall rung needs a height, a paddingX and an iconSize of 0 or more",
					})
				end
			end
		end
		local targets = (package.metrics :: { targetSizes: unknown }).targetSizes
		local sizes: { [string]: unknown } = if type(targets) == "table" then targets :: { [string]: unknown } else {}
		local minimum = sizes.minimum
		for _, name in { "pointer", "inline" } do
			local value = sizes[name]
			if
				value ~= nil
				and (type(value) ~= "number" or value < 24 or (type(minimum) == "number" and value > minimum))
			then
				table.insert(errors, {
					field = "metrics.targetSizes." .. name,
					message = `targetSizes.{name} must be from 24 to targetSizes.minimum`,
				})
			end
		end
		for _, name in { "thumb", "thumbLarge" } do
			local value = sizes[name]
			if
				value ~= nil
				and (type(value) ~= "number" or (type(minimum) == "number" and (value :: number) < (minimum :: number)))
			then
				table.insert(errors, {
					field = "metrics.targetSizes." .. name,
					message = `targetSizes.{name} must be a number of pixels, at least targetSizes.minimum`,
				})
			end
		end
		local motion = (package.metrics :: { motion: unknown }).motion
		if type(motion) ~= "table" then
			table.insert(errors, { field = "metrics.motion", message = "Motion tokens must be a table" })
		else
			local function issue(path: string, message: string)
				table.insert(errors, { field = "metrics.motion." .. path, message = message })
			end
			local function number(path: string, value: unknown, low: number, high: number, open: boolean?)
				if
					type(value) ~= "number"
					or (value :: number) > high
					or (value :: number) < low
					or (open == true and value == low)
				then
					issue(path, `must be a number from {low} to {high}{if open then ", above " .. low else ""}`)
				end
			end
			local tokens = motion :: { [string]: unknown }
			local function each(group: string, check: (string, unknown) -> ())
				local entries = tokens[group]
				if entries == nil then
					return
				end
				if type(entries) ~= "table" then
					issue(group, "must be a table")
					return
				end
				for key, value in entries :: { [unknown]: unknown } do
					check(group .. "." .. tostring(key), value)
				end
			end
			for _, key in { "fast", "normal", "press", "hover" } do
				if tokens[key] ~= nil then
					number(key, tokens[key], 0, 10)
				end
			end
			if tokens.reducedFade ~= nil then
				number("reducedFade", tokens.reducedFade, 0, 10, true)
			end
			for _, key in { "revealFadeShare", "unfoldStart" } do
				if tokens[key] ~= nil then
					number(key, tokens[key], 0, 1)
				end
			end
			if tokens.restLimit ~= nil then
				number("restLimit", tokens.restLimit, 0, 1)
			end
			for _, key in { "presentFadeIn", "presentFadeOut" } do
				if tokens[key] ~= nil then
					number(key, tokens[key], 0, 1, true)
				end
			end
			for _, role in { "popover", "dialog", "reveal", "sheet", "toast", "radial" } do
				each(role, function(path: string, value: unknown)
					number(path, value, 0, 10)
				end)
			end
			each("durations", function(path: string, value: unknown)
				number(path, value, 0, 10)
			end)
			each("springs", function(path: string, value: unknown)
				if type(value) ~= "table" then
					issue(path, "must be { period, damping }")
					return
				end
				local spring = value :: { period: unknown, damping: unknown }
				number(path .. ".period", spring.period, 0, 10, true)
				number(path .. ".damping", spring.damping, 0, 10, true)
			end)
			each("materialize", function(path: string, value: unknown)
				number(path, value, 0, 10, true)
			end)
			each("distances", function(path: string, value: unknown)
				number(path, value, 0, 10000)
			end)
			each("fling", function(path: string, value: unknown)
				number(path, value, 0, 100000, path ~= "fling.projection")
			end)
			each("easing", function(path: string, value: unknown)
				if type(value) ~= "string" or ComposeTypes.easing[value] == nil then
					issue(path, "must name a Compose.easing function")
				end
			end)
			each("styles", function(path: string, value: unknown)
				if type(value) ~= "string" or EASING_STYLES[value :: string] == nil then
					issue(path, "must name an Enum.EasingStyle item")
				end
			end)
		end
		for index, rule in (package.rules or {}) :: { ThemeTypes.Rule } do
			for property, value in (rule.properties or rule.props or {}) :: ThemeTypes.AuthoredRuleProperties do
				if type(value) == "table" then
					local reference = (value :: unknown) :: { metric: unknown, role: unknown }
					if
						reference.metric ~= nil
						and (reference.role ~= nil or support.numericMetric(package.metrics, reference.metric) == nil)
					then
						table.insert(errors, {
							field = `rules.{index}.properties.{property}`,
							message = "A metric reference must name one finite numeric theme metric",
						})
					end
				end
			end
		end
		local chrome: { [string]: ThemeTypes.SkinLayer } = package.chrome or {}
		local shadows: { [string]: ThemeTypes.Shadow } = package.style.shadows or {}
		local function checkLinks(value: unknown, path: string)
			if type(value) ~= "table" then
				return
			end
			local link = value :: { rotation: unknown, tint: unknown }
			if link.rotation ~= nil and link.rotation ~= 0 and link.rotation ~= 180 then
				table.insert(errors, { field = path .. ".rotation", message = "Art rotation must be 0 or 180" })
			end
			local tint = link.tint :: { [string]: unknown }
			if tint ~= nil then
				for _, channel in { "r", "g", "b" } do
					local amount = if type(tint) == "table" then tint[channel] else nil
					if type(amount) ~= "number" or (amount :: number) < 0 or (amount :: number) > 1 then
						table.insert(
							errors,
							{ field = path .. ".tint", message = "Art tint needs r, g and b from 0 to 1" }
						)
						break
					end
				end
			end
			for key, child in value :: { [unknown]: unknown } do
				checkLinks(child, path .. "." .. tostring(key))
			end
		end
		for slot, recipe in chrome do
			local shadow = recipe.shadow
			if type(shadow) == "string" and shadows[shadow] == nil and shadowPresets[shadow] == nil then
				table.insert(
					errors,
					{ field = "chrome." .. slot .. ".shadow", message = "Unknown shadow preset " .. shadow }
				)
			end
			checkLinks(recipe, "chrome." .. slot)
		end
		if #errors > 0 then
			return nil, { ok = false, errors = errors, missing = {}, contrast = {} }
		end
		package.schema = schema
		local contrast: { ThemeTypes.ContrastResult } = {}
		local function luminance(value: ThemeTypes.RGB): number
			local function linear(channel: number): number
				return if channel <= 0.04045 then channel / 12.92 else ((channel + 0.055) / 1.055) ^ 2.4
			end
			return 0.2126 * linear(value.r) + 0.7152 * linear(value.g) + 0.0722 * linear(value.b)
		end
		for _, palette in package.style.themes do
			if
				type(palette) ~= "table"
				or type(palette.name) ~= "string"
				or (palette.colors ~= nil and type(palette.colors) ~= "table")
			then
				table.insert(
					errors,
					{ field = "style.themes", message = "Palettes require a name and color dictionary" }
				)
				continue
			end
			local colors = merge(neutral.style.themes[1].colors, palette.colors)
			local valid = true
			for role, value in colors do
				if
					type(value) ~= "table"
					or type(value.r) ~= "number"
					or type(value.g) ~= "number"
					or type(value.b) ~= "number"
					or value.r < 0
					or value.r ~= value.r
					or value.g ~= value.g
					or value.b ~= value.b
					or value.r > 1
					or value.g < 0
					or value.g > 1
					or value.b < 0
					or value.b > 1
				then
					valid = false
					table.insert(
						errors,
						{ field = "colors." .. role, message = "Colors require RGB components between zero and one" }
					)
				end
			end
			if valid then
				for _, pair in
					{
						{ "content", "surface" },
						{ "contentStrong", "surfaceStrong" },
						{ "onAccent", "accent" },
						{ "onDanger", "danger" },
						{ "onSuccess", "success" },
						{ "onWarning", "warning" },
					}
				do
					local first, second = luminance(colors[pair[1]]), luminance(colors[pair[2]])
					local ratio = (math.max(first, second) + 0.05) / (math.min(first, second) + 0.05)
					table.insert(contrast, { pair = pair[1] .. "/" .. pair[2], ratio = ratio, ok = ratio >= 4.5 })
					if ratio < 4.5 then
						table.insert(
							errors,
							{ field = "style." .. palette.name, message = pair[1] .. " contrast is below 4.5:1" }
						)
					end
				end
				local extra = (
					merge(neutral.style.themes[1].extra or {}, palette.extra or {}) :: unknown
				) :: { [string]: ThemeTypes.RGB? }
				local selectedFill = extra.controlSelected
				local selectedLabel = extra.onSelected or colors.content
				if type(selectedFill) == "table" and type(selectedLabel) == "table" then
					local first, second = luminance(selectedLabel), luminance(selectedFill)
					local ratio = (math.max(first, second) + 0.05) / (math.min(first, second) + 0.05)
					table.insert(contrast, { pair = "onSelected/controlSelected", ratio = ratio, ok = ratio >= 4.5 })
					if ratio < 4.5 then
						table.insert(
							errors,
							{ field = "style." .. palette.name, message = "onSelected contrast is below 4.5:1" }
						)
					end
				end
			end
		end
		if #errors > 0 then
			return nil, { ok = false, errors = errors, missing = {}, contrast = contrast }
		end
		return frozen(package), { ok = true, errors = {}, missing = {}, contrast = contrast }
	end
	return { define = define, checkCoverage = checkCoverage }
end
