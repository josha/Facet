local WRAP_TAGS = { "Rain", "Dust", "Night", "Mirror", "Reverse", "Elimination" }
local RAIL_TAGS = {
	"Sprint",
	"Endurance",
	"Elimination",
	"Time Trial",
	"Drift Event",
	"Reverse Grid",
	"Night Race",
	"Wet Weather",
	"Ghost Lap",
	"Custom Rules",
}

return {
	title = "Recipes",
	build = function(ctx: any)
		local Facet, UI, Compose = ctx.Facet, ctx.UI, ctx.Compose
		local Host = ctx.Host
		local Compose = ctx.Compose
		local nativeTypes = ctx.types or { UDim = UDim, UDim2 = UDim2, Vector2 = Vector2, Color3 = Color3, Enum = Enum }
		local UDim, UDim2, Vector2, Color3, Enum =
			nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Vector2, nativeTypes.Color3, nativeTypes.Enum
		local actionsCap = Compose.cell(700)
		local actionsWidth = Compose.cell(0)
		local actionWidths = { Compose.cell(0), Compose.cell(0), Compose.cell(0) }
		local actionsHorizontal = Compose.formula(function(use)
			local required = 16
			for _, width in actionWidths do
				local measured = use(width)
				if measured <= 0 then
					return false
				end
				required += measured + 24
			end
			return required <= math.min(use(actionsCap), use(actionsWidth))
		end)
		local checks = Compose.cell({ tires = true })
		local acceptChecks, enabled = Compose.cell(true), Compose.cell(true)
		local requests, activations = Compose.cell(0), Compose.cell(0)
		local wrapTags, railTags = Compose.cell(WRAP_TAGS), Compose.cell(RAIL_TAGS)
		local wrapSelected, railSelected = {}, {}
		for _, tag in WRAP_TAGS do
			wrapSelected[tag] = Compose.cell(false)
		end
		for _, tag in RAIL_TAGS do
			railSelected[tag] = Compose.cell(false)
		end
		local retryCount, createCount, clearCount = Compose.cell(0), Compose.cell(0), Compose.cell(0)
		local expanded = { Rules = Compose.cell(false), Setup = Compose.cell(false), Rewards = Compose.cell(false) }
		local function selected(cells)
			local result = {}
			for id, cell in cells do
				result[id] = cell:peek()
			end
			return result
		end
		local function report()
			local openSection
			for id, cell in expanded do
				if cell:peek() then
					openSection = id
				end
			end
			return {
				actionsCap = actionsCap:peek(),
				actionsForm = if actionsHorizontal:peek() then "row" else "column",
				checks = checks:peek(),
				requests = requests:peek(),
				activations = activations:peek(),
				wrapSelected = selected(wrapSelected),
				railSelected = selected(railSelected),
				openSection = openSection,
				retryCount = retryCount:peek(),
				createCount = createCount:peek(),
				clearCount = clearCount:peek(),
			}
		end

		local function heading(id: string, text: string): any
			return UI.Label({
				Name = id,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				text = text,
				textRole = "title",
				TextWrapped = true,
				TextYAlignment = Enum.TextYAlignment.Top,
				TextXAlignment = Enum.TextXAlignment.Left,
			})
		end
		local function note(id: string, text: string): any
			return UI.Label({
				Name = id,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				text = text,
				textRole = "caption",
				TextWrapped = true,
				TextYAlignment = Enum.TextYAlignment.Top,
				TextXAlignment = Enum.TextXAlignment.Left,
			})
		end
		local function emptyState(
			id: string,
			opts: {
				icon: string?,
				iconLabel: string?,
				title: string,
				message: string,
				actionLabel: string,
				onAction: () -> (),
			}
		): any
			local children: { any } = {}
			if opts.icon ~= nil then
				table.insert(
					children,
					UI.Label "Icon" {
						text = opts.iconLabel or opts.title,
						icon = opts.icon,
					}
				)
			end
			table.insert(
				children,
				UI.Label "Title" {
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = opts.title,
					textRole = "heading",
					TextXAlignment = Enum.TextXAlignment.Center,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
				}
			)
			table.insert(
				children,
				UI.Label "Message" {
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = opts.message,
					TextXAlignment = Enum.TextXAlignment.Center,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
				}
			)
			table.insert(
				children,
				UI.Button "Action" {
					label = opts.actionLabel,
					appearance = "soft",
					onActivate = opts.onAction,
				}
			)
			return Host.Frame({
				Name = id,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Host.UIListLayout({
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 8),
				}),
				Host.UIPadding({
					PaddingTop = UDim.new(0, 16),
					PaddingBottom = UDim.new(0, 16),
					PaddingLeft = UDim.new(0, 16),
					PaddingRight = UDim.new(0, 16),
				}),
				table.unpack(children),
			})
		end
		local function metrics(use)
			local package = if ctx.theme then use(ctx.theme) else Facet.themes.neutralPackage()
			return package.metrics
		end
		local function dividerExample(id: string, name: string, sides: any, thickness: number?): any
			local function inset(side: string)
				return function(use)
					return UDim.new(
						0,
						if type(sides) == "table" and sides[side] then metrics(use).space[sides[side]] else 0
					)
				end
			end
			local line = Host.Frame({
				LayoutOrder = 1,
				Name = "Line",
				Size = function(use)
					return UDim2.new(1, 0, 0, (thickness or 1) * metrics(use).strokes.hairline)
				end,
			})
			line:AddTag("facet-divider")
			return Host.Frame({
				Name = id,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Host.UIListLayout({
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 4),
				}),
				UI.Label({
					LayoutOrder = 1,
					Name = "Label",
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = name,
					textRole = "caption",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				Host.Frame({
					LayoutOrder = 2,
					Name = "Pad",
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Vertical,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 0),
					}),
					Host.UIPadding({
						PaddingTop = inset("top"),
						PaddingBottom = inset("bottom"),
						PaddingLeft = inset("left"),
						PaddingRight = inset("right"),
					}),
					line,
				}),
			})
		end

		local function Page()
			local function actionButton(index, id, label, role, appearance)
				local button = UI.Button({
					Name = id,
					LayoutOrder = index,
					Size = function(use)
						return if use(actionsHorizontal) then UDim2.fromOffset(0, 44) else UDim2.new(1, 0, 0, 44)
					end,
					AutomaticSize = function(use)
						return if use(actionsHorizontal) then Enum.AutomaticSize.XY else Enum.AutomaticSize.Y
					end,
					TextWrapped = true,
					label = label,
					role = role,
					appearance = appearance,
					onActivate = function()
						activations:update(function(n)
							return n + 1
						end)
					end,
					Host.UIPadding({
						PaddingLeft = UDim.new(0, 12),
						PaddingRight = UDim.new(0, 12),
						PaddingTop = UDim.new(0, 6),
						PaddingBottom = UDim.new(0, 6),
					}),
				})
				local function styled(property)
					local value = Compose.cell(button:GetStyled(property))
					local connection = button:GetStyledPropertyChangedSignal(property):Connect(function()
						value:set(button:GetStyled(property))
					end)
					Compose.cleanup(function()
						connection:Disconnect()
					end)
					return value
				end
				local release, measure = ctx.runtime.mount(function()
					return Host.TextLabel "NaturalWidth" {
						Text = label,
						Visible = false,
						TextWrapped = false,
						Size = UDim2.fromOffset(0, 0),
						AutomaticSize = Enum.AutomaticSize.XY,
						FontFace = styled("FontFace"),
						TextSize = styled("TextSize"),
					}
				end, button)
				Compose.cleanup(release)
				local function measureChanged()
					actionWidths[index]:set(measure.TextBounds.X)
				end
				local connection = measure:GetPropertyChangedSignal("TextBounds"):Connect(measureChanged)
				Compose.cleanup(function()
					connection:Disconnect()
				end)
				measureChanged()
				return button
			end
			local function actionRow()
				local row = Host.Frame "Actions" {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Host.UISizeConstraint({
						MaxSize = function(use)
							return Vector2.new(use(actionsCap), math.huge)
						end,
					}),
					Host.UIListLayout({
						FillDirection = function(use)
							return if use(actionsHorizontal)
								then Enum.FillDirection.Horizontal
								else Enum.FillDirection.Vertical
						end,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 8),
					}),
					actionButton(1, "Cancel", "Cancel", "cancel", nil),
					actionButton(2, "Save", "Save changes to this profile", nil, "emphasis"),
					actionButton(3, "Delete", "Delete profile", "destructive", "utility"),
				}
				local function resized()
					actionsWidth:set(row.AbsoluteSize.X)
				end
				local connection = row:GetPropertyChangedSignal("AbsoluteSize"):Connect(resized)
				Compose.cleanup(function()
					connection:Disconnect()
				end)
				resized()
				return row
			end
			local function accordionItem(id: string, label: string, body: string): any
				return UI.DisclosureGroup({
					Name = id,
					label = label,
					appearance = "divided",
					expanded = expanded[id],
					onToggle = function(next)
						if next then
							ctx.runtime:batch(function()
								for other, cell in expanded do
									if other ~= id then
										cell:set(false)
									end
								end
							end)
						end
					end,
					content = function()
						return UI.Label "Body" {
							BackgroundTransparency = 1,
							BorderSizePixel = 0,
							Size = UDim2.new(1, 0, 0, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
							text = body,
							TextWrapped = true,
							TextYAlignment = Enum.TextYAlignment.Top,
							TextXAlignment = Enum.TextXAlignment.Left,
						}
					end,
				})
			end
			local function checkItem(id: string, label: string, width: any?): any
				return UI.Toggle({
					Name = id,
					Size = function(use)
						return if width then UDim2.new(width.Scale, width.Offset, 0, 0) else UDim2.new(1, 0, 0, 0)
					end,
					AutomaticSize = Enum.AutomaticSize.XY,
					label = label,
					presentation = "checkbox",
					controlSize = "compact",
					indicatorPosition = "leading",
					enabled = enabled,
					value = function(use)
						return use(checks)[id] == true
					end,
					onChange = function(next)
						requests:update(function(n)
							return n + 1
						end)
						if acceptChecks:peek() then
							local copy = table.clone(checks:peek())
							copy[id] = next
							checks:set(copy)
						end
					end,
				})
			end
			local function chipItem(tag, cells)
				return UI.Chip({
					Name = tag,
					label = tag,
					selected = cells[tag],
				})
			end

			local root = Host.Frame "Page" {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Host.UIListLayout({
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 24),
				}),
				Host.UIPadding({
					PaddingTop = UDim.new(0, 16),
					PaddingBottom = UDim.new(0, 16),
					PaddingLeft = UDim.new(0, 16),
					PaddingRight = UDim.new(0, 16),
				}),
				heading("ActionRowHeading", "Action row"),
				note(
					"ActionRowNote",
					"Two or three related buttons: one line when the labels fit, a stacked column when they do not. No fixed breakpoint decides it — the row is measured."
				),
				actionRow(),
				heading("CheckboxHeading", "Checkbox group"),
				note(
					"CheckboxNote",
					"Independent settings, not a single choice. Use a Picker instead the moment only one of these can be true at a time."
				),
				Host.Frame "CheckboxGroup" {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Vertical,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 4),
					}),
					checkItem("tires", "Tire wear"),
					checkItem("fuel", "Fuel use"),
					checkItem("damage", "Damage"),
					checkItem("weather", "Weather"),
				},
				Host.Frame "WrapChecks" {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 8),
						Wraps = true,
					}),
					checkItem("tires", "Tire wear", UDim.new(0, 0)),
					checkItem("fuel", "Fuel use", UDim.new(0, 0)),
					checkItem("damage", "Damage", UDim.new(0, 0)),
					checkItem("weather", "Weather", UDim.new(0, 0)),
				},
				heading("ChipHeading", "Chip group"),
				note("ChipWrapNote", "Wraps to a new line when it runs out of room."),
				Host.Frame "WrapChips" {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 8),
						Wraps = true,
					}),
					Compose.OrderedCollection({
						from = wrapTags,
						key = function(tag: string)
							return tag
						end,
						render = function(current, placement, key)
							local tag = current:peek()
							local node = chipItem(tag, wrapSelected)
							ctx.runtime.decorate(node, {
								LayoutOrder = function(use)
									return use(placement).index
								end,
							})
							return node
						end,
					}),
				},
				note(
					"ChipRailNote",
					"One scrolling row instead, for a long list on a narrow screen. A keyboard or gamepad focus move keeps the picked chip in view with no extra wiring."
				),
				Host.ScrollingFrame "RailChips" {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					AutomaticCanvasSize = Enum.AutomaticSize.X,
					CanvasSize = UDim2.new(),
					ScrollBarThickness = 6,
					Host.Frame "Row" {
						BackgroundTransparency = 1,
						Size = UDim2.new(0, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.XY,
						Host.UIListLayout({
							FillDirection = Enum.FillDirection.Horizontal,
							SortOrder = Enum.SortOrder.LayoutOrder,
							Padding = UDim.new(0, 8),
						}),
						Compose.OrderedCollection({
							from = railTags,
							key = function(tag: string)
								return tag
							end,
							render = function(current, placement, key)
								local tag = current:peek()
								return chipItem(tag, railSelected)
							end,
						}),
					},
				},
				heading("EmptyHeading", "Empty state"),
				note(
					"EmptyNote",
					"Distinct from a loading placeholder (Skeleton — the answer has not arrived) and from an error Notice (a banner about a condition). An empty state IS the page's content when the answer is nothing."
				),
				emptyState("EmptyCollection", {
					title = "No liveries yet",
					message = "Liveries you create for this kart show up here.",
					actionLabel = "Create a livery",
					onAction = function()
						createCount:set(createCount:peek() + 1)
					end,
				}),
				emptyState("NoResults", {
					icon = "facet:search",
					iconLabel = "No matches",
					title = 'No tracks match "Sunset"',
					message = "Check the spelling, or clear the search to see every track.",
					actionLabel = "Clear search",
					onAction = function()
						clearCount:update(function(n)
							return n + 1
						end)
					end,
				}),
				emptyState("LoadFailed", {
					icon = "status.error",
					iconLabel = "Couldn't load",
					title = "Couldn't load standings",
					message = "Check your connection and try again.",
					actionLabel = "Retry",
					onAction = function()
						retryCount:set(retryCount:peek() + 1)
					end,
				}),
				heading("DividerHeading", "Divider insets"),
				dividerExample("DividerFull", "Full"),
				dividerExample("DividerLeading", "Leading inset", { left = "m" }),
				dividerExample("DividerTrailing", "Trailing inset", { right = "m" }),
				dividerExample("DividerBoth", "Leading and trailing", { left = "m", right = "m" }),
				dividerExample("DividerHeavy", "Heavy", nil, 3),
				heading("AccordionHeading", "Single-open accordion"),
				Host.Frame "Accordion" {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Vertical,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 0),
					}),
					accordionItem("Rules", "Race rules", "Standard lap count, no shortcuts, collisions on."),
					accordionItem("Setup", "Car setup", "Tire compound, gear ratio and ride height for this track."),
					accordionItem("Rewards", "Rewards", "Podium finishes bank currency toward the next kart unlock."),
				},
			}
			return root
		end
		local function reset()
			actionsCap:set(700)
			checks:set({ tires = true })
			acceptChecks:set(true)
			enabled:set(true)
			requests:set(0)
			activations:set(0)
			retryCount:set(0)
			createCount:set(0)
			clearCount:set(0)
			wrapTags:set(WRAP_TAGS)
			for _, cells in { wrapSelected, railSelected, expanded } do
				for _, cell in cells do
					cell:set(false)
				end
			end
		end
		return {
			section = Page,
			report = report,
			reset = reset,
			screen = function()
				return Host.Frame "Recipes" {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 1, 0),
					Host.UIPadding({
						PaddingTop = UDim.new(0, 16),
						PaddingBottom = UDim.new(0, 16),
						PaddingLeft = UDim.new(0, 16),
						PaddingRight = UDim.new(0, 16),
					}),
					Host.ScrollingFrame "Content" {
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 1, 0),
						AutomaticCanvasSize = Enum.AutomaticSize.Y,
						CanvasSize = UDim2.new(),
						ScrollBarThickness = 6,
						Host.UIListLayout({ SortOrder = Enum.SortOrder.LayoutOrder }),
						Page(),
					},
				}
			end,
			steps = {
				narrowActions = function()
					actionsCap:set(260)
					return report()
				end,
				wideActions = function()
					actionsCap:set(700)
					return report()
				end,
				reset = function()
					reset()
					return report()
				end,
				rejectChecks = function()
					acceptChecks:set(false)
					return report()
				end,
				disableChecks = function()
					enabled:set(false)
					return report()
				end,
				reorderTags = function()
					wrapTags:set({ "Elimination", "Rain", "Night" })
					return report()
				end,
			},
		}
	end,
}
