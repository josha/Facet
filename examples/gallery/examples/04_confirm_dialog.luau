--!strict
-- A bound Alert owns modal presentation, focus, cancellation and restoration.
local example = { title = "Confirmation Dialog" }
function example.build(Facet: any, _core: any, _deps: any)
	local UI = Facet.View
	local built: any = {
		deletePath = "/DangerScreen/Page/Delete",
		restorePath = "/DangerScreen/Page/Restore",
		outcomePath = "/DangerScreen/Page/Outcome",
		titlePath = "/DangerScreen/Page/Title",
		confirmPath = "/ConfirmDialog/Center/Card/Actions/Order/[Confirm]/Confirm",
		cancelPath = "/ConfirmDialog/Center/Card/Actions/Order/[Cancel]/Cancel",
		cardPath = "/ConfirmDialog/Center/Card",
		dispose = function() end,
	}
	local SaveSlot = Facet.component(function(ui)
		local result, setResult = ui.state("none")
		local hasSave, setHasSave = ui.state(true)
		local open, setOpen = ui.state(false)
		local function outcome()
			if result() == "confirmed" then
				return "Deleted. The slot is empty now."
			end
			if result() == "cancelled" then
				return "Kept. Nothing was deleted."
			end
			return "This slot holds a save. Deleting it cannot be undone."
		end
		local function openDialog()
			setOpen(true)
		end
		local function restore()
			ui.batch(function()
				setHasSave(true)
				setResult("none")
			end)
		end
		built.result, built.hasSave, built.outcomeText = result, hasSave, outcome
		built.openDialog, built.restore = openDialog, restore
		return UI.Screen({
			id = "DangerScreen",
			surface = "base",
			padding = "m",
			UI.ScrollView({
				id = "Page",
				axis = "y",
				gap = "s",
				width = UI.fill(),
				height = UI.fill(),
				UI.Text({
					id = "Title",
					textSize = "title",
					text = function()
						return if hasSave() then "Save Slot 1 — Rally Stage 3, 42%" else "Save Slot 1 — empty"
					end,
				}),
				UI.Text({ id = "Outcome", text = outcome, textSize = "body", role = "secondary" }),
				UI.Button({ id = "Delete", label = "Delete Save", enabled = hasSave, onActivate = openDialog }),
				UI.Button({ id = "Restore", label = "Restore the save", onActivate = restore }),
			}),
			UI.Alert({
				id = "ConfirmDialog",
				title = "Delete this save?",
				severity = "critical",
				message = "This cannot be undone.",
				isPresented = open,
				onPresentedChange = setOpen,
				actions = {
					{
						id = "Confirm",
						label = "Delete Save",
						compactLabel = "Delete",
						role = "destructive",
						onActivate = function()
							ui.batch(function()
								setResult("confirmed")
								setHasSave(false)
							end)
						end,
					},
					{
						id = "Cancel",
						label = "Cancel",
						role = "cancel",
						onActivate = function()
							setResult("cancelled")
						end,
					},
				},
			}),
		})
	end)
	built.screen = SaveSlot({})
	return built
end
return example
