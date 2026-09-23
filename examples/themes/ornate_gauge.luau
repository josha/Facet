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

function ornate_gauge.resolve(snapshot: any, package: any?, themeName: string?): any
	local sizeNeed = needByName("gauge:dial")
	local colorNeed = needByName("gauge:needle")
	local ringNeed = needByName("gauge:ring")

	local size = (snapshot.controlSizes or {})["gauge:dial"]
	local usedSize = type(size) ~= "table" or type(size.height) ~= "number"

	local ring = (snapshot.radii or {})["gauge:ring"]
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
	local Compose = core.Compose
	local o: any = opts or {}
	local name: string = o.id or "Gauge"
	local capPx = ornate_gauge.CAP_PX
	local fraction = o.fraction

	local function clamp01(v: any): number
		local n = if type(v) == "number" then v else 0
		return math.clamp(n, 0, 1)
	end

	local FLOOR = 1e-4
	local lead = Compose.formula(function(use: any)
		local f = clamp01(if fraction ~= nil then use(fraction) else 0)
		return UI.fill(math.max(f, FLOOR))
	end)
	local trail = Compose.formula(function(use: any)
		local f = clamp01(if fraction ~= nil then use(fraction) else 0)
		return UI.fill(math.max(1 - f, FLOOR))
	end)

	local dialHeight: any = if o.heightPx ~= nil
		then Compose.formula(function(use: any)
			return { type = "fixed", px = use(o.heightPx) }
		end)
		else { type = "fixed", px = resolved.height }

	local FILL = UI.fill()

	local needle = UI.shadow(
		UI.Image(name .. "Needle")({
			image = ornate_gauge.ART.needle,
			width = { type = "fixed", px = ornate_gauge.NEEDLE_PX },
			height = FILL,
		}),
		{
			blurRadius = { scale = 0, offset = 18 },
			color = resolved.needle,
			transparency = 0.35,
			zIndex = -1,
		}
	)

	local dial = UI.corners(
		UI.ZStack(name .. "Dial")({
			width = FILL,
			height = dialHeight,

			UI.Image(name .. "Face")({
				image = ornate_gauge.ART.face,
				width = FILL,
				height = FILL,
			}),

			UI.HStack(name .. "Track")({
				width = FILL,
				height = FILL,
				gap = 0,
				padding = { top = 0, right = capPx, bottom = 0, left = capPx },

				UI.Spacer(name .. "Lead")({ width = lead, height = FILL }),
				needle,
				UI.Spacer(name .. "Trail")({ width = trail, height = FILL }),
			}),

			UI.Anchor(name .. "Caps")({
				width = FILL,
				height = FILL,

				UI.Image(name .. "CapStart")({
					image = ornate_gauge.ART.endcap,
					anchor = "left",
					width = { type = "fixed", px = capPx },
					height = FILL,
				}),
				UI.Image(name .. "CapEnd")({
					image = ornate_gauge.ART.endcap,
					anchor = "right",
					width = { type = "fixed", px = capPx },
					height = FILL,
				}),
			}),
		}),
		resolved.ring
	)

	return UI.VStack(name)({
		gap = "xs",
		width = FILL,

		UI.Text(name .. "Label")({
			text = o.label or "Boiler pressure (gauge:dial)",
			textSize = "caption",
		}),
		dial,
	})
end

return ornate_gauge
