--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type ControlSize = typeof(require("@repo/tools/typecheck/aliases").ControlSize)
type ControlSizeValue = typeof(require("@repo/tools/typecheck/aliases").ControlSizeValue)
type OptionalStringCell = typeof(require("@repo/tools/typecheck/aliases").OptionalStringCell)
type ReadOnlyValue<T> = { peek: (ReadOnlyValue<T>) -> T }
type Use = <T>(ReadOnlyValue<T>) -> T
type ExampleContext = typeof(require("@repo/examples/types").Context)
type Built = typeof(require("@repo/examples/types").Built)

return {
	title = "Keys and labels",
	build = function(ctx: ExampleContext): Built
		local Facet, UI, Compose: ComposeModule = ctx.Facet, ctx.UI, ctx.Compose
		local Host = ctx.Host
		local Compose: ComposeModule = ctx.Compose
		local nativeTypes = ctx.types
		local UDim, UDim2, Vector2, Color3, Enum =
			nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Vector2, nativeTypes.Color3, nativeTypes.Enum
		local initialRung: ControlSizeValue? = "regular"
		local rung: ControlSize, separator, title = Compose.cell(initialRung), Compose.cell("or"), Compose.cell("Saved")
		local guide = Compose.cell(false)
		local function bindingCell(value: string?): OptionalStringCell
			return Compose.cell(value)
		end
		local key = bindingCell(nil)
		local liveAction = Host.InputAction("Activate")({
			Type = Enum.InputActionType.Bool,
			Host.InputBinding({ KeyCode = Enum.KeyCode.Return }),
			Host.InputBinding({ KeyCode = Enum.KeyCode.ButtonA }),
		})
		local customAction = Host.InputAction("RecipeCommand")({
			Type = Enum.InputActionType.Bool,
			Compose.show(key, function()
				return Host.InputBinding({
					KeyCode = function(use: Use)
						return assert(Enum.KeyCode:FromName(assert(use(key))))
					end,
				})
			end),
		})
		Host.InputContext("ShortcutRecipe")({
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
			local root = Host.Frame("HintRecipe")({
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Host.UIListLayout({
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 16),
				}),
				UI.Text "Title" {
					LayoutOrder = 1,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = "Keys and labels",
					textRole = "heading",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				},
				UI.Text "Note" {
					LayoutOrder = 2,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = "Hints describe a shortcut. They do not take focus or claim its key.",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				},
				Host.Frame("Size")({
					LayoutOrder = 3,
					BackgroundTransparency = 1,
					Size = UDim2.new(0, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.XY,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 8),
						Wraps = true,
					}),
					UI.Button "Compact" {
						LayoutOrder = 1,
						label = "Compact",
						onActivate = function()
							rung:set("compact")
						end,
					},
					UI.Button "Large" {
						LayoutOrder = 2,
						label = "Large",
						onActivate = function()
							rung:set("large")
						end,
					},
					UI.Button "Rename" {
						LayoutOrder = 3,
						label = "Update label",
						onActivate = function()
							title:set("Lap saved")
						end,
					},
				}),
				UI.Text "LiveHeading" {
					LayoutOrder = 4,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = "This surface's action",
					textRole = "body",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				},
				UI.ShortcutHint "Live" {
					LayoutOrder = 5,
					action = liveAction,
					controlSize = rung,
				},
				UI.Text "ExplicitHeading" {
					LayoutOrder = 6,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = "Alternatives, with a localized joining word",
					textRole = "body",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				},
				UI.ShortcutHint "Explicit" {
					LayoutOrder = 7,
					keys = { { "K" }, { "F1" } },
					separator = separator,
					controlSize = rung,
				},
				UI.ShortcutHint "Labelled" {
					LayoutOrder = 7,
					keys = { { "M" } },
					controlSize = rung,
					label = "Open the map",
				},
				UI.Label "BoundLabel" { LayoutOrder = 8, title = title, icon = "checkmark" },
				UI.Text "CustomHeading" {
					LayoutOrder = 9,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = "A binding can arrive after its hint",
					textRole = "body",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				},
				UI.ShortcutHint "Custom" {
					LayoutOrder = 10,
					action = customAction,
					controlSize = rung,
				},
				Host.Frame("Bindings")({
					LayoutOrder = 11,
					BackgroundTransparency = 1,
					Size = UDim2.new(0, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.XY,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 8),
						Wraps = true,
					}),
					UI.Button "Bind" {
						LayoutOrder = 1,
						label = "Bind Enter",
						onActivate = function()
							binding("Return")
						end,
					},
					UI.Button "Rebind" {
						LayoutOrder = 2,
						label = "Rebind R",
						onActivate = function()
							binding("R")
						end,
					},
					UI.Button "Unbind" {
						LayoutOrder = 3,
						label = "Remove binding",
						onActivate = function()
							binding(nil)
						end,
					},
				}),
				UI.Button "OpenGuide" {
					LayoutOrder = 12,
					label = "Open shortcut guide",
					appearance = "link",
					onActivate = function()
						guide:set(true)
					end,
				},
				Host.Frame({
					LayoutOrder = 13,
					Name = "Guide",
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Compose.show(guide, function()
						return UI.Text "GuideText" {
							BackgroundTransparency = 1,
							BorderSizePixel = 0,
							Size = UDim2.new(1, 0, 0, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
							text = "The guide is open. Your screen decides what a link opens.",
							TextWrapped = true,
							TextYAlignment = Enum.TextYAlignment.Top,
							TextXAlignment = Enum.TextXAlignment.Left,
						}
					end),
				}),
			})
			return root
		end
		return {
			section = section,
			screen = function()
				return Host.Frame("ShortcutHint")({
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 1, 0),
					UI.ScrollView "Content" {
						padding = 16,
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 1, 0),
						ScrollBarThickness = 6,
						section(),
					},
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
