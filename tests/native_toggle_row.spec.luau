--!strict
local t = require("./lib/testkit")
local Compose = require("../src/vendor/compose/core")
local Roblox = require("../src/vendor/compose/roblox")
local context = require("../src/ui/context")
local register = require("../src/ui/inputs")
local bindThemes = require("../src/ui/themes")
local engineLib = require("./lib/native_engine")
local expect = t.expect

local themes = bindThemes(Compose)
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

local function shipped(name: string): any
	local module: any = (require :: any)("../examples/themes/" .. name)
	return (module.build(themes))
end

local function mount(theme: any?, build: (any) -> any): (any, () -> ())
	local engine: any = engineLib.new()
	local runtime = Roblox.createRuntime(engine)
	local UI: any = {}
	register(context(Compose, runtime, { types = engine.types, theme = theme }), UI)
	local screen = engine.new("ScreenGui")
	local stop = runtime.mount(function()
		return build(UI)
	end, screen)
	return screen, stop
end

local function find(root: any, name: string): any
	if root.Name == name then
		return root
	end
	for _, child in root:GetChildren() do
		local found = find(child, name)
		if found then
			return found
		end
	end
	return nil
end

local function padding(package: any, selector: string): (number, number)
	local engine: any = engineLib.new()
	local runtime = Roblox.createRuntime(engine)
	local sheet: any
	local stop = runtime.mount(function()
		sheet = themes.createStyleSheet(runtime, package, { types = engine.types })
		return sheet
	end, engine.new("Folder"))
	local left, right = nil, nil
	for _, rule in sheet:GetChildren() do
		if rule.Selector == selector then
			local properties = rule:GetProperties()
			left = if properties.PaddingLeft then properties.PaddingLeft.Offset else left
			right = if properties.PaddingRight then properties.PaddingRight.Offset else right
		end
	end
	stop()
	return assert(left), assert(right)
end

t.describe("native Toggle rows", function()
	t.it("a switch, bare or in a settings row, wears no plate and no control art", function()
		for _, theme in { "pixel_quest", "fantasy_ornate" } do
			local package = shipped(theme)
			local screen, stop = mount(package, function(UI)
				return UI.Button("Holder")({
					label = "",
					UI.Toggle("Bare")({ label = "Bare", value = Compose.cell(true) }),
					UI.Toggle("Row")({
						label = "Driving assistance",
						value = Compose.cell(true),
						row = { description = "Keep the car stable" },
					}),
				})
			end)
			for _, name in { "Bare", "Row" } do
				local toggle = find(screen, name)
				expect(`{theme} {name}: {toggle:HasTag("facet-toggle-row")}`).toBe(`{theme} {name}: true`)
				local art = nil
				for _, child in toggle:GetChildren() do
					if child.Name == "SkinBoundary" then
						art = child
					end
				end
				expect(`{theme} {name}: {art == nil}`).toBe(`{theme} {name}: true`)
			end
			local holder = find(screen, "Holder")
			local holderArt = false
			for _, child in holder:GetChildren() do
				holderArt = holderArt or child.Name == "SkinBoundary"
			end
			expect(`{theme} button art: {holderArt}`).toBe(`{theme} button art: true`)
			stop()
		end
	end)

	t.it("a toggle settings row starts its content where a button row does, in every package", function()
		local packages = { themes.neutralPackage() }
		for _, name in SHIPPED do
			table.insert(packages, shipped(name))
		end
		for _, package in packages do
			local bl, br = padding(package, ".facet-button::UIPadding")
			local tl, tr = padding(package, ".facet-toggle-settings::UIPadding")
			expect(`{package.identity.id}: {tl} {tr}`).toBe(`{package.identity.id}: {bl} {br}`)
			local sl, sr = padding(package, ".facet-slider-settings::UIPadding")
			expect(`{package.identity.id}: {sl} {sr}`).toBe(`{package.identity.id}: {bl} {br}`)
		end
		local screen, stop = mount(nil, function(UI)
			return UI.Toggle("Row")({
				label = "Driving assistance",
				value = Compose.cell(true),
				row = { description = "Keep the car stable" },
			})
		end)
		expect(find(screen, "Row"):HasTag("facet-toggle-settings")).toBe(true)
		stop()
		local plain, stopPlain = mount(nil, function(UI)
			return UI.Toggle("Plain")({ label = "Plain", value = Compose.cell(true) })
		end)
		expect(find(plain, "Plain"):HasTag("facet-toggle-settings")).toBe(false)
		stopPlain()
	end)

	t.it("a toggle settings row puts its icon first and its switch last, like a button row", function()
		local screen, stop = mount(nil, function(UI)
			return UI.Toggle("Row")({
				label = "Driving assistance",
				value = Compose.cell(true),
				row = { description = "Keep the car stable", icon = "settings" },
			})
		end)
		local content = find(find(screen, "Row"), "Content")
		local order = {}
		for _, child in content:GetChildren() do
			if child:IsA("GuiObject") then
				order[child.LayoutOrder] = child
			end
		end
		expect(order[1].Name).toBe("LeadingIcon")
		expect(order[3]:HasTag("facet-toggle-indicator")).toBe(true)
		expect(order[2]:FindFirstChildWhichIsA("UIFlexItem") ~= nil).toBe(true)
		local row = find(screen, "Row")
		expect(row.Size.X.Scale).toBe(1)
		expect(row.Size.Y.Offset >= 44).toBe(true)
		stop()
	end)
end)
