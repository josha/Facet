--!strict
-- A caller-owned trip plan flows through one NavigationStack. Environment facts
-- choose arrangement and controls; every page uses the same theme/input authorities.
return {
	title = "Plan a journey",
	ledgerRows = { "CAPABILITY-NAVIGATION" },
	build = function(ctx)
		local Facet, core, env = ctx.Facet, ctx.core, ctx.env
		local UI = Facet.UI
		local scope = core:scope("journey")
		local path = scope:own(core:signal({}))
		local destination = scope:own(core:signal("coast"))
		local notes = scope:own(core:signal("Meet at sunrise."))
		local minimum = scope:own(core:signal("m"))
		local alignment = scope:own(core:signal("firstTextBaseline"))
		local visits, exits = 0, 0
		local axis = scope:own(core:memo(function(use)
			return if use(env:get("sizeClass")) == "compact" then "y" else "x"
		end))
		local stack
		local function page(pageScope, children)
			visits += 1
			pageScope:own({
				dispose = function()
					exits += 1
				end,
			})
			return UI.ScrollView({
				id = "Scroll",
				width = UI.fill(),
				height = UI.fill(),
				children = { UI.VStack({ id = "Content", gap = "m", width = UI.fill(), children = children }) },
			})
		end
		stack = scope:own(Facet.Controls.NavigationStack(core, {
			id = "Journey",
			path = path,
			backLabel = "Back",
			transition = { enter = "slide-left", exit = "slide-right", class = "container" },
			env = env,
			root = {
				title = "Plan a journey",
				content = function(pageScope)
					local picker = pageScope:own(Facet.Controls.Picker(core, {
						id = "Destination",
						selected = destination,
						env = env,
						options = {
							{ value = "coast", label = "Coastal journey" },
							{ value = "forest", label = "Forest journey" },
							{ value = "mountain", label = "Mountain journey" },
						},
					}))
					return page(pageScope, {
						UI.Text({
							text = "Choose a destination. Your choices stay with you when you go back.",
							width = UI.fill(),
						}),
						picker.blueprint,
						UI.Button({
							id = "Continue",
							label = "Plan details",
							onActivate = function()
								stack.api.push({ id = "details" })
							end,
						}),
					})
				end,
			},
			destinations = {
				details = {
					title = "Journey details",
					content = function(pageScope)
						local editor = pageScope:own(
							Facet.Controls.TextInput(core, { id = "Notes", value = notes, multiline = true, env = env })
						)
						return page(pageScope, {
							UI.AdaptiveStack({
								id = "Columns",
								axis = axis,
								gap = "m",
								width = UI.fill(),
								children = {
									UI.VStack({
										id = "Summary",
										width = UI.fill(),
										gap = "s",
										children = {
											UI.HStack({
												id = "Baseline",
												align = alignment,
												gap = "s",
												width = UI.fill(),
												children = {
													UI.Text({ id = "Label", text = "Days", textSize = "caption" }),
													UI.Text({ id = "Value", text = "3", textSize = "title" }),
													UI.Spacer({ id = "FlexibleGap", minLength = minimum }),
													UI.Text({ id = "Unit", text = "away", textSize = "body" }),
												},
											}),
											UI.HStack({
												id = "LastBaseline",
												align = "lastTextBaseline",
												gap = "s",
												children = {
													UI.Text({ text = "Travel\nlight", textSize = "heading" }),
													UI.Text({ text = "and enjoy the view", textSize = "caption" }),
												},
											}),
										},
									}),
									UI.VStack({
										id = "Writing",
										width = UI.fill(),
										gap = "s",
										children = { UI.Text({ text = "Your notes" }), editor.blueprint },
									}),
								},
							}),
							UI.Button({
								id = "Review",
								label = "Review journey",
								onActivate = function()
									stack.api.push({ id = "review", value = destination:get() })
								end,
							}),
						})
					end,
				},
				review = {
					title = "Ready to go",
					content = function(pageScope, entry)
						return page(pageScope, {
							UI.Text({
								text = "Destination: " .. tostring(entry.value),
								textSize = "heading",
								width = UI.fill(),
							}),
							UI.Text({ text = notes, width = UI.fill() }),
							UI.Button({
								id = "StartAgain",
								label = "Back to the beginning",
								onActivate = function()
									stack.api.popToRoot()
								end,
							}),
						})
					end,
				},
			},
		}))
		return {
			screen = UI.Screen({ id = "NavigationFlow", surface = "base", children = { stack.blueprint } }),
			steps = {
				push = function()
					stack.api.push({ id = "details" })
				end,
				review = function()
					stack.api.push({ id = "review", value = destination:get() })
				end,
				back = function()
					return stack.api.back()
				end,
				reset = function()
					stack.api.popToRoot()
				end,
				spacing = function()
					minimum:set(if minimum:get() == "m" then "xl" else "m")
				end,
				baseline = function()
					alignment:set(
						if alignment:get() == "firstTextBaseline" then "lastTextBaseline" else "firstTextBaseline"
					)
				end,
			},
			states = function()
				return {
					{
						id = "details",
						kind = "page",
						open = function()
							path:set({ { id = "details" } })
							return true
						end,
					},
					{
						id = "review",
						kind = "page",
						open = function()
							path:set({ { id = "details" }, { id = "review", value = "coast" } })
							return true
						end,
					},
				}
			end,
			report = function()
				return {
					navigation = stack.dump(),
					visits = visits,
					exits = exits,
					notes = notes:get(),
					destination = destination:get(),
					axis = axis:get(),
				}
			end,
			dispose = function()
				scope:dispose()
			end,
		}
	end,
}
