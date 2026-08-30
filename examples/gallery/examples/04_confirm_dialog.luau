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

	-- Track the live modal handle so a button's own onActivate can dismiss it.
	local currentModal: any = nil

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

	-- The modal blueprint: a prompt and two buttons. It is presented lazily, only
	-- when the user asks to delete. Each button carries its APP SEMANTICS on its
	-- node onActivate: the presenter dispatches Activate (tap, or Return/A on the
	-- focused button) here with no consumer routing. The gamepad B
	-- button / Cancel routing dismisses WITHOUT reaching these — the presenter
	-- handles that and restores focus on its own.
	--
	-- A MODAL IS A SCRIM PLUS A PANEL, and it needs to LOOK like one.
	--
	-- This dialog had neither: the screen was transparent, so on a device the
	-- prompt and its two buttons floated loose over whatever was behind them with
	-- no boundary at all, and "Delete" — a destructive, irreversible action — sat
	-- unframed on top of the very screen it was about to change. Found on an
	-- a physical phone; in Studio over a plain baseplate it had looked merely plain.
	--
	-- ...AND THE CENTRING HAS TO BE ON A ZSTACK (example-quality-pass, measured
	-- 2026-08-06). `alignH`/`alignV` are documented as alignment inside a ZSTACK
	-- parent. They were authored on the Screen, which stacks its children
	-- vertically, so they were accepted and silently ignored and the card rendered
	-- at 16,16 — the top-left corner — while every reader of this file believed it
	-- was centred. The scrim Screen now holds ONE full-bleed ZStack, and the card
	-- centres inside that.
	local dialog = UI.Screen({
		id = "ConfirmDialog",
		surface = "scrim",
		padding = "m",
		children = {
			UI.ZStack({
				id = "Center",
				width = UI.fill(),
				height = UI.fill(),
				children = {
					UI.VStack({
						id = "Card",
						surface = "raised",
						padding = "m",
						gap = "s",
						alignH = "center",
						alignV = "center",
						children = {
							UI.Text({
								id = "Prompt",
								text = "Delete this save? This cannot be undone.",
								textSize = "body",
							}),
							UI.Button({
								id = "Confirm",
								label = "Delete",
								onActivate = function()
									result:set("confirmed")
									hasSave:set(false)
									presenter.dismiss(currentModal)
									currentModal = nil
								end,
							}),
							UI.Button({
								id = "Cancel",
								label = "Cancel",
								onActivate = function()
									result:set("cancelled")
									presenter.dismiss(currentModal)
									currentModal = nil
								end,
							}),
						},
					}),
				},
			}),
		},
	})

	local function openDialog()
		if currentModal ~= nil then
			return -- already open: one modal, not a stack of identical ones
		end
		currentModal = presenter.presentModal(dialog)
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
		confirmPath = "/ConfirmDialog/Center/Card/Confirm",
		cancelPath = "/ConfirmDialog/Center/Card/Cancel",
		cardPath = "/ConfirmDialog/Center/Card",
		dispose = function()
			if currentModal ~= nil then
				presenter.dismiss(currentModal)
				currentModal = nil
			end
			slotLabel:dispose()
			outcomeLabel:dispose()
			canDelete:dispose()
			result:dispose()
			hasSave:dispose()
		end,
	}
end

return example
