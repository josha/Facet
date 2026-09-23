--!strict
local catalogue = require("./demo_picker")
local screen = {}
screen.list = catalogue.list
screen.next = catalogue.next

function screen.configure(ctx)
	local Compose = ctx.Compose
	ctx.themeName = ctx.themeName or Compose.cell("Neutral")
	ctx.viewingDistance = Compose.cell("automatic")
	ctx.previewScale = Compose.formula(function(use)
		return if use(ctx.viewingDistance) == "ten-foot" then 1.5 else 1
	end)
	ctx.motionPreference = Compose.cell(nil)
	local gui = ctx.guiService
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
			return Host.TextLabel({
				Name = "DemoFailure",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = demo.title .. " could not load\n" .. tostring(result),
				TextWrapped = true,
			})
		end
	end
	local choices = {}
	for _, demo in (ctx.demos or catalogue.list()) do
		table.insert(choices, { value = demo.id, label = demo.title })
	end
	local themes = {}
	for name in ctx.packages do
		table.insert(themes, { value = name, label = name })
	end
	table.sort(themes, function(a, b)
		return if a.value == "Neutral" then true elseif b.value == "Neutral" then false else a.label < b.label
	end)
	local root = Host.Frame({
		Name = "Gallery",
		Size = function(use)
			local inverse = 1 / use(ctx.previewScale)
			return UDim2.fromScale(inverse, inverse)
		end,
		Host.UIScale({ Name = "ViewingDistance", Scale = ctx.previewScale }),
		BackgroundTransparency = function(use)
			return if use(ctx.sceneVisible) then 1 else 0
		end,

		Host.Frame({
			Name = "Toolbar",
			Size = UDim2.new(1, 0, 0, 56),
			BackgroundTransparency = 1,
			Host.UIPadding({
				PaddingLeft = UDim.new(0, 12),
				PaddingRight = UDim.new(0, 12),
				PaddingTop = UDim.new(0, 8),
			}),
			Host.UIListLayout({
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			UI.Picker({
				LayoutOrder = 1,
				Name = "Demo",
				label = "Demo",
				selected = selected,
				options = choices,
				Size = UDim2.new(1, -160, 0, 40),
			}),
			UI.Button({
				LayoutOrder = 2,
				Name = "Settings",
				label = "Settings",
				Size = UDim2.fromOffset(136, 40),
				onActivate = function()
					settingsOpen:set(not settingsOpen:peek())
				end,
			}),
		}),
		Host.Frame({
			Name = "Content",
			Position = UDim2.fromOffset(0, 56),
			Size = UDim2.new(1, 0, 1, -56),
			BackgroundTransparency = 1,
			Compose.switch(selected, branches),
		}),
		UI.Sheet({
			detent = Compose.cell("medium"),
			Name = "GallerySettings",
			isPresented = settingsOpen,
			title = "Gallery settings",
			content = function()
				return Host.Frame({
					Name = "Settings",
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
					UI.Picker({
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
					}),
					UI.Button({
						LayoutOrder = 9,
						Name = "Close",
						label = "Done",
						onActivate = function()
							settingsOpen:set(false)
						end,
					}),
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
					UI.Label({
						LayoutOrder = 4,
						Name = "MotionNote",
						Text = "Reduced removes decorative travel while progress keeps running. Roblox's reduced-motion preference remains in effect.",
						TextWrapped = true,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						BackgroundTransparency = 1,
					}),
					UI.Button({
						LayoutOrder = 5,
						Name = "FollowRobloxMotion",
						label = "Use Roblox motion preference",
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
					UI.Label({
						LayoutOrder = 7,
						Text = "Distant TV previews larger controls at 150% scale. Automatic and Near use normal scale; Roblox text and accessibility preferences still apply.",
						TextWrapped = true,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
					}),
					UI.Label({
						LayoutOrder = 8,
						Name = "NativePreview",
						Text = "In Studio, use Device Emulator for screen size, orientation and touch, and Controller Emulator for gamepad. Roblox Settings controls text size and accessibility preferences.",
						TextWrapped = true,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						BackgroundTransparency = 1,
					}),
				})
			end,
		}),
	})
	root:AddTag("facet-surface")
	return root
end
return screen
