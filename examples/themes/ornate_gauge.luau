--!strict

type ThemePackage = typeof(require("@repo/tools/typecheck/aliases").ThemePackage)
type Themes = typeof(require("@repo/tools/typecheck/aliases").FacetModule.themes)
type Controls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type Host = typeof(require("@repo/tools/typecheck/aliases").Host)
type RobloxTypes = typeof(require("@repo/tools/typecheck/aliases").RobloxTypes)
type PaletteExtra = typeof(require("@repo/tools/typecheck/aliases").PaletteExtra)
type ReadOnlyValue<T> = { peek: (ReadOnlyValue<T>) -> T }
type Use = <T>(ReadOnlyValue<T>) -> T
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
type CoverageNeed = { name: string, section: string?, kind: ("color" | "number")?, fields: { string }? }
type Resolved = {
	height: number,
	paddingX: number,
	iconSize: number,
	ring: number,
	needle: Tint,
	usedFallback: { size: boolean, needle: boolean, ring: boolean },
}
type Core = { Host: Host, types: RobloxTypes? }
type Options = {
	id: string?,
	label: string?,
	fraction: (number | ReadOnlyValue<number>)?,
	heightPx: ReadOnlyValue<number>?,
}

local ornate_gauge = {}

ornate_gauge.namespace = "gauge"
ornate_gauge.control = "OrnateGauge"

ornate_gauge.ART = table.freeze({
	face = "rbxassetid://117569461983627",
	needle = "rbxassetid://88340591181438",
	endcap = "rbxassetid://80585948903459",
})

ornate_gauge.CAP_PX = 28
ornate_gauge.NEEDLE_PX = 24

local DIAL_FIELDS: { string } = { "height", "paddingX", "iconSize" }
local DIAL_FALLBACK: Size = { height = 44, paddingX = 12, iconSize = 18 }
local NEEDLE_FALLBACK: Tint = { r = 0.75, g = 0.58, b = 0.23 }
local DIAL_NEED: Need<Size> = {
	name = "gauge:dial",
	kind = "controlSize",
	section = "metrics.controlSizes",
	fields = DIAL_FIELDS,
	authority = "layout",
	capability = "none",
	fallback = DIAL_FALLBACK,
}
local NEEDLE_NEED: Need<Tint> = {
	name = "gauge:needle",
	kind = "color",
	section = "style.themes[].extra",
	authority = "paint",
	capability = "none",
	fallback = NEEDLE_FALLBACK,
}
local RING_NEED: Need<number> = {
	name = "gauge:ring",
	kind = "number",
	section = "metrics.radii",
	authority = "paint",
	capability = "none",
	fallback = 6,
}
local NEEDS: { Need<Size> | Need<Tint> | Need<number> } = { DIAL_NEED, NEEDLE_NEED, RING_NEED }
table.freeze(DIAL_FIELDS)
table.freeze(DIAL_FALLBACK)
table.freeze(NEEDLE_FALLBACK)
table.freeze(DIAL_NEED)
table.freeze(NEEDLE_NEED)
table.freeze(RING_NEED)
ornate_gauge.needs = table.freeze(NEEDS)

local COVERAGE: { CoverageNeed } = {
	{ name = DIAL_NEED.name, section = DIAL_NEED.section, fields = DIAL_NEED.fields },
	{ name = NEEDLE_NEED.name, section = NEEDLE_NEED.section, kind = "color" },
	{ name = RING_NEED.name, section = RING_NEED.section, kind = "number" },
}

function ornate_gauge.check(themes: Themes, package: ThemePackage)
	return themes.checkCoverage(package, COVERAGE)
end

local function tintOf(extra: PaletteExtra?): Tint?
	local value = if extra then extra["gauge:needle"] else nil
	if type(value) == "table" then
		local r, g, b = value.r, value.g, value.b
		if type(r) == "number" and type(g) == "number" and type(b) == "number" then
			return { r = r, g = g, b = b }
		end
	end
	return nil
end

function ornate_gauge.resolve(package: ThemePackage?, themeName: string?): Resolved
	local metrics = if package ~= nil then package.metrics else nil
	local sizes = if metrics then metrics.controlSizes else nil
	local size = if sizes then sizes["gauge:dial"] else nil
	local usedSize = type(size) ~= "table" or type(size.height) ~= "number"
	local dial = if usedSize or size == nil then DIAL_NEED.fallback else size

	local radii = if metrics then metrics.radii else nil
	local ring = if radii then radii["gauge:ring"] else nil
	local usedRing = type(ring) ~= "number"

	local needle: Tint? = nil
	if package ~= nil then
		local wanted = themeName or package.style.defaultTheme
		for _, theme in package.style.themes do
			if theme.name == wanted then
				needle = tintOf(theme.extra)
			end
		end
	end
	local usedNeedle = needle == nil

	return {
		height = dial.height,
		paddingX = dial.paddingX,
		iconSize = dial.iconSize,
		ring = if ring ~= nil and not usedRing then ring else RING_NEED.fallback,
		needle = needle or NEEDLE_NEED.fallback,
		usedFallback = { size = usedSize, needle = usedNeedle, ring = usedRing },
	}
end

function ornate_gauge.blueprint(UI: Controls, core: Core, resolved: Resolved, opts: Options?): Frame
	local Host = core.Host
	local types = core.types
	local UDim = if types then types.UDim else UDim
	local UDim2 = if types then types.UDim2 else UDim2
	local Vector2 = if types then types.Vector2 else Vector2
	local Color3 = if types then types.Color3 else Color3
	local Enum = if types then types.Enum else Enum
	local o: Options = opts or {}
	local name = o.id or "Gauge"
	local capPx = ornate_gauge.CAP_PX
	local needleColor = Color3.new(resolved.needle.r, resolved.needle.g, resolved.needle.b)

	local function fraction(use: Use): number
		local value = o.fraction
		local n = if type(value) == "number" then value elseif value ~= nil then use(value) else 0
		return math.clamp(n, 0, 1)
	end
	local function height(use: Use): number
		local source = o.heightPx
		return if source ~= nil then use(source) else resolved.height
	end
	local function cap(side: string): ImageLabel
		return Host.ImageLabel(name .. side)({
			Image = ornate_gauge.ART.endcap,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(if side == "CapEnd" then 1 else 0, 0),
			Position = UDim2.fromScale(if side == "CapEnd" then 1 else 0, 0),
			Size = UDim2.new(0, capPx, 1, 0),
			ZIndex = 3,
		})
	end

	local dial = Host.Frame(name .. "Dial")({
		LayoutOrder = 2,
		BackgroundTransparency = 1,
		Size = function(use: Use): UDim2
			return UDim2.new(1, 0, 0, height(use))
		end,
		Host.UICorner({ CornerRadius = UDim.new(0, resolved.ring) }),
		Host.ImageLabel(name .. "Face")({
			Image = ornate_gauge.ART.face,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
		}),
		Host.Frame(name .. "Track")({
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(capPx, 0),
			Size = UDim2.new(1, -2 * capPx, 1, 0),
			ZIndex = 2,
			Host.ImageLabel(name .. "Needle")({
				Image = ornate_gauge.ART.needle,
				ImageColor3 = needleColor,
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0),
				Position = function(use: Use): UDim2
					return UDim2.fromScale(fraction(use), 0)
				end,
				Size = UDim2.new(0, ornate_gauge.NEEDLE_PX, 1, 0),
			}),
		}),
		cap("CapStart"),
		cap("CapEnd"),
	})

	return Host.Frame(name)({
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Host.UIListLayout({ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }),
		UI.Text(name .. "Label")({
			text = o.label or "Boiler pressure (gauge:dial)",
			textRole = "caption",
			LayoutOrder = 1,
		}),
		dial,
	})
end

return ornate_gauge
