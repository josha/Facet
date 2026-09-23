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
		local actionsCap = Compose.cell(700)
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
		local rootPath, controller
		local function selected(cells)
			local result = {}
			for id, cell in cells do
				result[id] = cell:peek()
			end
			return result
		end
		local function report()
			if not rootPath or not controller then
				return nil
			end
			ctx.presenter.refresh()
			local row, column =
				controller.rectOf(rootPath .. "/Actions/Row"), controller.rectOf(rootPath .. "/Actions/Column")
			local openSection
			for id, cell in expanded do
				if cell:peek() then
					openSection = id
				end
			end
			return {
				rootPath = rootPath,
				actionsCap = actionsCap:peek(),
				actionsForm = if row and row.w > 0
					then "row"
					else if column and column.w > 0 then "column" else "neither",
				row = row,
				column = column,
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
			return UI.Text(id)({ text = text, textSize = "title", width = UI.fill() })
		end
		local function note(id: string, text: string): any
			return UI.Text(id)({
				text = text,
				textSize = "caption",
				role = "secondary",
				width = UI.fill(),
				disclose = true,
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
					UI.Label("Icon")({
						title = opts.iconLabel or opts.title,
						icon = opts.icon,
						presentation = "iconOnly",
						iconSize = "controlSizes.large.iconSize",
					})
				)
			end
			table.insert(children, UI.Text("Title")({ text = opts.title, textSize = "heading", textAlign = "center" }))
			table.insert(
				children,
				UI.Text("Message")({
					text = opts.message,
					textAlign = "center",
					role = "secondary",
					width = UI.fill(),
					disclose = true,
				})
			)
			table.insert(
				children,
				UI.Button("Action")({ label = opts.actionLabel, appearance = "soft", onActivate = opts.onAction })
			)
			return UI.VStack(id)({
				width = UI.fill(),
				gap = "s",
				align = "center",
				padding = "m",
				table.unpack(children),
			})
		end
		-- Each line sits under a representative icon row, so a leading inset visibly
		-- starts where the row's text does: the Label's icon box plus its gap.
		local TEXT_INSET = { "controlSizes.regular.iconSize", "controls.label.gap" }
		local function dividerExample(id: string, name: string, sides: any, thickness: any?): any
			return UI.VStack(id)({
				width = UI.fill(),
				gap = "xs",

				UI.HStack("Row")({
					width = UI.fill(),
					gap = "controls.label.gap",
					align = "center",
					UI.Label("Icon")({ title = name, icon = "settings", presentation = "iconOnly" }),
					UI.Text("Title")({ text = name, width = UI.fill() }),
				}),
				UI.VStack("Pad")({
					width = UI.fill(),
					padding = sides,
					UI.Divider("Line")({ thickness = thickness }),
				}),
			})
		end

		local function Page()
			Compose.cleanup(function()
				rootPath, controller = nil, nil
			end)

			local function actionButton(
				id: string,
				label: string,
				role: string?,
				appearance: string?,
				widthDim: any
			): any
				return UI.Button(id)({
					label = label,
					role = role,
					appearance = appearance,
					width = widthDim,
					height = { type = "minMax", min = "targetSizes.minimum" },
					onActivate = function()
						activations:update(function(n)
							return n + 1
						end)
					end,
				})
			end
			local function actionRow(): any
				return UI.ViewThatFits("Actions")({
					width = function(use)
						return { type = "percent", fraction = 1, max = use(actionsCap) }
					end,

					UI.HStack("Row")({
						gap = "s",
						align = "center",

						actionButton("Cancel", "Cancel", "cancel", nil, UI.hug()),
						actionButton("Save", "Save changes to this profile", nil, "emphasis", UI.hug()),
						actionButton("Delete", "Delete profile", "destructive", "utility", UI.hug()),
					}),
					UI.VStack("Column")({
						gap = "s",
						align = "stretch",
						width = UI.fill(),

						actionButton("Cancel", "Cancel", "cancel", nil, UI.fill()),
						actionButton("Save", "Save changes to this profile", nil, "emphasis", UI.fill()),
						actionButton("Delete", "Delete profile", "destructive", "utility", UI.fill()),
					}),
				})
			end
			local function accordionItem(id: string, label: string, body: string): any
				return UI.DisclosureGroup(id)({
					label = label,
					appearance = "divided",
					expanded = expanded[id],
					onToggle = function(next)
						if next then
							ctx.app.runtime:batch(function()
								for other, cell in expanded do
									if other ~= id then
										cell:set(false)
									end
								end
							end)
						end
					end,
					content = function()
						return UI.Text("Body")({ text = body, width = UI.fill() })
					end,
				})
			end
			local function checkItem(id: string, label: string, width: any?): any
				return UI.Toggle(id)({
					label = label,
					presentation = "checkbox",
					width = width,
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
				return UI.Chip(tag)({ label = tag, selected = cells[tag] })
			end

			local root = UI.VStack("Page")({
				width = UI.fill(),
				gap = "l",
				align = "start",
				padding = "m",

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
				UI.VStack("CheckboxGroup")({
					gap = "xs",
					width = UI.fill(),

					checkItem("tires", "Tire wear"),
					checkItem("fuel", "Fuel use"),
					checkItem("damage", "Damage"),
					checkItem("weather", "Weather"),
				}),

				UI.HStack("WrapChecks")({
					wrap = true,
					gap = "s",
					width = UI.fill(),
					checkItem("tires", "Tire wear", UI.hug()),
					checkItem("fuel", "Fuel use", UI.hug()),
					checkItem("damage", "Damage", UI.hug()),
					checkItem("weather", "Weather", UI.hug()),
				}),

				heading("ChipHeading", "Chip group"),
				note("ChipWrapNote", "Wraps to a new line when it runs out of room."),
				UI.HStack("WrapChips")({
					wrap = true,
					gap = "s",
					width = UI.fill(),

					UI.ForEach("Tags")({
						items = wrapTags,
						key = function(tag: string)
							return tag
						end,
						row = function(tag)
							return chipItem(tag, wrapSelected)
						end,
					}),
				}),
				note(
					"ChipRailNote",
					"One scrolling row instead, for a long list on a narrow screen. A keyboard or gamepad focus move keeps the picked chip in view with no extra wiring."
				),
				UI.ScrollView("RailChips")({
					axis = "x",
					width = UI.fill(),
					height = UI.hug(),

					UI.HStack("Row")({
						gap = "s",

						UI.ForEach("Modes")({
							items = railTags,
							key = function(tag: string)
								return tag
							end,
							row = function(tag)
								return chipItem(tag, railSelected)
							end,
						}),
					}),
				}),

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
				-- one bounded card, so both ends of every line are on screen to compare;
				-- the trailing inset is the same amount as the leading one
				UI.VStack("Dividers")({
					surface = "raised",
					width = { type = "percent", fraction = 1, max = 360 },
					padding = "m",
					gap = "m",
					dividerExample("DividerFull", "Full width", 0),
					dividerExample("DividerLeading", "Leading inset: starts at the text", { left = TEXT_INSET }),
					dividerExample("DividerTrailing", "Trailing inset: stops short", { right = TEXT_INSET }),
					dividerExample("DividerBoth", "Leading and trailing", { left = TEXT_INSET, right = TEXT_INSET }),
					dividerExample("DividerHeavy", "Heavy: three hairlines", 0, function(use)
						local metrics = use(ctx.env:get("themeMetrics")) or Facet.themes.neutral()
						return 3 * metrics.strokes.hairline
					end),
				}),

				heading("AccordionHeading", "Single-open accordion"),
				UI.VStack("Accordion")({
					width = UI.fill(),
					gap = 0,

					accordionItem("Rules", "Race rules", "Standard lap count, no shortcuts, collisions on."),
					accordionItem("Setup", "Car setup", "Tire compound, gear ratio and ride height for this track."),
					accordionItem("Rewards", "Rewards", "Podium finishes bank currency toward the next kart unlock."),
				}),
			})
			return Facet.contribution.attach(root, {
				bindController = function(value)
					controller = value
				end,
				syncGeometry = function(_, node)
					if node then
						rootPath = node.path
					end
				end,
			})
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
				return UI.Screen("Recipes")({
					surface = "base",
					padding = { top = "m", bottom = "m" },
					UI.ScrollView("Content")({
						width = UI.fill(),
						height = UI.fill(),
						padding = { left = "m", right = "m" },
						Page(),
					}),
				})
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
