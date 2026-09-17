--!strict
return {
	title = "Alerts and confirmations",
	ledgerRows = {},
	build = function(ctx)
		local Facet, UI = ctx.Facet, ctx.Facet.View
		local status, setStatus, presented, setPresented
		local function open()
			setPresented(true)
			return true
		end
		local function reset()
			setPresented(false)
			setStatus("The save is ready to replace.")
		end
		local Example = Facet.component(function(ui)
			status, setStatus = ui.state("The save is ready to replace.")
			presented, setPresented = ui.state(false)
			return UI.Screen({
				id = "Alert",
				padding = "m",
				UI.ScrollView({
					id = "Page",
					width = UI.fill(),
					height = UI.fill(),
					gap = "m",
					UI.Text({ text = "Alerts and confirmations", textSize = "title" }),
					UI.Text({
						text = "A brief decision stays compact. Cancel leads a desktop row; phones and televisions stack the actions with cancel last.",
						width = UI.fill(),
					}),
					UI.Text({ id = "Status", text = status, width = UI.fill() }),
					UI.Button({ id = "Open", label = "Replace checkpoint…", onActivate = open }),
					UI.Button({ id = "Reset", label = "Reset", onActivate = reset }),
				}),
				UI.Alert({
					id = "ReplaceSave",
					title = "Replace this save?",
					severity = "critical",
					message = "Your current progress will replace the previous checkpoint.",
					isPresented = presented,
					onPresentedChange = setPresented,
					actions = {
						{
							id = "Cancel",
							label = "Keep previous",
							role = "cancel",
							onActivate = function()
								setStatus("Previous save kept.")
							end,
						},
						{
							id = "Replace",
							label = "Replace save",
							role = "destructive",
							onActivate = function()
								setStatus("Checkpoint replaced.")
							end,
						},
					},
				}),
			})
		end)
		return {
			screen = Example({}),
			steps = { open = open, reset = reset },
			states = function()
				return { { id = "confirmation", kind = "dialog", open = open } }
			end,
			report = function()
				return { status = status(), alert = { presented = presented() } }
			end,
			dispose = function() end,
		}
	end,
}
