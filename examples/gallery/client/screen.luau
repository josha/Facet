--!strict

type ExampleContext = typeof(require("@repo/examples/types").Context)
type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type ThemePackage = typeof(require("@repo/tools/typecheck/aliases").ThemePackage)
type StringPickerOption = typeof(require("@repo/tools/typecheck/aliases").StringPickerOption)
type Tab = typeof(require("@repo/tools/typecheck/aliases").Tab)
type StringPickerSpec = typeof(require("@repo/tools/typecheck/aliases").StringPickerSpec)
type GridProps = typeof(require("@repo/tools/typecheck/aliases").GridProps)
type StackProps = typeof(require("@repo/tools/typecheck/aliases").StackProps)
type Device = typeof(require("@repo/examples/types").Device)
type Size = typeof(require("@repo/examples/types").Size)
type ViewingDistance = typeof(require("@repo/examples/types").ViewingDistance)
type MotionLevel = typeof(require("@repo/examples/types").MotionLevel)
type CategoryLayout = typeof(require("@repo/examples/types").CategoryLayout)
type ThemeModule = typeof(require("@repo/examples/types").ThemeModule)
type Themes = typeof(require("@repo/tools/typecheck/aliases").FacetModule.themes)
type ReadOnlyValue<T> = { peek: (ReadOnlyValue<T>) -> T }
type Value<T> =
	ReadOnlyValue<T>
	& { set: (Value<T>, T) -> (), update: (Value<T>, (T) -> T) -> (), dispose: (Value<T>) -> () }
type Use = <T>(ReadOnlyValue<T>) -> T
local catalogue = require("./demo_picker")
local screen = {}
local DEVICES: { [string]: Device } = {
	phone = { width = 389, height = 762, displaySize = "Small", input = "Touch", rotates = true },
	tablet = { width = 768, height = 1024, displaySize = "Small", input = "Touch", rotates = true },
	tv = { width = 1920, height = 1080, displaySize = "Large", input = "Gamepad" },
	desktop = { displaySize = "Medium", input = "KeyboardAndMouse" },
}
screen.list = catalogue.list
screen.next = catalogue.next
screen.boot = catalogue.boot

function screen.configure(ctx: ExampleContext)
	local Compose = ctx.Compose
	ctx.overlayParent = ctx.Host.Frame "PreviewOverlays" {
		BackgroundTransparency = 1,
		Size = ctx.types.UDim2.fromOffset(0, 0),
		ZIndex = 100,
	}
	local themeName: Value<string> = ctx.themeName or Compose.cell("Neutral")
	ctx.themeName = themeName
	local automaticDistance: ViewingDistance? = "automatic"
	local viewingDistance: Value<ViewingDistance?> = Compose.cell(automaticDistance)
	ctx.viewingDistance = viewingDistance
	ctx.categoryPlacement = Compose.cell("automatic")
	local noLayout: CategoryLayout? = nil
	local categoryLayout: Value<CategoryLayout?> = Compose.cell(noLayout)
	ctx.categoryLayout = categoryLayout
	local devicePreview, orientationPreview = Compose.cell("automatic"), Compose.cell("portrait")
	ctx.devicePreview, ctx.orientationPreview = devicePreview, orientationPreview
	local device = Compose.formula(function(use: Use): Device?
		local chosen = DEVICES[use(devicePreview)]
		if chosen and chosen.rotates and use(orientationPreview) == "landscape" then
			return {
				width = chosen.height,
				height = chosen.width,
				displaySize = chosen.displaySize,
				input = chosen.input,
			}
		end
		return chosen
	end)
	ctx.device = device
	local display = ctx.viewport
	local gui = ctx.guiService
	local inset = Compose.cell(0)
	if gui then
		local function measure()
			pcall(function()
				inset:set(gui:GetGuiInset().Y)
			end)
		end
		measure()
		local connection = gui:GetPropertyChangedSignal("TopbarInset"):Connect(measure)
		Compose.cleanup(function()
			connection:Disconnect()
		end)
	end
	ctx.topInset = inset
	local noMetric: ReadOnlyValue<number>? = nil
	local metricScale: Value<ReadOnlyValue<number>?> = Compose.cell(noMetric)
	ctx.metricScale = metricScale
	local previewScale = Compose.formula(function(use: Use): number
		local chosen = use(device)
		if chosen and chosen.width and chosen.height and display then
			local size = use(display)
			return math.min(1, size.width / chosen.width, (size.height - use(inset)) / chosen.height)
		end
		return 1
	end)
	ctx.previewScale = previewScale
	if display then
		local previewViewport = Compose.formula(function(use: Use): Size
			local chosen = use(device)
			return if chosen
					and chosen.width
					and chosen.height
				then { width = chosen.width, height = chosen.height }
				else use(display)
		end)
		ctx.previewViewport = previewViewport
		ctx.sceneViewport = Compose.formula(function(use: Use): Size
			local size = use(previewViewport)
			local metric = use(metricScale)
			local chosen = use(device)
			local framed = chosen and chosen.width
			local scale = (if framed then 1 else use(previewScale)) * (if metric then use(metric) else 1)
			return { width = size.width / scale, height = size.height / scale }
		end)
	end
	local inputPreview, textPreview = Compose.cell("automatic"), Compose.cell("automatic")
	ctx.inputPreview, ctx.textPreview = inputPreview, textPreview
	local function previewInput(use: Use): string?
		local preview = use(inputPreview)
		if preview ~= "automatic" then
			return preview
		end
		local chosen = use(device)
		return chosen and chosen.input
	end
	local function forced(input: string): (Use) -> boolean?
		return function(use: Use): boolean?
			local preview = previewInput(use)
			return if preview == nil then nil else preview == input
		end
	end
	ctx.environment = {
		viewingDistance = viewingDistance,
		preferredInput = previewInput,
		touchEnabled = forced("Touch"),
		gamepadEnabled = forced("Gamepad"),
		mouseEnabled = forced("KeyboardAndMouse"),
		keyboardEnabled = forced("KeyboardAndMouse"),
		preferredTextSize = function(use: Use): string?
			local preview = use(textPreview)
			return if preview == "automatic" then nil else preview
		end,
		displaySize = function(use: Use): string?
			local chosen = use(device)
			return chosen and chosen.displaySize
		end,
		viewportSize = function(use: Use): Vector2?
			local chosen = use(device)
			return if chosen
					and chosen.width
					and chosen.height
				then ctx.types.Vector2.new(chosen.width, chosen.height)
				else nil
		end,
	}
	ctx.hoverPreview = forced("KeyboardAndMouse")
	local followDevice: MotionLevel? = nil
	local motionPreference: Value<MotionLevel?> = Compose.cell(followDevice)
	ctx.motionPreference = motionPreference
	local nativeReduced = Compose.cell(gui and gui.ReducedMotionEnabled == true or false)
	if gui then
		local connection = gui:GetPropertyChangedSignal("ReducedMotionEnabled"):Connect(function()
			nativeReduced:set(gui.ReducedMotionEnabled == true)
		end)
		Compose.cleanup(function()
			connection:Disconnect()
		end)
	end
	local function levelOf(use: Use): MotionLevel
		local chosen = use(motionPreference)
		if chosen == "none" then
			return "none"
		elseif chosen == "limited" or use(nativeReduced) then
			return "limited"
		end
		return "normal"
	end
	local initialLevel: MotionLevel = "normal"
	local motionLevel: Value<MotionLevel> = Compose.cell(initialLevel)
	Compose.watch(function(use: Use)
		motionLevel:set(levelOf(use))
	end)
	ctx.motionLevel = motionLevel
	ctx.reducedMotion = Compose.formula(function(use: Use): boolean
		return use(motionLevel) ~= "normal"
	end)
	local motionMode = Compose.cell("device")
	ctx.motionMode = motionMode
	Compose.watch(function(use: Use)
		motionMode:set(use(motionPreference) or "device")
	end)
end

function screen.preview(ctx: ExampleContext, content: Instance, bounds: GuiObject): Frame
	local overlayParent = assert(ctx.overlayParent)
	local root = ctx.Host.Frame "PreviewRoot" {
		Size = ctx.types.UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		content,
		overlayParent,
	}
	local function measure()
		local size = bounds.AbsoluteSize
		local at = bounds.AbsolutePosition - root.AbsolutePosition
		overlayParent.Size = ctx.types.UDim2.fromOffset(size.X, size.Y)
		overlayParent.Position = ctx.types.UDim2.fromOffset(at.X, at.Y)
	end
	local watched: { { node: GuiObject, property: string } } = {
		{ node = bounds, property = "AbsoluteSize" },
		{ node = bounds, property = "AbsolutePosition" },
		{ node = root, property = "AbsolutePosition" },
	}
	for _, entry in watched do
		local connection = entry.node:GetPropertyChangedSignal(entry.property):Connect(measure)
		ctx.Compose.cleanup(function()
			connection:Disconnect()
		end)
	end
	measure()
	return root
end

function screen.themePackages(
	themes: Themes,
	modules: { Instance },
	load: (ModuleScript) -> ThemeModule
): { [string]: ThemePackage }
	local packages: { [string]: ThemePackage } = {}
	for _, module in modules do
		if module:IsA("ModuleScript") then
			local ok, definition = pcall(load, module)
			if
				ok
				and type(definition) == "table"
				and not definition.testOnly
				and type(definition.build) == "function"
			then
				local built, package = pcall(definition.build, themes)
				if built and package then
					packages[module.Name] = package
				end
			end
		end
	end
	return packages
end

function screen.setTheme(ctx: ExampleContext, name: string): boolean
	local package = assert(ctx.packages)[name]
	if not package then
		return false
	end
	local themeName, themeMode, theme = assert(ctx.themeName), assert(ctx.themeMode), assert(ctx.theme)
	ctx.runtime:batch(function()
		themeName:set(name)
		themeMode:set(package.style.defaultTheme)
		theme:set(package)
	end)
	return true
end

function screen.resetAll(ctx: ExampleContext)
	local devicePreview, orientationPreview = assert(ctx.devicePreview), assert(ctx.orientationPreview)
	local inputPreview, textPreview = assert(ctx.inputPreview), assert(ctx.textPreview)
	local viewingDistance = assert(ctx.viewingDistance)
	ctx.runtime:batch(function()
		devicePreview:set("automatic")
		orientationPreview:set("portrait")
		inputPreview:set("automatic")
		textPreview:set("automatic")
		viewingDistance:set("automatic")
	end)
end

export type Report = {
	ok: boolean,
	current: string,
	mounted: string?,
	error: string?,
	theme: string,
	palette: string,
	demo: unknown,
	panel: string?,
}

function screen.dispatch(ctx: ExampleContext, command: string, argument: unknown): Report
	local ok = false
	local demos = ctx.demos or catalogue.list()
	local selection = assert(ctx.selection)
	local word = if type(argument) == "string" then argument else nil
	if command == "show" then
		for _, demo in demos do
			if demo.id == argument then
				selection:set(demo.id)
				ok = true
				break
			end
		end
	elseif command == "next" or command == "showNext" then
		local index = 1
		for position, demo in demos do
			if demo.id == selection:peek() then
				index = position
				break
			end
		end
		local step = if type(argument) == "number" then argument else 1
		selection:set(demos[(index - 1 + step) % #demos + 1].id)
		ok = true
	elseif command == "theme" then
		ok = screen.setTheme(ctx, word or "")
	elseif command == "device" then
		ok = word == "automatic" or word ~= nil and DEVICES[word] ~= nil
		if ok and word then
			assert(ctx.devicePreview):set(word)
		end
	elseif command == "input" then
		ok = word == "automatic" or word == "KeyboardAndMouse" or word == "Touch" or word == "Gamepad"
		if ok and word then
			assert(ctx.inputPreview):set(word)
		end
	elseif command == "orientation" then
		ok = word == "portrait" or word == "landscape"
		if ok and word then
			assert(ctx.orientationPreview):set(word)
		end
	elseif command == "panel" and ctx.requestPanel then
		ok = argument == nil or word == "demos" or word == "settings"
		if ok then
			ctx.requestPanel(word)
		end
	elseif command == "tab" and ctx.currentSelect then
		ok = ctx.currentSelect(argument) == true
	elseif command == "report" then
		ok = true
	end
	local panelOpen, panelSection = ctx.panelOpen, ctx.panelSection
	return {
		ok = ok,
		current = selection:peek(),
		mounted = assert(ctx.active):peek(),
		error = if ok then assert(ctx.errorMessage):peek() else "Unknown gallery command or choice",
		theme = assert(ctx.themeName):peek(),
		palette = assert(ctx.themeMode):peek(),
		demo = if command == "report" and ctx.currentReport then ctx.currentReport() else nil,
		panel = if panelOpen and panelSection and panelOpen:peek() then panelSection:peek() else nil,
	}
end

local function motionChoice(value: string): MotionLevel?
	if value == "normal" or value == "limited" or value == "none" then
		return value
	end
	return nil
end

function screen.build(ctx: ExampleContext)
	local Host, UI, Compose = ctx.Host, ctx.UI, ctx.Compose
	if not ctx.reducedMotion then
		screen.configure(ctx)
	end
	local UDim, UDim2, Enum = ctx.types.UDim, ctx.types.UDim2, ctx.types.Enum
	local selected = assert(ctx.selection)
	local environment = UI.environment()
	assert(ctx.metricScale):set(environment.metricScale)
	local sceneVisible = Compose.cell(false)
	ctx.sceneVisible = sceneVisible
	local themeName: Value<string> = ctx.themeName or Compose.cell("Neutral")
	ctx.themeName = themeName
	local nothing: string? = nil
	local active: Value<string?> = Compose.cell(nothing)
	ctx.active = active
	local errorMessage: Value<string?> = Compose.cell(nothing)
	ctx.errorMessage = errorMessage
	local themeMode, theme, packages = assert(ctx.themeMode), assert(ctx.theme), assert(ctx.packages)
	local devicePreview, orientationPreview = assert(ctx.devicePreview), assert(ctx.orientationPreview)
	local inputPreview, motionMode = assert(ctx.inputPreview), assert(ctx.motionMode)
	local motionPreference, previewScale = assert(ctx.motionPreference), assert(ctx.previewScale)
	local device, categoryLayout = assert(ctx.device), assert(ctx.categoryLayout)
	local load = assert(ctx.load)
	local branches: { [string]: () -> Instance } = {}
	for _, demo in (ctx.demos or catalogue.list()) do
		branches[demo.id] = function()
			ctx.currentReport = nil
			ctx.currentSelect = nil
			local ok, result = pcall(function()
				local definition = load(demo.kind, demo.module)
				local pageContext = table.clone(ctx)
				pageContext.viewport = ctx.previewViewport
				pageContext.pageVisible = Compose.formula(function(use: Use)
					return use(selected) == demo.id
				end)
				local built = definition.build(pageContext)
				if type(built) == "function" then
					return built()
				end
				ctx.currentReport = built.report
				ctx.currentSelect = built.select
				if built.dispose then
					Compose.cleanup(built.dispose)
				end
				return built.screen()
			end)
			if ok then
				active:set(demo.id)
				errorMessage:set(nil)
				return result
			end
			active:set(nil)
			ctx.currentReport = nil
			ctx.currentSelect = nil
			errorMessage:set(tostring(result))
			warn("[Facet Gallery] " .. demo.id .. ": " .. tostring(result))
			return UI.Text "DemoFailure" {
				Size = UDim2.fromScale(1, 1),
				AutomaticSize = Enum.AutomaticSize.None,
				BackgroundTransparency = 1,
				text = demo.title .. " could not load\n" .. tostring(result),
				TextWrapped = true,
			}
		end
	end
	local tabs: { Tab } = {}
	for _, demo in (ctx.demos or catalogue.list()) do
		table.insert(tabs, { id = demo.id, label = demo.title, content = branches[demo.id] })
	end
	local themes: { { value: string, label: string } } = {}
	for name, package in packages do
		table.insert(themes, { value = name, label = package.identity and package.identity.displayName or name })
	end
	table.sort(themes, function(a: { value: string, label: string }, b: { value: string, label: string }): boolean
		return if a.value == "Neutral" then true elseif b.value == "Neutral" then false else a.label < b.label
	end)
	local measuredToolbar = Compose.cell(56)
	local toolbarHeight = function(use: Use)
		return use(measuredToolbar)
	end
	local COPY: { [string]: string } = {
		preview = "Preview as",
		automatic = "Automatic",
		desktop = "Desktop",
		phone = "Phone",
		tablet = "Tablet",
		tv = "TV / 10-foot",
		orientation = "Orientation",
		portrait = "Portrait",
		landscape = "Landscape",
		input = "Input",
		KeyboardAndMouse = "Mouse & keyboard",
		Touch = "Touch",
		Gamepad = "Gamepad",
		resetAll = "Reset everything to Automatic",
		previewNote = "Phone and tablet layouts fit within this window. Automatic input follows the preview device, or your current device in Automatic preview.",
		motionNote = "Limited fades instead of moving. None snaps. The device's Reduce Motion still applies on top of the game's choice. Informational motion keeps running, in 250 ms steps.",
	}
	local function options(values: { string }): { StringPickerOption }
		local list: { StringPickerOption } = {}
		for _, value in values do
			table.insert(list, { value = value, label = COPY[value] })
		end
		return list
	end
	local function caption(name: string, text)
		return UI.Text(name)({
			text = text,
			textRole = "caption",
			role = "secondary",
		})
	end
	local function note(name: string, text)
		return UI.Text(name)({
			text = text,
			textRole = "caption",
			role = "secondary",
			TextWrapped = true,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
		})
	end

	local function displayPickers(style: "automatic" | "menu"): Frame
		local preview: StringPickerSpec = {
			Name = "Preview",
			label = COPY.preview,
			style = style,
			selected = devicePreview,
			options = options({ "automatic", "desktop", "phone", "tablet", "tv" }),
		}
		local orientation: StringPickerSpec = {
			Name = "Orientation",
			label = COPY.orientation,
			style = style,
			selected = orientationPreview,
			options = options({ "portrait", "landscape" }),
			enabled = function(use: Use): boolean
				local chosen = DEVICES[use(devicePreview)]
				return chosen ~= nil and chosen.rotates == true
			end,
		}
		local input: StringPickerSpec = {
			Name = "Input",
			label = COPY.input,
			style = style,
			selected = inputPreview,
			options = options({ "automatic", "KeyboardAndMouse", "Touch", "Gamepad" }),
		}
		return UI.VStack "Pickers" {
			gap = "s",
			width = "fill",
			UI.Picker(preview),
			UI.Picker(orientation),
			UI.Picker(input),
		}
	end
	local function settingsContent()
		local packagesGrid: GridProps = { Name = "Packages", columns = 2, gap = "xs" }
		for index, entry in themes do
			packagesGrid[#packagesGrid + 1] = UI.Button("P_" .. entry.value)({
				LayoutOrder = index,
				label = entry.label,
				selected = function(use: Use)
					return use(themeName) == entry.value
				end,
				onActivate = function()
					if themeName:peek() ~= entry.value then
						screen.setTheme(ctx, entry.value)
					end
				end,
			})
		end
		local motionOptions: { StringPickerOption } = {
			{ value = "device", label = "Device" },
			{ value = "normal", label = "Normal" },
			{ value = "limited", label = "Limited" },
			{ value = "none", label = "None" },
		}
		local motionSpec: StringPickerSpec = {
			Name = "MotionMode",
			label = "Motion",
			style = "segmented",
			selected = motionMode,
			options = motionOptions,
			onChange = function(value: string)
				motionPreference:set(motionChoice(value))
			end,
		}
		local build = ctx.buildStamp
		return UI.VStack "Settings" {
			gap = "m",
			width = "fill",
			UI.VStack "Display" {
				gap = "s",
				width = "fill",
				Compose.show(UI.environment().isTenFoot, function()
					return displayPickers("automatic")
				end, function()
					return displayPickers("menu")
				end),
				UI.Button "ResetAll" {
					label = COPY.resetAll,
					onActivate = function()
						screen.resetAll(ctx)
					end,
				},
				note("Note", COPY.previewNote),
			},
			UI.VStack "Motion" {
				gap = "xs",
				width = "fill",
				UI.Picker(motionSpec),
				note("MotionNote", COPY.motionNote),
			},
			if type(build) == "string" and build ~= "" then caption("Build", `build {build}`) else nil,
			UI.VStack "Choose" {
				gap = "xs",
				width = "fill",
				caption("Title", "Theme"),
				UI.Grid(packagesGrid),
				UI.HStack "Mode" {
					gap = "xs",
					Compose.keyed({
						from = function(use: Use): { string }
							local names: { string } = {}
							local palettes = use(theme).style.themes
							local available: { typeof(palettes[1]) } = if #palettes > 1 then palettes else {}
							for _, palette in available do
								table.insert(names, palette.name)
							end
							return names
						end,
						key = function(name: string)
							return name
						end,
						render = function(_, position, name: string): GuiObject
							return UI.Button(name)({
								label = name,
								LayoutOrder = position,
								selected = function(use: Use)
									return use(themeMode) == name
								end,
								onActivate = function()
									themeMode:set(name)
								end,
							})
						end,
					}),
				},
			},
		}
	end
	local panelOpen = Compose.cell(false)
	local section = Compose.cell("demos")
	ctx.panelOpen, ctx.panelSection = panelOpen, section
	local titles: { [string]: string } = {}
	for _, demo in (ctx.demos or catalogue.list()) do
		titles[demo.id] = demo.title
	end
	local environmentFacts = UI.environment()
	local gamepad = function(use: Use)
		return use(environmentFacts.effectiveInput) == "Gamepad"
	end
	local function closePanel()
		panelOpen:set(false)
	end
	local function request(want: string?)
		local open = panelOpen:peek()
		if want == nil then
			if open then
				closePanel()
			else
				panelOpen:set(true)
			end
		elseif open and section:peek() == want then
			closePanel()
		else
			section:set(want)
			panelOpen:set(true)
		end
	end
	ctx.requestPanel = request
	if ctx.inputTarget then
		local function action(name: string, key: Enum.KeyCode, want: string?)
			return Host.InputAction(name)({
				Type = Enum.InputActionType.Bool,
				Pressed = function()
					request(want)
				end,
				Host.InputBinding({ KeyCode = key }),
			})
		end
		Host.InputContext "ShowcaseChromeToggle" {
			Parent = ctx.inputTarget,
			Priority = ctx.Facet.inputPriority.aboveFacet,
			Sink = true,
			action("Activate", Enum.KeyCode.Backquote, nil),
		}
		Host.InputContext "ShowcaseChromeGamepad" {
			Parent = ctx.inputTarget,
			Priority = ctx.Facet.inputPriority.belowControls,
			Sink = true,
			action("Activate", Enum.KeyCode.ButtonL1, nil),
		}
	end

	local function demoList()
		local demoList: StackProps = { Name = "DemoList", gap = "xs", align = "start", width = "fill" }
		local demos = ctx.demos or catalogue.list()
		for index, tab in tabs do
			demoList[#demoList + 1] = UI.Button("Demo-" .. tab.id)({
				LayoutOrder = index,
				row = { title = tab.label, description = demos[index].blurb },
				textSize = "strong",
				appearance = function(use: Use)
					return if use(selected) == tab.id then "standard" else "utility"
				end,
				trailingIcon = function(use: Use)
					return if use(selected) == tab.id then "checkmark" else "chevron.trailing"
				end,
				selected = function(use: Use)
					return use(selected) == tab.id
				end,
				onActivate = function()
					selected:set(tab.id)
					closePanel()
				end,
			})
		end
		return UI.VStack(demoList)
	end
	local sectionOptions: { StringPickerOption } = {
		{ value = "demos", label = "Demos" },
		{ value = "settings", label = "Settings" },
	}
	local sectionSpec: StringPickerSpec = {
		Name = "Section",
		style = "segmented",
		selected = section,
		options = sectionOptions,
	}
	local function panel()
		return UI.VStack "ShowcasePanel" {
			gap = "s",
			width = "fill",
			UI.Picker(sectionSpec),
			Compose.show(function(use: Use)
				return use(section) == "demos"
			end, demoList, settingsContent),
		}
	end
	local function hint(name: string, text)
		return UI.Text(name)({
			text = text,
			textRole = "caption",
			role = "secondary",
			Visible = gamepad,
		})
	end
	local row = Host.Frame "Row" {
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1,
		Host.UIListLayout({
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Top,
		}),
		hint("MenuHint", "LB"),
		UI.CollapsibleView "Showcase" {
			label = function(use: Use)
				return titles[use(selected)] or "Demos"
			end,
			expanded = panelOpen,
			content = panel,
		},
		Compose.show(function(use: Use)
			local layout = use(categoryLayout)
			return layout ~= nil and use(layout.available)
		end, function()
			return UI.Button "ToggleSidebar" {
				label = function(use: Use)
					local layout = use(categoryLayout)
					return if layout and use(layout.placement) == "sidebar" then "Use top tabs" else "Use sidebar"
				end,
				onActivate = function()
					local layout = categoryLayout:peek()
					if layout then
						layout.toggle()
					end
				end,
			}
		end),
	}
	local toolbar = Host.Frame "Toolbar" {
		ZIndex = 3,
		Size = function(use: Use)
			return UDim2.new(1, 0, 0, toolbarHeight(use))
		end,
		BackgroundTransparency = 1,
		Host.UIPadding({
			PaddingLeft = UDim.new(0, 16),
			PaddingRight = UDim.new(0, 12),
			PaddingTop = UDim.new(0, 8),
			PaddingBottom = UDim.new(0, 4),
		}),
		Host.Frame "Column" {
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundTransparency = 1,
			Host.UIListLayout({ Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
			row,
		},
	}
	local rowSize = row:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local scale = previewScale:peek()
		measuredToolbar:set(math.max(56, math.ceil(row.AbsoluteSize.Y / (if scale > 0 then scale else 1)) + 12))
	end)
	Compose.cleanup(function()
		rowSize:Disconnect()
	end)
	local root = Host.Frame "Gallery" {
		Size = function(use: Use)
			local chosen = use(device)
			if chosen and chosen.width and chosen.height then
				return UDim2.fromOffset(chosen.width, chosen.height)
			end
			local inverse = 1 / use(previewScale)
			return UDim2.fromScale(inverse, inverse)
		end,
		Host.UIScale "ViewingDistance" { Scale = previewScale },
		Host.UIPadding "Overscan" {
			PaddingTop = function(use: Use)
				return UDim.new(0, use(environment.overscanInsets).top)
			end,
			PaddingBottom = function(use: Use)
				return UDim.new(0, use(environment.overscanInsets).bottom)
			end,
			PaddingLeft = function(use: Use)
				return UDim.new(0, use(environment.overscanInsets).left)
			end,
			PaddingRight = function(use: Use)
				return UDim.new(0, use(environment.overscanInsets).right)
			end,
		},
		BackgroundTransparency = function(use: Use)
			return if use(sceneVisible) then 1 else 0
		end,

		toolbar,
		UI.TabView "Demos" {
			selection = selected,
			tabs = tabs,
			retention = "top",
			transition = false,
			placement = "none",
			Position = function(use: Use)
				return UDim2.fromOffset(0, toolbarHeight(use))
			end,
			Size = function(use: Use)
				return UDim2.new(1, 0, 1, -toolbarHeight(use))
			end,
		},
	}
	root:AddTag("facet-surface")
	Compose.watch(function(use: Use)
		local chosen = use(device)
		if chosen and chosen.width then
			root:AddTag("facet-floating")
		else
			root:RemoveTag("facet-floating")
		end
	end)
	return screen.preview(ctx, root, root)
end
return screen
