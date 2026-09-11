--!strict
-- The same brief decision used by Actions and menus and tutorial 04.
return {
	title = "Alerts and confirmations",
	ledgerRows = {},
	build = function(ctx)
		local Facet, core = ctx.Facet, ctx.core
		local UI = Facet.UI
		local scope = core:scope("alert-demo")
		local status = scope:own(core:signal("The save is ready to replace."))
		local alert = scope:own(Facet.Controls.Alert(core, {
			id = "ReplaceSave",
			title = "Replace this save?",
			severity = "critical",
			message = "Your current progress will replace the previous checkpoint.",
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
		}))
		local function open()
			if not ctx.presenter then
				return false
			end
			alert.present(ctx.presenter)
			return true
		end
		local function reset()
			alert.dismiss()
			status:set("The save is ready to replace.")
		end
		return {
			screen = UI.Screen({
				id = "Alert",
				padding = "m",
				children = {
					UI.ScrollView({
						id = "Page",
						width = UI.fill(),
						height = UI.fill(),
						gap = "m",
						children = {
							UI.Text({ text = "Alerts and confirmations", textSize = "title" }),
							UI.Text({
								text = "A brief decision stays compact. Cancel leads a desktop row; phones and televisions stack the actions with cancel last.",
								width = UI.fill(),
							}),
							UI.Text({ id = "Status", text = status, width = UI.fill() }),
							UI.Button({ id = "Open", label = "Replace checkpoint…", onActivate = open }),
							UI.Button({ id = "Reset", label = "Reset", onActivate = reset }),
						},
					}),
				},
			}),
			steps = { open = open, reset = reset },
			states = function()
				return { { id = "confirmation", kind = "dialog", open = open } }
			end,
			report = function()
				return { status = status:get(), alert = alert.dump() }
			end,
			dispose = function()
				scope:dispose()
			end,
		}
	end,
}
