--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local themes = Facet.themes

local SHIPPED = {
	"classic_desktop",
	"compact_pointer",
	"fantasy_ornate",
	"fantasy_parchment",
	"glossy_mobile",
	"glossy_touch",
	"pixel_quest",
	"scifi_hud",
}

local function packages(): { { label: string, package: any } }
	local out = { { label = "Facet Neutral", package = themes.neutralPackage() } }
	for _, name in SHIPPED do
		local module: any = (require :: any)("../examples/themes/" .. name)
		local package, report = module.build(themes)
		assert(report.ok, name .. " did not build")
		table.insert(out, { label = name, package = package })
	end
	return out
end

local function sheetOf(package: any, palette: string?): (any, () -> ())
	local engine: any = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local _, sheet = runtime.mount(function()
		return themes.createStyleSheet(
			runtime,
			package,
			{ types = engine.types, theme = palette, preferredTransparency = 1, reducedMotion = false } :: any
		)
	end, engine.new("Folder"))
	return sheet, function()
		runtime:dispose()
	end
end

local function style(sheet: any, selector: string): { [string]: any }?
	for _, node in sheet:GetChildren() do
		if node.Selector == selector then
			return node:GetProperties()
		end
	end
	return nil
end

local function palettes(package: any): { any }
	return package.style.themes
end

t.describe("owner review 2026-09-26b: visual", function()
	t.it("draws the tab plate's hairline at the theme's hairline strength, not an opaque ring", function()
		for _, entry in packages() do
			for _, palette in palettes(entry.package) do
				local sheet, stop = sheetOf(entry.package, palette.name)
				local stroke = assert(style(sheet, ".facet-tab-plate::UIStroke"))
				local opacity = (palette.extra or {}).hairlineOpacity
					or themes.neutralPackage().style.themes[1].extra.hairlineOpacity
				t.expect(`{entry.label}/{palette.name} {stroke.Transparency}`)
					.toBe(`{entry.label}/{palette.name} {opacity}`)
				t.expect(stroke.Thickness).toBe(entry.package.metrics.strokes.hairline or 1)
				stop()
			end
		end
	end)
end)
