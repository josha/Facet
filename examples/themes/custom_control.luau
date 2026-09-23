--!strict

local custom_control = {}

custom_control.namespace = "demo"
custom_control.control = "Gauge"

custom_control.needs = table.freeze({
	table.freeze({
		name = "demo:gauge",
		kind = "controlSize",
		section = "metrics.controlSizes",
		fields = table.freeze({ "height", "paddingX", "iconSize" }),
		authority = "layout",
		capability = "none",
		fallback = table.freeze({ height = 24, paddingX = 8, iconSize = 14 }),
	}),
	table.freeze({
		name = "demo:gaugeTint",
		kind = "color",
		section = "style.themes[].extra",
		authority = "paint",
		capability = "none",
		fallback = table.freeze({ r = 0.35, g = 0.7, b = 0.9 }),
	}),
})

local function needByName(name: string): any
	for _, need in custom_control.needs do
		if need.name == name then
			return need
		end
	end
	return nil
end

function custom_control.check(package: any): any
	local covered: { string } = {}
	local missing: { any } = {}
	local function fail(name: string, message: string, fix: string)
		table.insert(missing, { name = name, message = message, fix = fix })
	end

	local sizes = (package.metrics or {}).controlSizes or {}
	local gauge = sizes["demo:gauge"]
	local sizeNeed = needByName("demo:gauge")
	if type(gauge) ~= "table" then
		fail(
			"demo:gauge",
			`theme package '{package.identity.id}' declares no '{custom_control.namespace}:gauge' control size, `
				.. `so every {custom_control.control} falls back to its built-in {sizeNeed.fallback.height}px row `
				.. "and stops following the theme",
			'add metrics.controlSizes["demo:gauge"] = { height = .., paddingX = .., iconSize = .. }'
		)
	else
		local incomplete: { string } = {}
		for _, field in sizeNeed.fields do
			if type(gauge[field]) ~= "number" then
				table.insert(incomplete, field)
			end
		end
		if #incomplete > 0 then
			fail(
				"demo:gauge",
				`'demo:gauge' is missing {table.concat(incomplete, ", ")}`,
				`declare {table.concat(sizeNeed.fields, ", ")} — the {custom_control.control} resolves all three on every solve`
			)
		else
			table.insert(covered, "demo:gauge")
		end
	end

	local uncovered: { string } = {}
	for _, theme in package.style.themes do
		local tint = (theme.extra or {})["demo:gaugeTint"]
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

function custom_control.resolve(snapshot: any, package: any?, themeName: string?): any
	local sizeNeed = needByName("demo:gauge")
	local tintNeed = needByName("demo:gaugeTint")
	local size = (snapshot.controlSizes or {})["demo:gauge"]
	local usedSizeFallback = type(size) ~= "table" or type(size.height) ~= "number"
	local tint: any = nil
	if package ~= nil then
		local wanted = themeName or package.style.defaultTheme
		for _, theme in package.style.themes do
			if theme.name == wanted then
				tint = (theme.extra or {})["demo:gaugeTint"]
			end
		end
	end
	local usedTintFallback = type(tint) ~= "table" or type(tint.r) ~= "number"
	return {
		height = if usedSizeFallback then sizeNeed.fallback.height else size.height,
		paddingX = if usedSizeFallback then sizeNeed.fallback.paddingX else size.paddingX,
		iconSize = if usedSizeFallback then sizeNeed.fallback.iconSize else size.iconSize,
		tint = if usedTintFallback then tintNeed.fallback else tint,
		usedFallback = { size = usedSizeFallback, tint = usedTintFallback },
	}
end

function custom_control.blueprint(UI: any, resolved: any, id: string?): any
	local name = id or "Gauge"
	return UI.VStack({
		id = name,
		gap = "xs",
		width = UI.fill(),

		UI.Text({ id = name .. "Label", text = "Custom gauge (demo:gauge)", textSize = "caption" }),
		UI.Box({
			id = name .. "Track",
			surface = "control",
			width = UI.fill(),
			height = { type = "fixed", px = resolved.height },
		}),
	})
end

return custom_control
