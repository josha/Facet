--!strict
-- ============================================================================
-- Example 4 of the Facet tutorial: a confirmation dialog.
-- ============================================================================
--
-- WHAT THIS TEACHES  —  the presenter stack
--   * modal presentation — presenter.presentModal opens a screen ON TOP of the
--                          current one
--   * focus trap         — while the modal is open, keyboard/gamepad focus
--                          cannot leave it; navigation wraps inside
--   * cancel routing     — the gamepad B button dismisses the modal
--   * focus restoration  — dismissing the modal returns focus to the control
--                          that was focused before it opened
--   * THE ANSWER IS VISIBLE — confirming or cancelling changes the screen
--                          underneath. A destructive action that leaves the
--                          screen byte-identical has not taught anything
--
-- WHAT THE PLAYER SEES
--   "Save Slot 1" holding a saved game, and a Delete button. Delete opens a
--   centred card over a dimmed screen. Confirming empties the slot, says so, and
--   offers "Restore the save"; cancelling says the save was kept. Either way the
--   base screen has changed, which is what makes the round trip readable.
--
-- deps used: presenter (see 01's header for the shared module shape).

local example = {}
example.title = "Confirmation Dialog"

function example.build(Facet: any, core: any, deps: any)
	local UI = Facet.UI
	local presenter = deps.presenter

	-- "none" | "confirmed" | "cancelled" — the last answer, and the thing the
	-- base screen reads so the player can SEE what their answer did.
	local result = core:signal("none")
	-- does the slot still hold a save? Confirming deletes it; Restore puts it back.
	local hasSave = core:signal(true)

	local slotLabel = core:memo(function(use)
		return if use(hasSave) then "Save Slot 1 — Rally Stage 3, 42%" else "Save Slot 1 — empty"
	end)
	local outcomeLabel = core:memo(function(use)
		local answer = use(result)
		if answer == "confirmed" then
			return "Deleted. The slot is empty now."
		elseif answer == "cancelled" then
			return "Kept. Nothing was deleted."
		end
		return "This slot holds a save. Deleting it cannot be undone."
	end)

	-- The standard Alert owns responsive sizing, modal focus and cancellation.
	-- The game supplies the decision and its effects, not another dialog layout.
	local dialog = Facet.Controls.Alert(core, {
		id = "ConfirmDialog",
		title = "Delete this save?",
		severity = "critical",
		message = "This cannot be undone.",
		actions = {
			{
				id = "Confirm",
				label = "Delete Save",
				compactLabel = "Delete",
				role = "destructive",
				onActivate = function()
					result:set("confirmed")
					hasSave:set(false)
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
		},
	})
	local function openDialog()
		dialog.present(presenter)
	end

	local function restore()
		hasSave:set(true)
		result:set("none")
	end

	-- The base screen. `Delete` is only offered while there is something to
	-- delete; once the slot is empty the same place offers `Restore the save`, so
	-- the demonstration is repeatable without leaving the place.
	local canDelete = core:memo(function(use)
		return use(hasSave)
	end)
	local screen = UI.Screen({
		id = "DangerScreen",
		surface = "base",
		padding = "m",
		children = {
			UI.ScrollView({
				id = "Page",
				axis = "y",
				gap = "s",
				width = UI.fill(),
				height = UI.fill(),
				children = {
					UI.Text({ id = "Title", text = slotLabel, textSize = "title" }),
					UI.Text({ id = "Outcome", text = outcomeLabel, textSize = "body", role = "secondary" }),
					UI.Button({ id = "Delete", label = "Delete Save", enabled = canDelete, onActivate = openDialog }),
					UI.Button({ id = "Restore", label = "Restore the save", onActivate = restore }),
				},
			}),
		},
	})

	return {
		screen = screen,
		result = result, -- "none" | "confirmed" | "cancelled"
		hasSave = hasSave, -- does the slot still hold a save?
		openDialog = openDialog, -- open the modal directly (tutorial convenience)
		restore = restore,
		outcomeText = function(): string
			return outcomeLabel:get()
		end,
		deletePath = "/DangerScreen/Page/Delete",
		restorePath = "/DangerScreen/Page/Restore",
		outcomePath = "/DangerScreen/Page/Outcome",
		titlePath = "/DangerScreen/Page/Title",
		confirmPath = "/ConfirmDialog/Center/Card/Actions/Confirm",
		cancelPath = "/ConfirmDialog/Center/Card/Actions/Cancel",
		cardPath = "/ConfirmDialog/Center/Card",
		dispose = function()
			dialog.dispose()
			slotLabel:dispose()
			outcomeLabel:dispose()
			canDelete:dispose()
			result:dispose()
			hasSave:dispose()
		end,
	}
end

return example
