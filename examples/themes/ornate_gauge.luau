--!strict

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

ornate_gauge.needs = table.freeze({
	table.freeze({
		name = "gauge:dial",
		kind = "controlSize",
		section = "metrics.controlSizes",
		fields = table.freeze({ "height", "paddingX", "iconSize" }),
		authority = "layout",
		capability = "none",
		fallback = table.freeze({ height = 44, paddingX = 12, iconSize = 18 }),
	}),
	table.freeze({
		name = "gauge:needle",
		kind = "color",
		section = "style.themes[].extra",
		authority = "paint",
		capability = "none",

		fallback = table.freeze({ r = 0.75, g = 0.58, b = 0.23 }),
	}),
	table.freeze({
		name = "gauge:ring",
		kind = "number",
		section = "metrics.radii",
		authority = "paint",
		capability = "none",
		fallback = 6,
	}),
})

local function needByName(name: string): any
	for _, need in ornate_gauge.needs do
		if need.name == name then
			return need
		end
	end
	return nil
end

function ornate_gauge.check(themes: any, package: any): any
	return themes.checkCoverage(package, ornate_gauge.needs)
end

function ornate_gauge.resolve(package: any?, themeName: string?): any
	local sizeNeed = needByName("gauge:dial")
	local colorNeed = needByName("gauge:needle")
	local ringNeed = needByName("gauge:ring")
	local metrics = if package ~= nil then package.metrics or {} else {}

	local size = (metrics.controlSizes or {})["gauge:dial"]
	local usedSize = type(size) ~= "table" or type(size.height) ~= "number"

	local ring = (metrics.radii or {})["gauge:ring"]
	local usedRing = type(ring) ~= "number"

	local needle: any = nil
	if package ~= nil then
		local wanted = themeName or package.style.defaultTheme
		for _, theme in package.style.themes do
			if theme.name == wanted then
				needle = (theme.extra or {})["gauge:needle"]
			end
		end
	end
	local usedNeedle = type(needle) ~= "table" or type(needle.r) ~= "number"

	return {
		height = if usedSize then sizeNeed.fallback.height else size.height,
		paddingX = if usedSize then sizeNeed.fallback.paddingX else size.paddingX,
		iconSize = if usedSize then sizeNeed.fallback.iconSize else size.iconSize,
		ring = if usedRing then ringNeed.fallback else ring,
		needle = if usedNeedle then colorNeed.fallback else needle,
		usedFallback = { size = usedSize, needle = usedNeedle, ring = usedRing },
	}
end

function ornate_gauge.blueprint(UI: any, core: any, resolved: any, opts: any?): any
	local Host = core.Host
	local types = core.types or { UDim = UDim, UDim2 = UDim2, Vector2 = Vector2, Color3 = Color3, Enum = Enum }
	local UDim, UDim2, Vector2, Color3, Enum = types.UDim, types.UDim2, types.Vector2, types.Color3, types.Enum
	local o: any = opts or {}
	local name: string = o.id or "Gauge"
	local capPx = ornate_gauge.CAP_PX
	local needleColor = Color3.new(resolved.needle.r, resolved.needle.g, resolved.needle.b)

	local function fraction(use: any): number
		local value = o.fraction
		local n = if type(value) == "number" then value elseif value ~= nil then use(value) else 0
		return math.clamp(if type(n) == "number" then n else 0, 0, 1)
	end
	local function height(use: any): number
		return if o.heightPx ~= nil then use(o.heightPx) else resolved.height
	end
	local function cap(side: string): any
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
		Size = function(use: any)
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
				Position = function(use: any)
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
		UI.Label(name .. "Label")({
			text = o.label or "Boiler pressure (gauge:dial)",
			textRole = "caption",
			LayoutOrder = 1,
		}),
		dial,
	})
end

return ornate_gauge
