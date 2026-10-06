--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness, tier: string)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type FrameConstructor = typeof(require("@repo/tools/typecheck/aliases").FrameConstructor)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local Compose: ComposeModule = Facet.Compose
	local themes = Facet.themes
	local expect = Verify.expect

	local function package(): any
		local made = themes.neutralPackage()
		made.metrics.controlSizes = {
			compact = { height = 40, paddingX = 11, iconSize = 16 },
			regular = { height = 52, paddingX = 15, iconSize = 20 },
			large = { height = 64, paddingX = 19, iconSize = 24 },
		}
		return made
	end

	local function world(theme: any, build: (any) -> any): (any, any, () -> ())
		local engine: any = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local gui = engine.new("GuiService")
		local input = engine.new("UserInputService")
		input.GetFocusedTextBox = function()
			return nil
		end
		local UI = Facet.controls(
			runtime,
			{
				types = engine.types,
				theme = theme,
				guiService = gui,
				services = { GuiService = gui, UserInputService = input },
			} :: any
		)
		local _, sheet: any = runtime.mount(function()
			return themes.createStyleSheet(runtime, theme, { types = engine.types } :: any)
		end, engine.new("Folder"))
		local stop, root: any = runtime.mount(function()
			return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({ build(UI) })
		end, engine.new("ScreenGui"))
		return root, sheet, function()
			stop()
			runtime:dispose()
		end
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

	local function matches(part: string, node: any): boolean
		for tag in string.gmatch(part, "%.([%w%-]+)") do
			if not node:HasTag(tag) then
				return false
			end
		end
		return true
	end

	local function padding(sheet: any, node: any, property: string): any
		local best, value = -math.huge, nil
		for _, rule in sheet:GetChildren() do
			local selector = rule.Selector
			local compound = string.match(selector, "^([%.%w%-]+)::UIPadding$")
			if compound and matches(compound, node) then
				local candidate = rule:GetProperties()[property]
				if candidate ~= nil and rule.Priority > best then
					best, value = rule.Priority, candidate
				end
			end
		end
		return value
	end

	local FORMS: { [string]: (any, string, ("xsmall" | "compact" | "regular" | "large")?) -> any } = {
		Button = function(UI: FacetControls, name: string, rung: ("xsmall" | "compact" | "regular" | "large")?)
			return UI.Button(name)({
				label = "Manage equipment",
				controlSize = rung,
				row = { description = "Choose a driver", value = "2 drivers", icon = "settings" },
				onActivate = function() end,
			})
		end,
		Toggle = function(UI: FacetControls, name: string, rung: ("xsmall" | "compact" | "regular" | "large")?)
			return UI.Toggle(name)({
				label = "Driving assistance",
				controlSize = rung,
				value = Compose.cell(true),
				row = { description = "Keep the car stable", icon = "settings" },
			})
		end,
		Slider = function(UI: FacetControls, name: string, rung: ("xsmall" | "compact" | "regular" | "large")?)
			return UI.Slider(name)({
				label = "Music volume",
				controlSize = rung,
				value = Compose.cell(50),
				min = 0,
				max = 100,
				row = { description = "Balance music", icon = "settings" },
			})
		end,
	}

	verifyHarness:suite("native settings rows share one list row", function()
		verifyHarness:case(
			"every row form takes its minimum height and padding from the controlSize rung of the theme",
			{
				id = "native_list_rows::native settings rows share one list row::every row form takes its minimum height and padding from the controlSize rung of the theme",
				run = function()
					local theme = package()
					for form, build in FORMS do
						for _, rung in
							{ "compact", "regular", "large", "none" } :: { "compact" | "large" | "none" | "regular" }
						do
							local step = if rung == "none" then nil else rung
							local metrics = theme.metrics.controlSizes[step or "regular"]
							local root, sheet, stop = world(theme, function(UI: FacetControls)
								return build(UI, "Row", step :: ("compact" | "large" | "regular" | "xsmall")?)
							end)
							local row = find(root, "Row")
							local label = `{form} {rung}`
							expect(`{label}: {row.Size.X.Scale} {row.Size.Y.Offset} {row.AutomaticSize.Name}`):toBe(
								`{label}: 1 {metrics.height} Y`
							)
							local vertical = (metrics.height - metrics.iconSize - theme.metrics.space.xs) // 2
							for side, pixels in
								{
									PaddingLeft = metrics.paddingX,
									PaddingRight = metrics.paddingX,
									PaddingTop = vertical,
									PaddingBottom = vertical,
								}
							do
								local value = padding(sheet, row, tostring(side))
								expect(`{label} {side}: {if value then value.Offset else "none"}`):toBe(
									`{label} {side}: {pixels}`
								)
							end
							stop()
						end
					end
				end,
			}
		)

		verifyHarness:case(
			"every row form is the same list row: tag, leading icon, filling captions, secondary description",
			{
				id = "native_list_rows::native settings rows share one list row::every row form is the same list row: tag, leading icon, filling captions, secondary description",
				run = function()
					for form, build in FORMS do
						local root, _, stop = world(themes.neutralPackage(), function(UI: FacetControls)
							return build(UI, "Row", nil)
						end)
						local row = find(root, "Row")
						expect(`{form}: {row:HasTag("facet-list-row")}`):toBe(`{form}: true`)
						local content = row:FindFirstChild("Content")
						expect(`{form} content: {content ~= nil}`):toBe(`{form} content: true`)
						local layout = content:FindFirstChildWhichIsA("UIListLayout")
						expect(`{form}: {layout.FillDirection.Name} {layout.VerticalAlignment.Name}`):toBe(
							`{form}: Horizontal Center`
						)
						local order = {}
						for _, child in content:GetChildren() do
							if child:IsA("GuiObject") then
								order[child.LayoutOrder] = child
							end
						end
						expect(`{form}: {order[1].Name} {order[2].Name}`):toBe(`{form}: LeadingIcon Captions`)
						local flex = order[2]:FindFirstChildWhichIsA("UIFlexItem")
						expect(`{form} fill: {flex and flex.FlexMode.Name}`):toBe(`{form} fill: Fill`)
						local title, description = find(order[2], "Title"), find(order[2], "Description")
						expect(`{form} title: {title and title.ClassName}`):toBe(`{form} title: TextLabel`)
						expect(`{form} description: {description and description:HasTag("facet-secondary")}`):toBe(
							`{form} description: true`
						)
						expect(`{form} wraps: {description.TextWrapped} {description.Size.X.Scale}`):toBe(
							`{form} wraps: true 1`
						)
						stop()
					end
				end,
			}
		)

		verifyHarness:case(
			"a row Button in a hugging parent takes its natural width instead of collapsing its captions",
			{
				id = "native_list_rows::native settings rows share one list row::a row Button in a hugging parent takes its natural width instead of collapsing its captions",
				run = function()
					local worlds = require("./lib/content_world")
					local w = worlds.new(function(UI: FacetControls, Host: RobloxHost, engine)
						return Host.Frame({
							Name = "Cell",
							AutomaticSize = engine.types.Enum.AutomaticSize.XY,
							UI.Button("Row")({
								label = "Button",
								row = { description = "Shown in the garage", icon = "settings", value = "On" },
							}),
						})
					end)
					local row = w.find("Row")
					Verify.expect(row.AutomaticSize.Name):toBe("XY")
					local title = w.find("Title", row)
					Verify.expect(`{title.Size.X.Scale} {title.AutomaticSize.Name}`):toBe("0 XY")
					Verify.expect(w.find("Value", row).Parent):toBe(w.find("Captions", row).Parent)
					w.stop()
				end,
			}
		)
	end)
end
