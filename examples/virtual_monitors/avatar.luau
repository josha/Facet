--!strict
local theme = require("./theme")
return function(ctx)
	local Compose, Host, UI, model = ctx.Compose, ctx.Host, ctx.UI, ctx.model
	local types, D2, V2, C3, CF, E = ctx.types, ctx.D2, ctx.V2, ctx.C3, ctx.CF, ctx.E
	local words, quiet, button = ctx.words, ctx.quiet, ctx.button
	local arithmetic = ctx.Facet.recipes.arithmetic
	local scrollTo, scrollToVisible = UI.scrollTo, UI.scrollToVisible
	local accents, accentOptions, accentItems = {}, {}, {}
	for _, entry in theme.ACCENTS do
		accents[entry.id] = entry.label
		table.insert(accentOptions, { value = entry.id, label = entry.label })
		table.insert(accentItems, { id = entry.id, label = entry.label, selected = model.palette, value = entry.id })
	end
	local spins = { "Off", "Slow", "Medium", "Fast" }
	local turnSteps = { 15, 30, 45, 90 }
	local dimensions = Compose.cell(V2.new(920, 560))
	local function wide(use)
		return use(dimensions).X >= 760
	end
	local function settingsWidth(use)
		return math.clamp(use(dimensions).X * 0.42, 340, 420)
	end
	local function previewHeight(use)
		return math.clamp(use(dimensions).Y * 0.34, 120, 280)
	end
	local function accentName(use)
		return accents[use(model.palette)] or use(model.palette)
	end
	local function rotation(use)
		return `{math.round(use(model.angle))}°`
	end
	local function spin(use)
		return spins[use(model.autoSpin) + 1]
	end
	local function openSummary()
		model.avatarSummary:set(true)
	end
	local function hud(id, title, rich, compact)
		return Host.Frame({
			Name = id .. "HUD",
			BackgroundTransparency = 1,
			Size = function(use)
				return D2.new(1, 0, 0, if wide(use) then 48 else 32)
			end,
			Compose.show(wide, function()
				local plate = UI.VStack({
					Name = id .. "Plate",
					width = "fill",
					height = "fill",
					padding = { top = 5, left = 6, right = 6, bottom = 4 },
					BackgroundTransparency = 0,
					Host.UICorner({ CornerRadius = ctx.D.new(0, 8) }),
					quiet(id .. "Label", title, "caption", {
						TextWrapped = false,
						Size = D2.new(1, 0, 0, 14),
						AutomaticSize = E.AutomaticSize.None,
					}),
					words(id .. "Rich", rich, "label", {
						TextWrapped = false,
						TextTruncate = E.TextTruncate.AtEnd,
						Size = D2.new(1, 0, 0, 20),
						AutomaticSize = E.AutomaticSize.None,
					}),
				})
				plate:AddTag("facet-panel")
				return plate
			end),
			Compose.show(function(use)
				return not wide(use)
			end, function()
				return button("Expand" .. id, compact, openSummary, {
					Size = D2.fromScale(1, 1),
					AutomaticSize = E.AutomaticSize.None,
					TextWrapped = false,
					TextTruncate = E.TextTruncate.AtEnd,
				})
			end),
		})
	end
	local function facts()
		local values = {
			{ id = "Palette", label = "Accent", value = accentName },
			{
				id = "Hat",
				label = "Hat",
				value = function(use)
					return if use(model.hat) then "On" else "Off"
				end,
			},
			{ id = "Rotation", label = "Rotation", value = rotation },
			{
				id = "TurnStep",
				label = "Turn step",
				value = function(use)
					return `{use(model.turnStep)}°`
				end,
			},
			{ id = "AutoSpin", label = "Auto-spin", value = spin },
		}
		local rows = { Name = "SummaryFacts", width = "fill", gap = "s" }
		for _, fact in values do
			table.insert(
				rows,
				UI.HStack({
					Name = "Summary" .. fact.id,
					width = "fill",
					gap = "s",
					quiet("Label", fact.label, "label", { Size = D2.new(0.5, -4, 0, 0) }),
					words("Value", fact.value, "label", {
						Size = D2.new(0.5, -4, 0, 0),
						TextXAlignment = E.TextXAlignment.Right,
					}),
				})
			)
		end
		table.insert(
			rows,
			button("Done", "Done", function()
				model.avatarSummary:set(false)
			end, { Size = D2.new(1, 0, 0, 44), AutomaticSize = E.AutomaticSize.None })
		)
		return UI.VStack(rows)
	end
	local angleDraft = Compose.cell(tostring(math.round(model.angle:peek())))
	Compose.watch(function(use)
		local angle = math.round(use(model.angle))
		if arithmetic.parse(angleDraft:peek()) ~= angle then
			angleDraft:set(tostring(angle))
		end
	end)
	local function page(name, ...)
		return UI.ScrollView(name)({
			padding = { top = 16, left = 16, right = 24, bottom = 16 },
			gap = 10,
			ScrollBarThickness = 5,
			...,
		})
	end
	local preview = UI.ZStack "PreviewPanel" {
		Size = function(use)
			return if wide(use) then D2.new(1, -settingsWidth(use) - 16, 1, 0) else D2.new(1, 0, 0, previewHeight(use))
		end,
		AutomaticSize = E.AutomaticSize.None,
		BackgroundTransparency = 0,
		ctx.rounded(),
		ctx.panelShadow(),
		ctx.stage("AvatarPreview", ctx.actions.avatarContent, {
			camera = CF.lookAt(types.Vector3.new(0, 3.4, -11), types.Vector3.new(0, 2.5, 0)),
			fieldOfView = 36,
			Ambient = C3.fromRGB(92, 99, 120),
			LightDirection = types.Vector3.new(-0.7, -0.8, 1),
		}),
		UI.VStack "AvatarHUD" {
			gap = "s",
			AnchorPoint = function(use)
				return if wide(use) then V2.new(0, 1) else V2.zero
			end,
			Position = function(use)
				return if wide(use) then D2.new(0, 12, 1, -12) else D2.fromOffset(12, 12)
			end,
			Size = function(use)
				return D2.fromOffset(if wide(use) then 190 else 84, if wide(use) then 164 else 116)
			end,
			AutomaticSize = E.AutomaticSize.None,
			hud("Look", "Look", function(use)
				return accentName(use) .. (if use(model.hat) then " · Hat on" else " · Hat off")
			end, accentName),
			hud("Rotation", "Rotation", rotation, rotation),
			hud("Spin", "Auto-spin", spin, spin),
		},
	}
	preview:AddTag("facet-panel")
	local settings = Host.Frame "AvatarSettings" {
		BorderSizePixel = 0,
		SelectionGroup = true,
		SelectionBehaviorDown = E.SelectionBehavior.Stop,
		SelectionBehaviorLeft = E.SelectionBehavior.Stop,
		SelectionBehaviorRight = E.SelectionBehavior.Stop,
		Size = function(use)
			return if wide(use) then D2.new(0, settingsWidth(use), 1, 0) else D2.new(1, 0, 1, -previewHeight(use) - 16)
		end,
		ctx.rounded(),
		Host.UIPadding({
			PaddingLeft = ctx.D.new(0, 12),
			PaddingRight = ctx.D.new(0, 12),
			PaddingTop = ctx.D.new(0, 12),
			PaddingBottom = ctx.D.new(0, 12),
		}),
		UI.NavigationStack "SettingsStack" {
			path = model.avatarPath,
			root = {
				title = "Explorer",
				content = function()
					local settingsPage
					settingsPage = page(
						"SettingsPage",
						quiet("Subtitle", "Choose an accent and accessories.", "label"),
						UI.DisclosureGroup "SettingsDisclosure" {
							label = "Appearance",
							expanded = model.avatarSettingsExpanded,
							Size = D2.new(1, 0, 0, 0),
							AutomaticSize = E.AutomaticSize.Y,
							content = function()
								return UI.VStack "AppearanceSettings" {
									width = "fill",
									gap = 10,
									words("PaletteLabel", "Accent", "label"),
									UI.Picker "Palette" {
										selected = model.palette,
										style = "segmented",
										options = accentOptions,
										Size = D2.new(1, 0, 0, 44),
										AutomaticSize = E.AutomaticSize.None,
									},
									UI.Toggle "Hat" {
										label = "Explorer hat",
										value = model.hat,
										Size = D2.new(1, 0, 0, 44),
										AutomaticSize = E.AutomaticSize.None,
									},
									UI.ColorPicker "HatColour" {
										label = "Hat colour",
										modes = { "swatches", "spectrum" },
										swatches = {
											{ color = C3.fromRGB(218, 195, 145), label = "Straw" },
											{ color = C3.fromRGB(105, 74, 55), label = "Leather" },
											{ color = C3.fromRGB(46, 52, 64), label = "Slate" },
											{ color = C3.fromRGB(176, 58, 46), label = "Brick" },
										},
										value = function(use)
											local tint = use(model.hatTint)
											return C3.fromRGB(tint[1], tint[2], tint[3])
										end,
										onChange = function(color)
											model.hatTint:set({
												math.round(color.R * 255),
												math.round(color.G * 255),
												math.round(color.B * 255),
											})
										end,
										enabled = model.hat,
									},
									UI.RadialMenu "QuickPalette" {
										label = "Quick accent",
										appearance = "buttons",
										Size = D2.new(1, 0, 0, 44),
										items = accentItems,
									},
								}
							end,
						},
						UI.Button "MotionRow" {
							row = { title = "Motion & turning" },
							onActivate = function()
								model.avatarPath:set({ { id = "motion", value = true } })
							end,
						},
						UI.HStack "SummaryActions" {
							width = "fill",
							gap = "s",
							button(
								"Summary",
								"Summary",
								openSummary,
								{ Size = D2.new(0.5, -4, 0, 44), AutomaticSize = E.AutomaticSize.None }
							),
							UI.CollapsibleView "Tips" {
								label = "Tips",
								icon = "edit",
								expanded = model.avatarTipsExpanded,
								Size = D2.new(0.5, -4, 0, 44),
								AutomaticSize = E.AutomaticSize.None,
								content = function()
									local tips
									tips = UI.VStack "PreviewTips" {
										width = "fill",
										gap = "s",
										quiet(
											"TurnTips",
											"Turn step sets the increment for Rotation and both Turn buttons. Use the stepper to choose 15°, 30°, 45° or 90°.",
											"label"
										),
										quiet(
											"SpinTips",
											"Auto-spin keeps turning the preview until you pick Off, or your device asks for reduced motion. Your choices survive switching screens.",
											"label"
										),
									}
									local grown = tips:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
										scrollToVisible(tips)
									end)
									Compose.cleanup(function()
										grown:Disconnect()
									end)
									return tips
								end,
							},
						},
						button("Reset", "Reset look", function()
							model.resetAvatarPresented:set(true)
						end, { Size = D2.new(1, 0, 0, 44), AutomaticSize = E.AutomaticSize.None }),
						button("SettingsTop", "Back to top", function()
							scrollTo(settingsPage, "top")
						end, { Size = D2.new(1, 0, 0, 44), AutomaticSize = E.AutomaticSize.None })
					)
					return settingsPage
				end,
			},
			destinations = {
				motion = {
					title = "Motion & turning",
					content = function()
						return page(
							"MotionPage",
							words("TurnStepLabel", "Turn step", "label"),
							UI.Stepper "TurnStep" {
								min = 1,
								max = #turnSteps,
								step = 1,
								value = function(use)
									return table.find(turnSteps, use(model.turnStep)) or 2
								end,
								onChange = function(index)
									model.turnStep:set(turnSteps[index])
								end,
								format = function(index)
									return `{turnSteps[index]}°`
								end,
								Size = D2.new(1, 0, 0, 44),
							},
							words("RotationLabel", "Rotation", "label"),
							UI.Slider "Rotation" {
								value = model.angle,
								min = -180,
								max = 180,
								step = model.turnStep,
								format = function(value)
									return `{math.round(value)}°`
								end,
								Size = D2.new(1, 0, 0, 44),
							},
							UI.NumberInput "ExactAngle" {
								label = "Exact angle",
								hint = "Type an angle or a sum, such as 90+45.",
								value = angleDraft,
								numericValue = model.angle,
								min = -180,
								max = 180,
								precision = 0,
								suffix = "°",
								scrub = true,
								parse = arithmetic.parse,
								Size = D2.new(1, 0, 0, 0),
								AutomaticSize = E.AutomaticSize.Y,
							},
							UI.HStack "TurnButtons" {
								width = "fill",
								gap = "s",
								button("TurnLeft", "Turn left", function()
									model.turn(-1)
								end, {
									Size = D2.new(0.5, -4, 0, 44),
									AutomaticSize = E.AutomaticSize.None,
								}),
								button("TurnRight", "Turn right", function()
									model.turn(1)
								end, {
									Size = D2.new(0.5, -4, 0, 44),
									AutomaticSize = E.AutomaticSize.None,
								}),
							},
							words("SpinLabel", "Auto-spin", "label"),
							UI.HStack "AutoSpinRow" {
								width = "fill",
								gap = "s",
								align = "center",
								quiet("SpinValue", spin, "label", { Size = D2.new(0, 0, 0, 0), UI.fill() }),
								UI.LevelPicker "AutoSpin" {
									value = model.autoSpin,
									count = 3,
									allowZero = true,
									Size = D2.fromOffset(156, 44),
									AutomaticSize = E.AutomaticSize.None,
								},
							}
						)
					end,
				},
			},
		},
	}
	settings:AddTag("facet-panel")
	local body = UI.HStack "AvatarBody" {
		width = "fill",
		height = "fill",
		gap = 16,
		wrap = true,
		preview,
		settings,
	}
	ctx.measure(body, dimensions)
	return body,
		UI.ZStack "Overlays" {
			width = "fill",
			height = "fill",
			UI.Sheet "AvatarSummary" {
				title = "Look summary",
				isPresented = model.avatarSummary,
				detent = model.avatarSummaryDetent,
				content = facts,
			},
			UI.Alert "ResetAvatar" {
				isPresented = model.resetAvatarPresented,
				title = "Reset your look?",
				message = "The accent, hat, hat colour and rotation return to their defaults.",
				actions = {
					{ id = "cancel", label = "Cancel", role = "cancel" },
					{ id = "reset", label = "Reset", role = "destructive", onActivate = model.resetAvatar },
				},
			},
		}
end
