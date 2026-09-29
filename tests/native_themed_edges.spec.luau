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
			{ types = engine.types, theme = palette, preferredTransparency = 1, motionLevel = "normal" } :: any
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

t.describe("themed edges, plates and gutters", function()
	t.it("keeps top tab shapes owned by the theme", function()
		local expected = {
			["Facet Neutral"] = 999,
			compact_pointer = 4,
			pixel_quest = 0,
			fantasy_parchment = 0,
		}
		for _, entry in packages() do
			local radius = expected[entry.label]
			if radius ~= nil then
				local sheet, stop = sheetOf(entry.package)
				local tab = assert(style(sheet, ".facet-top-tabs > #Tabs >> .facet-tab-item::UICorner"))
				local plate = assert(style(sheet, ".facet-top-tabs > .facet-tab-plate::UICorner"))
				t.expect(tab.CornerRadius.Offset).toBe(radius)
				t.expect(plate.CornerRadius.Offset).toBe(if radius > 0 then radius + 2 else 0)
				stop()
			end
		end
	end)

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
				if
					string.sub(selector, -10) == "::UIStroke"
					and properties.ApplyStrokeMode.Name == "Border"
					and not string.find(selector, "facet-avatar-stack", 1, true)
				then
					counted += 1
					t.expect(`{entry.label} {selector} {properties.BorderStrokePosition}`)
						.toBe(`{entry.label} {selector} Enum.BorderStrokePosition.Inner`)
				end
			end
			t.expect(counted > 5).toBe(true)
			stop()
		end
	end)

	t.it("gives every themed stroke a fade twin that a shared fade swaps in for the phantom", function()
		for _, entry in packages() do
			local sheet, stop = sheetOf(entry.package)
			local ordered = sheet:GetChildren()
			table.sort(ordered, function(a, b)
				return a.Priority < b.Priority
			end)
			local base = assert(style(sheet, ".facet-fade-stroke"))
			t.expect(`{base.Enabled} {base.Transparency}`).toBe("false 1")
			t.expect(ordered[1].Selector).toBe(".facet-fade-stroke")
			local fading, live
			for _, node in ordered do
				if node.Selector == ".facet-fading::UIStroke" then
					fading = node
				elseif node.Selector == ".facet-fading > .facet-fade-stroke" then
					live = node
				end
			end
			t.expect(fading:GetProperties().Enabled).toBe(false)
			t.expect(live:GetProperties().Enabled).toBe(true)
			t.expect(live.Priority > fading.Priority).toBe(true)
			for _, node in ordered do
				if string.sub(node.Selector, 1, 7) == ".facet-" and string.sub(node.Selector, -10) == "::UIStroke" then
					t.expect(`{node.Selector} {node.Priority <= fading.Priority}`).toBe(`{node.Selector} true`)
				end
			end
			local twins = 0
			for index, node in ordered do
				local selector = node.Selector :: string
				if string.sub(selector, -10) == "::UIStroke" and selector ~= ".facet-fading::UIStroke" then
					local twin = ordered[index - 1]
					t.expect(`{entry.label} {twin.Selector}`)
						.toBe(`{entry.label} {string.sub(selector, 1, -11)} > .facet-fade-stroke`)
					local expected = table.clone(node:GetProperties())
					for key, value in expected do
						t.expect(`{twin.Selector}.{key}={twin:GetProperties()[key]}`)
							.toBe(`{twin.Selector}.{key}={value}`)
					end
					twins += 1
				end
			end
			t.expect(twins > 10).toBe(true)
			stop()
		end
	end)

	t.it(
		"resolves a fade stroke exactly like the phantom it replaces, a game's partial stroke rule included",
		function()
			local styleRules = require("./lib/style_rules")
			local authored = themes.neutralPackage()
			authored.rules = { { selector = ".facet-floating::UIStroke", properties = { Thickness = 3 } } }
			for _, entry in
				{ { label = "neutral", package = themes.neutralPackage() }, { label = "game", package = authored } }
			do
				local engine: any = engineLib.new()
				local runtime = Facet.Roblox.createRuntime(engine)
				local _, sheet = runtime.mount(function()
					return themes.createStyleSheet(runtime, entry.package, { types = engine.types } :: any)
				end, engine.new("Folder"))
				for _, tags in { { "facet-floating" }, { "facet-step-circle" }, { "facet-layout" } } do
					local node = engine.new("Frame")
					for _, tag in tags do
						node:AddTag(tag)
					end
					local stroke = engine.new("UIStroke")
					stroke:AddTag("facet-fade-stroke")
					stroke.Parent = node
					local label = `{entry.label} {tags[1]}`
					local phantom = styleRules.resolve(sheet, node, "Thickness", "UIStroke") ~= nil
						or styleRules.resolve(sheet, node, "Color", "UIStroke") ~= nil
					for _, property in { "Transparency", "Thickness", "Color" } do
						local want = styleRules.resolve(sheet, node, property, "UIStroke")
						if want == nil and property == "Transparency" then
							want = if phantom then 0 else 1
						end
						if want ~= nil then
							t.expect(`{label} {property} {styleRules.resolve(sheet, stroke, property)}`)
								.toBe(`{label} {property} {want}`)
						end
					end
					t.expect(`{label} rest {styleRules.resolve(sheet, stroke, "Enabled")}`).toBe(`{label} rest false`)
					node:AddTag("facet-fading")
					t.expect(`{label} fading {styleRules.resolve(sheet, stroke, "Enabled")}`)
						.toBe(`{label} fading true`)
					t.expect(styleRules.resolve(sheet, node, "Enabled", "UIStroke")).toBe(false)
				end
				runtime:dispose()
			end
		end
	)

	t.it("preloads a theme's art once per applied package so a first panel does not open without it", function()
		local engine: any = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local requests: { { string } } = {}
		local provider = {
			PreloadAsync = function(_, content: { string })
				table.insert(requests, content)
			end,
		}
		local pixel = require("../examples/themes/pixel_quest").build(themes)
		local package = Facet.Compose.cell(themes.neutralPackage())
		runtime.mount(function()
			return themes.createStyleSheet(
				runtime,
				package,
				{ types = engine.types, contentProvider = provider } :: any
			)
		end, engine.new("Folder"))
		t.expect(#requests).toBe(0)
		package:set(pixel)
		t.expect(#requests).toBe(1)
		local expected, lazy = {}, 0
		for _, asset in pixel.assets do
			if asset.preload == "lazy" then
				lazy += 1
			else
				table.insert(expected, asset.content or asset.contentId)
			end
		end
		t.expect(lazy > 0).toBe(true)
		table.sort(expected)
		table.sort(requests[1])
		t.expect(table.concat(requests[1], ",")).toBe(table.concat(expected, ","))
		package:set(themes.neutralPackage())
		package:set(pixel)
		t.expect(#requests).toBe(1)
		runtime:dispose()
	end)

	t.it("cuts the avatar-stack separator into the neighbour, outside the avatar's own edge", function()
		for _, entry in packages() do
			local sheet, stop = sheetOf(entry.package)
			for _, member in { ".facet-avatar", ".facet-button" } do
				local selector = ".facet-avatar-stack > " .. member .. "::UIStroke"
				local properties = assert(style(sheet, selector))
				t.expect(`{entry.label} {selector} {properties.BorderStrokePosition}`)
					.toBe(`{entry.label} {selector} Enum.BorderStrokePosition.Outer`)
			end
			stop()
		end
	end)

	t.it("leaves a game's own stroke rules at the engine's stroke position", function()
		local authored = themes.neutralPackage()
		authored.rules = { { selector = ".game-card::UIStroke", properties = { Thickness = 2 } } }
		local sheet, stop = sheetOf(authored)
		local properties = assert(style(sheet, ".game-card::UIStroke"))
		t.expect(properties.ApplyStrokeMode.Name).toBe("Border")
		t.expect(properties.BorderStrokePosition).toBe(nil)
		stop()
	end)

	t.it("rounds every menu highlight concentric with the card inside the rows' inset", function()
		for _, entry in packages() do
			local sheet, stop = sheetOf(entry.package)
			local metrics = entry.package.metrics
			local inset = (metrics.space or themes.neutralPackage().metrics.space).xs
			local corner = assert(style(sheet, ".facet-menu-item::UICorner"))
			t.expect(corner.CornerRadius.Offset).toBe(math.max(0, metrics.radii.panel - inset))
			t.expect(style(sheet, ".facet-menu-end::UICorner")).toBe(nil)
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

	t.it("pads every gallery page through UI.ScrollView, never a hand-written UIPadding at its scroller", function()
		local offenders = {}
		for _, name in fs.readDir("examples/gallery/scenarios") do
			local lines = string.split(fs.readFile("examples/gallery/scenarios/" .. name), "\n")
			for index, line in lines do
				local indent = string.match(line, "^(\t+)Host%.UIPadding%(")
				if indent and not string.find(line, "}%),$") then
					local closing = indent .. "}),"
					for after = index + 1, #lines do
						if lines[after] == closing then
							if string.find(lines[after + 1] or "", "^" .. indent .. "Host%.ScrollingFrame") then
								table.insert(offenders, `{name}:{index} wraps a scroller`)
							end
							break
						end
					end
				end
				local outer = string.match(line, "^(\t*).-Host%.ScrollingFrame[%s%(]")
				if outer then
					local padded, crossAxis = false, false
					for after = index + 1, #lines do
						local inner = lines[after]
						if string.find(inner, "^" .. outer .. "[})]") then
							break
						end
						padded = padded or string.find(inner, "^" .. outer .. "\tHost%.UIPadding%(") ~= nil
						crossAxis = crossAxis
							or string.find(inner, "^" .. outer .. "\tScrollingDirection = [%w%.]+%.XY?,") ~= nil
					end
					if padded and not crossAxis then
						table.insert(offenders, `{name}:{index} pads inside a page scroller`)
					end
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
		end, { motionLevel = "none", theme = parchment })
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

	t.it("keeps a PageView dot a plain dot on a skinned theme, not a control plate", function()
		local parchment = (require :: any)("../examples/themes/fantasy_parchment").build(themes)
		local world = worlds.new(function(UI, Host)
			return UI.PageView({
				selection = Facet.Compose.cell("one"),
				pages = {
					{ id = "one", title = "One", content = Host.Frame({}) },
					{ id = "two", title = "Two", content = Host.Frame({}) },
				},
			})
		end, { motionLevel = "none", theme = parchment })
		local dots = world.find("Indicators")
		for _, dot in dots:GetChildren() do
			if dot:IsA("GuiButton") then
				t.expect(`{dot.Name} {dot:HasTag("facet-skinned")}`).toBe(`{dot.Name} false`)
			end
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

	t.it("keeps a horizontal rail free of the vertical gutter", function()
		local world = worlds.new(function(UI, Host)
			return Host.Frame {
				UI.ScrollView "Chips" { axis = "x", UI.Text { text = "A" } },
				UI.VirtualList "Rail" {
					from = { { id = 1 }, { id = 2 } },
					key = function(item)
						return item.id
					end,
					direction = "horizontal",
					itemSize = 80,
					render = function()
						return Host.Frame {}
					end,
				},
			}
		end)
		for _, name in { "Chips", "Rail" } do
			local node = world.find(name)
			local scroller = if node:IsA("ScrollingFrame")
				then node
				else node:FindFirstChildWhichIsA("ScrollingFrame", true)
			t.expect(`{name} {scroller.VerticalScrollBarInset.Name}`).toBe(`{name} ScrollBar`)
		end
		world.stop()
	end)
end)
