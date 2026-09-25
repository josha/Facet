--!strict
return {
	title = "Sensory feedback per control",
	ledgerRows = {},
	build = function(ctx)
		local UI, Compose, Host = ctx.UI, ctx.Compose, ctx.Host
		local D, D2, E = ctx.types.UDim, ctx.types.UDim2, ctx.types.Enum
		local playHaptics, selected, strength = Compose.cell(true), Compose.cell(false), Compose.cell(0.6)
		local requests, historyText, state =
			Compose.cell(0), Compose.cell("No feedback requested yet."), Compose.cell("Ready")
		local history = {}
		local effects = {
			press = Host.HapticEffect "PressEffect" { Type = E.HapticEffectType.UIClick },
			release = Host.HapticEffect "ReleaseEffect" { Type = E.HapticEffectType.UIClick },
			selection = Host.HapticEffect "SelectionEffect" { Type = E.HapticEffectType.UIHover },
			custom = Host.HapticEffect "CustomEffect" { Type = E.HapticEffectType.Custom },
		}
		Compose.watch(function(use)
			local amplitude = use(strength)
			local Key = ctx.types.FloatCurveKey
			effects.custom:SetWaveformKeys({
				Key.new(0, 0, E.KeyInterpolationMode.Linear),
				Key.new(12, amplitude, E.KeyInterpolationMode.Linear),
				Key.new(70, 0, E.KeyInterpolationMode.Linear),
				Key.new(120, amplitude * 0.5, E.KeyInterpolationMode.Linear),
				Key.new(220, 0, E.KeyInterpolationMode.Linear),
			})
		end)
		local function stopEffects()
			for _, effect in effects do
				effect:Stop()
			end
		end
		Compose.watch(function(use)
			if not use(playHaptics) then
				stopEffects()
				state:set("Feedback is off")
			end
		end)
		Compose.cleanup(stopEffects)
		local function record(kind, nativePress)
			if not playHaptics:peek() then
				state:set("Feedback is off")
				return
			end
			if not nativePress then
				effects[kind]:Play()
			end
			requests:update(function(value)
				return value + 1
			end)
			state:set(`Requested {kind} feedback`)
			table.insert(history, 1, `{requests:peek()}. {kind}`)
			if #history > 8 then
				table.remove(history)
			end
			historyText:set(table.concat(history, "\n"))
		end
		local function text(name, value, role)
			return UI.Label({
				Name = name,
				text = value,
				textRole = role,
				Size = D2.new(1, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
				TextWrapped = true,
				TextXAlignment = E.TextXAlignment.Left,
			})
		end
		local function row(name, title, description, control)
			return Host.Frame({
				Name = name,
				Size = D2.new(1, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Host.UIListLayout({ Padding = D.new(0, 6), SortOrder = E.SortOrder.LayoutOrder }),
				text("Title", title, "strong"),
				text("Description", description, "caption"),
				control,
			})
		end
		local function pressButton(effect)
			return UI.Button "Press" {
				label = "Press and hold",
				PressHapticEffect = if effect then Compose.static(effect) else nil,
				onPointerDown = function()
					record("press", true)
				end,
			}
		end
		local function report()
			return {
				enabled = playHaptics:peek(),
				requests = requests:peek(),
				state = state:peek(),
				motorConfirmed = false,
			}
		end
		return {
			playHaptics = playHaptics,
			requests = requests,
			historyText = historyText,
			effects = effects,
			report = report,
			steps = {
				setPlayHaptics = function(value)
					playHaptics:set(value)
				end,
				readHistory = function()
					return table.clone(history)
				end,
				readHaptics = report,
				playCustom = function()
					record("custom")
				end,
			},
			screen = function()
				return Host.ScrollingFrame "SensoryFeedback" {
					Size = D2.fromScale(1, 1),
					CanvasSize = D2.new(),
					AutomaticCanvasSize = E.AutomaticSize.Y,
					BackgroundTransparency = 1,
					ScrollBarThickness = 6,
					Host.UIPadding({
						PaddingLeft = D.new(0, 16),
						PaddingRight = D.new(0, 16),
						PaddingTop = D.new(0, 16),
						PaddingBottom = D.new(0, 16),
					}),
					Host.UIListLayout({ Padding = D.new(0, 16), SortOrder = E.SortOrder.LayoutOrder }),
					effects.press,
					effects.release,
					effects.selection,
					effects.custom,
					text("Heading", "Compare feedback timing", "heading"),
					text(
						"Introduction",
						"Try a press, a completed click, a selection and a custom double pulse. This demo opts in to haptics; turn it off to compare the same controls without feedback."
					),
					UI.Toggle "PlayHaptics" { value = playHaptics, label = "Play haptics" },
					text("Status", state, "caption"),
					text(
						"Evidence",
						"The log records requests. It cannot confirm what a device’s motors played; unsupported hardware may remain silent.",
						"caption"
					),
					row(
						"PressRow",
						"1. Press",
						"Feedback starts when the button is pressed, before release.",
						Compose.show(playHaptics, function()
							return pressButton(effects.press)
						end, function()
							return pressButton(nil)
						end)
					),
					row(
						"ReleaseRow",
						"2. Completed click",
						"Press, drag outside and release to cancel. Only a completed click requests feedback.",
						UI.Button "Release" {
							label = "Complete a click",
							onActivate = function()
								record("release")
							end,
						}
					),
					row(
						"SelectionRow",
						"3. Selection",
						"A short hover pulse accompanies each accepted selection change.",
						UI.Toggle "Selection" {
							value = selected,
							label = "Selected",
							onChange = function(value)
								selected:set(value)
								record("selection")
							end,
						}
					),
					row(
						"StrengthRow",
						"4. Custom double pulse",
						"Adjust the strength, then compare the two-pulse pattern with the buttons above.",
						UI.Slider "Strength" {
							value = strength,
							min = 0,
							max = 1,
							step = 0.1,
							label = "Pulse strength",
						}
					),
					UI.Button "Custom" {
						label = "Play double pulse",
						onActivate = function()
							record("custom")
						end,
					},
					text("History", historyText, "caption"),
				}
			end,
		}
	end,
}
