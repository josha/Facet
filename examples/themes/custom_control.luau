--!strict
type ThemePackage = typeof(require("@repo/tools/typecheck/aliases").ThemePackage)
type Controls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type Host = typeof(require("@repo/tools/typecheck/aliases").Host)
type RobloxTypes = typeof(require("@repo/tools/typecheck/aliases").RobloxTypes)
type ExtraValue = typeof(require("@repo/tools/typecheck/aliases").ThemeExtraValue)
type PaletteExtra = typeof(require("@repo/tools/typecheck/aliases").ThemePackage.style.themes[1].extra)
type Size = { height: number, paddingX: number, iconSize: number }
type Tint = { r: number, g: number, b: number }
type Need<Fallback> = {
	name: string,
	kind: string,
	section: string,
	fields: { string }?,
	authority: string,
	capability: string,
	fallback: Fallback,
}
type Gap = { name: string, message: string, fix: string }
type Report = { ok: boolean, covered: { string }, missing: { Gap } }
type Resolved = {
	height: number,
	paddingX: number,
	iconSize: number,
	tint: Tint,
	usedFallback: { size: boolean, tint: boolean },
}
type Core = { Host: Host, types: RobloxTypes? }

local custom_control = {}

custom_control.namespace = "demo"
custom_control.control = "Gauge"

local SIZE_FIELDS: { string } = table.freeze({ "height", "paddingX", "iconSize" })

local SIZE_FALLBACK: Size = { height = 24, paddingX = 8, iconSize = 14 }
local SIZE_NEED: Need<Size> = {
	name = "demo:gauge",
	kind = "controlSize",
	section = "metrics.controlSizes",
	fields = SIZE_FIELDS,
	authority = "layout",
	capability = "none",
	fallback = SIZE_FALLBACK,
}

local TINT_FALLBACK: Tint = { r = 0.35, g = 0.7, b = 0.9 }
local TINT_NEED: Need<Tint> = {
	name = "demo:gaugeTint",
	kind = "color",
	section = "style.themes[].extra",
	authority = "paint",
	capability = "none",
	fallback = TINT_FALLBACK,
}

local NEEDS: { Need<Size> | Need<Tint> } = { SIZE_NEED, TINT_NEED }
table.freeze(SIZE_FALLBACK)
table.freeze(TINT_FALLBACK)
table.freeze(SIZE_NEED)
table.freeze(TINT_NEED)
custom_control.needs = table.freeze(NEEDS)

local function tintOf(value: ExtraValue?): Tint?
	if type(value) == "table" then
		local r, g, b = value.r, value.g, value.b
		if type(r) == "number" and type(g) == "number" and type(b) == "number" then
			return { r = r, g = g, b = b }
		end
	end
	return nil
end

local function gaugeTint(extra: PaletteExtra): ExtraValue?
	return if extra then extra["demo:gaugeTint"] else nil
end

function custom_control.check(package: ThemePackage): Report
	local covered: { string } = {}
	local missing: { Gap } = {}
	local function fail(name: string, message: string, fix: string)
		table.insert(missing, { name = name, message = message, fix = fix })
	end

	local sizes = package.metrics and package.metrics.controlSizes
	local gauge = if sizes then sizes["demo:gauge"] else nil
	if type(gauge) ~= "table" then
		fail(
			"demo:gauge",
			`theme package '{package.identity.id}' declares no '{custom_control.namespace}:gauge' control size, `
				.. `so every {custom_control.control} falls back to its built-in {SIZE_NEED.fallback.height}px row `
				.. "and stops following the theme",
			'add metrics.controlSizes["demo:gauge"] = { height = .., paddingX = .., iconSize = .. }'
		)
	else
		local values: { [string]: number? } =
			{ height = gauge.height, paddingX = gauge.paddingX, iconSize = gauge.iconSize }
		local incomplete: { string } = {}
		for _, field in SIZE_FIELDS do
			if type(values[field]) ~= "number" then
				table.insert(incomplete, field)
			end
		end
		if #incomplete > 0 then
			fail(
				"demo:gauge",
				`'demo:gauge' is missing {table.concat(incomplete, ", ")}`,
				`declare {table.concat(SIZE_FIELDS, ", ")} — the {custom_control.control} resolves all three on every solve`
			)
		else
			table.insert(covered, "demo:gauge")
		end
	end

	local uncovered: { string } = {}
	for _, theme in package.style.themes do
		local tint = gaugeTint(theme.extra)
		if type(tint) ~= "table" or type(tint.r) ~= "number" then
			table.insert(uncovered, theme.name)
		end
	end
	if #uncovered > 0 then
		fail(
			"demo:gaugeTint",
			`theme(s) {table.concat(uncovered, ", ")} of package '{package.identity.id}' declare no `
				.. "'demo:gaugeTint', so the Gauge paints its built-in colour and ignores the palette",
			'add extra["demo:gaugeTint"] = { r = .., g = .., b = .. } to every theme'
		)
	else
		table.insert(covered, "demo:gaugeTint")
	end

	table.sort(covered)
	return { ok = #missing == 0, covered = covered, missing = missing }
end

function custom_control.resolve(package: ThemePackage?, themeName: string?): Resolved
	local sizes = if package and package.metrics then package.metrics.controlSizes else nil
	local size = if sizes then sizes["demo:gauge"] else nil
	local usedSizeFallback = type(size) ~= "table" or type(size.height) ~= "number"
	local resolvedSize = if usedSizeFallback or size == nil then SIZE_NEED.fallback else size
	local tint: Tint? = nil
	if package ~= nil then
		local wanted = themeName or package.style.defaultTheme
		for _, theme in package.style.themes do
			if theme.name == wanted then
				tint = tintOf(gaugeTint(theme.extra))
			end
		end
	end
	local usedTintFallback = tint == nil
	return {
		height = resolvedSize.height,
		paddingX = resolvedSize.paddingX,
		iconSize = resolvedSize.iconSize,
		tint = tint or TINT_NEED.fallback,
		usedFallback = { size = usedSizeFallback, tint = usedTintFallback },
	}
end

function custom_control.blueprint(UI: Controls, core: Core, resolved: Resolved, id: string?): Frame
	local Host = core.Host
	local types = core.types
	local UDim = if types then types.UDim else UDim
	local UDim2 = if types then types.UDim2 else UDim2
	local Enum = if types then types.Enum else Enum
	local name = id or "Gauge"
	local track = Host.Frame(name .. "Track")({
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, resolved.height),
		Host.UICorner {},
	})
	track:AddTag("facet-control")
	return Host.Frame(name)({
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Host.UIListLayout { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) },
		UI.Text(name .. "Label")({
			text = "Custom gauge (demo:gauge)",
			textRole = "caption",
			LayoutOrder = 1,
		}),
		track,
	})
end

return custom_control
