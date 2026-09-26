--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local themes = Facet.themes
local fs = require("@lune/fs")
local worlds = require("./lib/content_world")

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

	t.it("strokes a themed border inside the box so a container edge cannot clip it", function()
		for _, entry in packages() do
			local sheet, stop = sheetOf(entry.package)
			local counted = 0
			for _, node in sheet:GetChildren() do
				local selector = node.Selector :: string
				local properties = node:GetProperties()
				if string.sub(selector, -10) == "::UIStroke" and properties.ApplyStrokeMode.Name == "Border" then
					counted += 1
					t.expect(`{entry.label} {selector} {properties.BorderStrokePosition}`)
						.toBe(`{entry.label} {selector} Enum.BorderStrokePosition.Inner`)
				end
			end
			t.expect(counted > 5).toBe(true)
			stop()
		end
	end)

	t.it("rounds a menu's first and last rows with the panel's radius so a highlight stays inside the card", function()
		for _, entry in packages() do
			local sheet, stop = sheetOf(entry.package)
			local corner = assert(style(sheet, ".facet-menu-end::UICorner"))
			t.expect(corner.CornerRadius.Offset).toBe(entry.package.metrics.radii.panel)
			stop()
		end
	end)

	t.it("shows a skinned theme's selected art on a filled tab and a stepper's plate under its value", function()
		for _, entry in packages() do
			local sheet, stop = sheetOf(entry.package)
			local chrome = entry.package.chrome or {}
			local plate = chrome.control
			local layers = if plate == nil then {} elseif plate.kind == "layered" then plate.layers or {} else { plate }
			local selectedArt = false
			for _, layer in layers do
				if type(layer.asset) == "table" and layer.asset.selected ~= nil then
					selectedArt = true
				end
			end
			local filled = assert(style(sheet, ".facet-tab-filled.facet-skinned"))
			local boundary = assert(style(sheet, ".facet-tab-filled > #SkinBoundary"))
			t.expect(`{entry.label} {filled.BackgroundTransparency} {boundary.Visible}`)
				.toBe(if selectedArt then `{entry.label} nil nil` else `{entry.label} 0 false`)
			local track = assert(style(sheet, ".facet-skinned > #Content > .facet-stepper-track"))
			t.expect(track.BackgroundTransparency).toBe(1)
			stop()
		end
	end)

	t.it("pads every gallery page inside its scroller, so an edge control's ring and shadow have room", function()
		local offenders = {}
		for _, name in fs.readDir("examples/gallery/scenarios") do
			local lines = string.split(fs.readFile("examples/gallery/scenarios/" .. name), "\n")
			local closing: string? = nil
			for index, line in lines do
				local indent = string.match(line, "^(\t+)Host%.UIPadding%(")
				if indent then
					closing = indent .. "}),"
				elseif closing and line == closing then
					local following = lines[index + 1] or ""
					if string.find(following, "^" .. string.sub(closing, 1, -4) .. "Host%.ScrollingFrame") then
						table.insert(offenders, name)
					end
					closing = nil
				end
			end
		end
		t.expect(offenders).toEqual({})
	end)

	t.it("tints a skinned status badge's art with its status fill so the on-status digit reads", function()
		for _, entry in packages() do
			local sheet, stop = sheetOf(entry.package)
			local fill = assert(style(sheet, ".facet-status-info")).BackgroundColor3
			local art = assert(style(sheet, ".facet-badge.facet-status-info > #SkinBoundary >> .facet-skin-art"))
			t.expect(art.ImageColor3).toBe(fill)
			local plain = assert(style(sheet, ".facet-badge-status > #SkinBoundary >> .facet-skin-art"))
			t.expect(plain.ImageColor3).toBe(require("@lune/roblox").Color3.new(1, 1, 1))
			stop()
		end
	end)

	t.it("skins a table row with the theme's control art, selected art when selected", function()
		local parchment = (require :: any)("../examples/themes/fantasy_parchment").build(themes)
		local selection = Facet.Compose.cell({ a = true })
		local world = worlds.new(function(UI, Host)
			return UI.Table({
				from = Facet.Compose.cell({ { id = "a", label = "Alpha" }, { id = "b", label = "Beta" } }),
				key = "id",
				selection = selection,
				columns = {
					{
						id = "label",
						label = "Name",
						render = function(current)
							return Host.TextLabel({ Text = current:peek().label })
						end,
					},
				},
			})
		end, { reducedMotion = true, theme = parchment })
		world.find("Body").AbsoluteWindowSize = world.V2(400, 300)
		local rows = {}
		for _, node in world.screen:GetDescendants() do
			if node:HasTag("facet-tablerow") then
				table.insert(rows, node)
			end
		end
		t.expect(#rows).toBe(2)
		for _, row in rows do
			t.expect(row:HasTag("facet-skinned")).toBe(true)
			t.expect(row:FindFirstChild("Skin", true) ~= nil).toBe(true)
		end
		world.stop()
	end)

	t.it("keeps a persistent vertical scroll bar gutter on every themed scroller", function()
		for _, entry in packages() do
			local sheet, stop = sheetOf(entry.package)
			local scrolling = assert(style(sheet, "ScrollingFrame"))
			t.expect(scrolling.VerticalScrollBarInset.Name).toBe("Always")
			stop()
		end
	end)
end)
