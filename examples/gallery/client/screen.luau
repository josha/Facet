--!strict
local catalogue = require("./demo_picker")
local screen = {}
local DEVICES = {
	phone = { width = 389, height = 762, displaySize = "Small", input = "Touch", rotates = true },
	tablet = { width = 768, height = 1024, displaySize = "Small", input = "Touch", rotates = true },
	tv = { width = 1920, height = 1080, displaySize = "Large", input = "Gamepad" },
}
screen.list = catalogue.list
screen.next = catalogue.next
screen.boot = catalogue.boot

function screen.configure(ctx)
	local Compose = ctx.Compose
	ctx.themeName = ctx.themeName or Compose.cell("Neutral")
	ctx.viewingDistance = Compose.cell("automatic")
	ctx.categoryPlacement = Compose.cell("automatic")
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
	ctx.previewScale = Compose.formula(function(use)
		local device = use(ctx.device)
		if device and display then
			local size = use(display)
			return math.min(1, size.width / device.width, (size.height - inset) / device.height)
		end
		return if use(ctx.viewingDistance) == "ten-foot" then 1.5 else 1
	end)
	if display then
		ctx.previewViewport = Compose.formula(function(use)
			local device = use(ctx.device)
			return if device then { width = device.width, height = device.height } else use(display)
		end)
		ctx.sceneViewport = Compose.formula(function(use)
			local size = use(ctx.previewViewport)
			local scale = if use(ctx.device) then 1 else use(ctx.previewScale)
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
			return device and ctx.types.Vector2.new(device.width, device.height)
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
	}
end

function screen.build(ctx: any)
	local Host, UI, Compose = ctx.Host, ctx.UI, ctx.Compose
	if not ctx.reducedMotion then
		screen.configure(ctx)
	end
	local UDim, UDim2, Enum = ctx.types.UDim, ctx.types.UDim2, ctx.types.Enum
	local selected = ctx.selection
	ctx.sceneVisible = Compose.cell(false)
	local themeName = ctx.themeName or Compose.cell("Neutral")
	ctx.themeName = themeName
	local settingsOpen = Compose.cell(false)
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
	local function demoPicker(order)
		return UI.Picker({
			Name = "DemoPicker",
			LayoutOrder = order,
			style = "menu",
			sizing = "hug",
			selected = selected,
			options = demoOptions,
		})
	end
	local themes = {}
	for name, package in ctx.packages do
		table.insert(themes, { value = name, label = package.identity and package.identity.displayName or name })
	end
	table.sort(themes, function(a, b)
		return if a.value == "Neutral" then true elseif b.value == "Neutral" then false else a.label < b.label
	end)
	local compact = Compose.formula(function(use)
		local viewport = ctx.previewViewport and use(ctx.previewViewport)
		return viewport ~= nil and viewport.height > 0 and viewport.height < 480
	end)
	local measuredToolbar = Compose.cell(56)
	local toolbarHeight = function(use)
		return if use(compact) then 0 else use(measuredToolbar)
	end
	local toolbar = Host.Frame "Toolbar" {
		Visible = function(use)
			return not use(compact)
		end,
		Size = function(use)
			return UDim2.new(1, 0, 0, if use(compact) then 0 else 56)
		end,
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Host.UIPadding({
			PaddingLeft = UDim.new(0, 16),
			PaddingRight = UDim.new(0, 12),
			PaddingTop = UDim.new(0, 8),
			PaddingBottom = UDim.new(0, 4),
		}),
		Host.UIListLayout({
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
		UI.Text "Title" {
			LayoutOrder = 1,
			text = "Facet gallery",
			textRole = "title",
			Size = UDim2.fromScale(0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
		},
		demoPicker(2),
		Host.Frame "Spring" {
			LayoutOrder = 3,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(0, 0),
			Host.UIFlexItem({ FlexMode = Enum.UIFlexMode.Fill }),
		},
		UI.Button "Settings" {
			LayoutOrder = 4,
			label = "Settings",
			icon = "settings",
			appearance = "utility",
			onActivate = function()
				settingsOpen:set(not settingsOpen:peek())
			end,
		},
	}
	local toolbarSize = toolbar:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		measuredToolbar:set(math.max(56, math.ceil(toolbar.AbsoluteSize.Y)))
	end)
	Compose.cleanup(function()
		toolbarSize:Disconnect()
	end)
	local root = Host.Frame "Gallery" {
		AnchorPoint = ctx.types.Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = function(use)
			local device = use(ctx.device)
			if device then
				return UDim2.fromOffset(device.width, device.height)
			end
			local inverse = 1 / use(ctx.previewScale)
			return UDim2.fromScale(inverse, inverse)
		end,
		Host.UIScale "ViewingDistance" { Scale = ctx.previewScale },
		BackgroundTransparency = function(use)
			return if use(ctx.sceneVisible) then 1 else 0
		end,

		toolbar,
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
		UI.Sheet({
			detent = Compose.cell("medium"),
			Name = "GallerySettings",
			isPresented = settingsOpen,
			title = "Gallery settings",
			content = function()
				return Host.Frame "Settings" {
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,
					Host.UIListLayout({ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 12) }),
					UI.Picker({
						LayoutOrder = 1,
						Name = "Theme",
						label = "Theme",
						selected = themeName,
						options = themes,
						onChange = function(name)
							screen.setTheme(ctx, name)
						end,
					}),
					Compose.show(function(use)
						return #use(ctx.theme).style.themes > 1
					end, function()
						return UI.Picker({
							LayoutOrder = 2,
							Name = "Mode",
							label = "Appearance",
							selected = ctx.themeMode,
							options = function(use)
								local choices = {}
								for _, palette in use(ctx.theme).style.themes do
									table.insert(choices, { value = palette.name, label = palette.name })
								end
								return choices
							end,
						})
					end),
					UI.Picker({
						LayoutOrder = 3,
						Name = "Motion",
						label = "Motion",
						selected = ctx.motionMode,
						options = { { value = "full", label = "Full" }, { value = "reduced", label = "Reduced" } },
						onChange = function(value)
							ctx.motionPreference:set(value == "reduced")
							ctx.motionMode:set(if ctx.reducedMotion:peek() then "reduced" else "full")
						end,
					}),
					UI.Text({
						LayoutOrder = 4,
						Name = "MotionNote",
						text = "Reduced removes decorative travel while progress keeps running. Roblox's reduced-motion preference remains in effect.",
						textRole = "caption",
						TextWrapped = true,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						BackgroundTransparency = 1,
					}),
					UI.Button({
						LayoutOrder = 5,
						Name = "FollowRobloxMotion",
						label = "Use Roblox motion preference",
						appearance = "link",
						onActivate = function()
							ctx.motionPreference:set(nil)
						end,
					}),
					UI.Picker({
						LayoutOrder = 6,
						Name = "ViewingDistance",
						label = "Viewing-distance preview",
						selected = ctx.viewingDistance,
						options = {
							{ value = "automatic", label = "Automatic" },
							{ value = "near", label = "Near" },
							{ value = "ten-foot", label = "Distant TV" },
						},
					}),
					UI.Text({
						LayoutOrder = 7,
						text = "Distant TV previews larger controls at 150% scale. Automatic and Near use normal scale; Roblox text and accessibility preferences still apply.",
						textRole = "caption",
						TextWrapped = true,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
					}),
					UI.Picker({
						LayoutOrder = 0,
						Name = "CategoryPlacement",
						label = "Categories",
						selected = ctx.categoryPlacement,
						options = {
							{ value = "automatic", label = "Automatic" },
							{ value = "top", label = "Top" },
							{ value = "side", label = "Side" },
						},
					}),
					UI.Picker({
						LayoutOrder = 8,
						Name = "DevicePreview",
						label = "Device preview",
						selected = ctx.devicePreview,
						options = {
							{ value = "automatic", label = "Automatic" },
							{ value = "phone", label = "Phone" },
							{ value = "tablet", label = "Tablet" },
							{ value = "tv", label = "TV" },
						},
					}),
					Compose.show(function(use)
						local device = DEVICES[use(ctx.devicePreview)]
						return device ~= nil and device.rotates == true
					end, function()
						return UI.Picker({
							LayoutOrder = 9,
							Name = "OrientationPreview",
							label = "Orientation",
							selected = ctx.orientationPreview,
							options = {
								{ value = "portrait", label = "Portrait" },
								{ value = "landscape", label = "Landscape" },
							},
						})
					end),
					UI.Picker({
						LayoutOrder = 10,
						Name = "InputPreview",
						label = "Input preview",
						selected = ctx.inputPreview,
						options = {
							{ value = "automatic", label = "Automatic" },
							{ value = "KeyboardAndMouse", label = "Keyboard and mouse" },
							{ value = "Touch", label = "Touch" },
							{ value = "Gamepad", label = "Gamepad" },
						},
					}),
					UI.Picker({
						LayoutOrder = 11,
						Name = "TextPreview",
						label = "Text size preview",
						selected = ctx.textPreview,
						options = {
							{ value = "automatic", label = "Automatic" },
							{ value = "Medium", label = "Medium" },
							{ value = "Large", label = "Large" },
							{ value = "Larger", label = "Larger" },
							{ value = "Largest", label = "Largest" },
						},
					}),
					UI.Text({
						LayoutOrder = 12,
						Name = "NativePreview",
						text = "A device preview frames the gallery at that screen size and reads its display size and input: Phone and Tablet are touch, TV is a large display with a gamepad. The input and text size previews change what the controls read; your real input still works.",
						textRole = "caption",
						TextWrapped = true,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						BackgroundTransparency = 1,
					}),
				}
			end,
		}),
	}
	if ctx.inputTarget then
		Host.ScreenGui "FacetGalleryMenu" {
			ResetOnSpawn = false,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			ScreenInsets = Enum.ScreenInsets.TopbarSafeInsets,
			Enabled = compact,
			Parent = ctx.inputTarget,
			Host.StyleLink({ StyleSheet = ctx.sheet and Compose.static(ctx.sheet) }),
			Host.Frame "Strip" {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Host.UIPadding({ PaddingLeft = UDim.new(0, 8) }),
				Host.UIListLayout({
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
				}),
				demoPicker(1),
				UI.Button "StripSettings" {
					LayoutOrder = 2,
					label = "",
					name = "Settings",
					icon = "settings",
					appearance = "utility",
					onActivate = function()
						settingsOpen:set(true)
					end,
				},
			},
		}
	end
	root:AddTag("facet-surface")
	Compose.watch(function(use)
		if use(ctx.device) then
			root:AddTag("facet-floating")
		else
			root:RemoveTag("facet-floating")
		end
	end)
	return root
end
return screen
