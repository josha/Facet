return {
	title = "Adaptive controls",
	build = function(ctx)
		local UI, Host, Compose = ctx.UI, ctx.Host, ctx.Compose
		local UDim, UDim2, Vector2, Color3, Enum =
			ctx.types.UDim, ctx.types.UDim2, ctx.types.Vector2, ctx.types.Color3, ctx.types.Enum
		local volume, brightness, quality = Compose.cell(6), Compose.cell(40), Compose.cell("balanced")
		local advanced, vsync, telemetry = Compose.cell(false), Compose.cell(true), Compose.cell(false)
		local progress, section, saved = Compose.cell(0.35), Compose.cell("browse"), Compose.cell(false)
		local function wide(use)
			return use(ctx.viewport).width >= 900
		end
		local function columnSize(use)
			return if wide(use) then UDim2.new(0.5, -12, 0, 0) else UDim2.new(1, 0, 0, 0)
		end
		local function divider()
			return Host.Frame({
				Name = "Divider",
				Size = UDim2.new(1, 0, 0, 1),
				BackgroundColor3 = Color3.fromRGB(112, 120, 135),
				BackgroundTransparency = 0.6,
				BorderSizePixel = 0,
			})
		end
		local function label(name, text, role)
			return UI.Label({
				Name = name,
				label = text,
				textRole = role or "body",
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				TextWrapped = true,
			})
		end
		local function reset()
			volume:set(6)
			brightness:set(40)
			quality:set("balanced")
			advanced:set(false)
			vsync:set(true)
			telemetry:set(false)
			progress:set(0.35)
			saved:set(false)
		end
		local function noop() end
		local navOptions = {
			{ value = "browse", label = "Browse", icon = "menu" },
			{ value = "compose", label = "Compose", icon = "edit" },
			{ value = "more", label = "More", icon = "more" },
		}
		local function screen()
			local stats, tiles = {}, {}
			for i = 1, 12 do
				local stat = label("Stat" .. i, "S" .. i, "caption")
				ctx.runtime.decorate(stat, {
					Size = UDim2.fromOffset(72, 30),
					LayoutOrder = i,
					AutomaticSize = Enum.AutomaticSize.None,
					TextXAlignment = Enum.TextXAlignment.Center,
				})
				stat:AddTag("facet-control")
				table.insert(stats, stat)
			end
			for i, count in { "3", "9", "1", "7" } do
				local tile = Host.Frame({
					Name = "Tile" .. i,
					LayoutOrder = i,
					Size = UDim2.new(0.25, -6, 0, 44),
					UI.Badge({
						Name = "Count",
						label = count,
						Size = UDim2.fromOffset(28, 28),
						AnchorPoint = Vector2.new(1, 0),
						Position = UDim2.new(1, -6, 0, 6),
					}),
				})
				tile:AddTag("facet-control")
				table.insert(tiles, tile)
			end
			local media = Host.Frame({
				Name = "Media",
				Size = UDim2.new(1, 0, 0, 0),
				Host.UIAspectRatioConstraint({ AspectRatio = 16 / 9, DominantAxis = Enum.DominantAxis.Width }),
			})
			media:AddTag("facet-panel")
			return Host.Frame({
				Name = "AdaptiveScreen",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Host.UIPadding({
					PaddingTop = UDim.new(0, 16),
					PaddingBottom = UDim.new(0, 16),
					PaddingLeft = UDim.new(0, 16),
					PaddingRight = UDim.new(0, 16),
				}),
				Host.ScrollingFrame({
					Name = "BodyScroll",
					Size = UDim2.new(1, 0, 1, -60),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					AutomaticCanvasSize = Enum.AutomaticSize.Y,
					CanvasSize = UDim2.new(),
					ScrollBarThickness = 6,
					Host.Frame({
						Name = "Body",
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						BackgroundTransparency = 1,
						Host.UIListLayout({
							Name = "Columns",
							FillDirection = function(use)
								return if wide(use) then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
							end,
							Padding = UDim.new(0, 24),
							SortOrder = Enum.SortOrder.LayoutOrder,
						}),
						Host.Frame({
							Name = "Settings",
							Size = columnSize,
							AutomaticSize = Enum.AutomaticSize.Y,
							BackgroundTransparency = 1,
							LayoutOrder = 1,
							Host.UIListLayout({ Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
							label("Heading", "Settings", "heading"),
							divider(),
							UI.Stepper({

								Name = "Volume",
								label = "Volume",
								value = volume,
								min = 0,
								max = 10,
								step = 1,
							}),
							UI.Slider({

								Name = "Brightness",
								label = "Brightness",
								value = brightness,
								min = 0,
								max = 100,
								step = 5,
							}),
							UI.Picker({

								Name = "Quality",
								label = "Quality",
								selected = quality,
								options = {
									{ value = "performance", label = "Performance" },
									{ value = "balanced", label = "Balanced" },
									{ value = "fidelity", label = "Fidelity" },
								},
							}),
							divider(),
							label("NavHeading", "Icon segments, and the vertical rail", "caption"),
							UI.Picker({

								Name = "NavPill",
								selected = section,
								options = navOptions,
								style = "segmented",
								iconOnly = true,
							}),
							Host.Frame({

								Name = "NavRailRow",
								Size = UDim2.new(1, 0, 0, 132),
								BackgroundTransparency = 1,
								UI.Picker({
									Name = "NavRail",
									selected = section,
									options = navOptions,
									style = "segmented",
									axis = "y",
									iconOnly = true,
									Size = UDim2.fromOffset(52, 132),
								}),
								UI.Label({
									Name = "NavReadout",
									label = function(use)
										return `Selected: {use(section)} — the pill and the rail share this selection.`
									end,
									textRole = "caption",
									role = "secondary",
									TextWrapped = true,
									Position = UDim2.fromOffset(64, 0),
									Size = UDim2.new(1, -64, 1, 0),
								}),
							}),
							divider(),
							UI.DisclosureGroup({

								Name = "Advanced",
								label = "Advanced",
								description = "Optional rendering and privacy settings",
								icon = "settings",
								chevronPosition = "trailing",
								appearance = "divided",
								expanded = advanced,
								content = function()
									return Host.Frame({
										Name = "AdvancedBody",
										Size = UDim2.new(1, 0, 0, 0),
										AutomaticSize = Enum.AutomaticSize.Y,
										BackgroundTransparency = 1,
										Host.UIListLayout({
											SortOrder = Enum.SortOrder.LayoutOrder,
											Padding = UDim.new(0, 8),
										}),
										UI.Toggle({
											LayoutOrder = 1,
											Name = "Vsync",
											label = "Vertical sync",
											value = vsync,
											hint = "Keep frames aligned with the display",
										}),
										UI.Toggle({
											LayoutOrder = 2,
											Name = "Telemetry",
											label = "Share telemetry",
											value = telemetry,
											presentation = "checkbox",
											hint = "Send anonymous play statistics",
											indicatorPosition = "leading",
										}),
									})
								end,
							}),
						}),
						Host.Frame({
							Name = "Hud",
							Size = columnSize,
							AutomaticSize = Enum.AutomaticSize.Y,
							BackgroundTransparency = 1,
							LayoutOrder = 2,
							Host.UIListLayout({ Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
							label("HudHeading", "Status", "heading"),
							divider(),
							Host.Frame({

								Name = "Toolbar",
								Size = UDim2.new(1, 0, 0, 40),
								BackgroundTransparency = 1,
								UI.Button({
									Name = "TbBack",
									label = "Back",
									Size = UDim2.fromOffset(76, 40),
									onActivate = noop,
								}),
								UI.Button({
									Name = "TbPlay",
									label = "Play",
									Position = UDim2.fromOffset(84, 0),
									Size = UDim2.fromOffset(80, 40),
									onActivate = function()
										progress:set(math.min(1, progress:peek() + 0.1))
									end,
								}),
								UI.Button({
									Name = "TbMore",
									label = "More",
									icon = "more",
									AnchorPoint = Vector2.new(1, 0),
									Position = UDim2.fromScale(1, 0),
									Size = UDim2.fromOffset(80, 40),
									onActivate = noop,
								}),
							}),
							Host.Frame({

								Name = "CompactRow",
								Size = UDim2.new(1, 0, 0, 40),
								BackgroundTransparency = 1,
								Host.UIListLayout({
									SortOrder = Enum.SortOrder.LayoutOrder,
									FillDirection = Enum.FillDirection.Horizontal,
									Padding = UDim.new(0, 6),
								}),
								UI.Button({
									LayoutOrder = 1,
									Name = "CmpRoomy",
									label = "Edit item",
									Size = UDim2.new(1, -174, 0, 40),
									onActivate = noop,
								}),
								UI.Button({
									LayoutOrder = 2,
									Name = "CmpText",
									label = "Ed",
									Size = UDim2.fromOffset(52, 40),
									onActivate = noop,
								}),
								UI.Button({
									LayoutOrder = 3,
									Name = "CmpIcon",
									label = "Edit",
									icon = "edit",
									Size = UDim2.fromOffset(52, 40),
									onActivate = noop,
								}),
								UI.Button({
									LayoutOrder = 4,
									Name = "CmpNone",
									label = "Edit item",
									TextTruncate = Enum.TextTruncate.AtEnd,
									Size = UDim2.fromOffset(52, 40),
									onActivate = noop,
								}),
							}),
							UI.ProgressView({

								Name = "Download",
								label = "Download",
								value = progress,
								showValue = true,
							}),
							label("SaveLabel", function(use)
								return if use(saved) then "Settings saved." else "Save changes"
							end),
							media,
							Host.Frame({

								Name = "Stats",
								Size = UDim2.new(1, 0, 0, 0),
								AutomaticSize = Enum.AutomaticSize.Y,
								BackgroundTransparency = 1,
								Host.UIGridLayout({
									SortOrder = Enum.SortOrder.LayoutOrder,
									CellSize = UDim2.fromOffset(72, 30),
									LayoutOrder = i,
									CellPadding = UDim2.fromOffset(4, 4),
								}),
								table.unpack(stats),
							}),
							Host.Frame({

								Name = "Tiles",
								Size = UDim2.new(1, 0, 0, 44),
								BackgroundTransparency = 1,
								Host.UIListLayout({
									SortOrder = Enum.SortOrder.LayoutOrder,
									FillDirection = Enum.FillDirection.Horizontal,
									Padding = UDim.new(0, 8),
								}),
								table.unpack(tiles),
							}),
							divider(),
							label("VocabHeading", "Layout vocabulary", "heading"),
							Host.Frame({

								Name = "Legend",
								Size = UDim2.new(1, 0, 0, 24),
								BackgroundTransparency = 1,
								Host.UIGridLayout({
									SortOrder = Enum.SortOrder.LayoutOrder,
									CellSize = UDim2.new(1 / 3, -4, 1, 0),
									CellPadding = UDim2.fromOffset(6, 0),
								}),
								label("LegendLow", "Optional", "caption"),
								label("LegendMid", "Useful", "caption"),
								label("LegendHigh", "Essential", "caption"),
							}),
							Host.Frame({

								Name = "Shrink",
								Size = UDim2.new(1, 0, 0, 24),
								BackgroundTransparency = 1,
								Host.UIListLayout({
									SortOrder = Enum.SortOrder.LayoutOrder,
									FillDirection = Enum.FillDirection.Horizontal,
									HorizontalFlex = Enum.UIFlexAlignment.Fill,
									Padding = UDim.new(0, 6),
								}),
								Host.Frame({
									LayoutOrder = 1,
									Name = "Optional",
									Size = UDim2.fromOffset(140, 24),
									BackgroundColor3 = Color3.fromRGB(55, 75, 115),
									Host.UIFlexItem({ FlexMode = Enum.UIFlexMode.Shrink, ShrinkRatio = 2 }),
								}),
								Host.Frame({
									LayoutOrder = 2,
									Name = "Useful",
									Size = UDim2.fromOffset(140, 24),
									BackgroundColor3 = Color3.fromRGB(70, 90, 130),
									Host.UIFlexItem({ FlexMode = Enum.UIFlexMode.Shrink, ShrinkRatio = 1 }),
								}),
								Host.Frame({
									LayoutOrder = 3,
									Name = "Essential",
									Size = UDim2.fromOffset(140, 16),
									BackgroundColor3 = Color3.fromRGB(85, 110, 155),
									Host.UIFlexItem({ FlexMode = Enum.UIFlexMode.None }),
								}),
							}),
							label("SpecTitle", "Row grid", "caption"),
							Host.Frame({

								Name = "Specs",
								Size = UDim2.new(1, 0, 0, 48),
								BackgroundTransparency = 1,
								Host.UIGridLayout({
									SortOrder = Enum.SortOrder.LayoutOrder,
									CellSize = UDim2.new(0.5, -4, 0, 24),
									CellPadding = UDim2.fromOffset(8, 0),
								}),
								label("SpecAKey", "Columns", "caption"),
								label("SpecAVal", "align", "caption"),
								label("SpecBKey", "Span", "caption"),
								label("SpecBVal", "the header", "caption"),
							}),
						}),
					}),
				}),
				Host.Frame({
					Name = "Actions",
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.fromScale(0.5, 1),
					Size = UDim2.new(1, 0, 0, 44),
					BackgroundTransparency = 1,
					Host.UISizeConstraint({ MaxSize = Vector2.new(620, 44) }),
					Host.UIGridLayout({
						SortOrder = Enum.SortOrder.LayoutOrder,
						CellSize = UDim2.new(1 / 3, -6, 1, 0),
						CellPadding = UDim2.fromOffset(8, 0),
					}),
					UI.Button({
						LayoutOrder = 1,
						Name = "Save",
						label = "Save changes",
						onActivate = function()
							saved:set(true)
						end,
					}),
					UI.Button({
						LayoutOrder = 2,
						Name = "Reset",
						label = "Reset to defaults",
						role = "cancel",
						onActivate = reset,
					}),
					UI.Button({
						LayoutOrder = 3,
						Name = "Delete",
						label = "Delete profile",
						role = "destructive",
						onActivate = function()
							reset()
						end,
					}),
				}),
			})
		end
		return {
			screen = screen,
			reset = reset,
			report = function()
				return {
					volume = volume:peek(),
					brightness = brightness:peek(),
					quality = quality:peek(),
					progress = progress:peek(),
					advanced = advanced:peek(),
					vsync = vsync:peek(),
					telemetry = telemetry:peek(),
					saved = saved:peek(),
					nav = section:peek(),
				}
			end,
		}
	end,
}
