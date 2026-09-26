--!strict
local catalogue = require("./demo_picker")
local screen = {}
local DEVICES = {
	phone = { width = 389, height = 762, displaySize = "Small", input = "Touch", rotates = true },
	tablet = { width = 768, height = 1024, displaySize = "Small", input = "Touch", rotates = true },
	tv = { width = 1920, height = 1080, displaySize = "Large", input = "Gamepad" },
	desktop = { displaySize = "Medium", input = "KeyboardAndMouse" },
}
screen.list = catalogue.list
screen.next = catalogue.next
screen.boot = catalogue.boot

function screen.configure(ctx)
	local Compose = ctx.Compose
	ctx.themeName = ctx.themeName or Compose.cell("Neutral")
	ctx.viewingDistance = Compose.cell("automatic")
	ctx.categoryPlacement = Compose.cell("automatic")
	ctx.categoryLayout = Compose.cell(nil)
	ctx.devicePreview = Compose.cell("automatic")
	ctx.orientationPreview = Compose.cell("portrait")
	ctx.device = Compose.formula(function(use)
		local device = DEVICES[use(ctx.devicePreview)]
		if device and device.rotates and use(ctx.orientationPreview) == "landscape" then
			return {
				width = device.height,
				height = device.width,
				displaySize = device.displaySize,
				input = device.input,
			}
		end
		return device
	end)
	local display = ctx.viewport
	local gui = ctx.guiService
	local inset = 0
	if gui then
		pcall(function()
			inset = gui:GetGuiInset().Y
		end)
	end
	ctx.metricScale = Compose.cell(nil)
	ctx.previewScale = Compose.formula(function(use)
		local device = use(ctx.device)
		if device and device.width and display then
			local size = use(display)
			return math.min(1, size.width / device.width, (size.height - inset) / device.height)
		end
		return 1
	end)
	if display then
		ctx.previewViewport = Compose.formula(function(use)
			local device = use(ctx.device)
			return if device and device.width then { width = device.width, height = device.height } else use(display)
		end)
		ctx.sceneViewport = Compose.formula(function(use)
			local size = use(ctx.previewViewport)
			local metric = use(ctx.metricScale)
			local framed = use(ctx.device) and use(ctx.device).width
			local scale = (if framed then 1 else use(ctx.previewScale)) * (if metric then use(metric) else 1)
			return { width = size.width / scale, height = size.height / scale }
		end)
	end
	ctx.inputPreview = Compose.cell("automatic")
	ctx.textPreview = Compose.cell("automatic")
	local function previewInput(use)
		local preview = use(ctx.inputPreview)
		if preview ~= "automatic" then
			return preview
		end
		local device = use(ctx.device)
		return device and device.input
	end
	local function forced(input: string)
		return function(use)
			local preview = previewInput(use)
			return if preview == nil then nil else preview == input
		end
	end
	ctx.environment = {
		viewingDistance = ctx.viewingDistance,
		preferredInput = previewInput,
		touchEnabled = forced("Touch"),
		gamepadEnabled = forced("Gamepad"),
		mouseEnabled = forced("KeyboardAndMouse"),
		keyboardEnabled = forced("KeyboardAndMouse"),
		preferredTextSize = function(use)
			local preview = use(ctx.textPreview)
			return if preview == "automatic" then nil else preview
		end,
		displaySize = function(use)
			local device = use(ctx.device)
			return device and device.displaySize
		end,
		viewportSize = function(use)
			local device = use(ctx.device)
			return device and device.width and ctx.types.Vector2.new(device.width, device.height)
		end,
	}
	ctx.hoverPreview = forced("KeyboardAndMouse")
	ctx.motionPreference = Compose.cell(nil)
	local nativeReduced = Compose.cell(gui and gui.ReducedMotionEnabled == true or false)
	if gui then
		local connection = gui:GetPropertyChangedSignal("ReducedMotionEnabled"):Connect(function()
			nativeReduced:set(gui.ReducedMotionEnabled == true)
		end)
		Compose.cleanup(function()
			connection:Disconnect()
		end)
	end
	ctx.reducedMotion = Compose.formula(function(use)
		return use(nativeReduced) or use(ctx.motionPreference) == true
	end)
	ctx.motionMode = Compose.cell("full")
	Compose.watch(function(use)
		ctx.motionMode:set(if use(ctx.reducedMotion) then "reduced" else "full")
	end)
end

function screen.themePackages(themes, modules, load)
	local packages = {}
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

function screen.setTheme(ctx, name)
	local package = ctx.packages[name]
	if not package then
		return false
	end
	ctx.runtime.reactor:batch(function()
		ctx.themeName:set(name)
		ctx.themeMode:set(package.style.defaultTheme)
		ctx.theme:set(package)
	end)
	return true
end

function screen.resetAll(ctx)
	ctx.runtime.reactor:batch(function()
		ctx.devicePreview:set("automatic")
		ctx.orientationPreview:set("portrait")
		ctx.inputPreview:set("automatic")
		ctx.textPreview:set("automatic")
		ctx.viewingDistance:set("automatic")
	end)
end

function screen.dispatch(ctx, command, argument)
	local ok = false
	local demos = ctx.demos or catalogue.list()
	if command == "show" then
		for _, demo in demos do
			if demo.id == argument then
				ctx.selection:set(argument)
				ok = true
				break
			end
		end
	elseif command == "next" or command == "showNext" then
		local index = 1
		for position, demo in demos do
			if demo.id == ctx.selection:peek() then
				index = position
				break
			end
		end
		ctx.selection:set(demos[(index - 1 + (argument or 1)) % #demos + 1].id)
		ok = true
	elseif command == "theme" then
		ok = screen.setTheme(ctx, argument)
	elseif command == "device" then
		ok = argument == "automatic" or DEVICES[argument] ~= nil
		if ok then
			ctx.devicePreview:set(argument)
		end
	elseif command == "input" then
		ok = argument == "automatic" or argument == "KeyboardAndMouse" or argument == "Touch" or argument == "Gamepad"
		if ok then
			ctx.inputPreview:set(argument)
		end
	elseif command == "orientation" then
		ok = argument == "portrait" or argument == "landscape"
		if ok then
			ctx.orientationPreview:set(argument)
		end
	elseif command == "panel" and ctx.requestPanel then
		ok = argument == nil or argument == "demos" or argument == "settings"
		if ok then
			ctx.requestPanel(argument)
		end
	elseif command == "report" then
		ok = true
	end
	return {
		ok = ok,
		current = ctx.selection:peek(),
		mounted = ctx.active:peek(),
		error = if ok then ctx.errorMessage:peek() else "Unknown gallery command or choice",
		theme = ctx.themeName:peek(),
		palette = ctx.themeMode:peek(),
		demo = if command == "report" and ctx.currentReport then ctx.currentReport() else nil,
		panel = if ctx.panelOpen and ctx.panelOpen:peek() then ctx.panelSection:peek() else nil,
	}
end

function screen.build(ctx: any)
	local Host, UI, Compose = ctx.Host, ctx.UI, ctx.Compose
	if not ctx.reducedMotion then
		screen.configure(ctx)
	end
	local UDim, UDim2, Enum = ctx.types.UDim, ctx.types.UDim2, ctx.types.Enum
	local selected = ctx.selection
	local environment = UI.environment()
	ctx.metricScale:set(environment.metricScale)
	ctx.sceneVisible = Compose.cell(false)
	local themeName = ctx.themeName or Compose.cell("Neutral")
	ctx.themeName = themeName
	local active = Compose.cell(nil)
	ctx.active = active
	local errorMessage = Compose.cell(nil)
	ctx.errorMessage = errorMessage
	local branches = {}
	for _, demo in (ctx.demos or catalogue.list()) do
		branches[demo.id] = function()
			ctx.currentReport = nil
			local ok, result = pcall(function()
				local definition = ctx.load(demo.kind, demo.module)
				local pageContext = table.clone(ctx)
				pageContext.viewport = ctx.previewViewport
				pageContext.pageVisible = Compose.formula(function(use)
					return use(selected) == demo.id
				end)
				local built = definition.build(pageContext)
				if type(built) == "function" then
					return built()
				end
				ctx.currentReport = built.report
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
			errorMessage:set(tostring(result))
			warn("[Facet Gallery] " .. demo.id .. ": " .. tostring(result))
			return Host.TextLabel "DemoFailure" {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = demo.title .. " could not load\n" .. tostring(result),
				TextWrapped = true,
			}
		end
	end
	local tabs = {}
	for _, demo in (ctx.demos or catalogue.list()) do
		table.insert(tabs, { id = demo.id, label = demo.title, content = branches[demo.id] })
	end
	local demoOptions = {}
	for _, tab in tabs do
		table.insert(demoOptions, { value = tab.id, label = tab.label })
	end
	local themes = {}
	for name, package in ctx.packages do
		table.insert(themes, { value = name, label = package.identity and package.identity.displayName or name })
	end
	table.sort(themes, function(a, b)
		return if a.value == "Neutral" then true elseif b.value == "Neutral" then false else a.label < b.label
	end)
	local measuredToolbar = Compose.cell(56)
	local toolbarHeight = function(use)
		return use(measuredToolbar)
	end
	local COPY = {
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
		motionNote = "Reduced removes decorative travel. Informational motion keeps running, in 250 ms steps.",
	}
	local function options(values)
		local list = {}
		for _, value in values do
			table.insert(list, { value = value, label = COPY[value] })
		end
		return list
	end
	local function caption(name, text)
		return UI.Text(name)({ text = text, textRole = "caption", role = "secondary" })
	end
	local function note(name, text)
		return UI.Text(name)({
			text = text,
			textRole = "caption",
			role = "secondary",
			TextWrapped = true,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
		})
	end
	local function settingsContent()
		local themeChips = {}
		for index, entry in themes do
			table.insert(
				themeChips,
				UI.Button("P_" .. entry.value)({
					LayoutOrder = index,
					label = entry.label,
					selected = function(use)
						return use(themeName) == entry.value
					end,
					onActivate = function()
						if themeName:peek() ~= entry.value then
							screen.setTheme(ctx, entry.value)
						end
					end,
				})
			)
		end
		local build = ctx.buildStamp
		return UI.VStack "Settings" {
			gap = "m",
			width = "fill",
			UI.VStack "Display" {
				gap = "s",
				width = "fill",
				UI.Picker "Preview" {
					label = COPY.preview,
					style = "menu",
					selected = ctx.devicePreview,
					options = options({ "automatic", "desktop", "phone", "tablet", "tv" }),
				},
				UI.Picker "Orientation" {
					label = COPY.orientation,
					style = "menu",
					selected = ctx.orientationPreview,
					options = options({ "portrait", "landscape" }),
					enabled = function(use)
						local device = DEVICES[use(ctx.devicePreview)]
						return device ~= nil and device.rotates == true
					end,
				},
				UI.Picker "Input" {
					label = COPY.input,
					style = "menu",
					selected = ctx.inputPreview,
					options = options({ "automatic", "KeyboardAndMouse", "Touch", "Gamepad" }),
				},
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
				UI.Picker "MotionMode" {
					label = "Motion",
					style = "segmented",
					selected = ctx.motionMode,
					options = { { value = "full", label = "Full" }, { value = "reduced", label = "Reduced" } },
					onChange = function(value)
						ctx.motionPreference:set(value == "reduced")
						ctx.motionMode:set(if ctx.reducedMotion:peek() then "reduced" else "full")
					end,
				},
				note("MotionNote", COPY.motionNote),
			},
			if type(build) == "string" and build ~= "" then caption("Build", `build {build}`) else nil,
			UI.VStack "Choose" {
				gap = "xs",
				width = "fill",
				caption("Title", "Theme"),
				UI.Grid "Packages" { columns = 2, gap = "xs", table.unpack(themeChips) },
				UI.HStack "Mode" {
					gap = "xs",
					Compose.keyed({
						from = Compose.formula(function(use)
							local names = {}
							local palettes = use(ctx.theme).style.themes
							for _, palette in if #palettes > 1 then palettes else {} do
								table.insert(names, palette.name)
							end
							return names
						end),
						key = function(name)
							return name
						end,
						render = function(_, position, name)
							return UI.Button(name)({
								label = name,
								LayoutOrder = position,
								selected = function(use)
									return use(ctx.themeMode) == name
								end,
								onActivate = function()
									ctx.themeMode:set(name)
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
	local titles = {}
	for _, tab in tabs do
		titles[tab.id] = tab.label
	end
	local environmentFacts = UI.environment()
	local gamepad = function(use)
		return use(environmentFacts.effectiveInput) == "Gamepad"
	end
	local function request(want)
		local open = panelOpen:peek()
		if want == nil then
			panelOpen:set(not open)
		elseif open and section:peek() == want then
			panelOpen:set(false)
		else
			section:set(want)
			panelOpen:set(true)
		end
	end
	ctx.requestPanel = request
	if ctx.inputTarget then
		local function action(name, key, want)
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
			Priority = 13500,
			Sink = true,
			action("Activate", Enum.KeyCode.Backquote, nil),
			action("ActivateDemos", Enum.KeyCode.ButtonL1, "demos"),
			action("ActivateSettings", Enum.KeyCode.ButtonR1, "settings"),
		}
		Host.InputContext "ShowcasePanelCancel" {
			Parent = ctx.inputTarget,
			Priority = 2000,
			Sink = true,
			Enabled = panelOpen,
			Host.InputAction "Cancel" {
				Type = Enum.InputActionType.Bool,
				Pressed = function()
					panelOpen:set(false)
				end,
				Host.InputBinding({ KeyCode = Enum.KeyCode.ButtonB }),
				Host.InputBinding({ KeyCode = Enum.KeyCode.Escape }),
			},
		}
	end
	-- Settings holds wrapping notes, so the card takes a width there; Demos hugs its rows.
	local function settingsWidth(use)
		if use(section) ~= "settings" then
			return 0
		end
		local size = if ctx.previewViewport then use(ctx.previewViewport) else { width = 1e4, height = 1e4 }
		return math.min(460 * use(environment.metricScale), size.width - 28)
	end
	local function panel()
		local demoButtons = {}
		for index, tab in tabs do
			table.insert(
				demoButtons,
				UI.Button("Demo-" .. tab.id)({
					LayoutOrder = index,
					label = tab.label,
					selected = function(use)
						return use(selected) == tab.id
					end,
					onActivate = function()
						selected:set(tab.id)
						panelOpen:set(false)
					end,
				})
			)
		end
		-- A hugging ScrollingFrame outgrows a UISizeConstraint on Y, so the card
		-- takes its content height up to the room under the bar and scrolls past it.
		local content = Compose.cell(0)
		local card = UI.ScrollView "ShowcasePanel" {
			gap = "s",
			padding = "s",
			width = "hug",
			height = function(use)
				local size = if ctx.previewViewport then use(ctx.previewViewport) else { width = 1e4, height = 1e4 }
				return math.min(use(content), math.max(120, size.height - toolbarHeight(use) - 16))
			end,
			SelectionGroup = true,
			SelectionBehaviorLeft = Enum.SelectionBehavior.Stop,
			SelectionBehaviorRight = Enum.SelectionBehavior.Stop,
			SelectionBehaviorDown = Enum.SelectionBehavior.Stop,
			Host.UISizeConstraint {
				MinSize = function(use)
					return ctx.types.Vector2.new(settingsWidth(use), 0)
				end,
				MaxSize = function(use)
					local size = if ctx.previewViewport then use(ctx.previewViewport) else { width = 1e4, height = 1e4 }
					local wide = settingsWidth(use)
					return ctx.types.Vector2.new(if wide > 0 then wide else size.width - 28, math.huge)
				end,
			},
			caption("SectionTitle", "Section"),
			UI.Picker "Section" {
				style = "segmented",
				selected = section,
				options = { { value = "demos", label = "Demos" }, { value = "settings", label = "Settings" } },
			},
			Compose.show(function(use)
				return use(section) == "demos"
			end, function()
				return UI.VStack "DemoList" { gap = "xs", align = "center", width = "fill", table.unpack(demoButtons) }
			end, settingsContent),
		}
		card:AddTag("facet-panel")
		local list = card:FindFirstChildWhichIsA("UIListLayout")
		local inset = card:FindFirstChildWhichIsA("UIPadding")
		local function measure()
			local scale = ctx.previewScale:peek()
			local pad = if inset then inset.PaddingTop.Offset + inset.PaddingBottom.Offset else 0
			content:set(math.ceil(list.AbsoluteContentSize.Y / (if scale > 0 then scale else 1)) + pad)
		end
		local resized = list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(measure)
		Compose.cleanup(function()
			resized:Disconnect()
		end)
		measure()
		UI.focusSection(card, { focusOnAppear = true, returnFocus = true })
		return card
	end
	local function hint(name, text)
		return UI.Text(name)({ text = text, textRole = "caption", role = "secondary", Visible = gamepad })
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
		hint("DemosHint", "LB"),
		UI.Button "Showcase" {
			label = function(use)
				return if use(panelOpen) then "Close" else titles[use(selected)] or "Demos"
			end,
			onActivate = function()
				request(nil)
			end,
		},
		hint("SettingsHint", "RB"),
		Compose.show(function(use)
			local layout = use(ctx.categoryLayout)
			return layout ~= nil and use(layout.available)
		end, function()
			return UI.Button "ToggleSidebar" {
				label = function(use)
					local layout = use(ctx.categoryLayout)
					return if layout and use(layout.placement) == "sidebar" then "Use top tabs" else "Use sidebar"
				end,
				onActivate = function()
					local layout = ctx.categoryLayout:peek()
					if layout then
						layout.toggle()
					end
				end,
			}
		end),
	}
	local toolbar = Host.Frame "Toolbar" {
		ZIndex = 3,
		Size = function(use)
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
			Compose.show(panelOpen, panel),
		},
	}
	local rowSize = row:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local scale = ctx.previewScale:peek()
		measuredToolbar:set(math.max(56, math.ceil(row.AbsoluteSize.Y / (if scale > 0 then scale else 1)) + 12))
	end)
	Compose.cleanup(function()
		rowSize:Disconnect()
	end)
	local root = Host.Frame "Gallery" {
		Size = function(use)
			local device = use(ctx.device)
			if device and device.width then
				return UDim2.fromOffset(device.width, device.height)
			end
			local inverse = 1 / use(ctx.previewScale)
			return UDim2.fromScale(inverse, inverse)
		end,
		Host.UIScale "ViewingDistance" { Scale = ctx.previewScale },
		Host.UIPadding "Overscan" {
			PaddingTop = function(use)
				return UDim.new(0, use(environment.overscanInsets).top)
			end,
			PaddingBottom = function(use)
				return UDim.new(0, use(environment.overscanInsets).bottom)
			end,
			PaddingLeft = function(use)
				return UDim.new(0, use(environment.overscanInsets).left)
			end,
			PaddingRight = function(use)
				return UDim.new(0, use(environment.overscanInsets).right)
			end,
		},
		BackgroundTransparency = function(use)
			return if use(ctx.sceneVisible) then 1 else 0
		end,

		toolbar,
		Compose.show(panelOpen, function()
			return Host.TextButton "ShowcaseDismiss" {
				ZIndex = 2,
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = "",
				AutoButtonColor = false,
				Selectable = false,
				Activated = function()
					panelOpen:set(false)
				end,
			}
		end),
		UI.TabView "Demos" {
			selection = selected,
			tabs = tabs,
			retention = "top",
			transition = false,
			placement = "none",
			Position = function(use)
				return UDim2.fromOffset(0, toolbarHeight(use))
			end,
			Size = function(use)
				return UDim2.new(1, 0, 1, -toolbarHeight(use))
			end,
		},
	}
	root:AddTag("facet-surface")
	Compose.watch(function(use)
		if use(ctx.device) and use(ctx.device).width then
			root:AddTag("facet-floating")
		else
			root:RemoveTag("facet-floating")
		end
	end)
	return root
end
return screen
