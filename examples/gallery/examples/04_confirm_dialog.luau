--!strict

type ExampleContext = typeof(require("@repo/examples/types").Context)
type AlertAction = typeof(require("@repo/tools/typecheck/aliases").AlertAction)
type Use = typeof(require("@repo/tools/typecheck/aliases").Use)

local example = { title = "Confirmation Dialog" }
function example.build(ctx: ExampleContext)
	local UI, Compose = ctx.UI, ctx.Compose
	local built = {
		deletePath = "/DangerScreen/Page/Delete",
		restorePath = "/DangerScreen/Page/Restore",
		outcomePath = "/DangerScreen/Page/Outcome",
		titlePath = "/DangerScreen/Page/Title",
		confirmPath = "/ConfirmDialog/Center/Card/Actions/Order/[Confirm]/Confirm",
		cancelPath = "/ConfirmDialog/Center/Card/Actions/Order/[Cancel]/Cancel",
		cardPath = "/ConfirmDialog/Center/Card",
		dispose = function() end,
	}
	local result = Compose.cell("none")
	local hasSave = Compose.cell(true)
	local open = Compose.cell(false)
	local outcome = Compose.formula(function(use: Use)
		if use(result) == "confirmed" then
			return "Deleted. The slot is empty now."
		end
		if use(result) == "cancelled" then
			return "Kept. Nothing was deleted."
		end
		return "This slot holds a save. Deleting it cannot be undone."
	end)
	local function openDialog()
		open:set(true)
	end
	local function restore()
		ctx.runtime:batch(function()
			hasSave:set(true)
			result:set("none")
		end)
	end
	function built.result()
		return result:peek()
	end
	function built.hasSave()
		return hasSave:peek()
	end
	function built.outcomeText()
		return outcome:peek()
	end
	built.openDialog, built.restore = openDialog, restore
	function built.screen()
		local actions: { AlertAction } = {
			{
				id = "Confirm",
				label = "Delete save",
				compactLabel = "Delete",
				role = "destructive",
				onActivate = function()
					ctx.runtime:batch(function()
						result:set("confirmed")
						hasSave:set(false)
					end)
				end,
			},
			{
				id = "Cancel",
				label = "Cancel",
				role = "cancel",
				onActivate = function()
					result:set("cancelled")
				end,
			},
		}
		return UI.Screen "DangerScreen" {
			UI.ScrollView "Page" {
				gap = "s",
				align = "stretch",
				maxWidth = 560,
				UI.Text "Title" {
					textRole = "title",
					TextWrapped = true,
					text = function(use: Use)
						return if use(hasSave) then "Save Slot 1 — Rally Stage 3, 42%" else "Save Slot 1 — empty"
					end,
				},
				UI.Text "Outcome" { text = outcome, TextWrapped = true },
				UI.Button "Delete" {
					label = "Delete save",
					role = "destructive",
					enabled = hasSave,
					onActivate = openDialog,
				},
				UI.Button "Restore" {
					label = "Restore save",
					Visible = function(use: Use)
						return not use(hasSave)
					end,
					onActivate = restore,
				},
			},
			UI.Alert "ConfirmDialog" {
				title = "Delete this save?",
				severity = "critical",
				message = "This cannot be undone.",
				isPresented = open,
				actions = actions,
			},
		}
	end
	return built
end
return example
