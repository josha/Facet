--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local Compose = Facet.Compose
local themes = Facet.themes
local Roblox = require("@lune/roblox")

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

local function make(options: { [string]: any }?): (any, any, any)
	local engine: any = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local gui = engine.new("GuiService")
	local config: { [string]: any } = { types = engine.types, guiService = gui, services = { GuiService = gui } }
	for key, value in (options or {}) :: { [string]: any } do
		config[key] = value
	end
	return engine, runtime, Facet.controls(runtime, config :: any)
end

local function build(options: { [string]: any }?, body: (any, any) -> any): (any, any, () -> ())
	local engine, runtime, UI = make(options)
	local root: any
	runtime.mount(function()
		root = body(UI, runtime.constructors)
		return root
	end, engine.new("ScreenGui"))
	return root, engine, function()
		runtime:dispose()
	end
end

local function refusal(body: (any, any) -> any, options: { [string]: any }?): string?
	local engine, runtime, UI = make(options)
	local ok, message = pcall(function()
		runtime.mount(function()
			return body(UI, runtime.constructors)
		end, engine.new("ScreenGui"))
	end)
	runtime:dispose()
	return if ok then nil else tostring(message)
end

local function mentions(message: string?, fragment: string): boolean
	return message ~= nil and string.find(message, fragment, 1, true) ~= nil
end

local function sheetOf(package: any): (any, () -> ())
	local engine: any = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local _, sheet = runtime.mount(function()
		return themes.createStyleSheet(
			runtime,
			package,
			{ types = engine.types, preferredTransparency = 1, reducedMotion = false } :: any
		)
	end, engine.new("Folder"))
	return sheet, function()
		runtime:dispose()
	end
end

local function style(sheet: any, selector: string): { [string]: any }
	for _, node in sheet:GetChildren() do
		if node.Selector == selector then
			return node:GetProperties()
		end
	end
	error("No rule: " .. selector)
end

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

t.describe("native restored controls: Text", function()
	t.it("paints text with its type role and follows a bound text without a rebuild", function()
		local value = Compose.cell("Lap 1")
		local root, _, stop = build(nil, function(UI)
			return UI.Text("Lap")({ text = value, textRole = "title" })
		end)
		t.expect(root.ClassName).toBe("TextLabel")
		t.expect(root.Name).toBe("Lap")
		t.expect(root.Text).toBe("Lap 1")
		t.expect(root:HasTag("facet-text")).toBe(true)
		t.expect(root:HasTag("facet-type-title")).toBe(true)
		value:set("Lap 2")
		t.expect(root.Text).toBe("Lap 2")
		stop()
		value:set("Lap 3")
		t.expect(value:peek()).toBe("Lap 3")
	end)

	t.it("takes a pixel size, a role name, alignment, wrapping, rich text, direction and tint", function()
		local align = Compose.cell("center")
		local root, engine, stop = build(nil, function(UI, Host)
			return Host.Frame({
				UI.Text("Pixels")({ text = "a", textSize = 22 }),
				UI.Text("Role")({ text = "b", textSize = "caption" }),
				UI.Text("Styled")({
					text = "<b>c</b>",
					textAlign = align,
					wrap = true,
					rich = true,
					direction = "rtl",
					tint = Roblox.Color3.new(1, 0, 0),
				}),
			})
		end)
		local Enum = engine.types.Enum
		local pixels, role, styled =
			root:FindFirstChild("Pixels"), root:FindFirstChild("Role"), root:FindFirstChild("Styled")
		t.expect(pixels.TextSize).toBe(22)
		t.expect(pixels:HasTag("facet-type-body")).toBe(true)
		t.expect(role:HasTag("facet-type-caption")).toBe(true)
		t.expect(role:HasTag("facet-type-body")).toBe(false)
		t.expect(styled.TextXAlignment).toBe(Enum.TextXAlignment.Center)
		align:set("end")
		t.expect(styled.TextXAlignment).toBe(Enum.TextXAlignment.Right)
		t.expect(styled.TextWrapped).toBe(true)
		t.expect(styled.RichText).toBe(true)
		t.expect(styled.TextDirection).toBe(Enum.TextDirection.RightToLeft)
		t.expect(styled.TextColor3).toBe(engine.types.Color3.new(1, 0, 0))
		stop()
	end)

	t.it("turns the secondary role on and off with a bound role", function()
		local role = Compose.cell("secondary")
		local root, _, stop = build(nil, function(UI)
			return UI.Text({ text = "Offline", role = role })
		end)
		t.expect(root:HasTag("facet-secondary")).toBe(true)
		role:set("content")
		t.expect(root:HasTag("facet-secondary")).toBe(false)
		role:set("secondary")
		t.expect(root:HasTag("facet-secondary")).toBe(true)
		stop()
	end)

	t.it("refuses a missing text, the retired spellings, style authority and a doubled role", function()
		t.expect(mentions(
			refusal(function(UI)
				return UI.Text({})
			end),
			"requires text"
		)).toBe(true)
		for _, spec in { { label = "a" }, { text = "a", label = "b" }, { Text = "a" } } :: { any } do
			t.expect(mentions(
				refusal(function(UI)
					return UI.Text(spec)
				end),
				"set the text with text"
			)).toBe(true)
		end
		for _, key in { "color", "font" } do
			t.expect(mentions(
				refusal(function(UI)
					return UI.Text({ text = "a", [key] = "x" })
				end),
				"style authority"
			)).toBe(true)
		end
		t.expect(mentions(
			refusal(function(UI)
				return UI.Text({ text = "a", textSize = "title", textRole = "body" })
			end),
			"one time"
		)).toBe(true)
		t.expect(mentions(
			refusal(function(UI)
				return UI.Text({ text = "a", role = "loud" })
			end),
			"secondary or content"
		)).toBe(true)
		t.expect(mentions(
			refusal(function(UI)
				return UI.Text({ text = "a", direction = "up" })
			end),
			"auto, ltr or rtl"
		)).toBe(true)
	end)
end)

t.describe("native restored controls: Label", function()
	t.it("renders an icon and a title together and names itself by the title", function()
		local root, _, stop = build(nil, function(UI)
			return UI.Label("Save")({ title = "Save", icon = "rbxassetid://1" })
		end)
		t.expect(root.Name).toBe("Save")
		t.expect(root:FindFirstChild("Icon").ClassName).toBe("ImageLabel")
		t.expect(root:FindFirstChild("Icon").Image).toBe("rbxassetid://1")
		t.expect(root:FindFirstChild("Title").Text).toBe("Save")
		t.expect(root:GetAttribute("AccessibleLabel")).toBe("Save")
		t.expect(root:GetAttribute("FacetPresentation")).toBe("titleAndIcon")
		t.expect(root:FindFirstChild("Icon").LayoutOrder < root:FindFirstChild("Title").LayoutOrder).toBe(true)
		stop()
	end)

	t.it("keeps the title as the accessible name when it shows the icon only", function()
		local root, _, stop = build(nil, function(UI)
			return UI.Label({ title = "Save", icon = "rbxassetid://1", presentation = "iconOnly" })
		end)
		t.expect(root:FindFirstChild("Title")).toBe(nil)
		t.expect(root:FindFirstChild("Icon") ~= nil).toBe(true)
		t.expect(root:GetAttribute("AccessibleLabel")).toBe("Save")
		t.expect(root:GetAttribute("FacetPresentation")).toBe("iconOnly")
		stop()
	end)

	t.it("shows the title when iconOnly has no icon, because an empty square is worse than a word", function()
		local root, _, stop = build(nil, function(UI)
			return UI.Label({ title = "Save", presentation = "iconOnly" })
		end)
		t.expect(root:GetAttribute("FacetPresentation")).toBe("titleOnly")
		t.expect(root:FindFirstChild("Title") ~= nil).toBe(true)
		t.expect(root:FindFirstChild("Icon")).toBe(nil)
		stop()
	end)

	t.it("titleOnly renders no empty icon slot", function()
		local root, _, stop = build(nil, function(UI)
			return UI.Label({ title = "Save", icon = "rbxassetid://1", presentation = "titleOnly" })
		end)
		t.expect(root:FindFirstChild("Icon")).toBe(nil)
		t.expect(root:FindFirstChild("Title").Text).toBe("Save")
		stop()
	end)

	for _, form in { "cell", "formula", "function" } do
		t.it(`tracks a {form} title in the text and the accessible name without a rebuild`, function()
			local value = Compose.cell("Lap 1")
			local builds = 0
			local root, _, stop = build(nil, function(UI)
				builds += 1
				local title: any = if form == "cell"
					then value
					elseif form == "formula" then Compose.formula(function(use)
						return use(value)
					end)
					else function(use: any)
						return use(value)
					end
				return UI.Label("Lap")({ title = title })
			end)
			local before = root:FindFirstChild("Title")
			t.expect(before.Text).toBe("Lap 1")
			value:set("Lap 2")
			t.expect(root:FindFirstChild("Title")).toBe(before)
			t.expect(before.Text).toBe("Lap 2")
			t.expect(root:GetAttribute("AccessibleLabel")).toBe("Lap 2")
			t.expect(builds).toBe(1)
			stop()
			value:set("Lap 3")
			t.expect(value:peek()).toBe("Lap 3")
		end)
	end

	t.it("requires a title, because an icon-only label without one has no accessible name", function()
		for _, spec in
			{
				{ icon = "rbxassetid://1" },
				{ title = "" },
				{ title = 4 },
				{ title = Compose.cell("") },
				{
					title = function()
						return false
					end,
				},
			} :: { any }
		do
			t.expect(mentions(
				refusal(function(UI)
					return UI.Label(spec)
				end),
				"title"
			)).toBe(true)
		end
	end)

	t.it("rejects an unknown presentation and names the legal set", function()
		t.expect(mentions(
			refusal(function(UI)
				return UI.Label({ title = "T", presentation = "sideways" })
			end),
			"iconOnly | titleAndIcon | titleOnly"
		)).toBe(true)
	end)

	t.it("refuses an unknown semantic icon and plain-text options", function()
		t.expect(mentions(
			refusal(function(UI)
				return UI.Label({ title = "Saved", icon = "check" })
			end),
			"unknown icon"
		)).toBe(true)
		t.expect(mentions(
			refusal(function(UI)
				return UI.Label({ text = "Saved" })
			end),
			"UI.Text"
		)).toBe(true)
	end)

	t.it("sizes a semantic icon by a metric name or pixels, and puts it after the title on request", function()
		local root, _, stop = build(nil, function(UI, Host)
			return Host.Frame({
				UI.Label("Metric")({
					title = "Search",
					icon = "facet:search",
					presentation = "iconOnly",
					iconSize = "controlSizes.large.iconSize",
				}),
				UI.Label("Pixels")({
					title = "Next",
					icon = "chevron.trailing",
					iconSize = 30,
					iconPosition = "trailing",
				}),
			})
		end)
		local metric = root:FindFirstChild("Metric"):FindFirstChild("Icon")
		local expected = themes.neutralPackage().metrics.controlSizes.large.iconSize
		t.expect(metric.Size.X.Offset).toBe(expected)
		t.expect(metric.Image ~= "").toBe(true)
		local pixels = root:FindFirstChild("Pixels")
		t.expect(pixels:FindFirstChild("Icon").Size.X.Offset).toBe(30)
		t.expect(pixels:FindFirstChild("Title").LayoutOrder < pixels:FindFirstChild("Icon").LayoutOrder).toBe(true)
		stop()
	end)
end)

t.describe("native restored controls: Image", function()
	t.it("maps every scale mode to the native ScaleType and follows a bound mode", function()
		local mode = Compose.cell("fit")
		local root, engine, stop = build(nil, function(UI, Host)
			return Host.Frame({
				UI.Image("Bound")({ image = "rbxassetid://1", scaleMode = mode }),
				UI.Image("Tile")({
					image = "rbxassetid://1",
					scaleMode = "tile",
					tileSize = { width = 32, height = 16 },
				}),
				UI.Image("Slice")({
					image = "rbxassetid://1",
					scaleMode = "slice",
					sliceCenter = { x0 = 8, y0 = 8, x1 = 56, y1 = 56 },
					sliceScale = 2,
				}),
			})
		end)
		local types = engine.types
		local ScaleType = types.Enum.ScaleType
		local bound = root:FindFirstChild("Bound")
		t.expect(bound.ClassName).toBe("ImageLabel")
		t.expect(bound.Image).toBe("rbxassetid://1")
		t.expect(bound.ScaleType).toBe(ScaleType.Fit)
		for word, native in { fill = ScaleType.Crop, crop = ScaleType.Crop, stretch = ScaleType.Stretch } do
			mode:set(word)
			t.expect(bound.ScaleType).toBe(native)
		end
		local tile = root:FindFirstChild("Tile")
		t.expect(tile.ScaleType).toBe(ScaleType.Tile)
		t.expect(tile.TileSize).toBe(types.UDim2.fromOffset(32, 16))
		local slice = root:FindFirstChild("Slice")
		t.expect(slice.ScaleType).toBe(ScaleType.Slice)
		t.expect(slice.SliceCenter).toBe(types.Rect.new(8, 8, 56, 56))
		t.expect(slice.SliceScale).toBe(2)
		stop()
	end)

	t.it("checks each geometry key against its mode in both directions", function()
		local cases: { { spec: any, fragment: string } } = {
			{ spec = { scaleMode = "tile" }, fragment = "requires tileSize" },
			{ spec = { scaleMode = "tile", tileSize = { width = 1.5, height = 2 } }, fragment = "whole pixels" },
			{ spec = { tileSize = { width = 2, height = 2 } }, fragment = "tileSize requires scaleMode tile" },
			{ spec = { scaleMode = "slice" }, fragment = "requires sliceCenter" },
			{ spec = { sliceCenter = { x0 = 1, y0 = 1, x1 = 2, y1 = 2 } }, fragment = "requires scaleMode slice" },
			{ spec = { sliceScale = 2 }, fragment = "sliceScale requires scaleMode slice" },
			{
				spec = { scaleMode = "slice", sliceCenter = { x0 = 1, y0 = 1, x1 = 2, y1 = 2 }, sliceScale = 0 },
				fragment = "above zero",
			},
			{
				spec = { scaleMode = Compose.cell("fit"), tileSize = { width = 2, height = 2 } },
				fragment = "static",
			},
			{
				spec = { shape = "circle", scaleMode = "slice", sliceCenter = { x0 = 1, y0 = 1, x1 = 2, y1 = 2 } },
				fragment = "circle cannot slice",
			},
			{ spec = { scaleMode = "zoom" }, fragment = "scaleMode must be" },
			{ spec = { imageFraming = { width = 2, height = 2 } }, fragment = "unknown option" },
		}
		for _, case in cases do
			t.expect(mentions(
				refusal(function(UI)
					return UI.Image(case.spec)
				end),
				case.fragment
			)).toBe(true)
		end
		local mode = Compose.cell("fit")
		local root, engine, stop = build(nil, function(UI)
			return UI.Image({ scaleMode = mode })
		end)
		local ok, failure = pcall(function()
			mode:set("tile")
		end)
		t.expect(ok).toBe(false)
		t.expect(mentions(tostring(failure), "static geometry")).toBe(true)
		t.expect(root.ScaleType).toBe(engine.types.Enum.ScaleType.Fit)
		stop()
	end)

	t.it("resamples, tints, sizes and rounds a circle through native properties", function()
		local resample = Compose.cell("pixelated")
		local root, engine, stop = build(nil, function(UI)
			return UI.Image({
				image = "rbxassetid://2",
				resample = resample,
				tint = Roblox.Color3.new(0, 1, 0),
				shape = "circle",
			})
		end)
		local types = engine.types
		t.expect(root.ResampleMode).toBe(types.Enum.ResamplerMode.Pixelated)
		resample:set("default")
		t.expect(root.ResampleMode).toBe(types.Enum.ResamplerMode.Default)
		t.expect(root.ImageColor3).toBe(types.Color3.new(0, 1, 0))
		local height = themes.neutralPackage().metrics.controlSizes.regular.height
		t.expect(root.Size).toBe(types.UDim2.fromOffset(height, height))
		t.expect(root:FindFirstChildWhichIsA("UICorner").CornerRadius).toBe(types.UDim.new(0.5, 0))
		t.expect(root:FindFirstChildWhichIsA("UIAspectRatioConstraint").AspectRatio).toBe(1)
		t.expect(root.BackgroundTransparency).toBe(1)
		stop()
	end)
end)

t.describe("native restored controls: Divider", function()
	t.it("takes its direction from the stack that holds it and turns with it", function()
		local root, engine, stop = build(nil, function(UI, Host)
			return Host.Frame({
				UI.VStack("Column")({ UI.Divider("Rule")({}) }),
				UI.HStack("Row")({ UI.Divider("Rule")({}) }),
				UI.HStack("Forced")({ UI.Divider("Rule")({ axis = "y" }) }),
			})
		end)
		local UDim2 = engine.types.UDim2
		local hairline = themes.neutralPackage().metrics.strokes.hairline
		local function rule(name: string): any
			return root:FindFirstChild(name):FindFirstChild("Rule")
		end
		t.expect(rule("Column").Size).toBe(UDim2.new(1, 0, 0, hairline))
		t.expect(rule("Row").Size).toBe(UDim2.new(0, hairline, 1, 0))
		t.expect(rule("Forced").Size).toBe(UDim2.new(1, 0, 0, hairline))
		local layout = root:FindFirstChild("Column"):FindFirstChildWhichIsA("UIListLayout")
		layout.FillDirection = engine.types.Enum.FillDirection.Horizontal
		t.expect(rule("Column").Size).toBe(UDim2.new(0, hairline, 1, 0))
		layout.FillDirection = engine.types.Enum.FillDirection.Vertical
		t.expect(rule("Column").Size).toBe(UDim2.new(1, 0, 0, hairline))
		stop()
	end)

	t.it("uses the theme hairline weight by default and accepts pixels or a metric name", function()
		local theme = Compose.cell(themes.neutralPackage())
		local root, engine, stop = build({ theme = theme }, function(UI)
			return UI.VStack({
				UI.Divider("Default")({}),
				UI.Divider("Pixels")({ thickness = 3 }),
				UI.Divider("Step")({ thickness = "xs" }),
			})
		end)
		local UDim2 = engine.types.UDim2
		t.expect(root:FindFirstChild("Default").Size).toBe(UDim2.new(1, 0, 0, 1))
		t.expect(root:FindFirstChild("Pixels").Size).toBe(UDim2.new(1, 0, 0, 3))
		local xs = themes.neutralPackage().metrics.space.xs
		t.expect(root:FindFirstChild("Step").Size).toBe(UDim2.new(1, 0, 0, xs))
		local heavy = themes.neutralPackage()
		heavy.metrics.strokes.hairline = 2
		theme:set(heavy)
		t.expect(root:FindFirstChild("Default").Size).toBe(UDim2.new(1, 0, 0, 2))
		stop()
		t.expect(mentions(
			refusal(function(UI)
				return UI.Divider({ thickness = 0 })
			end),
			"positive number"
		)).toBe(true)
	end)

	t.it("wears the divider tags and adds the strong tag while a bound appearance is strong", function()
		local appearance = Compose.cell("standard")
		local root, _, stop = build(nil, function(UI)
			return UI.Divider({ appearance = appearance })
		end)
		t.expect(root:HasTag("facet-divider")).toBe(true)
		t.expect(root:HasTag("facet-divider-strong")).toBe(false)
		appearance:set("strong")
		t.expect(root:HasTag("facet-divider-strong")).toBe(true)
		appearance:set("standard")
		t.expect(root:HasTag("facet-divider-strong")).toBe(false)
		stop()
		t.expect(mentions(
			refusal(function(UI)
				return UI.Divider({ appearance = "loud" })
			end),
			"standard or strong"
		)).toBe(true)
	end)

	t.it("spends the transparency the hairline strokes spend in every shipped package", function()
		local count = 0
		for _, entry in packages() do
			local sheet, stop = sheetOf(entry.package)
			local extra = entry.package.style.themes[1].extra or {}
			local divider = style(sheet, ".facet-divider").BackgroundTransparency
			local stroke = style(sheet, ".facet-shortcut-hint::UIStroke").Transparency
			t.expect(divider).toBe(stroke)
			t.expect(divider).toBe(extra.hairlineOpacity or 0.92)
			local strong = style(sheet, ".facet-divider-strong").BackgroundTransparency
			t.expect(strong < divider).toBe(true)
			stop()
			count += 1
		end
		t.expect(count).toBe(#SHIPPED + 1)
	end)

	t.it("composited over its surface, a washed divider is quieter than secondary content", function()
		local function distance(a: any, b: any): number
			return math.max(math.abs(a.R - b.R), math.abs(a.G - b.G), math.abs(a.B - b.B))
		end
		local washed, bold = 0, {}
		for _, entry in packages() do
			local sheet, stop = sheetOf(entry.package)
			local rule = style(sheet, ".facet-divider")
			local transparency = rule.BackgroundTransparency
			if transparency < 0.5 then
				table.insert(bold, entry.label)
			else
				washed += 1
				local ink = rule.BackgroundColor3
				local words = style(sheet, ".facet-secondary").TextColor3
				for _, ground in
					{
						style(sheet, ".facet-level-segment").BackgroundColor3,
						style(sheet, ".facet-pane").BackgroundColor3,
					}
				do
					local alpha = 1 - transparency
					local seam = {
						R = ground.R + (ink.R - ground.R) * alpha,
						G = ground.G + (ink.G - ground.G) * alpha,
						B = ground.B + (ink.B - ground.B) * alpha,
					}
					t.expect(distance(seam, ground) > 0).toBe(true)
					t.expect(distance(seam, ground) < distance(words, ground)).toBe(true)
				end
			end
			stop()
		end
		t.expect(washed >= #SHIPPED).toBe(true)
		t.expect(table.concat(bold, ",")).toBe("pixel_quest")
	end)
end)

t.describe("native restored controls: Spacer", function()
	t.it("fills the free main-axis space and keeps a themed minimum on the stack axis", function()
		local floor = Compose.cell("m")
		local root, engine, stop = build(nil, function(UI)
			return UI.VStack({
				UI.HStack("Row")({ UI.Spacer("Gap")({ minLength = floor }) }),
				UI.VStack("Column")({ UI.Spacer("Gap")({ minLength = 12 }) }),
				UI.VStack("Bare")({ UI.Spacer("Gap")({}) }),
			})
		end)
		local UDim2 = engine.types.UDim2
		local space = themes.neutralPackage().metrics.space
		local row = root:FindFirstChild("Row"):FindFirstChild("Gap")
		t.expect(row:FindFirstChildWhichIsA("UIFlexItem").FlexMode).toBe(engine.types.Enum.UIFlexMode.Fill)
		t.expect(row.BackgroundTransparency).toBe(1)
		t.expect(row.Size).toBe(UDim2.fromOffset(space.m, 0))
		floor:set("l")
		t.expect(row.Size).toBe(UDim2.fromOffset(space.l, 0))
		t.expect(root:FindFirstChild("Column"):FindFirstChild("Gap").Size).toBe(UDim2.fromOffset(0, 12))
		t.expect(root:FindFirstChild("Bare"):FindFirstChild("Gap").Size).toBe(UDim2.fromOffset(0, 0))
		stop()
	end)

	t.it("keeps an explicit native size and refuses an invalid minimum", function()
		local root, engine, stop = build(nil, function(UI)
			return UI.HStack({ UI.Spacer("Gap")({ Size = Roblox.UDim2.fromOffset(40, 4), minLength = 8 }) })
		end)
		t.expect(root:FindFirstChild("Gap").Size).toBe(engine.types.UDim2.fromOffset(40, 4))
		stop()
		for _, value in { -1, "huge" } :: { any } do
			t.expect(refusal(function(UI)
				return UI.HStack({ UI.Spacer({ minLength = value }) })
			end) ~= nil).toBe(true)
		end
	end)
end)
