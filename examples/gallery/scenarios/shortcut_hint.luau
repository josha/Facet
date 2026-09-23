--!strict

return {
	title = "Keys and labels",
	build = function(ctx)
		local Facet, UI, Compose = ctx.Facet, ctx.UI, ctx.Compose
		local Host = ctx.Host
		local Compose = ctx.Compose
		local nativeTypes = ctx.types or { UDim = UDim, UDim2 = UDim2, Vector2 = Vector2, Color3 = Color3, Enum = Enum }
		local UDim, UDim2, Vector2, Color3, Enum =
			nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Vector2, nativeTypes.Color3, nativeTypes.Enum
		local rung, separator, title = Compose.cell("regular"), Compose.cell("or"), Compose.cell("Saved")
		local guide = Compose.cell(false)
		local key = Compose.cell(nil)
		local liveAction = Host.InputAction({
			Name = "Activate",
			Type = Enum.InputActionType.Bool,
			Host.InputBinding({ KeyCode = Enum.KeyCode.Return }),
			Host.InputBinding({ KeyCode = Enum.KeyCode.ButtonA }),
		})
		local customAction = Host.InputAction({
			Name = "RecipeCommand",
			Type = Enum.InputActionType.Bool,
			Compose.show(key, function()
				return Host.InputBinding({
					KeyCode = function(use)
						return Enum.KeyCode[use(key)]
					end,
				})
			end),
		})
		Host.InputContext({
			Name = "ShortcutRecipe",
			Parent = ctx.inputTarget,
			Enabled = true,
			liveAction,
			customAction,
		})
		local function report()
			return { binding = key:peek(), title = title:peek(), guideVisible = guide:peek(), controlSize = rung:peek() }
		end
		local function binding(value)
			key:set(value)
			return report()
		end
		local function section()
			local root = Host.Frame({
				Name = "HintRecipe",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Host.UIListLayout({
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 16),
				}),
				UI.Label({
					LayoutOrder = 1,
					Name = "Title",
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Text = "Keys and labels",
					TextSize = 22,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				UI.Label({
					LayoutOrder = 2,
					Name = "Note",
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Text = "Hints describe a shortcut. They do not take focus or claim its key.",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				Host.Frame({
					LayoutOrder = 3,
					Name = "Size",
					BackgroundTransparency = 1,
					Size = UDim2.new(0, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.XY,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 8),
						Wraps = true,
					}),
					UI.Button({
						LayoutOrder = 1,
						Name = "Compact",
						label = "Compact",
						onActivate = function()
							rung:set("compact")
						end,
					}),
					UI.Button({
						LayoutOrder = 2,
						Name = "Large",
						label = "Large",
						onActivate = function()
							rung:set("large")
						end,
					}),
					UI.Button({
						LayoutOrder = 3,
						Name = "Rename",
						label = "Update label",
						onActivate = function()
							title:set("Lap saved")
						end,
					}),
				}),
				UI.Label({
					LayoutOrder = 4,
					Name = "LiveHeading",
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Text = "This surface's action",
					TextSize = 16,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				UI.ShortcutHint({
					LayoutOrder = 5,
					Name = "Live",
					action = liveAction,
					controlSize = rung,
				}),
				UI.Label({
					LayoutOrder = 6,
					Name = "ExplicitHeading",
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Text = "Alternatives, with a localized joining word",
					TextSize = 16,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				UI.ShortcutHint({
					LayoutOrder = 7,
					Name = "Explicit",
					keys = { { "K" }, { "F1" } },
					separator = separator,
					controlSize = rung,
				}),
				UI.Label({ LayoutOrder = 8, Name = "BoundLabel", label = title, icon = "checkmark" }),
				UI.Label({
					LayoutOrder = 9,
					Name = "CustomHeading",
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Text = "A binding can arrive after its hint",
					TextSize = 16,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				UI.ShortcutHint({
					LayoutOrder = 10,
					Name = "Custom",
					action = customAction,
					controlSize = rung,
				}),
				Host.Frame({
					LayoutOrder = 11,
					Name = "Bindings",
					BackgroundTransparency = 1,
					Size = UDim2.new(0, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.XY,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 8),
						Wraps = true,
					}),
					UI.Button({
						LayoutOrder = 1,
						Name = "Bind",
						label = "Bind Enter",
						onActivate = function()
							binding("Return")
						end,
					}),
					UI.Button({
						LayoutOrder = 2,
						Name = "Rebind",
						label = "Rebind R",
						onActivate = function()
							binding("R")
						end,
					}),
					UI.Button({
						LayoutOrder = 3,
						Name = "Unbind",
						label = "Remove binding",
						onActivate = function()
							binding(nil)
						end,
					}),
				}),
				UI.Button({
					LayoutOrder = 12,
					Name = "OpenGuide",
					label = "Open shortcut guide",
					appearance = "link",
					onActivate = function()
						guide:set(true)
					end,
				}),
				Host.Frame({
					LayoutOrder = 13,
					Name = "Guide",
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Compose.show(guide, function()
						return UI.Label({
							Name = "GuideText",
							BackgroundTransparency = 1,
							BorderSizePixel = 0,
							Size = UDim2.new(1, 0, 0, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
							Text = "The guide is open. Your screen decides what a link opens.",
							TextWrapped = true,
							TextYAlignment = Enum.TextYAlignment.Top,
							TextXAlignment = Enum.TextXAlignment.Left,
						})
					end),
				}),
			})
			return root
		end
		return {
			section = section,
			screen = function()
				return Host.Frame({
					Name = "ShortcutHint",
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 1, 0),
					Host.UIPadding({
						PaddingTop = UDim.new(0, 16),
						PaddingBottom = UDim.new(0, 16),
						PaddingLeft = UDim.new(0, 16),
						PaddingRight = UDim.new(0, 16),
					}),
					Host.ScrollingFrame({
						Name = "Content",
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 1, 0),
						AutomaticCanvasSize = Enum.AutomaticSize.Y,
						CanvasSize = UDim2.new(),
						ScrollBarThickness = 6,
						section(),
					}),
				})
			end,
			report = report,
			steps = {
				compact = function()
					rung:set("compact")
					return report()
				end,
				large = function()
					rung:set("large")
					return report()
				end,
				localize = function()
					separator:set("ou")
					return report()
				end,
				rename = function()
					title:set("Lap saved")
					return report()
				end,
				bind = function()
					return binding("Return")
				end,
				rebind = function()
					return binding("R")
				end,
				unbind = function()
					return binding(nil)
				end,
			},
			reset = function()
				rung:set("regular")
				separator:set("or")
				title:set("Saved")
				guide:set(false)
				binding(nil)
			end,
		}
	end,
}
