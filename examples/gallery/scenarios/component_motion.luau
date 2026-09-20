--!strict
-- Describe once. State, derived values and animation belong to the mounted view.
return {
	title = "Automatic motion",
	ledgerRows = {},
	build = function(ctx: any)
		local UI, Compose = ctx.UI, ctx.Compose
		local commands, latest = {}, {}
		local function Section(props)
			local rows = { gap = "s" }
			for _, child in props.children do
				table.insert(rows, child)
			end
			return UI.VStack({
				gap = "s",
				width = UI.fill(),
				UI.Text({ text = props.title, textSize = "control" }),
				UI.VStack(rows),
				props.footer,
			})
		end
		-- An arriving panel fades in: a tween from clear to solid that starts when
		-- its branch mounts. A host without an application runtime shows it solid.
		local function arrival(): any
			local runtime = ctx.app and ctx.app.runtime
			if runtime == nil then
				return 1
			end
			local shown = Compose.cell(0)
			local fade = runtime.tween(function(use)
				return use(shown)
			end, { seconds = 0.2 })
			shown:set(1)
			return fade
		end
		local function Inventory()
			local expanded = Compose.cell(false)
			local selected = Compose.cell("scanner")
			local items = Compose.cell({
				{ id = "scanner", name = "Scanner", price = 40 },
				{ id = "grapple", name = "Grapple", price = 60 },
				{ id = "beacon", name = "Beacon", price = 20 },
			})
			local balance = Compose.cell(100)
			-- The displayed balance eases toward the model value. A host without an
			-- application runtime shows the model value directly.
			local runtime = ctx.app and ctx.app.runtime
			local displayedBalance = if runtime
				then runtime.tween(function(use)
					return use(balance)
				end, { seconds = 0.35 })
				else balance
			local item = Compose.formula(function(use)
				local list = use(items)
				for _, candidate in list do
					if candidate.id == use(selected) then
						return candidate
					end
				end
				return list[1]
			end)
			local affordable = Compose.formula(function(use)
				return use(balance) >= use(item).price
			end)
			local function buy()
				if affordable:peek() then
					balance:set(balance:peek() - item:peek().price)
				end
			end
			local function reverse()
				local list, reversed = items:peek(), {}
				for i = #list, 1, -1 do
					table.insert(reversed, list[i])
				end
				items:set(reversed)
			end
			commands.toggle = function()
				expanded:set(not expanded:peek())
			end
			commands.reverse, commands.buy = reverse, buy
			commands.reset = function()
				balance:set(100)
			end
			Compose.watch(function(use)
				latest = {
					expanded = use(expanded),
					selected = use(selected),
					balance = use(balance),
					affordable = use(affordable),
					first = use(items)[1].id,
				}
			end)
			local function ItemRow(current)
				return UI.ZStack("Card-" .. current:peek().id)({
					width = UI.fill(),
					opacity = function(use)
						return if use(selected) == use(current).id then 1 else 0.65
					end,
					animation = { opacity = "object" },
					UI.Button("Select")({
						label = function(use)
							return `{use(current).name} · {use(current).price} credits`
						end,
						onActivate = function()
							selected:set(current:peek().id)
						end,
					}),
				})
			end
			return UI.Screen("AutomaticMotion")({
				padding = "m",
				gap = "s",
				UI.ScrollView("Page")({
					width = UI.fill(),
					height = UI.fill(),
					gap = "m",
					animation = { layout = "container" },
					Section({
						title = "Equipment",
						footer = UI.Text({
							text = function(use)
								return `Balance: {math.floor(use(displayedBalance) + 0.5)} credits`
							end,
						}),
						children = {
							UI.ForEach("Items")({
								Compose.keyed({
									from = items,
									key = function(entry)
										return entry.id
									end,
									render = ItemRow,
								}),
							}),
						},
					}),
					UI.Toggle("DetailsToggle")({ label = "Show details", value = expanded }),
					UI.When("Details")({
						Compose.show(expanded, function()
							return UI.ZStack("Panel")({
								canvasGroup = true,
								opacity = arrival(),
								padding = "s",
								surface = "raised",
								width = UI.fill(),
								UI.Text({
									text = function(use)
										return `{use(item).name} costs {use(item).price} credits. Its row stays the same when reordered.`
									end,
								}),
							})
						end),
					}),
					UI.Button("Buy")({ label = "Buy selected", enabled = affordable, onActivate = buy }),
					UI.Button("Reverse")({ label = "Reverse order", onActivate = reverse }),
					UI.Button("Reset")({ label = "Reset balance", onActivate = commands.reset }),
				}),
			})
		end
		return {
			screen = Inventory,
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
