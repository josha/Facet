--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness, tier: string)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type PickerOption = typeof(require("@repo/tools/typecheck/aliases").PickerOption)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local Compose: ComposeModule = Facet.Compose
	local themes = Facet.themes

	type World = {
		engine: any,
		runtime: any,
		gui: any,
		input: any,
		root: any,
		settle: () -> (),
		stop: () -> (),
	}

	local function setup(build: (any, any, any) -> any, options: { [string]: any }?): World
		local engine: any = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local gui = engine.new("GuiService")
		local input = engine.new("UserInputService")
		input.GetFocusedTextBox = function()
			return nil
		end
		input.IsKeyDown = function()
			return false
		end
		local config: { [string]: any } = {
			types = engine.types,
			guiService = gui,
			services = { GuiService = gui, UserInputService = input },
			motionLevel = "none",
		}
		for key, value in (options or {}) :: { [string]: any } do
			config[key] = value
		end
		local UI = Facet.controls(runtime, config :: any)
		local Host = (runtime.constructors :: unknown) :: RobloxHost
		local stop, root: any = runtime.mount(function()
			return Host.ScreenGui({ build(UI, Host, engine) })
		end, engine.new("Folder"))
		return {
			engine = engine,
			runtime = runtime,
			gui = gui,
			input = input,
			root = root,
			settle = function()
				for _ = 1, 60 do
					engine.heartbeat.fire(1 / 60)
				end
			end,
			stop = function()
				stop()
				runtime:dispose()
			end,
		}
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

	local function glyph(name: string): string?
		return themes.resolveIcon({}, name)
	end

	local function paintedIcon(row: any): string?
		local icon = find(row, "LeadingIcon")
		return if icon and icon.Visible then icon.Image else nil
	end

	local function styleSheet(world: World, package: any): any
		local _, sheet = world.runtime.mount(function()
			return themes.createStyleSheet(
				world.runtime,
				package,
				{ types = world.engine.types, preferredTransparency = 1, motionLevel = "none" } :: any
			)
		end, world.engine.new("Folder"))
		return sheet
	end

	local function styledPadding(sheet: any, node: any, property: string): number?
		local best, priority = nil, -math.huge
		for _, rule in sheet:GetChildren() do
			local selector = rule.Selector
			local tags = if type(selector) == "string" then string.match(selector, "^([%w%-%.]+)::UIPadding$") else nil
			if tags and string.sub(tags, 1, 1) == "." then
				local matches = true
				for tag in string.gmatch(tags, "%.([%w%-]+)") do
					matches = matches and node:HasTag(tag)
				end
				local value = rule:GetProperties()[property]
				if matches and value ~= nil and (rule.Priority or 0) >= priority then
					best, priority = value.Offset, rule.Priority or 0
				end
			end
		end
		return best
	end

	local function withRungPadding(values: { [string]: number }): any
		local package: any = themes.neutralPackage()
		for rung, paddingX in values do
			package.metrics.controlSizes[rung] = package.metrics.controlSizes[rung] or { height = 28, iconSize = 12 }
			package.metrics.controlSizes[rung].paddingX = paddingX
		end
		return package
	end

	local function withSpacing(step: number): any
		local package: any = themes.neutralPackage()
		package.metrics.space.s = step
		return package
	end

	verifyHarness:suite("native parity weak3 h1", function()
		for _, style in { "radioGroup", "inline" } :: { "inline" | "radioGroup" } do
			verifyHarness:case(`repaints a live {style} option icon in place and keeps the row and its focus`, {
				id = "native_parity_weak3_h1::"
					.. "native parity weak3 h1"
					.. "::"
					.. `repaints a live {style} option icon in place and keeps the row and its focus`,
				run = function()
					local selected = Compose.cell("a")
					local icon = Compose.cell("checkmark")
					local options = Compose.cell({
						{ id = "one", value = "a", label = "Alpha", icon = icon :: any, badge = 3 } :: PickerOption,
						{ id = "two", value = "b", label = "Beach" } :: PickerOption,
					})
					local world = setup(function(UI: FacetControls)
						return UI.Picker "Routes" {
							style = style :: "inline" | "radioGroup",
							selected = selected,
							options = options,
						}
					end)
					local picker = find(world.root, "Routes")
					local row = find(picker, "one")
					world.gui.SelectedObject = row
					Verify.expect((paintedIcon(row))):toBe(glyph("checkmark"))
					icon:set("close")
					Verify.expect((paintedIcon(row))):toBe(glyph("close"))
					Verify.expect((find(picker, "one"))):toBe(row)
					options:set({
						{
							id = "one",
							value = "a",
							label = "Alpine",
							description = "A mountain route",
							icon = "edit",
							badge = 7,
						} :: PickerOption,
						{ id = "two", value = "b", label = "Beach" } :: PickerOption,
					})
					Verify.expect((find(picker, "one"))):toBe(row)
					Verify.expect(world.gui.SelectedObject):toBe(row)
					Verify.expect((paintedIcon(row))):toBe(glyph("edit"))
					options:set({
						{ id = "one", value = "a", label = "Alpine" } :: PickerOption,
						{ id = "two", value = "b", label = "Beach" } :: PickerOption,
					})
					Verify.expect((find(picker, "one"))):toBe(row)
					Verify.expect(world.gui.SelectedObject):toBe(row)
					Verify.expect((paintedIcon(row))):toBeNil()
					options:set({ { id = "one", value = "a", label = "Alpine", icon = "checkmark" } })
					Verify.expect((find(picker, "one"))):toBe(row)
					Verify.expect((paintedIcon(row))):toBe(glyph("checkmark"))
					Verify.expect((selected:peek())):toBe("a")
					world.stop()
				end,
			})
		end

		verifyHarness:case(
			"pads Button and Chip by the live controlSizes paddingX of each rung and follows a theme change",
			{
				id = "native_parity_weak3_h1::native parity weak3 h1::pads Button and Chip by the live controlSizes paddingX of each rung and follows a theme change",
				run = function()
					local rung = Compose.cell(nil :: string?)
					local theme = Compose.cell(themes.neutralPackage() :: any)
					local builds = 0
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						builds += 1
						return Host.Frame({
							UI.Button "Other" { label = "Other" } :: unknown,
							UI.Button "Live" { label = "Go", controlSize = rung },
							UI.Chip "Tag" { label = "Tag", selected = Compose.cell(false), controlSize = rung },
						})
					end, { theme = theme })
					local sheet = styleSheet(world, theme)
					local live, chip = find(world.root, "Live"), find(world.root, "Tag")
					world.gui.SelectedObject = live
					for _, node in { live, chip } do
						Verify.expect((styledPadding(sheet, node, "PaddingLeft"))):toBe(12)
						Verify.expect((styledPadding(sheet, node, "PaddingRight"))):toBe(12)
					end
					local first = { xsmall = 4, compact = 8, regular = 12, large = 16 }
					for _, name in { "xsmall", "compact", "regular", "large" } do
						rung:set(name :: "compact" | "large" | "regular" | "xsmall")
						for _, node in { live, chip } do
							Verify.expect(`{name} {styledPadding(sheet, node, "PaddingLeft")}`)
								:toBe(`{name} {first[name]}`)
							Verify.expect(`{name} {styledPadding(sheet, node, "PaddingRight")}`)
								:toBe(`{name} {first[name]}`)
						end
					end
					local second = { xsmall = 6, compact = 14, regular = 18, large = 22 }
					theme:set(withRungPadding(second))
					for _, name in { "xsmall", "compact", "regular", "large" } do
						rung:set(name :: "compact" | "large" | "regular" | "xsmall")
						for _, node in { live, chip } do
							Verify.expect(`{name} {styledPadding(sheet, node, "PaddingLeft")}`)
								:toBe(`{name} {second[name]}`)
							Verify.expect(`{name} {styledPadding(sheet, node, "PaddingRight")}`)
								:toBe(`{name} {second[name]}`)
						end
					end
					rung:set(nil)
					Verify.expect((styledPadding(sheet, live, "PaddingLeft"))):toBe(12)
					Verify.expect((find(world.root, "Live"))):toBe(live)
					Verify.expect((find(world.root, "Tag"))):toBe(chip)
					Verify.expect(world.gui.SelectedObject):toBe(live)
					Verify.expect(builds):toBe(1)
					world.stop()
				end,
			}
		)

		verifyHarness:case(
			"keeps the coach mark inside the theme spacing step at both lateral edges and inside the safe area",
			{
				id = "native_parity_weak3_h1::native parity weak3 h1::keeps the coach mark inside the theme spacing step at both lateral edges and inside the safe area",
				run = function()
					local theme = Compose.cell(themes.neutralPackage() :: any)
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						local anchor = UI.Button "Anchor" { label = "Anchor" }
						return Host.Frame({
							anchor :: unknown,
							UI.Callout({
								anchor = anchor :: GuiObject,
								isPresented = Compose.cell(true),
								onRetire = function() end,
								content = function(): Instance
									return UI.Button({ label = "Tip" })
								end,
							}),
						})
					end, { theme = theme })
					local V = world.engine.types.Vector2
					world.root.AbsolutePosition = V.new(0, 0)
					world.root.AbsoluteSize = V.new(320, 400)
					local anchor, panel = find(world.root, "Anchor"), find(world.root, "CalloutPanel")
					local function measure(x: number)
						anchor.AbsolutePosition = V.new(x, 20)
						anchor.AbsoluteSize = V.new(20, 44)
						panel.AbsoluteSize = V.new(panel.Size.X.Offset, 100)
						world.settle()
					end
					local function edges(): (number, number)
						local left = math.round(
							world.root.AbsolutePosition.X
								+ panel.Position.X.Offset
								- panel.AnchorPoint.X * panel.AbsoluteSize.X
						)
						return left, left + panel.Size.X.Offset
					end
					for _, step in { 8, 24 } do
						theme:set(withSpacing(step))
						measure(300)
						local _, right = edges()
						Verify.expect(`step {step} right edge {right}`):toBe(`step {step} right edge {320 - step}`)
						measure(0)
						local left = edges()
						Verify.expect(`step {step} left edge {left}`):toBe(`step {step} left edge {step}`)
					end
					world.root.AbsolutePosition = V.new(44, 0)
					world.root.AbsoluteSize = V.new(276, 400)
					measure(44)
					local left = edges()
					Verify.expect(left):toBe(44 + 24)
					measure(300)
					local _, right = edges()
					Verify.expect(right):toBe(320 - 24)
					Verify.expect((find(world.root, "CalloutPanel"))):toBe(panel)
					world.stop()
				end,
			}
		)
	end)
end
