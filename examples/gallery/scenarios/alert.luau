--!strict
return {
	title = "Alerts and confirmations",
	ledgerRows = {},
	build = function(ctx)
		local UI, Compose = ctx.UI, ctx.Compose
		local status = Compose.cell("The save is ready to replace.")
		local presented = Compose.cell(false)
		local function open()
			presented:set(true)
			return true
		end
		local function reset()
			presented:set(false)
			status:set("The save is ready to replace.")
		end
		local function Example()
			return UI.Screen("Alert")({
				padding = "m",
				UI.ScrollView("Page")({
					width = UI.fill(),
					height = UI.fill(),
					gap = "m",
					UI.Text({ text = "Alerts and confirmations", textSize = "title" }),
					UI.Text({
						text = "A brief decision stays compact. Cancel leads a desktop row; phones and televisions stack the actions with cancel last.",
						width = UI.fill(),
					}),
					UI.Text("Status")({ text = status, width = UI.fill() }),
					UI.Button("Open")({ label = "Replace checkpoint…", onActivate = open }),
					UI.Button("Reset")({ label = "Reset", onActivate = reset }),
				}),
				UI.Alert("ReplaceSave")({
					title = "Replace this save?",
					severity = "critical",
					message = "Your current progress will replace the previous checkpoint.",
					isPresented = presented,
					actions = {
						{
							id = "Cancel",
							label = "Keep previous",
							role = "cancel",
							onActivate = function()
								status:set("Previous save kept.")
							end,
						},
						{
							id = "Replace",
							label = "Replace save",
							role = "destructive",
							onActivate = function()
								status:set("Checkpoint replaced.")
							end,
						},
					},
				}),
			})
		end
		return {
			screen = Example,
			steps = { open = open, reset = reset },
			states = function()
				return { { id = "confirmation", kind = "dialog", open = open } }
			end,
			report = function()
				return { status = status:peek(), alert = { presented = presented:peek() } }
			end,
			dispose = function() end,
		}
	end,
}
