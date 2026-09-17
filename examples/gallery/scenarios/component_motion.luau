--!strict
-- Describe once. State, derived values and animation belong to the mounted view.
return {
	title = "Automatic motion",
	ledgerRows = {},
	build = function(ctx: any)
		local Facet, UI = ctx.Facet, ctx.Facet.View
		local commands, latest = {}, {}
		local Section = Facet.component(function(_, props)
			return UI.VStack({
				gap = "s",
				width = UI.fill(),
				UI.Text({ text = props.title, textSize = "control" }),
				UI.VStack({ gap = "s", children = props.children }),
				props.footer,
			})
		end)
		local Inventory = Facet.component(function(ui)
			local expanded, setExpanded = ui.state(false)
			local selected, setSelected = ui.state("scanner")
			local items, setItems = ui.state({
				{ id = "scanner", name = "Scanner", price = 40 },
				{ id = "grapple", name = "Grapple", price = 60 },
				{ id = "beacon", name = "Beacon", price = 20 },
			})
			local balance, setBalance = ui.state(100)
			local displayedBalance = ui.animate(balance, "object", { kind = "informational" })
			local item = ui.memo(function()
				for _, candidate in items() do
					if candidate.id == selected() then
						return candidate
					end
				end
				return items()[1]
			end)
			local function affordable()
				return balance() >= item().price
			end
			local function buy()
				if affordable() then
					setBalance(balance() - item().price)
				end
			end
			local function reverse()
				local reversed = {}
				for i = #items(), 1, -1 do
					table.insert(reversed, items()[i])
				end
				setItems(reversed)
			end
			commands.toggle = function()
				setExpanded(not expanded())
			end
			commands.reverse, commands.buy = reverse, buy
			commands.reset = function()
				setBalance(100)
			end
			ui.effect(function()
				latest = {
					expanded = expanded(),
					selected = selected(),
					balance = balance(),
					affordable = affordable(),
					first = items()[1].id,
				}
			end)
			local ItemRow = Facet.component(function(_, current)
				return UI.ZStack({
					id = "Card",
					width = UI.fill(),
					opacity = function()
						return if selected() == current().id then 1 else 0.65
					end,
					animation = { opacity = "object" },
					UI.Button({
						id = "Select",
						label = function()
							return `{current().name} · {current().price} credits`
						end,
						onActivate = function()
							setSelected(current().id)
						end,
					}),
				})
			end)
			return UI.Screen({
				id = "AutomaticMotion",
				padding = "m",
				gap = "s",
				UI.ScrollView({
					id = "Page",
					width = UI.fill(),
					height = UI.fill(),
					gap = "m",
					animation = { layout = "container" },
					Section({
						title = "Equipment",
						footer = UI.Text(function()
							return `Balance: {math.floor(displayedBalance() + 0.5)} credits`
						end),
						UI.ForEach({ id = "Items", items = items, key = "id", row = ItemRow }),
					}),
					UI.Toggle({
						id = "DetailsToggle",
						label = "Show details",
						value = expanded,
						onChange = setExpanded,
					}),
					UI.When({
						id = "Details",
						condition = expanded,
						transition = { enter = "fade" },
						UI.ZStack({
							id = "Panel",
							canvasGroup = true,
							padding = "s",
							surface = "raised",
							width = UI.fill(),
							UI.Text(function()
								return `{item().name} costs {item().price} credits. Its row stays the same when reordered.`
							end),
						}),
					}),
					UI.Button({ id = "Buy", label = "Buy selected", enabled = affordable, onActivate = buy }),
					UI.Button({ id = "Reverse", label = "Reverse order", onActivate = reverse }),
					UI.Button({ id = "Reset", label = "Reset balance", onActivate = commands.reset }),
				}),
			})
		end)
		return {
			screen = Inventory({}),
			present = {},
			steps = {
				toggle = function()
					commands.toggle()
					return latest
				end,
				reverse = function()
					commands.reverse()
					return latest
				end,
				buy = function()
					commands.buy()
					return latest
				end,
				resetBalance = function()
					commands.reset()
					return latest
				end,
			},
			report = function()
				return latest
			end,
			dispose = function() end,
		}
	end,
}
