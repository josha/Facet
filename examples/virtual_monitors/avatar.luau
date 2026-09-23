--!strict
return function(ctx)
	local Compose, Host, UI, runtime, model = ctx.Compose, ctx.Host, ctx.UI, ctx.runtime, ctx.model
	local types, D, D2, V2, C3, CF, E = ctx.types, ctx.D, ctx.D2, ctx.V2, ctx.C3, ctx.CF, ctx.E
	local text, row, column, button = ctx.text, ctx.row, ctx.column, ctx.button
	local palettes = { sage = "Sage", clay = "Clay", iris = "Iris" }
	local spins = { "Off", "Slow", "Medium", "Fast" }
	local turnSteps = { 15, 30, 45, 90 }
	local body = Host.Frame({ Name = "AvatarBody", Size = D2.fromScale(1, 1), BackgroundTransparency = 1 })
	local dimensions = ctx.observeSize(body)
	local function wide(use)
		return use(dimensions).X >= 760
	end
	local function settingsWidth(use)
		return math.clamp(use(dimensions).X * 0.42, 340, 420)
	end
	local function previewHeight(use)
		return math.clamp(use(dimensions).Y * 0.34, 120, 280)
	end
	local function paletteName(use)
		return palettes[use(model.palette)] or use(model.palette)
	end
	local function rotation(use)
		return `{math.round(use(model.angle))}°`
	end
	local function spin(use)
		return spins[use(model.autoSpin) + 1]
	end
	local function padding(value)
		return Host.UIPadding({
			PaddingLeft = D.new(0, value),
			PaddingRight = D.new(0, value),
			PaddingTop = D.new(0, value),
			PaddingBottom = D.new(0, value),
		})
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
				local plate = Host.Frame({
					Name = id .. "Plate",
					Size = D2.fromScale(1, 1),
					BorderSizePixel = 0,
					text(id .. "Label", title, 12, {
						Position = D2.fromOffset(6, 5),
						Size = D2.new(1, -12, 0, 14),
						AutomaticSize = E.AutomaticSize.None,
						TextWrapped = false,
					}, "facet-secondary"),
					text(id .. "Rich", rich, 15, {
						Position = D2.fromOffset(6, 21),
						Size = D2.new(1, -12, 0, 20),
						AutomaticSize = E.AutomaticSize.None,
						TextWrapped = false,
						TextTruncate = E.TextTruncate.AtEnd,
					}),
					Host.UICorner({ CornerRadius = D.new(0, 8) }),
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
					TextSize = 13,
					TextWrapped = false,
					TextTruncate = E.TextTruncate.AtEnd,
				})
			end),
		})
	end
	local function facts()
		local values = {
			{ id = "Palette", label = "Palette", value = paletteName },
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
		local rows = {}
		for _, fact in values do
			table.insert(
				rows,
				row("Summary" .. fact.id, {
					text("Label", fact.label, 17, { Size = D2.new(0.5, -4, 0, 0) }, "facet-secondary"),
					text(
						"Value",
						fact.value,
						17,
						{ Size = D2.new(0.5, -4, 0, 0), TextXAlignment = E.TextXAlignment.Right }
					),
				}, { Size = D2.new(1, 0, 0, 0), AutomaticSize = E.AutomaticSize.Y })
			)
		end
		table.insert(
			rows,
			button("Done", "Done", function()
				model.avatarSummary:set(false)
			end, { Size = D2.new(1, 0, 0, 44), AutomaticSize = E.AutomaticSize.None })
		)
		return column("SummaryFacts", rows)
	end
	local stop = runtime.mountFragment(function()
		local preview = Host.Frame({
			Name = "PreviewPanel",
			BorderSizePixel = 0,
			Size = function(use)
				return if wide(use)
					then D2.new(1, -settingsWidth(use) - 16, 1, 0)
					else D2.new(1, 0, 0, previewHeight(use))
			end,
			Host.UICorner({ CornerRadius = D.new(0, 12) }),
			ctx.stage("AvatarPreview", ctx.actions.avatarContent, {
				Size = D2.fromScale(1, 1),
				camera = CF.lookAt(types.Vector3.new(0, 3.4, -11), types.Vector3.new(0, 2.5, 0)),
				fieldOfView = 36,
				Ambient = C3.fromRGB(92, 99, 120),
				LightDirection = types.Vector3.new(-0.7, -0.8, 1),
			}),
			column("AvatarHUD", {
				hud("Look", "Look", function(use)
					return paletteName(use) .. (if use(model.hat) then " · Hat on" else " · Hat off")
				end, paletteName),
				hud("Rotation", "Rotation", rotation, rotation),
				hud("Spin", "Auto-spin", spin, spin),
			}, {
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
				ZIndex = 3,
			}),
		})
		preview:AddTag("facet-panel")
		local settings = Host.ScrollingFrame({
			Name = "AvatarSettings",
			BorderSizePixel = 0,
			CanvasSize = D2.fromOffset(0, 0),
			AutomaticCanvasSize = E.AutomaticSize.Y,
			ScrollingDirection = E.ScrollingDirection.Y,
			ScrollBarThickness = 5,
			SelectionGroup = true,
			SelectionBehaviorUp = E.SelectionBehavior.Stop,
			SelectionBehaviorDown = E.SelectionBehavior.Stop,
			SelectionBehaviorLeft = E.SelectionBehavior.Stop,
			SelectionBehaviorRight = E.SelectionBehavior.Stop,
			Position = function(use)
				return if wide(use)
					then D2.new(1, -settingsWidth(use), 0, 0)
					else D2.fromOffset(0, previewHeight(use) + 16)
			end,
			Size = function(use)
				return if wide(use)
					then D2.new(0, settingsWidth(use), 1, 0)
					else D2.new(1, 0, 1, -previewHeight(use) - 16)
			end,
			Host.UICorner({ CornerRadius = D.new(0, 12) }),
			column("Settings", {
				text("Heading", "Explorer", 28),
				text("Subtitle", "Choose a palette and accessories.", 16, {}, "facet-secondary"),
				UI.DisclosureGroup({
					Name = "SettingsDisclosure",
					label = "Appearance",
					expanded = model.avatarSettingsExpanded,
					Size = D2.new(1, 0, 0, 0),
					content = function()
						return column("AppearanceSettings", {
							text("PaletteLabel", "Palette", 18),
							UI.Picker({
								Name = "Palette",
								selected = model.palette,
								style = "segmented",
								options = {
									{ value = "sage", label = "Sage" },
									{ value = "clay", label = "Clay" },
									{ value = "iris", label = "Iris" },
								},
								Size = D2.new(1, 0, 0, 44),
								AutomaticSize = E.AutomaticSize.None,
							}),
							UI.Toggle({
								Name = "Hat",
								label = "Explorer hat",
								value = model.hat,
								Size = D2.new(1, 0, 0, 44),
								AutomaticSize = E.AutomaticSize.None,
							}),
							UI.RadialMenu({
								Name = "QuickPalette",
								label = "Quick palette",
								appearance = "buttons",
								Size = D2.new(1, 0, 0, 44),
								items = {
									{ id = "sage", label = "Sage", selected = model.palette, value = "sage" },
									{ id = "clay", label = "Clay", selected = model.palette, value = "clay" },
									{ id = "iris", label = "Iris", selected = model.palette, value = "iris" },
								},
							}),
						})
					end,
				}),
				text("TurnStepLabel", "Turn step", 18),
				UI.Stepper({
					Name = "TurnStep",
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
				}),
				text("RotationLabel", "Rotation", 18),
				UI.Slider({
					Name = "Rotation",
					value = model.angle,
					min = -180,
					max = 180,
					step = model.turnStep,
					format = function(value)
						return `{math.round(value)}°`
					end,
					Size = D2.new(1, 0, 0, 44),
				}),
				row("TurnButtons", {
					button("TurnLeft", "Turn left", function()
						model.turn(-1)
					end, { Size = D2.new(0.5, -4, 0, 44), AutomaticSize = E.AutomaticSize.None }),
					button("TurnRight", "Turn right", function()
						model.turn(1)
					end, { Size = D2.new(0.5, -4, 0, 44), AutomaticSize = E.AutomaticSize.None }),
				}, { Size = D2.new(1, 0, 0, 44) }),
				text("SpinLabel", "Auto-spin", 18),
				row("AutoSpinRow", {
					text("SpinValue", spin, 16, { Size = D2.new(1, -164, 0, 0) }, "facet-secondary"),
					UI.LevelPicker({
						Name = "AutoSpin",
						value = model.autoSpin,
						count = 3,
						allowZero = true,
						Size = D2.fromOffset(156, 44),
						AutomaticSize = E.AutomaticSize.None,
					}),
				}, { Size = D2.new(1, 0, 0, 44) }),
				row("SummaryActions", {
					button(
						"Summary",
						"Summary",
						openSummary,
						{ Size = D2.new(0.5, -4, 0, 44), AutomaticSize = E.AutomaticSize.None }
					),
					UI.CollapsibleView({
						Name = "Tips",
						label = "Tips",
						icon = "edit",
						expanded = model.avatarTipsExpanded,
						Size = D2.new(0.5, -4, 0, 44),
						AutomaticSize = E.AutomaticSize.None,
						content = function()
							return column("PreviewTips", {
								text(
									"TurnTips",
									"Turn step sets the increment for Rotation and both Turn buttons. Use the stepper to choose 15°, 30°, 45° or 90°.",
									17,
									{},
									"facet-secondary"
								),
								text(
									"SpinTips",
									"Auto-spin keeps turning the preview until you pick Off, or your device asks for reduced motion. Your choices survive switching screens.",
									17,
									{},
									"facet-secondary"
								),
							})
						end,
					}),
				}, { Size = D2.new(1, 0, 0, 44) }),
				button("Reset", "Reset look", function()
					model.resetAvatarPresented:set(true)
				end, { Size = D2.new(1, 0, 0, 44), AutomaticSize = E.AutomaticSize.None }),
			}, { Size = D2.new(1, -8, 0, 0), padding(16) }),
		})
		settings:AddTag("facet-panel")
		return {
			preview,
			settings,
			UI.Sheet({
				Name = "AvatarSummary",
				title = "Look summary",
				isPresented = model.avatarSummary,
				detent = model.avatarSummaryDetent,
				content = facts,
			}),
			UI.Alert({
				Name = "ResetAvatar",
				isPresented = model.resetAvatarPresented,
				title = "Reset your look?",
				message = "The palette, hat and rotation return to their defaults.",
				actions = {
					{ id = "cancel", label = "Cancel", role = "cancel" },
					{ id = "reset", label = "Reset", role = "destructive", onActivate = model.resetAvatar },
				},
			}),
		}
	end, body)
	Compose.cleanup(stop)
	return body
end
