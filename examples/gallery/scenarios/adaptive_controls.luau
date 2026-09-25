return {
	title = "Adaptive controls",
	build = function(ctx)
		local UI, Host, Compose = ctx.UI, ctx.Host, ctx.Compose
		local UDim, UDim2, Vector2, Color3, Enum =
			ctx.types.UDim, ctx.types.UDim2, ctx.types.Vector2, ctx.types.Color3, ctx.types.Enum
		local volume, brightness, quality = Compose.cell(6), Compose.cell(40), Compose.cell("balanced")
		local advanced, vsync, telemetry = Compose.cell(false), Compose.cell(true), Compose.cell(false)
		local outlineOpen = Compose.cell(true)
		local progress, section, saved = Compose.cell(0.35), Compose.cell("browse"), Compose.cell(false)
		local TILT_ANGLES = { 0, 45, 90, 135, 180, 225, 270, 315 }
		local lapWindow = Compose.cell({ lower = 4, upper = 12 })
		local tiltBand = Compose.cell({ lower = 20, upper = 70 })
		local tilt, balance, boost = Compose.cell(0), Compose.cell(50), Compose.cell(35)
		local camera, steer = Compose.cell(60), Compose.cell(50)
		local function wide(use)
			return use(ctx.viewport).width >= 900
		end
		local function columnSize(use)
			return if wide(use) then UDim2.new(0.5, -12, 0, 0) else UDim2.new(1, 0, 0, 0)
		end
		local function divider()
			return Host.Frame "Divider" {
				Size = UDim2.new(1, 0, 0, 1),
				BackgroundColor3 = Color3.fromRGB(112, 120, 135),
				BackgroundTransparency = 0.6,
				BorderSizePixel = 0,
			}
		end
		local function strongDivider()
			local edge = Host.Frame "PaneEdge" { Size = UDim2.new(1, 0, 0, 1), BorderSizePixel = 0 }
			edge:AddTag("facet-divider")
			edge:AddTag("facet-divider-strong")
			return edge
		end
		local function label(name, text, role)
			return UI.Text({
				Name = name,
				text = text,
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
			lapWindow:set({ lower = 4, upper = 12 })
			tiltBand:set({ lower = 20, upper = 70 })
			tilt:set(0)
			balance:set(50)
			boost:set(35)
			camera:set(60)
			steer:set(50)
		end
		local function sliderShapes()
			return Host.Frame "SliderShapes" {
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Host.UIListLayout({ Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
				label("SlidersHeading", "Slider shapes", "heading"),
				UI.Slider "LapWindow" {
					LayoutOrder = 2,
					label = "Laps",
					value = lapWindow,
					min = 1,
					max = 20,
					step = 1,
					range = true,
					minGap = 2,
				},
				UI.Text "TiltCaption" {
					LayoutOrder = 3,
					text = "Tilt (a turned range)",
					textRole = "caption",
					role = "secondary",
				},
				Host.Frame "TiltStage" {
					LayoutOrder = 4,
					Size = UDim2.new(1, 0, 0, 160),
					BackgroundTransparency = 1,
					UI.Slider "Tilt" {
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.5),
						Size = UDim2.new(0.6, 0, 0, 0),
						value = tiltBand,
						min = 0,
						max = 100,
						step = 10,
						range = true,
						minGap = 10,
						rotation = tilt,
					},
				},
				Host.Frame "BalanceRow" {
					LayoutOrder = 5,
					Size = UDim2.new(1, 0, 0, 180),
					BackgroundTransparency = 1,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Horizontal,
						Padding = UDim.new(0, 16),
						VerticalAlignment = Enum.VerticalAlignment.Center,
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
					UI.Slider "Balance" {
						LayoutOrder = 1,
						label = "Rear",
						value = balance,
						min = 0,
						max = 100,
						step = 5,
						axis = "y",
					},
					UI.Text "BalanceNote" {
						LayoutOrder = 2,
						text = "Rear bias runs bottom to top, and Up raises it.",
						textRole = "caption",
						role = "secondary",
						TextWrapped = true,
						Size = UDim2.new(1, -80, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
					},
				},
				UI.Slider "Boost" {
					LayoutOrder = 6,
					label = "Boost",
					value = boost,
					min = 0,
					max = 100,
					step = 5,
					thumb = "auto",
					controlSize = "compact",
				},
				UI.Slider "Camera" {
					LayoutOrder = 7,
					label = "Camera",
					value = camera,
					min = 0,
					max = 100,
					step = 5,
					thumb = "none",
				},
				UI.Slider "Steer" {
					LayoutOrder = 8,
					label = "Steer",
					value = steer,
					min = 0,
					max = 100,
					step = 10,
					thumbContent = function()
						return Host.Frame "Knob" {
							Size = UDim2.fromOffset(24, 24),
							BackgroundTransparency = 1,
							Host.Frame "Plate" {
								Size = UDim2.fromScale(1, 1),
								Host.UICorner({ CornerRadius = UDim.new(1, 0) }),
							},
							UI.Path "Mark" {
								points = {
									{ x = 0.5, y = 0.15, inX = 0, inY = 0, outX = 0, outY = 0 },
									{ x = 0.9, y = 0.85, inX = 0, inY = 0, outX = 0, outY = 0 },
									{ x = 0.1, y = 0.85, inX = 0, inY = 0, outX = 0, outY = 0 },
								},
								closed = true,
								thickness = 2,
								width = 12,
								AnchorPoint = Vector2.new(0.5, 0.5),
								Position = UDim2.fromScale(0.5, 0.5),
							},
						}
					end,
				},
			}
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
					BackgroundTransparency = 0,
				})
				stat:AddTag("facet-control")
				table.insert(stats, stat)
			end
			for i, count in { "3", "9", "1", "7" } do
				local tile = Host.Frame({
					Name = "Tile" .. i,
					LayoutOrder = i,
					Size = UDim2.new(0.25, -6, 0, 44),
					UI.Badge "Count" {
						label = count,
						status = "info",
						Size = UDim2.fromOffset(28, 28),
						AnchorPoint = Vector2.new(1, 0),
						Position = UDim2.new(1, -6, 0, 6),
					},
				})
				tile:AddTag("facet-control")
				table.insert(tiles, tile)
			end
			local media = Host.Frame "Media" {
				Size = UDim2.new(1, 0, 0, 0),
				Host.UIAspectRatioConstraint({ AspectRatio = 16 / 9, DominantAxis = Enum.DominantAxis.Width }),
			}
			media:AddTag("facet-panel")
			return Host.Frame "AdaptiveScreen" {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Host.UIPadding({
					PaddingTop = UDim.new(0, 16),
					PaddingBottom = UDim.new(0, 16),
					PaddingLeft = UDim.new(0, 16),
					PaddingRight = UDim.new(0, 16),
				}),
				Host.ScrollingFrame "BodyScroll" {
					Size = UDim2.new(1, 0, 1, -60),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					AutomaticCanvasSize = Enum.AutomaticSize.Y,
					CanvasSize = UDim2.new(),
					ScrollBarThickness = 4,
					ScrollBarImageTransparency = 0.4,
					VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
					Host.UIListLayout({ SortOrder = Enum.SortOrder.LayoutOrder }),
					Host.Frame "Body" {
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						BackgroundTransparency = 1,
						Host.UIListLayout "Columns" {
							FillDirection = function(use)
								return if wide(use) then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
							end,
							Padding = UDim.new(0, 24),
							SortOrder = Enum.SortOrder.LayoutOrder,
						},
						Host.Frame "Settings" {
							Size = columnSize,
							AutomaticSize = Enum.AutomaticSize.Y,
							BackgroundTransparency = 1,
							LayoutOrder = 1,
							Host.UIListLayout({ Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
							label("Heading", "Settings", "heading"),
							divider(),
							UI.Stepper "Volume" {
								label = "Volume",
								value = volume,
								min = 0,
								max = 10,
								step = 1,
							},
							UI.Slider "Brightness" {
								label = "Brightness",
								value = brightness,
								min = 0,
								max = 100,
								step = 5,
							},
							sliderShapes(),
							UI.Picker "Quality" {
								label = "Quality",
								selected = quality,
								options = {
									{ value = "performance", label = "Performance" },
									{ value = "balanced", label = "Balanced" },
									{ value = "fidelity", label = "Fidelity" },
								},
							},
							divider(),
							label("NavHeading", "Icon segments, and the vertical rail", "caption"),
							UI.Picker "NavPill" {
								selected = section,
								options = navOptions,
								style = "segmented",
								iconOnly = true,
							},
							Host.Frame "NavRailRow" {
								Size = UDim2.new(1, 0, 0, 132),
								BackgroundTransparency = 1,
								UI.Picker "NavRail" {
									selected = section,
									options = navOptions,
									style = "segmented",
									axis = "y",
									iconOnly = true,
									Size = UDim2.fromOffset(52, 132),
								},
								UI.Text "NavReadout" {
									text = function(use)
										return `Selected: {use(section)} — the pill and the rail share this selection.`
									end,
									textRole = "caption",
									role = "secondary",
									TextWrapped = true,
									Position = UDim2.fromOffset(64, 0),
									Size = UDim2.new(1, -64, 1, 0),
								},
							},
							divider(),
							UI.DisclosureGroup "Advanced" {
								label = "Advanced",
								description = "Optional rendering and privacy settings",
								icon = "settings",
								chevronPosition = "trailing",
								appearance = "divided",
								expanded = advanced,
								content = function()
									return Host.Frame "AdvancedBody" {
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
									}
								end,
							},
							strongDivider(),
							UI.DisclosureGroup "Outline" {
								label = "Components",
								appearance = "outline",
								textSize = "label",
								indent = "m",
								expanded = outlineOpen,
								content = function()
									return Host.Frame "OutlineRows" {
										Size = UDim2.new(1, 0, 0, 0),
										AutomaticSize = Enum.AutomaticSize.Y,
										BackgroundTransparency = 1,
										Host.UIListLayout({ SortOrder = Enum.SortOrder.LayoutOrder }),
										UI.Button "OutlineButton" {
											LayoutOrder = 1,
											label = "Button",
											appearance = "link",
											underline = "hover",
										},
										UI.Button "OutlineChip" {
											LayoutOrder = 2,
											label = "Chip",
											appearance = "link",
											underline = "hover",
										},
									}
								end,
							},
						},
						Host.Frame "Hud" {
							Size = columnSize,
							AutomaticSize = Enum.AutomaticSize.Y,
							BackgroundTransparency = 1,
							LayoutOrder = 2,
							Host.UIListLayout({ Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
							label("HudHeading", "Status", "heading"),
							divider(),
							Host.Frame "Toolbar" {
								Size = UDim2.new(1, 0, 0, 40),
								BackgroundTransparency = 1,
								UI.Button "TbBack" {
									label = "Back",
									Size = UDim2.fromOffset(76, 40),
									onActivate = noop,
								},
								UI.Button "TbPlay" {
									label = "Play",
									Position = UDim2.fromOffset(84, 0),
									Size = UDim2.fromOffset(80, 40),
									onActivate = function()
										progress:set(math.min(1, progress:peek() + 0.1))
									end,
								},
								UI.Button "TbMore" {
									label = "More",
									icon = "more",
									AnchorPoint = Vector2.new(1, 0),
									Position = UDim2.fromScale(1, 0),
									Size = UDim2.fromOffset(80, 40),
									onActivate = noop,
								},
							},
							Host.Frame "CompactRow" {
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
							},
							UI.ProgressView "Download" {
								label = "Download",
								value = progress,
								showValue = true,
							},
							label("SaveLabel", function(use)
								return if use(saved) then "Settings saved." else "Save changes"
							end),
							media,
							Host.Frame "Stats" {
								Size = UDim2.new(1, 0, 0, 0),
								AutomaticSize = Enum.AutomaticSize.Y,
								BackgroundTransparency = 1,
								Host.UIGridLayout({
									SortOrder = Enum.SortOrder.LayoutOrder,
									CellSize = UDim2.fromOffset(72, 30),
									CellPadding = UDim2.fromOffset(4, 4),
								}),
								table.unpack(stats),
							},
							Host.Frame "Tiles" {
								Size = UDim2.new(1, 0, 0, 44),
								BackgroundTransparency = 1,
								Host.UIListLayout({
									SortOrder = Enum.SortOrder.LayoutOrder,
									FillDirection = Enum.FillDirection.Horizontal,
									Padding = UDim.new(0, 8),
								}),
								table.unpack(tiles),
							},
							divider(),
							label("VocabHeading", "Layout vocabulary", "heading"),
							Host.Frame "Legend" {
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
							},
							Host.Frame "Shrink" {
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
							},
							label("SpecTitle", "Row grid", "caption"),
							Host.Frame "Specs" {
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
							},
						},
					},
				},
				Host.Frame "Actions" {
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
						compactLabel = "Save",
						onActivate = function()
							saved:set(true)
						end,
					}),
					UI.Button({
						LayoutOrder = 2,
						Name = "Reset",
						label = "Reset to defaults",
						compactLabel = "Reset",
						role = "cancel",
						onActivate = reset,
					}),
					UI.Button({
						LayoutOrder = 3,
						Name = "Delete",
						label = "Delete profile",
						compactLabel = "Delete",
						role = "destructive",
						onActivate = function()
							reset()
						end,
					}),
				},
			}
		end
		return {
			screen = screen,
			reset = reset,
			steps = {
				sliderBand = function()
					local current = lapWindow:peek()
					lapWindow:set(if current.lower == 4 then { lower = 2, upper = 18 } else { lower = 4, upper = 12 })
					return { band = `{lapWindow:peek().lower}-{lapWindow:peek().upper}` }
				end,
				sliderTilt = function()
					local at = table.find(TILT_ANGLES, tilt:peek()) or 1
					tilt:set(TILT_ANGLES[(at % #TILT_ANGLES) + 1])
					return { degrees = tilt:peek() }
				end,
				sliderAxis = function()
					balance:set(if balance:peek() >= 90 then 10 else 90)
					return { rear = balance:peek() }
				end,
			},
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
					band = lapWindow:peek(),
					tiltBand = tiltBand:peek(),
					tilt = tilt:peek(),
					rear = balance:peek(),
					boost = boost:peek(),
					camera = camera:peek(),
					steer = steer:peek(),
				}
			end,
		}
	end,
}
